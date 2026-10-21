/** OFF by default. Independent of photo, weekly and workout activation. */
export const SIGNUP_COMPLETION_INTENTS_PROJECT_REF_ENV =
  'MOBILE_SIGNUP_COMPLETION_INTENTS_PROJECT_REF'
const OLD_PRODUCTION = 'xuxehkhdvjivitduarvb'
type Environment = Record<string, string | undefined>

export function resolveSignupCompletionIntents(env: Environment): boolean {
  const allowed = (env[SIGNUP_COMPLETION_INTENTS_PROJECT_REF_ENV] ?? '')
    .split(/[\s,]+/)
    .filter(Boolean)
  if (allowed.includes(OLD_PRODUCTION)) return false
  try {
    const url = new URL(env.NEXT_PUBLIC_SUPABASE_URL ?? '')
    const ref =
      url.protocol === 'https:'
        ? url.hostname.match(/^([a-z0-9]{20})\.supabase\.co$/)?.[1]
        : undefined
    return ref !== undefined && ref !== OLD_PRODUCTION && allowed.includes(ref)
  } catch {
    return false
  }
}

/** Read again at each authority boundary; never cache an earlier ON result. */
export function signupCompletionIntentsEnabled(): boolean {
  return resolveSignupCompletionIntents({
    NEXT_PUBLIC_SUPABASE_URL: process.env.NEXT_PUBLIC_SUPABASE_URL,
    MOBILE_SIGNUP_COMPLETION_INTENTS_PROJECT_REF:
      process.env.MOBILE_SIGNUP_COMPLETION_INTENTS_PROJECT_REF,
  })
}
