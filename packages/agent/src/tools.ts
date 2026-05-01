/**
 * Tools que o LLM pode chamar. Cada tool tem:
 *  - schema (JSON Schema para o LLM)
 *  - execute(args, ctx) que opera no Supabase
 *
 * Formato compatível com OpenAI tool calling.
 */
import type { ServiceClient } from '@mpp/db'
import { z } from 'zod'

export interface ToolContext {
  supabase: ServiceClient
  userId: string
  userWpp: string
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
    if (args.sex) updates.sex = args.sex
    if (args.birth_date) updates.birth_date = args.birth_date
    if (args.height_cm != null) updates.height_cm = args.height_cm
    if (args.weight_kg != null) updates.weight_kg = args.weight_kg
    if (args.body_fat_percent != null) updates.body_fat_percent = args.body_fat_percent
    if (args.activity_level) updates.activity_level = args.activity_level
    if (args.training_frequency != null) updates.training_frequency = args.training_frequency
    if (args.water_intake) updates.water_intake = args.water_intake
    if (args.hunger_level) updates.hunger_level = args.hunger_level
    if (args.wake_time) updates.wake_time = args.wake_time
    if (args.bedtime) updates.bedtime = args.bedtime
    if (args.onboarding_step != null) updates.onboarding_step = args.onboarding_step
    if (args.onboarding_completed != null)
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
      .single()

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
// registra_refeicao — versão simples (sem TACO ainda)
// ----------------------------------------------------------------------------
export const registraRefeicao: ToolDefinition = {
  name: 'registra_refeicao',
  description:
    'Registra uma refeição com itens, calorias e macros. Use quando o usuário relatar uma refeição (texto ou foto).',
  parameters: z.object({
    meal_type: z
      .enum(['cafe', 'almoco', 'lanche', 'jantar', 'ceia', 'outro'])
      .optional(),
    items: z.array(
      z.object({
        food_name: z.string(),
        quantity_g: z.number().optional(),
        kcal: z.number(),
        protein_g: z.number(),
        carbs_g: z.number().optional(),
        fat_g: z.number().optional(),
      }),
    ),
  }),
  execute: async (args, ctx) => {
    const today = new Date().toISOString().split('T')[0]!

    // Garante snapshot do dia
    const { data: snap } = await ctx.supabase
      .from('daily_snapshots')
      .select('id, calories_consumed, protein_g, carbs_g, fat_g')
      .eq('user_id', ctx.userId)
      .eq('date', today)
      .maybeSingle()

    let snapshotId: string
    if (snap) {
      snapshotId = snap.id
    } else {
      const { data: created, error: createErr } = await ctx.supabase
        .from('daily_snapshots')
        .insert({ user_id: ctx.userId, date: today })
        .select('id')
        .single()
      if (createErr) throw createErr
      snapshotId = created.id
    }

    // Insere meal_logs
    const totals = { kcal: 0, p: 0, c: 0, f: 0 }
    for (const item of args.items) {
      totals.kcal += item.kcal
      totals.p += item.protein_g
      totals.c += item.carbs_g ?? 0
      totals.f += item.fat_g ?? 0
      await ctx.supabase.from('meal_logs').insert({
        user_id: ctx.userId,
        snapshot_id: snapshotId,
        meal_type: args.meal_type ?? null,
        food_name: item.food_name,
        quantity_g: item.quantity_g ?? null,
        kcal: item.kcal,
        protein_g: item.protein_g,
        carbs_g: item.carbs_g ?? null,
        fat_g: item.fat_g ?? null,
        source: 'agent_estimate',
      })
    }

    // Atualiza snapshot agregado
    const { data: updated, error: updErr } = await ctx.supabase
      .from('daily_snapshots')
      .update({
        calories_consumed: (snap?.calories_consumed ?? 0) + totals.kcal,
        protein_g: Number(snap?.protein_g ?? 0) + totals.p,
        carbs_g: Number(snap?.carbs_g ?? 0) + totals.c,
        fat_g: Number(snap?.fat_g ?? 0) + totals.f,
        updated_at: new Date().toISOString(),
      })
      .eq('id', snapshotId)
      .select('calories_consumed, protein_g, calories_target, protein_target')
      .single()
    if (updErr) throw updErr

    return {
      success: true,
      meal_totals: totals,
      day_totals: updated,
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
// Registry
// ----------------------------------------------------------------------------
export const ALL_TOOLS: ToolDefinition[] = [
  cadastraDadosIniciais,
  defineProtocolo,
  registraRefeicao,
  consultaProgresso,
]

export function getToolByName(name: string): ToolDefinition | undefined {
  return ALL_TOOLS.find((t) => t.name === name)
}
