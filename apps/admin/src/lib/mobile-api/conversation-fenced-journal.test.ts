import type { ServiceClient } from '@mpp/db'
import { describe, expect, it, vi } from 'vitest'
import { writerBinding, writerCommand, writerEpoch } from './__fixtures__/conversation-meal-writer'
import { createSupabaseConversationFencedJournal } from './conversation-fenced-journal'

function fixture() {
  const rpc = vi
    .fn()
    .mockResolvedValue({ data: { action: 'admitted', command: writerBinding() }, error: null })
  return {
    rpc,
    journal: createSupabaseConversationFencedJournal(
      { rpc } as unknown as ServiceClient,
      writerEpoch,
    ),
  }
}
describe('original-epoch command admission adapter', () => {
  it('uses only the atomic fenced RPC with the exact original body/epoch', async () => {
    const f = fixture()
    expect(await f.journal.admit(writerCommand())).toEqual({
      action: 'admitted',
      binding: writerBinding(),
    })
    expect(f.rpc).toHaveBeenCalledTimes(1)
    expect(f.rpc).toHaveBeenCalledWith('admit_conversation_meal_command_fenced', {
      p_user_id: writerCommand().ownerId,
      p_input: writerCommand().command,
      p_expected_epoch: writerEpoch,
    })
  })
  it.each([
    'input_conflict',
    'stale_epoch',
  ])('preserves %s without retrying old admission', async (action) => {
    const f = fixture()
    f.rpc.mockResolvedValue({ data: { action }, error: null })
    expect(await f.journal.admit(writerCommand())).toEqual({ action })
    expect(f.rpc).toHaveBeenCalledTimes(1)
  })
  it('preserves a known quota refusal as 429 without another RPC or admission', async () => {
    const f = fixture()
    f.rpc.mockResolvedValue({ data: { action: 'rate_limited' }, error: null })
    await expect(f.journal.admit(writerCommand())).rejects.toMatchObject({
      status: 429,
      code: 'conversation_admission_rate_limited',
    })
    expect(f.rpc).toHaveBeenCalledTimes(1)
  })
  it('keeps the existing replay receipt and delegates reads without admitting', async () => {
    const f = fixture()
    f.rpc
      .mockResolvedValueOnce({ data: { action: 'replay', command: writerBinding() }, error: null })
      .mockResolvedValueOnce({ data: { action: 'absent' }, error: null })
    expect(await f.journal.admit(writerCommand())).toMatchObject({ action: 'replay' })
    expect(
      await f.journal.read({
        ownerId: writerCommand().ownerId,
        commandId: writerCommand().commandId,
      }),
    ).toEqual({ action: 'absent' })
    expect(f.rpc.mock.calls[1]?.[0]).toBe('read_conversation_meal_command')
  })
  it.each([
    'owner_id',
    'command_id',
    'input_hash',
    'epoch',
  ])('rejects a returned mismatched %s', (field) => {
    const f = fixture()
    f.rpc.mockResolvedValue({
      data: {
        action: 'admitted',
        command: {
          ...writerBinding(),
          [field]: field === 'input_hash' ? 'f'.repeat(64) : '10000000-0000-4000-8000-000000000099',
        },
      },
      error: null,
    })
    return expect(f.journal.admit(writerCommand())).rejects.toMatchObject({ status: 503 })
  })
  it.each([
    '55P03',
    '40001',
  ])('sanitizes transient %s without reissuing admission', async (code) => {
    const f = fixture()
    f.rpc.mockResolvedValue({ data: null, error: { code, message: 'secret data' } })
    await expect(f.journal.admit(writerCommand())).rejects.toMatchObject({ status: 409 })
    expect(f.rpc).toHaveBeenCalledTimes(1)
  })
  it('does not release or retry when the fenced request outcome is unknown', async () => {
    const f = fixture()
    f.rpc.mockRejectedValue(new Error('private connection failure'))
    await expect(f.journal.admit(writerCommand())).rejects.toMatchObject({ status: 503 })
    expect(f.rpc).toHaveBeenCalledTimes(1)
  })
  it('pins the RPC and detaches the bound input before the first await', async () => {
    const f = fixture(),
      c = structuredClone(writerCommand())
    const p = f.journal.admit(c)
    Object.assign(c.command, { source: { channel: 'text', text: 'changed' } })
    await p
    expect(f.rpc.mock.calls[0]?.[1].p_input).toEqual(writerCommand().command)
  })
})
