/**
 * Guard pós-LLM pra `registra_refeicao` (ACT-3 prevention plan 2026-06-16).
 *
 * Rejeita chamadas claramente erradas ANTES do execute, com retry_hint
 * dirigido pra cada caso. Cada rejeição vira `tool_rejected_by_guard` em
 * product_events pra auditoria descobrir LLM regredindo.
 *
 * Regras validadas:
 *  R1 (empty_items): items=[] → LLM tentou registrar refeição sem items.
 *      Bug histórico: paciente diz "Pulei" e Haiku copia items do
 *      contexto, mas LLM pode também tentar registrar vazio se prompt
 *      regredir.
 *  R2 (implausible_total): sum(items.kcal) > 5000 → claramente errado
 *      (refeição humana max ~3500 kcal). Defesa contra Haiku alucinar
 *      números absurdos.
 *  R3 (duplicate_recent): já há meal_log pro mesmo (food_name normalizado,
 *      meal_type) nos últimos 5min → duplicação. NÃO bloqueia se
 *      trustedTap=true (paciente clicou ciente).
 *
 * NÃO valida zero-kcal items: o validated args do LLM não inclui kcal por
 * item ainda (vem do calcMealMacros pós-resolve TACO). Essa defesa fica
 * no interactive-handler (já existe: tap.blocked_zero_kcal).
 */

import type { GuardContext, GuardResult } from './tool-guards.js'
import { throwIfQueryFailed } from '../db-query-error.js'

interface RegistraRefeicaoArgs {
  meal_type?: string
  items?: Array<{ food_name: string; quantity_g?: number; kcal?: number }>
  replace?: boolean
}

function normalize(s: string): string {
  return s
    .toLowerCase()
    .normalize('NFD')
    .replace(/\p{Diacritic}/gu, '')
    .replace(/\s+/g, ' ')
    .trim()
}

export async function validateRegistraRefeicao(
  args: Record<string, unknown>,
  ctx: GuardContext,
): Promise<GuardResult> {
  const a = args as RegistraRefeicaoArgs
  const items = a.items ?? []

  // R1 — empty_items
  if (items.length === 0) {
    return {
      ok: false,
      reason: 'empty_items',
      retry_hint:
        'Você chamou registra_refeicao SEM items. Se o paciente não comeu nada, use marca_refeicao_pulada. Se comeu, liste os items na chamada.',
    }
  }

  // R2 — implausible_total_kcal (defesa contra alucinação)
  // kcal por item NEM SEMPRE vem no validated (depende do schema). Só checa
  // se LLM passou kcal explícito — caso contrário, espera calc do TACO.
  const itemsWithKcal = items.filter((it) => typeof it.kcal === 'number')
  if (itemsWithKcal.length > 0) {
    const total = itemsWithKcal.reduce((sum, it) => sum + Number(it.kcal ?? 0), 0)
    if (total > 5000) {
      return {
        ok: false,
        reason: 'implausible_total_kcal',
        details: { total_kcal: total, items_count: items.length },
        retry_hint: `Total de kcal somando os items deu ${total} kcal — implausivelmente alto. Confira as quantidades (provavelmente um item está com qty 10× maior que o real).`,
      }
    }
  }

  // R3 — duplicate_recent: já há meal_log pro mesmo (food_name, meal_type)
  // nos últimos 5min do mesmo user? Cobre LLM re-tentando após texto
  // ambíguo do paciente. NÃO aplica se trustedTap (paciente ciente).
  if (!ctx.trustedTap && a.meal_type && items.length > 0) {
    const fiveMinAgo = new Date(Date.now() - 5 * 60 * 1000).toISOString()
    const normalizedNames = items.map((it) => normalize(it.food_name))
    // biome-ignore lint/suspicious/noExplicitAny: supabase ServiceClient
    const sp = ctx.supabase as any
    const { data: recent, error: recentError } = await sp
      .from('meal_logs')
      .select('food_name, meal_type, created_at')
      .eq('user_id', ctx.userId)
      .eq('meal_type', a.meal_type)
      .gte('created_at', fiveMinAgo)
      .limit(20)
    throwIfQueryFailed(recentError, 'recent meal guard lookup failed')
    const recentRows =
      (recent as Array<{ food_name: string; meal_type: string }> | null) ?? []
    if (recentRows.length > 0) {
      const recentNames = new Set(recentRows.map((r) => normalize(r.food_name)))
      const overlap = normalizedNames.filter((n) => recentNames.has(n))
      // Considera duplicação se overlap >= 50% dos items propostos
      if (overlap.length > 0 && overlap.length / normalizedNames.length >= 0.5) {
        return {
          ok: false,
          reason: 'duplicate_recent',
          details: {
            meal_type: a.meal_type,
            overlap_count: overlap.length,
            proposed_count: normalizedNames.length,
            window_minutes: 5,
          },
          retry_hint: `Essa refeição (${a.meal_type}) já foi registrada nos últimos 5min com items semelhantes. Se o paciente está corrigindo, use replace=true. Se é refeição nova, confirme com ele antes de re-registrar.`,
        }
      }
    }
  }

  return { ok: true }
}
