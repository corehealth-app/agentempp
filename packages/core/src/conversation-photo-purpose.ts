/** Trusted server opt-in only; a client kind/header cannot activate a purpose. */
const origin = 'https://xitugspwfxkcluxvrdeg.supabase.co'
const target = (value: string | undefined) => value === origin || value === `${origin}/`
export function conversationPhotoMobileEnabled(
  env: Readonly<Record<string, string | undefined>> = process.env,
): boolean {
  return (
    env.MOBILE_CONVERSATION_PHOTOS_ENABLED === 'true' &&
    env.MOBILE_CONVERSATION_INTAKES_ENABLED === 'true' &&
    env.MOBILE_CURRENT_CLINICAL_PROJECT_REF === 'xitugspwfxkcluxvrdeg' &&
    target(env.NEXT_PUBLIC_SUPABASE_URL)
  )
}
export function conversationPhotoWorkerEnabled(
  env: Readonly<Record<string, string | undefined>> = process.env,
): boolean {
  return (
    env.MOBILE_CONVERSATION_PHOTOS_ENABLED === 'true' &&
    env.INNGEST_FUNCTION_SET === 'media-clinical-staging' &&
    target(env.SUPABASE_URL ?? env.NEXT_PUBLIC_SUPABASE_URL)
  )
}
