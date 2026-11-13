import { describe, expect, it } from 'vitest'
import {
  prepareTrainingExecutionMutation as prepare,
  projectTrainingExecutionPlan as project,
} from './training-execution-kernel'

const OWNER = 'a1111111-1111-4111-8111-111111111111',
  AUTH = 'a2222222-2222-4222-8222-222222222222',
  EPOCH = 'a3333333-3333-4333-8333-333333333333',
  PLAN = 'a4444444-4444-4444-8444-444444444444',
  SESSION = 'a5555555-5555-4555-8555-555555555555',
  OP = 'a6666666-6666-4666-8666-666666666666',
  SET = 'a7777777-7777-4777-8777-777777777777',
  NEXT = 'a8888888-8888-4888-8888-888888888888'
const at = '2026-11-13T15:30:00.000001Z'
const scope = () => ({
  owner_id: OWNER,
  auth_user_id: AUTH,
  epoch: EPOCH,
  time_zone: 'America/Sao_Paulo',
  current_local_date: '2026-11-13',
  open_local_date: '2026-11-13',
  observed_at: at,
  recording_allowed: true,
})
const exercise = () => ({
  name: 'Supino',
  muscle_group: 'Peitoral',
  sets: 3,
  reps_range: '8–12',
  rest_seconds: 60,
  notes: 'Controle a descida.',
})
const plan = () => ({
  id: PLAN,
  user_id: OWNER,
  version: 2,
  active: true,
  generated_at: '2026-11-12T10:00:00Z',
  valid_until: '2026-11-20T10:00:00Z',
  weekly_schedule: [
    { day: 'sexta', focus: 'Superiores', duration_min: 45, exercises: [exercise(), exercise()] },
    { day: 'domingo', focus: 'Descanso', duration_min: null, exercises: [] },
  ],
})
function firstExercise(p: ReturnType<typeof plan>) {
  const e = p.weekly_schedule[0]?.exercises[0]
  if (!e) throw new Error('Expected the original exercise fixture')
  return e
}
function started() {
  const p = plan(),
    s = scope(),
    definition = project(p, s)
  expect(definition).toMatchObject({ schema: 'training.execution-plan.v1' })
  const command = {
    schema: 'training.execution.start.v1',
    session_id: SESSION,
    operation_id: SESSION,
    expected_epoch: EPOCH,
    expected_local_date: s.current_local_date,
    plan_id: PLAN,
    plan_hash: definition.definition_hash,
    day_index: 0,
  }
  const v = prepare({ plan: p, scope: s, command, session: null, prior_receipt: null })
  expect(v).toMatchObject({ status: 'created' })
  return { command, value: v, scope: s, plan: p, definition }
}
function setCommand(overrides: Record<string, unknown> = {}) {
  return {
    schema: 'training.execution.update.v1',
    session_id: SESSION,
    operation_id: OP,
    expected_epoch: EPOCH,
    expected_revision: 0,
    action: {
      kind: 'save_set',
      exercise_index: 0,
      set: {
        id: SET,
        index: 0,
        repetitions: 10,
        load_kg: 20,
        duration_seconds: null,
        completed: true,
      },
    },
    ...overrides,
  }
}
function update(
  start: ReturnType<typeof started>,
  command: unknown,
  scopeOverride = start.scope,
  prior: unknown = null,
) {
  return prepare({
    scope: scopeOverride,
    session: start.value.session,
    plan: null,
    command,
    prior_receipt: prior,
  })
}
const expectCode = (f: () => unknown, code: string) => {
  expect(f).toThrowError(expect.objectContaining({ code }))
}

describe('Actual per-exercise work stays separate from a prescription', () => {
  it('projects immutable original instructions with distinct ordinals for equal exercise names', () => {
    const raw = plan(),
      d = project(raw, scope())
    expect(d).toMatchObject({
      schema: 'training.execution-plan.v1',
      owner_id: OWNER,
      auth_user_id: AUTH,
      plan_id: PLAN,
      plan_version: 2,
      epoch: EPOCH,
      time_zone: 'America/Sao_Paulo',
    })
    expect(d.definition_hash).toMatch(/^[0-9a-f]{64}$/)
    expect(d.days[0].exercises.map((e: { index: number }) => e.index)).toEqual([0, 1])
    expect(d.days[0].exercises[0]).toMatchObject({
      name: 'Supino',
      recommended_sets: 3,
      reps_reference: '8–12',
      notes: 'Controle a descida.',
    })
    expect(d.days[0].exercises[0].fingerprint).not.toBe(d.days[0].exercises[1].fingerprint)
    expect(d.days[1]).toMatchObject({ startable: false, exercises: [] })
    firstExercise(raw).name = 'Mudou fora'
    expect(d.days[0].exercises[0].name).toBe('Supino')
    expect(Object.isFrozen(d.days[0].exercises[0])).toBe(true)
  })
  it('fingerprints every source change while object key order does not change identity', () => {
    const p = plan(),
      a = project(p, scope())
    expect(project({ ...p, weekly_schedule: p.weekly_schedule }, scope()).definition_hash).toBe(
      a.definition_hash,
    )
    firstExercise(p).sets = 4
    expect(project(p, scope()).definition_hash).not.toBe(a.definition_hash)
  })
  it('starts with zero actual sets and no completed exercise, calories, XP or workout log', () => {
    const { value: v } = started()
    expect(v.session).toMatchObject({
      schema: 'training.execution.v1',
      id: SESSION,
      owner_id: OWNER,
      auth_user_id: AUTH,
      epoch: EPOCH,
      phase: 'in_progress',
      revision: 0,
      local_date: '2026-11-13',
    })
    expect(v.session.exercises).toEqual([
      { index: 0, completed: false, sets: [] },
      { index: 1, completed: false, sets: [] },
    ])
    for (const k of ['workout_id', 'estimated_kcal', 'xp', 'food_budget'])
      expect(v.session).not.toHaveProperty(k)
    expect(v.receipt).toMatchObject({
      session_id: SESSION,
      operation_id: SESSION,
      before_revision: null,
      after_revision: 0,
      kind: 'start',
    })
  })
  it('saves only the explicitly performed set and preserves its prior immutable observation', () => {
    const f = started(),
      v = update(f, setCommand())
    expect(v).toMatchObject({
      status: 'updated',
      session: { revision: 1, phase: 'in_progress' },
      receipt: { operation_id: OP, before_revision: 0, after_revision: 1 },
    })
    expect(v.session.exercises[0].sets).toEqual([setCommand().action.set])
    expect(v.session.exercises[0].completed).toBe(false)
    expect(v.session.exercises[1].sets).toEqual([])
    expect(f.value.session.exercises[0].sets).toEqual([])
    expect(v.audit).toMatchObject({
      kind: 'save_set',
      exercise_index: 0,
      before: null,
      after: setCommand().action.set,
    })
    expect(JSON.stringify(v.audit).length).toBeLessThan(600)
  })
  it('retains unknown repetitions/load and explicit zero load without copying planned values', () => {
    const f = started(),
      cmd = setCommand()
    cmd.action.set.repetitions = null as unknown as number
    cmd.action.set.load_kg = 0
    const v = update(f, cmd)
    expect(v.session.exercises[0].sets[0]).toMatchObject({
      repetitions: null,
      load_kg: 0,
      completed: true,
    })
  })
  it('marks only the exercise, without inventing three planned sets or a workout', () => {
    const f = started(),
      v = update(
        f,
        setCommand({ action: { kind: 'mark_exercise', exercise_index: 0, completed: true } }),
      )
    expect(v.session.exercises[0]).toEqual({ index: 0, completed: true, sets: [] })
    expect(v.session.exercises[1]).toEqual({ index: 1, completed: false, sets: [] })
    expect(v.session).not.toHaveProperty('workout_id')
  })
  it('uses the pinned original definition after a later plan is replaced', () => {
    const f = started()
    firstExercise(f.plan).name = 'Plano seguinte'
    const v = update(f, setCommand())
    expect(v.session.definition.exercises[0].name).toBe('Supino')
  })
  it('corrects and removes an actual set without shifting the identities of other exercises', () => {
    const f = started(),
      first = update(f, setCommand())
    f.value = first
    const cmd = setCommand({ operation_id: NEXT, expected_revision: 1 })
    cmd.action.set.load_kg = 22.5
    const corrected = update(f, cmd)
    f.value = corrected
    expect(corrected.audit).toMatchObject({ before: { load_kg: 20 } })
    expect(corrected.audit).toMatchObject({ after: { load_kg: 22.5 } })
    const removed = update(
      f,
      setCommand({
        operation_id: SET,
        expected_revision: 2,
        action: { kind: 'remove_set', exercise_index: 0, set_id: SET },
      }),
    )
    expect(removed.session.exercises.map((x: { sets: unknown[] }) => x.sets)).toEqual([[], []])
    expect(removed.audit).toMatchObject({ after: null })
  })
  it('replays an old committed operation observationally after abandonment and day closure', () => {
    const f = started(),
      command = setCommand(),
      first = update(f, command)
    f.value = first
    const abandoned = update(
      f,
      setCommand({ operation_id: NEXT, expected_revision: 1, action: { kind: 'abandon' } }),
    )
    f.value = abandoned
    const replay = update(
      f,
      command,
      { ...f.scope, open_local_date: null as unknown as string, recording_allowed: false },
      first.receipt,
    )
    expect(replay.status).toBe('replayed')
    expect(replay.session).toEqual(abandoned.session)
    expect(replay.session.phase).toBe('abandoned')
    expect(replay.session.revision).toBe(2)
    expect(replay.receipt).toEqual(first.receipt)
    expect(replay.audit).toBeNull()
  })
  it('replays start without replacing a session that already contains actual progress', () => {
    const f = started(),
      first = update(f, setCommand())
    const replay = prepare({
      plan: null,
      scope: f.scope,
      command: f.command,
      session: first.session,
      prior_receipt: f.value.receipt,
    })
    expect(replay.status).toBe('replayed')
    expect(replay.session.revision).toBe(1)
    expect(replay.session.exercises[0].sets).toHaveLength(1)
  })
  it('does not resurrect a terminal session on a new operation', () => {
    const f = started()
    f.value = update(f, setCommand({ action: { kind: 'abandon' } }))
    expectCode(
      () => update(f, setCommand({ operation_id: NEXT, expected_revision: 1 })),
      'training_execution_terminal',
    )
  })
  it('allows an unchanged original timezone session across midnight only while its original day is open', () => {
    const f = started(),
      s = { ...f.scope, current_local_date: '2026-11-14', observed_at: '2026-11-14T03:05:00Z' }
    expect(update(f, setCommand(), s)).toMatchObject({
      session: { local_date: '2026-11-13', revision: 1 },
    })
    expectCode(
      () => update(f, setCommand(), { ...s, open_local_date: null as unknown as string }),
      'training_execution_day_closed',
    )
  })
  for (const [name, patch, code] of [
    ['different owner', { owner_id: PLAN }, 'training_execution_owner_changed'],
    ['different auth', { auth_user_id: PLAN }, 'training_execution_owner_changed'],
    ['reset epoch', { epoch: PLAN }, 'training_execution_epoch_changed'],
    ['timezone moved', { time_zone: 'UTC' }, 'training_execution_scope_changed'],
    ['day closed', { open_local_date: null }, 'training_execution_day_closed'],
    [
      'clinical recording refused',
      { recording_allowed: false },
      'training_execution_recording_blocked',
    ],
    [
      'clock regressed',
      { observed_at: '2026-11-13T15:30:00.000000Z' },
      'training_execution_scope_changed',
    ],
  ] as const)
    it(`refuses ${name} without modifying recorded facts`, () => {
      const f = started(),
        before = JSON.stringify(f.value.session)
      expectCode(
        () => update(f, setCommand(), { ...f.scope, ...patch } as ReturnType<typeof scope>),
        code,
      )
      expect(JSON.stringify(f.value.session)).toBe(before)
    })
  it('refuses stale revisions and colliding set ordinals, even with valid owner identity', () => {
    const f = started()
    f.value = update(f, setCommand())
    expectCode(
      () => update(f, setCommand({ operation_id: NEXT })),
      'training_execution_revision_conflict',
    )
    const duplicate = setCommand({ operation_id: NEXT, expected_revision: 1 })
    duplicate.action.set.id = NEXT
    expectCode(() => update(f, duplicate), 'training_execution_set_conflict')
  })
  it('refuses a set id reused under another exercise', () => {
    const f = started()
    f.value = update(f, setCommand())
    const cmd = setCommand({ operation_id: NEXT, expected_revision: 1 })
    cmd.action.exercise_index = 1
    expectCode(() => update(f, cmd), 'training_execution_set_conflict')
  })
  it('refuses the same operation id with changed content and a foreign or future receipt', () => {
    const f = started(),
      cmd = setCommand(),
      v = update(f, cmd)
    f.value = v
    const changed = setCommand()
    changed.action.set.load_kg = 25
    expectCode(
      () => update(f, changed, f.scope, v.receipt),
      'training_execution_operation_conflict',
    )
    expectCode(
      () => update(f, cmd, f.scope, { ...v.receipt, owner_id: PLAN }),
      'training_execution_receipt_invalid',
    )
    expectCode(
      () => update(f, cmd, f.scope, { ...v.receipt, after_revision: 100 }),
      'training_execution_receipt_invalid',
    )
  })
  it('requires a real receipt to replay start and rejects superseded source definitions', () => {
    const f = started()
    expectCode(
      () =>
        prepare({
          plan: f.plan,
          scope: f.scope,
          session: f.value.session,
          command: f.command,
          prior_receipt: null,
        }),
      'training_execution_operation_conflict',
    )
    firstExercise(f.plan).name = 'Mudou no servidor'
    expectCode(
      () =>
        prepare({
          plan: f.plan,
          scope: f.scope,
          session: null,
          command: f.command,
          prior_receipt: null,
        }),
      'training_execution_plan_changed',
    )
  })
  it('cannot start a rest day or an expired/inactive plan', () => {
    const f = started()
    expectCode(
      () =>
        prepare({
          plan: f.plan,
          scope: f.scope,
          session: null,
          command: { ...f.command, day_index: 1 },
          prior_receipt: null,
        }),
      'training_execution_day_unavailable',
    )
    for (const p of [
      { ...f.plan, active: false },
      { ...f.plan, valid_until: '2026-11-13T15:00:00Z' },
    ])
      expectCode(() => project(p, f.scope), 'training_execution_plan_unavailable')
  })
  for (const patch of [
    { owner_id: OWNER },
    { estimated_kcal: 10 },
    { xp: 40 },
    { expected_revision: -1 },
    { action: { kind: 'complete_workout' } },
    { action: { kind: 'save_set', exercise_index: 99, set: {} } },
  ])
    it(`rejects client authority and malformed command ${JSON.stringify(patch)}`, () => {
      const f = started()
      expectCode(() => update(f, setCommand(patch)), 'training_execution_invalid_command')
    })
  it('rejects invalid quantities without rounding them into plausible facts', () => {
    for (const [key, value] of [
      ['repetitions', -1],
      ['repetitions', 1.5],
      ['load_kg', -5],
      ['load_kg', Number.POSITIVE_INFINITY],
      ['duration_seconds', -1],
    ] as const) {
      const f = started(),
        cmd = setCommand()
      ;(cmd.action.set as Record<string, unknown>)[key] = value
      expectCode(() => update(f, cmd), 'training_execution_invalid_command')
    }
  })
})

describe('Execution source chronology is proved, not inferred from a claimed date', () => {
  it('refuses a stored session whose claimed clinical date differs from its actual start in the pinned timezone', () => {
    const f = started()
    const session = { ...f.value.session, local_date: '2026-11-12' }
    expectCode(
      () =>
        prepare({
          plan: null,
          scope: { ...f.scope, open_local_date: '2026-11-12' },
          session,
          command: setCommand(),
          prior_receipt: null,
        }),
      'training_execution_state_unavailable',
    )
  })
  it('refuses an original operation receipt predating the session it claims to belong to', () => {
    const f = started(),
      command = setCommand(),
      v = update(f, command)
    f.value = v
    expectCode(
      () => update(f, command, f.scope, { ...v.receipt, at: '2026-11-12T15:30:00Z' }),
      'training_execution_receipt_invalid',
    )
  })
})
