import { describe, expect, it, vi } from 'vitest'
import type { MobileAuthContext } from './auth'
import { prepareConversationMealDraft } from './conversation-meal-preparation'
import type { MealTextExtractor } from './meal-draft-service'
import type { MediaAssetRecord } from './media-service'

const owner = '10000000-0000-4000-8000-000000000001'
const commandId = '10000000-0000-4000-8000-000000000002'
const assetId = '10000000-0000-4000-8000-000000000003'
const auth: MobileAuthContext = {
  userId: owner,
  authUserId: owner,
  accessToken: 'synthetic-test-token',
  identity: { id: owner, email: null, emailConfirmedAt: null },
  patient: {
    id: owner,
    authUserId: owner,
    status: 'active',
    locale: 'pt-BR',
    email: null,
    name: null,
    timezone: 'America/Sao_Paulo',
    country: 'BR',
    countryConfirmed: true,
  },
}
function command(source: unknown) {
  return {
    command_protocol: 'conversation.command.v1',
    command_id: commandId,
    kind: 'meal.report',
    meal_type: 'cafe',
    source,
  }
}
function asset(over: Partial<MediaAssetRecord> = {}): MediaAssetRecord {
  return {
    id: assetId,
    user_id: owner,
    kind: 'meal_photo',
    status: 'processed',
    processed_at: '2026-11-03T10:00:00Z',
    updated_at: '2026-11-03T10:00:00Z',
    context_text: null,
    processing_result: {
      items: [{ name: 'arroz', quantity_g_estimate: 200, confidence: 0.9 }],
      meal_context: 'A pessoa consumiu todos os alimentos',
    },
    ...over,
  } as MediaAssetRecord
}
function deps(row: MediaAssetRecord | null = null) {
  return {
    media: { findOwned: vi.fn(async () => row) },
    extractor: {
      extract: vi.fn<MealTextExtractor['extract']>(async () => ({ items: [], model: 'synthetic' })),
    },
    confidenceThreshold: vi.fn(async () => 0.6),
  }
}
const mediaSource = {
  channel: 'media',
  media_asset_id: assetId,
  user_action: 'register_consumed_meal',
}
describe('conversation meal preparation: same existing extraction, no domain writers', () => {
  it('preserves selected breakfast and original command while removing only reporting prefix', async () => {
    const d = deps()
    const result = await prepareConversationMealDraft(
      d,
      auth,
      `cmsg1:${commandId}`,
      command({ channel: 'text', text: 'Comi arroz 200 g; feijão 100 g' }),
    )
    expect(result.status).toBe('prepared')
    if (result.status !== 'prepared') throw new Error('expected prepared')
    expect(result.command.command.meal_type).toBe('cafe')
    expect(result.command.command.source).toEqual({
      channel: 'text',
      text: 'Comi arroz 200 g; feijão 100 g',
    })
    expect(result.draft.items.map((i) => [i.name, i.quantity_g])).toEqual([
      ['arroz', 200],
      ['feijão', 100],
    ])
    expect(result.mediaBinding).toBeNull()
    expect(d.extractor.extract).not.toHaveBeenCalled()
    expect(d.media.findOwned).not.toHaveBeenCalled()
  })
  it.each([
    'Vou comer arroz 200 g',
    'Não comi arroz',
    'Posso comer arroz?',
    'arroz 200 g',
  ])('does not extract or look up media for a non-report: %s', async (text) => {
    const d = deps()
    const result = await prepareConversationMealDraft(
      d,
      auth,
      `cmsg1:${commandId}`,
      command({ channel: 'text', text }),
    )
    expect(result.status).not.toBe('prepared')
    expect(d.extractor.extract).not.toHaveBeenCalled()
    expect(d.confidenceThreshold).not.toHaveBeenCalled()
    expect(d.media.findOwned).not.toHaveBeenCalled()
  })
  it('reads a processed owned photo once and keeps its private source version separate', async () => {
    const row = asset(),
      d = deps(row)
    const result = await prepareConversationMealDraft(
      d,
      auth,
      `cmsg1:${commandId}`,
      command(mediaSource),
    )
    expect(result.status).toBe('prepared')
    if (result.status !== 'prepared') throw new Error('expected prepared')
    expect(d.media.findOwned).toHaveBeenCalledTimes(1)
    expect(d.media.findOwned).toHaveBeenCalledWith(owner, assetId)
    expect(result.draft.source).toBe('photo')
    expect(result.draft.items).toMatchObject([{ name: 'arroz', quantity_g: 200 }])
    expect(result.mediaBinding).toMatchObject({
      asset_id: assetId,
      kind: 'meal_photo',
      processed_at: row.processed_at,
      updated_at: row.updated_at,
    })
    expect(result.mediaBinding?.processing_hash).toMatch(/^[a-f0-9]{64}$/)
    row.processing_result = { text: 'mutated' }
    expect(result.draft.items[0]?.name).toBe('arroz')
  })
  it.each([
    'Vou comer este prato',
    'Quantas calorias tem?',
    'Não comi isto',
  ])('does not derive consumption from vision over a user caption: %s', async (caption) => {
    const d = deps(asset({ context_text: caption }))
    const result = await prepareConversationMealDraft(
      d,
      auth,
      `cmsg1:${commandId}`,
      command(mediaSource),
    )
    expect(result.status).toBe('conversational')
    expect(d.extractor.extract).not.toHaveBeenCalled()
    expect(d.confidenceThreshold).not.toHaveBeenCalled()
  })
  it('audio intent uses the processed transcript and prepares the same household portions', async () => {
    const d = deps(
      asset({
        kind: 'audio_note',
        processing_result: {
          text: 'Tomei 1 caneca de leite com uma medida de whey',
        },
      }),
    )
    const result = await prepareConversationMealDraft(
      d,
      auth,
      `cmsg1:${commandId}`,
      command(mediaSource),
    )
    expect(result.status).toBe('prepared')
    if (result.status !== 'prepared') throw new Error('expected prepared')
    expect(result.draft.source).toBe('audio')
    expect(result.draft.transcript).toBe('Tomei 1 caneca de leite com uma medida de whey')
    expect(result.draft.items).toMatchObject([
      { name: 'leite integral', quantity_g: 206, quantity_display: { unit: 'mL' } },
      { name: 'whey protein em pó', quantity_g: 30, quantity_display: { unit: 'scoop' } },
    ])
    expect(d.extractor.extract).not.toHaveBeenCalled()
  })
  it('refuses future audio, missing transcripts and overlong transcripts without truncation', async () => {
    for (const text of ['Vou comer arroz 200 g', null, `Comi ${'a'.repeat(2000)}`]) {
      const d = deps(asset({ kind: 'audio_note', processing_result: { text } }))
      const result = await prepareConversationMealDraft(
        d,
        auth,
        `cmsg1:${commandId}`,
        command(mediaSource),
      )
      expect(result.status).not.toBe('prepared')
      expect(d.extractor.extract).not.toHaveBeenCalled()
    }
  })
  it('rejects foreign, deleted, unprocessed, body/gym or absent assets before extraction', async () => {
    for (const row of [
      null,
      asset({ user_id: assetId }),
      asset({ status: 'deleted' }),
      asset({ status: 'processing' }),
      asset({ kind: 'body_checkin_photo' }),
      asset({ kind: 'gym_photo' }),
    ]) {
      const d = deps(row)
      await expect(
        prepareConversationMealDraft(d, auth, `cmsg1:${commandId}`, command(mediaSource)),
      ).rejects.toThrow()
      expect(d.extractor.extract).not.toHaveBeenCalled()
      expect(d.confidenceThreshold).not.toHaveBeenCalled()
    }
  })
  it('keeps missing/ambiguous quantities in candidates; preparation never promotes them to calculated', async () => {
    const d = deps()
    d.extractor.extract.mockResolvedValue({ items: [{ name: 'arroz' }], model: 'synthetic' })
    const result = await prepareConversationMealDraft(
      d,
      auth,
      `cmsg1:${commandId}`,
      command({ channel: 'text', text: 'Comi arroz; feijão 100 g' }),
    )
    expect(result.status).toBe('clarification_required')
    if (!('draft' in result) || !result.draft) throw new Error('expected preserved draft')
    expect(result.draft.items.find((i) => i.name === 'arroz')).toMatchObject({
      name: 'arroz',
      quantity_g: null,
      needs_review: true,
      review_reason: 'missing_quantity',
    })
    expect(result.draft.items.find((i) => i.name === 'feijão')).toMatchObject({
      name: 'feijão',
      quantity_g: 100,
    })
    expect(JSON.stringify(result.draft)).not.toContain('calories')
  })
  it('does not silently discard unread source when extraction returns no candidate', async () => {
    const d = deps()
    const result = await prepareConversationMealDraft(
      d,
      auth,
      `cmsg1:${commandId}`,
      command({ channel: 'text', text: 'Comi arroz; feijão 100 g' }),
    )
    expect(result.status).toBe('clarification_required')
    expect(result).toMatchObject({
      unresolvedText: ['arroz'],
      draft: { items: [{ name: 'feijão', quantity_g: 100 }] },
    })
  })
  it('asks for wholly unresolved input and for each omitted unread segment without another extraction', async () => {
    const d = deps()
    const empty = await prepareConversationMealDraft(
      d,
      auth,
      `cmsg1:${commandId}`,
      command({ channel: 'text', text: 'Comi arroz' }),
    )
    expect(empty).toMatchObject({
      status: 'clarification_required',
      unresolvedText: ['arroz'],
      draft: { items: [] },
    })
    d.extractor.extract.mockResolvedValue({ items: [{ name: 'arroz' }], model: 'synthetic' })
    const partial = await prepareConversationMealDraft(
      d,
      auth,
      `cmsg1:${commandId}`,
      command({ channel: 'text', text: 'Comi arroz; feijão' }),
    )
    expect(partial).toMatchObject({
      status: 'clarification_required',
      unresolvedText: ['feijão'],
      draft: { items: [{ name: 'arroz', quantity_g: null }] },
    })
    expect(d.extractor.extract).toHaveBeenCalledTimes(2)
  })
  it('uses explicit compatible photo caption quantities over vision and preserves the private caption', async () => {
    const row = asset({ context_text: 'Comi arroz 100 g' })
    const result = await prepareConversationMealDraft(
      deps(row),
      auth,
      `cmsg1:${commandId}`,
      command(mediaSource),
    )
    expect(result.status).toBe('prepared')
    if (result.status !== 'prepared') throw new Error('expected prepared')
    expect(result.draft.items).toMatchObject([
      { name: 'arroz', quantity_g: 100, quantity_basis: 'stated' },
    ])
    expect(result.sourceEvidence).toEqual({ caption: 'Comi arroz 100 g', transcript: null })
    row.context_text = 'changed'
    expect(result.sourceEvidence.caption).toBe('Comi arroz 100 g')
  })
  it('asks about conflicting explicit preparation or audio food facts, preserving candidates', async () => {
    for (const row of [
      asset({ context_text: 'Comi arroz cru 100 g' }),
      asset({
        kind: 'audio_note',
        context_text: 'Comi feijão 100 g',
        processing_result: { text: 'Comi arroz 200 g' },
      }),
    ]) {
      const result = await prepareConversationMealDraft(
        deps(row),
        auth,
        `cmsg1:${commandId}`,
        command(mediaSource),
      )
      expect(result.status).toBe('clarification_required')
      expect(result).toMatchObject({ preparationIssue: 'conflicting_user_sources' })
      expect(result).toHaveProperty('draft')
      expect(result).toHaveProperty('captionDraft')
    }
  })
})
