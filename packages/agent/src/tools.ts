/**
 * Tools que o LLM pode chamar. Cada tool tem:
 *  - schema (JSON Schema para o LLM)
 *  - execute(args, ctx) que opera no Supabase
 *
 * Formato compatível com OpenAI tool calling.
 */
import { computeMetrics } from '@mpp/core'
import type { ServiceClient } from '@mpp/db'
import { z } from 'zod'
import { calcMealMacros } from './meal-pipeline.js'
import { loadCalcConfig } from './calc-config-loader.js'
import { loadDailyTargets } from './calc-targets.js'
import { countryToTimezone, getLocalDateString } from './timezone-utils.js'
import { detectCorrectionIntent } from './correction-detector.js'

export interface ToolContext {
  supabase: ServiceClient
  userId: string
  userWpp: string
  /** ISO alpha-2 do país de residência (pra TACO/USDA, persona, idioma). */
  userCountry?: string
  /** Timezone IANA do paciente (default America/Sao_Paulo). Usado pra
   * computar a data LOCAL ao buscar/inserir snapshot. Antes usava UTC
   * → paciente em New_York perdia consumo registrado entre 20h-24h. */
  userTimezone?: string
  /** ID da mensagem que originou o turno (provider_message_id). Usado pra
   * dedup de inserts em logs (meal_logs, workout_logs) — protege contra
   * dupla contagem em retentativas do Inngest. */
  providerMessageId?: string
  /** Últimas N mensagens do PACIENTE (direção 'in') no turno atual.
   * Usado pra validação semântica determinística — ex: detectar se
   * `replace=true` em registra_refeicao é legítimo (paciente disse
   * "corrige", "errei", etc) ou bug do LLM (foto nova classificada como
   * correção). NÃO substitui prompt rule, é defesa em profundidade. */
  recentUserMessages?: string[]
}

export interface ToolDefinition<T extends z.ZodTypeAny = z.ZodTypeAny> {
  name: string
  description: string
  parameters: T
  execute: (args: z.infer<T>, ctx: ToolContext) => Promise<Record<string, unknown>>
}

// ----------------------------------------------------------------------------
// cadastra_dados_iniciais — popula user_profiles durante onboarding
// ----------------------------------------------------------------------------
export const cadastraDadosIniciais: ToolDefinition = {
  name: 'cadastra_dados_iniciais',
  description:
    'Salva ou atualiza dados FACTUAIS do perfil do paciente (sexo, nascimento, altura, peso, BF%, atividade, sono, fome). ' +
    'Use durante onboarding OU quando o paciente confirmar EXPLICITAMENTE que quer atualizar ("meu peso mudou", "agora meço 1.80m"). ' +
    '⚠️ NÃO USE quando: ' +
    '(a) o paciente está ESPECULANDO ("acho que tenho uns 25%", "talvez seja 80kg"); ' +
    '(b) o paciente está REFLETINDO sobre dados antigos; ' +
    '(c) os números vieram de fonte externa não confirmada (foto de balança sem confirmação verbal). ' +
    '🚨 UNIDADES: height_cm SEMPRE em centímetros, weight_kg SEMPRE em quilos. Se o paciente disser em lb/inch (sistema imperial salvo em users.metadata.unit_system), CONVERTA antes (1 inch=2.54 cm, 1 lb=0.4536 kg). A tool valida limites: altura 100-250cm, peso 30-300kg, BF 5-60%. Se não bater, é provavelmente unidade errada — recue e pergunte.',
  parameters: z.object({
    name: z.string().optional().describe('Nome do usuário'),
    sex: z.enum(['masculino', 'feminino']).optional(),
    birth_date: z
      .string()
      .optional()
      .describe(
        'YYYY-MM-DD. Se você só sabe a idade do paciente, passe o número (ex: "44") — a tool deriva birth_date = ano_atual − idade.',
      ),
    height_cm: z.number().optional(),
    weight_kg: z.number().optional(),
    body_fat_percent: z.number().optional(),
    activity_level: z
      .enum(['sedentario', 'leve', 'moderado', 'alto', 'atleta'])
      .optional(),
    training_frequency: z.number().int().min(0).max(7).optional(),
    water_intake: z.enum(['pouco', 'moderado', 'bastante']).optional(),
    hunger_level: z.enum(['pouca', 'moderada', 'muita']).optional(),
    wake_time: z.string().optional().describe('HH:MM (também aceita "23h", "5h", "23:00:00")'),
    bedtime: z.string().optional().describe('HH:MM (também aceita "23h", "5h", "23:00:00")'),
    food_organization: z
      .enum(['sim', 'nao'])
      .optional()
      .describe(
        'Alimentação estruturada (paciente segue plano vs improvisa). Critério obrigatório pra Ganho de Massa per doc Notion. Pergunte: "Você costuma seguir um plano alimentar ou come o que aparece no dia?"',
      ),
    onboarding_step: z.number().int().min(0).max(11).optional(),
    onboarding_completed: z.boolean().optional(),
  }),
  execute: async (args, ctx) => {
    const updates: Record<string, unknown> = {}
    // Helper: aceita só números > 0 (LLM costuma mandar 0 como placeholder)
    const numPositive = (v: unknown): boolean => typeof v === 'number' && v > 0
    const strNonEmpty = (v: unknown): boolean => typeof v === 'string' && v.trim().length > 0
    const sanityErrors: string[] = []
    const inRange = (v: number, min: number, max: number, label: string, hint: string) => {
      if (v < min || v > max) sanityErrors.push(`${label}=${v} fora do esperado ${min}-${max}. ${hint}`)
    }

    if (strNonEmpty(args.sex)) updates.sex = args.sex
    // Coerção birth_date: aceita "YYYY-MM-DD", "DD/MM/YYYY" ou número (idade em anos).
    // LLM costumava passar a idade ("44") em vez de data — convertemos.
    if (strNonEmpty(args.birth_date)) {
      const raw = args.birth_date!.trim()
      if (/^\d{4}-\d{2}-\d{2}$/.test(raw)) {
        updates.birth_date = raw
      } else if (/^\d{1,2}\/\d{1,2}\/\d{4}$/.test(raw)) {
        const [d, m, y] = raw.split('/')
        updates.birth_date = `${y}-${m!.padStart(2, '0')}-${d!.padStart(2, '0')}`
      } else if (/^\d{1,3}$/.test(raw)) {
        // Idade em anos: deriva birth_date = ano_atual − idade, dia 1/janeiro
        const age = parseInt(raw, 10)
        if (age >= 12 && age <= 120) {
          updates.birth_date = `${new Date().getUTCFullYear() - age}-01-01`
        }
      }
    }
    if (numPositive(args.height_cm)) {
      inRange(args.height_cm!, 100, 250, 'height_cm', 'Provavelmente passou em inches — converta: cm = inch × 2.54.')
      updates.height_cm = args.height_cm
    }
    if (numPositive(args.weight_kg)) {
      inRange(args.weight_kg!, 30, 300, 'weight_kg', 'Provavelmente passou em libras — converta: kg = lb × 0.4536.')
      updates.weight_kg = args.weight_kg
    }
    if (numPositive(args.body_fat_percent)) {
      inRange(args.body_fat_percent!, 3, 60, 'body_fat_percent', 'BF% válido fica em 3-60. Reverifique com o paciente.')
      updates.body_fat_percent = args.body_fat_percent
    }
    if (sanityErrors.length > 0) {
      return { success: false, error: 'sanity_check_failed', issues: sanityErrors }
    }
    if (strNonEmpty(args.activity_level)) updates.activity_level = args.activity_level
    if (numPositive(args.training_frequency))
      updates.training_frequency = args.training_frequency
    if (strNonEmpty(args.water_intake)) updates.water_intake = args.water_intake
    if (strNonEmpty(args.hunger_level)) updates.hunger_level = args.hunger_level
    // Coerção time: aceita "HH:MM", "HH:MM:SS", "HHh", "HHhMM", "HH"
    // LLM costumava passar "23h" e "5h" — Postgres TIME rejeitava.
    const coerceTime = (raw: string): string | null => {
      const s = raw.trim().toLowerCase()
      if (/^\d{1,2}:\d{2}(:\d{2})?$/.test(s)) {
        const parts = s.split(':')
        return `${parts[0]!.padStart(2, '0')}:${parts[1]}:${parts[2] ?? '00'}`
      }
      const m = s.match(/^(\d{1,2})h(\d{0,2})$/)
      if (m) return `${m[1]!.padStart(2, '0')}:${(m[2] || '00').padStart(2, '0')}:00`
      if (/^\d{1,2}$/.test(s)) return `${s.padStart(2, '0')}:00:00`
      return null
    }
    if (strNonEmpty(args.wake_time)) {
      const t = coerceTime(args.wake_time!)
      if (t) updates.wake_time = t
    }
    if (strNonEmpty(args.bedtime)) {
      const t = coerceTime(args.bedtime!)
      if (t) updates.bedtime = t
    }
    if (strNonEmpty(args.food_organization)) updates.food_organization = args.food_organization
    if (typeof args.onboarding_step === 'number' && args.onboarding_step >= 0)
      updates.onboarding_step = args.onboarding_step
    if (typeof args.onboarding_completed === 'boolean')
      updates.onboarding_completed = args.onboarding_completed
    updates.updated_at = new Date().toISOString()

    const { error: upErr } = await ctx.supabase
      .from('user_profiles')
      .upsert({ user_id: ctx.userId, ...updates }, { onConflict: 'user_id' })
    if (upErr) throw upErr

    if (args.name) {
      await ctx.supabase.from('users').update({ name: args.name }).eq('id', ctx.userId)
    }

    // Lê métricas calculadas via view
    const { data: metrics } = await ctx.supabase
      .from('v_user_metrics')
      .select('*')
      .eq('user_id', ctx.userId)
      .maybeSingle()

    // Calcula meta canônica AGORA (com profile recém-atualizado) pra evitar
    // que o LLM estime na cabeça. Pode ser null se ainda faltam dados.
    const cfg = await loadCalcConfig(ctx.supabase)
    const targets = await loadDailyTargets(ctx.supabase, ctx.userId, cfg)

    return {
      success: true,
      updated_fields: Object.keys(updates),
      metrics: metrics ?? null,
      // ⚠️ Sempre que estes valores estiverem presentes, USE EXATAMENTE eles
      // ao informar meta ao paciente — não calcule na cabeça.
      calories_target_today: targets.calories_target,
      protein_target_today_g: targets.protein_target,
    }
  },
}

// ----------------------------------------------------------------------------
// define_protocolo — grava o protocolo escolhido
// ----------------------------------------------------------------------------
export const defineProtocolo: ToolDefinition = {
  name: 'define_protocolo',
  description:
    'Grava o protocolo nutricional + meta DO PACIENTE. ' +
    '⚠️ USE APENAS depois que: (1) cadastra_dados_iniciais foi chamada com peso/altura/BF; ' +
    '(2) você apresentou as 3 opções (recomposicao/ganho_massa/manutencao) e o paciente escolheu UMA explicitamente; ' +
    '(3) você apresentou o nível de fome (leve/moderada/alta → 400/500/600 kcal de déficit) e ele escolheu — APENAS pra protocolo recomposicao. ' +
    'NÃO USE quando o paciente apenas DESEJOU genericamente ("quero emagrecer", "quero ganhar massa") — peça pra ele confirmar a opção. ' +
    'Parâmetros: ' +
    'protocol = "recomposicao" (déficit + preserva massa), "ganho_massa" (superávit), "manutencao" (sem ajuste). ' +
    'deficit_level = kcal/dia de déficit, APENAS pra recomposicao. 400=fome leve, 500=moderada, 600=alta. Omita pra ganho_massa/manutencao. ' +
    'goal_type = "BF" (% gordura alvo) ou "IMC" (IMC alvo). ' +
    'goal_value = número absoluto da meta (ex: BF=15 ou IMC=23). Omita se não chegou nesse nível de detalhe.',
  parameters: z.object({
    protocol: z.enum(['recomposicao', 'ganho_massa', 'manutencao']),
    deficit_level: z
      .union([z.literal(400), z.literal(500), z.literal(600)])
      .optional()
      .describe('Apenas para protocolo recomposicao. 400=fome leve, 500=moderada, 600=alta.'),
    goal_type: z.enum(['BF', 'IMC']).optional().describe('"BF"=alvo de % gordura corporal, "IMC"=alvo de IMC'),
    goal_value: z.number().optional().describe('Número alvo (ex: 15 pra BF=15%, 23 pra IMC=23)'),
  }),
  execute: async (args, ctx) => {
    const { error } = await ctx.supabase
      .from('user_profiles')
      .update({
        current_protocol: args.protocol,
        deficit_level: args.deficit_level ?? null,
        goal_type: args.goal_type ?? null,
        goal_value: args.goal_value ?? null,
        updated_at: new Date().toISOString(),
      })
      .eq('user_id', ctx.userId)
    if (error) throw error

    // Calcula e RETORNA a meta canônica imediatamente — assim o LLM não precisa
    // estimar na cabeça (bug histórico: LLM dizia TDEE em vez de BMR×1.2−déficit).
    // Próxima resposta do LLM tem o valor pronto pra usar.
    const config = await loadCalcConfig(ctx.supabase)
    const targets = await loadDailyTargets(ctx.supabase, ctx.userId, config)

    return {
      success: true,
      protocol: args.protocol,
      // ⚠️ USE EXATAMENTE estes valores quando informar a meta ao paciente.
      calories_target_today: targets.calories_target,
      protein_target_today_g: targets.protein_target,
      formula_used:
        args.protocol === 'recomposicao'
          ? `BMR × ${config.recomp_bmr_multiplier} − ${args.deficit_level ?? 500} kcal (déficit)`
          : args.protocol === 'ganho_massa'
            ? `BMR × activity_factor × ${config.ganho_massa_surplus_multiplier} (superávit leve)`
            : 'BMR × activity_factor (manutenção)',
    }
  },
}

// ----------------------------------------------------------------------------
// registra_refeicao — usa TACO determinísticamente (ADR-006)
// ----------------------------------------------------------------------------
export const registraRefeicao: ToolDefinition = {
  name: 'registra_refeicao',
  description:
    'Registra uma REFEIÇÃO QUE O PACIENTE ACABOU DE CONSUMIR (consumida hoje, agora ou nas últimas horas). Macros calculados automaticamente via base nutricional TACO. NÃO calcule macros manualmente. ' +
    '⚠️ NÃO USE esta tool quando: ' +
    '(a) o paciente está descrevendo PADRÃO ALIMENTAR ou respondendo perguntas como "o que costuma comer", "o que gosta", "o que costuma fazer no café da manhã" — isso é coleta pra montar plano, não consumo; ' +
    '(b) o paciente está descrevendo cardápio HIPOTÉTICO ou plano futuro ("vou começar a comer X"); ' +
    '(c) o paciente está pedindo sugestão de cardápio. ' +
    'Use APENAS quando há sinal claro de CONSUMO RECENTE: "acabei de comer", "no almoço comi", foto de prato real, áudio descrevendo o que comeu hoje, "tomei café da manhã com…". ' +
    'PRESERVE EXATAMENTE o nome que o paciente usou no `food_name` (não troque "ovo mexido" por "ovo cozido", não traduza, não simplifique). ' +
    '🚨 **SEPARE alimentos compostos em itens INDIVIDUAIS no array.** NUNCA mande um nome com "com", "e", "+" — quebre. Exemplos: ' +
    '❌ items=[{food_name:"ovos cozidos com azeite", quantity_g:205}] (causa match errado, virou 1812 kcal de azeite). ' +
    '✅ items=[{food_name:"ovo cozido", quantity_g:200}, {food_name:"azeite de oliva", quantity_g:5}]. ' +
    '❌ items=[{food_name:"arroz com feijão e bife"}]. ' +
    '✅ items=[{food_name:"arroz branco cozido", quantity_g:100}, {food_name:"feijão preto cozido", quantity_g:80}, {food_name:"bife grelhado", quantity_g:120}]. ' +
    'Se o paciente não especificou quantidade, ESTIME baseado em referências visuais/típicas e siga. ' +
    '🔄 CORREÇÃO de refeição já registrada: passe `replace=true` + `meal_type` quando o paciente quiser SUBSTITUIR (ex: "corrige o café, era leite com whey, não chocolate", "na verdade comi X em vez de Y"). Sem replace=true, a tool SOMA ao snapshot — gera dupla contagem. Default replace=false (assume nova refeição). ' +
    '📏 UNIDADES: você passa SEMPRE quantity_g em GRAMAS (interno do sistema). Quando o paciente disser "2 ovos", converta pra 100g (50g/ovo). "250ml de leite" → 250g (1ml ≈ 1g pra líquidos). A tool retorna `display_qty` + `display_unit` no resultado pra você mostrar ao paciente em unidades naturais (ovos→"2 unidades", leite→"250 ml", pão francês→"1 pão"). USE display_qty/display_unit ao redigir a resposta — NÃO mostre "120g de ovo" pro paciente, mostre "2 ovos".',
  parameters: z.object({
    meal_type: z
      .enum(['cafe', 'almoco', 'lanche', 'jantar', 'ceia', 'outro'])
      .optional(),
    replace: z
      .boolean()
      .optional()
      .describe(
        'Se true: deleta meal_logs do dia+meal_type ANTES de inserir os novos (correção/substituição). Se false ou omitido: soma no snapshot (nova refeição).',
      ),
    items: z
      .array(
        z.object({
          food_name: z
            .string()
            .describe(
              'Nome EXATO do alimento como o paciente disse, em português (ex: "ovo mexido", "pão francês"). NÃO altere preparo nem traduza.',
            ),
          quantity_g: z.number().describe('Quantidade em gramas (estime se não informado)'),
        }),
      )
      .describe('Lista de itens consumidos AGORA (não padrão alimentar)'),
  }),
  execute: async (args, ctx) => {
    const today = getLocalDateString(ctx.userTimezone ?? 'America/Sao_Paulo')

    // Idempotência: se essa msg já gerou meal_logs, skipa snapshot increment.
    // Protege contra retry de Inngest e LLM emitindo a mesma tool 2x no turno.
    if (ctx.providerMessageId) {
      const { data: existing } = await ctx.supabase
        .from('meal_logs')
        .select('id, snapshot_id, food_name, kcal')
        .eq('user_id', ctx.userId)
        .eq('raw_provider_message_id', ctx.providerMessageId)
        .limit(20)
      if (existing && existing.length > 0) {
        return {
          success: true,
          deduped: true,
          message: 'Refeição já registrada (msg_id repetido). Não duplicou.',
          existing_count: existing.length,
        }
      }
    }

    // ========================================================================
    // GUARDA-CHUVA DETERMINÍSTICO (defesa em profundidade contra erro do LLM)
    // ========================================================================

    // (1) AUTO-CORRIGE meal_type pela hora local do paciente.
    // Reversível: se LLM passou meal_type errado (ex: "jantar" às 8h da manhã),
    // sistema sobrescreve silenciosamente pra hora-correspondente. Não pergunta
    // pro paciente — UX limpa. Logs em product_events pra auditoria.
    let mealTypeOriginal = args.meal_type
    if (args.meal_type) {
      const tz = ctx.userTimezone ?? 'America/Sao_Paulo'
      const localHour = Number.parseInt(
        new Intl.DateTimeFormat('en-US', { timeZone: tz, hour: '2-digit', hour12: false })
          .formatToParts(new Date())
          .find((p) => p.type === 'hour')?.value ?? '12',
        10,
      )
      const expected =
        localHour >= 5 && localHour < 11
          ? 'cafe'
          : localHour >= 11 && localHour < 15
            ? 'almoco'
            : localHour >= 15 && localHour < 18
              ? 'lanche'
              : localHour >= 18 && localHour < 23
                ? 'jantar'
                : 'lanche'
      if (args.meal_type !== expected) {
        await ctx.supabase.from('product_events').insert({
          user_id: ctx.userId,
          event: 'tool.meal_type_autocorrected',
          properties: {
            claimed: args.meal_type,
            corrected_to: expected,
            local_hour: localHour,
            timezone: tz,
            replace: args.replace ?? false,
          },
        })
        // Sobrescreve args.meal_type com o sugerido pela hora.
        args.meal_type = expected
      }
    }

    // (2) BLOQUEIA replace=true sem palavra-chave de correção.
    // Destrutivo: replace=true DELETA refeições do dia+meal_type.
    // Se últimas msgs do paciente NÃO têm "corrige/errei/troca/na verdade/...",
    // é provavelmente bug do LLM (ex: foto nova classificada como correção).
    // Downgrade pra replace=false silenciosamente — vira INSERT normal.
    if (args.replace === true) {
      const recentMsgs = ctx.recentUserMessages ?? []
      const correctionWord = detectCorrectionIntent(recentMsgs)
      if (!correctionWord) {
        await ctx.supabase.from('product_events').insert({
          user_id: ctx.userId,
          event: 'tool.replace_blocked_no_correction',
          properties: {
            meal_type: mealTypeOriginal,
            corrected_meal_type: args.meal_type,
            recent_msgs_count: recentMsgs.length,
            recent_msgs_preview: recentMsgs.slice(-2).map((m) => m.slice(0, 80)),
          },
        })
        // Downgrade silencioso — segue como INSERT normal.
        args.replace = false
      }
    }
    // ========================================================================

    // CORREÇÃO: paciente quer substituir refeição já registrada hoje.
    // Deleta meal_logs do dia+meal_type e SUBTRAI seus macros do snapshot
    // antes de inserir os novos. Sem isso, snapshot_add_meal duplica.
    let replacedSummary: { count: number; kcal_removed: number } | null = null
    if (args.replace === true && args.meal_type) {
      const startOfDay = `${today}T00:00:00`
      const endOfDay = `${today}T23:59:59.999`
      const { data: toRemove } = await ctx.supabase
        .from('meal_logs')
        .select('id, kcal, protein_g, carbs_g, fat_g')
        .eq('user_id', ctx.userId)
        .eq('meal_type', args.meal_type)
        .gte('created_at', startOfDay)
        .lte('created_at', endOfDay)
      if (toRemove && toRemove.length > 0) {
        const removed = toRemove.reduce(
          (acc, l) => ({
            kcal: acc.kcal + Number(l.kcal ?? 0),
            prot: acc.prot + Number(l.protein_g ?? 0),
            carb: acc.carb + Number(l.carbs_g ?? 0),
            fat: acc.fat + Number(l.fat_g ?? 0),
          }),
          { kcal: 0, prot: 0, carb: 0, fat: 0 },
        )
        // Deleta os logs antigos
        await ctx.supabase
          .from('meal_logs')
          .delete()
          .eq('user_id', ctx.userId)
          .eq('meal_type', args.meal_type)
          .gte('created_at', startOfDay)
          .lte('created_at', endOfDay)
        // Subtrai do snapshot via RPC (passa valores negativos)
        await (ctx.supabase as unknown as {
          rpc: (n: string, p: Record<string, unknown>) => Promise<{ error: unknown }>
        }).rpc('snapshot_add_meal', {
          p_user_id: ctx.userId,
          p_date: today,
          p_kcal: -removed.kcal,
          p_protein: -removed.prot,
          p_carbs: -removed.carb,
          p_fat: -removed.fat,
          p_calories_target: null,
          p_protein_target: null,
        })
        replacedSummary = { count: toRemove.length, kcal_removed: Math.round(removed.kcal) }
      } else {
        // replace=true mas nada pra substituir hoje desse meal_type.
        // É indício de bug do LLM (achou que era correção quando não era).
        // Loga e segue com insert normal — não bloqueia paciente.
        await ctx.supabase.from('product_events').insert({
          user_id: ctx.userId,
          event: 'tool.replace_without_target',
          properties: {
            meal_type: args.meal_type,
            date: today,
            note: 'replace=true mas nenhum meal_log existente desse tipo hoje',
          },
        })
      }
    }

    // Calcula macros via TACO
    const calc = await calcMealMacros(
      ctx.supabase,
      args.items,
      ctx.userCountry ?? 'BR',
      ctx.userId,
    )

    // Loga warnings de match (composite/category/protein/no_match) em product_events
    // pra aparecer agregado em /audit. Útil pra detectar padrões de match errado.
    const problematicItems = calc.items.filter((i) =>
      ['composite_rejected', 'category_mismatch', 'protein_mismatch', 'no_match'].includes(
        i.source,
      ),
    )
    if (problematicItems.length > 0) {
      await ctx.supabase.from('product_events').insert({
        user_id: ctx.userId,
        event: 'meal.match_warning',
        properties: {
          provider_message_id: ctx.providerMessageId ?? null,
          warnings: calc.warnings,
          problematic_items: problematicItems.map((i) => ({
            food_name: i.food_name,
            matched_to: i.matched_taco_name || null,
            source: i.source,
            similarity: i.similarity,
          })),
          total_items: calc.items.length,
        },
      })
    }

    // Garante targets calculados (calories_target + protein_target).
    // Sem isso, daily_balance fica positivo sempre e bloco 7700 nunca cresce.
    const config = await loadCalcConfig(ctx.supabase)
    const targets = await loadDailyTargets(ctx.supabase, ctx.userId, config)

    // RPC atomic: cria ou incrementa snapshot SEM race condition.
    const { data: updated, error: updErr } = await (ctx.supabase as unknown as {
      rpc: (
        n: string,
        p: Record<string, unknown>,
      ) => Promise<{
        data: { id: string; calories_consumed: number; protein_g: number; calories_target: number | null; protein_target: number | null; daily_balance: number } | null
        error: { message?: string } | null
      }>
    }).rpc('snapshot_add_meal', {
      p_user_id: ctx.userId,
      p_date: today,
      p_kcal: calc.totals.kcal,
      p_protein: calc.totals.protein_g,
      p_carbs: calc.totals.carbs_g,
      p_fat: calc.totals.fat_g,
      p_calories_target: targets.calories_target,
      p_protein_target: targets.protein_target,
    })
    if (updErr) throw new Error(updErr.message ?? 'snapshot_add_meal failed')
    if (!updated) throw new Error('snapshot_add_meal returned null')
    const snapshotId = updated.id

    // Insere cada item em meal_logs com upsert idempotente
    // (UNIQUE composite user_id,raw_provider_message_id,food_name).
    for (const item of calc.items) {
      await ctx.supabase.from('meal_logs').insert({
        user_id: ctx.userId,
        snapshot_id: snapshotId,
        meal_type: args.meal_type ?? null,
        food_name: item.food_name,
        quantity_g: item.quantity_g,
        kcal: item.kcal,
        protein_g: item.protein_g,
        carbs_g: item.carbs_g,
        fat_g: item.fat_g,
        source: item.source,
        confidence: item.similarity,
        raw_provider_message_id: ctx.providerMessageId ?? null,
      })
    }

    return {
      success: true,
      meal: {
        items: calc.items.map((i) => ({
          name: i.food_name,
          matched_to: i.matched_taco_name || null,
          quantity_g: i.quantity_g,
          // ⚠️ Use display_qty + display_unit ao MOSTRAR refeição ao paciente.
          // Ex: "2 unidades", "250 ml" — mais natural que "120g" pra ovo, "280g" pra leite.
          display_qty: i.display_qty ?? i.quantity_g,
          display_unit: i.display_unit ?? 'g',
          kcal: i.kcal,
          protein_g: i.protein_g,
          carbs_g: i.carbs_g,
          fat_g: i.fat_g,
          source: i.source,
        })),
        totals: calc.totals,
      },
      day_totals: updated,
      warnings: calc.warnings,
      replaced: replacedSummary,
    }
  },
}

// ----------------------------------------------------------------------------
// consulta_progresso — retorna painel atual
// ----------------------------------------------------------------------------
export const consultaProgresso: ToolDefinition = {
  name: 'consulta_progresso',
  description:
    'Retorna o painel de progresso do usuário (XP, level, streak, blocos completos, badges, último snapshot). Use quando ele perguntar como está indo.',
  parameters: z.object({}),
  execute: async (_args, ctx) => {
    const { data: progress } = await ctx.supabase
      .from('user_progress')
      .select('*')
      .eq('user_id', ctx.userId)
      .maybeSingle()

    const today = getLocalDateString(ctx.userTimezone ?? 'America/Sao_Paulo')
    const { data: snap } = await ctx.supabase
      .from('daily_snapshots')
      .select('*')
      .eq('user_id', ctx.userId)
      .eq('date', today)
      .maybeSingle()

    return { progress: progress ?? null, today: snap ?? null }
  },
}

// ----------------------------------------------------------------------------
// consulta_metricas — métricas determinísticas (anti-alucinação)
// ----------------------------------------------------------------------------
export const consultaMetricas: ToolDefinition = {
  name: 'consulta_metricas',
  description:
    'Retorna métricas DETERMINÍSTICAS do paciente: idade, BMR, TDEE, IMC, LBM, meta calórica de hoje, meta de proteína. ' +
    'Use APENAS quando precisar de um número que NÃO está no contexto do sistema (ex: paciente pediu "qual meu TDEE?" mas o contexto não trouxe). ' +
    '⚠️ NÃO use rotineiramente — o contexto do sistema já injeta meta/balanço/IMC na maioria dos turnos. ' +
    'Esta tool é o ESCAPE HATCH pra evitar alucinação quando o LLM ficaria tentado a calcular na cabeça.',
  parameters: z.object({}),
  execute: async (_args, ctx) => {
    const { data: profile } = await ctx.supabase
      .from('user_profiles')
      .select('*')
      .eq('user_id', ctx.userId)
      .maybeSingle()
    if (!profile) return { error: 'profile_not_found' }

    const config = await loadCalcConfig(ctx.supabase)
    const targets = await loadDailyTargets(ctx.supabase, ctx.userId, config)

    const profileTyped = profile as {
      sex: 'masculino' | 'feminino' | null
      birth_date: string | null
      height_cm: number | null
      weight_kg: number | null
      body_fat_percent: number | null
      activity_level: 'sedentario' | 'leve' | 'moderado' | 'alto' | 'atleta' | null
      training_frequency: number | null
      hunger_level: 'pouca' | 'moderada' | 'muita' | null
      current_protocol: 'recomposicao' | 'ganho_massa' | 'manutencao' | null
      goal_type: 'BF' | 'IMC' | null
      goal_value: number | null
      deficit_level: 400 | 500 | 600 | null
      water_intake: 'pouco' | 'moderado' | 'bastante' | null
    }
    const m = computeMetrics(
      {
        sex: profileTyped.sex,
        birthDate: profileTyped.birth_date ? new Date(profileTyped.birth_date) : null,
        heightCm: profileTyped.height_cm != null ? Number(profileTyped.height_cm) : null,
        weightKg: profileTyped.weight_kg != null ? Number(profileTyped.weight_kg) : null,
        bodyFatPercent:
          profileTyped.body_fat_percent != null ? Number(profileTyped.body_fat_percent) : null,
        activityLevel: profileTyped.activity_level,
        trainingFrequency: profileTyped.training_frequency,
        waterIntake: profileTyped.water_intake,
        hungerLevel: profileTyped.hunger_level,
        currentProtocol: profileTyped.current_protocol,
        goalType: profileTyped.goal_type,
        goalValue:
          profileTyped.goal_value != null ? Number(profileTyped.goal_value) : null,
        deficitLevel: profileTyped.deficit_level,
      },
      new Date(),
      config,
    )

    const tdee =
      m.bmr != null && m.activityFactor != null ? Math.round(m.bmr * m.activityFactor) : null

    return {
      age_years: m.age,
      bmr_kcal: m.bmr != null ? Math.round(m.bmr) : null,
      tdee_kcal: tdee,
      imc: m.imc != null ? +m.imc.toFixed(1) : null,
      lbm_kg: m.lbm != null ? +m.lbm.toFixed(1) : null,
      calories_target_today: targets.calories_target,
      protein_target_today_g: targets.protein_target,
      activity_factor: m.activityFactor,
      formula_used:
        profileTyped.body_fat_percent != null ? 'Katch-McArdle (com BF%)' : 'Mifflin-St Jeor',
    }
  },
}

// ----------------------------------------------------------------------------
// registra_treino
// ----------------------------------------------------------------------------
export const registraTreino: ToolDefinition = {
  name: 'registra_treino',
  description:
    'Registra um TREINO QUE O PACIENTE ACABOU DE EXECUTAR (completado hoje, agora ou nas últimas horas). Kcal queimadas calculadas automaticamente (workout_type × duração × intensidade × peso). NÃO calcule manualmente. ' +
    '⚠️ NÃO USE quando: ' +
    '(a) o paciente está descrevendo FREQUÊNCIA/PADRÃO ("treino 3x por semana", "qual sua frequência?", "costumo treinar de manhã") — isso é coleta pra montar plano; ' +
    '(b) o paciente está descrevendo treino FUTURO ou PLANEJADO ("vou começar a treinar", "amanhã faço pernas", "tô pensando em correr"); ' +
    '(c) o paciente pedindo SUGESTÃO de treino. ' +
    'Use APENAS com sinais claros de EXECUÇÃO RECENTE: "acabei de sair da academia", "treino de hoje foi…", "agora saí da corrida", "treinei pernas hoje".',
  parameters: z.object({
    workout_type: z
      .string()
      .describe(
        [
          'Slug do tipo de treino. Use o MAIS específico que o paciente descreveu.',
          'MUSCULAÇÃO: peito_triceps, costas_biceps, perna_completa (=pernas),',
          '  ombro_trapezio (=ombros), abdomen (=abdominal), biceps_triceps,',
          '  gluteos, full_body, treino_a / treino_b / treino_c, musculacao (genérico).',
          'CARDIO: corrida, corrida_leve, corrida_intensa, caminhada, caminhada_rapida,',
          '  bicicleta, eliptico, escada, natacao, hiit, jumping_jacks, esteira,',
          '  spinning, remo, zumba, danca, cardio (genérico), aerobico.',
          'ESPORTE: futebol, volei, beach_tennis, tenis, basquete, luta,',
          '  jiu_jitsu (=bjj), boxe, muay_thai, escalada.',
          'CALISTENIA: calistenia, handstand, crossfit (=crossfit_wod=funcional).',
          'MOBILIDADE: yoga, pilates (=pilates_solo), alongamento (=flex), mobility.',
          'Se não conseguir classificar: "outro".',
        ].join('\n'),
      ),
    duration_min: z.number().int().positive(),
    intensity: z.enum(['leve', 'moderada', 'alta']).optional(),
    notes: z.string().optional(),
  }),
  execute: async (args, ctx) => {
    const today = getLocalDateString(ctx.userTimezone ?? 'America/Sao_Paulo')

    // Idempotência: se essa msg já gerou workout_logs, skipa snapshot increment.
    if (ctx.providerMessageId) {
      const { data: existing } = await ctx.supabase
        .from('workout_logs')
        .select('id, snapshot_id, workout_type, estimated_kcal')
        .eq('user_id', ctx.userId)
        .eq('raw_provider_message_id', ctx.providerMessageId)
        .limit(5)
      if (existing && existing.length > 0) {
        return {
          success: true,
          deduped: true,
          message: 'Treino já registrado (msg_id repetido). Não duplicou.',
        }
      }
    }

    // Targets calóricos
    const cfg = await loadCalcConfig(ctx.supabase)
    const tgt = await loadDailyTargets(ctx.supabase, ctx.userId, cfg)

    // Pega peso atual pra calcular kcal (escala linear ref 70kg)
    const { data: prof } = await ctx.supabase
      .from('user_profiles')
      .select('weight_kg')
      .eq('user_id', ctx.userId)
      .maybeSingle()
    const weightKg = (prof as { weight_kg: number | null } | null)?.weight_kg ?? 70

    // Cálculo determinístico via SQL function (ADR-007)
    const { data: kcalResult, error: kcalErr } = await (ctx.supabase as unknown as {
      rpc: (
        n: string,
        p: Record<string, unknown>,
      ) => Promise<{ data: number | null; error: { message?: string } | null }>
    }).rpc('calc_workout_kcal', {
      p_slug: args.workout_type,
      p_duration_min: args.duration_min,
      p_intensity: args.intensity ?? 'moderada',
      p_weight_kg: weightKg,
    })
    if (kcalErr) throw new Error(kcalErr.message ?? 'calc_workout_kcal failed')
    const computedKcal = Number(kcalResult ?? 0)

    // Atomic: snapshot + targets + workout kcal
    const { data: snap, error: snapErr } = await (ctx.supabase as unknown as {
      rpc: (
        n: string,
        p: Record<string, unknown>,
      ) => Promise<{
        data: { id: string; exercise_calories: number; training_done: boolean } | null
        error: { message?: string } | null
      }>
    }).rpc('snapshot_add_workout', {
      p_user_id: ctx.userId,
      p_date: today,
      p_exercise_kcal: computedKcal,
      p_calories_target: tgt.calories_target,
      p_protein_target: tgt.protein_target,
    })
    if (snapErr) throw new Error(snapErr.message ?? 'snapshot_add_workout failed')
    if (!snap) throw new Error('snapshot_add_workout returned null')

    await ctx.supabase.from('workout_logs').insert({
      user_id: ctx.userId,
      snapshot_id: snap.id,
      workout_type: args.workout_type,
      duration_min: args.duration_min,
      intensity: args.intensity,
      estimated_kcal: computedKcal,
      notes: args.notes,
      raw_provider_message_id: ctx.providerMessageId ?? null,
    })

    return {
      success: true,
      kcal_burned: computedKcal,
      total_exercise_kcal_today: snap.exercise_calories,
    }
  },
}

// ----------------------------------------------------------------------------
// atualiza_data_user — nome, timezone, city
// ----------------------------------------------------------------------------
export const atualizaDataUser: ToolDefinition = {
  name: 'atualiza_data_user',
  description:
    'Atualiza dados básicos do usuário: nome (preferido), timezone (IANA, ex: America/Sao_Paulo) e cidade.',
  parameters: z.object({
    name: z.string().optional(),
    timezone: z.string().optional(),
    city: z.string().optional(),
  }),
  execute: async (args, ctx) => {
    const updates: {
      name?: string
      timezone?: string
      metadata?: import('@mpp/db').Json
      updated_at: string
    } = { updated_at: new Date().toISOString() }
    if (args.name) updates.name = args.name
    if (args.timezone) updates.timezone = args.timezone
    if (Object.keys(updates).length > 1) {
      const { error } = await ctx.supabase.from('users').update(updates).eq('id', ctx.userId)
      if (error) throw error
    }
    if (args.city) {
      // Atomic merge — não usar read-then-write (race com pause, escalation, etc)
      const { error: rpcErr } = await (ctx.supabase as unknown as {
        rpc: (n: string, p: Record<string, unknown>) => Promise<{ error: { message?: string } | null }>
      }).rpc('user_metadata_merge', {
        p_user_id: ctx.userId,
        p_patch: { city: args.city },
      })
      if (rpcErr) throw new Error(rpcErr.message ?? 'user_metadata_merge failed')
    }
    return { success: true, updated: [...Object.keys(updates), ...(args.city ? ['city'] : [])] }
  },
}

// ----------------------------------------------------------------------------
// encerra_atendimento — escala para humano
// ----------------------------------------------------------------------------
export const encerraAtendimento: ToolDefinition = {
  name: 'encerra_atendimento',
  description:
    'Sinaliza que o usuário pediu/precisa de atendimento humano. Marca o user com label "humano" e registra evento para a equipe ser notificada.',
  parameters: z.object({
    motivo: z.string().describe('Razão pela qual está escalando'),
  }),
  execute: async (args, ctx) => {
    // Atomic: adiciona label 'humano' + grava metadata extra na mesma transação
    const { data: result, error: rpcErr } = await (ctx.supabase as unknown as {
      rpc: (
        n: string,
        p: Record<string, unknown>,
      ) => Promise<{ data: { labels?: string[] } | null; error: { message?: string } | null }>
    }).rpc('user_metadata_label_add', {
      p_user_id: ctx.userId,
      p_label: 'humano',
      p_extra_patch: {
        escalated_at: new Date().toISOString(),
        escalation_reason: args.motivo,
      },
    })
    if (rpcErr) throw new Error(rpcErr.message ?? 'user_metadata_label_add failed')

    await ctx.supabase.from('product_events').insert({
      user_id: ctx.userId,
      event: 'human.escalation_requested',
      properties: { motivo: args.motivo, wpp: ctx.userWpp },
    })

    return { success: true, labels: result?.labels ?? ['humano'] }
  },
}

// ----------------------------------------------------------------------------
// delete_user — direito ao esquecimento (LGPD)
// ----------------------------------------------------------------------------
export const deleteUser: ToolDefinition = {
  name: 'delete_user',
  description:
    'Apaga TODOS os dados do usuário (LGPD). Use APENAS quando o usuário pedir explicitamente "apagar minha conta", "deletar meus dados" ou "reset_chat". Cascata em CASCADE remove perfil, progresso, mensagens, snapshots.',
  parameters: z.object({
    confirmacao: z.literal('confirmo').describe('Deve ser exatamente "confirmo"'),
  }),
  execute: async (args, ctx) => {
    if (args.confirmacao !== 'confirmo') {
      throw new Error('Confirmação inválida')
    }
    await ctx.supabase.from('users').update({ status: 'deleted' }).eq('id', ctx.userId)
    await ctx.supabase.from('product_events').insert({
      user_id: ctx.userId,
      event: 'user.delete_requested',
      properties: { wpp: ctx.userWpp, requested_at: new Date().toISOString() },
    })
    return { success: true, message: 'Dados marcados para exclusão. Job batch fará purge físico.' }
  },
}

// ----------------------------------------------------------------------------
// pausar_agente — coloca o agente em modo silencioso por N dias
// ----------------------------------------------------------------------------
export const pausarAgente: ToolDefinition = {
  name: 'pausar_agente',
  description:
    'Pausa o agente para este usuário por N dias. Durante a pausa, mensagens recebidas são reagidas com 💤 e crons de engajamento são ignorados. Use quando o usuário pedir explicitamente "férias", "pausar 1 semana", "parar por uns dias", etc. NUNCA pause sem o usuário pedir.',
  parameters: z.object({
    days: z.number().int().min(1).max(60).describe('Quantos dias pausar (1-60)'),
    reason: z.string().optional().describe('Motivo opcional, livre.'),
  }),
  execute: async (args, ctx) => {
    const { error } = await (ctx.supabase as unknown as {
      rpc: (n: string, p: Record<string, unknown>) => Promise<{ error: unknown }>
    }).rpc('pause_user', { p_user_id: ctx.userId, p_days: args.days })
    if (error) throw error
    const until = new Date(Date.now() + args.days * 86400_000)
    await ctx.supabase.from('product_events').insert({
      user_id: ctx.userId,
      event: 'agent.paused',
      properties: { days: args.days, until: until.toISOString(), reason: args.reason ?? null },
    })
    return {
      success: true,
      paused_until: until.toISOString(),
      paused_days: args.days,
      message: `Agente pausado até ${until.toLocaleDateString('pt-BR')}.`,
    }
  },
}

// ----------------------------------------------------------------------------
// retomar_agente — remove pausa e volta ao normal
// ----------------------------------------------------------------------------
export const retomarAgente: ToolDefinition = {
  name: 'retomar_agente',
  description:
    'Remove uma pausa ativa e retoma o atendimento normal. Use quando o usuário pedir "voltar", "destravar", "retomar agora" antes do prazo da pausa.',
  parameters: z.object({}),
  execute: async (_args, ctx) => {
    const { error } = await (ctx.supabase as unknown as {
      rpc: (n: string, p: Record<string, unknown>) => Promise<{ error: unknown }>
    }).rpc('resume_user', { p_user_id: ctx.userId })
    if (error) throw error
    await ctx.supabase.from('product_events').insert({
      user_id: ctx.userId,
      event: 'agent.resumed',
      properties: { resumed_at: new Date().toISOString() },
    })
    return { success: true, message: 'Pausa removida, atendimento retomado.' }
  },
}

// ----------------------------------------------------------------------------
// confirma_pais_residencia — grava onde o paciente RESIDE + idioma preferido
// ----------------------------------------------------------------------------
export const confirmaPaisResidencia: ToolDefinition = {
  name: 'confirma_pais_residencia',
  description:
    'Grava país de RESIDÊNCIA + idioma + sistema de medidas preferidos. ⚠️ NÃO assuma idioma nem unidade pelo país (brasileiro nos EUA pode preferir PT/métrico; americano no Brasil pode preferir EN/imperial). ' +
    'USE APENAS depois que: (1) o paciente confirmar onde MORA explicitamente; (2) responder SE o idioma é o esperado ou outro (OBRIGATÓRIO se country != BR); (3) responder SE prefere métrico ou imperial (OBRIGATÓRIO se country é US/GB). ' +
    'NÃO USE com base só no DDI do WhatsApp — esse é palpite, precisa confirmação verbal. Se o paciente pedir TROCAR de idioma no meio da conversa, chame essa tool de novo com o language atualizado pra persistir a preferência (mantenha country).',
  parameters: z.object({
    country: z
      .string()
      .length(2)
      .describe('ISO 3166-1 alpha-2 em UPPERCASE: BR, US, PT, ES, AR, MX, etc.'),
    language: z
      .enum(['pt-BR', 'pt-PT', 'en', 'es', 'fr', 'de', 'it'])
      .optional()
      .describe(
        'Idioma de conversação preferido pelo paciente. ⚠️ Se country != BR, é OBRIGATÓRIO perguntar ao paciente antes de chamar a tool — não derive do país. Se country=BR, pode omitir (default pt-BR).',
      ),
    unit_system: z
      .enum(['metric', 'imperial'])
      .optional()
      .describe(
        'Sistema de medidas preferido. metric=kg/cm (padrão BR/EU), imperial=lb/in (padrão US/UK). ⚠️ Pra country US/GB: pergunte ao paciente. Pra outros: omita (default metric).',
      ),
    timezone: z
      .string()
      .optional()
      .describe(
        'Timezone IANA específico (ex: America/New_York, Europe/Lisbon). Use APENAS se o paciente disse a CIDADE e ela tem timezone diferente do default do país (ex: paciente em Los Angeles → America/Los_Angeles em vez de New_York). Se não tiver certeza, omita — sistema deriva do país.',
      ),
  }),
  execute: async (args, ctx) => {
    const country = args.country.toUpperCase()
    if (!/^[A-Z]{2}$/.test(country)) {
      throw new Error(`Código país inválido: ${country}. Use ISO alpha-2 (BR, US, PT, etc.).`)
    }
    const updates: Record<string, unknown> = {
      country,
      country_confirmed: true,
      updated_at: new Date().toISOString(),
    }
    if (args.language) {
      updates.locale = args.language
    } else if (country === 'BR') {
      updates.locale = 'pt-BR'
    }
    // Sistema de medidas: armazena em metadata pra evitar migration nova.
    // Default metric (BR/EU); imperial só pra US/GB confirmado pelo paciente.
    const unitSystem =
      args.unit_system ?? (['US', 'GB'].includes(country) ? null : 'metric')
    if (unitSystem) {
      updates.metadata = { unit_system: unitSystem }
    }
    // Timezone: explícito do LLM tem prioridade; senão deriva do país.
    // Valida que é IANA válido tentando construir Intl.DateTimeFormat.
    let tz = args.timezone ?? countryToTimezone(country)
    try {
      new Intl.DateTimeFormat('en-US', { timeZone: tz })
    } catch {
      tz = countryToTimezone(country) // fallback se LLM passou tz inválido
    }
    updates.timezone = tz
    const { error } = await (ctx.supabase as unknown as {
      from: (t: string) => {
        update: (u: Record<string, unknown>) => {
          eq: (col: string, val: string) => Promise<{ error: { message: string } | null }>
        }
      }
    })
      .from('users')
      .update(updates)
      .eq('id', ctx.userId)
    if (error) throw new Error(error.message)
    await ctx.supabase.from('product_events').insert({
      user_id: ctx.userId,
      event: 'country.confirmed',
      properties: { country, language: args.language ?? null, wpp: ctx.userWpp },
    })
    return {
      success: true,
      country,
      language: args.language ?? (country === 'BR' ? 'pt-BR' : null),
      unit_system: unitSystem,
      timezone: tz,
      confirmed: true,
      message:
        country === 'BR'
          ? `País gravado como Brasil (pt-BR, métrico, timezone ${tz}).`
          : `País=${country}, idioma=${args.language ?? '?'}, unidades=${unitSystem ?? '?'}, timezone=${tz}. Sigo com cuidado: TACO é brasileira, alimentos locais podem sair imprecisos.`,
    }
  },
}

// ----------------------------------------------------------------------------
// Registry
// ----------------------------------------------------------------------------
export const ALL_TOOLS: ToolDefinition[] = [
  cadastraDadosIniciais,
  defineProtocolo,
  registraRefeicao,
  registraTreino,
  consultaProgresso,
  consultaMetricas,
  atualizaDataUser,
  encerraAtendimento,
  deleteUser,
  pausarAgente,
  retomarAgente,
  confirmaPaisResidencia,
]

export function getToolByName(name: string): ToolDefinition | undefined {
  return ALL_TOOLS.find((t) => t.name === name)
}
