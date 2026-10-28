import { describe, expect, it } from 'vitest'
import { readClinicalGenerationAuthority } from './clinical-generation-authority'

const user = 'b3b01000-0000-4000-8000-000000002961'
const generation = 'b3b01000-0000-4000-8000-000000002962'
const epoch = 'b3b01000-0000-4000-8000-000000002963'
const other = 'b3b01000-0000-4000-8000-000000002964'
const completedAt = '2026-10-01T23:00:00.000000Z'
const observedAt = '2026-10-27T23:00:00.000000Z'
const expected = { userId: user, profileCompletedAt: completedAt, observedAt }
function signup() {
  return {
    signup_generation: generation,
    signup_epoch: epoch,
    authority: {
      kind: 'signup_receipt',
      generation,
      epoch,
      completed_at: completedAt,
      timezone_at_signup: 'America/Sao_Paulo',
    },
  }
}
function legacy() {
  return {
    signup_generation: generation,
    signup_epoch: epoch,
    authority: {
      kind: 'legacy_transition',
      user_id: user,
      generation,
      epoch,
      admitted_at: '2026-10-27T22:00:00.000000Z',
      admitted_date: '2026-10-27',
      timezone_at_admission: 'America/Sao_Paulo',
      profile_completed_marker: null as string | null,
    },
  }
}

describe('captured clinical generation source', () => {
  it('requires and preserves the genuine signup discriminant and original completion', () => {
    expect(readClinicalGenerationAuthority(signup(), expected)).toEqual(signup().authority)
  })
  it('accepts an honest present legacy boundary while keeping the old marker unknown', () => {
    const raw = legacy()
    expect(readClinicalGenerationAuthority(raw, { ...expected, profileCompletedAt: null })).toEqual(
      raw.authority,
    )
    expect(raw.authority.profile_completed_marker).toBeNull()
  })
  it.each(['signup_generation', 'signup_epoch'])('refuses an alias substituted in %s', (field) => {
    const raw = signup()
    Object.assign(raw, { [field]: other })
    expect(() => readClinicalGenerationAuthority(raw, expected)).toThrow(
      'Invalid clinical generation authority',
    )
  })
  it.each(['generation', 'epoch'])('refuses a source with substituted %s', (field) => {
    const raw = signup()
    Object.assign(raw.authority, { [field]: other })
    expect(() => readClinicalGenerationAuthority(raw, expected)).toThrow()
  })
  it('refuses missing source instead of inferring it from a timestamp or UUID', () => {
    const { authority: _, ...raw } = signup()
    expect(() => readClinicalGenerationAuthority(raw, expected)).toThrow()
  })
  it('refuses an invented source kind and mixed source fields', () => {
    expect(() =>
      readClinicalGenerationAuthority(
        { ...signup(), authority: { ...signup().authority, kind: 'legacy_unknown' } },
        expected,
      ),
    ).toThrow()
    expect(() =>
      readClinicalGenerationAuthority(
        { ...signup(), authority: { ...signup().authority, admitted_at: observedAt } },
        expected,
      ),
    ).toThrow()
  })
  it.each([
    null,
    '2026-10-02T23:00:00.000000Z',
  ])('does not weaken genuine signup marker %s', (marker) => {
    expect(() =>
      readClinicalGenerationAuthority(signup(), { ...expected, profileCompletedAt: marker }),
    ).toThrow()
  })
  it('refuses a future genuine completion', () => {
    expect(() =>
      readClinicalGenerationAuthority(signup(), {
        ...expected,
        observedAt: '2026-09-30T23:00:00.000000Z',
      }),
    ).toThrow()
  })
  it('binds a legacy boundary to its actual owner', () => {
    const raw = legacy()
    raw.authority.user_id = other
    expect(() =>
      readClinicalGenerationAuthority(raw, { ...expected, profileCompletedAt: null }),
    ).toThrow()
  })
  it('refuses a changed legacy completion marker, including NULL substitution', () => {
    expect(() => readClinicalGenerationAuthority(legacy(), expected)).toThrow()
    const raw = legacy()
    raw.authority.profile_completed_marker = completedAt
    expect(() =>
      readClinicalGenerationAuthority(raw, { ...expected, profileCompletedAt: null }),
    ).toThrow()
    expect(readClinicalGenerationAuthority(raw, expected).kind).toBe('legacy_transition')
  })
  it('refuses a future admission and a marker after that boundary', () => {
    const raw = legacy()
    expect(() =>
      readClinicalGenerationAuthority(raw, {
        ...expected,
        profileCompletedAt: null,
        observedAt: '2026-10-27T21:59:59.999999Z',
      }),
    ).toThrow()
    raw.authority.profile_completed_marker = observedAt
    expect(() =>
      readClinicalGenerationAuthority(raw, { ...expected, profileCompletedAt: observedAt }),
    ).toThrow()
  })
})
