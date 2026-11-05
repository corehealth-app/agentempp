/** Per-operation physical RPC guard. No global cache, route, registration writer
 * or permissive default scope. Scope failure survives internal error handling. */
import { isDeepStrictEqual } from 'node:util'
import {
  parseRegistrationFeedbackV3,
  type RegistrationFeedbackV3,
} from '@mpp/agent/registration-feedback-v3'
import { z } from 'zod'
import {
  type CanonicalRegistrationFeedback,
  type FeedbackV3Identity,
  type FeedbackV3Observation,
  freezeFeedbackV3,
  parseCanonicalRegistrationFeedback,
  parseFeedbackV3Capture,
  pinFeedbackV3Identity,
} from './registration-feedback-v3-contracts'

type RPCName =
  | 'read_mobile_registration_feedback_v3'
  | 'capture_mobile_registration_feedback_v3'
  | 'commit_mobile_registration_feedback_v3'
export interface FeedbackV3RPCPort {
  rpc(name: RPCName, args: Readonly<Record<string, unknown>>): PromiseLike<unknown>
}
export interface FeedbackV3Scope {
  /** Must freshly verify actual Auth/admin/patient mapping and the caller's
   * pinned current clinical epoch. This callback is a backend capability. */
  checkCurrentScope(
    identity: Readonly<{
      owner_id: string
      registration_id: string
      origin: FeedbackV3Identity['origin']
      kind: FeedbackV3Identity['kind']
    }>,
  ): Promise<boolean>
}
export type FeedbackV3Read =
  | { action: 'available'; feedback: CanonicalRegistrationFeedback }
  | { action: 'absent' | 'event_conflict' }
export type FeedbackV3Capture =
  | { action: 'available'; observation: FeedbackV3Observation }
  | { action: 'event_conflict' }
export type FeedbackV3Commit =
  | { action: 'committed' | 'replay'; feedback: CanonicalRegistrationFeedback }
  | { action: 'source_conflict' | 'event_conflict' }
const available = z.object({ action: z.literal('available'), feedback: z.unknown() }).strict()
const absent = z.object({ action: z.literal('absent') }).strict()
const conflict = z.object({ action: z.literal('event_conflict') }).strict()
function unavailable(): never {
  throw new Error('Registration feedback unavailable')
}
export function createRegistrationFeedbackV3Store(
  rawPort: FeedbackV3RPCPort,
  rawScope: FeedbackV3Scope,
  rawIdentity: FeedbackV3Identity,
) {
  const identity = pinFeedbackV3Identity(rawIdentity),
    rpc = rawPort.rpc.bind(rawPort),
    check = rawScope.checkCurrentScope.bind(rawScope)
  const scope = freezeFeedbackV3({
    owner_id: identity.userId,
    registration_id: identity.registrationId,
    origin: identity.origin,
    kind: identity.kind,
  })
  const args = freezeFeedbackV3({
    p_user_id: identity.userId,
    p_registration_id: identity.registrationId,
    p_origin: identity.origin,
  })
  let closed = false
  async function current() {
    if (closed) unavailable()
    try {
      if ((await check(scope)) !== true || closed) unavailable()
    } catch {
      closed = true
      unavailable()
    }
  }
  async function observe<T>(read: () => PromiseLike<T>): Promise<T> {
    await current()
    let value: T
    try {
      value = structuredClone(await read())
    } catch {
      await current()
      return unavailable()
    }
    await current()
    return value
  }
  async function call(name: RPCName, body: Readonly<Record<string, unknown>>) {
    const pinned = freezeFeedbackV3(structuredClone(body))
    const raw = await observe(() => rpc(name, pinned))
    const envelope = z
      .object({ data: z.unknown(), error: z.unknown() })
      .passthrough()
      .parse(structuredClone(raw))
    if (envelope.error !== null) unavailable()
    return envelope.data
  }
  const store = {
    scopeClosed: () => closed,
    withCurrentScope: observe,
    async readReceipt(): Promise<FeedbackV3Read> {
      const value = z
        .discriminatedUnion('action', [available, absent, conflict])
        .parse(await call('read_mobile_registration_feedback_v3', args))
      return value.action === 'available'
        ? {
            action: 'available',
            feedback: parseCanonicalRegistrationFeedback(value.feedback, identity),
          }
        : value
    },
    async capture(): Promise<FeedbackV3Capture> {
      const value = z
        .discriminatedUnion('action', [
          z.object({ action: z.literal('available'), context: z.unknown() }).strict(),
          conflict,
        ])
        .parse(await call('capture_mobile_registration_feedback_v3', args))
      return value.action === 'available'
        ? { action: 'available', observation: parseFeedbackV3Capture(value.context, identity) }
        : value
    },
    async commit(
      rawObservation: FeedbackV3Observation,
      rawFeedback: RegistrationFeedbackV3,
    ): Promise<FeedbackV3Commit> {
      const observation = parseFeedbackV3Capture(rawObservation.context, identity)
      const feedback = freezeFeedbackV3(
        parseRegistrationFeedbackV3(structuredClone(rawFeedback), {
          registrationId: identity.registrationId,
          kind: identity.kind,
        }),
      )
      const value = z
        .discriminatedUnion('action', [
          z.object({ action: z.literal('committed'), feedback: z.unknown() }).strict(),
          z.object({ action: z.literal('replay'), feedback: z.unknown() }).strict(),
          z.object({ action: z.literal('source_conflict') }).strict(),
          conflict,
        ])
        .parse(
          await call('commit_mobile_registration_feedback_v3', {
            ...args,
            p_expected_context: observation.context,
            p_feedback: feedback,
          }),
        )
      if (value.action !== 'committed' && value.action !== 'replay') return value
      const saved = parseCanonicalRegistrationFeedback(value.feedback, identity)
      if (value.action === 'committed' && !isDeepStrictEqual(saved, feedback)) unavailable()
      return { action: value.action, feedback: saved }
    },
  }
  return Object.freeze(store)
}
