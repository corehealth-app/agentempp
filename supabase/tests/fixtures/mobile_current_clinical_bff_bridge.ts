/** Guarded parent owns the single rollback SQL connection; no database/network
 * client in this child. This proves the real BFF port against actual SQL. */
import { createInterface } from 'node:readline'
import type { ServiceClient } from '@mpp/db'
import { onboardingCompletionInputSchema } from '../../../apps/admin/src/lib/mobile-api/contracts'
import {
  assertCurrentSignupObjectiveEligible,
  type CurrentClinicalStateSource,
  captureCurrentClinicalState,
  currentSignupChoices,
  projectCurrentClinicalState,
} from '../../../apps/admin/src/lib/mobile-api/current-clinical-state'
import { createSupabaseCurrentClinicalStateSource } from '../../../apps/admin/src/lib/mobile-api/supabase-current-clinical-state'

if (process.env.PERFORME_CURRENT_CLINICAL_QA !== 'owned-local-rollback' || process.stdin.isTTY)
  throw new Error('Explicit local parent required')
const iterator = createInterface({ input: process.stdin, crlfDelay: Infinity })[
  Symbol.asyncIterator
]()
const send = (packet: unknown) => process.stdout.write(`${JSON.stringify(packet)}\n`)
async function receive() {
  const n = await iterator.next()
  if (n.done) throw new Error('Parent closed')
  return JSON.parse(n.value)
}
function require(value: unknown, message: string): asserts value {
  if (!value) throw new Error(message)
}
try {
  const publicRpc = process.env.PERFORME_CURRENT_TRANSPORT === 'public-rpc'
  const a = 'b3b01000-0000-4000-8000-000000002910',
    b = 'b3b01000-0000-4000-8000-000000002911'
  const privateSource: CurrentClinicalStateSource = {
    capture: async (request) => {
      send({ type: 'capture', request })
      return receive()
    },
  }
  const source = publicRpc
    ? createSupabaseCurrentClinicalStateSource({
        rpc: async (name: string, args: unknown) => {
          send({ type: 'rpc', name, args })
          return receive()
        },
      } as unknown as ServiceClient)
    : privateSource
  const body = {
    locale: 'pt-BR' as const,
    timezone: 'America/Sao_Paulo',
    sex: 'masculino' as const,
    birth_date: '1990-01-01',
    height_cm: 160,
    weight_kg: 90,
    body_fat_percent: 35,
    training_frequency: 4,
  }
  const input = onboardingCompletionInputSchema.parse({
    ...body,
    name: 'Synthetic QA',
    country: 'BR',
    objective: 'manutencao',
    activity_level: 'moderado',
    hunger_level: 'moderada',
    wake_time: '07:00',
    bedtime: '23:00',
    food_organization: 'sim',
    persona: 'focus',
    document_actions: [
      {
        document_key: 'terms',
        version: '1',
        locale: 'pt-BR',
        content_hash: 'a'.repeat(64),
        action: 'acceptance',
      },
    ],
  })
  const current = await captureCurrentClinicalState(source, { userId: a, mode: 'signup', body })
  require(current.health_state.hold_active &&
    current.epoch === null, 'Actual current HOLD/readonly epoch missing')
  require(currentSignupChoices(current).options.find((o) => o.objective === 'manutencao')
    ?.status === 'available', 'HOLD maintenance was not a choice')
  assertCurrentSignupObjectiveEligible(current, a, input)
  let refused = false
  try {
    assertCurrentSignupObjectiveEligible(current, a, { ...input, objective: 'recomposicao' })
  } catch (error) {
    refused = (error as { status?: number }).status === 422
  }
  require(refused, 'Actual current HOLD did not refuse deficit')
  const initial = await captureCurrentClinicalState(source, { userId: b, mode: 'profile' })
  require(initial.safety?.no_plan &&
    projectCurrentClinicalState(initial).targetSource ===
      'unavailable', 'Genuine signup no-plan was not projected')
  send({ type: 'clear', owner: b })
  require((await receive()).cleared === true, 'Actual FULL did not clear')
  const after = await captureCurrentClinicalState(source, { userId: b, mode: 'profile' })
  require(after.safety?.no_plan === false &&
    !after.health_state.hold_active &&
    after.health_state.safety_revision === '2', 'Reader did not refresh current clear')
  require(projectCurrentClinicalState(after).targetSource === 'unavailable' &&
    projectCurrentClinicalState(after)
      .phaseSelectionPending, 'Clear silently assigned the first phase')
  send({
    type: 'done',
    status: publicRpc ? 'PASS_CURRENT_BFF_PUBLIC_RPC_SQL' : 'PASS_CURRENT_BFF_PRIVATE_SQL',
    transport: publicRpc ? 'public-rpc' : 'private',
    cases: 6,
    capture_calls: 3,
    HTTP: false,
    full_BFF_factory: false,
    remote: false,
    Storage: false,
  })
} catch {
  send({ type: 'failure', status: 'FAIL_CURRENT_BFF_PRIVATE_SQL' })
  process.exitCode = 1
}
