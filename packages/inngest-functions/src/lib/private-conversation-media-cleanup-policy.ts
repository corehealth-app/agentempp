import { assertClinicalStagingWorkerTarget } from './clinical-staging-worker-target.js'

/** Cleanup remains independently enabled after stopping new uploads/models.
 * Only the explicit existing conversational staging worker can opt in. */
export function assertPrivateConversationMediaCleanup(
  env: Readonly<Record<string, string | undefined>> = process.env,
): void {
  assertClinicalStagingWorkerTarget(env, 'media-conversation-staging')
  if (env.MOBILE_CONVERSATION_PRIVATE_DISPOSAL_ENABLED !== 'true')
    throw Error('Private conversation media cleanup unavailable')
}

export function privateConversationMediaCleanupEnabled(): boolean {
  try {
    assertPrivateConversationMediaCleanup()
    return true
  } catch {
    return false
  }
}
