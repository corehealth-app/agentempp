/** Private composition of the real durable interpretation, shared calculator
 * and atomic writer. No HTTP route, legacy agent/executor or reward writer.
 * Historical enrichment below is NOT safe public/current-policy presentation. */
import { isDeepStrictEqual } from 'node:util'
import {
  calcMealMacros,
  detectExplicitMealType,
  isUnresolvedNutritionSource,
  type MealCalcResult,
} from '@mpp/agent'
import type { ServiceClient } from '@mpp/db'
import type { MobileAuthContext } from './auth'
import {
  type ConversationJournalBinding,
  conversationJournalBindingSchema,
} from './conversation-command-candidate-contracts'
import {
  type BoundConversationMealCommand,
  bindConversationCommand,
} from './conversation-command-contracts'
import {
  type ConversationCommandJournal,
  createSupabaseConversationCommandJournal,
} from './conversation-command-journal'
import { createConversationMealDayInitializer } from './conversation-meal-day'
import {
  type ConversationMealFeedbackService,
  createSupabaseConversationMealFeedbackService,
  type OriginalConversationMealFeedback,
} from './conversation-meal-feedback-service'
import {
  type ConversationMealEffectReceipt,
  parseConversationMealEffectReceipt,
} from './conversation-meal-feedback-store'
import {
  buildConversationMealInterpretationSource,
  type ConversationMealInterpretation,
  freezeInterpretation,
  parseConversationMealInterpretation,
} from './conversation-meal-interpretation-contracts'
import {
  type ConversationMealInterpreterPort,
  interpretPersistedConversationMeal,
} from './conversation-meal-interpretation-service'
import {
  type MaterializedConversationMeal,
  mapConversationMealCalculationSources,
  materializeConversationMealInterpretation,
} from './conversation-meal-materialization'
import {
  type CapturedConversationMealSource,
  type ConversationMealSourceFactory,
  createSupabaseConversationMealSourceFactory,
} from './conversation-meal-source'
import {
  type ConversationMealPreparedRead,
  type ConversationMealWriter,
  createSupabaseConversationMealWriter,
} from './conversation-meal-writer'
import {
  type ConversationResolvedMeal,
  parseConversationMealStoredSource,
  parseConversationResolvedMeal,
} from './conversation-meal-writer-contracts'
import { MobileApiError } from './http'
import { mobileQuantityDisplay } from './mobile-quantity-display'
import { applyMobilePreparedDishEstimate } from './prepared-dish-estimate'
import { authenticatedReevaluationOwner } from './reevaluation-cycle-service'

export interface ConversationMealRegistrationDependencies {
  interpreter: ConversationMealInterpreterPort
  writer?: ConversationMealWriter
  journal?: ConversationCommandJournal
  sources?: ConversationMealSourceFactory
  initializeDay?: (auth: MobileAuthContext, command: BoundConversationMealCommand) => Promise<void>
  interpret?: (
    command: BoundConversationMealCommand,
    source: CapturedConversationMealSource,
  ) => Promise<ConversationMealInterpretation>
  materialize?: typeof materializeConversationMealInterpretation
  calculate?: typeof calcMealMacros
  confidenceThreshold?: () => Promise<number>
  feedback?: ConversationMealFeedbackService
}
export type ConversationMealRegistrationResult =
  | {
      readonly status: 'saved'
      readonly command: BoundConversationMealCommand
      readonly serverBinding: ConversationJournalBinding
      readonly receipt: ConversationMealEffectReceipt
      readonly historicalFeedback: OriginalConversationMealFeedback | null
    }
  | {
      readonly status: 'not_recorded'
      readonly command: BoundConversationMealCommand
      readonly reason: string
      readonly foodIndexes: readonly number[]
    }

function unavailable(): never {
  throw new MobileApiError(
    503,
    'conversation_meal_registration_unavailable',
    'Meal registration is unavailable',
  )
}
function conflict(): never {
  throw new MobileApiError(
    409,
    'conversation_meal_registration_changed',
    'This meal command can no longer be processed',
  )
}
function reconciliation(): never {
  throw new MobileApiError(
    409,
    'conversation_meal_registration_reconciliation_required',
    'The result of this command must be reconciled',
  )
}
function binding(
  raw: ConversationJournalBinding,
  command: BoundConversationMealCommand,
): ConversationJournalBinding {
  const value = conversationJournalBindingSchema.parse(structuredClone(raw))
  if (
    !isDeepStrictEqual(value, raw) ||
    value.owner_id !== command.ownerId ||
    value.command_id !== command.commandId ||
    value.input_hash !== command.inputHash
  )
    return unavailable()
  return freezeInterpretation(value)
}
function sourceCapsule(
  raw: CapturedConversationMealSource,
  command: BoundConversationMealCommand,
  b: ConversationJournalBinding,
): CapturedConversationMealSource {
  const s = parseConversationMealStoredSource(raw, command)
  if (
    s.epoch !== b.epoch ||
    raw.sourceReader.ownerId !== command.ownerId ||
    raw.sourceReader.asOf !== s.capturedAt
  )
    return unavailable()
  // Detach all ports as well as data. In particular, a later changed callback
  // cannot replace the captured hit/MISS evidence used by the final writer.
  return Object.freeze({
    ...s,
    action: raw.action,
    sourceReader: Object.freeze({
      ownerId: raw.sourceReader.ownerId,
      asOf: raw.sourceReader.asOf,
      read: raw.sourceReader.read.bind(raw.sourceReader),
    }),
    auditSink: raw.auditSink.bind(raw),
    sourceReceipts: raw.sourceReceipts.bind(raw),
    auditEvents: raw.auditEvents.bind(raw),
  })
}
function notRecorded(
  command: BoundConversationMealCommand,
  reason: string,
  foodIndexes: readonly number[] = [],
): ConversationMealRegistrationResult {
  return freezeInterpretation({
    status: 'not_recorded',
    command,
    reason,
    foodIndexes: [...foodIndexes],
  })
}
function materialBinding(
  m: MaterializedConversationMeal,
  i: ConversationMealInterpretation,
  c: BoundConversationMealCommand,
  s: CapturedConversationMealSource,
): void {
  if (
    m.schema !== 'conversation.meal-materialization.v1' ||
    m.input_hash !== c.inputHash ||
    m.source_hash !== s.sourceHash ||
    m.attempt_id !== i.attempt_id
  )
    unavailable()
  const occurrenceIndexes = m.source_groups.flatMap((g) => g.interpretation_food_indexes)
  if (
    occurrenceIndexes.length !== i.foods.length ||
    new Set(occurrenceIndexes).size !== i.foods.length ||
    occurrenceIndexes.some((index) => !i.foods.some((f) => f.index === index))
  )
    unavailable()
  const inputs = m.source_groups.flatMap((g, index) => {
    if (
      g.group_index !== index ||
      g.source_positions.length !== g.interpretation_food_indexes.length
    )
      unavailable()
    for (const p of g.source_positions) {
      const f = i.foods.find((food) => food.index === p.food_index)
      if (
        !f ||
        !g.interpretation_food_indexes.includes(f.index) ||
        !isDeepStrictEqual(
          [p.name, p.quantity, p.unit_ref, p.visual_index],
          [f.name, f.quantity, f.unit, f.visual_index],
        )
      )
        unavailable()
    }
    if (
      new Set(g.source_positions.map((p) => p.food_index)).size !==
      g.interpretation_food_indexes.length
    )
      unavailable()
    return g.input_indexes
  })
  if (
    !m.inputs.length ||
    inputs.length !== m.inputs.length ||
    new Set(inputs).size !== m.inputs.length ||
    inputs.some((index) => !Number.isInteger(index) || index < 0 || index >= m.inputs.length)
  )
    unavailable()
  for (const [index, input] of m.inputs.entries()) {
    if (
      input.input_index !== index ||
      !m.source_groups[input.source_group_index]?.input_indexes.includes(index) ||
      !isDeepStrictEqual(input.calculation_input, {
        food_name: input.candidate.name,
        quantity_g: input.candidate.quantity_g,
      })
    )
      unavailable()
  }
}
function unresolved(calculation: MealCalcResult): boolean {
  return (
    !calculation.items.length ||
    calculation.items.some(
      (i) =>
        isUnresolvedNutritionSource(i.source) ||
        i.source === 'canonical_composite_partial' ||
        i.source === 'pending_approved' ||
        !!i.preparation_options?.length,
    )
  )
}
function resolvedPayload(
  command: BoundConversationMealCommand,
  s: CapturedConversationMealSource,
  material: MaterializedConversationMeal,
  calc: MealCalcResult,
  mealType: ConversationResolvedMeal['meal_type'],
): ConversationResolvedMeal {
  const sources = mapConversationMealCalculationSources(material, calc)
  const resolved = {
    schema: 'conversation.meal-resolved.v1',
    input_hash: command.inputHash,
    source_hash: s.sourceHash,
    meal_type: mealType,
    semantic_proof: {
      schema: 'conversation.meal-semantic.v1',
      decision: 'consumed_meal',
      input_hash: command.inputHash,
      source_hash: s.sourceHash,
      complete_source: true,
      source_units: [...s.context.source_units],
      input_count: material.inputs.length,
    },
    items: calc.items.map((item, index) => {
      const source = sources[index] ?? unavailable()
      const display = mobileQuantityDisplay(item.food_name) ?? source.quantity_display
      return {
        name: item.food_name,
        food_db_id: item.matched_taco_id,
        nutrition_source: item.source,
        quantity_g: item.quantity_g,
        kcal: item.kcal,
        protein_g: item.protein_g,
        carbs_g: item.carbs_g,
        fat_g: item.fat_g,
        confidence: source.confidence,
        input_indexes: [...source.input_indexes],
        quantity_basis: source.quantity_basis,
        display_qty: display
          ? item.quantity_g / display.grams_per_unit
          : (item.display_qty ?? null),
        display_unit: display?.unit ?? item.display_unit ?? null,
      }
    }),
    totals: {
      kcal: calc.totals.kcal,
      protein_g: calc.totals.protein_g,
      carbs_g: calc.totals.carbs_g,
      fat_g: calc.totals.fat_g,
    },
    preparation_annotations: calc.preparation_annotations ?? [],
    source_receipts: structuredClone(s.sourceReceipts()),
  }
  return parseConversationResolvedMeal(resolved, { command, source: s })
}
async function defaultThreshold(db: ServiceClient): Promise<number> {
  const { data, error } = await db
    .from('global_config')
    .select('value')
    .eq('key', 'vision.meal.confidence_threshold')
    .maybeSingle()
  if (error) return unavailable()
  const n = Number(data?.value)
  return Number.isFinite(n) && n > 0 && n <= 1 ? n : 0.6
}

export async function registerPersistedConversationMeal(
  db: ServiceClient,
  originalAuth: MobileAuthContext,
  idempotencyKey: string | null,
  raw: unknown,
  dependencies: ConversationMealRegistrationDependencies,
): Promise<ConversationMealRegistrationResult> {
  const auth = freezeInterpretation(structuredClone(originalAuth)),
    owner = authenticatedReevaluationOwner(auth)
  let command: BoundConversationMealCommand
  try {
    command = bindConversationCommand(owner, idempotencyKey, structuredClone(raw))
  } catch {
    throw new MobileApiError(
      422,
      'conversation_command_invalid',
      'A valid command identity and source are required',
    )
  }
  // Snapshot dependencies before the first await. No optional enrichment can
  // change these callbacks, or request a second factual/provider operation.
  const w = dependencies.writer ?? createSupabaseConversationMealWriter(db)
  const writer = {
    readPrepared: w.readPrepared.bind(w),
    readEffect: w.readEffect.bind(w),
    prepare: w.prepare.bind(w),
    commit: w.commit.bind(w),
  }
  const j = dependencies.journal ?? createSupabaseConversationCommandJournal(db),
    journal = Object.freeze({
      read: j.read.bind(j),
      admit: j.admit.bind(j),
      attach: j.attach.bind(j),
    })
  const f = dependencies.sources ?? createSupabaseConversationMealSourceFactory(db),
    capture = f.capture.bind(f)
  const initialize =
    dependencies.initializeDay?.bind(dependencies) ??
    createConversationMealDayInitializer(db).initialize
  const interpreter = {
    interpret: dependencies.interpreter.interpret.bind(dependencies.interpreter),
  }
  const interpret =
    dependencies.interpret?.bind(dependencies) ??
    (async (c: BoundConversationMealCommand, s: CapturedConversationMealSource) =>
      (
        await interpretPersistedConversationMeal(db, auth, `cmsg1:${c.commandId}`, c.command, {
          interpreter,
          journal,
          sources: { capture: async () => s },
        })
      ).interpretation)
  const materialize =
    dependencies.materialize?.bind(dependencies) ?? materializeConversationMealInterpretation
  const calculate = dependencies.calculate?.bind(dependencies) ?? calcMealMacros
  const threshold =
    dependencies.confidenceThreshold?.bind(dependencies) ?? (() => defaultThreshold(db))
  const feedback = dependencies.feedback ?? createSupabaseConversationMealFeedbackService(db)
  const ensureOriginal = feedback.ensureOriginal.bind(feedback),
    readOriginal = feedback.readOriginal.bind(feedback)
  const success = async (
    rawReceipt: ConversationMealEffectReceipt,
    b: ConversationJournalBinding,
    replay: boolean,
  ): Promise<ConversationMealRegistrationResult> => {
    const receipt = parseConversationMealEffectReceipt(rawReceipt, command)
    let historicalFeedback: OriginalConversationMealFeedback | null = null
    try {
      historicalFeedback = await (replay ? readOriginal : ensureOriginal)({
        auth,
        command,
        receipt,
      })
    } catch {
      /* The factual effect is already committed. Never retry it for enrichment. */
    }
    return freezeInterpretation({
      status: 'saved',
      command,
      serverBinding: b,
      receipt,
      historicalFeedback,
    })
  }
  const commit = async (
    resolvedHash: string,
    b: ConversationJournalBinding,
  ): Promise<ConversationMealRegistrationResult> => {
    try {
      const v = await writer.commit({ command, resolvedHash })
      if ('receipt' in v) return success(v.receipt, b, v.action === 'replay')
      return conflict()
    } catch (error) {
      if (error instanceof MobileApiError && error.status === 409) throw error
      // A lost HTTP outcome only grants a receipt read, never another writer.
      const recovered = await writer.readEffect(command)
      if (recovered.action === 'available') return success(recovered.receipt, b, true)
      return reconciliation()
    }
  }
  const prior = async (
    v: ConversationMealPreparedRead,
  ): Promise<ConversationMealRegistrationResult | null> => {
    if (v.action === 'stale_epoch') return conflict()
    if (v.action !== 'available') return null
    const b = binding(v.binding, command)
    if (v.receipt) return success(v.receipt, b, true)
    if (v.resolved) {
      if (!v.source || v.source.epoch !== b.epoch) return unavailable()
      parseConversationResolvedMeal(v.resolved.value, { command, source: v.source })
      return commit(v.resolved.resolvedHash, b)
    }
    return null
  }
  try {
    const stored = await writer.readPrepared(command),
      recovered = await prior(stored)
    if (recovered) return recovered
    let b: ConversationJournalBinding | null = null
    if (stored.action === 'available') b = binding(stored.binding, command)
    else {
      let admission: Awaited<ReturnType<ConversationCommandJournal['admit']>> | null = null
      try {
        admission = await journal.admit(command)
      } catch (error) {
        if (error instanceof MobileApiError && [409, 429].includes(error.status)) throw error
        const read = await journal.read({ ownerId: owner, commandId: command.commandId })
        if (read.action !== 'available' || !isDeepStrictEqual(read.source, command))
          return reconciliation()
        b = binding(read.binding, command)
      }
      if (admission) {
        if (!('binding' in admission)) return conflict()
        b = binding(admission.binding, command)
      }
    }
    if (!b) return reconciliation()
    // Never refresh official day/source facts after they have been captured.
    if (!(stored.action === 'available' && stored.source)) await initialize(auth, command)
    const s = sourceCapsule(await capture(command), command, b)
    if (
      stored.action === 'available' &&
      stored.source &&
      !isDeepStrictEqual(
        parseConversationMealStoredSource(stored.source, command),
        parseConversationMealStoredSource(s, command),
      )
    )
      return unavailable()
    const evidence = buildConversationMealInterpretationSource(command, s)
    const rawInterpretation = structuredClone(await interpret(command, s))
    const i = parseConversationMealInterpretation(rawInterpretation, {
      ownerId: owner,
      commandId: command.commandId,
      inputHash: command.inputHash,
      sourceHash: s.sourceHash,
      attemptId: rawInterpretation.attempt_id,
    })
    if (!isDeepStrictEqual(i.source_units, evidence.source_units)) return unavailable()
    if (i.decision !== 'reported_meal') return notRecorded(command, i.reason)
    const limit = await threshold()
    if (!Number.isFinite(limit) || limit <= 0 || limit > 1) return unavailable()
    const m = freezeInterpretation(
      structuredClone(await materialize(db, command, s, i, { confidenceThreshold: limit })),
    )
    if (m.status === 'clarification_required') return notRecorded(command, m.reason, m.food_indexes)
    materialBinding(m, i, command, s)
    // Labels require a separate explicit consent command. They are not generic
    // food references and cannot silently become approval or be discarded.
    if (m.nutrition_label) return notRecorded(command, 'nutrition_label_confirmation_required')
    const inputs = m.inputs.map((input) => ({ ...input.calculation_input }))
    const initial = await calculate(db, inputs, String(s.context.owner.country), owner, {
      consumptionPolicy: 'consumed-meal-v1',
      preparationAnnotations: 'consumed.preparation.v1',
      sourceReader: s.sourceReader,
      auditSink: s.auditSink,
    })
    const calc = applyMobilePreparedDishEstimate(
      structuredClone(initial),
      inputs,
      'mobile_app',
      typeof s.context.owner.locale === 'string' ? s.context.owner.locale : null,
    )
    if (unresolved(calc))
      return notRecorded(
        command,
        'nutrition_unresolved',
        i.foods.map((food) => food.index),
      )
    // The selected meal always wins over text or time. Optional automatic
    // personal-routine classification remains an activation gate until the
    // original source captures its actual owned meal-window evidence.
    const text = evidence.sources
      .filter((source) => source.unit !== 'vision_items')
      .map((source) => source.text ?? '')
      .join('\n')
    const mealType = command.command.meal_type ?? detectExplicitMealType(text)
    if (!mealType) return notRecorded(command, 'meal_type_required')
    const resolved = resolvedPayload(command, s, m, calc, mealType)
    let prepared: Awaited<ReturnType<ConversationMealWriter['prepare']>>
    try {
      prepared = await writer.prepare({ command, source: s, resolved })
    } catch (error) {
      if (error instanceof MobileApiError && error.status === 409) throw error
      const winner = await prior(await writer.readPrepared(command))
      return winner ?? reconciliation()
    }
    if (!('resolvedHash' in prepared)) {
      if (prepared.action !== 'resolved_conflict') return conflict()
      const winner = await prior(await writer.readPrepared(command))
      return winner ?? reconciliation()
    }
    return commit(prepared.resolvedHash, b)
  } catch (error) {
    if (error instanceof MobileApiError) throw error
    return unavailable()
  }
}
