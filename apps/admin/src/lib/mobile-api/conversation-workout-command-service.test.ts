import {
  parseFeedbackV3Registration,
  prepareRegistrationFeedbackV3,
} from '@mpp/agent/registration-feedback-v3'
import type { ServiceClient } from '@mpp/db'
import { describe, expect, it, vi } from 'vitest'
import { replyFixture } from './__fixtures__/conversation-meal-reply'
import { clinical as completeClinicalFixture } from './__fixtures__/feedback-v2-source'
import {
  type ConversationFeedbackPresentationV2,
  parseConversationFeedbackPresentationV2,
  renderHistoricalRegistrationFeedbackV3Sections,
} from './conversation-feedback-presentation-v2'
import { resolveConversationWorkoutReport } from './conversation-workout-authority'
import { createConversationWorkoutCommandService } from './conversation-workout-command-service'
import {
  bindConversationWorkoutCommand,
  parseConversationWorkoutSource,
  workoutDigest,
} from './conversation-workout-contracts'
import { projectCurrentClinicalPublicPolicy } from './current-clinical-read-model'
import { type CurrentClinicalStateSource, readCurrentClinicalState } from './current-clinical-state'
import actual from './testing/conversation-workout-reconcile-pg-golden.json'

function setup(index = 0, writer3 = false, fail: 'ensure' | 'read' | null = null) {
  const row = structuredClone(actual.workout_reconcile_actual_golden[index])
  if (!row?.response.source || !row.response.preparation || !row.response.effect)
    throw new Error('Missing actual workout fixture')
  const original = replyFixture(),
    profile = row.response.source.context.clinical,
    owner = row.bound_command.ownerId,
    auth = {
      ...original.auth,
      userId: owner,
      patient: { ...original.auth.patient, id: owner },
    },
    authPort = {
      verifyAccessToken: vi.fn(async () => auth.identity),
      loadPatient: vi.fn(async () => auth.patient),
      isAdmin: vi.fn(async () => false),
    },
    capture = vi.fn<CurrentClinicalStateSource['capture']>(async () => profile),
    rpc = vi.fn(async (name: string): Promise<{ data: unknown; error: null }> => {
      if (name === 'reconcile_conversation_workout') return { data: row.response, error: null }
      if (name === 'read_conversation_workout_preparation')
        return {
          data: {
            action: 'available',
            source: row.response.source,
            preparation: row.response.preparation,
          },
          error: null,
        }
      if (name === 'read_conversation_workout_effect')
        return { data: { action: 'available', ...row.response.effect }, error: null }
      throw new Error('A durable replay must not write or re-estimate')
    }),
    ensureWorkout = vi.fn(async (_input: unknown) => {
      if (fail === 'ensure') throw new Error('optional enrichment failure')
      return null
    }),
    readHistorical = vi.fn(
      async (_input: unknown): Promise<ConversationFeedbackPresentationV2 | null> => {
        if (fail === 'read') throw new Error('optional presentation failure')
        return null
      },
    ),
    feedbackV3 = vi.fn(() => ({
      ensureWorkout,
      readHistorical,
      readRoot: vi.fn(),
      ensureRoot: vi.fn(),
      ensureReply: vi.fn(),
    })),
    service = createConversationWorkoutCommandService({ rpc } as unknown as ServiceClient, {
      auth: authPort,
      clinical: { capture },
      feedbackV3,
      feedbackV3WriterEnabled: () => writer3,
    })
  return { row, auth, authPort, capture, rpc, service, ensureWorkout, readHistorical, feedbackV3 }
}

describe('default guarded workout command facade', () => {
  it('observes the current existing account epoch for the separate workout session without writing', async () => {
    const h = setup()
    expect(await h.service.session(h.auth)).toEqual({
      schema: 'conversation.workout-session.v1',
      auth_user_id: h.auth.authUserId,
      owner_id: h.auth.userId,
      epoch: h.row.epoch,
      observed_at: h.row.response.source.context.clinical.observed_at,
      workout_command_protocol: 'conversation.command.v1',
    })
    expect(h.authPort.isAdmin).toHaveBeenCalledWith(h.auth.authUserId)
    expect(h.rpc).not.toHaveBeenCalled()
  })

  it('does not offer a workout session to a newly privileged account', async () => {
    const h = setup()
    h.authPort.isAdmin.mockResolvedValue(true)
    await expect(h.service.session(h.auth)).rejects.toMatchObject({
      code: 'patient_admin_account_conflict',
    })
    expect(h.capture).not.toHaveBeenCalled()
    expect(h.rpc).not.toHaveBeenCalled()
  })

  it('keeps the original scope adapters when a capture replaces an Auth callback', async () => {
    const h = setup(),
      originalAdmin = h.authPort.isAdmin
    h.capture.mockImplementationOnce(async () => {
      originalAdmin.mockResolvedValue(true)
      h.authPort.isAdmin = vi.fn(async () => false)
      return h.row.response.source.context.clinical
    })
    await expect(h.service.session(h.auth)).rejects.toMatchObject({
      code: 'patient_admin_account_conflict',
    })
    expect(h.rpc).not.toHaveBeenCalled()
  })

  it('refuses a reset between the initial current epoch and the session observation', async () => {
    const h = setup()
    h.capture.mockResolvedValueOnce(h.row.response.source.context.clinical)
    h.capture.mockResolvedValueOnce({
      ...h.row.response.source.context.clinical,
      epoch: h.auth.authUserId,
    })
    await expect(h.service.session(h.auth)).rejects.toMatchObject({
      code: 'mobile_current_clinical_invalid_response',
    })
    expect(h.rpc).not.toHaveBeenCalled()
  })

  it.each([
    0, 1,
  ])('returns only proved original factual fields from actual SQL case %s', async (index) => {
    const h = setup(index)
    expect(h.rpc).not.toHaveBeenCalled()
    expect(h.authPort.verifyAccessToken).not.toHaveBeenCalled()
    const result = await h.service.read(
      h.auth,
      h.row.bound_command.commandId,
      h.row.bound_command.inputHash,
      h.row.epoch,
    )
    expect(result).toEqual({
      schema: 'conversation.workout-command-result.v1',
      status: 'saved',
      owner_id: h.auth.userId,
      command_id: h.row.bound_command.commandId,
      input_hash: h.row.bound_command.inputHash,
      epoch: h.row.epoch,
      registration: {
        provenance: 'conversation.workout.v1',
        registration_id: h.row.response.effect.receipt.registration_id,
        workout_id: h.row.response.effect.receipt.workout_id,
        performed_at: h.row.response.effect.receipt.performed_at,
        local_date: h.row.response.effect.receipt.local_date,
        time_zone: h.row.response.effect.receipt.time_zone,
        committed_at: h.row.response.effect.receipt.committed_at,
        effect_version: 1,
      },
      activity: {
        kind: 'workout',
        log_id: h.row.response.effect.receipt.workout_id,
        ...h.row.response.effect.receipt.activity,
      },
      feedback: null,
    })
    expect(h.rpc.mock.calls.map(([name]) => name)).toEqual(['reconcile_conversation_workout'])
    expect(h.authPort.isAdmin).toHaveBeenCalledWith(h.auth.authUserId)
    expect(h.auth.authUserId).not.toBe(h.auth.userId)
    expect(JSON.stringify(result)).not.toMatch(
      /clinical|source_hash|snapshot_id|raw_provider|calories_target|exercise_calories/u,
    )
  })

  it('replays a saved command through the actual backend without a second commit or provider', async () => {
    const h = setup(),
      key = `cmsg1:${h.row.bound_command.commandId}`
    const saved = await h.service.submit(h.auth, key, h.row.bound_command.command, h.row.epoch)
    const reopened = await h.service.read(
      h.auth,
      h.row.bound_command.commandId,
      h.row.bound_command.inputHash,
      h.row.epoch,
    )
    expect(saved).toEqual(reopened)
    expect(saved.status).toBe('saved')
    expect(h.rpc.mock.calls.map(([name]) => name)).toEqual([
      'read_conversation_workout_preparation',
      'read_conversation_workout_effect',
      'reconcile_conversation_workout',
    ])
  })

  it('refuses a changed epoch before any physical workout RPC', async () => {
    const h = setup()
    await expect(
      h.service.read(
        h.auth,
        h.row.bound_command.commandId,
        h.row.bound_command.inputHash,
        h.auth.authUserId,
      ),
    ).rejects.toMatchObject({ code: 'mobile_current_clinical_invalid_response' })
    expect(h.rpc).not.toHaveBeenCalled()
  })

  it('does not return a saved effect after the account becomes an admin during dispatch', async () => {
    const h = setup()
    h.rpc.mockImplementationOnce(async () => {
      h.authPort.isAdmin.mockResolvedValue(true)
      return { data: h.row.response, error: null }
    })
    await expect(
      h.service.read(
        h.auth,
        h.row.bound_command.commandId,
        h.row.bound_command.inputHash,
        h.row.epoch,
      ),
    ).rejects.toMatchObject({ code: 'patient_admin_account_conflict' })
    expect(h.rpc).toHaveBeenCalledTimes(1)
  })

  it('retains identity on an uncertain submission and performs no automatic resubmission', async () => {
    const h = setup()
    h.rpc.mockRejectedValueOnce(new Error('private transport failure'))
    const result = await h.service.submit(
      h.auth,
      `cmsg1:${h.row.bound_command.commandId}`,
      h.row.bound_command.command,
      h.row.epoch,
    )
    expect(result).toEqual({
      schema: 'conversation.workout-command-state.v1',
      status: 'pending',
      owner_id: h.auth.userId,
      command_id: h.row.bound_command.commandId,
      input_hash: h.row.bound_command.inputHash,
      epoch: h.row.epoch,
      reason: 'reconciliation_required',
    })
    expect(h.rpc).toHaveBeenCalledTimes(1)
    expect(JSON.stringify(result)).not.toContain('private')
  })

  it.each([
    ['Fiz caminhada', 'needs_reply'],
    ['Vou fazer caminhada', 'not_recorded'],
  ])('preserves the sealed decision for %s without a workout effect', async (text, status) => {
    const h = setup(),
      raw = { ...h.row.bound_command.command, source: { channel: 'text', text } },
      command = bindConversationWorkoutCommand(h.auth.userId, `cmsg1:${raw.command_id}`, raw),
      wire = {
        ...h.row.response.source,
        context: {
          ...h.row.response.source.context,
          source_input: command.command,
          input_hash: command.inputHash,
        },
      }
    const source = parseConversationWorkoutSource(command, wire),
      decision = resolveConversationWorkoutReport(source)
    h.rpc.mockImplementationOnce(async () => ({
      data: {
        action: 'available',
        source: wire,
        preparation: {
          prepared_hash: workoutDigest(decision),
          prepared: decision,
        },
      },
      error: null,
    }))
    const result = await h.service.submit(h.auth, `cmsg1:${raw.command_id}`, raw, h.row.epoch)
    expect(result).toMatchObject({
      schema: 'conversation.workout-command-state.v1',
      status,
      owner_id: h.auth.userId,
      command_id: command.commandId,
      input_hash: command.inputHash,
      epoch: h.row.epoch,
    })
    if (decision.status === 'needs_reply')
      expect(result).toHaveProperty('question', decision.question)
    if (decision.status === 'not_reported') expect(result).toHaveProperty('reason', decision.reason)
    expect(h.rpc.mock.calls.map(([name]) => name)).toEqual([
      'read_conversation_workout_preparation',
    ])
    expect(result).not.toHaveProperty('source_hash')
  })
})

describe('workout actual original proof and optional rich feedback', () => {
  it.each([
    ['legacy', false],
    ['2', false],
    ['legacy', true],
    ['2', true],
  ] as const)('POST %s with server writer %s keeps effect and exact private proof', async (selected, writer3) => {
    const h = setup(0, writer3),
      result = await h.service.submit(
        h.auth,
        `cmsg1:${h.row.bound_command.commandId}`,
        h.row.bound_command.command,
        h.row.epoch,
        selected,
      )
    expect(result.status).toBe('saved')
    expect(h.ensureWorkout).toHaveBeenCalledTimes(writer3 ? 1 : 0)
    expect(h.readHistorical).toHaveBeenCalledTimes(selected === '2' ? 1 : 0)
    if (writer3) {
      const input = h.ensureWorkout.mock.calls[0]?.[0]
      expect(input).toEqual({
        source: parseConversationWorkoutSource(
          bindConversationWorkoutCommand(
            h.auth.userId,
            `cmsg1:${h.row.bound_command.commandId}`,
            h.row.bound_command.command,
          ),
          h.row.response.source,
        ),
        prepared: h.row.response.preparation.prepared,
        effect: { action: 'available', ...h.row.response.effect },
      })
    }
    expect(h.rpc.mock.calls.map(([name]) => name)).toEqual([
      'read_conversation_workout_preparation',
      'read_conversation_workout_effect',
    ])
    expect(JSON.stringify(result)).not.toContain('source_hash')
  })
  it('GET reads genuine original proof and never ensures even when server writer is enabled', async () => {
    const h = setup(1, true),
      result = await h.service.read(
        h.auth,
        h.row.bound_command.commandId,
        h.row.bound_command.inputHash,
        h.row.epoch,
        '2',
      )
    expect(result.status).toBe('saved')
    expect(h.ensureWorkout).not.toHaveBeenCalled()
    expect(h.readHistorical).toHaveBeenCalledWith({
      auth: h.auth,
      proof: {
        kind: 'workout.report',
        source: parseConversationWorkoutSource(
          bindConversationWorkoutCommand(
            h.auth.userId,
            `cmsg1:${h.row.bound_command.commandId}`,
            h.row.bound_command.command,
          ),
          h.row.response.source,
        ),
        prepared: h.row.response.preparation.prepared,
        effect: { action: 'available', ...h.row.response.effect },
      },
    })
    expect(h.rpc.mock.calls.map(([name]) => name)).toEqual(['reconcile_conversation_workout'])
    if (result.status === 'saved') expect(result.activity.estimated_kcal).toBeNull()
  })
  it.each([
    'ensure',
    'read',
  ] as const)('optional %s failure preserves the factual ACK without resubmitting', async (failure) => {
    const h = setup(0, true, failure),
      result = await h.service.submit(
        h.auth,
        `cmsg1:${h.row.bound_command.commandId}`,
        h.row.bound_command.command,
        h.row.epoch,
        '2',
      )
    expect(result.status).toBe('saved')
    if (result.status === 'saved') expect(result.feedback).toBeNull()
    expect(h.rpc).toHaveBeenCalledTimes(2)
    expect(JSON.stringify(result)).not.toContain('optional')
  })
})

it.each(
  ['submit', 'read'].flatMap((method) =>
    ['unchanged', 'hold', 'future'].map((policyCase) => ({ method, policyCase })),
  ),
)('workout $method publishes only current clock-bound policy ($policyCase)', async ({
  method,
  policyCase,
}) => {
  const h = setup(0, true),
    raw = h.row.response,
    effect = { action: 'available' as const, ...raw.effect },
    command = bindConversationWorkoutCommand(
      h.auth.userId,
      `cmsg1:${h.row.bound_command.commandId}`,
      h.row.bound_command.command,
    ),
    source = parseConversationWorkoutSource(command, raw.source),
    state = completeClinicalFixture()
  // UNIT current-policy scenario over actual workout facts; no new SQL/canonical proof is claimed.
  state.user_id = state.health_state.user_id = h.auth.userId
  state.epoch = h.row.epoch
  state.date = state.safety.date = raw.effect.receipt.local_date
  state.timezone = state.safety.timezone = state.body.timezone = raw.effect.receipt.time_zone
  state.observed_at = state.safety.observed_at = raw.effect.receipt.committed_at
  const parsed = readCurrentClinicalState(state, h.auth.userId),
    policy = projectCurrentClinicalPublicPolicy(parsed),
    registration = parseFeedbackV3Registration({
      kind: 'workout',
      log_id: raw.effect.receipt.workout_id,
      ...raw.effect.receipt.activity,
    }),
    canonical = prepareRegistrationFeedbackV3({
      registrationId: raw.effect.receipt.registration_id,
      localDate: raw.effect.receipt.local_date,
      locale: 'pt-BR',
      registration,
      officialDay: null,
      policy,
      educationAvailable: false,
    }),
    proof = { kind: 'workout.report' as const, source, prepared: raw.preparation.prepared, effect },
    packet = parseConversationFeedbackPresentationV2(
      {
        schema: 'conversation.feedback-presentation.v2',
        mode: 'historical',
        assistant: 'Flow AI',
        original: {
          schema: 'registration.feedback.v3',
          registration_id: canonical.registration_id,
          kind: 'workout',
          local_date: canonical.local_date,
        },
        status: 'available',
        format: 'sections',
        recorded: registration,
        sections: renderHistoricalRegistrationFeedbackV3Sections(canonical, policy),
        current_policy: policy,
        provenance: {
          epoch: h.row.epoch,
          command_id: command.commandId,
          observed_at: state.observed_at,
        },
      },
      { auth: h.auth, proof, canonical },
    )
  h.capture.mockResolvedValue(state)
  h.readHistorical.mockImplementationOnce(async () => {
    const after = structuredClone(state)
    Object.assign(after.health_state, {
      safety_revision: '1',
      hold_active: true,
      hide_protein: true,
      last_declared_at: state.observed_at,
      items: [{ code: 'professional_diet', declared_at: state.observed_at }],
    })
    Object.assign(after.safety, { hold_active: true, hide_protein: true })
    if (policyCase === 'hold') h.capture.mockResolvedValue(after)
    if (policyCase === 'future') {
      const future = new Date(Date.parse(state.observed_at) + 60_000).toISOString()
      return parseConversationFeedbackPresentationV2(
        {
          ...packet,
          current_policy: { ...packet.current_policy, observed_at: future },
          provenance: { ...packet.provenance, observed_at: future },
        },
        { auth: h.auth, proof, canonical },
      )
    }
    return packet
  })
  const result =
    method === 'submit'
      ? await h.service.submit(
          h.auth,
          `cmsg1:${command.commandId}`,
          command.command,
          h.row.epoch,
          '2',
        )
      : await h.service.read(h.auth, command.commandId, command.inputHash, h.row.epoch, '2')
  expect(result.status).toBe('saved')
  if (result.status === 'saved') {
    if (policyCase === 'unchanged') {
      expect(result.feedback).toEqual(packet)
      expect(result.feedback?.sections).toHaveLength(6)
    } else expect(result.feedback).toBeNull()
    expect(result.activity.estimated_kcal).toBe(raw.effect.receipt.activity.estimated_kcal)
  }
  expect(h.rpc).toHaveBeenCalledTimes(method === 'submit' ? 2 : 1)
})
