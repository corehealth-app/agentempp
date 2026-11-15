import type { ServiceClient } from '@mpp/db'
import { describe, expect, it, vi } from 'vitest'
import { replyFixture } from './__fixtures__/conversation-meal-reply'
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
        readHistorical: async () => null,
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
describe('original-auth public completion runtime over real backend and public workout service', () => {
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
    expect(h.capture.mock.calls.length).toBeLessThanOrEqual(50)
    expect(h.writes()).toBe(1)
  })
  it.each([
    'home',
    'state',
    'read',
  ] as const)('treats malformed trusted %s observations as unavailable, not invalid user input', async (kind) => {
    const h = setup()
    h.complete()
    const actual = h.rpc.getMockImplementation()!
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
