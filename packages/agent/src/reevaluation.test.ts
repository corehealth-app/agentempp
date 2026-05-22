import { describe, it, expect } from 'vitest'
import { reevaluationKickoff } from './reevaluation.js'

describe('reevaluationKickoff — script oficial do manual MPP (14 dias)', () => {
  it('recomposição: peso + 3 fotos (frente/lado/costas) + FOME (muita/moderada/baixa)', () => {
    const t = reevaluationKickoff('recomposicao')
    expect(t).toMatch(/14 dias/i)
    expect(t).toMatch(/peso/i)
    expect(t).toMatch(/frente.*lado.*costas/i)
    expect(t).toMatch(/fome/i)
    expect(t).toMatch(/muita/i)
    // NÃO pede medidas/BF% nem contagem de calorias ("o que não pedir")
    expect(t).not.toMatch(/medidas|BF%|cont(e|a)\w* de calorias/i)
  })

  it('ganho de massa: Q3 = treinos de musculação por semana', () => {
    const t = reevaluationKickoff('ganho_massa')
    expect(t).toMatch(/peso/i)
    expect(t).toMatch(/frente.*lado.*costas/i)
    expect(t).toMatch(/treinos? de muscula/i)
  })

  it('manutenção: Q3 = dias de atividade física por semana', () => {
    const t = reevaluationKickoff('manutencao')
    expect(t).toMatch(/peso/i)
    expect(t).toMatch(/dias de atividade/i)
  })

  it('protocolo nulo/desconhecido → fallback genérico (peso + fotos)', () => {
    const t = reevaluationKickoff(null)
    expect(t).toMatch(/peso/i)
    expect(t).toMatch(/14 dias/i)
  })
})
