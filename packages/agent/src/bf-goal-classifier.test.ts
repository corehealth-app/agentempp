import { describe, expect, it } from 'vitest'
import { BF_METHOD_FLOOR, classifyBfGoal } from './bf-goal-classifier.js'

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
    // Piso do método (R4, 2026-10-04); antes era o "essencial" 5.
    expect(r.bfMinimoSaudavel).toBe(10)
    expect(r.refused).toBe(false)
    expect(r.bfRecompLimit).toBe(20)
  })

  it('homem 22% → 25% (ganhar gordura — raro mas válido)', () => {
    const r = classifyBfGoal({ currentBfPercent: 22, targetBfPercent: 25, sex: 'masculino' })
    expect(r.direction).toBe('ganhar')
    // 25 > 20 (limite recomp) → overweight_remaining
    expect(r.classification).toBe('overweight_remaining')
  })

  it('homem 18% → 3% → unhealthy_low (abaixo do piso do método, 10%)', () => {
    const r = classifyBfGoal({ currentBfPercent: 18, targetBfPercent: 3, sex: 'masculino' })
    expect(r.classification).toBe('unhealthy_low')
    expect(r.semanasParaMetaSeguro).toBe(null)
    expect(r.message).toContain('abaixo')
    expect(r.refused).toBe(true)
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
      // Era 20 → 5 (a meta de 5% era aceita). Com o piso do método (R4,
      // 2026-10-04) 5% é recusado; o caso passa a ser 25 → 10, no piso:
      // delta=15, semanas=30; alvo 10 >= piso 10 → não unhealthy_low;
      // alvo 10 ≤ recomp 20 → não overweight; 30 > 26 E 15 > 10 → long_term ✓
      const r = classifyBfGoal({ currentBfPercent: 25, targetBfPercent: 10, sex: 'masculino' })
      expect(r.classification).toBe('long_term')
      expect(r.refused).toBe(false)
      expect(r.message).toContain('LONGO PRAZO')
      expect(r.message).toContain('degrau intermediário')
    })

    it('20 → 5 (o long_term antigo) agora é recusado, não elogiado', () => {
      const r = classifyBfGoal({ currentBfPercent: 20, targetBfPercent: 5, sex: 'masculino' })
      expect(r.classification).toBe('unhealthy_low')
      expect(r.refused).toBe(true)
      expect(r.message).not.toContain('LONGO PRAZO')
    })

    it('long_term: mulher 38→18 (delta 20pp, 40sem) também é long_term', () => {
      const r = classifyBfGoal({ currentBfPercent: 38, targetBfPercent: 18, sex: 'feminino' })
      // alvo 18 < recomp limit 28 → não overweight. delta=20, semanas=40
      // 40>26 e 20>10 → long_term ✓
      expect(r.classification).toBe('long_term')
    })
  })
})

// R4 — piso do método (docs/CALCULO-MPP.md §8b). Dito pelo cliente em
// 28/12/2025 (texto) e no manual 9.3; implementado em 2026-10-04 a pedido do
// Eduardo; confirmação do cliente pendente.
describe('classifyBfGoal — piso do método: meta abaixo de 10% é recusada', () => {
  const REFUSAL_MAN = (alvo: number) =>
    `Não registrei essa meta: ${alvo}% fica abaixo de 10% de gordura corporal, que é o limite inferior seguro do método. ` +
    'O método não reduz a gordura corporal abaixo de 10%. Nada mudou no seu cadastro. ' +
    'Posso registrar uma meta a partir de 10%. Qual você prefere?'

  it('o piso é 10 e é uma constante só', () => {
    expect(BF_METHOD_FLOOR).toBe(10)
  })

  it.each([
    // [atual, alvo, o que acontecia antes]
    [12, 7, 'ideal: "Boa meta — vamos focar."'],
    [8, 7, 'maintenance (variação de 1 ponto)'],
    [8, 5, 'ideal'],
    [8, 6, 'ideal'],
    [12, 9.9, 'ideal'],
    [12, 4, 'unhealthy_low, aviso com pergunta'],
    [6, 8, 'ideal (subindo)'],
    [9, 9, 'maintenance'],
  ])('homem %s%% → %s%% recusado (antes: %s)', (atual, alvo) => {
    const r = classifyBfGoal({ currentBfPercent: atual, targetBfPercent: alvo, sex: 'masculino' })
    expect(r.refused).toBe(true)
    expect(r.classification).toBe('unhealthy_low')
    expect(r.semanasParaMetaSeguro).toBeNull()
    expect(r.bfMinimoSaudavel).toBe(10)
    expect(r.message).toBe(REFUSAL_MAN(alvo))
    expect(r.message).not.toMatch(/Boa meta|Meta saudável|manter o BF/)
  })

  // Review of 2026-10-04 (LOW): the target was shown rounded to one decimal,
  // so the refusal read "10% fica abaixo de 10%".
  it.each([[9.95], [9.96], [9.99], [9.999]])(
    'o que seria gravado é o que o piso julga: %s é recusado e o texto mostra 9.9%%, nunca 10%%',
    (alvo) => {
      const r = classifyBfGoal({ currentBfPercent: 12, targetBfPercent: alvo, sex: 'masculino' })
      expect(r.refused).toBe(true)
      expect(r.bfAlvo).toBe(9.9)
      expect(r.deltaPp).toBe(2.1)
      expect(r.message).toBe(REFUSAL_MAN(9.9))
      expect(r.message).not.toContain('10% fica abaixo de 10%')
    },
  )

  it('alvo aceito continua mostrado com uma casa (10.04 → 10)', () => {
    const r = classifyBfGoal({ currentBfPercent: 12, targetBfPercent: 10.04, sex: 'masculino' })
    expect(r.refused).toBe(false)
    expect(r.bfAlvo).toBe(10)
  })

  it.each([
    [12, 10, 'ideal', 4],
    [15, 10, 'ideal', 10],
    [11, 10, 'maintenance', null],
    [10, 10, 'maintenance', null],
  ])('homem %s%% → %s%% aceito no piso (%s)', (atual, alvo, classification, semanas) => {
    const r = classifyBfGoal({ currentBfPercent: atual, targetBfPercent: alvo, sex: 'masculino' })
    expect(r.refused).toBe(false)
    expect(r.classification).toBe(classification)
    expect(r.semanasParaMetaSeguro).toBe(semanas)
  })

  it('homem 12% → 10%: o texto de meta aceita não mudou', () => {
    const r = classifyBfGoal({ currentBfPercent: 12, targetBfPercent: 10, sex: 'masculino' })
    expect(r.message).toBe(
      'Meta saudável: 10% (abaixo dos 12% atuais, delta 2pp). No ritmo seguro de ~0.5pp/semana, ~4 semanas. Boa meta — vamos focar.',
    )
  })

  it('mulher 22% → 9% recusada; a oferta parte do 12% que o aviso já cita', () => {
    const r = classifyBfGoal({ currentBfPercent: 22, targetBfPercent: 9, sex: 'feminino' })
    expect(r.refused).toBe(true)
    expect(r.classification).toBe('unhealthy_low')
    expect(r.bfMinimoSaudavel).toBe(12)
    expect(r.message).toBe(
      'Não registrei essa meta: 9% fica abaixo de 10% de gordura corporal, que é o limite inferior seguro do método. ' +
        'O método não reduz a gordura corporal abaixo de 10%. Nada mudou no seu cadastro. ' +
        'Posso registrar uma meta a partir de 12%. Qual você prefere?',
    )
  })

  // O 12% feminino NÃO foi dito pelo cliente: continua aviso, nunca recusa.
  it.each([[10], [11], [11.9]])('mulher 22%% → %s%%: aviso de hoje, sem recusa', (alvo) => {
    const r = classifyBfGoal({ currentBfPercent: 22, targetBfPercent: alvo, sex: 'feminino' })
    expect(r.refused).toBe(false)
    expect(r.classification).toBe('unhealthy_low')
    expect(r.message).toBe(
      `Cuidado — ${alvo}% está ABAIXO do limite essencial pra mulher (mínimo 12%). ` +
        'Perder gordura abaixo desse limite compromete hormônios, recuperação muscular e saúde geral. ' +
        'Sugiro mirar pelo menos 15% — ainda atlético, mas seguro. Faz sentido revisar a meta?',
    )
  })

  it('mulher 11% → 11.5% continua maintenance (o 12% não passou à frente de "manter")', () => {
    const r = classifyBfGoal({ currentBfPercent: 11, targetBfPercent: 11.5, sex: 'feminino' })
    expect(r.refused).toBe(false)
    expect(r.classification).toBe('maintenance')
  })

  it('mulher 22% → 12% segue sem aviso e sem recusa', () => {
    const r = classifyBfGoal({ currentBfPercent: 22, targetBfPercent: 12, sex: 'feminino' })
    expect(r.refused).toBe(false)
    expect(r.classification).toBe('ideal')
  })
})
