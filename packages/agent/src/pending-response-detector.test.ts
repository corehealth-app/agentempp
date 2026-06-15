import { describe, it, expect } from 'vitest'
import { detectPendingResponse } from './pending-response-detector.js'

// Roberto 2026-05-28 — DEC-3 do plano. Quando paciente DIGITA em vez de tocar
// o botão, a gente trata como tap. Conservador: só texto CURTO e padrão CLARO.

describe('detectPendingResponse — paciente digita em vez de tocar botão', () => {
  it('"sim" / "s" / "tá" / "ok" → confirm', () => {
    for (const t of ['sim', 'Sim', 'sim.', 's', 'S', 'tá', 'ta', 'ok', 'OK', 'isso', 'confirma', 'confirmo', 'pode registrar', '👍', '✅']) {
      expect(detectPendingResponse(t)).toBe('confirm')
    }
  })

  it('"não" / "editar" / "corrige" / "errado" → edit', () => {
    for (const t of ['não', 'nao', 'Não', 'Editar', 'edita', 'corrige', 'corrija', 'errado', 'errei', 'tá errado', 'não é isso']) {
      expect(detectPendingResponse(t)).toBe('edit')
    }
  })

  it('texto longo (parece nova msg de comida) → null (cai no LLM)', () => {
    expect(detectPendingResponse('sim, comi também 100g de arroz')).toBe(null)
    expect(detectPendingResponse('não esquece de adicionar o ovo cozido também')).toBe(null)
  })

  it('texto sem match (mensagem arbitrária) → null', () => {
    expect(detectPendingResponse('como tô hoje?')).toBe(null)
    expect(detectPendingResponse('comi um arroz com frango')).toBe(null)
    expect(detectPendingResponse('valeu')).toBe(null)
    expect(detectPendingResponse('obrigado')).toBe(null)
  })

  it('vazio/null → null', () => {
    expect(detectPendingResponse('')).toBe(null)
    expect(detectPendingResponse(null)).toBe(null)
    expect(detectPendingResponse(undefined)).toBe(null)
  })

  // Bug T3 (2026-06-15): bare "pode" considerado mas REJEITADO no review
  // adversarial — em PT-BR "pode" é polissêmico (go-ahead genérico,
  // "é possível", concordância vaga). Falso-positivo de gravar refeição
  // sem confirmação real era risco maior que cobrir T3.
  it('bare "pode" → null (polissêmico em PT-BR, risco de falso positivo)', () => {
    expect(detectPendingResponse('pode')).toBe(null)
    expect(detectPendingResponse('Pode')).toBe(null)
    expect(detectPendingResponse('pode.')).toBe(null)
  })

  it('"pode registrar" continua casando (intenção explícita)', () => {
    expect(detectPendingResponse('pode registrar')).toBe('confirm')
    expect(detectPendingResponse('Pode registrar.')).toBe('confirm')
  })

  it('"registra mesmo assim" / "manda ver" → confirm (resposta ao block I4)', () => {
    expect(detectPendingResponse('registra mesmo assim')).toBe('confirm')
    expect(detectPendingResponse('pode mesmo assim')).toBe('confirm')
    expect(detectPendingResponse('manda ver')).toBe('confirm')
    expect(detectPendingResponse('manda registrar')).toBe('confirm')
  })

  it('"pode passar..." ou "pode trocar X" → null (não é confirmação)', () => {
    expect(detectPendingResponse('pode trocar o arroz por feijão?')).toBe(null)
    expect(detectPendingResponse('pode passar a receita?')).toBe(null)
  })
})
