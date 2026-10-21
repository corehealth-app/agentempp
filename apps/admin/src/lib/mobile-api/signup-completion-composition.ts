import type { ServiceClient } from '@mpp/db'
import { MobileApiError } from './http'
import type { SignupCompletionIntentSource } from './signup-completion-intent'
import { signupCompletionIntentsEnabled } from './signup-completion-switch'
import type { SignupStrengthAuthoritySource } from './signup-strength-authority'
import { createSupabaseSignupCompletionIntentSource } from './supabase-signup-completion-intent'
import { createSupabaseSignupStrengthAuthoritySource } from './supabase-signup-strength-authority'

export interface SignupCompletionSources {
  readonly intents: SignupCompletionIntentSource
  readonly admission: Pick<SignupStrengthAuthoritySource, 'bind'>
}
export interface SignupCompletionComposition {
  enabled(): boolean
  /** Synchronous, request-scoped and without I/O. */
  createSources(client: ServiceClient): SignupCompletionSources
}

export const defaultSignupCompletionComposition: SignupCompletionComposition = Object.freeze({
  enabled: signupCompletionIntentsEnabled,
  createSources(client: ServiceClient): SignupCompletionSources {
    const authority = createSupabaseSignupStrengthAuthoritySource(client)
    return Object.freeze({
      intents: createSupabaseSignupCompletionIntentSource(client),
      admission: Object.freeze({ bind: authority.bind }),
    })
  },
})

/** Called only for explicitly versioned transport, never for an old completion. */
export function captureSignupCompletionSources(
  composition: SignupCompletionComposition | undefined,
  client: ServiceClient,
) {
  const enabled = composition?.enabled.bind(composition)
  const requireEnabled = () => {
    if (enabled?.() !== true)
      throw new MobileApiError(
        503,
        'signup_completion_unavailable',
        'Signup completion is unavailable',
      )
  }
  requireEnabled()
  // requireEnabled above rejects undefined before any source construction.
  if (!composition) throw new Error('Invalid signup completion composition')
  const sources = composition.createSources(client)
  return Object.freeze({
    requireEnabled,
    intents: Object.freeze({
      begin: sources.intents.begin.bind(sources.intents),
      resolve: sources.intents.resolve.bind(sources.intents),
      verify: sources.intents.verify.bind(sources.intents),
    }),
    admission: Object.freeze({ bind: sources.admission.bind.bind(sources.admission) }),
  })
}
