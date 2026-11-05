import type { ServiceClient } from '@mpp/db'
import type { MobileAuthContext } from './auth'
import {
  currentClinicalReadBinding,
  projectCurrentClinicalPublicPolicy,
} from './current-clinical-read-model'
import { captureCurrentClinicalState } from './current-clinical-state'
import { MobileApiError } from './http'
import {
  createNutritionWindowCapture,
  type NutritionWindowReadPort,
} from './nutrition-window-repository'
import { readNutritionWindow } from './nutrition-window-service'
import { authenticatedReevaluationOwner } from './reevaluation-cycle-service'
import { createSupabaseCurrentClinicalStateSource } from './supabase-current-clinical-state'

/** Inert composition. No Auth bootstrap, clinical admission/application, closer
 * or domain writer is exposed to this new GET. Observations grant no writes. */
export function createNutritionWindowReadService(client: ServiceClient) {
  const source = createSupabaseCurrentClinicalStateSource(client)
  return Object.freeze({
    async read(auth: MobileAuthContext, selectedDate?: string) {
      const who = structuredClone(auth),
        owner = authenticatedReevaluationOwner(who)
      const capture = createNutritionWindowCapture(
        client as unknown as NutritionWindowReadPort,
        owner,
      )
      return readNutritionWindow(who, selectedDate, {
        capture,
        async observe() {
          const state = await captureCurrentClinicalState(source, {
            userId: owner,
            mode: 'profile',
          })
          if (state.epoch === null)
            throw new MobileApiError(
              503,
              'nutrition_window_unavailable',
              'The current clinical scope is unavailable',
            )
          return {
            authUserID: who.authUserId,
            ownerID: owner,
            epoch: state.epoch,
            timezone: state.timezone,
            currentLocalDate: state.date,
            observedAt: state.observed_at,
            binding: currentClinicalReadBinding(state),
            policy: projectCurrentClinicalPublicPolicy(state),
          }
        },
      })
    },
  })
}
