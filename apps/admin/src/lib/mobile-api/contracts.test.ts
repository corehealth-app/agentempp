import { describe, expect, it } from 'vitest'
import {
  idempotencyKeySchema,
  patchMeInputSchema,
  registrationProposalInputSchema,
} from './contracts'

describe('mobile API v1 contracts', () => {
  it('accepts a structured meal proposal without client supplied macros', () => {
    const parsed = registrationProposalInputSchema.parse({
      kind: 'meal',
      meal_type: 'jantar',
      items: [{ food_name: 'arroz branco cozido', quantity_g: 120 }],
    })

    expect(parsed).toEqual({
      kind: 'meal',
      meal_type: 'jantar',
      items: [{ food_name: 'arroz branco cozido', quantity_g: 120 }],
    })
  })

  it('rejects nutrition totals supplied by the mobile client', () => {
    expect(() =>
      registrationProposalInputSchema.parse({
        kind: 'meal',
        meal_type: 'jantar',
        items: [{ food_name: 'arroz', quantity_g: 120, kcal: 999 }],
      }),
    ).toThrow()
  })

  it('accepts only the public editable me fields', () => {
    expect(
      patchMeInputSchema.parse({
        name: 'Paciente Teste',
        locale: 'pt-BR',
        timezone: 'America/New_York',
      }),
    ).toEqual({
      name: 'Paciente Teste',
      locale: 'pt-BR',
      timezone: 'America/New_York',
    })

    expect(() => patchMeInputSchema.parse({ admin_notes: 'forbidden' })).toThrow()
  })

  it('requires opaque bounded idempotency keys', () => {
    expect(idempotencyKeySchema.parse('mobile-018f2c34-abcdef')).toBe('mobile-018f2c34-abcdef')
    expect(() => idempotencyKeySchema.parse('short')).toThrow()
    expect(() => idempotencyKeySchema.parse('line\nbreak-123')).toThrow()
  })
})
