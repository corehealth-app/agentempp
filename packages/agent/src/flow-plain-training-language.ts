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
 *     nothing changes: no output carries a spelling the table would read
 *     again, so an output is never replaced, but a term that was kept because
 *     of its neighbour ("Core" in "Leg day - Core") is read without it once
 *     the neighbour was a term too. The one output that carries a spelling is
 *     the renamed exercise, which keeps its original name in parentheses
 *     (rule 12): a rename row does not read inside parentheses nor where its
 *     Portuguese name already is, so that one is not read again either.
 *     A text in which no row acts comes back as the very same string (not
 *     normalised). A run of spaces counts as one space and is never read
 *     twice: the vocabulary is matched over the sentence with one space in
 *     each place (the time is linear in the run), and a run outside a
 *     replaced spelling is written back as it was.
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
 *     In `reps_range` and `rpe_target` ONLY, the word written alone is the
 *     term too, inside a closed grammar. BEFORE it: the start of the field
 *     or of a sentence, a number and a space, "ou", one of ( / + , ; : or a
 *     dash BETWEEN SPACES. AFTER it: the end (with or without a full stop),
 *     ")", ",", ";", "/", "+" or "ou". The output carries the introduction:
 *     "falha" → "até a última repetição bem feita", "8-12 (falha)" → "8-12
 *     (até a última repetição bem feita)". "sem falha", "pré-falha" and
 *     "Falha total" are outside the grammar and stay.
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
 *     The participle is read THROUGH an adverb. At the start, after
 *     punctuation, after "e" or after "ou" (where "composto" is as likely a
 *     participle as a noun: "Treino ABC, composto principalmente por
 *     exercícios básicos"), the word also stays when up to two adverbs of a
 *     closed list stand between it and the preposition: a word ending in
 *     "mente", apenas, só, sobretudo, quase, também, ainda, sempre, tanto, em
 *     grande parte, em sua maioria, na maior parte. Right after a determiner
 *     or a preposition ("os compostos normalmente de 6 a 10 repetições") the
 *     adverb is not read through: there it is the noun. The whole entries
 *     are read through the same adverbs wherever they are ("exercícios
 *     compostos principalmente por duas fases" stays).
 *  7. Capital letter: at the start of the field, of a sentence or of a line
 *     the output follows the case of the first letter of what it replaces;
 *     anywhere else it is lower case. A row whose output changes gender or
 *     number carries the determiners it swaps (`articles`).
 *  8. No row adds a body position, a joint, a direction, a load or a number
 *     that the replaced word does not say.
 *  9. The effort grade. A written "/10" is spelled out ("8/10" → "8 de 10").
 *     In `rpe_target`, the field the app prints after its own label, the
 *     repeated label leaves: "RPE 8" → "8"; and, when the label opens the
 *     field (an optional article, then RPE, PSE or "esforço", an optional
 *     "alvo", ":" or "="), also before ONE word ("RPE alto" → "alto"; never
 *     "PSE" before a word ending in "a" or "as", never before "percebido"/
 *     "percebida" or "alvo", which are part of the label's own name); and
 *     the label written after a whole grade leaves too ("8 RPE" → "8").
 *     THE SCALE (switch `effortOutOfTen`, on): a grade from 1 to 10 reads
 *     "<nota> de 10" — the whole of `rpe_target`, with or without its full
 *     stop ("9" → "9 de 10", "9." → "9 de 10."), or after RPE / PSE in any
 *     text the net reads ("RPE 8-9" → "esforço 8-9 de 10"; also in
 *     `reps_range`, `focus`, `muscle_group` and `name` when the generator
 *     writes the acronym there). It is written
 *     only after a grade that does NOT GO ON. What may follow the grade is a
 *     closed list: the end of the sentence; ")" or "]"; one of . , ; : ! ? …
 *     not followed by a digit; or a space and then a word or "(" — but not
 *     "ou", "e", "a", "até", "de", "em", "para" or "pra" followed by a
 *     number. "RPE 8/9", "RPE 8+", "RPE 8 ou 9", "RPE 8 para 9", "RPE 8 → 9",
 *     "RPE 8 - RIR 2" keep the grade as written, without the scale.
 *     A RANGE WRITTEN WITH SPACES — a space beside its dash ("8 - 10") or
 *     " a " ("8 a 10") — gains the scale only when NOTHING goes on after it
 *     (the end, a closing bracket, punctuation). Followed by a word or "("
 *     the second number may be another thing, as in a list written with
 *     dashes: "RPE 8 - 10 repetições", "RPE 7 - 3 séries de aquecimento" and
 *     "RPE 8 a 10 repetições por série" keep their numbers, without the
 *     scale (review of the second round: they were stored "8 - 10 de 10
 *     repetições"). A real range written that way loses it too ("RPE 8 a 9
 *     nas últimas séries"); the range written as one keeps it ("RPE 8-9 nas
 *     últimas"). Nor is the scale written when the sentence
 *     already says the scale after the grade (the word "escala", "de 10",
 *     "em 10" or "/10": "RPE 8 (de 10)", "RPE 8 numa escala de 0 a 10"). A
 *     grade the generator wrote after the WORD "esforço" in running text is
 *     not a spelling of the table: no scale. Nor is a grade followed by
 *     other text in `rpe_target` itself, without the acronym ("8 (pesado)"):
 *     a number before a word may be another thing.
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
 * 12. A RENAMED EXERCISE (switch `renames`, both rows on). The spelling
 *     becomes the Portuguese name followed by the original name, as the
 *     generator wrote it, in parentheses, so the person can still ask for it
 *     at the gym: "Hip Thrust com Barra" → "Elevação pélvica com Barra (Hip
 *     Thrust)". In `name` the parenthesis goes to the end of the name (of
 *     its sentence, before a final full stop), or right after the Portuguese
 *     name when the name already has a parenthesis ("Hip Thrust com Barra
 *     (glúteos)" → "Elevação pélvica (Hip Thrust) com Barra (glúteos)"). In
 *     any other field it comes right after, and only at the FIRST mention of
 *     the field; the following ones read the Portuguese name alone. A rename
 *     row does not read what is inside parentheses ("Glúteos (hip thrust)");
 *     does not act in a field (single phrase) or in a sentence (running
 *     text) that already carries its Portuguese name, whatever the case and
 *     the accents ("Hip Thrust (elevação pélvica)"); and does not act in the
 *     equipment list, which is what the person said they have. "Stiff" and
 *     "Leg Press" have no row: they stay exactly as the generator wrote.
 *
 * NUMBERS AND STRUCTURE are never read nor written: plan_type, duration_min,
 * sets, rest_seconds, any unknown key. Every digit of every text is the
 * generator's, in the same order; nothing is derived. ONE number is written
 * by the net: the "10" of " de 10" after an effort grade (rule 9). The
 * method's document does not define that scale; it is copy, not a rule.
 *
 * LIMITS. Running text (notes, progression_rule, an exercise's notes, each
 * step and each mistake) is replaced sentence by sentence; if the field
 * would pass its limit, the LAST replaced sentences go back to the generated
 * wording until it fits. A single-phrase field (day, focus, muscle_group,
 * name, reps_range, rpe_target, equipment_summary) keeps the generated value
 * whole when the plain one does not fit. Nothing is cut.
 * Before any of that, what the two switches ADD is left out, field by field,
 * so that plain words that fit are never given back because of it: first the
 * whole field with the scale and the parenthesis; if it does not fit,
 * without the scale; if it still does not fit, without the scale and without
 * the parenthesis (the Portuguese name alone); and only then the rule above,
 * applied to the text without both. `rpe_target` "RPE 9, até a falha" would
 * have 41 characters with the scale: it is stored as "9, até a última
 * repetição bem feita".
 *
 * THE TWO SWITCHES (FLOW_PLAIN_TRAINING_OWNER_SWITCHES) are ON since the
 * second round of 2026-10-10: the "de 10" scale of the effort grade (D1) and
 * the two rows that rename an exercise (D2). They were turned on by decisão
 * do orquestrador, anunciada ao dono em 2026-10-10, que pode riscar qualquer
 * uma. It is NOT the owner's nor the physician's written yes: in the doc the
 * three lines "sim do dono em" are still blank. Striking a decision is
 * taking its entry out of the literal (one line, tested). No production path
 * passes other switches.
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
 * The rows that RENAME an exercise (rule 12). Each one acts when, and only
 * when, its id is in the switches; both are, since the second round of
 * 2026-10-10 (see THE TWO SWITCHES above: the orchestrator's decision, the
 * owner's written yes still blank — the name of this list did not change).
 * "Stiff" and "Leg Press" have no row: they are the names on the machine and
 * the ones the gyms of Brazil use.
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
  /** D2: ids of FLOW_PLAIN_TRAINING_RENAMES_AWAITING_OWNER that are turned on. */
  renames: readonly string[]
}

/**
 * What production uses. Both decisions are ON by decisão do orquestrador,
 * anunciada ao dono em 2026-10-10, que pode riscar qualquer uma; the owner's
 * written yes is still blank in the doc (docs/mobile/api-v1.md). To strike
 * D1, write `effortOutOfTen: false`; to strike a name, take its id out.
 */
export const FLOW_PLAIN_TRAINING_OWNER_SWITCHES: FlowPlainTrainingOwnerSwitches = Object.freeze({
  effortOutOfTen: true,
  renames: Object.freeze(['hip_thrust', 'military_press']),
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

/** Words written in this file that a model may type without their accent: any case, any accent. */
function folded(text: string): string {
  return [...text].map((char) => (char === ' ' ? `${SP}+` : character(char, true))).join('')
}

// Rule 6.
/** Right after these, composto(s) / isolador(es) alone is a noun: determiners and prepositions. */
const DETERMINERS_AND_PREPOSITIONS = [
  ...['o', 'os', 'do', 'dos', 'no', 'nos', 'ao', 'aos', 'pelo', 'pelos'],
  ...['de', 'com', 'em', 'entre', 'para'],
]
/** Words after which composto(s) / isolador(es) alone is a noun: those, "e" and "ou". */
const BEFORE_A_NOUN = [...DETERMINERS_AND_PREPOSITIONS, 'e', 'ou']
const NOUN_POSITION = `(?<=^${SP}*|[.!?:;,(•—\\n]${SP}*|${WORD_START}(?:${alternatives(BEFORE_A_NOUN)})${SP}+)`
/** "composto vitamínico", "compostos químicos": the substance, not the exercise. */
const SUBSTANCE_WORDS = [
  ...['vitamínico', 'vitamínicos', 'químico', 'químicos', 'orgânico', 'orgânicos'],
  ...['ativo', 'ativos', 'bioativo', 'bioativos', 'natural', 'naturais'],
]
/** What makes "composto" a participle or the substance when it comes right after it. */
const MADE_OF_OR_SUBSTANCE = `(?:${alternatives(['por', 'pelo', 'pela', 'de', 'da', 'do', 'dos', 'das'])}|${SUBSTANCE_WORDS.map((word) => [...word].map((char) => character(char, true)).join('')).join('|')})${WORD_END}`
const MADE_OF = `(?:${alternatives(['por', 'pelo', 'pela', 'pelos', 'pelas'])})${WORD_END}`
const NOT_AN_ADJECTIVE = `(?!${SP}+${MADE_OF_OR_SUBSTANCE})`
const NOT_MADE_OF = `(?!${SP}+${MADE_OF})`
/**
 * The participle read THROUGH an adverb (review of 2026-10-10: "Treino ABC,
 * composto principalmente por exercícios básicos." was replaced). A closed
 * list: a word ending in "mente" and eleven written ones, one or two in a
 * row ("quase sempre"). These are small expressions of their own, tried only
 * on what follows a match of rule 6: inside the large alternation they made
 * the first call of a process pass its budget
 * (flow-plain-training-language.first-call.test.ts).
 */
const PARTICIPLE_ADVERBS: readonly string[] = [
  ...['apenas', 'só', 'sobretudo', 'quase', 'também', 'ainda', 'sempre', 'tanto'],
  ...['em grande parte', 'em sua maioria', 'na maior parte'],
]
const ADVERB = `(?:[${LETTER}]+${folded('mente')}|${PARTICIPLE_ADVERBS.map(folded).join('|')})${WORD_END}`
const THROUGH_AN_ADVERB = `^${SP}+(?:${ADVERB}${SP}+){1,2}`
/** After composto(s) / isolador(es) alone: an adverb, then what makes it a participle or the substance. */
const PARTICIPLE_AFTER_AN_ADVERB = new RegExp(`${THROUGH_AN_ADVERB}${MADE_OF_OR_SUBSTANCE}`, 'u')
/** After a whole entry ("exercícios compostos"): an adverb, then "por". */
const MADE_OF_AFTER_AN_ADVERB = new RegExp(`${THROUGH_AN_ADVERB}${MADE_OF}`, 'u')
/** Right after a determiner or a preposition the word alone is the noun: the adverb is not read through. */
const AFTER_A_DETERMINER = new RegExp(
  `${WORD_START}(?:${alternatives(DETERMINERS_AND_PREPOSITIONS)})${SP}+$`,
  'u',
)

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

/** The rows that act in a field, with the switches. */
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

// ── The two small fields (rules 5 and 9) ────────────────────────────────────
// Small expressions of their own, outside the vocabulary's large alternation
// (the first-call budget of that one is not touched). Review of 2026-10-10.

/** The row of "falha": the same spellings and the same plain text as in the table. */
const FAILURE_ROW = FLOW_PLAIN_TRAINING_VOCABULARY.find((row) => row.rule === 'failure') as FlowPlainTrainingRow
const FAILURE_SPELLINGS = [...FAILURE_ROW.spellings]
  .sort((a, b) => b.length - a.length)
  .map((spelling) => spellingPattern(spelling, 0))
  .join('|')
/**
 * Rule 5, in `reps_range` and `rpe_target`: "falha" written alone. Before it,
 * the start, a number and a space, "ou", one of ( / + , ; : or a dash between
 * spaces; after it, the end (with or without a full stop), one of ) , ; / +
 * or "ou".
 */
const SMALL_FIELD_FAILURE = new RegExp(
  `(?<=^${SP}*|[${DIGIT}]${SP}+|${WORD_START}${anyCase('ou')}${SP}+|[(/+,;:]${SP}*|${SP}${DASH}${SP}+)` +
    `(?:${FAILURE_SPELLINGS})${NOT_GLUED_AFTER}` +
    `(?=${SP}*(?:\\.?\\s*$|[),;/+]|${anyCase('ou')}${WORD_END}))`,
  'gu',
)
/** The introduction the output carries there ("falha" → "até a última repetição bem feita"). */
const SMALL_FIELD_FAILURE_PLAIN = `até a ${FAILURE_ROW.plain}`

const EFFORT_LABEL = `(?:RPE|PSE|${folded('esforço')})`
const SCALE_WRITTEN = `${SP}+${anyCase('de')}${SP}+10(?![${DIGIT}])`
const SENTENCE_END = String.raw`${SP}*\.?\s*`
/**
 * Rule 9, in `rpe_target`: the label that opens the field (an optional
 * article, RPE / PSE / "esforço", an optional "alvo", ":" or "=") before a
 * whole grade or ONE word…
 */
const EFFORT_LABEL_FIRST = new RegExp(
  `^(?<lead>${SP}*)(?<label>(?:(?:${alternatives(['o', 'a', 'um', 'uma'])})${SP}+)?(?<name>${EFFORT_LABEL})(?:${SP}+${anyCase('alvo')})?(?:${SP}*[:=]${SP}*|${SP}*))` +
    `(?:(?<grade>${GRADE})(?<scale>${SCALE_WRITTEN})?|(?<word>[${LETTER}]+))${SENTENCE_END}$`,
  'u',
)
/** …and the label written after a whole grade ("8 RPE"). */
const EFFORT_LABEL_LAST = new RegExp(
  `^(?<lead>${SP}*)(?<grade>${GRADE})(?<scale>${SCALE_WRITTEN})?(?<label>${SP}+${EFFORT_LABEL})${SENTENCE_END}$`,
  'u',
)
/** One word after the label that is part of the label's own name: the label stays. */
const LABEL_NAME_WORDS: ReadonlySet<string> = new Set(['alvo', 'percebido', 'percebida'])

// ── A renamed exercise (rule 12) ────────────────────────────────────────────
const RENAME_IDS: ReadonlySet<string> = new Set(
  FLOW_PLAIN_TRAINING_RENAMES_AWAITING_OWNER.map((row) => row.id),
)
const portugueseNames = new Map<string, RegExp>()
/** The Portuguese name of a rename row, whatever the case and the accents. */
function portugueseName(row: FlowPlainTrainingRow): RegExp {
  let pattern = portugueseNames.get(row.id)
  if (!pattern) {
    pattern = new RegExp(`${NOT_GLUED_BEFORE}${folded(row.plain)}${NOT_GLUED_AFTER}`, 'u')
    portugueseNames.set(row.id, pattern)
  }
  return pattern
}

/** True when the position is after a "(" that was not closed yet. */
function insideParentheses(text: string, index: number): boolean {
  let depth = 0
  for (let at = 0; at < index; at += 1) {
    const code = text.charCodeAt(at)
    if (code === 40) depth += 1
    else if (code === 41 && depth > 0) depth -= 1
  }
  return depth > 0
}

// ── One field ───────────────────────────────────────────────────────────────
/**
 * How a text is read. `scale` and `original` are what the two switches ADD;
 * a field that would pass its limit is read again without them (LIMITS).
 */
interface Reading {
  switches: FlowPlainTrainingOwnerSwitches
  /** The scale is written after an effort grade (never without the switch). */
  scale: boolean
  /** A renamed exercise keeps its original name in parentheses. */
  original: boolean
}

const readingOf = (switches: FlowPlainTrainingOwnerSwitches): Reading => ({
  switches,
  scale: switches.effortOutOfTen,
  original: true,
})

/** What the sentences of one field share (rule 12). */
interface FieldScope {
  /** Rename rows whose Portuguese name a single-phrase field already carries. */
  carries: ReadonlySet<string>
  /** Rename rows that already got their original name in parentheses in this field. */
  mentioned: Set<string>
}

interface Span {
  start: number
  end: number
}

interface Edit extends Span {
  output: string
  /** False for what is written beside a replaced spelling (the parenthesis): it is not a spelling. */
  counts?: boolean
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

/**
 * A text with ONE space in the place of every run of spaces, and the way back
 * to the text as written (rule 1; review of 2026-10-10). Every interval of the
 * vocabulary is "one or more" or "zero or more" spaces, also inside
 * look-behinds tried at every position: over a long run the time grew with
 * its square. Over this copy a run costs what one space costs, and nothing
 * else changes: a run is one space for every rule.
 */
interface Squeezed {
  text: string
  /** Where, in the text as written, the character at this position starts. */
  start(index: number): number
  /** Where, in the text as written, what ends at this position ends. */
  end(index: number): number
}

const SPACE_RUN = /[ \t\u00A0]{2}/
const isSpace = (char: string | undefined) => char === ' ' || char === '\t' || char === '\u00A0'

function squeeze(text: string): Squeezed {
  if (!SPACE_RUN.test(text)) return { text, start: (index) => index, end: (index) => index }
  const starts: number[] = []
  const ends: number[] = []
  const kept: string[] = []
  for (let at = 0; at < text.length; ) {
    let next = at + 1
    if (isSpace(text[at])) while (next < text.length && isSpace(text[next])) next += 1
    starts.push(at)
    ends.push(next)
    kept.push(text[at] as string)
    at = next
  }
  return {
    text: kept.join(''),
    start: (index) => starts[index] ?? text.length,
    end: (index) => (index <= 0 ? 0 : (ends[index - 1] ?? text.length)),
  }
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
/** The whole of `rpe_target` as a grade, with or without its full stop ("9", "9."). */
const BARE_GRADE = new RegExp(`^(${SP}*)(${GRADE})${SP}*\\.?\\s*$`, 'u')
/**
 * Rule 9: what may follow a grade for the scale to be written — a closed
 * list. Anything else may be the grade going on ("8/9", "8+", "8 ou 9",
 * "8 para 9", "8 → 9", "8 - …"), and a scale there would be stored as a
 * wrong number.
 */
const SCALE_MAY_FOLLOW = new RegExp(
  `^(?:\\s*$|${SP}*[)\\]]|[.,;:!?\\u2026](?!${SP}*[${DIGIT}])|${SP}+(?!(?:${['ou', 'e', 'a', 'até', 'de', 'em', 'para', 'pra'].map(folded).join('|')})${SP}+[${DIGIT}])(?:[${LETTER}]|\\())`,
  'u',
)
/**
 * Rule 9 (review of the second round of 2026-10-10). The grade pattern reads
 * "8 - 10" and "8 a 10" as a range. Written with a space beside the dash, or
 * with " a ", and followed by a word or "(", the second number may be another
 * thing — "RPE 8 - 10 repetições", "RPE 7 - 3 séries de aquecimento", "RPE 8
 * a 10 repetições por série" — and the scale was stored as a false sentence
 * ("10 de 10 repetições", "3 de 10 séries"). Such a range gains the scale
 * only when nothing goes on after it: the end, a closing bracket or
 * punctuation. Rule 11 reads the dash between spaces the same way.
 */
const SPACED_RANGE = new RegExp(`${SP}[-\\u2013]|[-\\u2013]${SP}|${SP}a${SP}`, 'u')
const WORD_FOLLOWS = new RegExp(`^${SP}+(?:[${LETTER}]|\\()`, 'u')

/**
 * Rule 9: the sentence already says the scale after the grade ("RPE 8 (de
 * 10)", "RPE 8 numa escala de 0 a 10"): writing it again would say it twice.
 */
const SCALE_SAID_AFTER = new RegExp(
  `${WORD_START}${folded('escala')}${WORD_END}|${WORD_START}(?:${anyCase('de')}|${anyCase('em')})${SP}+10(?![${DIGIT}])|\\/${SP}*10(?![${DIGIT}])`,
  'u',
)

/** The grade as written; "/10" spelled out; the scale added only when asked. */
function gradeText(grade: string, addScale: boolean): string {
  const written = WRITTEN_OUT_OF_TEN.exec(grade)
  if (written) return `${written[1]} de 10`
  return addScale && isGradeOutOfTen(grade) ? `${grade} de 10` : grade
}

/**
 * Rule 9, in `rpe_target`: the label of the field itself, when the sentence
 * is the label and a whole grade or one word. One edit, or none.
 */
function effortLabelEdit(text: string, asWritten: (start: number, end: number) => string, reading: Reading): Edit | null {
  const first = EFFORT_LABEL_FIRST.exec(text)
  if (first?.groups) {
    const { lead = '', label = '', name, grade, scale, word } = first.groups
    const start = lead.length
    const rest = start + label.length
    if (grade !== undefined) {
      // The grade as the generator wrote it; the scale it wrote, if any, stays as written.
      const written = gradeText(asWritten(rest, rest + grade.length), reading.scale && scale === undefined)
      return { start, end: rest + grade.length, output: written }
    }
    if (word !== undefined) {
      const separated = /[ \t\u00A0:=]$/.test(label)
      const agrees = name === 'PSE' && /[aA][sS]?$/.test(word)
      if (separated && !agrees && !LABEL_NAME_WORDS.has(word.toLowerCase())) return { start, end: rest, output: '' }
    }
    return null
  }
  const last = EFFORT_LABEL_LAST.exec(text)
  if (last?.groups) {
    const { lead = '', grade = '', scale = '', label = '' } = last.groups
    const start = lead.length
    const gradeEnd = start + grade.length
    const written = gradeText(asWritten(start, gradeEnd), reading.scale && scale === '')
    return {
      start,
      end: gradeEnd + scale.length + label.length,
      output: `${written}${asWritten(gradeEnd, gradeEnd + scale.length)}`,
    }
  }
  return null
}

/** The edits of one sentence, in the positions of the sentence as written. */
function editsOf(
  sentence: string,
  field: FlowPlainTrainingField,
  reading: Reading,
  scope: FieldScope,
): Edit[] {
  const { switches } = reading
  // Rule 1: every expression below reads the sentence with one space in each place.
  const squeezed = squeeze(sentence)
  const text = squeezed.text
  const asWritten = (start: number, end: number) => sentence.slice(squeezed.start(start), squeezed.end(end))
  const written = (edits: Edit[]): Edit[] =>
    edits
      .sort((a, b) => a.start - b.start || a.end - b.end)
      .map((edit) => ({
        ...edit,
        // What is written in (start = end) goes right after the character before it.
        start: edit.start === edit.end ? squeezed.end(edit.start) : squeezed.start(edit.start),
        end: squeezed.end(edit.end),
      }))

  if (field === 'rpe_target') {
    const label = effortLabelEdit(text, asWritten, reading)
    if (label) return written([label])
  }

  const { pattern, entries } = compiledFor(field, switches)
  const addresses: Span[] = Array.from(text.matchAll(ADDRESS_SPAN), (match) => ({
    start: match.index,
    end: match.index + match[0].length,
  }))
  const spans = sentenceSpans(text)
  const edits: Edit[] = []
  /** The renamed exercises of this sentence that are a first mention (rule 12). */
  const firstMentions: Array<{ edit: Edit; original: string }> = []
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
    // Rule 6: the participle read through an adverb ("…, composto principalmente por").
    if (row.rule === 'whole_entry' && MADE_OF_AFTER_AN_ADVERB.test(text.slice(end))) continue
    if (
      row.rule === 'noun_position' &&
      PARTICIPLE_AFTER_AN_ADVERB.test(text.slice(end)) &&
      !AFTER_A_DETERMINER.test(text.slice(0, start))
    ) {
      continue
    }
    const renamed = RENAME_IDS.has(row.id)
    if (renamed) {
      // Rule 12: not the person's equipment, not the generator's own gloss, not twice.
      if (field === 'equipment_summary') continue
      if (scope.carries.has(row.id) || portugueseName(row).test(text)) continue
      if (insideParentheses(text, start)) continue
    }
    // The count and the grade are written back as the generator wrote them, runs of spaces included.
    const numberAt = start + match[0].search(/\d/)

    let output = row.plain
    if (count !== undefined) {
      const counted = asWritten(numberAt, numberAt + count.length)
      output = (count === '1' && row.one ? row.one : row.plain).replace('<n>', counted)
    }
    if (grade !== undefined) {
      const rest = text.slice(end)
      const addScale =
        reading.scale &&
        !SCALE_FOLLOWS.test(rest) &&
        SCALE_MAY_FOLLOW.test(rest) &&
        !SCALE_SAID_AFTER.test(rest) &&
        // A range written with spaces, then a word: the second number may be another thing.
        !(SPACED_RANGE.test(grade) && WORD_FOLLOWS.test(rest))
      const graded = gradeText(asWritten(numberAt, numberAt + grade.length), addScale)
      // Rule 9: beside its own label, the grade alone.
      output = field === 'rpe_target' ? graded : row.plain.replace('<nota>', graded)
    }
    output = `${lead}${output}`
    if (article !== undefined) {
      output = `${row.articles?.[article.toLowerCase()] ?? article} ${output}`
    }
    if (startsSentence(text, spans, start) && /^\p{Lu}/u.test(match[0])) output = capitalised(output)
    // "12reps": the unit was glued to its number.
    if (row.rule === 'count_unit' && /\d$/.test(text.slice(0, start))) output = ` ${output}`
    const edit: Edit = { start, end, output }
    edits.push(edit)
    if (renamed && reading.original && !scope.mentioned.has(row.id)) {
      scope.mentioned.add(row.id)
      const original = article === undefined ? match[0] : match[0].slice(article.length).trimStart()
      firstMentions.push({ edit, original })
    }
  }

  // Rule 12: the original name in parentheses. In a name that has no
  // parenthesis yet, at the end of the name; anywhere else, right after.
  const atTheEnd = field === 'name' && firstMentions.length === 1 && !text.includes('(')
  for (const { edit, original } of firstMentions) {
    if (atTheEnd) {
      const end = text.length - (/[\s.!?…]*$/u.exec(text)?.[0].length ?? 0)
      if (end > edit.end) {
        edits.push({ start: end, end, output: ` (${original})`, counts: false })
        continue
      }
    }
    edit.output = `${edit.output} (${original})`
  }

  // Rule 5, in the two small fields: "falha" written alone.
  if (field === 'reps_range' || field === 'rpe_target') {
    for (const match of text.matchAll(SMALL_FIELD_FAILURE)) {
      const start = match.index
      const end = start + match[0].length
      if (addresses.some((address) => start < address.end && end > address.start)) continue
      if (edits.some((edit) => start < edit.end && end > edit.start)) continue
      const capital = startsSentence(text, spans, start) && /^\p{Lu}/u.test(match[0])
      edits.push({
        start,
        end,
        output: capital ? capitalised(SMALL_FIELD_FAILURE_PLAIN) : SMALL_FIELD_FAILURE_PLAIN,
      })
    }
  }

  if (field === 'rpe_target' && edits.length === 0) {
    const bare = BARE_GRADE.exec(text)
    if (bare) {
      const start = (bare[1] as string).length
      const end = start + (bare[2] as string).length
      const grade = asWritten(start, end)
      const graded = gradeText(grade, reading.scale)
      if (graded !== grade) edits.push({ start, end, output: graded })
    }
  }
  return written(edits)
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
 * No output is read again by the row that wrote it (pinned by test), so every
 * pass leaves fewer spellings and the reading ends; this is a safety net.
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
  reading: Reading,
  scope: FieldScope,
): Piece {
  let text = sentence
  let replaced = 0
  for (let pass = 0; pass < MAX_PASSES; pass += 1) {
    const edits = editsOf(text, field, reading, scope)
    if (edits.length === 0) break
    text = applyEdits(text, edits)
    replaced += edits.filter((edit) => edit.counts !== false).length
  }
  return { original: sentence, text, replaced }
}

/** A text (NFC), sentence by sentence. */
function plainPieces(normalised: string, field: FlowPlainTrainingField, reading: Reading): Piece[] {
  // Rule 12: a single-phrase field that already carries the Portuguese name
  // of a renamed exercise is left alone as a whole; in running text it is
  // sentence by sentence (editsOf).
  const carries = new Set<string>()
  if (field in SINGLE_PHRASE_LIMITS && reading.switches.renames.length > 0) {
    const whole = squeeze(normalised).text
    for (const row of FLOW_PLAIN_TRAINING_RENAMES_AWAITING_OWNER) {
      if (reading.switches.renames.includes(row.id) && portugueseName(row).test(whole)) carries.add(row.id)
    }
  }
  const scope: FieldScope = { carries, mentioned: new Set() }
  return sentenceSpans(normalised).map((span) =>
    plainSentence(normalised.slice(span.start, span.end), field, reading, scope),
  )
}

const joined = (pieces: readonly Piece[]) => pieces.map((piece) => piece.text).join('')
const replacedIn = (pieces: readonly Piece[]) => pieces.reduce((sum, piece) => sum + piece.replaced, 0)

export interface FlowPlainTrainingText {
  text: string
  /** How many spellings were replaced. A number only: it goes to telemetry. */
  replaced: number
}

function plainText(text: string, field: FlowPlainTrainingField, reading: Reading): FlowPlainTrainingText {
  if (typeof text !== 'string' || text === '') return { text, replaced: 0 }
  const pieces = plainPieces(text.normalize('NFC'), field, reading)
  const replaced = replacedIn(pieces)
  if (replaced === 0) return { text, replaced: 0 }
  return { text: joined(pieces), replaced }
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
  return plainText(text, field, readingOf(switches))
}

// ── The whole draft ─────────────────────────────────────────────────────────
/** The limits of the stored draft (trainingDraftPayloadSchema). */
const RUNNING_TEXT_LIMITS = { notes: 500, progression_rule: 500, exercise_notes: 300, execution_steps: 300, common_mistakes: 300 } as const
const SINGLE_PHRASE_LIMITS = { equipment_summary: 500, day: 20, focus: 80, name: 120, muscle_group: 80, reps_range: 40, rpe_target: 40 } as const

/**
 * LIMITS: the readings of a field, from the fullest to the plainest. What the
 * two switches add is left out before any plain word is given back: with the
 * scale and the parenthesis; without the scale; without both.
 */
function readingsOf(switches: FlowPlainTrainingOwnerSwitches): Reading[] {
  const readings: Reading[] = [readingOf(switches)]
  if (switches.effortOutOfTen) readings.push({ switches, scale: false, original: true })
  if (switches.renames.length > 0) readings.push({ switches, scale: false, original: false })
  return readings
}

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
  const readings = readingsOf(switches)

  const running = (value: unknown, field: keyof typeof RUNNING_TEXT_LIMITS): unknown => {
    if (typeof value !== 'string' || value === '') return value
    const limit = RUNNING_TEXT_LIMITS[field]
    const normalised = value.normalize('NFC')
    let pieces: Piece[] = []
    for (const reading of readings) {
      pieces = plainPieces(normalised, field, reading)
      const replaced = replacedIn(pieces)
      if (replaced === 0) return value
      if (joined(pieces).length <= limit) {
        result.termsReplaced += replaced
        return joined(pieces)
      }
    }
    // Not even the plainest reading fits: its last replaced sentences go back
    // to the generated wording until it does.
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
    for (const reading of readings) {
      const projected = plainText(value, field, reading)
      if (projected.replaced === 0) return value
      if (projected.text.length <= SINGLE_PHRASE_LIMITS[field]) {
        result.termsReplaced += projected.replaced
        return projected.text
      }
    }
    // Not even the plainest reading fits: the generated value stays whole (counted once).
    result.fieldsKeptAsGenerated += 1
    return value
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
