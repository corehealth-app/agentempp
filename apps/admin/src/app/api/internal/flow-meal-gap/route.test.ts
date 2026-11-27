import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import { isSelfAuthenticatedApiPath } from '@/lib/public-api-path'
import { POST } from './route'

const { claim, run } = vi.hoisted(() => ({ claim: vi.fn(), run: vi.fn() }))
vi.mock('@mpp/inngest-functions/flow-meal-gap-push', () => ({
  claimFlowMealGapCron: claim,
  runFlowMealGapPush: run,
}))

const path = '/api/internal/flow-meal-gap'
const host = 'agentempp-media-worker-staging-check-gestao-9664s-projects.vercel.app'
const token = '1'.repeat(64)

function request(proof?: string) {
  return new Request(`https://${host}${path}`, {
    method: 'POST',
    headers: proof ? { 'x-performe-meal-gap-token': proof } : {},
  })
}

beforeEach(() => {
  vi.clearAllMocks()
  vi.stubEnv('INNGEST_FUNCTION_SET', 'media-conversation-staging')
  vi.stubEnv('MOBILE_FLOW_MEAL_GAP_PUSH_ENABLED', 'true')
  vi.stubEnv('MOBILE_FLOW_MEAL_GAP_TRANSPORT', 'supabase-cron')
  vi.stubEnv('VERCEL_URL', host)
  vi.stubEnv('SUPABASE_URL', 'https://xitugspwfxkcluxvrdeg.supabase.co')
})
afterEach(() => vi.unstubAllEnvs())

describe('Flow meal reminder cron', () => {
  it('only exempts the exact signed endpoint from admin cookie auth', () => {
    expect(isSelfAuthenticatedApiPath(path)).toBe(true)
    expect(isSelfAuthenticatedApiPath(`${path}/other`)).toBe(false)
  })

  it('refuses requests outside the staging worker before checking credentials', async () => {
    vi.stubEnv('SUPABASE_URL', 'https://xuxehkhdvjivitduarvb.supabase.co')
    expect((await POST(request(token))).status).toBe(404)
    expect(claim).not.toHaveBeenCalled()
  })

  it('refuses a request without a valid, unspent dispatch', async () => {
    expect((await POST(request())).status).toBe(401)
    expect(claim).not.toHaveBeenCalled()
    claim.mockResolvedValue(false)
    expect((await POST(request(token))).status).toBe(401)
    expect(run).not.toHaveBeenCalled()
  })

  it('uses the existing reminder handler after a valid claim', async () => {
    claim.mockResolvedValue(true)
    run.mockResolvedValue({ accepted: 1, failed: 0 })
    expect(await (await POST(request(token))).json()).toEqual({ accepted: 1, failed: 0 })
    expect(claim).toHaveBeenCalledWith(host, token)
    expect(run).toHaveBeenCalledTimes(1)
  })
})
