import type { ServiceClient } from '@mpp/db'
import { describe, expect, it, vi } from 'vitest'
import { createCurrentVisionConfigLoader } from './current-vision-runtime-config'

const A = 'https://aaaaaaaaaaaaaaaaaaaa.supabase.co',
  B = 'https://bbbbbbbbbbbbbbbbbbbb.supabase.co'
function client(result: (table: string) => { data: unknown; error: unknown }) {
  const from = vi.fn((table: string) => {
    const q = {
      select: vi.fn(() => q),
      like: vi.fn(() => q),
      eq: vi.fn(() => q),
      // biome-ignore lint/suspicious/noThenProperty: Supabase builders are intentionally thenable.
      then: (resolve: (value: unknown) => unknown, reject: (error: unknown) => unknown) =>
        Promise.resolve(result(table)).then(resolve, reject),
    }
    return q
  })
  return { client: { from } as unknown as ServiceClient, from }
}
describe('BFF configured Vision loader', () => {
  it('keeps worker defaults and configured active prompt overrides', async () => {
    const c = client((t) => ({
      data:
        t === 'global_config'
          ? [
              { key: 'vision.model', value: 'custom/model' },
              { key: 'vision.meal.confidence_threshold', value: '0.8' },
            ]
          : [
              { slug: 'vision-body', content: 'body prompt' },
              { slug: 'vision-unknown', content: 'ignored' },
            ],
      error: null,
    }))
    expect(await createCurrentVisionConfigLoader()(c.client, A)).toEqual({
      model: 'custom/model',
      nutrition_label_model: 'anthropic/claude-sonnet-4.6',
      meal_confidence_threshold: 0.8,
      prompts: { body: 'body prompt' },
    })
    expect(c.from).toHaveBeenCalledTimes(2)
  })
  it('uses the Gemini default rather than the provider class default', async () => {
    const c = client(() => ({ data: [], error: null }))
    expect(await createCurrentVisionConfigLoader()(c.client, A)).toMatchObject({
      model: 'google/gemini-2.5-flash',
      meal_confidence_threshold: 0.6,
    })
  })
  it('expires after60s and does not renew stale LKG on refresh failure', async () => {
    let now = 0,
      failed = false
    const load = createCurrentVisionConfigLoader(() => now)
    const c = client(() => ({ data: [], error: failed ? new Error('offline') : null }))
    const original = await load(c.client, A)
    now = 59999
    expect(await load(c.client, A)).toBe(original)
    expect(c.from).toHaveBeenCalledTimes(2)
    now = 60001
    failed = true
    expect(await load(c.client, A)).toBe(original)
    expect(c.from).toHaveBeenCalledTimes(3)
    now = 60002
    expect(await load(c.client, A)).toBe(original)
    expect(c.from).toHaveBeenCalledTimes(4)
  })
  it.each([
    'global_config',
    'agent_rules',
  ])('fails without last-known-good if %s fails', async (table) => {
    const c = client((t) => ({ data: [], error: t === table ? new Error('failed') : null }))
    await expect(createCurrentVisionConfigLoader()(c.client, A)).rejects.toThrow()
  })
  it('never supplies originA last-known-good to originB', async () => {
    const load = createCurrentVisionConfigLoader(),
      a = client(() => ({ data: [], error: null })),
      b = client(() => ({ data: null, error: new Error('offline') }))
    await load(a.client, A)
    await expect(load(b.client, B)).rejects.toThrow()
    expect(b.from).toHaveBeenCalledTimes(1)
  })
  it('refuses unsafe cache origins before querying', async () => {
    const c = client(() => ({ data: [], error: null }))
    await expect(
      createCurrentVisionConfigLoader()(
        c.client,
        'https://user:synthetic@aaaaaaaaaaaaaaaaaaaa.supabase.co',
      ),
    ).rejects.toThrow()
    expect(c.from).not.toHaveBeenCalled()
  })
})
