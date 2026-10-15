import { z } from 'zod'
import { workoutProposalInputSchema } from './contracts'

const protocol = z.literal('ui-v1')
const revision = z.number().int().min(0).max(2147483647)

// The client carries intent/version only. SQL receives the original validated
// workout input separately, never these HTTP fields or client-owned authority.
export const workoutRegistrationCreateSchema = workoutProposalInputSchema
  .extend({ workout_protocol: protocol })
  .strict()
export const workoutRegistrationEditSchema = workoutRegistrationCreateSchema
  .extend({ expected_revision: revision })
  .strict()
export const workoutRegistrationSelectionSchema = z
  .object({ workout_protocol: protocol, expected_revision: revision })
  .strict()
