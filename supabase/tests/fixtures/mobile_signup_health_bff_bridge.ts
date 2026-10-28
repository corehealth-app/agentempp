/** Explicit owned-local QA process. The guarded parent performs every SQL call
 * in one rollback-only session; this process has no database/network client. */
import { createInterface } from 'node:readline'
import type { ServiceClient } from '@mpp/db'
import type { MobileAuthContext } from '../../../apps/admin/src/lib/mobile-api/auth'
import { onboardingCompletionInputSchema } from '../../../apps/admin/src/lib/mobile-api/contracts'
import { completeOnboarding } from '../../../apps/admin/src/lib/mobile-api/onboarding-service'
import { createSignupHealthAdmissionService } from '../../../apps/admin/src/lib/mobile-api/signup-health-admission'
import { createSupabaseOnboardingRepository } from '../../../apps/admin/src/lib/mobile-api/supabase-onboarding'

if (process.env.PERFORME_SIGNUP_HEALTH_BRIDGE_QA !== 'owned-local-rollback' || process.stdin.isTTY)
  throw new Error('Explicit owned-local parent required')
const lines = createInterface({ input: process.stdin, crlfDelay: Number.POSITIVE_INFINITY })
const iterator = lines[Symbol.asyncIterator]()
const send = (value: unknown) => process.stdout.write(`${JSON.stringify(value)}\n`)
async function receive() {
  const next = await iterator.next()
  if (next.done) throw new Error('Parent closed the bridge')
  return JSON.parse(next.value)
}
function require(value: unknown, label: string): asserts value {
  if (!value) throw new Error(label)
}
try {
  const { owner, command, submission } = await receive()
  require(owner === 'b3b01000-0000-4000-8000-000000002500', 'Unexpected fixture owner')
  const authId = 'b3b01000-0000-4000-8000-000000002501'
  const auth: MobileAuthContext = {
    userId: owner,
    authUserId: authId,
    accessToken: 'synthetic-local-verified',
    identity: {
      id: authId,
      email: 'synthetic@example.invalid',
      emailConfirmedAt: '2026-10-01T00:00:00Z',
    },
    patient: {
      id: owner,
      authUserId: authId,
      email: 'synthetic@example.invalid',
      name: null,
      locale: 'pt-BR',
      timezone: 'America/Sao_Paulo',
      country: 'BR',
      countryConfirmed: true,
      status: 'active',
    },
  }
  let calls = 0
  const service = createSignupHealthAdmissionService({
    enabled: true,
    repository: {
      async admit(userId, value) {
        calls++
        send({ type: 'admit', owner: userId, command: value })
        return receive()
      },
    },
  })
  const first = await service.admit(auth, command)
  require(first.availability === 'available' &&
    first.state.hold_active, 'Actual admission was not presented')
  require(!('epoch' in first.receipt) &&
    !('health_operation_key' in first.receipt), 'Private authority leaked')
  const repeated = await service.admit(auth, command)
  require(JSON.stringify(first) ===
    JSON.stringify(repeated), 'Replay changed original acknowledgement')
  send({ type: 'reset', owner })
  require((await receive()).reset === true, 'Parent did not reset the owned fixture')
  const afterReset = await service.admit(auth, command)
  require(JSON.stringify(first) ===
    JSON.stringify(afterReset), 'Old-epoch replay restored or changed state')
  let rejected = false
  try {
    await service.admit(auth, { ...command, weight_kg: 80 })
  } catch (error) {
    rejected = (error as { status?: number }).status === 422
  }
  require(rejected && calls === 3, 'Ordinary answer reached a repository')
  const completedInput = onboardingCompletionInputSchema.parse(submission)
  const completionRepository = createSupabaseOnboardingRepository({
    async rpc(fn: string, args: { p_user_id: string; p_submission: unknown }) {
      require(fn === 'complete_mobile_onboarding_atomic' &&
        args.p_user_id === owner, 'Unexpected completion transport')
      send({ type: 'complete', owner: args.p_user_id, submission: args.p_submission })
      return receive()
    },
  } as unknown as ServiceClient)
  const completed = await completeOnboarding(completionRepository, owner, completedInput)
  require(completed.objective === null &&
    completed.protocol_welcome === null &&
    completed.clinical_safety?.no_plan ===
      true, 'No-plan completion did not survive actual adapter/service')
  send({
    type: 'done',
    status: 'PASS_INJECTED_BFF_PRIVATE_SQL',
    actual_admissions: 1,
    original_replays: 2,
    ordinary_input_refused_before_sql: true,
    repository_calls: calls,
    HTTP_QA: false,
    private_authority_hidden: true,
    actual_no_plan_completion: true,
    welcome_absent: true,
    completion_calls: 1,
  })
} finally {
  lines.close()
}
