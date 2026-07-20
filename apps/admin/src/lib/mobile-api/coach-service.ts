import {
  type CoachMessageChannel,
  type CoachMessageContext,
  type CoachMessageLocale,
  type CoachPersonality,
  renderCoachTemplate,
  type SelectableCoachPersonality,
} from '@mpp/core'

export type MascotState = 'inactive' | 'reactivating' | 'active' | 'evolving' | 'neglected'

export interface CoachPersonaState {
  selected: SelectableCoachPersonality | null
  effective: CoachPersonality
  options: Array<{
    code: SelectableCoachPersonality
    name: string
    description: string
  }>
  mascot: {
    state: MascotState
    changed_at: string | null
  }
  contract_version: 'bodyflow.coach-persona.v1'
}

export interface ClaimedCoachMessageRecord {
  usageId: string
  templateVersionId: string
  packId: string
  requestedPersonality: CoachPersonality
  effectivePersonality: CoachPersonality
  reason: 'exact' | 'balanced_fallback'
  title: string | null
  subject: string | null
  body: string
  allowedVariables: string[]
  requiredVariables: string[]
}

export interface ClaimedCoachMessage {
  usageId: string
  templateVersionId: string
  packId: string
  requestedPersonality: CoachPersonality
  effectivePersonality: CoachPersonality
  reason: 'exact' | 'balanced_fallback'
  rendered: {
    title: string | null
    subject: string | null
    body: string
  }
}

export interface ClaimCoachMessageInput {
  userId: string
  context: CoachMessageContext
  channel: CoachMessageChannel
  locale: CoachMessageLocale
  eventKey: string
  variables: Record<string, string | number>
  now?: string
}

export interface CoachDependencies {
  repository: {
    getPersonaState(userId: string, locale: CoachMessageLocale): Promise<CoachPersonaState>
    setPersona(userId: string, persona: SelectableCoachPersonality): Promise<void>
    claimMessage(input: {
      userId: string
      context: CoachMessageContext
      channel: CoachMessageChannel
      locale: CoachMessageLocale
      eventKey: string
      availableVariables: string[]
      now?: string
    }): Promise<ClaimedCoachMessageRecord | null>
    markUsageFailed(usageId: string, reason: 'render_failed'): Promise<void>
  }
}

export function getCoachPersonaState(
  deps: CoachDependencies,
  userId: string,
  locale: CoachMessageLocale,
): Promise<CoachPersonaState> {
  return deps.repository.getPersonaState(userId, locale)
}

export async function setCoachPersona(
  deps: CoachDependencies,
  userId: string,
  persona: SelectableCoachPersonality,
  locale: CoachMessageLocale,
): Promise<CoachPersonaState> {
  await deps.repository.setPersona(userId, persona)
  return deps.repository.getPersonaState(userId, locale)
}

export async function claimAndRenderCoachMessage(
  deps: CoachDependencies,
  input: ClaimCoachMessageInput,
): Promise<ClaimedCoachMessage | null> {
  const claimed = await deps.repository.claimMessage({
    userId: input.userId,
    context: input.context,
    channel: input.channel,
    locale: input.locale,
    eventKey: input.eventKey,
    availableVariables: Object.keys(input.variables).sort(),
    now: input.now,
  })
  if (!claimed) return null

  try {
    const rendered = renderCoachTemplate(
      {
        context: input.context,
        channel: input.channel,
        locale: input.locale,
        title: claimed.title,
        subject: claimed.subject,
        body: claimed.body,
        allowedVariables: claimed.allowedVariables,
        requiredVariables: claimed.requiredVariables,
      },
      input.variables,
    )

    return {
      usageId: claimed.usageId,
      templateVersionId: claimed.templateVersionId,
      packId: claimed.packId,
      requestedPersonality: claimed.requestedPersonality,
      effectivePersonality: claimed.effectivePersonality,
      reason: claimed.reason,
      rendered,
    }
  } catch {
    await deps.repository.markUsageFailed(claimed.usageId, 'render_failed')
    return null
  }
}
