import { afterEach, describe, expect, it, vi } from 'vitest'
import {
  resolveStrengthTrainingWeek,
  strengthTrainingWeekEnabled,
} from './strength-training-week-switch'

const STAGING = 'xitugspwfxkcluxvrdeg'
const OLD_PRODUCTION = 'xuxehkhdvjivitduarvb'

afterEach(() => vi.unstubAllEnvs())

describe('weekly strength environment switch', () => {
  it.each([
    {},
    { NEXT_PUBLIC_SUPABASE_URL: `https://${STAGING}.supabase.co` },
    {
      NEXT_PUBLIC_SUPABASE_URL: `https://${STAGING}.supabase.co`,
      MOBILE_STRENGTH_WEEK_PROJECT_REF: 'true',
    },
    {
      NEXT_PUBLIC_SUPABASE_URL: `http://${STAGING}.supabase.co`,
      MOBILE_STRENGTH_WEEK_PROJECT_REF: STAGING,
    },
    {
      NEXT_PUBLIC_SUPABASE_URL: 'http://localhost:54321',
      MOBILE_STRENGTH_WEEK_PROJECT_REF: STAGING,
    },
    { NEXT_PUBLIC_SUPABASE_URL: 'not a URL', MOBILE_STRENGTH_WEEK_PROJECT_REF: STAGING },
    {
      NEXT_PUBLIC_SUPABASE_URL: `https://${STAGING}.supabase.co.attacker.test`,
      MOBILE_STRENGTH_WEEK_PROJECT_REF: STAGING,
    },
    {
      NEXT_PUBLIC_SUPABASE_URL: `https://${OLD_PRODUCTION}.supabase.co`,
      MOBILE_STRENGTH_WEEK_PROJECT_REF: OLD_PRODUCTION,
    },
    {
      NEXT_PUBLIC_SUPABASE_URL: `https://${STAGING}.supabase.co`,
      MOBILE_STRENGTH_WEEK_PROJECT_REF: `${STAGING},${OLD_PRODUCTION}`,
    },
  ])('stays OFF without an explicitly proved safe target %#', (env) => {
    expect(resolveStrengthTrainingWeek(env)).toBe(false)
  })

  it('enables only the listed project configured for the client', () => {
    expect(
      resolveStrengthTrainingWeek({
        NEXT_PUBLIC_SUPABASE_URL: `https://${STAGING}.supabase.co`,
        MOBILE_STRENGTH_WEEK_PROJECT_REF: ` , ${STAGING}\n`,
      }),
    ).toBe(true)
  })

  it('reads the independent flag anew; the workout registration switch cannot enable it', () => {
    vi.stubEnv('NEXT_PUBLIC_SUPABASE_URL', `https://${STAGING}.supabase.co`)
    vi.stubEnv('MOBILE_WORKOUT_REGISTRATION_PROJECT_REF', STAGING)
    vi.stubEnv('MOBILE_STRENGTH_WEEK_PROJECT_REF', '')
    expect(strengthTrainingWeekEnabled()).toBe(false)
    vi.stubEnv('MOBILE_STRENGTH_WEEK_PROJECT_REF', STAGING)
    expect(strengthTrainingWeekEnabled()).toBe(true)
    vi.stubEnv('MOBILE_STRENGTH_WEEK_PROJECT_REF', '')
    expect(strengthTrainingWeekEnabled()).toBe(false)
  })
})
