import { createHash } from 'node:crypto'
import type { ServiceClient } from '@mpp/db'
import { afterEach, describe, expect, it, vi } from 'vitest'
import { loadSignupPhotoSnapshot, parseSignupPhotoSnapshot } from './signup-body-photo-snapshot'
import { createSupabaseSignupBodyPhotoDependencies } from './supabase-signup-body-photos'

const OWNER = '00000000-0000-4000-8000-000000000951'
const SOURCES = {
  front: 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
  side: 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',
  back: 'cccccccc-cccc-4ccc-8ccc-cccccccccccc',
}
const AT = '2026-10-12T01:00:00.000Z'
const BODY = 'Synthetic consent, never published.'
afterEach(() => vi.unstubAllEnvs())

function openSnapshot() {
  return {
    version: 1,
    user_id: OWNER,
    profile_present: true,
    locale: 'pt-BR',
    timezone: 'America/Sao_Paulo',
    generation_token: {
      onboarding_completed: false,
      onboarding_completed_at: null,
      receipt_count: 0,
    },
    poses: (['front', 'side', 'back'] as const).map((pose) => ({
      pose,
      photo: { id: SOURCES[pose], status: 'read', created_at: AT },
    })),
    remaining_uploads: 6,
    consent: {
      legal_document_id: 'dddddddd-dddd-4ddd-8ddd-dddddddddddd',
      document_key: 'body_photo_estimate_consent',
      version: 'synthetic-v1',
      locale: 'pt-BR',
      body: BODY,
      body_hash: createHash('sha256').update(BODY).digest('hex'),
      accepted_at: AT,
    },
    estimate: {
      is_estimate: true,
      by_sex: {
        masculino: { usable: true, body_fat_percent: 24 },
        feminino: { usable: true, body_fat_percent: 24 },
      },
    },
    candidate: {
      method: 'arithmetic_mean_v1',
      body_fat_percent: 24,
      source_ids: SOURCES,
      fingerprint: 'a'.repeat(64),
    },
    confirmation: null,
  }
}

function closedSnapshot() {
  const validity: { invalidated_at: string | null } = { invalidated_at: null }
  return {
    ...openSnapshot(),
    generation_token: {
      onboarding_completed: true,
      onboarding_completed_at: AT,
      receipt_count: 1,
    },
    poses: [],
    remaining_uploads: 0,
    consent: null,
    estimate: null,
    candidate: null,
    confirmation: {
      decision: 'accepted',
      method: 'arithmetic_mean_v1',
      source_ids: SOURCES,
      fingerprint: 'a'.repeat(64),
      confirmed_body_fat_percent: 24,
      decided_at: AT,
      ...validity,
      active: true,
    },
  }
}

describe('B8b real individual readings from the same snapshot', () => {
  const readings = (values: number[]) =>
    (['front', 'side', 'back'] as const).map((pose, i) => ({
      pose,
      body_fat_percent: values[i],
    }))

  it.each([
    { values: [18, 24, 30], mean: 24 },
    { values: [18.125, 24.125, 30.125], mean: 24.13 },
  ])('preserves actual slots $values and canonical mean $mean', ({ values, mean }) => {
    const current = openSnapshot()
    Object.assign(current.estimate, { readings: readings(values) })
    current.estimate.by_sex.masculino.body_fat_percent = mean
    current.estimate.by_sex.feminino.body_fat_percent = mean
    current.candidate.body_fat_percent = mean
    let failure: unknown
    let parsed: unknown
    try {
      parsed = parseSignupPhotoSnapshot(current, OWNER, true)
    } catch (error) {
      failure = error
    }
    expect(failure).toBeUndefined()
    expect(parsed).toEqual(current)
    expect(current.candidate.source_ids).toEqual(SOURCES)
    expect(current.candidate.fingerprint).toBe('a'.repeat(64))
  })

  it('preserves 2/24/46 as unusable readings, even though their raw mean is24', () => {
    const current = openSnapshot()
    Object.assign(current.estimate, {
      readings: readings([2, 24, 46]),
      by_sex: {
        masculino: { usable: false, reason: 'out_of_range' },
        feminino: { usable: false, reason: 'out_of_range' },
      },
    })
    Reflect.set(current, 'candidate', null)
    let failure: unknown
    let parsed: unknown
    try {
      parsed = parseSignupPhotoSnapshot(current, OWNER, true)
    } catch (error) {
      failure = error
    }
    expect(failure).toBeUndefined()
    expect(parsed).toEqual(current)
  })

  it('keeps a legitimate older v1 without readings, never makes three copies of the mean', () => {
    const current = openSnapshot()
    expect(parseSignupPhotoSnapshot(current, OWNER, true)).toEqual(current)
    expect(current.estimate).not.toHaveProperty('readings')
  })

  it.each([
    null,
    [],
    readings([18, 24, 30]).slice(0, 2),
    [...readings([18, 24, 30])].reverse(),
    [
      { pose: 'front', body_fat_percent: 18 },
      { pose: 'front', body_fat_percent: 24 },
      { pose: 'back', body_fat_percent: 30 },
    ],
    [{ pose: 'front', body_fat_percent: '18' }, ...readings([18, 24, 30]).slice(1)],
    [{ pose: 'front', body_fat_percent: Infinity }, ...readings([18, 24, 30]).slice(1)],
    [
      { pose: 'front', body_fat_percent: 18, notes: 'synthetic private notes' },
      ...readings([18, 24, 30]).slice(1),
    ],
  ])('rejects an invalid triple before public projection: %j', (input) => {
    const current = openSnapshot()
    Object.assign(current.estimate, { readings: input })
    expect(() => parseSignupPhotoSnapshot(current, OWNER, true)).toThrow(
      'Invalid body photo snapshot',
    )
  })

  it.each([false, true])('rejects readings inconsistent with usable=%s', (usable) => {
    const current = openSnapshot()
    Object.assign(current.estimate, {
      readings: readings(usable ? [2, 24, 46] : [18, 24, 30]),
      by_sex: usable
        ? current.estimate.by_sex
        : {
            masculino: { usable: false, reason: 'out_of_range' },
            feminino: { usable: false, reason: 'out_of_range' },
          },
    })
    if (!usable) Reflect.set(current, 'candidate', null)
    expect(() => parseSignupPhotoSnapshot(current, OWNER, true)).toThrow(
      'Invalid body photo snapshot',
    )
  })
})

describe('official body photo snapshot boundary', () => {
  it('keeps the existing patient-not-found error for a missing domain owner', async () => {
    const rpc = vi.fn(async () => ({
      data: null,
      error: {
        code: 'P0002',
        message: 'onboarding_user_not_found',
      },
    }))
    await expect(
      loadSignupPhotoSnapshot({ rpc } as unknown as ServiceClient, OWNER, false),
    ).rejects.toMatchObject({
      status: 404,
      code: 'patient_not_found',
      message: 'Patient profile not found',
    })
    expect(rpc).toHaveBeenCalledTimes(1)
  })

  it('wires the real state factory to one strict open snapshot, lazily', async () => {
    vi.stubEnv('NEXT_PUBLIC_SUPABASE_URL', 'https://xitugspwfxkcluxvrdeg.supabase.co')
    const data = openSnapshot()
    const rpc = vi.fn(async () => ({ data, error: null }))
    const deps = createSupabaseSignupBodyPhotoDependencies({ rpc } as unknown as ServiceClient, {
      enabled: true,
    })
    expect(rpc).not.toHaveBeenCalled()
    expect(await deps.loadStateSnapshot?.(OWNER)).toEqual(data)
    expect(rpc).toHaveBeenCalledTimes(1)
    expect(rpc).toHaveBeenCalledWith('get_mobile_signup_body_photo_snapshot', {
      p_user_id: OWNER,
      p_include_open_photos: true,
    })
  })

  it('refuses the state-factory snapshot on an unknown target before any RPC', async () => {
    vi.stubEnv('NEXT_PUBLIC_SUPABASE_URL', 'https://unlisted.supabase.co')
    const rpc = vi.fn()
    const deps = createSupabaseSignupBodyPhotoDependencies({ rpc } as unknown as ServiceClient, {
      enabled: true,
    })
    await expect(Promise.resolve(deps.loadStateSnapshot?.(OWNER))).rejects.toMatchObject({
      status: 404,
      code: 'body_photos_unavailable',
    })
    expect(rpc).not.toHaveBeenCalled()
  })

  it('loads one snapshot RPC with the server owner and preserves the false branch', async () => {
    const data = closedSnapshot()
    const rpc = vi.fn(async () => ({ data, error: null }))
    const client = { rpc } as unknown as ServiceClient
    await expect(loadSignupPhotoSnapshot(client, OWNER, false)).resolves.toEqual(data)
    expect(rpc).toHaveBeenCalledTimes(1)
    expect(rpc).toHaveBeenCalledWith('get_mobile_signup_body_photo_snapshot', {
      p_user_id: OWNER,
      p_include_open_photos: false,
    })
  })

  it.each([
    [
      'wrong owner',
      (): unknown => ({ data: { ...openSnapshot(), user_id: SOURCES.front }, error: null }),
    ],
    ['null', (): unknown => null],
    ['malformed data', (): unknown => ({ data: null, error: null })],
    [
      'database error',
      (): unknown => ({
        data: null,
        error: { code: '08006', message: 'private database details' },
      }),
    ],
    [
      'throw',
      (): unknown => {
        throw new Error('private database details')
      },
    ],
  ] as const)('rejects a snapshot RPC %s without exposing raw details', async (_label, response) => {
    const rpc = vi.fn(async () => response())
    const client = { rpc } as unknown as ServiceClient
    await expect(loadSignupPhotoSnapshot(client, OWNER, true)).rejects.toMatchObject({
      status: 500,
      code: 'data_access_failed',
      message: 'Invalid body photo snapshot',
    })
    expect(rpc).toHaveBeenCalledTimes(1)
  })

  it('preserves a coherent open snapshot and its opaque official fingerprint', () => {
    const original = openSnapshot()
    expect(parseSignupPhotoSnapshot(original, OWNER, true)).toEqual(original)
    expect(original.candidate.fingerprint).toBe('a'.repeat(64))
  })

  it('preserves historical proof without photos or consent, including invalidated proof', () => {
    const original = closedSnapshot()
    original.confirmation = { ...original.confirmation, invalidated_at: AT, active: false }
    expect(parseSignupPhotoSnapshot(original, OWNER, false)).toEqual(original)
  })

  it('accepts a profile-only open read and a genuine missing profile', () => {
    const original = {
      ...openSnapshot(),
      poses: [],
      remaining_uploads: 0,
      consent: null,
      estimate: null,
      candidate: null,
    }
    expect(parseSignupPhotoSnapshot(original, OWNER, false)).toEqual(original)
    const missing = { ...original, profile_present: false }
    expect(parseSignupPhotoSnapshot(missing, OWNER, true)).toEqual(missing)
  })

  it('retains an unusable out-of-range triad without manufacturing a candidate', () => {
    const original = {
      ...openSnapshot(),
      candidate: null,
      estimate: {
        is_estimate: true,
        by_sex: {
          masculino: { usable: false, reason: 'out_of_range' },
          feminino: { usable: false, reason: 'out_of_range' },
        },
      },
    }
    expect(parseSignupPhotoSnapshot(original, OWNER, true)).toEqual(original)
  })

  it.each([
    [
      'version',
      (s: Record<string, unknown>) => {
        s.version = 2
      },
    ],
    [
      'owner',
      (s: Record<string, unknown>) => {
        s.user_id = SOURCES.front
      },
    ],
    [
      'unknown raw notes',
      (s: Record<string, unknown>) => {
        s.processing_result = 'private'
      },
    ],
    [
      'negative history',
      (s: Record<string, unknown>) => {
        s.generation_token = {
          onboarding_completed: false,
          onboarding_completed_at: null,
          receipt_count: -1,
        }
      },
    ],
    [
      'fractional history',
      (s: Record<string, unknown>) => {
        s.generation_token = {
          onboarding_completed: false,
          onboarding_completed_at: null,
          receipt_count: 1.5,
        }
      },
    ],
    [
      'unsafe history',
      (s: Record<string, unknown>) => {
        s.generation_token = {
          onboarding_completed: false,
          onboarding_completed_at: null,
          receipt_count: Number.MAX_SAFE_INTEGER + 1,
        }
      },
    ],
    [
      'malformed generation time',
      (s: Record<string, unknown>) => {
        s.generation_token = {
          onboarding_completed: true,
          onboarding_completed_at: '2026',
          receipt_count: 1,
        }
      },
    ],
    [
      'coerced boolean',
      (s: Record<string, unknown>) => {
        s.profile_present = 'true'
      },
    ],
    [
      'fractional remaining uploads',
      (s: Record<string, unknown>) => {
        s.remaining_uploads = 1.5
      },
    ],
    [
      'excess remaining uploads',
      (s: Record<string, unknown>) => {
        s.remaining_uploads = 10
      },
    ],
    [
      'noncanonical mean',
      (s: Record<string, unknown>) => {
        s.candidate = { ...openSnapshot().candidate, body_fat_percent: 23.995 }
      },
    ],
    [
      'nonfinite mean',
      (s: Record<string, unknown>) => {
        s.candidate = { ...openSnapshot().candidate, body_fat_percent: Number.NaN }
      },
    ],
    [
      'range',
      (s: Record<string, unknown>) => {
        s.candidate = { ...openSnapshot().candidate, body_fat_percent: 2 }
      },
    ],
    [
      'semantic duplicate IDs',
      (s: Record<string, unknown>) => {
        s.candidate = {
          ...openSnapshot().candidate,
          source_ids: { ...SOURCES, side: SOURCES.front.toUpperCase() },
        }
      },
    ],
    [
      'swapped slot IDs',
      (s: Record<string, unknown>) => {
        s.candidate = {
          ...openSnapshot().candidate,
          source_ids: { ...SOURCES, side: SOURCES.back, back: SOURCES.side },
        }
      },
    ],
    [
      'uppercase fingerprint',
      (s: Record<string, unknown>) => {
        s.candidate = { ...openSnapshot().candidate, fingerprint: 'A'.repeat(64) }
      },
    ],
    [
      'missing candidate',
      (s: Record<string, unknown>) => {
        s.candidate = null
      },
    ],
    [
      'mixed sex estimates',
      (s: Record<string, unknown>) => {
        s.estimate = {
          ...openSnapshot().estimate,
          by_sex: {
            masculino: { usable: true, body_fat_percent: 24 },
            feminino: { usable: true, body_fat_percent: 25 },
          },
        }
      },
    ],
    [
      'unaccepted consent',
      (s: Record<string, unknown>) => {
        s.consent = { ...openSnapshot().consent, accepted_at: null }
      },
    ],
    [
      'wrong consent language',
      (s: Record<string, unknown>) => {
        s.consent = { ...openSnapshot().consent, locale: 'en-US' }
      },
    ],
    [
      'corrupted consent text',
      (s: Record<string, unknown>) => {
        s.consent = { ...openSnapshot().consent, body: 'different' }
      },
    ],
    [
      'unread source',
      (s: Record<string, unknown>) => {
        s.poses = [
          { pose: 'front', photo: { id: SOURCES.front, status: 'unreadable', created_at: AT } },
          ...openSnapshot().poses.slice(1),
        ]
      },
    ],
    [
      'duplicate poses',
      (s: Record<string, unknown>) => {
        s.poses = [openSnapshot().poses[0], openSnapshot().poses[0], openSnapshot().poses[2]]
      },
    ],
    [
      'active proof on open generation',
      (s: Record<string, unknown>) => {
        s.confirmation = closedSnapshot().confirmation
      },
    ],
  ] as const)('rejects malformed or inconsistent %s with a safe data-access error', (_label, mutate) => {
    const value: Record<string, unknown> = structuredClone(openSnapshot())
    mutate(value)
    expect(() => parseSignupPhotoSnapshot(value, OWNER, true)).toThrowError(
      expect.objectContaining({ status: 500, code: 'data_access_failed' }),
    )
  })

  it('rejects open photo data from the profile-only branch', () => {
    expect(() => parseSignupPhotoSnapshot(openSnapshot(), OWNER, false)).toThrow()
  })

  it('rejects invalidated proof described as active', () => {
    const original = closedSnapshot()
    original.confirmation = { ...original.confirmation, invalidated_at: AT }
    expect(() => parseSignupPhotoSnapshot(original, OWNER, false)).toThrow()
  })

  it('rejects a declined receipt carrying an accepted value', () => {
    const original = closedSnapshot()
    original.confirmation.decision = 'declined'
    original.confirmation.active = false
    expect(() => parseSignupPhotoSnapshot(original, OWNER, false)).toThrow()
  })
})
