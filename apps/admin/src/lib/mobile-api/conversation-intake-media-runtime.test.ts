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

describe('versioned media admission through the actual request runtime', () => {
  function harness(privateEnabled = true, withdraw: 'none' | 'auth' | 'policy' = 'none') {
    const row = actual.cases.find((r) => r.kind === 'audio_workout')
    if (!row) throw Error('Actual audio source fixture required')
    const selection = row.selection.selection,
      binding = selection.intake
    const input = bindConversationIntake(binding.owner_id, `cintake1:${binding.intake_id}`, {
      intake_protocol: 'conversation.intake.v1',
      intake_id: binding.intake_id,
      source: selection.command.input.source,
    })
    const auth = {
      ...baseAuth,
      identity: { ...baseAuth.identity, email: 'media.synthetic@example.invalid' },
      userId: binding.owner_id,
      patient: { ...baseAuth.patient, id: binding.owner_id, timezone: 'UTC' },
    }
    const state = clinical()
    state.user_id = state.health_state.user_id = binding.owner_id
    state.epoch = binding.epoch
    const calls: string[] = []
    let allowed = privateEnabled,
      admin = false
    const db = {
      async rpc(name: string, args: Record<string, unknown>) {
        calls.push(name)
        if (name === 'read_conversation_intake') return { data: { action: 'absent' }, error: null }
        if (
          ['admit_conversation_intake', 'admit_conversation_versioned_media_intake_v2'].includes(
            name,
          )
        ) {
          expect(args).toEqual({
            p_user_id: binding.owner_id,
            p_expected_epoch: binding.epoch,
            p_input: input.input,
          })
          if (withdraw === 'auth') admin = true
          if (withdraw === 'policy') allowed = false
          return { data: { action: 'admitted', intake: binding }, error: null }
        }
        if (name === 'capture_conversation_intake_source')
          return { data: { action: 'media_unavailable' }, error: null }
        throw Error('Unexpected provider, claim or factual write')
      },
    } as unknown as ServiceClient
    const ports = {
      enabled: () => true,
      mealEnabled: () => true,
      workoutEnabled: () => true,
      mediaEnabled: () => true,
      privateMediaCatalogEnabled: () => allowed,
      createRouter: () => {
        throw Error('Unavailable media must not run a router')
      },
      auth: {
        verifyAccessToken: async () => auth.identity,
        loadPatient: async () => auth.patient,
        isAdmin: async () => admin,
      },
      clinical: { capture: async () => state },
    }
    const runtime = createConversationIntakeRuntime(
      db,
      auth,
      {
        ownerId: binding.owner_id,
        intakeId: binding.intake_id,
        inputHash: binding.input_hash,
        epoch: binding.epoch,
      },
      ports,
    )
    return {
      input,
      runtime,
      calls,
      restore: () => {
        allowed = true
        admin = false
      },
    }
  }
  it('uses the atomic dispatcher for opted-in media and keeps the existing capture path', async () => {
    const x = harness()
    expect(await x.runtime.submit(x.input, 'legacy', '1')).toMatchObject({
      status: 'held',
      reason: 'media_unavailable',
    })
    expect(x.calls).toEqual([
      'read_conversation_intake',
      'admit_conversation_versioned_media_intake_v2',
      'capture_conversation_intake_source',
    ])
  })
  it('keeps old media admission unchanged when the request was bound with opt-in off', async () => {
    const x = harness(false)
    expect(await x.runtime.submit(x.input, 'legacy', '1')).toMatchObject({ status: 'held' })
    expect(x.calls).toEqual([
      'read_conversation_intake',
      'admit_conversation_intake',
      'capture_conversation_intake_source',
    ])
  })
  it('preserves actual Auth revocation after the versioned physical admission', async () => {
    const x = harness(true, 'auth')
    await expect(x.runtime.submit(x.input, 'legacy', '1')).rejects.toMatchObject({
      code: 'patient_admin_account_conflict',
    })
    expect(x.calls).toEqual([
      'read_conversation_intake',
      'admit_conversation_versioned_media_intake_v2',
    ])
  })
  it('keeps private policy revocation sticky across the existing observer and a later retry', async () => {
    const x = harness(true, 'policy')
    await expect(x.runtime.submit(x.input, 'legacy', '1')).rejects.toMatchObject({
      code: 'conversation_intake_unavailable',
    })
    x.restore()
    await expect(x.runtime.read('legacy', '1')).rejects.toMatchObject({
      code: 'conversation_intake_unavailable',
    })
    expect(x.calls).toEqual([
      'read_conversation_intake',
      'admit_conversation_versioned_media_intake_v2',
    ])
  })
})
