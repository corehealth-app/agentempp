import { describe, it, expect } from 'vitest'
import { buildJudgePrompt, parseJudgeResult } from './llm-judge.js'

describe('parseJudgeResult', () => {
  it('parseia JSON limpo', () => {
    expect(parseJudgeResult('{"score": 8, "reasoning": "resposta sólida"}')).toEqual({
      score: 8,
      reasoning: 'resposta sólida',
    })
  })
  it('parseia JSON dentro de code fence ```json', () => {
    const r = parseJudgeResult('```json\n{"score": 6, "reasoning": "ok"}\n```')
    expect(r).toEqual({ score: 6, reasoning: 'ok' })
  })
  it('clampa score > 10 e < 0', () => {
    expect(parseJudgeResult('{"score": 12, "reasoning": "x"}')?.score).toBe(10)
    expect(parseJudgeResult('{"score": -3, "reasoning": "x"}')?.score).toBe(0)
  })
  it('texto sem JSON → null', () => {
    expect(parseJudgeResult('não consegui avaliar')).toBeNull()
  })
  it('score não-numérico → null', () => {
    expect(parseJudgeResult('{"score": "oito", "reasoning": "x"}')).toBeNull()
  })
})

describe('buildJudgePrompt', () => {
  it('inclui a msg do paciente, a resposta do agente e pede JSON com score', () => {
    const p = buildJudgePrompt({
      userInput: 'comi 2 ovos',
      agentResponse: 'Café registrado, 146 kcal.',
      stage: 'recomposicao',
    })
    expect(p.system).toMatch(/0 a 10|0-10/i)
    expect(p.system).toMatch(/json/i)
    expect(p.user).toContain('comi 2 ovos')
    expect(p.user).toContain('Café registrado')
  })
})
