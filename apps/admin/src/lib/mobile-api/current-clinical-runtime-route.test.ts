import { describe, expect, it, vi } from 'vitest'
import { selectCurrentClinicalRoute } from './current-clinical-runtime-route'
import type { CurrentClinicalRuntimeSelection } from './current-clinical-runtime-switch'

const request = (query = '') =>
  new Request(`https://app.example.invalid/api/mobile/v1/today${query}`)
describe('complete current route selection', () => {
  it('preserves the legacy route only when current is not selected or requested', async () => {
    const legacy = vi.fn(async () => new Response('legacy')),
      current = vi.fn()
    const route = selectCurrentClinicalRoute(current, legacy, () => ({ mode: 'legacy' }))
    expect(await (await route(request())).text()).toBe('legacy')
    expect(legacy).toHaveBeenCalledTimes(1)
    expect(current).not.toHaveBeenCalled()
  })
  it.each([
    'legacy',
    'unavailable',
  ] as const)('never dispatches a current request through legacy while %s', async (mode) => {
    const legacy = vi.fn(),
      current = vi.fn()
    const route = selectCurrentClinicalRoute(current, legacy, () => ({ mode }))
    expect((await route(request('?clinical_policy=current_clinical_v1'))).status).toBe(503)
    expect(legacy).not.toHaveBeenCalled()
    expect(current).not.toHaveBeenCalled()
  })
  it('rejects a bad explicit target even for an old client without constructing either family', async () => {
    const legacy = vi.fn(),
      current = vi.fn()
    expect(
      (
        await selectCurrentClinicalRoute(current, legacy, () => ({ mode: 'unavailable' }))(
          request(),
        )
      ).status,
    ).toBe(503)
    expect(legacy).not.toHaveBeenCalled()
    expect(current).not.toHaveBeenCalled()
  })
  it('validates incompatible negotiation before any legacy effect', async () => {
    const legacy = vi.fn(),
      current = vi.fn()
    const route = selectCurrentClinicalRoute(current, legacy, () => ({ mode: 'legacy' }))
    expect((await route(request('?clinical_policy=unknown'))).status).toBe(400)
    expect(legacy).not.toHaveBeenCalled()
    expect(current).not.toHaveBeenCalled()
  })
  it('binds one current target and preserves the dynamic route arguments', async () => {
    const selected: CurrentClinicalRuntimeSelection = {
      mode: 'current',
      storageOrigin: 'https://xitugspwfxkcluxvrdeg.supabase.co',
    }
    const handler = vi.fn(
      async (_request: Request, context: { id: string }) => new Response(context.id),
    )
    const current = vi.fn(() => handler),
      legacy = vi.fn()
    const route = selectCurrentClinicalRoute(current, legacy, () => selected)
    const context = { id: 'original-cycle' }
    expect(await (await route(request(), context)).text()).toBe('original-cycle')
    expect(current).toHaveBeenCalledTimes(1)
    expect(current).toHaveBeenCalledWith(selected)
    expect(handler).toHaveBeenCalledTimes(1)
    expect(handler).toHaveBeenCalledWith(expect.any(Request), context)
    expect(legacy).not.toHaveBeenCalled()
  })
})
