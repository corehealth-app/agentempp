import type { ServiceClient } from '@mpp/db'
import { describe, expect, it, vi } from 'vitest'
import {
  candidateAuth,
  candidateBinding,
  candidateCommand,
  candidateEnvelope,
  candidateId,
  candidateOwner,
  candidatePreparation,
} from './__fixtures__/conversation-candidate'
import { parseConversationCandidate } from './conversation-command-candidate-contracts'
import {
  preparePersistedConversationMealCandidate,
  readPersistedConversationMealCandidate,
} from './conversation-command-candidate-service'
import type {
  ConversationCommandJournal,
  ConversationJournalRead,
} from './conversation-command-journal'
import type { prepareConversationMealDraft } from './conversation-meal-preparation'
import type { MobileIdempotencyStore } from './idempotency'

function harness() {
  let state: ConversationJournalRead = { action: 'absent' }
  const journal: ConversationCommandJournal = {
    read: vi.fn(async () => state),
    admit: vi.fn<ConversationCommandJournal['admit']>(async () => {
      state = {
        action: 'available',
        binding: candidateBinding(),
        source: candidateCommand(),
        state: 'admitted',
        candidate: null,
        candidateHash: null,
      }
      return { action: 'admitted', binding: candidateBinding() }
    }),
    attach: vi.fn<ConversationCommandJournal['attach']>(async (c, p) => {
      if (state.action !== 'available') return { action: 'stale_epoch' }
      state = {
        ...state,
        state: 'candidate_attached',
        candidateHash: 'a'.repeat(64),
        candidate: parseConversationCandidate(
          {
            schema: 'conversation.meal-candidate.v1',
            input_hash: c.inputHash,
            status: (p as { status: string }).status,
            candidate: p,
          },
          c,
        ),
      }
      return { action: 'attached', candidateHash: 'a'.repeat(64) }
    }),
  }
  const work: MobileIdempotencyStore = {
    claim: vi.fn<MobileIdempotencyStore['claim']>(async () => ({
      action: 'claimed',
      claimId: 'test-claim',
    })),
    complete: vi.fn(async () => {}),
    fail: vi.fn(async () => {}),
  }
  const preparation = {
    media: { findOwned: vi.fn(async () => null) },
    extractor: null,
    confidenceThreshold: vi.fn(async () => 0.6),
  }
  const prepare = vi.fn<typeof prepareConversationMealDraft>(async () => candidatePreparation())
  const client = {
    rpc: vi.fn(async () => {
      throw new Error('unexpected domain RPC')
    }),
  } as unknown as ServiceClient
  const deps = { journal, work, preparation, prepare }
  return {
    deps,
    journal,
    work,
    prepare,
    client,
    set: (s: ConversationJournalRead) => {
      state = s
    },
    get: () => state,
    run: () =>
      preparePersistedConversationMealCandidate(
        client,
        candidateAuth,
        `cmsg1:${candidateId}`,
        candidateCommand().command,
        deps,
      ),
  }
}
describe('durable conversation candidate orchestration, no domain writer', () => {
  it('an expired attempt cannot fail a reclaimed lease while the newer attempt prepares', async () => {
    const h = harness()
    let startA: () => void = () => {
      throw new Error('start A not initialized')
    }
    let failA: () => void = () => {
      throw new Error('fail A not initialized')
    }
    let startB: () => void = () => {
      throw new Error('start B not initialized')
    }
    let resumeB: () => void = () => {
      throw new Error('resume B not initialized')
    }
    const startedA = new Promise<void>((resolve) => {
      startA = resolve
    })
    const failedA = new Promise<void>((resolve) => {
      failA = resolve
    })
    const startedB = new Promise<void>((resolve) => {
      startB = resolve
    })
    const pausedB = new Promise<void>((resolve) => {
      resumeB = resolve
    })
    h.prepare
      .mockImplementationOnce(async () => {
        startA()
        await failedA
        throw new Error('old provider request failed')
      })
      .mockImplementationOnce(async () => {
        startB()
        await pausedB
        return candidatePreparation()
      })
    // Mirrors the existing SQL cache: reacquisition after ten minutes returns
    // the SAME row ID. A third attempt sees B's new live acquisition.
    vi.mocked(h.work.claim)
      .mockResolvedValueOnce({ action: 'claimed', claimId: 'reused-row' })
      .mockResolvedValueOnce({ action: 'claimed', claimId: 'reused-row' })
      .mockResolvedValue({ action: 'in_progress' })
    const old = h.run()
    await startedA
    const current = h.run()
    await startedB
    const failed = expect(old).rejects.toMatchObject({ code: 'conversation_journal_unavailable' })
    failA()
    await failed
    expect(h.work.fail).not.toHaveBeenCalled()
    await expect(h.run()).rejects.toMatchObject({ code: 'conversation_candidate_in_progress' })
    expect(h.prepare).toHaveBeenCalledTimes(2)
    resumeB()
    const saved = await current
    expect(await h.run()).toEqual(saved)
    expect(h.journal.attach).toHaveBeenCalledTimes(1)
  })
  it('a concurrent retry shares the distributed work lease and waits for the one persisted result', async () => {
    const h = harness()
    let extractionStarted: () => void = () => {
      throw new Error('start not initialized')
    }
    let resumeExtraction: () => void = () => {
      throw new Error('resume not initialized')
    }
    const started = new Promise<void>((resolve) => {
      extractionStarted = resolve
    })
    const paused = new Promise<void>((resolve) => {
      resumeExtraction = resolve
    })
    h.prepare.mockImplementation(async () => {
      extractionStarted()
      await paused
      return candidatePreparation()
    })
    vi.mocked(h.work.claim)
      .mockResolvedValueOnce({ action: 'claimed', claimId: 'test-claim' })
      .mockResolvedValue({ action: 'in_progress' })
    const first = h.run()
    await started
    await expect(h.run()).rejects.toMatchObject({ code: 'conversation_candidate_in_progress' })
    expect(h.prepare).toHaveBeenCalledTimes(1)
    expect(h.journal.attach).not.toHaveBeenCalled()
    resumeExtraction()
    const result = await first
    expect(await h.run()).toEqual(result)
    expect(h.prepare).toHaveBeenCalledTimes(1)
    expect(h.journal.attach).toHaveBeenCalledTimes(1)
    expect(h.work.fail).not.toHaveBeenCalled()
  })
  it('admits before extraction and persists once; replays use the exact journal result', async () => {
    const h = harness()
    const first = await h.run(),
      second = await h.run()
    expect(first).toEqual(second)
    expect(first.action).toBe('available')
    expect(h.journal.admit).toHaveBeenCalledTimes(1)
    expect(h.prepare).toHaveBeenCalledTimes(1)
    expect(h.journal.attach).toHaveBeenCalledTimes(1)
    expect(h.work.claim).toHaveBeenCalledTimes(1)
    expect(h.work.complete).toHaveBeenCalledWith('test-claim', candidateOwner, 200, {
      command_id: candidateId,
      candidate_attached: true,
    })
    expect(h.work.fail).not.toHaveBeenCalled()
    expect(h.prepare.mock.invocationCallOrder[0]).toBeGreaterThan(
      vi.mocked(h.journal.admit).mock.invocationCallOrder[0] ?? 0,
    )
  })
  it('existing durable candidate bypasses expired/missing HTTP cache and every preparation dependency', async () => {
    const h = harness()
    await h.run()
    vi.mocked(h.work.claim).mockRejectedValue(new Error('cache expired'))
    h.prepare.mockClear()
    vi.mocked(h.journal.admit).mockClear()
    vi.mocked(h.work.claim).mockClear()
    const result = await h.run()
    expect(result).toEqual(h.get())
    expect(h.prepare).not.toHaveBeenCalled()
    expect(h.journal.admit).not.toHaveBeenCalled()
    expect(h.work.claim).not.toHaveBeenCalled()
  })
  it('same UUID with changed original content conflicts before extraction/cache work', async () => {
    const h = harness()
    await h.run()
    h.prepare.mockClear()
    vi.mocked(h.work.claim).mockClear()
    await expect(
      preparePersistedConversationMealCandidate(
        h.client,
        candidateAuth,
        `cmsg1:${candidateId}`,
        { ...candidateCommand().command, source: { channel: 'text', text: 'Comi arroz 300 g' } },
        h.deps,
      ),
    ).rejects.toMatchObject({ status: 409, code: 'conversation_command_conflict' })
    expect(h.prepare).not.toHaveBeenCalled()
    expect(h.work.claim).not.toHaveBeenCalled()
  })
  it('a reset refusal never falls through to admission, extraction or another epoch', async () => {
    const h = harness()
    h.set({ action: 'stale_epoch' })
    await expect(h.run()).rejects.toMatchObject({ status: 409, code: 'conversation_command_stale' })
    expect(h.journal.admit).not.toHaveBeenCalled()
    expect(h.prepare).not.toHaveBeenCalled()
    expect(h.work.claim).not.toHaveBeenCalled()
  })
  it('status GET uses the read-only journal path only', async () => {
    const h = harness()
    await h.run()
    h.prepare.mockClear()
    vi.mocked(h.work.claim).mockClear()
    const count = vi.mocked(h.journal.admit).mock.calls.length
    expect(
      await readPersistedConversationMealCandidate(h.client, candidateAuth, candidateId, h.journal),
    ).toEqual(h.get())
    expect(h.prepare).not.toHaveBeenCalled()
    expect(h.work.claim).not.toHaveBeenCalled()
    expect(h.journal.admit).toHaveBeenCalledTimes(count)
  })
  it('lost admission response is reconciled by read, without repeating admission', async () => {
    const h = harness(),
      admit = vi.mocked(h.journal.admit).getMockImplementation()
    if (!admit) throw new Error('fixture implementation')
    vi.mocked(h.journal.admit).mockImplementation(async (c) => {
      await admit(c)
      throw new Error('lost')
    })
    await expect(h.run()).resolves.toMatchObject({
      action: 'available',
      state: 'candidate_attached',
    })
    expect(h.journal.admit).toHaveBeenCalledTimes(1)
    expect(h.prepare).toHaveBeenCalledTimes(1)
  })
  it('lost candidate-attach response recovers persisted data without a second attach or extraction', async () => {
    const h = harness(),
      attach = vi.mocked(h.journal.attach).getMockImplementation()
    if (!attach) throw new Error('fixture implementation')
    vi.mocked(h.journal.attach).mockImplementation(async (c, p) => {
      await attach(c, p)
      throw new Error('lost')
    })
    await expect(h.run()).resolves.toMatchObject({
      action: 'available',
      state: 'candidate_attached',
    })
    expect(h.prepare).toHaveBeenCalledTimes(1)
    expect(h.journal.attach).toHaveBeenCalledTimes(1)
    expect(h.work.fail).not.toHaveBeenCalled()
  })
  it('uncertain preparation redacts errors and cannot release a lease whose row ID may have been reclaimed', async () => {
    const h = harness()
    h.prepare.mockRejectedValue(new Error('private-sentinel-password'))
    let seen: unknown
    try {
      await h.run()
    } catch (error) {
      seen = error
    }
    expect(seen).toMatchObject({ status: 503, code: 'conversation_journal_unavailable' })
    expect(String(seen)).not.toContain('private-sentinel')
    expect(h.work.fail).not.toHaveBeenCalled()
    expect(h.journal.attach).not.toHaveBeenCalled()
  })
  it('an active distributed preparation lease with no persisted candidate never re-extracts', async () => {
    const h = harness()
    vi.mocked(h.work.claim).mockResolvedValue({ action: 'in_progress' })
    await expect(h.run()).rejects.toMatchObject({
      status: 409,
      code: 'conversation_candidate_in_progress',
    })
    expect(h.prepare).not.toHaveBeenCalled()
    expect(h.work.fail).not.toHaveBeenCalled()
  })
  it('HTTP completion failure cannot invalidate the already durable result or cause another extraction', async () => {
    const h = harness()
    vi.mocked(h.work.complete).mockRejectedValue(new Error('lost cache response'))
    const first = await h.run()
    expect(await h.run()).toEqual(first)
    expect(h.prepare).toHaveBeenCalledTimes(1)
    expect(h.journal.attach).toHaveBeenCalledTimes(1)
  })
  it('a competing completed candidate is read as winner, rather than overwritten', async () => {
    const h = harness()
    vi.mocked(h.journal.attach).mockImplementation(async () => {
      h.set({
        action: 'available',
        binding: candidateBinding(),
        source: candidateCommand(),
        state: 'candidate_attached',
        candidate: parseConversationCandidate(candidateEnvelope(), candidateCommand()),
        candidateHash: 'b'.repeat(64),
      })
      return { action: 'candidate_conflict' }
    })
    await expect(h.run()).resolves.toMatchObject({ candidateHash: 'b'.repeat(64) })
    expect(h.journal.attach).toHaveBeenCalledTimes(1)
  })
  it('a reset during extraction withholds the stale result', async () => {
    const h = harness()
    h.prepare.mockImplementation(async () => {
      h.set({ action: 'stale_epoch' })
      return candidatePreparation()
    })
    await expect(h.run()).rejects.toMatchObject({ code: 'conversation_command_stale' })
    expect(h.work.complete).not.toHaveBeenCalled()
  })
  it('captures auth, raw command and callback identities before the first await', async () => {
    const h = harness(),
      auth = structuredClone(candidateAuth),
      raw = structuredClone(candidateCommand().command)
    const original = h.journal.read.bind(h.journal)
    vi.mocked(h.journal.read).mockImplementationOnce(async (who) => {
      auth.userId = candidateId
      Object.assign(raw, { source: { channel: 'text', text: 'changed' } })
      h.deps.prepare = vi.fn(async () => {
        throw new Error('replaced')
      })
      return original(who)
    })
    await expect(
      preparePersistedConversationMealCandidate(
        h.client,
        auth,
        `cmsg1:${candidateId}`,
        raw,
        h.deps,
      ),
    ).resolves.toMatchObject({ action: 'available' })
    expect(h.prepare.mock.calls[0]?.slice(1)).toEqual([
      candidateAuth,
      `cmsg1:${candidateId}`,
      candidateCommand().command,
    ])
  })
})
