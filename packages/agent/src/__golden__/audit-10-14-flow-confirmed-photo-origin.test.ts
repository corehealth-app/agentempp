/**
 * B4c, 2026-10-14 — confirmed signup photo origin in the real Flow model context.
 * Test first: current pipeline calls the model but omits the exact suffix.
 * Synthetic external database/model only; no model, network, SQL or Storage call.
 * The strict canonical RPC answer is available before the production read exists.
 * Do not move its GREEN call-count oracle before the causal suffix assertion.
 *
 * The invalidated receipt is persisted synthetic truth. This suite does not prove
 * SQL trigger atomicity, clinical validity or the wording of a real LLM response.
 * Harness adapted from audit-10-04-flow-prompt-budget.test.ts; old files unchanged.
 */
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import { clearCalcConfigCache } from '../calc-config-loader.js'
import { flowCapabilities } from '../flow-capabilities.js'
import type { PipelineDeps } from '../pipeline.js'
import { processAuthenticatedMessage, processMessage } from '../pipeline.js'
import { resetRouterFlagCacheForTests } from '../router-flag.js'

const NOW = new Date('2026-10-04T15:03:40.503Z')
const GENERATION = '2026-10-03T12:00:00.123456+00:00'
const USER_ID = '00000000-0000-4000-8000-000000000951'
const OTHER_USER = '00000000-0000-4000-8000-000000000952'
const TURN_ID = 'mobile_flow/synthetic/b4c-photo-origin'
const FROM = 'synthetic-b4c-only'
const PHRASE = 'O treino de hoje aumenta minha meta de calorias?'
const MODEL = 'anthropic/claude-sonnet-4.6'
const REPLY = 'B4C_MODEL_RESPONSE'
const RPC = 'get_mobile_signup_body_photo_snapshot'
const SUFFIX = ' (estimativa por fotos, confirmada pela pessoa; não é medida)'
const BARE_LINE = '- Gordura corporal: 22.1%'
const CONFIRMED_LINE = BARE_LINE + SUFFIX
const SOURCE_IDS = {
  front: 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
  side: 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',
  back: 'cccccccc-cccc-4ccc-8ccc-cccccccccccc',
}
const FINGERPRINT = 'a'.repeat(64)

type Row = Record<string, unknown>
type Result = { data: unknown; error: unknown }
const PROFILE: Row = {
  sex: 'masculino',
  birth_date: '2000-01-01',
  height_cm: 185,
  weight_kg: 80.5,
  user_id: USER_ID,
  onboarding_completed: true,
  onboarding_completed_at: GENERATION,
  body_fat_percent: 22.1,
  bf_percent_estimated: 22.1,
  bf_source: 'signup_photos',
  bf_estimated_at: GENERATION,
  activity_level: 'moderado',
  training_frequency: 4,
  water_intake: 'moderado',
  hunger_level: 'moderada',
  current_protocol: 'ganho_massa',
  goal_type: null,
  goal_value: null,
  deficit_level: null,
}

const S541: Row = {
  date: '2026-10-04',
  calories_target: 2980,
  protein_target: '144.00',
  calories_consumed: 541,
  protein_g: '59.03',
  carbs_g: '47.32',
  fat_g: '10.27',
  exercise_calories: 322,
  water_consumed_ml: 500,
  daily_balance: -2761,
  deficit_accumulated: 0,
  day_status: null,
  day_closed: false,
  gap_reminder_sent_at: null,
}

const PROGRESS: Row = {
  current_streak: 0,
  longest_streak: 0,
  xp_total: 0,
  level: 1,
  blocks_completed: 0,
  deficit_block: 0,
  last_active_date: null,
}

const USER: Row = {
  id: USER_ID,
  name: 'QA A',
  summary: null,
  last_active_at: null,
  country: 'BR',
  country_confirmed: true,
  country_detected_from_wpp: null,
  locale: 'pt-BR',
  metadata: null,
  timezone: 'America/Sao_Paulo',
}

/** Current SQL profile-only response: no open photos, notes, consent or estimate. */
function closedSnapshot() {
  return {
    version: 1,
    user_id: USER_ID,
    profile_present: true,
    locale: 'pt-BR',
    timezone: 'America/Sao_Paulo',
    generation_token: {
      onboarding_completed: true,
      onboarding_completed_at: GENERATION,
      receipt_count: 1,
    },
    poses: [],
    remaining_uploads: 0,
    consent: null,
    estimate: null,
    candidate: null,
    confirmation: {
      decision: 'accepted',
      method: 'arithmetic_mean_v1',
      source_ids: SOURCE_IDS,
      fingerprint: FINGERPRINT,
      confirmed_body_fat_percent: 22.1,
      decided_at: GENERATION,
      invalidated_at: null,
      active: true,
    },
  }
}

interface Fixture {
  channel?: 'flow' | 'whatsapp'
  profile?: Row
  snapshot?: unknown
  rpcError?: unknown
  rpcThrow?: boolean
}
interface LlmCall {
  systemPrompt: unknown
  messages: Array<{ role: string; content: string }>
  [key: string]: unknown
}
interface Harness {
  deps: PipelineDeps
  llmCalls: LlmCall[]
  rpcCalls: Array<{ name: string; args: unknown }>
  unexpectedRpcCalls: string[]
  writes: Array<{ table: string; kind: string; row: unknown }>
}

function harness(fixture: Fixture = {}): Harness {
  const provider = fixture.channel === 'whatsapp' ? 'whatsapp' : 'mobile_flow'
  const profile = fixture.profile ?? PROFILE
  const snapshot = fixture.snapshot === undefined ? closedSnapshot() : fixture.snapshot
  const llmCalls: LlmCall[] = []
  const rpcCalls: Harness['rpcCalls'] = []
  const unexpectedRpcCalls: string[] = []
  const writes: Harness['writes'] = []
  interface Read {
    table: string
    columns: string
    filters: Row
  }
  const rowsFor = (read: Read): unknown => {
    switch (read.table) {
      case 'users':
        return USER
      case 'user_profiles':
        return profile
      case 'user_progress':
        return PROGRESS
      case 'user_coach_preferences':
        return null
      case 'messages':
        return [
          {
            direction: 'in',
            content: PHRASE,
            content_type: 'text',
            created_at: NOW.toISOString(),
            provider,
            provider_message_id: TURN_ID,
          },
        ]
      case 'daily_snapshots': {
        if (read.filters.day_closed === true) return []
        if (read.filters.date !== '2026-10-04') return null
        if (read.columns.trim() === '*') return S541
        return Object.fromEntries(
          read.columns.split(',').map((key) => [key.trim(), S541[key.trim()] ?? null]),
        )
      }
      case 'global_config':
        if (read.filters.key === 'router.haiku_enabled') return { value: false }
        return [
          {
            key: 'calc.protein_factors',
            value: {
              muita: 1.6,
              pouca: 1.8,
              moderada: 1.8,
              training_low: 1.7,
              optimal_mid_training: 1.9,
              optimal_high_training: 2,
            },
          },
        ]
      case 'v_active_prompts':
        return {
          stage: read.filters.stage ?? 'ganho_massa',
          model: MODEL,
          temperature: 0.2,
          max_tokens: 1200,
          max_tool_iterations: 2,
          system_prompt: 'REGRAS COMPARTILHADAS',
          allowed_tools: null,
        }
      default:
        return []
    }
  }
  const supabase = {
    from(table: string) {
      const read: Read = { table, columns: '', filters: {} }
      const result = () => ({ data: rowsFor(read), error: null })
      const one = async () => {
        const { data } = result()
        return { data: Array.isArray(data) ? (data[0] ?? null) : data, error: null }
      }
      const chain = Promise.resolve().then(result) as Promise<Result> & Record<string, unknown>
      for (const method of [
        'neq',
        'gte',
        'lte',
        'lt',
        'gt',
        'in',
        'is',
        'like',
        'ilike',
        'or',
        'not',
        'order',
        'limit',
      ])
        chain[method] = () => chain
      chain.select = (columns?: string) => {
        if (typeof columns === 'string') read.columns = columns
        return chain
      }
      chain.eq = (key: string, value: unknown) => {
        read.filters[key] = value
        return chain
      }
      for (const kind of ['insert', 'update', 'upsert', 'delete']) {
        chain[kind] = (row: unknown) => {
          writes.push({ table, kind, row })
          return chain
        }
      }
      chain.single = one
      chain.maybeSingle = one
      return chain
    },
    async rpc(name: string, args: unknown) {
      rpcCalls.push({ name, args: structuredClone(args) })
      if (name === RPC) {
        expect(args).toEqual({ p_user_id: USER_ID, p_include_open_photos: false })
        if (fixture.rpcThrow) throw new Error('B4C_SYNTHETIC_RPC_FAILURE')
        return { data: structuredClone(snapshot), error: fixture.rpcError ?? null }
      }
      if (name === 'ensure_user_initialized') {
        expect(args).toEqual({ p_wpp: FROM })
        return { data: USER_ID, error: null }
      }
      // No embeddings dependency is supplied, so RAG must make no external RPC.
      unexpectedRpcCalls.push(name)
      throw new Error('B4C_UNEXPECTED_RPC')
    },
  } as unknown as PipelineDeps['supabase']
  const llm = {
    async complete(input: LlmCall) {
      llmCalls.push(structuredClone(input))
      return {
        content: REPLY,
        toolCalls: [],
        model: MODEL,
        promptTokens: 100,
        completionTokens: 4,
        cacheReadInputTokens: 0,
        cacheCreationInputTokens: 0,
        costUsd: 0,
      }
    },
  } as unknown as PipelineDeps['llm']
  return {
    deps: { supabase, llm, maxToolIterations: 3 },
    llmCalls,
    rpcCalls,
    unexpectedRpcCalls,
    writes,
  }
}

function flow(h: Harness) {
  return processAuthenticatedMessage(h.deps, {
    userId: USER_ID,
    providerMessageId: TURN_ID,
    text: PHRASE,
    timestamp: NOW,
  })
}
function whatsapp(h: Harness) {
  return processMessage(h.deps, {
    from: FROM,
    providerMessageId: TURN_ID,
    text: PHRASE,
    contentType: 'text',
    provider: 'whatsapp',
    timestamp: NOW,
  })
}

function modelContext(h: Harness): string {
  // This gate is deliberately before the missing-suffix assertion: a shortcut,
  // provider failure or fixture failure cannot stand in for the reported RED.
  expect(h.llmCalls).toHaveLength(1)
  const call = h.llmCalls[0]
  expect(call?.messages.at(-1)).toEqual({ role: 'user', content: PHRASE })
  expect(Array.isArray(call?.systemPrompt)).toBe(true)
  const blocks = call?.systemPrompt as Array<{ text: string }>
  expect(blocks).toHaveLength(2)
  expect(typeof blocks[1]?.text).toBe('string')
  return blocks[1]?.text ?? ''
}
function expectOneClosedRead(h: Harness): void {
  expect(h.rpcCalls.filter((call) => call.name === RPC)).toEqual([
    {
      name: RPC,
      args: { p_user_id: USER_ID, p_include_open_photos: false },
    },
  ])
  expect(h.unexpectedRpcCalls).toEqual([])
}
function expectPrivateProofAbsent(h: Harness): void {
  const request = JSON.stringify(h.llmCalls)
  for (const secret of [
    ...Object.values(SOURCE_IDS),
    FINGERPRINT,
    GENERATION,
    'arithmetic_mean_v1',
    'confirmed_body_fat_percent',
    'generation_token',
    'signup_body_photo_receipts',
  ])
    expect(request).not.toContain(secret)
}

beforeEach(() => {
  vi.useFakeTimers()
  vi.setSystemTime(NOW)
  clearCalcConfigCache()
  resetRouterFlagCacheForTests()
})
afterEach(() => {
  vi.useRealTimers()
  vi.unstubAllEnvs()
  clearCalcConfigCache()
  resetRouterFlagCacheForTests()
})

describe('B4c real Flow context — confirmed photo origin', () => {
  it('marks the actual model context for an active accepted same-generation 22.1 receipt', async () => {
    const h = harness()
    const output = await flow(h)
    expect(output.text).toBe(REPLY)
    const context = modelContext(h)
    // CURRENT RED: real model call exists, factual number exists, suffix absent.
    expect(context.split('\n').filter((line) => line.startsWith('- Gordura corporal:'))).toEqual([
      CONFIRMED_LINE,
    ])
    expect(context.split(SUFFIX)).toHaveLength(2)
    // GREEN oracle only: the current implementation legitimately has zero reads.
    expectOneClosedRead(h)
    expectPrivateProofAbsent(h)
  })

  it.each([
    'no receipt',
    'declined',
    'invalidated same-number manual write',
  ] as const)('keeps the bare line for %s despite public estimated/source equality', async (kind) => {
    const snapshot: Row = closedSnapshot()
    if (kind === 'no receipt') {
      snapshot.confirmation = null
      snapshot.generation_token = { ...closedSnapshot().generation_token, receipt_count: 0 }
    } else if (kind === 'declined') {
      snapshot.confirmation = {
        decision: 'declined',
        method: null,
        source_ids: null,
        fingerprint: null,
        confirmed_body_fat_percent: null,
        decided_at: GENERATION,
        invalidated_at: null,
        active: false,
      }
    } else {
      snapshot.confirmation = {
        ...closedSnapshot().confirmation,
        invalidated_at: NOW.toISOString(),
        active: false,
      }
    }
    const h = harness({ snapshot })
    await flow(h)
    const context = modelContext(h)
    expect(context.split('\n').filter((line) => line.startsWith('- Gordura corporal:'))).toEqual([
      BARE_LINE,
    ])
    expect(context).not.toContain(SUFFIX)
    expectOneClosedRead(h)
    expectPrivateProofAbsent(h)
  })

  it('keeps invalidated origin negative when a later manual BF differs from the confirmed value', async () => {
    const snapshot = {
      ...closedSnapshot(),
      confirmation: {
        ...closedSnapshot().confirmation,
        invalidated_at: NOW.toISOString(),
        active: false,
      },
    }
    const h = harness({ profile: { ...PROFILE, body_fat_percent: 22.11 }, snapshot })
    await flow(h)
    const context = modelContext(h)
    expect(context.split('\n').filter((line) => line.startsWith('- Gordura corporal:'))).toEqual([
      '- Gordura corporal: 22.11%',
    ])
    expect(context).not.toContain(SUFFIX)
    expectOneClosedRead(h)
    expectPrivateProofAbsent(h)
  })

  it('trusts the active receipt even when the public estimated/source hints change separately', async () => {
    const h = harness({ profile: { ...PROFILE, bf_percent_estimated: 27, bf_source: 'manual' } })
    await flow(h)
    const context = modelContext(h)
    expect(context.split('\n').filter((line) => line.startsWith('- Gordura corporal:'))).toEqual([
      CONFIRMED_LINE,
    ])
    expectOneClosedRead(h)
    expectPrivateProofAbsent(h)
  })

  it('keeps a historical accepted origin with the signup-photo feature switch OFF', async () => {
    vi.stubEnv('MOBILE_SIGNUP_BODY_PHOTOS_PROJECT_REF', '')
    const h = harness()
    await flow(h)
    expect(modelContext(h)).toContain(CONFIRMED_LINE)
    expectOneClosedRead(h)
    expect(flowCapabilities.find((capability) => capability.id === 6)).toEqual({
      id: 6,
      key: 'body_fat_from_photo',
      available: false,
    })
    expectPrivateProofAbsent(h)
  })

  it('keeps an open profile with historical receipts but no current confirmation as a legitimate negative', async () => {
    const snapshot = {
      ...closedSnapshot(),
      generation_token: {
        onboarding_completed: false,
        onboarding_completed_at: null,
        receipt_count: 2,
      },
      confirmation: null,
    }
    const h = harness({
      profile: { ...PROFILE, onboarding_completed: false, onboarding_completed_at: null },
      snapshot,
    })
    await flow(h)
    const context = modelContext(h)
    expect(context.split('\n').filter((line) => line.startsWith('- Gordura corporal:'))).toEqual([
      BARE_LINE,
    ])
    expect(context).not.toContain(SUFFIX)
    expectOneClosedRead(h)
    expectPrivateProofAbsent(h)
  })

  it('does not read origin when official BF is absent, even if public estimate is 22.1', async () => {
    const h = harness({ profile: { ...PROFILE, body_fat_percent: null }, rpcThrow: true })
    await flow(h)
    const context = modelContext(h)
    expect(context.split('\n').filter((line) => line.startsWith('- Gordura corporal:'))).toEqual([
      '- Gordura corporal: ?',
    ])
    expect(context).not.toContain(SUFFIX)
    expect(h.rpcCalls).toEqual([])
    expect(h.unexpectedRpcCalls).toEqual([])
  })

  it('leaves actual WhatsApp requests unchanged for the same profile and makes zero origin RPCs', async () => {
    const active = harness({ channel: 'whatsapp' })
    const absent = harness({ channel: 'whatsapp', snapshot: null, rpcThrow: true })
    const a = await whatsapp(active)
    const b = await whatsapp(absent)
    expect(a).toEqual(b)
    expect(active.llmCalls).toEqual(absent.llmCalls)
    expect(active.writes).toEqual(absent.writes)
    const context = modelContext(active)
    expect(context.split('\n').filter((line) => line.startsWith('- BF%:'))).toEqual(['- BF%: 22.1'])
    expect(context).not.toContain(SUFFIX)
    expect(active.rpcCalls).toEqual([{ name: 'ensure_user_initialized', args: { p_wpp: FROM } }])
    expect(absent.rpcCalls).toEqual(active.rpcCalls)
    expect(active.unexpectedRpcCalls).toEqual([])
    expect(absent.unexpectedRpcCalls).toEqual([])
  })
})

type InvalidCase = { label: string; mutate: (snapshot: Row) => void }
const invalidCases: InvalidCase[] = [
  {
    label: 'uninvalidated accepted value mismatch even when active is false',
    mutate: (s) => {
      s.confirmation = {
        ...closedSnapshot().confirmation,
        confirmed_body_fat_percent: 22.11,
        active: false,
      }
    },
  },
  {
    label: 'active receipt with receipt_count zero',
    mutate: (s) => {
      s.generation_token = { ...closedSnapshot().generation_token, receipt_count: 0 }
    },
  },
  {
    label: 'wrong owner',
    mutate: (s) => {
      s.user_id = OTHER_USER
    },
  },
  {
    label: 'wrong version',
    mutate: (s) => {
      s.version = 2
    },
  },
  {
    label: 'profile missing',
    mutate: (s) => {
      s.profile_present = false
    },
  },
  {
    label: 'stale generation',
    mutate: (s) => {
      s.generation_token = {
        ...closedSnapshot().generation_token,
        onboarding_completed_at: '2026-10-02T12:00:00.123456+00:00',
      }
    },
  },
  {
    label: 'different microsecond in the same millisecond',
    mutate: (s) => {
      s.generation_token = {
        ...closedSnapshot().generation_token,
        onboarding_completed_at: '2026-10-03T12:00:00.123457+00:00',
      }
    },
  },
  {
    label: 'malformed generation',
    mutate: (s) => {
      s.generation_token = { ...closedSnapshot().generation_token, onboarding_completed_at: '2026' }
    },
  },
  {
    label: 'incomplete generation',
    mutate: (s) => {
      s.generation_token = { ...closedSnapshot().generation_token, onboarding_completed: false }
    },
  },
  {
    label: 'coerced active boolean',
    mutate: (s) => {
      s.confirmation = { ...closedSnapshot().confirmation, active: 'true' }
    },
  },
  {
    label: 'unsupported decision',
    mutate: (s) => {
      s.confirmation = { ...closedSnapshot().confirmation, decision: 'unknown' }
    },
  },
  {
    label: 'unsupported mean method',
    mutate: (s) => {
      s.confirmation = { ...closedSnapshot().confirmation, method: 'minimum_v0' }
    },
  },
  {
    label: 'official-value mismatch',
    mutate: (s) => {
      s.confirmation = { ...closedSnapshot().confirmation, confirmed_body_fat_percent: 22.11 }
    },
  },
  {
    label: 'invalidated described as active',
    mutate: (s) => {
      s.confirmation = { ...closedSnapshot().confirmation, invalidated_at: NOW.toISOString() }
    },
  },
  {
    label: 'missing confirmation field',
    mutate: (s) => {
      delete s.confirmation
    },
  },
]

describe('B4c provenance data-access failures — no model or inferred label', () => {
  it('rejects a profile of another owner before reading the origin or calling the model', async () => {
    const h = harness({ profile: { ...PROFILE, user_id: OTHER_USER } })
    await expect(flow(h)).rejects.toBeInstanceOf(Error)
    expect(h.llmCalls).toEqual([])
    expect(h.rpcCalls).toEqual([])
    expect(h.unexpectedRpcCalls).toEqual([])
  })

  it.each(invalidCases)('rejects $label before the model', async ({ mutate }) => {
    const snapshot: Row = closedSnapshot()
    mutate(snapshot)
    const h = harness({ snapshot })
    await expect(flow(h)).rejects.toBeInstanceOf(Error)
    expect(h.llmCalls).toEqual([])
    expectOneClosedRead(h)
  })

  it.each([
    { label: 'null payload', snapshot: null },
    { label: 'array payload', snapshot: [] },
    { label: 'string payload', snapshot: USER_ID },
    { label: 'empty payload', snapshot: {} },
    { label: 'RPC returns error', rpcError: { code: '08006', message: 'B4C_SYNTHETIC_ERROR' } },
    { label: 'RPC throws', rpcThrow: true },
  ])('rejects $label before the model', async (fixture) => {
    const h = harness(fixture)
    await expect(flow(h)).rejects.toBeInstanceOf(Error)
    expect(h.llmCalls).toEqual([])
    expectOneClosedRead(h)
  })
})
