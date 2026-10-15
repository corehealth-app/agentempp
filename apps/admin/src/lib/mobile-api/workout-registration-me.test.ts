import { beforeEach, describe, expect, it, vi } from 'vitest'
import type { MobileAuthContext } from './auth'
import { meDto } from './read-model'
import { meWithWorkoutRegistrationCapability } from './workout-registration-service'

const state = vi.hoisted(() => ({ enabled: false }))
vi.mock('./workout-registration-switch', () => ({
  workoutRegistrationEnabled: () => state.enabled,
}))
const auth: MobileAuthContext = {
  userId: '00000000-0000-4000-8000-000000000001',
  authUserId: '00000000-0000-4000-8000-000000000002',
  accessToken: 'synthetic-private-token',
  identity: {
    id: '00000000-0000-4000-8000-000000000002',
    email: 'qa@example.invalid',
    emailConfirmedAt: '2026-10-15T10:00:00Z',
  },
  patient: {
    id: '00000000-0000-4000-8000-000000000001',
    authUserId: '00000000-0000-4000-8000-000000000002',
    email: 'qa@example.invalid',
    name: 'Synthetic',
    locale: 'pt-BR',
    timezone: 'UTC',
    country: 'BR',
    countryConfirmed: true,
    status: 'active',
  },
}
beforeEach(() => {
  state.enabled = false
})

describe('server-owned workout protocol advertisement in the existing /me read', () => {
  it('leaves the legacy /me output exactly unchanged while OFF', () => {
    expect(meWithWorkoutRegistrationCapability(auth)).toStrictEqual(meDto(auth))
    expect(meWithWorkoutRegistrationCapability(auth)).not.toHaveProperty(
      'workout_registration_protocol',
    )
  })
  it('adds only the available literal protocol without exposing auth/session material', () => {
    state.enabled = true
    const result = meWithWorkoutRegistrationCapability(auth)
    expect(result).toStrictEqual({ ...meDto(auth), workout_registration_protocol: 'ui-v1' })
    expect(JSON.stringify(result)).not.toContain(auth.accessToken)
    expect(result).not.toHaveProperty('expected_revision')
  })
})
