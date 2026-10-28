export type CurrentClinicalRuntimeTarget = {
  readonly mode: 'current'
  readonly storageOrigin: string
}
export type CurrentClinicalRuntimeSelection =
  | CurrentClinicalRuntimeTarget
  | { readonly mode: 'legacy' | 'unavailable' }
/** One explicit staging-only selection; a bad explicit target never falls back. */
export function resolveCurrentClinicalRuntime(
  env: Record<string, string | undefined>,
): CurrentClinicalRuntimeSelection {
  const selected = (env.MOBILE_CURRENT_CLINICAL_PROJECT_REF ?? '').trim()
  if (!selected) return Object.freeze({ mode: 'legacy' })
  const unavailable = Object.freeze({ mode: 'unavailable' as const })
  if (selected !== 'xitugspwfxkcluxvrdeg') return unavailable
  try {
    const url = new URL(env.NEXT_PUBLIC_SUPABASE_URL ?? '')
    if (
      url.protocol !== 'https:' ||
      url.hostname !== `${selected}.supabase.co` ||
      url.username ||
      url.password ||
      url.search ||
      url.hash ||
      url.port ||
      (url.pathname !== '/' && url.pathname !== '')
    )
      return unavailable
    return Object.freeze({ mode: 'current', storageOrigin: url.origin })
  } catch {
    return unavailable
  }
}
export function currentClinicalRuntimeSelection() {
  return resolveCurrentClinicalRuntime({
    NEXT_PUBLIC_SUPABASE_URL: process.env.NEXT_PUBLIC_SUPABASE_URL,
    MOBILE_CURRENT_CLINICAL_PROJECT_REF: process.env.MOBILE_CURRENT_CLINICAL_PROJECT_REF,
  })
}
