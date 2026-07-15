import { describe, expect, it } from 'vitest'
import { shouldBlockUntrustedNutritionLabelRegistration } from './vision-nutrition-guard.js'

describe('shouldBlockUntrustedNutritionLabelRegistration', () => {
  it('bloqueia refeição quando houve rótulo mas nenhum valor confiável', () => {
    expect(
      shouldBlockUntrustedNutritionLabelRegistration({
        toolName: 'registra_refeicao',
        nutritionLabelDetected: true,
        trustedLabelCount: 0,
      }),
    ).toBe(true)
  })

  it('libera quando existe rótulo confiável ou a tool não é de refeição', () => {
    expect(
      shouldBlockUntrustedNutritionLabelRegistration({
        toolName: 'registra_refeicao',
        nutritionLabelDetected: true,
        trustedLabelCount: 1,
        matchedLabelCount: 1,
      }),
    ).toBe(false)
    expect(
      shouldBlockUntrustedNutritionLabelRegistration({
        toolName: 'atualiza_peso',
        nutritionLabelDetected: true,
        trustedLabelCount: 0,
      }),
    ).toBe(false)
  })

  it('bloqueia quando o OCR é confiável mas nenhum item corresponde ao rótulo', () => {
    expect(
      shouldBlockUntrustedNutritionLabelRegistration({
        toolName: 'registra_refeicao',
        nutritionLabelDetected: true,
        trustedLabelCount: 1,
        matchedLabelCount: 0,
      }),
    ).toBe(true)
  })

  it('bloqueia burst enquanto existir qualquer rótulo detectado sem OCR confiável', () => {
    expect(
      shouldBlockUntrustedNutritionLabelRegistration({
        toolName: 'registra_refeicao',
        nutritionLabelDetected: true,
        detectedLabelCount: 2,
        trustedLabelCount: 1,
        matchedLabelCount: 1,
      }),
    ).toBe(true)
  })

  it('não interfere em turnos sem rótulo', () => {
    expect(
      shouldBlockUntrustedNutritionLabelRegistration({
        toolName: 'registra_refeicao',
        nutritionLabelDetected: false,
        trustedLabelCount: 0,
      }),
    ).toBe(false)
  })
})
