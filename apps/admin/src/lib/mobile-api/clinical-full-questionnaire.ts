/** Injection-only public read model. Describing/assessing never admits health
 * declarations, prepares a write, changes a target or consumes photo quota. */
import {
  getReevaluationFormDescriptor,
  isFullReevaluationKind,
  requiresReevaluationPhotos,
} from '@mpp/core/reevaluation-form'
import { z } from 'zod'
import type { MobileAuthContext } from './auth'
import { readClinicalFullContext } from './clinical-full-authority'
import {
  type ClinicalFullScope,
  clinicalFullError,
  type fullChoiceSchema,
  fullKind,
} from './clinical-full-contracts'
import { ClinicalFullChoiceUnavailable, evaluateClinicalFull } from './clinical-full-evaluation'
import {
  bindClinicalFullPublicCommand,
  clinicalFullPublicCandidateId,
  clinicalFullPublicDraftSchema,
} from './clinical-full-public-command'
import {
  type ClinicalQuestionnaireLocale,
  questionnaireOption,
  questionnaireQuestion,
} from './clinical-full-questionnaire-presentation'
import { reevaluationCycleUuidSchema as uuid } from './reevaluation-cycle-contracts'
import { authenticatedReevaluationOwner } from './reevaluation-cycle-service'

const scopeShape = { kind: fullKind, cycleId: uuid.nullable() }
const describeSchema = z
  .object({ ...scopeShape, activityPurpose: clinicalFullPublicDraftSchema.shape.activityPurpose })
  .strict()
const assessSchema = z.object({ ...scopeShape, input: clinicalFullPublicDraftSchema }).strict()
type Context = ReturnType<typeof readClinicalFullContext>
type Choice = z.infer<typeof fullChoiceSchema>
const choices: readonly Choice[] = [
  { kind: 'keep' },
  { kind: 'activity' },
  { kind: 'phase_calorie_step' },
  { kind: 'phase', phase: 'recomposicao' },
  { kind: 'phase', phase: 'ganho_massa' },
  { kind: 'phase', phase: 'manutencao' },
  { kind: 'schedule', action: 'reconfirm' },
  { kind: 'schedule', action: 'pause' },
]
function parse<S extends z.ZodTypeAny>(schema: S, raw: unknown): z.infer<S> {
  const result = schema.safeParse(structuredClone(raw))
  if (!result.success) throw clinicalFullError('invalid')
  return result.data
}
function scopeFor(
  owner: string,
  raw: { kind: ClinicalFullScope['kind']; cycleId: string | null },
): ClinicalFullScope {
  if (isFullReevaluationKind(raw.kind) !== (raw.cycleId !== null))
    throw clinicalFullError('invalid')
  return { userId: owner, kind: raw.kind, cycleId: raw.cycleId?.toLowerCase() ?? null }
}
function localeFor(auth: MobileAuthContext): ClinicalQuestionnaireLocale {
  if (auth.patient.locale !== 'pt-BR' && auth.patient.locale !== 'en-US')
    throw clinicalFullError('invalid')
  return auth.patient.locale
}
function reading(context: Context, scope: ClinicalFullScope) {
  if (!requiresReevaluationPhotos(scope.kind)) return { status: 'not_required' as const }
  const candidate = context.facts.protocol_authority.body_fat_candidate
  if (candidate?.availability !== 'available') return { status: 'photos_required' as const }
  return {
    status: 'ready' as const,
    percent: candidate.mean_hundredths / 100,
    candidate_id: clinicalFullPublicCandidateId(scope, {
      confirmed: true,
      sourceHash: candidate.source_hash,
      meanHundredths: candidate.mean_hundredths,
    }),
  }
}
function descriptor(
  context: Context,
  scope: ClinicalFullScope,
  purpose: z.infer<typeof describeSchema>['activityPurpose'],
  locale: ClinicalQuestionnaireLocale,
) {
  const p = context.facts.profile,
    origin = context.facts.protocol_authority.phase_origin
  const common = {
    sex: p.sex,
    currentActivityLevel: p.activity_level,
    holdActive: context.facts.safety.hold_active,
    confirmedMealDays: null,
  }
  const purposeOptions =
    p.current_protocol === 'recomposicao' && isFullReevaluationKind(scope.kind)
      ? (['normal', 'consider_maintenance', 'end_deficit'] as const)
      : (['normal'] as const)
  if (!purposeOptions.some((offered) => offered === purpose)) throw clinicalFullError('invalid')
  const form =
    p.current_protocol !== null
      ? getReevaluationFormDescriptor({
          ...common,
          phase: p.current_protocol,
          kind: scope.kind,
          activityPurpose: purpose,
        })
      : origin.kind === 'legacy_transition_unassigned' &&
          (scope.kind === 'REGULAR' ||
            scope.kind === 'EARLY_FULL' ||
            scope.kind === 'TRANSITION_FULL') &&
          purpose === 'normal'
        ? getReevaluationFormDescriptor({
            ...common,
            phase: null,
            kind: scope.kind,
            activityPurpose: 'normal',
            legacyOrigin: origin,
          })
        : origin.kind === 'confirmed_no_plan' &&
            (scope.kind === 'REGULAR' || scope.kind === 'EARLY_FULL') &&
            purpose === 'normal'
          ? getReevaluationFormDescriptor({
              ...common,
              phase: null,
              kind: scope.kind,
              activityPurpose: 'normal',
              noPlanOrigin: origin,
            })
          : (() => {
              throw clinicalFullError('changed')
            })()
  return {
    version: 1 as const,
    locale,
    kind: scope.kind,
    cycle_id: scope.cycleId,
    activity_purpose: purpose,
    // These select the descriptor's existing question branches, not an
    // eligible clinical effect. Actions still require actual assessment.
    activity_purpose_options: purposeOptions,
    questions: form.questions.map((q) => questionnaireQuestion(q, locale, scope.kind)),
    preference_question:
      form.preferenceQuestion === null
        ? null
        : {
            label:
              locale === 'pt-BR'
                ? form.preferenceQuestion.label
                : 'Do you have a goal in mind? (optional)',
            optional: true as const,
            options: form.preferenceQuestion.options.map((o) => questionnaireOption(o, locale)),
            routine_options: form.preferenceQuestion.routineOptions.map((o) =>
              questionnaireOption(o, locale),
            ),
            existing_actions: [...form.preferenceQuestion.existingActions],
          },
    // This capture has no proven meal-day aggregate. Unknown is not zero.
    support_text: null,
    photo_requirement: {
      required: form.photoRequirement.required,
      new_only: true as const,
      poses: [...form.photoRequirement.poses],
    },
    body_fat: reading(context, scope),
  }
}
type Evaluation = ReturnType<typeof evaluateClinicalFull>
function action(choice: Choice, value: Evaluation) {
  return {
    choice: structuredClone(choice),
    principal: value.package.proposal.principal,
    phase: value.safety.hide.objective ? null : value.package.proposal.profile.current_protocol,
    targets: {
      calories_kcal: value.safety.hide.calories ? null : value.package.proposal.targets.afterKcal,
      protein_g: value.safety.hide.protein ? null : value.package.proposal.targets.afterProtein,
    },
    professional_assessment_recommended: value.safety.professionalAssessmentRecommended,
    pause_weight_loss_guidance: value.safety.pauseWeightLossGuidance,
  }
}
type AssessmentStatus =
  | 'available'
  | 'no_change_available'
  | 'health_declaration_required'
  | 'photos_required'
  | 'body_fat_confirmation_required'
type Feedback = Pick<Evaluation['preference'], 'status' | 'reason' | 'missing'>
function assessment(
  status: AssessmentStatus,
  actions: ReturnType<typeof action>[] = [],
  preference: Feedback | null = null,
) {
  return { version: 1 as const, status, actions, preference }
}
export function createClinicalFullQuestionnaire(dependencies: {
  readonly enabled: boolean
  readonly repository: { capture(scope: ClinicalFullScope): Promise<unknown> }
}) {
  const enabled = dependencies.enabled === true,
    capture = dependencies.repository.capture.bind(dependencies.repository)
  function start(auth: MobileAuthContext) {
    const owner = authenticatedReevaluationOwner(auth),
      locale = localeFor(auth)
    if (!enabled) throw clinicalFullError('unavailable')
    return { owner, locale }
  }
  return Object.freeze({
    async describe(auth: MobileAuthContext, raw: unknown) {
      const { owner, locale } = start(auth),
        request = parse(describeSchema, raw),
        scope = scopeFor(owner, request)
      const context = readClinicalFullContext(await capture(scope), scope)
      return descriptor(context, scope, request.activityPurpose, locale)
    },
    async assess(auth: MobileAuthContext, raw: unknown) {
      const { owner } = start(auth),
        request = parse(assessSchema, raw),
        scope = scopeFor(owner, request)
      const context = readClinicalFullContext(await capture(scope), scope),
        input = request.input
      // Selecting a risk in an unsaved questionnaire is never an admission.
      if (
        input.answers.healthCheck?.kind === 'risks' &&
        input.answers.healthCheck.items.some(
          (code) => !context.facts.safety.items.some((item) => item.code === code),
        )
      )
        return assessment('health_declaration_required')
      const candidate = reading(context, scope)
      if (candidate.status === 'photos_required') return assessment('photos_required')
      if (candidate.status === 'ready' && input.bodyFat === null)
        return assessment('body_fat_confirmation_required')
      const bound = bindClinicalFullPublicCommand({ ...input, choice: { kind: 'keep' } }, scope, {
        context,
      })
      const actions: ReturnType<typeof action>[] = []
      let feedback: Feedback | null = null
      for (const choice of scope.kind === 'SAFETY'
        ? [{ kind: 'neutral_exit' } as const]
        : choices) {
        let value: Evaluation
        try {
          value = evaluateClinicalFull(context, scope, { ...bound, choice })
        } catch (error) {
          if (error instanceof ClinicalFullChoiceUnavailable) continue
          throw clinicalFullError('changed')
        }
        actions.push(action(choice, value))
        feedback ??= {
          status: value.preference.status,
          reason: value.preference.reason,
          missing: [...value.preference.missing],
        }
      }
      return assessment(actions.length ? 'available' : 'no_change_available', actions, feedback)
    },
  })
}
