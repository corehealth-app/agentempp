/** New admitted commands only. The caller must recover stored source/resolved/
 * effect first. This helper never captures meal source or closes/rewards days. */
import { createHash } from 'node:crypto'
import { isDeepStrictEqual } from 'node:util'
import type { ServiceClient } from '@mpp/db'
import type { MobileAuthContext } from './auth'
import { createClinicalDailyEffect } from './clinical-daily-effect'
import { clinicalDailyRepositoryError } from './clinical-daily-service'
import {
  type BoundConversationMealCommand,
  bindConversationCommand,
} from './conversation-command-contracts'
import {
  createCurrentClinicalAdmission,
  createSupabaseLegacyClinicalAdmissionSource,
} from './current-clinical-admission'
import type { ClinicalHttpDependencies } from './current-clinical-http'
import { createCurrentClinicalReadModel } from './current-clinical-read-model'
import { currentClinicalError, readCurrentClinicalState } from './current-clinical-state'
import { MobileApiError } from './http'
import { authenticatedReevaluationOwner } from './reevaluation-cycle-service'
import { createSupabaseCurrentClinicalStateSource } from './supabase-current-clinical-state'

export interface ConversationMealDayInitializer {
  initialize(auth: MobileAuthContext, command: BoundConversationMealCommand): Promise<void>
}
export interface ConversationMealDayPorts {
  createReadModel(
    client: ServiceClient,
  ): Pick<ReturnType<typeof createCurrentClinicalReadModel>, 'preflight'>
  createDailyEffect(options: {
    readonly nextOperationKey: () => string
  }): ClinicalHttpDependencies['applyDaily']
}
// Backend representation negotiation only: never fetched or supplied by HTTP.
const representation =
  'https://conversation.invalid/api/mobile/v1/today?clinical_policy=current_clinical_v1'
// UUIDv5(DNS, "performe.ai/conversation.meal.daily.v1"). Domain-specific UUIDv5
// names prevent collision with other server operation protocols.
const namespace = 'de8c8ce6-0dd4-5802-8ee3-77fc10fbebe8'
function dailyKey(owner: string, command: string, date: string): string {
  const bytes = createHash('sha1')
    .update(Buffer.from(namespace.replaceAll('-', ''), 'hex'))
    .update(`${owner}/${command}/${date}`, 'utf8')
    .digest()
    .subarray(0, 16)
  bytes[6] = (bytes.readUInt8(6) & 0x0f) | 0x50
  bytes[8] = (bytes.readUInt8(8) & 0x3f) | 0x80
  const hex = bytes.toString('hex')
  return `${hex.slice(0, 8)}-${hex.slice(8, 12)}-${hex.slice(12, 16)}-${hex.slice(16, 20)}-${hex.slice(20)}`
}
function freeze<T>(value: T): T {
  if (value !== null && typeof value === 'object') {
    for (const child of Object.values(value)) freeze(child)
    Object.freeze(value)
  }
  return value
}
function unavailable(): never {
  throw new MobileApiError(
    503,
    'conversation_meal_day_unavailable',
    'Meal day initialization is unavailable',
  )
}
function sanitized(error: unknown): never {
  if (error instanceof MobileApiError) {
    for (const kind of ['invalid_response', 'unavailable', 'changed', 'busy'] as const) {
      const safe = currentClinicalError(kind)
      if (error.code === safe.code && error.status === safe.status) throw safe
    }
    for (const kind of ['changed', 'busy', 'unavailable'] as const) {
      const safe = clinicalDailyRepositoryError(kind)
      if (error.code === safe.code && error.status === safe.status) throw safe
    }
    if (error.code === 'mobile_reevaluation_identity_invalid' && error.status === 403)
      throw new MobileApiError(
        403,
        'mobile_reevaluation_identity_invalid',
        'Authenticated patient required',
      )
    if (error.code === 'conversation_meal_day_owner_mismatch' && error.status === 403)
      throw new MobileApiError(
        403,
        'conversation_meal_day_owner_mismatch',
        'Authenticated command owner required',
      )
  }
  return unavailable()
}
export function createConversationMealDayInitializer(
  db: ServiceClient,
  ports?: Partial<ConversationMealDayPorts>,
): ConversationMealDayInitializer {
  const createReadModel =
    ports?.createReadModel?.bind(ports) ??
    ((client: ServiceClient) =>
      createCurrentClinicalReadModel(
        client,
        createSupabaseCurrentClinicalStateSource(client),
        undefined,
        {
          admission: createCurrentClinicalAdmission(
            createSupabaseLegacyClinicalAdmissionSource(client),
          ),
        },
      ))
  const createDailyEffect = ports?.createDailyEffect?.bind(ports) ?? createClinicalDailyEffect
  return Object.freeze({
    async initialize(
      originalAuth: MobileAuthContext,
      originalCommand: BoundConversationMealCommand,
    ): Promise<void> {
      try {
        const auth = freeze(structuredClone(originalAuth)),
          owner = authenticatedReevaluationOwner(auth).toLowerCase(),
          raw = structuredClone(originalCommand)
        const command = bindConversationCommand(raw.ownerId, `cmsg1:${raw.commandId}`, raw.command)
        if (!isDeepStrictEqual(raw, command)) return unavailable()
        if (command.ownerId !== owner)
          throw new MobileApiError(
            403,
            'conversation_meal_day_owner_mismatch',
            'Authenticated command owner required',
          )
        const model = createReadModel(db),
          preflight = model.preflight.bind(model)
        const rawAdmission = structuredClone(await preflight(auth, representation, 'today'))
        if (rawAdmission.owner.toLowerCase() !== owner || rawAdmission.compatible !== true)
          throw currentClinicalError('invalid_response')
        const state = readCurrentClinicalState(rawAdmission.state, owner)
        const admission = freeze({ owner, compatible: true, state })
        const key = dailyKey(owner, command.commandId, state.date)
        const applyDaily = createDailyEffect(Object.freeze({ nextOperationKey: () => key }))
        await applyDaily(Object.freeze({ auth, supabase: db, url: representation, admission }))
      } catch (error) {
        return sanitized(error)
      }
    },
  })
}
