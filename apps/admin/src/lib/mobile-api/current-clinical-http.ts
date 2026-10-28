/** Compatibility constructor with Today-only weekly enrichment. Mounted
 * non-Today readers use the pure read HTTP leaf and never trace weekly RPCs. */

import {
  type ClinicalHttpDependencies,
  createCurrentClinicalReadGetRoute,
} from './current-clinical-read-http'
import type { ClinicalReadEndpoint } from './current-clinical-read-model'
import type { MobileRouteRuntime } from './route'
import { strengthTrainingWeekEnabled } from './strength-training-week-switch'
import { loadTodayStrengthTrainingWeek } from './today-strength-training-week'

export type {
  ClinicalHttpDependencies,
  ClinicalHttpEffectScope,
} from './current-clinical-read-http'
export function createCurrentClinicalGetRoute(
  endpoint: ClinicalReadEndpoint,
  runtime: MobileRouteRuntime | undefined,
  dependencies: ClinicalHttpDependencies,
  enabled: () => boolean = strengthTrainingWeekEnabled,
) {
  return createCurrentClinicalReadGetRoute(
    endpoint,
    runtime,
    dependencies,
    endpoint === 'today'
      ? async (client, owner, data) => {
          const week = await loadTodayStrengthTrainingWeek(
            client,
            owner,
            data.current_protocol,
            enabled,
            true,
          )
          return week === undefined ? data : { ...data, strength_training_week: week }
        }
      : undefined,
  )
}
