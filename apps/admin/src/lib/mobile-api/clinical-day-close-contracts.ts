/** Dormant backend whole-close contracts. No route or caller-supplied effect. */
import { clinicalCivilDateSchema as civilDate } from '@mpp/core/reevaluation-clinical-safety'
import { z } from 'zod'
import { MobileApiError } from './http'
import { reevaluationCycleUuidSchema as uuid } from './reevaluation-cycle-contracts'

const integer = z.number().int().min(0).max(2147483647)
const amount = z.number().finite().min(0).max(9999.99)
const target = integer.min(1).nullable()
export const closePhase = z.enum(['recomposicao', 'manutencao', 'ganho_massa'])
export const closeStatus = z.enum(['complete', 'user_skipped', 'incomplete_no_response'])
export const closeHash = z.string().regex(/^[a-f0-9]{64}$/)
export const closeZone = z
  .string()
  .min(1)
  .max(256)
  .refine(
    (v) =>
      v === v.trim() &&
      Array.from(v).every((c) => {
        const code = c.charCodeAt(0)
        return code > 31 && code !== 127
      }),
  )
export const clinicalCloseCommandSchema = z
  .object({
    operationKey: uuid,
    from: civilDate,
    date: civilDate.nullable(),
    timezone: closeZone,
  })
  .strict()
  .refine((v) => v.date === null || v.date >= v.from)
export const clinicalCloseScopeSchema = z
  .object({
    userId: uuid,
    from: civilDate,
    date: civilDate.nullable(),
    timezone: closeZone,
  })
  .strict()
  .refine((v) => v.date === null || v.date >= v.from)
export type ClinicalCloseScope = z.infer<typeof clinicalCloseScopeSchema>
export const clinicalCloseRequestSchema = z
  .object({
    kind: z.enum(['close', 'reset']),
    from: civilDate,
    date: civilDate.nullable(),
    timezone: closeZone,
  })
  .strict()
  .refine((v) => (v.kind === 'reset') === (v.date === null))
export const clinicalCloseProgressSchema = z
  .object({
    xpTotal: integer,
    level: integer.min(1),
    currentStreak: integer,
    longestStreak: integer,
    blocksCompleted: integer,
    deficitBlock: integer,
    badgesEarned: z.array(z.string().min(1).max(256)).max(2048),
    lastActiveDate: civilDate,
  })
  .strict()
export const clinicalDayCloseEffectSchema = z.discriminatedUnion('kind', [
  z.object({ version: z.literal(1), kind: z.literal('reset') }).strict(),
  z
    .object({
      version: z.literal(1),
      kind: z.literal('close'),
      dayStatus: closeStatus,
      blockCredit: z.number().finite().min(-2147483648).max(2147483647),
      dailyBalance: z.number().int().min(-2147483648).max(2147483647),
      gap: z.array(z.enum(['cafe', 'almoco', 'lanche', 'jantar', 'ceia'])).max(5),
      fields: z
        .object({
          calories_consumed: integer,
          calories_target: target,
          protein_g: amount,
          protein_target: amount.nullable(),
          carbs_g: amount,
          fat_g: amount,
          exercise_calories: integer,
          training_done: z.boolean(),
          xp_earned: integer,
          current_protocol: closePhase.nullable(),
        })
        .strict(),
      progress: clinicalCloseProgressSchema,
      telemetry: z
        .array(
          z
            .object({
              event: z.enum([
                'daily_closer.completed',
                'badge.earned',
                'bloco7700.block_completed',
                'bloco7700.skipped_incomplete_day',
                'bloco7700.skipped_inactive_day',
                'bloco7700.skipped_subregistro',
              ]),
              properties: z.record(
                z.union([
                  z.string(),
                  z.number().finite(),
                  z.boolean(),
                  z.array(z.string()),
                  z.null(),
                ]),
              ),
            })
            .strict(),
        )
        .min(1)
        .max(6),
    })
    .strict(),
])
export type ClinicalDayCloseEffect = z.infer<typeof clinicalDayCloseEffectSchema>
export const clinicalClosedResultSchema = z
  .object({
    date: civilDate,
    closed: z.literal(true),
    dryRun: z.literal(false),
    late: z.boolean(),
    detail: z
      .object({
        caloriesConsumed: integer,
        exerciseCalories: integer,
        storedCaloriesTarget: target,
        caloriesTarget: target,
        storedProteinTarget: amount.nullable(),
        proteinTarget: amount.nullable(),
        dayStatus: closeStatus,
        xpEarned: integer,
        blockCredit: z.number().finite().min(-2147483648).max(2147483647),
        blockCreditStatus: z.enum(['calculated', 'not_applicable', 'preserved_unknown']).optional(),
        newBadges: z.array(z.string().min(1).max(256)).max(2048),
        progress: clinicalCloseProgressSchema,
      })
      .strict(),
  })
  .strict()
export const clinicalResetResultSchema = z
  .object({
    kind: z.literal('applied'),
    reset: z
      .object({
        applied: z.literal(true),
        previousStreak: integer.min(1),
        lastActiveDate: civilDate,
        gapDays: integer.min(2),
      })
      .strict(),
  })
  .strict()
export function clinicalCloseError(kind: 'changed' | 'busy' | 'unavailable') {
  return new MobileApiError(
    kind === 'unavailable' ? 503 : 409,
    `mobile_clinical_close_${kind}`,
    kind === 'changed'
      ? 'Day closure changed; refresh before trying again'
      : kind === 'busy'
        ? 'Day closure is busy; try again'
        : 'Day closure unavailable',
  )
}
