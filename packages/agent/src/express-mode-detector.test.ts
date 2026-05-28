import { describe, it, expect } from 'vitest'
import { isMealExpressEligible, isWorkoutExpressEligible } from './express-mode-detector.js'

// Roberto 2026-05-28 — Fase B botões #4. Default conservador: na dúvida, vai pra
// botão. Express = texto SEM incerteza + gramatura/unidade explícita pra cada item.

const items2 = [
  { food_name: 'arroz branco cozido', quantity_g: 100 },
  { food_name: 'frango grelhado', quantity_g: 150 },
]

describe('isMealExpressEligible — modo EXPRESS (grava direto sem botão)', () => {
  it('texto claro com gramas em cada item → EXPRESS ✅', () => {
    const r = isMealExpressEligible({
      contentType: 'text',
      patientText: 'comi 100g de arroz e 150g de frango',
      items: items2,
    })
    expect(r.eligible).toBe(true)
    expect(r.qty_markers_found).toBeGreaterThanOrEqual(2)
  })

  it('texto com "uns 100g" (incerteza) → NÃO express, vai pra botão', () => {
    const r = isMealExpressEligible({
      contentType: 'text',
      patientText: 'comi uns 100g de arroz e 150g de frango',
      items: items2,
    })
    expect(r.eligible).toBe(false)
    expect(r.reason).toBe('uncertainty_marker')
  })

  it('texto com "mais ou menos" / "acho que" / "talvez" → NÃO express', () => {
    for (const txt of ['mais ou menos 100g de arroz', 'acho que comi 200g', 'talvez 1 copo']) {
      const r = isMealExpressEligible({ contentType: 'text', patientText: txt, items: items2 })
      expect(r.eligible).toBe(false)
      expect(r.reason).toBe('uncertainty_marker')
    }
  })

  it('texto sem gramatura para todos os items → NÃO express', () => {
    const r = isMealExpressEligible({
      contentType: 'text',
      patientText: 'comi arroz com frango', // zero quantidade
      items: items2,
    })
    expect(r.eligible).toBe(false)
    expect(r.reason).toBe('qty_count_mismatch')
  })

  it('texto com gramatura SÓ pra 1 dos 2 items → NÃO express', () => {
    const r = isMealExpressEligible({
      contentType: 'text',
      patientText: 'comi 100g de arroz e um pouco de frango',
      items: items2,
    })
    expect(r.eligible).toBe(false)
    expect(r.reason).toBe('qty_count_mismatch')
  })

  it('foto SEMPRE não-express (mesmo com texto perfeito de legenda)', () => {
    const r = isMealExpressEligible({
      contentType: 'image',
      patientText: 'comi 100g arroz, 150g frango',
      items: items2,
    })
    expect(r.eligible).toBe(false)
    expect(r.reason).toBe('content_type_image')
  })

  it('áudio SEMPRE não-express', () => {
    const r = isMealExpressEligible({
      contentType: 'audio',
      patientText: 'comi 100g arroz',
      items: [{ food_name: 'arroz', quantity_g: 100 }],
    })
    expect(r.eligible).toBe(false)
    expect(r.reason).toBe('content_type_audio')
  })

  it('aceita unidades naturais ("2 unidades", "1 colher", "200 ml")', () => {
    const r = isMealExpressEligible({
      contentType: 'text',
      patientText: '2 ovos cozidos e 1 colher de azeite e 200ml de leite',
      items: [
        { food_name: 'ovo cozido', quantity_g: 100 },
        { food_name: 'azeite', quantity_g: 12 },
        { food_name: 'leite', quantity_g: 200 },
      ],
    })
    expect(r.eligible).toBe(true)
  })

  it('items vazios → NÃO express', () => {
    const r = isMealExpressEligible({
      contentType: 'text',
      patientText: 'comi 100g de arroz',
      items: [],
    })
    expect(r.eligible).toBe(false)
    expect(r.reason).toBe('no_items')
  })

  it('texto vazio → NÃO express', () => {
    const r = isMealExpressEligible({
      contentType: 'text',
      patientText: '',
      items: items2,
    })
    expect(r.eligible).toBe(false)
    expect(r.reason).toBe('empty_text')
  })

  it('caso Roberto: "comi 100g de arroz branco cozido + 150g de frango grelhado" → EXPRESS', () => {
    const r = isMealExpressEligible({
      contentType: 'text',
      patientText: 'comi 100g de arroz branco cozido + 150g de frango grelhado',
      items: [
        { food_name: 'arroz branco cozido', quantity_g: 100 },
        { food_name: 'frango grelhado', quantity_g: 150 },
      ],
    })
    expect(r.eligible).toBe(true)
  })
})

describe('isWorkoutExpressEligible — TREINO (Fase D botões #4)', () => {
  it('"30 min de caminhada" → EXPRESS', () => {
    const r = isWorkoutExpressEligible({
      contentType: 'text',
      patientText: '30 min de caminhada',
      workoutType: 'caminhada',
      durationMin: 30,
    })
    expect(r.eligible).toBe(true)
  })

  it('"caminhada" (sem duração no texto) → não express', () => {
    const r = isWorkoutExpressEligible({
      contentType: 'text',
      patientText: 'fiz caminhada hoje',
      workoutType: 'caminhada',
      durationMin: 30, // tool inferiu, mas texto não tem
    })
    expect(r.eligible).toBe(false)
    expect(r.reason).toBe('no_explicit_duration_in_text')
  })

  it('"treinei um pouco" → não express (sem duração + vago)', () => {
    const r = isWorkoutExpressEligible({
      contentType: 'text',
      patientText: 'treinei um pouco hoje',
      workoutType: 'musculacao',
      durationMin: null,
    })
    expect(r.eligible).toBe(false)
    expect(r.reason).toBe('no_duration')
  })

  it('"talvez 30 min de caminhada" → não express (incerteza)', () => {
    const r = isWorkoutExpressEligible({
      contentType: 'text',
      patientText: 'talvez 30 min de caminhada',
      workoutType: 'caminhada',
      durationMin: 30,
    })
    expect(r.eligible).toBe(false)
    expect(r.reason).toBe('uncertainty_marker')
  })

  it('foto/áudio NUNCA são express', () => {
    expect(
      isWorkoutExpressEligible({
        contentType: 'image',
        patientText: '30 min de caminhada',
        workoutType: 'caminhada',
        durationMin: 30,
      }).eligible,
    ).toBe(false)
    expect(
      isWorkoutExpressEligible({
        contentType: 'audio',
        patientText: '30 min de caminhada',
        workoutType: 'caminhada',
        durationMin: 30,
      }).eligible,
    ).toBe(false)
  })

  it('aceita "1 hora" como duração explícita', () => {
    const r = isWorkoutExpressEligible({
      contentType: 'text',
      patientText: 'fiz 1 hora de musculação',
      workoutType: 'musculacao',
      durationMin: 60,
    })
    expect(r.eligible).toBe(true)
  })
})
