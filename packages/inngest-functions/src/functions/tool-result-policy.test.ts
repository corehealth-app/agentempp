import { describe, expect, it } from 'vitest'
import { requireSuccessfulMealToolResult } from './tool-result-policy.js'

describe('requireSuccessfulMealToolResult', () => {
  it('aceita somente uma gravação confirmada pela tool', () => {
    expect(() => requireSuccessfulMealToolResult({ success: true })).not.toThrow()
  })

  it('bloqueia card falso quando o alvo da correção não é seguro', () => {
    expect(() =>
      requireSuccessfulMealToolResult({
        success: false,
        error: 'replacement_target_not_found',
        message: 'Nenhum registro foi apagado ou adicionado.',
      }),
    ).toThrow('replacement_target_not_found')
  })
})
