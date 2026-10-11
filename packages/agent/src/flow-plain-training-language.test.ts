/**
 * Flow only (app Performe AI): the closed vocabulary that turns a workout
 * suggestion into everyday words (flow-plain-training-language.ts).
 *
 * Audit 2026-10-10, owner's words: "quando ele monta o treino, está muito
 * tecnico os termos usados, precisam ser mais simples para facilitar o
 * entendimento do usuario". The exact turn is in
 * __golden__/audit-10-10-flow-workout-plain-language.test.ts; here each rule
 * of the module is pinned on its own.
 *
 * Every input → output line below is written HERE, by hand. None is read from
 * the module: a table that changes does not change what this file expects.
 * The default field of a line is `notes` (running text, where every row acts).
 *
 * Second round of 2026-10-10. The two switches are ON by decisão do
 * orquestrador, anunciada ao dono em 2026-10-10, que pode riscar qualquer uma
 * (the owner's written yes is still blank in the doc): a line that does not
 * name its switches is read with the scale of the effort grade and with the
 * two renames, as production reads it. The lines that pin one switch name it.
 */
import { readdirSync, readFileSync } from 'node:fs'
import { dirname, relative, resolve } from 'node:path'
import { fileURLToPath } from 'node:url'
import { describe, expect, it } from 'vitest'
import {
  FLOW_PLAIN_TRAINING_ENGLISH_NEIGHBOURS,
  FLOW_PLAIN_TRAINING_OWNER_SWITCHES,
  FLOW_PLAIN_TRAINING_RENAMES_AWAITING_OWNER,
  FLOW_PLAIN_TRAINING_VOCABULARY,
  type FlowPlainTrainingField,
  projectFlowPlainTrainingDraft,
  projectFlowPlainTrainingText,
} from './flow-plain-training-language.js'
import { classifyHealthProduct } from './plan-draft.js'

const plain = (text: string, field: FlowPlainTrainingField = 'notes') =>
  projectFlowPlainTrainingText(text, field).text

/** "gastrocnêmio" typed with a combining circumflex (NFD). */
const GASTROCNEMIO_NFD = 'gastrocne\u0302mio'
/** A sentence with decomposed accents and no spelling of the table. */
const NO_SPELLING_NFD = 'Aquec\u0327a os mu\u0301sculos antes de comec\u0327ar.'

describe('the decomposed-accent strings of this file are what they say', () => {
  it('both are NFD (their NFC form is another string) and the escapes are still escapes', () => {
    expect(GASTROCNEMIO_NFD).toHaveLength('gastrocnêmio'.length + 1)
    expect(GASTROCNEMIO_NFD.normalize('NFC')).toBe('gastrocnêmio')
    expect(GASTROCNEMIO_NFD).not.toBe('gastrocnêmio')
    expect(NO_SPELLING_NFD.normalize('NFC')).toBe('Aqueça os músculos antes de começar.')
    expect(NO_SPELLING_NFD).not.toBe(NO_SPELLING_NFD.normalize('NFC'))
  })
})

describe('U1 each listed spelling, in a sentence, gives the exact plain text', () => {
  it.each([
    // The reported draft (2026-10-10), piece by piece.
    ['6 reps', '6 repetições'],
    ['1 rep', '1 repetição'],
    ['12reps', '12 repetições'],
    ['Plano Push/Pull/Legs modificado', 'Plano empurrar/puxar/pernas modificado'],
    ['Quinta (Ombros+Core)', 'Quinta (Ombros+abdômen)'],
    [
      'Treino até próximo da falha técnica (RPE 8-9).',
      'Treino até próximo da última repetição bem feita (esforço 8-9 de 10).',
    ],
    [
      'Compostos primeiro, isoladores depois.',
      'Exercícios de vários músculos primeiro, exercícios de um músculo só depois.',
    ],
    ['Pegada pronada, mãos alinhadas', 'Pegada por cima, mãos alinhadas'],
    ['Perder retração escapular', 'Perder postura de ombros para trás'],
    ['mantendo as escápulas retraídas', 'mantendo os ombros para trás'],
    ['Empurre explosivo mantendo escápulas retraídas', 'Empurre explosivo mantendo ombros para trás'],
    ['Como intermediário, use progressão linear:', 'Como intermediário, use evolução passo a passo:'],
    // Both sides of a slash, and the other signs that are not glue.
    ['Push/Pull', 'Empurrar/puxar'],
    ['Upper/Lower A', 'Parte de cima/parte de baixo A'],
    ['Core/Lombar', 'Abdômen/Lombar'],
    ['glúteos/MMII/core', 'glúteos/parte de baixo do corpo/abdômen'],
    ['Isquiotibiais/Glúteos', 'Músculos de trás da coxa/Glúteos'],
    ['Glúteos/Isquiotibiais', 'Glúteos/músculos de trás da coxa'],
    ['Gastrocnêmio/Sóleo', 'Músculos da panturrilha'],
    ['Dia 1 - Push', 'Dia 1 - empurrar'],
    // With and without accents, composed and decomposed.
    ['gastrocnemio', 'músculo da panturrilha'],
    [GASTROCNEMIO_NFD, 'músculo da panturrilha'],
    ['sóleo', 'músculo da panturrilha'],
    ['progressao linear', 'evolução passo a passo'],
    // Whole entries (noun + adjective) and the words alone in noun position.
    ['Priorize exercícios multiarticulares', 'Priorize exercícios de vários músculos'],
    ['exercícios monoarticulares', 'exercícios de um músculo só'],
    ['movimentos compostos', 'exercícios de vários músculos'],
    ['exercício isolado', 'exercício de um músculo só'],
    [
      'Compostos constroem; isoladores lapidam.',
      'Exercícios de vários músculos constroem; exercícios de um músculo só lapidam.',
    ],
    ['Composto principal para peitoral.', 'Exercício de vários músculos principal para peitoral.'],
    ['Isolador específico para glúteos.', 'Exercício de um músculo só específico para glúteos.'],
    ['Comece pelos pesados e os compostos.', 'Comece pelos pesados e os exercícios de vários músculos.'],
    [
      'Descanse 60-90s entre séries de isoladores e 90-120s nos compostos.',
      'Descanse 60-90s entre séries de exercícios de um músculo só e 90-120s nos exercícios de vários músculos.',
    ],
    [
      'Comece com compostos e termine com isoladores.',
      'Comece com exercícios de vários músculos e termine com exercícios de um músculo só.',
    ],
    // English divisions with a row of their own.
    ['Push day', 'Dia de empurrar'],
    ['Pull day', 'Dia de puxar'],
    ['Leg day', 'Dia de pernas'],
    ['Lower back', 'Lombar'],
    ['Upper body', 'Parte de cima do corpo'],
    ['Lower body', 'Parte de baixo do corpo'],
    ['Full Body A', 'Corpo inteiro A'],
    ['Treino Full-Body', 'Treino corpo inteiro'],
    ['PPL', 'Empurrar/puxar/pernas'],
    ['Push Pull Legs', 'Empurrar/puxar/pernas'],
    // A term whose neighbour was itself a term is read again without it.
    ['Leg day - Core e panturrilha', 'Dia de pernas - abdômen e panturrilha'],
    ['Upper Body Push', 'Parte de cima do corpo empurrar'],
    ['Full Body - Lower', 'Corpo inteiro - parte de baixo do corpo'],
    ['Core Leg day', 'Abdômen dia de pernas'],
    // "Failure", only in its contexts.
    ['até falha', 'até a última repetição bem feita'],
    ['Treine até a falha muscular técnica.', 'Treine até a última repetição bem feita.'],
    ['Chegue próximo à falha.', 'Chegue próximo à última repetição bem feita.'],
    ['Pare antes da falha concêntrica.', 'Pare antes da última repetição bem feita.'],
    ['Leve a série à falha.', 'Leve a série à última repetição bem feita.'],
    ['Vá até a falha na última série.', 'Vá até a última repetição bem feita na última série.'],
    // Effort and repetitions left.
    ['RPE', 'Esforço'],
    ['RPE 8/10', 'Esforço 8 de 10'],
    ['RPE: 8', 'Esforço 8 de 10'],
    ['RPE8', 'Esforço 8 de 10'],
    ['Mantenha RPE 7.5 nas séries.', 'Mantenha esforço 7.5 de 10 nas séries.'],
    ['Controle a PSE.', 'Controle o esforço.'],
    ['Mantenha a PSE 8 nas séries.', 'Mantenha o esforço 8 de 10 nas séries.'],
    ['RIR 2', '2 repetições de sobra'],
    ['2 RIR', '2 repetições de sobra'],
    ['RIR 1', '1 repetição de sobra'],
    ['Deixe repetições em reserva.', 'Deixe repetições de sobra.'],
    // Grip and anatomy.
    ['pegada supinada', 'pegada por baixo'],
    ['porção clavicular do peitoral', 'parte de cima do peito'],
    ['cabeça longa do tríceps', 'parte de trás do braço'],
    ['cabeça curta do bíceps', 'parte da frente do braço'],
    ['Foco na cabeça longa do tríceps braquial.', 'Foco na parte de trás do braço.'],
    ['cabeça longa do bíceps braquial', 'parte da frente do braço'],
    ['cadeia posterior', 'parte de trás do corpo'],
    ['cadeia anterior', 'parte da frente do corpo'],
    // RC TL-2: the six example terms whose sentence is not in the evidence,
    // each in a sentence of this test (a close variant, declared as such).
    ['Foco na porção clavicular.', 'Foco na parte de cima do peito.'],
    ['Trabalha a cabeça longa do tríceps.', 'Trabalha a parte de trás do braço.'],
    ['Alongue os isquiotibiais antes.', 'Alongue os músculos de trás da coxa antes.'],
    ['Trabalha o gastrocnêmio e sóleo.', 'Trabalha os músculos da panturrilha.'],
    ['Trabalha gastrocnêmio.', 'Trabalha músculo da panturrilha.'],
    ['Trabalha sóleo.', 'Trabalha músculo da panturrilha.'],
    ['Fortalece a cadeia posterior.', 'Fortalece a parte de trás do corpo.'],
    // The sentences the generator's own rules carry (it may copy them).
    [
      'progressão linear 6→7→8→...→12 reps, então aumenta peso e volta pra 6',
      'evolução passo a passo 6→7→8→...→12 repetições, então aumenta peso e volta pra 6',
    ],
    [
      'Divisões válidas: Full Body, Upper/Lower, Push/Pull/Legs, ABC',
      'Divisões válidas: corpo inteiro, parte de cima/parte de baixo, empurrar/puxar/pernas, ABC',
    ],
    [
      'Adicione 1 rep por treino. Bateu 12 reps com técnica → aumenta peso, volta pra 6.',
      'Adicione 1 repetição por treino. Bateu 12 repetições com técnica → aumenta peso, volta pra 6.',
    ],
  ])('%j → %j', (written, expected) => {
    expect(plain(written)).toBe(expected)
  })

  it('reps_range "até falha" (the generator\'s own documented form) is plain and fits its 40 characters', () => {
    const result = projectFlowPlainTrainingText('até falha', 'reps_range')
    expect(result.text).toBe('até a última repetição bem feita')
    expect(result.text.length).toBeLessThanOrEqual(40)
    expect(result.replaced).toBe(1)
  })
})

describe('U2 what is NOT replaced comes back as the very same string', () => {
  it.each([
    // Glued to a letter, a digit, "_", "@" or "-".
    'reps_range',
    'cores vivas',
    'score',
    'Pull-up',
    'Push-up',
    'Pulldown com corda (ou pullover)',
    // A word that is not the term.
    'treino composto por 5 dias',
    'A creatina é um composto seguro',
    'Composto vitamínico não é necessário',
    'Livre de compostos químicos',
    'exercícios compostos por duas fases',
    'Se a técnica falha, reduza a carga',
    'Corrija qualquer falha técnica',
    'Lesão devida à falha na execução',
    'Atenção à falha de postura',
    'Você vai rir de tão leve',
    'PSE alta só na última série',
    // RIR with a number on both sides (rule 11): the three sentences of the
    // review of 2026-10-10. The count is the number AFTER the acronym; the
    // number before it is weeks, repetitions, sets.
    'Semana 1 RIR 3, semana 2 RIR 2, semana 3 RIR 1.',
    'Séries de 12 RIR 2.',
    'Faça 3 séries de 10 RIR 2-3.',
    // English exercise names: the neighbour is in the closed list.
    'Face Pull',
    'Pull Up',
    'Pull Down',
    'Pull Over',
    'Push Up',
    'Pull Through',
    'Band Pull Apart',
    'Sled Push',
    'Upper back',
    'Push Press',
    'Leg Extension',
    'Pull Overs',
    'Band Pull Aparts',
    'Push Workout',
    'Core Training',
    'Lower Trap',
    'Upper Lats',
    // Outside the vocabulary (RC TL-4).
    'Peitoral',
    'Quadríceps/Glúteos',
    'Agachamento livre',
    '10-20 séries/músculo/semana',
    'Junte as escápulas',
    'Deprima as escápulas',
    'dor unilateral no joelho',
    'Remada unilateral',
    'pegada neutra',
    'menor stress lombar',
    'Tríceps (cabeça longa)',
    // Exercise names no row renames: the machine's and the gym's own name (RC TL-13).
    'Stiff (levantamento romeno)',
    'Stiff Unilateral com Halter',
    'Leg Press 45°',
    'Leg press 45°',
    // A renamed exercise the generator already wrote in Portuguese, or in parentheses (RC TL-13).
    'Hip Thrust (elevação pélvica)',
    'Glúteos (hip thrust)',
    // A phrase kept whole because the plain form would break its agreement.
    'Mantenha ambas as escápulas retraídas',
    'escápulas retraídas e deprimidas',
    'Escápulas retraídas, deprimidas e firmes',
    // An address is protected as a span.
    'https://example.com/core/push',
    'Veja [o guia](https://example.com/push/pull/legs) antes',
    'www.exemplo.com/core',
    '',
    NO_SPELLING_NFD,
  ])('%j', (written) => {
    const result = projectFlowPlainTrainingText(written, 'notes')
    expect(result.text).toBe(written)
    expect(result.replaced).toBe(0)
  })

  it('the loose English words do not act inside an exercise name nor in the equipment list', () => {
    for (const field of ['name', 'equipment_summary'] as const) {
      for (const written of [
        'Core Blaster',
        'Push Press',
        'Prancha (core)',
        'Full Body Stretch',
        'Lower Back Extension',
        'Leg day',
        'Barra para Pull',
      ]) {
        expect(plain(written, field), `${field}: ${written}`).toBe(written)
      }
    }
    // The other rows do act in a name.
    expect(plain('Rosca direta (pegada supinada)', 'name')).toBe('Rosca direta (pegada por baixo)')
    expect(plain('Mesa flexora (isquiotibiais)', 'name')).toBe(
      'Mesa flexora (músculos de trás da coxa)',
    )
  })
})

describe('U3 capital letter and article follow the place and the word', () => {
  it.each([
    ['Compostos primeiro.', 'Exercícios de vários músculos primeiro.'],
    ['(Push superior)', '(empurrar superior)'],
    ['Core', 'Abdômen'],
    ['core', 'abdômen'],
    ['Treino de Core', 'Treino de abdômen'],
    ['Aqueça. Core no fim.', 'Aqueça. Abdômen no fim.'],
    ['Aqueça. core no fim.', 'Aqueça. abdômen no fim.'],
    ['Aqueça.\nPush na segunda.', 'Aqueça.\nEmpurrar na segunda.'],
    ['mantendo as escápulas retraídas', 'mantendo os ombros para trás'],
    ['As escápulas retraídas ajudam.', 'Os ombros para trás ajudam.'],
    ['com suas escápulas retraídas', 'com seus ombros para trás'],
    ['para os MMII', 'para a parte de baixo do corpo'],
    ['treino dos MMSS', 'treino da parte de cima do corpo'],
    ['Atenção à PSE.', 'Atenção ao esforço.'],
    ['O Upper vem antes do Lower.', 'A parte de cima do corpo vem antes da parte de baixo do corpo.'],
    ['No Upper/Lower de 4 dias', 'Na parte de cima/parte de baixo de 4 dias'],
    ['No Legs, comece pelo agachamento.', 'Nas pernas, comece pelo agachamento.'],
    ['dor no lower back', 'dor na lombar'],
    ['Treine o Core 3x.', 'Treine o abdômen 3x.'],
  ])('%j → %j', (written, expected) => {
    expect(plain(written)).toBe(expected)
  })
})

describe('U4 field limits are never passed and nothing is cut', () => {
  // Three terms, each in its own sentence, in a note of exactly 498 characters.
  const overhand = 'Use pegada pronada no supino.'
  const reps = 'Faça 12 reps por série.'
  const effort = 'Mantenha RPE 8 no fim.'
  const tail = `${overhand} ${reps} ${effort}`
  const head = 'Beba água durante o treino. '.repeat(14)
  const filler = `${'a'.repeat(498 - head.length - tail.length - 2)}. `
  const notes = `${head}${filler}${tail}`

  interface Exercise {
    name: string
    muscle_group: string
    sets: number
    reps_range: string
    rest_seconds: number
    execution_steps?: string[]
  }
  const exercise = (over: Partial<Exercise>): Exercise => ({
    name: 'Agachamento',
    muscle_group: 'pernas',
    sets: 4,
    reps_range: '8-12',
    rest_seconds: 90,
    ...over,
  })
  const longName = `Elevação de panturrilha em pé na máquina, com pausa de um segundo no alto e descida lenta e controlada (gastrocnêmio)`
  const longStep = `${'Desça devagar e suba sem pressa. '.repeat(7)}Faça 12 reps assim, sem parar no meio do caminho e sem perder ritmo.`
  const candidate = {
    plan_type: 'split',
    equipment_summary: 'halteres',
    notes,
    progression_rule: 'Suba a carga aos poucos.',
    weekly_schedule: [
      {
        day: 'Upper A',
        focus: 'Upper A',
        duration_min: 60,
        exercises: [
          exercise({ name: longName, reps_range: 'até falha', execution_steps: [longStep, 'Faça 8 reps.'] }),
        ],
      },
      { day: 'Dia 1 - Push', focus: 'Push', duration_min: 50, exercises: [exercise({})] },
    ],
  }
  const result = projectFlowPlainTrainingDraft(candidate)
  const payload = result.payload as typeof candidate

  it('the setup is the case: 498 characters, and the plain note would have 509 (515 with the scale, which is left out first: U17)', () => {
    expect(notes).toHaveLength(498)
    expect(longName.length).toBeLessThanOrEqual(120)
    expect(longName.length + ('músculo da panturrilha'.length - 'gastrocnêmio'.length)).toBeGreaterThan(120)
    expect(longStep.length).toBeLessThanOrEqual(300)
    expect(longStep.length + ('repetições'.length - 'reps'.length)).toBeGreaterThan(300)
  })

  it('running text: the last replaced sentences go back to the generated wording until it fits', () => {
    expect(payload.notes).toBe(
      `${head}${filler}Use pegada por cima no supino. ${reps} ${effort}`,
    )
    expect(payload.notes.length).toBeLessThanOrEqual(500)
    expect(payload.notes).not.toContain('…')
    // Every generated sentence is there, in plain words or as generated.
    expect(payload.notes.endsWith(`${reps} ${effort}`)).toBe(true)
    expect(payload.weekly_schedule[0]?.exercises[0]?.execution_steps).toEqual([
      longStep,
      'Faça 8 repetições.',
    ])
  })

  it('a single-phrase field keeps the generated value whole when the plain one does not fit', () => {
    expect(payload.weekly_schedule[0]?.day).toBe('Upper A')
    expect('Parte de cima do corpo A').toHaveLength(24)
    expect(payload.weekly_schedule[0]?.focus).toBe('Parte de cima do corpo A')
    expect(payload.weekly_schedule[0]?.exercises[0]?.name).toBe(longName)
    expect(payload.weekly_schedule[1]?.day).toBe('Dia 1 - empurrar')
    expect(payload.weekly_schedule[1]?.focus).toBe('Empurrar')
    expect(payload.weekly_schedule[0]?.exercises[0]?.reps_range).toBe('até a última repetição bem feita')
  })

  it('what was kept as generated is counted', () => {
    expect(result.termsReplaced).toBe(6)
    // The note's two last sentences and the long step.
    expect(result.sentencesKeptAsGenerated).toBe(3)
    // The day "Upper A" and the long exercise name.
    expect(result.fieldsKeptAsGenerated).toBe(2)
  })

  it('numbers, structure and unknown keys are not read nor written', () => {
    expect(payload.plan_type).toBe('split')
    expect(payload.weekly_schedule.map((day) => day.duration_min)).toEqual([60, 50])
    expect(payload.weekly_schedule[0]?.exercises[0]).toMatchObject({ sets: 4, rest_seconds: 90 })
    const odd = { notes: 12, weekly_schedule: 'Push', extra: 'Push/Pull/Legs', progression_rule: null }
    expect(projectFlowPlainTrainingDraft(odd).payload).toEqual(odd)
    for (const notObject of [null, undefined, 'Push', 7, ['Push']]) {
      expect(projectFlowPlainTrainingDraft(notObject)).toEqual({
        payload: notObject,
        termsReplaced: 0,
        sentencesKeptAsGenerated: 0,
        fieldsKeptAsGenerated: 0,
      })
    }
  })
})

/** A sentence in which the row acts, by the rule the row carries. */
function probe(row: { id: string; rule?: string }, spelling: string): string {
  const written = spelling.replace('<nota>', '8').replace('<n>', '2')
  if (row.rule === 'failure') return `Treine até a ${written} em 3 séries de 45 segundos.`
  if (row.rule === 'noun_position') return `${written} primeiro, em 3 séries de 45 segundos.`
  return `Faça 3 séries de ${written} em 45 segundos.`
}

const digitGroups = (text: string) => text.match(/\d+/g) ?? []

/** Production's switches with the scale of the effort grade written OFF (hand-written; U9 pins the literal). */
const SCALE_OFF = { effortOutOfTen: false, renames: ['hip_thrust', 'military_press'] }
/** Both switches written off: the reading of before the second round of 2026-10-10. */
const ALL_OFF = { effortOutOfTen: false, renames: [] as string[] }
/** How many times the scale is written in a text. */
const scales = (text: string) => text.split(' de 10').length - 1

describe('U5 applying it twice changes nothing more', () => {
  it('for every spelling of the table, and no plain text carries a spelling of the table', () => {
    expect(FLOW_PLAIN_TRAINING_VOCABULARY.length).toBeGreaterThan(0)
    for (const row of [...FLOW_PLAIN_TRAINING_VOCABULARY, ...FLOW_PLAIN_TRAINING_RENAMES_AWAITING_OWNER]) {
      const switches = { effortOutOfTen: true, renames: [row.id] }
      for (const spelling of row.spellings) {
        for (const field of ['notes', 'name', 'rpe_target', 'day'] as const) {
          const once = projectFlowPlainTrainingText(probe(row, spelling), field, switches).text
          expect(projectFlowPlainTrainingText(once, field, switches).text, `${row.id}: ${spelling}`).toBe(once)
        }
      }
      for (const output of [row.plain, row.one].filter((entry) => entry !== undefined)) {
        const written = `Faça ${String(output).replace('<nota>', '8').replace('<n>', '2')} hoje.`
        expect(projectFlowPlainTrainingText(written, 'notes', switches), `${row.id}: ${output}`).toEqual({
          text: written,
          replaced: 0,
        })
      }
    }
  })

  // 20,000 seeded random sentences made of the table's spellings. The
  // sentences are the same on every run and the same as when this was one
  // test: they are all written first, in the generator's order, and then read
  // in blocks, a test each. One test read them all in 16 s beside an Xcode
  // build, three times the 5 s a test has (a synchronous test is not
  // interrupted by vitest 2.1, but a later version or a slower machine would
  // fail it). The same readings and the same assertions on each sentence; no
  // timeout is raised.
  //
  // Second round of 2026-10-10: production writes " de 10" after an effort
  // grade, the only number the net adds. The strict equality of digits is
  // kept, on the reading with the scale off; and the reading production makes
  // is compared with that one — it may differ from it ONLY by " de 10"
  // written in. One more reading per sentence (60,000); nothing is relaxed.
  //
  // Review round 1 of the second round: with the third reading a block of
  // 1,000 no longer took "well under a second" — measured from 0.9 to 2.4 s
  // (the reviewer, beside an Xcode build: 1.0 to 2.4 s), half the room there
  // was under the 5 s of a test. The blocks are now of 500 (40 tests): the
  // same 20,000 sentences in the same order, the same three readings and the
  // same assertions on each. Measured beside an Xcode build, with two
  // workers: 0.4 to 0.8 s a block (19 s the 40). No timeout is raised.
  const SEEDED_SENTENCES = 20_000
  const SEEDED_BLOCK = 500
  const seeded = (() => {
    // A small deterministic generator.
    let seed = 20261010
    const random = () => {
      seed = (seed * 1664525 + 1013904223) % 4294967296
      return seed / 4294967296
    }
    const pick = <T,>(list: readonly T[]): T => list[Math.floor(random() * list.length)] as T
    const spellings = FLOW_PLAIN_TRAINING_VOCABULARY.flatMap((row) => row.spellings)
    const words = [
      ...['o', 'os', 'a', 'as', 'do', 'da', 'no', 'na', 'à', 'até', 'até a', 'próximo da', 'e', 'ou'],
      ...['de', 'com', 'por', 'para', 'em', 'um', 'treino', 'Mantenha', 'séries', '3', '12', '4x'],
      ...['peitoral', 'alta', 'deprimidas', 'ambas', 'suas', 'dia', 'Blaster', 'falha', 'técnica'],
      ...FLOW_PLAIN_TRAINING_ENGLISH_NEIGHBOURS,
    ]
    const separators = [' ', ' ', ' ', ', ', '. ', '/', ' (', ') ', ': ', '; ', ' - ', '+', '\n', '-', '_']
    const fields = ['notes', 'name', 'focus', 'day', 'rpe_target', 'reps_range', 'muscle_group'] as const
    const sentences: Array<{ written: string; field: (typeof fields)[number] }> = []
    for (let run = 0; run < SEEDED_SENTENCES; run += 1) {
      let written = ''
      const length = 1 + Math.floor(random() * 7)
      for (let index = 0; index < length; index += 1) {
        const piece = (random() < 0.55 ? pick(spellings) : pick(words))
          .replace('<nota>', pick(['8', '8-9', '7.5', '8/10', '15']))
          .replace('<n>', pick(['1', '2', '1-2']))
        written += (index > 0 ? pick(separators) : '') + piece
      }
      if (random() < 0.1) written = written.toUpperCase()
      sentences.push({ written, field: pick(fields) })
    }
    return sentences
  })()

  it('the seeded sentences are 20,000, and they do carry the spellings of the table', () => {
    expect(seeded).toHaveLength(SEEDED_SENTENCES)
    expect(new Set(seeded.map((sentence) => sentence.written)).size).toBeGreaterThan(15_000)
    expect(SEEDED_SENTENCES % SEEDED_BLOCK).toBe(0)
  })

  it.each(Array.from({ length: SEEDED_SENTENCES / SEEDED_BLOCK }, (_, block) => [block * SEEDED_BLOCK]))(
    'for the 500 seeded random sentences from %i on; and their digits are kept',
    (from) => {
      let acted = 0
      for (const { written, field } of seeded.slice(from, from + SEEDED_BLOCK)) {
        // With the scale off, every digit group is the generator's, in the same order.
        const off = projectFlowPlainTrainingText(written, field, SCALE_OFF)
        expect(digitGroups(off.text), `${field}: ${written}`).toEqual(digitGroups(written))
        // As production reads it: the same text, plus " de 10" written in and nothing else.
        const once = projectFlowPlainTrainingText(written, field)
        if (once.replaced > 0) acted += 1
        else expect(once.text, written).toBe(written)
        expect(once.text.replaceAll(' de 10', ''), `${field}: ${written}`).toBe(
          off.text.replaceAll(' de 10', ''),
        )
        expect(scales(once.text), `${field}: ${written}`).toBeGreaterThanOrEqual(scales(off.text))
        expect(projectFlowPlainTrainingText(once.text, field), `${field}: ${written}`).toEqual({
          text: once.text,
          replaced: 0,
        })
      }
      // More than half of every block (it was more than 10,000 of the 20,000).
      expect(acted).toBeGreaterThan(SEEDED_BLOCK / 2)
    },
  )

  it('for a whole draft, limits included', () => {
    const candidate = {
      notes: `${'Beba água durante o treino. '.repeat(17)}Use pegada pronada. Faça 12 reps. RPE 8.`,
      progression_rule: 'Use progressão linear: 6 reps, depois 7 reps.',
      weekly_schedule: [
        {
          day: 'Upper A',
          focus: 'Push/Pull',
          duration_min: 60,
          exercises: [
            {
              name: 'Supino',
              muscle_group: 'Isquiotibiais/Glúteos',
              sets: 3,
              reps_range: 'até falha',
              rest_seconds: 60,
              rpe_target: 'RPE 8/10',
              notes: 'Composto principal.',
              execution_steps: ['Pegada pronada.'],
              common_mistakes: ['Perder retração escapular'],
            },
          ],
        },
      ],
    }
    const once = projectFlowPlainTrainingDraft(candidate)
    expect(once.termsReplaced).toBeGreaterThan(0)
    const twice = projectFlowPlainTrainingDraft(once.payload)
    expect(twice.payload).toEqual(once.payload)
    expect(twice.termsReplaced).toBe(0)
  })
})

describe('U6 no replacement is read as medication or supplement', () => {
  it('every plain text of the table, and of the rows that rename an exercise', () => {
    expect(FLOW_PLAIN_TRAINING_VOCABULARY.length).toBeGreaterThan(0)
    for (const row of [...FLOW_PLAIN_TRAINING_VOCABULARY, ...FLOW_PLAIN_TRAINING_RENAMES_AWAITING_OWNER]) {
      for (const output of [row.plain, row.one].filter((entry) => entry !== undefined)) {
        const written = String(output).replace('<nota>', '8').replace('<n>', '2')
        expect(classifyHealthProduct(written, 'item'), written).toBeNull()
        expect(classifyHealthProduct(written, 'text'), written).toBeNull()
      }
    }
  })
})

describe('U7 only the app\'s workout proposal uses the vocabulary', () => {
  const here = dirname(fileURLToPath(import.meta.url))
  const repository = resolve(here, '../../..')
  const MODULE = /flow-plain-training-language/

  function sources(root: string): string[] {
    return (readdirSync(root, { recursive: true }) as string[])
      .filter((entry) => /\.(?:ts|tsx|mts|mjs|js)$/.test(entry))
      .filter((entry) => !/(?:^|\/)(?:node_modules|\.next|\.vercel|\.turbo|dist)\//.test(entry))
      .map((entry) => resolve(root, entry))
  }

  it('(a) exactly one source file imports it, and nothing outside the agent names it', () => {
    const agent = sources(here)
    const importers = agent
      .filter((file) => !file.endsWith('.test.ts'))
      .filter((file) => {
        const source = readFileSync(file, 'utf8')
        return /(?:from|import)\s*\(?\s*['"][^'"]*flow-plain-training-language(?:\.js)?['"]/.test(source)
      })
      .map((file) => relative(here, file))
    expect(importers).toEqual(['tools/plan-proposal-tools.ts'])

    // Named, so the list above cannot be read as luck.
    for (const file of [
      'tools.ts',
      'plan-draft.ts',
      'plan-document-extractor.ts',
      'training-plan-generator.ts',
      'pipeline.ts',
      'plan-suggestion-text.ts',
      'index.ts',
    ]) {
      expect(readFileSync(resolve(here, file), 'utf8'), file).not.toMatch(MODULE)
    }
    // The package does not export it, and no other package or app names it.
    const manifest = readFileSync(resolve(here, '../package.json'), 'utf8')
    expect(manifest).not.toMatch(MODULE)
    const elsewhere = [
      'packages/core/src',
      'packages/db/src',
      'packages/providers/src',
      'packages/inngest-functions/src',
      'apps/admin/src',
      'apps/mobile-bff/src',
      'apps/mobile-bff/scripts',
    ]
      .flatMap((root) => sources(resolve(repository, root)))
      .filter((file) => MODULE.test(readFileSync(file, 'utf8')))
      .map((file) => relative(repository, file))
    expect(elsewhere).toEqual([])
  })

  it('(b) it is called once, with one argument, inside propoe_plano_treino', () => {
    const source = readFileSync(resolve(here, 'tools/plan-proposal-tools.ts'), 'utf8')
    const calls = Array.from(source.matchAll(/projectFlowPlainTrainingDraft\s*\(([^()]*)\)/g))
    expect(calls).toHaveLength(1)
    expect(source.match(/projectFlowPlainTrainingDraft/g)).toHaveLength(2) // the import and the call
    expect(calls[0]?.[1]?.trim()).toMatch(/^[A-Za-z_]\w*$/)
    const at = calls[0]?.index ?? -1
    expect(at).toBeGreaterThan(source.indexOf('name: PROPOSE_TRAINING_PLAN_TOOL'))
    expect(at).toBeLessThan(source.indexOf('const proposeDiet'))
    // The text function is never called from the tool: one hook only.
    expect(source).not.toMatch(/projectFlowPlainTrainingText/)
  })
})

const MASCULINE_PLURAL_TO_FEMININE = { os: 'a', dos: 'da', nos: 'na', aos: 'à', pelos: 'pela' }
/** "o Upper" → "a parte de cima do corpo". */
const MASCULINE_TO_FEMININE = { o: 'a', do: 'da', no: 'na', ao: 'à', pelo: 'pela', um: 'uma' }
/** "no Legs" → "nas pernas". */
const MASCULINE_TO_FEMININE_PLURAL = { o: 'as', do: 'das', no: 'nas', ao: 'às', pelo: 'pelas' }
/** "a PSE" → "o esforço": the same determiners with and without a grade after it. */
const FEMININE_TO_MASCULINE = { a: 'o', da: 'do', na: 'no', à: 'ao', pela: 'pelo', uma: 'um' }

/** The active table, written by hand: a row added or changed is a red test. */
const EXPECTED_VOCABULARY = [
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
  { id: 'linear_progression', spellings: ['progressão linear'], plain: 'evolução passo a passo' },
  { id: 'reps', spellings: ['reps'], plain: 'repetições', rule: 'count_unit' },
  { id: 'rep', spellings: ['rep'], plain: 'repetição', rule: 'count_unit' },
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
 * The rows that rename an exercise. Both are ON in production since the second
 * round of 2026-10-10 (decisão do orquestrador, anunciada ao dono em
 * 2026-10-10, que pode riscar qualquer uma; the owner's written yes is still
 * blank). The exported name of the list did not change.
 */
const EXPECTED_RENAMES_AWAITING_OWNER = [
  {
    id: 'hip_thrust',
    spellings: ['Hip Thrust', 'Hip-Thrust'],
    plain: 'elevação pélvica',
    articles: { o: 'a', do: 'da', no: 'na', ao: 'à', um: 'uma' },
  },
  { id: 'military_press', spellings: ['Military press'], plain: 'desenvolvimento militar' },
]

describe('U8 no row adds or removes a number, and no row adds an instruction', () => {
  it('(a) the active table is this literal, row by row', () => {
    expect(FLOW_PLAIN_TRAINING_VOCABULARY).toEqual(EXPECTED_VOCABULARY)
    expect(FLOW_PLAIN_TRAINING_RENAMES_AWAITING_OWNER).toEqual(EXPECTED_RENAMES_AWAITING_OWNER)
    const ids = [...EXPECTED_VOCABULARY, ...EXPECTED_RENAMES_AWAITING_OWNER].map((row) => row.id)
    expect(new Set(ids).size).toBe(ids.length)
    // The closed list of English neighbours (rule 4), word by word.
    expect(FLOW_PLAIN_TRAINING_ENGLISH_NEIGHBOURS).toEqual([
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
    ])
  })

  it('(a) every spelling of the literal table acts, and gives the row\'s plain text', () => {
    for (const row of EXPECTED_VOCABULARY) {
      for (const spelling of row.spellings) {
        const written = probe(row, spelling)
        const result = projectFlowPlainTrainingText(written, 'notes')
        const expected = row.plain.replace('<nota>', '8').replace('<n>', '2')
        expect(result.replaced, `${row.id}: ${spelling}`).toBeGreaterThanOrEqual(1)
        expect(result.text.toLowerCase(), `${row.id}: ${spelling}`).toContain(expected.toLowerCase())
      }
    }
  })

  it('(b) the digit groups of the output are those of the input, in the same order', () => {
    const lines = [
      '6 reps',
      '12reps',
      'RPE 8/10',
      'RPE 8-9',
      'RIR 2',
      '2 RIR',
      'Treino até próximo da falha técnica (RPE 8-9). Descanso 60-120s. 5min de cardio. Durma 7-9h.',
      'progressão linear 6→7→8→...→12 reps, então aumenta peso e volta pra 6',
      '1ª semana 12-15 reps, 2ª semana 10-12 reps, 3ª semana 8-10 reps, 4ª semana 6-8 reps.',
    ]
    for (const row of [...EXPECTED_VOCABULARY, ...EXPECTED_RENAMES_AWAITING_OWNER]) {
      for (const spelling of row.spellings) lines.push(probe(row, spelling))
    }
    for (const written of lines) {
      for (const field of ['notes', 'name', 'rpe_target', 'reps_range', 'day'] as const) {
        // With the two switches written off (they are on in production: U9).
        const off = projectFlowPlainTrainingText(written, field, ALL_OFF).text
        expect(digitGroups(off), `${field}: ${written}`).toEqual(digitGroups(written))
        // With both switches on, the only group added is the "10" of " de 10".
        const on = projectFlowPlainTrainingText(written, field, {
          effortOutOfTen: true,
          renames: ['hip_thrust', 'military_press'],
        }).text
        const added = on.split(' de 10').length - written.split(' de 10').length
        expect(digitGroups(on.replaceAll(' de 10', '')), `${field} (on): ${written}`).toEqual(
          digitGroups(written.replaceAll(' de 10', '').replaceAll(/\s*\/\s*10\b/g, '')),
        )
        expect(added).toBeGreaterThanOrEqual(0)
      }
    }
  })

  it('(c) no plain text of the table carries a digit, an instruction verb or a joint', () => {
    expect(FLOW_PLAIN_TRAINING_VOCABULARY.length).toBeGreaterThan(0)
    const forbidden =
      /(?<![\p{L}])(?:mantenha|segure|desça|suba|empurre|puxe|dobre|estenda|trave|contraia|joelhos?|cotovelos?|coluna|punhos?|quadril|tornozelos?)(?![\p{L}])/iu
    for (const row of [...FLOW_PLAIN_TRAINING_VOCABULARY, ...FLOW_PLAIN_TRAINING_RENAMES_AWAITING_OWNER]) {
      for (const output of [row.plain, row.one].filter((entry) => entry !== undefined)) {
        expect(String(output), row.id).not.toMatch(/\d/)
        expect(String(output), row.id).not.toMatch(forbidden)
      }
    }
  })
})

describe('U9 the two decisions are ON, and each switch is exact on its own', () => {
  // Second round of 2026-10-10. D1 (the scale of the effort grade) and D2 (the
  // two exercise names) were turned on by decisão do orquestrador, anunciada
  // ao dono em 2026-10-10, que pode riscar qualquer uma. Striking one is
  // taking its entry out of the literal of (a): (c) pins what comes back.
  const on = (switches: { effortOutOfTen?: boolean; renames?: string[] }) => ({
    effortOutOfTen: switches.effortOutOfTen ?? false,
    renames: switches.renames ?? [],
  })

  it('(a) the switches are on, and frozen', () => {
    expect(FLOW_PLAIN_TRAINING_OWNER_SWITCHES).toEqual({
      effortOutOfTen: true,
      renames: ['hip_thrust', 'military_press'],
    })
    expect(Object.isFrozen(FLOW_PLAIN_TRAINING_OWNER_SWITCHES)).toBe(true)
    expect(Object.isFrozen(FLOW_PLAIN_TRAINING_OWNER_SWITCHES.renames)).toBe(true)
  })

  it('(b) by default the two exercises carry the Portuguese name with the original in parentheses, and a grade from 1 to 10 says "de 10"', () => {
    for (const [written, expected] of [
      // The reported draft, and the example of the decision (the generator wrote "com barra").
      ['Hip Thrust com Barra', 'Elevação pélvica com Barra (Hip Thrust)'],
      ['Hip Thrust com barra', 'Elevação pélvica com barra (Hip Thrust)'],
      ['Military press', 'Desenvolvimento militar (Military press)'],
      ['Hip-Thrust unilateral', 'Elevação pélvica unilateral (Hip-Thrust)'],
    ] as const) {
      expect(plain(written, 'name'), written).toBe(expected)
    }
    expect(plain('Faça o hip thrust devagar')).toBe('Faça a elevação pélvica (hip thrust) devagar')
    // "Stiff" and "Leg Press" stay exactly as the generator wrote them.
    for (const name of ['Leg Press 45°', 'Stiff Unilateral com Halter', 'Stiff (levantamento romeno)']) {
      expect(plain(name, 'name')).toBe(name)
      expect(plain(`Faça ${name} devagar.`)).toBe(`Faça ${name} devagar.`)
    }
    for (const [written, expected] of [
      ['9', '9 de 10'],
      ['8-9', '8-9 de 10'],
      ['7-8', '7-8 de 10'],
      ['7.5', '7.5 de 10'],
      ['10', '10 de 10'],
      ['8/10', '8 de 10'],
      ['9 de 10', '9 de 10'],
      ['15', '15'],
      ['moderado', 'moderado'],
    ] as const) {
      expect(plain(written, 'rpe_target'), written).toBe(expected)
    }
    // The shape does not change: a text, within the field's 40 characters.
    expect(typeof plain('9', 'rpe_target')).toBe('string')
  })

  it('(c) with each switch written off, the output is the one of before the decision (lock)', () => {
    const off = on({})
    for (const name of ['Hip Thrust com Barra', 'Military press', 'Leg Press 45°', 'Stiff Unilateral com Halter']) {
      expect(projectFlowPlainTrainingText(name, 'name', off)).toEqual({ text: name, replaced: 0 })
      expect(projectFlowPlainTrainingText(`Faça ${name} devagar.`, 'notes', off).text).toBe(`Faça ${name} devagar.`)
      // The scale on does not rename.
      expect(projectFlowPlainTrainingText(name, 'name', on({ effortOutOfTen: true })).text).toBe(name)
    }
    for (const grade of ['9', '8-9', '7.5', '7-8', '15', 'moderado']) {
      expect(projectFlowPlainTrainingText(grade, 'rpe_target', off)).toEqual({ text: grade, replaced: 0 })
      // The renames on do not write the scale.
      expect(
        projectFlowPlainTrainingText(grade, 'rpe_target', on({ renames: ['hip_thrust', 'military_press'] })).text,
      ).toBe(grade)
    }
    // Inside rpe_target, the repeated label leaves and "/10" is written out, scale or not.
    for (const [written, expected] of [
      ['RPE 8', '8'],
      ['RPE 8-9', '8-9'],
      ['8/10', '8 de 10'],
      ['RPE 8/10', '8 de 10'],
      ['PSE 15', '15'],
    ] as const) {
      expect(projectFlowPlainTrainingText(written, 'rpe_target', off).text, written).toBe(expected)
    }
    expect(projectFlowPlainTrainingText('Treine com RPE 8-9.', 'notes', off).text).toBe('Treine com esforço 8-9.')
  })

  it('(d) one rename on alone is exact, and leaves the other name', () => {
    const hip = on({ renames: ['hip_thrust'] })
    expect(projectFlowPlainTrainingText('Hip Thrust com Barra', 'name', hip).text).toBe(
      'Elevação pélvica com Barra (Hip Thrust)',
    )
    expect(projectFlowPlainTrainingText('Faça o hip thrust devagar', 'notes', hip).text).toBe(
      'Faça a elevação pélvica (hip thrust) devagar',
    )
    expect(projectFlowPlainTrainingText('Military press', 'name', hip).text).toBe('Military press')
    const military = on({ renames: ['military_press'] })
    expect(projectFlowPlainTrainingText('Military press', 'name', military).text).toBe(
      'Desenvolvimento militar (Military press)',
    )
    expect(projectFlowPlainTrainingText('Hip Thrust com Barra', 'name', military).text).toBe(
      'Hip Thrust com Barra',
    )
  })

  it('(e) the scale on alone: the grade says "de 10" and nothing else is added', () => {
    const scale = on({ effortOutOfTen: true })
    for (const [written, expected] of [
      ['9', '9 de 10'],
      ['8-9', '8-9 de 10'],
      ['7.5', '7.5 de 10'],
      ['RPE 8', '8 de 10'],
      ['8/10', '8 de 10'],
      ['9 de 10', '9 de 10'],
      ['15', '15'],
      ['PSE 15', '15'],
      ['moderado', 'moderado'],
    ] as const) {
      expect(projectFlowPlainTrainingText(written, 'rpe_target', scale).text, written).toBe(expected)
    }
    expect(projectFlowPlainTrainingText('Treine com RPE 8-9.', 'notes', scale).text).toBe(
      'Treine com esforço 8-9 de 10.',
    )
    expect(projectFlowPlainTrainingText('Treine com RPE 8 de 10.', 'notes', scale).text).toBe(
      'Treine com esforço 8 de 10.',
    )
    expect(projectFlowPlainTrainingText('Treine com RPE 15.', 'notes', scale).text).toBe(
      'Treine com esforço 15.',
    )
  })
})

describe('U10 what counts as a letter and as a digit (rule 2)', () => {
  /** True when the term was NOT read: the character beside it is glue. */
  const gluedAfter = (char: string) => projectFlowPlainTrainingText(`Core${char}`, 'notes').replaced === 0
  const gluedBefore = (char: string) => projectFlowPlainTrainingText(`${char}Core`, 'notes').replaced === 0

  it('up to U+024F it is what Unicode calls a letter or a number, character by character (plus "_", "@", "-")', () => {
    // The whole of Basic Latin, Latin-1 and Latin Extended-A and B: every
    // character Portuguese is written with. The boundaries are explicit
    // ranges; this is the proof that, here, they say what the Unicode
    // classes said before (review of 2026-10-10).
    const unicodeGlue = /[\p{L}\p{N}_@-]/u
    const wrongAfter: string[] = []
    const wrongBefore: string[] = []
    let glue = 0
    for (let code = 0; code <= 0x24f; code += 1) {
      const char = String.fromCodePoint(code)
      const expected = unicodeGlue.test(char)
      if (expected) glue += 1
      const label = `U+${code.toString(16).toUpperCase().padStart(4, '0')}`
      if (gluedAfter(char) !== expected) wrongAfter.push(label)
      if (gluedBefore(char) !== expected) wrongBefore.push(label)
    }
    expect(wrongAfter).toEqual([])
    expect(wrongBefore).toEqual([])
    // ASCII: 52 letters, 10 digits, "_", "@", "-". Latin-1: 65 letters and 6
    // numbers. Latin Extended-A and B: 128 and 208 letters.
    expect(glue).toBe(65 + 71 + 128 + 208)
    // By name, the ones a range could forget: ordinals, micro, superscripts, fractions.
    for (const char of ['ª', 'º', 'µ', '²', '³', '¹', '¼', '½', '¾', 'ß', 'ÿ', 'ı', 'ɏ']) {
      expect(gluedAfter(char), char).toBe(true)
      expect(gluedBefore(char), char).toBe(true)
    }
    // And the two signs that sit between the accented letters.
    for (const char of ['×', '÷']) {
      expect(gluedAfter(char), char).toBe(false)
      expect(gluedBefore(char), char).toBe(false)
    }
  })

  it('beyond U+024F nothing is a letter nor a number: a term glued to another alphabet is read (known limit, RC TL-15)', () => {
    const others = ['ɐ', 'α', 'ж', 'א', 'ع', 'क', '中', 'あ', '한', 'ẽ', 'ﬁ', 'Ａ', '٣', '①', '𝐀']
    for (const char of others) {
      // The sample is what it says: a letter or a number for Unicode, beyond U+024F.
      expect(/^[\p{L}\p{N}]$/u.test(char), char).toBe(true)
      expect(char.codePointAt(0) ?? 0, char).toBeGreaterThan(0x24f)
      expect(gluedAfter(char), char).toBe(false)
      expect(gluedBefore(char), char).toBe(false)
    }
    expect(plain('Treino de Coreж')).toBe('Treino de abdômenж')
    expect(plain('Core①')).toBe('Abdômen①')
    expect(plain('αCore')).toBe('αabdômen')
  })

  it.each([
    // The signs outside Latin-1 a model writes around a term: none is glue.
    ['Bateu 12 reps → aumenta peso', 'Bateu 12 repetições → aumenta peso', 'notes'],
    ['Push→Pull→Legs', 'Empurrar→puxar→pernas', 'notes'],
    ['Push → Pull → Legs', 'Empurrar → puxar → pernas', 'focus'],
    ['RPE 8–9', 'Esforço 8–9 de 10', 'notes'],
    ['RPE 8–9', '8–9 de 10', 'rpe_target'],
    ['Descanso 60–90 s; faça 8–12 reps', 'Descanso 60–90 s; faça 8–12 repetições', 'notes'],
    ['Aqueça — Core no fim', 'Aqueça — abdômen no fim', 'notes'],
    ['Treino de Core… depois alongue', 'Treino de abdômen… depois alongue', 'notes'],
    ['“Core” no fim', '“abdômen” no fim', 'notes'],
    ['Faça o ‘Push’ na segunda', 'Faça o ‘empurrar’ na segunda', 'notes'],
    ['Core 💪', 'Abdômen 💪', 'focus'],
    ['💪Core', '💪abdômen', 'focus'],
    ['• Compostos primeiro', '• exercícios de vários músculos primeiro', 'notes'],
    ['Supino Reto – pegada pronada', 'Supino Reto – pegada por cima', 'name'],
    ['Mesa flexora — isquiotibiais', 'Mesa flexora — músculos de trás da coxa', 'name'],
  ] as const)('%j → %j (%s)', (written, expected, field) => {
    expect(plain(written, field)).toBe(expected)
  })
})

describe('U11 RIR and its count (rule 11)', () => {
  const counts = ['1', '2', '3', '10', '12', '1-2', '2-3'] as const
  const left = (count: string) => (count === '1' ? '1 repetição de sobra' : `${count} repetições de sobra`)

  it('the three sentences of the review of 2026-10-10 keep their meaning: nothing is replaced', () => {
    // Before, the number BEFORE the acronym was taken as the count: "Semana 1
    // RIR 3" became "Semana 1 repetição de sobra 3" (week 1 with 1 repetition
    // left, when it is 3), "Séries de 12 RIR 2." became "Séries de 12
    // repetições de sobra 2." and "… 10 RIR 2-3." became "… 10 repetições de
    // sobra 2-3.". The digits kept their order and said another thing.
    for (const written of [
      'Semana 1 RIR 3, semana 2 RIR 2, semana 3 RIR 1.',
      'Séries de 12 RIR 2.',
      'Faça 3 séries de 10 RIR 2-3.',
    ]) {
      for (const field of ['notes', 'progression_rule', 'exercise_notes', 'execution_steps'] as const) {
        expect(projectFlowPlainTrainingText(written, field), `${field}: ${written}`).toEqual({
          text: written,
          replaced: 0,
        })
      }
    }
  })

  it('with a number on ONE side the count is that number; with a number on both sides the acronym stays', () => {
    for (const a of counts) {
      // The count before, the count after: the plain text carries that very count.
      expect(plain(`Deixe ${a} RIR em cada série.`), a).toBe(`Deixe ${left(a)} em cada série.`)
      expect(plain(`Termine com RIR ${a} em cada série.`), a).toBe(`Termine com ${left(a)} em cada série.`)
      for (const b of counts) {
        // Nobody knows which one is the count: no word is replaced, no number moves.
        for (const written of [`Séries de ${a} RIR ${b}.`, `Séries de ${a}RIR${b}.`, `Séries de ${a} RIR: ${b}.`, `Séries de ${a} RIR = ${b}.`]) {
          expect(projectFlowPlainTrainingText(written, 'notes'), written).toEqual({ text: written, replaced: 0 })
        }
      }
    }
  })

  it.each([
    // A dash between the number and the acronym does not free it: the plain
    // text would read as a range ("Semana 1 - 3 repetições de sobra").
    'Semana 1 - RIR 3, semana 2 - RIR 2.',
    'Semana 1 – RIR 3; semana 2 – RIR 2.',
    'Semana 1 — RIR 3',
    'Séries de 12 - RIR 2 - 3',
  ])('%j stays as written', (written) => {
    expect(projectFlowPlainTrainingText(written, 'notes')).toEqual({ text: written, replaced: 0 })
  })

  it.each([
    // A number that is not beside the acronym does not count as a side.
    ['Séries de 12, RIR 2.', 'Séries de 12, 2 repetições de sobra.'],
    ['Séries de 12 (RIR 2).', 'Séries de 12 (2 repetições de sobra).'],
    ['Deixe 2 RIR, 3 séries.', 'Deixe 2 repetições de sobra, 3 séries.'],
    ['Deixe 2 RIR em 3 séries.', 'Deixe 2 repetições de sobra em 3 séries.'],
    ['8-12 reps RIR 2', '8-12 repetições 2 repetições de sobra'],
    ['Semana 1: RIR 3. Semana 2: RIR 2.', 'Semana 1: 3 repetições de sobra. Semana 2: 2 repetições de sobra.'],
    // The number before may be the grade of the effort: it is a number all the same.
    // Since the second round the grade says its scale; after a dash it does not (the dash may go on).
    ['RPE 8 RIR 2', 'Esforço 8 de 10 RIR 2'],
    ['RPE 8 - RIR 2', 'Esforço 8 - RIR 2'],
    ['RPE 8, RIR 2', 'Esforço 8 de 10, 2 repetições de sobra'],
    ['RPE 8 (RIR 2)', 'Esforço 8 de 10 (2 repetições de sobra)'],
    ['12 reps - RIR 2', '12 repetições - 2 repetições de sobra'],
    ['- RIR 2 em todas as séries', '- 2 repetições de sobra em todas as séries'],
    // A range is read as the count when it is written as one ("2-3"). With
    // spaces around the dash the second number may be another thing ("RIR 2 -
    // 3 séries"): the words take the place of the acronym and no number moves.
    ['Termine com RIR 2-3.', 'Termine com 2-3 repetições de sobra.'],
    ['Termine com RIR 2–3.', 'Termine com 2–3 repetições de sobra.'],
    ['RIR 2 - 3 séries de 10', 'Repetições de sobra 2 - 3 séries de 10'],
    ['Termine com RIR 2 – 3.', 'Termine com repetições de sobra 2 – 3.'],
    ['RIR 2 – descanse 60 s', '2 repetições de sobra – descanse 60 s'],
    // Before the acronym a spaced range keeps its place, as the acronym had it.
    ['Deixe 2 - 3 RIR.', 'Deixe 2 - 3 repetições de sobra.'],
    // Glued, alone, and with ":".
    ['2RIR', '2 repetições de sobra'],
    ['RIR2', '2 repetições de sobra'],
    ['RIR', 'Repetições de sobra'],
    ['RIR: 2', 'Repetições de sobra: 2'],
    ['Deixe 1-2 RIR.', 'Deixe 1-2 repetições de sobra.'],
    // The words, which already bind the number as the plain text does, are renamed in place.
    ['2 repetições em reserva 3', '2 repetições de sobra 3'],
  ])('%j → %j', (written, expected) => {
    expect(plain(written)).toBe(expected)
  })
})

// ── Second round of 2026-10-10 ──────────────────────────────────────────────
// The open LOW findings of the review of 3b65bee (S3a, S3c) and what the two
// switches do (D2, D1). Every test below NAMES its switches: none depends on
// what production has on.

describe('U12 a participle is not the exercise (rule 6; review of 2026-10-10)', () => {
  const RUNNING_FIELDS = ['notes', 'progression_rule', 'exercise_notes', 'execution_steps'] as const
  // The first sentence is the one the review reported. The second ("e") was
  // written here: the reviewer's own sentence is in no record (RC TL-17).
  const PARTICIPLES = [
    'Treino ABC, composto principalmente por exercícios básicos.',
    'Treino dividido em três dias e composto principalmente por exercícios básicos.',
    'Composto principalmente por exercícios básicos, o treino dura 60 minutos.',
    'Treinos A e B, compostos basicamente de exercícios livres.',
    'exercícios compostos principalmente por duas fases',
    // The closed list of adverbs, one by one, and two in a row.
    ...[
      'apenas',
      'só',
      'somente',
      'sobretudo',
      'quase',
      'também',
      'ainda',
      'sempre',
      'tanto',
      'essencialmente',
      'em grande parte',
      'em sua maioria',
      'na maior parte',
      // Typed without the accent.
      'so',
      'tambem',
    ].map((adverb) => `Treino ABC, composto ${adverb} por exercícios básicos.`),
    'Treino ABC, composto quase sempre por exercícios básicos.',
    'Treino de 4 dias ou composto somente de exercícios livres.',
  ]

  it.each(PARTICIPLES)('%j stays as written, in every running text', (written) => {
    for (const field of RUNNING_FIELDS) {
      expect(projectFlowPlainTrainingText(written, field, ALL_OFF), field).toEqual({ text: written, replaced: 0 })
    }
  })

  it.each([
    // Locks: the noun is still replaced, as before.
    ['Compostos antes de isoladores.', 'Exercícios de vários músculos antes de exercícios de um músculo só.'],
    ['Compostos somente no início.', 'Exercícios de vários músculos somente no início.'],
    ['Compostos primeiro, isoladores depois.', 'Exercícios de vários músculos primeiro, exercícios de um músculo só depois.'],
    // After a determiner or a preposition the adverb is not read through.
    [
      'os compostos normalmente de 6 a 10 repetições',
      'os exercícios de vários músculos normalmente de 6 a 10 repetições',
    ],
    ['Comece com compostos principalmente de pernas.', 'Comece com exercícios de vários músculos principalmente de pernas.'],
    // An adverb with no "por"/"de" after it changes nothing.
    ['Treino ABC, compostos principalmente.', 'Treino ABC, exercícios de vários músculos principalmente.'],
    // Known limit (RC TL-17): another word between the participle and the preposition.
    [
      'Treino ABC, composto na prática por exercícios básicos.',
      'Treino ABC, exercício de vários músculos na prática por exercícios básicos.',
    ],
  ])('%j → %j', (written, expected) => {
    expect(projectFlowPlainTrainingText(written, 'notes', ALL_OFF).text).toBe(expected)
  })

  it('known limit (RC TL-17): at the start, a noun followed by an adverb of the list and "de" stays as generated', () => {
    expect(projectFlowPlainTrainingText('Compostos sempre de manhã.', 'notes', ALL_OFF)).toEqual({
      text: 'Compostos sempre de manhã.',
      replaced: 0,
    })
  })
})

describe('U13 "falha" alone in the repetitions and effort fields, inside a closed grammar (rule 5; review of 2026-10-10)', () => {
  // The reviewer's own spellings are in no record: these were read from the code (RC TL-18).
  const SMALL_FIELDS = ['reps_range', 'rpe_target'] as const

  it.each([
    ['falha', 'até a última repetição bem feita'],
    ['Falha técnica', 'Até a última repetição bem feita'],
    ['falha muscular', 'até a última repetição bem feita'],
    ['falha.', 'até a última repetição bem feita.'],
    ['8-12 ou falha', '8-12 ou até a última repetição bem feita'],
    ['8-12 (falha)', '8-12 (até a última repetição bem feita)'],
    ['8-12 - falha', '8-12 - até a última repetição bem feita'],
    ['12 falha', '12 até a última repetição bem feita'],
    ['8-12, falha', '8-12, até a última repetição bem feita'],
    ['8-12/falha', '8-12/até a última repetição bem feita'],
    ['falha ou 12', 'até a última repetição bem feita ou 12'],
    // The form the vocabulary already covered, unchanged.
    ['até falha', 'até a última repetição bem feita'],
    ['8-12 ou até a falha', '8-12 ou até a última repetição bem feita'],
  ])('%j → %j', (written, expected) => {
    for (const field of SMALL_FIELDS) {
      const once = projectFlowPlainTrainingText(written, field, ALL_OFF)
      expect(once, field).toEqual({ text: expected, replaced: 1 })
      expect(once.text.length, field).toBeLessThanOrEqual(40)
      // Applying it again changes nothing more.
      expect(projectFlowPlainTrainingText(once.text, field, ALL_OFF), field).toEqual({ text: expected, replaced: 0 })
    }
  })

  it.each([
    // Outside the grammar: after another word, glued to a hyphen, or followed by another word.
    'sem falha',
    'pré-falha',
    '8-12-falha',
    'Falha total',
    'falha na última série',
    'evite a falha',
    '8-12 falhas',
    // An address is protected as a span (rule 3), here too.
    'https://exemplo.com/falha',
  ])('%j stays as written', (written) => {
    for (const field of SMALL_FIELDS) {
      expect(projectFlowPlainTrainingText(written, field, ALL_OFF), field).toEqual({ text: written, replaced: 0 })
    }
  })

  it('the grammar is of the two small fields only: in running text "falha" keeps rule 5', () => {
    for (const written of ['Falha', 'falha', 'Corrija qualquer falha técnica', '8-12 ou falha', '12 falha']) {
      for (const field of ['notes', 'exercise_notes', 'execution_steps', 'focus', 'name'] as const) {
        expect(projectFlowPlainTrainingText(written, field, ALL_OFF), `${field}: ${written}`).toEqual({
          text: written,
          replaced: 0,
        })
      }
    }
  })

  // The range of two digits and two digits is the most likely value of the
  // field, and its plain text has 41 characters: it stays as generated. A
  // declared pendency (RC TL-18), with the exact strings of the review of
  // the second round.
  it.each([
    ['10-12 ou falha', '10-12 ou até a última repetição bem feita'],
    ['12-15 ou falha', '12-15 ou até a última repetição bem feita'],
    ['10-12 ou até a falha', '10-12 ou até a última repetição bem feita'],
  ])('%j: its plain text passes 40 characters, so it stays as generated, and is counted (RC TL-18)', (written, plainText) => {
    expect(plainText).toHaveLength(41)
    for (const field of SMALL_FIELDS) {
      expect(projectFlowPlainTrainingText(written, field, ALL_OFF).text, field).toBe(plainText)
      for (const switches of [ALL_OFF, FLOW_PLAIN_TRAINING_OWNER_SWITCHES]) {
        const result = projectFlowPlainTrainingDraft(
          {
            weekly_schedule: [
              { day: 'Segunda', focus: 'Peito', duration_min: 60, exercises: [{ name: 'Supino', [field]: written }] },
            ],
          },
          switches,
        )
        const exercise = (result.payload as { weekly_schedule: Array<{ exercises: Array<Record<string, unknown>> }> })
          .weekly_schedule[0]?.exercises[0]
        expect(exercise?.[field], field).toBe(written)
        expect(result.fieldsKeptAsGenerated, field).toBe(1)
        expect(result.termsReplaced, field).toBe(0)
      }
    }
  })
})

describe("U14 the field's own label leaves rpe_target without leftovers (rule 9; review of 2026-10-10)", () => {
  // The app prints this field after its own label ("Esforço alvo"). The
  // reviewer's spellings are in no record: these were read from the code (RC TL-19).
  const SCALE_ON = { effortOutOfTen: true, renames: [] as string[] }

  it.each([
    // written, with the scale off, with the scale on
    ['a PSE 8', '8', '8 de 10'],
    ['RPE alto', 'alto', 'alto'],
    ['8 RPE', '8', '8 de 10'],
    ['Esforço 8', '8', '8 de 10'],
    ['esforço 8-9', '8-9', '8-9 de 10'],
    ['RPE alvo: 8', '8', '8 de 10'],
    ['Esforço alto', 'alto', 'alto'],
    ['Esforço alvo 9', '9', '9 de 10'],
    ['Esforço: moderado', 'moderado', 'moderado'],
    ['Esforço 8 de 10', '8 de 10', '8 de 10'],
    ['8 esforço', '8', '8 de 10'],
    ['RPE 8.', '8.', '8 de 10.'],
    ['PSE 15', '15', '15'],
  ] as const)('%j → %j (scale off) and %j (scale on)', (written, off, scaled) => {
    for (const [switches, expected] of [
      [ALL_OFF, off],
      [SCALE_ON, scaled],
    ] as const) {
      const once = projectFlowPlainTrainingText(written, 'rpe_target', switches)
      expect(once.text).toBe(expected)
      expect(once.replaced).toBe(1)
      expect(projectFlowPlainTrainingText(once.text, 'rpe_target', switches)).toEqual({ text: expected, replaced: 0 })
    }
  })

  it.each([
    // Locks: what the label rule leaves alone (RC TL-19).
    ['RPE', 'Esforço'],
    ['PSE alta', 'PSE alta'],
    ['Esforço percebido 8', 'Esforço percebido 8'],
    ['Esforço percebido', 'Esforço percebido'],
    ['Esforço, 8', 'Esforço, 8'],
    ['Esforço', 'Esforço'],
    ['Mantenha RPE alto', 'Mantenha esforço alto'],
    ['RPE moderado-alto', 'Esforço moderado-alto'],
    ['RPE alvo', 'Esforço alvo'],
  ] as const)('%j → %j, scale on or off', (written, expected) => {
    for (const switches of [ALL_OFF, SCALE_ON]) {
      const once = projectFlowPlainTrainingText(written, 'rpe_target', switches)
      expect(once.text).toBe(expected)
      expect(projectFlowPlainTrainingText(once.text, 'rpe_target', switches)).toEqual({ text: expected, replaced: 0 })
    }
  })

  it('outside rpe_target the word "esforço" before a grade is never taken out', () => {
    for (const field of ['notes', 'reps_range', 'exercise_notes', 'focus'] as const) {
      for (const written of ['Esforço 8', 'esforço 8-9', 'Esforço alto']) {
        expect(projectFlowPlainTrainingText(written, field, ALL_OFF), `${field}: ${written}`).toEqual({
          text: written,
          replaced: 0,
        })
      }
    }
  })
})

describe('U15 a renamed exercise keeps its original name in parentheses, once, and never twice (rule 12)', () => {
  const RENAMES = { effortOutOfTen: false, renames: ['hip_thrust', 'military_press'] }
  const read = (written: string, field: FlowPlainTrainingField) =>
    projectFlowPlainTrainingText(written, field, RENAMES)

  it.each([
    // In the name the original goes to the end.
    ['Hip Thrust com Barra', 'Elevação pélvica com Barra (Hip Thrust)', 1],
    ['Hip Thrust com barra', 'Elevação pélvica com barra (Hip Thrust)', 1],
    ['Hip Thrust', 'Elevação pélvica (Hip Thrust)', 1],
    ['Military press', 'Desenvolvimento militar (Military press)', 1],
    ['Hip-Thrust unilateral', 'Elevação pélvica unilateral (Hip-Thrust)', 1],
    ['Barra — hip thrust', 'Barra — elevação pélvica (hip thrust)', 1],
    // A name that already has a parenthesis: the original right after the Portuguese name.
    ['Hip Thrust com Barra (glúteos)', 'Elevação pélvica (Hip Thrust) com Barra (glúteos)', 1],
    // The end of the name is before its final punctuation; a second sentence is left alone.
    ['Hip Thrust com Barra.', 'Elevação pélvica com Barra (Hip Thrust).', 1],
    ['Hip Thrust com Barra. Pausa no alto', 'Elevação pélvica com Barra (Hip Thrust). Pausa no alto', 1],
  ] as const)('name %j → %j', (written, expected, replaced) => {
    const once = read(written, 'name')
    expect(once).toEqual({ text: expected, replaced })
    expect(read(once.text, 'name')).toEqual({ text: expected, replaced: 0 })
    expect(classifyHealthProduct(once.text, 'item')).toBeNull()
    expect(classifyHealthProduct(once.text, 'text')).toBeNull()
  })

  it('the lengths the brief counts', () => {
    expect('Elevação pélvica com Barra (Hip Thrust)').toHaveLength(39)
    expect('Elevação pélvica com barra (Hip Thrust)').toHaveLength(39)
    expect('Desenvolvimento militar (Military press)').toHaveLength(40)
    expect('Elevação pélvica unilateral (Hip-Thrust)').toHaveLength(40)
    expect('Elevação pélvica (Hip Thrust) com Barra (glúteos)').toHaveLength(49)
    expect('Faça a elevação pélvica (hip thrust) devagar').toHaveLength(44)
  })

  it.each([
    // In running text the original comes right after, and only at the first mention of the field.
    ['Faça o hip thrust devagar', 'Faça a elevação pélvica (hip thrust) devagar', 1],
    [
      'Faça o Hip Thrust devagar. No hip thrust, suba o quadril até o fim.',
      'Faça a elevação pélvica (Hip Thrust) devagar. Na elevação pélvica, suba o quadril até o fim.',
      2,
    ],
    [
      'Hip Thrust leve, depois Hip Thrust pesado.',
      'Elevação pélvica (Hip Thrust) leve, depois elevação pélvica pesado.',
      2,
    ],
    [
      'Hip Thrust e Military press no mesmo dia.',
      'Elevação pélvica (Hip Thrust) e desenvolvimento militar (Military press) no mesmo dia.',
      2,
    ],
  ] as const)('notes %j → %j', (written, expected, replaced) => {
    for (const field of ['notes', 'progression_rule', 'exercise_notes', 'execution_steps', 'common_mistakes'] as const) {
      const once = read(written, field)
      expect(once, field).toEqual({ text: expected, replaced })
      expect(read(once.text, field), field).toEqual({ text: expected, replaced: 0 })
    }
  })

  it('in a one-phrase field that is not the name, the original comes right after', () => {
    expect(read('Glúteos e Hip Thrust', 'focus')).toEqual({ text: 'Glúteos e elevação pélvica (Hip Thrust)', replaced: 1 })
    expect(read('Hip Thrust', 'muscle_group')).toEqual({ text: 'Elevação pélvica (Hip Thrust)', replaced: 1 })
  })

  it.each([
    // The field or the sentence already carries the Portuguese name (with or without accents, any case).
    ['Hip Thrust (elevação pélvica)', 'name'],
    ['Hip Thrust/Elevação pélvica', 'name'],
    ['Elevacao pelvica ou HIP THRUST', 'name'],
    ['Elevação pélvica com barra (Hip Thrust)', 'name'],
    ['Desenvolvimento militar (Military press)', 'name'],
    ['A elevação pélvica (hip thrust) vem primeiro.', 'notes'],
    ['Na elevação pélvica, também chamada de hip thrust, suba o quadril.', 'notes'],
    // The spelling is inside parentheses: it is the generator's own gloss.
    ['Glúteos (hip thrust)', 'name'],
    ['Glúteos (hip thrust com barra)', 'name'],
    ['Empurre o quadril (como no Hip Thrust) até o fim.', 'notes'],
    // The equipment list is what the person said they have.
    ['banco para hip thrust, barra', 'equipment_summary'],
    ['Hip Thrust', 'equipment_summary'],
    // "Stiff" and "Leg Press": no row.
    ['Stiff Unilateral com Halter', 'name'],
    ['Stiff (levantamento romeno)', 'name'],
    ['Leg Press 45°', 'name'],
    ['Leg press 45°', 'name'],
    // Glued, it is not the term (rule 2).
    ['Hip Thruster', 'name'],
  ] as const)('%j (%s) stays as written', (written, field) => {
    expect(read(written, field)).toEqual({ text: written, replaced: 0 })
  })

  it.each([
    // Known limit (RC TL-13): the row renames its two words and nothing around them.
    ['Single Leg Hip Thrust', 'Single Leg elevação pélvica (Hip Thrust)'],
    ['Hip Thrust Unilateral na Máquina', 'Elevação pélvica Unilateral na Máquina (Hip Thrust)'],
    ['Seated Military Press', 'Seated desenvolvimento militar (Military Press)'],
  ] as const)('name %j → %j: the other words of the name stay as generated', (written, expected) => {
    expect(read(written, 'name')).toEqual({ text: expected, replaced: 1 })
    expect(read(expected, 'name')).toEqual({ text: expected, replaced: 0 })
  })

  it('a name with two sentences: the one that already carries the Portuguese name stops the whole field', () => {
    const written = 'Hip Thrust com Barra. Também chamado de elevação pélvica'
    expect(read(written, 'name')).toEqual({ text: written, replaced: 0 })
  })
})

describe('U16 the scale is written only after a grade that does not go on (rule 9)', () => {
  const SCALE = { effortOutOfTen: true, renames: [] as string[] }
  const read = (written: string, field: FlowPlainTrainingField) =>
    projectFlowPlainTrainingText(written, field, SCALE).text

  it.each([
    // The grade goes on after the number: no scale (before, "esforço 8 de 10/9", "8 de 10+", "8 de 10 ou 9").
    ['Treine com RPE 8/9.', 'Treine com esforço 8/9.'],
    ['Treine com RPE 8+.', 'Treine com esforço 8+.'],
    ['Treine com RPE 8 ou 9.', 'Treine com esforço 8 ou 9.'],
    ['RPE 8 → 9 ao longo das semanas', 'Esforço 8 → 9 ao longo das semanas'],
    ['RPE 8.55', 'Esforço 8.55'],
    ['RPE 8 e 9 nas últimas', 'Esforço 8 e 9 nas últimas'],
    ['RPE 8 até 9', 'Esforço 8 até 9'],
    ['RPE 8 de 12', 'Esforço 8 de 12'],
    ['RPE 8 em 10', 'Esforço 8 em 10'],
    ['RPE 8~9', 'Esforço 8~9'],
    ['RPE 8 9', 'Esforço 8 9'],
    ['RPE 8, 9 na última', 'Esforço 8, 9 na última'],
    ['RPE 8 - RIR 2', 'Esforço 8 - RIR 2'],
    ['RPE 8%', 'Esforço 8%'],
    // The sentence already says the scale after the grade: it is not said twice.
    ['RPE 8 (de 10)', 'Esforço 8 (de 10)'],
    ['RPE 8 (escala de 0 a 10)', 'Esforço 8 (escala de 0 a 10)'],
    ['Mantenha RPE 8 numa escala de 1 a 10.', 'Mantenha esforço 8 numa escala de 1 a 10.'],
    ['RPE 8 (8/10)', 'Esforço 8 (8/10)'],
    // The scale is written.
    ['Treine com RPE 8/10.', 'Treine com esforço 8 de 10.'],
    ['Treine com RPE 8-9.', 'Treine com esforço 8-9 de 10.'],
    ['RPE 8 a 9', 'Esforço 8 a 9 de 10'],
    ['RPE 8 (pesado)', 'Esforço 8 de 10 (pesado)'],
    ['(RPE 8)', '(esforço 8 de 10)'],
    ['RPE 8, RIR 2', 'Esforço 8 de 10, 2 repetições de sobra'],
    ['RPE 8 RIR 2', 'Esforço 8 de 10 RIR 2'],
    ['RPE 8; descanse', 'Esforço 8 de 10; descanse'],
    ['Mantenha RPE 8 nas séries', 'Mantenha esforço 8 de 10 nas séries'],
    // Already written: nothing is added.
    ['Treine com RPE 8 de 10.', 'Treine com esforço 8 de 10.'],
    // Outside 1 to 10: no scale.
    ['Treine com RPE 15.', 'Treine com esforço 15.'],
  ])('notes %j → %j', (written, expected) => {
    expect(read(written, 'notes')).toBe(expected)
    expect(read(expected, 'notes')).toBe(expected)
  })

  it.each([
    ['RPE 8/9', '8/9'],
    ['RPE 8+', '8+'],
    ['RPE 8 ou 9', '8 ou 9'],
    ['RPE 8 (de 10)', '8 (de 10)'],
    ['RPE 8/10', '8 de 10'],
    ['8/9', '8/9'],
    ['8+', '8+'],
    ['8 ou 9', '8 ou 9'],
    ['RPE 8', '8 de 10'],
    ['9', '9 de 10'],
    ['8-9', '8-9 de 10'],
    ['8 a 9', '8 a 9 de 10'],
    ['10', '10 de 10'],
    ['0', '0'],
    ['11', '11'],
    // Review round 1 of the second round: the grade alone with its full stop
    // is the whole field too ("RPE 9." already gave "9 de 10.").
    ['9.', '9 de 10.'],
    ['8-9.', '8-9 de 10.'],
    ['8/10.', '8 de 10.'],
    ['15.', '15.'],
    // Known limit (RC TL-14): a grade followed by other text in the field
    // itself, without the acronym, is not read — a number before a word may
    // be another thing ("8 séries").
    ['8 (pesado)', '8 (pesado)'],
    ['8, pesado', '8, pesado'],
    ['8 séries', '8 séries'],
    // Review round 1 of the second round: a range written with spaces beside
    // its dash, then a word — the second number may be another thing.
    ['RPE 8 - 3 séries', '8 - 3 séries'],
    ['RPE 8 para 9', '8 para 9'],
    // …but the whole field as a range is the grade.
    ['8 - 9', '8 - 9 de 10'],
    ['RPE 8 - 9', '8 - 9 de 10'],
  ])('rpe_target %j → %j', (written, expected) => {
    expect(read(written, 'rpe_target')).toBe(expected)
    expect(read(expected, 'rpe_target')).toBe(expected)
  })

  it('a value that is already the same comes back as the same string, with nothing counted', () => {
    for (const written of ['8/9', '8+', '8 ou 9', '9 de 10', '9 de 10.', '15', '15.', '8 (pesado)', 'moderado']) {
      expect(projectFlowPlainTrainingText(written, 'rpe_target', SCALE)).toEqual({ text: written, replaced: 0 })
    }
  })

  // Review round 1 of the second round (2026-10-10). The grade pattern reads
  // "8 - 10" and "8 a 10" as a range. In a list written with dashes the number
  // after the dash is another thing ("RPE 8 - 10 repetições"), and with the
  // scale ON the net stored a false sentence ("10 de 10 repetições", "3 de 10
  // séries"). The four texts below are the reviewer's, through the entry
  // production uses, with production's switches.
  it('the four reported texts — a spaced range, then a word — gain no scale through projectFlowPlainTrainingDraft', () => {
    const candidate = {
      notes: 'Supino: 4 séries - RPE 8 - 10 repetições - descanso 90 s.',
      weekly_schedule: [
        {
          day: 'Segunda',
          focus: 'Peito',
          duration_min: 60,
          exercises: [
            {
              name: 'Supino',
              muscle_group: 'peito',
              sets: 4,
              reps_range: '8-12',
              rest_seconds: 90,
              rpe_target: 'RPE 8 - 3 séries',
              notes: 'RPE 7 - 3 séries de aquecimento. Depois RPE 9 – 2 séries pesadas.',
              execution_steps: ['RPE 8 a 10 repetições por série.'],
            },
          ],
        },
      ],
    }
    interface Stored {
      notes: string
      weekly_schedule: Array<{
        exercises: Array<{ rpe_target: string; notes: string; execution_steps: string[] }>
      }>
    }

    const result = projectFlowPlainTrainingDraft(candidate)
    const stored = result.payload as Stored
    const exercise = stored.weekly_schedule[0]?.exercises[0]

    expect(exercise?.notes).toBe('Esforço 7 - 3 séries de aquecimento. Depois esforço 9 – 2 séries pesadas.')
    expect(stored.notes).toBe('Supino: 4 séries - esforço 8 - 10 repetições - descanso 90 s.')
    expect(exercise?.execution_steps).toEqual(['Esforço 8 a 10 repetições por série.'])
    expect(exercise?.rpe_target).toBe('8 - 3 séries')
    // No scale anywhere, and every digit is the generator's, in the same order.
    expect(scales(JSON.stringify(stored))).toBe(0)
    expect(digitGroups(JSON.stringify(stored))).toEqual(digitGroups(JSON.stringify(candidate)))
    expect(result).toMatchObject({ termsReplaced: 5, sentencesKeptAsGenerated: 0, fieldsKeptAsGenerated: 0 })
    // With the scale written off the stored draft is the same one.
    expect(projectFlowPlainTrainingDraft(candidate, SCALE_OFF).payload).toEqual(stored)
    // Applying it again changes nothing more.
    expect(projectFlowPlainTrainingDraft(stored)).toMatchObject({ payload: stored, termsReplaced: 0 })
  })

  it.each([
    // A space beside the dash, or " a ", and then a word or "(": no scale.
    ['RPE 7 - 3 séries de aquecimento.', 'Esforço 7 - 3 séries de aquecimento.'],
    ['Depois RPE 9 – 2 séries pesadas.', 'Depois esforço 9 – 2 séries pesadas.'],
    ['Supino: 4 séries - RPE 8 - 10 repetições - descanso 90 s.', 'Supino: 4 séries - esforço 8 - 10 repetições - descanso 90 s.'],
    ['RPE 8 a 10 repetições por série.', 'Esforço 8 a 10 repetições por série.'],
    ['RPE 8- 3 séries', 'Esforço 8- 3 séries'],
    ['RPE 8 -3 séries', 'Esforço 8 -3 séries'],
    ['RPE 8 - 9 (pesado)', 'Esforço 8 - 9 (pesado)'],
    // Known limit (RC TL-14): a real range written that way loses the scale too.
    ['RPE 8 a 9 nas últimas séries', 'Esforço 8 a 9 nas últimas séries'],
    ['RPE 8 - 9 nas últimas séries', 'Esforço 8 - 9 nas últimas séries'],
    // "para" / "pra" and a number: the grade goes on (before, "esforço 8 de 10 para 9").
    ['RPE 8 para 9', 'Esforço 8 para 9'],
    ['RPE 8 pra 9', 'Esforço 8 pra 9'],
    ['Suba de RPE 7 para 8 na semana 2.', 'Suba de esforço 7 para 8 na semana 2.'],
    // Locks: the range written as one, or a spaced one after which nothing goes on, keeps the scale.
    ['RPE 8-9 nas últimas', 'Esforço 8-9 de 10 nas últimas'],
    ['RPE 8–9 (pesado)', 'Esforço 8–9 de 10 (pesado)'],
    ['RPE 8 - 9', 'Esforço 8 - 9 de 10'],
    ['(RPE 8 - 9)', '(esforço 8 - 9 de 10)'],
    ['RPE 8 a 9, sem pressa', 'Esforço 8 a 9 de 10, sem pressa'],
    ['RPE 8 para o fim da série', 'Esforço 8 de 10 para o fim da série'],
    // Known limit (RC TL-14): a spaced range and then the end or punctuation
    // is read as a range, whatever the generator meant by the second number.
    ['Treine com RPE 8 - 9.', 'Treine com esforço 8 - 9 de 10.'],
  ])('notes %j → %j (spaced range)', (written, expected) => {
    expect(read(written, 'notes')).toBe(expected)
    expect(read(expected, 'notes')).toBe(expected)
    // With the scale off the text is the same one, less the scale.
    expect(projectFlowPlainTrainingText(written, 'notes', ALL_OFF).text).toBe(expected.replaceAll(' de 10', ''))
  })

  it('the scale follows the acronym in ANY text field the net reads, not only in rpe_target and in running text', () => {
    // What the app may receive (note for the iOS lane): " de 10" in the
    // repetitions line, in the focus and in the muscle group too, when the
    // generator writes RPE / PSE and a grade there.
    for (const [written, field, expected] of [
      ['8-12 RPE 9', 'reps_range', '8-12 esforço 9 de 10'],
      ['Pernas RPE 9', 'focus', 'Pernas esforço 9 de 10'],
      ['Glúteos PSE 8', 'muscle_group', 'Glúteos esforço 8 de 10'],
      ['Agachamento (RPE 8)', 'name', 'Agachamento (esforço 8 de 10)'],
    ] as const) {
      expect(projectFlowPlainTrainingText(written, field, SCALE), written).toEqual({ text: expected, replaced: 1 })
      expect(expected.length, written).toBeLessThanOrEqual(40)
    }
  })

  it('the scale is of the effort grade only: no other number of a draft gains it', () => {
    for (const [written, field] of [
      ['8', 'reps_range'],
      ['8-12', 'reps_range'],
      ['Faça 8 repetições.', 'notes'],
      ['Esforço 8-9 nas últimas séries.', 'notes'],
      ['Dia 3', 'day'],
    ] as const) {
      expect(projectFlowPlainTrainingText(written, field, SCALE), written).toEqual({ text: written, replaced: 0 })
    }
  })
})

describe('U17 when the scale or the parenthesis does not fit, it is left out and the plain words stay (limits)', () => {
  const BOTH = { effortOutOfTen: true, renames: ['hip_thrust', 'military_press'] }

  interface Exercise {
    name: string
    rpe_target?: string
    notes?: string
    [key: string]: unknown
  }
  const draftOf = (exercise: Partial<Exercise>, notes?: string) => ({
    ...(notes === undefined ? {} : { notes }),
    weekly_schedule: [
      {
        day: 'Segunda',
        focus: 'Pernas',
        duration_min: 60,
        exercises: [{ name: 'Agachamento', muscle_group: 'pernas', sets: 4, reps_range: '8-12', rest_seconds: 90, ...exercise }],
      },
    ],
  })
  const project = (exercise: Partial<Exercise>, notes?: string) => {
    const result = projectFlowPlainTrainingDraft(draftOf(exercise, notes), BOTH)
    const payload = result.payload as { notes?: string; weekly_schedule: Array<{ exercises: Exercise[] }> }
    return { result, notes: payload.notes, exercise: payload.weekly_schedule[0]?.exercises[0] as Exercise }
  }

  it('rpe_target "RPE 9, até a falha": with the scale it would have 41 characters; it stays plain, without the scale', () => {
    expect('9 de 10, até a última repetição bem feita').toHaveLength(41)
    const { result, exercise } = project({ rpe_target: 'RPE 9, até a falha' })
    expect(exercise.rpe_target).toBe('9, até a última repetição bem feita')
    expect(exercise.rpe_target).toHaveLength(35)
    expect(result).toMatchObject({ termsReplaced: 2, sentencesKeptAsGenerated: 0, fieldsKeptAsGenerated: 0 })
  })

  it('rpe_target "RPE 9 (falha)": 42 with the scale, 36 without', () => {
    expect('9 de 10 (até a última repetição bem feita)').toHaveLength(42)
    const { result, exercise } = project({ rpe_target: 'RPE 9 (falha)' })
    expect(exercise.rpe_target).toBe('9 (até a última repetição bem feita)')
    expect(exercise.rpe_target).toHaveLength(36)
    expect(result).toMatchObject({ termsReplaced: 2, sentencesKeptAsGenerated: 0, fieldsKeptAsGenerated: 0 })
  })

  it('what fits keeps the scale', () => {
    expect(project({ rpe_target: 'RPE 9' }).exercise.rpe_target).toBe('9 de 10')
    expect(project({ rpe_target: '9' }).exercise.rpe_target).toBe('9 de 10')
  })

  it('a note of 494 characters: 498 in plain words, 504 with the scale; the plain sentences stay, without " de 10"', () => {
    const body = `${'Beba água durante o treino. '.repeat(16)}Respire bem nas séries. `
    const written = `${body}Mantenha RPE 8 no fim.`
    expect(written).toHaveLength(494)
    expect(`${body}Mantenha esforço 8 no fim.`).toHaveLength(498)
    expect(`${body}Mantenha esforço 8 de 10 no fim.`).toHaveLength(504)

    const { result, notes } = project({}, written)

    expect(notes).toBe(`${body}Mantenha esforço 8 no fim.`)
    expect(result).toMatchObject({ termsReplaced: 1, sentencesKeptAsGenerated: 0, fieldsKeptAsGenerated: 0 })
  })

  it('a name of 110 characters: only the Portuguese name (116); with the parenthesis it would have 129', () => {
    const written =
      'Hip Thrust com barra, com os ombros apoiados no banco, pausa de dois segundos no alto e descida lenta e segura'
    const portuguese =
      'Elevação pélvica com barra, com os ombros apoiados no banco, pausa de dois segundos no alto e descida lenta e segura'
    expect(written).toHaveLength(110)
    expect(portuguese).toHaveLength(116)
    expect(`${portuguese} (Hip Thrust)`).toHaveLength(129)

    const { result, exercise } = project({ name: written })

    expect(exercise.name).toBe(portuguese)
    expect(result).toMatchObject({ termsReplaced: 1, sentencesKeptAsGenerated: 0, fieldsKeptAsGenerated: 0 })
  })

  it('a name of 116 characters: not even the Portuguese name fits (122); the generated name stays, counted once', () => {
    const written =
      'Hip Thrust com barra, com os ombros apoiados no banco, pausa de dois segundos no alto e descida lenta e segura assim'
    expect(written).toHaveLength(116)
    expect(written.replace('Hip Thrust', 'Elevação pélvica')).toHaveLength(122)

    const { result, exercise } = project({ name: written })

    expect(exercise.name).toBe(written)
    expect(result).toMatchObject({ termsReplaced: 0, sentencesKeptAsGenerated: 0, fieldsKeptAsGenerated: 1 })
  })

  it("an exercise's note of 290 characters: the whole field without the parenthesis (296), no sentence given back", () => {
    const head = 'Desça devagar e suba sem pressa. '.repeat(8)
    const written = `${head}Faça o hip thrust devagar.`
    expect(written).toHaveLength(290)
    expect(`${head}Faça a elevação pélvica (hip thrust) devagar.`).toHaveLength(309)

    const { result, exercise } = project({ notes: written })

    expect(exercise.notes).toBe(`${head}Faça a elevação pélvica devagar.`)
    expect(exercise.notes).toHaveLength(296)
    expect(result).toMatchObject({ termsReplaced: 1, sentencesKeptAsGenerated: 0, fieldsKeptAsGenerated: 0 })
  })

  it('applying it again to each of these drafts changes nothing more', () => {
    for (const exercise of [
      { rpe_target: 'RPE 9, até a falha' },
      { rpe_target: 'RPE 9 (falha)' },
      { name: 'Hip Thrust com barra, com os ombros apoiados no banco, pausa de dois segundos no alto e descida lenta e segura' },
      { notes: `${'Desça devagar e suba sem pressa. '.repeat(8)}Faça o hip thrust devagar.` },
    ]) {
      const once = projectFlowPlainTrainingDraft(draftOf(exercise), BOTH)
      const twice = projectFlowPlainTrainingDraft(once.payload, BOTH)
      expect(twice.payload).toEqual(once.payload)
      expect(twice.termsReplaced).toBe(0)
    }
  })
})
