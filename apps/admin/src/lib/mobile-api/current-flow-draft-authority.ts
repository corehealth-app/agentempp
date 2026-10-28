/** Backend-only SQL draft authority. No default route, flag or activation.
 * The expected context and original inbound stay in a request-owned closure. */
import type {
  FlowClinicalCreatedDraft,
  FlowClinicalDraftCreate,
  FlowClinicalDraftKey,
  FlowClinicalStoredDraft,
} from '@mpp/agent'
import type { ServiceClient } from '@mpp/db'
import { z } from 'zod'
import {
  currentClinicalError,
  projectCurrentClinicalState,
  readCurrentClinicalState,
} from './current-clinical-state'
import { hashMobileRequest } from './idempotency'

const uuid = z.string().uuid()
const key = z
  .object({
    domain: z.enum(['training', 'nutrition']),
    requestKey: z.string().regex(/^[A-Za-z0-9._:/-]{8,200}$/),
  })
  .strict()
const wire = z
  .object({
    version: z.literal(1),
    state: z.unknown(),
    day: z
      .object({
        snapshot_id: uuid,
        date: z.string().regex(/^\d{4}-\d{2}-\d{2}$/),
        calories_target: z.number().finite().nullable(),
        protein_target: z.number().finite().nullable(),
        current_protocol: z.enum(['recomposicao', 'ganho_massa', 'manutencao']).nullable(),
        target_revision: z.string().regex(/^(0|[1-9][0-9]{0,18})$/),
        calorie_origin: z.unknown().refine((v) => v !== undefined),
      })
      .strict()
      .nullable(),
    allowed: z.object({ training: z.boolean(), nutrition: z.boolean() }).strict(),
  })
  .strict()
function record(v: unknown): v is Record<string, unknown> {
  return !!v && typeof v === 'object' && !Array.isArray(v)
}
function freeze<T>(v: T): T {
  if (v && typeof v === 'object') {
    for (const c of Object.values(v)) freeze(c)
    Object.freeze(v)
  }
  return v
}
export function readCurrentFlowDraftContext(raw: unknown, owner: string) {
  try {
    const value = wire.parse(structuredClone(raw)),
      state = readCurrentClinicalState(value.state, owner),
      day = value.day,
      policy = projectCurrentClinicalState(state),
      training = !policy.hide.objective,
      nutrition =
        training &&
        !policy.pauseWeightLossGuidance &&
        !policy.hide.calories &&
        !policy.hide.protein &&
        day !== null &&
        day.calories_target !== null &&
        day.calories_target > 0 &&
        day.protein_target !== null &&
        day.protein_target > 0
    if (
      value.allowed.training !== training ||
      value.allowed.nutrition !== nutrition ||
      (day && day.date !== state.date)
    )
      throw new Error('invalid')
    if (day && day.calorie_origin !== null) {
      const origin = day.calorie_origin
      if (
        !record(origin) ||
        origin.user_id !== owner ||
        origin.snapshot_id !== day.snapshot_id ||
        origin.date !== day.date ||
        origin.signup_generation !== state.signup_generation ||
        origin.signup_epoch !== state.epoch ||
        origin.calories_target !== day.calories_target ||
        origin.phase !== day.current_protocol ||
        origin.version !== 1 ||
        origin.target_component !== 'calories' ||
        ![
          'clinical_signup_v1',
          'clinical_first_phase_v1',
          'clinical_daily_v1',
          'clinical_full_v1',
        ].includes(String(origin.source))
      )
        throw new Error('invalid')
    }
    return freeze({ version: 1 as const, state, day, allowed: value.allowed })
  } catch {
    throw currentClinicalError('invalid_response')
  }
}
export type CurrentFlowDraftContext = ReturnType<typeof readCurrentFlowDraftContext>
export function currentFlowDraftBinding(context: CurrentFlowDraftContext) {
  const state = structuredClone(context.state) as unknown as Record<string, unknown>
  delete state.observed_at
  delete state.context_hash
  if (record(state.safety)) delete state.safety.observed_at
  return hashMobileRequest({ version: 1, state, day: context.day, allowed: context.allowed })
}
export interface CurrentFlowDraftLookup extends FlowClinicalDraftKey {
  sourceMessageId: string
  expected: CurrentFlowDraftContext
}
export interface CurrentFlowDraftWrite extends FlowClinicalDraftCreate {
  sourceMessageId: string
  expected: CurrentFlowDraftContext
}
export interface CurrentFlowDraftAuthority {
  capture(): Promise<unknown>
  findTurn(input: Readonly<FlowClinicalDraftKey>): Promise<string>
  lookup(input: Readonly<CurrentFlowDraftLookup>): Promise<FlowClinicalStoredDraft | null>
  create(input: Readonly<CurrentFlowDraftWrite>): Promise<FlowClinicalCreatedDraft>
}
export function bindCurrentFlowDraftAuthority(
  source: CurrentFlowDraftAuthority,
): CurrentFlowDraftAuthority {
  return Object.freeze({
    capture: source.capture.bind(source),
    findTurn: source.findTurn.bind(source),
    lookup: source.lookup.bind(source),
    create: source.create.bind(source),
  })
}
const stored = z.object({
  id: uuid,
  status: z.enum([
    'extracting',
    'generating',
    'needs_completion',
    'ready_for_review',
    'confirmed',
    'discarded',
    'expired',
    'failed',
  ]),
  payload: z.record(z.unknown()).nullable(),
})
export function readCurrentFlowStoredDraft(raw: unknown): FlowClinicalStoredDraft {
  try {
    return freeze(stored.parse(structuredClone(raw)))
  } catch {
    throw currentClinicalError('invalid_response')
  }
}
export function readCurrentFlowCreatedDraft(raw: unknown): FlowClinicalCreatedDraft {
  const base = readCurrentFlowStoredDraft(raw)
  if (!record(raw) || typeof raw.inserted !== 'boolean')
    throw currentClinicalError('invalid_response')
  return freeze({ ...base, inserted: raw.inserted })
}
type DraftRpc = (
  name:
    | 'get_mobile_flow_plan_context'
    | 'lookup_mobile_flow_plan_draft'
    | 'create_mobile_flow_plan_draft',
  args: Record<string, unknown>,
) => PromiseLike<unknown>
export function createSupabaseCurrentFlowDraftAuthority(
  client: ServiceClient,
  ownerID: string,
): CurrentFlowDraftAuthority {
  const owner = uuid.parse(ownerID),
    rpc = client.rpc.bind(client) as unknown as DraftRpc,
    from = client.from.bind(client)
  async function call(name: Parameters<DraftRpc>[0], args: Record<string, unknown>) {
    const input = freeze(structuredClone(args))
    let envelope: unknown
    try {
      envelope = await rpc(name, input)
    } catch {
      throw currentClinicalError('unavailable')
    }
    if (!record(envelope) || !Object.hasOwn(envelope, 'data') || !Object.hasOwn(envelope, 'error'))
      throw currentClinicalError('invalid_response')
    if (envelope.error !== null) {
      if (!record(envelope.error)) throw currentClinicalError('invalid_response')
      const code = envelope.error.code
      if (['40001', 'P0002', '23514', 'PD409'].includes(String(code)))
        throw currentClinicalError('changed')
      if (code === '55P03') throw currentClinicalError('busy')
      throw currentClinicalError('unavailable')
    }
    return envelope.data
  }
  function parameters(input: Readonly<CurrentFlowDraftLookup>) {
    const selected = key.parse({ domain: input.domain, requestKey: input.requestKey }),
      expected = readCurrentFlowDraftContext(input.expected, owner)
    return {
      p_user_id: owner,
      p_domain: selected.domain,
      p_request_key: selected.requestKey,
      p_source_message_id: uuid.parse(input.sourceMessageId),
      p_expected: expected,
    }
  }
  return Object.freeze({
    async capture() {
      return readCurrentFlowDraftContext(
        await call('get_mobile_flow_plan_context', { p_user_id: owner }),
        owner,
      )
    },
    async findTurn(input: Readonly<FlowClinicalDraftKey>) {
      const selected = key.parse({ domain: input.domain, requestKey: input.requestKey }),
        suffix = selected.domain === 'training' ? ':propoe_plano_treino' : ':propoe_plano_dieta'
      if (!selected.requestKey.endsWith(suffix)) throw currentClinicalError('invalid_response')
      let result: unknown
      try {
        result = await from('messages')
          .select('id')
          .eq('user_id', owner)
          .eq('provider', 'mobile_flow')
          .eq('direction', 'in')
          .eq('role', 'user')
          .eq('provider_message_id', selected.requestKey.slice(0, -suffix.length))
          .maybeSingle()
      } catch {
        throw currentClinicalError('unavailable')
      }
      if (!record(result) || result.error !== null) throw currentClinicalError('unavailable')
      if (!record(result.data)) throw currentClinicalError('changed')
      const id = uuid.safeParse(result.data.id)
      if (!id.success) throw currentClinicalError('invalid_response')
      return id.data
    },
    async lookup(input: Readonly<CurrentFlowDraftLookup>) {
      const result = await call('lookup_mobile_flow_plan_draft', parameters(input))
      return result === null ? null : readCurrentFlowStoredDraft(result)
    },
    async create(input: Readonly<CurrentFlowDraftWrite>) {
      const args = parameters(input),
        status = z.enum(['needs_completion', 'ready_for_review']).parse(input.status),
        payload = z.record(z.unknown()).parse(input.payload),
        uncertain = z.array(z.unknown()).parse(input.uncertainFields),
        detail = z.record(z.unknown()).parse(input.originDetail)
      return readCurrentFlowCreatedDraft(
        await call('create_mobile_flow_plan_draft', {
          ...args,
          p_status: status,
          p_payload: payload,
          p_uncertain_fields: uncertain,
          p_origin_detail: detail,
        }),
      )
    },
  })
}
