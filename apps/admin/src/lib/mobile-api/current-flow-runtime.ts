import {
  createCurrentClinicalAdmission,
  createSupabaseLegacyClinicalAdmissionSource,
} from './current-clinical-admission'
import { createCurrentClinicalRuntimeReadDependencies } from './current-clinical-read-runtime'
import { createSupabaseCurrentFlowDraftAuthority } from './current-flow-draft-authority'
import { createSupabaseCurrentFlowDraftLookup } from './current-flow-draft-shortcut'
import { createCurrentFlowRoutes } from './current-flow-http'
import { createFlowAgent } from './flow-agent-factory'
import { createSupabaseFlowChatStore, loadFlowHistory, sendFlowMessage } from './flow-chat-service'
import { createSupabaseFlowPhraseReplyStore } from './flow-phrase-reply-store'
import { executeSupabaseIdempotent } from './idempotency'
import { createSupabaseCurrentClinicalStateSource } from './supabase-current-clinical-state'
import { readSupabaseCurrentFlowPeriodRows } from './supabase-current-flow-period'
export function createCurrentFlowRuntimeRoutes() {
  return createCurrentFlowRoutes({
    enabled: true,
    createDependencies(client, owner) {
      const admission = createCurrentClinicalAdmission(
        createSupabaseLegacyClinicalAdmissionSource(client),
      )
      return {
        clinical: {
          ...createCurrentClinicalRuntimeReadDependencies(admission),
          admission,
          state: createSupabaseCurrentClinicalStateSource(client),
          drafts: createSupabaseCurrentFlowDraftAuthority(client, owner),
          periodRows: readSupabaseCurrentFlowPeriodRows,
        },
        createChatDependencies(context, clinical) {
          return {
            store: createSupabaseFlowChatStore(context.supabase),
            drafts: createSupabaseCurrentFlowDraftLookup(context.supabase, owner),
            agent: createFlowAgent(context, clinical),
            phraseReplies: createSupabaseFlowPhraseReplyStore(context.supabase),
          }
        },
        loadHistory: loadFlowHistory,
        sendMessage: sendFlowMessage,
        executeIdempotent: executeSupabaseIdempotent,
        now: () => new Date(),
      }
    },
  })
}
