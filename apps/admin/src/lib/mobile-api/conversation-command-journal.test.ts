import type { ServiceClient } from '@mpp/db'
import { describe, expect, it, vi } from 'vitest'
import {
  candidateBinding,
  candidateCommand,
  candidateEnvelope,
  candidateId,
  candidateOwner,
  candidatePreparation,
  candidateRead,
} from './__fixtures__/conversation-candidate'
import { createSupabaseConversationCommandJournal } from './conversation-command-journal'

const who = { ownerId: candidateOwner, commandId: candidateId }
function db(data: unknown) {
  const rpc = vi.fn(async () => ({ data, error: null }))
  return { client: { rpc } as unknown as ServiceClient, rpc }
}
describe('private typed conversation journal transport', () => {
  it('construction is inert; read decodes/detaches original source and persisted candidate only', async () => {
    const raw = candidateRead(),
      d = db(raw)
    const store = createSupabaseConversationCommandJournal(d.client)
    expect(d.rpc).not.toHaveBeenCalled()
    const result = await store.read(who)
    expect(d.rpc).toHaveBeenCalledWith('read_conversation_meal_command', {
      p_user_id: candidateOwner,
      p_command_id: candidateId,
    })
    expect(result.action).toBe('available')
    if (result.action !== 'available') throw new Error('fixture')
    expect(result.source).toEqual(candidateCommand())
    expect(result.candidate?.candidate).toEqual(candidatePreparation())
    Object.assign(raw.source_input, { source: { channel: 'text', text: 'changed' } })
    expect(result.source.command.source).toEqual(candidateCommand().command.source)
    expect(Object.isFrozen(result.candidate?.candidate)).toBe(true)
  })
  it('distinguishes admitted-without-result, absent and stale without writing', async () => {
    for (const raw of [candidateRead(false), { action: 'absent' }, { action: 'stale_epoch' }]) {
      const d = db(raw),
        store = createSupabaseConversationCommandJournal(d.client)
      const result = await store.read(who)
      expect(result.action).toBe(raw.action)
      expect(d.rpc).toHaveBeenCalledTimes(1)
    }
  })
  it('admits only the validated original command and binds the returned owner/epoch/input hash', async () => {
    const d = db({ action: 'admitted', command: candidateBinding() })
    const store = createSupabaseConversationCommandJournal(d.client)
    expect((await store.admit(candidateCommand())).action).toBe('admitted')
    expect(d.rpc).toHaveBeenCalledWith('admit_conversation_meal_command', {
      p_user_id: candidateOwner,
      p_input: candidateCommand().command,
    })
  })
  it('attaches one closed candidate envelope without any domain or feedback RPC', async () => {
    const d = db({ action: 'attached', candidate_hash: 'a'.repeat(64) })
    const store = createSupabaseConversationCommandJournal(d.client)
    await expect(store.attach(candidateCommand(), candidatePreparation())).resolves.toEqual({
      action: 'attached',
      candidateHash: 'a'.repeat(64),
    })
    expect(d.rpc).toHaveBeenCalledWith('attach_conversation_meal_candidate', {
      p_user_id: candidateOwner,
      p_command_id: candidateId,
      p_input_hash: candidateCommand().inputHash,
      p_candidate: candidateEnvelope(),
    })
    expect(d.rpc).toHaveBeenCalledTimes(1)
  })
  it.each([
    'input_conflict',
    'candidate_conflict',
    'stale_epoch',
    'absent',
  ])('keeps the explicit attach outcome %s', async (action) => {
    const d = db({ action })
    expect(
      await createSupabaseConversationCommandJournal(d.client).attach(
        candidateCommand(),
        candidatePreparation(),
      ),
    ).toEqual({ action })
  })
  it('rejects internally inconsistent owner, ID, input, status and candidate provenance', async () => {
    const invalid: unknown[] = []
    let r = candidateRead()
    r.command.owner_id = candidateId
    invalid.push(r)
    r = candidateRead()
    r.command.input_hash = 'b'.repeat(64)
    invalid.push(r)
    r = candidateRead()
    r.source_input = { ...r.source_input, meal_type: 'almoco' }
    invalid.push(r)
    r = candidateRead()
    r.state = 'admitted'
    invalid.push(r)
    r = candidateRead()
    if (r.candidate) r.candidate.status = 'conversational'
    invalid.push(r)
    r = candidateRead()
    if (r.candidate) Object.assign(r.candidate.candidate.command, { ownerId: candidateId })
    invalid.push(r)
    invalid.push({ ...candidateRead(), secret_context: 'private-sentinel' })
    for (const raw of invalid) {
      const d = db(raw)
      await expect(
        createSupabaseConversationCommandJournal(d.client).read(who),
      ).rejects.toMatchObject({ code: 'conversation_journal_unavailable', status: 503 })
    }
  })
  it('malformed optional candidates cannot become prepared food or expose private provider details', async () => {
    const r = candidateRead()
    if (!r.candidate || r.candidate.candidate.status !== 'prepared') throw new Error('fixture')
    const item = r.candidate.candidate.draft.items[0]
    if (!item) throw new Error('fixture item')
    item.quantity_g = null
    const d = db(r)
    await expect(
      createSupabaseConversationCommandJournal(d.client).read(who),
    ).rejects.toMatchObject({ code: 'conversation_journal_unavailable' })
    const bad = {
      rpc: vi.fn(async () => ({ data: null, error: { message: 'private-sentinel-token' } })),
    }
    try {
      await createSupabaseConversationCommandJournal(bad as unknown as ServiceClient).read(who)
      throw new Error('expected error')
    } catch (error) {
      expect(String(error)).not.toContain('private-sentinel')
      expect(error).toMatchObject({ code: 'conversation_journal_unavailable' })
    }
  })
})
