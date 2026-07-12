/**
 * Guard pós-LLM pra `marca_refeicao_pulada` (ACT-3 prevention plan 2026-06-16).
 *
 * Centraliza as defesas que estavam no pipeline.ts (FIX 4 audit 06-15)
 * e adiciona novas. Padrão: cada rejeição vira tool_rejected_by_guard +
 * retry message dirigido.
 *
 * Regras validadas:
 *  S1 (skip_blocked_vision_pending): há foto de meal analisada SEM virar
 *      registro nas últimas 4h E meal_type da foto não claramente diferente.
 *      Bug Roberto 06-15: LLM chamou skip depois de paciente responder
 *      disambiguação de foto — foto perdida.
 *  S2 (duplicate_skip): já há marca_refeicao_pulada gravada hoje pro
 *      mesmo (user, date, meal_type) — não duplica skip.
 *  S3 (skip_after_registration): já há meal_logs do dia pro mesmo
 *      meal_type — paciente registrou E agora pulou? LLM errou.
 *
 * Nota: S1 também está em pipeline.ts (bloqueio inline). Aqui é defesa
 * em camadas — se o pipeline path mudar, guard pega.
 */

import { getLocalDateString } from '../timezone-utils.js'
import type { GuardContext, GuardResult } from './tool-guards.js'

interface MarcaPuladaArgs {
  meal_type?: string
  reason?: string
}

const MEAL_CONTEXT_MAP: Array<[RegExp, string]> = [
  [/caf[eé]|manh[ãa]|brunch/, 'cafe'],
  [/almo[çc]o|lunch/, 'almoco'],
  [/lanche|snack|tarde/, 'lanche'],
  [/jantar|dinner|noite/, 'jantar'],
  [/ceia|antes\s+de\s+dormir/, 'ceia'],
]

function inferMealFromContext(visionContext?: string | null): string | null {
  if (!visionContext) return null
  const ctx = visionContext.toLowerCase()
  for (const [re, meal] of MEAL_CONTEXT_MAP) {
    if (re.test(ctx)) return meal
  }
  return null
}

export async function validateMarcaRefeicaoPulada(
  args: Record<string, unknown>,
  ctx: GuardContext,
): Promise<GuardResult> {
  const a = args as MarcaPuladaArgs
  const mealType = a.meal_type ?? null

  // S1 — vision pendente. Replica defesa do pipeline.ts (FIX 4).
  if (ctx.visionPending) {
    const visionMealType = inferMealFromContext(
      ctx.visionPending.mealContext as string | null | undefined,
    )
    const ageMinutes = Number(ctx.visionPending.ageMinutes ?? 0)
    // Skip claramente de OUTRA refeição? OK liberar (paciente quer pular
    // jantar mas foto era do café).
    const clearlyDifferent =
      visionMealType != null && mealType != null && visionMealType !== mealType
    const veryOld = ageMinutes > 240 // > 4h: provavelmente foto abandonada
    if (!clearlyDifferent && !veryOld) {
      return {
        ok: false,
        reason: 'skip_blocked_vision_pending',
        details: {
          attempted_meal_type: mealType,
          vision_meal_inferred: visionMealType,
          vision_age_minutes: ageMinutes,
          vision_items_count: Array.isArray(ctx.visionPending.items)
            ? ctx.visionPending.items.length
            : 0,
        },
        retry_hint: `Há foto de refeição pendente de registro (${ageMinutes}min atrás). Antes de chamar marca_refeicao_pulada, chame registra_refeicao com os items da foto. Só pule se o paciente disser LITERALMENTE "pulei"/"não comi" SOBRE OUTRA refeição.`,
      }
    }
  }

  // S2 + S3: checagens pela data local da mensagem original. Consultar
  // consumed_at a partir de 00:00 UTC falha para pacientes fora de UTC.
  if (mealType) {
    const timezone = ctx.userTimezone ?? 'America/Sao_Paulo'
    const referenceTimestamp = ctx.referenceTimestamp ?? new Date()
    const localDate = getLocalDateString(timezone, referenceTimestamp)

    // biome-ignore lint/suspicious/noExplicitAny: supabase ServiceClient
    const sp = ctx.supabase as any

    const { count: skipCount, error: skipError } = await sp
      .from('product_events')
      .select('id', { count: 'exact', head: true })
      .eq('user_id', ctx.userId)
      .eq('event', 'meal.user_skipped')
      .filter('properties->>local_date', 'eq', localDate)
      .filter('properties->>meal_type', 'eq', mealType)
    if (skipError) throw new Error(skipError.message ?? 'skip lookup failed')
    if ((skipCount ?? 0) > 0) {
      return {
        ok: false,
        reason: 'duplicate_skip',
        details: { meal_type: mealType, local_date: localDate },
        retry_hint: `${mealType} já foi marcado como pulado em ${localDate}. Não chame a tool novamente.`,
      }
    }

    const { data: snapshot, error: snapshotError } = await sp
      .from('daily_snapshots')
      .select('id')
      .eq('user_id', ctx.userId)
      .eq('date', localDate)
      .maybeSingle()
    if (snapshotError) throw new Error(snapshotError.message ?? 'snapshot lookup failed')

    // S3: já há meal_logs do mesmo meal_type no snapshot local?
    const { count: mealLogsCount, error: mealLogsError } = snapshot
      ? await sp
          .from('meal_logs')
          .select('id', { count: 'exact', head: true })
          .eq('user_id', ctx.userId)
          .eq('snapshot_id', snapshot.id)
          .eq('meal_type', mealType)
      : { count: 0, error: null }
    if (mealLogsError) throw new Error(mealLogsError.message ?? 'meal logs lookup failed')
    if ((mealLogsCount ?? 0) > 0) {
      return {
        ok: false,
        reason: 'skip_after_registration',
        details: { meal_type: mealType, local_date: localDate, existing_meals: mealLogsCount },
        retry_hint: `O paciente JÁ registrou ${mealType} hoje (${mealLogsCount} item(ns) em meal_logs). Não dá pra pular uma refeição que já foi registrada. Se foi engano e ele quer apagar, use corrige_refeicao com replace=true e items=[].`,
      }
    }
  }

  return { ok: true }
}
