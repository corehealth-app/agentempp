/**
 * The completion of the sign-up (POST /onboarding with `document_actions`)
 * refuses an objective the rule does not allow, so that the rule holds even
 * for a client that never called the eligibility check
 * (docs/CALCULO-MPP.md §10o; docs/mobile/api-v1.md "Objetivo fora da regra na
 * conclusão"). It runs before the SQL function and changes nothing in it.
 *
 * BEFORE THE IDEMPOTENCY KEY IS CLAIMED. The handler calls it ahead of the
 * idempotent execution, so a refusal — and a read that fails — leaves no row
 * in the ledger. Inside it, the released claim would stay there as 'failed'
 * with the hash of the refused request, and the same key sent again with the
 * objective corrected would be a 409 `idempotency_key_conflict`
 * (20260720130537_mobile_api_idempotency.sql compares the hash before the
 * state). The published app sends the same key again after a refusal.
 *
 * FIRST COMPLETION ONLY. `complete_mobile_onboarding_atomic`
 * (supabase/migrations/20260915150739_bodyflow_server_owned_onboarding.sql)
 * writes `current_protocol` in one branch only: the one it takes when the
 * profile's `onboarding_completed_at` IS NULL. With a completion time it takes
 * the other branch — a re-acceptance of documents, or a replay — which writes
 * no column of the profile and only requires the data sent again to equal the
 * data stored (`onboarding_already_completed` otherwise). So the check runs
 * when that column is read as null, and an account that has a completion time
 * is never checked, moved or refused here, whatever objective it holds.
 *
 * `onboarding_completed` (the boolean) is not consulted, because the SQL
 * function does not consult it either: an older account marked completed with
 * no completion time is recorded by the function as a first completion, and
 * is checked as one (declared in the doc, RC E).
 *
 * Only a completion time that was READ exempts a request: a text that is a
 * date and time with an offset, as the database client writes it. Any other
 * text in its place is not a reading (500, below). Without a
 * profile row the SQL function records nothing (`onboarding_user_not_found`);
 * the check runs all the same, and so it answers before every refusal of the
 * SQL function, that one included.
 *
 * The read is outside the SQL function's transaction, and that is safe in the
 * direction that matters: a completion recorded between this read and the
 * function's own only makes the function take the branch that records no
 * objective; the opposite needs a completion time to be emptied, which
 * nothing does.
 *
 * WHAT IS DECIDED. The answer of the eligibility check, by construction: the
 * same function over the same rounding (`decideOnboardingEligibility`) and the
 * same calc-config loader. Only an objective the rule marks 'available' goes
 * on; 'blocked' and 'not_offered' are refused alike. Nothing else of the
 * submission is read (not sleep, not eating).
 *
 * FAIL CLOSED. If the profile cannot be read or the calc config cannot be
 * loaded, nothing is completed and nothing is decided on a default:
 * 500 `data_access_failed`. That is about a read that FAILS. A read that
 * succeeds and brings no `calc.*` row, or a row that holds no number, gives
 * the cut of the code, as in the eligibility check (the loader and the rule do
 * that, not this file; doc §10a).
 *
 * It writes nothing and logs nothing, the submission is not touched, and the
 * refusal carries no value of the request and no reason: the app asks the
 * eligibility check again and shows what it answers.
 */
import { loadCalcConfig } from '@mpp/agent'
import type { CalcConfig } from '@mpp/core'
import { z } from 'zod'
import type { OnboardingCompletionInput } from './contracts'
import { MobileApiError } from './http'
import { decideOnboardingEligibility } from './protocol-eligibility-service'
import type { MobileRouteContext } from './route'

interface QueryResult {
  data: unknown
  error: unknown
}

interface UntypedQuery {
  select(columns: string): UntypedQuery
  eq(column: string, value: unknown): UntypedQuery
  maybeSingle(): PromiseLike<QueryResult>
}

// `onboarding_completed_at` is not in the generated database types.
interface UntypedClient {
  from(table: string): UntypedQuery
}

type GuardContext = Pick<MobileRouteContext, 'auth' | 'supabase'>

// The same reading GET /onboarding makes of this column (supabase-onboarding.ts):
// `Date.parse` alone would take "1" or "2026" for a completion time.
const completionTimeSchema = z.string().datetime({ offset: true })

function isRecord(value: unknown): value is Record<string, unknown> {
  return value !== null && typeof value === 'object' && !Array.isArray(value)
}

function completionLookupFailed(): MobileApiError {
  return new MobileApiError(500, 'data_access_failed', 'Onboarding completion lookup failed')
}

/**
 * Whether the SQL function would record this request as a first completion:
 * true unless a completion time is read from the profile.
 */
async function isFirstCompletion(context: GuardContext): Promise<boolean> {
  let result: QueryResult
  try {
    result = await (context.supabase as unknown as UntypedClient)
      .from('user_profiles')
      .select('onboarding_completed_at')
      .eq('user_id', context.auth.userId)
      .maybeSingle()
  } catch {
    throw completionLookupFailed()
  }
  if (!isRecord(result) || result.error) throw completionLookupFailed()

  // No profile row (see the header).
  if (result.data === null) return true
  if (!isRecord(result.data)) throw completionLookupFailed()

  const completedAt = result.data.onboarding_completed_at
  if (completedAt === null) return true
  if (completionTimeSchema.safeParse(completedAt).success) return false
  // The column did not come back as a time or as null: not a reading.
  throw completionLookupFailed()
}

/**
 * Call BEFORE the idempotency key is claimed and the completion is recorded
 * (see the header). Returns when the request may go on to the SQL function;
 * throws 422 `onboarding_objective_not_eligible` when a first completion asks
 * for an objective the rule does not mark available.
 */
export async function assertOnboardingObjectiveEligible(
  context: GuardContext,
  input: OnboardingCompletionInput,
): Promise<void> {
  if (!(await isFirstCompletion(context))) return

  let config: CalcConfig
  try {
    config = await loadCalcConfig(context.supabase)
  } catch {
    // The cuts come from the config: without it nothing is decided.
    throw new MobileApiError(500, 'data_access_failed', 'Calculation config lookup failed')
  }

  const decided = decideOnboardingEligibility(input, config)
  if (decided.objectives[input.objective].status !== 'available') {
    throw new MobileApiError(
      422,
      'onboarding_objective_not_eligible',
      'The objective is not available for the data sent',
    )
  }
}
