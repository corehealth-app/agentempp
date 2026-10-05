import { existsSync, readFileSync } from 'node:fs'
import { fileURLToPath } from 'node:url'
import { MOBILE_FLOW_TURN_DEADLINE_MS } from '@mpp/agent'
import { afterEach, beforeEach, describe, expect, it, type MockInstance, vi } from 'vitest'
import {
  FLOW_EXECUTION_LEASE_MS,
  FLOW_TURN_HARD_LIMIT_MS,
  type FlowAgent,
  type FlowChatStore,
  type StoredFlowMessage,
  sendFlowMessage,
} from './flow-chat-service'
import { MobileApiError } from './http'

// Audit 2026-10-04 (Flow cost and speed). A Flow turn had no time limit of
// its own: the shared model client allows 90 s and one retry per call, the
// plan generator 120 s, and a turn could outlive the route's 300 s. The
// function then died with the turn in `processing`, and every retry of the
// app got 409 until the 10-minute lease ran out.
//
// The service now waits for the agent at most FLOW_TURN_HARD_LIMIT_MS from
// the start of the turn and fails the turn with the error it already returns
// for a provider failure (502 flow_provider_failed, inbound `failed`), so a
// retry runs at once. The agent has its own, earlier deadline for model work
// (packages/agent, MOBILE_FLOW_TURN_DEADLINE_MS); this is the guarantee for
// everything else it awaits.
//
// > RC PERF-T1 — cenário função encerrada pela plataforma ANTES do limite (queda de instância, deploy no meio do turno) NÃO coberto nesta PR (pendência da audit 2026-10-04).
//   O turno ainda fica "processing" até o lease; o limite só age enquanto a função vive.
// > RC PERF-T2 — cenário leituras do banco ANTES do agente travadas (autenticação, idempotência, as quatro leituras iniciais) NÃO coberto nesta PR (pendência da audit 2026-10-04).
//   O limite conta desde o início do turno, mas só interrompe a espera pelo agente.
// > RC PERF-T3 — cenário agente que continua rodando DEPOIS que o serviço encerrou o turno NÃO coberto nesta PR (pendência da audit 2026-10-04).
//   A resposta atrasada é descartada (travado em teste); uma ferramenta em andamento ainda pode
//   gravar um rascunho, que a nova tentativa do mesmo turno reaproveita pela chave do turno.

const userId = '00000000-0000-0000-0000-000000000111'
const now = new Date('2026-10-04T18:00:00.000Z')
const patientText = 'Sugira um cardápio completo para hoje'
const LIMIT_MS = FLOW_TURN_HARD_LIMIT_MS as number

function message(overrides: Partial<StoredFlowMessage> = {}): StoredFlowMessage {
  return {
    id: '00000000-0000-0000-0000-000000000201',
    role: 'user',
    content: patientText,
    state: 'completed',
    requestId: 'request-limit-0001',
    createdAt: now.toISOString(),
    ...overrides,
  }
}

/** A store whose every call takes `tripMs` on the fake clock. */
function dependencies(agent: FlowAgent['reply'], tripMs = 0) {
  const trip = async <T>(value: T): Promise<T> => {
    if (tripMs > 0) await new Promise((resolve) => setTimeout(resolve, tripMs))
    return value
  }
  const store: FlowChatStore = {
    loadHistory: vi.fn(async () => trip([])),
    countRecentExecutions: vi.fn(async () => trip(0)),
    findInbound: vi.fn(async () => trip(null)),
    findAssistant: vi.fn(async () => trip(null)),
    insertInbound: vi.fn(async () => trip(message({ state: 'processing' }))),
    transitionInbound: vi.fn(async () => trip(true)),
    insertAssistant: vi.fn(async () =>
      trip(message({ role: 'assistant', content: 'Resposta.', id: 'assistant-1' })),
    ),
    completeInbound: vi.fn(async () => trip(undefined)),
    failInbound: vi.fn(async () => trip(undefined)),
  }
  return { store, agent: { reply: vi.fn(agent) } }
}

function send(deps: ReturnType<typeof dependencies>) {
  const outcome: { error: unknown; settledAt: number | null; value: unknown } = {
    error: null,
    settledAt: null,
    value: null,
  }
  const started = performance.now()
  const pending = sendFlowMessage(deps, {
    userId,
    text: patientText,
    idempotencyKey: 'mobile-flow-limit-0001',
    requestId: 'request-limit-0001',
    now,
  }).then(
    (value) => {
      outcome.value = value
      outcome.settledAt = performance.now() - started
    },
    (error: unknown) => {
      outcome.error = error
      outcome.settledAt = performance.now() - started
    },
  )
  return { outcome, pending }
}

let info: MockInstance<typeof console.info>
let failureLog: MockInstance<typeof console.error>

beforeEach(() => {
  vi.useFakeTimers({ toFake: ['setTimeout', 'clearTimeout', 'Date', 'performance'] })
  info = vi.spyOn(console, 'info').mockImplementation(() => {})
  failureLog = vi.spyOn(console, 'error').mockImplementation(() => {})
})

afterEach(() => {
  vi.useRealTimers()
  info.mockRestore()
  failureLog.mockRestore()
})

describe('Flow turn hard limit', () => {
  it('sits under the app timeout and the function limit, and above the agent deadline', () => {
    expect(LIMIT_MS).toBe(165_000)
    expect(LIMIT_MS).toBeLessThan(180_000) // the app's request timeout, locked below
    expect(LIMIT_MS).toBeLessThan(300_000) // the route's maxDuration, locked below
    expect(LIMIT_MS).toBeLessThan(FLOW_EXECUTION_LEASE_MS)
    // The agent's own deadline ends a slow turn first, with room for its
    // closing writes; this limit is the backstop.
    expect(MOBILE_FLOW_TURN_DEADLINE_MS).toBe(150_000)
    expect(LIMIT_MS - MOBILE_FLOW_TURN_DEADLINE_MS).toBeGreaterThanOrEqual(10_000)
  })

  // The two numbers the limit is measured against, read from their sources
  // (read-only): if either changes, this fails and the limit is revisited.
  const repository = fileURLToPath(
    new URL(
      '../../../../ios/BodyFlow/BodyFlow/Core/FlowChat/MobileFlowChatRepository.swift',
      import.meta.url,
    ),
  )
  const route = fileURLToPath(
    new URL('../../app/api/mobile/v1/flow/chat/route.ts', import.meta.url),
  )

  it.skipIf(!existsSync(repository))('the app still waits 180 s for POST /flow/chat', () => {
    const source = readFileSync(repository, 'utf8')
    const post = source.slice(source.indexOf('func send('))
    expect(post).toMatch(/path: "\/api\/mobile\/v1\/flow\/chat"[\s\S]*?timeout: \.seconds\(180\)/)
  })

  it('the route still allows 300 s', () => {
    expect(readFileSync(route, 'utf8')).toMatch(/^export const maxDuration = 300$/m)
  })

  it('an agent that never answers fails the turn at the limit with the provider-failure error', async () => {
    const deps = dependencies(() => new Promise(() => {}))
    const { outcome, pending } = send(deps)

    await vi.advanceTimersByTimeAsync(LIMIT_MS - 1)
    expect(outcome.settledAt).toBeNull()
    expect(deps.store.failInbound).not.toHaveBeenCalled()

    await vi.advanceTimersByTimeAsync(1)
    await pending

    expect(outcome.error).toEqual(
      new MobileApiError(502, 'flow_provider_failed', 'Flow is temporarily unavailable'),
    )
    expect(outcome.settledAt).toBe(LIMIT_MS)
    // The turn is given back as failed: a retry runs at once instead of 409.
    expect(deps.store.failInbound).toHaveBeenCalledOnce()
    expect(deps.store.failInbound).toHaveBeenCalledWith(
      userId,
      `mobile_flow/${userId}/mobile-flow-limit-0001`,
      'flow_provider_failed',
    )
    expect(deps.store.insertAssistant).not.toHaveBeenCalled()
    expect(deps.store.completeInbound).not.toHaveBeenCalled()
    expect(vi.getTimerCount()).toBe(0)
  })

  it('logs a fixed code and nothing of the patient', async () => {
    const deps = dependencies(() => new Promise(() => {}))
    const { pending } = send(deps)
    await vi.advanceTimersByTimeAsync(LIMIT_MS)
    await pending

    const failures = failureLog.mock.calls.filter((call) => call[0] === '[mobile-flow] turn_failed')
    expect(failures).toEqual([
      [
        '[mobile-flow] turn_failed',
        {
          error_name: 'Error',
          provider_status: null,
          internal_code: 'flow turn time limit exceeded',
        },
      ],
    ])
    const timing = info.mock.calls.find((call) => call[0] === '[mobile-flow] turn_timing')?.[1]
    expect(timing).toMatchObject({ outcome: 'flow_provider_failed', total_ms: LIMIT_MS })
    expect(JSON.stringify([...info.mock.calls, ...failureLog.mock.calls])).not.toContain('cardápio')
  })

  it('the limit counts from the start of the turn, not from the agent call', async () => {
    // Four waves of 2 s run before the agent: it gets what is left.
    const deps = dependencies(() => new Promise(() => {}), 2_000)
    const { outcome, pending } = send(deps)

    await vi.advanceTimersByTimeAsync(LIMIT_MS - 1)
    expect(deps.agent.reply).toHaveBeenCalledOnce()
    expect(deps.store.failInbound).not.toHaveBeenCalled()

    await vi.advanceTimersByTimeAsync(1)
    expect(deps.store.failInbound).toHaveBeenCalledOnce()
    await vi.advanceTimersByTimeAsync(2_000)
    await pending
    expect(outcome.error).toMatchObject({ code: 'flow_provider_failed' })
    // The limit, plus the one write that fails the turn.
    expect(outcome.settledAt).toBe(LIMIT_MS + 2_000)
  })

  it('an answer inside the limit is delivered and leaves no timer behind', async () => {
    const deps = dependencies(async () => {
      await new Promise((resolve) => setTimeout(resolve, LIMIT_MS - 1))
      return { text: 'Resposta.', metadata: {} }
    })
    const { outcome, pending } = send(deps)

    await vi.advanceTimersByTimeAsync(LIMIT_MS - 1)
    await pending

    expect(outcome.error).toBeNull()
    expect(outcome.value).toMatchObject({ message: { role: 'assistant', content: 'Resposta.' } })
    expect(deps.store.failInbound).not.toHaveBeenCalled()
    expect(vi.getTimerCount()).toBe(0)
  })

  it('an agent error inside the limit is still the same failure, and clears the timer', async () => {
    const deps = dependencies(async () => {
      await new Promise((resolve) => setTimeout(resolve, 1_000))
      throw new Error('provider detail must not escape')
    })
    const { outcome, pending } = send(deps)

    await vi.advanceTimersByTimeAsync(1_000)
    await pending

    expect(outcome.error).toMatchObject({ status: 502, code: 'flow_provider_failed' })
    expect(outcome.settledAt).toBe(1_000)
    expect(vi.getTimerCount()).toBe(0)
  })

  it.each([
    ['answers', false],
    ['fails', true],
  ])('an agent that %s after the limit changes nothing: no reply stored, no unhandled rejection', async (_label, fails) => {
    const deps = dependencies(async () => {
      await new Promise((resolve) => setTimeout(resolve, LIMIT_MS + 30_000))
      if (fails) throw new Error('late provider failure')
      return { text: 'Resposta atrasada.', metadata: {} }
    })
    const unhandled = vi.fn()
    process.on('unhandledRejection', unhandled)
    try {
      const { outcome, pending } = send(deps)
      await vi.advanceTimersByTimeAsync(LIMIT_MS)
      await pending
      expect(outcome.error).toMatchObject({ code: 'flow_provider_failed' })

      await vi.advanceTimersByTimeAsync(60_000)
      await new Promise<void>((resolve) => setImmediate(resolve))

      expect(deps.store.insertAssistant).not.toHaveBeenCalled()
      expect(deps.store.completeInbound).not.toHaveBeenCalled()
      expect(deps.store.failInbound).toHaveBeenCalledOnce()
      expect(unhandled).not.toHaveBeenCalled()
    } finally {
      process.off('unhandledRejection', unhandled)
    }
  })
})
