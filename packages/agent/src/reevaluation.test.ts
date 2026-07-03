import { describe, expect, it } from 'vitest'
import { reevaluationKickoff } from './reevaluation.js'

describe('reevaluationKickoff — script oficial do manual MPP (14 dias)', () => {
  it('recomposição: peso + fotos + fome + frequência de treino/atividade', () => {
    const t = reevaluationKickoff('recomposicao')
    expect(t).toMatch(/14 dias/i)
    expect(t).toMatch(/Vou coletar 4 dados/i)
    expect(t).toMatch(/peso/i)
    expect(t).toMatch(/frente.*lado.*costas/i)
    expect(t).toMatch(/fome/i)
    expect(t).toMatch(/muita/i)
    expect(t).toMatch(/atividade física\/treino/i)
    expect(t).toMatch(/continua igual/i)
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

  // Audit 06-18: pergunta de meta estendida pra cobrir BF além de peso_kg. Bug raiz era
  // que engagement-sender não passava nem peso (select sem goal_type), mas
  // o reevaluation.ts em si só cobria peso_kg. Testa ambos os ramos.
  describe('pergunta opcional — meta de peso, BF ou IMC', () => {
    it('sem meta definida em recomposição → 4 perguntas, sem meta extra', () => {
      const t = reevaluationKickoff('recomposicao')
      expect(t).toMatch(/Vou coletar 4 dados/i)
      expect(t).toMatch(/4\) Quantas vezes por semana/i)
      expect(t).not.toMatch(/5\)/)
      expect(t).not.toMatch(/meta de peso/i)
      expect(t).not.toMatch(/meta de gordura/i)
    })

    it('goal_type=peso_kg em recomposição → 5 perguntas, Q5 cita peso atual', () => {
      const t = reevaluationKickoff('recomposicao', { currentTargetWeightKg: 70 })
      expect(t).toMatch(/Vou coletar 5 dados/i)
      expect(t).toMatch(/4\) Quantas vezes por semana/i)
      expect(t).toMatch(/5\) Sua \*meta de peso\* continua sendo \*70kg\*/i)
      expect(t).not.toMatch(/gordura corporal/i)
    })

    it('goal_type=BF (caso Roberto 06-18) em recomposição → 5 perguntas, Q5 cita BF%', () => {
      const t = reevaluationKickoff('recomposicao', { currentTargetBfPercent: 20 })
      expect(t).toMatch(/Vou coletar 5 dados/i)
      expect(t).toMatch(/5\) Sua \*meta de gordura corporal\* continua sendo \*20%\*/i)
      expect(t).not.toMatch(/meta de peso continua/i)
    })

    it('ambos definidos (raro) → prioriza peso (1 goal_type por paciente)', () => {
      const t = reevaluationKickoff('recomposicao', {
        currentTargetWeightKg: 70,
        currentTargetBfPercent: 18,
      })
      expect(t).toMatch(/meta de peso/i)
      expect(t).not.toMatch(/meta de gordura/i)
    })

    it('valores zero/negativos contam como ausente (defesa contra dado ruim)', () => {
      const t = reevaluationKickoff('recomposicao', {
        currentTargetWeightKg: 0,
        currentTargetBfPercent: -5,
      })
      expect(t).toMatch(/4\) Quantas vezes por semana/i)
      expect(t).not.toMatch(/5\)/)
    })

    // Audit 06-18 extensão IMC: cobre os 5 pacientes em prod
    it('goal_type=IMC (5 pacientes em prod) → 5 perguntas, Q5 cita IMC + sugere migração', () => {
      const t = reevaluationKickoff('recomposicao', { currentTargetImc: 23 })
      expect(t).toMatch(/Vou coletar 5 dados/i)
      expect(t).toMatch(/5\) Sua \*meta de IMC\* continua sendo \*23\*/i)
      // Sugere migração pra peso ou BF (não força)
      expect(t).toMatch(/peso \(kg\)/i)
      expect(t).toMatch(/% de gordura/i)
    })

    it('IMC + peso (raro — 2 goal_types) → prioriza peso', () => {
      const t = reevaluationKickoff('recomposicao', {
        currentTargetWeightKg: 70,
        currentTargetImc: 23,
      })
      expect(t).toMatch(/meta de peso/i)
      expect(t).not.toMatch(/meta de IMC/i)
    })

    it('IMC + BF (raro) → prioriza BF sobre IMC', () => {
      const t = reevaluationKickoff('recomposicao', {
        currentTargetBfPercent: 18,
        currentTargetImc: 23,
      })
      expect(t).toMatch(/meta de gordura/i)
      expect(t).not.toMatch(/meta de IMC/i)
    })

    it('IMC zero/negativo → fallback pra 4 perguntas de recomposição', () => {
      const t = reevaluationKickoff('recomposicao', { currentTargetImc: 0 })
      expect(t).toMatch(/4\) Quantas vezes por semana/i)
      expect(t).not.toMatch(/5\)/)
      expect(t).not.toMatch(/meta de IMC/i)
    })
  })
})
