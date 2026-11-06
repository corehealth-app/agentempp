/** Private request-bound composition only. No route, session, provider factory,
 * environment flag or public activation is installed by this leaf. */
import { isDeepStrictEqual } from 'node:util'
import type { ServiceClient } from '@mpp/db'
import type { MobileAuthContext } from './auth'
import {
  assertConversationReadonlyNonAdmin,
  type ConversationCurrentScopeDependencies,
  createConversationCurrentScope,
  createConversationReadonlyAuth,
  parseConversationReadonlyIdentity,
  parseConversationReadonlyPatient,
} from './conversation-current-scope'
import type { ConversationFeedbackPresentationNegotiation } from './conversation-feedback-presentation-negotiation'
import {
  type BoundConversationIntake,
  pinConversationIntake,
} from './conversation-intake-contracts'
import {
  type ConversationIntakeDriverPorts,
  type ConversationIntakeLookup,
  createConversationIntakeDriver,
} from './conversation-intake-driver'
import {
  type ConversationIntakeRecoveryRPCPort,
  createConversationIntakeRecoveryStore,
} from './conversation-intake-recovery-store'
import {
  type ConversationIntakeRPCPort,
  createConversationIntakeStore,
} from './conversation-intake-store'
import { conversationMealCommandsEnabled } from './conversation-meal-command-routes'
import { createConversationMealCommandService } from './conversation-meal-command-service'
import { conversationWorkoutCommandsEnabled } from './conversation-workout-command-routes'
import { createConversationWorkoutCommandService } from './conversation-workout-command-service'
import { workoutHash, workoutSnapshot, workoutUUID } from './conversation-workout-contracts'
import { captureCurrentClinicalState } from './current-clinical-state'
import { MobileApiError } from './http'
import { authenticatedReevaluationOwner } from './reevaluation-cycle-service'
import { createSupabaseCurrentClinicalStateSource } from './supabase-current-clinical-state'

export interface ConversationIntakeRuntimePorts extends ConversationCurrentScopeDependencies {
  readonly createRouter: ConversationIntakeDriverPorts['createRouter']
  /** Trusted server policy only. Absence is OFF; no request/header chooses it. */
  readonly enabled?: () => boolean
  readonly mealEnabled?: () => boolean
  readonly workoutEnabled?: () => boolean
}
function unavailable() {
  return new MobileApiError(503, 'conversation_intake_unavailable', 'Intake is unavailable')
}
function changed() {
  return new MobileApiError(409, 'conversation_intake_changed', 'Original intake has changed')
}
function authFailure(status: number, code: string) {
  return new MobileApiError(status, code, 'Original authenticated scope is unavailable')
}
// Preserve the existing observer's typed mandatory failures even when a child
// service owns an internal scope. An ordinary SDK failure is still reconciled
// by the driver's existing read-only recovery, without another submit.
const scopeRefusalCodes = new Set([
  'missing_access_token',
  'invalid_access_token',
  'email_not_confirmed',
  'patient_admin_account_conflict',
  'patient_profile_unavailable',
  'patient_account_inactive',
  'conversation_patient_changed',
  'conversation_scope_changed',
  'conversation_epoch_changed',
  'conversation_scope_unavailable',
  'mobile_current_clinical_invalid_response',
  'mobile_current_clinical_unavailable',
  'mobile_current_clinical_changed',
  'mobile_current_clinical_busy',
])
export function createConversationIntakeRuntime(
  db: ServiceClient,
  originalAuth: MobileAuthContext,
  originalLookup: ConversationIntakeLookup,
  ports: ConversationIntakeRuntimePorts,
) {
  const enabled = ports.enabled?.bind(ports) ?? (() => false),
    mealEnabled = ports.mealEnabled?.bind(ports) ?? conversationMealCommandsEnabled,
    workoutEnabled = ports.workoutEnabled?.bind(ports) ?? conversationWorkoutCommandsEnabled
  let closed: MobileApiError | null = null
  function available() {
    if (closed) throw closed
    try {
      if (enabled() !== true || mealEnabled() !== true || workoutEnabled() !== true)
        throw unavailable()
    } catch {
      closed = unavailable()
      throw closed
    }
  }
  available()
  if (typeof ports.createRouter !== 'function') throw unavailable()
  const makeRouter = ports.createRouter.bind(ports),
    auth = workoutSnapshot(originalAuth),
    id = workoutSnapshot(originalLookup),
    owner = authenticatedReevaluationOwner(auth)
  if (
    !isDeepStrictEqual(Object.keys(id).sort(), ['epoch', 'inputHash', 'intakeId', 'ownerId']) ||
    owner !== id.ownerId
  )
    throw changed()
  workoutUUID.parse(id.ownerId)
  workoutUUID.parse(id.intakeId)
  workoutHash.parse(id.inputHash)
  workoutUUID.parse(id.epoch)
  const a = ports.auth ?? createConversationReadonlyAuth(db),
    verifyAccessToken = a.verifyAccessToken.bind(a),
    loadPatient = a.loadPatient.bind(a),
    isAdmin = a.isAdmin.bind(a),
    c = ports.clinical ?? createSupabaseCurrentClinicalStateSource(db),
    capture = c.capture.bind(c),
    dependencies = Object.freeze({
      auth: Object.freeze({
        async verifyAccessToken(token: string) {
          return checkedAuth(async () => {
            if (token !== auth.accessToken) throw changed()
            let raw: unknown
            try {
              raw = workoutSnapshot(await verifyAccessToken(token))
            } catch {
              throw authFailure(401, 'invalid_access_token')
            }
            const value = parseConversationReadonlyIdentity(raw)
            if (value.id !== auth.authUserId) throw changed()
            return workoutSnapshot(value)
          })
        },
        async loadPatient(subject: string) {
          return checkedAuth(async () => {
            if (subject !== auth.authUserId) throw changed()
            let raw: unknown
            try {
              raw = workoutSnapshot(await loadPatient(subject))
            } catch {
              throw authFailure(503, 'patient_profile_unavailable')
            }
            const value = parseConversationReadonlyPatient(raw, subject)
            if (value.id !== owner) throw authFailure(409, 'conversation_patient_changed')
            return workoutSnapshot(value)
          })
        },
        async isAdmin(subject: string) {
          return checkedAuth(async () => {
            if (subject !== auth.authUserId) throw changed()
            let value: boolean
            try {
              value = await isAdmin(subject)
            } catch {
              throw authFailure(503, 'patient_profile_unavailable')
            }
            assertConversationReadonlyNonAdmin(value)
            return false
          })
        },
      }),
      clinical: Object.freeze({
        async capture(request: Parameters<typeof capture>[0]) {
          if (closed) throw closed
          try {
            available()
            if (
              request.userId !== id.ownerId ||
              request.mode !== 'profile' ||
              request.expectedEpoch !== id.epoch
            )
              throw changed()
            // The real typed services keep their own child scope. Share this
            // sticky capability/clinical boundary too, so their internal RPC
            // guards cannot continue after a refusal inside the child service.
            const state = workoutSnapshot(await captureCurrentClinicalState({ capture }, request))
            available()
            return state
          } catch (error) {
            closed ??= error instanceof MobileApiError ? error : unavailable()
            throw closed
          }
        },
      }),
    }),
    binding = workoutSnapshot({ authUserId: auth.authUserId, ...id }),
    lane = createConversationCurrentScope(db, auth, binding, dependencies)
  async function checkedAuth<T>(read: () => Promise<T>): Promise<T> {
    available()
    try {
      const value = workoutSnapshot(await read())
      available()
      return value
    } catch (error) {
      closed ??=
        error instanceof MobileApiError ? error : authFailure(503, 'conversation_scope_unavailable')
      throw closed
    }
  }
  async function observe(identity: ConversationIntakeLookup) {
    if (closed) throw closed
    try {
      if (!isDeepStrictEqual(workoutSnapshot(identity), id)) throw changed()
      available()
      const state = workoutSnapshot(await lane.observe(binding))
      available()
      return state
    } catch (error) {
      closed ??= error instanceof MobileApiError ? error : unavailable()
      throw closed
    }
  }
  async function typed<T>(call: () => PromiseLike<T>): Promise<T> {
    try {
      const result = workoutSnapshot(await call())
      if (closed) throw closed
      return result
    } catch (error) {
      if (closed) throw closed
      if (error instanceof MobileApiError && scopeRefusalCodes.has(error.code)) closed = error
      throw closed ?? error
    }
  }
  // Generated DB types do not yet declare these five names. Keep that transport
  // cast local and narrow; store codecs still validate every physical response.
  const rpc = db.rpc.bind(db) as unknown as ConversationIntakeRPCPort['rpc'],
    scopePort = Object.freeze({
      async checkCurrentScope(identity: ConversationIntakeLookup) {
        await observe(identity)
        return true
      },
    }),
    store = createConversationIntakeStore({ rpc }, scopePort),
    recoveryRPC = db.rpc.bind(db) as unknown as ConversationIntakeRecoveryRPCPort['rpc'],
    recovery = createConversationIntakeRecoveryStore({ rpc: recoveryRPC }, scopePort),
    // The existing meal facade resumes prepared effects through several RPCs.
    // Its RPCs are awaited (not builder-chained). Guard the request-owned client
    // seam as well as the outer service, preserving the real writers/codecs.
    // observe uses the original client/clinical source, so it cannot recurse.
    physicalRpc = db.rpc.bind(db),
    mealRpc = async (...parameters: Parameters<ServiceClient['rpc']>) => {
      const [name, rawArgs, rawOptions] = parameters,
        args = rawArgs === undefined ? undefined : workoutSnapshot(rawArgs),
        options = rawOptions === undefined ? undefined : workoutSnapshot(rawOptions)
      await observe(id)
      try {
        const value = workoutSnapshot(
          await (parameters.length > 2
            ? physicalRpc(name, args, options)
            : parameters.length > 1
              ? physicalRpc(name, args)
              : physicalRpc(name)),
        )
        await observe(id)
        return value
      } catch (error) {
        await observe(id)
        throw error
      }
    },
    mealDb = new Proxy(db, {
      get(target, key) {
        if (key === 'rpc') return mealRpc
        const value = Reflect.get(target, key, target)
        return typeof value === 'function' ? value.bind(target) : value
      },
    }),
    meal = createConversationMealCommandService(mealDb, dependencies),
    workout = createConversationWorkoutCommandService(db, dependencies),
    driver = createConversationIntakeDriver({
      store,
      recovery,
      scope: { observeCurrentScope: observe },
      createRouter: makeRouter,
      domains: {
        meal: {
          submit: (child, negotiation) =>
            typed(() =>
              meal.submit(auth, `cmsg1:${child.command_id}`, child.input, child.epoch, negotiation),
            ),
          read: (child, negotiation) =>
            typed(() =>
              meal.read(auth, child.command_id, child.input_hash, child.epoch, negotiation),
            ),
        },
        workout: {
          submit: (child, negotiation) =>
            typed(() =>
              workout.submit(
                auth,
                `cmsg1:${child.command_id}`,
                child.input,
                child.epoch,
                negotiation,
              ),
            ),
          read: (child, negotiation) =>
            typed(() =>
              workout.read(auth, child.command_id, child.input_hash, child.epoch, negotiation),
            ),
        },
      },
    })
  function negotiation(value: ConversationFeedbackPresentationNegotiation) {
    if (value !== 'legacy' && value !== '2') throw changed()
    return value
  }
  return Object.freeze({
    async submit(
      original: BoundConversationIntake,
      selected: ConversationFeedbackPresentationNegotiation = 'legacy',
    ) {
      available()
      let command: BoundConversationIntake
      try {
        command = pinConversationIntake(original)
        if (
          command.ownerId !== id.ownerId ||
          command.intakeId !== id.intakeId ||
          command.inputHash !== id.inputHash
        )
          throw changed()
      } catch {
        closed = changed()
        throw closed
      }
      return driver.submit(command, id.epoch, negotiation(selected))
    },
    async read(selected: ConversationFeedbackPresentationNegotiation = 'legacy') {
      available()
      return driver.read(id, negotiation(selected))
    },
  })
}
