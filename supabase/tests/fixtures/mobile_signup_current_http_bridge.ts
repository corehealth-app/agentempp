/** Real public HTTP factories/adapters/SQL, synthetic owners, rollback parent. */
import assert from 'node:assert/strict'
import { createInterface } from 'node:readline'
import type { ServiceClient } from '@mpp/db'
import { createCurrentSignupEligibilityRoute } from '../../../apps/admin/src/lib/mobile-api/current-signup-eligibility-http.js'
import type { MobileRouteRuntime } from '../../../apps/admin/src/lib/mobile-api/route.js'
import { createSignupHealthAdmissionRoutes } from '../../../apps/admin/src/lib/mobile-api/signup-health-admission-http.js'
import { signupHealthAuth } from '../../../apps/admin/src/lib/mobile-api/testing/signup-health-admission-fixture.js'

if (process.env.PERFORME_SIGNUP_CURRENT_HTTP_QA !== 'owned-local-rollback' || process.stdin.isTTY)
  throw new Error('Owned rollback parent required')
const lines = createInterface({ input: process.stdin, crlfDelay: Infinity })[Symbol.asyncIterator]()
async function parent(packet: object): Promise<unknown> {
  process.stdout.write(`${JSON.stringify(packet)}\n`)
  const next = await lines.next()
  assert(!next.done)
  return JSON.parse(next.value)
}
async function main() {
  const initial = (await parent({ type: 'init' })) as {
    owner: string
    other: string
    command: Record<string, unknown>
    minorBirth: string
  }
  let owner = initial.owner
  const client = {
    rpc: (name: string, args: Record<string, unknown>) => parent({ type: 'rpc', name, args }),
  } as unknown as ServiceClient
  const runtime: MobileRouteRuntime = {
    authenticate: async () => {
      const auth = signupHealthAuth()
      auth.userId = owner
      auth.patient.id = owner
      return auth
    },
    authorizeEntitlement: async () => {},
    createServiceClient: () => client,
    createRequestId: () => 'owned-signup-current-http',
  }
  const health = createSignupHealthAdmissionRoutes({ enabled: true }, runtime)
  const eligibility = createCurrentSignupEligibilityRoute({ enabled: true }, runtime)
  const body = {
    version: 2,
    locale: 'pt-BR',
    timezone: 'America/Sao_Paulo',
    sex: 'masculino',
    birth_date: '1990-01-01',
    height_cm: 180,
    weight_kg: 80,
    body_fat_percent: 24,
    training_frequency: 4,
  }
  const { operation_key: key, ...declaration } = initial.command
  assert.equal(typeof key, 'string')
  const post = (value: unknown, operation = key as string) =>
    new Request('https://owned.test/api/mobile/v1/onboarding/eligibility', {
      method: 'POST',
      headers: { 'content-type': 'application/json', 'idempotency-key': operation },
      body: JSON.stringify(value),
    })
  async function data(response: Response) {
    assert.equal(response.status, 200, `HTTP ${response.status}`)
    return (await response.json()).data
  }
  const ordinary = await data(await eligibility(post(body)))
  assert.equal(ordinary.decision, 'assigned')
  const first = await data(await health.POST(post(declaration)))
  assert.equal(first.state.hold_active, true)
  assert.deepEqual(await data(await health.POST(post(declaration))), first)
  const held = await data(await eligibility(post(body)))
  assert.equal(held.decision, 'choice')
  assert.equal(held.objective, null)
  assert.deepEqual(
    held.options.map((o: { status: string }) => o.status),
    ['blocked', 'blocked', 'available'],
  )
  const noPlan = await data(await eligibility(post({ ...body, birth_date: initial.minorBirth })))
  assert.equal(noPlan.decision, 'no_plan')
  assert.equal(noPlan.objective, null)
  assert.deepEqual(noPlan.options, [])
  owner = initial.other
  const other = await data(await eligibility(post(body)))
  assert.equal(other.decision, 'assigned')
  owner = initial.owner
  await parent({ type: 'reset', owner })
  const oldAck = await data(await health.POST(post(declaration)))
  // Conversation reset is not a clinical clearance. Original ACK and the
  // still-active safety state survive, without any new declaration.
  assert.deepEqual(oldAck, first)
  assert.equal(
    (await health.POST(post(declaration, 'b3b01000-0000-4000-8000-000000005899'))).status,
    409,
  )
  const fresh = await data(await eligibility(post(body)))
  assert.equal(fresh.decision, 'choice')
  for (const output of [ordinary, held, noPlan, other, fresh])
    for (const key of [
      'epoch',
      'user_id',
      'health_state',
      'generation_token',
      'context_hash',
      'calculation_config',
      'targets',
    ])
      assert(!Object.hasOwn(output, key))
  process.stdout.write(
    `${JSON.stringify({ type: 'result', status: 'PASS_PUBLIC_HTTP_LOCAL_SQL', checks: 7 })}\n`,
  )
}
main().catch((error) => {
  process.stderr.write(error instanceof Error ? (error.stack ?? error.message) : String(error))
  process.exitCode = 1
})
