/** Pure preparation of server-owned training facts. This module installs no
 * route/storage/registration/energy/XP writer. An atomic persistence port must
 * lock the original scope and persist state + minimal receipt/audit together. */
import { z } from 'zod'
import { conversationJournalInstant } from './conversation-meal-journal-store'
import { MobileApiError } from './http'
import { hashMobileRequest } from './idempotency'

const uuid = z
  .string()
  .uuid()
  .transform((v) => v.toLowerCase())
const hash = z.string().regex(/^[0-9a-f]{64}$/)
const clock = z.string().datetime({ offset: true })
const civil = z
  .string()
  .regex(/^\d{4}-\d{2}-\d{2}$/)
  .refine((v) => {
    const d = new Date(`${v}T00:00:00Z`)
    return Number.isFinite(d.getTime()) && d.toISOString().slice(0, 10) === v
  })
const revision = z.number().int().min(0).max(2147483647)
const scopeSchema = z
  .object({
    owner_id: uuid,
    auth_user_id: uuid,
    epoch: uuid,
    time_zone: z.string().min(1).max(100),
    current_local_date: civil,
    open_local_date: civil.nullable(),
    observed_at: clock,
    recording_allowed: z.boolean(),
  })
  .strict()
const text = (max: number) => z.string().max(max).nullable().optional()
const originalExercise = z
  .object({
    name: z.string().trim().min(1).max(120),
    muscle_group: text(80),
    sets: z.number().int().min(1).max(15).nullable().optional(),
    reps_range: text(80),
    rest_seconds: z.number().int().min(0).max(600).nullable().optional(),
    rpe_target: text(40),
    notes: text(300),
    execution_steps: z.array(z.string().max(300)).max(10).optional(),
    common_mistakes: z.array(z.string().max(300)).max(10).optional(),
  })
  .passthrough()
const originalDay = z
  .object({
    day: z.string().min(1).max(80),
    focus: text(80),
    duration_min: z.number().int().positive().max(1440).nullable().optional(),
    exercises: z.array(originalExercise).max(20),
  })
  .passthrough()
const originalPlan = z
  .object({
    id: uuid,
    user_id: uuid,
    version: z.number().int().min(1).max(2147483647),
    active: z.boolean(),
    generated_at: clock,
    valid_until: clock.nullable(),
    weekly_schedule: z.array(originalDay).min(1).max(7),
  })
  .passthrough()
const definitionExercise = z
  .object({
    index: z.number().int().min(0).max(19),
    fingerprint: hash,
    name: z.string().min(1).max(120),
    muscle_group: z.string().max(80).nullable(),
    recommended_sets: z.number().int().min(1).max(15).nullable(),
    reps_reference: z.string().max(80).nullable(),
    rest_seconds: z.number().int().min(0).max(600).nullable(),
    rpe_target: z.string().max(40).nullable(),
    notes: z.string().max(300).nullable(),
    execution_steps: z.array(z.string().max(300)).max(10),
    common_mistakes: z.array(z.string().max(300)).max(10),
  })
  .strict()
const definitionSchema = z
  .object({
    plan_id: uuid,
    plan_version: z.number().int().positive(),
    plan_hash: hash,
    day_index: z.number().int().min(0).max(6),
    day_label: z.string().min(1).max(80),
    focus: z.string().max(80).nullable(),
    recommended_duration_min: z.number().int().positive().max(1440).nullable(),
    exercises: z.array(definitionExercise).min(1).max(20),
  })
  .strict()
const actualSetSchema = z
  .object({
    id: uuid,
    index: z.number().int().min(0).max(99),
    repetitions: z.number().int().min(0).max(10000).nullable(),
    load_kg: z.number().finite().min(0).max(10000).nullable(),
    duration_seconds: z.number().int().min(0).max(86400).nullable(),
    completed: z.boolean(),
  })
  .strict()
const exerciseStateSchema = z
  .object({
    index: z.number().int().min(0).max(19),
    completed: z.boolean(),
    sets: z.array(actualSetSchema).max(100),
  })
  .strict()
const sessionSchema = z
  .object({
    schema: z.literal('training.execution.v1'),
    id: uuid,
    owner_id: uuid,
    auth_user_id: uuid,
    epoch: uuid,
    time_zone: z.string().min(1).max(100),
    local_date: civil,
    started_at: clock,
    updated_at: clock,
    phase: z.enum(['in_progress', 'abandoned']),
    revision,
    definition: definitionSchema,
    exercises: z.array(exerciseStateSchema).min(1).max(20),
  })
  .strict()
const startSchema = z
  .object({
    schema: z.literal('training.execution.start.v1'),
    session_id: uuid,
    operation_id: uuid,
    expected_epoch: uuid,
    expected_local_date: civil,
    plan_id: uuid,
    plan_hash: hash,
    day_index: z.number().int().min(0).max(6),
  })
  .strict()
const actionSchema = z.discriminatedUnion('kind', [
  z
    .object({
      kind: z.literal('save_set'),
      exercise_index: z.number().int().min(0).max(19),
      set: actualSetSchema,
    })
    .strict(),
  z
    .object({
      kind: z.literal('remove_set'),
      exercise_index: z.number().int().min(0).max(19),
      set_id: uuid,
    })
    .strict(),
  z
    .object({
      kind: z.literal('mark_exercise'),
      exercise_index: z.number().int().min(0).max(19),
      completed: z.boolean(),
    })
    .strict(),
  z.object({ kind: z.literal('abandon') }).strict(),
])
const updateSchema = z
  .object({
    schema: z.literal('training.execution.update.v1'),
    session_id: uuid,
    operation_id: uuid,
    expected_epoch: uuid,
    expected_revision: revision,
    action: actionSchema,
  })
  .strict()
const commandSchema = z.discriminatedUnion('schema', [startSchema, updateSchema])
const receiptSchema = z
  .object({
    schema: z.literal('training.execution.receipt.v1'),
    owner_id: uuid,
    epoch: uuid,
    session_id: uuid,
    operation_id: uuid,
    input_hash: hash,
    before_revision: revision.nullable(),
    after_revision: revision,
    kind: z.enum(['start', 'save_set', 'remove_set', 'mark_exercise', 'abandon']),
    at: clock,
  })
  .strict()
export type TrainingExecutionSession = z.infer<typeof sessionSchema>
export type TrainingExecutionReceipt = z.infer<typeof receiptSchema>
export interface PreparedTrainingExecutionMutation {
  status: 'created' | 'updated' | 'replayed'
  session: TrainingExecutionSession
  receipt: TrainingExecutionReceipt
  audit: null | {
    kind: TrainingExecutionReceipt['kind']
    exercise_index?: number
    before: unknown
    after: unknown
  }
}
function fail(code: string, status = 409): never {
  throw new MobileApiError(
    status,
    code,
    'Training execution could not be reconciled. Refresh its original session.',
  )
}
function parse<T>(schema: z.ZodType<T>, raw: unknown, code: string, status = 503): T {
  try {
    return schema.parse(structuredClone(raw))
  } catch {
    return fail(code, status)
  }
}
function freeze<T>(value: T): T {
  if (value && typeof value === 'object') {
    for (const nested of Object.values(value)) freeze(nested)
    Object.freeze(value)
  }
  return value
}
function bounded(raw: unknown, max: number, code: string, status = 503) {
  try {
    if (Buffer.byteLength(JSON.stringify(raw), 'utf8') > max) fail(code, status)
  } catch {
    return fail(code, status)
  }
}
function localDateInZone(instant: string, timeZone: string, code: string): string {
  try {
    const parts = new Intl.DateTimeFormat('en', {
      timeZone,
      year: 'numeric',
      month: '2-digit',
      day: '2-digit',
    }).formatToParts(new Date(instant))
    const part = (kind: string) => parts.find((p) => p.type === kind)?.value
    conversationJournalInstant(instant)
    return `${part('year')}-${part('month')}-${part('day')}`
  } catch {
    return fail(code, 503)
  }
}
function scope(raw: unknown) {
  const v = parse(scopeSchema, raw, 'training_execution_scope_unavailable')
  if (
    localDateInZone(v.observed_at, v.time_zone, 'training_execution_scope_unavailable') !==
    v.current_local_date
  )
    fail('training_execution_scope_unavailable', 503)
  return v
}
/** The raw plan row and scope must come from existing authenticated server
 * readers. This projection conveys no registration or clinical authority. */
export function projectTrainingExecutionPlan(raw: unknown, rawScope: unknown) {
  const s = scope(rawScope)
  bounded(raw, 262144, 'training_execution_plan_unavailable')
  const p = parse(originalPlan, raw, 'training_execution_plan_unavailable')
  if (p.user_id !== s.owner_id) fail('training_execution_owner_changed')
  if (!s.recording_allowed) fail('training_execution_recording_blocked')
  if (
    !p.active ||
    (p.valid_until !== null &&
      conversationJournalInstant(p.valid_until) <= conversationJournalInstant(s.observed_at))
  )
    fail('training_execution_plan_unavailable')
  if (conversationJournalInstant(p.generated_at) > conversationJournalInstant(s.observed_at))
    fail('training_execution_plan_unavailable', 503)
  const fingerprint = hashMobileRequest(p)
  return freeze({
    schema: 'training.execution-plan.v1' as const,
    owner_id: s.owner_id,
    auth_user_id: s.auth_user_id,
    epoch: s.epoch,
    time_zone: s.time_zone,
    current_local_date: s.current_local_date,
    observed_at: s.observed_at,
    plan_id: p.id,
    plan_version: p.version,
    definition_hash: fingerprint,
    days: p.weekly_schedule.map((day, index) => ({
      index,
      label: day.day,
      focus: day.focus ?? null,
      recommended_duration_min: day.duration_min ?? null,
      startable: day.exercises.length > 0,
      exercises: day.exercises.map((e, ordinal) => ({
        index: ordinal,
        fingerprint: hashMobileRequest({
          plan_id: p.id,
          plan_hash: fingerprint,
          day_index: index,
          exercise_index: ordinal,
          source: e,
        }),
        name: e.name,
        muscle_group: e.muscle_group ?? null,
        recommended_sets: e.sets ?? null,
        reps_reference: e.reps_range ?? null,
        rest_seconds: e.rest_seconds ?? null,
        rpe_target: e.rpe_target ?? null,
        notes: e.notes ?? null,
        execution_steps: e.execution_steps ?? [],
        common_mistakes: e.common_mistakes ?? [],
      })),
    })),
  })
}
function validSession(raw: unknown) {
  bounded(raw, 524288, 'training_execution_state_unavailable')
  const v = parse(sessionSchema, raw, 'training_execution_state_unavailable')
  const sets = v.exercises.flatMap((e) => e.sets)
  if (
    localDateInZone(v.started_at, v.time_zone, 'training_execution_state_unavailable') !==
      v.local_date ||
    v.definition.exercises.length !== v.exercises.length ||
    v.exercises.some(
      (e, i) =>
        e.index !== i ||
        v.definition.exercises[i]?.index !== i ||
        new Set(e.sets.map((s) => s.index)).size !== e.sets.length,
    ) ||
    new Set(sets.map((s) => s.id)).size !== sets.length ||
    conversationJournalInstant(v.updated_at) < conversationJournalInstant(v.started_at)
  )
    fail('training_execution_state_unavailable', 503)
  return v
}
/** Prepare a single CAS transition. prior_receipt is an ORIGINAL server read,
 * never an HTTP field. The adapter must atomically persist the expected revision,
 * next session and unique receipt/audit; otherwise this is not persistence. */
export function prepareTrainingExecutionMutation(raw: unknown): PreparedTrainingExecutionMutation {
  const input = parse(
    z
      .object({
        plan: z.unknown().nullable(),
        scope: z.unknown(),
        session: z.unknown().nullable(),
        command: z.unknown(),
        prior_receipt: z.unknown().nullable(),
      })
      .strict(),
    raw,
    'training_execution_invalid_command',
    422,
  )
  bounded(input.command, 16384, 'training_execution_invalid_command', 422)
  const command = parse(commandSchema, input.command, 'training_execution_invalid_command', 422),
    s = scope(input.scope),
    current = input.session == null ? null : validSession(input.session),
    inputHash = hashMobileRequest(command)
  if (
    current &&
    (current.owner_id !== s.owner_id ||
      current.auth_user_id !== s.auth_user_id ||
      current.id !== command.session_id)
  )
    fail('training_execution_owner_changed')
  if (command.expected_epoch !== s.epoch || (current && current.epoch !== s.epoch))
    fail('training_execution_epoch_changed')
  if (
    current &&
    (current.time_zone !== s.time_zone ||
      current.local_date > s.current_local_date ||
      conversationJournalInstant(current.updated_at) > conversationJournalInstant(s.observed_at))
  )
    fail('training_execution_scope_changed')
  if (input.prior_receipt != null) {
    const r = parse(receiptSchema, input.prior_receipt, 'training_execution_receipt_invalid', 409)
    if (r.input_hash !== inputHash) fail('training_execution_operation_conflict')
    const kind = command.schema === 'training.execution.start.v1' ? 'start' : command.action.kind
    if (
      !current ||
      r.owner_id !== s.owner_id ||
      r.epoch !== s.epoch ||
      r.session_id !== current.id ||
      r.operation_id !== command.operation_id ||
      r.kind !== kind ||
      r.after_revision > current.revision ||
      conversationJournalInstant(r.at) < conversationJournalInstant(current.started_at) ||
      conversationJournalInstant(r.at) > conversationJournalInstant(current.updated_at) ||
      (kind === 'start'
        ? r.before_revision !== null ||
          r.after_revision !== 0 ||
          command.operation_id !== current.id
        : command.schema !== 'training.execution.update.v1' ||
          r.before_revision !== command.expected_revision ||
          r.after_revision !== command.expected_revision + 1)
    )
      fail('training_execution_receipt_invalid')
    return freeze({ status: 'replayed', session: current, receipt: r, audit: null })
  }
  if (command.schema === 'training.execution.start.v1') {
    if (current) fail('training_execution_operation_conflict')
    if (command.operation_id !== command.session_id) fail('training_execution_invalid_command', 422)
    if (command.expected_local_date !== s.current_local_date)
      fail('training_execution_scope_changed')
    if (s.open_local_date !== s.current_local_date) fail('training_execution_day_closed')
    const p = projectTrainingExecutionPlan(input.plan, s)
    if (p.plan_id !== command.plan_id || p.definition_hash !== command.plan_hash)
      fail('training_execution_plan_changed')
    const day = p.days[command.day_index]
    if (!day?.startable) fail('training_execution_day_unavailable')
    const session: TrainingExecutionSession = {
      schema: 'training.execution.v1',
      id: command.session_id,
      owner_id: s.owner_id,
      auth_user_id: s.auth_user_id,
      epoch: s.epoch,
      time_zone: s.time_zone,
      local_date: s.current_local_date,
      started_at: s.observed_at,
      updated_at: s.observed_at,
      phase: 'in_progress',
      revision: 0,
      definition: {
        plan_id: p.plan_id,
        plan_version: p.plan_version,
        plan_hash: p.definition_hash,
        day_index: command.day_index,
        day_label: day.label,
        focus: day.focus,
        recommended_duration_min: day.recommended_duration_min,
        exercises: day.exercises,
      },
      exercises: day.exercises.map((e) => ({ index: e.index, completed: false, sets: [] })),
    }
    const receipt: TrainingExecutionReceipt = {
      schema: 'training.execution.receipt.v1',
      owner_id: s.owner_id,
      epoch: s.epoch,
      session_id: session.id,
      operation_id: command.operation_id,
      input_hash: inputHash,
      before_revision: null,
      after_revision: 0,
      kind: 'start',
      at: s.observed_at,
    }
    return freeze({
      status: 'created',
      session,
      receipt,
      audit: {
        kind: 'start',
        before: null,
        after: { plan_id: p.plan_id, plan_hash: p.definition_hash, day_index: command.day_index },
      },
    })
  }
  if (!current) fail('training_execution_state_unavailable', 409)
  if (current.phase !== 'in_progress') fail('training_execution_terminal')
  if (s.open_local_date !== current.local_date) fail('training_execution_day_closed')
  if (!s.recording_allowed) fail('training_execution_recording_blocked')
  if (command.expected_revision !== current.revision) fail('training_execution_revision_conflict')
  if (current.revision === 2147483647) fail('training_execution_revision_exhausted')
  const next = structuredClone(current),
    a = command.action
  let audit: NonNullable<PreparedTrainingExecutionMutation['audit']>
  if (a.kind === 'abandon') {
    next.phase = 'abandoned'
    audit = { kind: 'abandon', before: 'in_progress', after: 'abandoned' }
  } else {
    const e = next.exercises[a.exercise_index]
    if (!e || e.index !== a.exercise_index) fail('training_execution_invalid_command', 422)
    if (a.kind === 'mark_exercise') {
      audit = { kind: a.kind, exercise_index: e.index, before: e.completed, after: a.completed }
      e.completed = a.completed
    } else if (a.kind === 'save_set') {
      if (
        next.exercises.some(
          (other) => other.index !== e.index && other.sets.some((set) => set.id === a.set.id),
        ) ||
        e.sets.some((set) => set.id !== a.set.id && set.index === a.set.index)
      )
        fail('training_execution_set_conflict')
      const existing = e.sets.find((set) => set.id === a.set.id)
      if (!existing && e.sets.length >= 100) fail('training_execution_set_limit')
      audit = {
        kind: a.kind,
        exercise_index: e.index,
        before: existing ? structuredClone(existing) : null,
        after: structuredClone(a.set),
      }
      e.sets = e.sets.filter((set) => set.id !== a.set.id)
      e.sets.push(structuredClone(a.set))
      e.sets.sort((a, b) => a.index - b.index)
    } else {
      const existing = e.sets.find((set) => set.id === a.set_id)
      if (!existing) fail('training_execution_set_conflict')
      audit = {
        kind: a.kind,
        exercise_index: e.index,
        before: structuredClone(existing),
        after: null,
      }
      e.sets = e.sets.filter((set) => set.id !== a.set_id)
    }
  }
  next.revision++
  next.updated_at = s.observed_at
  const receipt: TrainingExecutionReceipt = {
    schema: 'training.execution.receipt.v1',
    owner_id: s.owner_id,
    epoch: s.epoch,
    session_id: current.id,
    operation_id: command.operation_id,
    input_hash: inputHash,
    before_revision: current.revision,
    after_revision: next.revision,
    kind: a.kind,
    at: s.observed_at,
  }
  return freeze({ status: 'updated', session: next, receipt, audit })
}
