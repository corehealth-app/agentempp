/** Actual private continuation processing behind a current, read-only Auth
 * guard. Unknown writes reconcile by reading; no retry or new identity exists. */
import { isDeepStrictEqual } from 'node:util'
import type { ServiceClient } from '@mpp/db'
import { z } from 'zod'
import type { MobileAuthContext } from './auth'
import { createSupabaseConversationMealContinuationFeedback } from './conversation-meal-continuation-feedback'
import {
  type ConversationMealContinuationReadIdentity,
  detachConversationContinuationReadJson,
  parseConversationMealContinuationRead,
} from './conversation-meal-continuation-read-contracts'
import {
  type ConversationMealContinuationReadStore,
  createSupabaseConversationMealContinuationReadStore,
} from './conversation-meal-continuation-read-store'
import type {
  ConversationMealContinuationScope,
  ConversationMealContinuationServiceDependencies,
} from './conversation-meal-continuation-service'
import { createConversationMealContinuationService } from './conversation-meal-continuation-service'
import { freezeInterpretation } from './conversation-meal-interpretation-contracts'
import {
  bindConversationMealReplySubmission,
  type ConversationMealReplyIdentity,
  conversationMealReplyUnavailable,
  parseConversationMealReplyIdentity,
  projectConversationMealReplyResult,
} from './conversation-meal-reply-public-contracts'
import {
  type ConversationMealReplyScopeDependencies,
  createConversationMealReplyScope,
} from './conversation-meal-reply-scope'
import { MobileApiError } from './http'
import { authenticatedReevaluationOwner } from './reevaluation-cycle-service'

export interface ConversationMealReplyFeedbackInput {
  readonly auth: MobileAuthContext
  readonly binding: {
    readonly parentBinding: Extract<
      Awaited<ReturnType<ConversationMealContinuationReadStore['read']>>,
      { action: 'available' }
    >['parent']['binding']
    readonly childBinding: NonNullable<
      Extract<
        Awaited<ReturnType<ConversationMealContinuationReadStore['read']>>,
        { action: 'available' }
      >['reply']
    >['binding']
    readonly parentDecisionHash: string
    readonly receipt: NonNullable<
      NonNullable<
        Extract<
          Awaited<ReturnType<ConversationMealContinuationReadStore['read']>>,
          { action: 'available' }
        >['reply']
      >['receipt']
    >
  }
}
export interface ConversationMealReplyFeedbackPort {
  ensureOriginal(input: ConversationMealReplyFeedbackInput): Promise<unknown>
  readHistorical(input: ConversationMealReplyFeedbackInput): Promise<unknown>
}
export interface ConversationMealReplyPublicPorts extends ConversationMealReplyScopeDependencies {
  readonly reader?: ConversationMealContinuationReadStore
  readonly processor?: (
    db: ServiceClient,
    dependencies: Pick<ConversationMealContinuationServiceDependencies, 'checkCurrentScope'>,
  ) => Pick<ReturnType<typeof createConversationMealContinuationService>, 'submit'>
  /** Optional test/application port; the production default is the qualified
   * linked adapter. GET invokes only historical reads, never enrichment. */
  readonly feedback?: (
    db: ServiceClient,
    checkCurrentScope: (scope: ConversationMealReplyFeedbackInput) => Promise<boolean>,
  ) => ConversationMealReplyFeedbackPort
}
function changed(action: string): never {
  throw new MobileApiError(
    409,
    `conversation_meal_reply_${action}`,
    'The original linked meal state has changed',
  )
}
export function createConversationMealReplyPublicService(
  db: ServiceClient,
  ports: ConversationMealReplyPublicPorts = {},
) {
  const rpc = db.rpc.bind(db),
    from = db.from.bind(db),
    sdk = new Proxy(db, {
      get(target, key, receiver) {
        if (key === 'rpc') return rpc
        if (key === 'from') return from
        return Reflect.get(target, key, receiver)
      },
    })
  const r = ports.reader ?? createSupabaseConversationMealContinuationReadStore(sdk),
    read = r.read.bind(r),
    processor = ports.processor?.bind(ports) ?? createConversationMealContinuationService,
    feedbackFactory =
      ports.feedback?.bind(ports) ??
      ((
        sdk: ServiceClient,
        check: (scope: ConversationMealReplyFeedbackInput) => Promise<boolean>,
      ) =>
        createSupabaseConversationMealContinuationFeedback(sdk, {
          checkCurrentScope: check,
          ...(scopeDependencies.clinical ? { clinicalSource: scopeDependencies.clinical } : {}),
        }))
  const scopeDependencies: ConversationMealReplyScopeDependencies = Object.freeze({
    ...(ports.auth
      ? {
          auth: Object.freeze({
            verifyAccessToken: ports.auth.verifyAccessToken.bind(ports.auth),
            loadPatient: ports.auth.loadPatient.bind(ports.auth),
            isAdmin: ports.auth.isAdmin.bind(ports.auth),
          }),
        }
      : {}),
    ...(ports.clinical
      ? { clinical: Object.freeze({ capture: ports.clinical.capture.bind(ports.clinical) }) }
      : {}),
  })
  async function run(
    who: MobileAuthContext,
    identity: ConversationMealReplyIdentity,
    bound: ReturnType<typeof bindConversationMealReplySubmission> | null,
  ) {
    const scope = createConversationMealReplyScope(sdk, who, identity, scopeDependencies)
    await scope.observe()
    let outcome: unknown = null
    if (bound) {
      const process = processor(sdk, {
          checkCurrentScope: (s: ConversationMealContinuationScope) => scope.check(s),
        }),
        submit = process.submit.bind(process)
      try {
        outcome = await submit(who, bound.reply)
      } catch {
        /* one actual read below, no second submit */
      }
      await scope.observe()
      try {
        const quota = z
          .object({
            status: z.literal('held'),
            identity: z.unknown(),
            reason: z.literal('rate_limited'),
          })
          .strict()
          .safeParse(detachConversationContinuationReadJson(outcome))
        if (
          quota.success &&
          isDeepStrictEqual(
            parseConversationMealReplyIdentity(
              quota.data.identity as ConversationMealContinuationReadIdentity,
            ),
            identity,
          )
        )
          throw new MobileApiError(
            429,
            'conversation_meal_reply_rate_limited',
            'Too many new conversation commands; reconcile before retrying',
          )
      } catch (error) {
        if (error instanceof MobileApiError && error.status === 429) throw error
      }
    }
    async function actual(i: ConversationMealContinuationReadIdentity) {
      await scope.observe()
      let raw: unknown
      try {
        raw = await read(i)
      } catch {
        await scope.observe()
        return conversationMealReplyUnavailable()
      }
      await scope.observe()
      return parseConversationMealContinuationRead(raw, i)
    }
    const first = await actual(identity)
    let proof: { kind: 'reply' | 'parent_only_after_reply_conflict'; state: unknown }
    if (first.action === 'available') proof = { kind: 'reply', state: first }
    else if (first.action === 'reply_conflict') {
      const parent = await actual({
        ownerId: identity.ownerId,
        parentCommandId: identity.parentCommandId,
        parentInputHash: identity.parentInputHash,
        epoch: identity.epoch,
      })
      if (parent.action !== 'available') return changed(parent.action)
      proof = { kind: 'parent_only_after_reply_conflict', state: parent }
    } else return changed(first.action)
    const state = proof.state as Extract<
      Awaited<ReturnType<typeof actual>>,
      { action: 'available' }
    >
    if (bound && state.parent.decision.decision_hash !== bound.submission.parent_decision_hash)
      return changed('decision_conflict')
    if (bound && state.reply && !isDeepStrictEqual(state.reply.body, bound.reply.input))
      return changed('input_conflict')
    let feedback: unknown = null
    if (
      proof.kind === 'reply' &&
      state.reply?.state === 'saved' &&
      state.reply.receipt &&
      state.fulfillment?.child_binding.command_id === identity.replyId &&
      feedbackFactory
    ) {
      await scope.observe()
      try {
        const input = freezeInterpretation({
            auth: who,
            binding: {
              parentBinding: state.parent.binding,
              childBinding: state.reply.binding,
              parentDecisionHash: state.parent.decision.decision_hash,
              receipt: state.reply.receipt,
            },
          }),
          port = feedbackFactory(
            sdk,
            async (candidate) =>
              isDeepStrictEqual(detachConversationContinuationReadJson(candidate), input) &&
              scope.check(),
          ),
          methods = Object.getOwnPropertyDescriptors(port),
          ensureMethod = methods.ensureOriginal,
          historicalMethod = methods.readHistorical
        if (
          !ensureMethod ||
          !('value' in ensureMethod) ||
          typeof ensureMethod.value !== 'function' ||
          !historicalMethod ||
          !('value' in historicalMethod) ||
          typeof historicalMethod.value !== 'function'
        )
          throw new Error('Optional historical adapter unavailable')
        const ensure = ensureMethod.value.bind(
            port,
          ) as ConversationMealReplyFeedbackPort['ensureOriginal'],
          historical = historicalMethod.value.bind(
            port,
          ) as ConversationMealReplyFeedbackPort['readHistorical']
        if (bound) {
          try {
            await ensure(input)
          } catch {
            /* optional seal failure never repeats factual food */
          }
          await scope.observe()
        }
        feedback = await historical(input)
      } catch {
        feedback = null
      }
    }
    const observation = await scope.observe()
    return projectConversationMealReplyResult({
      auth: who,
      identity,
      proof,
      observation,
      mode: bound ? 'submit' : 'read',
      outcome,
      feedback,
    })
  }
  return Object.freeze({
    async submit(
      auth: MobileAuthContext,
      parentCommandId: string,
      epoch: string,
      raw: unknown,
      idempotencyKey: string | null,
    ) {
      const who = freezeInterpretation(
          detachConversationContinuationReadJson(auth) as MobileAuthContext,
        ),
        owner = authenticatedReevaluationOwner(who),
        bound = bindConversationMealReplySubmission({
          ownerId: owner,
          parentCommandId,
          epoch,
          idempotencyKey,
          body: raw,
        }),
        i = parseConversationMealReplyIdentity({
          ownerId: owner,
          parentCommandId,
          parentInputHash: bound.submission.parent_input_hash,
          epoch,
          replyId: bound.submission.reply_id,
          replyInputHash: bound.reply.inputHash,
        })
      return run(who, i, bound)
    },
    async reconcile(
      auth: MobileAuthContext,
      parentCommandId: string,
      replyId: string,
      epoch: string,
      query: { parent_input_hash: string; reply_input_hash: string },
    ) {
      const who = freezeInterpretation(
          detachConversationContinuationReadJson(auth) as MobileAuthContext,
        ),
        owner = authenticatedReevaluationOwner(who),
        q = z
          .object({
            parent_input_hash: z.string().regex(/^[a-f0-9]{64}$/u),
            reply_input_hash: z.string().regex(/^[a-f0-9]{64}$/u),
          })
          .strict()
          .parse(detachConversationContinuationReadJson(query)),
        i = parseConversationMealReplyIdentity({
          ownerId: owner,
          parentCommandId,
          parentInputHash: q.parent_input_hash,
          epoch,
          replyId,
          replyInputHash: q.reply_input_hash,
        })
      return run(who, i, null)
    },
  })
}
