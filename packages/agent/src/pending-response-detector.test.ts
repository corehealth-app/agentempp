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
})
