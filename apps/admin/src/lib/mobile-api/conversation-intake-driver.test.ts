import { describe, expect, it, vi } from 'vitest'
import { replyFixture } from './__fixtures__/conversation-meal-reply'
import { writerReceipt } from './__fixtures__/conversation-meal-writer'
import { bindConversationCommand } from './conversation-command-contracts'
import {
  bindConversationIntake,
  type ConversationIntakeRoutingDecision,
  parseConversationIntakeRoutingDecision,
} from './conversation-intake-contracts'
import {
  type ConversationIntakeDriverPorts,
  createConversationIntakeDriver,
} from './conversation-intake-driver'
import type { createConversationIntakeRecoveryStore } from './conversation-intake-recovery-store'
import { createOpenRouterConversationIntakeRouter } from './conversation-intake-router'
import { createConversationIntakeStore } from './conversation-intake-store'
import { projectSavedConversationMealCommandResult } from './conversation-meal-command-result'
import { bindConversationWorkoutCommand, workoutDigest } from './conversation-workout-contracts'
import { MobileApiError } from './http'

const id = 'c3cc0000-0000-4000-8000-000000000039',
  childId = 'c3cc0000-0000-4000-8000-000000000040',
  claimId = 'c3cc0000-0000-4000-8000-000000000041',
  sourceHash = 'a'.repeat(64)

/** External store and typed-service boundary doubles only. These fixtures do
 * not claim SQL persistence or a saved workout; K qualifies the actual RPCs. */
function setup(text = 'Caminhei 30 min', media = false) {
  const f = replyFixture(),
    owner = f.auth.userId,
    epoch = f.identity.epoch
  const command = bindConversationIntake(owner, `cintake1:${id}`, {
    intake_protocol: 'conversation.intake.v1',
    intake_id: id,
    source: media
      ? { channel: 'media', media_asset_id: childId, user_action: 'report_actual_record' }
      : { channel: 'text', text },
  })
  const binding = {
    owner_id: owner,
    intake_id: id,
    input_hash: command.inputHash,
    epoch,
    admitted_at: '2026-11-05T12:00:00.000001Z',
  }
  const context = {
    schema: 'conversation.intake-source.v1',
    ...binding,
    source_input: command.input,
    captured_at: '2026-11-05T12:00:00.000002Z',
    time_zone: 'UTC',
    local_date: '2026-11-05',
    media: media
      ? {
          asset_id: childId,
          owner_id: owner,
          kind: 'audio_note',
          status: 'processed',
          processed_at: '2026-11-05T11:59:59Z',
          updated_at: '2026-11-05T11:59:59Z',
          context_text: null,
          processing_result: { text },
        }
      : null,
  } as const
  const decision: ConversationIntakeRoutingDecision = {
    schema: 'conversation.intake-routing.v1',
    kind: 'workout.report',
    reason: 'performed_activity',
  }
  function selection(d = decision) {
    const input = {
      command_protocol: 'conversation.command.v1' as const,
      command_id: childId,
      kind: d.kind,
      source: { channel: 'text' as const, text },
    }
    const child =
      d.kind === 'workout.report'
        ? bindConversationWorkoutCommand(owner, `cmsg1:${childId}`, input)
        : d.kind === 'meal.report'
          ? bindConversationCommand(owner, `cmsg1:${childId}`, input)
          : null
    return {
      schema: 'conversation.intake-selection.v1' as const,
      intake: binding,
      source_hash: sourceHash,
      decision_hash: workoutDigest(d),
      decision: d,
      selected_at: '2026-11-05T12:00:00.000004Z',
      command: child
        ? {
            kind: child.command.kind,
            owner_id: owner,
            command_id: child.commandId,
            input_hash: child.inputHash,
            epoch,
            admitted_at: '2026-11-05T12:00:00.000003Z',
            input: child.command,
          }
        : null,
    }
  }
  let present = false,
    captured = false,
    claimed = false,
    sealed: ReturnType<typeof selection> | null = null,
    allowed = true
  const readValue = () =>
    present
      ? {
          action: 'available' as const,
          intake: binding,
          source_input: command.input,
          source_hash: captured ? sourceHash : null,
          claimed,
          selection: sealed,
        }
      : { action: 'absent' as const }
  const store = {
    read: vi.fn(async () => readValue()),
    admit: vi.fn(async () => {
      present = true
      return { action: 'admitted' as const, intake: binding }
    }),
    capture: vi.fn(async () => {
      captured = true
      return { action: 'captured' as const, source_hash: sourceHash, context }
    }),
    claim: vi.fn(async () => {
      claimed = true
      return { action: 'claimed' as const, claim_id: claimId }
    }),
    seal: vi.fn<ReturnType<typeof createConversationIntakeStore>['seal']>(
      async (_c: unknown, _e: unknown, _s: unknown, _claim: unknown, d: unknown) => {
        sealed = selection(parseConversationIntakeRoutingDecision(d))
        return { action: 'sealed' as const, selection: sealed }
      },
    ),
  }
  const pendingReply = () => {
    const c = sealed?.command
    if (!c) throw new Error('Missing actual selected child')
    return {
      schema:
        c.kind === 'meal.report'
          ? 'conversation.meal-command-state.v1'
          : 'conversation.workout-command-state.v1',
      status: 'pending',
      owner_id: owner,
      command_id: c.command_id,
      input_hash: c.input_hash,
      epoch,
      reason: 'reconciliation_required',
    } as const
  }
  const domain = () => ({
    submit: vi.fn<ConversationIntakeDriverPorts['domains']['meal']['submit']>(async () =>
      pendingReply(),
    ),
    read: vi.fn<ConversationIntakeDriverPorts['domains']['meal']['read']>(async () =>
      pendingReply(),
    ),
  })
  const domains = { meal: domain(), workout: domain() }
  type Recovery = ReturnType<typeof createConversationIntakeRecoveryStore>
  const proof = {
    action: 'available' as const,
    intake: binding,
    source_hash: sourceHash,
    claim_id: claimId,
    lease_anchor_at: '2026-11-05T12:00:00.000003Z',
    lease_clock_origin: 'claim' as const,
    result: null,
  }
  const recovery = {
    read: vi.fn<Recovery['read']>(async () => proof),
    reconcile: vi.fn<Recovery['reconcile']>(async () => ({ action: 'in_flight' })),
  }
  const route = vi.fn(async () => decision),
    createRouter = vi.fn<ConversationIntakeDriverPorts['createRouter']>(() => ({ route })),
    scope = {
      observeCurrentScope: vi.fn(async () => {
        if (!allowed) throw new Error('Original scope is unavailable')
        return f.profile
      }),
    },
    ports = { store, recovery, domains, createRouter, scope }
  const driver = createConversationIntakeDriver(ports)
  return {
    auth: f.auth,
    command,
    binding,
    context,
    decision,
    selection,
    epoch,
    owner,
    store,
    domains,
    route,
    createRouter,
    recovery,
    proof,
    scope,
    driver,
    ports,
    readValue,
    lookup: { ownerId: owner, intakeId: id, inputHash: command.inputHash, epoch },
    setAllowed: (value: boolean) => {
      allowed = value
    },
    setState: (state: { claimed?: boolean; selection?: ReturnType<typeof selection> }) => {
      present = true
      captured = true
      claimed = state.claimed ?? true
      sealed = state.selection ?? null
    },
  }
}

function selectedChild(f: ReturnType<typeof setup>) {
  const child = f.selection().command
  if (!child) throw new Error('Missing fixture child')
  return child
}

describe('POST-only recovery of the original routing claim', () => {
  function known(f: ReturnType<typeof setup>) {
    return {
      ...f.proof,
      result: {
        schema: 'conversation.intake-routing-result.v1' as const,
        decision: f.decision,
        decision_hash: workoutDigest(f.decision),
        recorded_at: '2026-11-05T12:00:00.000004Z',
        origin: 'router' as const,
      },
    }
  }
  it('uses a durable routing decision to retry only original typed admission, without provider or recapture', async () => {
    const f = setup()
    f.setState({ claimed: true })
    f.recovery.read.mockResolvedValue(known(f))
    expect(await f.driver.submit(f.command, f.epoch)).toMatchObject({
      status: 'selected',
      result: { status: 'pending' },
    })
    expect(f.recovery.read).toHaveBeenCalledWith(f.command, f.binding, sourceHash)
    expect(f.store.seal).toHaveBeenCalledWith(f.command, f.epoch, sourceHash, claimId, f.decision)
    expect(f.domains.workout.submit).toHaveBeenCalledOnce()
    expect(f.createRouter).not.toHaveBeenCalled()
    expect(f.store.capture).not.toHaveBeenCalled()
    expect(f.store.claim).not.toHaveBeenCalled()
    expect(f.recovery.reconcile).not.toHaveBeenCalled()
  })
  it('lets SQL decide whether an unresolved claim is still in flight, without using a client clock', async () => {
    const f = setup()
    f.setState({ claimed: true })
    expect(await f.driver.submit(f.command, f.epoch)).toMatchObject({
      status: 'pending',
      reason: 'routing_reconciliation_required',
    })
    expect(f.recovery.reconcile).toHaveBeenCalledWith(f.command, f.binding, sourceHash, claimId)
    expect(f.store.seal).not.toHaveBeenCalled()
    expect(f.createRouter).not.toHaveBeenCalled()
    expect(f.domains.workout.submit).not.toHaveBeenCalled()
  })
  it('consumes only the actual selection after SQL closes an interrupted claim', async () => {
    const f = setup()
    f.setState({ claimed: true })
    const decision: ConversationIntakeRoutingDecision = {
      schema: 'conversation.intake-routing.v1',
      kind: 'clarification_required',
      reason: 'routing_interrupted',
      question: {
        field: 'description',
        text: 'Não foi possível concluir o processamento. Pode confirmar o que deseja registrar?',
      },
    }
    const selection = { ...f.selection(decision), selected_at: '2026-11-05T12:01:01Z' }
    f.recovery.reconcile.mockImplementation(async () => {
      f.setState({ selection })
      return {
        action: 'reconciled',
        result: {
          ...f.proof,
          result: {
            schema: 'conversation.intake-routing-result.v1',
            decision,
            decision_hash: workoutDigest(decision),
            recorded_at: selection.selected_at,
            origin: 'interrupted',
          },
        },
      }
    })
    expect(await f.driver.submit(f.command, f.epoch)).toMatchObject({
      status: 'clarification_required',
      reason: 'routing_interrupted',
      question: decision.question,
    })
    expect(f.store.seal).not.toHaveBeenCalled()
    expect(f.domains.workout.submit).not.toHaveBeenCalled()
    expect(f.createRouter).not.toHaveBeenCalled()
  })
  it('never fabricates a selection from an interrupted private proof', async () => {
    const f = setup()
    f.setState({ claimed: true })
    f.recovery.read.mockResolvedValue({
      ...known(f),
      result: { ...known(f).result, origin: 'interrupted' },
    })
    expect(await f.driver.submit(f.command, f.epoch)).toMatchObject({ status: 'pending' })
    expect(f.store.seal).not.toHaveBeenCalled()
    expect(f.domains.workout.submit).not.toHaveBeenCalled()
    expect(f.createRouter).not.toHaveBeenCalled()
  })
  it('prefers a real concurrent selection observed after routing-proof lookup', async () => {
    const f = setup()
    f.setState({ claimed: true })
    f.recovery.read.mockImplementation(async () => {
      f.setState({ selection: f.selection() })
      return known(f)
    })
    expect(await f.driver.submit(f.command, f.epoch)).toMatchObject({ status: 'selected' })
    expect(f.store.seal).not.toHaveBeenCalled()
    expect(f.domains.workout.submit).toHaveBeenCalledOnce()
    expect(f.createRouter).not.toHaveBeenCalled()
  })
  it.each([
    'day_closed',
    'day_changed',
    'rate_limited',
  ] as const)('preserves the original durable decision when actual seal refuses %s', async (action) => {
    const f = setup()
    f.setState({ claimed: true })
    f.recovery.read.mockResolvedValue(known(f))
    f.store.seal.mockResolvedValue({ action })
    expect(await f.driver.submit(f.command, f.epoch)).toMatchObject({
      status: 'held',
      reason: action,
    })
    expect(f.store.seal).toHaveBeenCalledOnce()
    expect(f.recovery.reconcile).not.toHaveBeenCalled()
    expect(f.createRouter).not.toHaveBeenCalled()
    expect(f.domains.workout.submit).not.toHaveBeenCalled()
  })
  it('does not run mutating recovery after an uncertain seal in the same attempt', async () => {
    const f = setup()
    f.store.seal.mockRejectedValueOnce(new Error('Transport lost after seal'))
    expect(await f.driver.submit(f.command, f.epoch)).toMatchObject({ status: 'pending' })
    expect(f.recovery.read).not.toHaveBeenCalled()
    expect(f.recovery.reconcile).not.toHaveBeenCalled()
    expect(f.store.seal).toHaveBeenCalledOnce()
  })
  it('GET remains observational for a claimed parent', async () => {
    const f = setup()
    f.setState({ claimed: true })
    expect(await f.driver.read(f.lookup)).toMatchObject({ status: 'pending' })
    expect(f.recovery.read).not.toHaveBeenCalled()
    expect(f.recovery.reconcile).not.toHaveBeenCalled()
    expect(f.store.seal).not.toHaveBeenCalled()
    expect(f.createRouter).not.toHaveBeenCalled()
  })
})

/** Exercise the real typed meal projector with its synthetic receipt fixture.
 * This is the transport contract, not evidence of a physical domain write. */
function savedMeal(f: ReturnType<typeof setup>) {
  const decision: ConversationIntakeRoutingDecision = {
      schema: 'conversation.intake-routing.v1',
      kind: 'meal.report',
      reason: 'reported_consumption',
    },
    selection = f.selection(decision),
    child = selection.command
  if (!child) throw new Error('Missing actual meal child')
  const command = bindConversationCommand(f.owner, `cmsg1:${child.command_id}`, child.input)
  const receipt = {
    ...writerReceipt(),
    owner_id: f.owner,
    command_id: child.command_id,
    input_hash: child.input_hash,
    provider_key: `conversation.meal/${f.owner}/${child.command_id}`,
    local_date: '2026-11-05',
    timezone: 'UTC',
    consumed_at: '2026-11-05T12:00:01.000004Z',
  }
  const result = projectSavedConversationMealCommandResult({
    auth: f.auth,
    command,
    expectedEpoch: f.epoch,
    serverBinding: {
      owner_id: f.owner,
      command_id: child.command_id,
      input_hash: child.input_hash,
      command_protocol: 'conversation.command.v1',
      kind: 'meal.report',
      epoch: f.epoch,
      admitted_at: child.admitted_at,
    },
    receipt,
    feedback: null,
  })
  f.setState({ selection })
  return result
}

describe('durable neutral intake orchestration over genuine typed service boundaries', () => {
  it('seals one original pair before forwarding and never calls selected an ACK', async () => {
    const f = setup(),
      result = await f.driver.submit(f.command, f.epoch, '2')
    expect(result).toMatchObject({
      schema: 'conversation.intake-result.v1',
      status: 'selected',
      intake: f.binding,
      selection: { kind: 'workout.report', command: { command_id: childId } },
      result: { status: 'pending' },
    })
    expect(f.domains.workout.submit.mock.invocationCallOrder[0]).toBeGreaterThan(
      f.store.seal.mock.invocationCallOrder[0] ?? Infinity,
    )
    expect(f.domains.meal.submit).not.toHaveBeenCalled()
    expect(f.route).toHaveBeenCalledOnce()
    expect(result).not.toHaveProperty('selection.command.input')
    expect(JSON.stringify(result)).not.toContain('source_input')
    expect(JSON.stringify(result)).not.toContain('claim_id')
  })
  it('reuses the same sealed child on a technical repeat without another classification', async () => {
    const f = setup()
    const first = await f.driver.submit(f.command, f.epoch)
    const second = await f.driver.submit(f.command, f.epoch)
    expect(second).toEqual(first)
    expect(f.store.admit).toHaveBeenCalledOnce()
    expect(f.store.seal).toHaveBeenCalledOnce()
    expect(f.route).toHaveBeenCalledOnce()
    expect(f.domains.workout.submit.mock.calls[0]).toEqual(f.domains.workout.submit.mock.calls[1])
  })
  it('cold-reads the persisted neutral body and original child without any mutation', async () => {
    const f = setup()
    f.setState({ selection: f.selection() })
    const result = await f.driver.read(f.lookup, '2')
    expect(result).toMatchObject({ status: 'selected', result: { status: 'pending' } })
    expect(f.domains.workout.read).toHaveBeenCalledOnce()
    for (const method of [
      f.store.admit,
      f.store.capture,
      f.store.claim,
      f.store.seal,
      f.createRouter,
      f.domains.meal.submit,
      f.domains.workout.submit,
    ])
      expect(method).not.toHaveBeenCalled()
  })
  it('keeps an absent read factual instead of fabricating admission or a replay grant', async () => {
    const f = setup()
    expect(await f.driver.read(f.lookup)).toEqual({
      schema: 'conversation.intake-result.v1',
      status: 'absent',
      lookup: f.lookup,
    })
    expect(f.store.admit).not.toHaveBeenCalled()
    expect(f.createRouter).not.toHaveBeenCalled()
  })
  it('preserves an unknown routing claim and never recalls its provider', async () => {
    const f = setup()
    f.setState({ claimed: true })
    expect(await f.driver.submit(f.command, f.epoch)).toMatchObject({
      status: 'pending',
      reason: 'routing_reconciliation_required',
    })
    expect(f.createRouter).not.toHaveBeenCalled()
    expect(f.store.claim).not.toHaveBeenCalled()
    expect(f.store.seal).not.toHaveBeenCalled()
  })
  it('reconciles a lost seal response only by reading the original selection and child', async () => {
    const f = setup()
    f.store.seal.mockImplementationOnce(async () => {
      f.setState({ selection: f.selection() })
      throw new Error('Lost response after commit')
    })
    expect(await f.driver.submit(f.command, f.epoch)).toMatchObject({
      status: 'selected',
      result: { status: 'pending' },
    })
    expect(f.store.seal).toHaveBeenCalledOnce()
    expect(f.domains.workout.read).toHaveBeenCalledOnce()
    expect(f.domains.workout.submit).not.toHaveBeenCalled()
    expect(f.route).toHaveBeenCalledOnce()
  })
  it('does not repeat routing after a thrown provider outcome', async () => {
    const f = setup()
    f.route.mockRejectedValueOnce(new Error('Provider uncertain'))
    expect(await f.driver.submit(f.command, f.epoch)).toMatchObject({
      status: 'pending',
      reason: 'routing_reconciliation_required',
    })
    expect(await f.driver.submit(f.command, f.epoch)).toMatchObject({
      status: 'pending',
      reason: 'routing_reconciliation_required',
    })
    expect(f.route).toHaveBeenCalledOnce()
    expect(f.store.seal).not.toHaveBeenCalled()
  })
  it('checks a pure router configuration before consuming a permanent claim', async () => {
    const f = setup()
    f.createRouter.mockImplementationOnce(() => {
      throw new Error('Router is not configured')
    })
    expect(await f.driver.submit(f.command, f.epoch)).toMatchObject({
      status: 'pending',
      reason: 'intake_pending',
    })
    expect(f.store.claim).not.toHaveBeenCalled()
    expect(f.route).not.toHaveBeenCalled()
    expect(f.store.seal).not.toHaveBeenCalled()
  })
  it('preserves the receiver of the injected router instead of calling an extracted method', async () => {
    const f = setup()
    const router = {
      async route() {
        if (this !== router) throw new Error('Router receiver changed')
        return f.decision
      },
    }
    f.createRouter.mockReturnValueOnce(router)
    expect(await f.driver.submit(f.command, f.epoch)).toMatchObject({
      status: 'selected',
      result: { status: 'pending' },
    })
    expect(f.store.seal).toHaveBeenCalledOnce()
  })
  it('reconciles a lost typed submit response through the same child read without another write', async () => {
    const f = setup()
    f.setState({ selection: f.selection() })
    f.domains.workout.submit.mockRejectedValueOnce(
      new Error('Response lost after a possible effect'),
    )
    expect(await f.driver.submit(f.command, f.epoch)).toMatchObject({
      status: 'selected',
      result: { status: 'pending' },
    })
    expect(f.domains.workout.submit).toHaveBeenCalledOnce()
    expect(f.domains.workout.read).toHaveBeenCalledOnce()
    expect(f.store.admit).not.toHaveBeenCalled()
    expect(f.route).not.toHaveBeenCalled()
  })
  it('reconciles a typed availability error after a possible effect without another write', async () => {
    const f = setup()
    f.setState({ selection: f.selection() })
    f.domains.workout.submit.mockRejectedValueOnce(
      new MobileApiError(503, 'conversation_workout_unavailable', 'Response unavailable'),
    )
    expect(await f.driver.submit(f.command, f.epoch)).toMatchObject({
      status: 'selected',
      result: { status: 'pending' },
    })
    expect(f.domains.workout.submit).toHaveBeenCalledOnce()
    expect(f.domains.workout.read).toHaveBeenCalledOnce()
  })
  it('preserves a typed authorization refusal without attempting reconciliation', async () => {
    const f = setup()
    f.setState({ selection: f.selection() })
    f.domains.workout.submit.mockRejectedValueOnce(
      new MobileApiError(403, 'patient_admin_account_conflict', 'Unavailable'),
    )
    await expect(f.driver.submit(f.command, f.epoch)).rejects.toMatchObject({
      code: 'patient_admin_account_conflict',
    })
    expect(f.domains.workout.read).not.toHaveBeenCalled()
  })
  it.each([
    'not_reported',
    'clarification_required',
  ] as const)('reads terminal %s without a fabricated domain command', async (kind) => {
    const f = setup(),
      decision: ConversationIntakeRoutingDecision = {
        schema: 'conversation.intake-routing.v1',
        kind,
        reason: 'not_unambiguous',
        ...(kind === 'clarification_required'
          ? { question: { field: 'record_kind' as const, text: 'Você consumiu ou realizou isso?' } }
          : {}),
      }
    f.setState({ selection: f.selection(decision) })
    expect(await f.driver.read(f.lookup)).toMatchObject({
      status: kind === 'not_reported' ? 'not_recorded' : kind,
    })
    expect(f.domains.meal.read).not.toHaveBeenCalled()
    expect(f.domains.workout.read).not.toHaveBeenCalled()
    expect(f.createRouter).not.toHaveBeenCalled()
  })
  it('forwards a genuine meal child through only the meal service', async () => {
    const f = setup('Comi arroz e feijão'),
      decision: ConversationIntakeRoutingDecision = {
        schema: 'conversation.intake-routing.v1',
        kind: 'meal.report',
        reason: 'reported_consumption',
      }
    f.route.mockResolvedValueOnce(decision)
    expect(await f.driver.submit(f.command, f.epoch)).toMatchObject({
      status: 'selected',
      selection: { kind: 'meal.report' },
      result: { status: 'pending' },
    })
    expect(f.domains.meal.submit).toHaveBeenCalledOnce()
    expect(f.domains.workout.submit).not.toHaveBeenCalled()
  })
  it.each([
    'submit',
    'read',
  ] as const)('accepts an independently identified saved meal through %s', async (method) => {
    const f = setup('Comi arroz 100 g'),
      saved = savedMeal(f)
    expect(saved.receipt.registration_id).not.toBe(saved.command_id)
    f.domains.meal[method].mockResolvedValueOnce(saved)
    const result =
      method === 'submit'
        ? await f.driver.submit(f.command, f.epoch)
        : await f.driver.read(f.lookup)
    expect(result).toMatchObject({ status: 'selected', result: saved })
    expect(f.domains.meal[method]).toHaveBeenCalledOnce()
    expect(f.store.seal).not.toHaveBeenCalled()
    expect(f.route).not.toHaveBeenCalled()
  })
  it.each([
    'owner_id',
    'command_id',
    'input_hash',
  ] as const)('rejects a saved meal receipt with another %s', async (field) => {
    const f = setup('Comi arroz 100 g'),
      saved = savedMeal(f)
    const wrong = field === 'input_hash' ? 'f'.repeat(64) : id
    f.domains.meal.read.mockResolvedValueOnce({
      ...saved,
      receipt: { ...saved.receipt, [field]: wrong },
    })
    await expect(f.driver.read(f.lookup)).rejects.toMatchObject({
      code: 'conversation_intake_child_changed',
    })
  })
  it.each([
    'before',
    'after',
    'throws',
  ] as const)('preserves actual store mandatory %s refusal across the whole submit', async (position) => {
    const f = setup()
    f.setState({ selection: f.selection() })
    const rpc = vi.fn(async () => ({ data: f.readValue(), error: null })),
      checkCurrentScope = vi.fn(async () => true)
    if (position === 'before') checkCurrentScope.mockResolvedValueOnce(false)
    if (position === 'after')
      checkCurrentScope.mockResolvedValueOnce(true).mockResolvedValueOnce(false)
    if (position === 'throws')
      checkCurrentScope.mockRejectedValueOnce(new Error('Auth unavailable'))
    const store = createConversationIntakeStore({ rpc }, { checkCurrentScope }),
      driver = createConversationIntakeDriver({ ...f.ports, store })
    await expect(driver.submit(f.command, f.epoch)).rejects.toMatchObject({
      status: 503,
      code: 'conversation_intake_unavailable',
    })
    expect(rpc).toHaveBeenCalledTimes(position === 'after' ? 1 : 0)
    expect(checkCurrentScope).toHaveBeenCalledTimes(position === 'after' ? 2 : 1)
    expect(f.domains.workout.read).not.toHaveBeenCalled()
    expect(f.domains.workout.submit).not.toHaveBeenCalled()
    expect(f.route).not.toHaveBeenCalled()
  })
  it('durably returns one non-recording clarification after routing provider failure, without repeating its call', async () => {
    const f = setup(),
      complete = vi.fn(async () => {
        throw new Error('Provider response lost')
      }),
      driver = createConversationIntakeDriver({
        ...f.ports,
        createRouter: () => createOpenRouterConversationIntakeRouter('synthetic-key', { complete }),
      })
    const first = await driver.submit(f.command, f.epoch),
      replay = await driver.submit(f.command, f.epoch)
    expect(first).toMatchObject({ status: 'clarification_required', reason: 'routing_unavailable' })
    expect(replay).toEqual(first)
    expect(complete).toHaveBeenCalledOnce()
    expect(f.store.seal).toHaveBeenCalledOnce()
    for (const domain of [f.domains.meal, f.domains.workout]) {
      expect(domain.submit).not.toHaveBeenCalled()
      expect(domain.read).not.toHaveBeenCalled()
    }
  })
  it('keeps media held before claiming instead of fabricating a typed user action', async () => {
    const f = setup('Caminhei 30 minutos', true)
    expect(await f.driver.submit(f.command, f.epoch)).toMatchObject({
      status: 'held',
      reason: 'media_projection_required',
    })
    expect(f.store.capture).toHaveBeenCalledOnce()
    expect(f.createRouter).not.toHaveBeenCalled()
    expect(f.store.claim).not.toHaveBeenCalled()
    expect(f.store.seal).not.toHaveBeenCalled()
    expect(f.domains.workout.submit).not.toHaveBeenCalled()
  })
  it('keeps a current-scope refusal before any store or domain call', async () => {
    const f = setup()
    f.setAllowed(false)
    await expect(f.driver.submit(f.command, f.epoch)).rejects.toMatchObject({
      code: 'conversation_intake_scope_changed',
    })
    expect(f.store.read).not.toHaveBeenCalled()
    expect(f.store.admit).not.toHaveBeenCalled()
  })
  it('does not publish a child result after scope changes during its call', async () => {
    const f = setup()
    f.setState({ selection: f.selection() })
    f.domains.workout.submit.mockImplementationOnce(async () => {
      f.setAllowed(false)
      return {
        schema: 'conversation.workout-command-state.v1',
        status: 'pending',
        owner_id: f.owner,
        command_id: childId,
        input_hash: selectedChild(f).input_hash,
        epoch: f.epoch,
        reason: 'reconciliation_required',
      }
    })
    await expect(f.driver.submit(f.command, f.epoch)).rejects.toMatchObject({
      code: 'conversation_intake_scope_changed',
    })
    expect(f.domains.workout.submit).toHaveBeenCalledOnce()
    expect(f.store.seal).not.toHaveBeenCalled()
  })
  it('rejects an exchanged child identity instead of publishing another receipt', async () => {
    const f = setup()
    f.setState({ selection: f.selection() })
    f.domains.workout.read.mockResolvedValueOnce({
      schema: 'conversation.workout-command-state.v1',
      status: 'pending',
      owner_id: childId,
      command_id: childId,
      input_hash: selectedChild(f).input_hash,
      epoch: f.epoch,
      reason: 'reconciliation_required',
    })
    await expect(f.driver.read(f.lookup)).rejects.toMatchObject({
      code: 'conversation_intake_child_changed',
    })
  })
  it('never reconstructs the cold original input from the child text', async () => {
    const f = setup()
    f.setState({ selection: f.selection() })
    const read = f.readValue()
    if (read.action !== 'available') throw new Error('Missing fixture state')
    f.store.read.mockResolvedValueOnce({
      ...read,
      source_input: { ...f.command.input, meal_type_hint: 'cafe' as const },
    })
    await expect(f.driver.read(f.lookup)).rejects.toMatchObject({
      code: 'conversation_intake_changed',
    })
    expect(f.domains.workout.read).not.toHaveBeenCalled()
  })
})
