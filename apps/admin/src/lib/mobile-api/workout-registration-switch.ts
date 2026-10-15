/** OFF until this configured project is explicitly listed. Never targets the
 * old production, including accidental mixed allowlists. No client or I/O. */
export const WORKOUT_REGISTRATION_PROJECT_REF_ENV = 'MOBILE_WORKOUT_REGISTRATION_PROJECT_REF'
const OLD_PRODUCTION = 'xuxehkhdvjivitduarvb'
type Environment = Record<string, string | undefined>

export function resolveWorkoutRegistration(env: Environment): boolean {
  const allowed = (env[WORKOUT_REGISTRATION_PROJECT_REF_ENV] ?? '').split(/[\s,]+/).filter(Boolean)
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

export function workoutRegistrationEnabled(): boolean {
  return resolveWorkoutRegistration({
    NEXT_PUBLIC_SUPABASE_URL: process.env.NEXT_PUBLIC_SUPABASE_URL,
    MOBILE_WORKOUT_REGISTRATION_PROJECT_REF: process.env.MOBILE_WORKOUT_REGISTRATION_PROJECT_REF,
  })
}
