import { afterEach, describe, expect, it, vi } from 'vitest'
import {
  resolveSignupCompletionIntents,
  SIGNUP_COMPLETION_INTENTS_PROJECT_REF_ENV,
  signupCompletionIntentsEnabled,
} from './signup-completion-switch'

const STAGING = 'xitugspwfxkcluxvrdeg'
const OLD = 'xuxehkhdvjivitduarvb'
const URL = `https://${STAGING}.supabase.co`
afterEach(() => vi.unstubAllEnvs())

describe('signup completion intent switch', () => {
  it.each([
    {},
    { NEXT_PUBLIC_SUPABASE_URL: URL },
    { NEXT_PUBLIC_SUPABASE_URL: URL, MOBILE_SIGNUP_COMPLETION_INTENTS_PROJECT_REF: '' },
    {
      NEXT_PUBLIC_SUPABASE_URL: URL,
      MOBILE_SIGNUP_COMPLETION_INTENTS_PROJECT_REF: 'other-project-ref',
    },
    { MOBILE_SIGNUP_COMPLETION_INTENTS_PROJECT_REF: STAGING },
    {
      NEXT_PUBLIC_SUPABASE_URL: 'http://127.0.0.1:21994',
      MOBILE_SIGNUP_COMPLETION_INTENTS_PROJECT_REF: STAGING,
    },
    {
      NEXT_PUBLIC_SUPABASE_URL: `http://${STAGING}.supabase.co`,
      MOBILE_SIGNUP_COMPLETION_INTENTS_PROJECT_REF: STAGING,
    },
    {
      NEXT_PUBLIC_SUPABASE_URL: `https://${STAGING}.supabase.co.example.invalid`,
      MOBILE_SIGNUP_COMPLETION_INTENTS_PROJECT_REF: STAGING,
    },
    {
      NEXT_PUBLIC_SUPABASE_URL: `https://${OLD}.supabase.co`,
      MOBILE_SIGNUP_COMPLETION_INTENTS_PROJECT_REF: OLD,
    },
    {
      NEXT_PUBLIC_SUPABASE_URL: URL,
      MOBILE_SIGNUP_COMPLETION_INTENTS_PROJECT_REF: `${STAGING},${OLD}`,
    },
    {
      NEXT_PUBLIC_SUPABASE_URL: 'not a url',
      MOBILE_SIGNUP_COMPLETION_INTENTS_PROJECT_REF: STAGING,
    },
  ])('stays OFF for unavailable or forbidden configuration (%j)', (env) => {
    expect(resolveSignupCompletionIntents(env)).toBe(false)
  })

  it.each([
    STAGING,
    ` ${STAGING} `,
    `ignored,\n${STAGING}\t`,
  ])('requires the configured hosted ref to be listed (%s)', (refs) => {
    expect(
      resolveSignupCompletionIntents({
        NEXT_PUBLIC_SUPABASE_URL: URL,
        [SIGNUP_COMPLETION_INTENTS_PROJECT_REF_ENV]: refs,
      }),
    ).toBe(true)
  })

  it('does not borrow activation from weekly, workouts or photos', () => {
    expect(
      resolveSignupCompletionIntents({
        NEXT_PUBLIC_SUPABASE_URL: URL,
        MOBILE_STRENGTH_WEEK_PROJECT_REF: STAGING,
        MOBILE_WORKOUT_REGISTRATION_PROJECT_REF: STAGING,
        MOBILE_SIGNUP_BODY_PHOTOS_PROJECT_REF: STAGING,
      }),
    ).toBe(false)
  })

  it('reads the running configuration again rather than caching an ON decision', () => {
    vi.stubEnv('NEXT_PUBLIC_SUPABASE_URL', URL)
    vi.stubEnv(SIGNUP_COMPLETION_INTENTS_PROJECT_REF_ENV, STAGING)
    expect(signupCompletionIntentsEnabled()).toBe(true)
    vi.stubEnv(SIGNUP_COMPLETION_INTENTS_PROJECT_REF_ENV, '')
    expect(signupCompletionIntentsEnabled()).toBe(false)
    vi.stubEnv(SIGNUP_COMPLETION_INTENTS_PROJECT_REF_ENV, `${STAGING} ${OLD}`)
    expect(signupCompletionIntentsEnabled()).toBe(false)
  })
})
