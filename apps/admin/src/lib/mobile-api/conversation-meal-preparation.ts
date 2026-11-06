/** Non-mutating first preparation for a command. The future permanent journal
 * must run BEFORE this service, store this result once, and fence the media
 * version at commit. This service is deliberately not installed on a route. */
import { createHash } from 'node:crypto'
import { sanitizeExtractedItems } from '@mpp/agent'
import {
  type ConversationMealIntent,
  classifyConversationMealIntent,
} from '@mpp/agent/conversation-meal-intent'
import type { MobileAuthContext } from './auth'
import type { MealDraftInput } from './contracts'
import {
  type BoundConversationMealCommand,
  bindConversationCommand,
} from './conversation-command-contracts'
import { MobileApiError } from './http'
import { createMealDraft, type MealDraft, type MealDraftDependencies } from './meal-draft-service'
import type { MediaAssetRecord } from './media-service'
import { authenticatedReevaluationOwner } from './reevaluation-cycle-service'

interface MediaBinding {
  asset_id: string
  kind: 'meal_photo' | 'audio_note'
  processed_at: string
  updated_at: string
  processing_hash: string
}
interface OversizedSourceText {
  sha256: string
  utf16_length: number
}
export interface ConversationMealSourceEvidence {
  caption: string | null
  transcript: string | null
  /** Invalid, oversized sources are never truncated into usable food reports.
   * Keep only their digest/length so a bounded clarification can be replayed. */
  oversized?: { caption?: OversizedSourceText; transcript?: OversizedSourceText }
}
export type ConversationMealPreparation =
  | {
      status: 'prepared'
      command: BoundConversationMealCommand
      intent: ConversationMealIntent
      draft: MealDraft
      mediaBinding: Readonly<MediaBinding> | null
      sourceEvidence: Readonly<ConversationMealSourceEvidence>
    }
  | {
      status: 'conversational' | 'clarification_required'
      command: BoundConversationMealCommand
      intent: ConversationMealIntent
      draft?: MealDraft
      captionDraft?: MealDraft
      preparationIssue?:
        | 'conflicting_user_sources'
        | 'unresolved_source'
        | 'missing_quantity_or_identity'
      unresolvedText?: string[]
      mediaBinding?: Readonly<MediaBinding> | null
      sourceEvidence?: Readonly<ConversationMealSourceEvidence>
    }

function jsonCanonical(value: unknown): string {
  if (value === null || typeof value === 'boolean' || typeof value === 'string')
    return JSON.stringify(value)
  if (typeof value === 'number' && Number.isFinite(value)) return JSON.stringify(value)
  if (Array.isArray(value)) return `[${value.map(jsonCanonical).join(',')}]`
  if (value && typeof value === 'object' && Object.getPrototypeOf(value) === Object.prototype)
    return `{${Object.entries(value)
      .sort(([a], [b]) => (a < b ? -1 : a > b ? 1 : 0))
      .map(([key, item]) => `${JSON.stringify(key)}:${jsonCanonical(item)}`)
      .join(',')}}`
  throw new MobileApiError(
    409,
    'conversation_media_invalid',
    'Media processing result is unavailable',
  )
}

function boundedSourceEvidence(
  caption: string | null,
  transcript: string | null,
): Readonly<ConversationMealSourceEvidence> {
  const oversized: NonNullable<ConversationMealSourceEvidence['oversized']> = {}
  const bounded = (value: string | null, key: 'caption' | 'transcript', limit: number) => {
    if (value === null || value.length <= limit) return value
    oversized[key] = Object.freeze({
      sha256: createHash('sha256').update(value).digest('hex'),
      utf16_length: value.length,
    })
    return null
  }
  const result = {
    caption: bounded(caption, 'caption', 1000),
    transcript: bounded(transcript, 'transcript', 2000),
  }
  return Object.freeze(
    Object.keys(oversized).length ? { ...result, oversized: Object.freeze(oversized) } : result,
  )
}
function stop(
  command: BoundConversationMealCommand,
  intent: ConversationMealIntent,
): ConversationMealPreparation | null {
  if (intent.decision === 'actual_report' || intent.decision === 'explicit_media_registration')
    return null
  return { status: intent.decision, command, intent }
}
const normalizeName = (s: string) =>
  s
    .normalize('NFD')
    .replace(/\p{Diacritic}/gu, '')
    .toLowerCase()
    .replace(/\s+/gu, ' ')
    .trim()
const pointerCaption =
  /^(?:(?:meu|minha|my|este|esta|esse|essa|this|a|o)\s+)?(?:almoco|jantar|cafe da manha|lanche|refeicao|prato|meal|plate|breakfast|lunch|dinner|isto|isso|it|this)$/u
function finalize(
  value: Extract<ConversationMealPreparation, { status: 'prepared' }>,
  unresolvedText: string[],
): ConversationMealPreparation {
  if (unresolvedText.length)
    return {
      ...value,
      status: 'clarification_required',
      preparationIssue: 'unresolved_source',
      unresolvedText: [...unresolvedText],
    }
  if (
    !value.draft.items.length ||
    value.draft.items.some(
      (i) =>
        i.quantity_g === null ||
        i.review_reason === 'ambiguous' ||
        i.review_reason === 'low_confidence',
    )
  )
    return {
      ...value,
      status: 'clarification_required',
      preparationIssue: 'missing_quantity_or_identity',
    }
  return value
}
function ownedProcessed(
  asset: MediaAssetRecord | null,
  owner: string,
  assetId: string,
): MediaAssetRecord & { kind: 'meal_photo' | 'audio_note'; processed_at: string } {
  if (!asset || asset.id !== assetId || asset.user_id !== owner || asset.status === 'deleted')
    throw new MobileApiError(404, 'media_asset_not_found', 'Media asset was not found')
  if (asset.kind !== 'meal_photo' && asset.kind !== 'audio_note')
    throw new MobileApiError(422, 'media_kind_not_supported', 'Media kind cannot describe a meal')
  if (asset.status !== 'processed' || !asset.processed_at || !asset.updated_at)
    throw new MobileApiError(409, 'media_not_processed', 'Media asset is not processed yet')
  // Detached before any extractor await; callbacks cannot swap this source.
  return structuredClone(asset) as MediaAssetRecord & {
    kind: 'meal_photo' | 'audio_note'
    processed_at: string
  }
}
export async function prepareConversationMealDraft(
  dependencies: MealDraftDependencies,
  auth: MobileAuthContext,
  idempotencyKey: string | null,
  raw: unknown,
): Promise<ConversationMealPreparation> {
  const owner = authenticatedReevaluationOwner(structuredClone(auth))
  const command = bindConversationCommand(owner, idempotencyKey, raw)
  const findOwned = dependencies.media.findOwned.bind(dependencies.media)
  const unresolvedText: string[] = []
  const extract = dependencies.extractor?.extract.bind(dependencies.extractor)
  const extractor = extract
    ? {
        async extract(input: { text: string; userId: string }) {
          const result = await extract(input)
          for (const fragment of input.text.split('\n').filter((s) => s.trim())) {
            if (!sanitizeExtractedItems(fragment, result.items).length)
              unresolvedText.push(fragment)
          }
          return result
        },
      }
    : null
  const threshold = dependencies.confidenceThreshold.bind(dependencies)
  const readDraft = async (
    deps: MealDraftDependencies,
    input: MealDraftInput,
  ): Promise<MealDraft> => {
    try {
      return await createMealDraft(deps, owner, input)
    } catch (error) {
      if (
        !(error instanceof MobileApiError) ||
        error.code !== 'meal_draft_empty' ||
        input.source !== 'text'
      )
        throw error
      if (!unresolvedText.length) unresolvedText.push(input.text)
      return {
        source: 'text',
        media_asset_id: null,
        transcript: null,
        context_note: null,
        items: [],
        nutrition_label: null,
        extraction: { method: 'deterministic', model: null },
      }
    }
  }
  // Neutral media requires the persisted interpreter and its actual SQL lineage.
  // This older preview helper cannot supply that authority or rename its action.
  if ('intake_origin' in command.command)
    throw new MobileApiError(
      409,
      'conversation_intake_projection_requires_persisted_source',
      'The original persisted intake source is required',
    )
  const source = command.command.source
  if (source.channel === 'text') {
    const intent = classifyConversationMealIntent({ channel: 'text', text: source.text })
    const stopped = stop(command, intent)
    if (stopped) return stopped
    if (intent.decision !== 'actual_report') throw new Error('Invalid text intent')
    const draft = await readDraft(
      { media: { findOwned }, extractor, confidenceThreshold: threshold },
      { source: 'text', text: intent.foodText },
    )
    return finalize(
      {
        status: 'prepared',
        command,
        intent,
        draft,
        mediaBinding: null,
        sourceEvidence: Object.freeze({ caption: null, transcript: null }),
      },
      unresolvedText,
    )
  }
  const asset = ownedProcessed(
    await findOwned(owner, source.media_asset_id),
    owner,
    source.media_asset_id,
  )
  const result = asset.processing_result
  const transcript =
    result &&
    typeof result === 'object' &&
    !Array.isArray(result) &&
    'text' in result &&
    typeof result.text === 'string'
      ? result.text
      : null
  const caption = source.caption ?? asset.context_text ?? undefined
  const sourceEvidence = boundedSourceEvidence(
    caption ?? null,
    asset.kind === 'audio_note' ? transcript : null,
  )
  const intent = classifyConversationMealIntent(
    asset.kind === 'audio_note'
      ? {
          channel: 'audio',
          userAction: source.user_action,
          caption,
          serverProcessedTranscript: transcript,
        }
      : { channel: 'photo', userAction: source.user_action, caption },
  )
  const stopped = stop(command, intent)
  if (stopped) return { ...stopped, sourceEvidence }
  // No storage paths, credentials, object URLs or other private asset columns
  // are retained in the version pin. Vision context cannot establish intent.
  const canonical = jsonCanonical({ result: result ?? null, context_text: asset.context_text })
  if (canonical.length > 1048576)
    throw new MobileApiError(
      409,
      'conversation_media_invalid',
      'Media processing result is unavailable',
    )
  const mediaBinding = Object.freeze({
    asset_id: asset.id,
    kind: asset.kind,
    processed_at: asset.processed_at,
    updated_at: asset.updated_at,
    processing_hash: createHash('sha256').update(canonical).digest('hex'),
  })
  const pinnedDependencies: MealDraftDependencies = {
    extractor,
    confidenceThreshold: threshold,
    media: {
      findOwned: async (userId, id) =>
        userId === owner && id === asset.id ? structuredClone(asset) : null,
    },
  }
  let draft =
    asset.kind === 'audio_note'
      ? {
          ...(await readDraft(pinnedDependencies, {
            source: 'text',
            text: intent.decision === 'actual_report' ? intent.foodText : (transcript ?? ''),
          })),
          source: 'audio' as const,
          media_asset_id: asset.id,
          transcript,
        }
      : await readDraft(pinnedDependencies, {
          source: 'media',
          media_asset_id: asset.id,
        })
  if (caption?.trim()) {
    const captionIntent = classifyConversationMealIntent({ channel: 'text', text: caption })
    const captionText =
      captionIntent.decision === 'actual_report' ? captionIntent.foodText : caption.trim()
    if (!pointerCaption.test(normalizeName(captionText))) {
      const captionDraft = await readDraft(pinnedDependencies, {
        source: 'text',
        text: captionText,
      })
      const original = draft.items
      // Resolve explicit names/quantities only on a unique exact name match.
      // Do not infer that raw means cooked, merge unrelated foods, or silently
      // replace one of two contradictory user statements (caption vs audio).
      const matches = captionDraft.items.map((item) =>
        original.filter((i) => normalizeName(i.name) === normalizeName(item.name)),
      )
      const conflict =
        matches.some((rows) => rows.length !== 1) ||
        new Set(captionDraft.items.map((i) => normalizeName(i.name))).size !==
          captionDraft.items.length ||
        (asset.kind === 'audio_note' &&
          captionDraft.items.some(
            (item, i) =>
              item.quantity_g !== null &&
              matches[i]?.[0]?.quantity_g !== null &&
              item.quantity_g !== matches[i]?.[0]?.quantity_g,
          ))
      if (conflict)
        return {
          status: 'clarification_required',
          command,
          intent,
          draft,
          captionDraft,
          preparationIssue: 'conflicting_user_sources',
          mediaBinding,
          sourceEvidence,
        }
      draft = {
        ...draft,
        items: original.map((item) => {
          const explicit = captionDraft.items.find(
            (i) => normalizeName(i.name) === normalizeName(item.name),
          )
          return explicit?.quantity_g !== null && explicit !== undefined
            ? { ...explicit, candidate_id: item.candidate_id }
            : item
        }),
      }
    }
  }
  // Draft estimates/missing/ambiguous flags remain unchanged. Nutrition and
  // specific questions are later preparation stages, not silently zero values.
  return finalize(
    { status: 'prepared', command, intent, draft, mediaBinding, sourceEvidence },
    unresolvedText,
  )
}
