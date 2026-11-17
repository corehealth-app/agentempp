import { createPrivateMediaSingleDisposal } from './private-conversation-media-disposal'
import type { MobileRouteContext } from './route'
import { versionedOwnedMediaResponse } from './versioned-media-owned-response'

/** The DELETE entry alone supplies a single-source byte revocation capability.
 * Trusted catalog proof and owner binding happen before it can perform IO. */
export function versionedMediaDisposalResponse(
  context: MobileRouteContext,
  assetId: string,
  legacy: () => Promise<Response>,
  env: Readonly<Record<string, string | undefined>> = process.env,
): Promise<Response> {
  return versionedOwnedMediaResponse(context, assetId, 'delete', legacy, env, undefined, {
    dispose: (identity) => createPrivateMediaSingleDisposal(context.supabase).dispose(identity),
  })
}
