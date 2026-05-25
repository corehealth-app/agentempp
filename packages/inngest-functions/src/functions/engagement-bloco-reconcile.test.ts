import { describe, expect, it } from 'vitest'
import { reconcileBlocoMention } from '@mpp/agent'

/**
 * Bug (E) Roberto 2026-05-25: a mensagem matinal de engajamento ALUCINAVA o
 * número do bloco 7700. O LLM escreveu "saldo no bloco 7700 agora em 2.958 kcal
 * de 7.700 (38%)" enquanto o valor REAL em user_progress.deficit_block era 1.235.
 * Causa: o engagement-sender chama o LLM direto (não passa pelo card canônico),
 * então o número não era validado contra o banco.
 *
 * reconcileBlocoMention torna o número DETERMINÍSTICO: substitui qualquer menção
 * de bloco pelo valor canônico, com o % recalculado de round(deficitBlock/7700*100),
 * e usa o formato de milhar com ponto do projeto ("1.235").
 */
describe('reconcileBlocoMention (fix E — engagement bloco hallucination)', () => {
  it('(a) substitui número alucinado e recalcula o % pelo valor do banco', () => {
    const text = 'Bom dia! Seu saldo no bloco 7700 agora em 2.958 kcal de 7.700 (38%). Vamos!'
    const out = reconcileBlocoMention(text, { deficitBlock: 1235 })
    // Valor canônico no formato do projeto (milhar com ponto) + % recalculado
    expect(out).toContain('1.235')
    expect(out).toContain('(16%)') // round(1235 / 7700 * 100) = 16
    // Não pode sobrar o número alucinado nem o % errado
    expect(out).not.toContain('2.958')
    expect(out).not.toContain('38%')
  })

  it('(b) texto SEM menção de bloco fica inalterado (não força o bloco a aparecer)', () => {
    const text = 'Bom dia! Que tal um café reforçado em proteína hoje? Bora!'
    expect(reconcileBlocoMention(text, { deficitBlock: 1235 })).toBe(text)
  })

  it('(c) número já correto fica inalterado', () => {
    const text = 'Seu saldo no bloco 7700 agora em 1.235 kcal de 7.700 (16%). Segue firme!'
    expect(reconcileBlocoMention(text, { deficitBlock: 1235 })).toBe(text)
  })
})
