/** OFF until the configured project is explicitly listed. Never permits the
 * old production, including mixed allowlists. No client, I/O or activation. */
export const STRENGTH_WEEK_PROJECT_REF_ENV = 'MOBILE_STRENGTH_WEEK_PROJECT_REF'
const OLD_PRODUCTION = 'xuxehkhdvjivitduarvb'
type Environment = Record<string, string | undefined>

export function resolveStrengthTrainingWeek(env: Environment): boolean {
  const allowed = (env[STRENGTH_WEEK_PROJECT_REF_ENV] ?? '').split(/[\s,]+/).filter(Boolean)
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

export function strengthTrainingWeekEnabled(): boolean {
  return resolveStrengthTrainingWeek({
    NEXT_PUBLIC_SUPABASE_URL: process.env.NEXT_PUBLIC_SUPABASE_URL,
    MOBILE_STRENGTH_WEEK_PROJECT_REF: process.env.MOBILE_STRENGTH_WEEK_PROJECT_REF,
  })
}
