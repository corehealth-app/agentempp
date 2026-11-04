/** Private linked clarification orchestration. The original report/source/model
 * stays original; SQL owns current admission, answer-chain and atomic fulfillment.
 * No HTTP activation, day initialization, interpreter, fake child-v1 receipt or
 * feedback enrichment is supplied by this service. */
import { isDeepStrictEqual } from 'node:util'
import {
  calcMealMacros,
  detectExplicitMealType,
  isUnresolvedNutritionSource,
  type MealCalcResult,
} from '@mpp/agent'
import type { ServiceClient } from '@mpp/db'
import type { MobileAuthContext } from './auth'
import { bindConversationCommand } from './conversation-command-contracts'
import {
  type BoundConversationMealReply,
  bindConversationMealReply,
} from './conversation-meal-continuation-input'
import {
  type ConversationMealContinuationReadIdentity,
  type ConversationMealContinuationReadOutcome,
  detachConversationContinuationReadJson,
  parseConversationMealContinuationPreparationShape,
  parseConversationMealContinuationRead,
  parseConversationMealContinuationReadIdentity,
} from './conversation-meal-continuation-read-contracts'
import {
  type ConversationMealContinuationSourceFactory,
  createSupabaseConversationMealContinuationSourceFactory,
} from './conversation-meal-continuation-source'
import {
  type ConversationMealContinuationWriteOutcome,
  type ConversationMealContinuationWriter,
  createSupabaseConversationMealContinuationWriter,
} from './conversation-meal-continuation-writer'
import {
  buildConversationMealInterpretationSource,
  freezeInterpretation,
  parseConversationMealInterpretation,
} from './conversation-meal-interpretation-contracts'
import {
  type MaterializedConversationMeal,
  mapConversationMealCalculationSources,
  materializeStoredConversationMealContinuation,
} from './conversation-meal-materialization'
import type { CapturedConversationMealSource } from './conversation-meal-source'
import { parseConversationMealStoredSource } from './conversation-meal-writer-contracts'
import { MobileApiError } from './http'
import { mobileQuantityDisplay } from './mobile-quantity-display'
import { applyMobilePreparedDishEstimate } from './prepared-dish-estimate'
import { authenticatedReevaluationOwner } from './reevaluation-cycle-service'

type Available = Extract<ConversationMealContinuationReadOutcome, { action: 'available' }>
type Receipt = NonNullable<NonNullable<Available['reply']>['receipt']>
type Identity = ConversationMealContinuationReadIdentity & {
  readonly replyId: string
  readonly replyInputHash: string
}
/** Preconditions only. The mandatory callback must close over the actual verified
 * Auth/lease observation; these IDs never create or renew a capability. */
export interface ConversationMealContinuationScope {
  readonly authUserId: string
  readonly ownerId: string
  readonly epoch: string
  readonly parentCommandId: string
  readonly replyId: string
}
export interface ConversationMealContinuationServiceDependencies {
  readonly checkCurrentScope: (
    scope: ConversationMealContinuationScope,
  ) => boolean | Promise<boolean>
  readonly writer?: ConversationMealContinuationWriter
  readonly sources?: ConversationMealContinuationSourceFactory
  readonly materialize?: typeof materializeStoredConversationMealContinuation
  readonly calculate?: typeof calcMealMacros
  readonly confidenceThreshold?: () => Promise<number>
}
export type ConversationMealContinuationServiceResult =
  | {
      readonly status: 'saved'
      readonly identity: Identity
      readonly receipt: Receipt
      readonly historicalFeedback: null
      readonly feedbackGate: 'continuation_feedback_v2_unavailable'
    }
  | {
      readonly status: 'needs_reply'
      readonly identity: Identity
      readonly question: NonNullable<Available['head']['question']>
    }
  | { readonly status: 'held'; readonly identity: Identity; readonly reason: string }
  | {
      readonly status: 'reconciliation_required'
      readonly identity: Identity
      readonly reason: string
    }
class ScopeChanged extends Error {}
function unavailable(): never {
  throw new MobileApiError(
    503,
    'conversation_meal_continuation_unavailable',
    'Linked meal processing is unavailable',
  )
}
function replyIdentity(raw: ConversationMealContinuationReadIdentity): Identity {
  const i = parseConversationMealContinuationReadIdentity(raw)
  if (!i.replyId || !i.replyInputHash || i.replyId === i.parentCommandId) unavailable()
  return Object.freeze({ ...i, replyId: i.replyId, replyInputHash: i.replyInputHash })
}
function bind(raw: BoundConversationMealReply): BoundConversationMealReply {
  const copy = detachConversationContinuationReadJson(raw) as BoundConversationMealReply
  const bound = bindConversationMealReply({
    binding: copy.binding,
    replyId: copy.replyId,
    input: copy.input,
    idempotencyKey: copy.idempotencyKey,
  })
  if (!isDeepStrictEqual(copy, bound)) unavailable()
  return bound
}
function unresolved(c: MealCalcResult) {
  return (
    !c.items.length ||
    c.items.some(
      (i) =>
        isUnresolvedNutritionSource(i.source) ||
        i.source === 'canonical_composite_partial' ||
        i.source === 'pending_approved' ||
        !!i.preparation_options?.length,
    )
  )
}
function readyMeal(
  material: MaterializedConversationMeal,
  calc: MealCalcResult,
  source: CapturedConversationMealSource,
  mealType: 'cafe' | 'almoco' | 'lanche' | 'jantar' | 'ceia' | 'outro',
) {
  const mapped = mapConversationMealCalculationSources(material, calc)
  return {
    meal_type: mealType,
    items: calc.items.map((item, index) => {
      const fact = mapped[index] ?? unavailable(),
        display = mobileQuantityDisplay(item.food_name) ?? fact.quantity_display
      return {
        name: item.food_name,
        food_db_id: item.matched_taco_id,
        nutrition_source: item.source,
        quantity_g: item.quantity_g,
        kcal: item.kcal,
        protein_g: item.protein_g,
        carbs_g: item.carbs_g,
        fat_g: item.fat_g,
        confidence: fact.confidence,
        input_indexes: [...fact.input_indexes],
        quantity_basis: fact.quantity_basis,
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
    source_receipts: structuredClone(source.sourceReceipts()),
  }
}
export function createConversationMealContinuationService(
  db: ServiceClient,
  dependencies: ConversationMealContinuationServiceDependencies,
) {
  if (typeof dependencies?.checkCurrentScope !== 'function') unavailable()
  // Pin all callbacks and SDK methods before callers can mutate them across awaits.
  const check = dependencies.checkCurrentScope.bind(dependencies),
    materialize =
      dependencies.materialize?.bind(dependencies) ?? materializeStoredConversationMealContinuation,
    calculate = dependencies.calculate?.bind(dependencies) ?? calcMealMacros,
    threshold = dependencies.confidenceThreshold?.bind(dependencies)
  const injectedWriter =
    dependencies.writer &&
    Object.freeze({
      read: dependencies.writer.read.bind(dependencies.writer),
      admit: dependencies.writer.admit.bind(dependencies.writer),
      prepare: dependencies.writer.prepare.bind(dependencies.writer),
      commit: dependencies.writer.commit.bind(dependencies.writer),
    })
  const sourceFromRead = dependencies.sources?.fromRead.bind(dependencies.sources)
  const rpc = db.rpc.bind(db),
    from = db.from.bind(db)
  async function run(
    originalAuth: MobileAuthContext,
    rawIdentity: ConversationMealContinuationReadIdentity,
    originalBound: BoundConversationMealReply | null,
    readOnly: boolean,
  ): Promise<ConversationMealContinuationServiceResult> {
    const auth = freezeInterpretation(
        detachConversationContinuationReadJson(originalAuth) as MobileAuthContext,
      ),
      owner = authenticatedReevaluationOwner(auth),
      identity = replyIdentity(rawIdentity)
    if (owner !== identity.ownerId) unavailable()
    const bound = originalBound === null ? null : bind(originalBound)
    const scope = Object.freeze({
      authUserId: auth.authUserId,
      ownerId: owner,
      epoch: identity.epoch,
      parentCommandId: identity.parentCommandId,
      replyId: identity.replyId,
    })
    const result = (
      status: 'held' | 'reconciliation_required',
      reason: string,
    ): ConversationMealContinuationServiceResult => Object.freeze({ status, identity, reason })
    async function current() {
      try {
        if ((await check(scope)) !== true) throw new ScopeChanged()
      } catch {
        throw new ScopeChanged()
      }
    }
    async function guarded<T>(fn: () => PromiseLike<T>): Promise<T> {
      await current()
      try {
        const value = await fn()
        await current()
        return value
      } catch (error) {
        await current()
        throw error
      }
    }
    // The nutrition reader writes immutable private lookup receipts. Its physical
    // RPCs are guarded individually as well as each surrounding service await.
    const guardedDb = new Proxy(db, {
      get(target, key, receiver) {
        if (key === 'rpc') return (...args: Parameters<typeof rpc>) => guarded(() => rpc(...args))
        if (key === 'from') return from
        return Reflect.get(target, key, receiver)
      },
    })
    const writer = injectedWriter ?? createSupabaseConversationMealContinuationWriter(guardedDb)
    const sourceFactory =
      sourceFromRead ?? createSupabaseConversationMealContinuationSourceFactory(guardedDb).fromRead
    function qualify(raw: unknown): ConversationMealContinuationReadOutcome {
      const state = parseConversationMealContinuationRead(raw, identity)
      if (
        state.action === 'available' &&
        bound &&
        (state.parent.decision.decision_hash !== bound.binding.decisionHash ||
          (state.reply && !isDeepStrictEqual(state.reply.body, bound.input)))
      )
        unavailable()
      return state
    }
    function saved(s: Available): ConversationMealContinuationServiceResult | null {
      if (s.reply?.state !== 'saved' || !s.reply.receipt) return null
      return freezeInterpretation({
        status: 'saved',
        identity,
        receipt: s.reply.receipt,
        historicalFeedback: null,
        feedbackGate: 'continuation_feedback_v2_unavailable',
      })
    }
    function observed(raw: ConversationMealContinuationWriteOutcome): Available | null {
      const outcome = detachConversationContinuationReadJson(
        raw,
      ) as ConversationMealContinuationWriteOutcome
      if (outcome.status !== 'observed') return null
      const state = qualify(outcome.state)
      return state.action === 'available' ? state : null
    }
    function settled(s: Available): ConversationMealContinuationServiceResult | null {
      const receipt = saved(s)
      if (receipt) return receipt
      if (s.head.fulfilled_by !== null) return result('held', 'parent_fulfilled')
      if (s.reply?.state === 'awaiting_reply')
        return s.head.question
          ? freezeInterpretation({ status: 'needs_reply', identity, question: s.head.question })
          : result('held', 'current_question_unavailable')
      if (s.reply?.state === 'superseded') return result('held', 'reply_superseded')
      return null
    }
    async function commit(s: Available): Promise<ConversationMealContinuationServiceResult> {
      if (
        !s.reply?.preparation ||
        s.reply.preparation.preparation.status !== 'ready' ||
        s.reply.state !== 'prepared'
      )
        return result('reconciliation_required', 'ready_preparation_unavailable')
      const hash = s.reply.preparation.prepared_hash
      const next = observed(await guarded(() => writer.commit(identity, hash)))
      if (!next || next.reply?.preparation?.prepared_hash !== hash)
        return result('reconciliation_required', 'commit_uncertain')
      return saved(next) ?? result('reconciliation_required', 'commit_unproven')
    }
    async function prepare(payload: unknown): Promise<ConversationMealContinuationServiceResult> {
      const input = parseConversationMealContinuationPreparationShape(payload)
      const next = observed(await guarded(() => writer.prepare(identity, input)))
      if (!next || !isDeepStrictEqual(next.reply?.preparation?.preparation, input))
        return result('reconciliation_required', 'preparation_uncertain')
      const done = settled(next)
      return done ?? (await commit(next))
    }
    try {
      const initial = qualify(await guarded(() => writer.read(identity)))
      let state: Available
      if (initial.action !== 'available') {
        if (readOnly || !bound || !['absent', 'reply_conflict'].includes(initial.action))
          return result('held', initial.action)
        const admitted = observed(await guarded(() => writer.admit(bound)))
        if (!admitted) return result('reconciliation_required', 'admission_uncertain')
        state = admitted
      } else state = initial
      const done = settled(state)
      if (done) return done
      if (readOnly)
        return result(
          'held',
          state.reply?.state === 'prepared'
            ? 'ready_for_explicit_resume'
            : 'awaiting_explicit_resume',
        )
      if (state.reply?.state === 'prepared') return await commit(state)
      if (!state.reply || state.reply.state !== 'admitted')
        return result('held', 'reply_unavailable')
      await current()
      const supplied = sourceFactory(identity, state)
      const command = bindConversationCommand(
        owner,
        `cmsg1:${identity.parentCommandId}`,
        state.parent.source.context.source_input,
      )
      const interpretation = parseConversationMealInterpretation(state.parent.semantic.result, {
        ownerId: owner,
        commandId: identity.parentCommandId,
        inputHash: identity.parentInputHash,
        sourceHash: state.parent.source.source_hash,
        attemptId: state.parent.semantic.attempt_id,
      })
      if (
        !isDeepStrictEqual(command, supplied.command) ||
        !isDeepStrictEqual(interpretation, supplied.interpretation)
      )
        unavailable()
      function pinSource(
        raw: CapturedConversationMealSource,
        expected: { sourceHash: string; capturedAt: string; context: unknown },
      ): CapturedConversationMealSource {
        const data = parseConversationMealStoredSource(raw, command)
        if (
          data.epoch !== identity.epoch ||
          raw.sourceReader.ownerId !== owner ||
          raw.sourceReader.asOf !== data.capturedAt ||
          !isDeepStrictEqual(
            { sourceHash: data.sourceHash, capturedAt: data.capturedAt, context: data.context },
            expected,
          )
        )
          unavailable()
        const read = raw.sourceReader.read.bind(raw.sourceReader),
          audit = raw.auditSink.bind(raw),
          receipts = raw.sourceReceipts.bind(raw),
          events = raw.auditEvents.bind(raw)
        return Object.freeze({
          ...data,
          action: raw.action,
          sourceReader: Object.freeze({
            ownerId: owner,
            asOf: data.capturedAt,
            read: (...args: Parameters<typeof read>) => guarded(() => read(...args)),
          }),
          auditSink: (...args: Parameters<typeof audit>) => guarded(async () => audit(...args)),
          sourceReceipts: () => freezeInterpretation(structuredClone(receipts())),
          auditEvents: () => freezeInterpretation(structuredClone(events())),
        })
      }
      const childSource = state.reply.source
      const bundle = Object.freeze({
        command,
        interpretation,
        originalSource: pinSource(supplied.originalSource, {
          sourceHash: state.parent.source.source_hash,
          capturedAt: state.parent.source.captured_at,
          context: state.parent.source.context,
        }),
        resolutionSource: pinSource(supplied.resolutionSource, {
          sourceHash: childSource.context.authority.source_hash,
          capturedAt: childSource.captured_at,
          context: childSource.context.authority.context,
        }),
      })
      const limit = await guarded(async () => {
        if (threshold) return threshold()
        const { data, error } = await from('global_config')
          .select('value')
          .eq('key', 'vision.meal.confidence_threshold')
          .maybeSingle()
        if (error) unavailable()
        const n = Number(data?.value)
        return Number.isFinite(n) && n > 0 && n <= 1 ? n : 0.6
      })
      if (!Number.isFinite(limit) || limit <= 0 || limit > 1) unavailable()
      const built = freezeInterpretation(
        detachConversationContinuationReadJson(
          await guarded(() =>
            materialize(
              guardedDb,
              bundle.command,
              bundle.originalSource,
              bundle.interpretation,
              { confidenceThreshold: limit },
              {
                resolutionSource: bundle.resolutionSource,
                answerChain: state.reply?.source.context.answer_chain ?? unavailable(),
              },
            ),
          ),
        ) as Awaited<ReturnType<typeof materializeStoredConversationMealContinuation>>,
      )
      const material = built.materialization
      const child = state.reply
      const base = {
        schema: 'conversation.meal-continuation-preparation.v1',
        input_hash: child.binding.input_hash,
        source_hash: child.source.source_hash,
        parent_ref: child.source.context.parent,
        answer_chain_hash: child.source.context.answer_chain_hash,
        quantity_witnesses: built.quantity_witnesses,
        materialization: material,
      }
      if (material.status === 'clarification_required') {
        if (material.reason !== 'missing_quantity' || material.food_indexes.length !== 1)
          return result('held', material.reason)
        return await prepare({
          ...base,
          status: 'needs_reply',
          next_need: { kind: 'quantity', food_index: material.food_indexes[0] },
        })
      }
      if (material.nutrition_label) return result('held', 'nutrition_label_confirmation_required')
      if (
        material.input_hash !== bundle.command.inputHash ||
        material.source_hash !== bundle.originalSource.sourceHash ||
        material.attempt_id !== bundle.interpretation.attempt_id
      )
        unavailable()
      const evidence = buildConversationMealInterpretationSource(
        bundle.command,
        bundle.originalSource,
      )
      const text = evidence.sources
        .filter((s) => s.unit !== 'vision_items')
        .map((s) => s.text ?? '')
        .join('\n')
      const explicit = bundle.command.command.meal_type ?? detectExplicitMealType(text)
      const typed = child.source.context.answer_chain.find(
        (a) => a.answer.kind === 'meal_type',
      )?.answer
      if (typed?.kind === 'meal_type' && explicit && typed.meal_type !== explicit)
        return result('held', 'meal_type_conflict')
      const mealType = explicit ?? (typed?.kind === 'meal_type' ? typed.meal_type : null)
      if (!mealType)
        return await prepare({
          ...base,
          status: 'needs_reply',
          next_need: { kind: 'meal_type', food_index: null },
        })
      const inputs = material.inputs.map((i) => ({ ...i.calculation_input }))
      const source = bundle.resolutionSource
      const initialCalc = await guarded(() =>
        calculate(guardedDb, inputs, String(source.context.owner.country), owner, {
          consumptionPolicy: 'consumed-meal-v1',
          preparationAnnotations: 'consumed.preparation.v1',
          sourceReader: source.sourceReader,
          auditSink: source.auditSink,
        }),
      )
      const calc = applyMobilePreparedDishEstimate(
        structuredClone(initialCalc),
        inputs,
        'mobile_app',
        typeof source.context.owner.locale === 'string' ? source.context.owner.locale : null,
      )
      if (unresolved(calc)) return result('held', 'nutrition_unresolved')
      return await prepare({
        ...base,
        status: 'ready',
        meal: readyMeal(material, calc, source, mealType),
      })
    } catch (error) {
      return result(
        'reconciliation_required',
        error instanceof ScopeChanged ? 'scope_changed' : 'processing_uncertain',
      )
    }
  }
  return Object.freeze({
    submit(auth: MobileAuthContext, raw: BoundConversationMealReply) {
      const bound = bind(raw)
      return run(
        auth,
        {
          ownerId: bound.binding.ownerId,
          parentCommandId: bound.binding.parentCommandId,
          parentInputHash: bound.binding.parentInputHash,
          epoch: bound.binding.epoch,
          replyId: bound.replyId,
          replyInputHash: bound.inputHash,
        },
        bound,
        false,
      )
    },
    reconcile(auth: MobileAuthContext, identity: ConversationMealContinuationReadIdentity) {
      return run(auth, identity, null, true)
    },
  })
}
