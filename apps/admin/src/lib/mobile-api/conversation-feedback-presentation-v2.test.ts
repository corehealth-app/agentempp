import { prepareRegistrationFeedbackV2 } from '@mpp/agent/registration-feedback-v2'
import {
  parseFeedbackV3Registration,
  prepareRegistrationFeedbackV3,
} from '@mpp/agent/registration-feedback-v3'
import type { ServiceClient } from '@mpp/db'
import { describe, expect, it, vi } from 'vitest'
import linkedActual from '../../../../ios/BodyFlow/BodyFlowTests/Fixtures/ConversationLinkedActualHTTPFixtures.json'
import rootActual from '../../../../ios/BodyFlow/BodyFlowTests/Fixtures/FlowMealEditLifecycleFixtures.json'
import { replyFixture } from './__fixtures__/conversation-meal-reply'
import { clinical } from './__fixtures__/feedback-v2-source'
import { bindConversationCommand } from './conversation-command-contracts'
import {
  type ConversationFeedbackPresentationV2Proof,
  createConversationFeedbackPresentationV2Service,
  parseConversationFeedbackPresentationV2,
  renderHistoricalRegistrationFeedbackV3Sections,
} from './conversation-feedback-presentation-v2'
import {
  bindConversationWorkoutCommand,
  parseConversationWorkoutSource,
} from './conversation-workout-contracts'
import { projectCurrentClinicalPublicPolicy } from './current-clinical-read-model'
import { readCurrentClinicalState } from './current-clinical-state'
import workoutGolden from './testing/conversation-workout-pg-golden.json'

function requireValue<T>(value: T | null | undefined): T {
  if (value === null || value === undefined) throw new Error('Missing genuine fixture value')
  return value
}

function fixture(kind: 'root' | 'linked' = 'root') {
  const packet =
    kind === 'root' ? rootActual.original_saved.data : linkedActual.saved_reply.packet.data
  const receipt = packet.receipt
  const source = kind === 'root' ? rootActual : linkedActual
  const who = structuredClone(replyFixture().auth)
  who.authUserId = source.auth_user_id
  who.identity.id = source.auth_user_id
  who.patient.authUserId = source.auth_user_id
  who.userId = receipt.owner_id
  who.patient.id = receipt.owner_id
  const state = clinical()
  state.user_id = receipt.owner_id
  state.health_state.user_id = receipt.owner_id
  state.epoch = packet.epoch
  state.date = state.safety.date = receipt.local_date
  state.observed_at = state.safety.observed_at = requireValue(
    packet.feedback,
  ).provenance.observed_at
  const proof: ConversationFeedbackPresentationV2Proof =
    kind === 'root'
      ? {
          kind: 'meal.report',
          command: bindConversationCommand(
            receipt.owner_id,
            `cmsg1:${rootActual.original_command.command_id}`,
            rootActual.original_command,
          ),
          serverBinding: {
            owner_id: receipt.owner_id,
            command_id: receipt.command_id,
            input_hash: receipt.input_hash,
            command_protocol: 'conversation.command.v1',
            kind: 'meal.report',
            epoch: packet.epoch,
            admitted_at: rootActual.original_saved.data.admitted_at,
          },
          receipt,
        }
      : {
          kind: 'meal.clarify',
          binding: {
            parentBinding: linkedActual.saved_reply.packet.data.parent_binding,
            childBinding: linkedActual.saved_reply.packet.data.child_binding,
            parentDecisionHash: linkedActual.saved_reply.packet.data.parent_decision_hash,
            receipt,
          },
        }
  const parsedState = readCurrentClinicalState(state, receipt.owner_id)
  const canonical = prepareRegistrationFeedbackV3({
    registrationId: receipt.registration_id,
    localDate: receipt.local_date,
    locale: 'pt-BR',
    registration: parseFeedbackV3Registration(requireValue(packet.feedback).recorded),
    officialDay: null,
    policy: projectCurrentClinicalPublicPolicy(parsedState),
    educationAvailable: false,
  })
  return { who, state: structuredClone(parsedState), proof, canonical, receipt }
}
function setup(kind: 'root' | 'linked' = 'root') {
  const f = fixture(kind),
    events: string[] = [],
    auth = {
      verifyAccessToken: vi.fn(async () => {
        events.push('token')
        return f.who.identity
      }),
      loadPatient: vi.fn(async () => {
        events.push('patient')
        return f.who.patient
      }),
      isAdmin: vi.fn(async () => {
        events.push('admin')
        return false
      }),
    },
    capture = vi.fn(async () => {
      events.push('profile')
      return f.state
    }),
    readOriginal = vi.fn(async (_input: unknown): Promise<unknown> => {
      events.push('canonical-read')
      return f.canonical
    }),
    service = createConversationFeedbackPresentationV2Service({} as ServiceClient, {
      auth,
      clinical: { capture },
      original: { readOriginal },
    })
  return { ...f, auth, capture, readOriginal, service, events }
}
const find = (sections: readonly { key: string; text: string }[], key: string) =>
  requireValue(sections.find((s) => s.key === key)).text
function rich() {
  const f = fixture(),
    c = structuredClone(f.canonical)
  c.day = {
    local_date: c.local_date,
    current_protocol: 'recomposicao',
    consumed: { calories_kcal: 1785, protein_g: 126, carbs_g: 180, fat_g: 45 },
    targets: { calories_kcal: 2400, protein_g: 150 },
    calorie_percentage: 74.4,
    protein_percentage: 84,
    remaining_food_kcal: 615,
    food_excess_kcal: 0,
    exercise_kcal: null,
    exercise_energy: { status: 'unavailable', reason: 'unknown_workout_energy' },
  }
  c.block = {
    status: 'available',
    target_kcal: 7700,
    current_kcal: 3120,
    percentage: 41,
    completed_blocks: 2,
    total_credited_kcal: 18520,
  }
  return { f, c, p: structuredClone(projectCurrentClinicalPublicPolicy(f.state)) }
}

describe('new current-safe v3 presentation without modifying wrapper1', () => {
  it.each([
    'root',
    'linked',
  ] as const)('binds genuine %s receipt/command/epoch and reads only its immutable canonical once', async (kind) => {
    const h = setup(kind),
      before = structuredClone(h.canonical)
    expect(h.events).toEqual([])
    const value = await h.service.readHistorical({ auth: h.who, proof: h.proof })
    expect(value).toMatchObject({
      schema: 'conversation.feedback-presentation.v2',
      mode: 'historical',
      assistant: 'Flow AI',
      original: {
        schema: 'registration.feedback.v3',
        registration_id: h.receipt.registration_id,
        kind: 'meal',
        local_date: h.receipt.local_date,
      },
      recorded: h.canonical.registration,
      provenance: {
        epoch: h.state.epoch,
        command_id: h.receipt.command_id,
        observed_at: h.state.observed_at,
      },
    })
    expect(requireValue(value).sections.map((s) => s.key)).toEqual([
      'saved',
      'items',
      'summary',
      'day',
      'block',
      'education',
    ])
    expect(Object.keys(requireValue(value))).not.toContain('canonical_body')
    expect(h.readOriginal).toHaveBeenCalledTimes(1)
    expect(h.capture).toHaveBeenCalledTimes(2)
    expect(h.events).toEqual([
      'token',
      'admin',
      'patient',
      'profile',
      'token',
      'admin',
      'patient',
      'canonical-read',
      'token',
      'admin',
      'patient',
      'profile',
      'token',
      'admin',
      'patient',
    ])
    expect(h.canonical).toEqual(before)
    expect(
      parseConversationFeedbackPresentationV2(value, {
        auth: h.who,
        proof: h.proof,
        canonical: h.canonical,
      }),
    ).toEqual(value)
    if (kind === 'linked') expect(h.receipt.registration_id).not.toBe(h.receipt.command_id)
  })
  it('never relabels an existing canonical2 or weakens its factual acknowledgement', async () => {
    const h = setup(),
      registration = h.canonical.registration
    if (registration.kind !== 'meal') throw new Error('meal')
    h.readOriginal.mockResolvedValue(
      prepareRegistrationFeedbackV2({
        registrationId: h.receipt.registration_id,
        localDate: h.receipt.local_date,
        locale: 'pt-BR',
        registration,
        officialDay: null,
        policy: projectCurrentClinicalPublicPolicy(h.state),
      }),
    )
    const ack = structuredClone(h.receipt)
    expect(await h.service.readHistorical({ auth: h.who, proof: h.proof })).toBe(null)
    expect(h.receipt).toEqual(ack)
    expect(h.readOriginal).toHaveBeenCalledTimes(1)
  })
  it.each([
    'root',
    'linked',
  ] as const)('rejects changed %s source identity before any canonical read', async (kind) => {
    const h = setup(kind),
      originalProof = structuredClone(h.proof),
      proof =
        originalProof.kind === 'meal.report'
          ? { ...originalProof, command: { ...originalProof.command, inputHash: 'a'.repeat(64) } }
          : originalProof.kind === 'meal.clarify'
            ? {
                ...originalProof,
                binding: {
                  ...(originalProof.binding as object),
                  parentDecisionHash: 'a'.repeat(64),
                },
              }
            : originalProof
    expect(await h.service.readHistorical({ auth: h.who, proof })).toBe(null)
    expect(h.readOriginal).not.toHaveBeenCalled()
  })
  it('latches post-read admin revocation and never publishes returned original text', async () => {
    const h = setup()
    h.readOriginal.mockImplementationOnce(async () => {
      h.auth.isAdmin.mockResolvedValue(true)
      return h.canonical
    })
    expect(await h.service.readHistorical({ auth: h.who, proof: h.proof })).toBe(null)
    expect(h.readOriginal).toHaveBeenCalledTimes(1)
  })
  it('observes after a thrown canonical read, without retry or losing receipt', async () => {
    const h = setup(),
      ack = structuredClone(h.receipt)
    h.readOriginal.mockRejectedValueOnce(new Error('private detail'))
    expect(await h.service.readHistorical({ auth: h.who, proof: h.proof })).toBe(null)
    expect(h.capture).toHaveBeenCalledTimes(2)
    expect(h.readOriginal).toHaveBeenCalledTimes(1)
    expect(h.receipt).toEqual(ack)
  })
  it('pins the canonical read before a post-scope callback can mutate the returned object', async () => {
    const h = setup(),
      original = structuredClone(h.canonical.registration)
    h.capture
      .mockImplementationOnce(async () => h.state)
      .mockImplementationOnce(async () => {
        if (h.canonical.registration.kind !== 'meal') throw new Error('meal')
        requireValue(h.canonical.registration.items[0]).food_name = 'altered after receipt read'
        return h.state
      })
    const result = requireValue(await h.service.readHistorical({ auth: h.who, proof: h.proof }))
    expect(result.recorded).toEqual(original)
    expect(h.readOriginal).toHaveBeenCalledTimes(1)
  })
  it('withholds policy drift, epoch reset and backwards clocks', async () => {
    for (const change of ['epoch', 'clinical', 'clock']) {
      const h = setup(),
        after = structuredClone(h.state)
      if (change === 'epoch') after.epoch = h.who.authUserId
      if (change === 'clinical') after.profile_hash = 'c'.repeat(64)
      if (change === 'clock')
        after.observed_at = requireValue(after.safety).observed_at = '2020-01-01T00:00:00Z'
      h.capture.mockResolvedValueOnce(h.state).mockResolvedValueOnce(after)
      expect(await h.service.readHistorical({ auth: h.who, proof: h.proof })).toBe(null)
    }
  })
  it('does not execute supplied getters or publish a different original food fact', async () => {
    const h = setup(),
      value = await h.service.readHistorical({ auth: h.who, proof: h.proof }),
      hook = vi.fn(() => requireValue(value).recorded)
    const raw = { ...value }
    Object.defineProperty(raw, 'recorded', { enumerable: true, get: hook })
    expect(() =>
      parseConversationFeedbackPresentationV2(raw, {
        auth: h.who,
        proof: h.proof,
        canonical: h.canonical,
      }),
    ).toThrow()
    expect(hook).not.toHaveBeenCalled()
    const changed = structuredClone(requireValue(value))
    if (changed.recorded.kind !== 'meal') throw new Error('meal')
    requireValue(changed.recorded.items[0]).kcal += 1
    expect(() =>
      parseConversationFeedbackPresentationV2(changed, {
        auth: h.who,
        proof: h.proof,
        canonical: h.canonical,
      }),
    ).toThrow()
  })
  it.each([
    'registration',
    'kind',
    'date',
    'epoch',
    'command',
    'clock',
    'section-order',
    'unmasked-text',
    'raw-body',
  ])('drops changed optional %s instead of changing the saved receipt', async (attack) => {
    const h = setup(),
      originalReceipt = structuredClone(h.receipt),
      value = requireValue(await h.service.readHistorical({ auth: h.who, proof: h.proof })),
      raw = {
        ...structuredClone(value),
        original: { ...value.original },
        provenance: { ...value.provenance },
        sections: [...value.sections],
      }
    if (attack === 'registration') raw.original.registration_id = h.who.authUserId
    if (attack === 'kind') raw.original.kind = 'workout'
    if (attack === 'date') raw.original.local_date = '2026-11-05'
    if (attack === 'epoch') raw.provenance.epoch = h.who.authUserId
    if (attack === 'command') raw.provenance.command_id = h.who.authUserId
    if (attack === 'clock') raw.provenance.observed_at = '2026-11-04T00:00:00Z'
    if (attack === 'section-order') raw.sections = [...raw.sections].reverse()
    if (attack === 'unmasked-text')
      raw.sections = raw.sections.map((s) =>
        s.key === 'education' ? { ...s, text: 'unproved optional comment' } : s,
      )
    const candidate = attack === 'raw-body' ? { ...raw, canonical_body: h.canonical } : raw
    expect(() =>
      parseConversationFeedbackPresentationV2(candidate, {
        auth: h.who,
        proof: h.proof,
        canonical: h.canonical,
      }),
    ).toThrow()
    expect(h.receipt).toEqual(originalReceipt)
  })
  it('uses the actual current clinical pause observation without hiding saved food facts', async () => {
    const h = setup(),
      { c } = rich(),
      state = structuredClone(h.state)
    Object.assign(state.health_state, {
      safety_revision: '1',
      hold_active: true,
      hide_protein: true,
      last_declared_at: state.observed_at,
      items: [{ code: 'professional_diet', declared_at: state.observed_at }],
    })
    Object.assign(requireValue(state.safety), { hold_active: true, hide_protein: true })
    h.capture.mockResolvedValue(state)
    h.readOriginal.mockResolvedValue(c)
    const value = requireValue(await h.service.readHistorical({ auth: h.who, proof: h.proof }))
    expect(value.current_policy.pause_weight_loss_guidance).toBe(true)
    expect(value.recorded).toEqual(c.registration)
    expect(find(value.sections, 'day')).toContain('Consumido: 1.785')
    expect(find(value.sections, 'day')).not.toContain('2.400')
  })
})

describe('current mask preserves historical factual consumption and unknown energy', () => {
  it('renders all six sections, leaves unknown exercise unavailable and retains independent food targets', () => {
    const { c, p } = rich(),
      before = structuredClone(c),
      sections = renderHistoricalRegistrationFeedbackV3Sections(c, p)
    expect(find(sections, 'day')).toContain('1.785 / 2.400 kcal')
    expect(find(sections, 'day')).toContain('126 / 150 g')
    expect(find(sections, 'day')).toContain('Gasto de exercício indisponível')
    expect(c).toEqual(before)
  })
  it.each([
    'budget',
    'balance',
    'calories',
    'protein',
    'block',
    'objective',
  ] as const)('applies current %s without changing saved food facts', (flag) => {
    const { c, p } = rich()
    p.hide[flag] = true
    const sections = renderHistoricalRegistrationFeedbackV3Sections(c, p),
      day = find(sections, 'day')
    expect(find(sections, 'items')).toContain('leite')
    if (['budget', 'balance', 'calories'].includes(flag)) expect(day).not.toContain('615')
    if (flag === 'calories') expect(day).not.toContain('2.400')
    if (flag === 'protein') expect(day).not.toContain('/ 150')
    if (['block', 'objective'].includes(flag))
      expect(find(sections, 'block')).not.toContain('3.120')
    expect(find(sections, 'education')).toContain('indisponível')
  })
  it.each([
    'pt-BR',
    'en',
  ])('uses neutral reviewed pause copy in %s, retaining food consumed but no targets/budget/block', (locale) => {
    const { c, p } = rich()
    c.locale = locale as 'pt-BR' | 'en'
    p.pause_weight_loss_guidance = true
    const s = renderHistoricalRegistrationFeedbackV3Sections(c, p),
      d = find(s, 'day')
    expect(d).toContain(locale === 'en' ? 'Consumed: 1,785' : 'Consumido: 1.785')
    expect(d).not.toContain('2.400')
    expect(d).not.toContain('2,400')
    expect(d).not.toContain('615')
    expect(find(s, 'block')).not.toContain('3.120')
    expect(find(s, 'block')).not.toContain('3,120')
    expect(find(s, 'education')).toContain(locale === 'en' ? 'paused' : 'pausadas')
  })
  it('keeps consumed facts under incomplete assessment without reviving targets, block or education', () => {
    const { c, p } = rich()
    p.assessment = 'incomplete'
    p.target_source = 'unavailable'
    const s = renderHistoricalRegistrationFeedbackV3Sections(c, p)
    expect(find(s, 'day')).toContain('Consumido: 1.785')
    expect(find(s, 'day')).not.toContain('2.400')
    expect(find(s, 'block')).not.toContain('3.120')
  })
})

it('requires actual workout source/prepared/effect proof and preserves original unknown energy rather than 0', async () => {
  const a = requireValue(workoutGolden.workout_actual_golden[1]),
    context = a.source.context,
    command = bindConversationWorkoutCommand(
      context.owner_id,
      `cmsg1:${context.command_id}`,
      context.source_input,
    ),
    source = parseConversationWorkoutSource(command, a.source),
    proof: ConversationFeedbackPresentationV2Proof = {
      kind: 'workout.report',
      source,
      prepared: a.preparation.prepared,
      effect: a.effect,
    },
    who = structuredClone(replyFixture().auth)
  who.userId = who.patient.id = context.owner_id
  const state = structuredClone(readCurrentClinicalState(context.clinical, context.owner_id))
  state.observed_at = '2026-11-05T01:00:00.000001Z'
  const canonical = prepareRegistrationFeedbackV3({
    registrationId: a.effect.receipt.registration_id,
    localDate: a.effect.receipt.local_date,
    locale: 'en',
    registration: {
      kind: 'workout',
      log_id: a.effect.receipt.workout_id,
      ...a.effect.receipt.activity,
    },
    officialDay: null,
    policy: projectCurrentClinicalPublicPolicy(state),
  })
  const readOriginal = vi.fn(async () => canonical),
    service = createConversationFeedbackPresentationV2Service({} as ServiceClient, {
      original: { readOriginal },
      auth: {
        verifyAccessToken: async () => who.identity,
        isAdmin: async () => false,
        loadPatient: async () => who.patient,
      },
      clinical: { capture: async () => state },
    })
  const value = await service.readHistorical({ auth: who, proof })
  expect(value).toMatchObject({
    original: { kind: 'workout' },
    recorded: { kind: 'workout', estimated_kcal: null },
  })
  const wrong = structuredClone(canonical)
  if (wrong.registration.kind !== 'workout') throw new Error('workout')
  wrong.registration.estimated_kcal = 0
  expect(() =>
    parseConversationFeedbackPresentationV2(value, { auth: who, proof, canonical: wrong }),
  ).toThrow()
  const badProof = {
    ...proof,
    effect: { ...a.effect, receipt: { ...a.effect.receipt, provenance: 'ui-v1' } },
  }
  expect(await service.readHistorical({ auth: who, proof: badProof })).toBe(null)
})
