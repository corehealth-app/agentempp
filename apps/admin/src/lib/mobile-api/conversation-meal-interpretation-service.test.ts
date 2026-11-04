import type { ServiceClient } from '@mpp/db'
import { describe, expect, it, vi } from 'vitest'
import {
  candidateAuth,
  candidateBinding,
  candidateCommand,
  candidateEpoch,
  candidateId,
  candidateOwner,
} from './__fixtures__/conversation-candidate'
import { bindConversationCommand } from './conversation-command-contracts'
import type { ConversationMealInterpretation } from './conversation-meal-interpretation-contracts'
import { interpretPersistedConversationMeal } from './conversation-meal-interpretation-service'

const attemptId = '10000000-0000-4000-8000-000000000010'
const sourceHash = 'a'.repeat(64)
const unavailableDb = {} as ServiceClient
function interpretation(): ConversationMealInterpretation {
  return {
    schema: 'conversation.meal-interpretation.v1',
    interpreter_version: 'conversation.meal-interpreter.v1',
    owner_id: candidateOwner,
    command_id: candidateId,
    attempt_id: attemptId,
    input_hash: candidateCommand().inputHash,
    source_hash: sourceHash,
    source_units: ['command_text'],
    decision: 'clarification_required',
    reason: 'ambiguous',
    sources: [
      {
        unit: 'command_text',
        classification: 'ambiguous',
        spans: [{ start: 0, end: 15, kind: 'other', food_index: null }],
        visual_indexes: [],
      },
    ],
    foods: [],
    provider_metadata: {
      model: 'anthropic/claude-haiku-4.5',
      prompt_tokens: 10,
      completion_tokens: 20,
      cost_usd: null,
      latency_ms: 100,
    },
  }
}
function record(action: string, status = 'completed') {
  return {
    action,
    owner_id: candidateOwner,
    command_id: candidateId,
    attempt_id: attemptId,
    interpreter_version: 'conversation.meal-interpreter.v1',
    input_hash: candidateCommand().inputHash,
    source_hash: sourceHash,
    epoch: candidateEpoch,
    status,
    result: status === 'completed' ? interpretation() : null,
    result_hash: status === 'completed' ? 'b'.repeat(64) : null,
    started_at: '2026-11-04T00:00:00Z',
    finished_at: status === 'started' ? null : '2026-11-04T00:00:01Z',
    error_code: status === 'unknown' ? 'provider_outcome_unknown' : null,
  }
}
function dependencies(command = candidateCommand()) {
  const interpreted = { ...interpretation(), input_hash: command.inputHash }
  const saved = (action: string, status = 'completed') => ({
    ...record(action, status),
    input_hash: command.inputHash,
    result: status === 'completed' ? interpreted : null,
  })
  const journal = {
    read: vi.fn().mockResolvedValue({ action: 'absent' }),
    admit: vi.fn().mockResolvedValue({
      action: 'admitted',
      binding: { ...candidateBinding(), input_hash: command.inputHash },
    }),
    attach: vi.fn(() => {
      throw new Error('legacy candidate attach forbidden')
    }),
  }
  const sources = {
    capture: vi.fn().mockResolvedValue({
      action: 'captured',
      sourceHash,
      capturedAt: '2026-11-04T00:00:00Z',
      epoch: candidateEpoch,
      context: {
        schema: 'conversation.meal-source.v1',
        owner_id: candidateOwner,
        command_id: candidateId,
        input_hash: command.inputHash,
        epoch: candidateEpoch,
        source_input: command.command,
        source_units: ['command_text'],
        source_evidence: {},
        media: null,
        catalog: {},
        owner: {},
        clinical: {},
        day: {},
      },
    }),
  }
  const store = {
    read: vi.fn().mockResolvedValue({ action: 'absent' }),
    start: vi.fn().mockResolvedValue(saved('claimed', 'started')),
    commit: vi.fn().mockResolvedValue(saved('committed')),
    markUnknown: vi.fn().mockResolvedValue(saved('committed', 'unknown')),
  }
  const interpreter = { interpret: vi.fn().mockResolvedValue(interpreted) }
  return { journal, sources, store, interpreter }
}
function run(d: ReturnType<typeof dependencies>, raw: unknown = candidateCommand().command) {
  return interpretPersistedConversationMeal(
    unavailableDb,
    candidateAuth,
    `cmsg1:${candidateId}`,
    raw,
    d,
  )
}

describe('actual durable meal interpretation composition', () => {
  it('reads before any admission/capture and replays without a provider call', async () => {
    const d = dependencies()
    d.store.read.mockResolvedValue(record('available'))
    expect(await run(d)).toMatchObject({ status: 'interpreted', interpretation: interpretation() })
    for (const call of [
      d.journal.read,
      d.journal.admit,
      d.sources.capture,
      d.store.start,
      d.interpreter.interpret,
      d.store.commit,
    ])
      expect(call).not.toHaveBeenCalled()
  })
  it('admission + actual captured source + DB claim precede the one provider call and result commit', async () => {
    const d = dependencies()
    expect(await run(d)).toMatchObject({ status: 'interpreted', interpretation: interpretation() })
    expect(d.journal.admit).toHaveBeenCalledWith(candidateCommand())
    expect(d.sources.capture).toHaveBeenCalledWith(candidateCommand())
    expect(d.store.start).toHaveBeenCalledWith(candidateCommand(), sourceHash)
    expect(d.interpreter.interpret).toHaveBeenCalledTimes(1)
    expect(d.interpreter.interpret).toHaveBeenCalledWith(
      expect.objectContaining({
        source_units: ['command_text'],
        sources: [{ unit: 'command_text', text: 'Comi arroz 200 g', visual_items: [] }],
      }),
      expect.objectContaining({ attemptId, remainingMs: expect.any(Number) }),
    )
    expect(d.store.commit).toHaveBeenCalledWith(candidateCommand(), attemptId, interpretation())
    expect(d.journal.attach).not.toHaveBeenCalled()
  })
  it.each([
    'started',
    'unknown',
    'error',
  ])('never reclaims or pays again for durable %s', async (status) => {
    const d = dependencies()
    d.store.read.mockResolvedValue(record('reconciliation_required', status))
    await expect(run(d)).rejects.toMatchObject({
      status: 409,
      code: 'conversation_meal_interpretation_reconciliation_required',
    })
    expect(d.interpreter.interpret).not.toHaveBeenCalled()
    expect(d.store.start).not.toHaveBeenCalled()
    expect(d.sources.capture).not.toHaveBeenCalled()
  })
  it('a competing claim returns only its terminal winner without calling provider', async () => {
    const d = dependencies()
    d.store.start.mockResolvedValue(record('replay'))
    expect(await run(d)).toMatchObject({ status: 'interpreted' })
    expect(d.interpreter.interpret).not.toHaveBeenCalled()
  })
  it('lost start response reconciles by read and never converts stored started into permission', async () => {
    const d = dependencies()
    d.store.start.mockRejectedValue(new Error('lost response'))
    d.store.read
      .mockResolvedValueOnce({ action: 'absent' })
      .mockResolvedValueOnce(record('reconciliation_required', 'started'))
    await expect(run(d)).rejects.toMatchObject({ status: 409 })
    expect(d.store.start).toHaveBeenCalledTimes(1)
    expect(d.interpreter.interpret).not.toHaveBeenCalled()
  })
  it('lost success commit response returns only a persisted read result', async () => {
    const d = dependencies()
    d.store.commit.mockRejectedValue(new Error('lost commit'))
    d.store.read
      .mockResolvedValueOnce({ action: 'absent' })
      .mockResolvedValueOnce(record('available'))
    expect(await run(d)).toMatchObject({ interpretation: interpretation() })
    expect(d.interpreter.interpret).toHaveBeenCalledTimes(1)
    expect(d.store.commit).toHaveBeenCalledTimes(1)
    expect(d.store.markUnknown).not.toHaveBeenCalled()
  })
  it('an unresolved commit remains reconciliation, with no second commit or provider attempt', async () => {
    const d = dependencies()
    d.store.commit.mockRejectedValue(new Error('uncertain'))
    d.store.read
      .mockResolvedValueOnce({ action: 'absent' })
      .mockResolvedValueOnce(record('reconciliation_required', 'started'))
    await expect(run(d)).rejects.toMatchObject({ status: 409 })
    expect(d.store.commit).toHaveBeenCalledTimes(1)
    expect(d.interpreter.interpret).toHaveBeenCalledTimes(1)
  })
  it('provider failure marks unknown once and never reruns extraction/domain work', async () => {
    const d = dependencies()
    d.interpreter.interpret.mockRejectedValue(new Error('private provider detail'))
    d.store.read
      .mockResolvedValueOnce({ action: 'absent' })
      .mockResolvedValueOnce(record('reconciliation_required', 'unknown'))
    await expect(run(d)).rejects.toMatchObject({ status: 409 })
    expect(d.store.markUnknown).toHaveBeenCalledWith(
      candidateCommand(),
      attemptId,
      'provider_outcome_unknown',
    )
    expect(d.store.commit).not.toHaveBeenCalled()
    expect(d.interpreter.interpret).toHaveBeenCalledTimes(1)
  })
  it('does not persist a returned interpretation belonging to another source', async () => {
    const d = dependencies()
    d.interpreter.interpret.mockResolvedValue({ ...interpretation(), source_hash: 'f'.repeat(64) })
    await expect(run(d)).rejects.toMatchObject({ status: 409 })
    expect(d.store.commit).not.toHaveBeenCalled()
    expect(d.store.markUnknown).toHaveBeenCalledTimes(1)
  })
  it('does not call provider if the DB claim has another epoch', async () => {
    const d = dependencies()
    d.store.start.mockResolvedValue({
      ...record('claimed', 'started'),
      epoch: '10000000-0000-4000-8000-000000000099',
    })
    await expect(run(d)).rejects.toMatchObject({ status: 503 })
    expect(d.interpreter.interpret).not.toHaveBeenCalled()
  })
  it('uses a finite backend budget before doing any lookup', async () => {
    const d = dependencies()
    await expect(
      interpretPersistedConversationMeal(
        unavailableDb,
        candidateAuth,
        `cmsg1:${candidateId}`,
        candidateCommand().command,
        { ...d, remainingMs: Number.NaN },
      ),
    ).rejects.toMatchObject({ status: 503 })
    expect(d.store.read).not.toHaveBeenCalled()
    expect(d.interpreter.interpret).not.toHaveBeenCalled()
  })
  it.each([
    'stale_epoch',
    'source_conflict',
    'day_closed',
  ])('refusal %s makes no provider call', async (action) => {
    const d = dependencies()
    d.store.start.mockResolvedValue({ action })
    await expect(run(d)).rejects.toMatchObject({ status: 409 })
    expect(d.interpreter.interpret).not.toHaveBeenCalled()
  })
  it('does not route bare food lists through the old first-person pre-gate', async () => {
    const command = structuredClone(candidateCommand().command)
    Object.assign(command, { source: { channel: 'text', text: 'arroz 200 g; feijão 100 g' } })
    const bound = bindConversationCommand(candidateOwner, `cmsg1:${candidateId}`, command),
      d = dependencies(bound)
    expect(await run(d, command)).toMatchObject({ status: 'interpreted' })
    expect(d.interpreter.interpret).toHaveBeenCalledWith(
      expect.objectContaining({
        sources: [{ unit: 'command_text', text: 'arroz 200 g; feijão 100 g', visual_items: [] }],
      }),
      expect.any(Object),
    )
    expect(d.journal.attach).not.toHaveBeenCalled()
  })
  it('rejects changed identity before any lookup', async () => {
    const d = dependencies()
    await expect(
      interpretPersistedConversationMeal(
        unavailableDb,
        candidateAuth,
        'wrong-key',
        candidateCommand().command,
        d,
      ),
    ).rejects.toMatchObject({ status: 422 })
    expect(d.store.read).not.toHaveBeenCalled()
  })
  it('detaches callbacks and the authenticated command before the first await', async () => {
    const d = dependencies()
    let release!: () => void
    d.store.read.mockImplementationOnce(async () => {
      await new Promise<void>((resolve) => {
        release = resolve
      })
      return { action: 'absent' }
    })
    const raw = structuredClone(candidateCommand().command),
      response = run(d, raw)
    const original = d.interpreter.interpret
    d.interpreter.interpret = vi.fn().mockRejectedValue(new Error('mutated dependency'))
    Object.assign(raw, { source: { channel: 'text', text: 'changed' } })
    release()
    expect(await response).toMatchObject({ status: 'interpreted' })
    expect(original).toHaveBeenCalledTimes(1)
    expect(d.interpreter.interpret).not.toHaveBeenCalled()
  })
})
