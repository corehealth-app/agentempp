import { expect, it, vi } from 'vitest'

// A direct media transport must load the processing algorithm without creating
// an Inngest client, registering jobs or composing legacy message/clinical IO.
vi.mock('../client.js', () => {
  throw new Error('Scheduler runtime loaded by private media processing')
})

it('can inspect an unavailable source without loading the scheduler or calling any IO', async () => {
  const { processPrivateConversationMedia } = await import(
    './private-conversation-media-processing.js'
  )
  const storage = { download: vi.fn() }
  const providers = { analyzeImage: vi.fn(), transcribeAudio: vi.fn() }
  const findOwned = vi.fn(),
    completeProcessing = vi.fn(),
    failProcessing = vi.fn()
  await expect(
    processPrivateConversationMedia(
      {
        catalog: {
          claimProcessing: vi.fn().mockResolvedValue({
            schema: 'conversation.media-processing-claim.v2',
            action: 'unavailable',
          }),
          findOwned,
          completeProcessing,
          failProcessing,
        },
        storage,
        providers,
        now: () => new Date('2026-11-18T03:00:00Z'),
      },
      {
        userId: 'c3672000-0000-4000-8000-000000000001',
        assetId: 'c3672000-0000-4000-8000-000000000002',
        requestId: 'a'.repeat(64),
      },
    ),
  ).resolves.toEqual({ status: 'skipped' })
  for (const operation of [
    storage.download,
    providers.analyzeImage,
    providers.transcribeAudio,
    findOwned,
    completeProcessing,
    failProcessing,
  ])
    expect(operation).not.toHaveBeenCalled()
})

it('composes the existing private provider ports without a scheduler and enforces live revocation', async () => {
  const { createPrivateMediaProcessingDependencies } = await import(
    '../lib/private-conversation-media-dependencies.js'
  )
  const { createClient } = await import('@supabase/supabase-js')
  const client = createClient('https://xitugspwfxkcluxvrdeg.supabase.co', 'synthetic-key')
  const env = {
    SUPABASE_URL: 'https://xitugspwfxkcluxvrdeg.supabase.co',
    INNGEST_FUNCTION_SET: 'media-conversation-staging',
    MOBILE_CONVERSATION_PRIVATE_CATALOG_ENABLED: 'true',
  }
  const deps = createPrivateMediaProcessingDependencies(client, env)
  expect(Number.isFinite(deps.now().getTime())).toBe(true)
  env.MOBILE_CONVERSATION_PRIVATE_CATALOG_ENABLED = 'false'
  expect(() => deps.now()).toThrow('Private media')
})
