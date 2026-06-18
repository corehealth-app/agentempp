/**
 * Testes de integridade das tool descriptions (audit 06-18).
 *
 * Bug descoberto no review adversarial: `' + +` no fim de uma linha
 * (tools.ts:477) era operador `+` unário sobre a próxima string, gerando
 * 'NaN' literal e TRUNCANDO o restante da description do `registra_refeicao`.
 * Resultado: o LLM em prod NÃO recebia as instruções de UNIDADES, DIA DA
 * REFEIÇÃO e APRENDIZADO DE CORREÇÕES (3 seções inteiras). Plausivelmente
 * explica vários bugs históricos (corrections não usado, refeição no dia
 * errado, unidade errada).
 *
 * Esse teste trava o invariante: cada tool description tem cobertura
 * mínima esperada (palavras-chave que NÃO podem desaparecer).
 */
import { describe, expect, it } from 'vitest'
import { registraRefeicao, defineMetaPeso } from './tools.js'

describe('registraRefeicao.description — integridade', () => {
  const d = registraRefeicao.description

  it('NÃO contém NaN literal (regressão do bug `+ +`)', () => {
    expect(d).not.toMatch(/\bNaN\b/)
  })

  it('contém todas as seções críticas (cada uma é instrução load-bearing)', () => {
    expect(d).toContain('UNIDADES')
    expect(d).toContain('DIA DA REFEIÇÃO')
    expect(d).toContain('APRENDIZADO DE CORREÇÕES')
    expect(d).toContain('CORREÇÃO IMPLÍCITA')
    expect(d).toContain('TABELA DE DECISÃO')
  })

  it('cobre os principais cenários de uso', () => {
    expect(d).toContain('display_qty')
    expect(d).toContain('display_unit')
    expect(d).toContain('consumed_date')
    expect(d).toContain('corrections')
    expect(d).toContain('replace=true')
  })

  it('tem comprimento esperado (>3000 chars; bug truncava em ~2000)', () => {
    expect(d.length).toBeGreaterThan(3000)
  })
})

describe('defineMetaPeso.description — integridade (XOR weight|bf)', () => {
  const d = defineMetaPeso.description

  it('NÃO contém NaN literal', () => {
    expect(d).not.toMatch(/\bNaN\b/)
  })

  it('explica os 2 parâmetros XOR', () => {
    expect(d).toContain('target_weight_kg')
    expect(d).toContain('target_bf_percent')
    expect(d.toUpperCase()).toContain('XOR')
  })

  it('cita os 2 caminhos (PESO + BF)', () => {
    expect(d.toUpperCase()).toContain('PESO')
    expect(d.toUpperCase()).toContain('BF')
  })

  it('orienta quando usar cada um', () => {
    // Indicadores de uso: paciente que fala em peso/kg vs % gordura/BF
    expect(d).toMatch(/peso/i)
    expect(d).toMatch(/gordura corporal/i)
    expect(d).toMatch(/kg|quilos?/i)
  })
})
