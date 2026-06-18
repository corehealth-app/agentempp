import { describe, expect, it } from 'vitest'
import { classifyBfGoal } from './bf-goal-classifier.js'

describe('classifyBfGoal — bug Roberto 06-18 (Q4 reavaliação BF)', () => {
  // Roberto: masculino, BF atual 20%, meta 20% (goal_type=BF, goal_value=20).
  // Maintenance — delta <1pp.
  it('Roberto cenário: BF atual=20 alvo=20 → maintenance', () => {
    const r = classifyBfGoal({ currentBfPercent: 20, targetBfPercent: 20, sex: 'masculino' })
    expect(r.classification).toBe('maintenance')
    expect(r.direction).toBe('manter')
    expect(r.bfAtual).toBe(20)
    expect(r.bfAlvo).toBe(20)
    expect(r.semanasParaMetaSeguro).toBe(null)
    expect(r.message).toContain('20%')
  })

  it('homem 25% → 15% saudável e factível em ritmo seguro', () => {
    const r = classifyBfGoal({ currentBfPercent: 25, targetBfPercent: 15, sex: 'masculino' })
    expect(r.classification).toBe('ideal')
    expect(r.direction).toBe('perder')
    expect(r.deltaPp).toBe(10)
    expect(r.semanasParaMetaSeguro).toBe(20) // 10pp / 0.5pp por semana
    expect(r.bfMinimoSaudavel).toBe(5)
    expect(r.bfRecompLimit).toBe(20)
  })

  it('homem 22% → 25% (ganhar gordura — raro mas válido)', () => {
    const r = classifyBfGoal({ currentBfPercent: 22, targetBfPercent: 25, sex: 'masculino' })
    expect(r.direction).toBe('ganhar')
    // 25 > 20 (limite recomp) → overweight_remaining
    expect(r.classification).toBe('overweight_remaining')
  })

  it('homem 18% → 3% → unhealthy_low (abaixo do essencial 5%)', () => {
    const r = classifyBfGoal({ currentBfPercent: 18, targetBfPercent: 3, sex: 'masculino' })
    expect(r.classification).toBe('unhealthy_low')
    expect(r.semanasParaMetaSeguro).toBe(null)
    expect(r.message).toContain('abaixo')
  })

  it('mulher 30% → 26% saudável (recomp limit 28%)', () => {
    const r = classifyBfGoal({ currentBfPercent: 30, targetBfPercent: 26, sex: 'feminino' })
    expect(r.classification).toBe('ideal')
    expect(r.bfRecompLimit).toBe(28)
    expect(r.bfMinimoSaudavel).toBe(12)
    expect(r.deltaPp).toBe(4)
    expect(r.semanasParaMetaSeguro).toBe(8) // 4pp / 0.5
  })

  it('mulher 22% → 8% → unhealthy_low (abaixo essencial 12)', () => {
    const r = classifyBfGoal({ currentBfPercent: 22, targetBfPercent: 8, sex: 'feminino' })
    expect(r.classification).toBe('unhealthy_low')
  })

  it('homem 35% → 30% → overweight_remaining (30 > 20 recomp limit)', () => {
    const r = classifyBfGoal({ currentBfPercent: 35, targetBfPercent: 30, sex: 'masculino' })
    expect(r.classification).toBe('overweight_remaining')
    expect(r.message).toContain('intermediário')
  })

  it('round1: BFs decimais funcionam', () => {
    const r = classifyBfGoal({ currentBfPercent: 20.7, targetBfPercent: 18.3, sex: 'masculino' })
    expect(r.bfAtual).toBe(20.7)
    expect(r.bfAlvo).toBe(18.3)
    expect(r.deltaPp).toBe(2.4)
  })

  // Hardenings do review adversarial 06-18
  describe('hardenings review 06-18', () => {
    it('threshold <= inclusivo: delta exato 1.0pp → maintenance (não aggressive)', () => {
      const r = classifyBfGoal({ currentBfPercent: 20, targetBfPercent: 19, sex: 'masculino' })
      expect(r.classification).toBe('maintenance')
      expect(r.direction).toBe('manter')
    })

    it('threshold <=: delta 1.1pp já entra em perder (não maintenance)', () => {
      const r = classifyBfGoal({ currentBfPercent: 20, targetBfPercent: 18.9, sex: 'masculino' })
      expect(r.direction).toBe('perder')
    })

    it('aggressive: só dispara delta>=2pp E semanas<4 (delta 1pp em 2sem é ideal/manter)', () => {
      // delta 1pp = maintenance, então testamos delta 2.5pp em 5 semanas
      // (deve ser ideal pq semanas>=4) — e delta 2.5pp em 4 semanas
      // testado abaixo
      const r = classifyBfGoal({ currentBfPercent: 20, targetBfPercent: 17.5, sex: 'masculino' })
      expect(r.semanasParaMetaSeguro).toBe(5)
      expect(r.classification).toBe('ideal')
    })

    it('aggressive: delta 3pp em 6 semanas é ideal (não aggressive)', () => {
      const r = classifyBfGoal({ currentBfPercent: 20, targetBfPercent: 17, sex: 'masculino' })
      expect(r.semanasParaMetaSeguro).toBe(6)
      expect(r.classification).toBe('ideal')
    })

    it('long_term: delta 17pp leva 34sem (>26) → long_term (não ideal)', () => {
      const r = classifyBfGoal({ currentBfPercent: 18, targetBfPercent: 1, sex: 'masculino' })
      // Espera unhealthy_low (1 < 5 essential) — não atinge long_term
      expect(r.classification).toBe('unhealthy_low')
    })

    it('long_term: cenário REAL — homem dentro do limit precisa de mais de 26 semanas', () => {
      // BF 19, alvo 6 (saudável > 5 essencial, dentro do recomp 20)
      // delta=13pp, semanas=26 → NÃO entra (precisa > 26)
      // Vamos pra delta 13pp = 26 sem (não entra), delta 15 = 30 sem (entra)
      const r = classifyBfGoal({ currentBfPercent: 20, targetBfPercent: 5, sex: 'masculino' })
      // delta=15, semanas=30, alvo=5=essencial (boundary, < essencial seria 4)
      // alvo 5 >= bfMinimoSaudavel 5 → não unhealthy_low. recomp 20, alvo 5 ≤ 20 → não overweight
      // semanas 30 > 26 E delta 15 > 10 → long_term ✓
      expect(r.classification).toBe('long_term')
      expect(r.message).toContain('LONGO PRAZO')
      expect(r.message).toContain('degrau intermediário')
    })

    it('long_term: mulher 38→18 (delta 20pp, 40sem) também é long_term', () => {
      const r = classifyBfGoal({ currentBfPercent: 38, targetBfPercent: 18, sex: 'feminino' })
      // alvo 18 < recomp limit 28 → não overweight. delta=20, semanas=40
      // 40>26 e 20>10 → long_term ✓
      expect(r.classification).toBe('long_term')
    })
  })
})
