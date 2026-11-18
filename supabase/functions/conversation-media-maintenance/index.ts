// Cleanup-only entrypoint. maintenance.js is produced from the tested shared
// source by scripts/build-conversation-media-maintenance.mjs; never hand-edit it.
import { createClient } from 'npm:@supabase/supabase-js@2.105.1'
import { createConversationMediaMaintenanceHandler } from './maintenance.js'

const origin = 'https://xitugspwfxkcluxvrdeg.supabase.co'
const handle = createConversationMediaMaintenanceHandler({
  env: {
    SUPABASE_URL: Deno.env.get('SUPABASE_URL'),
    // This entrypoint can request a lease, not enable the bridge. SQL starts
    // OFF; the operator must qualify it before scheduling or authorizing jobs.
    MOBILE_CONVERSATION_MAINTENANCE_BRIDGE_ENABLED: 'true',
  },
  createClient({ signal, assertActive }: { signal: AbortSignal; assertActive(): void }) {
    const key = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')
    if (!key) throw Error('Maintenance unavailable')
    return createClient(origin, key, {
      auth: { persistSession: false, autoRefreshToken: false },
      global: {
        async fetch(input, init) {
          assertActive()
          const request = new Request(input, init)
          const url = new URL(request.url)
          const rpc = url.pathname.startsWith('/rest/v1/rpc/') && request.method === 'POST'
          const table =
            ['/rest/v1/users', '/rest/v1/media_assets'].includes(url.pathname) &&
            ['GET', 'DELETE'].includes(request.method)
          const storage =
            url.pathname.startsWith('/storage/v1/object/') &&
            ['POST', 'DELETE'].includes(request.method)
          if (url.origin !== origin || !(rpc || table || storage))
            throw Error('Maintenance unavailable')
          const result = await fetch(request, {
            signal: AbortSignal.any([signal, request.signal]),
          })
          assertActive()
          return result
        },
      },
    })
  },
})
Deno.serve(handle)
