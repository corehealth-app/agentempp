/**
 * Flow only (app Performe AI): plain words for a workout suggestion.
 *
 * Audit 2026-10-10, owner's words: "quando ele monta o treino, está muito
 * tecnico os termos usados, precisam ser mais simples para facilitar o
 * entendimento do usuario". The person read "Push/Pull/Legs", "RPE 8-9",
 * "falha técnica", "progressão linear", "reps", "compostos/isoladores",
 * "pegada pronada", "retração escapular" in the draft and in the chat.
 *
 * Two layers, both on the app-only proposal tool (`propoe_plano_treino`):
 *  1. the request to the generator asks for everyday words
 *     (training-plan-generator.ts, Flow branches only);
 *  2. `projectFlowPlainTrainingDraft` is the deterministic net: it is applied
 *     ONCE to the candidate, before it is assessed and stored. The chat text
 *     is rendered from the stored draft, so the chat and the Plan tab show
 *     the same words.
 *
 * The net is a CLOSED VOCABULARY with structural guards, like
 * flow-public-names.ts. It replaces the spellings of the table below and
 * nothing else; it does not rewrite a sentence and it reads no meaning. A
 * term outside the table goes through untouched and is left to the request.
 * When in doubt a rule leaves the generated word: a wrong replacement is
 * stored for good, a technical word left is what the app showed before.
 *
 * THE RULES (each one is pinned in flow-plain-training-language.test.ts):
 *  1. Sentence by sentence, left to right, over the text normalised to NFC.
 *     At a position the longer spelling wins. A sentence is read again until
 *     nothing changes: no output carries a spelling, so an output is never
 *     replaced, but a term that was kept because of its neighbour ("Core" in
 *     "Leg day - Core") is read without it once the neighbour was a term too.
 *     A text in which no row acts comes back as the very same string (not
 *     normalised).
 *  2. Whole words only: a spelling glued to a letter, a digit, "_", "@" or
 *     "-" is not the term ("reps_range", "Push-up", "Pulldown", "score").
 *     "/", "+", brackets and punctuation are NOT glue: both sides of
 *     "Isquiotibiais/Glúteos" are read. One exception, written: a digit glued
 *     before reps/rep ("12reps" → "12 repetições").
 *     A LETTER is a letter of the Latin alphabet, with or without an accent
 *     (A–Z, a–z and every letter up to U+024F, "ª", "º" and "µ" included); a
 *     DIGIT is 0–9 or one of "²", "³", "¹", "¼", "½", "¾". Up to U+024F that
 *     is exactly what Unicode calls a letter and a number. Beyond it nothing
 *     is glue: "→", "–", "—", "…", curly quotes and emoji never were, and a
 *     letter or a number of another alphabet (Greek, Cyrillic, …) no longer
 *     is ("Coreж" is read as "Core").
 *  3. An address is protected as a span (a scheme "://", "www.", or the
 *     target of a Markdown link).
 *  4. The English division words. Every `division` row and the six loose
 *     words (`division_word`: Push, Pull, Legs, Upper, Lower, Core) do not
 *     act in an exercise NAME nor in the EQUIPMENT list. Elsewhere a loose
 *     word does not act when its neighbour, on either side, separated only
 *     by spaces, is in the closed list of English neighbours ("Pull Up",
 *     "Face Pull", "Band Pull Apart", "Upper back").
 *  5. "falha" (alone or with técnica / muscular / concêntrica) only after
 *     "até a", "até à", "até", "à", "próximo da", "próximo à", "perto da",
 *     "antes da". After a bare "até" the article is added ("até falha" →
 *     "até a última repetição bem feita"). After a lone "à" it is not the
 *     term when "de", "do", "da", "dos", "das", "na", "no", "nas", "nos" or
 *     "em" follows ("devida à falha na execução"). "Corrija qualquer falha
 *     técnica" and "se a técnica falha" are not the term.
 *  6. composto(s), multiarticular(es), isolador(es), monoarticular(es) and
 *     uniarticular(es) ALONE only in noun position: at the start of the
 *     field; after . ! ? : ; , ( • — or a line break; or right after o, os,
 *     do, dos, no, nos, ao, aos, pelo, pelos, e, ou, de, com, em, entre,
 *     para. Never before por, pelo, pela, de, da, do, dos, das ("composto por
 *     5 dias"), nor before a word of the substance ("composto vitamínico",
 *     "compostos químicos"). After any other word ("um composto seguro",
 *     "treino composto", "priorize compostos") they stay. "isolado(s)" alone is never replaced. The whole
 *     entries (exercício/movimento + the adjective) act anywhere, except
 *     before por, pelo, pela, pelos, pelas.
 *  7. Capital letter: at the start of the field, of a sentence or of a line
 *     the output follows the case of the first letter of what it replaces;
 *     anywhere else it is lower case. A row whose output changes gender or
 *     number carries the determiners it swaps (`articles`).
 *  8. No row adds a body position, a joint, a direction, a load or a number
 *     that the replaced word does not say.
 *  9. `rpe_target`: the repeated label leaves when a grade follows ("RPE 8" →
 *     "8") and a written "/10" is spelled out ("8/10" → "8 de 10"). The scale
 *     is added to a bare grade ONLY with the owner's switch.
 * 10. An acronym (a spelling written in capitals: RPE, PSE, RIR, PPL, MMSS,
 *     MMII) is matched in capitals only: "rir" is a verb. "PSE" alone stays
 *     before a word ending in "a" or "as" ("PSE alta"), which agrees with it.
 * 11. RIR and its count (`counted_acronym`). The acronym binds its count to
 *     the right ("RIR 2") and the plain text binds it to the left ("2
 *     repetições de sobra"). With a number on ONE side of the acronym, that
 *     number is the count ("RIR 2", "2 RIR"). With a number on BOTH sides
 *     ("Séries de 12 RIR 2", "Semana 1 RIR 3", "2 RIR: 3") nobody knows which
 *     one is the count: the acronym stays, no word is replaced and no number
 *     moves. A number counts as a side when only spaces separate it from the
 *     acronym (before it, also one dash: "Semana 1 - RIR 3" would read as the
 *     range "1 - 3"; after it, also ":" or "="). After the acronym a range is
 *     the count only when it is written as one ("RIR 2-3"); with spaces
 *     around the dash ("RIR 2 - 3 séries") the second number may be another
 *     thing, so the words take the place of the acronym and no number moves
 *     ("repetições de sobra 2 - 3 séries"). The words ("repetições em
 *     reserva") are renamed in place wherever they are.
 *
 * NUMBERS AND STRUCTURE are never read nor written: plan_type, duration_min,
 * sets, rest_seconds, any unknown key. Every digit of every text is the
 * generator's, in the same order; nothing is derived.
 *
 * LIMITS. Running text (notes, progression_rule, an exercise's notes, each
 * step and each mistake) is replaced sentence by sentence; if the field
 * would pass its limit, the LAST replaced sentences go back to the generated
 * wording until it fits. A single-phrase field (day, focus, muscle_group,
 * name, reps_range, rpe_target, equipment_summary) keeps the generated value
 * whole when the plain one does not fit. Nothing is cut.
 *
 * WHAT WAITS FOR THE OWNER is written here and switched OFF
 * (FLOW_PLAIN_TRAINING_OWNER_SWITCHES): the rows that rename an exercise and
 * the "de 10" scale of the effort grade. No production path passes other
 * switches; they exist so that turning one on is a one-line, tested change.
 *
 * The legacy WhatsApp tool (gera_treino), the menu proposal, the document
 * import and the chat's free text never call this file.
 */

export type FlowPlainTrainingField =
  | 'notes'
  | 'progression_rule'
  | 'equipment_summary'
  | 'day'
  | 'focus'
  | 'name'
  | 'muscle_group'
  | 'reps_range'
  | 'rpe_target'
  | 'exercise_notes'
  | 'execution_steps'
  | 'common_mistakes'

/** How a row is applied beyond "whole word, anywhere" (the rules above). */
export type FlowPlainTrainingRule =
  | 'division'
  | 'division_word'
  | 'effort_grade'
  | 'failure'
  | 'count_unit'
  | 'whole_entry'
  | 'noun_position'
  | 'feminine_plural_phrase'
  | 'feminine_acronym'
  | 'counted_acronym'

/**
 * A row of the vocabulary. A spelling is written as a person reads it:
 * letters match whatever the case and the accents (capitals only when the
 * spelling is an acronym); a space is one or more spaces; "/", "+", "," and
 * "-" accept spaces around them; "<n>" is a count ("2", "1-2") and "<nota>"
 * a grade ("8", "8-9", "7.5", "8/10"), glued or after a space, ":" or "=".
 */
export interface FlowPlainTrainingRow {
  id: string
  spellings: readonly string[]
  plain: string
  /** The output when the count is exactly 1. */
  one?: string
  rule?: FlowPlainTrainingRule
  /** Determiners swapped together with the row, written in lower case. */
  articles?: Readonly<Record<string, string>>
}

const MASCULINE_PLURAL_TO_FEMININE = { os: 'a', dos: 'da', nos: 'na', aos: 'à', pelos: 'pela' }
/** "o Upper" → "a parte de cima do corpo". */
const MASCULINE_TO_FEMININE = { o: 'a', do: 'da', no: 'na', ao: 'à', pelo: 'pela', um: 'uma' }
/** "no Legs" → "nas pernas". */
const MASCULINE_TO_FEMININE_PLURAL = { o: 'as', do: 'das', no: 'nas', ao: 'às', pelo: 'pelas' }
const FEMININE_TO_MASCULINE = { a: 'o', da: 'do', na: 'no', à: 'ao', pela: 'pelo', uma: 'um' }

/** The active table. Editorial text: the owner may strike any row (docs/mobile/api-v1.md). */
export const FLOW_PLAIN_TRAINING_VOCABULARY: readonly FlowPlainTrainingRow[] = [
  // ── Divisions of the week, in English ──
  {
    id: 'push_pull_legs',
    spellings: ['Push/Pull/Legs', 'Push Pull Legs', 'Push-Pull-Legs', 'PPL'],
    plain: 'empurrar/puxar/pernas',
    rule: 'division',
  },
  {
    id: 'upper_lower',
    spellings: ['Upper/Lower', 'Upper-Lower', 'Upper Lower'],
    plain: 'parte de cima/parte de baixo',
    rule: 'division',
    articles: MASCULINE_TO_FEMININE,
  },
  { id: 'full_body', spellings: ['Full Body', 'Full-Body', 'Fullbody'], plain: 'corpo inteiro', rule: 'division' },
  {
    id: 'upper_body',
    spellings: ['Upper body'],
    plain: 'parte de cima do corpo',
    rule: 'division',
    articles: MASCULINE_TO_FEMININE,
  },
  {
    id: 'lower_body',
    spellings: ['Lower body'],
    plain: 'parte de baixo do corpo',
    rule: 'division',
    articles: MASCULINE_TO_FEMININE,
  },
  { id: 'lower_back', spellings: ['Lower back'], plain: 'lombar', rule: 'division', articles: MASCULINE_TO_FEMININE },
  { id: 'push_day', spellings: ['Push day'], plain: 'dia de empurrar', rule: 'division' },
  { id: 'pull_day', spellings: ['Pull day'], plain: 'dia de puxar', rule: 'division' },
  { id: 'leg_day', spellings: ['Leg day', 'Legs day'], plain: 'dia de pernas', rule: 'division' },
  { id: 'push', spellings: ['Push'], plain: 'empurrar', rule: 'division_word' },
  { id: 'pull', spellings: ['Pull'], plain: 'puxar', rule: 'division_word' },
  {
    id: 'legs',
    spellings: ['Legs'],
    plain: 'pernas',
    rule: 'division_word',
    articles: MASCULINE_TO_FEMININE_PLURAL,
  },
  {
    id: 'upper',
    spellings: ['Upper'],
    plain: 'parte de cima do corpo',
    rule: 'division_word',
    articles: MASCULINE_TO_FEMININE,
  },
  {
    id: 'lower',
    spellings: ['Lower'],
    plain: 'parte de baixo do corpo',
    rule: 'division_word',
    articles: MASCULINE_TO_FEMININE,
  },
  { id: 'core', spellings: ['Core'], plain: 'abdômen', rule: 'division_word' },
  { id: 'mmss', spellings: ['MMSS'], plain: 'parte de cima do corpo', articles: MASCULINE_PLURAL_TO_FEMININE },
  { id: 'mmii', spellings: ['MMII'], plain: 'parte de baixo do corpo', articles: MASCULINE_PLURAL_TO_FEMININE },
  // ── Effort ──
  { id: 'rpe_graded', spellings: ['RPE <nota>'], plain: 'esforço <nota>', rule: 'effort_grade' },
  {
    id: 'pse_graded',
    spellings: ['PSE <nota>'],
    plain: 'esforço <nota>',
    rule: 'effort_grade',
    articles: FEMININE_TO_MASCULINE,
  },
  { id: 'rpe', spellings: ['RPE'], plain: 'esforço' },
  {
    id: 'pse',
    spellings: ['PSE'],
    plain: 'esforço',
    rule: 'feminine_acronym',
    articles: FEMININE_TO_MASCULINE,
  },
  {
    id: 'reps_left_counted',
    spellings: ['RIR <n>', '<n> RIR'],
    plain: '<n> repetições de sobra',
    one: '<n> repetição de sobra',
    rule: 'counted_acronym',
  },
  {
    id: 'reps_left',
    spellings: ['RIR', 'repetições em reserva', 'reps em reserva'],
    plain: 'repetições de sobra',
    rule: 'counted_acronym',
  },
  { id: 'rep_left', spellings: ['repetição em reserva', 'rep em reserva'], plain: 'repetição de sobra' },
  {
    id: 'failure',
    spellings: [
      'falha muscular técnica',
      'falha técnica muscular',
      'falha muscular',
      'falha técnica',
      'falha concêntrica',
      'falha',
    ],
    plain: 'última repetição bem feita',
    rule: 'failure',
  },
  // ── Progression and repetitions ──
  { id: 'linear_progression', spellings: ['progressão linear'], plain: 'evolução passo a passo' },
  { id: 'reps', spellings: ['reps'], plain: 'repetições', rule: 'count_unit' },
  { id: 'rep', spellings: ['rep'], plain: 'repetição', rule: 'count_unit' },
  // ── Exercises of many muscles and of one muscle ──
  {
    id: 'compound_exercises',
    spellings: [
      'exercícios compostos',
      'movimentos compostos',
      'exercícios multiarticulares',
      'movimentos multiarticulares',
    ],
    plain: 'exercícios de vários músculos',
    rule: 'whole_entry',
  },
  {
    id: 'compound_exercise',
    spellings: [
      'exercício composto',
      'movimento composto',
      'exercício multiarticular',
      'movimento multiarticular',
    ],
    plain: 'exercício de vários músculos',
    rule: 'whole_entry',
  },
  {
    id: 'isolation_exercises',
    spellings: [
      'exercícios isolados',
      'movimentos isolados',
      'exercícios isoladores',
      'movimentos isoladores',
      'exercícios monoarticulares',
      'movimentos monoarticulares',
      'exercícios uniarticulares',
      'movimentos uniarticulares',
    ],
    plain: 'exercícios de um músculo só',
    rule: 'whole_entry',
  },
  {
    id: 'isolation_exercise',
    spellings: [
      'exercício isolado',
      'movimento isolado',
      'exercício isolador',
      'movimento isolador',
      'exercício monoarticular',
      'movimento monoarticular',
      'exercício uniarticular',
      'movimento uniarticular',
    ],
    plain: 'exercício de um músculo só',
    rule: 'whole_entry',
  },
  {
    id: 'compounds',
    spellings: ['compostos', 'multiarticulares'],
    plain: 'exercícios de vários músculos',
    rule: 'noun_position',
  },
  {
    id: 'compound',
    spellings: ['composto', 'multiarticular'],
    plain: 'exercício de vários músculos',
    rule: 'noun_position',
  },
  {
    id: 'isolations',
    spellings: ['isoladores', 'monoarticulares', 'uniarticulares'],
    plain: 'exercícios de um músculo só',
    rule: 'noun_position',
  },
  {
    id: 'isolation',
    spellings: ['isolador', 'monoarticular', 'uniarticular'],
    plain: 'exercício de um músculo só',
    rule: 'noun_position',
  },
  // ── Grip and shoulder blades ──
  { id: 'overhand_grip', spellings: ['pegada pronada'], plain: 'pegada por cima' },
  { id: 'underhand_grip', spellings: ['pegada supinada'], plain: 'pegada por baixo' },
  {
    id: 'scapular_retraction',
    spellings: ['retração escapular', 'retração das escápulas', 'retração de escápulas'],
    plain: 'postura de ombros para trás',
  },
  {
    id: 'scapulae_retracted',
    spellings: ['escápulas retraídas'],
    plain: 'ombros para trás',
    rule: 'feminine_plural_phrase',
    articles: { as: 'os', das: 'dos', nas: 'nos', às: 'aos', pelas: 'pelos', suas: 'seus' },
  },
  // ── Anatomy ──
  { id: 'hamstrings', spellings: ['isquiotibiais'], plain: 'músculos de trás da coxa' },
  { id: 'hamstring', spellings: ['isquiotibial'], plain: 'músculo de trás da coxa' },
  {
    id: 'calf_muscles_pair',
    spellings: [
      'gastrocnêmio e o sóleo',
      'sóleo e o gastrocnêmio',
      'gastrocnêmio e sóleo',
      'sóleo e gastrocnêmio',
      'gastrocnêmio/sóleo',
      'sóleo/gastrocnêmio',
      'gastrocnêmio, sóleo',
      'sóleo, gastrocnêmio',
      'gastrocnêmio+sóleo',
      'sóleo+gastrocnêmio',
    ],
    plain: 'músculos da panturrilha',
    articles: { o: 'os', do: 'dos', no: 'nos', ao: 'aos', pelo: 'pelos' },
  },
  { id: 'calf_muscles', spellings: ['gastrocnêmios', 'sóleos'], plain: 'músculos da panturrilha' },
  { id: 'calf_muscle', spellings: ['gastrocnêmio', 'sóleo'], plain: 'músculo da panturrilha' },
  { id: 'posterior_chain', spellings: ['cadeia posterior'], plain: 'parte de trás do corpo' },
  { id: 'anterior_chain', spellings: ['cadeia anterior'], plain: 'parte da frente do corpo' },
  {
    id: 'upper_chest',
    spellings: [
      'porção clavicular do peitoral maior',
      'porção clavicular do peitoral',
      'porção clavicular do peito',
      'porção clavicular',
    ],
    plain: 'parte de cima do peito',
  },
  {
    id: 'triceps_heads',
    spellings: [
      'cabeça longa do tríceps braquial',
      'cabeça lateral do tríceps braquial',
      'cabeça medial do tríceps braquial',
      'cabeça longa do tríceps',
      'cabeça lateral do tríceps',
      'cabeça medial do tríceps',
    ],
    plain: 'parte de trás do braço',
  },
  {
    id: 'biceps_heads',
    spellings: [
      'cabeça longa do bíceps braquial',
      'cabeça curta do bíceps braquial',
      'cabeça longa do bíceps',
      'cabeça curta do bíceps',
    ],
    plain: 'parte da frente do braço',
  },
]

/**
 * The rows that RENAME an exercise. Candidates only: each one acts when, and
 * only when, its id is in the owner's switches. "Stiff" and "Leg Press" have
 * no row: the recommendation is to keep the name the gym and the machine use.
 */
export const FLOW_PLAIN_TRAINING_RENAMES_AWAITING_OWNER: readonly FlowPlainTrainingRow[] = [
  {
    id: 'hip_thrust',
    spellings: ['Hip Thrust', 'Hip-Thrust'],
    plain: 'elevação pélvica',
    articles: { o: 'a', do: 'da', no: 'na', ao: 'à', um: 'uma' },
  },
  { id: 'military_press', spellings: ['Military press'], plain: 'desenvolvimento militar' },
]

export interface FlowPlainTrainingOwnerSwitches {
  /** D1: write the scale after an effort grade from 1 to 10 ("9" → "9 de 10"). */
  effortOutOfTen: boolean
  /** D2: ids of FLOW_PLAIN_TRAINING_RENAMES_AWAITING_OWNER the owner approved. */
  renames: readonly string[]
}

/** What production uses. Turning a switch on needs the owner's yes, dated in the doc. */
export const FLOW_PLAIN_TRAINING_OWNER_SWITCHES: FlowPlainTrainingOwnerSwitches = Object.freeze({
  effortOutOfTen: false,
  renames: Object.freeze([] as string[]),
})

/**
 * English words that make a loose Push / Pull / Legs / Upper / Lower / Core
 * part of an exercise or equipment name (rule 4). A closed list.
 */
export const FLOW_PLAIN_TRAINING_ENGLISH_NEIGHBOURS: readonly string[] = [
  // Exercise names.
  ...['Up', 'Ups', 'Down', 'Downs', 'Over', 'Overs', 'Apart', 'Aparts', 'Through', 'Throughs'],
  ...['Around', 'Press', 'Presses', 'Row', 'Rows', 'Jerk', 'Jerks', 'Deadlift', 'Deadlifts'],
  ...['Hold', 'Holds', 'Split', 'Splits', 'Legged', 'Stability'],
  // Equipment.
  ...['Rack', 'Racks', 'Band', 'Bands', 'Cable', 'Cables', 'Sled', 'Sleds', 'Machine', 'Machines'],
  // Body parts, in English.
  ...['Back', 'Body', 'Chest', 'Abs', 'Arm', 'Arms', 'Leg', 'Face', 'Trap', 'Traps', 'Lat', 'Lats'],
  ...['Pec', 'Pecs', 'Glute', 'Glutes', 'Limb', 'Limbs'],
  // Session words, in English.
  ...['Day', 'Days', 'Workout', 'Workouts', 'Training', 'Session', 'Sessions', 'Exercise'],
  ...['Exercises', 'Movement', 'Movements', 'Routine', 'Strength', 'Work'],
]

// ── Patterns ────────────────────────────────────────────────────────────────
const SP = String.raw`[ \t\u00A0]`
/**
 * Rule 2: what a letter and a digit are, as EXPLICIT ranges (Basic Latin,
 * Latin-1 and Latin Extended-A and B, up to U+024F; the test pins that, there,
 * they are exactly what Unicode calls a letter and a number). Never the
 * Unicode property classes of every letter and every number: repeated in the
 * boundaries of one very large alternation, they made V8 take 4 to 9 seconds
 * to compile the expression for the first text with a character outside
 * Latin-1 ("→", "–", "…"), with Node stopped (review of 2026-10-10;
 * flow-plain-training-language.first-call.test.ts).
 */
const LETTER = String.raw`A-Za-z\u00AA\u00B5\u00BA\u00C0-\u00D6\u00D8-\u00F6\u00F8-\u024F`
const DIGIT = String.raw`0-9\u00B2\u00B3\u00B9\u00BC-\u00BE`
const GLUE = String.raw`${LETTER}${DIGIT}_@\-`
const NOT_GLUED_BEFORE = `(?<![${GLUE}])`
const NOT_GLUED_AFTER = `(?![${GLUE}])`
const WORD_START = `(?<![${LETTER}${DIGIT}])`
const WORD_END = `(?![${LETTER}${DIGIT}])`

const NUMBER = String.raw`\d{1,2}(?:[.,]\d)?`
/** "8", "8-9", "8 a 9", "7.5", and the same with "/10" written after. */
const GRADE = `${NUMBER}(?:${SP}*[-\\u2013]${SP}*${NUMBER}|${SP}+a${SP}+${NUMBER})?(?:${SP}*\\/${SP}*10(?!\\d))?`
/** "2", "1-2". */
const COUNT = String.raw`\d{1,2}(?:${SP}*[-\u2013]${SP}*\d{1,2})?`
/** After its label ("RIR 2-3") a range is the count only when it is written glued (rule 11). */
const COUNT_AFTER_LABEL = String.raw`\d{1,2}(?:[-\u2013]\d{1,2})?`

const ACCENT_FOLDS: Record<string, string> = {
  a: 'aáàâã',
  e: 'eéê',
  i: 'ií',
  o: 'oóôõ',
  u: 'uúü',
  c: 'cç',
}
const ACCENT_BASE = new Map<string, string>()
for (const [base, variants] of Object.entries(ACCENT_FOLDS)) {
  for (const variant of variants) ACCENT_BASE.set(variant, base)
}

function escapePattern(text: string): string {
  return text.replace(/[.*+?^${}()|[\]\\/-]/g, '\\$&')
}

/** One character, whatever its case; with `accents`, whatever its accent too. */
function character(char: string, accents: boolean): string {
  const lower = char.toLowerCase()
  const base = accents ? ACCENT_BASE.get(lower) : undefined
  const forms = base ? (ACCENT_FOLDS[base] as string) : lower
  const all = [...new Set([...forms, ...forms.toUpperCase()])].join('')
  return all.length === 1 ? escapePattern(all) : `[${escapePattern(all)}]`
}

/** Words written in this file (contexts, neighbours): any case, accents as written. */
function anyCase(text: string): string {
  return [...text].map((char) => (char === ' ' ? `${SP}+` : character(char, false))).join('')
}

/** A spelling written in capitals only (rule 10): "RPE <nota>", "<n> RIR", "PPL". */
function isAcronym(spelling: string): boolean {
  const letters = spelling.replace(/<[^>]+>/g, '')
  return /\p{Lu}/u.test(letters) && !/\p{Ll}/u.test(letters)
}

/** A spelling of the table as a pattern (the mini-syntax of FlowPlainTrainingRow). */
function spellingPattern(spelling: string, key: number): string {
  const acronym = isAcronym(spelling)
  const text = spelling.replace(/\s*([/+,])\s*/g, '$1')
  let source = ''
  for (let index = 0; index < text.length; ) {
    if (text.startsWith(' <nota>', index)) {
      source += `${SP}*[:=]?${SP}*(?<n${key}>${GRADE})`
      index += ' <nota>'.length
    } else if (text.startsWith('<n> ', index)) {
      source += `(?<c${key}>${COUNT})${SP}*`
      index += '<n> '.length
    } else if (text.startsWith(' <n>', index)) {
      source += `${SP}*(?<c${key}>${COUNT_AFTER_LABEL})`
      index += ' <n>'.length
    } else {
      const char = text[index] as string
      if (char === ' ') source += `${SP}+`
      else if (char === '/' || char === '+' || char === ',') source += `${SP}*${escapePattern(char)}${SP}*`
      else if (char === '-') source += `${SP}*[-\\u2010\\u2011\\u2013]${SP}*`
      else source += acronym ? escapePattern(char) : character(char, true)
      index += 1
    }
  }
  return source
}

const alternatives = (words: readonly string[]) => words.map(anyCase).join('|')

// Rule 4.
const NEIGHBOUR = `(?:${alternatives(FLOW_PLAIN_TRAINING_ENGLISH_NEIGHBOURS)})`
const NO_NEIGHBOUR_BEFORE = `(?<!${WORD_START}${NEIGHBOUR}${SP}+)`
const NO_NEIGHBOUR_AFTER = `(?!${SP}+${NEIGHBOUR}${WORD_END})`

// Rule 5. "até" and "próximo" are also read without their accent; "à" is not "a".
const UNTIL = '[aA][tT][eéEÉ]'
const NEAR = '[pP][rR][oóOÓ][xX][iI][mM][oO]'
const FAILURE_AFTER_ARTICLE = `(?<=${WORD_START}(?:${UNTIL}${SP}+[aàAÀ]|${NEAR}${SP}+(?:[dD][aA]|[àÀ])|${anyCase('perto da')}|${anyCase('antes da')})${SP}+)`
const FAILURE_AFTER_BARE_UNTIL = `(?<=${WORD_START}${UNTIL}${SP}+)`
// A lone "à" also introduces a fault OF something ("devida à falha na
// execução", "atenção à falha de postura"): that one is not the term.
const FAILURE_AFTER_LONE_A = `(?<=${WORD_START}[àÀ]${SP}+)`
const NOT_A_FAULT_OF = `(?!${SP}+(?:${alternatives(['de', 'do', 'da', 'dos', 'das', 'na', 'no', 'nas', 'nos', 'em'])})${WORD_END})`

// Rule 6.
/** Words after which composto(s) / isolador(es) alone is a noun: determiners, "e", "ou" and prepositions. */
const BEFORE_A_NOUN = [
  ...['o', 'os', 'do', 'dos', 'no', 'nos', 'ao', 'aos', 'pelo', 'pelos', 'e', 'ou'],
  ...['de', 'com', 'em', 'entre', 'para'],
]
const NOUN_POSITION = `(?<=^${SP}*|[.!?:;,(•—\\n]${SP}*|${WORD_START}(?:${alternatives(BEFORE_A_NOUN)})${SP}+)`
/** "composto vitamínico", "compostos químicos": the substance, not the exercise. */
const SUBSTANCE_WORDS = [
  ...['vitamínico', 'vitamínicos', 'químico', 'químicos', 'orgânico', 'orgânicos'],
  ...['ativo', 'ativos', 'bioativo', 'bioativos', 'natural', 'naturais'],
]
const NOT_AN_ADJECTIVE = `(?!${SP}+(?:${alternatives(['por', 'pelo', 'pela', 'de', 'da', 'do', 'dos', 'das'])}|${SUBSTANCE_WORDS.map((word) => [...word].map((char) => character(char, true)).join('')).join('|')})${WORD_END})`
const NOT_MADE_OF = `(?!${SP}+(?:${alternatives(['por', 'pelo', 'pela', 'pelos', 'pelas'])})${WORD_END})`

// "escápulas retraídas": another feminine plural word right before, or a
// feminine participle coordinated right after ("e deprimidas", ", deprimidas"),
// would lose its agreement.
const NO_FEMININE_PLURAL_BEFORE = `(?<!${WORD_START}[${LETTER}]*[aA][sS]${SP}+)`
const NO_FEMININE_PARTICIPLE_AFTER = `(?!(?:${SP}+[eE]|${SP}*,)${SP}+[${LETTER}]+[aAiIíÍ][dD][aA][sS]${WORD_END})`

// "PSE alta": the adjective agrees with the acronym, not with "esforço".
const NO_FEMININE_WORD_AFTER = `(?!${SP}+[${LETTER}]+[aA][sS]?${WORD_END})`

// Rule 11. A number beside the acronym: before it, spaces and at most one dash
// between them ("Semana 1 - RIR 3" would read as the range "1 - 3"); after it,
// spaces and at most one ":" or "=".
const DASH = String.raw`[-\u2013\u2014]`
const NO_COUNT_BEFORE = `(?<!\\d${SP}*(?:${DASH}${SP}*)?)`
const NO_COUNT_AFTER = `(?!${SP}*[:=]?${SP}*\\d)`
// "RIR 2 - 3 séries": with spaces the second number may not be the count.
const NO_SPACED_RANGE_AFTER = `(?!${SP}*${DASH}${SP}*\\d)`

/** A digit may be glued before reps/rep (rule 2). */
const NOT_GLUED_BEFORE_UNIT = String.raw`(?<![${LETTER}_@\-])`

/** An address: a scheme, "www." or the target of a Markdown link. */
const ADDRESS_SPAN = /(?:[a-z][a-z0-9+.-]*:\/\/|www\.)[^\s<>"`]+|(?<=\]\()[^\s)]+/giu

interface Entry {
  row: FlowPlainTrainingRow
  key: number
  /** Written before the output ("até falha" → "até A última…"). */
  lead: string
}

interface Compiled {
  pattern: RegExp
  entries: Entry[]
}

const NOT_IN_NAMES: ReadonlySet<string> = new Set(['division', 'division_word'])

function compile(rows: readonly FlowPlainTrainingRow[]): Compiled {
  const spelled = rows
    .flatMap((row) => row.spellings.map((spelling) => ({ row, spelling })))
    // The longer spelling first; the table's order breaks a tie.
    .map((entry, order) => ({ ...entry, order }))
    .sort((a, b) => b.spelling.length - a.spelling.length || a.order - b.order)

  const entries: Entry[] = []
  const sources: string[] = []
  const add = (row: FlowPlainTrainingRow, source: (key: number) => string, lead = '') => {
    const key = entries.length
    entries.push({ row, key, lead })
    sources.push(`(?<g${key}>${source(key)})`)
  }
  for (const { row, spelling } of spelled) {
    const article = (key: number) =>
      row.articles
        ? `(?:(?<a${key}>${alternatives(Object.keys(row.articles).sort((a, b) => b.length - a.length))})${SP}+)?`
        : ''
    const body = (key: number) => spellingPattern(spelling, key)
    switch (row.rule) {
      case 'division_word':
        add(
          row,
          (key) =>
            `${NOT_GLUED_BEFORE}${article(key)}${NO_NEIGHBOUR_BEFORE}${body(key)}${NOT_GLUED_AFTER}${NO_NEIGHBOUR_AFTER}`,
        )
        break
      case 'feminine_acronym':
        add(row, (key) => `${NOT_GLUED_BEFORE}${article(key)}${body(key)}${NOT_GLUED_AFTER}${NO_FEMININE_WORD_AFTER}`)
        break
      case 'failure':
        add(row, (key) => `${FAILURE_AFTER_ARTICLE}${body(key)}${NOT_GLUED_AFTER}`)
        add(row, (key) => `${FAILURE_AFTER_LONE_A}${body(key)}${NOT_GLUED_AFTER}${NOT_A_FAULT_OF}`)
        add(row, (key) => `${FAILURE_AFTER_BARE_UNTIL}${body(key)}${NOT_GLUED_AFTER}`, 'a ')
        break
      case 'count_unit':
        add(row, (key) => `${NOT_GLUED_BEFORE_UNIT}${body(key)}${NOT_GLUED_AFTER}`)
        break
      case 'counted_acronym':
        // Rule 11: never with a number on both sides of the acronym.
        if (spelling.startsWith('<n> ')) {
          add(row, (key) => `${NOT_GLUED_BEFORE}${body(key)}${NOT_GLUED_AFTER}${NO_COUNT_AFTER}`)
        } else if (spelling.endsWith(' <n>')) {
          add(
            row,
            (key) =>
              `${NOT_GLUED_BEFORE}${NO_COUNT_BEFORE}${body(key)}${NOT_GLUED_AFTER}${NO_SPACED_RANGE_AFTER}`,
          )
        } else if (isAcronym(spelling)) {
          add(
            row,
            (key) =>
              `${NOT_GLUED_BEFORE}(?:${NO_COUNT_BEFORE}${body(key)}|${body(key)}${NO_COUNT_AFTER})${NOT_GLUED_AFTER}`,
          )
        } else {
          add(row, (key) => `${NOT_GLUED_BEFORE}${body(key)}${NOT_GLUED_AFTER}`)
        }
        break
      case 'whole_entry':
        add(row, (key) => `${NOT_GLUED_BEFORE}${body(key)}${NOT_GLUED_AFTER}${NOT_MADE_OF}`)
        break
      case 'noun_position':
        add(row, (key) => `${NOUN_POSITION}${body(key)}${NOT_GLUED_AFTER}${NOT_AN_ADJECTIVE}`)
        break
      case 'feminine_plural_phrase':
        add(
          row,
          (key) =>
            `${NOT_GLUED_BEFORE}${NO_FEMININE_PLURAL_BEFORE}${article(key)}${body(key)}${NOT_GLUED_AFTER}${NO_FEMININE_PARTICIPLE_AFTER}`,
        )
        break
      default:
        add(row, (key) => `${NOT_GLUED_BEFORE}${article(key)}${body(key)}${NOT_GLUED_AFTER}`)
    }
  }
  return { pattern: new RegExp(sources.join('|'), 'gu'), entries }
}

const compiledByKey = new Map<string, Compiled>()

/** The rows that act in a field, with the owner's switches. */
function compiledFor(field: FlowPlainTrainingField, switches: FlowPlainTrainingOwnerSwitches): Compiled {
  const inName = field === 'name' || field === 'equipment_summary'
  const renames = FLOW_PLAIN_TRAINING_RENAMES_AWAITING_OWNER.filter((row) =>
    switches.renames.includes(row.id),
  )
  const cacheKey = `${inName ? 'name' : 'text'}|${renames.map((row) => row.id).join(',')}`
  let compiled = compiledByKey.get(cacheKey)
  if (!compiled) {
    const active = FLOW_PLAIN_TRAINING_VOCABULARY.filter(
      (row) => !(inName && row.rule !== undefined && NOT_IN_NAMES.has(row.rule)),
    )
    compiled = compile([...active, ...renames])
    compiledByKey.set(cacheKey, compiled)
  }
  return compiled
}

// ── One field ───────────────────────────────────────────────────────────────
interface Span {
  start: number
  end: number
}

interface Edit extends Span {
  output: string
}

/** The sentences of a text: cut after . ! ? … before a space, and at a line break. */
function sentenceSpans(text: string): Span[] {
  const spans: Span[] = []
  let start = 0
  for (const match of text.matchAll(/[.!?…]+(?=\s)|\n/gu)) {
    const end = match.index + match[0].length
    if (end > start) {
      spans.push({ start, end })
      start = end
    }
  }
  if (start < text.length) spans.push({ start, end: text.length })
  return spans
}

function startsSentence(text: string, spans: readonly Span[], index: number): boolean {
  const span = spans.find((entry) => index >= entry.start && index < entry.end)
  return text.slice(span?.start ?? 0, index).trim() === ''
}

function capitalised(text: string): string {
  return text.charAt(0).toLocaleUpperCase('pt-BR') + text.slice(1)
}

/** True when every number of the grade is between 1 and 10. */
function isGradeOutOfTen(grade: string): boolean {
  const numbers = grade.match(/\d{1,2}(?:[.,]\d)?/g) ?? []
  return (
    numbers.length > 0 &&
    numbers.every((number) => {
      const value = Number(number.replace(',', '.'))
      return value >= 1 && value <= 10
    })
  )
}

const WRITTEN_OUT_OF_TEN = new RegExp(`^(.*?)${SP}*\\/${SP}*10$`, 'u')
const SCALE_FOLLOWS = new RegExp(`^${SP}+de${SP}+10(?!\\d)`, 'u')
const BARE_GRADE = new RegExp(`^(${SP}*)(${GRADE})${SP}*$`, 'u')

/** The grade as written; "/10" spelled out; the scale added only when asked. */
function gradeText(grade: string, addScale: boolean): string {
  const written = WRITTEN_OUT_OF_TEN.exec(grade)
  if (written) return `${written[1]} de 10`
  return addScale && isGradeOutOfTen(grade) ? `${grade} de 10` : grade
}

function editsOf(
  text: string,
  field: FlowPlainTrainingField,
  switches: FlowPlainTrainingOwnerSwitches,
): Edit[] {
  const { pattern, entries } = compiledFor(field, switches)
  const addresses: Span[] = Array.from(text.matchAll(ADDRESS_SPAN), (match) => ({
    start: match.index,
    end: match.index + match[0].length,
  }))
  const spans = sentenceSpans(text)
  const edits: Edit[] = []
  for (const match of text.matchAll(pattern)) {
    const start = match.index
    const end = start + match[0].length
    if (addresses.some((address) => start < address.end && end > address.start)) continue
    const groups = match.groups ?? {}
    const entry = entries.find((candidate) => groups[`g${candidate.key}`] !== undefined)
    if (!entry) continue
    const { row, key, lead } = entry
    const grade = groups[`n${key}`]
    const count = groups[`c${key}`]
    const article = groups[`a${key}`]

    let output = row.plain
    if (count !== undefined) {
      output = (count === '1' && row.one ? row.one : row.plain).replace('<n>', count)
    }
    if (grade !== undefined) {
      const addScale = switches.effortOutOfTen && !SCALE_FOLLOWS.test(text.slice(end))
      const written = gradeText(grade, addScale)
      // Rule 9: beside its own label, the grade alone.
      output = field === 'rpe_target' ? written : row.plain.replace('<nota>', written)
    }
    output = `${lead}${output}`
    if (article !== undefined) {
      output = `${row.articles?.[article.toLowerCase()] ?? article} ${output}`
    }
    if (startsSentence(text, spans, start) && /^\p{Lu}/u.test(match[0])) output = capitalised(output)
    // "12reps": the unit was glued to its number.
    if (row.rule === 'count_unit' && /\d$/.test(text.slice(0, start))) output = ` ${output}`
    edits.push({ start, end, output })
  }
  if (field === 'rpe_target' && edits.length === 0) {
    const bare = BARE_GRADE.exec(text)
    if (bare) {
      const grade = bare[2] as string
      const written = gradeText(grade, switches.effortOutOfTen)
      const start = (bare[1] as string).length
      if (written !== grade) edits.push({ start, end: start + grade.length, output: written })
    }
  }
  return edits
}

function applyEdits(text: string, edits: readonly Edit[]): string {
  let out = ''
  let at = 0
  for (const edit of edits) {
    out += text.slice(at, edit.start) + edit.output
    at = edit.end
  }
  return out + text.slice(at)
}

/**
 * No output of the table carries a spelling of the table (pinned by test), so
 * every pass leaves fewer spellings and the reading ends; this is a safety net.
 */
const MAX_PASSES = 6

interface Piece {
  /** The sentence as generated (NFC). */
  original: string
  text: string
  replaced: number
}

/**
 * One sentence, read until nothing more changes (rule 1): a term kept because
 * of its neighbour ("Core" in "Leg day - Core", "Push" in "Upper Body Push")
 * is read again once that neighbour is no longer English.
 */
function plainSentence(
  sentence: string,
  field: FlowPlainTrainingField,
  switches: FlowPlainTrainingOwnerSwitches,
): Piece {
  let text = sentence
  let replaced = 0
  for (let pass = 0; pass < MAX_PASSES; pass += 1) {
    const edits = editsOf(text, field, switches)
    if (edits.length === 0) break
    text = applyEdits(text, edits)
    replaced += edits.length
  }
  return { original: sentence, text, replaced }
}

/** A text (NFC), sentence by sentence. */
function plainPieces(
  normalised: string,
  field: FlowPlainTrainingField,
  switches: FlowPlainTrainingOwnerSwitches,
): Piece[] {
  return sentenceSpans(normalised).map((span) =>
    plainSentence(normalised.slice(span.start, span.end), field, switches),
  )
}

const joined = (pieces: readonly Piece[]) => pieces.map((piece) => piece.text).join('')
const replacedIn = (pieces: readonly Piece[]) => pieces.reduce((sum, piece) => sum + piece.replaced, 0)

export interface FlowPlainTrainingText {
  text: string
  /** How many spellings were replaced. A number only: it goes to telemetry. */
  replaced: number
}

/**
 * One text of a workout suggestion in plain words. No limit is applied here
 * (projectFlowPlainTrainingDraft does it). A text in which no row acts comes
 * back as the very same string.
 */
export function projectFlowPlainTrainingText(
  text: string,
  field: FlowPlainTrainingField,
  switches: FlowPlainTrainingOwnerSwitches = FLOW_PLAIN_TRAINING_OWNER_SWITCHES,
): FlowPlainTrainingText {
  if (typeof text !== 'string' || text === '') return { text, replaced: 0 }
  const pieces = plainPieces(text.normalize('NFC'), field, switches)
  const replaced = replacedIn(pieces)
  if (replaced === 0) return { text, replaced: 0 }
  return { text: joined(pieces), replaced }
}

// ── The whole draft ─────────────────────────────────────────────────────────
/** The limits of the stored draft (trainingDraftPayloadSchema). */
const RUNNING_TEXT_LIMITS = { notes: 500, progression_rule: 500, exercise_notes: 300, execution_steps: 300, common_mistakes: 300 } as const
const SINGLE_PHRASE_LIMITS = { equipment_summary: 500, day: 20, focus: 80, name: 120, muscle_group: 80, reps_range: 40, rpe_target: 40 } as const

export interface FlowPlainTrainingDraft {
  /** The candidate with its texts in plain words: same keys, same types, same numbers. */
  payload: unknown
  termsReplaced: number
  /** Sentences of running text left as generated because the field would pass its limit. */
  sentencesKeptAsGenerated: number
  /** Single-phrase fields left as generated because the plain value would not fit. */
  fieldsKeptAsGenerated: number
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === 'object' && value !== null && !Array.isArray(value)
}

/**
 * The candidate of a workout suggestion with every text the Plan tab shows in
 * plain words, within the limits of each field. Anything that is not a text
 * of a known field comes back as it came.
 */
export function projectFlowPlainTrainingDraft(
  candidate: unknown,
  switches: FlowPlainTrainingOwnerSwitches = FLOW_PLAIN_TRAINING_OWNER_SWITCHES,
): FlowPlainTrainingDraft {
  const result: FlowPlainTrainingDraft = {
    payload: candidate,
    termsReplaced: 0,
    sentencesKeptAsGenerated: 0,
    fieldsKeptAsGenerated: 0,
  }
  if (!isRecord(candidate)) return result

  const running = (value: unknown, field: keyof typeof RUNNING_TEXT_LIMITS): unknown => {
    if (typeof value !== 'string' || value === '') return value
    const limit = RUNNING_TEXT_LIMITS[field]
    const pieces = plainPieces(value.normalize('NFC'), field, switches)
    if (replacedIn(pieces) === 0) return value
    // The last replaced sentences go back to the generated wording until it fits.
    for (let index = pieces.length - 1; index >= 0 && joined(pieces).length > limit; index -= 1) {
      const piece = pieces[index] as Piece
      if (piece.replaced === 0) continue
      pieces[index] = { original: piece.original, text: piece.original, replaced: 0 }
      result.sentencesKeptAsGenerated += 1
    }
    const replaced = replacedIn(pieces)
    if (replaced === 0) return value
    result.termsReplaced += replaced
    return joined(pieces)
  }

  const single = (value: unknown, field: keyof typeof SINGLE_PHRASE_LIMITS): unknown => {
    if (typeof value !== 'string' || value === '') return value
    const projected = projectFlowPlainTrainingText(value, field, switches)
    if (projected.replaced === 0) return value
    if (projected.text.length > SINGLE_PHRASE_LIMITS[field]) {
      result.fieldsKeptAsGenerated += 1
      return value
    }
    result.termsReplaced += projected.replaced
    return projected.text
  }

  const list = (value: unknown, field: 'execution_steps' | 'common_mistakes'): unknown =>
    Array.isArray(value) ? value.map((item) => running(item, field)) : value

  const set = (target: Record<string, unknown>, key: string, value: unknown) => {
    if (Object.hasOwn(target, key)) target[key] = value
  }

  const payload: Record<string, unknown> = { ...candidate }
  set(payload, 'notes', running(candidate.notes, 'notes'))
  set(payload, 'progression_rule', running(candidate.progression_rule, 'progression_rule'))
  set(payload, 'equipment_summary', single(candidate.equipment_summary, 'equipment_summary'))
  if (Array.isArray(candidate.weekly_schedule)) {
    payload.weekly_schedule = candidate.weekly_schedule.map((entry: unknown) => {
      if (!isRecord(entry)) return entry
      const day: Record<string, unknown> = { ...entry }
      set(day, 'day', single(entry.day, 'day'))
      set(day, 'focus', single(entry.focus, 'focus'))
      if (Array.isArray(entry.exercises)) {
        day.exercises = entry.exercises.map((item: unknown) => {
          if (!isRecord(item)) return item
          const exercise: Record<string, unknown> = { ...item }
          set(exercise, 'name', single(item.name, 'name'))
          set(exercise, 'muscle_group', single(item.muscle_group, 'muscle_group'))
          set(exercise, 'reps_range', single(item.reps_range, 'reps_range'))
          set(exercise, 'rpe_target', single(item.rpe_target, 'rpe_target'))
          set(exercise, 'notes', running(item.notes, 'exercise_notes'))
          set(exercise, 'execution_steps', list(item.execution_steps, 'execution_steps'))
          set(exercise, 'common_mistakes', list(item.common_mistakes, 'common_mistakes'))
          return exercise
        })
      }
      return day
    })
  }
  result.payload = payload
  return result
}
