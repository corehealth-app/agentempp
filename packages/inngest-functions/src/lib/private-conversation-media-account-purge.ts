import type { ServiceClient } from '@mpp/db'
import {
  createPurgeDependencies,
  type UserDeletionPurgeDependencies,
} from '../functions/user-deletion-purger.js'
import { assertPrivateConversationMediaCleanup } from './private-conversation-media-cleanup-policy.js'
import { createPrivateMediaDisposalV2 } from './private-conversation-media-disposal.js'

/** Add private readiness ahead of the existing legacy/recurring coordinator.
 * No account or frozen record is removed until every independent protocol is
 * ready. The original cutoff, batch, row filters and delete remain unchanged. */
export function createPrivateConversationPurgeDependencies(
  client: ServiceClient,
): UserDeletionPurgeDependencies {
  const guard = assertPrivateConversationMediaCleanup
  guard()
  const legacy = createPurgeDependencies(client, { conversationMedia: true })
  const privateMedia = createPrivateMediaDisposalV2(client, guard)
  async function checked<T>(action: () => Promise<T>): Promise<T> {
    guard()
    const result = await action()
    guard()
    return result
  }
  return {
    repository: {
      listUsersReadyForPurge: (cutoff, limit) =>
        checked(() => legacy.repository.listUsersReadyForPurge(cutoff, limit)),
      async prepareConversationMediaPurge(userId, cutoff) {
        if (!(await checked(() => privateMedia.prepareAccountPurge(userId, cutoff)))) return false
        // The explicit constructor guarantees the legacy prerequisite exists.
        const prepare = legacy.repository.prepareConversationMediaPurge
        if (!prepare) throw Error('Private conversation account purge unavailable')
        return checked(() => prepare(userId, cutoff))
      },
      prepareRecurringMediaPurge: (userId, cutoff) =>
        checked(() => legacy.repository.prepareRecurringMediaPurge(userId, cutoff)),
      listUserMedia: (userId) => checked(() => legacy.repository.listUserMedia(userId)),
      deleteUserMediaCatalog: (userId) =>
        checked(() => legacy.repository.deleteUserMediaCatalog(userId)),
      deleteUser: (userId, cutoff) => checked(() => legacy.repository.deleteUser(userId, cutoff)),
    },
    storage: {
      remove: (bucket, path) => checked(() => legacy.storage.remove(bucket, path)),
    },
  }
}
