/** Complete private SQL read DTOs. Decoding never grants Auth, source capture,
 * preparation, nutrition, write or retry authority. Opaque SQL tokens stay opaque. */
import { isDeepStrictEqual } from 'node:util'
import { getLocalDateString } from '@mpp/agent'
import { z } from 'zod'
import { conversationJournalBindingSchema } from './conversation-command-candidate-contracts'
import { bindConversationCommand } from './conversation-command-contracts'
import {
  type ConversationMealQuestion,
  type ConversationMealReplyBody,
  parseConversationMealQuestion,
  parseConversationMealReplyBody,
  validateConversationMealReplyQuestion,
} from './conversation-meal-continuation-input'
import { convertConversationMealQuantity } from './conversation-meal-continuation-quantity'
import {
  type ConversationMealDecisionReceipt,
  parseConversationMealDecisionReceipt,
} from './conversation-meal-decision-store'
import { conversationOperationCanonicalJson } from './conversation-meal-edit-contracts'
import {
  buildConversationMealInterpretationSource,
  freezeInterpretation,
  interpretationReferenceSchema,
  mealInterpretationSchema,
  mealInterpretationUnitSchema,
  parseConversationMealInterpretation,
} from './conversation-meal-interpretation-contracts'
import { validateConversationMealInterpretationModel } from './conversation-meal-interpretation-validation'
import { conversationJournalInstant } from './conversation-meal-journal-store'
import {
  conversationWriterClock,
  parseConversationMealStoredSource,
} from './conversation-meal-writer-contracts'
import { MobileApiError } from './http'
import { mobileQuantityDisplay } from './mobile-quantity-display'

const uuid = z
  .string()
  .length(36)
  .regex(/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/u)
const hash = z
  .string()
  .length(64)
  .regex(/^[0-9a-f]{64}$/u)
const n = z.number().finite(),
  index = n.int().min(0).max(29)
const ids = z
  .array(index)
  .max(30)
  .refine((a) => new Set(a).size === a.length)
const clock = conversationWriterClock.refine((s) => !/\.\d{10}/u.test(s))
const text = (max: number) =>
  z
    .string()
    .min(1)
    .max(max)
    .refine(
      (s) =>
        s.trim().length > 0 &&
        !Array.from(s).some((ch) => {
          const c = ch.charCodeAt(0)
          return (c < 32 && ![9, 10, 13].includes(c)) || c === 127
        }),
    )
const mealType = z.enum(['cafe', 'almoco', 'lanche', 'jantar', 'ceia', 'outro'])
const unit = z.enum(['g', 'kg', 'mL', 'L', 'unit', 'scoop', 'caneca'])
const answer = z.discriminatedUnion('kind', [
  z
    .object({
      kind: z.literal('quantity'),
      food_index: index,
      amount: n.positive().max(9999),
      unit,
    })
    .strict(),
  z.object({ kind: z.literal('meal_type'), meal_type: mealType }).strict(),
])
const ref = z
  .object({
    unit: z.enum(['mL', 'unit', 'scoop']),
    grams_per_unit: n.positive(),
    reference_id: text(200),
    estimated: z.literal(true),
  })
  .strict()
const link = z
  .object({ reply_id: uuid, reply_input_hash: hash, question_key: hash, answer })
  .strict()
const links = z.array(link).max(31)
const parentRef = z
  .object({
    command_id: uuid,
    input_hash: hash,
    source_hash: hash,
    attempt_id: uuid,
    result_hash: hash,
    decision_hash: hash,
  })
  .strict()
const childBinding = z
  .object({
    owner_id: uuid,
    command_id: uuid,
    input_hash: hash,
    command_protocol: z.literal('conversation.clarification.v1'),
    kind: z.literal('meal.clarify'),
    epoch: uuid,
    admitted_at: clock,
  })
  .strict()
const identitySchema = z
  .object({
    ownerId: uuid,
    parentCommandId: uuid,
    parentInputHash: hash,
    epoch: uuid,
    replyId: uuid.nullable().optional(),
    replyInputHash: hash.nullable().optional(),
  })
  .strict()
export type ConversationMealContinuationReadIdentity = Readonly<z.infer<typeof identitySchema>>
export function conversationContinuationReadUnavailable(): never {
  throw new MobileApiError(
    503,
    'conversation_continuation_read_unavailable',
    'Linked meal state is unavailable',
  )
}

/** Separate 4MiB private whole-read budget; never broadens the edit/HTTP caps. */
export function detachConversationContinuationReadJson(raw: unknown): unknown {
  const seen = new Set<object>()
  const check = (v: unknown, depth: number): void => {
    if (depth > 64) conversationContinuationReadUnavailable()
    if (v === null || typeof v === 'boolean') return
    if (typeof v === 'string') {
      if (v.length > 4194304) conversationContinuationReadUnavailable()
      for (let i = 0; i < v.length; i++) {
        const c = v.charCodeAt(i)
        if (c === 0) conversationContinuationReadUnavailable()
        if (c >= 0xd800 && c <= 0xdbff) {
          const d = v.charCodeAt(++i)
          if (!(d >= 0xdc00 && d <= 0xdfff)) conversationContinuationReadUnavailable()
        } else if (c >= 0xdc00 && c <= 0xdfff) conversationContinuationReadUnavailable()
      }
      return
    }
    if (typeof v === 'number' && Number.isFinite(v)) return
    if (typeof v !== 'object' || !v || seen.has(v)) conversationContinuationReadUnavailable()
    if (Array.isArray(v)) {
      if (Object.getPrototypeOf(v) !== Array.prototype) conversationContinuationReadUnavailable()
    } else if (Object.getPrototypeOf(v) !== Object.prototype && Object.getPrototypeOf(v) !== null) {
      conversationContinuationReadUnavailable()
    }
    seen.add(v)
    const keys = Reflect.ownKeys(v)
    for (const k of keys) {
      if (Array.isArray(v) && k === 'length') continue
      if (typeof k !== 'string') conversationContinuationReadUnavailable()
      if (Array.isArray(v) && (!/^(0|[1-9][0-9]*)$/u.test(k) || Number(k) >= v.length))
        conversationContinuationReadUnavailable()
      const d = Object.getOwnPropertyDescriptor(v, k)
      if (!d?.enumerable || !('value' in d)) conversationContinuationReadUnavailable()
      check(k, depth + 1)
      check(d.value, depth + 1)
    }
    if (Array.isArray(v) && keys.length !== v.length + 1) conversationContinuationReadUnavailable()
    seen.delete(v)
  }
  check(raw, 0)
  if (Buffer.byteLength(JSON.stringify(raw), 'utf8') > 4194304)
    conversationContinuationReadUnavailable()
  return freezeInterpretation(structuredClone(raw))
}
function exact<T>(schema: z.ZodType<T>, raw: unknown): T {
  const copy = detachConversationContinuationReadJson(raw),
    value = schema.parse(copy)
  if (!isDeepStrictEqual(copy, value)) conversationContinuationReadUnavailable()
  return freezeInterpretation(value)
}
export function parseConversationMealContinuationReadIdentity(
  raw: unknown,
): ConversationMealContinuationReadIdentity {
  try {
    const i = exact(identitySchema, raw)
    if ((i.replyId == null) !== (i.replyInputHash == null))
      conversationContinuationReadUnavailable()
    return i
  } catch {
    return conversationContinuationReadUnavailable()
  }
}
const macros = {
  kcal: n.nonnegative(),
  protein_g: n.nonnegative(),
  carbs_g: n.nonnegative(),
  fat_g: n.nonnegative(),
}
const candidate = z
  .object({
    candidate_id: text(250),
    name: text(160),
    quantity_g: n.positive().max(9999),
    quantity_basis: z.enum(['stated', 'portion_reference', 'visual_estimate']),
    count: n.positive().nullable(),
    unit_label: text(40).nullable(),
    confidence: n.min(0).max(1).nullable(),
    needs_review: z.boolean(),
    review_reason: z
      .enum(['low_confidence', 'estimated_quantity', 'missing_quantity', 'ambiguous'])
      .nullable(),
    quantity_display: ref.optional(),
  })
  .strict()
const materialized = z
  .object({
    schema: z.literal('conversation.meal-materialization.v1'),
    status: z.literal('materialized'),
    input_hash: hash,
    source_hash: hash,
    attempt_id: uuid,
    inputs: z
      .array(
        z
          .object({
            input_index: index,
            calculation_input: z
              .object({ food_name: text(160), quantity_g: n.positive().max(9999) })
              .strict(),
            candidate,
            source_group_index: index,
          })
          .strict(),
      )
      .min(1)
      .max(30),
    source_groups: z
      .array(
        z
          .object({
            group_index: index,
            interpretation_food_indexes: ids.refine((a) => a.length > 0),
            input_indexes: ids.refine((a) => a.length > 0),
            rule: z.enum([
              'literal',
              'mobile_household',
              'milk_whey_cup',
              'milk_whey_total',
              'prepared_dish',
              'visual',
            ]),
            source_positions: z
              .array(
                z
                  .object({
                    food_index: index,
                    unit: mealInterpretationUnitSchema,
                    name: interpretationReferenceSchema.nullable(),
                    quantity: interpretationReferenceSchema.nullable(),
                    unit_ref: interpretationReferenceSchema.nullable(),
                    visual_index: index.nullable(),
                  })
                  .strict(),
              )
              .min(1)
              .max(30),
          })
          .strict(),
      )
      .min(1)
      .max(30),
    nutrition_label: z.null(),
  })
  .strict()
const incomplete = z
  .object({
    status: z.literal('clarification_required'),
    reason: z.literal('missing_quantity'),
    food_indexes: ids.refine((a) => a.length === 1),
  })
  .strict()
const material = z.discriminatedUnion('status', [materialized, incomplete])
const witness = z
  .object({
    reply_id: uuid,
    food_index: index,
    amount: n.positive().max(9999),
    unit,
    quantity_g: n.positive().max(9999),
    quantity_basis: z.enum(['stated', 'portion_reference']),
    quantity_display: ref.nullable(),
    input_indexes: ids,
  })
  .strict()
const item = z
  .object({
    name: text(250).refine((v) => v.replace(/^ +| +$/gu, '') === v),
    food_db_id: n.int().positive().max(2147483647).nullable(),
    nutrition_source: z.enum([
      'taco',
      'canonical_exact',
      'canonical_fuzzy',
      'canonical_composite',
      'canonical_composite_partial',
      'rule_based',
      'user_correction',
      'history',
      'user_kcal',
      'product_label',
      'llm_estimate',
    ]),
    quantity_g: n.positive().max(9999),
    kcal: n.min(0).max(99999),
    protein_g: n.min(0).max(9999),
    carbs_g: n.min(0).max(9999),
    fat_g: n.min(0).max(9999),
    confidence: n.min(0).max(1).nullable(),
    input_indexes: ids.refine((a) => a.length > 0),
    quantity_basis: z.enum(['stated', 'portion_reference', 'visual_estimate']),
    display_qty: n.positive().nullable(),
    display_unit: text(40).nullable(),
  })
  .strict()
const meal = z
  .object({
    meal_type: mealType,
    items: z.array(item).min(1).max(30),
    totals: z.object(macros).strict(),
    preparation_annotations: z
      .array(
        z
          .object({
            schema: z.literal('consumed.preparation.v1'),
            kind: z.literal('default_cooked'),
            input_indexes: ids.refine((a) => a.length > 0),
            food_name: text(250),
            policy: text(128),
            reference_id: text(200),
          })
          .strict(),
      )
      .max(30),
    source_receipts: z.array(z.object({ id: uuid, hash }).strict()).max(64),
  })
  .strict()
const prepBase = {
  schema: z.literal('conversation.meal-continuation-preparation.v1'),
  input_hash: hash,
  source_hash: hash,
  parent_ref: parentRef,
  answer_chain_hash: hash,
  quantity_witnesses: z.array(witness).max(30),
  materialization: material,
}
const preparation = z.discriminatedUnion('status', [
  z.object({ ...prepBase, status: z.literal('ready'), meal }).strict(),
  z
    .object({
      ...prepBase,
      status: z.literal('needs_reply'),
      next_need: z
        .object({ kind: z.enum(['quantity', 'meal_type']), food_index: index.nullable() })
        .strict(),
    })
    .strict(),
])
export type ConversationMealContinuationPreparation = Readonly<z.infer<typeof preparation>>
/** Outbound shape only. This does not prove source freshness, quantities,
 * accepted answers, current Auth or write permission; the SQL writer does. */
export function parseConversationMealContinuationPreparationShape(
  raw: unknown,
): ConversationMealContinuationPreparation {
  try {
    const value = exact(preparation, raw)
    if (Buffer.byteLength(JSON.stringify(value), 'utf8') > 262144)
      conversationContinuationReadUnavailable()
    return value
  } catch {
    return conversationContinuationReadUnavailable()
  }
}
const effect = z
  .object({
    schema: z.literal('conversation.meal-continuation-effect.v1'),
    owner_id: uuid,
    command_id: uuid,
    input_hash: hash,
    parent_command_id: uuid,
    parent_input_hash: hash,
    parent_decision_hash: hash,
    epoch: uuid,
    registration_id: uuid,
    provider_key: z.string(),
    meal_type: mealType,
    local_date: z.string().date(),
    timezone: z.string().min(1),
    consumed_at: clock,
    log_ids: z
      .array(uuid)
      .min(1)
      .max(30)
      .refine((a) => new Set(a).size === a.length),
    effect_version: z.string().regex(/^cmeal1:[a-f0-9]{64}$/u),
  })
  .strict()
const feedbackBinding = z
  .object({
    parentBinding: conversationJournalBindingSchema,
    childBinding,
    parentDecisionHash: hash,
    receipt: effect,
  })
  .strict()
export type ConversationMealContinuationFeedbackBinding = Readonly<z.infer<typeof feedbackBinding>>
/** A closed historical binding, not current Auth, source or mutation authority.
 * The actual feedback RPC independently resolves this child and frozen source. */
export function parseConversationMealContinuationFeedbackBinding(
  raw: unknown,
): ConversationMealContinuationFeedbackBinding {
  const b = exact(feedbackBinding, raw),
    p = b.parentBinding,
    c = b.childBinding,
    e = b.receipt
  if (
    p.owner_id !== c.owner_id ||
    p.epoch !== c.epoch ||
    p.command_id === c.command_id ||
    e.owner_id !== c.owner_id ||
    e.command_id !== c.command_id ||
    e.input_hash !== c.input_hash ||
    e.epoch !== c.epoch ||
    e.parent_command_id !== p.command_id ||
    e.parent_input_hash !== p.input_hash ||
    e.parent_decision_hash !== b.parentDecisionHash ||
    e.provider_key !== `conversation.clarification/${p.owner_id}/${p.command_id}` ||
    conversationJournalInstant(c.admitted_at) < conversationJournalInstant(p.admitted_at) ||
    conversationJournalInstant(e.consumed_at) < conversationJournalInstant(c.admitted_at) ||
    getLocalDateString(e.timezone, new Date(e.consumed_at)) !== e.local_date
  )
    conversationContinuationReadUnavailable()
  return freezeInterpretation(b)
}
const source = z
  .object({
    source_hash: hash,
    captured_at: clock,
    context: z.custom<ReturnType<typeof parseConversationMealStoredSource>['context']>(),
  })
  .strict()
const childContext = z
  .object({
    schema: z.literal('conversation.meal-continuation-source.v1'),
    owner_id: uuid,
    command_id: uuid,
    input_hash: hash,
    epoch: uuid,
    source_input: z.custom<ConversationMealReplyBody>(),
    parent: parentRef,
    answer_chain_hash: hash,
    answer_chain: links,
    authority: z
      .object({
        source_hash: hash,
        context: z.custom<ReturnType<typeof parseConversationMealStoredSource>['context']>(),
      })
      .strict(),
  })
  .strict()
const reply = z
  .object({
    binding: childBinding,
    body: z.custom<ConversationMealReplyBody>(),
    source: source.extend({ context: childContext }).strict(),
    preparation: z
      .object({
        prepared_hash: hash,
        prepared_at: clock,
        preparation,
        next_question: z.custom<ConversationMealQuestion>().nullable(),
      })
      .strict()
      .nullable(),
    receipt: effect.nullable(),
    state: z.enum(['admitted', 'awaiting_reply', 'prepared', 'saved', 'superseded']),
  })
  .strict()
const available = z
  .object({
    action: z.literal('available'),
    parent: z
      .object({
        binding: conversationJournalBindingSchema,
        source,
        semantic: z
          .object({
            interpreter_version: z.literal('conversation.meal-interpreter.v1'),
            attempt_id: uuid,
            result_hash: hash,
            result: mealInterpretationSchema,
          })
          .strict(),
        decision: z.custom<ConversationMealDecisionReceipt>(),
      })
      .strict(),
    head: z
      .object({
        revision: n.int().min(0).max(31),
        question: z.custom<ConversationMealQuestion>().nullable(),
        answers_hash: hash,
        answers: links,
        fulfilled_by: uuid.nullable(),
      })
      .strict(),
    reply: reply.nullable(),
    fulfillment: z
      .object({
        parent_binding: conversationJournalBindingSchema,
        child_binding: childBinding,
        receipt: effect,
      })
      .strict()
      .nullable(),
    observed_at: clock,
  })
  .strict()
const refusal = z
  .object({
    action: z.enum([
      'absent',
      'stale_epoch',
      'input_conflict',
      'ineligible',
      'reply_conflict',
      'event_conflict',
    ]),
  })
  .strict()
type Available = z.infer<typeof available>
type Parent = Available['parent']
type Reply = NonNullable<Available['reply']>
type Chain = z.infer<typeof links>
export type ConversationMealContinuationReadOutcome =
  | Readonly<Available>
  | Readonly<z.infer<typeof refusal>>

function proveLinks(chain: Chain, parent: Parent): void {
  if (
    new Set(chain.map((l) => l.reply_id)).size !== chain.length ||
    new Set(chain.map((l) => l.question_key)).size !== chain.length
  )
    conversationContinuationReadUnavailable()
  const quantities = new Set<number>()
  let typed = false
  const result = parent.semantic.result as ReturnType<typeof parseConversationMealInterpretation>
  const context = parent.source.context as ReturnType<
    typeof parseConversationMealStoredSource
  >['context']
  for (const l of chain) {
    if (l.reply_id === parent.binding.command_id) conversationContinuationReadUnavailable()
    if (l.answer.kind === 'quantity') {
      const f = result.foods[l.answer.food_index]
      if (
        !f ||
        f.index !== l.answer.food_index ||
        f.name === null ||
        f.quantity !== null ||
        f.unit !== null ||
        f.visual_index !== null ||
        quantities.has(f.index)
      )
        conversationContinuationReadUnavailable()
      quantities.add(f.index)
      const sourceText =
        f.name.unit === 'command_text'
          ? context.source_input.source.channel === 'text'
            ? context.source_input.source.text
            : null
          : f.name.unit === 'media_caption'
            ? context.source_evidence.caption
            : context.source_evidence.transcript
      if (typeof sourceText !== 'string') conversationContinuationReadUnavailable()
      const name = sourceText.slice(f.name.start, f.name.end),
        reference = mobileQuantityDisplay(name)
      if (
        !['g', 'kg'].includes(l.answer.unit) &&
        l.answer.unit !== reference?.unit &&
        !(l.answer.unit === 'L' && reference?.unit === 'mL') &&
        !(l.answer.unit === 'caneca' && reference?.reference_id === 'fao-infoods-v2-whole-milk-tb')
      )
        conversationContinuationReadUnavailable()
    } else {
      if (typed || context.source_input.meal_type !== undefined)
        conversationContinuationReadUnavailable()
      typed = true
    }
  }
}
function parentParts(
  p: Parent,
  identity: ConversationMealContinuationReadIdentity,
  observed: string,
) {
  const b = p.binding
  if (
    b.owner_id !== identity.ownerId ||
    b.command_id !== identity.parentCommandId ||
    b.input_hash !== identity.parentInputHash ||
    b.epoch !== identity.epoch
  )
    conversationContinuationReadUnavailable()
  const c = p.source.context as Parameters<typeof bindConversationCommand>[2]
  if (!c || typeof c !== 'object' || Array.isArray(c)) conversationContinuationReadUnavailable()
  const rawContext = p.source.context as {
    source_input: Parameters<typeof bindConversationCommand>[2]
  }
  const command = bindConversationCommand(
    b.owner_id,
    `cmsg1:${b.command_id}`,
    rawContext.source_input,
  )
  const stored = parseConversationMealStoredSource(
    {
      sourceHash: p.source.source_hash,
      capturedAt: p.source.captured_at,
      epoch: b.epoch,
      context: rawContext as unknown as ReturnType<
        typeof parseConversationMealStoredSource
      >['context'],
    },
    command,
  )
  const sourcePacket = buildConversationMealInterpretationSource(command, stored)
  const semantic = parseConversationMealInterpretation(p.semantic.result, {
    ownerId: b.owner_id,
    commandId: b.command_id,
    inputHash: b.input_hash,
    sourceHash: p.source.source_hash,
    attemptId: p.semantic.attempt_id,
  })
  const model = {
    schema: semantic.schema,
    decision: semantic.decision,
    reason: semantic.reason,
    sources: semantic.sources,
    foods: semantic.foods,
  }
  const visualIndexes = semantic.foods.flatMap((f) =>
    f.visual_index === null ? [] : [f.visual_index],
  )
  const visualCount =
    sourcePacket.sources.find((s) => s.unit === 'vision_items')?.visual_items.length ?? 0
  if (
    semantic.decision !== 'reported_meal' ||
    semantic.foods.length < 1 ||
    visualIndexes.length !== visualCount ||
    new Set(visualIndexes).size !== visualCount ||
    !isDeepStrictEqual(model, validateConversationMealInterpretationModel(model, sourcePacket))
  )
    conversationContinuationReadUnavailable()
  const decision = parseConversationMealDecisionReceipt(p.decision, b)
  if (
    !['missing_quantity', 'meal_type_required'].includes(decision.reason) ||
    decision.source_hash !== p.source.source_hash ||
    decision.attempt_id !== p.semantic.attempt_id ||
    decision.semantic_result_hash !== p.semantic.result_hash ||
    p.semantic.interpreter_version !== semantic.interpreter_version ||
    !isDeepStrictEqual(semantic.source_units, sourcePacket.source_units)
  )
    conversationContinuationReadUnavailable()
  if (
    conversationJournalInstant(b.admitted_at) > conversationJournalInstant(p.source.captured_at) ||
    conversationJournalInstant(p.source.captured_at) >
      conversationJournalInstant(decision.sealed_at) ||
    conversationJournalInstant(decision.sealed_at) > conversationJournalInstant(observed)
  )
    conversationContinuationReadUnavailable()
  return { command, stored, semantic, decision, sourcePacket }
}
function proveQuestion(raw: unknown, p: Parent, answers: Chain, expectedRevision: number) {
  const q = parseConversationMealQuestion(raw)
  if (q.revision !== expectedRevision) conversationContinuationReadUnavailable()
  if (q.kind === 'quantity') {
    const semantic = p.semantic.result as ReturnType<typeof parseConversationMealInterpretation>
    const f = semantic.foods[q.food_index]
    const c = p.source.context as ReturnType<typeof parseConversationMealStoredSource>['context']
    if (
      !f ||
      f.name === null ||
      f.quantity !== null ||
      f.unit !== null ||
      f.visual_index !== null ||
      answers.some((l) => l.answer.kind === 'quantity' && l.answer.food_index === q.food_index)
    )
      conversationContinuationReadUnavailable()
    const s =
      f.name.unit === 'command_text'
        ? c.source_input.source.channel === 'text'
          ? c.source_input.source.text
          : null
        : f.name.unit === 'media_caption'
          ? c.source_evidence.caption
          : c.source_evidence.transcript
    if (typeof s !== 'string' || s.slice(f.name.start, f.name.end) !== q.food_name)
      conversationContinuationReadUnavailable()
  } else {
    const c = p.source.context as ReturnType<typeof parseConversationMealStoredSource>['context']
    if (
      c.source_input.meal_type !== undefined ||
      answers.some((l) => l.answer.kind === 'meal_type')
    )
      conversationContinuationReadUnavailable()
  }
  return q
}

function proveMaterial(m: z.infer<typeof material>, p: Parent): void {
  if (m.status !== 'materialized') return
  if (
    m.input_hash !== p.binding.input_hash ||
    m.source_hash !== p.source.source_hash ||
    m.attempt_id !== p.semantic.attempt_id
  )
    conversationContinuationReadUnavailable()
  const semantics = p.semantic.result as ReturnType<typeof parseConversationMealInterpretation>
  const covered = new Set<number>(),
    inputs = new Set<number>()
  for (const [i, x] of m.inputs.entries())
    if (
      x.input_index !== i ||
      x.candidate.name !== x.calculation_input.food_name ||
      x.candidate.quantity_g !== x.calculation_input.quantity_g ||
      x.source_group_index >= m.source_groups.length
    )
      conversationContinuationReadUnavailable()
  for (const [i, g] of m.source_groups.entries()) {
    if (g.group_index !== i || g.source_positions.length !== g.interpretation_food_indexes.length)
      conversationContinuationReadUnavailable()
    for (const pos of g.source_positions) {
      const f = semantics.foods[pos.food_index]
      if (
        !f ||
        covered.has(f.index) ||
        !g.interpretation_food_indexes.includes(f.index) ||
        !isDeepStrictEqual(pos.name, f.name) ||
        !isDeepStrictEqual(pos.quantity, f.quantity) ||
        !isDeepStrictEqual(pos.unit_ref, f.unit) ||
        pos.visual_index !== f.visual_index ||
        pos.unit !== (f.name?.unit ?? (f.visual_index !== null ? 'vision_items' : f.quantity?.unit))
      )
        conversationContinuationReadUnavailable()
      covered.add(f.index)
    }
    for (const j of g.input_indexes) {
      if (inputs.has(j) || m.inputs[j]?.source_group_index !== i)
        conversationContinuationReadUnavailable()
      inputs.add(j)
    }
  }
  if (covered.size !== semantics.foods.length || inputs.size !== m.inputs.length)
    conversationContinuationReadUnavailable()
}
// Qualification only: same exact decimal comparisons as the existing resolved
// meal reader; never derive or replace submitted nutrition values.
const decimalScale = 10n ** 330n
function decimal(value: number): bigint {
  const [whole = '0', fraction = ''] = conversationOperationCanonicalJson(value).split('.')
  return BigInt(whole + fraction) * 10n ** BigInt(330 - fraction.length)
}
function proveEffect(
  e: z.infer<typeof effect>,
  b: z.infer<typeof childBinding>,
  p: Parent,
  observed: string,
) {
  const d = p.decision as ReturnType<typeof parseConversationMealDecisionReceipt>
  const context = p.source.context
  if (
    e.owner_id !== b.owner_id ||
    e.command_id !== b.command_id ||
    e.input_hash !== b.input_hash ||
    e.epoch !== b.epoch ||
    e.parent_command_id !== p.binding.command_id ||
    e.parent_input_hash !== p.binding.input_hash ||
    e.parent_decision_hash !== d.decision_hash ||
    e.timezone !== context.owner.timezone ||
    e.local_date !== context.day.date ||
    e.provider_key !== `conversation.clarification/${b.owner_id}/${p.binding.command_id}` ||
    getLocalDateString(e.timezone, new Date(e.consumed_at)) !== e.local_date ||
    conversationJournalInstant(e.consumed_at) < conversationJournalInstant(b.admitted_at) ||
    conversationJournalInstant(e.consumed_at) > conversationJournalInstant(observed)
  )
    conversationContinuationReadUnavailable()
}
function proveReply(
  r: Reply,
  v: Available,
  identity: ConversationMealContinuationReadIdentity,
  parts: ReturnType<typeof parentParts>,
) {
  const b = r.binding,
    p = v.parent,
    c = r.source.context,
    body = parseConversationMealReplyBody(r.body),
    head = v.head
  if (
    b.owner_id !== identity.ownerId ||
    b.command_id !== identity.replyId ||
    b.input_hash !== identity.replyInputHash ||
    b.epoch !== identity.epoch ||
    b.command_id === p.binding.command_id ||
    c.owner_id !== b.owner_id ||
    c.command_id !== b.command_id ||
    c.input_hash !== b.input_hash ||
    c.epoch !== b.epoch ||
    !isDeepStrictEqual(c.source_input, body) ||
    !isDeepStrictEqual(c.parent, {
      command_id: p.binding.command_id,
      input_hash: p.binding.input_hash,
      source_hash: p.source.source_hash,
      attempt_id: p.semantic.attempt_id,
      result_hash: p.semantic.result_hash,
      decision_hash: parts.decision.decision_hash,
    }) ||
    conversationJournalInstant(b.admitted_at) <
      conversationJournalInstant(parts.decision.sealed_at) ||
    conversationJournalInstant(r.source.captured_at) < conversationJournalInstant(b.admitted_at) ||
    conversationJournalInstant(r.source.captured_at) > conversationJournalInstant(v.observed_at)
  )
    conversationContinuationReadUnavailable()
  const authority = parseConversationMealStoredSource(
    {
      sourceHash: c.authority.source_hash,
      capturedAt: r.source.captured_at,
      epoch: b.epoch,
      context: c.authority.context,
    },
    parts.command,
  )
  for (const key of ['source_input', 'source_units', 'source_evidence', 'media', 'owner'] as const)
    if (!isDeepStrictEqual(authority.context[key], parts.stored.context[key]))
      conversationContinuationReadUnavailable()
  if (
    authority.context.day.date !== parts.stored.context.day.date ||
    c.answer_chain.length !== body.expected_revision + 1 ||
    head.revision < body.expected_revision
  )
    conversationContinuationReadUnavailable()
  if (head.revision === body.expected_revision) {
    if (head.question === null) conversationContinuationReadUnavailable()
    validateConversationMealReplyQuestion(body, head.question)
  }
  proveLinks(c.answer_chain, p)
  const last = c.answer_chain.at(-1)
  if (
    !last ||
    !isDeepStrictEqual(last, {
      reply_id: b.command_id,
      reply_input_hash: b.input_hash,
      question_key: body.question_key,
      answer: body.answer,
    }) ||
    !isDeepStrictEqual(c.answer_chain.slice(0, -1), head.answers.slice(0, body.expected_revision))
  )
    conversationContinuationReadUnavailable()
  if (isDeepStrictEqual(c.answer_chain, head.answers) && c.answer_chain_hash !== head.answers_hash)
    conversationContinuationReadUnavailable()
  const stored = r.preparation
  if (stored) {
    const prep = stored.preparation
    if (
      conversationJournalInstant(stored.prepared_at) <
        conversationJournalInstant(r.source.captured_at) ||
      conversationJournalInstant(stored.prepared_at) > conversationJournalInstant(v.observed_at) ||
      Buffer.byteLength(JSON.stringify(prep), 'utf8') > 262144 ||
      prep.input_hash !== b.input_hash ||
      prep.source_hash !== r.source.source_hash ||
      !isDeepStrictEqual(prep.parent_ref, c.parent) ||
      prep.answer_chain_hash !== c.answer_chain_hash
    )
      conversationContinuationReadUnavailable()
    proveMaterial(prep.materialization, p)
    const quantities = c.answer_chain.filter((l) => l.answer.kind === 'quantity')
    if (
      prep.quantity_witnesses.length !== quantities.length ||
      new Set(prep.quantity_witnesses.map((w) => w.reply_id)).size !== quantities.length
    )
      conversationContinuationReadUnavailable()
    for (const w of prep.quantity_witnesses) {
      const l = quantities.find((l) => l.reply_id === w.reply_id)
      if (
        !l ||
        l.answer.kind !== 'quantity' ||
        w.food_index !== l.answer.food_index ||
        w.amount !== l.answer.amount ||
        w.unit !== l.answer.unit ||
        w.quantity_basis !== (w.unit === 'g' || w.unit === 'kg' ? 'stated' : 'portion_reference')
      )
        conversationContinuationReadUnavailable()
      const f = parts.semantic.foods[w.food_index],
        name = f?.name
      if (!name) conversationContinuationReadUnavailable()
      const s = parts.sourcePacket.sources.find((s) => s.unit === name.unit)?.text
      if (typeof s !== 'string') conversationContinuationReadUnavailable()
      const converted = convertConversationMealQuantity(
        s.slice(name.start, name.end),
        l.answer.amount,
        l.answer.unit,
      )
      if (
        w.quantity_g !== converted.quantity_g ||
        w.quantity_basis !== converted.quantity_basis ||
        !isDeepStrictEqual(w.quantity_display, converted.quantity_display)
      )
        conversationContinuationReadUnavailable()
      if (prep.materialization.status === 'materialized') {
        if (
          !w.input_indexes.length ||
          w.input_indexes.some(
            (i) =>
              prep.materialization.status !== 'materialized' ||
              prep.materialization.inputs[i]?.calculation_input.quantity_g !== w.quantity_g ||
              !prep.materialization.source_groups.some(
                (g) =>
                  g.interpretation_food_indexes.includes(w.food_index) &&
                  g.input_indexes.includes(i),
              ),
          )
        )
          conversationContinuationReadUnavailable()
      } else if (w.input_indexes.length) conversationContinuationReadUnavailable()
    }
    if (prep.status === 'needs_reply') {
      if (stored.next_question === null) conversationContinuationReadUnavailable()
      const next = proveQuestion(
        stored.next_question,
        p,
        c.answer_chain,
        body.expected_revision + 1,
      )
      if (
        next.kind !== prep.next_need.kind ||
        next.food_index !== prep.next_need.food_index ||
        (next.kind === 'meal_type' && prep.materialization.status !== 'materialized') ||
        (prep.materialization.status === 'clarification_required' &&
          (next.kind !== 'quantity' ||
            !isDeepStrictEqual(prep.materialization.food_indexes, [next.food_index])))
      )
        conversationContinuationReadUnavailable()
      if (
        head.revision === next.revision &&
        (!isDeepStrictEqual(head.question, next) ||
          !isDeepStrictEqual(head.answers, c.answer_chain) ||
          head.answers_hash !== c.answer_chain_hash)
      )
        conversationContinuationReadUnavailable()
    } else {
      if (stored.next_question !== null || prep.materialization.status !== 'materialized')
        conversationContinuationReadUnavailable()
      const typed = c.answer_chain.find((l) => l.answer.kind === 'meal_type')?.answer
      if (
        (typed?.kind === 'meal_type' && typed.meal_type !== prep.meal.meal_type) ||
        (parts.command.command.meal_type !== undefined &&
          parts.command.command.meal_type !== prep.meal.meal_type)
      )
        conversationContinuationReadUnavailable()
      const covered = new Set<number>(),
        names = new Set<string>()
      const inputCount = prep.materialization.inputs.length
      for (const i of prep.meal.items) {
        if (
          names.has(i.name) ||
          i.input_indexes.some((j) => j >= inputCount) ||
          (['canonical_exact', 'canonical_fuzzy', 'history'].includes(i.nutrition_source) &&
            i.food_db_id === null) ||
          decimal(i.kcal) > (decimal(i.quantity_g) * 95n) / 10n + 5n * decimalScale ||
          decimal(i.protein_g) + decimal(i.carbs_g) + decimal(i.fat_g) >
            (decimal(i.quantity_g) * 11n) / 10n + 5n * decimalScale
        )
          conversationContinuationReadUnavailable()
        names.add(i.name)
        for (const j of i.input_indexes) covered.add(j)
      }
      if (
        covered.size !== inputCount ||
        new Set(prep.meal.source_receipts.map((s) => s.id)).size !==
          prep.meal.source_receipts.length
      )
        conversationContinuationReadUnavailable()
      for (const a of prep.meal.preparation_annotations)
        if (
          !prep.meal.items.some(
            (i) =>
              i.name === a.food_name && a.input_indexes.every((j) => i.input_indexes.includes(j)),
          )
        )
          conversationContinuationReadUnavailable()
      for (const field of ['kcal', 'protein_g', 'carbs_g', 'fat_g'] as const) {
        const total = decimal(prep.meal.totals[field])
        const difference = total - prep.meal.items.reduce((sum, i) => sum + decimal(i[field]), 0n)
        if (
          total % (decimalScale / 10n) !== 0n ||
          (difference < 0n ? -difference : difference) > (50000001n * decimalScale) / 1000000000n
        )
          conversationContinuationReadUnavailable()
      }
    }
  }
  const expectedState = r.receipt
    ? 'saved'
    : head.fulfilled_by !== null
      ? 'superseded'
      : stored?.preparation.status === 'needs_reply'
        ? 'awaiting_reply'
        : head.revision > body.expected_revision
          ? 'superseded'
          : stored
            ? 'prepared'
            : 'admitted'
  if (r.state !== expectedState) conversationContinuationReadUnavailable()
  if (r.receipt) {
    if (
      !stored ||
      stored.preparation.status !== 'ready' ||
      head.fulfilled_by !== b.command_id ||
      !v.fulfillment ||
      !isDeepStrictEqual(v.fulfillment.child_binding, b) ||
      !isDeepStrictEqual(v.fulfillment.receipt, r.receipt) ||
      r.receipt.meal_type !== stored.preparation.meal.meal_type ||
      r.receipt.log_ids.length !== stored.preparation.meal.items.length ||
      conversationJournalInstant(r.receipt.consumed_at) <
        conversationJournalInstant(stored.prepared_at)
    )
      conversationContinuationReadUnavailable()
    proveEffect(r.receipt, b, p, v.observed_at)
  }
}

export function parseConversationMealContinuationRead(
  raw: unknown,
  identity: ConversationMealContinuationReadIdentity,
): ConversationMealContinuationReadOutcome {
  try {
    return decodeConversationMealContinuationRead(
      raw,
      parseConversationMealContinuationReadIdentity(identity),
    )
  } catch {
    return conversationContinuationReadUnavailable()
  }
}
function decodeConversationMealContinuationRead(
  raw: unknown,
  identity: ConversationMealContinuationReadIdentity,
): ConversationMealContinuationReadOutcome {
  const detached = detachConversationContinuationReadJson(raw),
    r = refusal.safeParse(detached)
  if (r.success) return exact(refusal, detached)
  const v = exact(available, detached),
    parts = parentParts(v.parent, identity, v.observed_at),
    h = v.head
  proveLinks(h.answers, v.parent)
  if (h.revision !== h.answers.length || (h.fulfilled_by === null) !== (v.fulfillment === null))
    conversationContinuationReadUnavailable()
  if (h.fulfilled_by === null) {
    if (h.question === null) conversationContinuationReadUnavailable()
    const q = proveQuestion(h.question, v.parent, h.answers, h.revision)
    if (
      h.revision === 0 &&
      ((parts.decision.reason === 'missing_quantity' &&
        (q.kind !== 'quantity' ||
          !isDeepStrictEqual(parts.decision.food_indexes, [q.food_index]))) ||
        (parts.decision.reason === 'meal_type_required' && q.kind !== 'meal_type'))
    )
      conversationContinuationReadUnavailable()
  } else if (h.question !== null || h.revision === 0) conversationContinuationReadUnavailable()
  if ((identity.replyId == null) !== (v.reply === null)) conversationContinuationReadUnavailable()
  if (v.reply) proveReply(v.reply, v, identity, parts)
  if (v.fulfillment) {
    const f = v.fulfillment
    if (
      !isDeepStrictEqual(f.parent_binding, v.parent.binding) ||
      f.child_binding.owner_id !== identity.ownerId ||
      f.child_binding.epoch !== identity.epoch ||
      f.child_binding.command_id !== h.fulfilled_by ||
      h.answers.at(-1)?.reply_id !== f.child_binding.command_id ||
      h.answers.at(-1)?.reply_input_hash !== f.child_binding.input_hash ||
      conversationJournalInstant(f.child_binding.admitted_at) <
        conversationJournalInstant(parts.decision.sealed_at)
    )
      conversationContinuationReadUnavailable()
    proveEffect(f.receipt, f.child_binding, v.parent, v.observed_at)
  }
  return freezeInterpretation(v)
}
