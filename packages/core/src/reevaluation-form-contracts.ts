import { z } from 'zod'
import {
  HEALTH_CHECK_QUESTION,
  HEALTH_RISK_ITEMS,
  healthCheckDraftSchema,
  PROFESSIONAL_CONVERSATION_DECLARATION,
  REEVALUATION_OPT_OUT_LABEL,
  unknownDraftAnswer,
} from './health-check-contracts.js'
import { clinicalTimestampSchema } from './reevaluation-clinical-safety.js'

const phaseSchema = z.enum(['recomposicao', 'ganho_massa', 'manutencao'])
const kindSchema = z.enum(['REGULAR', 'EARLY_FULL', 'TRANSITION_FULL', 'ROUTINE_REVIEW', 'SAFETY'])
const purposeSchema = z.enum(['normal', 'consider_maintenance', 'end_deficit'])
const levelSchema = z.enum(['sedentario', 'leve', 'moderado', 'alto', 'atleta'])
const nullable = <S extends z.ZodTypeAny>(schema: S) =>
  z.preprocess(unknownDraftAnswer, schema.nullable())

const activitySchema = z
  .object({
    otherExerciseType: nullable(z.string().trim().min(1)),
    otherExerciseDays: nullable(z.number().int().min(0).max(7)),
    sessionMinutes: nullable(z.number().finite().positive()),
    sessionIntensity: nullable(z.enum(['leve', 'moderada', 'alta'])),
    mostlySitting: nullable(z.boolean()),
    activityLevel: nullable(levelSchema),
    activityLevelConfirmed: z.boolean().default(false),
  })
  .strict()
  .refine(
    (activity) => !activity.activityLevelConfirmed || activity.activityLevel !== null,
    'Activity confirmation requires an explicit level',
  )

const preferenceValueSchema = z.discriminatedUnion('kind', [
  z.object({ kind: z.literal('weight'), kg: z.number().finite().min(30).max(300) }).strict(),
  z.object({ kind: z.literal('body_fat'), percent: z.number().finite().min(3).max(60) }).strict(),
  z
    .object({
      kind: z.literal('routine'),
      value: z.enum(['regular_training', 'more_energy', 'organized_food', 'maintain_weight']),
    })
    .strict(),
  z.object({ kind: z.literal('follow_app') }).strict(),
  z.object({ kind: z.literal('professional') }).strict(),
])
/** Input-range validation only. Future clinical review must apply n21 refusals separately. */
const preferenceSchema = nullable(
  z.discriminatedUnion('action', [
    z.object({ action: z.literal('keep') }).strict(),
    z.object({ action: z.literal('remove') }).strict(),
    z.object({ action: z.literal('skip') }).strict(),
    z.object({ action: z.literal('change'), value: preferenceValueSchema }).strict(),
  ]),
)
export const reevaluationGoalPreferenceSchema = preferenceSchema

const answerSchema = z
  .object({
    weightKg: nullable(z.number().finite().min(30).max(300)),
    strengthSessions: nullable(z.number().int().min(0).max(7)),
    adherence: nullable(z.enum(['bem_consistente', 'mais_ou_menos', 'pouco_consistente'])),
    hunger: nullable(z.enum(['pouca', 'moderada', 'muita'])),
    energy: nullable(z.enum(['boa', 'ok', 'baixa'])),
    strengthProgression: nullable(
      z.enum(['melhorou', 'ficou_parecido', 'piorou_ou_travou', 'nao_sei_avaliar']),
    ),
    fatPerception: nullable(z.enum(['nao_percebi', 'um_pouco', 'claramente'])),
    difficultToMaintain: nullable(z.enum(['nao', 'sim'])),
    activity: nullable(activitySchema),
    healthCheck: healthCheckDraftSchema,
    professionalConversationConfirmed: nullable(z.boolean()),
  })
  .strict()

/** Shared input grammar. Presence/meaning remains owned by the descriptor and
 * clinical evaluator; exporting this does not authorize an omitted answer. */
export const reevaluationAnswersSchema = answerSchema

export function isFullReevaluationKind(kind: string): boolean {
  return kind === 'REGULAR' || kind === 'EARLY_FULL' || kind === 'TRANSITION_FULL'
}
export function requiresReevaluationPhotos(kind: string): boolean {
  return kind === 'REGULAR' || kind === 'TRANSITION_FULL'
}
function activityApplies(
  phase: z.infer<typeof phaseSchema>,
  kind: z.infer<typeof kindSchema>,
  purpose: z.infer<typeof purposeSchema>,
): boolean {
  return !isFullReevaluationKind(kind) || phase !== 'recomposicao' || purpose !== 'normal'
}

export const plannedReevaluationFormDraftSchema = z
  .object({
    version: z.literal(1),
    phase: phaseSchema,
    kind: kindSchema,
    activityPurpose: purposeSchema,
    answers: answerSchema,
    preference: preferenceSchema,
  })
  .strict()
  .superRefine((draft, ctx) => {
    const allowed = new Set<keyof typeof draft.answers>(['strengthSessions', 'activity'])
    if (draft.kind === 'ROUTINE_REVIEW' && draft.phase !== 'recomposicao') allowed.add('hunger')
    if (isFullReevaluationKind(draft.kind)) {
      for (const key of [
        'weightKg',
        'adherence',
        'hunger',
        'energy',
        'healthCheck',
        'professionalConversationConfirmed',
      ] as const)
        allowed.add(key)
      if (draft.phase === 'ganho_massa') {
        allowed.add('strengthProgression')
        allowed.add('fatPerception')
      }
      if (draft.phase === 'manutencao') allowed.add('difficultToMaintain')
      if (!activityApplies(draft.phase, draft.kind, draft.activityPurpose))
        allowed.delete('activity')
    } else if (draft.preference !== null) {
      ctx.addIssue({
        code: z.ZodIssueCode.custom,
        path: ['preference'],
        message: 'Preference is outside this review kind',
      })
    }
    for (const key of Object.keys(draft.answers) as (keyof typeof draft.answers)[]) {
      if (!allowed.has(key) && draft.answers[key] !== null) {
        ctx.addIssue({
          code: z.ZodIssueCode.custom,
          path: ['answers', key],
          message: 'Answer is outside this review context',
        })
      }
    }
  })
export type PlannedReevaluationFormDraft = z.infer<typeof plannedReevaluationFormDraftSchema>

/** Internal capture metadata, not a client declaration or proof by itself.
 * The SQL writer checks the genuine keyed signup receipt in the captured epoch. */
const noPlanOriginSchema = z
  .object({
    kind: z.literal('confirmed_no_plan'),
    signupGeneration: z.string().uuid(),
    signupEpoch: z.string().uuid(),
    completedAt: z
      .string()
      .datetime({ precision: 6 })
      .refine((value) => !value.startsWith('0000-')),
  })
  .strict()

export const healthOnlyReevaluationFormDraftSchema = z
  .object({
    version: z.literal(1),
    phase: z.null(),
    noPlanOrigin: noPlanOriginSchema,
    kind: z.enum(['REGULAR', 'EARLY_FULL']),
    activityPurpose: z.literal('normal'),
    answers: answerSchema
      .pick({ weightKg: true, healthCheck: true, professionalConversationConfirmed: true })
      .extend({
        strengthSessions: z.null().default(null),
        adherence: z.null().default(null),
        hunger: z.null().default(null),
        energy: z.null().default(null),
        strengthProgression: z.null().default(null),
        fatPerception: z.null().default(null),
        difficultToMaintain: z.null().default(null),
        activity: z.null().default(null),
      })
      .strict(),
    preference: z.null().default(null),
  })
  .strict()

/** A current legacy admission proves neither a historical signup nor a prior
 * clinical phase. Its identity is captured by the backend, never by the app. */
export const legacyReevaluationOriginSchema = z
  .object({
    kind: z.literal('legacy_transition_unassigned'),
    generation: z.string().uuid(),
    epoch: z.string().uuid(),
    admittedAt: clinicalTimestampSchema,
  })
  .strict()
export const legacyUnassignedReevaluationFormDraftSchema = z
  .object({
    version: z.literal(1),
    phase: z.null(),
    legacyOrigin: legacyReevaluationOriginSchema,
    kind: z.enum(['REGULAR', 'EARLY_FULL', 'TRANSITION_FULL']),
    activityPurpose: z.literal('normal'),
    answers: healthOnlyReevaluationFormDraftSchema.shape.answers
      .extend({
        strengthSessions: answerSchema.shape.strengthSessions,
        hunger: answerSchema.shape.hunger,
        activity: answerSchema.shape.activity,
      })
      .strict(),
    preference: z.null().default(null),
  })
  .strict()

export const reevaluationFormDraftSchema = z.union([
  plannedReevaluationFormDraftSchema,
  healthOnlyReevaluationFormDraftSchema,
  legacyUnassignedReevaluationFormDraftSchema,
])
export type ReevaluationFormDraft = z.infer<typeof reevaluationFormDraftSchema>
export type ReevaluationAnswers = ReevaluationFormDraft['answers']
export type ReevaluationAnswerKey = keyof ReevaluationAnswers

/** Pure local validation; no profile, weight-entry, target, calendar or preference persistence. */
export function parseReevaluationFormDraft(input: unknown): ReevaluationFormDraft {
  return reevaluationFormDraftSchema.parse(input)
}

const labels = Object.freeze({
  weightKg: 'Qual é o seu peso hoje?',
  strengthSessions: 'Quantos treinos de musculação por semana você fez nestes 14 dias?',
  adherence: 'Nos últimos 14 dias, como foi sua alimentação em relação ao plano?',
  hunger: 'Como esteve a sua fome, na média?',
  energy: 'E a sua energia no dia a dia?',
  strengthProgression: 'Em relação aos 14 dias anteriores, seu treino de força…',
  fatPerception: 'Você percebeu ganho de gordura?',
  difficultToMaintain: 'Está difícil manter o plano?',
  activity: 'Nível de atividade confirmado',
  healthCheck: HEALTH_CHECK_QUESTION,
  professionalConversationConfirmed: PROFESSIONAL_CONVERSATION_DECLARATION,
})
type ActivityQuestionKey =
  `activity.${Exclude<keyof z.infer<typeof activitySchema>, 'activityLevelConfirmed'>}`
export interface ReevaluationQuestion {
  key: Exclude<ReevaluationAnswerKey, 'activity'> | ActivityQuestionKey
  label: string
  optOutLabel: typeof REEVALUATION_OPT_OUT_LABEL
  options?: { value: string | boolean; label: string }[]
  min?: number
  max?: number
  preselected?: z.infer<typeof levelSchema> | null
  initiallyConfirmed?: false
  hint?: string
}
const options = (values: readonly (readonly [string, string])[]) =>
  values.map(([value, label]) => ({ value, label }))
const choiceOptions = {
  professionalConversationConfirmed: [
    { value: true, label: 'Sim' },
    { value: false, label: 'Não' },
  ],
  adherence: options([
    ['bem_consistente', 'Bem consistente'],
    ['mais_ou_menos', 'Mais ou menos'],
    ['pouco_consistente', 'Pouco consistente'],
  ]),
  hunger: options([
    ['pouca', 'Pouca'],
    ['moderada', 'Moderada'],
    ['muita', 'Muita'],
  ]),
  energy: options([
    ['boa', 'Boa'],
    ['ok', 'Ok'],
    ['baixa', 'Baixa'],
  ]),
  strengthProgression: options([
    ['melhorou', 'Melhorou'],
    ['ficou_parecido', 'Ficou parecido'],
    ['piorou_ou_travou', 'Piorou ou travou'],
    ['nao_sei_avaliar', 'Não sei avaliar'],
  ]),
  fatPerception: options([
    ['nao_percebi', 'Não percebi'],
    ['um_pouco', 'Um pouco'],
    ['claramente', 'Claramente'],
  ]),
  difficultToMaintain: options([
    ['nao', 'Não'],
    ['sim', 'Sim'],
  ]),
}
const plannedDescriptorContextSchema = z
  .object({
    phase: phaseSchema,
    kind: kindSchema,
    sex: z.enum(['masculino', 'feminino']).nullable(),
    currentActivityLevel: levelSchema.nullable(),
    holdActive: z.boolean(),
    activityPurpose: purposeSchema,
    confirmedMealDays: z.number().int().min(0).max(14).nullable(),
  })
  .strict()
const descriptorContextSchema = z.union([
  plannedDescriptorContextSchema,
  plannedDescriptorContextSchema
    .extend({
      phase: z.null(),
      noPlanOrigin: noPlanOriginSchema,
      kind: z.enum(['REGULAR', 'EARLY_FULL']),
      activityPurpose: z.literal('normal'),
    })
    .strict(),
  plannedDescriptorContextSchema
    .extend({
      phase: z.null(),
      legacyOrigin: legacyReevaluationOriginSchema,
      kind: z.enum(['REGULAR', 'EARLY_FULL', 'TRANSITION_FULL']),
      activityPurpose: z.literal('normal'),
    })
    .strict(),
])
export type ReevaluationFormContext = z.infer<typeof descriptorContextSchema>

/** A description of fields, not authority to open unsupported kinds in the calendar. */
export function getReevaluationFormDescriptor(input: ReevaluationFormContext) {
  const context = descriptorContextSchema.parse(input)
  const questions: ReevaluationQuestion[] = []
  function add(key: Exclude<ReevaluationAnswerKey, 'activity'>) {
    questions.push({
      key,
      label:
        context.kind === 'TRANSITION_FULL'
          ? ((
              {
                strengthSessions: 'Quantos treinos de musculação por semana você faz atualmente?',
                adherence: 'Como está sua alimentação em relação ao plano atual?',
                strengthProgression: 'Atualmente, como está a evolução do seu treino de força?',
              } as Partial<Record<ReevaluationAnswerKey, string>>
            )[key] ?? labels[key])
          : labels[key],
      optOutLabel: REEVALUATION_OPT_OUT_LABEL,
      ...(key in choiceOptions
        ? { options: structuredClone(choiceOptions[key as keyof typeof choiceOptions]) }
        : {}),
      ...(key === 'weightKg' ? { min: 30, max: 300 } : {}),
      ...(key === 'strengthSessions' ? { min: 0, max: 7 } : {}),
    })
  }
  if (context.phase === null) {
    add('weightKg')
    if ('legacyOrigin' in context) {
      add('strengthSessions')
      add('hunger')
    }
  } else if (isFullReevaluationKind(context.kind)) {
    for (const key of ['weightKg', 'strengthSessions', 'adherence', 'hunger', 'energy'] as const)
      add(key)
    if (context.phase === 'ganho_massa') {
      add('strengthProgression')
      add('fatPerception')
    }
    if (context.phase === 'manutencao') add('difficultToMaintain')
  } else {
    add('strengthSessions')
    if (context.kind === 'ROUTINE_REVIEW' && context.phase !== 'recomposicao') add('hunger')
  }
  if (
    context.phase === null
      ? 'legacyOrigin' in context
      : activityApplies(context.phase, context.kind, context.activityPurpose)
  ) {
    const activityQuestions: Omit<ReevaluationQuestion, 'optOutLabel'>[] = [
      { key: 'activity.otherExerciseType', label: 'Que outro exercício você faz?' },
      { key: 'activity.otherExerciseDays', label: 'Em quantos dias por semana?', min: 0, max: 7 },
      { key: 'activity.sessionMinutes', label: 'Quanto tempo dura uma sessão típica, em minutos?' },
      {
        key: 'activity.sessionIntensity',
        label: 'Qual é a intensidade típica?',
        options: options([
          ['leve', 'Leve'],
          ['moderada', 'Moderada'],
          ['alta', 'Alta'],
        ]),
      },
      {
        key: 'activity.mostlySitting',
        label: 'Fora do treino, você passa a maior parte do dia sentado(a)?',
        options: [
          { value: true, label: 'Sim' },
          { value: false, label: 'Não' },
        ],
      },
      {
        key: 'activity.activityLevel',
        label: 'Nível de atividade',
        preselected: context.currentActivityLevel,
        initiallyConfirmed: false,
        options: options([
          ['sedentario', 'Sedentário'],
          ['leve', 'Leve'],
          ['moderado', 'Moderado'],
          ['alto', 'Alto'],
          ['atleta', 'Atleta'],
        ]),
        hint: 'Leve: 1–3 sessões/semana; Moderado: 4–5; Alto: 6–7; Atleta: dois treinos por dia. O nível precisa ser confirmado; a frequência sozinha não muda as calorias.',
      },
    ]
    questions.push(
      ...activityQuestions.map(
        (q): ReevaluationQuestion => ({ ...q, optOutLabel: REEVALUATION_OPT_OUT_LABEL }),
      ),
    )
  }
  if (isFullReevaluationKind(context.kind)) {
    add('healthCheck')
    const health = questions[questions.length - 1]
    if (health)
      health.options = [
        ...HEALTH_RISK_ITEMS.filter(
          (item) => item.applicability === 'all' || context.sex !== 'masculino',
        ).map((item) => ({ value: item.code, label: item.label })),
        { value: 'none', label: 'Nenhuma destas' },
      ]
    if (context.holdActive) add('professionalConversationConfirmed')
  }
  return {
    questions,
    preferenceQuestion:
      context.phase !== null && isFullReevaluationKind(context.kind)
        ? {
            label: 'Você tem uma meta em mente? (opcional)',
            optional: true as const,
            options: options([
              ['weight', 'Um peso (kg)'],
              ['body_fat', 'Um percentual de gordura (%)'],
              ['routine', 'Uma meta de rotina'],
              ['follow_app', 'Prefiro seguir as metas do app'],
              ['professional', 'Prefiro definir com um profissional'],
              ['skip', 'Pular'],
            ]),
            routineOptions: options([
              ['regular_training', 'Treinar com regularidade'],
              ['more_energy', 'Ter mais disposição no dia a dia'],
              ['organized_food', 'Organizar melhor minha alimentação'],
              ['maintain_weight', 'Manter meu peso atual'],
            ]),
            existingActions: ['keep', 'change', 'remove'] as const,
          }
        : null,
    supportText:
      context.phase !== null &&
      context.kind !== 'TRANSITION_FULL' &&
      isFullReevaluationKind(context.kind) &&
      context.confirmedMealDays !== null
        ? `Você registrou refeições em ${context.confirmedMealDays} dos últimos 14 dias.`
        : null,
    photoRequirement: {
      required: requiresReevaluationPhotos(context.kind),
      newOnly: true as const,
      poses: ['front', 'side', 'back'] as const,
    },
    decisionPriority:
      context.phase === null
        ? []
        : (['safety_exit', 'phase_or_schedule', 'activity_level', 'phase_calories'] as const),
  }
}

/** Mandatory gate for future rule readers; explicit unknown never opens a guard. */
export function getKnownReevaluationAnswers<K extends ReevaluationAnswerKey>(
  input: unknown,
  keys: readonly K[],
):
  | { status: 'known'; values: Pick<ReevaluationAnswers, K> }
  | { status: 'missing'; missing: { key: K; label: string; message: string }[] } {
  const draft = parseReevaluationFormDraft(input)
  const values: Partial<ReevaluationAnswers> = {}
  const missing: { key: K; label: string; message: string }[] = []
  for (const key of keys) {
    if (!Object.hasOwn(labels, key)) throw new Error('Unknown reevaluation answer key')
    if (
      draft.phase === null &&
      !(
        'legacyOrigin' in draft
          ? [
              'weightKg',
              'strengthSessions',
              'hunger',
              'activity',
              'healthCheck',
              'professionalConversationConfirmed',
            ]
          : ['weightKg', 'healthCheck', 'professionalConversationConfirmed']
      ).includes(key)
    )
      throw new Error('Answer is outside this health-only review')
    const value = draft.answers[key]
    if (
      value === null ||
      value === 'nao_sei_avaliar' ||
      (key === 'activity' && !draft.answers.activity?.activityLevelConfirmed)
    ) {
      const label = labels[key]
      missing.push({
        key,
        label,
        message: `Faltou responder ${label}. Sem essa resposta o app não muda a sua meta nesta reavaliação.`,
      })
    } else Object.assign(values, { [key]: value })
  }
  return missing.length
    ? { status: 'missing', missing }
    : { status: 'known', values: values as Pick<ReevaluationAnswers, K> }
}
