import { afterEach, expect, it, vi } from 'vitest'

const env = {
  SUPABASE_URL: 'https://xitugspwfxkcluxvrdeg.supabase.co',
  SUPABASE_SERVICE_ROLE_KEY: 'synthetic-server-only',
  INNGEST_FUNCTION_SET: 'media-conversation-staging',
  MOBILE_CONVERSATION_PROCESSING_BRIDGE_ENABLED: 'true',
  MOBILE_CONVERSATION_PROCESSING_WORKER_PROJECT_ID: 'prj_0SRds3zTc57EB0sExjYPygKGEgBx',
  MOBILE_CONVERSATION_PROCESSING_SOURCE_SHA: 'c'.repeat(40),
  VERCEL_URL: 'agentempp-media-worker-staging-qa180-gestao-9664s-projects.vercel.app',
}
afterEach(() => {
  vi.unstubAllEnvs()
  vi.unstubAllGlobals()
})
it('the actual exported POST checks the oneuse capability through the pinned SDK with no admin session', async () => {
  for (const [key, value] of Object.entries(env)) vi.stubEnv(key, value)
  const calls: string[] = []
  vi.stubGlobal(
    'fetch',
    vi.fn(async (input: RequestInfo | URL, init?: RequestInit) => {
      const request = new Request(input, init),
        url = new URL(request.url)
      expect(url.origin).toBe(env.SUPABASE_URL)
      expect(url.pathname).toBe('/rest/v1/rpc/claim_conversation_media_processing_job_v2')
      expect(request.method).toBe('POST')
      calls.push(url.pathname)
      const args = await request.json()
      expect(args.p_source_sha).toBe(env.MOBILE_CONVERSATION_PROCESSING_SOURCE_SHA)
      expect(args.p_token_sha256).not.toBe('b'.repeat(64))
      return Response.json(null)
    }),
  )
  const { POST } = await import('./route')
  const reply = await POST(
    new Request('https://worker.invalid/api/internal/conversation-media/process-v2', {
      method: 'POST',
      headers: {
        'content-type': 'application/json',
        'x-performe-processing-token': 'b'.repeat(64),
      },
      body: JSON.stringify({ dispatch_id: 'c1800000-0000-4000-8000-000000000001' }),
    }),
  )
  expect(reply.status).toBe(401)
  expect(await reply.json()).toEqual({ status: 'unauthorized' })
  expect(calls).toHaveLength(1)
})
it('the actual endpoint stays OFF on an old/default worker and performs no IO', async () => {
  vi.stubEnv('INNGEST_FUNCTION_SET', 'all')
  const network = vi.fn()
  vi.stubGlobal('fetch', network)
  const { POST } = await import('./route')
  const reply = await POST(new Request('https://worker.invalid', { method: 'POST', body: '{}' }))
  expect(reply.status).toBe(503)
  expect(network).not.toHaveBeenCalled()
})

it('uses the installed SDK authenticated download path and preserves byte validation before a model', async () => {
  for (const [key, value] of Object.entries({
    ...env,
    MOBILE_CONVERSATION_PRIVATE_CATALOG_ENABLED: 'true',
    MOBILE_CONVERSATION_PHOTOS_ENABLED: 'true',
  }))
    vi.stubEnv(key, value)
  const owner = 'c1800000-0000-4000-8000-000000000003',
    asset = 'c1800000-0000-4000-8000-000000000004',
    dispatch = 'c1800000-0000-4000-8000-000000000001',
    lease = 'c1800000-0000-4000-8000-000000000002',
    requestId = 'a'.repeat(64)
  const created = new Date(Date.now() - 1000).toISOString(),
    until = new Date(Date.parse(created) + 30 * 86400_000).toISOString()
  const identity = {
    catalog_version: 2,
    user_id: owner,
    asset_id: asset,
    kind: 'conversation_photo',
    bucket_id: 'meal-photos',
    object_path: `conversation-v2/${owner}/${asset}.jpg`,
    mime_type: 'image/jpeg',
    declared_size_bytes: 8,
  }
  const paths: string[] = [],
    failures: string[] = []
  vi.stubGlobal(
    'fetch',
    vi.fn(async (input: RequestInfo | URL, init?: RequestInit) => {
      const request = new Request(input, init),
        url = new URL(request.url)
      expect(url.origin).toBe(env.SUPABASE_URL)
      paths.push(url.pathname)
      if (url.pathname.startsWith('/storage/v1/object/'))
        return new Response(new Uint8Array([255, 216, 255, 224]), {
          headers: { 'content-type': 'image/jpeg' },
        })
      const args = await request.json()
      switch (url.pathname.split('/').at(-1)) {
        case 'claim_conversation_media_processing_job_v2':
          return Response.json({
            schema: 'conversation.media-processing-dispatch.v2',
            dispatch_id: dispatch,
            job_id: 'c1800000-0000-4000-8000-000000000005',
            lease_id: lease,
            user_id: owner,
            asset_id: asset,
            request_id: requestId,
            source_sha: env.MOBILE_CONVERSATION_PROCESSING_SOURCE_SHA,
            kind: 'conversation_photo',
            expires_at: new Date(Date.now() + 300_000).toISOString(),
          })
        case 'validate_conversation_media_processing_job_v2':
          return Response.json(true)
        case 'claim_conversation_media_processing_v2':
          return Response.json({
            schema: 'conversation.media-processing-claim.v2',
            action: 'claimed',
            asset: {
              identity,
              state: { status: 'processing', created_at: created, retention_until: until },
              context_text: null,
              processing_request_id: requestId,
            },
            claim: {
              token: 'c1800000-0000-4000-8000-000000000006',
              lease_until: new Date(Date.now() + 300_000).toISOString(),
            },
          })
        case 'fail_conversation_media_processing_v2':
          failures.push(args.p_failure_code)
          return Response.json(true)
        case 'complete_conversation_media_processing_job_v2':
          return Response.json(true)
        default:
          throw Error('Unexpected IO')
      }
    }),
  )
  const { POST } = await import('./route')
  const reply = await POST(
    new Request('https://worker.invalid', {
      method: 'POST',
      headers: {
        'content-type': 'application/json',
        'x-performe-processing-token': 'b'.repeat(64),
      },
      body: JSON.stringify({ dispatch_id: dispatch }),
    }),
  )
  expect(reply.status).toBe(200)
  expect(paths).toContain(`/storage/v1/object/meal-photos/conversation-v2/${owner}/${asset}.jpg`)
  expect(failures).toEqual(['media_size_mismatch'])
})
