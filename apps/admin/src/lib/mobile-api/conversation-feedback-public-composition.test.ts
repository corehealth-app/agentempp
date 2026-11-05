import type { ServiceClient } from '@mpp/db'
import { describe, expect, it, vi } from 'vitest'
import { publicFeedbackV3Fixture } from './__fixtures__/conversation-feedback-v3-presentation'
import { createConversationFeedbackPublicComposition } from './conversation-feedback-public-composition'
import {
  bindConversationWorkoutCommand,
  parseConversationWorkoutSource,
} from './conversation-workout-contracts'
import workoutGolden from './testing/conversation-workout-pg-golden.json'

describe('actual source/receipt bridge composition for public presentation', () => {
  it('delegates explicit workout enrichment with real immutable source/prepared/effect and pins its callback', async () => {
    const actual = workoutGolden.workout_actual_golden[1]
    if (!actual) throw new Error('Missing actual workout fixture')
    const c = actual.source.context,
      command = bindConversationWorkoutCommand(c.owner_id, `cmsg1:${c.command_id}`, c.source_input),
      source = parseConversationWorkoutSource(command, actual.source),
      input = { source, prepared: actual.preparation.prepared, effect: actual.effect },
      f = publicFeedbackV3Fixture(),
      ensureWorkout = vi.fn().mockResolvedValue(null),
      readWorkout = vi.fn(),
      original = {
        ensureWorkout,
        readWorkout,
        readRoot: vi.fn(),
        readReply: vi.fn(),
        ensureRoot: vi.fn(),
        ensureReply: vi.fn(),
      },
      service = createConversationFeedbackPublicComposition({} as ServiceClient, f.who, c.epoch, {
        original,
      })
    original.ensureWorkout = vi.fn(() => {
      throw new Error('Late callback replacement')
    })
    expect(await service.ensureWorkout(input)).toBeNull()
    expect(ensureWorkout).toHaveBeenCalledWith(input)
    expect(readWorkout).not.toHaveBeenCalled()
  })
  it.each([
    'root',
    'linked',
  ] as const)('reads %s canonical3 with genuine proof and never ensures from presentation', async (kind) => {
    const f = publicFeedbackV3Fixture(kind),
      readRoot = vi.fn().mockResolvedValue(f.canonical),
      readReply = vi.fn().mockResolvedValue(f.canonical),
      ensureRoot = vi.fn(),
      ensureReply = vi.fn(),
      readWorkout = vi.fn(),
      ensureWorkout = vi.fn()
    const service = createConversationFeedbackPublicComposition(
      {} as ServiceClient,
      f.who,
      f.state.epoch,
      {
        auth: {
          verifyAccessToken: async () => f.who.identity,
          loadPatient: async () => f.who.patient,
          isAdmin: async () => false,
        },
        clinical: { capture: async () => f.state },
        original: { readRoot, readReply, readWorkout, ensureRoot, ensureReply, ensureWorkout },
      },
    )
    const result = await service.readHistorical({ auth: f.who, proof: f.proof })
    expect(result?.schema).toBe('conversation.feedback-presentation.v2')
    expect(result?.original.registration_id).toBe(f.receipt.registration_id)
    if (f.proof.kind === 'meal.report')
      expect(readRoot).toHaveBeenCalledWith({
        auth: f.who,
        command: f.proof.command,
        serverBinding: f.proof.serverBinding,
        receipt: f.proof.receipt,
      })
    else
      expect(readReply).toHaveBeenCalledWith({
        auth: f.who,
        binding: f.proof.kind === 'meal.clarify' ? f.proof.binding : null,
      })
    expect(ensureRoot).not.toHaveBeenCalled()
    expect(ensureReply).not.toHaveBeenCalled()
    expect(ensureWorkout).not.toHaveBeenCalled()
  })
})
