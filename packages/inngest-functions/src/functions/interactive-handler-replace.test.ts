import { shouldInferReplaceAfterEdit } from '@mpp/agent'
import { describe, expect, it } from 'vitest'

describe('interactive handler — replace após edição de pending', () => {
  it('não infere replace só por pending editado quando o novo item tem baixo overlap', () => {
    const decision = shouldInferReplaceAfterEdit({
      hasPriorMealOfSameType: true,
      hasPriorEditedPending: true,
      recentUserMessages: ['Torta de frango'],
      newItems: [{ food_name: 'torta de frango', quantity_g: 150 }],
      editedPendingItems: [{ food_name: 'couve-flor grelhada', quantity_g: 150 }],
    })

    expect(decision.inferReplace).toBe(false)
    expect(decision.reason).toBe('blocked_weak_evidence')
    expect(decision.overlapRatio).toBe(0)
  })

  it('continua inferindo replace quando há frase explícita de correção', () => {
    const decision = shouldInferReplaceAfterEdit({
      hasPriorMealOfSameType: true,
      hasPriorEditedPending: true,
      recentUserMessages: ['corrige o jantar, era torta de frango'],
      newItems: [{ food_name: 'torta de frango', quantity_g: 150 }],
      editedPendingItems: [{ food_name: 'couve-flor grelhada', quantity_g: 150 }],
    })

    expect(decision.inferReplace).toBe(true)
    expect(decision.reason).toBe('explicit_correction')
  })
})
