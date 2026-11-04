/** Read-only CURRENT-policy guard around immutable HISTORICAL feedback. This
 * wrapper is not a rewritten receipt, clinical write authority or Today panel. */
import { isDeepStrictEqual } from 'node:util'
import type { RegistrationFeedback } from '@mpp/agent/registration-feedback'
import {
  type FeedbackV2Section,
  parseRegistrationFeedbackV2,
  prepareRegistrationFeedbackV2,
  type RegistrationFeedbackV2,
  renderRegistrationFeedbackV2,
} from '@mpp/agent/registration-feedback-v2'
import type { ServiceClient } from '@mpp/db'
import {
  type ConversationJournalBinding,
  conversationJournalBindingSchema,
} from './conversation-command-candidate-contracts'
import { bindConversationCommand } from './conversation-command-contracts'
import {
  type ConversationMealFeedbackService,
  type ConversationMealOriginalFeedbackInput,
  createSupabaseConversationMealFeedbackService,
  type OriginalConversationMealFeedback,
} from './conversation-meal-feedback-service'
import { parseConversationMealEffectReceipt } from './conversation-meal-feedback-store'
import { freezeInterpretation } from './conversation-meal-interpretation-contracts'
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
import { createSupabaseCurrentClinicalStateSource } from './supabase-current-clinical-state'

export interface ConversationMealFeedbackPresentationInput
  extends ConversationMealOriginalFeedbackInput {
  /** Actual private journal/readPrepared result, NEVER a mobile expectedEpoch. */
  readonly serverBinding: ConversationJournalBinding
}
interface PresentationMetadata {
  readonly schema: 'conversation.feedback-presentation.v1'
  readonly mode: 'historical'
  readonly assistant: 'Flow AI'
  readonly original: {
    schema: 'registration.feedback.v1' | 'registration.feedback.v2'
    registration_id: string
    kind: 'meal'
    local_date: string
  }
  readonly current_policy: ReturnType<typeof projectCurrentClinicalPublicPolicy>
  readonly provenance: { epoch: string; command_id: string; observed_at: string }
}
export type ConversationMealFeedbackPresentation = PresentationMetadata &
  (
    | {
        readonly status: 'available'
        readonly format: 'sections'
        readonly recorded: Extract<RegistrationFeedbackV2['registration'], { kind: 'meal' }>
        readonly sections: readonly FeedbackV2Section[]
      }
    | {
        readonly status: 'available'
        readonly format: 'legacy'
        readonly legacy_body: RegistrationFeedback
      }
    | {
        readonly status: 'unavailable'
        readonly format: 'placeholder'
        readonly sections: readonly FeedbackV2Section[]
      }
  )
export interface ConversationMealFeedbackPresentationService {
  readHistorical(
    input: ConversationMealFeedbackPresentationInput,
  ): Promise<ConversationMealFeedbackPresentation | null>
}
export interface ConversationMealFeedbackPresentationDependencies {
  clinicalSource?: CurrentClinicalStateSource
  original?: Pick<ConversationMealFeedbackService, 'readOriginal'>
}
function invalid(): never {
  throw new Error('Historical feedback presentation unavailable')
}
function instant(raw: string): bigint {
  const match =
    /^(\d{4}-\d{2}-\d{2})T(?:[01]\d|2[0-3]):[0-5]\d:[0-5]\d(?:\.(\d{1,9}))?(?:Z|[+-](?:[01]\d|2[0-3]):[0-5]\d)$/u.exec(
      raw,
    )
  if (!match || raw.startsWith('0000')) invalid()
  const civil = new Date(`${match[1]}T00:00:00.000Z`),
    time = Date.parse(raw)
  if (
    !Number.isFinite(time) ||
    !Number.isFinite(civil.getTime()) ||
    civil.toISOString().slice(0, 10) !== match[1]
  )
    invalid()
  return BigInt(time) * 1_000_000n + BigInt((match[2] ?? '').padEnd(9, '0').slice(3))
}
function bind(input: ConversationMealFeedbackPresentationInput) {
  const raw = structuredClone(input),
    owner = authenticatedReevaluationOwner(raw.auth)
  const command = bindConversationCommand(
    owner,
    `cmsg1:${raw.command.commandId}`,
    raw.command.command,
  )
  if (!isDeepStrictEqual(command, raw.command)) invalid()
  const receipt = parseConversationMealEffectReceipt(raw.receipt, command),
    server = conversationJournalBindingSchema.parse(raw.serverBinding)
  if (
    !isDeepStrictEqual(server, raw.serverBinding) ||
    server.owner_id !== owner ||
    server.command_id !== command.commandId ||
    server.input_hash !== command.inputHash
  )
    invalid()
  instant(server.admitted_at)
  return freezeInterpretation({ auth: raw.auth, command, receipt, server })
}
function original(
  raw: OriginalConversationMealFeedback,
  b: ReturnType<typeof bind>,
): OriginalConversationMealFeedback {
  const value = structuredClone(raw),
    identity = {
      userId: b.command.ownerId,
      registrationId: b.receipt.registration_id,
      kind: 'meal' as const,
    }
  if (value.schema === 'registration.feedback.v1') {
    const parsed = parseRegistrationFeedback(value, identity)
    if (parsed.day !== null && parsed.day.local_date !== b.receipt.local_date) invalid()
    return freezeInterpretation(parsed)
  }
  const parsed = parseRegistrationFeedbackV2(value, identity)
  if (
    parsed.local_date !== b.receipt.local_date ||
    parsed.registration.kind !== 'meal' ||
    parsed.registration.meal_kind !== b.receipt.meal_type ||
    !isDeepStrictEqual(
      [...parsed.registration.items.map((item) => item.log_id)].sort(),
      [...b.receipt.log_ids].sort(),
    )
  )
    invalid()
  return freezeInterpretation(parsed)
}
function restricted(policy: PresentationMetadata['current_policy']): boolean {
  return (
    policy.assessment !== 'complete' ||
    !policy.recording_allowed ||
    policy.pause_weight_loss_guidance ||
    Object.values(policy.hide).some(Boolean)
  )
}
function renderHistorical(
  saved: RegistrationFeedbackV2,
  policy: PresentationMetadata['current_policy'],
): readonly FeedbackV2Section[] {
  // This private render adapter is never saved/returned as an original v2 DTO.
  // It changes only visibility of existing historical values, never numbers.
  const display = structuredClone(saved),
    limited = restricted(policy)
  if (limited) {
    const neutral = prepareRegistrationFeedbackV2({
      registrationId: saved.registration_id,
      localDate: saved.local_date,
      locale: saved.locale,
      registration: saved.registration,
      officialDay: null,
      policy,
      preferencesKnown: false,
    })
    display.guidance = neutral.guidance
    display.education = policy.pause_weight_loss_guidance
      ? neutral.education
      : { status: 'unavailable' }
    if (policy.assessment !== 'complete' || !policy.recording_allowed) {
      display.day = null
      display.block = neutral.block
    } else {
      const day = display.day,
        pause = policy.pause_weight_loss_guidance
      if (day) {
        if (pause || policy.hide.objective) day.current_protocol = null
        if (pause || policy.hide.calories) {
          day.targets.calories_kcal = null
          day.calorie_percentage = null
        }
        if (pause || policy.hide.protein) {
          day.targets.protein_g = null
          day.protein_percentage = null
        }
        if (
          pause ||
          policy.hide.balance ||
          policy.hide.budget ||
          day.targets.calories_kcal === null
        ) {
          day.remaining_food_kcal = null
          day.food_excess_kcal = null
        }
      }
      if (pause || policy.hide.block || policy.hide.objective)
        display.block = { status: 'protected' }
    }
  }
  const en = saved.locale === 'en'
  return renderRegistrationFeedbackV2(display).map((section) => {
    if (section.key === 'day')
      return {
        ...section,
        text: `${en ? 'At the time of this registration' : 'No momento deste registro'} (${saved.local_date}):\n${section.text}`,
      }
    if (section.key === 'block') {
      const text =
        display.block.status === 'not_applicable'
          ? en
            ? 'The consolidated block did not apply to the objective at this registration.'
            : 'O bloco consolidado não se aplicava ao objetivo no momento deste registro.'
          : section.text
      return {
        ...section,
        text: `${limited ? (en ? 'Historical progress under current guidance' : 'Progresso histórico sob as orientações atuais') : en ? 'Historical consolidated progress' : 'Progresso consolidado no momento do registro'}:\n${text}`,
      }
    }
    if (section.key === 'education' && !limited && saved.education.status === 'available')
      return {
        ...section,
        text: `${en ? 'Educational comment at the time of registration' : 'Comentário educativo no momento do registro'}:\n${section.text}`,
      }
    return section
  })
}

// Reuse the existing current-policy mask for actual linked child effects too.
// Callers must first bind their real sealed receipt and current observations.
export {
  renderHistorical as renderHistoricalMealFeedbackSections,
  restricted as isHistoricalMealFeedbackRestricted,
}
export function createSupabaseConversationMealFeedbackPresentation(
  db: ServiceClient,
  dependencies: ConversationMealFeedbackPresentationDependencies = {},
): ConversationMealFeedbackPresentationService {
  try {
    const source = dependencies.clinicalSource ?? createSupabaseCurrentClinicalStateSource(db)
    const capture = Object.freeze({ capture: source.capture.bind(source) })
    const originalSource =
        dependencies.original ?? createSupabaseConversationMealFeedbackService(db),
      readOriginal = originalSource.readOriginal.bind(originalSource)
    return Object.freeze({
      async readHistorical(
        input: ConversationMealFeedbackPresentationInput,
      ): Promise<ConversationMealFeedbackPresentation | null> {
        try {
          const b = bind(input),
            request = Object.freeze({
              userId: b.command.ownerId,
              mode: 'profile' as const,
              expectedEpoch: b.server.epoch,
            })
          const before = readCurrentClinicalState(
            await captureCurrentClinicalState(capture, request),
            b.command.ownerId,
          )
          if (
            before.epoch !== b.server.epoch ||
            instant(before.observed_at) < instant(b.server.admitted_at)
          )
            return null
          const read = await readOriginal(
            Object.freeze({ auth: b.auth, command: b.command, receipt: b.receipt }),
          )
          if (read === null) return null
          const saved = original(read, b)
          const after = readCurrentClinicalState(
            await captureCurrentClinicalState(capture, request),
            b.command.ownerId,
          )
          if (
            after.epoch !== b.server.epoch ||
            instant(after.observed_at) < instant(before.observed_at) ||
            currentClinicalReadBinding(before) !== currentClinicalReadBinding(after)
          )
            return null
          const policy = projectCurrentClinicalPublicPolicy(after)
          const meta: PresentationMetadata = {
            schema: 'conversation.feedback-presentation.v1',
            mode: 'historical',
            assistant: 'Flow AI',
            original: {
              schema: saved.schema,
              registration_id: b.receipt.registration_id,
              kind: 'meal',
              local_date: b.receipt.local_date,
            },
            current_policy: policy,
            provenance: {
              epoch: b.server.epoch,
              command_id: b.command.commandId,
              observed_at: after.observed_at,
            },
          }
          if (saved.schema === 'registration.feedback.v1') {
            if (!restricted(policy))
              return freezeInterpretation({
                ...meta,
                status: 'available',
                format: 'legacy',
                legacy_body: saved,
              })
            const en = saved.locale === 'en'
            return freezeInterpretation({
              ...meta,
              status: 'unavailable',
              format: 'placeholder',
              sections: [
                {
                  key: 'saved',
                  text: en ? 'Your meal remains saved.' : 'Sua refeição continua salva.',
                },
                {
                  key: 'summary',
                  text: en
                    ? 'This historical summary is currently unavailable. Your meal remains saved.'
                    : 'Este resumo histórico está indisponível neste momento. Sua refeição continua salva.',
                },
              ],
            })
          }
          if (saved.registration.kind !== 'meal') invalid()
          return freezeInterpretation({
            ...meta,
            status: 'available',
            format: 'sections',
            recorded: saved.registration,
            sections: renderHistorical(saved, policy),
          })
        } catch {
          // Unknown policy, reset, drift, source/owner gap or outage withholds
          // presentation; never returns unsafe opaque text or logs health data.
          return null
        }
      },
    })
  } catch {
    return Object.freeze({ readHistorical: async () => null })
  }
}
