import { describe, expect, it } from 'vitest'
import { createJourneySocialService, type JourneySocialRPCPort } from './journey-social-service'

const owner = '19500000-0000-4000-9000-000000000001'
const auth = '19500000-0000-4000-8000-000000000001'
const login = '19500000-0000-4000-a000-000000000001'
const member = '19500000-0000-4000-b000-000000000001'
const peer = '19500000-0000-4000-b000-000000000002'
const operation = '19500000-0000-4000-c000-000000000001'
const profile = {
  revision: 1,
  opted_in: true,
  nickname: 'Pessoa A',
  member_id: member,
  moderation: 'active',
}
const join = {
  operation_id: operation,
  expected_revision: 0,
  opted_in: true,
  nickname: 'Pessoa A',
  consent_version: 'journey-social.v1',
}
function harness(data: unknown = profile) {
  const calls: { name: string; args: Record<string, unknown> }[] = []
  let response = data,
    observed = 0
  let failAt = 0
  const port: JourneySocialRPCPort = {
    async rpc(name, args) {
      calls.push({ name, args: structuredClone(args) })
      return { data: response, error: null }
    },
  }
  const service = createJourneySocialService(port, { owner, auth, login }, async () => {
    observed++
    if (observed === failAt) throw Error('original session changed')
  })
  return {
    service,
    calls,
    observed: () => observed,
    respond: (next: unknown) => {
      response = next
    },
    fail: (n: number) => {
      failAt = n
    },
  }
}
const ranking = () => ({
  week_start: '2026-11-02',
  week_end: '2026-11-08',
  through_date: '2026-11-04',
  basis: 'closed_daily_xp',
  entries: [
    { member_id: member, nickname: 'Pessoa A', rank: 1, weekly_xp: 30, is_you: true },
    { member_id: peer, nickname: 'Pessoa B', rank: 1, weekly_xp: 30, is_you: false },
  ],
  next_cursor: null,
})
describe('Journey social original-session service', () => {
  it('uses only the authenticated gateway with fixed original identity and fresh pre/post admission', async () => {
    const f = harness()
    expect(await f.service.profile()).toEqual(profile)
    expect(f.calls).toEqual([
      {
        name: 'journey_social_patient_authenticated',
        args: {
          p_user_id: owner,
          p_auth_user_id: auth,
          p_auth_session_id: login,
          p_action: 'profile.read',
          p_input: {},
        },
      },
    ])
    expect(f.observed()).toBe(2)
  })
  it('does not dispatch after pre-admission fails and never retries a physical RPC', async () => {
    const f = harness()
    f.fail(1)
    await expect(f.service.profile()).rejects.toThrow('original session changed')
    expect(f.calls).toHaveLength(0)
  })
  it('does not publish a successful result after original-session admission changes', async () => {
    const f = harness()
    f.fail(2)
    await expect(f.service.profile()).rejects.toThrow('original session changed')
    expect(f.calls).toHaveLength(1)
  })
  it('refuses ownership and clinical fields before a mutation reaches the gateway', async () => {
    const f = harness()
    await expect(f.service.participate({ ...join, owner_id: owner, calories: 1 })).rejects.toThrow()
    expect(f.calls).toHaveLength(0)
  })
  it('returns the original mutation receipt with newer withdrawn state, never restoring old consent', async () => {
    const receipt = { operation_id: operation, revision: 1, opted_in: true }
    const current = { ...profile, revision: 2, opted_in: false, nickname: null }
    const f = harness({ status: 'replayed', receipt, profile: current })
    const result = await f.service.participate(join)
    expect(result).toEqual({ status: 'replayed', receipt, profile: current })
    expect(Object.isFrozen(result)).toBe(true)
    expect(Object.isFrozen(result.profile)).toBe(true)
    expect(f.calls[0]?.args.p_input).toEqual(join)
  })
  it('refuses a receipt for another operation or an incorrect resulting revision', async () => {
    const f = harness({
      status: 'applied',
      receipt: { operation_id: peer, revision: 1, opted_in: true },
      profile,
    })
    await expect(f.service.participate(join)).rejects.toMatchObject({ status: 503 })
    f.respond({
      status: 'applied',
      receipt: { operation_id: operation, revision: 2, opted_in: true },
      profile: { ...profile, revision: 2 },
    })
    await expect(f.service.participate(join)).rejects.toMatchObject({ status: 503 })
  })
  it('preserves official tied XP and rejects extra public health attributes', async () => {
    const data = ranking(),
      f = harness(data)
    expect(await f.service.ranking()).toEqual(data)
    f.respond({ ...data, entries: data.entries.map((entry) => ({ ...entry, protein_g: 22 })) })
    await expect(f.service.ranking()).rejects.toMatchObject({ status: 503 })
  })
  it.each([
    { week_start: '2026-11-03' },
    { week_end: '2026-11-09' },
    { through_date: '2026-02-31' },
    { basis: 'provisional_xp' },
    { entries: [{ member_id: owner, nickname: 'Pessoa A', rank: 1, weekly_xp: 30, is_you: true }] },
  ])('refuses inconsistent dates, basis or leaked internal identities: %j', async (patch) => {
    const f = harness({ ...ranking(), ...patch })
    await expect(f.service.ranking()).rejects.toMatchObject({ status: 503 })
  })
  it('binds continuation to the original public audience without adding client authority', async () => {
    const cursor = {
      context_hash: 'a'.repeat(64),
      offset: 2,
      viewer_member_id: member,
      week_start: '2026-11-02',
      through_date: '2026-11-04',
    }
    const f = harness({ ...ranking(), entries: [], next_cursor: null })
    expect(await f.service.ranking(cursor, 2)).toMatchObject({ entries: [] })
    expect(f.calls[0]?.args.p_input).toEqual({ limit: 2, cursor })
    await expect(f.service.ranking({ ...cursor, auth_user_id: auth }, 2)).rejects.toThrow()
    expect(f.calls).toHaveLength(1)
  })
  it('uses typed block/report commands and validates literal receipts without granting XP', async () => {
    const f = harness({
      status: 'applied',
      receipt: { operation_id: operation, revision: 2, member_id: peer, blocked: true },
      profile: { ...profile, revision: 2 },
    })
    expect(
      await f.service.block({
        operation_id: operation,
        expected_revision: 1,
        member_id: peer,
        blocked: true,
      }),
    ).toMatchObject({ receipt: { blocked: true } })
    expect(f.calls[0]?.args.p_action).toBe('block.update')
    f.respond({
      status: 'applied',
      receipt: {
        operation_id: operation,
        revision: 2,
        report_id: operation,
        report_status: 'pending',
      },
      profile: { ...profile, revision: 2 },
    })
    expect(
      await f.service.report({
        operation_id: operation,
        expected_revision: 1,
        member_id: peer,
        reason: 'nickname',
      }),
    ).toMatchObject({ receipt: { report_status: 'pending' } })
    expect(f.calls[1]?.args.p_action).toBe('report.create')
  })
  it('preserves an unavailable nickname in the own blocked list and rejects reporter details', async () => {
    const data = { revision: 4, entries: [{ member_id: peer, nickname: null }], next_cursor: null },
      f = harness(data)
    expect(await f.service.blocks()).toEqual(data)
    f.respond({ ...data, entries: [{ ...data.entries[0], auth_user_id: auth }] })
    await expect(f.service.blocks()).rejects.toMatchObject({ status: 503 })
  })
  it.each([
    ['PT401', 401],
    ['PT409', 409],
    ['42501', 403],
    ['22023', 422],
    ['PT404', 404],
    ['unexpected', 503],
  ])('maps %s without exposing SQL details or retrying', async (code, status) => {
    let calls = 0
    const service = createJourneySocialService(
      {
        async rpc() {
          calls++
          return { data: null, error: { code, message: 'sensitive SQL details' } }
        },
      },
      { owner, auth, login },
      async () => {},
    )
    await expect(service.profile()).rejects.toMatchObject({ status })
    expect(calls).toBe(1)
  })
})
