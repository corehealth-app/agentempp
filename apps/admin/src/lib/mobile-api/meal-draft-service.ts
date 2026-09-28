import {
  buildDraftCandidates,
  draftFromStatedText,
  draftFromVisionItems,
  labelCandidateId,
  MEAL_DRAFT_MAX_TEXT_LENGTH,
  type MealDraftCandidate,
  type MealDraftRawItem,
  parseCountedSegment,
  sanitizeExtractedItems,
} from '@mpp/agent'
import type { MealDraftInput } from './contracts'
import { MobileApiError } from './http'
import type { MediaAssetRecord, MediaAssetRepository } from './media-service'

// Candidates for review, never nutrition. Text the deterministic parser does
// not read goes to an extractor WITHOUT tools; its output is treated as
// untrusted data (quantities must be in the patient's own words). Without an
// extractor the same segments are read word by word. Either way a quantity
// that was not said, seen or covered by an existing portion reference stays
// missing.

export interface MealTextExtraction {
  items: unknown
  model: string
}

export interface MealTextExtractor {
  /** Returns the raw structured output; throws on provider failure. */
  extract(input: { text: string; userId: string }): Promise<MealTextExtraction>
}

export interface MealDraftDependencies {
  media: Pick<MediaAssetRepository, 'findOwned'>
  extractor: MealTextExtractor | null
  confidenceThreshold: () => Promise<number>
}

export const DEFAULT_MEAL_CONFIDENCE_THRESHOLD = 0.6

type DraftSource = 'text' | 'photo' | 'audio'

interface NutritionLabelDraft {
  product_name: string | null
  serving_size_g: number | null
  per_serving: Record<string, number | null> | null
  per_100g: Record<string, number | null> | null
  confidence: number | null
  applies_to_candidate_id: string | null
}

export interface MealDraft {
  source: DraftSource
  media_asset_id: string | null
  transcript: string | null
  context_note: string | null
  items: MealDraftCandidate[]
  nutrition_label: NutritionLabelDraft | null
  extraction: { method: 'deterministic' | 'vision' | 'llm_text'; model: string | null }
}

function record(value: unknown): Record<string, unknown> | null {
  return typeof value === 'object' && value !== null && !Array.isArray(value)
    ? (value as Record<string, unknown>)
    : null
}

function text(value: unknown, maxLength: number): string | null {
  return typeof value === 'string' && value.trim() ? value.trim().slice(0, maxLength) : null
}

function number(value: unknown): number | null {
  return typeof value === 'number' && Number.isFinite(value) && value >= 0 ? value : null
}

function macros(value: unknown): Record<string, number | null> | null {
  const source = record(value)
  if (!source) return null
  return {
    kcal: number(source.kcal),
    protein_g: number(source.protein_g),
    carbs_g: number(source.carbs_g),
    fat_g: number(source.fat_g),
  }
}

async function draftFromText(
  deps: MealDraftDependencies,
  userId: string,
  sourceText: string,
  source: DraftSource,
): Promise<Pick<MealDraft, 'items' | 'extraction'>> {
  const { raw, rest } = draftFromStatedText(sourceText)
  if (rest.length === 0) {
    return { items: buildDraftCandidates(raw), extraction: { method: 'deterministic', model: null } }
  }

  if (deps.extractor) {
    const remaining = rest.join('\n')
    let extraction: MealTextExtraction
    try {
      extraction = await deps.extractor.extract({ text: remaining, userId })
    } catch {
      throw new MobileApiError(502, 'meal_extraction_failed', 'Meal extraction failed')
    }
    const extracted = sanitizeExtractedItems(remaining, extraction.items)
    void source
    return {
      items: buildDraftCandidates([...raw, ...extracted]),
      extraction: { method: 'llm_text', model: extraction.model },
    }
  }

  const counted = rest
    .map(parseCountedSegment)
    .filter((item): item is MealDraftRawItem => item !== null)
  return {
    items: buildDraftCandidates([...raw, ...counted]),
    extraction: { method: 'deterministic', model: null },
  }
}

function requireProcessed(asset: MediaAssetRecord | null): MediaAssetRecord {
  if (!asset || asset.status === 'deleted') {
    throw new MobileApiError(404, 'media_asset_not_found', 'Media asset was not found')
  }
  if (asset.kind !== 'meal_photo' && asset.kind !== 'audio_note') {
    throw new MobileApiError(422, 'media_kind_not_supported', 'Media kind cannot describe a meal')
  }
  if (asset.status !== 'processed') {
    throw new MobileApiError(409, 'media_not_processed', 'Media asset is not processed yet')
  }
  return asset
}

export async function createMealDraft(
  deps: MealDraftDependencies,
  userId: string,
  input: MealDraftInput,
): Promise<MealDraft> {
  if (input.source === 'text') {
    const draft = await draftFromText(deps, userId, input.text, 'text')
    if (draft.items.length === 0) {
      throw new MobileApiError(422, 'meal_draft_empty', 'No food could be read from the text')
    }
    return {
      source: 'text',
      media_asset_id: null,
      transcript: null,
      context_note: null,
      nutrition_label: null,
      ...draft,
    }
  }

  const asset = requireProcessed(await deps.media.findOwned(userId, input.media_asset_id))
  const result = record(asset.processing_result)

  if (asset.kind === 'audio_note') {
    const transcript = text(result?.text, MEAL_DRAFT_MAX_TEXT_LENGTH)
    if (!transcript) {
      throw new MobileApiError(422, 'meal_draft_empty', 'The recording has no speech to read')
    }
    const draft = await draftFromText(deps, userId, transcript, 'audio')
    return {
      source: 'audio',
      media_asset_id: asset.id,
      transcript,
      context_note: null,
      nutrition_label: null,
      ...draft,
    }
  }

  const items = draftFromVisionItems(result?.items, await deps.confidenceThreshold())
  const label = record(result?.nutrition_label)
  const productName = text(label?.product_name, 160)
  return {
    source: 'photo',
    media_asset_id: asset.id,
    transcript: null,
    context_note: text(result?.meal_context, 500),
    items,
    nutrition_label: label
      ? {
          product_name: productName,
          serving_size_g: number(label.serving_size_g),
          per_serving: macros(label.per_serving),
          per_100g: macros(label.per_100g),
          confidence: number(label.confidence),
          applies_to_candidate_id: labelCandidateId(items, productName),
        }
      : null,
    extraction: { method: 'vision', model: null },
  }
}
