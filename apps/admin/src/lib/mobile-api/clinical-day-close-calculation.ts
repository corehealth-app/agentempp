/** Real core calculation from the backend SQL capture. No DB client, host clock,
 * cache, model output or runtime activation. Current and historical dates differ. */
import {
  calcDailyXP,
  computeProgress,
  creditDayToBloco,
  type DailySnapshot,
  deriveMealGap,
  deriveMealPatternFromRows,
  deriveSkippedMealsFromCandidates,
  netBalance,
  resolveClosedDayStatus,
  type UserProgress,
} from '@mpp/core'
import {
  clinicalDateOrdinal,
  clinicalCivilDateSchema as date,
  clinicalTimestampSchema as instant,
} from '@mpp/core/reevaluation-clinical-safety'
import { z } from 'zod'
import {
  clinicalCloseError,
  clinicalCloseRequestSchema,
  clinicalCloseScopeSchema,
  clinicalDayCloseEffectSchema,
  closeHash,
  closePhase,
  closeStatus,
} from './clinical-day-close-contracts'
import {
  clinicalTargetOriginSchema,
  readClinicalCloseConfigRows,
} from './clinical-snapshot-calculation'
import { readCurrentClinicalState } from './current-clinical-state'
import { reevaluationCycleUuidSchema as uuid } from './reevaluation-cycle-contracts'

const finite = z.number().finite()
const timestamp = z.string().datetime({ offset: true })
const historicalTargetOrigin = clinicalTargetOriginSchema.and(
  z.object({
    deficit_level: z.union([z.literal(400), z.literal(500), z.literal(600)]).nullable(),
    origin_kind: z.enum(['calculated', 'confirmed', 'carried']),
  }),
)
const context = z
  .object({
    version: z.literal(1),
    user_id: uuid,
    request: clinicalCloseRequestSchema,
    observed_at: instant,
    context_hash: closeHash,
    facts: z.object({
      owner: z.object({
        id: uuid,
        status: z.literal('active'),
        wpp: z.null(),
        timezone: z.string(),
        locale: z.string(),
      }),
      current: z.unknown(),
      profile: z.object({
        user_id: uuid,
        sex: z.enum(['masculino', 'feminino']).nullable(),
        birth_date: date.nullable(),
        height_cm: finite.nullable(),
        weight_kg: finite.nullable(),
        body_fat_percent: finite.nullable(),
        body_fat_measured_at: instant.nullable(),
        onboarding_completed: z.boolean(),
        onboarding_completed_at: instant.nullable(),
        current_protocol: closePhase.nullable(),
        deficit_level: finite.nullable(),
        activity_level: z.string().nullable(),
        training_frequency: finite.nullable(),
        hunger_level: z.string().nullable(),
      }),
      progress: z
        .object({
          xp_total: finite,
          level: finite,
          current_streak: finite,
          longest_streak: finite,
          blocks_completed: finite,
          deficit_block: finite,
          badges_earned: z.array(z.string()),
          last_active_date: date.nullable(),
        })
        .nullable(),
      snapshot: z
        .object({
          id: uuid,
          user_id: uuid,
          date,
          calories_target: finite.nullable(),
          protein_target: finite.nullable(),
          current_protocol: closePhase.nullable(),
          day_closed: z.boolean(),
          day_status: closeStatus.nullable(),
          gap_reminder_sent_at: timestamp.nullable(),
        })
        .nullable(),
      calendar: z.object({
        today: date,
        date: date.nullable(),
        latest_closable_date: date,
        late: z.boolean().nullable(),
        current_day_end: instant,
        day_start: timestamp.nullable(),
        day_end: timestamp.nullable(),
        pattern_from: date,
        pattern_to: date,
      }),
      day_meals: z.array(
        z.object({
          id: uuid,
          user_id: uuid,
          snapshot_id: uuid.nullable(),
          meal_type: z.string().nullable(),
          kcal: finite.min(0).nullable(),
          protein_g: finite.min(0).nullable(),
          carbs_g: finite.min(0).nullable(),
          fat_g: finite.min(0).nullable(),
          consumed_at: timestamp,
        }),
      ),
      day_workouts: z.array(
        z.object({
          id: uuid,
          user_id: uuid,
          estimated_kcal: finite.min(0).nullable(),
          performed_at: timestamp,
        }),
      ),
      inbound_messages: z.array(z.object({ id: uuid, created_at: timestamp })),
      pattern_snapshots: z.array(z.object({ id: uuid, date })),
      pattern_meals: z.array(z.object({ id: uuid, snapshot_id: uuid, meal_type: z.string() })),
      registered_meals: z.array(z.object({ id: uuid, meal_type: z.string() })),
      skip_events: z.array(
        z.object({
          id: uuid,
          occurred_at: timestamp,
          properties: z.object({ local_date: z.unknown(), meal_type: z.unknown() }),
        }),
      ),
      target_authority: z.object({
        phase_origin: z.object({ kind: z.string(), phase: closePhase.optional() }),
        body_fat_origin: z.unknown(),
        signup_body_fat_origin: z.unknown(),
        body_fat_candidate: z.null(),
        applied_target: historicalTargetOrigin.nullable(),
      }),
      disposition: z.enum([
        'ready',
        'already_closed',
        'not_closable_yet',
        'behind_frontier',
        'earlier_date_changed',
        'inactive',
        'pending_activity',
        'unchanged',
      ]),
    }),
  })
  .strict()

export function prepareClinicalDayClose(raw: unknown, expected: unknown) {
  const scope = clinicalCloseScopeSchema.parse(expected)
  const serialized = JSON.stringify(raw)
  if (!serialized || serialized.length > 2097152) throw clinicalCloseError('unavailable')
  const packet = context.parse(JSON.parse(serialized))
  const { facts, request } = packet
  const { profile, calendar, snapshot } = facts
  const current = readCurrentClinicalState(facts.current, scope.userId)
  const fail = (): never => {
    throw clinicalCloseError('unavailable')
  }
  if (
    packet.user_id !== scope.userId ||
    facts.owner.id !== scope.userId ||
    profile.user_id !== scope.userId ||
    request.from !== scope.from ||
    request.date !== scope.date ||
    request.timezone !== scope.timezone ||
    facts.owner.timezone !== scope.timezone ||
    current.timezone !== scope.timezone ||
    current.observed_at !== packet.observed_at ||
    current.date !== calendar.today ||
    calendar.date !== scope.date ||
    calendar.current_day_end <= packet.observed_at ||
    clinicalDateOrdinal(calendar.pattern_from) !== clinicalDateOrdinal(current.date) - 14 ||
    clinicalDateOrdinal(calendar.pattern_to) !== clinicalDateOrdinal(current.date) - 1 ||
    facts.target_authority.phase_origin.kind !== current.phase_origin.kind ||
    (snapshot && (snapshot.user_id !== scope.userId || snapshot.date !== scope.date)) ||
    profile.onboarding_completed !== current.generation_token?.onboarding_completed ||
    profile.onboarding_completed_at !== current.generation_token?.onboarding_completed_at ||
    (
      [
        'sex',
        'birth_date',
        'height_cm',
        'weight_kg',
        'body_fat_percent',
        'training_frequency',
      ] as const
    ).some((field) => profile[field] !== current.body[field])
  )
    fail()
  if (
    current.phase_origin.kind === 'assigned' &&
    (current.phase_origin.phase !== profile.current_protocol ||
      facts.target_authority.phase_origin.phase !== profile.current_protocol)
  )
    fail()
  const patternIds = new Set(facts.pattern_snapshots.map((s) => s.id))
  if (
    facts.pattern_snapshots.some(
      (s) => s.date < calendar.pattern_from || s.date > calendar.pattern_to,
    ) ||
    facts.pattern_meals.some((m) => !patternIds.has(m.snapshot_id))
  )
    fail()
  if (scope.date !== null) {
    const start = timestamp.parse(calendar.day_start),
      end = timestamp.parse(calendar.day_end)
    if (calendar.late === null) fail()
    const inDay = (at: string) =>
      Date.parse(at) >= Date.parse(start) && Date.parse(at) < Date.parse(end)
    if (
      facts.day_meals.some((m) => m.user_id !== scope.userId || !inDay(m.consumed_at)) ||
      facts.day_workouts.some((w) => w.user_id !== scope.userId || !inDay(w.performed_at)) ||
      facts.inbound_messages.some((m) => !inDay(m.created_at))
    )
      fail()
    const applied = facts.target_authority.applied_target
    if (
      applied &&
      (!snapshot ||
        applied.user_id !== scope.userId ||
        applied.signup_generation !== current.signup_generation ||
        applied.signup_epoch !== current.epoch ||
        applied.snapshot_id !== snapshot.id ||
        applied.date !== scope.date ||
        applied.phase !== snapshot.current_protocol ||
        applied.calories_target !== snapshot.calories_target ||
        applied.recorded_at > packet.observed_at ||
        Date.parse(applied.recorded_at) >= Date.parse(end) ||
        (applied.phase !== 'recomposicao' && applied.deficit_level !== null))
    )
      fail()
  }
  if (facts.disposition !== 'ready') {
    if (scope.date === null)
      return {
        kind: 'skip' as const,
        result: {
          kind: 'unchanged' as const,
          reset: { applied: false as const, reason: facts.disposition },
        },
      }
    if (
      ![
        'already_closed',
        'not_closable_yet',
        'behind_frontier',
        'earlier_date_changed',
        'inactive',
      ].includes(facts.disposition)
    )
      fail()
    return {
      kind: 'skip' as const,
      result: {
        date: scope.date,
        closed: false as const,
        dryRun: false as const,
        late: z.boolean().parse(calendar.late),
        skipReason: facts.disposition,
      },
    }
  }
  if (scope.date === null)
    return {
      kind: 'apply' as const,
      contextHash: packet.context_hash,
      effect: clinicalDayCloseEffectSchema.parse({ version: 1, kind: 'reset' }),
    }
  const { config } = readClinicalCloseConfigRows(current.calculation_config)
  // A later assessment/current formula never rewrites yesterday. Protein is
  // the actual historical value, independent of the calorie source receipt.
  const caloriesTarget = snapshot?.calories_target ?? null
  const proteinTarget = snapshot?.protein_target ?? null
  const historicalPhase = snapshot?.current_protocol ?? null
  const designDeficit =
    historicalPhase === 'recomposicao'
      ? (facts.target_authority.applied_target?.deficit_level ?? null)
      : 0
  const sum = (key: 'kcal' | 'protein_g' | 'carbs_g' | 'fat_g') =>
    facts.day_meals.reduce((n, m) => n + (m[key] ?? 0), 0)
  const calories = sum('kcal'),
    protein = sum('protein_g')
  const exercise = facts.day_workouts.reduce((n, w) => n + (w.estimated_kcal ?? 0), 0)
  const trainingDone = facts.day_workouts.length > 0
  const xp = calcDailyXP(
    {
      trainingDone,
      proteinG: protein,
      caloriesConsumed: calories,
      caloriesTarget: caloriesTarget ?? undefined,
      proteinTarget: proteinTarget ?? undefined,
      mealsLogged: facts.day_meals.length,
      photoLogged: false,
      weightLogged: false,
    },
    config,
  )
  const fields = {
    calories_consumed: Math.round(calories),
    calories_target: caloriesTarget,
    protein_g: Math.round(protein * 10) / 10,
    protein_target: proteinTarget,
    carbs_g: Math.round(sum('carbs_g') * 10) / 10,
    fat_g: Math.round(sum('fat_g') * 10) / 10,
    exercise_calories: Math.round(exercise),
    training_done: trainingDone,
    xp_earned: xp,
    current_protocol: historicalPhase,
  }
  const balance = netBalance(
    fields.calories_consumed,
    caloriesTarget ?? 0,
    fields.exercise_calories,
  )
  const hasActivity = facts.day_meals.length + facts.day_workouts.length > 0
  const pattern = deriveMealPatternFromRows(facts.pattern_snapshots, facts.pattern_meals)
  const skips = deriveSkippedMealsFromCandidates(scope.date, facts.skip_events)
  const gap = deriveMealGap(pattern, facts.registered_meals, skips)
  const dayStatus = resolveClosedDayStatus({
    existingDayStatus: snapshot?.day_status ?? null,
    reminderSent: Boolean(snapshot?.gap_reminder_sent_at),
    hasActivity,
    gapCount: hasActivity ? gap.gap.size : 0,
    skippedCount: hasActivity ? gap.skipped.size : 0,
    fallbackPattern: hasActivity ? pattern.fallbackUsed : false,
  })
  const blockEnabled =
    historicalPhase === 'recomposicao' &&
    designDeficit !== null &&
    current.phase_origin.kind === 'assigned' &&
    current.safety?.no_plan === false
  const policy = { version: 'flow-recomposition-v1' as const, enabled: blockEnabled }
  // Human policy: unknown historical deficit closes records/XP but preserves
  // the existing block. Do not substitute500,0 or today's deficit in its math.
  const blockCredit =
    blockEnabled && designDeficit !== null
      ? creditDayToBloco(
          {
            hasActivity,
            dayStatus,
            caloriesConsumed: calories,
            caloriesTarget,
            dailyBalance: balance,
            designDeficit,
          },
          policy,
        )
      : 0
  const p = facts.progress
  const previous: UserProgress = {
    xpTotal: p?.xp_total ?? 0,
    level: p?.level ?? 1,
    currentStreak: p?.current_streak ?? 0,
    longestStreak: p?.longest_streak ?? 0,
    blocksCompleted: p?.blocks_completed ?? 0,
    deficitBlock: p?.deficit_block ?? 0,
    badgesEarned: p?.badges_earned ?? [],
    lastActiveDate: p?.last_active_date ? new Date(p.last_active_date) : null,
  }
  const day: DailySnapshot = {
    date: new Date(scope.date),
    caloriesConsumed: fields.calories_consumed,
    caloriesTarget,
    proteinG: fields.protein_g,
    proteinTarget: proteinTarget || null,
    exerciseCalories: fields.exercise_calories,
    trainingDone,
    xpEarned: xp,
    dailyBalance: balance,
  }
  const next = computeProgress(day, previous, config, blockCredit, policy)
  const newBadges = next.badgesEarned.filter((badge) => !previous.badgesEarned.includes(badge))
  const telemetry: Array<{
    event: string
    properties: Record<string, string | number | boolean | string[] | null>
  }> = []
  if (blockEnabled && dayStatus === 'incomplete_no_response')
    telemetry.push({
      event: 'bloco7700.skipped_incomplete_day',
      properties: {
        date: scope.date,
        gap: [...gap.gap],
        reason: 'lembrete enviado, paciente não respondeu',
      },
    })
  if (blockEnabled && !hasActivity)
    telemetry.push({
      event: 'bloco7700.skipped_inactive_day',
      properties: { date: scope.date, calories_target: caloriesTarget },
    })
  else if (
    blockEnabled &&
    dayStatus !== 'user_skipped' &&
    caloriesTarget !== null &&
    caloriesTarget > 0 &&
    calories < 0.5 * caloriesTarget
  )
    telemetry.push({
      event: 'bloco7700.skipped_subregistro',
      properties: {
        date: scope.date,
        day_status: dayStatus,
        calories_consumed: Math.round(calories),
        calories_target: caloriesTarget,
        pct: Math.round((calories / caloriesTarget) * 100),
      },
    })
  if (newBadges.length)
    telemetry.push({
      event: 'badge.earned',
      properties: { badges: newBadges, snapshot_date: scope.date },
    })
  if (blockEnabled && next.blocksCompleted > previous.blocksCompleted)
    telemetry.push({
      event: 'bloco7700.block_completed',
      properties: {
        snapshot_date: scope.date,
        previous_count: previous.blocksCompleted,
        new_count: next.blocksCompleted,
        kg_estimate: next.blocksCompleted,
      },
    })
  telemetry.push({
    event: 'daily_closer.completed',
    properties: {
      snapshot_date: scope.date,
      calories_consumed: fields.calories_consumed,
      calories_target: caloriesTarget,
      exercise_calories: fields.exercise_calories,
      training_done: trainingDone,
      day_status: dayStatus,
      xp_earned: xp,
      blocks_completed: next.blocksCompleted,
      blocks_completed_delta: next.blocksCompleted - previous.blocksCompleted,
    },
  })
  return {
    kind: 'apply' as const,
    contextHash: packet.context_hash,
    effect: clinicalDayCloseEffectSchema.parse({
      version: 1,
      kind: 'close',
      fields,
      dayStatus,
      blockCredit,
      dailyBalance: balance,
      gap: hasActivity ? [...gap.gap] : [],
      progress: {
        xpTotal: next.xpTotal,
        level: next.level,
        currentStreak: next.currentStreak,
        longestStreak: next.longestStreak,
        blocksCompleted: next.blocksCompleted,
        deficitBlock: next.deficitBlock,
        badgesEarned: next.badgesEarned,
        lastActiveDate: scope.date,
      },
      telemetry,
    }),
  }
}
