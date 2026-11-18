import type { ServiceClient } from '@mpp/db'
import { createClient } from '@supabase/supabase-js'
import { afterEach, describe, expect, it, vi } from 'vitest'
import { createPrivateMediaTransportHandler } from './private-conversation-media-transport.js'

const origin = 'https://xitugspwfxkcluxvrdeg.supabase.co'
const dispatch = 'c1800000-0000-4000-8000-000000000001'
const lease = 'c1800000-0000-4000-8000-000000000002'
const owner = 'c1800000-0000-4000-8000-000000000003'
const asset = 'c1800000-0000-4000-8000-000000000004'
const job = 'c1800000-0000-4000-8000-000000000005'
const source = 'c'.repeat(40),
  token = 'b'.repeat(64)
const at = Date.parse('2026-11-18T04:00:00Z')
const environment = {
  SUPABASE_URL: origin,
  INNGEST_FUNCTION_SET: 'media-conversation-staging',
  MOBILE_CONVERSATION_PRIVATE_CATALOG_ENABLED: 'true',
  MOBILE_CONVERSATION_PROCESSING_BRIDGE_ENABLED: 'true',
  MOBILE_CONVERSATION_PROCESSING_SOURCE_SHA: source,
  MOBILE_CONVERSATION_PROCESSING_WORKER_PROJECT_ID: 'prj_0SRds3zTc57EB0sExjYPygKGEgBx',
  VERCEL_URL: 'agentempp-media-worker-staging-qa180-gestao-9664s-projects.vercel.app',
  VERCEL_AUTOMATION_BYPASS_SECRET: 'synthetic-bypass-only',
}
function setup(
  options: {
    grant?: unknown
    completion?: unknown
    busy?: boolean
    env?: Partial<typeof environment>
  } = {},
) {
  const calls: Array<{ name: string; args: Record<string, unknown> }> = []
  const env = { ...environment, ...options.env }
  const create = vi.fn(
    ({ signal }: { signal: AbortSignal }) =>
      createClient(origin, 'synthetic-key', {
        auth: { persistSession: false, autoRefreshToken: false },
        global: {
          fetch: async (input, init) => {
            const req = new Request(input, init),
              url = new URL(req.url)
            expect(url.origin).toBe(origin)
            expect(signal.aborted).toBe(false)
            const name = url.pathname.replace('/rest/v1/rpc/', '')
            const args = (await req.json()) as Record<string, unknown>
            calls.push({ name, args })
            switch (name) {
              case 'register_conversation_media_processing_transport_v2':
                return Response.json(true)
              case 'claim_conversation_media_processing_job_v2':
                return Response.json(
                  options.grant === undefined
                    ? {
                        schema: 'conversation.media-processing-dispatch.v2',
                        dispatch_id: dispatch,
                        job_id: job,
                        lease_id: lease,
                        user_id: owner,
                        asset_id: asset,
                        request_id: 'a'.repeat(64),
                        source_sha: source,
                        kind: 'audio_note',
                        expires_at: new Date(at + 300_000).toISOString(),
                      }
                    : options.grant,
                )
              case 'validate_conversation_media_processing_job_v2':
                return Response.json(true)
              case 'complete_conversation_media_processing_job_v2':
                return Response.json(options.completion ?? true)
              case 'claim_conversation_media_processing_v2':
                return Response.json(
                  options.busy
                    ? {
                        schema: 'conversation.media-processing-claim.v2',
                        action: 'busy',
                        retry_at: new Date(at + 240_000).toISOString(),
                      }
                    : { schema: 'conversation.media-processing-claim.v2', action: 'unavailable' },
                )
              default:
                throw Error('Unexpected IO')
            }
          },
        },
      }) as unknown as ServiceClient,
  )
  const handler = createPrivateMediaTransportHandler({ env, createClient: create, now: () => at })
  const request = (
    body: unknown = { dispatch_id: dispatch },
    headers: Record<string, string> = {},
  ) =>
    new Request('https://worker.invalid/api/internal/conversation-media/process-v2', {
      method: 'POST',
      headers: {
        'content-type': 'application/json',
        'x-performe-processing-token': token,
        ...headers,
      },
      body: JSON.stringify(body),
    })
  return { handler, request, calls, create, env }
}
afterEach(() => {
  vi.useRealTimers()
  vi.unstubAllEnvs()
})
describe('private processing direct transport', () => {
  it.each([
    { MOBILE_CONVERSATION_PROCESSING_BRIDGE_ENABLED: 'false' },
    { SUPABASE_URL: 'https://foreign.supabase.co' },
    { INNGEST_FUNCTION_SET: 'all' },
    { MOBILE_CONVERSATION_PROCESSING_SOURCE_SHA: '' },
    { MOBILE_CONVERSATION_PROCESSING_WORKER_PROJECT_ID: 'foreign' },
    { VERCEL_URL: 'foreign.vercel.app' },
  ])('refuses unqualified target %j before composing a client', async (env) => {
    const x = setup({ env })
    expect((await x.handler(x.request())).status).toBe(503)
    expect(x.create).not.toHaveBeenCalled()
  })
  it.each([
    [{ dispatch_id: dispatch, user_id: owner }, {}],
    [{ dispatch_id: 'not-uuid' }, {}],
    [{ dispatch_id: dispatch }, { 'x-performe-processing-token': 'bad' }],
    [{ dispatch_id: dispatch }, { 'content-length': '257' }],
    [{ dispatch_id: dispatch }, { 'content-type': 'text/plain' }],
  ] as const)('refuses untrusted body/header %j', async (body, headers) => {
    const x = setup()
    expect((await x.handler(x.request(body, headers))).status).toBe(400)
    expect(x.create).not.toHaveBeenCalled()
  })
  it('denies unknown or consumed capabilities without a processing call', async () => {
    const x = setup({ grant: null })
    expect((await x.handler(x.request())).status).toBe(401)
    expect(x.calls.map((x) => x.name)).toEqual(['claim_conversation_media_processing_job_v2'])
    expect(x.calls[0]?.args.p_token_sha256).not.toBe(token)
  })
  it('completes an already unavailable core source without Storage, provider or factual writer', async () => {
    const x = setup()
    const response = await x.handler(x.request())
    expect(response.status).toBe(200)
    expect(await response.json()).toEqual({ status: 'completed' })
    expect(
      x.calls.filter((x) => x.name === 'claim_conversation_media_processing_v2')[0]?.args,
    ).toEqual({ p_user_id: owner, p_asset_id: asset, p_request_id: 'a'.repeat(64) })
    expect(x.calls.at(-1)).toMatchObject({
      name: 'complete_conversation_media_processing_job_v2',
      args: { p_outcome: 'completed', p_dispatch_id: dispatch, p_lease_id: lease },
    })
  })
  it('defers a core lease without memoizing busy as completed', async () => {
    const x = setup({ busy: true })
    expect((await x.handler(x.request())).status).toBe(200)
    expect(x.calls.at(-1)).toMatchObject({
      args: { p_outcome: 'defer', p_retry_at: new Date(at + 241_000).toISOString() },
    })
  })
  it('defers featureOFF before claiming a core source and without spending a retry', async () => {
    const x = setup({ env: { MOBILE_CONVERSATION_PRIVATE_CATALOG_ENABLED: 'false' } })
    expect((await x.handler(x.request())).status).toBe(200)
    expect(x.calls.some((x) => x.name === 'claim_conversation_media_processing_v2')).toBe(false)
    expect(x.calls.at(-1)).toMatchObject({ args: { p_outcome: 'defer' } })
  })
  it('does not overwrite a lost completion acknowledgement with a retry', async () => {
    const x = setup({ completion: false })
    expect((await x.handler(x.request())).status).toBe(503)
    expect(
      x.calls.filter((x) => x.name === 'complete_conversation_media_processing_job_v2'),
    ).toHaveLength(1)
  })
  it('registers only its own runtime target/source and existing credential under a hashed setup capability', async () => {
    const x = setup()
    expect((await x.handler(x.request({ setup: true }))).status).toBe(200)
    expect(x.calls).toHaveLength(1)
    expect(x.calls[0]).toMatchObject({
      name: 'register_conversation_media_processing_transport_v2',
      args: {
        p_target_url: `https://${environment.VERCEL_URL}`,
        p_source_sha: source,
        p_bypass_secret: environment.VERCEL_AUTOMATION_BYPASS_SECRET,
      },
    })
    expect(x.calls[0]?.args.p_setup_token_sha256).not.toBe(token)
  })
})

it('bounds a stalled chunked body even if cancelling its untrusted stream never settles', async () => {
  vi.useFakeTimers()
  const x = setup()
  const init: RequestInit & { duplex: 'half' } = {
    method: 'POST',
    duplex: 'half',
    headers: { 'content-type': 'application/json', 'x-performe-processing-token': token },
    body: new ReadableStream<Uint8Array>({
      pull: () => new Promise(() => {}),
      cancel: () => new Promise(() => {}),
    }),
  }
  const pending = x.handler(new Request('https://worker.invalid', init))
  let settled = false
  void pending.then(() => {
    settled = true
  })
  await vi.advanceTimersByTimeAsync(5001)
  expect(settled).toBe(true)
  expect((await pending).status).toBe(400)
  expect(x.create).not.toHaveBeenCalled()
})
