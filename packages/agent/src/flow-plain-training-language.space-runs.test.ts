/**
 * Flow only (app Performe AI): what a long run of spaces inside a field costs
 * in the plain-language net (flow-plain-training-language.ts).
 *
 * Audit 2026-10-10, adversarial review of 3b65bee, round 2 (LOW, left open
 * then): "the time of the net grows with the square of a long run of spaces
 * inside a field". Every interval of the vocabulary's expression is "one or
 * more spaces" or "zero or more spaces", also inside look-behinds that are
 * tried at every position, and the expression was run over the sentence as
 * written. Measured on 8d5729b, in a new process, with the text below (three
 * runs of N spaces): N = 100, 19 ms; 200, 71 ms; 400, 293 ms; 800, 1,777 ms;
 * 1,000, 2,625 ms; 1,200, 2,944 ms; 1,400, 4,051 ms. Four times the time for
 * twice the spaces. The net is synchronous and runs inside the turn of the
 * suggestion: for that time Node answers nobody.
 *
 * The fix: the expression is matched over a copy of the sentence in which
 * every run of spaces is ONE space, and what it finds is written back at the
 * positions of the sentence as written. No expression changed and no output
 * changed: a run of spaces outside a replaced spelling is kept as it is.
 *
 * The size of the run. A field of a stored draft has at most 500 characters,
 * and there a run of spaces costs tens of milliseconds, before and after. The
 * text of these tests has three runs of 1,200 spaces (3,616 characters): the
 * size at which the code of 8d5729b took about 3 seconds, enough to see the
 * budget fail by its assertion and little enough to end inside the 5 seconds
 * a test has. No timeout is raised anywhere.
 *
 * Tests 1 and 2 do not depend on time. Test 3 does, and says so.
 *
 * This file is on its own, like flow-plain-training-language.first-call.test.ts:
 * test 1 wraps String.prototype.matchAll for the length of one test.
 */
import { afterEach, describe, expect, it } from 'vitest'
import {
  type FlowPlainTrainingField,
  projectFlowPlainTrainingText,
} from './flow-plain-training-language.js'

/** Both switches written off: the rows and the rules, nothing of the two decisions. */
const ALL_OFF = { effortOutOfTen: false, renames: [] as string[] }

const RUN = 1_200
const SPACES = ' '.repeat(RUN)
/** One sentence: "Faça", "12 reps", "RPE" and "8." with a long run of spaces between them. */
const LONG_RUNS = `Faça${SPACES}12 reps${SPACES}RPE${SPACES}8.`
/** The same sentence with one space in each place. */
const ONE_SPACE = 'Faça 12 reps RPE 8.'
/**
 * What the net has always answered for it: the two runs outside a replaced
 * spelling stay; the one between the acronym and its grade is part of the
 * spelling ("RPE   8" is "RPE 8") and leaves with it.
 */
const LONG_RUNS_PLAIN = `Faça${SPACES}12 repetições${SPACES}esforço 8.`

const SPACE_RUN = /[ \t\u00A0]{2}/

const originalMatchAll = String.prototype.matchAll

afterEach(() => {
  String.prototype.matchAll = originalMatchAll
})

/** Every text handed to an expression whose source has more than 2,000 characters (the vocabulary's). */
function recordingVocabularyReadings(): string[] {
  const seen: string[] = []
  String.prototype.matchAll = function (this: string, pattern: RegExp) {
    if (pattern instanceof RegExp && pattern.source.length > 2_000) seen.push(String(this))
    return originalMatchAll.call(this, pattern)
  } as typeof String.prototype.matchAll
  return seen
}

describe('a long run of spaces inside a field (review of 2026-10-10)', () => {
  it('the text of these tests is the case: one sentence, three runs of 1,200 spaces', () => {
    expect(LONG_RUNS).toHaveLength(3 * RUN + 'Faça12 repsRPE8.'.length)
    expect(LONG_RUNS.replace(/ +/g, ' ')).toBe(ONE_SPACE)
    expect(SPACE_RUN.test(LONG_RUNS)).toBe(true)
    expect(SPACE_RUN.test(ONE_SPACE)).toBe(false)
  })

  it("1 the vocabulary's expression is never handed two spaces in a row (does not depend on time)", () => {
    const seen = recordingVocabularyReadings()

    const result = projectFlowPlainTrainingText(LONG_RUNS, 'notes', ALL_OFF)

    String.prototype.matchAll = originalMatchAll
    // Not vacuous: the expression was run, and on this very sentence with one space in each place.
    expect(seen.length).toBeGreaterThan(0)
    expect(seen).toContain(ONE_SPACE)
    expect(seen.filter((text) => SPACE_RUN.test(text)).map((text) => text.length)).toEqual([])
    // And the answer is the one of always, byte for byte.
    expect(result).toEqual({ text: LONG_RUNS_PLAIN, replaced: 2 })
  })

  it('the recorder of test 1 does record: a text of the vocabulary, read once, is seen', () => {
    const seen = recordingVocabularyReadings()

    projectFlowPlainTrainingText('Faça 12 reps.', 'notes', ALL_OFF)

    String.prototype.matchAll = originalMatchAll
    expect(seen).toContain('Faça 12 reps.')
    expect(String.prototype.matchAll).toBe(originalMatchAll)
  })

  // Lines of flow-plain-training-language.test.ts (U1, U3, U10, U11), written
  // again HERE by hand with a run of THREE spaces in every place, and what
  // each one gives: a run outside a replaced spelling stays as written; a
  // space inside a replaced spelling ("RPE   8", "2   RIR", "a   PSE") or one
  // the plain text brings ("repetições de sobra") is a single space, as it
  // always was. The grade and the count are written back as the generator
  // wrote them, runs included ("8   -   9").
  const THREE = '   '
  const LINES: ReadonlyArray<readonly [string, string, FlowPlainTrainingField]> = [
    ['Faça   12   reps   por   série.', 'Faça   12   repetições   por   série.', 'notes'],
    ['Plano   Push/Pull/Legs   modificado', 'Plano   empurrar/puxar/pernas   modificado', 'notes'],
    ['Plano   Push   /   Pull   /   Legs   modificado', 'Plano   empurrar/puxar/pernas   modificado', 'notes'],
    ['Push   Pull   Legs', 'Empurrar/puxar/pernas', 'focus'],
    [
      'Treino   até   próximo   da   falha   técnica   (RPE   8-9).',
      'Treino   até   próximo   da   última repetição bem feita   (esforço 8-9).',
      'notes',
    ],
    [
      'Compostos   primeiro,   isoladores   depois.',
      'Exercícios de vários músculos   primeiro,   exercícios de um músculo só   depois.',
      'notes',
    ],
    [
      'Comece   com   compostos   e   termine   com   isoladores.',
      'Comece   com   exercícios de vários músculos   e   termine   com   exercícios de um músculo só.',
      'notes',
    ],
    ['mantendo   as   escápulas   retraídas', 'mantendo   os ombros para trás', 'execution_steps'],
    [
      'Como   intermediário,   use   progressão   linear:',
      'Como   intermediário,   use   evolução passo a passo:',
      'progression_rule',
    ],
    ['Leg   day   -   Core   e   panturrilha', 'Dia de pernas   -   abdômen   e   panturrilha', 'notes'],
    ['Treine   até   a   falha   muscular   técnica.', 'Treine   até   a   última repetição bem feita.', 'notes'],
    [
      'Vá   até   a   falha   na   última   série.',
      'Vá   até   a   última repetição bem feita   na   última   série.',
      'exercise_notes',
    ],
    ['até   falha', 'até   a última repetição bem feita', 'reps_range'],
    ['Mantenha   a   PSE   8   nas   séries.', 'Mantenha   o esforço 8   nas   séries.', 'notes'],
    ['RPE   8   -   9   no   fim', 'Esforço 8   -   9   no   fim', 'notes'],
    ['RPE:   8', '8', 'rpe_target'],
    ['Deixe   2   RIR   em   cada   série.', 'Deixe   2 repetições de sobra   em   cada   série.', 'notes'],
    [
      'Termine   com   RIR   2   em   cada   série.',
      'Termine   com   2 repetições de sobra   em   cada   série.',
      'notes',
    ],
    ['Deixe   1   -   2   RIR.', 'Deixe   1   -   2 repetições de sobra.', 'notes'],
    ['Trabalha   o   gastrocnêmio   e   o   sóleo.', 'Trabalha   os músculos da panturrilha.', 'notes'],
    ['Foco   na   cabeça   longa   do   tríceps   braquial.', 'Foco   na   parte de trás do braço.', 'notes'],
    [
      'O   Upper   vem   antes   do   Lower.',
      'A parte de cima do corpo   vem   antes   da parte de baixo do corpo.',
      'notes',
    ],
    ['Aqueça.   Core   no   fim.', 'Aqueça.   Abdômen   no   fim.', 'notes'],
    ['Rosca   direta   (pegada   supinada)', 'Rosca   direta   (pegada por baixo)', 'name'],
    ['Bateu   12   reps   →   aumenta   peso', 'Bateu   12   repetições   →   aumenta   peso', 'progression_rule'],
    // Lines in which nothing acts, or the rule keeps the word.
    ['Séries   de   12   RIR   2.', 'Séries   de   12   RIR   2.', 'notes'],
    [
      'Semana   1   -   RIR   3,   semana   2   -   RIR   2.',
      'Semana   1   -   RIR   3,   semana   2   -   RIR   2.',
      'notes',
    ],
    ['treino   composto   por   5   dias', 'treino   composto   por   5   dias', 'notes'],
    ['Face   Pull   e   Pull   Up', 'Face   Pull   e   Pull   Up', 'notes'],
    ['Corrija   qualquer   falha   técnica', 'Corrija   qualquer   falha   técnica', 'notes'],
    ['Agachamento   livre   com   barra', 'Agachamento   livre   com   barra', 'name'],
    [
      'Veja   [o   guia](https://example.com/push/pull/legs)   antes',
      'Veja   [o   guia](https://example.com/push/pull/legs)   antes',
      'notes',
    ],
  ]

  it('2 a run of spaces changes nothing but the time: each line with 1, 2, 3, 7 and 40 spaces in every place (lock)', () => {
    let compared = 0
    for (const [written, expected, field] of LINES) {
      // No line was written with a run of another size: the widening below is exact.
      expect(written.replaceAll(THREE, '')).not.toMatch(/ /)
      expect(expected.replaceAll(THREE, '').replaceAll(' ', '')).not.toMatch(/\s/)
      for (const width of [1, 2, 3, 7, 40]) {
        const run = ' '.repeat(width)
        const wide = written.replaceAll(THREE, run)
        const result = projectFlowPlainTrainingText(wide, field, ALL_OFF)
        expect(result.text, `${width}: ${written}`).toBe(expected.replaceAll(THREE, run))
        // A line in which nothing acts comes back as the very same string.
        if (written === expected) expect(result, `${width}: ${written}`).toEqual({ text: wide, replaced: 0 })
        compared += 1
      }
    }
    expect(compared).toBe(LINES.length * 5)
    expect(LINES).toHaveLength(32)
  })

  it('rule 11 keeps its reach across a run: a number on both sides of the acronym, however far, keeps the acronym', () => {
    const far = `Séries de 12${' '.repeat(300)}RIR 2.`
    expect(projectFlowPlainTrainingText(far, 'notes', ALL_OFF)).toEqual({ text: far, replaced: 0 })
    const farAfter = `Séries de 12 RIR${' '.repeat(300)}2.`
    expect(projectFlowPlainTrainingText(farAfter, 'notes', ALL_OFF)).toEqual({ text: farAfter, replaced: 0 })
  })

  it('tabs and no-break spaces are spaces of a run too, and each one that stays is the one written', () => {
    const written = `Faça \t\u00A0 12 \t reps \u00A0\u00A0 por série.`
    expect(projectFlowPlainTrainingText(written, 'notes', ALL_OFF)).toEqual({
      text: `Faça \t\u00A0 12 \t repetições \u00A0\u00A0 por série.`,
      replaced: 1,
    })
  })

  it('3 budget: the text with three runs of 1,200 spaces is read within 1 second (DEPENDS ON TIME; no timeout raised)', () => {
    // Read once before, with one space: the expression is compiled outside the measure.
    expect(projectFlowPlainTrainingText(ONE_SPACE, 'notes', ALL_OFF).replaced).toBe(2)

    const started = performance.now()
    const result = projectFlowPlainTrainingText(LONG_RUNS, 'notes', ALL_OFF)
    const elapsedMs = performance.now() - started

    expect(result).toEqual({ text: LONG_RUNS_PLAIN, replaced: 2 })
    expect(elapsedMs).toBeLessThan(1_000)
  })
})
