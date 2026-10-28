/** The new clinical worker set may only use this project's staging database.
 * This checks the same precedence as createWorkerSupabase, including an empty
 * explicit SUPABASE_URL. It is not proof of Inngest environment isolation. */
export function assertClinicalStagingWorkerTarget(
  env: Readonly<Record<string, string | undefined>> = process.env,
): void {
  const target = env.SUPABASE_URL ?? env.NEXT_PUBLIC_SUPABASE_URL
  const origin = 'https://xitugspwfxkcluxvrdeg.supabase.co'
  if (
    env.INNGEST_FUNCTION_SET !== 'media-clinical-staging' ||
    (target !== origin && target !== `${origin}/`)
  ) {
    // Do not include URLs, owners, credentials or provider responses in errors.
    throw new Error('Clinical staging worker target unavailable')
  }
}
