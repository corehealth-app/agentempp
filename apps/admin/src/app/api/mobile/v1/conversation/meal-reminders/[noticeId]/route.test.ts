import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import type { MobileRouteContext } from '@/lib/mobile-api/route'

type RouteParams = { params: Promise<{ noticeId: string }> }
type Handler = (context: MobileRouteContext, params: RouteParams) => Promise<Response>
const boundary = vi.hoisted(() => ({ handler: null as Handler | null }))
vi.mock('@/lib/mobile-api/route', () => ({
  createMobileRouteWithContext: (handler: Handler) => {
    boundary.handler = handler
  },
}))
import './route'

const id = '19000000-0000-4000-8000-000000001110'
const owner = '19000000-0000-4000-8000-000000001100'
const fixture = {
  id,
  local_date: '2026-11-26',
  meal_type: 'jantar',
  state: 'pending',
}
const rpc = vi.fn()

function getNotice(noticeId = id) {
  const request = new Request(
    `https://example.test/api/mobile/v1/conversation/meal-reminders/${noticeId}`,
    { headers: { 'X-Conversation-Owner': 'user-supplied-owner' } },
  )
  const context = {
    request,
    requestId: 'reminder-test',
    auth: { userId: owner },
    supabase: { rpc },
  } as unknown as MobileRouteContext
  if (!boundary.handler) throw new Error('Meal reminder route did not register')
  return boundary.handler(context, { params: Promise.resolve({ noticeId }) })
}

describe('Flow meal reminder read', () => {
  beforeEach(() => {
    vi.stubEnv('MOBILE_FLOW_MEAL_GAP_PUSH_ENABLED', 'true')
    vi.stubEnv('NEXT_PUBLIC_SUPABASE_URL', 'https://xitugspwfxkcluxvrdeg.supabase.co')
    rpc.mockReset()
  })
  afterEach(() => vi.unstubAllEnvs())

  it('uses the authenticated owner and strips internal details from the response', async () => {
    rpc.mockResolvedValue({ data: { ...fixture, device_id: 'private-device-id' }, error: null })
    const response = await getNotice()
    expect(response.status).toBe(200)
    expect((await response.json()).data).toEqual(fixture)
    expect(rpc).toHaveBeenCalledWith('read_flow_meal_gap_notice', {
      p_user_id: owner,
      p_notice_id: id,
    })
  })

  it('treats absent and foreign notices the same', async () => {
    rpc.mockResolvedValue({ data: null, error: null })
    await expect(getNotice()).rejects.toMatchObject({ status: 404 })
  })

  it('rejects a result for a different notice', async () => {
    rpc.mockResolvedValue({ data: { ...fixture, id: owner }, error: null })
    await expect(getNotice()).rejects.toMatchObject({ status: 500 })
  })

  it('cannot reach the RPC while disabled or on a different database', async () => {
    vi.stubEnv('MOBILE_FLOW_MEAL_GAP_PUSH_ENABLED', 'false')
    await expect(getNotice()).rejects.toMatchObject({ status: 503 })
    vi.stubEnv('MOBILE_FLOW_MEAL_GAP_PUSH_ENABLED', 'true')
    vi.stubEnv('NEXT_PUBLIC_SUPABASE_URL', 'https://unrelated.example.test')
    await expect(getNotice()).rejects.toMatchObject({ status: 503 })
    expect(rpc).not.toHaveBeenCalled()
  })
})
