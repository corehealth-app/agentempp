/** Real current SQL source + actual read-model composition/core, in one parent
 * rollback session. Numeric base is a synthetic stale read, not Supabase E2E. */
import { createInterface } from 'node:readline'
import type { ServiceClient } from '@mpp/db'
import type { MobileAuthContext } from '../../../apps/admin/src/lib/mobile-api/auth'
import { createCurrentClinicalReadModel } from '../../../apps/admin/src/lib/mobile-api/current-clinical-read-model'
import { createSupabaseCurrentClinicalStateSource } from '../../../apps/admin/src/lib/mobile-api/supabase-current-clinical-state'
import { buildDailyState } from '../../../packages/core/src/index'

if (
  process.env.PERFORME_CURRENT_CLINICAL_QA !== 'owned-local-rollback' ||
  process.env.PERFORME_CURRENT_TRANSPORT !== 'public-rpc' ||
  process.stdin.isTTY
)
  throw new Error('Explicit owned public transport parent required')
const iterator = createInterface({ input: process.stdin, crlfDelay: Infinity })[
  Symbol.asyncIterator
]()
const send = (value: unknown) => process.stdout.write(`${JSON.stringify(value)}\n`)
async function receive() {
  const n = await iterator.next()
  if (n.done) throw new Error('Parent closed')
  return JSON.parse(n.value)
}
function require(value: unknown): asserts value {
  if (!value) throw new Error('Reader SQL case failed')
}
try {
  const owner = 'b3b01000-0000-4000-8000-000000002911',
    identity = 'b3b01000-0000-4000-8000-000000002912'
  const auth: MobileAuthContext = {
    userId: owner,
    authUserId: identity,
    accessToken: 'synthetic-local',
    identity: { id: identity, email: null, emailConfirmedAt: null },
    patient: {
      id: owner,
      authUserId: identity,
      email: null,
      name: 'Synthetic QA',
      locale: 'pt-BR',
      timezone: 'UTC',
      country: 'BR',
      countryConfirmed: true,
      status: 'active',
    },
  }
  const source = createSupabaseCurrentClinicalStateSource({
    rpc: async (name: string, args: unknown) => {
      send({ type: 'rpc', name, args })
      return receive()
    },
  } as unknown as ServiceClient)
  let numericReads = 0
  const model = createCurrentClinicalReadModel({} as ServiceClient, source, {
    async today(_client, _owner, state) {
      require(_owner === owner)
      numericReads++
      return buildDailyState({
        localDate: state.date,
        generatedAt: state.observed_at,
        protocol: null,
        calculatedTargets: { calories_target: 1900, protein_target: 130 },
        snapshot: {
          caloriesConsumed: 650,
          caloriesTarget: 1900,
          proteinG: 25,
          proteinTarget: 130,
          carbsG: 90,
          fatG: 15,
          exerciseCalories: 100,
          waterConsumedMl: 500,
          protocol: null,
          dayClosed: false,
          dayStatus: null,
          updatedAt: state.observed_at,
        },
        meals: [],
        workouts: [],
        pendingRegistrations: [],
        routineItems: [],
        hydrationTarget: null,
        progress: null,
        mealGap: {
          expected: ['cafe'],
          registered: [],
          skipped: [],
          open: ['cafe'],
          reliable: false,
          activeDays: 0,
        },
      })
    },
    async progress() {
      send({ type: 'clear', owner })
      require((await receive()).cleared === true)
      return null
    },
    async profile() {
      return null
    },
    async plan() {
      return { training: null, nutrition: [] }
    },
    async trends() {
      return { days: 7, daily: [], weights: [] }
    },
  })
  const url = 'https://local.invalid/today?clinical_policy=current_clinical_v1'
  let refused = false
  try {
    await model.today(auth, 'https://local.invalid/today')
  } catch (error) {
    refused = (error as { code?: string }).code === 'clinical_client_update_required'
  }
  require(refused && numericReads === 0)
  const initial = await model.today(auth, url)
  require(
    initial.targets.calories_kcal === null &&
      initial.targets.protein_g === null &&
      initial.protocol === null &&
      initial.consumed.calories_kcal === 650,
  )
  refused = false
  try {
    await model.progress(auth, url)
  } catch (error) {
    refused = (error as { code?: string }).code === 'mobile_current_clinical_changed'
  }
  require(refused)
  const after = await model.today(auth, url)
  require(
    after.targets.calories_kcal === null &&
      after.targets.protein_g === null &&
      after.clinical_policy?.phase_selection_pending === true &&
      after.clinical_policy.target_source === 'unavailable',
  )
  send({
    type: 'done',
    status: 'PASS_CURRENT_READERS_PUBLIC_RPC_SQL',
    cases: 4,
    capture_calls: 7,
    numeric_base: 'synthetic_stale_core_fixture',
    actual_current_SQL: true,
    HTTP: false,
    full_BFF_factory: false,
    remote: false,
    Storage: false,
  })
} catch {
  send({ type: 'failure', status: 'FAIL_CURRENT_READERS_PUBLIC_RPC_SQL' })
  process.exitCode = 1
}
