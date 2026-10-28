import { buildDailyState } from '@mpp/core'
import type { ServiceClient } from '@mpp/db'
import { describe, expect, it, vi } from 'vitest'
import {
  type CurrentClinicalReaderSources,
  createCurrentClinicalReadModel,
} from './current-clinical-read-model'
import {
  type ClinicalFlowPeriodRow,
  createCurrentFlowClinicalPort,
} from './current-flow-clinical-port'
import type { MobileRouteContext } from './route'
import { currentFlowDraftFixture } from './testing/current-flow-draft-fixture'
import { currentOnboardingWire } from './testing/current-onboarding-fixture'
import { consentAuth } from './testing/reevaluation-photo-consent-fixture'

function setup(kind: 'healthy' | 'hold' | 'no_plan' = 'healthy') {
  const state = currentOnboardingWire(kind),
    order: string[] = [],
    capture = vi.fn(async (_request: { userId: string; mode: string }) => structuredClone(state)),
    client = {} as ServiceClient
  const day = buildDailyState({
    localDate: state.date,
    generatedAt: state.observed_at,
    protocol: 'recomposicao',
    calculatedTargets: { calories_target: 1800, protein_target: 140 },
    snapshot: {
      caloriesConsumed: 1000,
      proteinG: 50,
      carbsG: 100,
      fatG: 20,
      exerciseCalories: 50,
      caloriesTarget: 1800,
      proteinTarget: 140,
      protocol: 'recomposicao',
      waterConsumedMl: 0,
      dayClosed: false,
      dayStatus: null,
      updatedAt: null,
    },
    meals: [],
    workouts: [],
    pendingRegistrations: [],
    hydrationTarget: null,
    routineItems: [],
    progress: null,
    mealGap: {
      expected: [],
      registered: [],
      skipped: [],
      open: [],
      reliable: false,
      activeDays: 0,
    },
  })
  const reads: CurrentClinicalReaderSources = {
    today: async () => {
      order.push('today')
      return day
    },
    progress: async () => null,
    plan: async () => ({ training: null, nutrition: [] }),
    trends: async () => {
      throw new Error('unused')
    },
    profile: async () => {
      throw new Error('unused')
    },
  }
  const rows: ClinicalFlowPeriodRow[] = [
    {
      date: '2026-10-26',
      calories_consumed: 1000,
      protein_g: 50,
      daily_balance: -600,
      day_status: 'complete',
      balance_proven: true,
    },
  ]
  const periodRows = vi.fn(async () => rows),
    daily = vi.fn(async () => {
      order.push('daily')
    }),
    close = vi.fn(async () => {
      order.push('close')
    })
  const draftFixture = currentFlowDraftFixture(state)
  const dependencies = {
    state: { capture },
    createReadModel: () => createCurrentClinicalReadModel(client, { capture }, reads),
    applyDaily: daily,
    closeDays: close,
    periodRows,
    drafts: draftFixture.authority,
  }
  const context: MobileRouteContext = {
    auth: consentAuth,
    request: new Request(
      'https://performe.test/api/mobile/v1/flow/chat?clinical_policy=current_clinical_v1',
    ),
    requestId: 'qa',
    supabase: client,
  }
  return {
    state,
    order,
    capture,
    client,
    rows,
    periodRows,
    daily,
    close,
    context,
    dependencies,
    draftFixture,
    port: createCurrentFlowClinicalPort(context, dependencies),
  }
}
describe('dormant current Flow clinical composition', () => {
  it('runs preflight/daily/whole closer once, then projects both repeated reads without private authority', async () => {
    const s = setup('no_plan')
    const a = await s.port.read()
    await s.port.read()
    expect(s.order.slice(0, 3)).toEqual(['daily', 'close', 'today'])
    expect(s.daily).toHaveBeenCalledTimes(1)
    expect(s.close).toHaveBeenCalledTimes(1)
    expect(a.policy.pause_weight_loss_guidance).toBe(true)
    expect(a.today.targets.calories_kcal).toBeNull()
    expect(a.today.consumed.calories_kcal).toBe(1000)
    expect(a.today.daily_balance_kcal).toBeNull()
    expect(JSON.stringify(a)).not.toMatch(
      /safety_revision|health_state|profile_hash|context_hash|signup_generation|calculation_config|reduced_intake/,
    )
    expect(Object.isFrozen(a.profile)).toBe(true)
  })
  it('requires explicit known representation before any effects', () => {
    const s = setup()
    s.context.request = new Request('https://performe.test/api/mobile/v1/flow/chat')
    expect(() => createCurrentFlowClinicalPort(s.context, s.dependencies)).toThrow()
    expect(s.daily).not.toHaveBeenCalled()
    expect(s.capture).not.toHaveBeenCalled()
  })
  it('does not replace the original binding after health/config/epoch drift', async () => {
    const s = setup()
    await s.port.read()
    s.state.profile_hash = 'c'.repeat(64)
    await expect(s.port.read()).rejects.toMatchObject({
      status: 409,
      code: 'mobile_current_clinical_changed',
    })
  })
  it('freezes owner and callbacks before awaits', async () => {
    const s = setup()
    const read = s.port.read()
    s.dependencies.applyDaily = vi.fn(async () => {
      throw new Error('replacement')
    })
    s.context.auth = { ...s.context.auth, userId: 'another' }
    await read
    expect(
      s.capture.mock.calls.every(
        (call) => (call[0] as { userId: string }).userId === consentAuth.userId,
      ),
    ).toBe(true)
  })
  it('uses exact closed-day evidence, preserving consumption when balance is hidden or unproven', async () => {
    const s = setup()
    let value = await s.port.period('semana')
    expect(value).toMatchObject({ days: 1, avgConsumed: 1000, avgProtein: 50, avgNetBalance: -600 })
    const first = s.rows[0]
    if (!first) throw new Error('missing fixture')
    first.balance_proven = false
    value = await s.port.period('semana')
    expect(value.avgNetBalance).toBeNull()
    expect(value.avgConsumed).toBe(1000)
    const h = setup('no_plan')
    expect((await h.port.period('mes')).avgNetBalance).toBeNull()
    expect(s.periodRows).toHaveBeenCalledWith(
      s.client,
      consentAuth.userId,
      '2026-10-21',
      '2026-10-27',
    )
  })
  it('rejects a row outside the bound civil interval and duplicate days', async () => {
    const s = setup()
    const first = s.rows[0]
    if (!first) throw new Error('missing fixture')
    first.date = '2026-10-01'
    await expect(s.port.period('semana')).rejects.toThrow()
    const t = setup()
    const other = t.rows[0]
    if (!other) throw new Error('missing fixture')
    t.rows.push({ ...other })
    await expect(t.port.period('mes')).rejects.toThrow()
  })
  it('does not retry effects after a failed initialization or fall back to a formula', async () => {
    const s = setup()
    s.dependencies.applyDaily.mockRejectedValueOnce(new Error('unavailable'))
    await expect(s.port.read()).rejects.toThrow('unavailable')
    await expect(s.port.read()).rejects.toThrow('unavailable')
    expect(s.daily).toHaveBeenCalledTimes(1)
    expect(s.close).not.toHaveBeenCalled()
  })
  it('captures the original exact day before today and refuses changed/restored targets without rebasing', async () => {
    const s = setup()
    s.draftFixture.authority.capture.mockImplementation(async () => {
      s.order.push('draft-context')
      return {
        version: 1,
        state: structuredClone(s.state),
        day: structuredClone(s.draftFixture.day),
        allowed: { training: true, nutrition: true },
      }
    })
    await s.port.read()
    expect(s.order.indexOf('draft-context')).toBeLessThan(s.order.indexOf('today'))
    s.draftFixture.day.target_revision = '2'
    await expect(s.port.revalidate()).rejects.toMatchObject({
      code: 'mobile_current_clinical_changed',
    })
  })
  it('fixes private command and inbound once, and refuses creating a new key without prior lookup', async () => {
    const s = setup(),
      drafts = s.port.drafts!
    const key = { domain: 'nutrition' as const, requestKey: 'qa-original:propoe_plano_dieta' }
    const create = {
      ...key,
      status: 'needs_completion' as const,
      payload: { meta_kcal: 1800, meta_protein_g: 140 },
      uncertainFields: [],
      originDetail: { identity: 'flow' },
    }
    await expect(drafts.create(create)).rejects.toThrow()
    expect(s.draftFixture.authority.create).not.toHaveBeenCalled()
    await s.port.read()
    await drafts.lookup(key)
    await drafts.lookup(key)
    const result = await drafts.create(create)
    expect(s.draftFixture.authority.findTurn).toHaveBeenCalledTimes(1)
    expect(s.draftFixture.authority.create).toHaveBeenCalledWith(
      expect.objectContaining({
        sourceMessageId: expect.any(String),
        expected: expect.objectContaining({
          day: expect.objectContaining({ target_revision: '0' }),
        }),
      }),
    )
    expect(JSON.stringify(result)).not.toMatch(
      /expected|signup_generation|calculation_config|health_state|sourceMessageId/,
    )
  })
  it('rejects a public target pair that differs from the original SQL day rather than replacing authority', async () => {
    const s = setup()
    s.draftFixture.day.calories_target = 1801
    await expect(s.port.read()).rejects.toMatchObject({ code: 'mobile_current_clinical_changed' })
    expect(s.draftFixture.authority.create).not.toHaveBeenCalled()
  })
})
