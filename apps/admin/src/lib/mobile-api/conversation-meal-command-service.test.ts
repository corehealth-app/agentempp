import type { ServiceClient } from '@mpp/db'
import { describe, expect, it, vi } from 'vitest'
import { candidateAuth } from './__fixtures__/conversation-candidate'
import {
  writerBinding,
  writerCommand,
  writerEpoch,
  writerReceipt,
  writerResolved,
  writerSource,
} from './__fixtures__/conversation-meal-writer'
import { clinical } from './__fixtures__/feedback-v2-source'
import { createConversationMealCommandService } from './conversation-meal-command-service'
import { registerPersistedConversationMeal } from './conversation-meal-registration-service'

const command = writerCommand()
function terminalDecision() {
  return {
    action: 'available',
    binding: writerBinding(),
    decision: {
      schema: 'conversation.meal-decision.v1',
      status: 'not_recorded',
      reason: 'missing_quantity',
      food_indexes: [0],
      owner_id: command.ownerId,
      command_id: command.commandId,
      epoch: writerEpoch,
      input_hash: command.inputHash,
      source_hash: 'b'.repeat(64),
      attempt_id: '10000000-0000-4000-8000-000000000080',
      semantic_result_hash: 'c'.repeat(64),
      decision_hash: 'd'.repeat(64),
      sealed_at: '2026-11-04T12:01:00.000004Z',
    },
  }
}
function completedSemanticProof() {
  const d = terminalDecision().decision
  return {
    action: 'available',
    status: 'completed',
    owner_id: d.owner_id,
    command_id: d.command_id,
    epoch: d.epoch,
    input_hash: d.input_hash,
    source_hash: d.source_hash,
    attempt_id: d.attempt_id,
    result_hash: d.semantic_result_hash,
    result: { present: true },
  }
}
function ports() {
  const binding = writerBinding(),
    receipt = writerReceipt()
  return {
    writer: {
      readPrepared: vi.fn().mockResolvedValue({ action: 'absent' }),
      readEffect: vi.fn(),
      prepare: vi.fn(),
      commit: vi.fn(),
    },
    journal: {
      read: vi.fn().mockResolvedValue({
        action: 'available',
        binding,
        source: command,
        state: 'admitted',
        candidate: null,
        candidateHash: null,
      }),
      admit: vi.fn(),
      attach: vi.fn(),
    },
    clinical: {
      capture: vi
        .fn()
        .mockResolvedValue(
          JSON.parse(JSON.stringify(clinical()).replaceAll(clinical().epoch, writerEpoch)),
        ),
    },
    semantics: {
      read: vi.fn().mockResolvedValue({ action: 'absent' }),
      start: vi.fn(),
      commit: vi.fn(),
      markUnknown: vi.fn(),
    },
    createInterpreter: vi.fn(() => ({ interpret: vi.fn() })),
    register: vi.fn().mockResolvedValue({
      status: 'saved',
      command,
      serverBinding: binding,
      receipt,
      historicalFeedback: { private: 'NEVER PUBLISH' },
    }),
    presentation: { readHistorical: vi.fn().mockResolvedValue(null) },
    decisions: {
      read: vi.fn().mockResolvedValue({ action: 'absent' }),
      seal: vi.fn().mockResolvedValue({ ...terminalDecision(), action: 'sealed' }),
    },
  }
}
function fixture() {
  const p = ports(),
    service = createConversationMealCommandService(
      { rpc: vi.fn(), from: vi.fn() } as unknown as ServiceClient,
      {
        ...p,
        journal: () => p.journal,
      },
    )
  return {
    p,
    service,
    submit: () =>
      service.submit(candidateAuth, `cmsg1:${command.commandId}`, command.command, writerEpoch),
    read: () => service.read(candidateAuth, command.commandId, command.inputHash, writerEpoch),
  }
}
function stored() {
  return {
    action: 'available',
    binding: writerBinding(),
    source: writerSource(),
    resolved: {
      resolvedHash: 'c'.repeat(64),
      preparedAt: writerSource().capturedAt,
      value: writerResolved(),
    },
    receipt: writerReceipt(),
  }
}
describe('public command submission and effect-only reconciliation', () => {
  it('observes an authenticated current server epoch without a food/model/writer operation', async () => {
    const f = fixture(),
      reply = await f.service.session(candidateAuth)
    expect(reply).toEqual({
      schema: 'conversation.session.v1',
      auth_user_id: candidateAuth.authUserId,
      owner_id: command.ownerId,
      epoch: writerEpoch,
      observed_at: clinical().observed_at,
      meal_command_protocol: 'conversation.command.v1',
    })
    expect(f.p.clinical.capture).toHaveBeenCalledWith({ userId: command.ownerId, mode: 'profile' })
    for (const m of [
      f.p.writer.readPrepared,
      f.p.register,
      f.p.createInterpreter,
      f.p.journal.admit,
    ])
      expect(m).not.toHaveBeenCalled()
  })
  it('keeps the canonical patient distinct from the authenticated login subject', async () => {
    const f = fixture(),
      subject = '10000000-0000-4000-8000-000000000099'
    const auth = structuredClone(candidateAuth)
    auth.authUserId = subject
    auth.identity.id = subject
    auth.patient.authUserId = subject
    expect(await f.service.session(auth)).toMatchObject({
      auth_user_id: subject,
      owner_id: command.ownerId,
      epoch: writerEpoch,
    })
    expect(f.p.clinical.capture).toHaveBeenCalledWith({ userId: command.ownerId, mode: 'profile' })
  })
  it('projects an existing factual result before provider, registration, daily or admission', async () => {
    const f = fixture()
    f.p.writer.readPrepared.mockResolvedValue(stored())
    expect(await f.submit()).toMatchObject({
      schema: 'conversation.meal-command-result.v1',
      status: 'saved',
      receipt: writerReceipt(),
      feedback: null,
    })
    expect(f.p.createInterpreter).not.toHaveBeenCalled()
    expect(f.p.register).not.toHaveBeenCalled()
    expect(f.p.journal.admit).not.toHaveBeenCalled()
    expect(f.p.clinical.capture).not.toHaveBeenCalled()
  })
  it('passes the exact fenced journal to the real registration boundary and never returns raw private feedback', async () => {
    const f = fixture(),
      result = await f.submit()
    expect(result).toMatchObject({ status: 'saved', feedback: null })
    expect(JSON.stringify(result)).not.toContain('NEVER PUBLISH')
    expect(f.p.register).toHaveBeenCalledWith(
      expect.anything(),
      candidateAuth,
      `cmsg1:${command.commandId}`,
      command.command,
      expect.objectContaining({
        journal: expect.objectContaining({ admit: expect.any(Function) }),
        interpreter: expect.anything(),
      }),
    )
    expect(f.p.clinical.capture).toHaveBeenCalledWith(
      expect.objectContaining({
        userId: command.ownerId,
        mode: 'profile',
        expectedEpoch: writerEpoch,
      }),
    )
  })
  it('rejects an internal post-reset recovery read before source/model/effect work', async () => {
    const f = fixture()
    f.p.register.mockImplementation(registerPersistedConversationMeal)
    f.p.writer.readPrepared.mockResolvedValueOnce({ action: 'absent' }).mockResolvedValueOnce({
      ...stored(),
      binding: { ...writerBinding(), epoch: '10000000-0000-4000-8000-000000000099' },
    })
    await expect(f.submit()).rejects.toMatchObject({ status: 409 })
    expect(f.p.writer.readPrepared).toHaveBeenCalledTimes(2)
    for (const m of [f.p.writer.prepare, f.p.writer.commit, f.p.journal.admit, f.p.semantics.start])
      expect(m).not.toHaveBeenCalled()
    expect(f.p.createInterpreter.mock.results[0]?.value.interpret).not.toHaveBeenCalled()
  })
  it('recovers an original-epoch saved effect after a lost commit response using one binding+receipt read', async () => {
    const f = fixture(),
      prepared = { ...stored(), receipt: null }
    f.p.register.mockImplementation(registerPersistedConversationMeal)
    f.p.writer.readPrepared
      .mockResolvedValueOnce(prepared)
      .mockResolvedValueOnce(prepared)
      .mockResolvedValueOnce(stored())
    f.p.writer.commit.mockRejectedValue(new Error('response lost after commit'))
    expect(await f.submit()).toMatchObject({ status: 'saved', receipt: writerReceipt() })
    expect(f.p.writer.commit).toHaveBeenCalledTimes(1)
    expect(f.p.writer.readPrepared).toHaveBeenCalledTimes(3)
    expect(f.p.writer.readEffect).not.toHaveBeenCalled()
    expect(f.p.createInterpreter).not.toHaveBeenCalled()
    expect(f.p.journal.admit).not.toHaveBeenCalled()
  })
  it('provider missing fails before admission/registration, never consumes a model claim', async () => {
    const f = fixture()
    f.p.createInterpreter.mockImplementation(() => {
      throw new Error('missing private key')
    })
    await expect(f.submit()).rejects.toMatchObject({ status: 503 })
    expect(f.p.register).not.toHaveBeenCalled()
    expect(f.p.semantics.start).not.toHaveBeenCalled()
    expect(f.p.journal.admit).not.toHaveBeenCalled()
  })
  it('resumes a prepared or already interpreted command even when provider is unconfigured', async () => {
    const prepared = fixture()
    prepared.p.writer.readPrepared.mockResolvedValue({ ...stored(), receipt: null })
    prepared.p.createInterpreter.mockImplementation(() => {
      throw new Error('not needed')
    })
    expect(await prepared.submit()).toMatchObject({ status: 'saved' })
    expect(prepared.p.createInterpreter).not.toHaveBeenCalled()
    const interpreted = fixture()
    interpreted.p.semantics.read.mockResolvedValue({ action: 'available', status: 'completed' })
    interpreted.p.createInterpreter.mockImplementation(() => {
      throw new Error('not needed')
    })
    expect(await interpreted.submit()).toMatchObject({ status: 'saved' })
    expect(interpreted.p.createInterpreter).not.toHaveBeenCalled()
  })
  it('refuses a changed expected epoch before any fresh provider or writer work', async () => {
    const f = fixture()
    f.p.writer.readPrepared.mockResolvedValue({
      ...stored(),
      receipt: null,
      binding: { ...writerBinding(), epoch: '10000000-0000-4000-8000-000000000099' },
    })
    await expect(f.submit()).rejects.toMatchObject({ status: 409 })
    expect(f.p.createInterpreter).not.toHaveBeenCalled()
    expect(f.p.register).not.toHaveBeenCalled()
  })
  it('cannot acknowledge another bound command or an invalid factual result', async () => {
    const f = fixture()
    f.p.register.mockResolvedValue({
      ...(await f.p.register()),
      command: { ...command, inputHash: 'f'.repeat(64) },
    })
    f.p.register.mockClear()
    await expect(f.submit()).rejects.toMatchObject({ status: 503 })
  })
  it('clarification returns original identity without a saved-effect claim', async () => {
    const f = fixture()
    f.p.semantics.read
      .mockResolvedValueOnce({ action: 'absent' })
      .mockResolvedValueOnce(completedSemanticProof())
    f.p.register.mockResolvedValue({
      status: 'not_recorded',
      command,
      reason: 'missing_quantity',
      foodIndexes: [0],
    })
    expect(await f.submit()).toEqual({
      schema: 'conversation.meal-command-state.v1',
      status: 'not_recorded',
      owner_id: command.ownerId,
      command_id: command.commandId,
      input_hash: command.inputHash,
      epoch: writerEpoch,
      reason: 'missing_quantity',
      food_indexes: [0],
    })
    expect(f.p.decisions.seal).toHaveBeenCalledTimes(1)
    expect(f.p.decisions.seal).toHaveBeenCalledWith(
      {
        ownerId: command.ownerId,
        commandId: command.commandId,
        inputHash: command.inputHash,
        epoch: writerEpoch,
      },
      {
        sourceHash: 'b'.repeat(64),
        attemptId: terminalDecision().decision.attempt_id,
        resultHash: 'c'.repeat(64),
      },
      {
        schema: 'conversation.meal-decision.v1',
        status: 'not_recorded',
        reason: 'missing_quantity',
        food_indexes: [0],
      },
    )
  })
  it('returns the immutable non-registration winner on POST before interpretation or registration', async () => {
    const f = fixture()
    f.p.decisions.read.mockResolvedValue(terminalDecision())
    expect(await f.submit()).toMatchObject({
      status: 'not_recorded',
      reason: 'missing_quantity',
      food_indexes: [0],
    })
    for (const method of [
      f.p.createInterpreter,
      f.p.register,
      f.p.semantics.read,
      f.p.decisions.seal,
      f.p.journal.admit,
    ])
      expect(method).not.toHaveBeenCalled()
  })
  it('restores a terminal clarification on GET without calculations, writes or semantic invocation', async () => {
    const f = fixture()
    f.p.writer.readPrepared.mockResolvedValue({ ...stored(), receipt: null, resolved: null })
    f.p.decisions.read.mockResolvedValue(terminalDecision())
    expect(await f.read()).toMatchObject({
      status: 'not_recorded',
      reason: 'missing_quantity',
      food_indexes: [0],
    })
    for (const method of [
      f.p.createInterpreter,
      f.p.register,
      f.p.semantics.read,
      f.p.decisions.seal,
      f.p.journal.admit,
    ])
      expect(method).not.toHaveBeenCalled()
  })
  it('recovers a lost seal response by one terminal read without sealing again', async () => {
    const f = fixture()
    f.p.register.mockResolvedValue({
      status: 'not_recorded',
      command,
      reason: 'missing_quantity',
      foodIndexes: [0],
    })
    f.p.semantics.read
      .mockResolvedValueOnce({ action: 'absent' })
      .mockResolvedValueOnce(completedSemanticProof())
    f.p.decisions.seal.mockRejectedValue(new Error('response lost after seal'))
    f.p.decisions.read
      .mockResolvedValueOnce({ action: 'absent' })
      .mockResolvedValueOnce(terminalDecision())
    expect(await f.submit()).toMatchObject({ status: 'not_recorded', reason: 'missing_quantity' })
    expect(f.p.decisions.seal).toHaveBeenCalledTimes(1)
    expect(f.p.decisions.read).toHaveBeenCalledTimes(2)
    expect(f.p.register).toHaveBeenCalledTimes(1)
  })
  it('keeps an unproven seal outcome in reconciliation without claiming a terminal answer', async () => {
    const f = fixture()
    f.p.register.mockResolvedValue({
      status: 'not_recorded',
      command,
      reason: 'missing_quantity',
      foodIndexes: [0],
    })
    f.p.semantics.read
      .mockResolvedValueOnce({ action: 'absent' })
      .mockResolvedValueOnce(completedSemanticProof())
    f.p.decisions.seal.mockRejectedValue(new Error('unknown outcome'))
    await expect(f.submit()).rejects.toMatchObject({
      status: 409,
      code: 'conversation_decision_reconciliation_required',
    })
    expect(f.p.decisions.seal).toHaveBeenCalledTimes(1)
    expect(f.p.decisions.read).toHaveBeenCalledTimes(2)
    expect(f.p.register).toHaveBeenCalledTimes(1)
  })
  it.each([
    'started',
    'unknown',
    'error',
  ])('cannot seal a terminal answer from an unfinished %s attempt', async (status) => {
    const f = fixture()
    f.p.register.mockResolvedValue({
      status: 'not_recorded',
      command,
      reason: 'missing_quantity',
      foodIndexes: [0],
    })
    f.p.semantics.read.mockResolvedValueOnce({ action: 'absent' }).mockResolvedValueOnce({
      ...completedSemanticProof(),
      status,
      result: null,
      result_hash: null,
    })
    await expect(f.submit()).rejects.toMatchObject({ status: 503 })
    expect(f.p.decisions.seal).not.toHaveBeenCalled()
  })
  it('rejects a changed semantic epoch before sealing or returning its decision', async () => {
    const f = fixture()
    f.p.register.mockResolvedValue({
      status: 'not_recorded',
      command,
      reason: 'missing_quantity',
      foodIndexes: [0],
    })
    f.p.semantics.read.mockResolvedValueOnce({ action: 'absent' }).mockResolvedValueOnce({
      ...completedSemanticProof(),
      epoch: '10000000-0000-4000-8000-000000000099',
    })
    await expect(f.submit()).rejects.toMatchObject({ status: 409 })
    expect(f.p.decisions.seal).not.toHaveBeenCalled()
  })
  it('classifies an actual stale-epoch semantic refusal as a permanent scope change', async () => {
    const f = fixture()
    f.p.register.mockResolvedValue({
      status: 'not_recorded',
      command,
      reason: 'missing_quantity',
      foodIndexes: [0],
    })
    f.p.semantics.read
      .mockResolvedValueOnce({ action: 'absent' })
      .mockResolvedValueOnce({ action: 'stale_epoch' })
    await expect(f.submit()).rejects.toMatchObject({
      status: 409,
      code: 'conversation_command_changed',
    })
    expect(f.p.decisions.seal).not.toHaveBeenCalled()
  })
  it('returns a concurrent factual winner instead of the losing terminal decision', async () => {
    const f = fixture()
    f.p.register.mockResolvedValue({
      status: 'not_recorded',
      command,
      reason: 'missing_quantity',
      foodIndexes: [0],
    })
    f.p.semantics.read
      .mockResolvedValueOnce({ action: 'absent' })
      .mockResolvedValueOnce(completedSemanticProof())
    f.p.decisions.seal.mockResolvedValue({ action: 'resolved_conflict' })
    f.p.writer.readPrepared
      .mockResolvedValueOnce({ action: 'absent' })
      .mockResolvedValueOnce(stored())
    expect(await f.submit()).toMatchObject({ status: 'saved', receipt: writerReceipt() })
    expect(f.p.register).toHaveBeenCalledTimes(1)
    expect(f.p.decisions.seal).toHaveBeenCalledTimes(1)
    expect(f.p.writer.commit).not.toHaveBeenCalled()
  })
  it('GET reconciliation reads a saved result without a provider or registration', async () => {
    const f = fixture()
    f.p.writer.readPrepared.mockResolvedValue(stored())
    expect(await f.read()).toMatchObject({ status: 'saved', receipt: writerReceipt() })
    expect(f.p.register).not.toHaveBeenCalled()
    expect(f.p.createInterpreter).not.toHaveBeenCalled()
    expect(f.p.journal.admit).not.toHaveBeenCalled()
  })
  it('GET preserves a pending command without running semantics, capture or writers', async () => {
    const f = fixture()
    f.p.writer.readPrepared.mockResolvedValue({ ...stored(), receipt: null })
    expect(await f.read()).toEqual({
      schema: 'conversation.meal-command-state.v1',
      status: 'pending',
      owner_id: command.ownerId,
      command_id: command.commandId,
      input_hash: command.inputHash,
      epoch: writerEpoch,
    })
    for (const m of [
      f.p.register,
      f.p.createInterpreter,
      f.p.semantics.read,
      f.p.journal.admit,
      f.p.writer.commit,
    ])
      expect(m).not.toHaveBeenCalled()
  })
  it('GET absence is scoped by the real current-epoch observation and never creates a command', async () => {
    const f = fixture()
    f.p.journal.read.mockResolvedValue({ action: 'absent' })
    expect(await f.read()).toMatchObject({ status: 'absent', epoch: writerEpoch })
    expect(f.p.clinical.capture).toHaveBeenCalledTimes(1)
    expect(f.p.register).not.toHaveBeenCalled()
    expect(f.p.writer.readPrepared).not.toHaveBeenCalled()
    expect(f.p.journal.admit).not.toHaveBeenCalled()
  })
  it('GET rejects the wrong input hash or tombstoned epoch without returning source/private context', async () => {
    const hash = fixture()
    await expect(
      hash.service.read(candidateAuth, command.commandId, 'f'.repeat(64), writerEpoch),
    ).rejects.toMatchObject({ status: 409 })
    expect(hash.p.writer.readPrepared).not.toHaveBeenCalled()
    const tombstone = fixture()
    tombstone.p.journal.read.mockResolvedValue({ action: 'stale_epoch' })
    await expect(tombstone.read()).rejects.toMatchObject({ status: 409 })
  })
  it('optional presentation failure cannot turn saved food into a retry', async () => {
    const f = fixture()
    f.p.presentation.readHistorical.mockRejectedValue(new Error('optional unavailable'))
    expect(await f.submit()).toMatchObject({ status: 'saved', feedback: null })
    expect(f.p.register).toHaveBeenCalledTimes(1)
  })
})
