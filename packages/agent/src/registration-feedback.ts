/** C13 pure presentation. A trusted consumer supplies confirmed facts and owns durable replay/CAS. */
import { createHash } from 'node:crypto'
import type { DailyState } from '@mpp/core'
import {
  FLOW_CURATED_PHRASE_CATALOG,
  type FlowPhraseCatalog,
  type FlowPhraseMealKind,
} from './flow-curated-phrase-catalog.js'
import {
  createFlowPhraseRotationState,
  type FlowPhraseRequest,
  selectFlowCuratedPhrase,
} from './flow-curated-phrase-selector.js'
import type { FlowStatusPhraseCursor, FlowStatusPhraseReceipt } from './flow-curated-phrases.js'
import { projectFlowPublicNames } from './flow-public-names.js'

type Nutrients = { kcal: number; protein_g: number; carbs_g: number; fat_g: number }
type FeedbackDayInput = Pick<
  DailyState,
  'local_date' | 'current_protocol' | 'remaining_food_kcal' | 'food_excess_kcal' | 'exercise_kcal'
> & {
  consumed: Pick<DailyState['consumed'], 'calories_kcal' | 'protein_g' | 'carbs_g' | 'fat_g'>
  targets: Pick<DailyState['targets'], 'calories_kcal' | 'protein_g'>
}
export interface RegistrationFeedbackInput {
  userId: string
  registrationId: string
  locale: string | null
  accountName?: string | null
  registration: { status: 'confirmed' } & (
    | {
        kind: 'meal'
        mealKind: FlowPhraseMealKind
        totals: Nutrients
        items: readonly (Nutrients & { food_name: string })[]
      }
    | { kind: 'workout' }
  )
  day: FeedbackDayInput | null
}
export interface RegistrationFeedback {
  schema: 'registration.feedback.v1'
  registration_id: string
  kind: 'meal' | 'workout'
  locale: 'pt-BR' | 'en'
  meal_totals: Nutrients | null
  day:
    | (FeedbackDayInput & { calorie_percentage: number | null; protein_percentage: number | null })
    | null
  lines: {
    key: 'meal_totals' | 'day_calories' | 'day_protein' | 'food_budget' | 'day_unavailable'
    text: string
  }[]
  food_comment: string | null
  incentive: string | null
}

/** Q42 headings are centralized, presentation only; this is not a target/balance calculator. */
export const REGISTRATION_FEEDBACK_CALORIE_LABELS = {
  'pt-BR': {
    recomposicao: 'Limite calórico atingido',
    ganho_massa: 'Meta calórica atingida',
    manutencao: 'Meta diária utilizada',
  },
  en: {
    recomposicao: 'Calorie limit reached',
    ganho_massa: 'Calorie target reached',
    manutencao: 'Daily target used',
  },
} as const
const finiteNonnegative = (value: unknown): value is number =>
  typeof value === 'number' && Number.isFinite(value) && value >= 0
const target = (value: unknown) => value === null || (finiteNonnegative(value) && value > 0)
const nonempty = (value: unknown): value is string =>
  typeof value === 'string' && value.trim().length > 0
const hash = (value: string) => createHash('sha256').update(value).digest('hex')
const roundOne = (value: number) => Math.round(value * 10) / 10
const percent = (value: number, total: number | null) =>
  total === null ? null : roundOne((value / total) * 100)

function validate(
  input: RegistrationFeedbackInput,
  cursor: FlowStatusPhraseCursor | null,
  catalog: FlowPhraseCatalog,
): void {
  if (
    !nonempty(input.userId) ||
    !nonempty(input.registrationId) ||
    input.registration.status !== 'confirmed' ||
    !['meal', 'workout'].includes(input.registration.kind)
  )
    throw new Error('Feedback requires an owned confirmed registration')
  if (
    input.registration.kind === 'meal' &&
    (!['cafe', 'almoco', 'lanche', 'jantar', 'ceia', 'outro'].includes(
      input.registration.mealKind,
    ) ||
      ![
        input.registration.totals.kcal,
        input.registration.totals.protein_g,
        input.registration.totals.carbs_g,
        input.registration.totals.fat_g,
      ].every(finiteNonnegative) ||
      input.registration.items.length < 1 ||
      input.registration.items.length > 30 ||
      input.registration.items.some(
        (row) =>
          !nonempty(row.food_name) ||
          ![row.kcal, row.protein_g, row.carbs_g, row.fat_g].every(finiteNonnegative),
      ))
  )
    throw new Error('Invalid confirmed meal facts')
  const day = input.day
  if (
    day &&
    (!/^\d{4}-\d{2}-\d{2}$/u.test(day.local_date) ||
      (day.current_protocol !== null &&
        !['recomposicao', 'ganho_massa', 'manutencao'].includes(day.current_protocol)) ||
      ![
        day.consumed.calories_kcal,
        day.consumed.protein_g,
        day.consumed.carbs_g,
        day.consumed.fat_g,
      ].every(finiteNonnegative) ||
      !finiteNonnegative(day.exercise_kcal) ||
      !target(day.targets.calories_kcal) ||
      !target(day.targets.protein_g) ||
      ![day.remaining_food_kcal, day.food_excess_kcal].every(
        (value) => value === null || finiteNonnegative(value),
      ))
  )
    throw new Error('Invalid official day facts')
  if (
    cursor &&
    (cursor.schema !== 'flow.phrase-state.v1' ||
      cursor.userId !== input.userId ||
      cursor.catalogVersion !== catalog.version ||
      !Number.isSafeInteger(cursor.ordinal) ||
      cursor.ordinal < 0 ||
      !Array.isArray(cursor.usedTextKeys) ||
      cursor.usedTextKeys.some((key) => !/^[a-f0-9]{64}$/u.test(key)) ||
      new Set(cursor.usedTextKeys).size !== cursor.usedTextKeys.length ||
      cursor.usedTextKeys.length > cursor.ordinal ||
      (cursor.ordinal === 0
        ? cursor.lastTextKey !== null || cursor.usedTextKeys.length > 0
        : cursor.lastTextKey === null || cursor.usedTextKeys.at(-1) !== cursor.lastTextKey))
  )
    throw new Error('Invalid shared phrase cursor')
}

/** New publication only. Resolve a stored event receipt before calling this function. */
export function prepareRegistrationFeedback(
  input: RegistrationFeedbackInput,
  cursor: FlowStatusPhraseCursor | null,
  catalog: FlowPhraseCatalog = FLOW_CURATED_PHRASE_CATALOG,
): {
  feedback: RegistrationFeedback
  nextCursor: FlowStatusPhraseCursor
  receipts: FlowStatusPhraseReceipt[]
  steps: { receipt: FlowStatusPhraseReceipt; nextCursor: FlowStatusPhraseCursor }[]
} {
  validate(input, cursor, catalog)
  const locale = input.locale?.toLowerCase().startsWith('en') ? 'en' : 'pt-BR'
  const en = locale === 'en'
  const number = new Intl.NumberFormat(en ? 'en-US' : 'pt-BR', { maximumFractionDigits: 2 })
  const decimal = new Intl.NumberFormat(en ? 'en-US' : 'pt-BR', {
    minimumFractionDigits: 1,
    maximumFractionDigits: 1,
  })
  const n = (value: number) => number.format(value)
  const d = input.day
  const feedback: RegistrationFeedback = {
    schema: 'registration.feedback.v1',
    registration_id: input.registrationId,
    kind: input.registration.kind,
    locale,
    meal_totals: null,
    day:
      d === null
        ? null
        : {
            local_date: d.local_date,
            current_protocol: d.current_protocol,
            remaining_food_kcal: d.remaining_food_kcal,
            food_excess_kcal: d.food_excess_kcal,
            exercise_kcal: d.exercise_kcal,
            consumed: {
              calories_kcal: d.consumed.calories_kcal,
              protein_g: d.consumed.protein_g,
              carbs_g: d.consumed.carbs_g,
              fat_g: d.consumed.fat_g,
            },
            targets: { calories_kcal: d.targets.calories_kcal, protein_g: d.targets.protein_g },
            calorie_percentage: percent(d.consumed.calories_kcal, d.targets.calories_kcal),
            protein_percentage: percent(d.consumed.protein_g, d.targets.protein_g),
          },
    lines: [],
    food_comment: null,
    incentive: null,
  }
  if (input.registration.kind === 'meal') {
    // Use the total already computed and confirmed by the existing meal writer.
    // Re-summing binary floats here can disagree with its canonical decimal total.
    const confirmed = input.registration.totals
    const totals = {
      kcal: confirmed.kcal,
      protein_g: confirmed.protein_g,
      carbs_g: confirmed.carbs_g,
      fat_g: confirmed.fat_g,
    }
    feedback.meal_totals = totals
    feedback.lines.push({
      key: 'meal_totals',
      text: en
        ? `${n(totals.kcal)} kcal | Protein: ${n(totals.protein_g)} g | Carbohydrates: ${n(totals.carbs_g)} g | Fat: ${n(totals.fat_g)} g`
        : `${n(totals.kcal)} kcal | Proteína: ${n(totals.protein_g)} g | Carboidratos: ${n(totals.carbs_g)} g | Gorduras: ${n(totals.fat_g)} g`,
    })
  }
  const day = feedback.day
  if (day === null)
    feedback.lines.push({
      key: 'day_unavailable',
      text: en
        ? 'The data for this day is unavailable.'
        : 'Os dados deste dia estão indisponíveis.',
    })
  else {
    if (
      ![day.calorie_percentage, day.protein_percentage].every(
        (value) => value === null || finiteNonnegative(value),
      )
    )
      throw new Error('Invalid official day percentage')
    const calorieLabel =
      day.current_protocol === null
        ? en
          ? 'Daily target used'
          : 'Meta diária utilizada'
        : REGISTRATION_FEEDBACK_CALORIE_LABELS[locale][day.current_protocol]
    feedback.lines.push({
      key: 'day_calories',
      text:
        day.calorie_percentage === null || day.targets.calories_kcal === null
          ? `${en ? 'Consumed' : 'Consumido'}: ${n(day.consumed.calories_kcal)} kcal. ${en ? 'Target unavailable' : 'Meta indisponível'}.`
          : `${calorieLabel}: ${decimal.format(day.calorie_percentage)}% (${n(day.consumed.calories_kcal)} / ${n(day.targets.calories_kcal)} kcal)`,
    })
    feedback.lines.push({
      key: 'day_protein',
      text:
        day.protein_percentage === null || day.targets.protein_g === null
          ? `${en ? 'Protein' : 'Proteína'}: ${n(day.consumed.protein_g)} g. ${en ? 'Target unavailable' : 'Meta indisponível'}.`
          : `${en ? 'Protein' : 'Proteína'}: ${decimal.format(day.protein_percentage)}% (${n(day.consumed.protein_g)} / ${n(day.targets.protein_g)} g)`,
    })
    if (day.food_excess_kcal !== null && day.food_excess_kcal > 0)
      feedback.lines.push({
        key: 'food_budget',
        text: en
          ? `Excess: ${n(day.food_excess_kcal)} kcal of food.`
          : `Excedente: ${n(day.food_excess_kcal)} kcal de comida.`,
      })
    else if (day.remaining_food_kcal !== null)
      feedback.lines.push({
        key: 'food_budget',
        text: en
          ? `Remaining: ${n(day.remaining_food_kcal)} kcal for food.`
          : `Restam ${n(day.remaining_food_kcal)} kcal para comida.`,
      })
  }
  const receipts: FlowStatusPhraseReceipt[] = []
  const steps: { receipt: FlowStatusPhraseReceipt; nextCursor: FlowStatusPhraseCursor }[] = []
  let state =
    cursor === null
      ? createFlowPhraseRotationState(input.userId, catalog.version)
      : { ...cursor, replayByEventKey: {} }
  const prefix = `mobile_registration/${input.userId}/${input.registrationId}`
  const select = (request: FlowPhraseRequest) => {
    const result = selectFlowCuratedPhrase(request, state, catalog)
    const receipt = result.nextState.replayByEventKey[request.eventKey]
    if (!receipt) throw new Error(`Unable to prepare feedback phrase: ${result.reason}`)
    if (result.phrase !== null && hash(result.phrase) !== result.nextState.lastTextKey)
      throw new Error('Invalid feedback phrase projection')
    state = result.nextState
    const publicReceipt = { eventKey: request.eventKey, ...receipt }
    receipts.push(publicReceipt)
    const { replayByEventKey: _eventReceipts, ...stepCursor } = state
    steps.push({ receipt: publicReceipt, nextCursor: stepCursor })
    return result.phrase
  }
  const common = { userId: input.userId, locale: input.locale, accountName: input.accountName }
  if (input.registration.kind === 'meal')
    feedback.food_comment = select({
      ...common,
      eventKey: `${prefix}/food`,
      kind: 'food',
      items: input.registration.items,
      mealKind: input.registration.mealKind,
    })
  feedback.incentive =
    input.registration.kind === 'workout'
      ? select({ ...common, eventKey: `${prefix}/incentive`, kind: 'workout' })
      : select({ ...common, eventKey: `${prefix}/incentive`, kind: 'incentive', slot: 'any' })
  feedback.lines = feedback.lines.map((row) => ({
    ...row,
    text: projectFlowPublicNames(row.text, { accountName: input.accountName }).text,
  }))
  const { replayByEventKey: _receipts, ...nextCursor } = state
  return { feedback, nextCursor, receipts, steps }
}
