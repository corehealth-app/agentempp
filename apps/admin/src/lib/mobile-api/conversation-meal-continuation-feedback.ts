/** Optional frozen enrichment for an ACTUAL linked child effect. It never
 * admits, calculates or registers food, recaptures its original or grants Auth. */
import { isDeepStrictEqual } from 'node:util'
import {
  parseRegistrationFeedbackV2,
  prepareRegistrationFeedbackV2,
} from '@mpp/agent/registration-feedback-v2'
import type { Json, ServiceClient } from '@mpp/db'
import { z } from 'zod'
import type { MobileAuthContext } from './auth'
import {
  type ConversationMealContinuationFeedbackBinding,
  detachConversationContinuationReadJson,
  parseConversationMealContinuationFeedbackBinding,
} from './conversation-meal-continuation-read-contracts'
import {
  type ConversationMealFeedbackPresentation,
  isHistoricalMealFeedbackRestricted,
  renderHistoricalMealFeedbackSections,
} from './conversation-meal-feedback-presentation'
import type { OriginalConversationMealFeedback } from './conversation-meal-feedback-service'
import { freezeInterpretation } from './conversation-meal-interpretation-contracts'
import { conversationJournalInstant } from './conversation-meal-journal-store'
import {
  currentClinicalReadBinding,
  projectCurrentClinicalPublicPolicy,
} from './current-clinical-read-model'
import {
  type CurrentClinicalStateSource,
  captureCurrentClinicalState,
  readCurrentClinicalState,
} from './current-clinical-state'
import { authenticatedReevaluationOwner } from './reevaluation-cycle-service'
import { parseRegistrationFeedback } from './registration-feedback-receipt'
import {
  loadFeedbackV2ClinicalContext,
  proveFeedbackV2Day,
} from './registration-feedback-v2-clinical'
import { parseFeedbackV2Capture } from './registration-feedback-v2-store'
import { createSupabaseCurrentClinicalStateSource } from './supabase-current-clinical-state'

export interface ConversationMealContinuationFeedbackInput {
  readonly auth: MobileAuthContext
  readonly binding: unknown
}
export interface ConversationMealContinuationFeedbackScope {
  readonly auth: MobileAuthContext
  readonly binding: ConversationMealContinuationFeedbackBinding
}
export interface ConversationMealContinuationFeedbackDependencies {
  /** Supplied by the actual authenticated request/session owner. IDs and this
   * pure historical binding never manufacture an observation or capability. */
  checkCurrentScope(scope: ConversationMealContinuationFeedbackScope): boolean | Promise<boolean>
  loadClinical?: typeof loadFeedbackV2ClinicalContext
  clinicalSource?: CurrentClinicalStateSource
}
export interface ConversationMealContinuationFeedbackService {
  readOriginal(
    input: ConversationMealContinuationFeedbackInput,
  ): Promise<OriginalConversationMealFeedback | null>
  ensureOriginal(
    input: ConversationMealContinuationFeedbackInput,
  ): Promise<OriginalConversationMealFeedback | null>
  readHistorical(
    input: ConversationMealContinuationFeedbackInput,
  ): Promise<ConversationMealFeedbackPresentation | null>
}
const no = (): never => {
  throw new Error('Linked original feedback unavailable')
}
const empty = z
  .object({ action: z.enum(['absent', 'stale_epoch', 'event_conflict', 'source_conflict']) })
  .strict()
const readResult = z.discriminatedUnion('action', [
  z.object({ action: z.literal('available'), feedback: z.unknown() }).strict(),
  z.object({ action: z.literal('legacy'), feedback: z.unknown() }).strict(),
  empty,
])
function envelope(raw: unknown): unknown {
  if (!raw || typeof raw !== 'object' || Array.isArray(raw)) return no()
  const d = Object.getOwnPropertyDescriptors(raw),
    allowed = new Set(['data', 'error', 'success', 'count', 'status', 'statusText'])
  for (const key of Reflect.ownKeys(d)) {
    if (typeof key !== 'string' || !allowed.has(key)) return no()
    const f = d[key]
    if (!f?.enumerable || !('value' in f)) return no()
  }
  if (!d.data || !d.error || d.error.value !== null || (d.success && d.success.value !== true))
    return no()
  return detachConversationContinuationReadJson(d.data.value)
}
function scope(
  input: ConversationMealContinuationFeedbackInput,
): ConversationMealContinuationFeedbackScope {
  const raw = detachConversationContinuationReadJson(
    input,
  ) as unknown as ConversationMealContinuationFeedbackInput
  if (
    Object.keys(raw).length !== 2 ||
    !Object.hasOwn(raw, 'auth') ||
    !Object.hasOwn(raw, 'binding')
  )
    return no()
  const auth = raw.auth,
    binding = parseConversationMealContinuationFeedbackBinding(raw.binding)
  if (authenticatedReevaluationOwner(auth) !== binding.childBinding.owner_id) return no()
  return freezeInterpretation({ auth, binding })
}
function feedback(
  raw: unknown,
  s: ConversationMealContinuationFeedbackScope,
  legacy: boolean,
): OriginalConversationMealFeedback {
  const e = s.binding.receipt,
    identity = { userId: e.owner_id, registrationId: e.registration_id, kind: 'meal' as const }
  if (legacy) {
    const value = parseRegistrationFeedback(raw, identity)
    if (value.day && value.day.local_date !== e.local_date) return no()
    return freezeInterpretation(value)
  }
  const value = parseRegistrationFeedbackV2(raw, identity)
  if (
    value.local_date !== e.local_date ||
    value.registration.kind !== 'meal' ||
    value.registration.meal_kind !== e.meal_type ||
    !isDeepStrictEqual(value.registration.items.map((x) => x.log_id).sort(), [...e.log_ids].sort())
  )
    return no()
  return freezeInterpretation(value)
}

export function createSupabaseConversationMealContinuationFeedback(
  db: ServiceClient,
  dependencies: ConversationMealContinuationFeedbackDependencies,
): ConversationMealContinuationFeedbackService {
  try {
    const rpc = db.rpc.bind(db)
    if (typeof dependencies.checkCurrentScope !== 'function') return no()
    const check = dependencies.checkCurrentScope.bind(dependencies)
    const loadClinical = dependencies.loadClinical ?? loadFeedbackV2ClinicalContext
    const source = dependencies.clinicalSource ?? createSupabaseCurrentClinicalStateSource(db)
    const capture = Object.freeze({ capture: source.capture.bind(source) })
    const current = async (s: ConversationMealContinuationFeedbackScope) => {
      if ((await check(s)) !== true) return no()
    }
    async function read(s: ConversationMealContinuationFeedbackScope) {
      await current(s)
      const e = s.binding.receipt
      const value = readResult.parse(
        envelope(
          await rpc('read_conversation_meal_feedback_v2', {
            p_user_id: e.owner_id,
            p_command_id: e.command_id,
          }),
        ),
      )
      await current(s)
      return value.action === 'available' || value.action === 'legacy'
        ? { action: value.action, feedback: feedback(value.feedback, s, value.action === 'legacy') }
        : value
    }
    async function readOriginal(s: ConversationMealContinuationFeedbackScope) {
      const r = await read(s)
      return 'feedback' in r ? r.feedback : null
    }
    return Object.freeze({
      async readOriginal(input: ConversationMealContinuationFeedbackInput) {
        try {
          return await readOriginal(scope(input))
        } catch {
          return null
        }
      },
      async ensureOriginal(input: ConversationMealContinuationFeedbackInput) {
        try {
          const s = scope(input),
            b = s.binding,
            e = b.receipt,
            existing = await read(s)
          if (existing.action !== 'absent') return 'feedback' in existing ? existing.feedback : null
          await current(s)
          const raw = z
            .discriminatedUnion('action', [
              z
                .object({
                  action: z.literal('available'),
                  receipt: z.unknown(),
                  context: z.unknown(),
                })
                .strict(),
              z
                .object({
                  action: z.literal('unavailable'),
                  reason: z.literal('original_context_unavailable'),
                  receipt: z.unknown(),
                })
                .strict(),
              empty,
            ])
            .parse(
              envelope(
                await rpc('read_conversation_meal_feedback_source', {
                  p_user_id: e.owner_id,
                  p_command_id: e.command_id,
                }),
              ),
            )
          await current(s)
          if (raw.action !== 'available') return null
          const actual = parseConversationMealContinuationFeedbackBinding({
            ...b,
            receipt: raw.receipt,
          })
          if (!isDeepStrictEqual(actual, b)) return null
          const observation = parseFeedbackV2Capture(raw.context, {
            userId: e.owner_id,
            registrationId: e.registration_id,
            kind: 'meal',
          })
          const p = observation.context.confirmed.proposal
          if (
            !isDeepStrictEqual(observation.context, raw.context) ||
            observation.clinical.epoch !== e.epoch ||
            !p ||
            typeof p !== 'object' ||
            Array.isArray(p) ||
            p.command_protocol !== 'conversation.clarification.v1' ||
            p.command_id !== e.command_id ||
            p.source_provider_message_id !== e.provider_key ||
            p.source_timestamp !== e.consumed_at ||
            p.source_timezone !== e.timezone ||
            p.mealType !== e.meal_type ||
            observation.facts.localDate !== e.local_date ||
            !isDeepStrictEqual([...observation.facts.logIds].sort(), [...e.log_ids].sort()) ||
            observation.context.logs.some(
              (row) =>
                typeof row.consumed_at !== 'string' ||
                conversationJournalInstant(row.consumed_at) !==
                  conversationJournalInstant(e.consumed_at),
            )
          )
            return null
          const policy = projectCurrentClinicalPublicPolicy(observation.clinical)
          let officialDay: Awaited<
            ReturnType<typeof loadFeedbackV2ClinicalContext>
          >['officialDay'] = null
          try {
            await current(s)
            const clinical = structuredClone(await loadClinical(db, s.auth, observation))
            await current(s)
            if (isDeepStrictEqual(clinical.policy, policy) && clinical.officialDay !== null)
              officialDay = proveFeedbackV2Day(observation, clinical.officialDay)
          } catch {
            /* Optional day context does not repeat or invalidate food. */
          }
          const prepared = prepareRegistrationFeedbackV2({
            registrationId: e.registration_id,
            localDate: e.local_date,
            locale: observation.clinical.body.locale === 'en-US' ? 'en-US' : 'pt-BR',
            registration: observation.facts.registration,
            policy,
            officialDay,
            preferencesKnown: false,
          })
          await current(s)
          try {
            const result = z
              .discriminatedUnion('action', [
                z
                  .object({ action: z.enum(['committed', 'replay']), feedback: z.unknown() })
                  .strict(),
                z.object({ action: z.literal('legacy'), feedback: z.unknown() }).strict(),
                z
                  .object({
                    action: z.literal('unavailable'),
                    reason: z.literal('original_context_unavailable'),
                    receipt: z.unknown(),
                  })
                  .strict(),
                empty,
              ])
              .parse(
                envelope(
                  await rpc('commit_conversation_meal_feedback_v2', {
                    p_user_id: e.owner_id,
                    p_command_id: e.command_id,
                    p_expected_effect_version: e.effect_version,
                    p_feedback: prepared as unknown as Json,
                  }),
                ),
              )
            await current(s)
            if (
              result.action !== 'committed' &&
              result.action !== 'replay' &&
              result.action !== 'legacy'
            )
              return null
            const saved = feedback(result.feedback, s, result.action === 'legacy')
            if (result.action === 'committed' && !isDeepStrictEqual(saved, prepared)) return no()
            return saved
          } catch {
            // Exactly one receipt-only reconciliation. No second seal, capture,
            // calculation, registration, current/day load or model invocation.
            return await readOriginal(s)
          }
        } catch {
          return null
        }
      },
      async readHistorical(input: ConversationMealContinuationFeedbackInput) {
        try {
          const s = scope(input),
            b = s.binding,
            e = b.receipt
          const request = Object.freeze({
            userId: e.owner_id,
            mode: 'profile' as const,
            expectedEpoch: e.epoch,
          })
          await current(s)
          const before = readCurrentClinicalState(
            await captureCurrentClinicalState(capture, request),
            e.owner_id,
          )
          await current(s)
          if (
            before.epoch !== e.epoch ||
            conversationJournalInstant(before.observed_at) <
              conversationJournalInstant(e.consumed_at)
          )
            return null
          const saved = await readOriginal(s)
          if (saved === null) return null
          await current(s)
          const after = readCurrentClinicalState(
            await captureCurrentClinicalState(capture, request),
            e.owner_id,
          )
          await current(s)
          if (
            after.epoch !== e.epoch ||
            conversationJournalInstant(after.observed_at) <
              conversationJournalInstant(before.observed_at) ||
            currentClinicalReadBinding(before) !== currentClinicalReadBinding(after)
          )
            return null
          const policy = projectCurrentClinicalPublicPolicy(after)
          const meta = {
            schema: 'conversation.feedback-presentation.v1' as const,
            mode: 'historical' as const,
            assistant: 'Flow AI' as const,
            original: {
              schema: saved.schema,
              registration_id: e.registration_id,
              kind: 'meal' as const,
              local_date: e.local_date,
            },
            current_policy: policy,
            provenance: {
              epoch: e.epoch,
              command_id: e.command_id,
              observed_at: after.observed_at,
            },
          }
          if (saved.schema === 'registration.feedback.v2') {
            if (saved.registration.kind !== 'meal') return no()
            return freezeInterpretation({
              ...meta,
              status: 'available' as const,
              format: 'sections' as const,
              recorded: saved.registration,
              sections: renderHistoricalMealFeedbackSections(saved, policy),
            })
          }
          if (!isHistoricalMealFeedbackRestricted(policy))
            return freezeInterpretation({
              ...meta,
              status: 'available' as const,
              format: 'legacy' as const,
              legacy_body: saved,
            })
          const en = saved.locale === 'en'
          return freezeInterpretation({
            ...meta,
            status: 'unavailable' as const,
            format: 'placeholder' as const,
            sections: [
              {
                key: 'saved' as const,
                text: en ? 'Your meal remains saved.' : 'Sua refeição continua salva.',
              },
              {
                key: 'summary' as const,
                text: en
                  ? 'This historical summary is currently unavailable. Your meal remains saved.'
                  : 'Este resumo histórico está indisponível neste momento. Sua refeição continua salva.',
              },
            ],
          })
        } catch {
          return null
        }
      },
    })
  } catch {
    return Object.freeze({
      readOriginal: async () => null,
      ensureOriginal: async () => null,
      readHistorical: async () => null,
    })
  }
}
