/** Durable interpretation composition only. No candidate pre-gate, second text
 * extractor, nutrition calculator, registration, message or reward writer. */
import { isDeepStrictEqual } from 'node:util'
import type { ServiceClient } from '@mpp/db'
import type { MobileAuthContext } from './auth'
import {
  type BoundConversationMealCommand,
  bindConversationCommand,
} from './conversation-command-contracts'
import {
  type ConversationCommandJournal,
  createSupabaseConversationCommandJournal,
} from './conversation-command-journal'
import {
  buildConversationMealInterpretationSource,
  type CapturedMealInterpretationSource,
  type ConversationMealInterpretation,
  type ConversationMealInterpretationSource,
  freezeInterpretation,
  type MealInterpretationModelResult,
  mealInterpretationSchema,
} from './conversation-meal-interpretation-contracts'
import { validateConversationMealInterpretationModel } from './conversation-meal-interpretation-validation'
import {
  type ConversationMealSemanticOutcome,
  type ConversationMealSemanticStore,
  createSupabaseConversationMealSemanticStore,
} from './conversation-meal-semantic-store'
import { createSupabaseConversationMealSourceFactory } from './conversation-meal-source'
import { MobileApiError } from './http'
import { authenticatedReevaluationOwner } from './reevaluation-cycle-service'

export interface ConversationMealInterpreterPort {
  interpret(
    source: ConversationMealInterpretationSource,
    attempt: { attemptId: string; remainingMs: number },
  ): Promise<ConversationMealInterpretation>
}
export interface ConversationMealInterpretationDependencies {
  interpreter: ConversationMealInterpreterPort
  store?: ConversationMealSemanticStore
  journal?: ConversationCommandJournal
  sources?: {
    capture(command: BoundConversationMealCommand): Promise<CapturedMealInterpretationSource>
  }
  /** Backend request budget, capped at the existing 45s model-call ceiling. */
  remainingMs?: number
}
export interface PersistedMealInterpretation {
  readonly status: 'interpreted'
  readonly command: BoundConversationMealCommand
  readonly interpretation: ConversationMealInterpretation
}
function unavailable(): never {
  throw new MobileApiError(
    503,
    'conversation_meal_interpretation_unavailable',
    'Meal interpretation is unavailable',
  )
}
function conflict(): never {
  throw new MobileApiError(
    409,
    'conversation_meal_interpretation_changed',
    'This command can no longer be processed',
  )
}
function reconciliation(): never {
  throw new MobileApiError(
    409,
    'conversation_meal_interpretation_reconciliation_required',
    'The outcome of this interpretation must be reconciled',
  )
}
function existing(
  value: ConversationMealSemanticOutcome,
  command: BoundConversationMealCommand,
): PersistedMealInterpretation | null {
  if (value.action === 'absent') return null
  if (
    value.action === 'stale_epoch' ||
    value.action === 'source_conflict' ||
    value.action === 'day_closed' ||
    value.action === 'attempt_conflict'
  )
    return conflict()
  if (!('status' in value)) return unavailable()
  if (
    value.owner_id !== command.ownerId ||
    value.command_id !== command.commandId ||
    value.input_hash !== command.inputHash
  )
    return unavailable()
  if (value.status !== 'completed' || value.result === null) return reconciliation()
  const interpretation = mealInterpretationSchema.parse(structuredClone(value.result))
  if (
    !isDeepStrictEqual(interpretation, value.result) ||
    interpretation.owner_id !== command.ownerId ||
    interpretation.command_id !== command.commandId ||
    interpretation.input_hash !== command.inputHash ||
    interpretation.attempt_id !== value.attempt_id ||
    interpretation.source_hash !== value.source_hash
  )
    return unavailable()
  return freezeInterpretation({ status: 'interpreted', command, interpretation })
}

/** A bound send declares consumption. A caption that only identifies the meal
 * and its independently verified day still refers to all bound visual items. */
function interpretBoundMealPhoto(
  command: BoundConversationMealCommand,
  source: ConversationMealInterpretationSource,
  attemptId: string,
): ConversationMealInterpretation | null {
  const input = command.command
  const [first, second] = source.sources
  const caption = first?.unit === 'media_caption' ? first.text : null
  const observation = caption === null ? first : second
  if (
    !('intake_origin' in input) ||
    input.source.channel !== 'media' ||
    input.source.user_action !== 'report_actual_record' ||
    source.media_binding?.kind !== 'conversation_photo' ||
    source.media_binding.catalog_version !== 2 ||
    source.sources.length !== (caption === null ? 1 : 2) ||
    observation?.unit !== 'vision_items' ||
    !observation.visual_items.length
  )
    return null

  const textSources: MealInterpretationModelResult['sources'] = []
  if (caption === null) {
    if (input.source.caption !== undefined) return null
  } else {
    const description =
      /^(?<report>(?:isso|isto|esse|essa|este|esta) foi) (?:meu|minha) (?:café da manhã|cafe da manha|almoço|almoco|jantar|lanche|refeição|refeicao) de (?<day>ontem|anteontem)[.!]?$/iu.exec(
        caption,
      )?.groups
    if (
      input.source.caption !== caption ||
      !source.reported_day ||
      !description?.report ||
      description.day?.toLowerCase() !== source.reported_day
    )
      return null
    const reportEnd = description.report.length
    textSources.push({
      unit: 'media_caption',
      classification: 'reported',
      spans: [
        { start: 0, end: reportEnd, kind: 'report', food_index: null },
        { start: reportEnd, end: caption.length, kind: 'other', food_index: null },
      ],
      visual_indexes: [],
    })
  }

  // At least one portion distinguishes a partial meal from the single
  // missing-portion sentinel used for a nutrition label.
  const hasPortion = observation.visual_items.some((item) => {
    if (!item || typeof item !== 'object' || Array.isArray(item)) return false
    const grams = item.quantity_g_estimate
    return typeof grams === 'number' && grams > 0 && grams <= 9999
  })
  if (!hasPortion) return null

  const indexes = observation.visual_items.map((_, index) => index)
  const result = validateConversationMealInterpretationModel(
    {
      schema: 'conversation.meal-interpretation.v1',
      decision: 'reported_meal',
      reason: 'explicit_media_action',
      sources: [
        ...textSources,
        { unit: 'vision_items', classification: 'visual', spans: [], visual_indexes: indexes },
      ],
      foods: indexes.map((index) => ({
        index,
        name: null,
        quantity: null,
        unit: null,
        visual_index: index,
      })),
    },
    source,
  )
  return {
    ...result,
    interpreter_version: source.interpreter_version,
    owner_id: source.owner_id,
    command_id: source.command_id,
    attempt_id: attemptId,
    input_hash: source.input_hash,
    source_hash: source.source_hash,
    source_units: source.source_units,
    provider_metadata: {
      model: 'bound-photo-observations',
      prompt_tokens: 0,
      completion_tokens: 0,
      cost_usd: 0,
      latency_ms: 0,
    },
  }
}

export async function interpretPersistedConversationMeal(
  db: ServiceClient,
  auth: MobileAuthContext,
  idempotencyKey: string | null,
  raw: unknown,
  dependencies: ConversationMealInterpretationDependencies,
): Promise<PersistedMealInterpretation> {
  const started = Date.now(),
    who = structuredClone(auth),
    owner = authenticatedReevaluationOwner(who)
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
  const budget = dependencies.remainingMs ?? 45000
  if (!Number.isFinite(budget) || budget <= 0) return unavailable()
  const deadline = started + Math.min(45000, budget)
  // Freeze callbacks before any await, including injected implementations.
  const s = dependencies.store ?? createSupabaseConversationMealSemanticStore(db)
  const store = {
    read: s.read.bind(s),
    start: s.start.bind(s),
    commit: s.commit.bind(s),
    markUnknown: s.markUnknown.bind(s),
  }
  const j = dependencies.journal ?? createSupabaseConversationCommandJournal(db)
  const journal = { read: j.read.bind(j), admit: j.admit.bind(j) }
  const sources = dependencies.sources ?? createSupabaseConversationMealSourceFactory(db)
  const capture = sources.capture.bind(sources),
    interpret = dependencies.interpreter.interpret.bind(dependencies.interpreter)
  const read = async () => existing(await store.read(command), command)
  try {
    // A completed/uncertain durable attempt wins before any admission, source
    // capture or provider work, even after old HTTP-cache leases have expired.
    const prior = await read()
    if (prior) return prior
    let admitted = await journal.read({ ownerId: owner, commandId: command.commandId })
    if (admitted.action === 'stale_epoch') return conflict()
    if (admitted.action === 'available' && !isDeepStrictEqual(admitted.source, command))
      return conflict()
    if (admitted.action === 'absent') {
      try {
        const admission = await journal.admit(command)
        if (!('binding' in admission)) return conflict()
        if (
          admission.binding.owner_id !== owner ||
          admission.binding.command_id !== command.commandId ||
          admission.binding.input_hash !== command.inputHash
        )
          return conflict()
      } catch (error) {
        if (error instanceof MobileApiError && [409, 429].includes(error.status)) throw error
        admitted = await journal.read({ ownerId: owner, commandId: command.commandId })
        if (admitted.action === 'stale_epoch') return conflict()
        if (admitted.action !== 'available' || !isDeepStrictEqual(admitted.source, command))
          return unavailable()
      }
    }
    // This is the actual stored original source; unlike old draft preparation,
    // it does not ask a regex classifier or text extractor before semantics.
    const source = buildConversationMealInterpretationSource(command, await capture(command))
    if (Date.now() >= deadline) return unavailable()
    let claim: ConversationMealSemanticOutcome
    try {
      claim = await store.start(command, source.source_hash)
    } catch {
      const recovered = await read()
      return recovered ?? reconciliation()
    }
    if (claim.action !== 'claimed') return existing(claim, command) ?? unavailable()
    if (
      !('status' in claim) ||
      claim.status !== 'started' ||
      claim.result !== null ||
      claim.owner_id !== owner ||
      claim.command_id !== command.commandId ||
      claim.input_hash !== command.inputHash ||
      claim.source_hash !== source.source_hash ||
      claim.epoch !== source.epoch
    )
      return unavailable()
    // Only this NEW start response is a call permission. A read of 'started'
    // cannot recreate it. No timer, HTTP TTL or failure releases it for reuse.
    let interpreted: ConversationMealInterpretation
    try {
      const remainingMs = deadline - Date.now()
      if (remainingMs <= 0) return reconciliation()
      const returned =
        interpretBoundMealPhoto(command, source, claim.attempt_id) ??
        (await interpret(source, { attemptId: claim.attempt_id, remainingMs }))
      interpreted = mealInterpretationSchema.parse(structuredClone(returned))
      if (
        !isDeepStrictEqual(returned, interpreted) ||
        interpreted.owner_id !== owner ||
        interpreted.command_id !== command.commandId ||
        interpreted.input_hash !== command.inputHash ||
        interpreted.source_hash !== source.source_hash ||
        interpreted.attempt_id !== claim.attempt_id ||
        !isDeepStrictEqual(interpreted.source_units, source.source_units)
      )
        return unavailable()
    } catch {
      try {
        await store.markUnknown(command, claim.attempt_id, 'provider_outcome_unknown')
      } catch {
        /* A failed marker never licenses another provider call. */
      }
      return (await read()) ?? reconciliation()
    }
    try {
      return (
        existing(await store.commit(command, claim.attempt_id, interpreted), command) ??
        reconciliation()
      )
    } catch (error) {
      if (error instanceof MobileApiError && error.status === 409) throw error
      // The result might already be committed. Read exactly once; neither
      // repeat the commit nor mark it unknown while that response is uncertain.
      return (await read()) ?? reconciliation()
    }
  } catch (error) {
    if (error instanceof MobileApiError && [409, 422, 429].includes(error.status)) throw error
    return unavailable()
  }
}
