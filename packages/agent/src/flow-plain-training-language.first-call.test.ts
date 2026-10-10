/**
 * Flow only (app Performe AI): what the FIRST workout suggestion of a server
 * process costs in the plain-language net (flow-plain-training-language.ts).
 *
 * Audit 2026-10-10, adversarial review, round 1. Measured on the reviewed
 * code, each one in a new process:
 *  - the reported cut, whose texts are all Latin-1: 158 ms;
 *  - the same cut with the progression example the Flow's OWN prompt teaches
 *    ("… com o movimento certo → aumente o peso e volte para 6."): 4,563 ms;
 *  - an en dash in an exercise's note and in its name: 4,620 ms, and 2,739 ms
 *    more on the following call;
 *  - the default progression rule the generator uses when the model omits the
 *    field ("… com técnica → aumenta peso, volta pra 6."): 4,313 ms.
 * The net is synchronous and runs inside the turn of the suggestion: for that
 * time Node answers nobody, in every cold instance.
 *
 * The cause. The word boundaries (rule 2) were written with the Unicode
 * classes of every letter and of every number, repeated inside one very large
 * alternation. For a text with a character outside Latin-1 ("→", "–", "—",
 * "…", curly quotes, an emoji) V8 compiles a second version of the
 * expression, for two-byte strings, and that version took seconds. With the
 * boundaries written as explicit ranges it takes milliseconds.
 *
 * This file is on its own ON PURPOSE: vitest gives each test file a process
 * of its own, so the first call below is the first call of the process. The
 * tests run in the order they are written, and each one makes the net read a
 * two-byte text it had not read yet (first the texts' expression, then the
 * names' one). No timeout is raised anywhere: the budget is an assertion.
 */
import { readFileSync } from 'node:fs'
import { fileURLToPath } from 'node:url'
import { describe, expect, it } from 'vitest'
import {
  projectFlowPlainTrainingDraft,
  projectFlowPlainTrainingText,
} from './flow-plain-training-language.js'
import { trainingSystemPrompt } from './training-plan-generator.js'

interface Exercise {
  name: string
  notes?: string
  [key: string]: unknown
}
interface Day {
  exercises: Exercise[]
  [key: string]: unknown
}
interface Plan {
  weekly_schedule: Day[]
  progression_rule?: string
  notes?: string
  [key: string]: unknown
}

const REPORT = JSON.parse(
  readFileSync(
    fileURLToPath(
      new URL(
        './__golden__/fixtures/audit-10-10-flow-workout-reported-draft.json',
        import.meta.url,
      ),
    ),
    'utf8',
  ),
) as { generator_output_3_day_cut: Plan }

/** What the generator answered for the reported turn (the 3-day cut of the evidence). */
const cut = (): Plan => structuredClone(REPORT.generator_output_3_day_cut)

/** The progression example the Flow prompt teaches (training-plan-generator.ts, Flow branch). */
const PROMPT_EXAMPLE =
  'Adicione 1 repetição por treino. Chegou a 12 repetições com o movimento certo → aumente o peso e volte para 6.'
/** The rule the generator uses when the model omits the field (training-plan-generator.ts). */
const DEFAULT_RULE =
  'Adicione 1 rep por treino. Bateu 12 reps com técnica → aumenta peso, volta pra 6.'

const PLAIN_NOTES =
  'Plano empurrar/puxar/pernas modificado para 5 dias: Segunda (empurrar superior), Terça (puxar), Quarta (pernas completo), Quinta (Ombros+abdômen), Sexta (pernas posterior). Exercícios de vários músculos primeiro, exercícios de um músculo só depois. 10-20 séries/músculo/semana. Descanso 60-120s. Treino até próximo da última repetição bem feita (esforço 8-9). Aqueça sempre: 5min cardio leve + séries progressivas. Hidrate-se. Durma 7-9h. Qualquer dor articular, pare e reavalie técnica.'

/**
 * One second. On the reviewed code the calls below took 5,316 ms and 3,012 ms
 * (the same sequence, measured before the fix); with the boundaries as
 * explicit ranges, 57 ms and 18 ms, with an Xcode build running beside it.
 */
const FIRST_CALL_BUDGET_MS = 1_000

const isLatin1 = (text: string) => [...text].every((char) => (char.codePointAt(0) ?? 0) <= 0xff)

function timed<T>(run: () => T): { value: T; elapsedMs: number } {
  const started = performance.now()
  const value = run()
  return { value, elapsedMs: performance.now() - started }
}

describe('the first workout suggestion of a process does not stop Node (review of 2026-10-10)', () => {
  it('1 the reported cut with the progression example the Flow prompt teaches ("→"): the first call of the process', () => {
    // The scenario is the one measured: the cut alone is Latin-1, the example is the prompt's, and it is not.
    expect(isLatin1(JSON.stringify(REPORT.generator_output_3_day_cut))).toBe(true)
    expect(trainingSystemPrompt('flow')).toContain(`"progression_rule": "${PROMPT_EXAMPLE}"`)
    expect(isLatin1(PROMPT_EXAMPLE)).toBe(false)
    const candidate = { ...cut(), progression_rule: PROMPT_EXAMPLE }

    const { value, elapsedMs } = timed(() => projectFlowPlainTrainingDraft(candidate))

    const payload = value.payload as Plan
    // No row acts on the example: it is stored as written. The rest is the plain draft.
    expect(payload.progression_rule).toBe(PROMPT_EXAMPLE)
    expect(payload.notes).toBe(PLAIN_NOTES)
    expect(value.termsReplaced).toBe(16)
    expect(elapsedMs).toBeLessThan(FIRST_CALL_BUDGET_MS)
  })

  it("2 an en dash in an exercise's note and in its name: the first two-byte NAME of the process, and the call after it", () => {
    const withDash = (): Plan => {
      const plan = cut()
      const exercise = plan.weekly_schedule[0]?.exercises[0] as Exercise
      expect(exercise.name).toBe('Supino Reto com Barra')
      exercise.name = 'Supino Reto com Barra – pegada pronada'
      exercise.notes = 'Composto principal para peitoral – pegada na largura dos ombros.'
      return plan
    }

    const first = timed(() => projectFlowPlainTrainingDraft(withDash()))
    const following = timed(() => projectFlowPlainTrainingDraft(withDash()))

    for (const { value } of [first, following]) {
      const exercise = (value.payload as Plan).weekly_schedule[0]?.exercises[0] as Exercise
      expect(exercise.name).toBe('Supino Reto com Barra – pegada por cima')
      expect(exercise.notes).toBe(
        'Exercício de vários músculos principal para peitoral – pegada na largura dos ombros.',
      )
    }
    expect(first.elapsedMs).toBeLessThan(FIRST_CALL_BUDGET_MS)
    expect(following.elapsedMs).toBeLessThan(FIRST_CALL_BUDGET_MS)
  })

  it('3 the default progression rule of the generator ("→"), as a draft without the field receives it', () => {
    expect(isLatin1(DEFAULT_RULE)).toBe(false)

    const { value, elapsedMs } = timed(() =>
      projectFlowPlainTrainingText(DEFAULT_RULE, 'progression_rule'),
    )

    expect(value).toEqual({
      text: 'Adicione 1 repetição por treino. Bateu 12 repetições com técnica → aumenta peso, volta pra 6.',
      replaced: 2,
    })
    // A lock: after tests 1 and 2 the expressions are compiled, before and after the fix.
    expect(elapsedMs).toBeLessThan(FIRST_CALL_BUDGET_MS)
  })

  it('the cause: no boundary of the module is written with the Unicode class of every letter or of every number', () => {
    const source = readFileSync(
      fileURLToPath(new URL('./flow-plain-training-language.ts', import.meta.url)),
      'utf8',
    )
    // A backslash, "p" and the class L or N alone (a narrower class, such as
    // capitals, is another thing). What a letter and a digit ARE is pinned by
    // behaviour, character by character, in flow-plain-training-language.test.ts (U10).
    expect(source.match(/\\p\{[LN]\}/g) ?? []).toEqual([])
  })
})
