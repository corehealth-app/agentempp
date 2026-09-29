/**
 * Golden test — Flow diet proposal refused before generation, staging device
 * gate of 2026-09-28 (QA account A, 23:02, 23:13 and 23:22 local).
 *
 * Exact scenario: "Quero uma proposta de cardapio de um dia, dentro da minha
 * meta, sem restricoes." The model called propoe_plano_dieta twice; both calls
 * threw at argument validation (no generator event, ~14 s), then answered
 * with no text, so the app showed "Não foi possível falar com o Flow". The
 * schema refuses null for optional arguments (restrictions/preferences/
 * meals_per_day) — what a model writes for "sem restrições". The exact
 * argument sent was not logged; the probe on staging-equivalent schema shows
 * null optionals are refused (this is the covered variant). Numeric strings
 * and unknown enum values stay refused.
 *
 * Only the Flow proposal tools normalise; WhatsApp gera_* are unchanged.
 */
import { describe, expect, it } from 'vitest'
import { geraDieta, geraTreino, propoePlanoDieta, propoePlanoTreino } from '../tools.js'
import { normalizeToolArguments } from '../tools/types.js'

describe('audit 2026-09-28 — null optional arguments on Flow proposals', () => {
  it('propoe_plano_dieta accepts "sem restrições" written as null', () => {
    for (const args of [
      { horizon: 'daily', restrictions: null },
      { horizon: 'daily', restrictions: null, preferences: null, meals_per_day: null },
    ]) {
      expect(propoePlanoDieta.parameters.safeParse(normalizeToolArguments(propoePlanoDieta, args)).success).toBe(true)
    }
  })

  it('propoe_plano_treino accepts null optionals too', () => {
    const args = { available_equipment: ['academia completa'], location: 'academia_completa', days_per_week: 4, training_level: 'intermediario', limitations: null, priority_muscles: null }
    expect(propoePlanoTreino.parameters.safeParse(normalizeToolArguments(propoePlanoTreino, args)).success).toBe(true)
  })

  it('a null required argument is still refused', () => {
    const args = { available_equipment: ['academia completa'], location: null, days_per_week: 4, training_level: 'intermediario' }
    expect(propoePlanoTreino.parameters.safeParse(normalizeToolArguments(propoePlanoTreino, args)).success).toBe(false)
  })

  it('wrong types and unknown values are still refused', () => {
    for (const args of [{ horizon: 'daily', meals_per_day: '4' }, { horizon: 'diario' }]) {
      expect(propoePlanoDieta.parameters.safeParse(normalizeToolArguments(propoePlanoDieta, args)).success).toBe(false)
    }
  })

  it('WhatsApp gera_* tools are unchanged: null still refused', () => {
    expect(geraDieta.parameters.safeParse(normalizeToolArguments(geraDieta, { horizon: 'daily', restrictions: null })).success).toBe(false)
    expect(geraTreino.parameters.safeParse(normalizeToolArguments(geraTreino, { available_equipment: ['academia completa'], location: 'academia_completa', days_per_week: 4, training_level: 'intermediario', limitations: null })).success).toBe(false)
  })
})
