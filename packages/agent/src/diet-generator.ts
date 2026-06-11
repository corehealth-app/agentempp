/**
 * Gerador de prescrição de dieta + lista de compras (Sprint 4.1 — Roberto
 * pediu 2026-06-11). Manual MPP seção "Prescrição de Dieta Personalizada".
 *
 * ESQUELETO PRONTO — falta:
 *  - Integração no pipeline conversacional (tool `gera_dieta` que dispara
 *    isso e retorna lista pro paciente)
 *  - Alinhamento com Roberto: dieta RÍGIDA (paciente segue à risca) ou
 *    REFERÊNCIA (sugestão flexível)? Decisão muda o tom do prompt.
 *  - Receita de prosa do "tom Dr. Roberto" no system prompt
 *  - Cron de regeneração semanal opcional
 *
 * Hoje: chamada manual via script ou tool. Output validado contra schema.
 */
import type { ServiceClient } from '@mpp/db'
import type { OpenRouterLLM } from '@mpp/providers'

export interface DietGeneratorInput {
  userId: string
  /** Perfil do paciente (do user_profiles + user_progress). */
  profile: {
    name: string | null
    sex: 'masculino' | 'feminino' | null
    age: number | null
    weight_kg: number | null
    height_cm: number | null
    activity_level: 'sedentario' | 'leve' | 'moderado' | 'alto' | 'atleta' | null
    protocol: 'recomposicao' | 'manutencao' | 'ganho_massa' | null
    meta_kcal: number | null
    meta_protein_g: number | null
    bf_percent: number | null
    restrictions?: string[] // alergias, intolerâncias
    preferences?: string[] // alimentos que gosta (do histórico)
  }
  /** Alimentos que o paciente já come com frequência (do meal_logs). */
  historical_foods?: Array<{ food_name: string; frequency: number }>
  /** Quantas refeições por dia (padrão 4: café, almoço, lanche, jantar). */
  meals_per_day?: number
  /** RÍGIDA (paciente segue à risca) ou REFERÊNCIA (sugestão flexível). */
  mode?: 'rigida' | 'referencia'
  /** Horizon da prescrição. */
  horizon?: 'daily' | 'weekly'
}

export interface DietMeal {
  meal_type: 'cafe' | 'lanche_manha' | 'almoco' | 'lanche_tarde' | 'jantar' | 'ceia'
  time_suggestion?: string // ex: "07:30"
  items: Array<{
    food_name: string
    quantity_g: number
    display_qty?: number
    display_unit?: string
    kcal: number
    protein_g: number
    carbs_g: number
    fat_g: number
  }>
  total_kcal: number
  total_protein_g: number
  notes?: string
}

export interface ShoppingItem {
  category: 'proteínas' | 'carboidratos' | 'vegetais' | 'frutas' | 'laticínios' | 'gorduras' | 'outros'
  food_name: string
  quantity_g: number
  display_qty?: number
  display_unit?: string
}

export interface DietPlan {
  user_id: string
  generated_at: string
  mode: 'rigida' | 'referencia'
  horizon: 'daily' | 'weekly'
  meta_kcal: number
  meta_protein_g: number
  daily_meals: DietMeal[] // pra horizon=daily, len=1; pra weekly, len=7
  shopping_list: ShoppingItem[]
  notes?: string
}

const DIET_SYSTEM_PROMPT = `Você é Dr. Roberto Menescal, nutricionista que conduz o Método MPP via WhatsApp.

Sua tarefa: gerar uma prescrição alimentar PERSONALIZADA pro paciente baseada em:
1. Meta calórica e proteica diária (deve bater exatamente)
2. Alimentos que ele já come (do histórico) — priorize esses pra maximizar adesão
3. Restrições e preferências
4. Modo da prescrição (rígida = paciente segue à risca; referência = sugestão flexível)

REGRAS:
- TODA refeição precisa atingir a meta proteica total do dia (dividida proporcionalmente)
- Use alimentos do histórico do paciente sempre que possível
- Quantidades em unidades naturais quando faz sentido (1 pão, 2 ovos, 1 colher de azeite)
- Macros somam EXATAMENTE: kcal_total = kcal_café + kcal_almoço + kcal_lanche + kcal_jantar (±5%)
- Use TACO brasileira como referência calórica (não invente kcal/100g)

OUTPUT em JSON com schema:
{
  "daily_meals": [{ meal_type, time_suggestion, items: [{ food_name, quantity_g, kcal, protein_g, carbs_g, fat_g }], total_kcal, total_protein_g, notes }],
  "shopping_list": [{ category, food_name, quantity_g }]
}

NÃO inclua comentários neurocomportamentais aqui (Haiku faz isso separado). Foque em precisão técnica.`

export async function generateDietPlan(
  llm: OpenRouterLLM,
  _supabase: ServiceClient,
  input: DietGeneratorInput,
): Promise<DietPlan | null> {
  const mode = input.mode ?? 'referencia'
  const horizon = input.horizon ?? 'daily'
  const meals_per_day = input.meals_per_day ?? 4

  const historicalSummary =
    (input.historical_foods ?? [])
      .slice(0, 20)
      .map((h) => `- ${h.food_name} (${h.frequency}x)`)
      .join('\n') || '(sem histórico)'

  const restrictions =
    (input.profile.restrictions ?? []).length > 0
      ? input.profile.restrictions!.join(', ')
      : '(nenhuma)'

  const userPayload = `Paciente: ${input.profile.name ?? '?'} (${input.profile.sex}, ${input.profile.age}a, ${input.profile.weight_kg}kg, ${input.profile.height_cm}cm)
Protocolo: ${input.profile.protocol}
Meta calórica diária: ${input.profile.meta_kcal} kcal
Meta proteica diária: ${input.profile.meta_protein_g} g
BF estimado: ${input.profile.bf_percent ?? '?'}%

Refeições por dia: ${meals_per_day}
Modo: ${mode} (${mode === 'rigida' ? 'paciente segue à risca' : 'referência flexível'})
Horizonte: ${horizon}

Alimentos que o paciente já come (priorize):
${historicalSummary}

Restrições/alergias: ${restrictions}

Gere a prescrição em JSON.`

  try {
    const result = await llm.complete({
      model: 'anthropic/claude-sonnet-4.5',
      systemPrompt: DIET_SYSTEM_PROMPT,
      messages: [{ role: 'user', content: userPayload }],
      temperature: 0.3,
      maxTokens: 4000,
      metadata: { Stage: 'diet-generator' },
    })
    const content = result.content ?? ''
    const jsonMatch = content.match(/\{[\s\S]*\}/)
    if (!jsonMatch) return null
    const parsed = JSON.parse(jsonMatch[0]) as Partial<DietPlan>
    if (!parsed.daily_meals || !parsed.shopping_list) return null

    return {
      user_id: input.userId,
      generated_at: new Date().toISOString(),
      mode,
      horizon,
      meta_kcal: input.profile.meta_kcal ?? 0,
      meta_protein_g: input.profile.meta_protein_g ?? 0,
      daily_meals: parsed.daily_meals,
      shopping_list: parsed.shopping_list,
      notes: parsed.notes,
    }
  } catch {
    return null
  }
}

/**
 * Persiste o plano em `prescriptions` (tabela criada em
 * 20260611230000_prescriptions_training_phrases.sql).
 */
export async function saveDietPlan(
  supabase: ServiceClient,
  plan: DietPlan,
): Promise<{ id: string | null }> {
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  const sp = supabase as any
  const { data, error } = await sp
    .from('prescriptions')
    .insert({
      user_id: plan.user_id,
      type: 'combined', // dieta + lista de compras juntas
      payload: plan,
      generated_by: 'agent',
      generated_at: plan.generated_at,
      valid_until: plan.horizon === 'weekly'
        ? new Date(Date.now() + 7 * 24 * 3600 * 1000).toISOString()
        : new Date(Date.now() + 24 * 3600 * 1000).toISOString(),
      version: 1,
    })
    .select('id')
    .single()
  if (error) return { id: null }
  return { id: data?.id ?? null }
}
