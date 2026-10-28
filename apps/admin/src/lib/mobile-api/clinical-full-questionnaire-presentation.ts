/** Closed presentation vocabulary. Clinical field presence and option tokens
 * remain owned by the shared descriptor, never duplicated in the client. */
import type { ReevaluationQuestion } from '@mpp/core/reevaluation-form'
import { clinicalFullError } from './clinical-full-contracts'

export type ClinicalQuestionnaireLocale = 'pt-BR' | 'en-US'
const englishQuestions: Record<ReevaluationQuestion['key'], string> = {
  weightKg: 'What is your weight today?',
  strengthSessions: 'How many strength sessions per week did you do in the last 14 days?',
  adherence: 'In the last 14 days, how closely did your meals follow the plan?',
  hunger: 'How hungry did you feel on average?',
  energy: 'How was your energy during the day?',
  strengthProgression: 'Compared with the previous 14 days, your strength training…',
  fatPerception: 'Have you noticed an increase in body fat?',
  difficultToMaintain: 'Is the plan difficult to maintain?',
  healthCheck: 'Do any of these situations apply to you now? Select all that apply.',
  professionalConversationConfirmed: 'I have discussed what I reported with a professional.',
  'activity.otherExerciseType': 'What other exercise do you do?',
  'activity.otherExerciseDays': 'On how many days per week?',
  'activity.sessionMinutes': 'How long is a typical session, in minutes?',
  'activity.sessionIntensity': 'What is the typical intensity?',
  'activity.mostlySitting': 'Outside training, do you spend most of the day sitting?',
  'activity.activityLevel': 'Activity level',
}
const englishOptions: Record<string, string> = {
  bem_consistente: 'Very consistent',
  mais_ou_menos: 'Somewhat consistent',
  pouco_consistente: 'Not very consistent',
  pouca: 'Low',
  moderada: 'Moderate',
  muita: 'High',
  boa: 'Good',
  ok: 'Okay',
  baixa: 'Low',
  melhorou: 'Improved',
  ficou_parecido: 'Stayed similar',
  piorou_ou_travou: 'Worsened or stalled',
  nao_sei_avaliar: 'I cannot tell',
  nao_percebi: 'I have not noticed',
  um_pouco: 'A little',
  claramente: 'Clearly',
  nao: 'No',
  sim: 'Yes',
  leve: 'Light',
  alta: 'High',
  sedentario: 'Sedentary',
  moderado: 'Moderate',
  alto: 'High',
  atleta: 'Athlete',
  true: 'Yes',
  false: 'No',
  none: 'None of these',
  unintended_weight_loss: 'I lost weight without intending to',
  reduced_intake: 'I am eating much less than planned or skipping meals',
  persistent_fatigue_weakness_dizziness:
    'Strong fatigue, weakness or dizziness that does not go away',
  menstrual_change: 'Irregular or absent periods',
  loss_of_control_eating: 'I felt I lost control over how much I was eating',
  appetite_weight_treatment: 'I use medication or treatment that changes appetite or weight',
  professional_diet:
    'A professional manages my food or protein intake because of a health condition',
  pregnant_or_breastfeeding: 'I am pregnant or breastfeeding',
  weight: 'A weight (kg)',
  body_fat: 'A body fat percentage (%)',
  routine: 'A routine goal',
  follow_app: 'I prefer to follow the app’s goals',
  professional: 'I prefer to decide with a professional',
  skip: 'Skip',
  regular_training: 'Train regularly',
  more_energy: 'Have more energy during the day',
  organized_food: 'Organize my meals better',
  maintain_weight: 'Maintain my current weight',
}
export function questionnaireOption<T extends string | boolean>(
  option: { value: T; label: string },
  locale: ClinicalQuestionnaireLocale,
) {
  const label = locale === 'pt-BR' ? option.label : englishOptions[String(option.value)]
  if (!label) throw clinicalFullError('unavailable')
  return { value: option.value, label }
}
function control(key: ReevaluationQuestion['key']) {
  switch (key) {
    case 'weightKg':
      return { input_kind: 'decimal' as const, unit: 'kg' as const }
    case 'strengthSessions':
    case 'activity.otherExerciseDays':
      return { input_kind: 'integer' as const, unit: 'per_week' as const }
    case 'activity.sessionMinutes':
      return { input_kind: 'decimal' as const, unit: 'minutes' as const }
    case 'activity.otherExerciseType':
      return { input_kind: 'text' as const, unit: null }
    case 'activity.mostlySitting':
    case 'professionalConversationConfirmed':
      return { input_kind: 'boolean' as const, unit: null }
    case 'healthCheck':
      return { input_kind: 'health_selection' as const, unit: null }
    default:
      return { input_kind: 'single_choice' as const, unit: null }
  }
}
export function questionnaireQuestion(
  q: ReevaluationQuestion,
  locale: ClinicalQuestionnaireLocale,
  kind?: string,
) {
  const transitionQuestions: Partial<Record<ReevaluationQuestion['key'], string>> = {
    strengthSessions: 'How many strength sessions per week do you currently do?',
    adherence: 'How closely do your meals currently follow the plan?',
    strengthProgression: 'How is your strength training progressing now?',
  }
  const label =
    locale === 'pt-BR'
      ? q.label
      : ((kind === 'TRANSITION_FULL' ? transitionQuestions[q.key] : undefined) ??
        englishQuestions[q.key])
  if (!label) throw clinicalFullError('unavailable')
  return {
    key: q.key,
    label,
    ...control(q.key),
    opt_out_label: locale === 'pt-BR' ? q.optOutLabel : 'Prefer not to answer',
    options: q.options?.map((o) => questionnaireOption(o, locale)) ?? null,
    min: q.min ?? null,
    max: q.max ?? null,
    preselected: q.preselected ?? null,
    initially_confirmed: q.initiallyConfirmed ?? null,
    hint: !q.hint
      ? null
      : locale === 'pt-BR'
        ? q.hint
        : 'Light: 1–3 sessions/week; Moderate: 4–5; High: 6–7; Athlete: two sessions a day. Confirm the level explicitly; frequency alone does not change calories.',
  }
}
