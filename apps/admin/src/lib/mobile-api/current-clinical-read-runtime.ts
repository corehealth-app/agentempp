import type { ServiceClient } from '@mpp/db'
import { createClinicalCloseDaysEffect } from './clinical-close-days-effect'
import { createClinicalDailyEffect } from './clinical-daily-effect'
import {
  type CurrentClinicalAdmission,
  createCurrentClinicalAdmission,
  createSupabaseLegacyClinicalAdmissionSource,
} from './current-clinical-admission'
import type { ClinicalHttpDependencies } from './current-clinical-http'
import { createCurrentClinicalReadModel } from './current-clinical-read-model'
import { createSupabaseCurrentClinicalStateSource } from './supabase-current-clinical-state'
/** Called only by an explicitly selected current route. Construction is inert. */
export function createCurrentClinicalRuntimeReadDependencies(
  admission?: CurrentClinicalAdmission,
): ClinicalHttpDependencies {
  return Object.freeze({
    createReadModel: (client: ServiceClient) =>
      createCurrentClinicalReadModel(
        client,
        createSupabaseCurrentClinicalStateSource(client),
        undefined,
        {
          admission:
            admission ??
            createCurrentClinicalAdmission(createSupabaseLegacyClinicalAdmissionSource(client)),
        },
      ),
    applyDaily: createClinicalDailyEffect(),
    closeDays: createClinicalCloseDaysEffect(),
  })
}
