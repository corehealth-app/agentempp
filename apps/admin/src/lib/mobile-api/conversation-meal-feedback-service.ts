/** Optional immutable ORIGINAL/historical enrichment after mandatory SQL meal
 * success. This service is not current clinical presentation or registration. */
import { isDeepStrictEqual } from 'node:util'
import type { RegistrationFeedback } from '@mpp/agent/registration-feedback'
import {
  parseRegistrationFeedbackV2,
  prepareRegistrationFeedbackV2,
  type RegistrationFeedbackV2,
} from '@mpp/agent/registration-feedback-v2'
import type { ServiceClient } from '@mpp/db'
import type { MobileAuthContext } from './auth'
import {
  type BoundConversationMealCommand,
  bindConversationCommand,
} from './conversation-command-contracts'
import {
  type ConversationMealEffectReceipt,
  type ConversationMealFeedbackRead,
  type ConversationMealFeedbackStore,
  createSupabaseConversationMealFeedbackStore,
  parseConversationMealEffectReceipt,
} from './conversation-meal-feedback-store'
import { freezeInterpretation } from './conversation-meal-interpretation-contracts'
import { projectCurrentClinicalPublicPolicy } from './current-clinical-read-model'
import { authenticatedReevaluationOwner } from './reevaluation-cycle-service'
import { parseRegistrationFeedback } from './registration-feedback-receipt'
import {
  loadFeedbackV2ClinicalContext,
  proveFeedbackV2Day,
} from './registration-feedback-v2-clinical'
import { parseFeedbackV2Capture } from './registration-feedback-v2-store'

export type OriginalConversationMealFeedback = RegistrationFeedback | RegistrationFeedbackV2
export interface ConversationMealOriginalFeedbackInput {
  readonly auth: MobileAuthContext
  readonly command: BoundConversationMealCommand
  /** Mandatory effect receipt from the actual private SQL writer adapter. */
  readonly receipt: unknown
}
export interface ConversationMealFeedbackService {
  ensureOriginal(
    input: ConversationMealOriginalFeedbackInput,
  ): Promise<OriginalConversationMealFeedback | null>
  /** Receipt-only: never creates feedback or loads current clinical context. */
  readOriginal(
    input: ConversationMealOriginalFeedbackInput,
  ): Promise<OriginalConversationMealFeedback | null>
}
export interface ConversationMealFeedbackServiceDependencies {
  store?: ConversationMealFeedbackStore
  loadClinical?: typeof loadFeedbackV2ClinicalContext
}
function binding(original: ConversationMealOriginalFeedbackInput) {
  const raw = structuredClone(original),
    owner = authenticatedReevaluationOwner(raw.auth)
  const command = bindConversationCommand(
    owner,
    `cmsg1:${raw.command.commandId}`,
    raw.command.command,
  )
  if (!isDeepStrictEqual(command, raw.command)) throw new Error('Invalid original meal binding')
  const receipt = parseConversationMealEffectReceipt(raw.receipt, command)
  return freezeInterpretation({ auth: raw.auth, command, receipt })
}
function originalFeedback(
  raw: unknown,
  b: { command: BoundConversationMealCommand; receipt: ConversationMealEffectReceipt },
  version: 'legacy' | 'v2',
): OriginalConversationMealFeedback {
  const value = structuredClone(raw),
    identity = {
      userId: b.command.ownerId,
      registrationId: b.receipt.registration_id,
      kind: 'meal' as const,
    }
  if (version === 'legacy') return freezeInterpretation(parseRegistrationFeedback(value, identity))
  const feedback = parseRegistrationFeedbackV2(value, identity)
  if (
    feedback.local_date !== b.receipt.local_date ||
    feedback.registration.kind !== 'meal' ||
    feedback.registration.meal_kind !== b.receipt.meal_type ||
    !isDeepStrictEqual(
      [...feedback.registration.items.map((item) => item.log_id)].sort(),
      [...b.receipt.log_ids].sort(),
    )
  )
    throw new Error('Invalid original meal feedback')
  return freezeInterpretation(feedback)
}
function fromRead(
  value: ConversationMealFeedbackRead,
  b: ReturnType<typeof binding>,
): OriginalConversationMealFeedback | null {
  return value.action === 'available' || value.action === 'legacy'
    ? originalFeedback(value.feedback, b, value.action === 'legacy' ? 'legacy' : 'v2')
    : null
}

export function createSupabaseConversationMealFeedbackService(
  db: ServiceClient,
  dependencies: ConversationMealFeedbackServiceDependencies = {},
): ConversationMealFeedbackService {
  try {
    const source = dependencies.store ?? createSupabaseConversationMealFeedbackStore(db)
    // Capture callback identities once. Factory construction performs no I/O.
    const store = Object.freeze({
      readReceipt: source.readReceipt.bind(source),
      readSource: source.readSource.bind(source),
      commit: source.commit.bind(source),
    })
    const loadClinical = dependencies.loadClinical ?? loadFeedbackV2ClinicalContext
    return Object.freeze({
      async readOriginal(
        input: ConversationMealOriginalFeedbackInput,
      ): Promise<OriginalConversationMealFeedback | null> {
        try {
          const b = binding(input)
          return fromRead(
            await store.readReceipt(Object.freeze({ command: b.command, receipt: b.receipt })),
            b,
          )
        } catch {
          return null
        }
      },
      async ensureOriginal(
        input: ConversationMealOriginalFeedbackInput,
      ): Promise<OriginalConversationMealFeedback | null> {
        try {
          const b = binding(input)
          const existing = await store.readReceipt(
            Object.freeze({ command: b.command, receipt: b.receipt }),
          )
          if (existing.action !== 'absent') return fromRead(existing, b)
          const saved = await store.readSource(b.command)
          if (saved.action !== 'available') return null
          const sourceReceipt = parseConversationMealEffectReceipt(saved.receipt, b.command)
          if (!isDeepStrictEqual(sourceReceipt, b.receipt)) return null
          const identity = {
            userId: b.command.ownerId,
            registrationId: b.receipt.registration_id,
            kind: 'meal' as const,
          }
          const observation = parseFeedbackV2Capture(
            structuredClone(saved.originalObservation.context),
            identity,
          )
          if (!isDeepStrictEqual(observation, saved.originalObservation)) return null
          const proposal = observation.context.confirmed.proposal
          if (
            !proposal ||
            typeof proposal !== 'object' ||
            Array.isArray(proposal) ||
            proposal.command_protocol !== 'conversation.command.v1' ||
            proposal.command_id !== b.command.commandId ||
            proposal.source_provider_message_id !== b.receipt.provider_key ||
            proposal.source_timestamp !== b.receipt.consumed_at ||
            proposal.source_timezone !== b.receipt.timezone ||
            proposal.mealType !== b.receipt.meal_type ||
            observation.facts.localDate !== b.receipt.local_date ||
            !isDeepStrictEqual([...observation.facts.logIds].sort(), [...b.receipt.log_ids].sort())
          )
            return null
          // This is an ORIGINAL captured policy, never a newly minted current
          // authority. Any failure to prove current/day equivalence withholds
          // day/block numbers while retaining that historical factual receipt.
          const originalPolicy = projectCurrentClinicalPublicPolicy(observation.clinical)
          let officialDay: Awaited<
            ReturnType<typeof loadFeedbackV2ClinicalContext>
          >['officialDay'] = null
          try {
            const clinical = structuredClone(await loadClinical(db, b.auth, observation))
            if (isDeepStrictEqual(clinical.policy, originalPolicy) && clinical.officialDay !== null)
              officialDay = proveFeedbackV2Day(observation, clinical.officialDay)
          } catch {
            /* Optional current/day proof is unavailable or changed. */
          }
          const locale = observation.clinical.body.locale
          const feedback = prepareRegistrationFeedbackV2({
            registrationId: b.receipt.registration_id,
            localDate: observation.facts.localDate,
            locale: locale === 'en-US' ? 'en-US' : 'pt-BR',
            registration: observation.facts.registration,
            policy: originalPolicy,
            officialDay,
            preferencesKnown: false,
          })
          try {
            const result = await store.commit({ command: b.command, receipt: b.receipt, feedback })
            if (
              result.action === 'committed' ||
              result.action === 'replay' ||
              result.action === 'legacy'
            )
              return originalFeedback(
                result.feedback,
                b,
                result.action === 'legacy' ? 'legacy' : 'v2',
              )
            return null
          } catch {
            // Unknown seal outcome: exactly one immutable read. No retry,
            // recapture, clinical reload, calculation, registration or LLM call.
            return fromRead(
              await store.readReceipt(Object.freeze({ command: b.command, receipt: b.receipt })),
              b,
            )
          }
        } catch {
          // Optional enrichment must never invalidate the already-saved meal.
          // No provider/health detail is returned or logged.
          return null
        }
      },
    })
  } catch {
    // Even construction of optional enrichment cannot change saved success.
    return Object.freeze({ readOriginal: async () => null, ensureOriginal: async () => null })
  }
}
