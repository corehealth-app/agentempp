import type { ServiceClient } from '@mpp/db'
import { describe, expect, it, vi } from 'vitest'
import { replyFixture } from './__fixtures__/conversation-meal-reply'
import { writerSource } from './__fixtures__/conversation-meal-writer'
import { bindConversationCommand } from './conversation-command-contracts'
import { buildConversationMealInterpretationSource } from './conversation-meal-interpretation-contracts'
import { prepareConversationMealDraft } from './conversation-meal-preparation'
import { createSupabaseConversationMealSourceFactory } from './conversation-meal-source'
import { positionConversationMealSource } from './conversation-meal-source-positioning'
import { parseConversationMealStoredSource } from './conversation-meal-writer-contracts'
import { resolveConversationWorkoutReport } from './conversation-workout-authority'
import {
  bindConversationWorkoutCommand,
  parseConversationWorkoutSource,
  workoutDigest,
} from './conversation-workout-contracts'

const id = 'c3cc0000-0000-4000-8000-000000000044',
  child = 'c3cc0000-0000-4000-8000-000000000045',
  asset = 'c3cc0000-0000-4000-8000-000000000046',
  claim = 'c3cc0000-0000-4000-8000-000000000048'
function fixture<const Kind extends 'meal.report' | 'workout.report'>(kind: Kind) {
  const f = replyFixture(),
    owner = f.auth.userId,
    epoch = f.profile.epoch as string,
    origin = {
      schema: 'conversation.intake-media-origin.v1' as const,
      intake_id: id,
      input_hash: 'a'.repeat(64),
      source_hash: 'b'.repeat(64),
      epoch,
      claim_id: claim,
      decision_hash: 'c'.repeat(64),
    },
    input = {
      command_protocol: 'conversation.command.v1' as const,
      command_id: child,
      kind,
      source: {
        channel: 'media' as const,
        media_asset_id: asset,
        user_action: 'report_actual_record' as const,
        caption: kind === 'meal.report' ? 'Comi arroz 100 g' : 'Fiz 30 minutos de caminhada leve',
      },
      intake_origin: origin,
    },
    media = {
      asset_id: asset,
      owner_id: owner,
      kind: 'audio_note' as const,
      status: 'processed' as const,
      processed_at: f.profile.observed_at,
      updated_at: f.profile.observed_at,
      context_text: kind === 'meal.report' ? 'Comi feijão 100 g' : 'Não fiz caminhada',
      processing_result: { text: input.source.caption },
    },
    projection = {
      schema: 'conversation.intake-media-projection.v1' as const,
      origin,
      media: {
        asset_id: asset,
        owner_id: owner,
        kind: media.kind,
        processed_at: media.processed_at,
        updated_at: media.updated_at,
        processing_hash: workoutDigest({
          context_text: media.context_text,
          processing_result: media.processing_result,
        }),
      },
      child_input_hash: workoutDigest(input),
    }
  return { f, owner, epoch, input, media, projection }
}
describe('actual typed captures of a sealed neutral-media child', () => {
  async function meal() {
    const f = fixture('meal.report'),
      command = bindConversationCommand(f.owner, `cmsg1:${child}`, f.input),
      context = {
        ...writerSource().context,
        schema: 'conversation.meal-source.v2' as const,
        owner_id: f.owner,
        command_id: child,
        input_hash: command.inputHash,
        epoch: f.epoch,
        source_input: f.input,
        source_units: ['media_caption', 'media_context', 'media_transcript'] as (
          | 'media_caption'
          | 'media_context'
          | 'media_transcript'
        )[],
        source_evidence: {
          caption: f.input.source.caption,
          context_text: f.media.context_text,
          transcript: f.media.processing_result.text,
        },
        media: f.media,
        intake_projection: f.projection,
      },
      raw = {
        action: 'captured',
        source_hash: 'd'.repeat(64),
        captured_at: f.f.profile.observed_at,
        context,
      },
      db = { rpc: async () => ({ data: raw, error: null }) } as unknown as ServiceClient
    return {
      ...f,
      command,
      raw,
      source: await createSupabaseConversationMealSourceFactory(db).capture(command),
    }
  }
  it('carries caption, asset context and transcript independently into the real meal interpreter and writer decoders', async () => {
    const f = await meal(),
      interpreted = buildConversationMealInterpretationSource(f.command, f.source)
    expect(interpreted.sources.map((value) => [value.unit, value.text])).toEqual([
      ['media_caption', 'Comi arroz 100 g'],
      ['media_context', 'Comi feijão 100 g'],
      ['media_transcript', 'Comi arroz 100 g'],
    ])
    expect(
      parseConversationMealStoredSource(
        {
          sourceHash: f.raw.source_hash,
          capturedAt: f.raw.captured_at,
          epoch: f.epoch,
          context: f.raw.context,
        },
        f.command,
      ).context.schema,
    ).toBe('conversation.meal-source.v2')
  })
  it('keeps the older preview and positioning helpers from relabeling neutral media into typed user intent', async () => {
    const f = await meal(),
      findOwned = vi.fn(),
      d = { media: { findOwned }, extractor: null, confidenceThreshold: async () => 0.6 }
    await expect(
      prepareConversationMealDraft(d, f.f.auth, `cmsg1:${child}`, f.input),
    ).rejects.toMatchObject({ code: 'conversation_intake_projection_requires_persisted_source' })
    await expect(
      positionConversationMealSource(f.f.auth, f.command, {}, {}, { confidenceThreshold: 0.6 }),
    ).rejects.toMatchObject({ code: 'conversation_intake_projection_requires_persisted_source' })
    expect(findOwned).not.toHaveBeenCalled()
  })
  it('refuses media content changed under the same asset identity and timestamps', async () => {
    const f = await meal(),
      changed = structuredClone(f.raw)
    changed.context.media.processing_result.text = 'Vou comer arroz'
    expect(() =>
      parseConversationMealStoredSource(
        {
          sourceHash: changed.source_hash,
          capturedAt: changed.captured_at,
          epoch: f.epoch,
          context: changed.context,
        },
        f.command,
      ),
    ).toThrow()
  })
  function workout() {
    const f = fixture('workout.report'),
      command = bindConversationWorkoutCommand(f.owner, `cmsg1:${child}`, f.input),
      context = {
        schema: 'conversation.workout-source.v2',
        owner_id: f.owner,
        command_id: child,
        input_hash: command.inputHash,
        epoch: f.epoch,
        source_input: f.input,
        admitted_at: f.f.profile.observed_at,
        captured_at: f.f.profile.observed_at,
        clinical: f.f.profile,
        day_closed: false,
        media: f.media,
        intake_projection: f.projection,
        catalogue: [
          {
            id,
            slug: 'caminhada',
            display_name: 'Caminhada',
            is_active: true,
            updated_at: f.f.profile.observed_at,
          },
        ],
      }
    return { ...f, command, context }
  }
  it('keeps the conflicting media context visible to the independent workout guard', () => {
    const f = workout(),
      source = parseConversationWorkoutSource(f.command, {
        source_hash: 'd'.repeat(64),
        context: f.context,
      })
    expect(source.sources.map((value) => value.unit)).toEqual([
      'media_caption',
      'media_context',
      'media_transcript',
    ])
    expect(resolveConversationWorkoutReport(source)).toMatchObject({
      status: 'not_reported',
      reason: 'non_performed_or_conflicting_source',
    })
  })
  it('equipment pixels alone cannot become a performed workout', () => {
    const f = workout(),
      input = {
        ...f.input,
        source: {
          channel: 'media' as const,
          media_asset_id: asset,
          user_action: 'report_actual_record',
        },
      },
      media = {
        ...f.media,
        kind: 'gym_photo',
        context_text: null,
        processing_result: { type: 'equipment', equipment: ['esteira'] },
      },
      command = bindConversationWorkoutCommand(f.owner, `cmsg1:${child}`, input),
      projection = {
        ...f.projection,
        child_input_hash: command.inputHash,
        media: {
          ...f.projection.media,
          kind: 'gym_photo',
          processing_hash: workoutDigest({
            context_text: null,
            processing_result: media.processing_result,
          }),
        },
      },
      context = {
        ...f.context,
        source_input: input,
        input_hash: command.inputHash,
        media,
        intake_projection: projection,
      },
      source = parseConversationWorkoutSource(command, { source_hash: 'd'.repeat(64), context })
    expect(resolveConversationWorkoutReport(source)).toMatchObject({
      status: 'needs_reply',
      question: { field: 'activity' },
    })
  })
})
