import { createClinicalFullEntryRoutes } from './clinical-full-entry'
import { createClinicalFullRoutes } from './clinical-full-http'
import { createClinicalFullQuestionnaire } from './clinical-full-questionnaire'
import { createClinicalFullQuestionnaireRoutes } from './clinical-full-questionnaire-http'
import { createClinicalFullService } from './clinical-full-service'
import {
  createCurrentClinicalAdmission,
  createSupabaseLegacyClinicalAdmissionSource,
} from './current-clinical-admission'
import { captureCurrentClinicalState } from './current-clinical-state'
import type { MobileRouteRuntime } from './route'
import { createSupabaseClinicalFullRepository } from './supabase-clinical-full'
import { createSupabaseCurrentClinicalStateSource } from './supabase-current-clinical-state'
import { createSupabaseHealthHoldRepository } from './supabase-health-hold'
export function createCurrentClinicalFullEntryRuntimeRoutes(runtime?: MobileRouteRuntime) {
  return createClinicalFullEntryRoutes(
    {
      enabled: true,
      async admitLegacy(client, owner) {
        const current = createSupabaseCurrentClinicalStateSource(client)
        const before = await captureCurrentClinicalState(current, {
          userId: owner,
          mode: 'profile',
        })
        await createCurrentClinicalAdmission(
          createSupabaseLegacyClinicalAdmissionSource(client),
        ).establish(before, current)
      },
    },
    runtime,
  )
}
export function createCurrentClinicalQuestionnaireRuntimeRoutes() {
  return createClinicalFullQuestionnaireRoutes({
    enabled: true,
    createService: (client) =>
      createClinicalFullQuestionnaire({
        enabled: true,
        repository: createSupabaseClinicalFullRepository(client),
      }),
  })
}
export function createCurrentClinicalFullRuntimeRoutes() {
  return createClinicalFullRoutes({
    enabled: true,
    createService: (client) =>
      createClinicalFullService({
        enabled: true,
        repository: createSupabaseClinicalFullRepository(client),
      }),
    createHealthDependencies: (client) => ({
      enabled: true,
      repository: createSupabaseHealthHoldRepository(client),
    }),
  })
}
