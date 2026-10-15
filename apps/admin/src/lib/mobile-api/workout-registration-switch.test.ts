import { describe, expect, it, vi } from 'vitest'
import {
  resolveWorkoutRegistration,
  workoutRegistrationEnabled,
} from './workout-registration-switch'

const STAGING = 'xitugspwfxkcluxvrdeg'
const OLD_PRODUCTION = 'xuxehkhdvjivitduarvb'

describe('versioned workout registration environment switch', () => {
  it.each([
    {},
    { NEXT_PUBLIC_SUPABASE_URL: `https://${STAGING}.supabase.co` },
    {
      NEXT_PUBLIC_SUPABASE_URL: `https://${STAGING}.supabase.co`,
      MOBILE_WORKOUT_REGISTRATION_PROJECT_REF: 'true',
    },
    {
      NEXT_PUBLIC_SUPABASE_URL: `http://${STAGING}.supabase.co`,
      MOBILE_WORKOUT_REGISTRATION_PROJECT_REF: STAGING,
    },
    {
      NEXT_PUBLIC_SUPABASE_URL: 'http://localhost:54321',
      MOBILE_WORKOUT_REGISTRATION_PROJECT_REF: STAGING,
    },
    {
      NEXT_PUBLIC_SUPABASE_URL: `https://${OLD_PRODUCTION}.supabase.co`,
      MOBILE_WORKOUT_REGISTRATION_PROJECT_REF: OLD_PRODUCTION,
    },
    {
      NEXT_PUBLIC_SUPABASE_URL: `https://${STAGING}.supabase.co`,
      MOBILE_WORKOUT_REGISTRATION_PROJECT_REF: `${STAGING},${OLD_PRODUCTION}`,
    },
  ])('is OFF by default or for an unproved/old production target %#', (env) => {
    expect(resolveWorkoutRegistration(env)).toBe(false)
  })

  it('accepts only the explicitly listed project of the configured client', () => {
    expect(
      resolveWorkoutRegistration({
        NEXT_PUBLIC_SUPABASE_URL: `https://${STAGING}.supabase.co`,
        MOBILE_WORKOUT_REGISTRATION_PROJECT_REF: STAGING,
      }),
    ).toBe(true)
  })

  it('reads configuration anew, without enabling or writing an environment', () => {
    vi.stubEnv('NEXT_PUBLIC_SUPABASE_URL', `https://${STAGING}.supabase.co`)
    vi.stubEnv('MOBILE_WORKOUT_REGISTRATION_PROJECT_REF', '')
    try {
      expect(workoutRegistrationEnabled()).toBe(false)
      vi.stubEnv('MOBILE_WORKOUT_REGISTRATION_PROJECT_REF', STAGING)
      expect(workoutRegistrationEnabled()).toBe(true)
    } finally {
      vi.unstubAllEnvs()
    }
  })
})
