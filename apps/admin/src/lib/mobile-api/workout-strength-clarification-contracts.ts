import { z } from 'zod'
import { resourceIdSchema } from './contracts'

export const workoutStrengthUUIDSchema = resourceIdSchema.transform((value) => value.toLowerCase())
export const workoutStrengthAnswerSchema = z
  .object({
    expected_lifecycle_key: workoutStrengthUUIDSchema,
    expected_fact_revision: z.number().int().min(0).max(2147483647),
    question_key: workoutStrengthUUIDSchema,
    answer: z.enum(['yes', 'no']),
  })
  .strict()
export type WorkoutStrengthAnswerBody = z.infer<typeof workoutStrengthAnswerSchema>
