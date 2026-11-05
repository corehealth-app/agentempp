import { prepareRegistrationFeedbackV2 } from '@mpp/agent/registration-feedback-v2'
import {
  parseFeedbackV3Registration,
  prepareRegistrationFeedbackV3,
} from '@mpp/agent/registration-feedback-v3'
import type { ServiceClient } from '@mpp/db'
import { describe, expect, it, vi } from 'vitest'
import { publicFeedbackV3Fixture } from './__fixtures__/conversation-feedback-v3-presentation'
import { replyFixture, replyPresentation } from './__fixtures__/conversation-meal-reply'
import { conversationJournalBindingSchema } from './conversation-command-candidate-contracts'
import type { ConversationReadonlyAuth } from './conversation-current-scope'
import { createConversationFeedbackPublicComposition } from './conversation-feedback-public-composition'
import { createConversationMealCommandRoutes } from './conversation-meal-command-routes'
import type { ConversationMealCommandServicePorts } from './conversation-meal-command-service'
import { createConversationMealCommandService } from './conversation-meal-command-service'
import { parseConversationMealEffectReceipt } from './conversation-meal-feedback-store'
import { createConversationMealReplyPublicRoutes } from './conversation-meal-reply-public-routes'
import { createConversationMealReplyPublicService } from './conversation-meal-reply-public-service'
import { projectCurrentClinicalPublicPolicy } from './current-clinical-read-model'

const db = { rpc: vi.fn(), from: vi.fn() } as unknown as ServiceClient
function original(canonical: unknown) {
  return {
    ensureRoot: vi.fn().mockResolvedValue(canonical),
    readRoot: vi.fn().mockResolvedValue(canonical),
    ensureReply: vi.fn().mockResolvedValue(canonical),
    readReply: vi.fn().mockResolvedValue(canonical),
    ensureWorkout: vi.fn(),
    readWorkout: vi.fn(),
  }
}
function rootSetup(writer3 = false) {
  const f = publicFeedbackV3Fixture(),
    proof = f.proof
  if (proof.kind !== 'meal.report') throw new Error('Expected actual root proof')
  const p = {
    ...proof,
    serverBinding: conversationJournalBindingSchema.parse(proof.serverBinding),
    receipt: parseConversationMealEffectReceipt(proof.receipt, proof.command),
  }
  const bridge = original(f.canonical),
    scope = {
      auth: {
        verifyAccessToken: vi.fn<ConversationReadonlyAuth['verifyAccessToken']>(
          async () => f.who.identity,
        ),
        loadPatient: vi.fn<ConversationReadonlyAuth['loadPatient']>(async () => f.who.patient),
        isAdmin: vi.fn(async () => false),
      },
      clinical: { capture: async () => f.state },
    },
    feedbackV3 = vi.fn(() =>
      createConversationFeedbackPublicComposition(db, f.who, f.state.epoch, {
        ...scope,
        original: bridge,
      }),
    ),
    prepared = {
      action: 'available' as const,
      binding: p.serverBinding,
      source: p.command,
      receipt: f.receipt,
      resolved: null,
    },
    readPrepared = vi.fn().mockResolvedValue(prepared),
    commit = vi.fn(),
    readHistorical = vi.fn().mockResolvedValue(null),
    register = vi.fn<NonNullable<ConversationMealCommandServicePorts['register']>>(
      async (_db, _auth, _key, _raw, deps) => {
        if (deps.originalEnrichment)
          await deps.originalEnrichment.ensureOriginal({
            auth: f.who,
            command: p.command,
            receipt: f.receipt,
            serverBinding: p.serverBinding,
          })
        return {
          status: 'saved' as const,
          command: p.command,
          receipt: p.receipt,
          serverBinding: p.serverBinding,
          historicalFeedback: null,
        }
      },
    ),
    service = createConversationMealCommandService(db, {
      writer: { readPrepared, readEffect: vi.fn(), prepare: vi.fn(), commit },
      journal: () => ({
        read: vi.fn().mockResolvedValue(prepared),
        admit: vi.fn(),
        attach: vi.fn(),
      }),
      clinical: scope.clinical,
      auth: scope.auth,
      semantics: {
        read: vi.fn().mockResolvedValue({ action: 'absent' }),
        start: vi.fn(),
        commit: vi.fn(),
        markUnknown: vi.fn(),
      },
      decisions: { read: vi.fn().mockResolvedValue({ action: 'absent' }), seal: vi.fn() },
      register,
      createInterpreter: () => ({ interpret: vi.fn() }),
      presentation: { readHistorical },
      feedbackV3,
      feedbackV3WriterEnabled: () => writer3,
    })
  return {
    ...f,
    p,
    bridge,
    feedbackV3,
    readPrepared,
    commit,
    register,
    readHistorical,
    service,
    scope,
  }
}
describe('root public source/receipt-bound presentation composition', () => {
  it.each([
    '2',
    'unknown',
    'absent',
  ])('actual root public GET emits the compatible body and echo for %s', async (header) => {
    const f = rootSetup(),
      h = new Headers({
        'X-Conversation-Owner': f.p.command.ownerId,
        'X-Conversation-Epoch': f.state.epoch,
        'X-Conversation-Input-Hash': f.p.command.inputHash,
      })
    if (header !== 'absent') h.set('X-Conversation-Feedback-Presentation', header)
    const routes = createConversationMealCommandRoutes(
        { enabled: () => true, service: () => f.service },
        {
          createServiceClient: () => db,
          authenticate: async () => f.who,
          authorizeEntitlement: async () => {},
          createRequestId: () => 'unit-genuine-root',
        },
      ),
      response = await routes.GET(
        new Request(`https://app.invalid/${f.p.command.commandId}`, { headers: h }),
        { params: Promise.resolve({ commandId: f.p.command.commandId }) },
      ),
      packet = await response.json()
    expect(response.status).toBe(200)
    expect(packet.data.receipt).toEqual(f.receipt)
    expect(packet.data.feedback?.schema).toBe(
      header === '2' ? 'conversation.feedback-presentation.v2' : undefined,
    )
    expect(response.headers.get('X-Conversation-Feedback-Presentation')).toBe(
      header === '2' ? '2' : null,
    )
    expect(response.headers.get('Cache-Control')).toBe('no-store')
    expect(f.register).not.toHaveBeenCalled()
    expect(f.bridge.ensureRoot).not.toHaveBeenCalled()
  })
  it.each([
    'submit',
    'read',
  ] as const)('negotiated %s displays UNIT canonical3 from actual immutable root facts without effects or seal', async (method) => {
    const f = rootSetup(),
      result =
        method === 'submit'
          ? await f.service.submit(
              f.who,
              `cmsg1:${f.p.command.commandId}`,
              f.p.command.command,
              f.state.epoch,
              '2',
            )
          : await f.service.read(
              f.who,
              f.p.command.commandId,
              f.p.command.inputHash,
              f.state.epoch,
              '2',
            )
    expect(result).toMatchObject({
      status: 'saved',
      receipt: f.receipt,
      feedback: {
        schema: 'conversation.feedback-presentation.v2',
        recorded: f.canonical.registration,
      },
    })
    expect(f.bridge.readRoot).toHaveBeenCalledTimes(1)
    expect(f.bridge.ensureRoot).not.toHaveBeenCalled()
    expect(f.register).not.toHaveBeenCalled()
    expect(f.commit).not.toHaveBeenCalled()
  })
  it('header2 preserves an old winner and wrapper1 literally rather than relabeling it', async () => {
    const f = rootSetup(true),
      registration = f.canonical.registration
    if (registration.kind !== 'meal') throw new Error('Expected meal')
    const old = prepareRegistrationFeedbackV2({
      registrationId: f.receipt.registration_id,
      localDate: f.receipt.local_date,
      locale: 'pt-BR',
      registration,
      officialDay: null,
      policy: projectCurrentClinicalPublicPolicy(f.state),
      educationAvailable: false,
    })
    f.bridge.readRoot.mockResolvedValue(old)
    f.readHistorical.mockResolvedValue(f.legacyPresentation)
    const result = await f.service.read(
      f.who,
      f.p.command.commandId,
      f.p.command.inputHash,
      f.state.epoch,
      '2',
    )
    if (result.status !== 'saved') throw new Error('Expected saved original receipt')
    expect(result.feedback).toEqual(f.legacyPresentation)
    expect(result.feedback?.schema).toBe('conversation.feedback-presentation.v1')
    expect(f.bridge.ensureRoot).not.toHaveBeenCalled()
    expect(f.register).not.toHaveBeenCalled()
  })
  it('default noheader performs no extra canonical3 read and preserves literal factual ACK', async () => {
    const f = rootSetup(true),
      result = await f.service.read(
        f.who,
        f.p.command.commandId,
        f.p.command.inputHash,
        f.state.epoch,
      )
    expect(result).toMatchObject({ status: 'saved', receipt: f.receipt, feedback: null })
    expect(f.feedbackV3).not.toHaveBeenCalled()
    expect(f.bridge.ensureRoot).not.toHaveBeenCalled()
  })
  it.each([
    'legacy',
    '2',
  ] as const)('trusted writer3 runs after real receipt even with presentation %s and never changes command identity', async (selected) => {
    const f = rootSetup(true)
    f.readPrepared.mockResolvedValue({ action: 'absent' })
    const result = await f.service.submit(
      f.who,
      `cmsg1:${f.p.command.commandId}`,
      f.p.command.command,
      f.state.epoch,
      selected,
    )
    expect(result).toMatchObject({
      status: 'saved',
      command_id: f.p.command.commandId,
      input_hash: f.p.command.inputHash,
      receipt: f.receipt,
    })
    expect(f.bridge.ensureRoot).toHaveBeenCalledWith({
      auth: f.who,
      command: f.p.command,
      receipt: f.receipt,
      serverBinding: f.p.serverBinding,
    })
    expect(f.register).toHaveBeenCalledTimes(1)
    if (result.status !== 'saved') throw new Error('Expected saved original receipt')
    expect(result.feedback?.schema).toBe(
      selected === '2' ? 'conversation.feedback-presentation.v2' : undefined,
    )
  })
  it('header2 never enables writer3; failed optional display keeps saved receipt without register retry', async () => {
    const f = rootSetup()
    f.readPrepared.mockResolvedValue({ action: 'absent' })
    f.bridge.readRoot.mockRejectedValue(new Error('optional lost'))
    const result = await f.service.submit(
      f.who,
      `cmsg1:${f.p.command.commandId}`,
      f.p.command.command,
      f.state.epoch,
      '2',
    )
    expect(result).toMatchObject({ status: 'saved', receipt: f.receipt, feedback: null })
    expect(f.register).toHaveBeenCalledTimes(1)
    expect(f.register.mock.calls[0][4].originalEnrichment).toBeUndefined()
    expect(f.bridge.ensureRoot).not.toHaveBeenCalled()
  })
})

function replySetup(writer3 = false) {
  const f = replyFixture(),
    old = replyPresentation(f),
    receipt = f.state.reply?.receipt
  if (!receipt) throw new Error('Missing actual SQL receipt')
  // UNIT prepare with recorded facts from qualified SQL/renderer fixtures;
  // no claim of a canonical3 body observed over HTTP or sealed in SQL.
  const canonical = prepareRegistrationFeedbackV3({
      registrationId: receipt.registration_id,
      localDate: receipt.local_date,
      locale: 'pt-BR',
      registration: parseFeedbackV3Registration(old.recorded),
      officialDay: null,
      policy: projectCurrentClinicalPublicPolicy(f.profile),
      educationAvailable: false,
    }),
    bridge = original(canonical),
    auth = {
      verifyAccessToken: vi.fn(async () => f.auth.identity),
      loadPatient: async () => f.auth.patient,
      isAdmin: async () => false,
    },
    clinical = { capture: vi.fn(async () => f.profile) },
    feedbackV3 = vi.fn(() =>
      createConversationFeedbackPublicComposition(db, f.auth, f.identity.epoch, {
        auth,
        clinical,
        original: bridge,
      }),
    ),
    submit = vi.fn().mockResolvedValue({
      status: 'saved',
      identity: f.identity,
      receipt,
      historicalFeedback: null,
      feedbackGate: 'continuation_feedback_v2_unavailable',
    }),
    ensureOriginal = vi.fn(),
    readHistorical = vi.fn().mockResolvedValue(null),
    read = vi.fn().mockResolvedValue(f.state),
    service = createConversationMealReplyPublicService(db, {
      auth,
      clinical,
      reader: { read },
      processor: () => ({ submit }),
      feedback: () => ({ ensureOriginal, readHistorical }),
      feedbackV3,
      feedbackV3WriterEnabled: () => writer3,
    })
  return {
    ...f,
    read,
    canonical,
    bridge,
    feedbackV3,
    submit,
    ensureOriginal,
    readHistorical,
    service,
    receipt,
    clinical,
  }
}
describe('linked public presentation composition', () => {
  it('actual linked GET emits wrapper2 with original receipt and independent reply protocol', async () => {
    const f = replySetup(true),
      i = f.identity,
      routes = createConversationMealReplyPublicRoutes(
        { enabled: () => true, service: () => f.service },
        {
          createServiceClient: () => db,
          authenticate: async () => f.auth,
          authorizeEntitlement: async () => {},
          createRequestId: () => 'unit-sql-linked',
        },
      ),
      response = await routes.GET(
        new Request(
          `https://app.invalid/${i.parentCommandId}/${i.replyId}?parent_input_hash=${i.parentInputHash}&reply_input_hash=${i.replyInputHash}`,
          {
            headers: {
              'X-Conversation-Owner': i.ownerId,
              'X-Conversation-Epoch': i.epoch,
              'X-Conversation-Feedback-Presentation': '2',
            },
          },
        ),
        { params: Promise.resolve({ commandId: i.parentCommandId, replyId: i.replyId }) },
      ),
      packet = await response.json()
    expect(response.status).toBe(200)
    expect(packet.data.receipt).toEqual(f.receipt)
    expect(packet.data.feedback.schema).toBe('conversation.feedback-presentation.v2')
    expect(response.headers.get('X-Conversation-Feedback-Presentation')).toBe('2')
    expect(response.headers.get('X-Conversation-Protocol')).toBe('meal-reply-v1')
    expect(f.submit).not.toHaveBeenCalled()
    expect(f.bridge.ensureReply).not.toHaveBeenCalled()
  })
  it.each([
    'submit',
    'read',
  ] as const)('negotiated linked %s preserves parent/child lineage and actual receipt', async (method) => {
    const f = replySetup(true),
      i = f.identity,
      result =
        method === 'submit'
          ? await f.service.submit(f.auth, i.parentCommandId, i.epoch, f.submission, f.key, '2')
          : await f.service.reconcile(
              f.auth,
              i.parentCommandId,
              i.replyId,
              i.epoch,
              { parent_input_hash: i.parentInputHash, reply_input_hash: i.replyInputHash },
              '2',
            )
    expect(result).toMatchObject({
      status: 'saved',
      receipt: f.receipt,
      feedback: {
        schema: 'conversation.feedback-presentation.v2',
        recorded: f.canonical.registration,
      },
    })
    expect(f.bridge.readReply).toHaveBeenCalledWith({
      auth: f.auth,
      binding: {
        parentBinding: f.state.parent.binding,
        childBinding: f.state.reply?.binding,
        parentDecisionHash: f.state.parent.decision.decision_hash,
        receipt: f.receipt,
      },
    })
    expect(f.bridge.ensureReply).not.toHaveBeenCalled()
    expect(f.submit).not.toHaveBeenCalled()
    expect(f.ensureOriginal).not.toHaveBeenCalled()
  })
  it('unknown/default selection keeps old display literal with no extra reader or new ensure', async () => {
    const f = replySetup(),
      i = f.identity
    f.readHistorical.mockResolvedValue(replyPresentation(f))
    const result = await f.service.reconcile(f.auth, i.parentCommandId, i.replyId, i.epoch, {
      parent_input_hash: i.parentInputHash,
      reply_input_hash: i.replyInputHash,
    })
    expect(result.feedback).toEqual(replyPresentation(f))
    expect(f.feedbackV3).not.toHaveBeenCalled()
    expect(f.ensureOriginal).not.toHaveBeenCalled()
  })
  it('only enriches a new linked success; a lost submit body recovers by canonical read alone', async () => {
    for (const lost of [false, true]) {
      const f = replySetup(true),
        i = f.identity
      f.read.mockResolvedValueOnce(replyFixture('prepared').state)
      if (lost) f.submit.mockRejectedValue(new Error('lost body'))
      const result = await f.service.submit(
        f.auth,
        i.parentCommandId,
        i.epoch,
        f.submission,
        f.key,
        '2',
      )
      expect(result).toMatchObject({
        status: 'saved',
        receipt: f.receipt,
        feedback: { schema: 'conversation.feedback-presentation.v2' },
      })
      expect(f.bridge.ensureReply).toHaveBeenCalledTimes(lost ? 0 : 1)
      expect(f.bridge.readReply).toHaveBeenCalledTimes(1)
      expect(f.submit).toHaveBeenCalledTimes(1)
    }
  })
  it('optional canonical3 failure preserves factual ACK and never retries submit', async () => {
    const f = replySetup(true),
      i = f.identity
    f.read.mockResolvedValueOnce(replyFixture('prepared').state)
    f.bridge.ensureReply.mockRejectedValue(new Error('lost seal'))
    f.bridge.readReply.mockRejectedValue(new Error('lost read'))
    const result = await f.service.submit(
      f.auth,
      i.parentCommandId,
      i.epoch,
      f.submission,
      f.key,
      '2',
    )
    expect(result).toMatchObject({ status: 'saved', receipt: f.receipt, feedback: null })
    expect(f.submit).toHaveBeenCalledTimes(1)
  })
})

it.each(
  (['legacy', '2'] as const).flatMap((selected) =>
    ['submit', 'read'].flatMap((method) => [
      { method, selected, refusal: 'admin', code: 'patient_admin_account_conflict' },
      { method, selected, refusal: 'inactive', code: 'patient_account_inactive' },
      { method, selected, refusal: 'mapping', code: 'conversation_patient_changed' },
      { method, selected, refusal: 'token', code: 'invalid_access_token' },
    ]),
  ),
)('root $method ($selected) keeps mandatory $refusal refusal', async ({
  method,
  selected,
  refusal,
  code,
}) => {
  const f = rootSetup(),
    refuse = async () => {
      if (refusal === 'admin') f.scope.auth.isAdmin.mockResolvedValue(true)
      else if (refusal === 'inactive')
        f.scope.auth.loadPatient.mockResolvedValue({ ...f.who.patient, status: 'inactive' })
      else if (refusal === 'mapping')
        f.scope.auth.loadPatient.mockResolvedValue({ ...f.who.patient, id: f.who.authUserId })
      else f.scope.auth.verifyAccessToken.mockResolvedValue(null)
      return null
    }
  if (selected === '2') f.bridge.readRoot.mockImplementationOnce(refuse)
  else f.readHistorical.mockImplementationOnce(refuse)
  const work =
    method === 'submit'
      ? f.service.submit(
          f.who,
          `cmsg1:${f.p.command.commandId}`,
          f.p.command.command,
          f.state.epoch,
          selected,
        )
      : f.service.read(f.who, f.p.command.commandId, f.p.command.inputHash, f.state.epoch, selected)
  await expect(work).rejects.toMatchObject({ code })
  if (selected === '2') expect(f.readHistorical).not.toHaveBeenCalled()
  else expect(f.readHistorical).toHaveBeenCalledTimes(1)
  expect(f.commit).not.toHaveBeenCalled()
})
