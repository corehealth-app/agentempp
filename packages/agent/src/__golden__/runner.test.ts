import { describe, expect, it } from 'vitest'
import { buildScriptedLLM, normalizeForGolden, diffGolden } from './runner.js'

describe('golden runner — primitives', () => {
  it('buildScriptedLLM retorna turnos em sequência', async () => {
    const llm = buildScriptedLLM([
      { llm_response: 'oi' },
      { llm_response: 'tudo bem' },
    ])
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
// biome-ignore lint/suspicious/noExplicitAny: legacy — see ACT-1 prevention plan 2026-06-16
    const r1 = await (llm as any).complete({})
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
// biome-ignore lint/suspicious/noExplicitAny: legacy — see ACT-1 prevention plan 2026-06-16
    const r2 = await (llm as any).complete({})
    expect(r1.content).toBe('oi')
    expect(r2.content).toBe('tudo bem')
  })

  it('buildScriptedLLM repete último turno se exceder roteiro', async () => {
    const llm = buildScriptedLLM([{ llm_response: 'unica' }])
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
// biome-ignore lint/suspicious/noExplicitAny: legacy — see ACT-1 prevention plan 2026-06-16
    const r1 = await (llm as any).complete({})
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
// biome-ignore lint/suspicious/noExplicitAny: legacy — see ACT-1 prevention plan 2026-06-16
    const r2 = await (llm as any).complete({})
    expect(r1.content).toBe('unica')
    expect(r2.content).toBe('unica')
  })

  it('normalizeForGolden substitui números por N e remove emojis', () => {
    const out = normalizeForGolden(
      'Consumido 1.433 kcal de 1843 🔥 Restam 410 kcal ✅',
    )
    expect(out).toBe('Consumido N kcal de N Restam N kcal')
  })

  it('normalizeForGolden mantém estrutura semântica', () => {
    const out = normalizeForGolden('Almoço registrado. 521 kcal hoje.')
    expect(out).toBe('Almoço registrado. N kcal hoje.')
  })

  it('diffGolden retorna [] quando tools e tokens batem', () => {
    const diffs = diffGolden(
      {
        name: 'baseline',
        description: 'happy path',
        user_message: 'oi',
        llm_turns: [],
        expected_tools_called: ['registra_refeicao'],
        expected_text_contains: ['almoço registrado'],
      },
      {
        tools_called: ['registra_refeicao'],
        final_text: 'Almoço registrado. 500 kcal.',
      },
    )
    expect(diffs).toEqual([])
  })

  it('diffGolden reporta tools faltando + tokens ausentes', () => {
    const diffs = diffGolden(
      {
        name: 'baseline',
        description: 'expected refeicao',
        user_message: 'oi',
        llm_turns: [],
        expected_tools_called: ['registra_refeicao'],
        expected_text_contains: ['bloco 7700'],
      },
      {
        tools_called: ['consulta_progresso'],
        final_text: 'olá tudo bem',
      },
    )
    expect(diffs).toContain('missing tool: registra_refeicao')
    expect(diffs).toContain('unexpected tool: consulta_progresso')
    expect(diffs.some((d) => d.includes('text missing pattern'))).toBe(true)
  })

  it('diffGolden ignora variação numérica via normalize', () => {
    const diffs = diffGolden(
      {
        name: 'baseline',
        description: 'numero não importa',
        user_message: 'oi',
        llm_turns: [],
        expected_tools_called: [],
        expected_text_contains: ['restam N kcal'],
      },
      {
        tools_called: [],
        // 1843 vira N — pattern match
        final_text: 'Restam 1843 kcal hoje',
      },
    )
    expect(diffs).toEqual([])
  })
})
