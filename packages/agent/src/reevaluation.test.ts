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

  // Audit 06-18: Q4 estendida pra cobrir BF além de peso_kg. Bug raiz era
  // que engagement-sender não passava nem peso (select sem goal_type), mas
  // o reevaluation.ts em si só cobria peso_kg. Testa ambos os ramos.
  describe('Q4 opcional — meta de peso OU BF', () => {
    it('sem meta definida → 3 perguntas (sem Q4)', () => {
      const t = reevaluationKickoff('recomposicao')
      expect(t).toMatch(/Vou coletar 3 dados/i)
      expect(t).not.toMatch(/4\)/)
      expect(t).not.toMatch(/meta de peso/i)
      expect(t).not.toMatch(/meta de gordura/i)
    })

    it('goal_type=peso_kg → 4 perguntas, Q4 cita peso atual', () => {
      const t = reevaluationKickoff('recomposicao', { currentTargetWeightKg: 70 })
      expect(t).toMatch(/Vou coletar 4 dados/i)
      expect(t).toMatch(/4\) Sua \*meta de peso\* continua sendo \*70kg\*/i)
      expect(t).not.toMatch(/gordura corporal/i)
    })

    it('goal_type=BF (caso Roberto 06-18) → 4 perguntas, Q4 cita BF%', () => {
      const t = reevaluationKickoff('recomposicao', { currentTargetBfPercent: 20 })
      expect(t).toMatch(/Vou coletar 4 dados/i)
      expect(t).toMatch(/4\) Sua \*meta de gordura corporal\* continua sendo \*20%\*/i)
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
      expect(t).not.toMatch(/4\)/)
    })
  })
})
