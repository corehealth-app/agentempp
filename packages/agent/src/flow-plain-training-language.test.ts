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
      'Treino até próximo da última repetição bem feita (esforço 8-9).',
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
    ['RPE: 8', 'Esforço 8'],
    ['RPE8', 'Esforço 8'],
    ['Mantenha RPE 7.5 nas séries.', 'Mantenha esforço 7.5 nas séries.'],
    ['Controle a PSE.', 'Controle o esforço.'],
    ['Mantenha a PSE 8 nas séries.', 'Mantenha o esforço 8 nas séries.'],
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
    // Exercise names: no row renames them while the owner has not approved (RC TL-13).
    'Hip Thrust com Barra',
    'Military press',
    'Stiff (levantamento romeno)',
    'Stiff Unilateral com Halter',
    'Leg Press 45°',
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

  it('the setup is the case: 498 characters, and the plain note would have 509', () => {
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
  // in 20 blocks of 1,000, a test each. One test read them all in 16 s beside
  // an Xcode build, three times the 5 s a test has (a synchronous test is not
  // interrupted by vitest 2.1, but a later version or a slower machine would
  // fail it); a block takes well under a second. The same 40,000 readings and
  // the same assertions on each sentence; no timeout is raised.
  const SEEDED_SENTENCES = 20_000
  const SEEDED_BLOCK = 1_000
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
    'for the 1,000 seeded random sentences from %i on; and their digits are kept',
    (from) => {
      let acted = 0
      for (const { written, field } of seeded.slice(from, from + SEEDED_BLOCK)) {
        const once = projectFlowPlainTrainingText(written, field)
        if (once.replaced > 0) acted += 1
        else expect(once.text, written).toBe(written)
        expect(digitGroups(once.text), `${field}: ${written}`).toEqual(digitGroups(written))
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
  it('every plain text of the table, and of the rows that wait for the owner', () => {
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

/** The rows that rename an exercise: written, exercised here, read by no production path. */
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
        const off = projectFlowPlainTrainingText(written, field).text
        expect(digitGroups(off), `${field}: ${written}`).toEqual(digitGroups(written))
        // With the owner's switch on, the only group added is the "10" of " de 10".
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

describe('U9 what waits for the owner is off, and is exact when on', () => {
  const on = (switches: { effortOutOfTen?: boolean; renames?: string[] }) => ({
    effortOutOfTen: switches.effortOutOfTen ?? false,
    renames: switches.renames ?? [],
  })

  it('(a) the switches are off, and frozen', () => {
    expect(FLOW_PLAIN_TRAINING_OWNER_SWITCHES).toEqual({ effortOutOfTen: false, renames: [] })
    expect(Object.isFrozen(FLOW_PLAIN_TRAINING_OWNER_SWITCHES)).toBe(true)
    expect(Object.isFrozen(FLOW_PLAIN_TRAINING_OWNER_SWITCHES.renames)).toBe(true)
  })

  it('(b) by default no exercise is renamed and the effort grade keeps its text', () => {
    for (const name of ['Hip Thrust com Barra', 'Military press', 'Leg Press 45°', 'Stiff Unilateral com Halter']) {
      expect(plain(name, 'name')).toBe(name)
      expect(plain(`Faça ${name} devagar.`)).toBe(`Faça ${name} devagar.`)
    }
    for (const grade of ['9', '8-9', '7.5', '7-8', '15', 'moderado']) {
      expect(plain(grade, 'rpe_target')).toBe(grade)
    }
  })

  it('(c) a rename the owner approves is exact', () => {
    const hip = on({ renames: ['hip_thrust'] })
    expect(projectFlowPlainTrainingText('Hip Thrust com Barra', 'name', hip).text).toBe(
      'Elevação pélvica com Barra',
    )
    expect(projectFlowPlainTrainingText('Faça o hip thrust devagar', 'notes', hip).text).toBe(
      'Faça a elevação pélvica devagar',
    )
    expect(projectFlowPlainTrainingText('Military press', 'name', hip).text).toBe('Military press')
    const military = on({ renames: ['military_press'] })
    expect(projectFlowPlainTrainingText('Military press', 'name', military).text).toBe(
      'Desenvolvimento militar',
    )
    expect(projectFlowPlainTrainingText('Hip Thrust com Barra', 'name', military).text).toBe(
      'Hip Thrust com Barra',
    )
  })

  it('(d) with the scale approved, the grade says "de 10" and nothing else is added', () => {
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

  it('(e) by default, inside rpe_target, the repeated label leaves and "/10" is written out', () => {
    expect(plain('RPE 8', 'rpe_target')).toBe('8')
    expect(plain('RPE 8-9', 'rpe_target')).toBe('8-9')
    expect(plain('8/10', 'rpe_target')).toBe('8 de 10')
    expect(plain('RPE 8/10', 'rpe_target')).toBe('8 de 10')
    expect(plain('PSE 15', 'rpe_target')).toBe('15')
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
    ['RPE 8–9', 'Esforço 8–9', 'notes'],
    ['RPE 8–9', '8–9', 'rpe_target'],
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
    ['RPE 8 RIR 2', 'Esforço 8 RIR 2'],
    ['RPE 8 - RIR 2', 'Esforço 8 - RIR 2'],
    ['RPE 8, RIR 2', 'Esforço 8, 2 repetições de sobra'],
    ['RPE 8 (RIR 2)', 'Esforço 8 (2 repetições de sobra)'],
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
