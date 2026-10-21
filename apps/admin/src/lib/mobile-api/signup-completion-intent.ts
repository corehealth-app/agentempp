import { snapshotSignupStrengthEpoch } from './signup-strength-authority'

export interface SignupCompletionIntent {
  readonly userId: string
  readonly preparationId: string
  readonly intentId: string
  readonly requestKey: string
  readonly epoch: string
  readonly issuedAt: string
}

export interface SignupCompletionPreparation {
  readonly userId: string
  readonly preparationId: string
}

export interface SignupCompletionVerification {
  readonly userId: string
  readonly intentId: string
  readonly requestKey: string
}

export interface SignupCompletionIntentSource {
  begin(input: SignupCompletionPreparation): Promise<SignupCompletionIntent>
  resolve(input: SignupCompletionPreparation): Promise<SignupCompletionIntent | null>
  verify(input: SignupCompletionVerification): Promise<SignupCompletionIntent>
}

/** Copy E0 before preparation can await or an injected producer can mutate an alias. */
export function snapshotSignupCompletionEpoch(
  value: SignupCompletionIntent,
  expected: SignupCompletionVerification,
): string {
  if (value?.intentId !== expected.intentId || value?.requestKey !== expected.requestKey)
    throw new Error('Invalid signup completion intent')
  return snapshotSignupStrengthEpoch(value, expected.userId)
}
