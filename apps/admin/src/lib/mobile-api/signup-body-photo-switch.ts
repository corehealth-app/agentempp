/**
 * The switch of the body photos of the sign-up
 * (docs/mobile/api-v1.md, "Fotos do corpo no cadastro").
 *
 * WHY A SWITCH. The same app-server code is what the old production
 * publishes, and the photo routes sit outside the paid-access gate: with them
 * on, any account that was just created can store body images and, once the
 * reading is built, ask for a paid AI reading. So the photos are born OFF and
 * are switched on per environment, by configuration.
 *
 * OFF BY DEFAULT. One lock, from the environment alone: the project ref of
 * the configured database URL is listed in
 * `MOBILE_SIGNUP_BODY_PHOTOS_PROJECT_REF` (refs separated by commas or
 * spaces), and is never the production ref, which is refused here in code
 * whatever the variable says. Absent, empty or anything else = off.
 *
 * Off, the routes answer as a server that has no photos: the state says "not
 * available" without a single query, and accepting the consent, creating a
 * photo and completing an upload answer 404. Deleting never depends on it.
 *
 * It is the same design as the two other switches of the app server (the
 * evaluation access and the on-request day close). The reading of the ref is
 * repeated here, not imported, so this module reaches nothing; a test keeps
 * the three in agreement. Being born off is a decisão do orquestrador,
 * anunciada ao dono em 2026-10-10/11, que pode riscar qualquer uma.
 */
export const SIGNUP_BODY_PHOTOS_PROJECT_REF_ENV = 'MOBILE_SIGNUP_BODY_PHOTOS_PROJECT_REF'

/** The production database. Never switched on, whatever is configured. */
const PRODUCTION_PROJECT_REF = 'xuxehkhdvjivitduarvb'

type Environment = Record<string, string | undefined>

/** The project ref of a hosted database URL (`https://<ref>.supabase.co`), or null. */
export function projectRefFromUrl(url: string | undefined): string | null {
  if (!url) return null
  try {
    const { protocol, hostname } = new URL(url)
    if (protocol !== 'https:') return null
    const match = hostname.match(/^([a-z0-9]{20})\.supabase\.co$/)
    return match?.[1] ?? null
  } catch {
    return null
  }
}

/** The lock, from the environment alone. False = off. */
export function resolveSignupBodyPhotos(env: Environment): boolean {
  const allowedRefs = (env[SIGNUP_BODY_PHOTOS_PROJECT_REF_ENV] ?? '')
    .split(/[\s,]+/)
    .map((ref) => ref.trim())
    .filter(Boolean)
  const ref = projectRefFromUrl(env.NEXT_PUBLIC_SUPABASE_URL)
  if (ref === null || ref === PRODUCTION_PROJECT_REF) return false
  // Listing the production ref is a configuration mistake: nothing is trusted.
  if (allowedRefs.includes(PRODUCTION_PROJECT_REF)) return false
  return allowedRefs.includes(ref)
}

/** The switch as the running server sees it, read at each request. */
export function signupBodyPhotosEnabled(): boolean {
  return resolveSignupBodyPhotos({
    [SIGNUP_BODY_PHOTOS_PROJECT_REF_ENV]: process.env.MOBILE_SIGNUP_BODY_PHOTOS_PROJECT_REF,
    // The same static expression the service client factory reads
    // (../supabase/server), so the lock looks at the URL the client was built
    // with even where the bundler inlines it.
    NEXT_PUBLIC_SUPABASE_URL: process.env.NEXT_PUBLIC_SUPABASE_URL,
  })
}
