import { protocolWelcomeMessage } from '@mpp/core'
import type { OnboardingCompletionInput } from './contracts'
import { MobileApiError } from './http'

export type OnboardingActionType = 'acceptance' | 'acknowledgement' | 'consent'

export const MAX_PUBLIC_ONBOARDING_STATE_BYTES = 60_000

export interface OnboardingDocumentRecord {
  documentKey: string
  version: string
  locale: string
  body: string | null
  contentUrl: string | null
  contentHash: string
  purpose: string
  action: OnboardingActionType
  required: boolean
  effectiveAt: string
}

export interface OnboardingAcceptedActionRecord {
  documentKey: string
  version: string
  locale: string
  contentHash: string
  purpose: string
  action: OnboardingActionType
  actedAt: string
}

export interface OnboardingDraftRecord {
  name: string
  locale: OnboardingCompletionInput['locale']
  country: string
  timezone: string
  sex: OnboardingCompletionInput['sex']
  birthDate: string
  heightCm: number
  weightKg: number
  bodyFatPercent: number | null
  objective: OnboardingCompletionInput['objective']
  activityLevel: OnboardingCompletionInput['activity_level']
  trainingFrequency: number
  waterIntake: OnboardingCompletionInput['water_intake']
  hungerLevel: OnboardingCompletionInput['hunger_level']
  wakeTime: string
  bedtime: string
  foodOrganization: OnboardingCompletionInput['food_organization']
  persona: OnboardingCompletionInput['persona']
}

export interface OnboardingLoadRecord {
  locale: OnboardingCompletionInput['locale']
  completed: boolean
  completedAt: string | null
  documents: OnboardingDocumentRecord[]
  acceptedActions: OnboardingAcceptedActionRecord[]
  draft: OnboardingDraftRecord | null
}

export interface OnboardingCompletionRecord {
  userId: string
  completed: true
  completedAt: string
  objective: OnboardingCompletionInput['objective']
  persona: OnboardingCompletionInput['persona']
  documentActions: OnboardingAcceptedActionRecord[]
}

export type OnboardingRepositoryErrorCode =
  | 'documents_unavailable'
  | 'requirements_changed'
  | 'already_completed'
  | 'invalid_submission'
  | 'user_not_found'
  | 'internal'

export class OnboardingRepositoryError extends Error {
  constructor(readonly code: OnboardingRepositoryErrorCode) {
    super(code)
    this.name = 'OnboardingRepositoryError'
  }
}

export interface OnboardingRepository {
  load(userId: string, locale: string): Promise<OnboardingLoadRecord>
  complete(userId: string, input: OnboardingCompletionInput): Promise<OnboardingCompletionRecord>
}

function acceptedActionDto(action: OnboardingAcceptedActionRecord) {
  return {
    document_key: action.documentKey,
    version: action.version,
    locale: action.locale,
    content_hash: action.contentHash,
    purpose: action.purpose,
    action: action.action,
    acted_at: action.actedAt,
  }
}

function mapRepositoryError(error: unknown): never {
  if (!(error instanceof OnboardingRepositoryError)) throw error

  if (error.code === 'documents_unavailable') {
    throw new MobileApiError(
      503,
      'onboarding_documents_unavailable',
      'Onboarding documents are not available',
    )
  }
  if (error.code === 'requirements_changed') {
    throw new MobileApiError(
      409,
      'onboarding_requirements_changed',
      'Onboarding requirements changed; reload before trying again',
    )
  }
  if (error.code === 'already_completed') {
    throw new MobileApiError(
      409,
      'onboarding_already_completed',
      'Onboarding was already completed with different data',
    )
  }
  if (error.code === 'invalid_submission') {
    throw new MobileApiError(422, 'onboarding_rejected', 'Onboarding data was rejected')
  }
  if (error.code === 'user_not_found') {
    throw new MobileApiError(404, 'patient_not_found', 'Patient profile not found')
  }
  throw new MobileApiError(500, 'onboarding_persistence_failed', 'Onboarding could not be saved')
}

export async function getOnboardingState(
  repository: OnboardingRepository,
  userId: string,
  locale: string,
  options: { acceptsUnknownWater?: boolean } = {},
) {
  let state: OnboardingLoadRecord
  try {
    state = await repository.load(userId, locale)
  } catch (error) {
    mapRepositoryError(error)
  }

  // A distributed old iOS binary cannot decode a NULL habit in its required
  // reconsent draft. Never fabricate an enum to satisfy that decoder.
  let draft = state.draft
  if (draft && draft.waterIntake == null && options.acceptsUnknownWater !== true) {
    if (!state.completed) {
      throw new MobileApiError(
        409,
        'onboarding_client_update_required',
        'Update the app to review this onboarding profile',
      )
    }
    // The completed account needs no reconsent draft to enter the app.
    draft = null
  }

  const documents = state.documents.map((document) => ({
    document_key: document.documentKey,
    version: document.version,
    locale: document.locale,
    body: document.body,
    content_url: document.contentUrl,
    content_hash: document.contentHash,
    purpose: document.purpose,
    action: document.action,
    required: document.required,
    effective_at: document.effectiveAt,
  }))
  const requirementsAvailable =
    documents.length > 0 && documents.every((document) => document.required)

  const result = {
    locale: state.locale,
    completion: {
      completed: state.completed,
      completed_at: state.completedAt,
    },
    requirements: {
      available: requirementsAvailable,
      blocking_reason: requirementsAvailable ? null : ('documents_unavailable' as const),
      documents,
    },
    accepted_actions: state.acceptedActions.map(acceptedActionDto),
    draft: draft
      ? {
          name: draft.name,
          locale: draft.locale,
          country: draft.country,
          timezone: draft.timezone,
          sex: draft.sex,
          birth_date: draft.birthDate,
          height_cm: draft.heightCm,
          weight_kg: draft.weightKg,
          body_fat_percent: draft.bodyFatPercent,
          objective: draft.objective,
          activity_level: draft.activityLevel,
          training_frequency: draft.trainingFrequency,
          water_intake: draft.waterIntake,
          hunger_level: draft.hungerLevel,
          wake_time: draft.wakeTime,
          bedtime: draft.bedtime,
          food_organization: draft.foodOrganization,
          persona: draft.persona,
          current_step: 'consent' as const,
        }
      : null,
  }
  if (
    new TextEncoder().encode(JSON.stringify(result)).byteLength > MAX_PUBLIC_ONBOARDING_STATE_BYTES
  ) {
    throw new MobileApiError(
      503,
      'onboarding_documents_unavailable',
      'Onboarding documents are not available',
    )
  }
  return result
}

export async function completeOnboarding(
  repository: OnboardingRepository,
  userId: string,
  input: OnboardingCompletionInput,
) {
  let completion: OnboardingCompletionRecord
  try {
    completion = await repository.complete(userId, input)
  } catch (error) {
    mapRepositoryError(error)
  }

  return {
    onboarding_completed: completion.completed,
    completed_at: completion.completedAt,
    objective: completion.objective,
    persona: completion.persona,
    document_actions: completion.documentActions.map(acceptedActionDto),
    // The entry message of the objective that was RECORDED, in the language of
    // the request and with the name it carried. Built here, after the
    // repository answered: the SQL function and the strict reader of its
    // result know nothing about it. It depends only on the request and on the
    // recorded objective, so a replay of the same request returns the same.
    protocol_welcome: {
      protocol: completion.objective,
      paragraphs: protocolWelcomeMessage(completion.objective, input.name, input.locale),
    },
  }
}
