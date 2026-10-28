/** Parent owns one SQL rollback. No network, provider or legacy reader. */
import assert from 'node:assert/strict'
import { createInterface } from 'node:readline'
import type { ServiceClient } from '@mpp/db'
import { readSupabaseCurrentFlowPeriodRows } from '../../../apps/admin/src/lib/mobile-api/supabase-current-flow-period'

if (process.env.PERFORME_FLOW_PERIOD_QA !== 'owned-local-rollback' || process.stdin.isTTY)
  throw new Error('Owned parent required')
const iterator = createInterface({ input: process.stdin, crlfDelay: Infinity })[
  Symbol.asyncIterator
]()
async function request(packet: unknown): Promise<unknown> {
  process.stdout.write(`${JSON.stringify(packet)}\n`)
  const next = await iterator.next()
  assert.equal(next.done, false)
  return JSON.parse(next.value)
}
async function run() {
  const seed = (await request({ type: 'seed' })) as { owner: string; from: string; to: string }
  const client = {
    rpc: (name: string, args: Record<string, unknown>) => request({ type: 'rpc', name, args }),
  } as unknown as ServiceClient
  const first = await readSupabaseCurrentFlowPeriodRows(client, seed.owner, seed.from, seed.to)
  assert.equal(first.length, 2)
  assert.equal(first[0].balance_proven, false)
  assert.equal(first[0].daily_balance, null)
  assert.equal(first[0].calories_consumed, 1300)
  assert.equal(first[1].balance_proven, true)
  assert.equal(first[1].daily_balance, -400)
  assert.equal(first[1].calories_consumed, 1600)
  assert.equal(JSON.stringify(first).includes('context_hash'), false)
  await request({ type: 'tamper' })
  const second = await readSupabaseCurrentFlowPeriodRows(client, seed.owner, seed.from, seed.to)
  assert.equal(second[1].calories_consumed, 1601)
  assert.equal(second[1].balance_proven, false)
  assert.equal(second[1].daily_balance, null)
  const previous = (day: string) =>
    new Date(Date.parse(`${day}T00:00:00Z`) - 86400000).toISOString().slice(0, 10)
  await assert.rejects(
    readSupabaseCurrentFlowPeriodRows(client, seed.owner, previous(seed.from), previous(seed.to)),
    {
      code: 'mobile_current_clinical_changed',
    },
  )
  process.stdout.write(
    `${JSON.stringify({ type: 'done', status: 'PASS_REAL_PERIOD_BFF_SQL', cases: 3 })}\n`,
  )
}
run().then(
  () => process.exit(0),
  (error) => {
    process.stderr.write(`${String(error.stack ?? error)}\n`)
    process.stdout.write('{"type":"failure"}\n')
    process.exit(1)
  },
)
