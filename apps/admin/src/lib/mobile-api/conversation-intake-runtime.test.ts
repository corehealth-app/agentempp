import type { ServiceClient } from '@mpp/db'
import { describe, expect, it, vi } from 'vitest'
import { replyFixture } from './__fixtures__/conversation-meal-reply'
import {
  writerBinding,
  writerCommand,
  writerEpoch,
  writerPrepared,
  writerReceipt,
} from './__fixtures__/conversation-meal-writer'
import { clinical } from './__fixtures__/feedback-v2-source'
import { bindConversationCommand } from './conversation-command-contracts'
import type { ConversationReadonlyAuth } from './conversation-current-scope'
import {
  bindConversationIntake,
  type ConversationIntakeRoutingDecision,
} from './conversation-intake-contracts'
import { createConversationIntakeRoutes } from './conversation-intake-routes'
import { createConversationIntakeRuntime } from './conversation-intake-runtime'
import { bindConversationWorkoutCommand, workoutDigest } from './conversation-workout-contracts'
import type { CurrentClinicalStateSource } from './current-clinical-state'
import actualWorkout from './testing/conversation-workout-reconcile-pg-golden.json'

const intakeId = 'c3cc0000-0000-4000-8000-000000000039'

function required<T>(value: T | null | undefined): T {
  if (value == null) throw new Error('Missing qualified test fixture')
  return value
}

function original() {
  const f = replyFixture(),
    command = bindConversationIntake(f.auth.userId, `cintake1:${intakeId}`, {
      intake_protocol: 'conversation.intake.v1',
      intake_id: intakeId,
      source: { channel: 'text', text: 'Fiz 30 minutos de caminhada.' },
    }),
    lookup = {
      ownerId: command.ownerId,
      intakeId: command.intakeId,
      inputHash: command.inputHash,
      epoch: f.identity.epoch,
    }
  return { ...f, command, lookup }
}

/** SDK/Auth/clinical/provider boundaries only. All stores, current-scope,
 * driver and typed command services under test are the production defaults. */
function setup() {
  const f = original(),
    authPort = {
      verifyAccessToken: vi.fn<ConversationReadonlyAuth['verifyAccessToken']>(
        async () => f.auth.identity,
      ),
      loadPatient: vi.fn<ConversationReadonlyAuth['loadPatient']>(async () => f.auth.patient),
      isAdmin: vi.fn<ConversationReadonlyAuth['isAdmin']>(async () => false),
    },
    capture = vi.fn<CurrentClinicalStateSource['capture']>(async () => f.profile),
    binding = {
      owner_id: f.lookup.ownerId,
      intake_id: intakeId,
      input_hash: f.command.inputHash,
      epoch: f.lookup.epoch,
      admitted_at: '2026-11-05T12:00:00.000001Z',
    },
    context = {
      schema: 'conversation.intake-source.v1',
      ...binding,
      source_input: f.command.input,
      captured_at: '2026-11-05T12:00:00.000002Z',
      time_zone: 'UTC',
      local_date: '2026-11-05',
      media: null,
    },
    sourceHash = 'a'.repeat(64),
    claimId = 'c3cc0000-0000-4000-8000-000000000041',
    childId = 'c3cc0000-0000-4000-8000-000000000040'
  let admitted = false,
    captured = false,
    claimed = false,
    sealed: ReturnType<typeof selection> | null = null
  function selection(kind: 'meal.report' | 'workout.report' | 'not_reported' = 'workout.report') {
    const decision = {
        schema: 'conversation.intake-routing.v1' as const,
        kind,
        reason: 'performed_activity',
      },
      input = {
        command_protocol: 'conversation.command.v1' as const,
        command_id: childId,
        kind,
        source: {
          channel: 'text' as const,
          text: f.command.input.source.channel === 'text' ? f.command.input.source.text : '',
        },
      },
      child =
        kind === 'meal.report'
          ? bindConversationCommand(f.lookup.ownerId, `cmsg1:${childId}`, input)
          : kind === 'workout.report'
            ? bindConversationWorkoutCommand(f.lookup.ownerId, `cmsg1:${childId}`, input)
            : null
    return {
      schema: 'conversation.intake-selection.v1' as const,
      intake: binding,
      source_hash: sourceHash,
      decision_hash: workoutDigest(decision),
      decision,
      selected_at: '2026-11-05T12:00:00.000004Z',
      command: child
        ? {
            kind: child.command.kind,
            owner_id: child.ownerId,
            command_id: child.commandId,
            input_hash: child.inputHash,
            epoch: f.lookup.epoch,
            admitted_at: '2026-11-05T12:00:00.000003Z',
            input: child.command,
          }
        : null,
    }
  }
  const route = vi.fn(async (): Promise<ConversationIntakeRoutingDecision> => selection().decision),
    createRouter = vi.fn(() => ({ route })),
    rpc = vi.fn(
      async (
        name: string,
        _args: Record<string, unknown>,
      ): Promise<{ data: unknown; error: unknown }> => {
        if (name === 'read_conversation_intake')
          return {
            data: admitted
              ? {
                  action: 'available',
                  intake: binding,
                  source_input: f.command.input,
                  source_hash: captured ? sourceHash : null,
                  claimed,
                  selection: sealed,
                }
              : { action: 'absent' },
            error: null,
          }
        if (name === 'admit_conversation_intake') {
          admitted = true
          return { data: { action: 'admitted', intake: binding }, error: null }
        }
        if (name === 'capture_conversation_intake_source') {
          captured = true
          return { data: { action: 'captured', source_hash: sourceHash, context }, error: null }
        }
        if (name === 'claim_conversation_intake_routing') {
          if (claimed) return { data: { action: 'already_claimed' }, error: null }
          claimed = true
          return { data: { action: 'claimed', claim_id: claimId }, error: null }
        }
        if (name === 'seal_conversation_intake_routing') {
          const d = _args.p_decision as ConversationIntakeRoutingDecision
          if (d.kind === 'clarification_required') throw new Error('Not a fixture decision')
          sealed = selection(d.kind)
          return { data: { action: 'sealed', selection: sealed }, error: null }
        }
        if (name === 'reconcile_conversation_workout' || name === 'read_conversation_meal_command')
          return { data: { action: 'absent' }, error: null }
        throw new Error(`SDK boundary unavailable: ${name}`)
      },
    ),
    ports = {
      createRouter,
      enabled: vi.fn(() => true),
      mealEnabled: vi.fn(() => true),
      workoutEnabled: vi.fn(() => true),
      auth: authPort,
      clinical: { capture },
    },
    create = () =>
      createConversationIntakeRuntime({ rpc } as unknown as ServiceClient, f.auth, f.lookup, ports)
  return {
    ...f,
    authPort,
    capture,
    binding,
    context,
    sourceHash,
    claimId,
    childId,
    selection,
    route,
    createRouter,
    rpc,
    ports,
    create,
    seal(kind: 'meal.report' | 'workout.report' = 'workout.report') {
      admitted = captured = claimed = true
      sealed = selection(kind)
    },
    claimed() {
      admitted = captured = claimed = true
    },
  }
}

describe('actual request-bound routing recovery adapter', () => {
  function configure(h: ReturnType<typeof setup>, terminal = false, revoke = false) {
    h.claimed()
    const originalRPC = required(h.rpc.getMockImplementation()),
      decision = h.selection('not_reported').decision
    h.rpc.mockImplementation(async (name, args) => {
      if (name === 'read_conversation_intake_routing_result') {
        if (revoke) h.authPort.isAdmin.mockResolvedValueOnce(true)
        return {
          data: {
            action: 'available',
            intake: h.binding,
            source_hash: h.sourceHash,
            claim_id: h.claimId,
            lease_anchor_at: '2026-11-05T12:00:00.000003Z',
            lease_clock_origin: 'claim',
            result: terminal
              ? {
                  schema: 'conversation.intake-routing-result.v1',
                  decision_hash: workoutDigest(decision),
                  decision,
                  recorded_at: '2026-11-05T12:00:00.000004Z',
                  origin: 'router',
                }
              : null,
          },
          error: null,
        }
      }
      if (name === 'reconcile_conversation_intake_routing')
        return { data: { action: 'in_flight' }, error: null }
      return originalRPC(name, args)
    })
  }
  it('resumes a durable original non-recording decision through the physical adapter without provider', async () => {
    const h = setup()
    configure(h, true)
    expect(await h.create().submit(h.command)).toMatchObject({ status: 'not_recorded' })
    expect(h.rpc.mock.calls.map(([name]) => name)).toEqual([
      'read_conversation_intake',
      'read_conversation_intake_routing_result',
      'read_conversation_intake',
      'seal_conversation_intake_routing',
    ])
    expect(h.rpc.mock.calls[1]?.[1]).toEqual({
      p_user_id: h.lookup.ownerId,
      p_intake_id: intakeId,
      p_input_hash: h.lookup.inputHash,
      p_expected_epoch: h.lookup.epoch,
      p_source_hash: h.sourceHash,
    })
    expect(h.createRouter).not.toHaveBeenCalled()
  })
  it('uses SQL reconciliation once on the same original binding and claim', async () => {
    const h = setup()
    configure(h)
    expect(await h.create().submit(h.command)).toMatchObject({
      status: 'pending',
      reason: 'routing_reconciliation_required',
    })
    const calls = h.rpc.mock.calls.filter(
      ([name]) => name === 'reconcile_conversation_intake_routing',
    )
    expect(calls).toHaveLength(1)
    expect(calls[0]?.[1]).toEqual({
      p_user_id: h.lookup.ownerId,
      p_intake_id: intakeId,
      p_input_hash: h.lookup.inputHash,
      p_expected_epoch: h.lookup.epoch,
      p_source_hash: h.sourceHash,
      p_claim_id: h.claimId,
    })
    expect(h.rpc.mock.calls.some(([name]) => name === 'seal_conversation_intake_routing')).toBe(
      false,
    )
    expect(h.createRouter).not.toHaveBeenCalled()
  })
  it('a physical proof read that observes temporary admin membership cannot proceed after it heals', async () => {
    const h = setup()
    configure(h, false, true)
    const runtime = h.create()
    await expect(runtime.submit(h.command)).rejects.toMatchObject({
      code: 'patient_admin_account_conflict',
    })
    await expect(runtime.read()).rejects.toMatchObject({ code: 'patient_admin_account_conflict' })
    expect(h.rpc.mock.calls.map(([name]) => name)).toEqual([
      'read_conversation_intake',
      'read_conversation_intake_routing_result',
    ])
    expect(h.createRouter).not.toHaveBeenCalled()
  })
})

type MealBoundaryControls = {
  authPort: {
    verifyAccessToken: ReturnType<typeof vi.fn<ConversationReadonlyAuth['verifyAccessToken']>>
    loadPatient: ReturnType<typeof vi.fn<ConversationReadonlyAuth['loadPatient']>>
    isAdmin: ReturnType<typeof vi.fn<ConversationReadonlyAuth['isAdmin']>>
  }
  mealEnabled: ReturnType<typeof vi.fn<() => boolean>>
}
// External SQL/Auth boundaries only: the real meal facade, writer, default
// feedback composition and neutral runtime all run without a replacement ACK.
function guardedMealBoundary(
  pending = false,
  onRpc?: (name: string, controls: MealBoundaryControls) => void,
) {
  const original = replyFixture(),
    typed = writerCommand(),
    receipt = writerReceipt(),
    auth = {
      ...original.auth,
      userId: typed.ownerId,
      patient: { ...original.auth.patient, id: typed.ownerId },
    },
    authPort = {
      verifyAccessToken: vi.fn<ConversationReadonlyAuth['verifyAccessToken']>(
        async () => auth.identity,
      ),
      loadPatient: vi.fn<ConversationReadonlyAuth['loadPatient']>(async () => auth.patient),
      isAdmin: vi.fn<ConversationReadonlyAuth['isAdmin']>(async () => false),
    },
    mealEnabled = vi.fn(() => true),
    profile = JSON.parse(
      JSON.stringify(clinical())
        .replaceAll(clinical().epoch, writerEpoch)
        .replaceAll('2026-11-03', '2026-11-05'),
    ),
    command = bindConversationIntake(auth.userId, `cintake1:${intakeId}`, {
      intake_protocol: 'conversation.intake.v1',
      intake_id: intakeId,
      meal_type_hint: typed.command.meal_type,
      source: typed.command.source,
    }),
    binding = {
      owner_id: auth.userId,
      intake_id: intakeId,
      input_hash: command.inputHash,
      epoch: writerEpoch,
      admitted_at: '2026-11-04T11:59:59Z',
    },
    decision = {
      schema: 'conversation.intake-routing.v1',
      kind: 'meal.report',
      reason: 'performed_meal',
    },
    selection = {
      schema: 'conversation.intake-selection.v1',
      intake: binding,
      source_hash: 'b'.repeat(64),
      decision_hash: workoutDigest(decision),
      decision,
      selected_at: '2026-11-04T12:00:00.000002Z',
      command: {
        kind: 'meal.report',
        owner_id: auth.userId,
        command_id: typed.commandId,
        input_hash: typed.inputHash,
        epoch: writerEpoch,
        admitted_at: writerBinding().admitted_at,
        input: typed.command,
      },
    },
    prepared = { ...writerPrepared(), receipt: pending ? null : receipt },
    rpc = vi.fn(async (name: string) => {
      onRpc?.(name, { authPort, mealEnabled })
      if (name === 'read_conversation_intake')
        return {
          data: {
            action: 'available',
            intake: binding,
            source_input: command.input,
            source_hash: selection.source_hash,
            claimed: true,
            selection,
          },
          error: null,
        }
      if (name === 'read_conversation_meal_prepared') return { data: prepared, error: null }
      if (name === 'read_conversation_meal_command')
        return {
          data: {
            action: 'available',
            command: writerBinding(),
            state: 'admitted',
            source_input: typed.command,
            candidate: null,
            candidate_hash: null,
          },
          error: null,
        }
      if (
        name === 'read_conversation_meal_decision' ||
        name === 'read_mobile_registration_feedback_v3'
      )
        return { data: { action: 'absent' }, error: null }
      if (name === 'commit_conversation_meal')
        return { data: { action: 'committed', receipt }, error: null }
      if (name === 'get_mobile_current_clinical_state') return { data: profile, error: null }
      throw new Error('No admission, interpreter or writer for a durable original')
    }),
    createRouter = vi.fn(),
    api = createConversationIntakeRuntime(
      {
        rpc,
        from: () => {
          throw new Error('No table operation in read-only feedback fixture')
        },
      } as unknown as ServiceClient,
      auth,
      { ownerId: auth.userId, intakeId, inputHash: command.inputHash, epoch: writerEpoch },
      {
        enabled: () => true,
        mealEnabled,
        workoutEnabled: () => true,
        createRouter,
        auth: authPort,
        clinical: { capture: async () => profile },
      },
    )
  return { api, command, receipt, auth, rpc, authPort, mealEnabled, createRouter }
}

describe('private request-bound intake runtime', () => {
  it('is default OFF before any Auth, router, neutral or typed work', () => {
    const f = original(),
      rpc = vi.fn(),
      createRouter = vi.fn()
    expect(() =>
      createConversationIntakeRuntime({ rpc } as unknown as ServiceClient, f.auth, f.lookup, {
        createRouter,
      }),
    ).toThrowError(expect.objectContaining({ code: 'conversation_intake_unavailable' }))
    expect(rpc).not.toHaveBeenCalled()
    expect(createRouter).not.toHaveBeenCalled()
  })
  it.each([
    'mealEnabled',
    'workoutEnabled',
  ] as const)('requires %s before neutral admission and constructing a router', (gate) => {
    const h = setup()
    h.ports[gate].mockReturnValue(false)
    expect(h.create).toThrowError(
      expect.objectContaining({ code: 'conversation_intake_unavailable' }),
    )
    expect(h.authPort.verifyAccessToken).not.toHaveBeenCalled()
    expect(h.rpc).not.toHaveBeenCalled()
    expect(h.createRouter).not.toHaveBeenCalled()
  })

  it('pins capability methods with their original receiver and closes forever on a later throw', async () => {
    const h = setup(),
      policy = {
        ...h.ports,
        value: true,
        enabled() {
          return this.value
        },
      },
      runtime = createConversationIntakeRuntime(
        { rpc: h.rpc } as unknown as ServiceClient,
        h.auth,
        h.lookup,
        policy,
      )
    policy.enabled = () => true
    policy.value = false
    await expect(runtime.read()).rejects.toMatchObject({ code: 'conversation_intake_unavailable' })
    policy.value = true
    await expect(runtime.submit(h.command)).rejects.toMatchObject({
      code: 'conversation_intake_unavailable',
    })
    expect(h.rpc).not.toHaveBeenCalled()
    const throwing = setup(),
      api = throwing.create()
    throwing.ports.enabled.mockImplementation(() => {
      throw new Error('policy unavailable')
    })
    await expect(api.read()).rejects.toMatchObject({ code: 'conversation_intake_unavailable' })
    throwing.ports.enabled.mockReturnValue(true)
    await expect(api.read()).rejects.toMatchObject({ code: 'conversation_intake_unavailable' })
    expect(throwing.rpc).not.toHaveBeenCalled()
  })

  it('rejects an original owner mismatch before any physical operation', () => {
    const h = setup()
    h.lookup.ownerId = h.auth.authUserId
    expect(h.create).toThrowError(expect.objectContaining({ code: 'conversation_intake_changed' }))
    expect(h.rpc).not.toHaveBeenCalled()
    expect(h.authPort.verifyAccessToken).not.toHaveBeenCalled()
  })

  it('pins the original Auth and lookup before external aliases can change', async () => {
    const h = setup(),
      api = h.create(),
      originalToken = h.auth.accessToken,
      originalEpoch = h.lookup.epoch,
      originalOwner = h.lookup.ownerId
    h.auth.accessToken = 'changed-external-token'
    h.auth.patient.status = 'blocked'
    h.lookup.epoch = h.auth.authUserId
    h.lookup.ownerId = h.auth.authUserId
    h.authPort.loadPatient.mockResolvedValue({
      ...h.auth.patient,
      id: originalOwner,
      status: 'active',
    })
    const result = await api.read()
    expect(result).toMatchObject({
      status: 'absent',
      lookup: { ownerId: originalOwner, epoch: originalEpoch },
    })
    expect(
      h.authPort.verifyAccessToken.mock.calls.every(([token]) => token === originalToken),
    ).toBe(true)
    expect(h.rpc).toHaveBeenCalledWith('read_conversation_intake', {
      p_user_id: originalOwner,
      p_intake_id: intakeId,
      p_input_hash: h.command.inputHash,
      p_expected_epoch: originalEpoch,
    })
  })

  it('read is only observational and never constructs a router or a typed submit', async () => {
    const h = setup(),
      api = h.create()
    expect(await api.read()).toMatchObject({ status: 'absent' })
    expect(h.rpc.mock.calls.map(([name]) => name)).toEqual(['read_conversation_intake'])
    expect(h.createRouter).not.toHaveBeenCalled()
    expect(h.route).not.toHaveBeenCalled()
    expect(h.authPort.isAdmin).toHaveBeenCalledWith(h.auth.authUserId)
    expect(h.auth.authUserId).not.toBe(h.auth.userId)
    expect(
      h.capture.mock.calls.every(
        ([request]) =>
          request.userId === h.auth.userId &&
          request.expectedEpoch === h.lookup.epoch &&
          request.mode === 'profile',
      ),
    ).toBe(true)
  })

  it('refuses a different bound intake and latches that original lookup', async () => {
    const h = setup(),
      api = h.create(),
      other = bindConversationIntake(h.auth.userId, `cintake1:${h.childId}`, {
        ...h.command.input,
        intake_id: h.childId,
      })
    await expect(api.submit(other)).rejects.toMatchObject({ code: 'conversation_intake_changed' })
    await expect(api.read()).rejects.toMatchObject({ code: 'conversation_intake_changed' })
    expect(h.rpc).not.toHaveBeenCalled()
  })

  it('a revoked token closes the same runtime even after the token port recovers', async () => {
    const h = setup(),
      api = h.create()
    h.authPort.verifyAccessToken.mockResolvedValueOnce(null)
    await expect(api.read()).rejects.toMatchObject({ code: 'invalid_access_token' })
    h.authPort.verifyAccessToken.mockResolvedValue(h.auth.identity)
    await expect(api.submit(h.command)).rejects.toMatchObject({ code: 'invalid_access_token' })
    expect(h.rpc).not.toHaveBeenCalled()
  })

  it('ANY admin membership after the physical neutral read stops all admission and reconcile attempts', async () => {
    const h = setup(),
      api = h.create(),
      physical = required(h.rpc.getMockImplementation())
    h.rpc.mockImplementation(async (name, args) => {
      const response = await physical(name, args)
      h.authPort.isAdmin.mockResolvedValue(true)
      return response
    })
    await expect(api.submit(h.command)).rejects.toMatchObject({
      code: 'patient_admin_account_conflict',
    })
    h.authPort.isAdmin.mockResolvedValue(false)
    await expect(api.read()).rejects.toMatchObject({ code: 'patient_admin_account_conflict' })
    expect(h.rpc.mock.calls.map(([name]) => name)).toEqual(['read_conversation_intake'])
    expect(h.createRouter).not.toHaveBeenCalled()
  })

  it('mapping revocation after capture cannot be healed by a later valid callback', async () => {
    const h = setup(),
      api = h.create(),
      physical = required(h.rpc.getMockImplementation())
    h.rpc.mockImplementation(async (name, args) => {
      const response = await physical(name, args)
      if (name === 'capture_conversation_intake_source')
        h.authPort.loadPatient.mockResolvedValue({ ...h.auth.patient, id: h.auth.authUserId })
      return response
    })
    await expect(api.submit(h.command)).rejects.toMatchObject({
      code: 'conversation_patient_changed',
    })
    h.authPort.loadPatient.mockResolvedValue(h.auth.patient)
    await expect(api.read()).rejects.toMatchObject({ code: 'conversation_patient_changed' })
    expect(h.rpc.mock.calls.map(([name]) => name)).toEqual([
      'read_conversation_intake',
      'admit_conversation_intake',
      'capture_conversation_intake_source',
    ])
    expect(h.route).not.toHaveBeenCalled()
  })

  it('epoch revocation at claim cannot reach seal or any typed service', async () => {
    const h = setup(),
      api = h.create(),
      physical = required(h.rpc.getMockImplementation())
    h.rpc.mockImplementation(async (name, args) => {
      const response = await physical(name, args)
      if (name === 'claim_conversation_intake_routing')
        h.capture.mockResolvedValue({ ...h.profile, epoch: h.auth.authUserId })
      return response
    })
    await expect(api.submit(h.command)).rejects.toMatchObject({
      code: 'mobile_current_clinical_invalid_response',
    })
    h.capture.mockResolvedValue(h.profile)
    await expect(api.read()).rejects.toMatchObject({
      code: 'mobile_current_clinical_invalid_response',
    })
    expect(h.rpc.mock.calls.map(([name]) => name)).toEqual([
      'read_conversation_intake',
      'admit_conversation_intake',
      'capture_conversation_intake_source',
      'claim_conversation_intake_routing',
    ])
    expect(h.route).not.toHaveBeenCalled()
  })

  it('capability loss during a physical RPC closes before seal and stays closed', async () => {
    const h = setup(),
      api = h.create(),
      physical = required(h.rpc.getMockImplementation())
    h.rpc.mockImplementation(async (name, args) => {
      const response = await physical(name, args)
      h.ports.workoutEnabled.mockReturnValue(false)
      return response
    })
    await expect(api.submit(h.command)).rejects.toMatchObject({
      code: 'conversation_intake_unavailable',
    })
    h.ports.workoutEnabled.mockReturnValue(true)
    await expect(api.read()).rejects.toMatchObject({ code: 'conversation_intake_unavailable' })
    expect(h.rpc.mock.calls.map(([name]) => name)).toEqual(['read_conversation_intake'])
  })

  it('pins the SDK response before a post-observation can mutate its source alias', async () => {
    const h = setup(),
      api = h.create()
    let mutate: (() => void) | null = null
    h.capture.mockImplementation(async () => {
      mutate?.()
      mutate = null
      return h.profile
    })
    h.rpc.mockImplementation(async () => {
      const envelope = { data: { action: 'absent' }, error: null }
      mutate = () => {
        envelope.data.action = 'input_conflict'
      }
      return envelope
    })
    expect(await api.read()).toMatchObject({ status: 'absent' })
    expect(h.rpc).toHaveBeenCalledTimes(1)
  })

  it('an SDK throw still performs the shared post-check and cannot reconcile after revocation', async () => {
    const h = setup(),
      api = h.create()
    h.rpc.mockImplementation(async () => {
      h.authPort.isAdmin.mockResolvedValue(true)
      throw new Error('SDK transport lost')
    })
    await expect(api.submit(h.command)).rejects.toMatchObject({
      code: 'patient_admin_account_conflict',
    })
    expect(h.rpc).toHaveBeenCalledTimes(1)
    expect(h.route).not.toHaveBeenCalled()
  })

  it('unknown routing outcome keeps the single claim and only reconciles by reads', async () => {
    const h = setup(),
      api = h.create()
    h.route.mockRejectedValue(new Error('Provider outcome unknown'))
    expect(await api.submit(h.command)).toMatchObject({
      status: 'pending',
      reason: 'routing_reconciliation_required',
    })
    expect(await api.read()).toMatchObject({
      status: 'pending',
      reason: 'routing_reconciliation_required',
    })
    expect(await api.submit(h.command)).toMatchObject({
      status: 'pending',
      reason: 'routing_reconciliation_required',
    })
    expect(h.route).toHaveBeenCalledTimes(1)
    expect(
      h.rpc.mock.calls.filter(([name]) => name === 'claim_conversation_intake_routing'),
    ).toHaveLength(1)
    expect(
      h.rpc.mock.calls.some(
        ([name]) =>
          name === 'seal_conversation_intake_routing' ||
          name.includes('workout') ||
          name.includes('meal'),
      ),
    ).toBe(false)
  })

  it.each([
    'meal.report',
    'workout.report',
  ] as const)('uses the actual %s read API from an immutable selection, never submit', async (kind) => {
    const h = setup()
    h.seal(kind)
    const result = await h.create().read('2'),
      child = required(h.selection(kind).command)
    expect(result).toMatchObject({
      status: 'selected',
      result: { status: 'absent', command_id: child.command_id, input_hash: child.input_hash },
    })
    expect(h.rpc.mock.calls.map(([name]) => name)).toEqual([
      'read_conversation_intake',
      kind === 'meal.report' ? 'read_conversation_meal_command' : 'reconcile_conversation_workout',
    ])
    expect(h.rpc.mock.calls[1]?.[1]).toMatchObject({
      p_user_id: h.auth.userId,
      p_command_id: child.command_id,
    })
    expect(h.createRouter).not.toHaveBeenCalled()
  })

  it('invokes the real workout submit backend after durable seal, and never promotes its unavailable read into saved', async () => {
    const h = setup(),
      result = await h.create().submit(h.command)
    expect(result).toMatchObject({
      status: 'selected',
      result: { schema: 'conversation.workout-command-state.v1', status: 'pending' },
    })
    expect(h.rpc.mock.calls.map(([name]) => name)).toEqual([
      'read_conversation_intake',
      'admit_conversation_intake',
      'capture_conversation_intake_source',
      'claim_conversation_intake_routing',
      'seal_conversation_intake_routing',
      'read_conversation_workout_preparation',
    ])
    expect(h.rpc.mock.calls.at(-1)?.[1]).toEqual({
      p_user_id: h.auth.userId,
      p_command_id: h.childId,
      p_input_hash: required(h.selection().command).input_hash,
      p_expected_epoch: h.lookup.epoch,
    })
    expect(h.route).toHaveBeenCalledTimes(1)
  })

  it.each([
    'read',
    'submit',
    'HTTP_POST',
  ] as const)('projects a saved original through the real default workout %s, not an injected result', async (method) => {
    const row = structuredClone(actualWorkout.workout_reconcile_actual_golden[0])
    if (!row?.response.source || !row.response.preparation || !row.response.effect)
      throw new Error('Missing actual qualified SQL workout')
    const qualifiedSource = row.response.source,
      original = replyFixture(),
      auth = {
        ...original.auth,
        userId: row.bound_command.ownerId,
        patient: { ...original.auth.patient, id: row.bound_command.ownerId },
      },
      typed = row.response.source.context.source_input,
      command = bindConversationIntake(auth.userId, `cintake1:${intakeId}`, {
        intake_protocol: 'conversation.intake.v1',
        intake_id: intakeId,
        source: typed.source,
      }),
      before = new Date(
        new Date(row.response.source.context.admitted_at).getTime() - 2000,
      ).toISOString(),
      after = new Date(
        new Date(row.response.source.context.admitted_at).getTime() + 2000,
      ).toISOString(),
      binding = {
        owner_id: auth.userId,
        intake_id: intakeId,
        input_hash: command.inputHash,
        epoch: row.epoch,
        admitted_at: before,
      },
      decision = {
        schema: 'conversation.intake-routing.v1' as const,
        kind: 'workout.report' as const,
        reason: 'performed_activity',
      },
      selection = {
        schema: 'conversation.intake-selection.v1',
        intake: binding,
        source_hash: 'b'.repeat(64),
        decision_hash: workoutDigest(decision),
        decision,
        selected_at: after,
        command: {
          kind: 'workout.report',
          owner_id: auth.userId,
          command_id: typed.command_id,
          input_hash: row.bound_command.inputHash,
          epoch: row.epoch,
          admitted_at: row.response.source.context.admitted_at,
          input: typed,
        },
      },
      rpc = vi.fn(async (name: string) => {
        if (name === 'read_conversation_intake')
          return {
            data: {
              action: 'available',
              intake: binding,
              source_input: command.input,
              source_hash: selection.source_hash,
              claimed: true,
              selection,
            },
            error: null,
          }
        if (name === 'reconcile_conversation_workout') return { data: row.response, error: null }
        if (name === 'read_conversation_workout_preparation')
          return {
            data: {
              action: 'available',
              source: row.response.source,
              preparation: row.response.preparation,
            },
            error: null,
          }
        if (name === 'read_conversation_workout_effect')
          return { data: { action: 'available', ...row.response.effect }, error: null }
        throw new Error('A durable original must not repeat admission, effect or provider')
      }),
      createRouter = vi.fn(),
      runtime = createConversationIntakeRuntime(
        { rpc } as unknown as ServiceClient,
        auth,
        { ownerId: auth.userId, intakeId, inputHash: command.inputHash, epoch: row.epoch },
        {
          enabled: () => true,
          mealEnabled: () => true,
          workoutEnabled: () => true,
          createRouter,
          auth: {
            verifyAccessToken: async () => auth.identity,
            loadPatient: async () => auth.patient,
            isAdmin: async () => false,
          },
          clinical: { capture: async () => qualifiedSource.context.clinical },
        },
      )
    const result = await (async () => {
      if (method === 'read') return runtime.read()
      if (method === 'submit') return runtime.submit(command)
      // Actual HTTP handler, input binding, neutral runtime and typed facade;
      // only external Auth/SQL use fixtures. This is not network/provider QA.
      const response = await createConversationIntakeRoutes(
        { enabled: () => true, service: () => runtime },
        {
          createServiceClient: () => ({ rpc }) as unknown as ServiceClient,
          authenticate: async () => auth,
          authorizeEntitlement: async () => {},
          createRequestId: () => 'actual-intake-handler-test',
        },
      ).POST(
        new Request('https://app.invalid/api/mobile/v1/conversation/intakes', {
          method: 'POST',
          headers: {
            'Content-Type': 'application/json',
            'Idempotency-Key': `cintake1:${intakeId}`,
            'X-Conversation-Owner': auth.userId,
            'X-Conversation-Epoch': row.epoch,
          },
          body: JSON.stringify(command.input),
        }),
      )
      expect(response.status).toBe(200)
      expect(response.headers.get('X-Conversation-Protocol')).toBe('intake-v1')
      expect(response.headers.get('Cache-Control')).toBe('no-store')
      return (await response.json()).data
    })()
    expect(result).toMatchObject({
      status: 'selected',
      result: {
        schema: 'conversation.workout-command-result.v1',
        status: 'saved',
        owner_id: auth.userId,
        command_id: typed.command_id,
        input_hash: row.bound_command.inputHash,
        epoch: row.epoch,
        registration: { workout_id: row.response.effect.receipt.workout_id },
        activity: row.response.effect.receipt.activity,
        feedback: null,
      },
    })
    expect(JSON.stringify(result)).not.toMatch(/source_input|context|clinical|prepared_hash/)
    expect(createRouter).not.toHaveBeenCalled()
    expect(rpc.mock.calls.map(([name]) => name)).toEqual(
      method === 'read'
        ? ['read_conversation_intake', 'reconcile_conversation_workout']
        : [
            'read_conversation_intake',
            'read_conversation_workout_preparation',
            'read_conversation_workout_effect',
          ],
    )
  })
  it('rechecks both capabilities inside the real typed service scope before any next physical admission', async () => {
    const h = setup(),
      api = h.create(),
      physical = required(h.rpc.getMockImplementation())
    h.rpc.mockImplementation(async (name, args) => {
      if (name === 'read_conversation_workout_preparation') {
        h.ports.workoutEnabled.mockReturnValue(false)
        return { data: { action: 'absent' }, error: null }
      }
      if (name === 'admit_conversation_workout_command')
        return { data: { action: 'replay', command: required(h.selection().command) }, error: null }
      return physical(name, args)
    })
    await expect(api.submit(h.command)).rejects.toMatchObject({
      code: 'conversation_intake_unavailable',
    })
    expect(h.rpc.mock.calls.map(([name]) => name)).toEqual([
      'read_conversation_intake',
      'admit_conversation_intake',
      'capture_conversation_intake_source',
      'claim_conversation_intake_routing',
      'seal_conversation_intake_routing',
      'read_conversation_workout_preparation',
    ])
    h.ports.workoutEnabled.mockReturnValue(true)
    await expect(api.read()).rejects.toMatchObject({ code: 'conversation_intake_unavailable' })
  })

  it.each([
    ['profile', 503, 'patient_profile_unavailable'],
    ['admin', 403, 'patient_admin_account_conflict'],
    ['mapping', 409, 'conversation_patient_changed'],
  ] as const)('latches inner typed %s refusal before driver reconciliation', async (mode, status, code) => {
    const h = setup()
    h.seal()
    const api = h.create(),
      physical = required(h.rpc.getMockImplementation())
    h.rpc.mockImplementation(async (name, args) => {
      if (name === 'read_conversation_workout_preparation') {
        if (mode === 'profile')
          h.authPort.loadPatient.mockRejectedValueOnce(new Error('mapping lookup failed'))
        else if (mode === 'admin') h.authPort.isAdmin.mockResolvedValueOnce(true)
        else
          h.authPort.loadPatient.mockResolvedValueOnce({ ...h.auth.patient, id: h.auth.authUserId })
        throw new Error('SDK outcome unknown')
      }
      return physical(name, args)
    })
    await expect(api.submit(h.command)).rejects.toMatchObject({ status, code })
    await expect(api.read()).rejects.toMatchObject({ status, code })
    expect(h.rpc.mock.calls.map(([name]) => name)).toEqual([
      'read_conversation_intake',
      'read_conversation_workout_preparation',
    ])
  })

  it('both typed capabilities are still required after routing and before the seal can admit a child', async () => {
    const h = setup(),
      api = h.create()
    h.route.mockImplementation(async () => {
      h.ports.mealEnabled.mockReturnValue(false)
      return h.selection().decision
    })
    await expect(api.submit(h.command)).rejects.toMatchObject({
      code: 'conversation_intake_unavailable',
    })
    expect(h.rpc.mock.calls.map(([name]) => name)).toEqual([
      'read_conversation_intake',
      'admit_conversation_intake',
      'capture_conversation_intake_source',
      'claim_conversation_intake_routing',
    ])
    expect(h.route).toHaveBeenCalledTimes(1)
  })
  it('ordinary SDK uncertainty keeps read-only reconciliation without treating it as a mandatory scope refusal', async () => {
    const h = setup(),
      api = h.create(),
      physical = required(h.rpc.getMockImplementation())
    h.rpc.mockRejectedValueOnce(new Error('SDK transport unavailable')).mockImplementation(physical)
    expect(await api.submit(h.command)).toMatchObject({
      status: 'pending',
      reason: 'intake_reconciliation_required',
    })
    expect(await api.read()).toMatchObject({ status: 'absent' })
    expect(h.rpc.mock.calls.map(([name]) => name)).toEqual([
      'read_conversation_intake',
      'read_conversation_intake',
      'read_conversation_intake',
    ])
    expect(h.createRouter).not.toHaveBeenCalled()
  })

  it('uses real meal submit/read, preserves its independent receipt UUID and keeps factual ACK when optional feedback is unavailable', async () => {
    const original = replyFixture(),
      typed = writerCommand(),
      receipt = writerReceipt(),
      auth = {
        ...original.auth,
        userId: typed.ownerId,
        patient: { ...original.auth.patient, id: typed.ownerId },
      },
      profile = JSON.parse(JSON.stringify(clinical()).replaceAll(clinical().epoch, writerEpoch)),
      command = bindConversationIntake(auth.userId, `cintake1:${intakeId}`, {
        intake_protocol: 'conversation.intake.v1',
        intake_id: intakeId,
        meal_type_hint: typed.command.meal_type,
        source: typed.command.source,
      }),
      binding = {
        owner_id: auth.userId,
        intake_id: intakeId,
        input_hash: command.inputHash,
        epoch: writerEpoch,
        admitted_at: '2026-11-04T11:59:59Z',
      },
      decision = {
        schema: 'conversation.intake-routing.v1',
        kind: 'meal.report',
        reason: 'performed_meal',
      },
      selection = {
        schema: 'conversation.intake-selection.v1',
        intake: binding,
        source_hash: 'b'.repeat(64),
        decision_hash: workoutDigest(decision),
        decision,
        selected_at: '2026-11-04T12:00:00.000002Z',
        command: {
          kind: 'meal.report',
          owner_id: auth.userId,
          command_id: typed.commandId,
          input_hash: typed.inputHash,
          epoch: writerEpoch,
          admitted_at: writerBinding().admitted_at,
          input: typed.command,
        },
      },
      prepared = { ...writerPrepared(), receipt },
      rpc = vi.fn(async (name: string) => {
        if (name === 'read_conversation_intake')
          return {
            data: {
              action: 'available',
              intake: binding,
              source_input: command.input,
              source_hash: selection.source_hash,
              claimed: true,
              selection,
            },
            error: null,
          }
        if (name === 'read_conversation_meal_prepared') return { data: prepared, error: null }
        if (name === 'read_conversation_meal_command')
          return {
            data: {
              action: 'available',
              command: writerBinding(),
              state: 'admitted',
              source_input: typed.command,
              candidate: null,
              candidate_hash: null,
            },
            error: null,
          }
        if (name === 'get_mobile_current_clinical_state')
          throw new Error('Optional legacy feedback current state unavailable')
        throw new Error('No admission, interpreter or writer for a durable original')
      }),
      createRouter = vi.fn(),
      api = createConversationIntakeRuntime(
        { rpc } as unknown as ServiceClient,
        auth,
        { ownerId: auth.userId, intakeId, inputHash: command.inputHash, epoch: writerEpoch },
        {
          enabled: () => true,
          mealEnabled: () => true,
          workoutEnabled: () => true,
          createRouter,
          auth: {
            verifyAccessToken: async () => auth.identity,
            loadPatient: async () => auth.patient,
            isAdmin: async () => false,
          },
          clinical: { capture: async () => profile },
        },
      )
    expect(receipt.registration_id).not.toBe(typed.commandId)
    for (const result of [await api.submit(command), await api.read()]) {
      expect(result).toMatchObject({
        status: 'selected',
        result: {
          schema: 'conversation.meal-command-result.v1',
          status: 'saved',
          command_id: typed.commandId,
          input_hash: typed.inputHash,
          receipt: { registration_id: receipt.registration_id },
          feedback: null,
        },
      })
    }
    expect(rpc.mock.calls.map(([name]) => name)).toEqual([
      'read_conversation_intake',
      'read_conversation_meal_prepared',
      'get_mobile_current_clinical_state',
      'read_conversation_intake',
      'read_conversation_meal_command',
      'read_conversation_meal_prepared',
      'get_mobile_current_clinical_state',
    ])
    expect(createRouter).not.toHaveBeenCalled()
  })
  it('control: a real prepared meal can commit and return its genuine writer receipt', async () => {
    const h = guardedMealBoundary(true)
    expect(await h.api.submit(h.command)).toMatchObject({
      status: 'selected',
      result: { status: 'saved', receipt: h.receipt },
    })
    expect(h.rpc.mock.calls.filter(([name]) => name === 'commit_conversation_meal')).toHaveLength(1)
  })
  it.each([
    'capability',
    'token',
  ] as const)('never commits a prepared meal after %s is revoked during its physical read', async (mode) => {
    const h = guardedMealBoundary(true, (name, controls) => {
      if (name === 'read_conversation_meal_prepared') {
        if (mode === 'capability') controls.mealEnabled.mockReturnValue(false)
        else controls.authPort.verifyAccessToken.mockResolvedValue(null)
      }
    })
    await expect(h.api.submit(h.command)).rejects.toMatchObject({
      code: mode === 'capability' ? 'conversation_intake_unavailable' : 'invalid_access_token',
    })
    expect(h.rpc.mock.calls.some(([name]) => name === 'commit_conversation_meal')).toBe(false)
    expect(h.rpc.mock.calls.some(([name]) => name === 'read_conversation_meal_decision')).toBe(
      false,
    )
  })
  it.each([
    'token',
    'profile',
    'admin',
    'mapping',
  ] as const)('latches inner optional feedback %s refusal before it can be suppressed', async (mode) => {
    let triggered = false
    const h = guardedMealBoundary(false, (name, controls) => {
      if (name !== 'read_mobile_registration_feedback_v3' || triggered) return
      triggered = true
      if (mode === 'token') controls.authPort.verifyAccessToken.mockResolvedValueOnce(null)
      if (mode === 'profile')
        controls.authPort.loadPatient.mockRejectedValueOnce(new Error('Lookup failed'))
      if (mode === 'admin') controls.authPort.isAdmin.mockResolvedValueOnce(true)
      if (mode === 'mapping')
        controls.authPort.loadPatient.mockResolvedValueOnce({
          ...h.auth.patient,
          id: h.auth.authUserId,
        })
    })
    const code = (
      {
        token: 'invalid_access_token',
        profile: 'patient_profile_unavailable',
        admin: 'patient_admin_account_conflict',
        mapping: 'conversation_patient_changed',
      } as const
    )[mode]
    const operation = h.api.submit(h.command, '2')
    await operation.catch(() => undefined)
    expect(triggered, JSON.stringify(h.rpc.mock.calls.map(([name]) => name))).toBe(true)
    await expect(operation).rejects.toMatchObject({ code })
    const count = h.rpc.mock.calls.length
    await expect(h.api.read('2')).rejects.toMatchObject({ code })
    expect(h.rpc).toHaveBeenCalledTimes(count)
    expect(h.rpc.mock.calls.some(([name]) => name === 'get_mobile_current_clinical_state')).toBe(
      false,
    )
  })
})
