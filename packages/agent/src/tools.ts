/**
 * Tools que o LLM pode chamar. Cada tool tem:
 *  - schema (JSON Schema para o LLM)
 *  - execute(args, ctx) que opera no Supabase
 *
 * Formato compatível com OpenAI tool calling.
 */
import type { ServiceClient } from '@mpp/db'
import { z } from 'zod'
import { calcMealMacros } from './meal-pipeline.js'
import { loadCalcConfig } from './calc-config-loader.js'
import { loadDailyTargets } from './calc-targets.js'

export interface ToolContext {
  supabase: ServiceClient
  userId: string
  userWpp: string
  /** ISO alpha-2 do país de residência (pra TACO/USDA, persona, idioma). */
  userCountry?: string
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
    'Salva ou atualiza dados iniciais do usuário no perfil. Use quando o usuário fornecer dados do questionário inicial: sexo, data de nascimento, altura, peso, BF%, frequência de treino, sono, fome.',
  parameters: z.object({
    name: z.string().optional().describe('Nome do usuário'),
    sex: z.enum(['masculino', 'feminino']).optional(),
    birth_date: z.string().optional().describe('YYYY-MM-DD'),
    height_cm: z.number().optional(),
    weight_kg: z.number().optional(),
    body_fat_percent: z.number().optional(),
    activity_level: z
      .enum(['sedentario', 'leve', 'moderado', 'alto', 'atleta'])
      .optional(),
    training_frequency: z.number().int().min(0).max(7).optional(),
    water_intake: z.enum(['pouco', 'moderado', 'bastante']).optional(),
    hunger_level: z.enum(['pouca', 'moderada', 'muita']).optional(),
    wake_time: z.string().optional().describe('HH:MM'),
    bedtime: z.string().optional().describe('HH:MM'),
    onboarding_step: z.number().int().min(0).max(11).optional(),
    onboarding_completed: z.boolean().optional(),
  }),
  execute: async (args, ctx) => {
    const updates: Record<string, unknown> = {}
    // Helper: aceita só números > 0 (LLM costuma mandar 0 como placeholder)
    const numPositive = (v: unknown): boolean => typeof v === 'number' && v > 0
    const strNonEmpty = (v: unknown): boolean => typeof v === 'string' && v.trim().length > 0

    if (strNonEmpty(args.sex)) updates.sex = args.sex
    if (strNonEmpty(args.birth_date)) updates.birth_date = args.birth_date
    if (numPositive(args.height_cm)) updates.height_cm = args.height_cm
    if (numPositive(args.weight_kg)) updates.weight_kg = args.weight_kg
    if (numPositive(args.body_fat_percent)) updates.body_fat_percent = args.body_fat_percent
    if (strNonEmpty(args.activity_level)) updates.activity_level = args.activity_level
    if (numPositive(args.training_frequency))
      updates.training_frequency = args.training_frequency
    if (strNonEmpty(args.water_intake)) updates.water_intake = args.water_intake
    if (strNonEmpty(args.hunger_level)) updates.hunger_level = args.hunger_level
    if (strNonEmpty(args.wake_time)) updates.wake_time = args.wake_time
    if (strNonEmpty(args.bedtime)) updates.bedtime = args.bedtime
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

    return {
      success: true,
      updated_fields: Object.keys(updates),
      metrics: metrics ?? null,
    }
  },
}

// ----------------------------------------------------------------------------
// define_protocolo — grava o protocolo escolhido
// ----------------------------------------------------------------------------
export const defineProtocolo: ToolDefinition = {
  name: 'define_protocolo',
  description:
    'Grava o protocolo escolhido pelo usuário. Use APENAS após validar critérios via cadastra_dados_iniciais e o usuário escolher explicitamente.',
  parameters: z.object({
    protocol: z.enum(['recomposicao', 'ganho_massa', 'manutencao']),
    deficit_level: z
      .union([z.literal(400), z.literal(500), z.literal(600)])
      .optional()
      .describe('Apenas para protocolo recomposicao'),
    goal_type: z.enum(['BF', 'IMC']).optional(),
    goal_value: z.number().optional(),
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
    return { success: true, protocol: args.protocol }
  },
}

// ----------------------------------------------------------------------------
// registra_refeicao — usa TACO determinísticamente (ADR-006)
// ----------------------------------------------------------------------------
export const registraRefeicao: ToolDefinition = {
  name: 'registra_refeicao',
  description:
    'Registra uma refeição. Você fornece apenas os nomes dos alimentos e quantidades em gramas. Os macros (kcal/proteína/carbo/gordura) são calculados automaticamente via base nutricional TACO. NÃO calcule macros manualmente — esta tool faz isso.',
  parameters: z.object({
    meal_type: z
      .enum(['cafe', 'almoco', 'lanche', 'jantar', 'ceia', 'outro'])
      .optional(),
    items: z
      .array(
        z.object({
          food_name: z
            .string()
            .describe('Nome do alimento em português (ex: "arroz branco cozido")'),
          quantity_g: z.number().describe('Quantidade em gramas'),
        }),
      )
      .describe('Lista de itens consumidos'),
  }),
  execute: async (args, ctx) => {
    const today = new Date().toISOString().split('T')[0]!

    // Calcula macros via TACO
    const calc = await calcMealMacros(ctx.supabase, args.items, ctx.userCountry ?? 'BR')

    // Garante snapshot do dia
    const { data: snap } = await ctx.supabase
      .from('daily_snapshots')
      .select('id, calories_consumed, protein_g, carbs_g, fat_g, calories_target, protein_target')
      .eq('user_id', ctx.userId)
      .eq('date', today)
      .maybeSingle()

    // Garante targets calculados (calories_target + protein_target).
    // Sem isso, daily_balance fica positivo sempre e bloco 7700 nunca cresce.
    const config = await loadCalcConfig(ctx.supabase)
    const targets = await loadDailyTargets(ctx.supabase, ctx.userId, config)

    let snapshotId: string
    if (snap) {
      snapshotId = snap.id
      // Se snapshot existe mas tá sem target (caso legado), retroplena.
      if (snap.calories_target == null && targets.calories_target != null) {
        await ctx.supabase
          .from('daily_snapshots')
          .update({
            calories_target: targets.calories_target,
            protein_target: targets.protein_target,
          })
          .eq('id', snapshotId)
      }
    } else {
      const { data: created, error: createErr } = await ctx.supabase
        .from('daily_snapshots')
        .insert({
          user_id: ctx.userId,
          date: today,
          calories_target: targets.calories_target,
          protein_target: targets.protein_target,
        })
        .select('id')
        .single()
      if (createErr) throw createErr
      snapshotId = created.id
    }

    // Insere cada item em meal_logs
    for (const item of calc.items) {
      await ctx.supabase.from('meal_logs').insert({
        user_id: ctx.userId,
        snapshot_id: snapshotId,
        meal_type: args.meal_type ?? null,
        food_name: item.matched_taco_name || item.food_name,
        quantity_g: item.quantity_g,
        kcal: item.kcal,
        protein_g: item.protein_g,
        carbs_g: item.carbs_g,
        fat_g: item.fat_g,
        source: item.source,
        confidence: item.similarity,
      })
    }

    // Atualiza snapshot agregado
    const { data: updated, error: updErr } = await ctx.supabase
      .from('daily_snapshots')
      .update({
        calories_consumed: Math.round((snap?.calories_consumed ?? 0) + calc.totals.kcal),
        protein_g: +(Number(snap?.protein_g ?? 0) + calc.totals.protein_g).toFixed(2),
        carbs_g: +(Number(snap?.carbs_g ?? 0) + calc.totals.carbs_g).toFixed(2),
        fat_g: +(Number(snap?.fat_g ?? 0) + calc.totals.fat_g).toFixed(2),
        updated_at: new Date().toISOString(),
      })
      .eq('id', snapshotId)
      .select('calories_consumed, protein_g, calories_target, protein_target, daily_balance')
      .single()
    if (updErr) throw updErr

    return {
      success: true,
      meal: {
        items: calc.items.map((i) => ({
          name: i.matched_taco_name || i.food_name,
          quantity_g: i.quantity_g,
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

    const today = new Date().toISOString().split('T')[0]!
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
// registra_treino
// ----------------------------------------------------------------------------
export const registraTreino: ToolDefinition = {
  name: 'registra_treino',
  description:
    'Registra um treino executado (musculação, cardio, etc). Use quando usuário relatar treino concluído.',
  parameters: z.object({
    workout_type: z
      .string()
      .describe('Ex: "peito_triceps", "perna_completa", "cardio", "corrida"'),
    duration_min: z.number().int().positive(),
    intensity: z.enum(['leve', 'moderada', 'alta']).optional(),
    estimated_kcal: z.number().int().nonnegative().optional(),
    notes: z.string().optional(),
  }),
  execute: async (args, ctx) => {
    const today = new Date().toISOString().split('T')[0]!

    const { data: snap } = await ctx.supabase
      .from('daily_snapshots')
      .select('id, exercise_calories')
      .eq('user_id', ctx.userId)
      .eq('date', today)
      .maybeSingle()

    // Mesmo padrão de registra_refeicao: garante targets no snapshot novo.
    const cfg = await loadCalcConfig(ctx.supabase)
    const tgt = await loadDailyTargets(ctx.supabase, ctx.userId, cfg)

    let snapshotId: string
    if (snap) {
      snapshotId = snap.id
    } else {
      const { data: created, error } = await ctx.supabase
        .from('daily_snapshots')
        .insert({
          user_id: ctx.userId,
          date: today,
          calories_target: tgt.calories_target,
          protein_target: tgt.protein_target,
        })
        .select('id')
        .single()
      if (error) throw error
      snapshotId = created.id
    }

    await ctx.supabase.from('workout_logs').insert({
      user_id: ctx.userId,
      snapshot_id: snapshotId,
      workout_type: args.workout_type,
      duration_min: args.duration_min,
      intensity: args.intensity,
      estimated_kcal: args.estimated_kcal,
      notes: args.notes,
    })

    await ctx.supabase
      .from('daily_snapshots')
      .update({
        exercise_calories: (snap?.exercise_calories ?? 0) + (args.estimated_kcal ?? 0),
        training_done: true,
        updated_at: new Date().toISOString(),
      })
      .eq('id', snapshotId)

    return { success: true }
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
    if (args.city) {
      const { data: user } = await ctx.supabase
        .from('users')
        .select('metadata')
        .eq('id', ctx.userId)
        .maybeSingle()
      const metadata = ((user?.metadata as Record<string, unknown>) ?? {}) as Record<string, unknown>
      metadata.city = args.city
      updates.metadata = JSON.parse(JSON.stringify(metadata))
    }
    const { error } = await ctx.supabase.from('users').update(updates).eq('id', ctx.userId)
    if (error) throw error
    return { success: true, updated: Object.keys(updates) }
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
    const { data: user } = await ctx.supabase
      .from('users')
      .select('metadata')
      .eq('id', ctx.userId)
      .maybeSingle()
    const metadata = (user?.metadata as Record<string, unknown>) ?? {}
    const labels = (metadata.labels as string[] | undefined) ?? []
    if (!labels.includes('humano')) labels.push('humano')
    metadata.labels = labels
    metadata.escalated_at = new Date().toISOString()
    metadata.escalation_reason = args.motivo

    await ctx.supabase
      .from('users')
      .update({ metadata: JSON.parse(JSON.stringify(metadata)) })
      .eq('id', ctx.userId)
    await ctx.supabase.from('product_events').insert({
      user_id: ctx.userId,
      event: 'human.escalation_requested',
      properties: { motivo: args.motivo, wpp: ctx.userWpp },
    })

    return { success: true, labels }
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
// confirma_pais_residencia — grava onde o paciente realmente mora
// ----------------------------------------------------------------------------
export const confirmaPaisResidencia: ToolDefinition = {
  name: 'confirma_pais_residencia',
  description:
    'Grava o país onde o paciente RESIDE atualmente. Use APENAS depois que o usuário confirmar explicitamente. Se ele disser "moro no Brasil", "estou em Portugal agora", "vivo em Madrid", chame essa tool com o ISO 3166-1 alpha-2 correto. Não use código de telefone como prova de residência — a tool serve pra corrigir/confirmar.',
  parameters: z.object({
    country: z
      .string()
      .length(2)
      .describe('ISO 3166-1 alpha-2 em UPPERCASE: BR, US, PT, ES, AR, MX, etc.'),
  }),
  execute: async (args, ctx) => {
    const country = args.country.toUpperCase()
    if (!/^[A-Z]{2}$/.test(country)) {
      throw new Error(`Código país inválido: ${country}. Use ISO alpha-2 (BR, US, PT, etc.).`)
    }
    const { error } = await ctx.supabase
      .from('users')
      .update({
        country,
        country_confirmed: true,
        updated_at: new Date().toISOString(),
      } as never)
      .eq('id', ctx.userId)
    if (error) throw error
    await ctx.supabase.from('product_events').insert({
      user_id: ctx.userId,
      event: 'country.confirmed',
      properties: { country, wpp: ctx.userWpp },
    })
    return {
      success: true,
      country,
      confirmed: true,
      message:
        country === 'BR'
          ? 'País gravado como Brasil. Sigo com TACO e medidas brasileiras.'
          : `País gravado como ${country}. Sigo com cuidado: ainda estou otimizado pra Brasil (TACO, medidas), pode haver imprecisão em alimentos locais.`,
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
