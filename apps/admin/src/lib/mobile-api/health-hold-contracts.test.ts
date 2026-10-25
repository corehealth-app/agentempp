import { describe, expect, it } from 'vitest'
import { parseHealthHoldSnapshot, parseHealthRiskDeclaration } from './health-hold-contracts'
import fixture from './testing/health-hold-fixture.json'

const owner = fixture.absent.user_id
const other = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'
const input = fixture.initial
const parse = (value: unknown) =>
  parseHealthRiskDeclaration(value, owner, input.receipt.operation_key, input.receipt.items)

describe('private health wire authority from actual synthetic PostgreSQL output', () => {
  it('accepts proven absent, current declaration and old receipt with newer state exactly', () => {
    expect(parseHealthHoldSnapshot(fixture.absent, owner)).toEqual(fixture.absent)
    expect(parse(input)).toEqual(input)
    expect(parse(fixture.replay)).toEqual(fixture.replay)
    expect(fixture.replay.receipt).toEqual(fixture.initial.receipt)
    expect(fixture.replay.state.safety_revision).not.toBe(fixture.replay.receipt.safety_revision)
  })

  it.each([
    null,
    {},
    [],
    { ...fixture.absent, availability: 'disabled' },
    { ...fixture.absent, user_id: other },
    { ...fixture.absent, safety_revision: 0 },
    { ...fixture.absent, safety_revision: '00' },
    { ...fixture.absent, safety_revision: '9223372036854775808' },
    { ...fixture.absent, hold_active: true },
    { ...fixture.absent, safety_revision: '1', last_declared_at: input.receipt.declared_at },
    { ...fixture.absent, hide_protein: true },
    { ...fixture.absent, last_declared_at: input.receipt.declared_at },
    { ...input.state, hide_protein: false },
    { ...input.state, declared_no_plan: true },
    { ...input.state, last_declared_at: '2026-02-30T01:00:00.000000Z' },
    { ...input.state, last_declared_at: '2026-10-25T13:00:00Z' },
    {
      ...input.state,
      items: [{ code: 'secret-unknown-risk', declared_at: input.receipt.declared_at }],
    },
    { ...input.state, items: [...input.state.items, ...input.state.items] },
    { ...fixture.later.state, items: [...fixture.later.state.items].reverse() },
    { ...input.state, last_declared_at: '2026-10-01T00:00:00.000000Z' },
  ])('rejects malformed or foreign snapshots without returning no-HOLD %#', (value) => {
    let caught: unknown
    try {
      parseHealthHoldSnapshot(value, owner)
    } catch (error) {
      caught = error
    }
    expect(caught).toMatchObject({
      status: 500,
      code: 'mobile_health_hold_invalid_response',
      details: undefined,
    })
    expect(String(caught)).not.toMatch(/professional_diet|secret-unknown-risk|b3b01000/)
  })

  it.each([
    { ...input, user_id: other },
    { ...input, state: { ...input.state, user_id: other } },
    { ...input, receipt: { ...input.receipt, operation_key: other } },
    { ...input, receipt: { ...input.receipt, items: ['reduced_intake'] } },
    { ...input, receipt: { ...input.receipt, safety_revision: '2' } },
    { ...input, receipt: { ...input.receipt, declared_at: '2026-12-31T00:00:00.000000Z' } },
    {
      ...input,
      state: {
        ...fixture.absent,
        safety_revision: '1',
        last_declared_at: input.receipt.declared_at,
      },
    },
  ])('binds receipts to operation, items, current revision and owner %#', (value) => {
    expect(() => parse(value)).toThrow()
  })

  it('allows old receipt with a newer already-cleared state but not same-revision clearance', () => {
    const cleared = {
      ...fixture.absent,
      safety_revision: '3',
      last_declared_at: fixture.later.receipt.declared_at,
    }
    expect(parse({ ...input, state: cleared }).state).toEqual(cleared)
    expect(() => parse({ ...input, state: { ...cleared, safety_revision: '1' } })).toThrow()
  })
})
