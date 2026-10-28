import { describe, expect, it } from 'vitest'
import {
  parseReevaluationCycleRpcState,
  parseReevaluationCycleState,
} from './reevaluation-cycle-contracts'

function state() {
  return {
    version: 1,
    availability: 'available',
    unavailable_reason: null,
    clock: { base_date: '2026-10-01', due_date: '2026-10-15', timezone: 'America/Sao_Paulo' },
    cycle: {
      id: 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
      signup_generation: 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',
      revision: '9007199254740993',
      kind: 'REGULAR',
      status: 'open',
      base_date: '2026-10-01',
      due_date: '2026-10-15',
      timezone_at_open: 'America/Sao_Paulo',
      opened_at: '2026-10-15T03:00:00.123456Z',
    },
  }
}
const disabled = {
  version: 1,
  availability: 'unavailable',
  unavailable_reason: 'disabled',
  clock: null,
  cycle: null,
}

describe('reevaluation cycle wire version1', () => {
  it('retains the exact bigint revision and all six timestamp decimals', () => {
    expect(parseReevaluationCycleRpcState(state())).toEqual(state())
    const maximum = state()
    maximum.cycle.revision = '9223372036854775807'
    expect(parseReevaluationCycleRpcState(maximum).cycle?.revision).toBe('9223372036854775807')
  })

  it.each([
    'open',
    'collecting',
    'review_ready',
  ])('reads the exact authoritative EARLY_FULL %s wire', (status) => {
    const input = state()
    input.cycle.kind = 'EARLY_FULL'
    input.cycle.status = status
    expect(parseReevaluationCycleRpcState(input)).toEqual(input)
    expect(() =>
      parseReevaluationCycleRpcState({
        ...input,
        availability: 'unavailable',
        unavailable_reason: 'not_due',
      }),
    ).toThrow()
    expect(() =>
      parseReevaluationCycleRpcState({ ...input, cycle: { ...input.cycle, noPlan: true } }),
    ).toThrow()
  })

  it('accepts due but not started without inventing a cycle', () => {
    expect(parseReevaluationCycleRpcState({ ...state(), cycle: null }).cycle).toBeNull()
  })

  it.each(['open', 'collecting', 'review_ready'])('accepts the active status %s', (status) => {
    const input = state()
    input.cycle.status = status
    expect(parseReevaluationCycleRpcState(input).cycle?.status).toBe(status)
  })

  it.each([
    'onboarding_incomplete',
    'anchor_unproven',
  ])('accepts %s only without an anchor', (reason) => {
    const input = {
      ...state(),
      availability: 'unavailable',
      unavailable_reason: reason,
      clock: null,
      cycle: null,
    }
    expect(parseReevaluationCycleRpcState(input)).toEqual(input)
    expect(() => parseReevaluationCycleRpcState({ ...input, clock: state().clock })).toThrow()
    expect(() => parseReevaluationCycleRpcState({ ...input, cycle: state().cycle })).toThrow()
  })

  it('accepts not_due with the SQL clock, including an already open cycle', () => {
    const input = { ...state(), availability: 'unavailable', unavailable_reason: 'not_due' }
    expect(parseReevaluationCycleRpcState(input)).toEqual(input)
    expect(() => parseReevaluationCycleRpcState({ ...input, clock: null })).toThrow()
  })

  it('allows disabled only as a local result, never as an RPC response', () => {
    expect(parseReevaluationCycleState(disabled)).toEqual(disabled)
    expect(() => parseReevaluationCycleRpcState(disabled)).toThrow()
    expect(() => parseReevaluationCycleState({ ...disabled, clock: state().clock })).toThrow()
  })

  it.each([
    ['2024-02-20', '2024-03-05'],
    ['2026-03-01', '2026-03-15'],
    ['0001-01-01', '0001-01-15'],
    ['9999-12-17', '9999-12-31'],
  ])('uses fourteen civil days from %s even across leap days and DST', (base, due) => {
    const input = {
      ...state(),
      clock: { base_date: base, due_date: due, timezone: 'America/New_York' },
      cycle: null,
    }
    expect(parseReevaluationCycleRpcState(input)).toEqual(input)
  })

  it.each([
    ['2026-02-29', '2026-03-15'],
    ['2024-02-30', '2024-03-15'],
    ['0000-01-01', '0000-01-15'],
    ['2026-10-01', '2026-10-14'],
    ['2026-10-01', '2026-10-16'],
    ['9999-12-18', '9999-12-31'],
  ])('rejects the invalid civil clock %s / %s', (base, due) => {
    expect(() =>
      parseReevaluationCycleRpcState({
        ...state(),
        clock: { ...state().clock, base_date: base, due_date: due },
        cycle: null,
      }),
    ).toThrow()
  })

  it.each([
    0,
    1,
    9007199254740992,
    '0',
    '-1',
    '+1',
    '01',
    '1e3',
    '1.0',
    '9223372036854775808',
  ])('rejects noncanonical or overflowing revision %s', (revision) => {
    expect(() =>
      parseReevaluationCycleRpcState({ ...state(), cycle: { ...state().cycle, revision } }),
    ).toThrow()
  })

  it.each([
    { id: 'not-an-id' },
    { signup_generation: null },
    { revision: null },
    { status: 'completed' },
    { status: 'invalidated' },
    { kind: 'SAFETY' },
    { base_date: '2026-10-02' },
    { due_date: '2026-10-16' },
    { timezone_at_open: 'UTC' },
    { opened_at: '2026-02-30T03:00:00.123456Z' },
    { opened_at: '2026-10-15T24:00:00.123456Z' },
    { opened_at: '2026-10-15T03:00:00.123Z' },
    { opened_at: '2026-10-15T03:00:00.123456+00:00' },
    { body_fat_percent: 25 },
    { answers: {} },
  ])('rejects incoherent or clinical cycle data %#', (change) => {
    expect(() =>
      parseReevaluationCycleRpcState({ ...state(), cycle: { ...state().cycle, ...change } }),
    ).toThrow()
  })

  it.each([
    { version: 2 },
    { version: '1' },
    { availability: 'unavailable' },
    { unavailable_reason: 'not_due' },
    { clock: null },
    { cycle: undefined },
    { targets: {} },
    { clock: { ...state().clock, timezone: '' } },
    { clock: { ...state().clock, timezone: ' UTC ' } },
    { clock: { ...state().clock, timezone: 'UTC\n' } },
    { clock: { ...state().clock, extra: true } },
  ])('rejects incomplete, incompatible or extended state %#', (change) => {
    expect(() => parseReevaluationCycleRpcState({ ...state(), ...change })).toThrow()
  })

  it('does not reinterpret the PostgreSQL timezone catalogue through a different ICU list', () => {
    const input = state()
    input.clock.timezone = 'Etc/UTC'
    input.cycle.timezone_at_open = 'Etc/UTC'
    expect(parseReevaluationCycleRpcState(input)).toEqual(input)
  })

  it('returns a generic error without leaking malformed clinical values', () => {
    let error: unknown
    try {
      parseReevaluationCycleRpcState({ private_photo_url: 'sensitive-fixture' })
    } catch (caught) {
      error = caught
    }
    expect(error).toMatchObject({
      status: 500,
      code: 'mobile_reevaluation_invalid_response',
      details: undefined,
    })
    expect(String(error)).not.toContain('sensitive-fixture')
  })
})
