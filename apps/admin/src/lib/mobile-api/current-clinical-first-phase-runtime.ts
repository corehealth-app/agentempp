import { createClinicalFirstPhaseRoutes } from './clinical-first-phase-http'
import { createClinicalFirstPhaseService } from './clinical-first-phase-service'
import { createSupabaseClinicalFirstPhaseRepository } from './supabase-clinical-first-phase'
export function createCurrentClinicalFirstPhaseRuntimeRoutes() {
  return createClinicalFirstPhaseRoutes({
    enabled: true,
    createService: (client) =>
      createClinicalFirstPhaseService({
        enabled: true,
        repository: createSupabaseClinicalFirstPhaseRepository(client),
      }),
  })
}
