/**
 * "Does my workout free more food?" — answered by the system, not the model.
 * Pure module, no I/O. Flow channel only (the pipeline gates the call).
 *
 * iPhone, staging, 2026-10-04 — in the Flow chat the patient wrote
 *   "Treinei musculacao hoje e gastei 322 kcal. Posso comer 322 kcal a mais?"
 * and Flow answered "Sim! Sua meta já considera esse gasto…". The rule is the
 * opposite (docs/CALCULO-MPP.md §2): food = consumed − target, WITHOUT
 * exercise; the workout never raises what is left to eat.
 *
 * Judging the model's text by regex was rejected in review: an answer such as
 * "Sim! A meta continua 2.980 kcal… você tem 322 kcal de folga" passes any
 * "states the rule" check. So the DIRECT question gets a deterministic answer
 * built from the day's numbers, and everything else goes to the model with
 * the corrected context (flow-energy-context.ts).
 *
 * The predicate is a strict whitelist: a miss still reaches the model with the
 * right numbers; a false positive silences an unrelated message with a canned
 * text. When in doubt it does NOT match.
 */
import { eatingBalance } from '@mpp/core'

export interface ExerciseFoodDay {
  /** The day's target as the Flow context shows it; null when there is none. */
  caloriesTarget: number | null
  caloriesConsumed: number
  /** Exercise of the day in the database (not what the patient typed). */
  exerciseCalories: number
  protocol: string | null
}

// ---------------------------------------------------------------------------
// Predicate — a whitelist grammar over the WHOLE message
// ---------------------------------------------------------------------------
//
// The first version looked for the question anywhere in the message and kept
// lists of what to exclude. Review 2026-10-04 proved it hijacked unrelated
// messages (a workout to create or delete, a symptom, a patient who did not
// train, "o que posso comer a mais?", another person…): no exclusion list is
// ever complete. So this is the opposite: the message is accepted only when
// EVERY word of it belongs to
//   (greeting) + first-person past report of today's workout + direct question
// in either order. One leftover word and the model answers.
//
// Round 2 of the review narrowed it again: no question stands without the
// report ("treino" is also the workout plan and the routine in the profile),
// and a message that ends as a statement ("…consigo comer mais.") is not a
// question.

const MAX_LENGTH = 160

/**
 * The message as words and numbers separated by one space. "/" is a sentence
 * break or a comma, "?" a question mark, "#" any symbol the grammar does not
 * know (emoji, "+", quotes…) — no rule accepts "#". "1.200 kcal" reads as 1200
 * (pt-BR thousands) and "5,5 km" as 5.5.
 */
function tokenize(text: string): string {
  const flat = text
    .normalize('NFD')
    .replace(/[̀-ͯ]/g, '')
    .toLowerCase()
    .replace(/(\d)\.(?=\d{3}(?!\d))/g, '$1')
    .replace(/(\d),(?=\d)/g, '$1.')
    .replace(/[\r\n]+/g, ' . ')
  const out: string[] = []
  for (const piece of flat.match(/\d+(?:\.\d+)?|[a-z]+|[^\sa-z\d]+/g) ?? []) {
    if (/^[\da-z]/.test(piece)) {
      out.push(piece)
      continue
    }
    if (!/^[.,;:!?…]+$/.test(piece)) {
      out.push('#')
      continue
    }
    const mark = piece.includes('?') ? '?' : '/'
    const last = out[out.length - 1]
    // Punctuation runs collapse into one break; a question mark wins.
    if (last === '/' || last === '?') {
      if (mark === '?') out[out.length - 1] = '?'
    } else {
      out.push(mark)
    }
  }
  while (out[0] === '/') out.shift()
  while (out[out.length - 1] === '/' || out[out.length - 1] === '?') out.pop()
  return out.join(' ')
}

const oneOf = (...alternatives: string[]): string => `(?:${alternatives.join('|')})`
const whole = (pattern: string): RegExp => new RegExp(`^${pattern}$`)

const N = String.raw`\d+(?:\.\d+)?`
const KCAL = '(?:kcal|kcals|calorias|cal)'
const TODAY = '(?:hoje|hj)'

// ── Workout report: first person, past tense, affirmative, today or no day ──
const MODALITY =
  '(?:musculacao|academia|treino|cardio|bike|esteira|crossfit|pilates|funcional|corrida|natacao|caminhada|spinning|luta|yoga|futebol)'
const DURATION = `${N} (?:min|mins|minuto|minutos|h|hora|horas|km)`
const WORKOUT = oneOf(
  `treinei(?: (?:${MODALITY}|na academia))?`,
  'malhei',
  'corri',
  'nadei',
  'pedalei',
  'caminhei',
  `fiz(?: ${DURATION} de)?(?: (?:um|uma|o|a|meu|minha))? ${MODALITY}`,
  'fui (?:na|a|pra|para a) academia',
)
// "hoje", "agora cedo", "1 hora", "10 km", "pesado" — nothing else.
const DETAIL = oneOf(TODAY, 'agora', 'cedo', 'de manha', 'de tarde', DURATION, 'pesado', 'leve')
const BURNED = `(?:gastei|queimei)(?: (?:umas|uns))? ${N} ${KCAL}`
const REPORT = oneOf(
  // "treinei musculacao hoje e gastei 322 kcal"
  `(?:${TODAY} )?(?:eu )?${WORKOUT}(?: ${DETAIL}){0,3}(?:(?: e| /)? ${BURNED})?`,
  // "queimei 322 kcal na academia"
  `(?:${TODAY} )?(?:eu )?${BURNED} (?:no|na|de|com o|com a) ${MODALITY}(?: (?:de )?${TODAY}| agora)?`,
)

// ── Direct question ─────────────────────────────────────────────────────────
// First person only: "pode" / "ele pode" is about somebody else. "Consigo" is
// not a permission verb: in "treinei e consigo comer mais" it is capacity or
// appetite, which a ganho-de-massa patient reports as good news.
const CAN = '(?:(?:eu )?posso|da (?:pra|para)(?: eu)?)'
const MUST = '(?:(?:eu )?(?:posso|devo|preciso|tenho que)|da (?:pra|para)(?: eu)?)'
const MORE = '(?:a mais|mais|extra|extras)'
const OF_THE_WORKOUT = '(?:do treino|que (?:eu )?(?:gastei|queimei) no treino)'
const BURNED_CALORIES = oneOf(
  OF_THE_WORKOUT,
  'que (?:eu )?(?:gastei|queimei)',
  'gastas',
  'queimadas',
)
// "Certo" closes a question only after a pause ("…a mais, certo?"); glued to
// the verb it is an adverb ("comer mais certo").
const QUESTION_END = `(?: (?:${TODAY}|agora))?(?:(?: /)? (?:ne|entao)| / certo)?`

// The question names the workout itself. It still needs the report next to
// it: after a plan suggestion "o treino muda minha meta?" is about the plan,
// and "minha meta muda quando eu treino?" is about the rule in general.
const NAMES_THE_WORKOUT = oneOf(
  // "posso comer as calorias do treino"
  `${CAN} comer (?:essas|as) (?:${N} )?${KCAL} ${OF_THE_WORKOUT}(?: ${MORE})?`,
  // "preciso repor as calorias do treino"
  `${MUST} (?:repor|comer de volta)(?: (?:as|essas|esses|os))?(?: ${N})? ${KCAL} ${OF_THE_WORKOUT}`,
  // "o treino aumenta minha meta"
  `(?:o|meu) (?:treino|exercicio)(?: de ${TODAY})? (?:aumenta|muda|altera|sobe) (?:a|minha|a minha) meta(?: (?:de ${TODAY}|${TODAY}|de calorias|calorica))?`,
  // "a meta aumenta com o treino"
  `(?:a|minha|a minha) meta(?: de ${TODAY})? (?:aumenta|muda|sobe) (?:com o treino|porque treinei|quando (?:eu )?treino|ja que treinei)`,
)
// "A mais" of what is not said: only the report next to it makes it the
// workout question ("posso comer mais?" alone is about anything).
const EATS_MORE = oneOf(
  // "posso comer mais", "… 322 kcal a mais", "… um pouco a mais", "… 322 a mais"
  `${CAN} comer(?: (?:${N}(?: ${KCAL})?|um pouco|um pouquinho))? ${MORE}`,
  // "posso comer mais 400 kcal", "… mais um pouco", "… mais calorias"
  `${CAN} comer mais (?:${N} ${KCAL}|um pouco|um pouquinho|${KCAL})`,
  // "posso comer 322 kcal" — accepted only as an echo of the report, see below
  `${CAN} comer ${N} ${KCAL}`,
  // "posso comer essas 322 kcal" (an echo of the report too), "… essas calorias a mais"
  `${CAN} comer (?:essas|as) (?:${N} )?${KCAL}(?: ${BURNED_CALORIES})?(?: ${MORE})?`,
  // "preciso repor as calorias", "posso comer de volta essas calorias"
  `${MUST} (?:repor|comer de volta)(?: (?:as|essas|esses|os))?(?: ${N})? ${KCAL}(?: ${BURNED_CALORIES})?`,
)
// "minha meta aumenta", "a meta de hoje muda"
const TARGET_MOVES = `(?:a|minha|a minha) meta(?: de ${TODAY})? (?:aumenta|muda|sobe)`
const AFTER_THE_REPORT = oneOf(
  EATS_MORE,
  NAMES_THE_WORKOUT,
  TARGET_MOVES,
  // "isso aumenta minha meta": "isso" is the workout just reported
  `isso (?:aumenta|muda|altera|sobe) (?:a|minha|a minha) meta(?: (?:de ${TODAY}|${TODAY}|de calorias|calorica))?`,
)
// Question first: only the forms that the report can follow as a reason.
const BEFORE_THE_REPORT = oneOf(EATS_MORE, TARGET_MOVES)

// ── Whole message ───────────────────────────────────────────────────────────
const GREETING = '(?:(?:oi|ola|bom dia|boa tarde|boa noite|flow)(?: /)? )*'
// A "?" between report and question is not accepted: "treinei hoje?" asks,
// it does not report.
const THEN = '(?: /)?(?: (?:e entao|e por isso|e|entao|por isso))?'
const BECAUSE = oneOf('(?: /)? (?:porque|ja que)', ' [/?]')
// Both orders carry the report: there is no form with the question alone.
const MESSAGE = [
  // "(como|já que) treinei…, posso comer mais?"
  whole(`${GREETING}(?:(?:como|ja que) )?${REPORT}${THEN} ${AFTER_THE_REPORT}${QUESTION_END}`),
  // "posso comer mais porque treinei?", "minha meta aumenta porque treinei?"
  whole(`${GREETING}${BEFORE_THE_REPORT}${QUESTION_END}${BECAUSE} ${REPORT}`),
]

// A number with no unit ("comer 322 a mais") or calories with no "a mais"
// ("comer 322 kcal") could be a food portion or a meal size, and "essas 500
// kcal" may point at a food quoted earlier in the chat. Each is the workout
// question only when it repeats the calories the patient just reported.
const QUESTION_NUMBER = new RegExp(`\\bcomer ((?:essas|as) )?(${N})( ${KCAL})?( ${MORE})?(?: |$)`)
const REPORTED_BURN = new RegExp(`\\b(?:gastei|queimei)(?: (?:umas|uns))? (${N}) ${KCAL}(?: |$)`)

function reportedBurn(message: string): number | null {
  const burned = REPORTED_BURN.exec(message)
  return burned ? Number(burned[1]) : null
}

function numberEchoesTheReport(message: string): boolean {
  const asked = QUESTION_NUMBER.exec(message)
  if (!asked) return true
  const [, demonstrative, number, unit, more] = asked
  // "comer 500 kcal a mais" names calories on top of the day by itself.
  if (!demonstrative && unit && more) return true
  return reportedBurn(message) === Number(number)
}

// The tokenizer drops the final mark, so the raw text is read here: a message
// with no "?" that ends in a mark states, it does not ask ("Treinei hoje e
// posso comer mais!"). With no final mark at all (voice, fast typing) the
// question mark stays optional. Closing quotes and spaces are skipped.
const ENDS_WITH_A_MARK = /[.!…,;:][\s"'”’»]*$/

function endsAsStatement(rawText: string): boolean {
  return !rawText.includes('?') && ENDS_WITH_A_MARK.test(rawText)
}

/**
 * True only when the ENTIRE message is (greeting) + "I trained today (and
 * burned N kcal)" + the direct question "may I eat (N kcal) more / must I
 * replace it / does the workout raise my target?", in either order, in
 * Portuguese. Anything else in it — another request, a symptom, a food, another
 * day or person, "o que", "mas", a negation — returns false. So does the
 * question with no report, and a message that ends as a statement.
 */
export function asksExerciseFoodQuestion(patientText: string): boolean {
  const raw = patientText ?? ''
  if (endsAsStatement(raw)) return false
  const message = tokenize(raw)
  if (message.length === 0 || message.length > MAX_LENGTH) return false
  if (!MESSAGE.some((form) => form.test(message))) return false
  return numberEchoesTheReport(message)
}

/**
 * The calories the patient says the workout burned ("gastei 400 kcal"), or
 * null when the message gives none. Only for the answer's wording: the numbers
 * of the answer always come from the database.
 */
export function statedWorkoutCalories(patientText: string): number | null {
  return reportedBurn(tokenize(patientText ?? ''))
}

// ---------------------------------------------------------------------------
// Answer
// ---------------------------------------------------------------------------

/** How every variant of the answer opens. */
export const EXERCISE_FOOD_ANSWER_OPENING = 'O treino não aumenta o que você pode comer hoje'

// Said instead of any claim about "the workout" when the day has none stored:
// the Flow chat does not register workouts, so typing "treinei e gastei 322
// kcal" stores nothing, and the block receives nothing either.
const NO_WORKOUT_STORED =
  'Não encontrei treino registrado hoje. Quando você registrar o treino no app, o gasto fica à parte e não entra no que resta para comida.'

// Added when the patient typed a burn that is not the stored one: the number
// in the answer is the app's, and nothing is said about the workout he cited.
const STORED_VALUE_NOTE = 'Esse é o valor registrado no app.'

/**
 * True when the last thing Flow said in this conversation is, character by
 * character (after trimming), the text the system would send NOW. Only then is
 * the patient not helped by the system answering: the model answers, with the
 * corrected context. A system answer with other numbers (the day moved on), to
 * another state, or from a previous day (the history loader dates it) is a
 * different text, so the system answers again — a prefix test here once sent
 * the report phrase to the model for the rest of the day.
 */
export function lastReplyIsSameAnswer(
  history: ReadonlyArray<{ role: 'user' | 'assistant'; content: string }>,
  answer: string,
): boolean {
  for (let index = history.length - 1; index >= 0; index -= 1) {
    const message = history[index]
    if (message?.role === 'assistant') return message.content.trim() === answer.trim()
  }
  return false
}

/** "2.980" — pt-BR thousands, written out so it never depends on the ICU build. */
function kcal(value: number): string {
  return String(Math.round(Math.abs(value))).replace(/\B(?=(\d{3})+(?!\d))/g, '.')
}

/**
 * The answer to the direct question, in plain text (no Markdown), built only
 * from the day's numbers. It does not open with "Não": the patient may still
 * have food left — just not because of the workout.
 *
 * `statedCalories` is what the patient typed as burned, if anything; it never
 * enters a number of the answer, it only adds the note that the workout
 * calories shown are the stored ones.
 *
 * Wording is patient-facing clinical text: needs Roberto's review.
 */
export function renderExerciseFoodAnswer(
  day: ExerciseFoodDay,
  statedCalories: number | null = null,
): string {
  const target =
    day.caloriesTarget != null && Number.isFinite(day.caloriesTarget) && day.caloriesTarget > 0
      ? Math.round(day.caloriesTarget)
      : null
  const consumed = Number.isFinite(day.caloriesConsumed) ? Math.round(day.caloriesConsumed) : 0
  const exercise = Number.isFinite(day.exerciseCalories) ? Math.round(day.exerciseCalories) : 0
  // Block wording only in recomposição; whether exercise enters the day
  // balance in ganho de massa / manutenção is Roberto's open decision.
  const recomp = day.protocol === 'recomposicao'
  const food = target == null ? null : eatingBalance(consumed, target)

  // What the workout does NOT do, said against the state of the day.
  const plural = exercise !== 1
  const doesNot =
    food == null || food < 0
      ? plural
        ? 'não entram no que resta para comida'
        : 'não entra no que resta para comida'
      : food === 0
        ? plural
          ? 'não liberam mais comida'
          : 'não libera mais comida'
        : plural
          ? 'não apagam esse excedente'
          : 'não apaga esse excedente'
  // "Registradas hoje": the number is the app's, whatever the patient typed
  // (the Flow chat stores no workout; an earlier one may be all there is).
  const subject = plural
    ? `As ${kcal(exercise)} kcal de treino registradas hoje`
    : 'A 1 kcal de treino registrada hoje'
  const storedSentence = recomp
    ? `${subject} ${plural ? 'aceleram' : 'acelera'} o bloco de 7.700 kcal, mas ${doesNot}.`
    : `${subject} ${plural ? 'ficam' : 'fica'} à parte e ${doesNot}.`
  const statedAnotherNumber =
    statedCalories != null &&
    Number.isFinite(statedCalories) &&
    Math.round(statedCalories) !== exercise
  const exerciseSentence =
    exercise <= 0
      ? NO_WORKOUT_STORED
      : statedAnotherNumber
        ? `${storedSentence} ${STORED_VALUE_NOTE}`
        : storedSentence

  if (target == null || food == null) {
    return `${EXERCISE_FOOD_ANSWER_OPENING}: a meta do dia não muda com exercício.\n\n${exerciseSentence}`
  }

  const left = Math.abs(food) === 1 ? 'resta 1 kcal' : `restam ${kcal(food)} kcal`
  const foodSentence =
    food < 0
      ? consumed === 0
        ? `Você ainda não tem consumo lançado hoje, então ${left} para comer hoje (meta menos consumido).`
        : `Você consumiu ${kcal(consumed)} kcal, então ${left} para comer hoje (meta menos consumido).`
      : food === 0
        ? `Você consumiu ${kcal(consumed)} kcal, então você já bateu a meta de hoje.`
        : `Você consumiu ${kcal(consumed)} kcal, então você está ${kcal(food)} kcal acima da meta (consumido menos meta).`

  return `${EXERCISE_FOOD_ANSWER_OPENING}: sua meta continua em ${kcal(target)} kcal.\n\n${foodSentence} ${exerciseSentence}`
}
