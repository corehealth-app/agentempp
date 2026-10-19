/** Internal request context. It is never part of the onboarding JSON submission. */
export interface SignupStrengthEpochObservation {
  readonly userId: string
  readonly epoch: string
}

export interface SignupStrengthRequestIdentity {
  readonly userId: string
  readonly requestKey: string
  readonly requestHash: string
  readonly expectedEpoch: string
}

export interface CapturedSignupStrengthRequest extends SignupStrengthEpochObservation {
  readonly requestKey: string
  readonly requestHash: string
  readonly admissionId: string
  /** A point-in-time replay check; the keyed writer must also enforce this context. */
  verifyReplay(): Promise<void>
}

export interface SignupStrengthAuthoritySource {
  /** Observation must not bind the key or claim the HTTP ledger before eligibility. */
  observe(input: { readonly userId: string }): Promise<SignupStrengthEpochObservation>
  bind(input: SignupStrengthRequestIdentity): Promise<CapturedSignupStrengthRequest>
}

function invalidAuthority(): Error {
  return new Error('Invalid signup request authority')
}

function nonEmpty(value: unknown): value is string {
  return typeof value === 'string' && value.trim().length > 0
}

/** Copy primitives now: a producer can retain a mutable alias despite readonly types. */
export function snapshotSignupStrengthEpoch(
  observation: SignupStrengthEpochObservation,
  userId: string,
): string {
  const owner = observation?.userId
  const epoch = observation?.epoch
  if (owner !== userId || !nonEmpty(epoch)) throw invalidAuthority()
  return epoch
}

export function snapshotSignupStrengthRequest(
  handle: CapturedSignupStrengthRequest,
  expected: SignupStrengthRequestIdentity,
): CapturedSignupStrengthRequest {
  const userId = handle?.userId
  const requestKey = handle?.requestKey
  const requestHash = handle?.requestHash
  const epoch = handle?.epoch
  const admissionId = handle?.admissionId
  const verifyReplay = handle?.verifyReplay
  if (
    userId !== expected.userId ||
    requestKey !== expected.requestKey ||
    requestHash !== expected.requestHash ||
    epoch !== expected.expectedEpoch ||
    !nonEmpty(admissionId) ||
    typeof verifyReplay !== 'function'
  )
    throw invalidAuthority()
  // Retain the original method/receiver, without exposing its mutable tuple downstream.
  return Object.freeze({
    userId,
    requestKey,
    requestHash,
    epoch,
    admissionId,
    verifyReplay: verifyReplay.bind(handle),
  })
}
