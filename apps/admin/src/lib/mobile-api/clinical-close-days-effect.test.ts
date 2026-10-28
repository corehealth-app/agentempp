import { DayCloseMemoryDb } from '@mpp/agent/testing/day-close-memory-db'
import { afterEach, describe, expect, it, vi } from 'vitest'
import type { MobileAuthContext } from './auth'
import { createClinicalCloseDaysEffect } from './clinical-close-days-effect'
import {
  clinicalCloseCommandSchema,
  clinicalClosedResultSchema,
  clinicalCloseError,
} from './clinical-day-close-contracts'
import type { createClinicalDayCloseService } from './clinical-day-close-service'
import {
  type ClinicalHttpEffectScope,
  createCurrentClinicalGetRoute,
} from './current-clinical-http'
import type { createCurrentClinicalReadModel } from './current-clinical-read-model'
import type { MobileRouteRuntime } from './route'

const owner = 'b3b01000-0000-4000-8000-000000003800',
  other = 'b3b01000-0000-4000-8000-000000003801'
const zone = 'America/Sao_Paulo',
  now = new Date('2026-10-05T11:00:00Z')
const ON = {
  MOBILE_DAY_CLOSE_FROM: '2026-09-22',
  MOBILE_DAY_CLOSE_PROJECT_REF: 'xitugspwfxkcluxvrdeg',
  NEXT_PUBLIC_SUPABASE_URL: 'https://xitugspwfxkcluxvrdeg.supabase.co',
}
const auth = (): MobileAuthContext => ({
  userId: owner,
  authUserId: other,
  accessToken: 'synthetic-only',
  identity: { id: other, email: null, emailConfirmedAt: null },
  patient: {
    id: owner,
    authUserId: other,
    email: null,
    name: null,
    locale: 'pt-BR',
    timezone: zone,
    country: 'BR',
    countryConfirmed: true,
    status: 'active',
  },
})
function closed(date: string) {
  return clinicalClosedResultSchema.parse({
    date,
    closed: true,
    dryRun: false,
    late: true,
    detail: {
      caloriesConsumed: 1500,
      exerciseCalories: 0,
      storedCaloriesTarget: 2000,
      caloriesTarget: 2000,
      storedProteinTarget: 130,
      proteinTarget: 130,
      dayStatus: 'complete',
      xpEarned: 15,
      blockCredit: 1000,
      newBadges: [],
      progress: {
        xpTotal: 15,
        level: 1,
        currentStreak: 1,
        longestStreak: 1,
        blocksCompleted: 0,
        deficitBlock: 1000,
        badgesEarned: [],
        lastActiveDate: date,
      },
    },
  })
}
function harness(dates = ['2026-10-04']) {
  const db = new DayCloseMemoryDb()
  db.addAccount({
    userId: owner,
    profile: { current_protocol: 'recomposicao', deficit_level: 500 },
  })
  for (const date of dates)
    db.registerMeal({
      userId: owner,
      date,
      consumedAt: `${date}T15:00:00Z`,
      kcal: 1500,
      proteinG: 100,
      mealType: 'almoco',
      caloriesTarget: 2000,
      proteinTarget: 130,
    })
  db.failWith = (operation) => (operation.kind === 'select' ? null : 'Legacy writer forbidden')
  const run = vi.fn<ReturnType<typeof createClinicalDayCloseService>['run']>(
    async (_auth, input) => {
      const command = clinicalCloseCommandSchema.parse(input)
      return command.date === null
        ? {
            kind: 'unchanged' as const,
            reset: { applied: false as const, reason: 'unchanged' as const },
          }
        : closed(command.date)
    },
  )
  let seq = 3900
  const nextOperationKey = vi.fn(() => `b3b01000-0000-4000-8000-${String(++seq).padStart(12, '0')}`)
  const service = { run }
  const options = { env: ON, now, nextOperationKey, createService: () => service }
  const effect = createClinicalCloseDaysEffect(options)
  const scope: ClinicalHttpEffectScope = {
    auth: auth(),
    supabase: db.client,
    url: 'https://bodyflow.test/api/mobile/v1/today?clinical_policy=current_clinical_v1',
    admission: { owner } as ClinicalHttpEffectScope['admission'],
  }
  return { db, run, nextOperationKey, options, service, effect, scope }
}
afterEach(() => vi.restoreAllMocks())
describe('guarded dormant HTTP closer effect', () => {
  it('uses official timezone, environment start and one server UUID per command, without legacy writes', async () => {
    const h = harness()
    vi.spyOn(console, 'info').mockImplementation(() => {})
    h.scope.auth.patient.timezone = 'Asia/Tokyo'
    await h.effect(h.scope)
    expect(h.run.mock.calls.map(([, command]) => command)).toEqual([
      {
        operationKey: 'b3b01000-0000-4000-8000-000000003901',
        from: ON.MOBILE_DAY_CLOSE_FROM,
        date: '2026-10-04',
        timezone: zone,
      },
      {
        operationKey: 'b3b01000-0000-4000-8000-000000003902',
        from: ON.MOBILE_DAY_CLOSE_FROM,
        date: null,
        timezone: zone,
      },
    ])
    expect(h.db.writes).toEqual([])
  })
  it('keeps the three-date budget and does not reset with a pending fourth date', async () => {
    const h = harness(['2026-10-01', '2026-10-02', '2026-10-03', '2026-10-04'])
    vi.spyOn(console, 'info').mockImplementation(() => {})
    await h.effect(h.scope)
    expect(h.run).toHaveBeenCalledTimes(3)
    expect(h.nextOperationKey).toHaveBeenCalledTimes(3)
    expect(h.db.writes).toEqual([])
  })
  it.each([
    {},
    {
      ...ON,
      NEXT_PUBLIC_SUPABASE_URL: 'https://xuxehkhdvjivitduarvb.supabase.co',
      MOBILE_DAY_CLOSE_PROJECT_REF: 'xuxehkhdvjivitduarvb',
    },
  ])('keeps an OFF/forbidden-project guard at zero queries and zero operation keys', async (env) => {
    const h = harness()
    await createClinicalCloseDaysEffect({ ...h.options, env })(h.scope)
    expect(h.db.operations).toEqual([])
    expect(h.run).not.toHaveBeenCalled()
    expect(h.nextOperationKey).not.toHaveBeenCalled()
  })
  it('preserves only closed clinical failures and does not retry/fallback', async () => {
    const h = harness()
    vi.spyOn(console, 'error').mockImplementation(() => {})
    h.run.mockRejectedValueOnce(clinicalCloseError('changed'))
    await expect(h.effect(h.scope)).rejects.toMatchObject({
      status: 409,
      code: 'mobile_clinical_close_changed',
    })
    expect(h.run).toHaveBeenCalledTimes(1)
    expect(h.db.writes).toEqual([])
  })
  it('maps a pending-activity reset refusal to a conflict before any later reader', async () => {
    const h = harness([])
    vi.spyOn(console, 'error').mockImplementation(() => {})
    h.run.mockResolvedValueOnce({
      kind: 'unchanged',
      reset: { applied: false, reason: 'pending_activity' },
    })
    await expect(h.effect(h.scope)).rejects.toMatchObject({ code: 'mobile_clinical_close_changed' })
    expect(h.run).toHaveBeenCalledTimes(1)
    expect(h.db.writes).toEqual([])
  })
  it('converts the service skipReason explicitly and refuses stale discovery without legacy fallback', async () => {
    const h = harness()
    vi.spyOn(console, 'error').mockImplementation(() => {})
    h.run.mockResolvedValueOnce({
      date: '2026-10-04',
      closed: false,
      dryRun: false,
      late: true,
      skipReason: 'earlier_date_changed',
    })
    await expect(h.effect(h.scope)).rejects.toMatchObject({ code: 'mobile_clinical_close_changed' })
    expect(h.run).toHaveBeenCalledTimes(1)
    expect(h.db.writes).toEqual([])
  })
  it('fails account reads through the clinical error contract while retaining the original hook behavior for other callers', async () => {
    const h = harness()
    vi.spyOn(console, 'error').mockImplementation(() => {})
    h.db.failWith = (operation) => (operation.target === 'users' ? 'private provider detail' : null)
    await expect(h.effect(h.scope)).rejects.toMatchObject({
      status: 503,
      code: 'mobile_clinical_close_unavailable',
      message: 'Day closure unavailable',
    })
    expect(h.run).not.toHaveBeenCalled()
  })
  it('binds owner and producer callbacks before the account read yields', async () => {
    const h = harness()
    vi.spyOn(console, 'info').mockImplementation(() => {})
    h.db.before = () => {
      h.scope.auth.userId = other
      h.service.run = vi.fn(async () => {
        throw new Error('replaced')
      })
    }
    await h.effect(h.scope)
    expect(h.run.mock.calls.every(([context]) => context.userId === owner)).toBe(true)
    expect(h.db.writes).toEqual([])
  })
  it('propagates a clinical refusal through the real HTTP wrapper, without invoking the numeric reader', async () => {
    const h = harness()
    vi.spyOn(console, 'error').mockImplementation(() => {})
    h.run.mockRejectedValueOnce(clinicalCloseError('busy'))
    const today = vi.fn(async () => ({ current_protocol: 'recomposicao' }))
    const model = { preflight: async () => h.scope.admission, today } as unknown as ReturnType<
      typeof createCurrentClinicalReadModel
    >
    const runtime: MobileRouteRuntime = {
      createServiceClient: () => h.db.client,
      createRequestId: () => 'request-is-not-an-operation-uuid',
      authenticate: async () => auth(),
      authorizeEntitlement: async () => {},
    }
    const handler = createCurrentClinicalGetRoute(
      'today',
      runtime,
      { createReadModel: () => model, applyDaily: async () => {}, closeDays: h.effect },
      () => false,
    )
    const response = await handler(new Request(h.scope.url))
    expect(response.status).toBe(409)
    expect(today).not.toHaveBeenCalled()
    expect(h.nextOperationKey).toHaveBeenCalledTimes(1)
    expect(h.db.writes).toEqual([])
  })
})
