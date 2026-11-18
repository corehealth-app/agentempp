import { describe, expect, it } from 'vitest'
import { createJourneyModerationService } from './service'

const actor = '19900000-0000-4000-8000-000000000004'
const login = '19900000-0000-4000-a000-000000000004'
const member = '19900000-0000-4000-9000-000000000007'
const report = '19900000-0000-4000-b000-000000000010'
const operation = '19900000-0000-4000-b000-000000000011'
const command = {
  operation_id: operation,
  member_id: member,
  expected_revision: 1,
  action: 'suspend',
}
const receipt = {
  operation_id: operation,
  member_id: member,
  revision: 2,
  previous_moderation: 'active',
  moderation: 'suspended',
}
const profile = {
  revision: 2,
  opted_in: true,
  nickname: 'Pessoa 7',
  member_id: member,
  moderation: 'suspended',
}
const entry = {
  report_id: report,
  reason: 'nickname',
  status: 'pending',
  revision: 1,
  created_at: '2026-11-18T21:00:00.123456+00:00',
  member_id: member,
  nickname: 'Pessoa 7',
  moderation: 'active',
  profile_revision: 1,
}

function fixture(data: unknown, error: unknown = null) {
  const calls: Array<{ name: string; args: Record<string, unknown> }> = []
  let admitted = true
  let after: (() => void) | null = null
  const service = createJourneyModerationService(
    {
      rpc: async (name: string, args: Record<string, unknown>) => {
        calls.push({ name, args })
        after?.()
        return { data, error }
      },
    },
    { actor, login },
    async () => {
      if (!admitted) throw new Error('session changed')
    },
  )
  return {
    service,
    calls,
    revoke: () => {
      admitted = false
    },
    after: (fn: () => void) => {
      after = fn
    },
  }
}

describe('operational moderation gateway service', () => {
  it('binds operator/session outside the command and uses only the authenticated gateway', async () => {
    const f = fixture({ status: 'applied', receipt, profile })
    await expect(f.service.moderate(command)).resolves.toEqual({
      status: 'applied',
      receipt,
      profile,
    })
    expect(f.calls).toEqual([
      {
        name: 'journey_social_operator_authenticated',
        args: {
          p_actor_id: actor,
          p_auth_session_id: login,
          p_action: 'profile.moderate',
          p_input: command,
        },
      },
    ])
  })
  it('denies writes before physical invocation after original-session loss', async () => {
    const f = fixture({ status: 'applied', receipt, profile })
    f.revoke()
    await expect(f.service.moderate(command)).rejects.toThrow('session changed')
    expect(f.calls).toEqual([])
  })
  it('does not publish data if the original operator session changes during the physical call', async () => {
    const f = fixture({ status: 'applied', receipt, profile })
    f.after(f.revoke)
    await expect(f.service.moderate(command)).rejects.toThrow('session changed')
    expect(f.calls).toHaveLength(1)
  })
  it.each([
    { ...command, actor_id: actor },
    { ...command, expected_revision: '1' },
    { ...command, action: 'delete' },
    { ...command, expected_revision: 0 },
    { ...command, operation_id: 'invalid' },
    { ...command, expected_revision: Number.MAX_SAFE_INTEGER },
  ])('rejects untyped/extra authority before a physical write: %j', async (input) => {
    const f = fixture(null)
    await expect(f.service.moderate(input)).rejects.toThrow()
    expect(f.calls).toEqual([])
  })
  it.each([
    { status: 'applied', receipt: { ...receipt, operation_id: report }, profile },
    { status: 'applied', receipt: { ...receipt, moderation: 'active' }, profile },
    { status: 'applied', receipt: { ...receipt, revision: 3 }, profile },
    { status: 'applied', receipt, profile: { ...profile, revision: 3 } },
    { status: 'applied', receipt, profile: { ...profile, member_id: actor } },
    { status: 'applied', receipt, profile: { ...profile, email: 'private@example.invalid' } },
  ])('refuses mismatched receipts/current projections: %j', async (data) => {
    const f = fixture(data)
    await expect(f.service.moderate(command)).rejects.toThrow()
    expect(f.calls).toHaveLength(1)
  })
  it('replay returns the original receipt but preserves withdrawn current consent', async () => {
    const current = { ...profile, revision: 3, opted_in: false, nickname: null }
    const f = fixture({ status: 'replayed', receipt, profile: current })
    await expect(f.service.moderate(command)).resolves.toMatchObject({
      profile: { opted_in: false, nickname: null, revision: 3 },
    })
  })
  it.each([
    'PT401',
    'PT409',
    '42501',
    '22023',
    'PT404',
    'unexpected',
  ])('never retries an uncertain or rejected write (%s)', async (code) => {
    const f = fixture(null, { code })
    await expect(f.service.moderate(command)).rejects.toThrow()
    expect(f.calls).toHaveLength(1)
  })
  it('reads a bounded queue without reporters/health/owner IDs and returns immutable facts', async () => {
    const f = fixture({ entries: [entry], next_cursor: null })
    const result = await f.service.queue({ limit: 20, cursor: null })
    expect(result).toEqual({ entries: [entry], next_cursor: null })
    expect(Object.isFrozen(result.entries[0])).toBe(true)
    expect(f.calls[0]?.args).toMatchObject({
      p_action: 'queue.read',
      p_input: { limit: 20, cursor: null },
    })
  })
  it.each([
    { entries: [{ ...entry, reporter_id: actor }], next_cursor: null },
    { entries: [entry, entry], next_cursor: null },
    { entries: [entry], next_cursor: { created_at: entry.created_at, report_id: operation } },
    { entries: [{ ...entry, member_id: login }], next_cursor: null },
  ])('rejects leaked fields, duplicate reports and inconsistent cursor: %j', async (data) => {
    const f = fixture(data)
    await expect(f.service.queue({ limit: 20, cursor: null })).rejects.toThrow()
  })
  it('compares microsecond queue order without dropping sub-millisecond precision', async () => {
    const second = {
      ...entry,
      report_id: operation,
      created_at: '2026-11-18T21:00:00.123457+00:00',
    }
    const f = fixture({
      entries: [entry, second],
      next_cursor: { created_at: second.created_at, report_id: second.report_id },
    })
    await expect(f.service.queue({ limit: 2, cursor: null })).resolves.toMatchObject({
      entries: [entry, second],
    })
    const reversed = fixture({ entries: [second, entry], next_cursor: null })
    await expect(reversed.service.queue({ limit: 2, cursor: null })).rejects.toThrow()
  })
  it('resolves a report without implicitly changing its profile', async () => {
    const c = {
      operation_id: operation,
      report_id: report,
      expected_revision: 1,
      status: 'dismissed',
    }
    const f = fixture({
      status: 'applied',
      receipt: {
        operation_id: operation,
        report_id: report,
        revision: 2,
        report_status: 'dismissed',
      },
    })
    await expect(f.service.resolveReport(c)).resolves.toMatchObject({
      receipt: { report_status: 'dismissed' },
    })
    expect(f.calls).toHaveLength(1)
    expect(f.calls[0]?.args).toMatchObject({ p_action: 'report.resolve' })
  })
  it.each([
    'applied',
    'fenced',
  ])('explicit response recovery uses only receipt/fence resolution: %s', async (status) => {
    const f = fixture({
      status,
      kind: 'profile',
      operation_id: operation,
      expected_revision: 1,
      receipt: status === 'applied' ? receipt : null,
    })
    await expect(f.service.recover({ kind: 'profile', command })).resolves.toMatchObject({ status })
    expect(f.calls).toHaveLength(1)
    expect(f.calls[0]?.args).toMatchObject({
      p_action: 'operation.resolve',
      p_input: { kind: 'profile', command },
    })
  })
  it('fenced recovery cannot claim a successful receipt', async () => {
    const f = fixture({
      status: 'fenced',
      kind: 'profile',
      operation_id: operation,
      expected_revision: 1,
      receipt,
    })
    await expect(f.service.recover({ kind: 'profile', command })).rejects.toThrow()
  })
})
