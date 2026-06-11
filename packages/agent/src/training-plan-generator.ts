/**
 * Gerador de plano de treino esporádico (Sprint 4.2 — Roberto pediu
 * 2026-06-11 via áudio). Manual MPP seção "Prescrição de treinos".
 *
 * Conceito Roberto (áudio): paciente envia foto dos equipamentos UMA VEZ
 * → sistema gera plano semanal → cron entrega só o treino do dia de manhã
 * junto com balanço (SEM regerar com LLM). Custo de LLM: 1× na geração,
 * depois zero.
 *
 * ESQUELETO PRONTO — falta:
 *  - Integração no pipeline conversacional (tool `gera_treino` quando
 *    paciente envia foto de equipamentos)
 *  - Vision identificando equipamentos da foto (Sonnet 4.5)
 *  - Cron de entrega diária determinística (`training-daily-delivery.ts`)
 *  - Templates de execução por exercício (com mídia opcional)
 */
import type { ServiceClient } from '@mpp/db'
import type { OpenRouterLLM } from '@mpp/providers'

export interface TrainingGeneratorInput {
  userId: string
  profile: {
    name: string | null
    sex: 'masculino' | 'feminino' | null
    age: number | null
    weight_kg: number | null
    height_cm: number | null
    protocol: 'recomposicao' | 'manutencao' | 'ganho_massa' | null
    bf_percent: number | null
    /** Nível atual de musculação. */
    training_level: 'iniciante' | 'intermediario' | 'avancado' | null
    /** Lesões/limitações. */
    limitations?: string[]
    /** Grupos musculares que quer priorizar. */
    priority_muscles?: string[]
  }
  /** Quantos dias por semana. */
  days_per_week: number
  /** Quais dias da semana (ex: ['seg', 'qua', 'sex']). */
  training_days?: string[]
  /** Equipamentos disponíveis (do vision na foto). */
  available_equipment: string[]
  /** Local. */
  location: 'academia_completa' | 'academia_limitada' | 'casa'
  /** Topa treinar até falha muscular? */
  goes_to_failure?: boolean
}

export interface TrainingExercise {
  name: string
  muscle_group: string
  sets: number
  reps_range: string // "8-12" ou "até falha"
  rest_seconds: number
  rpe_target?: string
  notes?: string
  execution_steps?: string[] // passo-a-passo
  common_mistakes?: string[]
}

export interface TrainingDay {
  day: string // 'seg' / 'ter' / ... ou 'A' / 'B'
  focus: string // 'Inferiores' / 'Empurrar' / 'Full Body'
  duration_min: number
  exercises: TrainingExercise[]
}

export interface TrainingPlan {
  user_id: string
  generated_at: string
  plan_type: 'split' | 'full_body' | 'custom'
  days_per_week: number
  equipment_summary: string
  weekly_schedule: TrainingDay[]
  progression_rule: string
  notes?: string
}

const TRAINING_SYSTEM_PROMPT = `Você é Dr. Roberto Menescal, conduzindo o Método MPP via WhatsApp.

Sua tarefa: gerar um plano de treino semanal personalizado pro paciente baseado em:
1. Perfil (nível, protocolo, limitações)
2. Equipamentos disponíveis
3. Dias por semana que ele consegue treinar
4. Grupos musculares de prioridade

REGRAS MPP (seção "Prescrição de treinos" do manual):
- Compostos primeiro, isoladores depois
- Séries por músculo/semana: 10-20 séries efetivas
- Repetições por série: 6-15
- Intervalo de descanso: 60-120s
- Intensidade: até falha muscular técnica (paciente "topa falha")
  - Se iniciante: período de aclimatação 15d com mesmo peso, depois adaptação 4-6 meses em escada (1ª 12-15 / 2ª 10-12 / 3ª 8-10 / 4ª 6-8 reps)
  - Se já treina: progressão linear 6→7→8→...→12 reps, então aumenta peso e volta pra 6
- Divisões válidas: Full Body, Upper/Lower, Push/Pull/Legs, ABC
- Tendência por sexo (não regra): Homens → peitoral/dorsal/braços/ombros. Mulheres → glúteos/MMII/core.

USE só equipamentos da lista disponível.

OUTPUT em JSON com schema:
{
  "plan_type": "split" | "full_body" | "custom",
  "weekly_schedule": [{ day, focus, duration_min, exercises: [{ name, muscle_group, sets, reps_range, rest_seconds, rpe_target, notes, execution_steps: ["..."], common_mistakes: ["..."] }] }],
  "progression_rule": "Adicione 1 rep por treino. Bateu 12 reps com técnica → aumenta peso, volta pra 6.",
  "notes": "..."
}

Compostos constroem; isoladores lapidam. Treine até a falha muscular técnica.`

export async function generateTrainingPlan(
  llm: OpenRouterLLM,
  _supabase: ServiceClient,
  input: TrainingGeneratorInput,
): Promise<TrainingPlan | null> {
  const equipSummary = input.available_equipment.join(', ')
  const limitations =
    (input.profile.limitations ?? []).length > 0 ? input.profile.limitations!.join(', ') : '(nenhuma)'
  const priority =
    (input.profile.priority_muscles ?? []).length > 0
      ? input.profile.priority_muscles!.join(', ')
      : '(sem prioridade específica)'

  const userPayload = `Paciente: ${input.profile.name ?? '?'} (${input.profile.sex}, ${input.profile.age}a)
Protocolo: ${input.profile.protocol}
Nível: ${input.profile.training_level}
Limitações: ${limitations}
Prioridade muscular: ${priority}

Local: ${input.location}
Equipamentos: ${equipSummary}
Dias por semana: ${input.days_per_week}${input.training_days ? ` (${input.training_days.join('/')})` : ''}
Topa falha muscular: ${input.goes_to_failure ?? 'não sei'}

Gere o plano em JSON.`

  try {
    const result = await llm.complete({
      model: 'anthropic/claude-sonnet-4.5',
      systemPrompt: TRAINING_SYSTEM_PROMPT,
      messages: [{ role: 'user', content: userPayload }],
      temperature: 0.4,
      maxTokens: 4500,
      metadata: { Stage: 'training-generator' },
    })
    const content = result.content ?? ''
    const jsonMatch = content.match(/\{[\s\S]*\}/)
    if (!jsonMatch) return null
    const parsed = JSON.parse(jsonMatch[0]) as Partial<TrainingPlan>
    if (!parsed.weekly_schedule) return null

    return {
      user_id: input.userId,
      generated_at: new Date().toISOString(),
      plan_type: parsed.plan_type ?? 'split',
      days_per_week: input.days_per_week,
      equipment_summary: equipSummary,
      weekly_schedule: parsed.weekly_schedule,
      progression_rule:
        parsed.progression_rule ??
        'Adicione 1 rep por treino. Bateu 12 reps com técnica → aumenta peso, volta pra 6.',
      notes: parsed.notes,
    }
  } catch {
    return null
  }
}

/**
 * Persiste o plano em `training_plans` (tabela criada em
 * 20260611230000_prescriptions_training_phrases.sql). Marca planos
 * anteriores como inactive.
 */
export async function saveTrainingPlan(
  supabase: ServiceClient,
  plan: TrainingPlan,
): Promise<{ id: string | null }> {
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  const sp = supabase as any
  // Desativa planos antigos
  await sp.from('training_plans').update({ active: false }).eq('user_id', plan.user_id)

  const { data, error } = await sp
    .from('training_plans')
    .insert({
      user_id: plan.user_id,
      plan_type: plan.plan_type,
      days_per_week: plan.days_per_week,
      equipment_summary: plan.equipment_summary,
      weekly_schedule: plan,
      generated_by: 'agent',
      generated_at: plan.generated_at,
      // valid_until 6 semanas — plano "esporádico" (Roberto): paciente pode
      // pedir regenerar antes se equipamentos/rotina mudarem
      valid_until: new Date(Date.now() + 6 * 7 * 24 * 3600 * 1000).toISOString(),
      active: true,
      version: 1,
      notes: plan.notes,
    })
    .select('id')
    .single()
  if (error) return { id: null }
  return { id: data?.id ?? null }
}

/**
 * Retorna o treino do dia atual pra entregar via cron determinístico
 * (sem LLM). Se hoje não é dia de treino, retorna null.
 *
 * Usado em `meal-gap-reminder`-style cron matinal.
 */
export async function getTodayTraining(
  supabase: ServiceClient,
  userId: string,
  todayLabel: string, // 'seg', 'ter', etc — calc do timezone do paciente
): Promise<{ plan_id: string; day: TrainingDay } | null> {
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  const sp = supabase as any
  const { data } = await sp
    .from('training_plans')
    .select('id, weekly_schedule')
    .eq('user_id', userId)
    .eq('active', true)
    .order('generated_at', { ascending: false })
    .limit(1)
    .maybeSingle()
  if (!data) return null
  const schedule = (data.weekly_schedule as { weekly_schedule?: TrainingDay[] })?.weekly_schedule
  if (!Array.isArray(schedule)) return null
  const today = schedule.find((d) => d.day === todayLabel)
  if (!today) return null
  return { plan_id: data.id, day: today }
}
