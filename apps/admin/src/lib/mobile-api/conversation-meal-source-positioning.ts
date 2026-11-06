/** Source positioning only; no semantic consumption authority, domain, receipt, analytics or model call.
 * SQL origin is established by the real source factory/prepare CAS, never by
 * accepting this private shape from an HTTP client. Rebuild uses owned frozen
 * processed evidence and the existing deterministic parsers, without inference. */
import { isDeepStrictEqual } from 'node:util'
import { mobileMilkWheyPortions, parseStatedGrams } from '@mpp/agent'
import { classifyConversationMealIntent } from '@mpp/agent/conversation-meal-intent'
import { z } from 'zod'
import type { MobileAuthContext } from './auth'
import type { ConversationCandidateEnvelope } from './conversation-command-candidate-contracts'
import {
  detachAndFreeze,
  parseConversationCandidate,
} from './conversation-command-candidate-contracts'
import type { BoundConversationMealCommand } from './conversation-command-contracts'
import {
  bindConversationCommand,
  conversationMealCommandSchema,
} from './conversation-command-contracts'
import { prepareConversationMealDraft } from './conversation-meal-preparation'
import { sameCurrentClinicalInstant } from './current-clinical-state'
import { MobileApiError } from './http'
import type { MealDraft } from './meal-draft-service'
import { createMealDraft } from './meal-draft-service'
import type { MediaAssetRecord } from './media-service'
import { isRecognizedPreparedDish } from './prepared-dish-estimate'
import { authenticatedReevaluationOwner } from './reevaluation-cycle-service'

const uuid = z
  .string()
  .uuid()
  .regex(/^[0-9a-f-]+$/u)
const hash = z.string().regex(/^[a-f0-9]{64}$/u)
const sourceUnit = z.enum(['command_text', 'media_caption', 'media_transcript', 'vision_items'])
const media = z
  .object({
    asset_id: uuid,
    kind: z.enum(['meal_photo', 'audio_note']),
    status: z.literal('processed'),
    processed_at: z.string().datetime({ offset: true }),
    updated_at: z.string().datetime({ offset: true }),
    processing_result: z.unknown(),
    context_text: z.string().nullable(),
  })
  .strict()
const observation = z
  .object({
    sourceHash: hash,
    context: z
      .object({
        schema: z.literal('conversation.meal-source.v1'),
        owner_id: uuid,
        command_id: uuid,
        input_hash: hash,
        epoch: uuid,
        source_input: conversationMealCommandSchema,
        source_units: z.array(sourceUnit).min(1).max(3),
        source_evidence: z.record(z.unknown()),
        media: media.nullable(),
      })
      .passthrough(),
  })
  .strict()
type Unit = z.infer<typeof sourceUnit>
type Candidate = Extract<ConversationCandidateEnvelope['candidate'], { status: 'prepared' }>
type Item = Candidate['draft']['items'][number]
type SourcePosition =
  | { unit: Exclude<Unit, 'vision_items'>; segment_index: number; item_index: number }
  | { unit: 'vision_items'; item_index: number }
export interface ConversationMealPositionCoverage {
  readonly schema: 'conversation.meal-positioning.v1'
  readonly input_hash: string
  readonly source_hash: string
  readonly complete_source: false
  readonly source_units: readonly Unit[]
  readonly input_count: number
}
export type ConversationMealSourcePositioning =
  | {
      status: 'positioned'
      coverage: ConversationMealPositionCoverage
      inputs: readonly { input_index: number; candidate: Item; source_position: SourcePosition }[]
      preparation: Candidate
    }
  | {
      status: 'conversational' | 'clarification_required'
      reason?: 'unresolved_source' | 'candidate_source_mismatch'
      unresolvedText?: readonly string[]
      preparation: ConversationCandidateEnvelope['candidate']
    }

const normalized = (s: string) =>
  s
    .normalize('NFD')
    .replace(/\p{Diacritic}/gu, '')
    .toLowerCase()
    .replace(/\s+/gu, ' ')
    .trim()
const pointerCaption =
  /^(?:(?:meu|minha|my|este|esta|esse|essa|this|a|o)\s+)?(?:almoco|jantar|cafe da manha|lanche|refeicao|prato|meal|plate|breakfast|lunch|dinner|isto|isso|it|this)$/u
function changed(): never {
  throw new MobileApiError(
    409,
    'conversation_semantic_source_changed',
    'The meal source changed; review this report',
  )
}
function record(v: unknown): Record<string, unknown> | null {
  return v !== null && typeof v === 'object' && !Array.isArray(v)
    ? (v as Record<string, unknown>)
    : null
}
function sameItem(a: Item, b: Item): boolean {
  return (
    normalized(a.name) === normalized(b.name) &&
    a.quantity_g === b.quantity_g &&
    a.quantity_basis === b.quantity_basis &&
    a.count === b.count &&
    normalized(a.unit_label ?? '') === normalized(b.unit_label ?? '') &&
    isDeepStrictEqual(a.quantity_display, b.quantity_display)
  )
}
function sameCandidates(expected: readonly Item[], actual: readonly Item[]): boolean {
  const remaining = [...actual]
  for (const item of expected) {
    const at = remaining.findIndex((other) => sameItem(item, other))
    if (at < 0) return false
    remaining.splice(at, 1)
  }
  return remaining.length === 0
}
function parts(text: string): string[] {
  return text
    .split(/\r?\n|;|(?<!\d),|,(?!\d)/u)
    .map((s) => s.trim())
    .filter(Boolean)
    .flatMap((part) =>
      isRecognizedPreparedDish(parseStatedGrams(part)?.name ?? '')
        ? [part]
        : part
            .split(/\s+e\s+(?=\S)/u)
            .map((s) => s.trim())
            .filter(Boolean),
    )
}
/** The name must cover its whole phrase, not just one shared word. Everything
 * outside names must belong to the quantity grammar the actual parser used. */
function wholeClauseCovered(text: string, items: readonly Item[]): boolean {
  if (/(?:^|[\s,(])[-−]\s*\d/u.test(text)) return false
  const recipe = mobileMilkWheyPortions(text)
  // The existing exact recipe intentionally expands generic "leite"/"whey"
  // into their editable references. Only that whole-phrase resolver may own
  // these added descriptors; one-word similarity never grants coverage.
  if (
    recipe &&
    recipe.length === items.length &&
    recipe.every(
      (part, i) =>
        normalized(part.food_name) === normalized(items[i]?.name ?? '') &&
        part.quantity_g === items[i]?.quantity_g &&
        part.quantity_basis === items[i]?.quantity_basis,
    )
  )
    return true
  if (
    [...text.matchAll(/\d+(?:[.,]\d+)?\s*(?:kg|quilos?|g|gr|grs|gramas?|grams?)(?![\p{L}\d])/giu)]
      .length > items.length
  )
    return false
  if (/\b(?:pela metade|a metade|menos|no sonho|sonhei|imaginei)\b/iu.test(normalized(text)))
    return false
  let rest = normalized(text)
  for (const item of items) {
    const name = normalized(item.name),
      at = rest.indexOf(name)
    if (!name || at < 0) return false
    rest = rest.slice(0, at) + ' '.repeat(name.length) + rest.slice(at + name.length)
  }
  rest = rest
    .replace(/\d+(?:[.,]\d+)?/gu, ' ')
    .replace(
      /\b(?:kg|quilos?|g|gr|grs|gramas?|grams?|ml|l|litros?|canecas?|medidas?|doses?|fatias?|unidades?|un|und|um|uma|dois|duas|tres|quatro|cinco|seis|sete|oito|nove|dez|meio|meia|de|do|da|dos|das|com|e|of|with)\b/gu,
      ' ',
    )
    .replace(/[\s,;:.!+\-/]/gu, '')
  return rest.length === 0
}
async function orderedTextEvidence(
  text: string,
  unit: Exclude<Unit, 'vision_items'>,
  owner: string,
  threshold: number,
) {
  const found: Array<{ candidate: Item; source_position: SourcePosition }> = [],
    unresolved: string[] = []
  for (const [segmentIndex, segment] of parts(text).entries()) {
    let draft: MealDraft
    try {
      draft = await createMealDraft(
        {
          media: { findOwned: async () => null },
          extractor: null,
          confidenceThreshold: async () => threshold,
        },
        owner,
        { source: 'text', text: segment },
      )
    } catch (error) {
      if (!(error instanceof MobileApiError) || error.code !== 'meal_draft_empty') throw error
      unresolved.push(segment)
      continue
    }
    if (
      !draft.items.length ||
      draft.items.some(
        (i) =>
          i.quantity_g === null ||
          i.review_reason === 'ambiguous' ||
          i.review_reason === 'low_confidence',
      ) ||
      !wholeClauseCovered(segment, draft.items)
    ) {
      unresolved.push(segment)
      continue
    }
    const original = normalized(segment)
    const ordered = draft.items
      .map((candidate, i) => ({
        candidate,
        position: original.indexOf(normalized(candidate.name)),
        fallback: i,
      }))
      .sort((a, b) => a.position - b.position || a.fallback - b.fallback)
    for (const [itemIndex, item] of ordered.entries())
      found.push({
        candidate: item.candidate,
        source_position: { unit, segment_index: segmentIndex, item_index: itemIndex },
      })
  }
  return { found, unresolved }
}
/** Positions supported food syntax. Unknown fragments remain a
 * clarification with the complete stored preparation. This is not an LLM
 * trust bit, nominal-food proof, nutrition resolver, database-origin proof or registration writer.
 * Every result has complete_source:false; the later semantic interpreter must
 * resolve actual consumption and nominal food phrases before any SQL proof. */
export async function positionConversationMealSource(
  auth: MobileAuthContext,
  bound: BoundConversationMealCommand,
  rawCandidate: unknown,
  rawObservation: unknown,
  options: { confidenceThreshold: number },
): Promise<ConversationMealSourcePositioning> {
  if ('intake_origin' in bound.command)
    throw new MobileApiError(
      409,
      'conversation_intake_projection_requires_persisted_source',
      'The original persisted intake source is required',
    )
  const who = structuredClone(auth),
    owner = authenticatedReevaluationOwner(who)
  let command: BoundConversationMealCommand
  try {
    command = bindConversationCommand(owner, `cmsg1:${bound.commandId}`, bound.command)
    if (!isDeepStrictEqual(command, bound)) changed()
  } catch {
    changed()
  }
  const envelope = parseConversationCandidate(rawCandidate, command),
    candidate = envelope.candidate
  if (candidate.status !== 'prepared')
    return detachAndFreeze({ status: candidate.status, preparation: candidate })
  let captured: z.infer<typeof observation>, threshold: number
  try {
    const originalObservation = structuredClone(rawObservation)
    captured = observation.parse(originalObservation)
    if (!isDeepStrictEqual(captured, originalObservation)) changed()
    threshold = z.number().finite().min(0).max(1).parse(options.confidenceThreshold)
  } catch {
    changed()
  }
  const c = captured.context
  if (
    c.owner_id !== owner ||
    c.command_id !== command.commandId ||
    c.input_hash !== command.inputHash ||
    !isDeepStrictEqual(c.source_input, command.command) ||
    new Set(c.source_units).size !== c.source_units.length
  )
    changed()
  const input = command.command.source
  let asset: MediaAssetRecord | null = null
  if (input.channel === 'text') {
    if (
      c.media !== null ||
      !isDeepStrictEqual(c.source_units, ['command_text']) ||
      Object.keys(c.source_evidence).length !== 0
    )
      changed()
  } else {
    const m = c.media,
      r = record(m?.processing_result)
    if (!m || m.asset_id !== input.media_asset_id) changed()
    const caption = input.caption ?? m.context_text,
      transcript = m.kind === 'audio_note' ? (typeof r?.text === 'string' ? r.text : null) : null
    const units: Unit[] = []
    if (caption !== null && caption.replace(/^ +| +$/gu, '') !== '') units.push('media_caption')
    units.push(m.kind === 'audio_note' ? 'media_transcript' : 'vision_items')
    if (
      !isDeepStrictEqual(units, c.source_units) ||
      !isDeepStrictEqual(c.source_evidence, { caption, transcript })
    )
      changed()
    if (
      !candidate.mediaBinding ||
      candidate.mediaBinding.asset_id !== m.asset_id ||
      candidate.mediaBinding.kind !== m.kind ||
      !sameCurrentClinicalInstant(candidate.mediaBinding.processed_at, m.processed_at) ||
      !sameCurrentClinicalInstant(candidate.mediaBinding.updated_at, m.updated_at)
    )
      changed()
    // These are selected fields from the actual owned SQL capture, not a
    // substitute provider or fabricated asset; omitted path columns are unused.
    asset = {
      id: m.asset_id,
      user_id: owner,
      kind: m.kind,
      status: m.status,
      processed_at: m.processed_at,
      updated_at: m.updated_at,
      context_text: m.context_text,
      processing_result: m.processing_result,
    } as MediaAssetRecord
  }
  const rebuilt = await prepareConversationMealDraft(
    {
      media: {
        findOwned: async (id, assetId) =>
          asset && id === owner && asset.id === assetId ? structuredClone(asset) : null,
      },
      extractor: null,
      confidenceThreshold: async () => threshold,
    },
    who,
    `cmsg1:${command.commandId}`,
    command.command,
  )
  const ask = (
    reason: 'unresolved_source' | 'candidate_source_mismatch',
    unresolved: readonly string[] = [],
  ): ConversationMealSourcePositioning =>
    detachAndFreeze({
      status: 'clarification_required',
      reason,
      ...(unresolved.length ? { unresolvedText: [...unresolved] } : {}),
      preparation: candidate,
    })
  if (rebuilt.status !== 'prepared') return ask('unresolved_source')
  if (
    !isDeepStrictEqual(candidate.intent, rebuilt.intent) ||
    !isDeepStrictEqual(candidate.sourceEvidence, rebuilt.sourceEvidence) ||
    !isDeepStrictEqual(candidate.mediaBinding, rebuilt.mediaBinding)
  )
    changed()
  if (
    !sameCandidates(rebuilt.draft.items, candidate.draft.items) ||
    !isDeepStrictEqual(rebuilt.draft.nutrition_label, candidate.draft.nutrition_label)
  )
    return ask('candidate_source_mismatch')
  let evidence: Array<{ candidate: Item; source_position: SourcePosition }> = []
  if (input.channel === 'text' || asset?.kind === 'audio_note') {
    const unit = input.channel === 'text' ? 'command_text' : 'media_transcript'
    const text =
      rebuilt.intent.decision === 'actual_report'
        ? rebuilt.intent.foodText
        : (rebuilt.sourceEvidence.transcript ?? '')
    const checked = await orderedTextEvidence(text, unit, owner, threshold)
    if (
      checked.unresolved.length ||
      !sameCandidates(
        checked.found.map((i) => i.candidate),
        rebuilt.draft.items,
      )
    )
      return ask('unresolved_source', checked.unresolved)
    evidence = checked.found
  } else {
    const rows = record(asset?.processing_result)?.items
    if (!Array.isArray(rows) || rows.length !== rebuilt.draft.items.length)
      return ask('unresolved_source')
    for (const [i, row] of rows.entries()) {
      const raw = record(row),
        item = rebuilt.draft.items[i]
      const name =
        typeof raw?.name === 'string' ? raw.name.replace(/^\s*\d{1,2}\s*x\s+/iu, '').trim() : ''
      if (!item || normalized(name) !== normalized(item.name)) return ask('unresolved_source')
      evidence.push({ candidate: item, source_position: { unit: 'vision_items', item_index: i } })
    }
  }
  const caption = rebuilt.sourceEvidence.caption
  if (caption?.trim() && !pointerCaption.test(normalized(caption))) {
    const intent = classifyConversationMealIntent({ channel: 'text', text: caption })
    const text = intent.decision === 'actual_report' ? intent.foodText : caption
    const checked = await orderedTextEvidence(text, 'media_caption', owner, threshold)
    if (
      checked.unresolved.length ||
      !checked.found.length ||
      checked.found.some((i) => !rebuilt.draft.items.some((item) => sameItem(item, i.candidate)))
    )
      return ask('unresolved_source', checked.unresolved)
  }
  const remaining = [...candidate.draft.items]
  const inputs = evidence.map((entry, index) => {
    const at = remaining.findIndex((i) => sameItem(entry.candidate, i))
    if (at < 0) changed()
    const [original] = remaining.splice(at, 1)
    if (!original) changed()
    return { input_index: index, candidate: original, source_position: entry.source_position }
  })
  if (!inputs.length || inputs.length > 30 || remaining.length) return ask('unresolved_source')
  return detachAndFreeze({
    status: 'positioned',
    preparation: candidate,
    inputs,
    coverage: {
      schema: 'conversation.meal-positioning.v1',
      input_hash: command.inputHash,
      source_hash: captured.sourceHash,
      complete_source: false,
      source_units: [...c.source_units],
      input_count: inputs.length,
    },
  })
}
