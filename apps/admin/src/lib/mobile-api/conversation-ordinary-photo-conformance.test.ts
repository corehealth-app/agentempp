/** Actual local PostgreSQL capture/seal output, not a client-authored origin. */
import type { ServiceClient } from '@mpp/db'
import { describe, expect, it } from 'vitest'
import { z } from 'zod'
import actual from './__fixtures__/conversation-ordinary-photo-actual.json'
import { bindConversationCommand } from './conversation-command-contracts'
import {
  bindConversationIntake,
  parseConversationIntakeSelection,
} from './conversation-intake-contracts'
import { buildConversationMealInterpretationSource } from './conversation-meal-interpretation-contracts'
import { createSupabaseConversationMealSourceFactory } from './conversation-meal-source'
import { parseConversationMealStoredSource } from './conversation-meal-writer-contracts'
import { resolveConversationWorkoutReport } from './conversation-workout-authority'
import {
  bindConversationWorkoutCommand,
  parseConversationWorkoutSource,
  workoutDigest,
} from './conversation-workout-contracts'

describe('ordinary-purpose original photo travels through genuine neutral and typed captures', () => {
  for (const row of actual.cases)
    it(row.kind, async () => {
      const raw = row.selection.selection,
        child = raw.command,
        input = child.input,
        owner = raw.intake.owner_id,
        parent = bindConversationIntake(owner, `cintake1:${raw.intake.intake_id}`, {
          intake_protocol: 'conversation.intake.v1',
          intake_id: raw.intake.intake_id,
          source: input.source,
        }),
        selection = parseConversationIntakeSelection(parent, raw.intake, raw)
      expect(selection.media_projection?.media.kind).toBe('conversation_photo')
      if (child.kind === 'meal.report') {
        const command = bindConversationCommand(owner, `cmsg1:${child.command_id}`, input),
          db = { rpc: async () => ({ data: row.source, error: null }) } as unknown as ServiceClient,
          source = await createSupabaseConversationMealSourceFactory(db).capture(command),
          packet = buildConversationMealInterpretationSource(command, source)
        const visual = packet.sources.find((x) => x.unit === 'vision_items')?.visual_items
        const analysis = row.source.context.media.processing_result.analysis
        if ('product_name' in analysis) {
          expect(visual).toEqual([
            {
              name: analysis.product_name,
              quantity_g_estimate: 0,
              confidence: analysis.confidence,
            },
          ])
        } else {
          if (!Array.isArray(analysis.items)) throw new Error('Missing actual meal observations')
          expect(visual).toEqual(analysis.items.length ? analysis.items : undefined)
          if (analysis.items.length === 0) {
            const unit =
              row.kind === 'ordinary_meal_context_only' ? 'media_context' : 'media_caption'
            expect(packet.source_units).toEqual([unit])
            expect(packet.sources).toEqual([{ unit, text: 'Comi arroz 100 g', visual_items: [] }])
          }
        }
        expect(
          parseConversationMealStoredSource(source, command).context.media?.processing_result,
        ).toEqual(row.source.context.media.processing_result)
        expect(source.context.media?.kind).toBe('conversation_photo')
      } else {
        const command = bindConversationWorkoutCommand(owner, `cmsg1:${child.command_id}`, input),
          source = parseConversationWorkoutSource(command, row.source),
          report = resolveConversationWorkoutReport(source)
        expect(source.context.media?.kind).toBe('conversation_photo')
        expect(source.sources).toEqual([])
        expect(report).toMatchObject({ status: 'needs_reply', question: { field: 'activity' } })
      }
    })
})

describe('ordinary classified media cannot borrow legacy admission or another domain', () => {
  it('refuses an equipment envelope in a meal capture even with a recomputed processing hash', async () => {
    const row = actual.cases.find((x) => x.kind === 'ordinary_meal')
    if (!row) throw new Error('Missing actual ordinary-meal fixture')
    const child = row.selection.selection.command
    const command = bindConversationCommand(
      child.owner_id,
      `cmsg1:${child.command_id}`,
      child.input,
    )
    const source = z.record(z.unknown()).parse(structuredClone(row.source))
    const context = z.record(z.unknown()).parse(source.context)
    const media = z.record(z.unknown()).parse(context.media)
    media.processing_result = {
      schema: 'conversation.image-result.v1',
      status: 'ready',
      classification: 'equipment',
      analysis: { type: 'equipment', equipment: [], location: null, confidence: 0.9 },
    }
    const projection = z.record(z.unknown()).parse(context.intake_projection)
    const proof = z.record(z.unknown()).parse(projection.media)
    proof.processing_hash = workoutDigest({
      context_text: media.context_text,
      processing_result: media.processing_result,
    })
    projection.media = proof
    context.media = media
    context.intake_projection = projection
    source.context = context
    const db = { rpc: async () => ({ data: source, error: null }) } as unknown as ServiceClient
    await expect(
      createSupabaseConversationMealSourceFactory(db).capture(command),
    ).rejects.toMatchObject({ code: 'conversation_meal_source_unavailable' })
  })
})

it('keeps a genuine caption-only ordinary source usable by the persisted writer decoder', async () => {
  const row = actual.cases.find((x) => x.kind === 'ordinary_meal_caption_only')
  if (!row) throw new Error('Missing actual SQL case')
  const child = row.selection.selection.command,
    command = bindConversationCommand(
      row.selection.selection.intake.owner_id,
      `cmsg1:${child.command_id}`,
      child.input,
    ),
    db = { rpc: async () => ({ data: row.source, error: null }) } as unknown as ServiceClient,
    source = await createSupabaseConversationMealSourceFactory(db).capture(command)
  expect(parseConversationMealStoredSource(source, command).context.source_units).toEqual([
    'media_caption',
  ])
})
