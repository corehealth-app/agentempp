import { createHash } from 'node:crypto'
import { describe, expect, it } from 'vitest'
import {
  candidateAuth,
  candidateCommand,
  candidateId,
  candidateOwner,
  candidatePreparation,
} from './__fixtures__/conversation-candidate'
import {
  encodeConversationCandidate,
  parseConversationCandidate,
} from './conversation-command-candidate-contracts'
import { bindConversationCommand } from './conversation-command-contracts'
import { prepareConversationMealDraft } from './conversation-meal-preparation'
import type { MediaAssetRecord } from './media-service'

const assetId = '10000000-0000-4000-8000-000000000005'
describe('persisted candidate codec with the actual multimodal preparer', () => {
  it.each([
    'Não comi esta refeição',
    'Posso comer arroz?',
    'Comi arroz, mas não comi feijão',
  ])('retains the safe stopped intent when caption conflicts with oversized audio: %s', async (caption) => {
    const raw = {
      ...candidateCommand().command,
      source: {
        channel: 'media',
        media_asset_id: assetId,
        user_action: 'register_consumed_meal',
        caption,
      },
    }
    const row = {
      id: assetId,
      user_id: candidateOwner,
      kind: 'audio_note',
      status: 'processed',
      processed_at: '2026-11-03T10:00:00Z',
      updated_at: '2026-11-03T10:00:00Z',
      context_text: null,
      processing_result: { text: 'x'.repeat(2001) },
    } as MediaAssetRecord
    const bound = bindConversationCommand(candidateOwner, `cmsg1:${candidateId}`, raw)
    const p = await prepareConversationMealDraft(
      {
        media: { findOwned: async () => row },
        extractor: null,
        confidenceThreshold: async () => 0.6,
      },
      candidateAuth,
      `cmsg1:${candidateId}`,
      raw,
    )
    expect(['conversational', 'clarification_required']).toContain(p.status)
    expect(encodeConversationCandidate(bound, p).candidate).toEqual(p)
    expect(p).not.toHaveProperty('draft')
    expect(p).not.toHaveProperty('captionDraft')
  })
  it.each([
    '',
    ' ',
    'x'.repeat(2001),
    ' '.repeat(150000),
  ])('persists missing/oversized audio as one bounded clarification, never truncated food', async (transcript) => {
    const raw = {
      ...candidateCommand().command,
      source: { channel: 'media', media_asset_id: assetId, user_action: 'register_consumed_meal' },
    }
    const row = {
      id: assetId,
      user_id: candidateOwner,
      kind: 'audio_note',
      status: 'processed',
      processed_at: '2026-11-03T10:00:00Z',
      updated_at: '2026-11-03T10:00:00Z',
      context_text: null,
      processing_result: { text: transcript },
    } as MediaAssetRecord
    const bound = bindConversationCommand(candidateOwner, `cmsg1:${candidateId}`, raw)
    const p = await prepareConversationMealDraft(
      {
        media: { findOwned: async () => row },
        extractor: null,
        confidenceThreshold: async () => 0.6,
      },
      candidateAuth,
      `cmsg1:${candidateId}`,
      raw,
    )
    expect(p.status).toBe('clarification_required')
    const encoded = encodeConversationCandidate(bound, p)
    expect(encoded.candidate).toEqual(p)
    expect(parseConversationCandidate(JSON.parse(JSON.stringify(encoded)), bound)).toEqual(encoded)
    if (transcript.length > 2000) {
      expect(encoded.candidate.sourceEvidence).toEqual({
        caption: null,
        transcript: null,
        oversized: {
          transcript: {
            utf16_length: transcript.length,
            sha256: createHash('sha256').update(transcript).digest('hex'),
          },
        },
      })
      expect(Buffer.byteLength(JSON.stringify(encoded))).toBeLessThan(4096)
    } else expect(encoded.candidate.sourceEvidence).toEqual({ caption: null, transcript })
  })
  it.each([
    '',
    'x'.repeat(1001),
  ])('persists empty/oversized owned photo captions safely', async (caption) => {
    const raw = {
      ...candidateCommand().command,
      source: { channel: 'media', media_asset_id: assetId, user_action: 'register_consumed_meal' },
    }
    const row = {
      id: assetId,
      user_id: candidateOwner,
      kind: 'meal_photo',
      status: 'processed',
      processed_at: '2026-11-03T10:00:00Z',
      updated_at: '2026-11-03T10:00:00Z',
      context_text: caption,
      processing_result: { items: [{ name: 'arroz', quantity_g_estimate: 200, confidence: 0.9 }] },
    } as MediaAssetRecord
    const bound = bindConversationCommand(candidateOwner, `cmsg1:${candidateId}`, raw)
    const p = await prepareConversationMealDraft(
      {
        media: { findOwned: async () => row },
        extractor: null,
        confidenceThreshold: async () => 0.6,
      },
      candidateAuth,
      `cmsg1:${candidateId}`,
      raw,
    )
    expect(p.status).toBe(caption.length ? 'clarification_required' : 'prepared')
    expect(encodeConversationCandidate(bound, p).candidate).toEqual(p)
  })
  it.each([
    'Comi arroz 200 g; feijão 100 g',
    'Tomei 1 caneca de leite com uma medida de whey',
    'Comi arroz',
    'Vou comer arroz',
    'Comi arroz, mas não comi feijão',
  ])('keeps exact prepared or clarified source facts through JSON replay: %s', async (text) => {
    const raw = { ...candidateCommand().command, source: { channel: 'text', text } }
    const bound = bindConversationCommand(candidateOwner, `cmsg1:${candidateId}`, raw)
    const p = await prepareConversationMealDraft(
      {
        media: { findOwned: async () => null },
        extractor: null,
        confidenceThreshold: async () => 0.6,
      },
      candidateAuth,
      `cmsg1:${candidateId}`,
      raw,
    )
    const envelope = encodeConversationCandidate(bound, p)
    expect(envelope.candidate).toEqual(p)
    expect(parseConversationCandidate(JSON.parse(JSON.stringify(envelope)), bound)).toEqual(
      envelope,
    )
  })
  it.each([
    'Comi arroz 100 g',
    'Comi arroz cru 100 g',
    'Não comi esta refeição',
  ])('keeps real photo caption, override and conflict results: %s', async (caption) => {
    const raw = {
      ...candidateCommand().command,
      source: { channel: 'media', media_asset_id: assetId, user_action: 'register_consumed_meal' },
    }
    const row = {
      id: assetId,
      user_id: candidateOwner,
      kind: 'meal_photo',
      status: 'processed',
      processed_at: '2026-11-03T10:00:00Z',
      updated_at: '2026-11-03T10:00:00Z',
      context_text: caption,
      processing_result: { items: [{ name: 'arroz', quantity_g_estimate: 200, confidence: 0.9 }] },
    } as MediaAssetRecord
    const bound = bindConversationCommand(candidateOwner, `cmsg1:${candidateId}`, raw)
    const p = await prepareConversationMealDraft(
      {
        media: { findOwned: async () => row },
        extractor: null,
        confidenceThreshold: async () => 0.6,
      },
      candidateAuth,
      `cmsg1:${candidateId}`,
      raw,
    )
    expect(encodeConversationCandidate(bound, p).candidate).toEqual(p)
  })
  it('keeps audio transcript and reference milk/scoop quantities without another conversion', async () => {
    const raw = {
      ...candidateCommand().command,
      source: { channel: 'media', media_asset_id: assetId, user_action: 'register_consumed_meal' },
    }
    const row = {
      id: assetId,
      user_id: candidateOwner,
      kind: 'audio_note',
      status: 'processed',
      processed_at: '2026-11-03T10:00:00Z',
      updated_at: '2026-11-03T10:00:00Z',
      context_text: null,
      processing_result: { text: 'Tomei 1 caneca de leite com uma medida de whey' },
    } as MediaAssetRecord
    const bound = bindConversationCommand(candidateOwner, `cmsg1:${candidateId}`, raw)
    const p = await prepareConversationMealDraft(
      {
        media: { findOwned: async () => row },
        extractor: null,
        confidenceThreshold: async () => 0.6,
      },
      candidateAuth,
      `cmsg1:${candidateId}`,
      raw,
    )
    const result = encodeConversationCandidate(bound, p)
    if (result.candidate.status !== 'prepared') throw new Error('fixture')
    expect(result.candidate.draft.items).toMatchObject([
      { quantity_g: 206, quantity_display: { unit: 'mL' } },
      { quantity_g: 30, quantity_display: { unit: 'scoop' } },
    ])
    expect(parseConversationCandidate(JSON.parse(JSON.stringify(result)), bound)).toEqual(result)
  })
  it('never accepts hidden authority fields or a version it cannot read', () => {
    const bound = candidateCommand(),
      result = encodeConversationCandidate(bound, candidatePreparation())
    for (const bad of [
      { ...result, schema: 'conversation.meal-candidate.v99' },
      { ...result, candidate: { ...result.candidate, resolved_meal: { kcal: 123 } } },
      {
        ...result,
        candidate: {
          ...result.candidate,
          intent: { ...result.candidate.intent, complete_source: true },
        },
      },
    ])
      expect(() => parseConversationCandidate(bad, bound)).toThrow('temporarily unavailable')
  })
})
