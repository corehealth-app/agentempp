import type { ServiceClient } from '@mpp/db'
import { describe, expect, it } from 'vitest'
import actual from './__fixtures__/conversation-intake-media-actual.json'
import { auth as baseAuth, clinical } from './__fixtures__/feedback-v2-source'
import { bindConversationIntake } from './conversation-intake-contracts'
import { createConversationIntakeRuntime } from './conversation-intake-runtime'

describe('request-owned negotiated media scope in the real typed facades', () => {
  for (const row of actual.cases.filter((r) => ['meal_photo', 'audio_workout'].includes(r.kind)))
    it(`fences the next child RPC after media revocation inside ${row.kind}`, async () => {
      const selected = row.selection.selection,
        binding = selected.intake,
        input = bindConversationIntake(binding.owner_id, `cintake1:${binding.intake_id}`, {
          intake_protocol: 'conversation.intake.v1',
          intake_id: binding.intake_id,
          source: selected.command.input.source,
        }),
        auth = {
          ...baseAuth,
          userId: binding.owner_id,
          identity: { ...baseAuth.identity, email: 'media.synthetic@example.invalid' },
          patient: { ...baseAuth.patient, id: binding.owner_id, timezone: 'UTC' },
        },
        state = clinical(),
        calls: string[] = []
      state.user_id = binding.owner_id
      state.epoch = binding.epoch
      state.health_state.user_id = binding.owner_id
      state.date = state.safety.date = '2026-11-06'
      state.observed_at = state.safety.observed_at = '2026-11-06T12:00:00.000001Z'
      let allowed = true
      const domainRead =
        selected.command.kind === 'meal.report'
          ? 'read_conversation_meal_prepared'
          : 'read_conversation_workout_preparation'
      const db = {
        async rpc(name: string) {
          calls.push(name)
          if (name === 'read_conversation_intake')
            return {
              data: {
                action: 'available',
                intake: binding,
                source_input: input.input,
                source_hash: selected.source_hash,
                claimed: true,
                selection: selected,
              },
              error: null,
            }
          if (name === domainRead) {
            allowed = false
            return { data: { action: 'absent' }, error: null }
          }
          throw new Error('Unexpected physical RPC after revocation')
        },
      } as unknown as ServiceClient
      const runtime = createConversationIntakeRuntime(
        db,
        auth,
        {
          ownerId: binding.owner_id,
          intakeId: binding.intake_id,
          inputHash: binding.input_hash,
          epoch: binding.epoch,
        },
        {
          enabled: () => true,
          mealEnabled: () => true,
          workoutEnabled: () => true,
          mediaEnabled: () => allowed,
          createRouter: () => {
            throw new Error('Persisted selection must not call a router')
          },
          auth: {
            verifyAccessToken: async () => auth.identity,
            loadPatient: async () => auth.patient,
            isAdmin: async () => false,
          },
          clinical: { capture: async () => state },
        },
      )
      await expect(runtime.submit(input, 'legacy', '1')).rejects.toMatchObject({ status: 503 })
      expect(calls).toEqual(['read_conversation_intake', domainRead])
      // Revocation remains sticky even if configuration comes back. No capture,
      // new claim, model, admission or writer may resume in this request.
      allowed = true
      await expect(runtime.read('legacy', '1')).rejects.toMatchObject({ status: 503 })
      expect(calls).toEqual(['read_conversation_intake', domainRead])
    })
})
