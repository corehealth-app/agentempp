import { writeFileSync } from 'node:fs'
import { describe, expect, it } from 'vitest'
import { projectTrainingWindow, readTrainingWindow } from './training-window-service'

const OWNER = 'a1111111-1111-4111-8111-111111111111',
  AUTH = 'a2222222-2222-4222-8222-222222222222',
  EPOCH = 'a3333333-3333-4333-8333-333333333333',
  ID = 'a4444444-4444-4444-8444-444444444444'
const scope = () => ({
  authUserID: AUTH,
  ownerID: OWNER,
  epoch: EPOCH,
  timezone: 'America/Sao_Paulo',
  currentLocalDate: '2026-11-04',
  observedAt: '2026-11-04T15:00:00.000001Z',
  binding: 'owned-profile',
  policy: {
    version: 1 as const,
    observed_at: '2026-11-04T15:00:00.000000Z',
    assessment: 'complete' as const,
    recording_allowed: true,
    pause_weight_loss_guidance: false,
    professional_assessment_recommended: false,
    phase_selection_pending: false,
    target_source: 'official_only' as const,
    hide: {
      objective: false,
      calories: false,
      protein: false,
      balance: false,
      block: false,
      budget: false,
    },
  },
})
const workout = (
  id = ID,
): {
  id: string
  user_id: string
  workout_type: string | null
  duration_min: number | null
  estimated_kcal: number | null
  intensity: string | null
  performed_at: string
} => ({
  id,
  user_id: OWNER,
  workout_type: 'Caminhada',
  duration_min: 30,
  estimated_kcal: 116,
  intensity: 'leve',
  performed_at: '2026-11-04T14:00:00.000001Z',
})
const capture = () => ({ workouts: [workout()], count: 1 })
const auth = { userId: OWNER, authUserId: AUTH }
describe('Owned training Day/Week read never registers a workout', () => {
  it('exposes the official recorded activity once in its civil day, with no food budget/XP', () => {
    const v = projectTrainingWindow(scope(), undefined, capture())
    expect(v.schema).toBe('training.window.v1')
    expect(v.week_start).toBe('2026-11-02')
    expect(v.week_end).toBe('2026-11-08')
    expect(v.days).toHaveLength(7)
    expect(v.days[2]).toEqual({
      local_date: '2026-11-04',
      workouts: [
        {
          id: ID,
          workout_type: 'Caminhada',
          duration_min: 30,
          estimated_kcal: 116,
          intensity: 'leve',
          performed_at: '2026-11-04T14:00:00.000001Z',
        },
      ],
    })
    if (process.env.TRAINING_WINDOW_FIXTURE_OUTPUT)
      writeFileSync(process.env.TRAINING_WINDOW_FIXTURE_OUTPUT, `${JSON.stringify(v, null, 2)}\n`)
    expect(JSON.stringify(v)).not.toContain('food_budget')
    expect(JSON.stringify(v)).not.toContain('xp_')
  })
  it('represents a complete empty week without claiming a prescribed plan was executed', () => {
    const v = projectTrainingWindow(scope(), undefined, { workouts: [], count: 0 })
    expect(v.days.every((d) => d.workouts.length === 0)).toBe(true)
    expect(v.completeness).toBe('complete')
  })
  it('retains unknown energy/duration instead of zero or inferred intensity', () => {
    const c = capture()
    c.workouts[0] = {
      ...workout(),
      duration_min: null,
      estimated_kcal: null,
      intensity: null,
      workout_type: null,
    }
    const w = projectTrainingWindow(scope(), undefined, c).days[2].workouts[0]
    expect(w.estimated_kcal).toBeNull()
    expect(w.duration_min).toBeNull()
    expect(w.intensity).toBeNull()
  })
  it('keeps two identical legitimate records with distinct ids', () => {
    const c = capture()
    c.workouts.push(workout(AUTH))
    c.count = 2
    expect(projectTrainingWindow(scope(), undefined, c).days[2].workouts).toHaveLength(2)
  })
  it('groups by the authoritative timezone across midnight and accepts historical selected weeks', () => {
    const c = capture()
    c.workouts[0].performed_at = '2026-11-04T02:59:59.999999Z'
    const v = projectTrainingWindow(scope(), undefined, c)
    expect(v.days[1].workouts).toHaveLength(1)
    expect(v.days[2].workouts).toEqual([])
    expect(
      projectTrainingWindow(scope(), '2026-10-26', { workouts: [], count: 0 }).selected_local_date,
    ).toBe('2026-10-26')
  })
  it('does not change stored activity facts into calories available for eating under a clinical hold', () => {
    const s = scope()
    s.policy.pause_weight_loss_guidance = true
    s.policy.hide.budget = true
    s.policy.hide.block = true
    const v = projectTrainingWindow(s, undefined, capture())
    expect(v.clinical_policy.pause_weight_loss_guidance).toBe(true)
    expect(v.days[2].workouts[0].estimated_kcal).toBe(116)
    expect(Object.keys(v)).not.toContain('targets')
  })
  for (const [label, mutate] of [
    [
      'foreign owner',
      (c: ReturnType<typeof capture>) => {
        c.workouts[0].user_id = AUTH
      },
    ],
    [
      'duplicate id',
      (c: ReturnType<typeof capture>) => {
        c.workouts.push(workout())
        c.count = 2
      },
    ],
    [
      'truncated count',
      (c: ReturnType<typeof capture>) => {
        c.count = 2
      },
    ],
    [
      'negative kcal',
      (c: ReturnType<typeof capture>) => {
        c.workouts[0].estimated_kcal = -1
      },
    ],
    [
      'zero duration',
      (c: ReturnType<typeof capture>) => {
        c.workouts[0].duration_min = 0
      },
    ],
    [
      'future record',
      (c: ReturnType<typeof capture>) => {
        c.workouts[0].performed_at = '2026-11-04T15:00:00.000002Z'
      },
    ],
    [
      'outside week',
      (c: ReturnType<typeof capture>) => {
        c.workouts[0].performed_at = '2026-10-01T10:00:00Z'
      },
    ],
  ] as const)
    it(`refuses ${label}`, () => {
      const c = capture()
      mutate(c)
      expect(() => projectTrainingWindow(scope(), undefined, c)).toThrow()
    })
  it('rejects impossible dates and invalid IANA zones', () => {
    expect(() => projectTrainingWindow(scope(), '2026-02-30', capture())).toThrow()
    expect(() =>
      projectTrainingWindow({ ...scope(), timezone: 'not/a-zone' }, undefined, capture()),
    ).toThrow()
  })
  it('reads twice and reobserves current scope without exposing a write port', async () => {
    let captures = 0,
      observes = 0
    const v = await readTrainingWindow(auth, undefined, {
      observe: async () => {
        observes++
        return scope()
      },
      capture: async () => {
        captures++
        return capture()
      },
    })
    expect(v.days[2].workouts).toHaveLength(1)
    expect([captures, observes]).toEqual([2, 2])
  })
  it('withholds a changed/deleted record between observations', async () => {
    let n = 0
    await expect(
      readTrainingWindow(auth, undefined, {
        observe: async () => scope(),
        capture: async () => (++n === 1 ? capture() : { workouts: [], count: 0 }),
      }),
    ).rejects.toMatchObject({ status: 409 })
  })
  for (const field of [
    'ownerID',
    'authUserID',
    'epoch',
    'timezone',
    'currentLocalDate',
    'binding',
    'observedAt',
  ] as const)
    it(`withholds changed scope ${field}`, async () => {
      let n = 0
      await expect(
        readTrainingWindow(auth, undefined, {
          capture: async () => capture(),
          observe: async () => {
            const s = scope()
            if (++n === 2) {
              if (field === 'timezone') s.timezone = 'UTC'
              else if (field === 'currentLocalDate') s.currentLocalDate = '2026-11-05'
              else if (field === 'observedAt') s.observedAt = '2026-11-04T15:00:00.000000Z'
              else s[field] = field === 'binding' ? 'changed' : ID
            }
            return s
          },
        }),
      ).rejects.toMatchObject({ status: 409 })
    })
  it('rejects wrong authenticated owner before reading any records', async () => {
    let reads = 0
    await expect(
      readTrainingWindow({ ...auth, userId: AUTH }, undefined, {
        observe: async () => scope(),
        capture: async () => {
          reads++
          return capture()
        },
      }),
    ).rejects.toMatchObject({ status: 409 })
    expect(reads).toBe(0)
  })
  it('source version is deterministic for record order but changes with official facts', () => {
    const a = capture()
    a.workouts.push(workout(AUTH))
    a.count = 2
    const b = structuredClone(a)
    b.workouts.reverse()
    expect(projectTrainingWindow(scope(), undefined, a).source_version).toBe(
      projectTrainingWindow(scope(), undefined, b).source_version,
    )
    b.workouts[0].duration_min = 31
    expect(projectTrainingWindow(scope(), undefined, a).source_version).not.toBe(
      projectTrainingWindow(scope(), undefined, b).source_version,
    )
  })
})
