import type { ServiceClient } from '@mpp/db'
import { describe, expect, it, vi } from 'vitest'
import {
  activateDueCoachContentPack,
  type CoachContentPackActivationDependencies,
  createCoachContentPackActivationRepository,
} from './coach-content-pack-activation.js'

const NOW = '2026-08-20T04:13:00.000Z'
const PACK_ID = '00000000-0000-4000-8000-000000000951'
const PREVIOUS_PACK_ID = '00000000-0000-4000-8000-000000000952'

function dependencies(
  result: Awaited<
    ReturnType<CoachContentPackActivationDependencies['repository']['activateDue']>
  > = { outcome: 'no_due_pack' },
): CoachContentPackActivationDependencies {
  return {
    repository: {
      activateDue: vi.fn().mockResolvedValue(result),
    },
  }
}

describe('BodyFlow coach content pack activation', () => {
  it('returns a bounded no-op when no approved pack is due', async () => {
    const deps = dependencies()

    await expect(activateDueCoachContentPack(deps, new Date(NOW))).resolves.toEqual({
      outcome: 'no_due_pack',
    })
    expect(deps.repository.activateDue).toHaveBeenCalledWith(NOW)
  })

  it('activates at most one complete approved pack per invocation', async () => {
    const deps = dependencies({
      outcome: 'activated',
      packId: PACK_ID,
      previousPackId: PREVIOUS_PACK_ID,
      entryCount: 1080,
      activatedAt: NOW,
    })

    await expect(activateDueCoachContentPack(deps, new Date(NOW))).resolves.toEqual({
      outcome: 'activated',
      packId: PACK_ID,
      previousPackId: PREVIOUS_PACK_ID,
      entryCount: 1080,
      activatedAt: NOW,
    })
    expect(deps.repository.activateDue).toHaveBeenCalledOnce()
  })

  it('treats a retry after a committed activation as an idempotent no-op', async () => {
    const deps = dependencies()
    vi.mocked(deps.repository.activateDue)
      .mockResolvedValueOnce({
        outcome: 'activated',
        packId: PACK_ID,
        previousPackId: null,
        entryCount: 1080,
        activatedAt: NOW,
      })
      .mockResolvedValueOnce({ outcome: 'no_due_pack' })

    await expect(activateDueCoachContentPack(deps, new Date(NOW))).resolves.toMatchObject({
      outcome: 'activated',
    })
    await expect(activateDueCoachContentPack(deps, new Date(NOW))).resolves.toEqual({
      outcome: 'no_due_pack',
    })
    expect(deps.repository.activateDue).toHaveBeenCalledTimes(2)
  })

  it('fails closed with a generic error when the approved pack is incomplete', async () => {
    const rpc = vi.fn().mockResolvedValue({
      data: null,
      error: { message: 'approved content pack must contain exactly 1,080 valid renditions' },
    })
    const repository = createCoachContentPackActivationRepository({
      rpc,
    } as unknown as ServiceClient)

    await expect(repository.activateDue(NOW)).rejects.toThrow(
      'coach content pack activation failed',
    )
    expect(rpc).toHaveBeenCalledWith('activate_due_coach_content_pack', { p_now: NOW })
  })

  it('maps only technical activation fields and never returns patient data', async () => {
    const rpc = vi.fn().mockResolvedValue({
      data: {
        outcome: 'activated',
        pack_id: PACK_ID,
        previous_pack_id: null,
        entry_count: 1080,
        activated_at: NOW,
      },
      error: null,
    })
    const repository = createCoachContentPackActivationRepository({
      rpc,
    } as unknown as ServiceClient)

    const result = await repository.activateDue(NOW)

    expect(result).toEqual({
      outcome: 'activated',
      packId: PACK_ID,
      previousPackId: null,
      entryCount: 1080,
      activatedAt: NOW,
    })
    expect(JSON.stringify(result)).not.toMatch(/user|email|name|message|body|token/i)
  })
})
