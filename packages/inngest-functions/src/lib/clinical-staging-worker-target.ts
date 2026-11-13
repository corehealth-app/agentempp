/** The explicit clinical/conversational worker sets only use this staging database.
 * This checks the same precedence as createWorkerSupabase, including an empty
 * explicit SUPABASE_URL. It is not proof of Inngest environment isolation. */
export function assertClinicalStagingWorkerTarget(
  env: Readonly<Record<string, string | undefined>> = process.env,
  expectedSet?: string,
): void {
  const target = env.SUPABASE_URL ?? env.NEXT_PUBLIC_SUPABASE_URL
  const origin = 'https://xitugspwfxkcluxvrdeg.supabase.co'
  if (
    !['media-clinical-staging', 'media-conversation-staging'].includes(
      env.INNGEST_FUNCTION_SET ?? '',
    ) ||
    (expectedSet !== undefined && env.INNGEST_FUNCTION_SET !== expectedSet) ||
    (target !== origin && target !== `${origin}/`)
  ) {
    // Do not include URLs, owners, credentials or provider responses in errors.
    throw new Error('Clinical staging worker target unavailable')
  }
}
