/** Actual entry runtime, admission adapter and current parser; parent owns SQL.
 * Synthetic Auth only. No deployed HTTP, provider, photos or customer records. */
import assert from 'node:assert/strict'
import { createInterface } from 'node:readline'
import type { ServiceClient } from '@mpp/db'
import type { MobileAuthContext } from '../../../apps/admin/src/lib/mobile-api/auth'
import { createCurrentClinicalFullEntryRuntimeRoutes } from '../../../apps/admin/src/lib/mobile-api/current-clinical-full-runtime'
import {
  projectCurrentClinicalState,
  readCurrentClinicalState,
} from '../../../apps/admin/src/lib/mobile-api/current-clinical-state'
import { MobileApiError } from '../../../apps/admin/src/lib/mobile-api/http'
import { createSupabaseCurrentClinicalStateSource } from '../../../apps/admin/src/lib/mobile-api/supabase-current-clinical-state'

if (process.env.PERFORME_LEGACY_ENTRY_QA !== 'owned-local-rollback' || process.stdin.isTTY)
  throw Error('Owned rollback parent required')
const lines = createInterface({ input: process.stdin, crlfDelay: Infinity })[Symbol.asyncIterator]()
const send = (value: unknown) => process.stdout.write(`${JSON.stringify(value)}\n`)
async function ask(packet: object): Promise<unknown> {
  send(packet)
  const result = await lines.next()
  if (result.done) throw Error('Parent closed')
  return JSON.parse(result.value)
}
const uid = (n: number) => `b3b01000-0000-4000-8000-${String(n).padStart(12, '0')}`
const cases: string[] = [],
  calls: { name: string; owner: unknown }[] = []
const client = {
  rpc(name: string, args: Record<string, unknown>) {
    calls.push({ name, owner: args.p_user_id })
    return ask({ type: 'rpc', name, args })
  },
} as unknown as ServiceClient
try {
  for (let n = 5100; n <= 5104; n++) {
    const owner = uid(n),
      genuine = n === 5104
    const auth = {
      userId: owner,
      authUserId: uid(5199),
      identity: { id: uid(5199) },
      patient: { id: owner, authUserId: uid(5199), status: 'active', locale: 'pt-BR' },
    } as MobileAuthContext
    const runtime = {
      authenticate: async () => auth,
      authorizeEntitlement: async () => {},
      createServiceClient: () => client,
      createRequestId: () => 'owned-legacy-entry',
    }
    const routes = createCurrentClinicalFullEntryRuntimeRoutes(runtime),
      count = calls.length
    const base = 'https://owned.test/api/mobile/v1/reevaluation'
    const post = (body: unknown) =>
      new Request(base + '/start', {
        method: 'POST',
        headers: { 'content-type': 'application/json', 'idempotency-key': uid(n + 100) },
        body: JSON.stringify(body),
      })
    assert.equal(calls.length, count)
    assert.equal((await routes.GET(new Request(base + '?owner=other'))).status, 422)
    assert.equal((await routes.START(post({ reason: null, kind: 'TRANSITION_FULL' }))).status, 422)
    const refused = createCurrentClinicalFullEntryRuntimeRoutes({
      ...runtime,
      authorizeEntitlement: async () => {
        throw new MobileApiError(403, 'forbidden', 'Forbidden')
      },
    })
    assert.equal((await refused.GET(new Request(base))).status, 403)
    assert.equal(calls.length, count)
    cases.push(`constructor_query_body_and_entitlement_have_no_IO_${n}`)
    const response = await routes.GET(new Request(base))
    assert.equal(response.status, 200)
    const entry = (await response.json()).data
    assert.equal(entry.availability, 'available')
    assert.equal(entry.cycle, null)
    if (!genuine) assert.equal(entry.clock.base_date, entry.clock.due_date)
    for (const key of ['generation', 'authority', 'admitted_at', 'profile_completed_marker'])
      assert(!JSON.stringify(entry).includes(key))
    cases.push(`actual_runtime_GET_establishes_only_supported_source_and_honest_calendar_${n}`)
    const started = await routes.START(post({ reason: null }))
    assert.equal(started.status, 200)
    const cycle = (await started.json()).data.cycle
    assert.equal(cycle.kind, genuine ? 'REGULAR' : 'TRANSITION_FULL')
    const state = readCurrentClinicalState(
      await createSupabaseCurrentClinicalStateSource(client).capture({
        userId: owner,
        mode: 'profile',
      }),
      owner,
    )
    assert.equal(state.first_completion, false)
    assert.equal(state.generation_authority?.kind, genuine ? 'signup_receipt' : 'legacy_transition')
    assert.equal(state.generation_token?.onboarding_completed_at === null, !genuine && n % 2 === 1)
    assert.equal(projectCurrentClinicalState(state).phaseSelectionPending, false)
    assert.equal(
      projectCurrentClinicalState(state).targetSource,
      n === 5102 || n === 5103 ? 'official_only' : 'assigned_phase',
    )
    const ownCalls = calls.slice(count)
    assert(ownCalls.every((call) => call.owner === owner))
    assert.equal(
      ownCalls.filter((call) => call.name === 'admit_mobile_clinical_legacy_generation').length,
      genuine ? 0 : 1,
    )
    cases.push(
      `actual_START_keeps_returned_kind_without_repeating_admission_or_inventing_marker_${n}`,
    )
  }
  send({
    type: 'done',
    status: 'PASS_ACTUAL_LEGACY_ENTRY_RUNTIME_SQL',
    cases,
    rpc_calls: calls.length,
    real_Auth: false,
    deployed_HTTP: false,
    PostgREST: false,
    Storage: false,
  })
} catch (error) {
  send({ type: 'failure' })
  console.error(error)
  process.exitCode = 1
} finally {
  await lines.return?.()
}
