import { buildDailyState } from '@mpp/core'
import type { ServiceClient } from '@mpp/db'
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import { createFlowAgent } from './flow-agent-factory'
import type { MobileRouteContext } from './route'

const controlled = vi.hoisted(() => ({
  constructors: vi.fn(),
  complete: vi.fn(),
  today: vi.fn(),
  close: vi.fn(),
}))
vi.mock('@mpp/providers', async (importOriginal) => {
  const original = await importOriginal<typeof import('@mpp/providers')>()
  return {
    ...original,
    OpenRouterLLM: class {
      constructor(config: unknown) {
        controlled.constructors(config)
      }
      complete(params: unknown) {
        return controlled.complete(params)
      }
    },
  }
})
vi.mock('./read-model', () => ({ loadToday: controlled.today }))
vi.mock('./day-close-on-request', () => ({ closeOpenDaysOnRequest: controlled.close }))

const OWNER = '00000000-0000-0000-0000-000000000711'
const NOW = new Date('2026-10-08T18:00:00Z')

function context(
  options: { expiredSubscription?: boolean; onRead?: (table: string) => void } = {},
): MobileRouteContext {
  const tables: Record<string, unknown> = {
    users: {
      id: OWNER,
      name: 'Synthetic',
      locale: 'pt-BR',
      timezone: 'America/Sao_Paulo',
      metadata: null,
      summary: null,
      country: 'BR',
      country_confirmed: true,
    },
    user_profiles: { current_protocol: 'manutencao' },
    user_progress: {
      current_streak: 0,
      longest_streak: 0,
      xp_total: 0,
      level: 1,
      blocks_completed: 0,
      deficit_block: 0,
      last_active_date: null,
    },
    daily_snapshots: [],
    messages: [],
    product_events: [],
    agent_rules: [],
    global_config: [],
    pending_registrations: [],
    subscriptions: options.expiredSubscription
      ? [{ user_id: OWNER, status: 'expired', current_period_end: null, trial_ends_at: null }]
      : [],
    v_active_prompts: {
      stage: 'manutencao',
      model: 'synthetic/model',
      temperature: 0,
      max_tokens: 100,
      allowed_tools: [],
      system_prompt: 'Synthetic context.',
    },
  }
  const supabase = {
    from(table: string) {
      options.onRead?.(table)
      const query = Promise.resolve({ data: tables[table] ?? [], error: null }) as Promise<{
        data: unknown
        error: null
      }> &
        Record<string, unknown>
      for (const method of [
        'select',
        'eq',
        'like',
        'gte',
        'lte',
        'lt',
        'gt',
        'order',
        'limit',
        'or',
        'filter',
        'insert',
        'update',
      ])
        query[method] = () => query
      const single = async () => ({
        data: Array.isArray(tables[table])
          ? ((tables[table] as unknown[])[0] ?? null)
          : (tables[table] ?? null),
        error: null,
      })
      query.single = single
      query.maybeSingle = single
      return query
    },
  } as unknown as ServiceClient
  return {
    request: new Request('https://performe.test/api/mobile/v1/flow/chat'),
    requestId: 'synthetic-request',
    supabase,
    auth: {
      accessToken: 'redacted',
      authUserId: 'synthetic-auth',
      userId: OWNER,
      identity: {
        id: 'synthetic-auth',
        email: 'synthetic@example.invalid',
        emailConfirmedAt: '2026-10-01T00:00:00Z',
      },
      patient: {
        id: OWNER,
        authUserId: 'synthetic-auth',
        email: 'synthetic@example.invalid',
        name: 'Synthetic',
        locale: 'pt-BR',
        timezone: null,
        country: 'BR',
        countryConfirmed: true,
        status: 'active',
      },
    },
  }
}

function officialToday() {
  return buildDailyState({
    localDate: '2026-10-08',
    generatedAt: NOW.toISOString(),
    protocol: 'manutencao',
    calculatedTargets: { calories_target: 2400, protein_target: 150 },
    snapshot: null,
    meals: [],
    workouts: [],
    pendingRegistrations: [],
    hydrationTarget: null,
    routineItems: [],
    progress: null,
    mealGap: {
      expected: [],
      registered: [],
      skipped: [],
      open: [],
      reliable: false,
      activeDays: 0,
    },
  })
}

function input(text: string) {
  return {
    userId: OWNER,
    providerMessageId: `mobile_flow/${OWNER}/synthetic-c7`,
    text,
    timestamp: NOW,
  }
}

beforeEach(() => {
  vi.clearAllMocks()
  vi.stubEnv('OPENROUTER_API_KEY', '')
  vi.stubEnv('HELICONE_API_KEY', '')
  controlled.today.mockResolvedValue(officialToday())
  controlled.close.mockResolvedValue(undefined)
  controlled.complete.mockResolvedValue({
    content: 'Resposta normal do Flow.',
    toolCalls: [],
    model: 'synthetic/model',
    promptTokens: 1,
    completionTokens: 1,
    totalTokens: 2,
    costUsd: 0,
    finishReason: 'stop',
    latencyMs: 1,
  })
})
afterEach(() => vi.unstubAllEnvs())

describe('Flow-only factory, real authenticated entry and lazy provider', () => {
  it.each([
    'Como está meu dia?',
    'Como está meu dia até agora?',
    'How is my day so far?',
  ])('answers %s without a provider key or constructing a provider', async (text) => {
    const ctx = context()
    const reply = await createFlowAgent(ctx).reply(input(text))
    expect(reply.text).toContain(
      text.startsWith('How') ? 'Consumed: 0 / 2,400 kcal (0%).' : 'Consumido: 0 / 2.400 kcal (0%).',
    )
    expect(reply.metadata).toMatchObject({
      modelUsed: 'none',
      promptTokens: 0,
      completionTokens: 0,
      costUsd: 0,
    })
    expect(controlled.constructors).not.toHaveBeenCalled()
    expect(controlled.complete).not.toHaveBeenCalled()
    expect(controlled.close).toHaveBeenCalledWith(ctx, { now: NOW })
    expect(controlled.today).toHaveBeenCalledWith(ctx.supabase, OWNER, 'UTC', NOW)
  })

  it('rejects another owner before any loader or provider operation', async () => {
    await expect(
      createFlowAgent(context()).reply({ ...input('Como está meu dia?'), userId: 'another-owner' }),
    ).rejects.toThrow()
    expect(controlled.today).not.toHaveBeenCalled()
    expect(controlled.close).not.toHaveBeenCalled()
    expect(controlled.constructors).not.toHaveBeenCalled()
  })

  it('keeps the original missing-key error when a model is needed', async () => {
    await expect(
      createFlowAgent(context()).reply(input('Quero conversar sobre minha rotina.')),
    ).rejects.toThrow('Flow provider is not configured')
    expect(controlled.constructors).not.toHaveBeenCalled()
    expect(controlled.today).not.toHaveBeenCalled()
  })

  it('constructs the real provider once per normal reply with the existing options', async () => {
    vi.stubEnv('OPENROUTER_API_KEY', 'synthetic-test-key')
    vi.stubEnv('HELICONE_API_KEY', 'synthetic-tracing-key')
    const reply = await createFlowAgent(context()).reply(
      input('Quero conversar sobre minha rotina.'),
    )
    expect(reply.text).toBe('Resposta normal do Flow.')
    expect(controlled.constructors).toHaveBeenCalledTimes(1)
    expect(controlled.constructors).toHaveBeenCalledWith({
      apiKey: 'synthetic-test-key',
      heliconeApiKey: 'synthetic-tracing-key',
      appName: 'Performe AI Flow',
    })
    expect(controlled.complete).toHaveBeenCalledTimes(1)
    expect(controlled.today).not.toHaveBeenCalled()
    expect(controlled.close).not.toHaveBeenCalled()
  })

  it('keeps a failed official Today read an error, without model fallback', async () => {
    controlled.today.mockRejectedValueOnce(new Error('Synthetic Today failure'))
    await expect(createFlowAgent(context()).reply(input('Como está meu dia?'))).rejects.toThrow(
      'Synthetic Today failure',
    )
    expect(controlled.constructors).not.toHaveBeenCalled()
    expect(controlled.complete).not.toHaveBeenCalled()
  })

  it('finishes the guarded closer before reading the official day with the same instant', async () => {
    const order: string[] = []
    const reads: string[] = []
    let entered = () => {}
    let release = () => {}
    const started = new Promise<void>((resolve) => {
      entered = resolve
    })
    const resumed = new Promise<void>((resolve) => {
      release = resolve
    })
    controlled.close.mockImplementationOnce(async () => {
      order.push('close-start')
      entered()
      await resumed
      order.push('close-end')
    })
    controlled.today.mockImplementationOnce(async () => {
      order.push('today')
      return officialToday()
    })
    const reply = createFlowAgent(
      context({
        onRead: (table) => {
          reads.push(table)
        },
      }),
    ).reply(input('Como está meu dia?'))
    await started
    expect(controlled.today).not.toHaveBeenCalled()
    expect(controlled.constructors).not.toHaveBeenCalled()
    expect(reads).toEqual([])
    release()
    await reply
    expect(order).toEqual(['close-start', 'close-end', 'today'])
    expect(reads).toEqual(['users', 'user_progress'])
    expect(controlled.close).toHaveBeenCalledTimes(1)
    expect(controlled.today).toHaveBeenCalledTimes(1)
  })

  it('does not close or read days for a subscription blocked before the status branch', async () => {
    vi.stubEnv('NODE_ENV', 'production')
    vi.stubEnv('SUBSCRIPTION_GATE', 'on')
    const reply = await createFlowAgent(context({ expiredSubscription: true })).reply(
      input('Como está meu dia?'),
    )
    expect(reply.text).toContain('assinatura precisa ser renovada')
    expect(controlled.close).not.toHaveBeenCalled()
    expect(controlled.today).not.toHaveBeenCalled()
    expect(controlled.constructors).not.toHaveBeenCalled()
  })

  it.each([
    'Como está meu dia? Estou com tontura.',
    'How is my day? I have an allergy.',
  ])('keeps a compound request in the normal Flow path: %s', async (text) => {
    vi.stubEnv('OPENROUTER_API_KEY', 'synthetic-test-key')
    const reply = await createFlowAgent(context()).reply(input(text))
    expect(reply.text).toBe('Resposta normal do Flow.')
    expect(controlled.constructors).toHaveBeenCalledTimes(1)
    expect(controlled.complete).toHaveBeenCalledTimes(1)
    expect(controlled.close).not.toHaveBeenCalled()
    expect(controlled.today).not.toHaveBeenCalled()
  })
})
