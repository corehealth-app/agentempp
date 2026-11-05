import { prepareRegistrationFeedbackV2 } from '@mpp/agent/registration-feedback-v2'
import { prepareRegistrationFeedbackV3 } from '@mpp/agent/registration-feedback-v3'
import type { ServiceClient } from '@mpp/db'
import { describe, expect, it, vi } from 'vitest'
import { legacyFeedback, auth as oldAuth } from './__fixtures__/feedback-v2-source'
import {
  frozenMealV3Capture,
  linkedMealV3Capture,
  workoutV3Capture,
} from './__fixtures__/feedback-v3-source'
import type { MobileAuthContext } from './auth'
import { conversationJournalBindingSchema } from './conversation-command-candidate-contracts'
import { bindConversationCommand } from './conversation-command-contracts'
import {
  type ConversationFeedbackV3RootInput,
  type ConversationFeedbackV3WorkoutInput,
  createConversationFeedbackV3OriginalBridge,
} from './conversation-feedback-v3-original-bridge'
import { parseConversationMealContinuationFeedbackBinding } from './conversation-meal-continuation-read-contracts'
import type { ConversationMealReplyFeedbackInput } from './conversation-meal-reply-public-service'
import {
  bindConversationWorkoutCommand,
  parseConversationWorkoutSource,
} from './conversation-workout-contracts'
import { parseConversationWorkoutEffect } from './conversation-workout-writer'
import { projectCurrentClinicalPublicPolicy } from './current-clinical-read-model'
import {
  type FeedbackV3Identity,
  parseFeedbackV3Capture,
} from './registration-feedback-v3-contracts'

type Case =
  | { family: 'root'; input: ConversationFeedbackV3RootInput }
  | { family: 'reply'; input: ConversationMealReplyFeedbackInput }
  | { family: 'workout'; input: ConversationFeedbackV3WorkoutInput }
function setup(
  family: 'root' | 'reply' | 'workout',
  options: { empty?: boolean; lost?: boolean; canonicalFailure?: boolean } = {},
) {
  const f =
    family === 'workout'
      ? workoutV3Capture('unknown')
      : family === 'reply'
        ? linkedMealV3Capture()
        : frozenMealV3Capture()
  const who: FeedbackV3Identity = f.who
  const auth: MobileAuthContext = structuredClone(oldAuth)
  auth.userId = who.userId
  auth.patient.id = who.userId
  auth.identity.email = 'bridge-qa@example.invalid'
  auth.patient.email = auth.identity.email
  let proof: Case
  if (family === 'root') {
    const root = frozenMealV3Capture(),
      c = root.context.source.command
    const command = bindConversationCommand(who.userId, `cmsg1:${c.command_id}`, {
      command_protocol: 'conversation.command.v1',
      command_id: c.command_id,
      kind: 'meal.report',
      meal_type: 'cafe',
      source: { channel: 'text', text: 'Comi leite integral 206 g' },
    })
    if (
      f.context.source.kind !== 'pending_registration' ||
      !('command' in f.context.source) ||
      !f.context.source.command
    )
      throw new Error('Expected root source')
    const raw = f.context.source.command
    raw.input_hash = command.inputHash
    const receipt = raw.receipt
    if (!receipt || typeof receipt !== 'object' || Array.isArray(receipt))
      throw new Error('Expected root receipt')
    Object.assign(receipt, { input_hash: command.inputHash })
    const serverBinding = conversationJournalBindingSchema.parse({
      owner_id: who.userId,
      command_id: command.commandId,
      input_hash: command.inputHash,
      command_protocol: 'conversation.command.v1',
      kind: 'meal.report',
      epoch: c.epoch,
      admitted_at: '2026-11-03T11:59:59.000001Z',
    })
    proof = { family: 'root', input: { auth, command, receipt, serverBinding } }
  } else if (family === 'reply') {
    const source = f.context.source
    if (
      source.kind !== 'pending_registration' ||
      !('command' in source) ||
      !source.command ||
      !('continuation' in source.command)
    )
      throw new Error('Expected linked source')
    proof = {
      family: 'reply',
      input: {
        auth,
        binding: parseConversationMealContinuationFeedbackBinding(source.command.continuation),
      },
    }
  } else {
    const source = f.context.source
    if (
      source.kind !== 'conversation_workout' ||
      !('input' in source) ||
      !('captured' in source) ||
      !('prepared' in source) ||
      !('effect' in source)
    )
      throw new Error('Expected own workout source')
    const command = bindConversationWorkoutCommand(
      who.userId,
      `cmsg1:${who.registrationId}`,
      source.input,
    )
    const captured = parseConversationWorkoutSource(command, source.captured)
    const effect = parseConversationWorkoutEffect(captured, source.prepared, source.effect)
    proof = { family: 'workout', input: { source: captured, prepared: source.prepared, effect } }
  }
  const observation = parseFeedbackV3Capture(f.context, who),
    epoch = observation.clinical.epoch
  if (!epoch) throw new Error('Expected real source epoch')
  const prior = prepareRegistrationFeedbackV3({
    registrationId: who.registrationId,
    localDate: observation.localDate,
    locale: 'pt-BR',
    registration: observation.registration,
    policy: projectCurrentClinicalPublicPolicy(observation.clinical),
    officialDay: null,
  })
  const state = {
    identity: structuredClone(auth.identity),
    patient: structuredClone(auth.patient),
    clinical: structuredClone(observation.clinical),
    admin: false,
    stored: options.empty ? (null as unknown) : (structuredClone(prior) as unknown),
    capture: structuredClone(f.context) as unknown,
    afterRPC: null as ((name: string) => void) | null,
  }
  const ports = {
    verifyAccessToken: vi.fn(async (_token: string) => structuredClone(state.identity)),
    loadPatient: vi.fn(async (_id: string) => structuredClone(state.patient)),
    isAdmin: vi.fn(async (_id: string) => state.admin),
  }
  const clinical = { capture: vi.fn(async () => structuredClone(state.clinical)) }
  const deps = { auth: ports, clinical }
  const rpc = vi.fn(async (name: string, args: Record<string, unknown>) => {
    if (name === 'get_mobile_current_clinical_state')
      throw new Error('Synthetic optional day unavailable')
    expect(args.p_user_id).toBe(who.userId)
    expect(args.p_registration_id).toBe(who.registrationId)
    expect(args.p_origin).toBe(who.origin)
    let data: unknown
    if (name === 'read_mobile_registration_feedback_v3')
      data = state.stored
        ? { action: 'available', feedback: structuredClone(state.stored) }
        : { action: 'absent' }
    else if (name === 'capture_mobile_registration_feedback_v3')
      data = { action: 'available', context: structuredClone(state.capture) }
    else if (name === 'commit_mobile_registration_feedback_v3') {
      if (options.canonicalFailure) data = { action: 'source_conflict' }
      else {
        state.stored = structuredClone(args.p_feedback)
        data = { action: 'committed', feedback: structuredClone(state.stored) }
        if (options.lost) throw new Error('Synthetic lost canonical success')
      }
    } else throw new Error('Domain/writer/refetch RPC forbidden')
    state.afterRPC?.(name)
    return { data, error: null }
  })
  const from = vi.fn(() => {
    throw new Error('Domain table/refetch forbidden')
  })
  const db = { rpc, from } as unknown as ServiceClient
  const bridge = createConversationFeedbackV3OriginalBridge(db, auth, epoch, deps)
  const read = () =>
    proof.family === 'root'
      ? bridge.readRoot(proof.input)
      : proof.family === 'reply'
        ? bridge.readReply(proof.input)
        : bridge.readWorkout(proof.input)
  const ensure = () =>
    proof.family === 'root'
      ? bridge.ensureRoot(proof.input)
      : proof.family === 'reply'
        ? bridge.ensureReply(proof.input)
        : bridge.ensureWorkout(proof.input)
  const root = () => {
    if (proof.family !== 'root') throw new Error('Expected root case')
    return proof.input
  }
  const reply = () => {
    if (proof.family !== 'reply') throw new Error('Expected reply case')
    return proof.input
  }
  const workout = () => {
    if (proof.family !== 'workout') throw new Error('Expected workout case')
    return proof.input
  }
  return {
    auth,
    who,
    epoch,
    proof,
    observation,
    prior,
    state,
    ports,
    clinical,
    deps,
    rpc,
    from,
    db,
    bridge,
    read,
    ensure,
    root,
    reply,
    workout,
  }
}
const canonicalNames = (h: ReturnType<typeof setup>) =>
  h.rpc.mock.calls
    .map(([name]) => name)
    .filter((name) => name.endsWith('_registration_feedback_v3'))

describe('canonical v3 original-enrichment bridge; inert until trusted server selection', () => {
  it('is inert at construction and pins dependency method identities', async () => {
    const h = setup('root'),
      oldVerify = h.ports.verifyAccessToken,
      oldCapture = h.clinical.capture
    expect(h.rpc).not.toHaveBeenCalled()
    expect(oldVerify).not.toHaveBeenCalled()
    expect(oldCapture).not.toHaveBeenCalled()
    h.deps.auth.verifyAccessToken = vi.fn(async () => ({
      ...h.auth.identity,
      id: '99999999-0000-4000-8000-000000000001',
    }))
    h.deps.clinical.capture = vi.fn(async () => ({
      ...h.state.clinical,
      epoch: '99999999-0000-4000-8000-000000000001',
    }))
    expect(await h.read()).toEqual(h.prior)
    expect(oldVerify).toHaveBeenCalled()
    expect(oldCapture).toHaveBeenCalled()
    expect(h.deps.auth.verifyAccessToken).not.toHaveBeenCalled()
    expect(h.deps.clinical.capture).not.toHaveBeenCalled()
  })
  it.each([
    'root',
    'reply',
    'workout',
  ] as const)('reads the durable %s canonical only; never ensures or recaptures', async (family) => {
    const h = setup(family)
    expect(await h.read()).toEqual(h.prior)
    expect(canonicalNames(h)).toEqual(['read_mobile_registration_feedback_v3'])
    expect(h.ports.verifyAccessToken).toHaveBeenCalled()
    expect(h.ports.isAdmin).toHaveBeenCalled()
    expect(h.ports.loadPatient).toHaveBeenCalled()
    expect(h.clinical.capture).toHaveBeenCalled()
    expect(h.from).not.toHaveBeenCalled()
  })
  it.each([
    'root',
    'reply',
    'workout',
  ] as const)('ensures %s only after actual closed domain proof with the same canonical identity', async (family) => {
    const h = setup(family, { empty: true })
    expect(await h.ensure()).toMatchObject({
      schema: 'registration.feedback.v3',
      registration_id: h.who.registrationId,
      registration: h.observation.registration,
    })
    expect(canonicalNames(h)).toEqual([
      'read_mobile_registration_feedback_v3',
      'capture_mobile_registration_feedback_v3',
      'commit_mobile_registration_feedback_v3',
      'read_mobile_registration_feedback_v3',
    ])
    expect(h.from).not.toHaveBeenCalled()
  })
  it('preserves a literal historical v1 winner without resealing or source reads', async () => {
    const h = setup('root'),
      old = legacyFeedback()
    h.state.stored = old
    expect(await h.ensure()).toEqual(old)
    expect(canonicalNames(h)).toEqual(['read_mobile_registration_feedback_v3'])
  })
  it('preserves the old v2 catalog and original body before any new metadata preparation', async () => {
    const h = setup('reply'),
      old = prepareRegistrationFeedbackV2({
        registrationId: h.who.registrationId,
        localDate: h.observation.localDate,
        locale: 'en',
        registration: h.observation.registration,
        policy: null,
        officialDay: null,
      })
    h.state.stored = old
    expect(await h.ensure()).toEqual(old)
    expect(canonicalNames(h)).toEqual(['read_mobile_registration_feedback_v3'])
  })
  it('does not ensure when a read finds no existing receipt', async () => {
    const h = setup('root', { empty: true })
    expect(await h.read()).toBeNull()
    expect(canonicalNames(h)).toEqual(['read_mobile_registration_feedback_v3'])
  })
  it('keeps canonical failure optional without repeating domain, capture or commit', async () => {
    const h = setup('root', { empty: true, canonicalFailure: true })
    expect(await h.ensure()).toBeNull()
    expect(canonicalNames(h)).toEqual([
      'read_mobile_registration_feedback_v3',
      'capture_mobile_registration_feedback_v3',
      'commit_mobile_registration_feedback_v3',
    ])
  })
  it('reconciles lost canonical success once with the immutable identity, without domain retry', async () => {
    const h = setup('workout', { empty: true, lost: true })
    expect(await h.ensure()).toMatchObject({ schema: 'registration.feedback.v3' })
    expect(canonicalNames(h)).toEqual([
      'read_mobile_registration_feedback_v3',
      'capture_mobile_registration_feedback_v3',
      'commit_mobile_registration_feedback_v3',
      'read_mobile_registration_feedback_v3',
    ])
  })
  it.each([
    'admin',
    'inactive',
    'owner',
    'auth',
    'epoch',
  ] as const)('refuses current %s revocation before a metadata RPC', async (reason) => {
    const h = setup('root')
    if (reason === 'admin') h.state.admin = true
    else if (reason === 'inactive') h.state.patient.status = 'inactive'
    else if (reason === 'owner') h.state.patient.id = '99999999-0000-4000-8000-000000000001'
    else if (reason === 'auth') h.state.identity.id = '99999999-0000-4000-8000-000000000001'
    else h.state.clinical.epoch = '99999999-0000-4000-8000-000000000001'
    expect(await h.read()).toBeNull()
    expect(h.rpc).not.toHaveBeenCalled()
  })
  it('rejects returned success after revocation and keeps the original factory closed', async () => {
    const h = setup('root')
    h.state.afterRPC = () => {
      h.state.admin = true
    }
    expect(await h.read()).toBeNull()
    expect(h.rpc).toHaveBeenCalledTimes(1)
    h.state.admin = false
    h.state.afterRPC = null
    const authReads = h.ports.verifyAccessToken.mock.calls.length
    expect(await h.ensure()).toBeNull()
    expect(h.rpc).toHaveBeenCalledTimes(1)
    expect(h.ports.verifyAccessToken).toHaveBeenCalledTimes(authReads)
  })
  it('does not turn a newer current profile into the original server epoch or source', async () => {
    const h = setup('root'),
      newEpoch = '99999999-0000-4000-8000-000000000001'
    h.state.clinical.epoch = newEpoch
    const bridge = createConversationFeedbackV3OriginalBridge(h.db, h.auth, newEpoch, h.deps)
    expect(await bridge.ensureRoot(h.root())).toBeNull()
    expect(h.rpc).not.toHaveBeenCalled()
  })
  it('requires the actual root server owner/hash/epoch binding and durable receipt', async () => {
    for (const field of ['epoch', 'input_hash', 'owner_id', 'receipt'] as const) {
      const h = setup('root')
      if (field === 'receipt') Object.assign(h.root(), { receipt: null })
      else
        Object.assign(h.root().serverBinding, {
          [field]: field === 'input_hash' ? 'f'.repeat(64) : '99999999-0000-4000-8000-000000000001',
        })
      expect(await h.ensure()).toBeNull()
      expect(h.rpc).not.toHaveBeenCalled()
    }
  })
  it('requires real linked parent/child ownership and its original receipt', async () => {
    const h = setup('reply'),
      changed = structuredClone(h.reply().binding)
    Object.assign(changed.parentBinding, { command_id: changed.childBinding.command_id })
    Object.assign(h.reply(), { binding: changed })
    expect(await h.ensure()).toBeNull()
    expect(h.rpc).not.toHaveBeenCalled()
  })
  it('requires own-workout performed source/preparation/receipt, never a mutation response alone', async () => {
    const h = setup('workout')
    Object.assign(h.workout(), {
      effect: { action: 'committed', receipt: { schema: 'conversation.workout-effect.v1' } },
    })
    expect(await h.ensure()).toBeNull()
    expect(h.rpc).not.toHaveBeenCalled()
  })
  it('rejects another Auth or owner even if the input is otherwise an existing factual proof', async () => {
    const h = setup('root')
    Object.assign(h.root(), { auth: structuredClone(h.auth) })
    h.root().auth.accessToken = 'different-original-token'
    expect(await h.ensure()).toBeNull()
    expect(h.rpc).not.toHaveBeenCalled()
  })
  it('pins proof/auth aliases before the first asynchronous current observation', async () => {
    const h = setup('root')
    h.state.afterRPC = () => {
      Object.assign(h.root().serverBinding, { epoch: '99999999-0000-4000-8000-000000000001' })
      h.root().auth.accessToken = 'changed-after-await'
    }
    expect(await h.read()).toEqual(h.prior)
    expect(
      h.ports.verifyAccessToken.mock.calls.every(([token]) => token === 'synthetic-test-token'),
    ).toBe(true)
  })
  it('binds fresh capture to the actual original receipt rather than accepting a new valid source for the same registration', async () => {
    const h = setup('root', { empty: true }),
      changed = structuredClone(parseFeedbackV3Capture(h.state.capture, h.who).context)
    if (changed.source.kind !== 'pending_registration' || !changed.source.command)
      throw new Error('Expected root command')
    const receipt = changed.source.command.receipt
    if (!receipt || typeof receipt !== 'object' || Array.isArray(receipt))
      throw new Error('Expected receipt')
    receipt.effect_version = `cmeal1:${'e'.repeat(64)}`
    expect(() => parseFeedbackV3Capture(changed, h.who)).not.toThrow()
    h.state.capture = changed
    expect(await h.ensure()).toBeNull()
    expect(canonicalNames(h)).toEqual([
      'read_mobile_registration_feedback_v3',
      'capture_mobile_registration_feedback_v3',
    ])
  })
  it('never returns canonical facts from a different owned effect merely sharing the registration ID', async () => {
    const h = setup('workout'),
      changed = structuredClone(h.prior)
    if (changed.registration.kind !== 'workout') throw new Error('Expected workout')
    changed.registration.duration_min = 31
    h.state.stored = changed
    expect(await h.read()).toBeNull()
    expect(canonicalNames(h)).toEqual(['read_mobile_registration_feedback_v3'])
  })
})

it('does not dispatch a concurrent operation after another observation closed the same original factory', async () => {
  const h = setup('root')
  let enter: () => void = () => {
    throw new Error('Gate not initialized')
  }
  let release: () => void = () => {
    throw new Error('Gate not initialized')
  }
  const entered = new Promise<void>((resolve) => {
    enter = resolve
  })
  const gate = new Promise<void>((resolve) => {
    release = resolve
  })
  let calls = 0
  h.clinical.capture.mockImplementation(async () => {
    if (++calls === 1) {
      enter()
      await gate
      return structuredClone(h.state.clinical)
    }
    throw new Error('Synthetic current scope observation failed')
  })
  const pending = h.read()
  await entered
  expect(await h.read()).toBeNull()
  release()
  expect(await pending).toBeNull()
  expect(h.rpc).not.toHaveBeenCalled()
})
