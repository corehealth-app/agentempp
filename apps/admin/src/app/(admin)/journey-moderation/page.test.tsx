import { renderToStaticMarkup } from 'react-dom/server'
import { beforeEach, describe, expect, it, vi } from 'vitest'

const state = vi.hoisted(() => ({ allowed: false, calls: [] as string[], unavailable: true }))
vi.mock('@/lib/admin-page-guard', () => ({
  guardAdminPage: async (path: string) => {
    state.calls.push(path)
    return state.allowed
      ? { ok: true, admin: { role: 'operations_admin' } }
      : { ok: false, reason: 'role', admin: { role: 'support' } }
  },
}))
vi.mock('./actions', () => ({
  journeyModerationAction: async () => {
    state.calls.push('bootstrap')
    return state.unavailable
      ? { ok: false, code: 'unavailable' }
      : {
          ok: true,
          type: 'queue',
          context: {
            origin: 'https://admin.example.invalid',
            owner: 'a'.repeat(64),
            login: 'b'.repeat(64),
          },
          value: { entries: [], next_cursor: null },
        }
  },
}))
vi.mock('./connected-panel', () => ({
  ConnectedModerationPanel: () => <div>Fila operacional</div>,
}))

import JourneyModerationPage from './page'

beforeEach(() => {
  state.allowed = false
  state.unavailable = true
  state.calls = []
})
describe('guarded operational page', () => {
  it('refuses a direct page before any operational bootstrap', async () => {
    const page = await JourneyModerationPage()
    const html = renderToStaticMarkup(page)
    expect(state.calls).toEqual(['/journey-moderation'])
    expect(html).toContain('Não autorizado')
    expect(html).not.toContain('Fila operacional')
  })
  it('keeps capability off with an explicit preparation state', async () => {
    state.allowed = true
    const html = renderToStaticMarkup(await JourneyModerationPage())
    expect(state.calls).toEqual(['/journey-moderation', 'bootstrap'])
    expect(html).toContain('em preparação')
    expect(html).not.toContain('Fila operacional')
  })
  it('mounts the real connected panel only after operational bootstrap', async () => {
    state.allowed = true
    state.unavailable = false
    const html = renderToStaticMarkup(await JourneyModerationPage())
    expect(html).toContain('Fila operacional')
    expect(state.calls).toEqual(['/journey-moderation', 'bootstrap'])
  })
})
