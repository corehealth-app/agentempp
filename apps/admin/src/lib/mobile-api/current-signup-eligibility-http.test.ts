import type { ServiceClient } from '@mpp/db'
import { describe, expect, it, vi } from 'vitest'
import { createCurrentSignupEligibilityRoute } from './current-signup-eligibility-http'
import type { MobileRouteRuntime } from './route'
import { signupHealthAuth, signupHealthIDs } from './testing/signup-health-admission-fixture'

const at = '2026-10-27T12:00:00.000001Z'
const input = {
  version: 2,
  locale: 'pt-BR',
  timezone: 'America/Sao_Paulo',
  sex: 'masculino',
  birth_date: '1990-01-01',
  height_cm: 180,
  weight_kg: 80,
  body_fat_percent: 24,
  training_frequency: 4,
}
function snapshot(
  body: Omit<typeof input, 'body_fat_percent'> & { body_fat_percent: number | null } = input,
) {
  const { version: _, ...fields } = body
  return {
    version: 1,
    user_id: signupHealthIDs.owner,
    mode: 'signup',
    profile_present: true,
    epoch: signupHealthIDs.epoch,
    signup_generation: null,
    generation_token: {
      onboarding_completed: false,
      onboarding_completed_at: null,
      receipt_count: 0,
    },
    first_completion: true,
    observed_at: at,
    date: '2026-10-27',
    timezone: fields.timezone,
    body: fields,
    assessment: 'complete',
    missing: [],
    health_state: {
      version: 1,
      user_id: signupHealthIDs.owner,
      safety_revision: '0',
      hold_active: false,
      declared_no_plan: false,
      hide_protein: false,
      last_declared_at: null as string | null,
      items: [] as { code: string; declared_at: string }[],
    },
    safety: {
      version: 1,
      no_plan: false,
      hold_active: false,
      loss_guard: false,
      hide_protein: false,
      recording_allowed: true,
      date: '2026-10-27',
      timezone: fields.timezone,
      observed_at: at,
    },
    phase_origin: { kind: 'not_completed' },
    calculation_config: [] as { key: string; value: unknown; updated_at: string }[],
    profile_hash: 'a'.repeat(64),
    context_hash: 'b'.repeat(64),
  }
}
function setup(value = snapshot(), enabled = true) {
  const rpc = vi.fn().mockResolvedValue({ data: value, error: null })
  const auth = signupHealthAuth()
  const runtime: MobileRouteRuntime = {
    authenticate: vi.fn(async () => auth),
    authorizeEntitlement: vi.fn(async () => {}),
    createServiceClient: () => ({ rpc }) as unknown as ServiceClient,
    createRequestId: () => 'current-signup-test',
  }
  return { rpc, auth, runtime, route: createCurrentSignupEligibilityRoute({ enabled }, runtime) }
}
function request(
  body: unknown = input,
  query = '',
  key: string | null = signupHealthIDs.operation,
) {
  return new Request(`https://owned.test/api/mobile/v1/onboarding/eligibility${query}`, {
    method: 'POST',
    headers: { 'content-type': 'application/json', ...(key ? { 'idempotency-key': key } : {}) },
    body: JSON.stringify(body),
  })
}
describe('current signup eligibility public V2', () => {
  it('uses exactly the authenticated SQL capture and returns no private clinical authority', async () => {
    const x = setup(),
      response = await x.route(request())
    expect(response.status).toBe(200)
    const data = (await response.json()).data
    expect(data).toMatchObject({
      version: 2,
      decision: 'assigned',
      objective: 'recomposicao',
      professional_assessment_recommended: false,
      pause_weight_loss_guidance: false,
    })
    expect(data).not.toHaveProperty('basis')
    expect(data.notice).not.toHaveLength(0)
    expect(data.options.map((o: { status: string }) => o.status)).toEqual([
      'available',
      'blocked',
      'not_offered',
    ])
    const { version: _, ...body } = input
    expect(x.rpc).toHaveBeenCalledOnce()
    expect(x.rpc).toHaveBeenCalledWith('get_mobile_current_clinical_state', {
      p_user_id: signupHealthIDs.owner,
      p_mode: 'signup',
      p_body: body,
      p_expected: null,
    })
    for (const key of [
      'user_id',
      'epoch',
      'health_state',
      'calculation_config',
      'generation_token',
      'observed_at',
      'profile_hash',
      'context_hash',
      'targets',
    ])
      expect(data).not.toHaveProperty(key)
  })
  it('uses SQL civil age for no-plan, with explicit null and no automatic substitute', async () => {
    const body = { ...input, birth_date: '2008-10-28' },
      value = snapshot(body)
    value.safety.no_plan = value.safety.hide_protein = true
    const x = setup(value),
      response = await x.route(request(body))
    expect(response.status).toBe(200)
    expect((await response.json()).data).toMatchObject({
      version: 2,
      decision: 'no_plan',
      objective: null,
      options: [],
      professional_assessment_recommended: true,
      pause_weight_loss_guidance: true,
    })
  })
  it('persisted pregnancy declaration overrides an adult concrete objective without exposing the answer', async () => {
    const value = snapshot()
    Object.assign(value.health_state, {
      safety_revision: '1',
      hold_active: true,
      declared_no_plan: true,
      last_declared_at: at,
      items: [{ code: 'pregnant_or_breastfeeding', declared_at: at }],
    })
    Object.assign(value.safety, { no_plan: true, hold_active: true, hide_protein: true })
    const x = setup(value),
      response = await x.route(request()),
      data = (await response.json()).data
    expect(response.status).toBe(200)
    expect(data).toMatchObject({ decision: 'no_plan', objective: null, options: [] })
    expect(JSON.stringify(data)).not.toContain('pregnant_or_breastfeeding')
  })
  it.each([
    'pt-BR',
    'en-US',
  ])('keeps ordinary choices and safe no-plan copy in %s', async (locale) => {
    const body = { ...input, locale, body_fat_percent: 15 },
      x = setup(snapshot(body))
    const response = await x.route(request(body)),
      data = (await response.json()).data
    expect(response.status).toBe(200)
    expect(data).toMatchObject({ decision: 'choice', objective: null, notice: null })
    expect(data.options.map((o: { status: string }) => o.status)).toEqual([
      'available',
      'available',
      'available',
    ])
    const minor = { ...body, birth_date: '2008-10-28' },
      value = snapshot(minor)
    Object.assign(value.safety, { no_plan: true, hide_protein: true })
    const noPlan = await setup(value).route(request(minor)),
      result = (await noPlan.json()).data
    expect(noPlan.status).toBe(200)
    expect(result.notice[1]).toContain(
      locale === 'pt-BR' ? 'profissional de saúde' : 'healthcare professional',
    )
  })
  it('uses captured config and exact stored BMI boundary with genuinely absent BF', async () => {
    const body = { ...input, weight_kg: 59.94, body_fat_percent: null },
      value = snapshot(body)
    value.calculation_config = [{ key: 'calc.training_min', value: 7, updated_at: at }]
    const x = setup(value),
      response = await x.route(request(body)),
      data = (await response.json()).data
    expect(response.status).toBe(200)
    expect(data.pause_weight_loss_guidance).toBe(false)
    expect(data.options[0].status).toBe('available')
    expect(data.options[1]).toMatchObject({ status: 'blocked', reasons: ['gain_training'] })
    expect(data.options[1].message.join(' ')).toContain('7')
  })
  it('reads admitted HOLD, never offers automatic recomposition in its copy or consumes a health receipt from the client', async () => {
    const value = snapshot()
    Object.assign(value.health_state, {
      safety_revision: '1',
      hold_active: true,
      last_declared_at: at,
      items: [{ code: 'reduced_intake', declared_at: at }],
    })
    value.safety.hold_active = true
    const x = setup(value),
      response = await x.route(request())
    const data = (await response.json()).data
    expect(response.status).toBe(200)
    expect(data).toMatchObject({ decision: 'choice', objective: null })
    expect(data.options.map((o: { status: string }) => o.status)).toEqual([
      'blocked',
      'blocked',
      'available',
    ])
    expect(data.options[0].reasons).toEqual(['health_review'])
    expect(data.notice.join(' ')).toContain('pausadas')
    expect(JSON.stringify(data)).not.toContain('reduced_intake')
    expect(JSON.stringify(data)).not.toContain('definido automaticamente')
  })
  it('low-weight copy does not suggest a recomposition which the current rule blocks', async () => {
    const body = { ...input, weight_kg: 50, body_fat_percent: 24, training_frequency: 0 },
      value = snapshot(body)
    value.safety.loss_guard = true
    const x = setup(value),
      response = await x.route(request(body)),
      data = (await response.json()).data
    expect(response.status).toBe(200)
    expect(data.options[0]).toMatchObject({ status: 'blocked', reasons: ['loss_guard'] })
    expect(data.options[1]).toMatchObject({
      status: 'blocked',
      reasons: ['gain_composition', 'gain_training'],
    })
    expect(data.options[1].message.join(' ')).not.toContain('escolher recomposição')
    expect(data.options[2].status).toBe('available')
  })
  it('rejects private authority, ordinary/health answers, invalid DOB/zone and negotiation before RPC', async () => {
    const x = setup()
    for (const patch of [
      { epoch: signupHealthIDs.epoch },
      { user_id: signupHealthIDs.owner },
      { no_plan: true },
      { risks: ['reduced_intake'] },
      { health_receipt: signupHealthIDs.receipt },
      { date: '2000-01-01' },
      { objective: null },
      { birth_date: '2026-02-30' },
      { timezone: 'unknown' },
      { version: 1 },
    ])
      expect((await x.route(request({ ...input, ...patch }))).status).toBe(422)
    expect((await x.route(request(input, '?clinical_policy=unknown'))).status).toBe(422)
    expect((await x.route(request(input, '', null))).status).toBe(400)
    expect(x.rpc).not.toHaveBeenCalled()
  })
  it('every read captures again, and SQL changes cannot fall back to the cached legacy config', async () => {
    const x = setup()
    expect((await x.route(request())).status).toBe(200)
    x.rpc.mockResolvedValueOnce({ data: null, error: { code: '40001', message: 'private epoch' } })
    const response = await x.route(request())
    expect(response.status).toBe(409)
    expect(await response.text()).not.toContain('private epoch')
    expect(x.rpc).toHaveBeenCalledTimes(2)
  })
  it('refuses completed or foreign observations instead of deciding a new initial phase', async () => {
    for (const patch of [
      { user_id: signupHealthIDs.intent },
      { first_completion: false },
      { safety: { ...snapshot().safety, no_plan: true } },
    ]) {
      const x = setup(Object.assign(snapshot(), patch)),
        response = await x.route(request())
      expect(response.status).toBeGreaterThanOrEqual(409)
      expect(await response.text()).not.toContain(signupHealthIDs.epoch)
    }
  })
  it('preserves feature/auth/entitlement gates before clinical reads', async () => {
    const off = setup(snapshot(), false)
    expect((await off.route(request())).status).toBe(404)
    expect(off.rpc).not.toHaveBeenCalled()
    const x = setup()
    const { MobileApiError } = await import('./http')
    vi.mocked(x.runtime.authorizeEntitlement).mockRejectedValueOnce(
      new MobileApiError(403, 'forbidden', 'Forbidden'),
    )
    expect((await x.route(request())).status).toBe(403)
    expect(x.rpc).not.toHaveBeenCalled()
  })
})
