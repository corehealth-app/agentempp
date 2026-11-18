import type { Database } from '@mpp/db'
import { createPrivateMediaTransportHandler } from '@mpp/inngest-functions/private-media-processing-transport'
import { createClient } from '@supabase/supabase-js'

const origin = 'https://xitugspwfxkcluxvrdeg.supabase.co'
const allowedRpc = new Set([
  'register_conversation_media_processing_transport_v2',
  'claim_conversation_media_processing_job_v2',
  'validate_conversation_media_processing_job_v2',
  'complete_conversation_media_processing_job_v2',
  'claim_conversation_media_processing_v2',
  'get_conversation_media_asset_v2',
  'complete_conversation_media_processing_v2',
  'fail_conversation_media_processing_v2',
])

const handle = createPrivateMediaTransportHandler({
  env: process.env,
  createClient({ signal, assertActive }) {
    const key = process.env.SUPABASE_SERVICE_ROLE_KEY
    if (!key) throw Error('Private processing unavailable')
    return createClient<Database>(origin, key, {
      auth: { persistSession: false, autoRefreshToken: false, detectSessionInUrl: false },
      global: {
        async fetch(input, init) {
          assertActive()
          const request = new Request(input, init),
            url = new URL(request.url)
          const rpc =
            request.method === 'POST' &&
            url.pathname.startsWith('/rest/v1/rpc/') &&
            allowedRpc.has(url.pathname.slice('/rest/v1/rpc/'.length))
          const config =
            request.method === 'GET' &&
            ((url.pathname === '/rest/v1/global_config' &&
              url.searchParams.get('key') === 'like.vision.%' &&
              url.searchParams.get('select') === 'key,value') ||
              (url.pathname === '/rest/v1/agent_rules' &&
                url.searchParams.get('slug') === 'like.vision-%' &&
                url.searchParams.get('status') === 'eq.active' &&
                url.searchParams.get('select') === 'slug,content'))
          const media =
            request.method === 'GET' &&
            /^\/storage\/v1\/object\/(?:meal-photos|audio-notes)\/conversation-v2\/[0-9a-f-]{36}\/[0-9a-f-]{36}\.(?:jpg|png|webp|heic|heif|mp3|m4a|aac|wav|ogg)$/.test(
              url.pathname,
            )
          if (url.origin !== origin || !(rpc || config || media))
            throw Error('Private processing unavailable')
          const reply = await fetch(request, {
            signal: AbortSignal.any([signal, request.signal]),
            redirect: 'error',
          })
          assertActive()
          return reply
        },
      },
    })
  },
})

export const runtime = 'nodejs'
export const maxDuration = 300
export const POST = (request: Request) => handle(request)
