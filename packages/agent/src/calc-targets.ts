/**
 * Carrega user_profile + computa targets (atalho de hot path).
 *
 * A REGRA de cálculo (computeDailyTargets) vive no engine @mpp/core/engine/targets
 * — aqui fica só o I/O (ler o perfil do banco). Re-exportamos computeDailyTargets
 * pra compatibilidade de imports existentes via @mpp/agent.
 */
import { computeDailyTargets } from '@mpp/core'
import type { CalcConfig, DailyTargets } from '@mpp/core'

export { computeDailyTargets } from '@mpp/core'
export type { DailyTargets, ProfileRow } from '@mpp/core'

export async function loadDailyTargets(
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
// biome-ignore lint/suspicious/noExplicitAny: legacy — see ACT-1 prevention plan 2026-06-16
  svc: any,
  userId: string,
  config: CalcConfig,
): Promise<DailyTargets> {
  const { data } = await svc
    .from('user_profiles')
    .select(
      'sex, birth_date, height_cm, weight_kg, body_fat_percent, activity_level, training_frequency, water_intake, hunger_level, current_protocol, goal_type, goal_value, deficit_level',
    )
    .eq('user_id', userId)
    .maybeSingle()
  return computeDailyTargets(data ?? null, config)
}
