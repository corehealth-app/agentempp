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
