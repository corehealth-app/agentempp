/**
 * Tools que o LLM pode chamar. Cada tool tem:
 *  - schema (JSON Schema para o LLM)
 *  - execute(args, ctx) que opera no Supabase
 *
 * Formato compatível com OpenAI tool calling.
 */
import {
  computeMaintenanceAdjustment,
  computeMetrics,
  computePeriodSummary,
  evaluateGainSafety,
  evaluateGainVelocity,
  type SnapshotForAgg,
} from '@mpp/core'
import type { ServiceClient } from '@mpp/db'
import { z } from 'zod'
import { calcMealMacros } from './meal-pipeline.js'
import { detectAdditionInRecentMessages } from './addition-intent-detector.js'
import { detectPhantomItems } from './phantom-item-detector.js'
import { loadCalcConfig } from './calc-config-loader.js'
import { loadDailyTargets } from './calc-targets.js'
import { countryToTimezone, getLocalDateString, getTzOffset } from './timezone-utils.js'
import { detectCorrectionIntent } from './correction-detector.js'
import { classifyWeightGoal } from './weight-goal-classifier.js'

export interface ToolContext {
  supabase: ServiceClient
  userId: string
  userWpp: string
  /** LLM disponível pra tools que precisam gerar conteúdo (gera_dieta,
   * gera_treino). Injetado pelo pipeline. Opcional pra retrocompatibilidade. */
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  llm?: any
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
    '(3) você apresentou o nível de fome (muita/moderada/pouca → 400/500/600 kcal de déficit; MAIS fome = MENOR déficit, pra proteger a adesão — regra do método) e ele escolheu — APENAS pra protocolo recomposicao. ' +
    'NÃO USE quando o paciente apenas DESEJOU genericamente ("quero emagrecer", "quero ganhar massa") — peça pra ele confirmar a opção. ' +
    'Parâmetros: ' +
    'protocol = "recomposicao" (déficit + preserva massa), "ganho_massa" (superávit), "manutencao" (sem ajuste). ' +
    'deficit_level = kcal/dia de déficit, APENAS pra recomposicao. 400=MUITA fome, 500=moderada, 600=POUCA fome (mais fome → MENOR déficit, pra não quebrar a adesão — regra fixa do método). Omita pra ganho_massa/manutencao. ' +
    'goal_type = "BF" (% gordura alvo) ou "IMC" (IMC alvo). ' +
    'goal_value = número absoluto da meta (ex: BF=15 ou IMC=23). Omita se não chegou nesse nível de detalhe.',
  parameters: z.object({
    protocol: z.enum(['recomposicao', 'ganho_massa', 'manutencao']),
    deficit_level: z
      .union([z.literal(400), z.literal(500), z.literal(600)])
      .optional()
      .describe('Apenas para protocolo recomposicao. 400=MUITA fome, 500=moderada, 600=POUCA fome (mais fome = menor déficit).'),
    goal_type: z.enum(['BF', 'IMC']).optional().describe('"BF"=alvo de % gordura corporal, "IMC"=alvo de IMC'),
    goal_value: z.number().optional().describe('Número alvo (ex: 15 pra BF=15%, 23 pra IMC=23)'),
  }),
  execute: async (args, ctx) => {
    const updatePayload: Record<string, unknown> = {
      current_protocol: args.protocol,
      deficit_level: args.deficit_level ?? null,
      goal_type: args.goal_type ?? null,
      goal_value: args.goal_value ?? null,
      updated_at: new Date().toISOString(),
    }
    // Sub-projeto C (wiring): ao entrar em ganho/manutenção, captura o BASELINE
    // do ciclo (peso/BF/treino de início) pra computar velocidade e tetos de
    // segurança na reavaliação (dia 14). Recomposição NÃO captura — intocado.
    if (args.protocol === 'ganho_massa' || args.protocol === 'manutencao') {
      const { data: cur } = await ctx.supabase
        .from('user_profiles')
        .select('weight_kg, body_fat_percent, training_frequency')
        .eq('user_id', ctx.userId)
        .maybeSingle()
      const c = cur as {
        weight_kg: number | null
        body_fat_percent: number | null
        training_frequency: number | null
      } | null
      updatePayload.cycle_start_weight_kg = c?.weight_kg ?? null
      updatePayload.cycle_start_bf_percent = c?.body_fat_percent ?? null
      updatePayload.cycle_start_training_freq = c?.training_frequency ?? null
      updatePayload.cycle_start_at = new Date().toISOString()
    }
    const { error } = await ctx.supabase
      .from('user_profiles')
      // eslint-disable-next-line @typescript-eslint/no-explicit-any
      .update(updatePayload as any)
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
// define_meta_peso — registra a meta de PESO (kg) + classifica viabilidade
// ----------------------------------------------------------------------------
// Roberto 2026-06-01: paciente pensa em "quero pesar X kg", não em IMC.
// Tool recebe o peso alvo, calcula IMC alvo, classifica (saudável/sobrepeso/
// obesidade/abaixo) e retorna mensagem pro LLM redigir variando. Grava no
// user_profiles via goal_type='peso_kg' + goal_value=X.
export const defineMetaPeso: ToolDefinition = {
  name: 'define_meta_peso',
  description:
    'Salva a meta de PESO em kg que o paciente quer atingir + retorna classificação automática da viabilidade (saudável/abaixo/sobrepeso/obesidade/agressiva). ' +
    '⚠️ USE APENAS depois que: (1) cadastra_dados_iniciais foi chamada com altura E peso atual; (2) o paciente declarou EXPLICITAMENTE o peso alvo ("quero pesar 65kg", "minha meta é 70"). ' +
    'NÃO USE quando o paciente especulou ("acho que 60 seria bom") ou pediu sua opinião antes — pergunte/oriente primeiro. ' +
    'A tool retorna: imc_alvo, faixa saudável da altura dele, semanas estimadas no ritmo seguro, e uma MENSAGEM-BASE conforme a classificação. ' +
    'IMPORTANTE: a mensagem retornada NÃO é literal — varie o jeito de dizer mas MANTENHA os números (peso mínimo/máximo saudável, IMC alvo, semanas). NUNCA invente valor de IMC ou faixa saudável — use os da tool.',
  parameters: z.object({
    target_weight_kg: z
      .number()
      .min(30)
      .max(300)
      .describe('Peso alvo do paciente em quilos (positivo, 30-300). Se ele falou em libras, converta antes: kg = lb × 0.4536.'),
  }),
  execute: async (args, ctx) => {
    // Busca peso atual + altura do profile
    const { data: prof } = await ctx.supabase
      .from('user_profiles')
      .select('weight_kg, height_cm')
      .eq('user_id', ctx.userId)
      .maybeSingle()
    const p = prof as { weight_kg: number | null; height_cm: number | null } | null
    if (!p?.weight_kg || !p?.height_cm) {
      return {
        success: false,
        error:
          'Peso atual ou altura ainda não cadastrados. Pergunte ao paciente e chame cadastra_dados_iniciais primeiro.',
      }
    }

    const assessment = classifyWeightGoal({
      currentWeightKg: Number(p.weight_kg),
      targetWeightKg: args.target_weight_kg,
      heightCm: Number(p.height_cm),
    })

    // Grava no banco
    const { error } = await ctx.supabase
      .from('user_profiles')
      // eslint-disable-next-line @typescript-eslint/no-explicit-any
      .update({
        goal_type: 'peso_kg',
        goal_value: args.target_weight_kg,
        updated_at: new Date().toISOString(),
      } as any)
      .eq('user_id', ctx.userId)
    if (error) throw error

    return {
      success: true,
      target_weight_kg: args.target_weight_kg,
      classification: assessment.classification,
      imc_atual: assessment.imcAtual,
      imc_alvo: assessment.imcAlvo,
      peso_minimo_saudavel_kg: assessment.pesoMinimoSaudavelKg,
      peso_maximo_saudavel_kg: assessment.pesoMaximoSaudavelKg,
      semanas_para_meta_ritmo_seguro: assessment.semanasParaMetaSeguro,
      direction: assessment.direction,
      delta_kg: assessment.deltaKg,
      // ⚠️ Use ESTA mensagem como base — varie o jeito de dizer mas MANTENHA
      // todos os números (IMC, faixa, semanas). NUNCA invente valores.
      message_template: assessment.message,
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
    '➕ ADIÇÃO de item a refeição JÁ REGISTRADA ("adicionei X", "esqueci de mencionar Y", "coloca mais Z"): chame com APENAS os itens NOVOS, sem re-listar a refeição inteira, e SEM replace=true. Exemplo: paciente diz "Adicionei uma medida de geleia de morango ao café" → items=[{food_name:"geleia de morango",quantity_g:20}]. Se você re-listar todos os itens da refeição + os novos sem replace=true, DUPLICA as calorias no tracking. ' +
    '🔄 CORREÇÃO de refeição já registrada: passe `replace=true` + `meal_type` quando o paciente quiser SUBSTITUIR (ex: "corrige o café, era leite com whey, não chocolate", "na verdade comi X em vez de Y"). Com replace=true a tool apaga os logs anteriores do meal_type e insere os novos. Sem replace=true, a tool SOMA — gera dupla contagem. Default replace=false (assume nova refeição ou adição). ' +
    '📌 TABELA DE DECISÃO replace: "adicionei X" = replace=false, apenas item novo. "na verdade era X" ou "corrige" = replace=true, todos os itens corretos. ' +
    '🔁 CORREÇÃO IMPLÍCITA: se paciente acabou de registrar refeição e em <15min envia OS MESMOS alimentos com QUANTIDADES DIFERENTES (mesmo sem dizer "corrige"), trate como correção e use replace=true. Ex: agent registrou "200g arroz + 180g carne" pela foto, paciente responde "100g arroz, 100g carne" → replace=true. (Sistema também detecta automaticamente como defesa em profundidade.) ' + +
    '📏 UNIDADES: você passa SEMPRE quantity_g em GRAMAS (interno do sistema). Quando o paciente disser "2 ovos", converta pra 100g (50g/ovo). "250ml de leite" → 250g (1ml ≈ 1g pra líquidos). A tool retorna `display_qty` + `display_unit` no resultado pra você mostrar ao paciente em unidades naturais (ovos→"2 unidades", leite→"250 ml", pão francês→"1 pão"). USE display_qty/display_unit ao redigir a resposta — NÃO mostre "120g de ovo" pro paciente, mostre "2 ovos". ' +
    '📅 DIA DA REFEIÇÃO: por padrão assume HOJE. Se o paciente disser que a refeição foi de um DIA ANTERIOR ("isso foi ontem", "comi ontem à noite", "esse jantar foi de ontem"), passe `consumed_date` (YYYY-MM-DD) com a data certa — senão a refeição entra no dia errado. ' +
    '🧠 APRENDIZADO DE CORREÇÕES: quando o paciente CORRIGE um alimento que foi mal identificado (ex: a visão disse "batata" e ele diz "não, é mandioca", ou "é cuscuz, não farofa", ou "o pão é francês"), passe o array `corrections` com `{de: "batata", para: "mandioca"}`. Inclui também quando ele diz "apenas N unidades" pra ajustar quantidade junto com identidade. Se ele informar os macros específicos (ex: "minha geleia caseira tem 130 kcal por 100g"), inclua em `corrections` os campos de macro. O sistema aprende E o `corrections` preenchido é a evidência mais forte de que o turno é correção — garante que o replace=true não vai ser derrubado pela defesa anti-erro do LLM.',
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
    corrections: z
      .array(
        z.object({
          de: z
            .string()
            .describe('Nome que foi identificado ERRADO (ex: "batata")'),
          para: z
            .string()
            .describe('Nome correto que o paciente informou (ex: "mandioca")'),
          kcal_per_100g: z
            .number()
            .optional()
            .describe('Macro customizado: kcal/100g, SÓ se o paciente informou explicitamente'),
          protein_g: z.number().optional().describe('Macro customizado: proteína g/100g'),
          carbs_g: z.number().optional().describe('Macro customizado: carboidrato g/100g'),
          fat_g: z.number().optional().describe('Macro customizado: gordura g/100g'),
        }),
      )
      .optional()
      .describe(
        'Correções de IDENTIDADE de alimento que o paciente fez (ex: "batata" → "mandioca"). O sistema aprende e reaplica. NÃO use pra mudança de quantidade.',
      ),
    consumed_date: z
      .string()
      .optional()
      .describe(
        'Data em que a refeição foi CONSUMIDA, formato YYYY-MM-DD. Use APENAS quando a refeição foi de um DIA ANTERIOR (paciente diz "isso foi ontem", "comi ontem à noite", "esse jantar foi de ontem"). Omita pra refeição de HOJE.',
      ),
  }),
  execute: async (args, ctx) => {
    const tz = ctx.userTimezone ?? 'America/Sao_Paulo'
    const today = getLocalDateString(tz)
    // Fix B (2026-05-25): a refeição pode ser de um DIA ANTERIOR ("isso foi de
    // ontem" — caso real do Paulo). Antes a tool SEMPRE usava o dia da GRAVAÇÃO
    // e nunca gravava consumed_at (caía no DEFAULT now()), então "registra o
    // jantar de ontem" era IMPOSSÍVEL e a única saída era backfill manual (fonte
    // nº1 de inconsistência). Agora respeita `consumed_date` em tudo: snapshot do
    // dia certo + consumed_at explícito.
    const effectiveDate =
      args.consumed_date && /^\d{4}-\d{2}-\d{2}$/.test(args.consumed_date)
        ? args.consumed_date
        : today
    // consumed_at: hoje → agora; dia passado → meio-dia LOCAL daquele dia (cai
    // na data certa em qualquer fuso, e o recompute por consumed_at do closer/
    // auditoria fica fiel).
    const consumedAtIso =
      effectiveDate === today
        ? new Date().toISOString()
        : `${effectiveDate}T12:00:00${getTzOffset(tz)}`

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
    // APRENDIZADO DE CORREÇÕES DE ALIMENTO (Roberto 2026-05-14)
    // ========================================================================
    // Quando o paciente corrige a IDENTIDADE de um alimento ("batata" → "mandioca"),
    // grava em user_food_corrections pra reaplicar nas próximas. Design:
    //  - 1ª correção: status='learning', confirmed_count=1 (aplica c/ confirmação)
    //  - 2ª confirmação igual: status='active', confirmed_count=2 (aplica silencioso)
    //  - correção CONTRA uma entrada (de=corrected_to anterior, ou para≠ anterior):
    //    contradicted_count++, e se contradições >= confirmações → status='retired'
    if (args.corrections && args.corrections.length > 0) {
      // ServiceClient ainda não tem os tipos gerados de user_food_corrections —
      // cast solto (mesmo padrão de lookupUserHistory). Tabela criada em
      // migration 20260514120000.
      // eslint-disable-next-line @typescript-eslint/no-explicit-any
      const supaCorr = ctx.supabase as any
      const normalizeName = (s: string) =>
        s.toLowerCase().normalize('NFD').replace(/[̀-ͯ]/g, '').trim()
      for (const corr of args.corrections) {
        const said = normalizeName(corr.de)
        const correctedTo = normalizeName(corr.para)
        if (!said || !correctedTo || said === correctedTo) continue

        const { data: existingRows } = await supaCorr
          .from('user_food_corrections')
          .select('id, corrected_to, confirmed_count, contradicted_count, status')
          .eq('user_id', ctx.userId)
          .eq('said_name', said)
          .limit(1)
        const existing = (existingRows ?? [])[0] as
          | {
              id: string
              corrected_to: string
              confirmed_count: number
              contradicted_count: number
              status: string
            }
          | undefined

        const customMacros = {
          custom_kcal_per_100g: corr.kcal_per_100g ?? null,
          custom_protein_g: corr.protein_g ?? null,
          custom_carbs_g: corr.carbs_g ?? null,
          custom_fat_g: corr.fat_g ?? null,
        }

        if (!existing) {
          // 1ª correção desse nome → entra como learning
          await supaCorr.from('user_food_corrections').insert({
            user_id: ctx.userId,
            said_name: said,
            corrected_to: correctedTo,
            ...customMacros,
            confirmed_count: 1,
            status: 'learning',
          })
          await ctx.supabase.from('product_events').insert({
            user_id: ctx.userId,
            event: 'food_correction.learned',
            properties: { said_name: said, corrected_to: correctedTo, has_custom_macros: corr.kcal_per_100g != null },
          })
        } else if (normalizeName(existing.corrected_to) === correctedTo) {
          // Mesma correção de novo → confirma. 2ª confirmação ativa.
          const newCount = existing.confirmed_count + 1
          await supaCorr
            .from('user_food_corrections')
            .update({
              confirmed_count: newCount,
              status: newCount >= 2 ? 'active' : existing.status,
              last_seen: new Date().toISOString(),
              ...(corr.kcal_per_100g != null ? customMacros : {}),
            })
            .eq('id', existing.id)
          await ctx.supabase.from('product_events').insert({
            user_id: ctx.userId,
            event: 'food_correction.confirmed',
            properties: { said_name: said, corrected_to: correctedTo, confirmed_count: newCount, now_active: newCount >= 2 },
          })
        } else {
          // Correção CONTRADIZ a entrada (mesmo said_name, corrected_to diferente).
          // Conta contradição; se contradições >= confirmações, aposenta a entrada
          // antiga e recomeça com a nova correção.
          const newContradicted = existing.contradicted_count + 1
          const retire = newContradicted >= existing.confirmed_count
          await supaCorr
            .from('user_food_corrections')
            .update({
              corrected_to: retire ? correctedTo : existing.corrected_to,
              contradicted_count: retire ? 0 : newContradicted,
              confirmed_count: retire ? 1 : existing.confirmed_count,
              status: retire ? 'learning' : existing.status,
              last_seen: new Date().toISOString(),
              ...(retire ? customMacros : {}),
            })
            .eq('id', existing.id)
          await ctx.supabase.from('product_events').insert({
            user_id: ctx.userId,
            event: 'food_correction.contradicted',
            properties: {
              said_name: said,
              old_corrected_to: existing.corrected_to,
              new_corrected_to: correctedTo,
              retired_and_relearned: retire,
            },
          })
        }
      }
    }

    // ========================================================================
    // GUARDA-CHUVA DETERMINÍSTICO (defesa em profundidade contra erro do LLM)
    // ========================================================================

    // (-1) PHANTOM ITEMS (Amanda 2026-06-11): se o LLM propôs itens que NÃO
    // foram mencionados pelo paciente nem aparecem em propostas/cards recentes
    // do agente, E o paciente acabou de NEGAR algo ("não", "esquece"), é
    // alucinação clara (cross-day contamination, contexto sujo). Bloquear o
    // tool call e devolver erro pro LLM corrigir.
    if (args.items && args.items.length > 0 && ctx.recentUserMessages) {
      const phantomCheck = detectPhantomItems({
        proposedItems: args.items.map((i: { food_name: string }) => ({
          food_name: i.food_name,
        })),
        recentUserMessages: ctx.recentUserMessages,
        // recentAgentTexts não está no ctx hoje; passamos vazio (conservador)
        recentAgentTexts: [],
      })
      if (phantomCheck.shouldBlock) {
        await ctx.supabase.from('product_events').insert({
          user_id: ctx.userId,
          event: 'tool.phantom_items_blocked',
          properties: {
            meal_type: args.meal_type,
            phantom_items: phantomCheck.phantomItems,
            denial_trigger: phantomCheck.denialTrigger,
            recent_user_msgs_count: ctx.recentUserMessages.length,
          },
        })
        return {
          success: false,
          error:
            'BLOQUEADO: você está tentando registrar itens (' +
            phantomCheck.phantomItems.join(', ') +
            ') que o paciente NÃO MENCIONOU. O paciente acabou de NEGAR algo ("' +
            (phantomCheck.denialTrigger ?? '') +
            '"). NÃO ALUCINE itens. Releia o que o paciente disse e proponha SÓ o que ele realmente falou OU itens visíveis na foto identificados via vision. Se for café da manhã e ele só descreveu café, registre só café.',
        }
      }
    }


    // (0) EVIDÊNCIA OBJETIVA DE CORREÇÃO — sobreposição de food_names em janela curta.
    //
    // Casos reais que cobrimos:
    //  - Esposa do Roberto (2026-05-12): foto detectou 200g arroz + 180g carne
    //    (errado). Ela respondeu "100g arroz, 100g carne" SEM dizer "corrige".
    //    LLM mandou replace=false → soma. Detecção implícita aplica replace=true.
    //  - Sogro do Roberto Paulo (2026-05-13): foto identificou "bebida láctea com
    //    espuma" zerada (composite_rejected). Paulo respondeu "Leite semi
    //    desnatado com café". LLM mandou replace=true CORRETAMENTE, mas o blocker
    //    (que pedia palavra-chave "corrige/errei") fez downgrade pra false → soma.
    //
    // SOLUÇÃO UNIFICADA: calcular evidência objetiva SEMPRE e usar em ambos os
    // caminhos. Evidência objetiva = >=50% overlap de food_name em <15min de
    // QUALQUER meal_type recente. Verbal = palavra-chave nas msgs recentes.
    // Qualquer uma serve pra ratificar replace=true.
    //
    // CROSS-MEAL-TYPE (Paulo 2026-05-13 18:43-19:15): foto chegou 15:43 BRT e
    // foi registrada como 'lanche' (chute por hora). Paulo corrigiu e LLM
    // mandou meal_type='almoco'. Antes: detector filtrava por meal_type igual,
    // não via os logs anteriores em 'lanche' → soma. Agora: olha qualquer
    // meal_type recente e, se encontrar overlap forte, marca crossMealTypeFrom
    // pra apagar também daquele meal_type no replace.
    let objectiveCorrectionEvidence = false
    let overlapMeta: { ratio: number; recent: string[]; new: string[]; from_meal_type: string | null } | null = null
    let crossMealTypeFrom: string | null = null
    if (args.meal_type && args.items.length > 0) {
      // Janela 30min (era 15min). Caso Luciana 2026-05-15: corrigiu "não tem bacon"
      // 17min após a foto → fora dos 15min → detector pulou → blocker derrubou
      // replace → consumido duplicou. 30min cobre correção mais reflexiva.
      const thirtyMinAgo = new Date(Date.now() - 30 * 60 * 1000).toISOString()
      const { data: recentLogs } = await ctx.supabase
        .from('meal_logs')
        .select('food_name, quantity_g, meal_type')
        .eq('user_id', ctx.userId)
        .gte('created_at', thirtyMinAgo)
        .limit(30)
      const recent = (recentLogs ?? []) as Array<{
        food_name: string
        quantity_g: number
        meal_type: string
      }>
      if (recent.length > 0) {
        const normalize = (s: string) =>
          s.toLowerCase().normalize('NFD').replace(/[̀-ͯ]/g, '').trim()
        const newNames: string[] = args.items.map((i: { food_name: string }) =>
          normalize(i.food_name),
        )
        // Agrupa logs por meal_type e calcula overlap pra cada grupo separado.
        // Se overlap >= 50% em algum grupo, esse é o "target da correção".
        // Prioriza o MESMO meal_type (caso simples) sobre cross-meal-type.
        const groups = new Map<string, string[]>()
        for (const r of recent) {
          const arr = groups.get(r.meal_type) ?? []
          arr.push(normalize(r.food_name))
          groups.set(r.meal_type, arr)
        }
        let bestRatio = 0
        let bestMealType: string | null = null
        let bestNames: string[] = []
        // Tenta primeiro o mesmo meal_type
        const sameTypeNames = groups.get(args.meal_type)
        if (sameTypeNames && sameTypeNames.length > 0) {
          const overlap = newNames.filter((nn) =>
            sameTypeNames.some((rn) => rn.includes(nn) || nn.includes(rn)),
          ).length
          const ratio = overlap / Math.max(newNames.length, sameTypeNames.length)
          if (ratio > bestRatio) {
            bestRatio = ratio
            bestMealType = args.meal_type
            bestNames = sameTypeNames
          }
        }
        // Depois testa outros meal_types — só aceita se overlap >= 50%.
        for (const [mt, names] of groups.entries()) {
          if (mt === args.meal_type) continue
          const overlap = newNames.filter((nn) =>
            names.some((rn) => rn.includes(nn) || nn.includes(rn)),
          ).length
          const ratio = overlap / Math.max(newNames.length, names.length)
          if (ratio >= 0.5 && ratio > bestRatio) {
            bestRatio = ratio
            bestMealType = mt
            bestNames = names
          }
        }
        overlapMeta = {
          ratio: Math.round(bestRatio * 100) / 100,
          recent: bestNames,
          new: newNames,
          from_meal_type: bestMealType,
        }
        if (bestRatio >= 0.5) {
          objectiveCorrectionEvidence = true
          if (bestMealType && bestMealType !== args.meal_type) {
            crossMealTypeFrom = bestMealType
          }
        }
      }
    }

    // EVIDÊNCIA EXPLÍCITA: se o LLM preencheu `corrections[]` na chamada, é
    // declaração ATIVA dele que isso é correção. Mais forte que overlap.
    // Caso real (Amanda 2026-05-15): "É cuscuz, não farofa" + "Apenas 1 unidade"
    // — corrections[] populado, mas overlap só 25-40% (corrige item-a-item de
    // uma refeição de 3 itens), e detector verbal não pegava as frases naturais.
    // Resultado: blocker derrubava replace, refeição somava a cada correção.
    if (args.corrections && args.corrections.length > 0) {
      objectiveCorrectionEvidence = true
    }

    // Caso A: LLM mandou replace=false mas há evidência objetiva → auto-aplica
    // EXCEÇÃO (Luciana 2026-06-10): se paciente disse "segunda fatia", "mais um",
    // "outro pedaço" etc nas últimas msgs, é ADIÇÃO e NÃO correção. Não pode
    // virar replace=true ou o item anterior será apagado. Detector roda só
    // quando há overlap forte (objectiveCorrectionEvidence=true) — overlap por
    // sobreposição de food_name SEM intent verbal de correção pode ser
    // legitimamente o mesmo alimento de novo (2ª porção). Intent verbal de
    // ADIÇÃO é o sinal mais forte que isso é adição, não correção.
    let implicitReplaceDetected = false
    if (args.replace !== true && objectiveCorrectionEvidence) {
      const additionTrigger = detectAdditionInRecentMessages(
        (ctx.recentUserMessages ?? []).map((c) => ({ role: 'user' as const, content: c })),
        4,
      )
      if (additionTrigger) {
        await ctx.supabase.from('product_events').insert({
          user_id: ctx.userId,
          event: 'tool.replace_blocked_addition_intent',
          properties: {
            meal_type: args.meal_type,
            overlap_ratio: overlapMeta?.ratio,
            recent_names: overlapMeta?.recent,
            new_names: overlapMeta?.new,
            addition_trigger: additionTrigger,
          },
        })
      } else {
        args.replace = true
        implicitReplaceDetected = true
        await ctx.supabase.from('product_events').insert({
          user_id: ctx.userId,
          event: 'tool.replace_implicit_detected',
          properties: {
            meal_type: args.meal_type,
            overlap_ratio: overlapMeta?.ratio,
            recent_names: overlapMeta?.recent,
            new_names: overlapMeta?.new,
          },
        })
      }
    }

    // (1) AUTO-CORRIGE meal_type pela hora local do paciente.
    // CONSERVADOR: só sobrescreve quando há discrepância GRAVE (≥3h da janela)
    // OU quando paciente NÃO mencionou meal_type explícito na msg recente.
    //
    // Antes (bug): qualquer mismatch hora→meal sobrescrevia, ignorando o que
    // paciente falou. Caso real: às 18:28 BRT (boundary) Luan disse "café da
    // tarde" e sistema converteu pra jantar. Usuário ficou confuso.
    //
    // Bug original que essa defesa cobria: foto sem texto às 8h → LLM chutava
    // jantar (achou que era correção). Esse caso continua coberto: 8h vs jantar
    // (≥3h) → corrige.
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
      // Detecta se paciente mencionou meal_type explícito nas últimas msgs.
      // Se sim, NÃO auto-corrige (paciente sabe o que fala).
      const recentMsgs = (ctx.recentUserMessages ?? []).join(' ').toLowerCase()
      const userMentionedMeal =
        /\bcaf[eé](?:\s+da\s+manh)?\b|\b(?:cafe|breakfast)\b|\balmo[çc]o\b|\blunch\b|\blanche\b|\bsnack\b|\b(?:café\s+da\s+tarde|merenda)\b|\bjantar\b|\bdinner\b|\bceia\b|\bsupper\b/i.test(
          recentMsgs,
        )

      // Distância em janelas (cafe=0, almoco=1, lanche=2, jantar=3, ceia=4)
      const order = ['cafe', 'almoco', 'lanche', 'jantar']
      const distance = Math.abs(
        (order.indexOf(args.meal_type) >= 0 ? order.indexOf(args.meal_type) : 0) -
          (order.indexOf(expected) >= 0 ? order.indexOf(expected) : 0),
      )

      // Bloqueia autocorrect quando replace=true — autocorrect cross-meal-type
      // + replace=true é catastrófico: LLM manda {meal_type:'lanche', replace:true}
      // pra corrigir lanche, autocorrect vira pra 'cafe', replace=true APAGA todos
      // os meal_logs do CAFÉ do dia (sem relação com a intenção do LLM). Caso
      // Amanda 2026-05-30: empanada do lanche da manhã sumiu por isso. Em replace
      // sempre confia no LLM; mismatch fica só como log.
      const shouldAutoCorrect =
        args.meal_type !== expected &&
        !userMentionedMeal &&
        distance >= 2 &&
        args.replace !== true

      if (args.meal_type !== expected) {
        await ctx.supabase.from('product_events').insert({
          user_id: ctx.userId,
          event: shouldAutoCorrect
            ? 'tool.meal_type_autocorrected'
            : 'tool.meal_type_mismatch_kept',
          properties: {
            claimed: args.meal_type,
            expected_by_hour: expected,
            local_hour: localHour,
            timezone: tz,
            distance,
            user_mentioned_meal: userMentionedMeal,
            replace: args.replace ?? false,
          },
        })
        if (shouldAutoCorrect) {
          // Discrepância grave + paciente sem nomear meal_type → sobrescreve.
          args.meal_type = expected
        }
        // Senão: respeita o que LLM passou (paciente nomeou OU diferença pequena).
      }
    }

    // (2) BLOQUEIA replace=true sem evidência de correção (verbal OU objetiva).
    // Destrutivo: replace=true DELETA refeições do dia+meal_type.
    //
    // Antes (bug Paulo 2026-05-13): exigia palavra-chave verbal. LLM mandou
    // replace=true corretamente porque Paulo re-listou os mesmos itens, mas msg
    // dele ("Leite semi desnatado com café") não tinha "corrige/errei" → blocker
    // downgrade pra false → SOMOU em vez de substituir.
    //
    // Agora: aceita verbal (correctionWord) OU objetiva (overlap >=50% em <15min).
    // Só downgrade quando NENHUMA evidência existe — aí é provável bug do LLM.
    if (args.replace === true && !implicitReplaceDetected) {
      const recentMsgs = ctx.recentUserMessages ?? []
      const correctionWord = detectCorrectionIntent(recentMsgs)
      if (!correctionWord && !objectiveCorrectionEvidence) {
        await ctx.supabase.from('product_events').insert({
          user_id: ctx.userId,
          event: 'tool.replace_blocked_no_correction',
          properties: {
            meal_type: mealTypeOriginal,
            corrected_meal_type: args.meal_type,
            recent_msgs_count: recentMsgs.length,
            recent_msgs_preview: recentMsgs.slice(-2).map((m) => m.slice(0, 80)),
            overlap_ratio: overlapMeta?.ratio ?? 0,
          },
        })
        // Downgrade silencioso — segue como INSERT normal.
        args.replace = false
      } else if (!correctionWord && objectiveCorrectionEvidence) {
        // LLM acertou replace=true sem palavra-chave verbal — ratificado por overlap.
        await ctx.supabase.from('product_events').insert({
          user_id: ctx.userId,
          event: 'tool.replace_ratified_by_overlap',
          properties: {
            meal_type: args.meal_type,
            overlap_ratio: overlapMeta?.ratio,
          },
        })
      }
    }
    // ========================================================================

    // CORREÇÃO: paciente quer substituir refeição já registrada hoje.
    // Deleta meal_logs do dia+meal_type e SUBTRAI seus macros do snapshot
    // antes de inserir os novos. Sem isso, snapshot_add_meal duplica.
    let replacedSummary: { count: number; kcal_removed: number; cross_from?: string } | null = null
    if (args.replace === true && args.meal_type) {
      // Lista de meal_types pra apagar: SEMPRE o atual + cross se detectado.
      // Cross-meal-type: paciente corrigiu trocando o tipo (ex: lanche → almoco).
      const mealTypesToDelete = crossMealTypeFrom
        ? [args.meal_type, crossMealTypeFrom]
        : [args.meal_type]
      // BUG HISTÓRICO (Roberto 09/05): query usava `created_at >= '${today}T00:00:00'`
      // sem timezone — Postgres interpretava como UTC, mas `today` era data LOCAL
      // (EDT). Pra paciente em UTC-4 entre 20h-24h local (= 00h-04h UTC do dia
      // seguinte), os meal_logs criados nesse intervalo tinham created_at do
      // "dia seguinte UTC" e ficavam fora do range. Replace nunca encontrava
      // nada → log "tool.replace_without_target" → 4x duplicate insert.
      //
      // Fix: filtra pelo SNAPSHOT do dia local (snapshot_id linkado à data local
      // via snapshot_add_meal), em vez de range de created_at em UTC.
      const { data: snapToday } = await ctx.supabase
        .from('daily_snapshots')
        .select('id')
        .eq('user_id', ctx.userId)
        .eq('date', effectiveDate)
        .maybeSingle()
      const snapId = (snapToday as { id: string } | null)?.id ?? null
      type RemoveRow = {
        id: string
        kcal: number | null
        protein_g: number | null
        carbs_g: number | null
        fat_g: number | null
      }
      let allRemoved: RemoveRow[] = []
      if (snapId) {
        for (const mt of mealTypesToDelete) {
          const { data: rows } = await ctx.supabase
            .from('meal_logs')
            .select('id, kcal, protein_g, carbs_g, fat_g')
            .eq('user_id', ctx.userId)
            .eq('meal_type', mt)
            .eq('snapshot_id', snapId)
          if (rows) allRemoved = allRemoved.concat(rows as RemoveRow[])
        }
      }
      if (allRemoved.length > 0) {
        const removed = allRemoved.reduce(
          (acc, l) => ({
            kcal: acc.kcal + Number(l.kcal ?? 0),
            prot: acc.prot + Number(l.protein_g ?? 0),
            carb: acc.carb + Number(l.carbs_g ?? 0),
            fat: acc.fat + Number(l.fat_g ?? 0),
          }),
          { kcal: 0, prot: 0, carb: 0, fat: 0 },
        )
        // Deleta os logs antigos de TODOS os meal_types alvo (atual + cross)
        for (const mt of mealTypesToDelete) {
          await ctx.supabase
            .from('meal_logs')
            .delete()
            .eq('user_id', ctx.userId)
            .eq('meal_type', mt)
            .eq('snapshot_id', snapId!)
        }
        if (crossMealTypeFrom) {
          await ctx.supabase.from('product_events').insert({
            user_id: ctx.userId,
            event: 'tool.replace_cross_meal_type',
            properties: {
              from_meal_type: crossMealTypeFrom,
              to_meal_type: args.meal_type,
              removed_count: allRemoved.length,
              removed_kcal: Math.round(removed.kcal),
            },
          })
        }
        // Subtrai do snapshot via RPC (passa valores negativos)
        await (ctx.supabase as unknown as {
          rpc: (n: string, p: Record<string, unknown>) => Promise<{ error: unknown }>
        }).rpc('snapshot_add_meal', {
          p_user_id: ctx.userId,
          p_date: effectiveDate,
          p_kcal: -removed.kcal,
          p_protein: -removed.prot,
          p_carbs: -removed.carb,
          p_fat: -removed.fat,
          p_calories_target: null,
          p_protein_target: null,
        })
        replacedSummary = {
          count: allRemoved.length,
          kcal_removed: Math.round(removed.kcal),
          ...(crossMealTypeFrom ? { cross_from: crossMealTypeFrom } : {}),
        }
      } else {
        // replace=true mas nada pra substituir hoje desse meal_type.
        // É indício de bug do LLM (achou que era correção quando não era).
        // Loga e segue com insert normal — não bloqueia paciente.
        await ctx.supabase.from('product_events').insert({
          user_id: ctx.userId,
          event: 'tool.replace_without_target',
          properties: {
            meal_type: args.meal_type,
            date: effectiveDate,
            note: 'replace=true mas nenhum meal_log existente desse tipo hoje',
          },
        })
      }
    }

    // ========================================================================
    // DEDUP INTRA-ARRAY (Amanda 2026-05-15) — Bug A
    // ========================================================================
    // Quando LLM envia items=[{burrito,300},{burrito,300},{coca,250},{coca,250}]
    // (replicando a lista), cada item vira meal_log separado e calorias dobram.
    // Caso real Amanda: "Burrito de filé\n1 coca 250ml" virou 1.110 kcal em vez
    // de 555. Luciana 2026-05-11 teve cenoura/tomate/alface/arroz QUADRUPLICADOS
    // num único almoço (2.199 kcal no almoço).
    //
    // Defesa: agrega itens com (food_name normalizado + sem qty) iguais somando
    // quantity_g. Se quantity_g idêntica → provável duplicação acidental do LLM,
    // merge SOMA. Se quantidades diferentes → também SOMA (paciente comeu 2x do
    // mesmo item em quantidades distintas — semanticamente correto).
    {
      const normName = (s: string) =>
        s.toLowerCase().normalize('NFD').replace(/[̀-ͯ]/g, '').replace(/\s+/g, ' ').trim()
      const mergedMap = new Map<string, { food_name: string; quantity_g: number; original_count: number }>()
      for (const it of args.items) {
        const key = normName(it.food_name)
        const existing = mergedMap.get(key)
        if (existing) {
          existing.quantity_g += it.quantity_g
          existing.original_count += 1
        } else {
          mergedMap.set(key, { food_name: it.food_name, quantity_g: it.quantity_g, original_count: 1 })
        }
      }
      const dupCount = Array.from(mergedMap.values()).filter((m) => m.original_count > 1).length
      if (dupCount > 0) {
        const merged = Array.from(mergedMap.values())
        await ctx.supabase.from('product_events').insert({
          user_id: ctx.userId,
          event: 'tool.items_deduped',
          properties: {
            meal_type: args.meal_type ?? null,
            provider_message_id: ctx.providerMessageId ?? null,
            original_count: args.items.length,
            merged_count: merged.length,
            duplicates: merged
              .filter((m) => m.original_count > 1)
              .map((m) => ({ food_name: m.food_name, repeated: m.original_count, summed_g: m.quantity_g })),
          },
        })
        args.items = merged.map(({ food_name, quantity_g }) => ({ food_name, quantity_g }))
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
          warnings: calc.user_warnings,
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

    // Loga aplicação do mapa de correções (Roberto 2026-05-14) — observabilidade
    // pra ver no /audit se o mapa está ajudando ou poluindo.
    const correctionApplied = calc.audit_warnings.filter((w) =>
      /correção aprendida do paciente/i.test(w),
    )
    if (correctionApplied.length > 0) {
      await ctx.supabase.from('product_events').insert({
        user_id: ctx.userId,
        event: 'food_correction.applied',
        properties: {
          provider_message_id: ctx.providerMessageId ?? null,
          applied: correctionApplied,
          count: correctionApplied.length,
        },
      })
    }

    // Garante targets calculados (calories_target + protein_target).
    // Sem isso, daily_balance fica positivo sempre e bloco 7700 nunca cresce.
    const config = await loadCalcConfig(ctx.supabase)
    const targets = await loadDailyTargets(ctx.supabase, ctx.userId, config)

    // ========================================================================
    // DEDUP CONTRA O DIA (Paulo 2026-05-24) — Bug A, 4ª camada
    // ========================================================================
    // Caso real: Paulo registrou o café (whey 114g + leite 70g) às 08:44.
    // Às 12:28 mandou FOTO do almoço; ao processar, o LLM RE-INSERIU whey+leite
    // em meal_type='cafe' (linhas duplicadas) → café contado em dobro (+184 kcal).
    //
    // As 3 dedups anteriores não pegam esse caso:
    //  - idempotência por raw_provider_message_id → só retry da MESMA mensagem.
    //  - janela de correção (30min) → café 08:44 vs foto 12:28 = 3h44, fora.
    //  - dedup intra-array → só dentro da MESMA chamada.
    //
    // 4ª camada (determinística): quando NÃO é correção (replace !== true) e há
    // meal_type, busca os meal_logs JÁ registrados hoje no mesmo
    // (user_id, snapshot_id, meal_type) e descarta dos itens a inserir aqueles
    // cujo NOME normalizado + QUANTIDADE arredondada já existem. Chave é
    // nome+quantidade (NÃO só nome) pra não bloquear quem come o mesmo item em
    // quantidade diferente no mesmo tipo de refeição.
    //
    // Importante: filtra ANTES do snapshot_add_meal, então o snapshot recebe só
    // os itens que sobraram — senão o snapshot inflaria mesmo sem o meal_log
    // duplicado.
    let itemsToInsert = calc.items
    let totalsToAdd = calc.totals
    if (args.replace !== true && args.meal_type && calc.items.length > 0) {
      // Resolve o snapshot do dia local (mesma estratégia do path de replace:
      // por (user_id, date) em vez de range de created_at em UTC).
      const { data: snapToday } = await ctx.supabase
        .from('daily_snapshots')
        .select('id')
        .eq('user_id', ctx.userId)
        .eq('date', effectiveDate)
        .maybeSingle()
      const existingSnapId = (snapToday as { id: string } | null)?.id ?? null
      if (existingSnapId) {
        const { data: sameMealRows } = await ctx.supabase
          .from('meal_logs')
          .select('food_name, quantity_g')
          .eq('user_id', ctx.userId)
          .eq('snapshot_id', existingSnapId)
          .eq('meal_type', args.meal_type)
        const existing = (sameMealRows ?? []) as Array<{
          food_name: string
          quantity_g: number
        }>
        if (existing.length > 0) {
          const normName = (s: string) =>
            s.toLowerCase().normalize('NFD').replace(/[̀-ͯ]/g, '').replace(/\s+/g, ' ').trim()
          // Chave = nome normalizado + quantidade arredondada (g inteiro).
          const dedupKey = (food: string, qty: number) =>
            `${normName(food)}|${Math.round(qty)}`
          const existingKeys = new Set(existing.map((r) => dedupKey(r.food_name, r.quantity_g)))
          const skipped: Array<{ food_name: string; quantity_g: number }> = []
          const survivors = calc.items.filter((it) => {
            if (existingKeys.has(dedupKey(it.food_name, it.quantity_g))) {
              skipped.push({ food_name: it.food_name, quantity_g: it.quantity_g })
              return false
            }
            return true
          })
          if (skipped.length > 0) {
            await ctx.supabase.from('product_events').insert({
              user_id: ctx.userId,
              event: 'tool.meal_item_redup_skipped',
              properties: {
                meal_type: args.meal_type,
                provider_message_id: ctx.providerMessageId ?? null,
                date: effectiveDate,
                skipped_count: skipped.length,
                skipped,
                note: 'item idêntico (nome+qtd) já registrado hoje nesse meal_type por msg anterior — não reinsere (caso Paulo 2026-05-24)',
              },
            })
            itemsToInsert = survivors
            // Recalcula os totais a somar no snapshot SÓ com os sobreviventes.
            totalsToAdd = survivors.reduce(
              (acc, it) => ({
                kcal: acc.kcal + Number(it.kcal ?? 0),
                protein_g: acc.protein_g + Number(it.protein_g ?? 0),
                carbs_g: acc.carbs_g + Number(it.carbs_g ?? 0),
                fat_g: acc.fat_g + Number(it.fat_g ?? 0),
                fiber_g: acc.fiber_g + Number((it as { fiber_g?: number }).fiber_g ?? 0),
              }),
              { kcal: 0, protein_g: 0, carbs_g: 0, fat_g: 0, fiber_g: 0 },
            )
          }
        }
      }
    }

    // ── PRÉ-FILTRAGEM por (pmid, food_name) — Amanda 2026-05-30 13:32 ──
    // Bug observado em prod: LLM no retry mandou registra_refeicao com 2 itens
    // {empanada + pastel} usando mesmo pmid; pastel já tinha sido inserido na
    // tentativa anterior → UNIQUE (user_id, raw_provider_message_id, food_name)
    // bloqueou. Sem filtragem prévia, o snapshot_add_meal abaixo já incrementa
    // por TODOS os itens — então o pastel dup adicionava 306 kcal duplicada ao
    // snapshot mesmo o meal_log sendo rejeitado. Drift: snap=1071, sum=764.
    // Fix: query (pmid, food_name) existentes, filtra os duplicados de
    // itemsToInsert E subtrai do totalsToAdd ANTES do snapshot_add_meal.
    if (ctx.providerMessageId && itemsToInsert.length > 0) {
      const { data: existingForPmid } = await ctx.supabase
        .from('meal_logs')
        .select('food_name')
        .eq('user_id', ctx.userId)
        .eq('raw_provider_message_id', ctx.providerMessageId)
      const existingNames = new Set(
        ((existingForPmid ?? []) as Array<{ food_name: string }>).map((r) =>
          r.food_name.toLowerCase().trim(),
        ),
      )
      if (existingNames.size > 0) {
        const dupRemoved: typeof itemsToInsert = []
        itemsToInsert = itemsToInsert.filter((it) => {
          if (existingNames.has(it.food_name.toLowerCase().trim())) {
            dupRemoved.push(it)
            return false
          }
          return true
        })
        if (dupRemoved.length > 0) {
          // Recalcula totalsToAdd só com sobreviventes pra snapshot_add_meal
          // não receber kcal de itens que NÃO serão inseridos.
          totalsToAdd = itemsToInsert.reduce(
            (acc, it) => ({
              kcal: acc.kcal + Number(it.kcal ?? 0),
              protein_g: acc.protein_g + Number(it.protein_g ?? 0),
              carbs_g: acc.carbs_g + Number(it.carbs_g ?? 0),
              fat_g: acc.fat_g + Number(it.fat_g ?? 0),
              fiber_g: acc.fiber_g + Number((it as { fiber_g?: number }).fiber_g ?? 0),
            }),
            { kcal: 0, protein_g: 0, carbs_g: 0, fat_g: 0, fiber_g: 0 },
          )
          await ctx.supabase.from('product_events').insert({
            user_id: ctx.userId,
            event: 'tool.meal_logs_skipped_dup_pmid',
            properties: {
              provider_message_id: ctx.providerMessageId,
              meal_type: args.meal_type ?? null,
              skipped_count: dupRemoved.length,
              skipped: dupRemoved.map((i) => ({ food_name: i.food_name, kcal: i.kcal })),
              note: 'item já existia em meal_logs com mesmo (pmid, food_name) — pulado e não somado ao snapshot',
            },
          })
        }
      }
    }

    // Se TODOS os itens eram duplicatas do dia, não toca no snapshot nem insere
    // nada — responde coerentemente (sem card fantasma de refeição "nova").
    if (itemsToInsert.length === 0) {
      return {
        success: true,
        already_logged: true,
        meal: { items: [], totals: { kcal: 0, protein_g: 0, carbs_g: 0, fat_g: 0, fiber_g: 0 } },
        warnings: calc.user_warnings,
        replaced: replacedSummary,
      }
    }

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
      p_date: effectiveDate,
      p_kcal: totalsToAdd.kcal,
      p_protein: totalsToAdd.protein_g,
      p_carbs: totalsToAdd.carbs_g,
      p_fat: totalsToAdd.fat_g,
      p_calories_target: targets.calories_target,
      p_protein_target: targets.protein_target,
    })
    if (updErr) throw new Error(updErr.message ?? 'snapshot_add_meal failed')
    if (!updated) throw new Error('snapshot_add_meal returned null')
    const snapshotId = updated.id

    // Insere cada item em meal_logs (apenas os sobreviventes da dedup).
    // TODO: a UNIQUE composite (user_id, raw_provider_message_id, food_name)
    // garante idempotência só por mensagem; o ideal seria um .upsert() com
    // ON CONFLICT DO NOTHING, mas o supabase-js exige declarar onConflict com
    // o nome exato da constraint — fica como follow-up pra não arriscar trocar
    // semântica do insert puro sem validar a constraint em prod.
    // Bug Roberto 2026-05-29 21:37: handler do tap rodou esta tool, snapshot foi
    // criado, mas os 5 inserts deste loop falharam silenciosamente — a tool
    // retornou `success:true` e o paciente recebeu "Café registrado ✅" sem
    // nada gravado. Causa: ausência de error check no await do supabase-js
    // (erro retorna em `{ data, error }`, não throw). Agora: throw em qualquer
    // erro de insert + verificação pós-loop por count, garantindo que o
    // success não mente. Inngest faz retry da step.run em throw — visibilidade.
    const insertErrors: string[] = []
    for (const item of itemsToInsert) {
      const { error: insErr } = await ctx.supabase.from('meal_logs').insert({
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
        consumed_at: consumedAtIso,
        raw_provider_message_id: ctx.providerMessageId ?? null,
      })
      if (insErr) {
        insertErrors.push(`${item.food_name}: ${insErr.message ?? 'unknown'}`)
      }
    }
    if (insertErrors.length > 0) {
      await ctx.supabase.from('product_events').insert({
        user_id: ctx.userId,
        event: 'tool.meal_logs_insert_failed',
        properties: {
          provider_message_id: ctx.providerMessageId ?? null,
          meal_type: args.meal_type ?? null,
          snapshot_id: snapshotId,
          attempted: itemsToInsert.length,
          errors: insertErrors,
        },
      })
      throw new Error(
        `meal_logs insert failed (${insertErrors.length}/${itemsToInsert.length}): ${insertErrors.join('; ')}`,
      )
    }

    return {
      success: true,
      meal: {
        // Reporta SÓ os itens que foram de fato inseridos (sobreviventes da
        // dedup contra o dia) — senão o card mostraria itens duplicados que
        // não entraram no snapshot.
        items: itemsToInsert.map((i) => ({
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
        totals: totalsToAdd,
      },
      day_totals: updated,
      warnings: calc.user_warnings,
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
    'Retorna o painel de progresso do usuário (XP, nível, sequência de dias, blocos completos, conquistas, registro de hoje). Use quando ele perguntar como está indo.',
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

    // Traduz as chaves pra português ANTES de devolver pro LLM. Sem isso o LLM
    // vê "current_streak"/"level" no JSON e replica "streak"/"level" na resposta
    // ao paciente (Roberto reclamou 2026-05-13/14).
    const p = progress as {
      xp_total?: number
      level?: number
      current_streak?: number
      longest_streak?: number
      blocks_completed?: number
      deficit_block?: number
      badges_earned?: string[]
    } | null
    const progressoPt = p
      ? {
          xp: p.xp_total ?? 0,
          nivel: p.level ?? 1,
          sequencia_dias_consecutivos: p.current_streak ?? 0,
          recorde_sequencia: p.longest_streak ?? 0,
          blocos_7700_completos: p.blocks_completed ?? 0,
          deficit_no_bloco_atual: p.deficit_block ?? 0,
          conquistas: p.badges_earned ?? [],
        }
      : null

    return { progresso: progressoPt, hoje: snap ?? null }
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
    'Registra um TREINO QUE O PACIENTE ACABOU DE EXECUTAR (completado hoje, agora ou nas últimas horas). ' +
    'Kcal queimadas: por padrão calculadas via fórmula (workout_type × duração × intensidade × peso). ' +
    'EXCEÇÃO: se o paciente enviou FOTO de app de fitness (Apple Health, Strava, Garmin, Samsung Health, etc) com kcal NUMÉRICO VISÍVEL, ' +
    'passe esse valor em `estimated_kcal_from_image` e o sistema usará ele em vez da fórmula. ' +
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
    estimated_kcal_from_image: z
      .number()
      .positive()
      .optional()
      .describe(
        'kcal extraído de FOTO de app de fitness (Apple Health, Strava, Garmin, Samsung Health, Polar, Fitbit, etc). ' +
          'PASSE quando o paciente enviou screenshot E o número aparece claramente na imagem. ' +
          'Se houver múltiplos workouts na foto, divida em chamadas separadas, cada uma com seu kcal próprio. ' +
          'NÃO PASSE quando o paciente descreveu o treino só em texto/áudio — nesses casos a fórmula determinística é mais confiável que adivinhação. ' +
          'Sistema valida sanidade: se valor for absurdo (<10% ou >300% da fórmula), descarta e usa fórmula.',
      ),
  }),
  execute: async (args, ctx) => {
    const today = getLocalDateString(ctx.userTimezone ?? 'America/Sao_Paulo')

    // Idempotência granular: bloqueia retry/Inngest replay (mesma msg + mesmo
    // workout_type), mas PERMITE múltiplos workouts diferentes da mesma foto
    // (ex: foto do app mostra musculação + bike — 2 calls registra_treino com
    // mesmo pmid mas workout_type diferentes, ambos devem entrar).
    //
    // Bug histórico: dedupe era só por pmid. Roberto mandou foto com 3
    // exercícios → LLM fez 2 calls (musculação + bike) → bike foi deduped
    // (mesmo pmid) e ficou sem registrar; só musculação ficou no snapshot.
    if (ctx.providerMessageId) {
      const { data: existing } = await ctx.supabase
        .from('workout_logs')
        .select('id, snapshot_id, workout_type, estimated_kcal')
        .eq('user_id', ctx.userId)
        .eq('raw_provider_message_id', ctx.providerMessageId)
        .eq('workout_type', args.workout_type)
        .limit(2)
      if (existing && existing.length > 0) {
        return {
          success: true,
          deduped: true,
          message: `Treino ${args.workout_type} já registrado (msg_id+tipo repetido). Não duplicou.`,
        }
      }
    }

    // 2ª camada de dedup (Paulo 2026-05-26): a MESMA caminhada foi descrita em
    // mensagens DIFERENTES (pmid diferente) e duplicou — a idempotência por pmid
    // acima não pega. Se um treino IDÊNTICO (tipo + duração) já foi registrado
    // nas últimas 6h, é re-processamento → não duplica. (Espelha a 4ª camada de
    // dedup do registra_refeicao; janela de 6h evita bloquear treino repetido
    // legítimo de manhã+noite.)
    if (args.duration_min != null) {
      const sixHoursAgo = new Date(Date.now() - 6 * 3600 * 1000).toISOString()
      const { data: recentSame } = await ctx.supabase
        .from('workout_logs')
        .select('id')
        .eq('user_id', ctx.userId)
        .eq('workout_type', args.workout_type)
        .eq('duration_min', args.duration_min)
        .gte('created_at', sixHoursAgo)
        .limit(1)
      if (recentSame && recentSame.length > 0) {
        await ctx.supabase.from('product_events').insert({
          user_id: ctx.userId,
          event: 'tool.workout_redup_skipped',
          properties: {
            workout_type: args.workout_type,
            duration_min: args.duration_min,
            provider_message_id: ctx.providerMessageId ?? null,
            note: 'treino idêntico (tipo+duração) já registrado nas últimas 6h — não reinsere (caso Paulo 2026-05-26)',
          },
        })
        return {
          success: true,
          deduped: true,
          message: `Treino ${args.workout_type} (${args.duration_min}min) já registrado recentemente. Não duplicou.`,
        }
      }
    }

    // 3ª camada: CORREÇÃO de treino (Roberto 2026-05-27). Paulo registrou caminhada
    // 60min, corrigiu pra 30min → o sistema SOMOU (60+30=90min/247kcal) em vez de
    // SUBSTITUIR. Dedup só pega tipo+duração igual. Espelha o `replace` do
    // registra_refeicao: se a mensagem do paciente tem intenção de correção E já
    // existe treino do MESMO TIPO nas últimas 2h, deletamos o antigo, abatemos
    // o kcal do snapshot, e seguimos pro insert normal (que soma o novo).
    if (args.duration_min != null) {
      const correctionWord = detectCorrectionIntent(ctx.recentUserMessages ?? [])
      if (correctionWord) {
        const twoHoursAgo = new Date(Date.now() - 2 * 3600 * 1000).toISOString()
        const { data: oldOnes } = await ctx.supabase
          .from('workout_logs')
          .select('id, estimated_kcal, duration_min')
          .eq('user_id', ctx.userId)
          .eq('workout_type', args.workout_type)
          .gte('created_at', twoHoursAgo)
        const oldRows = (oldOnes ?? []) as Array<{
          id: string
          estimated_kcal: number | null
          duration_min: number | null
        }>
        if (oldRows.length > 0) {
          const oldKcalSum = oldRows.reduce((s, w) => s + (w.estimated_kcal ?? 0), 0)
          await ctx.supabase
            .from('workout_logs')
            .delete()
            .in('id', oldRows.map((r) => r.id))
          // Abate o kcal antigo do snapshot (negativo) — o insert normal abaixo
          // soma o novo kcal. Net: troca o antigo pelo novo.
          if (oldKcalSum > 0) {
            await (ctx.supabase as unknown as {
              rpc: (
                n: string,
                p: Record<string, unknown>,
              ) => Promise<{ error: { message?: string } | null }>
            }).rpc('snapshot_add_workout', {
              p_user_id: ctx.userId,
              p_date: today,
              p_exercise_kcal: -oldKcalSum,
            })
          }
          await ctx.supabase.from('product_events').insert({
            user_id: ctx.userId,
            event: 'tool.workout_replaced',
            properties: {
              workout_type: args.workout_type,
              correction_word: correctionWord,
              old_count: oldRows.length,
              old_kcal_sum: oldKcalSum,
              old_durations: oldRows.map((r) => r.duration_min),
              new_duration_min: args.duration_min,
            },
          })
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

    // Cálculo determinístico via SQL function (ADR-007). Sempre roda — mesmo
    // quando vamos usar valor da foto, a fórmula serve de baseline pra sanity check.
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
    const formulaKcal = Number(kcalResult ?? 0)

    // HÍBRIDO: usa kcal da foto se foi passado E está dentro de range razoável
    // (10%-300% da fórmula). Senão, usa a fórmula. Loga decisão pra auditoria.
    let finalKcal = formulaKcal
    let kcalSource: 'image' | 'formula' = 'formula'
    let imageDiscarded = false
    if (args.estimated_kcal_from_image && args.estimated_kcal_from_image > 0) {
      const ratio = args.estimated_kcal_from_image / Math.max(formulaKcal, 1)
      const inRange = ratio >= 0.1 && ratio <= 3.0
      if (inRange) {
        finalKcal = Math.round(args.estimated_kcal_from_image)
        kcalSource = 'image'
      } else {
        imageDiscarded = true
      }
      // Audit: registra a decisão pra debug + ajuste futuro de threshold
      await ctx.supabase.from('product_events').insert({
        user_id: ctx.userId,
        event: imageDiscarded ? 'workout.kcal_image_discarded' : 'workout.kcal_image_used',
        properties: {
          workout_type: args.workout_type,
          duration_min: args.duration_min,
          intensity: args.intensity ?? 'moderada',
          weight_kg: weightKg,
          formula_kcal: formulaKcal,
          image_kcal: args.estimated_kcal_from_image,
          ratio: +ratio.toFixed(2),
          chosen: kcalSource,
        },
      })
    }

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
      p_exercise_kcal: finalKcal,
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
      estimated_kcal: finalKcal,
      notes: args.notes
        ? `${args.notes} [src=${kcalSource}]`
        : `[kcal_source=${kcalSource}, formula=${formulaKcal}, image=${args.estimated_kcal_from_image ?? 'n/a'}]`,
      raw_provider_message_id: ctx.providerMessageId ?? null,
    })

    return {
      success: true,
      kcal_burned: finalKcal,
      kcal_source: kcalSource,
      formula_kcal: formulaKcal,
      image_kcal: args.estimated_kcal_from_image ?? null,
      image_discarded: imageDiscarded,
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
// ----------------------------------------------------------------------------
// marca_refeicao_pulada — paciente confirmou que não comeu essa refeição
// ----------------------------------------------------------------------------
export const marcaRefeicaoPulada: ToolDefinition = {
  name: 'marca_refeicao_pulada',
  description:
    'Marca uma REFEIÇÃO específica como PULADA pelo paciente hoje (ele não comeu intencionalmente). ' +
    'Use quando paciente responder confirmando que pulou: "pulei o jantar", "não comi café hoje", ' +
    '"fiquei sem almoço", "não tinha fome", "passei direto", "fui dormir sem jantar", "tô em jejum". ' +
    'NÃO use quando paciente está PERGUNTANDO sobre pular, ou explicando teoria — só quando ele relata ' +
    'comportamento real do dia. Loga em product_events pro daily-closer considerar o dia como completo ' +
    '(creditar bloco 7700 normalmente) mesmo sem registro daquela refeição. Sem isso, o sistema fica ' +
    'esperando lembrete/registro e pode marcar dia como incomplete_no_response.',
  parameters: z.object({
    meal_type: z
      .enum(['cafe', 'almoco', 'lanche', 'jantar', 'ceia'])
      .describe('Tipo da refeição que o paciente confirmou ter pulado'),
    reason: z
      .string()
      .optional()
      .describe('Motivo opcional informado pelo paciente (ex: "jejum intermitente", "sem fome", "trabalho")'),
  }),
  execute: async (args, ctx) => {
    await ctx.supabase.from('product_events').insert({
      user_id: ctx.userId,
      event: 'meal.user_skipped',
      properties: {
        meal_type: args.meal_type,
        reason: args.reason ?? null,
        provider_message_id: ctx.providerMessageId ?? null,
      },
    })
    return {
      success: true,
      meal_type: args.meal_type,
      message: `Refeição "${args.meal_type}" marcada como pulada hoje. O dia segue válido pro bloco 7700 (assumimos que foi intencional).`,
    }
  },
}

// ----------------------------------------------------------------------------
// consulta_reavaliacao_protocolo — decisões determinísticas de ganho/manutenção
// ----------------------------------------------------------------------------
export const consultaReavaliacaoProtocolo: ToolDefinition = {
  name: 'consulta_reavaliacao_protocolo',
  description:
    'Computa as decisões DETERMINÍSTICAS da reavaliação de GANHO DE MASSA ou MANUTENÇÃO ' +
    '(velocidade de ganho, teto de gordura/IMC, ajuste calórico) a partir do baseline do ciclo e dos ' +
    'valores atuais. Use na reavaliação (~14 dias), DEPOIS que o paciente informar peso/BF atuais. Só ' +
    'para ganho_massa/manutencao (recomposição usa a escada de déficit). Os números vêm CALCULADOS — não ' +
    'invente velocidade/ajuste de cabeça.',
  parameters: z.object({
    current_weight_kg: z.number().describe('Peso atual informado na reavaliação (kg)'),
    current_bf_percent: z.number().optional().describe('BF% atual, se informado'),
    current_training_freq: z
      .number()
      .int()
      .optional()
      .describe('Treinos de musculação/semana atuais (usado na manutenção)'),
  }),
  execute: async (args, ctx) => {
    const { data: p } = await ctx.supabase
      .from('user_profiles')
      .select(
        'sex, height_cm, current_protocol, training_frequency, cycle_start_weight_kg, cycle_start_bf_percent, cycle_start_training_freq, cycle_start_at',
      )
      .eq('user_id', ctx.userId)
      .maybeSingle()
    const prof = p as {
      sex: 'masculino' | 'feminino' | null
      height_cm: number | null
      current_protocol: 'recomposicao' | 'ganho_massa' | 'manutencao' | null
      training_frequency: number | null
      cycle_start_weight_kg: number | null
      cycle_start_bf_percent: number | null
      cycle_start_training_freq: number | null
      cycle_start_at: string | null
    } | null
    if (!prof) return { error: 'profile_not_found' }
    const protocol = prof.current_protocol
    if (protocol !== 'ganho_massa' && protocol !== 'manutencao') {
      return { error: 'tool_apenas_ganho_ou_manutencao', current_protocol: protocol }
    }

    if (protocol === 'ganho_massa') {
      if (prof.cycle_start_weight_kg == null || prof.cycle_start_at == null) {
        return {
          error: 'sem_baseline_do_ciclo',
          hint: 'baseline não capturado no início do ciclo; defina o protocolo de novo pra registrar o início',
        }
      }
      const days = Math.max(
        1,
        Math.round((Date.now() - new Date(prof.cycle_start_at).getTime()) / 86_400_000),
      )
      const velocity = evaluateGainVelocity(prof.cycle_start_weight_kg, args.current_weight_kg, days)
      let safety: ReturnType<typeof evaluateGainSafety> | null = null
      if (
        prof.sex &&
        prof.height_cm &&
        prof.cycle_start_bf_percent != null &&
        args.current_bf_percent != null
      ) {
        const hM = Number(prof.height_cm) / 100
        const imcStart = prof.cycle_start_weight_kg / (hM * hM)
        const imcNow = args.current_weight_kg / (hM * hM)
        safety = evaluateGainSafety({
          sex: prof.sex,
          bfStart: prof.cycle_start_bf_percent,
          bfNow: args.current_bf_percent,
          imcStart,
          imcNow,
        })
      }
      return { protocol, days_in_cycle: days, velocity, safety }
    }

    // manutenção: ajuste por treino a menos
    const prevFreq = prof.cycle_start_training_freq ?? prof.training_frequency ?? 0
    const nowFreq = args.current_training_freq ?? prof.training_frequency ?? prevFreq
    const adjustment = computeMaintenanceAdjustment(prevFreq, nowFreq)
    return { protocol, adjustment }
  },
}

// ----------------------------------------------------------------------------
// registra_metrica_diaria — captura leve de água/sono/passos quando mencionados
// ----------------------------------------------------------------------------
export const registraMetricaDiaria: ToolDefinition = {
  name: 'registra_metrica_diaria',
  description:
    'Grava água (ml), sono (horas) e/ou passos do paciente no dia de HOJE, quando ele MENCIONAR esses dados ' +
    '("bebi 2L de água", "dormi 7 horas", "fiz 8 mil passos"). Grava só o que o paciente informou (parcial ok). ' +
    '⚠️ NÃO infira nem pergunte proativamente — registre apenas o que ele relatar espontaneamente. Não é meta ' +
    'obrigatória nem entra no card de balanço.',
  parameters: z.object({
    water_ml: z.number().optional().describe('Água consumida hoje em ml (ex: 2000 = 2L)'),
    sleep_hours: z.number().optional().describe('Horas de sono da última noite (ex: 7.5)'),
    steps: z.number().int().optional().describe('Passos do dia'),
  }),
  execute: async (args, ctx) => {
    if (args.water_ml == null && args.sleep_hours == null && args.steps == null) {
      return { error: 'nenhuma métrica informada' }
    }
    const tz = ctx.userTimezone ?? 'America/Sao_Paulo'
    const today = getLocalDateString(tz)
    const patch: Record<string, number> = {}
    if (args.water_ml != null) patch.water_consumed_ml = Math.round(args.water_ml)
    if (args.sleep_hours != null) patch.sleep_hours = args.sleep_hours
    if (args.steps != null) patch.steps = Math.round(args.steps)
    // upsert: cria o snapshot de hoje se não existir (colunas NOT NULL têm default);
    // se existir, atualiza só as métricas informadas (preserva consumo/proteína/etc).
    await ctx.supabase
      .from('daily_snapshots')
      .upsert({ user_id: ctx.userId, date: today, ...patch }, { onConflict: 'user_id,date' })
    await ctx.supabase.from('product_events').insert({
      user_id: ctx.userId,
      event: 'metric.captured',
      properties: { date: today, ...patch },
    })
    return { success: true, date: today, ...patch }
  },
}

// ----------------------------------------------------------------------------
// consulta_resumo_periodo — médias/aderência de 7 ou 30 dias (determinístico)
// ----------------------------------------------------------------------------
export const consultaResumoPeriodo: ToolDefinition = {
  name: 'consulta_resumo_periodo',
  description:
    'Retorna o RESUMO determinístico de um período (semana = 7 dias, mês = 30 dias): médias de calorias e ' +
    'proteína, média do déficit do dia, dias completos e % de aderência. Use quando o paciente pedir comparação/' +
    'evolução ("como foi minha semana?", "minha média de proteína subiu?"). Assim os números vêm CALCULADOS do ' +
    'banco, não da sua cabeça (evita alucinação de média).',
  parameters: z.object({
    periodo: z.enum(['semana', 'mes']).describe('semana = últimos 7 dias; mes = últimos 30 dias'),
  }),
  execute: async (args, ctx) => {
    const tz = ctx.userTimezone ?? 'America/Sao_Paulo'
    const today = getLocalDateString(tz)
    const n = args.periodo === 'semana' ? 7 : 30
    const start = new Date(`${today}T00:00:00Z`)
    start.setUTCDate(start.getUTCDate() - (n - 1))
    const startStr = start.toISOString().slice(0, 10)
    const { data } = await ctx.supabase
      .from('daily_snapshots')
      .select('calories_consumed, protein_g, daily_balance, day_status')
      .eq('user_id', ctx.userId)
      .eq('day_closed', true)
      .gte('date', startStr)
      .lte('date', today)
      .order('date', { ascending: true })
    const summary = computePeriodSummary((data ?? []) as unknown as SnapshotForAgg[])
    return { periodo: args.periodo, from: startStr, to: today, ...summary }
  },
}

// ----------------------------------------------------------------------------
// gera_dieta — Sprint 4.1 (Roberto 2026-06-11)
// ----------------------------------------------------------------------------
export const geraDieta: ToolDefinition = {
  name: 'gera_dieta',
  description:
    'Gera uma prescrição de dieta personalizada + lista de compras pro paciente, baseada no ' +
    'perfil dele (meta calórica/proteica, protocolo, restrições) e no histórico de alimentos que ele já come. ' +
    'Use APENAS quando o paciente pedir EXPLICITAMENTE pra gerar/montar AGORA — frases imperativas diretas: ' +
    '"monta um cardápio pra mim agora", "me gera a dieta", "preciso da lista de compras". ' +
    'NÃO use quando paciente está só TIRANDO DÚVIDA ou EXPLORANDO ("é possível ter uma dieta X?", ' +
    '"quero entender melhor sobre dieta"). Nesse caso, responda a dúvida sem chamar a tool, e CONFIRME antes: ' +
    '"Quer que eu gere agora um cardápio personalizado pra você?". ' +
    'NÃO use quando ele só descreve o que come (isso é registra_refeicao). ' +
    'A dieta é referência (sugestão flexível), não rígida — paciente pode adaptar. ' +
    'Modo "daily" = 1 dia. Modo "weekly" também é 1 dia hoje (variação semanal ainda não está completa). ' +
    'Se receber {success:false}, NÃO finja que gerou — explique que houve problema técnico e peça pra tentar daqui a alguns minutos.',
  parameters: z.object({
    horizon: z
      .enum(['daily', 'weekly'])
      .default('daily')
      .describe('Período da prescrição. "weekly" recomendado quando paciente quer planejamento semanal'),
    meals_per_day: z
      .number()
      .int()
      .min(2)
      .max(6)
      .default(4)
      .optional()
      .describe('Número de refeições por dia (default 4: café/almoço/lanche/jantar)'),
    restrictions: z
      .array(z.string())
      .optional()
      .describe('Alergias ou restrições do paciente (ex: ["lactose", "glúten"])'),
    preferences: z
      .array(z.string())
      .optional()
      .describe('Alimentos preferidos pra incluir (ex: ["frango", "ovo", "tapioca"])'),
  }),
  execute: async (args, ctx) => {
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    const sp = ctx.supabase as any

    // 1. Carrega perfil do paciente
    const { data: u } = await sp
      .from('users')
      .select('name, country, locale')
      .eq('id', ctx.userId)
      .maybeSingle()
    const { data: p } = await sp
      .from('user_profiles')
      .select('sex, birth_date, weight_kg, height_cm, activity_level, current_protocol')
      .eq('user_id', ctx.userId)
      .maybeSingle()
    const ageFromBirth = (bd: string | null | undefined): number | null =>
      bd ? Math.floor((Date.now() - new Date(bd).getTime()) / 31557600000) : null
    const { data: up } = await sp
      .from('user_progress')
      .select('current_bf_percent')
      .eq('user_id', ctx.userId)
      .maybeSingle()

    // 2. Carrega targets calóricos/proteicos
    const cfg = await loadCalcConfig(ctx.supabase)
    const targets = await loadDailyTargets(ctx.supabase, ctx.userId, cfg)

    // 3. Carrega histórico de alimentos (últimos 30d, top 30 mais frequentes)
    const since = new Date(Date.now() - 30 * 24 * 3600 * 1000).toISOString()
    const { data: histLogs } = await sp
      .from('meal_logs')
      .select('food_name')
      .eq('user_id', ctx.userId)
      .gte('created_at', since)
    const freqMap = new Map<string, number>()
    for (const r of (histLogs ?? []) as Array<{ food_name: string }>) {
      const k = r.food_name.toLowerCase().trim()
      freqMap.set(k, (freqMap.get(k) ?? 0) + 1)
    }
    const historical_foods = Array.from(freqMap.entries())
      .sort((a, b) => b[1] - a[1])
      .slice(0, 30)
      .map(([food_name, frequency]) => ({ food_name, frequency }))

    // Rate-limit: max 2 gerações nas últimas 2h. Evita loop/abuso (cada
    // chamada custa ~$0.05 de LLM).
    const cooldownSince = new Date(Date.now() - 2 * 3600 * 1000).toISOString()
    const { data: recent } = await sp
      .from('product_events')
      .select('id')
      .eq('user_id', ctx.userId)
      .eq('event', 'diet.generated')
      .gte('occurred_at', cooldownSince)
    if ((recent ?? []).length >= 2) {
      return {
        success: false,
        error:
          'Já geramos 2 cardápios nas últimas 2h. Espera um pouco e me avisa se quer outra versão — explique pro paciente sem chamar a tool de novo.',
      }
    }

    // 4. Gera via diet-generator
    const { generateDietPlan, saveDietPlan } = await import('./diet-generator.js')
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    const llm = (ctx as any).llm
    if (!llm) {
      return {
        success: false,
        error: 'LLM não disponível no contexto da tool. Configure ctx.llm.',
      }
    }
    const plan = await generateDietPlan(llm, ctx.supabase, {
      userId: ctx.userId,
      profile: {
        name: u?.name ?? null,
        sex: (p?.sex as 'masculino' | 'feminino' | null) ?? null,
        age: ageFromBirth(p?.birth_date),
        weight_kg: p?.weight_kg ?? null,
        height_cm: p?.height_cm ?? null,
        activity_level: (p?.activity_level as 'sedentario' | 'leve' | 'moderado' | 'alto' | 'atleta' | null) ?? null,
        protocol: (p?.current_protocol as 'recomposicao' | 'manutencao' | 'ganho_massa' | null) ?? null,
        meta_kcal: targets.calories_target ?? null,
        meta_protein_g: targets.protein_target ?? null,
        bf_percent: up?.current_bf_percent ?? null,
        restrictions: args.restrictions ?? [],
        preferences: args.preferences ?? [],
      },
      historical_foods,
      meals_per_day: args.meals_per_day,
      mode: 'referencia',
      horizon: args.horizon ?? 'daily',
    })
    if (!plan) {
      return { success: false, error: 'Falha ao gerar dieta. Tente novamente em alguns segundos.' }
    }
    const saved = await saveDietPlan(ctx.supabase, plan)
    if (!saved.id) {
      // Save falhou — NÃO registra diet.generated (senão rate-limit
      // bloqueia 2h sem prescription real). Loga separado pra audit.
      await ctx.supabase.from('product_events').insert({
        user_id: ctx.userId,
        event: 'diet.save_failed',
        properties: { horizon: plan.horizon, meals_count: plan.daily_meals.length },
      })
      return {
        success: false,
        error:
          'Gerei o cardápio mas tive problema ao salvar. Pede pro paciente tentar de novo em alguns segundos.',
      }
    }
    await ctx.supabase.from('product_events').insert({
      user_id: ctx.userId,
      event: 'diet.generated',
      properties: {
        prescription_id: saved.id,
        horizon: plan.horizon,
        meals_count: plan.daily_meals.length,
        shopping_items: plan.shopping_list.length,
      },
    })
    return {
      success: true,
      prescription_id: saved.id,
      horizon: plan.horizon,
      meta_kcal: plan.meta_kcal,
      meta_protein_g: plan.meta_protein_g,
      daily_meals: plan.daily_meals,
      shopping_list: plan.shopping_list,
      message:
        'Dieta gerada com sucesso. Apresente ao paciente: liste as refeições com itens + macros + horários sugeridos, depois a lista de compras agrupada por categoria. ' +
        'Termine com nota: "Isso é referência — adapte conforme seu dia. Me avise se quiser ajustar algo."',
    }
  },
}

// ----------------------------------------------------------------------------
// gera_treino — Sprint 4.2 (Roberto 2026-06-11)
// ----------------------------------------------------------------------------
export const geraTreino: ToolDefinition = {
  name: 'gera_treino',
  description:
    'Gera UM plano de treino semanal personalizado pro paciente. ' +
    'Use APENAS depois de PERGUNTAR E CONFIRMAR com o paciente OS TRÊS dados: ' +
    '(1) equipamentos disponíveis (lista detalhada ou foto), ' +
    '(2) quantos dias por semana topa treinar, ' +
    '(3) nível atual de musculação: iniciante (nunca treinou ou parou >6 meses), intermediário (1-2a treinando constante), ou avançado (3a+ com técnica). ' +
    'NUNCA chute training_level — pergunte explícito. ' +
    'O plano é ESPORÁDICO: gera UMA vez, sistema entrega o treino do dia automaticamente todo dia ' +
    '(cron determinístico, sem regerar com LLM). Paciente pode pedir regenerar se equipamentos/rotina mudarem. ' +
    'NÃO use pra "vou fazer um treino agora" (isso é registra_treino). ' +
    'Se receber {success:false}, NÃO finja que gerou — explique que houve problema técnico e peça pra tentar daqui a alguns minutos.',
  parameters: z.object({
    available_equipment: z
      .array(z.string())
      .min(1)
      .describe('Lista de equipamentos identificados (ex: ["halteres 5-30kg", "barra fixa", "elástico"])'),
    location: z
      .enum(['academia_completa', 'academia_limitada', 'casa'])
      .describe('Local onde o paciente vai treinar'),
    days_per_week: z
      .number()
      .int()
      .min(1)
      .max(7)
      .describe('Dias por semana que o paciente topa treinar'),
    training_days: z
      .array(z.string())
      .optional()
      .describe('Dias específicos da semana (ex: ["seg","qua","sex"])'),
    training_level: z
      .enum(['iniciante', 'intermediario', 'avancado'])
      .describe('Nível atual de musculação do paciente'),
    goes_to_failure: z
      .boolean()
      .optional()
      .describe('Topa treinar até falha muscular? (false = abordagem mais guiada/segura)'),
    limitations: z
      .array(z.string())
      .optional()
      .describe('Lesões/dores/limitações (ex: ["dor no joelho", "lombar sensível"])'),
    priority_muscles: z
      .array(z.string())
      .optional()
      .describe('Grupos musculares de prioridade (ex: ["glúteos", "MMII"])'),
  }),
  execute: async (args, ctx) => {
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    const sp = ctx.supabase as any
    const { data: u } = await sp
      .from('users')
      .select('name')
      .eq('id', ctx.userId)
      .maybeSingle()
    const { data: p } = await sp
      .from('user_profiles')
      .select('sex, birth_date, weight_kg, height_cm, current_protocol')
      .eq('user_id', ctx.userId)
      .maybeSingle()
    const ageFromBirthT = (bd: string | null | undefined): number | null =>
      bd ? Math.floor((Date.now() - new Date(bd).getTime()) / 31557600000) : null
    const { data: up } = await sp
      .from('user_progress')
      .select('current_bf_percent')
      .eq('user_id', ctx.userId)
      .maybeSingle()

    // Rate-limit: max 1 geração de plano nas últimas 24h. Treino é
    // esporádico — paciente NÃO precisa regenerar 5x/dia.
    const cooldownSinceT = new Date(Date.now() - 24 * 3600 * 1000).toISOString()
    const { data: recentT } = await sp
      .from('product_events')
      .select('id')
      .eq('user_id', ctx.userId)
      .eq('event', 'training.plan_generated')
      .gte('occurred_at', cooldownSinceT)
    if ((recentT ?? []).length >= 1) {
      return {
        success: false,
        error:
          'Já geramos um plano de treino nas últimas 24h. Pra regenerar, peça pro paciente esperar até amanhã ou avisar Eduardo. Não chame a tool de novo.',
      }
    }

    const { generateTrainingPlan, saveTrainingPlan } = await import('./training-plan-generator.js')
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    const llm = (ctx as any).llm
    if (!llm) {
      return { success: false, error: 'LLM não disponível no contexto da tool.' }
    }
    const plan = await generateTrainingPlan(llm, ctx.supabase, {
      userId: ctx.userId,
      profile: {
        name: u?.name ?? null,
        sex: (p?.sex as 'masculino' | 'feminino' | null) ?? null,
        age: ageFromBirthT(p?.birth_date),
        weight_kg: p?.weight_kg ?? null,
        height_cm: p?.height_cm ?? null,
        protocol: (p?.current_protocol as 'recomposicao' | 'manutencao' | 'ganho_massa' | null) ?? null,
        bf_percent: up?.current_bf_percent ?? null,
        training_level: args.training_level,
        limitations: args.limitations ?? [],
        priority_muscles: args.priority_muscles ?? [],
      },
      days_per_week: args.days_per_week,
      training_days: args.training_days,
      available_equipment: args.available_equipment,
      location: args.location,
      goes_to_failure: args.goes_to_failure,
    })
    if (!plan) {
      return { success: false, error: 'Falha ao gerar plano de treino. Tente novamente.' }
    }
    const saved = await saveTrainingPlan(ctx.supabase, plan)
    if (!saved.id) {
      // Cron de entrega faz inner join com training_plans active=true.
      // Sem ID salvo, paciente nunca recebe o treino diário. Não registra
      // training.plan_generated (rate-limit 24h ficaria preso sem plano).
      await ctx.supabase.from('product_events').insert({
        user_id: ctx.userId,
        event: 'training.save_failed',
        properties: { days_per_week: plan.days_per_week, location: args.location },
      })
      return {
        success: false,
        error:
          'Gerei o plano mas tive problema ao salvar. Pede pro paciente tentar de novo em alguns segundos.',
      }
    }
    await ctx.supabase.from('product_events').insert({
      user_id: ctx.userId,
      event: 'training.plan_generated',
      properties: {
        plan_id: saved.id,
        plan_type: plan.plan_type,
        days_per_week: plan.days_per_week,
        equipment_count: args.available_equipment.length,
        location: args.location,
      },
    })
    return {
      success: true,
      plan_id: saved.id,
      plan_type: plan.plan_type,
      days_per_week: plan.days_per_week,
      weekly_schedule: plan.weekly_schedule,
      progression_rule: plan.progression_rule,
      message:
        'Plano de treino gerado e salvo. Apresente ao paciente: visão geral (split + dias) + 1º treino completo com execução passo-a-passo. ' +
        'Mencione: "Te envio o treino do dia automaticamente todo dia de manhã. Avise se precisar regenerar o plano."',
    }
  },
}

export const ALL_TOOLS: ToolDefinition[] = [
  cadastraDadosIniciais,
  defineProtocolo,
  defineMetaPeso,
  registraRefeicao,
  registraTreino,
  consultaProgresso,
  consultaMetricas,
  consultaResumoPeriodo,
  consultaReavaliacaoProtocolo,
  registraMetricaDiaria,
  marcaRefeicaoPulada,
  atualizaDataUser,
  encerraAtendimento,
  deleteUser,
  pausarAgente,
  retomarAgente,
  confirmaPaisResidencia,
  geraDieta,
  geraTreino,
]

export function getToolByName(name: string): ToolDefinition | undefined {
  return ALL_TOOLS.find((t) => t.name === name)
}
