import { describe, expect, it } from 'vitest'
import { classifyWeightGoal, IMC_GOAL_FLOOR } from './weight-goal-classifier.js'

describe('classifyWeightGoal', () => {
  it('meta saudável + ritmo razoável → ideal', () => {
    const r = classifyWeightGoal({ currentWeightKg: 80, targetWeightKg: 75, heightCm: 175 })
    expect(r.classification).toBe('ideal')
    expect(r.imcAlvo).toBeCloseTo(24.5, 1)
    expect(r.direction).toBe('perder')
    expect(r.semanasParaMetaSeguro).not.toBeNull()
  })

  it('meta abaixo do saudável (IMC < 18.5) → unhealthy_low', () => {
    // Mulher 1.65m querendo 48kg → IMC 17.6
    const r = classifyWeightGoal({ currentWeightKg: 65, targetWeightKg: 48, heightCm: 165 })
    expect(r.classification).toBe('unhealthy_low')
    expect(r.imcAlvo).toBeLessThan(18.5)
    expect(r.pesoMinimoSaudavelKg).toBeCloseTo(50.4, 1)
    expect(r.message).toContain('abaixo do saudável')
    expect(r.semanasParaMetaSeguro).toBeNull()
    // R4 (2026-10-04): perdendo peso para IMC < 18.5 a meta não é gravada.
    expect(r.refused).toBe(true)
    expect(r.message).not.toContain('quer rever?')
  })

  it('meta ainda em sobrepeso (IMC 25-29.9) → overweight_remaining', () => {
    // Homem 1.75m, atual 100kg, meta 80kg → IMC alvo 26.1
    const r = classifyWeightGoal({ currentWeightKg: 100, targetWeightKg: 80, heightCm: 175 })
    expect(r.classification).toBe('overweight_remaining')
    expect(r.imcAlvo).toBeCloseTo(26.1, 1)
  })

  it('meta ainda em obesidade (IMC ≥ 30) → obesity_remaining', () => {
    // Homem 1.75m, atual 120kg, meta 95kg → IMC alvo 31.0
    const r = classifyWeightGoal({ currentWeightKg: 120, targetWeightKg: 95, heightCm: 175 })
    expect(r.classification).toBe('obesity_remaining')
    expect(r.imcAlvo).toBeCloseTo(31, 1)
    expect(r.message).toContain('obesidade')
  })

  it('meta saudável mas perda > 15% → aggressive_pace', () => {
    // Homem 1.75m, 100kg → 70kg = -30% do peso atual
    const r = classifyWeightGoal({ currentWeightKg: 100, targetWeightKg: 70, heightCm: 175 })
    expect(r.classification).toBe('aggressive_pace')
    expect(r.deltaKg).toBe(30)
  })

  it('meta ≈ peso atual (±2%) → maintenance', () => {
    const r = classifyWeightGoal({ currentWeightKg: 75, targetWeightKg: 76, heightCm: 175 })
    expect(r.classification).toBe('maintenance')
    expect(r.direction).toBe('manter')
  })

  it('quer GANHAR peso em faixa saudável', () => {
    const r = classifyWeightGoal({ currentWeightKg: 60, targetWeightKg: 68, heightCm: 175 })
    expect(r.direction).toBe('ganhar')
    expect(r.classification).toBe('ideal')
  })
})

// R4 — magro demais (docs/CALCULO-MPP.md §8b). Dito pelo cliente em 09/06/2026
// (texto e manual 3.5); implementado em 2026-10-04 a pedido do Eduardo;
// confirmação do cliente pendente.
describe('classifyWeightGoal — meta que deixa o IMC abaixo de 18.5', () => {
  it('o piso é 18.5 e é uma constante só', () => {
    expect(IMC_GOAL_FLOOR).toBe(18.5)
  })

  it('55 kg → 48 kg, 170 cm (perdendo): recusada, com a faixa saudável no texto', () => {
    const r = classifyWeightGoal({ currentWeightKg: 55, targetWeightKg: 48, heightCm: 170 })
    expect(r.classification).toBe('unhealthy_low')
    expect(r.direction).toBe('perder')
    expect(r.imcAlvo).toBe(16.6)
    expect(r.refused).toBe(true)
    expect(r.message).toBe(
      'Essa meta (48kg) te deixaria com IMC 16.6, abaixo do saudável (mínimo OMS é 18.5). ' +
        'Pra sua altura, o peso mínimo saudável é 53.5kg. ' +
        'Por segurança, não registrei essa meta e nada mudou no seu cadastro. ' +
        'Posso registrar uma meta entre 53.5 e 72kg. Qual você prefere?',
    )
  })

  it('45 kg → 48 kg, 170 cm (ganhando): aviso de hoje, sem recusa', () => {
    const r = classifyWeightGoal({ currentWeightKg: 45, targetWeightKg: 48, heightCm: 170 })
    expect(r.classification).toBe('unhealthy_low')
    expect(r.direction).toBe('ganhar')
    expect(r.refused).toBe(false)
    expect(r.message).toBe(
      'Essa meta (48kg) te deixaria com IMC 16.6, abaixo do saudável (mínimo OMS é 18.5). ' +
        'Pra sua altura, o peso mínimo saudável é 53.5kg. ' +
        'Sugiro ajustar a meta pra algo entre 53.5 e 72kg — quer rever?',
    )
  })

  const REFUSAL = (alvoKg: number, imc: number, minKg: number, maxKg: number) =>
    `Essa meta (${alvoKg}kg) te deixaria com IMC ${imc}, abaixo do saudável (mínimo OMS é 18.5). ` +
    `Pra sua altura, o peso mínimo saudável é ${minKg}kg. ` +
    'Por segurança, não registrei essa meta e nada mudou no seu cadastro. ' +
    `Posso registrar uma meta entre ${minKg} e ${maxKg}kg. Qual você prefere?`

  // Review of 2026-10-04 (HIGH): the "manter" band (change under 2% of the
  // weight) ran before the floor, so these goals were saved as maintenance.
  it.each([
    // [atual, alvo, altura, IMC mostrado, mínimo, máximo, delta]
    [54, 53, 170, 18.3, 53.5, 72, 1],
    [52, 51.5, 170, 17.8, 53.5, 72, 0.5],
    [40, 39.3, 160, 15.4, 47.4, 63.7, 0.7],
  ])(
    '%s kg → %s kg, %s cm (perdendo menos de 2%% do peso): recusada, nunca "manter"',
    (atual, alvo, altura, imc, min, max, delta) => {
      const r = classifyWeightGoal({ currentWeightKg: atual, targetWeightKg: alvo, heightCm: altura })
      expect(r.refused).toBe(true)
      expect(r.classification).toBe('unhealthy_low')
      // Any loss is a loss: the model must not read "manter" beside a refusal.
      expect(r.direction).toBe('perder')
      expect(r.deltaKg).toBe(delta)
      expect(r.semanasParaMetaSeguro).toBeNull()
      expect(r.message).toBe(REFUSAL(alvo, imc, min, max))
      expect(r.message).not.toMatch(/manter|Manutenção/)
    },
  )

  // Review of 2026-10-04 (HIGH): the floor judged the BMI rounded to one
  // decimal, so a raw 18.45–18.499 became 18.5 and passed as "ideal".
  it.each([
    // [atual, alvo, altura, IMC bruto, mínimo, máximo]
    [55, 53.4, 170, 18.478, 53.5, 72],
    [70, 66.7, 190, 18.476, 66.8, 89.9],
    [70, 66.6, 190, 18.449, 66.8, 89.9],
    [45, 41.6, 150, 18.489, 41.7, 56],
  ])(
    '%s kg → %s kg, %s cm (IMC bruto %s): recusada, e o texto mostra 18.4, nunca 18.5',
    (atual, alvo, altura, _imcBruto, min, max) => {
      const r = classifyWeightGoal({ currentWeightKg: atual, targetWeightKg: alvo, heightCm: altura })
      expect(r.refused).toBe(true)
      expect(r.classification).toBe('unhealthy_low')
      expect(r.imcAlvo).toBe(18.4)
      expect(r.message).toBe(REFUSAL(alvo, 18.4, min, max))
      expect(r.message).not.toContain('IMC 18.5')
    },
  )

  it.each([
    [55, 53.5, 170],
    [70, 66.8, 190],
    [45, 41.7, 150],
  ])('%s kg → %s kg, %s cm: o peso mínimo que a recusa oferece é aceito', (atual, alvo, altura) => {
    const r = classifyWeightGoal({ currentWeightKg: atual, targetWeightKg: alvo, heightCm: altura })
    expect(r.pesoMinimoSaudavelKg).toBe(alvo)
    expect(r.refused).toBe(false)
    expect(r.classification).toBe('ideal')
    expect(r.imcAlvo).toBe(18.5)
  })

  it('150 cm: o mínimo oferecido era 41.6 kg (IMC 18.49, recusado pela própria tool); agora 41.7', () => {
    const r = classifyWeightGoal({ currentWeightKg: 50, targetWeightKg: 40, heightCm: 150 })
    expect(r.pesoMinimoSaudavelKg).toBe(41.7)
    expect(r.message).toContain('Posso registrar uma meta entre 41.7 e 56kg.')
  })

  it('de 140 a 210 cm (0,5 em 0,5): o mínimo oferecido é aceito e 0,1 kg abaixo dele é recusado', () => {
    for (let altura = 140; altura <= 210; altura += 0.5) {
      const min = classifyWeightGoal({
        currentWeightKg: 90,
        targetWeightKg: 80,
        heightCm: altura,
      }).pesoMinimoSaudavelKg
      const atMin = classifyWeightGoal({
        currentWeightKg: min + 5,
        targetWeightKg: min,
        heightCm: altura,
      })
      const below = classifyWeightGoal({
        currentWeightKg: min + 5,
        targetWeightKg: Math.round((min - 0.1) * 10) / 10,
        heightCm: altura,
      })
      expect([altura, atMin.refused, atMin.imcAlvo >= 18.5]).toEqual([altura, false, true])
      expect([altura, below.refused, below.imcAlvo < 18.5]).toEqual([altura, true, true])
    }
  })

  it('52 kg → 52 kg, 170 cm (meta igual ao peso atual, já abaixo de 18.5): "manter", sem recusa (pendência)', () => {
    const r = classifyWeightGoal({ currentWeightKg: 52, targetWeightKg: 52, heightCm: 170 })
    expect(r.classification).toBe('maintenance')
    expect(r.direction).toBe('manter')
    expect(r.refused).toBe(false)
  })

  it('52 kg → 52.5 kg, 170 cm (ganhando menos de 2%, ainda abaixo de 18.5): "manter", sem recusa (pendência)', () => {
    const r = classifyWeightGoal({ currentWeightKg: 52, targetWeightKg: 52.5, heightCm: 170 })
    expect(r.classification).toBe('maintenance')
    expect(r.refused).toBe(false)
  })

  // Same raw judgement on the way up: it was "Ótima meta — IMC 18.5 cai bem
  // na faixa saudável" for a goal the tool itself puts under the minimum.
  it('50 kg → 53.4 kg, 170 cm (ganhando, IMC bruto 18.478): aviso, sem recusa', () => {
    const r = classifyWeightGoal({ currentWeightKg: 50, targetWeightKg: 53.4, heightCm: 170 })
    expect(r.classification).toBe('unhealthy_low')
    expect(r.direction).toBe('ganhar')
    expect(r.refused).toBe(false)
    expect(r.message).toBe(
      'Essa meta (53.4kg) te deixaria com IMC 18.4, abaixo do saudável (mínimo OMS é 18.5). ' +
        'Pra sua altura, o peso mínimo saudável é 53.5kg. ' +
        'Sugiro ajustar a meta pra algo entre 53.5 e 72kg — quer rever?',
    )
  })

  it('nenhuma outra classe é recusada', () => {
    for (const [cur, tgt, h] of [
      [80, 75, 175],
      [100, 80, 175],
      [120, 95, 175],
      [100, 70, 175],
      [75, 76, 175],
      [60, 68, 175],
    ] as const) {
      expect(
        classifyWeightGoal({ currentWeightKg: cur, targetWeightKg: tgt, heightCm: h }).refused,
      ).toBe(false)
    }
  })
})
