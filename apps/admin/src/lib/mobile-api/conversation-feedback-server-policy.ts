import { resolveCurrentClinicalRuntime } from './current-clinical-runtime-switch'
/** Canonical selection is server-only, default OFF and staging-only. A request
 * header controls presentation compatibility and is never consulted here. */
export function conversationFeedbackV3WriterEnabled(
  env: Record<string, string | undefined> = process.env,
): boolean {
  return (
    env.MOBILE_CONVERSATION_FEEDBACK_VERSION === '3' &&
    resolveCurrentClinicalRuntime(env).mode === 'current'
  )
}
