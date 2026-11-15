import type { ServiceClient } from '@mpp/db'
import { describe, expect, it, vi } from 'vitest'
import { replyFixture } from './__fixtures__/conversation-meal-reply'
import { hashMobileRequest } from './idempotency'
import golden from './testing/training-completion-pg-golden.json'
import { createTrainingExecutionCompletionService } from './training-execution-completion-runtime'

function setup(failFeedback = false) {
  const g = structuredClone(golden),
    owner = g.begin.scope.owner_id,
    auth = g.begin.scope.auth_user_id,
    login = '139d0000-0000-4000-8000-000000000005'
  const who = structuredClone(replyFixture().auth)
  Object.assign(who, {
    authUserId: auth,
    userId: owner,
    accessToken: `e30.${Buffer.from(JSON.stringify({ sub: auth, session_id: login })).toString('base64url')}.synthetic`,
  })
  Object.assign(who.identity, { id: auth })
  Object.assign(who.patient, { id: owner, authUserId: auth, status: 'active' })
  const profile = { ...g.source.context.clinical, observed_at: g.completed.scope.observed_at }
  let completed = false,
    writes = 0
  const rpc = vi.fn(
    async (
      name: string,
      _args: Record<string, unknown>,
    ): Promise<{ data: unknown; error: null }> => {
      if (name === 'submit_training_execution_completion_authenticated') {
        if (!completed) writes++
        completed = true
        return {
          data: {
            status: 'saved',
            source: g.source,
            preparation: g.preparation,
            effect: g.effect,
            completion: g.completed,
          },
          error: null,
        }
      }
      if (name === 'begin_training_execution_completion_authenticated')
        return { data: completed ? { ...g.completed, action: 'replay' } : g.begin, error: null }
      if (name === 'read_training_execution_completion_authenticated')
        return { data: completed ? g.completed : { ...g.begin, action: 'available' }, error: null }
      if (name === 'read_training_execution_state_v2_authenticated')
        return {
          data: completed
            ? { action: 'completion', context: g.completed }
            : { action: 'progress', scope: g.begin.scope, session: g.begin.session },
          error: null,
        }
      if (name === 'read_training_execution_home_v2_authenticated') {
        const s = completed ? g.completed.session : g.begin.session
        return {
          data: {
            scope: completed ? g.completed.scope : g.begin.scope,
            plan: null,
            sessions: [
              {
                id: s.id,
                revision: s.revision,
                local_date: s.local_date,
                started_at: s.started_at,
                updated_at: s.updated_at,
                plan_id: s.definition.plan_id,
                day_index: s.definition.day_index,
                day_label: s.definition.day_label,
                total_exercises: 2,
                completed_exercises: 0,
                phase: s.phase,
                day_closed: false,
                completion: completed
                  ? {
                      id: g.command.operation_id,
                      input_hash: g.begin.completion.input_hash,
                      status: 'completed',
                    }
                  : null,
              },
            ],
            next_cursor: null,
          },
          error: null,
        }
      }
      if (name === 'read_conversation_workout_preparation')
        return {
          data: { action: 'available', source: g.source, preparation: g.preparation },
          error: null,
        }
      if (name === 'read_conversation_workout_effect')
        return { data: completed ? g.effect : { action: 'absent' }, error: null }
      if (name === 'commit_training_execution_completion_authenticated') {
        completed = true
        writes++
        return { data: { action: 'committed', receipt: g.effect.receipt }, error: null }
      }
      if (name === 'reconcile_conversation_workout') return { data: g.reconciliation, error: null }
      throw Error(`Unexpected RPC ${name}`)
    },
  )
  const authPort = {
    verifyAccessToken: vi.fn(async () => who.identity),
    loadPatient: vi.fn(async () => who.patient),
    isAdmin: vi.fn(async () => false),
  }
  const ensureWorkout = vi.fn(async () => {
    if (failFeedback) throw Error('Optional education unavailable')
    return null
  })
  const readHistorical = vi.fn(async (_input: unknown) => null)
  const authorize = vi.fn(async () => {}),
    capture = vi.fn(async () => profile)
  const service = createTrainingExecutionCompletionService(
    { rpc } as unknown as ServiceClient,
    who,
    authorize,
    {
      auth: authPort,
      clinical: { capture },
      feedbackV3WriterEnabled: () => true,
      feedbackV3: () => ({
        ensureWorkout,
        readHistorical,
        readRoot: vi.fn(),
        ensureRoot: vi.fn(),
        ensureReply: vi.fn(),
      }),
    },
  )
  const identity = {
    session_id: g.command.session_id,
    completion_id: g.command.operation_id,
    epoch: g.command.expected_epoch,
    input_hash: g.begin.completion.input_hash,
  }
  return {
    g,
    who,
    rpc,
    authPort,
    ensureWorkout,
    readHistorical,
    authorize,
    capture,
    service,
    identity,
    writes: () => writes,
    complete: () => {
      completed = true
    },
  }
}
function installProgressObservation(h: ReturnType<typeof setup>, exists = true, reserved = false) {
  const s = h.g.begin.session
  const command = exists
    ? {
        schema: 'training.execution.start.v1',
        session_id: s.id,
        operation_id: s.id,
        expected_epoch: s.epoch,
        expected_local_date: s.local_date,
        plan_id: s.definition.plan_id,
        plan_hash: s.definition.plan_hash,
        day_index: s.definition.day_index,
      }
    : {
        schema: 'training.execution.update.v1',
        session_id: s.id,
        operation_id: '14100000-0000-4000-8000-000000000077',
        expected_epoch: s.epoch,
        expected_revision: 0,
        action: { kind: 'mark_exercise', exercise_index: 0, completed: true },
      }
  const receipt = {
    schema: 'training.execution.receipt.v1',
    owner_id: s.owner_id,
    epoch: s.epoch,
    session_id: s.id,
    operation_id: s.id,
    input_hash: hashMobileRequest(command),
    before_revision: null,
    after_revision: 0,
    kind: 'start',
    at: s.started_at,
  }
  const context = reserved ? { ...h.g.begin, action: 'available' } : h.g.completed
  const actual = h.rpc.getMockImplementation()
  if (!actual) throw new Error('Missing original RPC fixture')
  h.rpc.mockImplementation(async (name, args) =>
    name === 'reconcile_training_execution_progress_authenticated'
      ? {
          data: {
            action: exists ? 'available' : 'absent',
            scope: context.scope,
            state: { action: 'completion', context },
            ...(exists ? { command, receipt } : {}),
          },
          error: null,
        }
      : actual(name, args),
  )
  return { command, receipt, key: `texecution1:${command.operation_id}` }
}
describe('original-auth public completion runtime over real backend and public workout service', () => {
  it('recovers an original progress ACK after another device completed without another progress or workout writer', async () => {
    const h = setup()
    h.complete()
    const op = installProgressObservation(h),
      v = await h.service.progress(op.key, op.command)
    expect(v).toMatchObject({
      schema: 'training.execution-mutation.v2',
      status: 'replayed',
      receipt: op.receipt,
      current: { session: { phase: 'completed', revision: 1 } },
    })
    expect(h.writes()).toBe(0)
    expect(
      h.rpc.mock.calls.every(([n]) => n === 'reconcile_training_execution_progress_authenticated'),
    ).toBe(true)
  })
  it('retires only proven-unapplied old CAS work behind a permanent completed state, without inventing a receipt', async () => {
    const h = setup()
    h.complete()
    const op = installProgressObservation(h, false),
      v = await h.service.progress(op.key, op.command)
    expect(v).toMatchObject({
      schema: 'training.execution-mutation.v2',
      status: 'not_applied',
      receipt: null,
      operation_id: op.command.operation_id,
      input_hash: hashMobileRequest(op.command),
      current: { session: { phase: 'completed' } },
    })
    expect(h.writes()).toBe(0)
    expect(
      h.rpc.mock.calls.every(([n]) => n === 'reconcile_training_execution_progress_authenticated'),
    ).toBe(true)
  })
  it('a cancellable finish reservation keeps unresolved progress pending and never masquerades as a permanent rejection', async () => {
    const h = setup(),
      op = installProgressObservation(h, false, true),
      v = await h.service.progress(op.key, op.command)
    expect(v).toMatchObject({
      schema: 'training.execution-mutation.v2',
      status: 'pending',
      receipt: null,
      operation_id: op.command.operation_id,
      current: { session: { phase: 'in_progress' }, completion: { status: 'reserved' } },
    })
    expect(h.writes()).toBe(0)
    expect(
      h.rpc.mock.calls.every(([n]) => n === 'reconcile_training_execution_progress_authenticated'),
    ).toBe(true)
  })
  it('recovers an owned completed session after a cold start without requiring a source text or admitting a command', async () => {
    const h = setup()
    h.complete()
    const value = await h.service.state(h.identity.session_id, h.identity.epoch)
    expect(value).toMatchObject({
      schema: 'training.execution-state.v2',
      session: { phase: 'completed' },
      completion: { status: 'completed' },
    })
    expect(h.writes()).toBe(0)
    expect(h.ensureWorkout).not.toHaveBeenCalled()
  })
  it('v2 discovery includes actual completed history with its completion correlation while keeping prescribed sets separate', async () => {
    const h = setup()
    h.complete()
    const value = await h.service.home()
    expect(value).toMatchObject({
      schema: 'training.execution-home.v2',
      sessions: [
        {
          phase: 'completed',
          total_exercises: 2,
          completed_exercises: 0,
          completion: {
            id: h.identity.completion_id,
            input_hash: h.identity.input_hash,
            status: 'completed',
          },
        },
      ],
    })
    expect(h.writes()).toBe(0)
    expect(h.ensureWorkout).not.toHaveBeenCalled()
  })
  it('v2 state also reads actual v1 progress without pretending that it completed an activity', async () => {
    const h = setup(),
      value = await h.service.state(h.identity.session_id, h.identity.epoch)
    expect(value).toMatchObject({
      schema: 'training.execution-state.v2',
      session: { phase: 'in_progress', revision: 0 },
      completion: null,
    })
    expect(h.writes()).toBe(0)
  })
  it('returns safe completed actuals, seals optional existing feedback and never uses the ordinary writer', async () => {
    const h = setup(),
      value = await h.service.submit(`tfinish1:${h.g.command.operation_id}`, h.g.command)
    expect(value).toMatchObject({
      schema: 'training.execution-completion.v1',
      status: 'completed',
      session: { phase: 'completed' },
      workout: { workout_type: 'full_body', duration_min: 30 },
    })
    expect(h.writes()).toBe(1)
    expect(h.ensureWorkout).toHaveBeenCalledTimes(1)
    expect(h.rpc.mock.calls.some(([n]) => n === 'commit_conversation_workout')).toBe(false)
    expect(JSON.stringify(value)).not.toMatch(
      /"(clinical|source_input|prepared|frozen_state|workout_hash|auth_session_id|command|source_hash|strength_capture)":/,
    )
  })
  it('repeated finish recovers the same receipt without another workout', async () => {
    const h = setup(),
      first = await h.service.submit(`tfinish1:${h.g.command.operation_id}`, h.g.command)
    const again = await h.service.submit(`tfinish1:${h.g.command.operation_id}`, h.g.command)
    expect(again.receipt).toEqual(first.receipt)
    expect(again.workout).toEqual(first.workout)
    expect(h.writes()).toBe(1)
  })
  it('optional feedback failure never changes a completed outcome to failed or repeats its registration', async () => {
    const h = setup(true),
      value = await h.service.submit(`tfinish1:${h.g.command.operation_id}`, h.g.command)
    expect(value.status).toBe('completed')
    expect(value.feedback).toBeNull()
    expect(h.writes()).toBe(1)
  })
  it('cold read binds the server-owned command to the requested session and hash, with no source text in a query or second registration', async () => {
    const h = setup()
    h.complete()
    const value = await h.service.read(h.identity)
    expect(value).toMatchObject({ status: 'completed', completion_id: h.identity.completion_id })
    expect(h.writes()).toBe(0)
    expect(h.ensureWorkout).not.toHaveBeenCalled()
    expect(
      h.rpc.mock.calls.every(([n]) =>
        [
          'read_training_execution_completion_authenticated',
          'reconcile_conversation_workout',
        ].includes(n),
      ),
    ).toBe(true)
  })
  it.each([
    { session_id: '139d0000-0000-4000-8000-000000000099' },
    { input_hash: 'a'.repeat(64) },
  ])('refuses changed cold-read correlation without exposing a receipt: %j', async (change) => {
    const h = setup()
    h.complete()
    await expect(h.service.read({ ...h.identity, ...change })).rejects.toMatchObject({
      status: 409,
    })
    expect(h.writes()).toBe(0)
    expect(h.ensureWorkout).not.toHaveBeenCalled()
  })
  it('never swallows a mandatory scope change during optional education after the domain commit', async () => {
    const h = setup()
    h.ensureWorkout.mockImplementation(async () => {
      h.authPort.isAdmin.mockResolvedValue(true)
      return null
    })
    await expect(
      h.service.submit(`tfinish1:${h.g.command.operation_id}`, h.g.command),
    ).rejects.toThrow()
    expect(h.writes()).toBe(1)
    await expect(
      h.service.submit(`tfinish1:${h.g.command.operation_id}`, h.g.command),
    ).rejects.toThrow()
    expect(h.writes()).toBe(1)
  })
  it('does not duplicate current-scope provider work in two wrappers around the same protected RPC', async () => {
    const h = setup()
    await h.service.submit(`tfinish1:${h.g.command.operation_id}`, h.g.command)
    // A bounded registration must not perform two identical before/after
    // observations at EVERY SQL boundary. The backend already owns that fence.
    expect(h.capture.mock.calls.length).toBeLessThanOrEqual(3)
    expect(h.writes()).toBe(1)
  })
  it('returns the proved workout through the current-safe feedback renderer without re-reconciling the saved domain', async () => {
    const h = setup()
    const value = await h.service.submit(`tfinish1:${h.g.command.operation_id}`, h.g.command)
    expect(value.status).toBe('completed')
    expect(h.rpc.mock.calls.map(([n]) => n)).toEqual([
      'submit_training_execution_completion_authenticated',
    ])
    expect(h.readHistorical).toHaveBeenCalledTimes(1)
    expect(h.readHistorical.mock.calls[0]?.[0]).toMatchObject({
      auth: h.who,
      proof: { kind: 'workout.report', effect: h.g.effect, prepared: h.g.preparation.prepared },
    })
    expect(h.writes()).toBe(1)
  })
  it('recovers a lost atomic reply by observation only, never resubmitting a finish', async () => {
    const h = setup(),
      original = h.rpc.getMockImplementation()
    if (!original) throw Error('Missing boundary fixture')
    h.rpc.mockImplementation(async (name, args) => {
      const v = await original(name, args)
      if (name === 'submit_training_execution_completion_authenticated')
        throw Error('Lost after commit')
      return v
    })
    expect(
      await h.service.submit(`tfinish1:${h.g.command.operation_id}`, h.g.command),
    ).toMatchObject({ status: 'completed' })
    expect(h.writes()).toBe(1)
    expect(
      h.rpc.mock.calls.filter(([n]) => n === 'submit_training_execution_completion_authenticated'),
    ).toHaveLength(1)
  })
  it.each([
    'home',
    'state',
    'read',
  ] as const)('treats malformed trusted %s observations as unavailable, not invalid user input', async (kind) => {
    const h = setup()
    h.complete()
    const actual = h.rpc.getMockImplementation()
    if (!actual) throw new Error('Missing original RPC fixture')
    h.rpc.mockImplementation(async (name, args) => {
      if (
        (kind === 'home' && name === 'read_training_execution_home_v2_authenticated') ||
        (kind === 'state' && name === 'read_training_execution_state_v2_authenticated') ||
        (kind === 'read' && name === 'read_training_execution_completion_authenticated')
      )
        return { data: { action: 'unexpected', private_data: 'never expose' }, error: null }
      return actual(name, args)
    })
    const request =
      kind === 'home'
        ? h.service.home()
        : kind === 'state'
          ? h.service.state(h.identity.session_id, h.identity.epoch)
          : h.service.read(h.identity)
    await expect(request).rejects.toMatchObject({
      status: 503,
      code: 'training_completion_unavailable',
    })
    expect(h.writes()).toBe(0)
  })
  it('fails changed current Auth before any protected domain operation', async () => {
    const h = setup()
    h.authPort.isAdmin.mockResolvedValue(true)
    await expect(
      h.service.submit(`tfinish1:${h.g.command.operation_id}`, h.g.command),
    ).rejects.toThrow()
    expect(h.rpc).not.toHaveBeenCalled()
  })
})

describe('original finish resolution keeps observation and explicit withdrawal separate', () => {
  function install(
    h: ReturnType<typeof setup>,
    action: 'absent' | 'available' | 'withdrawn' = 'absent',
  ) {
    const c = h.g.command,
      request = {
        session_id: c.session_id,
        operation_id: c.operation_id,
        epoch: c.expected_epoch,
        before_revision: c.expected_revision,
        input_hash: h.g.begin.completion.input_hash,
      },
      scope = h.g.begin.scope
    const raw = {
      action,
      request,
      scope,
      state: { action: 'progress', scope, session: h.g.begin.session },
      ...(action === 'available' ? { completion: { ...h.g.begin, action: 'available' } } : {}),
      ...(action === 'withdrawn'
        ? {
            withdrawal: {
              schema: 'training.execution-finish-withdrawal.v1',
              ...request,
              owner_id: scope.owner_id,
              auth_user_id: scope.auth_user_id,
              at: scope.observed_at,
            },
          }
        : {}),
    }
    const original = h.rpc.getMockImplementation()
    if (!original) throw Error('Missing actual fixture')
    h.rpc.mockImplementation(async (name, args) =>
      name === 'observe_training_execution_finish_authenticated' ||
      name === 'withdraw_training_execution_finish_authenticated'
        ? { data: raw, error: null }
        : original(name, args),
    )
    const body = (mode: 'observe' | 'withdraw') => ({
      schema: 'training.execution.finish-resolution.v1',
      mode,
      command: c,
    })
    return {
      raw,
      body,
      key: (mode: 'observe' | 'withdraw') => `tresolve1:${mode}:${c.operation_id}`,
    }
  }
  it('observes a never-admitted exact command without executing it or creating education', async () => {
    const h = setup(),
      f = install(h)
    expect(await h.service.resolveFinish(f.key('observe'), f.body('observe'))).toMatchObject({
      status: 'ready',
      mode: 'observe',
      completion: null,
    })
    const call = h.rpc.mock.calls.find(
      ([n]) => n === 'observe_training_execution_finish_authenticated',
    )
    expect(call?.[1]).toEqual({
      p_user_id: h.g.begin.scope.owner_id,
      p_auth_user_id: h.g.begin.scope.auth_user_id,
      p_auth_session_id: '139d0000-0000-4000-8000-000000000005',
      p_command: h.g.command,
    })
    expect(
      h.rpc.mock.calls.some(
        ([n]) => n.startsWith('begin_') || n.startsWith('commit_') || n.startsWith('withdraw_'),
      ),
    ).toBe(false)
    expect(h.ensureWorkout).not.toHaveBeenCalled()
    expect(h.writes()).toBe(0)
  })
  it('withdraws only explicitly, returns the bound marker and never treats ready/reserved as cancellation', async () => {
    for (const action of ['withdrawn', 'absent', 'available'] as const) {
      const h = setup(),
        f = install(h, action),
        pending = h.service.resolveFinish(f.key('withdraw'), f.body('withdraw'))
      if (action === 'withdrawn')
        expect(await pending).toMatchObject({
          status: 'withdrawn',
          mode: 'withdraw',
          completion: null,
        })
      else await expect(pending).rejects.toMatchObject({ status: 503 })
      expect(h.writes()).toBe(0)
      expect(h.ensureWorkout).not.toHaveBeenCalled()
    }
  })
  it('rejects wrong mode keys and extra fields before any provider observation', async () => {
    const h = setup(),
      f = install(h)
    await expect(
      h.service.resolveFinish(f.key('observe'), f.body('withdraw')),
    ).rejects.toBeDefined()
    await expect(
      h.service.resolveFinish(f.key('observe'), { ...f.body('observe'), extra: true }),
    ).rejects.toBeDefined()
    expect(h.rpc).not.toHaveBeenCalled()
    expect(h.capture).not.toHaveBeenCalled()
  })
  it('never publishes an observation after the original authentication disappears', async () => {
    const h = setup(),
      f = install(h),
      original = h.rpc.getMockImplementation()
    if (!original) throw Error('Missing fixture')
    h.rpc.mockImplementation(async (name, args) => {
      const result = await original(name, args)
      if (name === 'observe_training_execution_finish_authenticated')
        h.authPort.verifyAccessToken.mockRejectedValue(Error('Expired original login'))
      return result
    })
    await expect(h.service.resolveFinish(f.key('observe'), f.body('observe'))).rejects.toBeDefined()
    expect(h.writes()).toBe(0)
  })
})
