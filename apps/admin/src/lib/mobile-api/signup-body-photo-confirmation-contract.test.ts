import { describe, expect, it } from 'vitest'
import { onboardingCompletionInputSchema } from './contracts'

const FRONT = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'
const SIDE = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb'
const BACK = 'cccccccc-cccc-4ccc-8ccc-cccccccccccc'
const ACCEPT = {
  decision: 'accept',
  source_ids: { front: FRONT, side: SIDE, back: BACK },
  fingerprint: 'a'.repeat(64),
}

function submission(confirmation?: unknown) {
  return {
    name: 'Synthetic User',
    locale: 'pt-BR',
    country: 'BR',
    timezone: 'America/Sao_Paulo',
    sex: 'masculino',
    birth_date: '1990-01-01',
    height_cm: 180,
    weight_kg: 80,
    objective: 'recomposicao',
    activity_level: 'moderado',
    training_frequency: 4,
    water_intake: 'moderado',
    hunger_level: 'moderada',
    wake_time: '07:00',
    bedtime: '23:00',
    food_organization: 'sim',
    persona: 'focus',
    document_actions: [
      {
        document_key: 'terms_of_service',
        version: '2026-09-15.1',
        locale: 'pt-BR',
        content_hash: 'b'.repeat(64),
        action: 'acceptance',
      },
    ],
    ...(confirmation === undefined ? {} : { body_photo_confirmation: confirmation }),
  }
}

describe('D2 explicit photo confirmation on the existing completion contract', () => {
  it('accepts the three official slot IDs and fingerprint without a client BF value', () => {
    const original = submission(ACCEPT)
    const parsed = onboardingCompletionInputSchema.safeParse(original)
    expect(parsed.success).toBe(true)
    if (!parsed.success) throw new Error('Expected the explicit confirmation to parse')
    expect(parsed.data).toEqual(original)
    expect(parsed.data).not.toHaveProperty('body_fat_percent')
  })

  it('accepts an explicit decline without introducing an inferred refusal or a BF value', () => {
    const original = submission({ decision: 'decline' })
    expect(onboardingCompletionInputSchema.safeParse(original)).toMatchObject({
      success: true,
      data: original,
    })
  })

  it('preserves the legacy completion with no confirmation metadata', () => {
    const original = { ...submission(), body_fat_percent: 24 }
    expect(onboardingCompletionInputSchema.parse(original)).toEqual(original)
    expect(original).not.toHaveProperty('body_photo_confirmation')
  })

  it.each([
    null,
    { decision: 'accept' },
    { ...ACCEPT, source_ids: { front: FRONT, side: SIDE } },
    { ...ACCEPT, source_ids: { ...ACCEPT.source_ids, extra: BACK } },
    { ...ACCEPT, source_ids: { front: FRONT, side: FRONT.toUpperCase(), back: BACK } },
    { ...ACCEPT, fingerprint: 'A'.repeat(64) },
    { ...ACCEPT, fingerprint: 'a'.repeat(63) },
    { ...ACCEPT, body_fat_percent: 24 },
    { ...ACCEPT, user_id: FRONT },
    { decision: 'decline', source_ids: ACCEPT.source_ids },
  ])('refuses malformed or client-controlled confirmation %#', (confirmation) => {
    expect(onboardingCompletionInputSchema.safeParse(submission(confirmation)).success).toBe(false)
  })
})
