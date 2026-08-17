import { describe, it, expect } from 'vitest'
import { registraTreino } from './tools.js'
import type { ServiceClient } from '@mpp/db'

// Trava o fix do dedup de treino (Paulo 2026-05-26): a MESMA caminhada descrita
// em mensagens DIFERENTES (pmid diferente) duplicava. A 2ª camada barra treino
// idêntico (tipo+duração) já registrado nas últimas 6h, retornando ANTES do
// cálculo/RPCs (early return) — por isso o mock só precisa cobrir workout_logs.
function makeCtx(opts: { recentSameWorkout: boolean }) {
  const events: Array<{ event: string; properties: Record<string, unknown> }> = []
  const chain = (rows: unknown): unknown => {
    const o: Record<string, unknown> = { data: rows, error: null }
    for (const m of ['select', 'eq', 'lte', 'gt', 'lt', 'order', 'limit', 'maybeSingle', 'single', 'in', 'is']) {
      o[m] = () => chain(rows)
    }
    o.then = (cb: (v: { data: unknown; error: null }) => unknown) =>
      Promise.resolve(cb({ data: rows, error: null }))
    return o
  }
  const supabase = {
    from: (t: string) => {
      if (t === 'workout_logs') {
        // Query por pmid (idempotência) NÃO usa .gte → []. Query da 2ª camada
        // (dedup) USA .gte('created_at') → devolve match se recentSameWorkout.
        const wl = (usedGte: boolean): unknown => {
          const o: Record<string, unknown> = {}
          for (const m of ['select', 'eq', 'lte', 'gt', 'lt', 'order', 'limit', 'maybeSingle', 'single', 'in', 'is']) {
            o[m] = () => wl(usedGte)
          }
          o.gte = () => wl(true)
          o.then = (cb: (v: { data: unknown; error: null }) => unknown) =>
            Promise.resolve(cb({ data: usedGte && opts.recentSameWorkout ? [{ id: 'w1' }] : [], error: null }))
          return o
        }
        return { ...(wl(false) as object), insert: () => chain([]) }
      }
      if (t === 'product_events') {
        return {
          insert: (e: { event: string; properties: Record<string, unknown> } | Array<{ event: string; properties: Record<string, unknown> }>) => {
            for (const ev of Array.isArray(e) ? e : [e]) events.push(ev)
            return chain(null)
          },
        }
      }
      return { ...(chain([]) as object), insert: () => chain([]) }
    },
    rpc: async () => ({ data: null, error: null }),
  } as unknown as ServiceClient
  return {
    events,
    ctx: {
      supabase,
      userId: 'u1',
      userWpp: '5511999999999',
      userCountry: 'BR',
      userTimezone: 'America/Sao_Paulo',
      providerMessageId: 'pmid-novo',
      recentUserMessages: [],
    },
  }
}

describe('registra_treino — dedup (Paulo 2026-05-26)', () => {
  it('treino idêntico (tipo+duração) já registrado nas últimas 6h → deduped, não duplica', async () => {
    const { ctx, events } = makeCtx({ recentSameWorkout: true })
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
// biome-ignore lint/suspicious/noExplicitAny: legacy — see ACT-1 prevention plan 2026-06-16
// biome-ignore lint/suspicious/noExplicitAny: legacy — see ACT-1 prevention plan 2026-06-16
    const r = (await registraTreino.execute({ workout_type: 'caminhada', duration_min: 60 } as any, ctx as any)) as {
      deduped?: boolean
    }
    expect(r.deduped).toBe(true)
    expect(events.find((e) => e.event === 'tool.workout_redup_skipped')).toBeDefined()
  })
})

// ── FIX #3 CORREÇÃO DE TREINO (Roberto 2026-05-27) ───────────────────────────
// Paulo: caminhada 60min → "Correção: a caminhada é 30 minutos" → soma virou
// 60+30=90min/247kcal. A correção precisa substituir log e snapshot em uma
// única transação, sem janela de estado parcial entre delete, abatimento e insert.

function makeReplaceCtx(opts: { hasOldWorkoutSameType: boolean; correctionMsg: string }) {
  const events: Array<{ event: string; properties: Record<string, unknown> }> = []
  const rpcCalls: Array<{ name: string; params: Record<string, unknown> }> = []
  const deleteCalls: Array<{ table: string }> = []

  // workout_logs cadeia: distingue camadas pelo padrão de chamadas.
  //   - .eq('raw_provider_message_id', ...) → idempotência pmid (devolve [])
  //   - .eq('duration_min', X).gte(...) → dedup tipo+duração (devolve [])
  //   - .eq('workout_type', X).gte(...) SEM .eq('duration_min', ...) → 3ª camada
  //     (correção) — aqui devolve o treino antigo se opts.hasOldWorkoutSameType
  function wlChain() {
    let hasDuration = false
    let hasGte = false
    const o: Record<string, unknown> = {}
    const term = () => {
      const oldRow = hasGte && !hasDuration && opts.hasOldWorkoutSameType
        ? [{ id: 'old-1', estimated_kcal: 165, duration_min: 60 }]
        : []
      return Promise.resolve({ data: oldRow, error: null })
    }
    for (const m of ['select', 'order', 'limit', 'maybeSingle', 'single', 'in', 'is', 'lt', 'lte', 'gt']) {
      o[m] = () => o
    }
    o.eq = (col: string) => {
      if (col === 'duration_min') hasDuration = true
      return o
    }
    o.gte = () => {
      hasGte = true
      return o
    }
    o.then = (cb: (v: { data: unknown; error: null }) => unknown) => term().then(cb as never)
    o.delete = () => ({ in: () => { deleteCalls.push({ table: 'workout_logs' }); return Promise.resolve({ data: null, error: null }) } })
    o.insert = () => Promise.resolve({ data: null, error: null })
    return o
  }
  const supabase = {
    from: (t: string) => {
      if (t === 'workout_logs') return wlChain()
      if (t === 'product_events') {
        return {
          insert: (e: { event: string; properties: Record<string, unknown> }) => {
            events.push(e)
            return Promise.resolve({ data: null, error: null })
          },
        }
      }
      if (t === 'user_profiles') {
        return {
          select: () => ({ eq: () => ({ maybeSingle: () => Promise.resolve({ data: { weight_kg: 70 }, error: null }) }) }),
        }
      }
      if (t === 'global_config') {
        return {
          select: () => ({
            like: () => Promise.resolve({ data: [], error: null }),
          }),
        }
      }
      return { insert: () => Promise.resolve({ data: null, error: null }), select: () => Promise.resolve({ data: [], error: null }) }
    },
    rpc: async (name: string, params: Record<string, unknown>) => {
      rpcCalls.push({ name, params })
      if (name === 'snapshot_add_workout') {
        return { data: { id: 's1', exercise_calories: 82, training_done: true }, error: null }
      }
      if (name === 'register_workout_atomic') {
        return {
          data: {
            snapshot_id: 's1',
            inserted: true,
            replaced_count: 1,
            exercise_calories: 82,
            training_done: true,
          },
          error: null,
        }
      }
      if (name === 'calc_workout_kcal') return { data: 82, error: null }
      return { data: null, error: null }
    },
  } as unknown as ServiceClient

  return {
    events,
    rpcCalls,
    deleteCalls,
    ctx: {
      supabase,
      userId: 'u1',
      userWpp: '5511999999999',
      userCountry: 'BR',
      userTimezone: 'America/Sao_Paulo',
      providerMessageId: 'pmid-correcao',
      recentUserMessages: [opts.correctionMsg],
    },
  }
}

describe('registra_treino — correção via texto SUBSTITUI em vez de SOMAR (Roberto 2026-05-27)', () => {
  it('texto com correção usa uma única RPC atômica, sem delete nem abatimento separado', async () => {
    const { ctx, events, rpcCalls, deleteCalls } = makeReplaceCtx({
      hasOldWorkoutSameType: true,
      correctionMsg: 'Correção: a caminhada é 30 minutos , foi considerado calorias de 60 minutos',
    })
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
// biome-ignore lint/suspicious/noExplicitAny: legacy — see ACT-1 prevention plan 2026-06-16
// biome-ignore lint/suspicious/noExplicitAny: legacy — see ACT-1 prevention plan 2026-06-16
    await registraTreino.execute({ workout_type: 'caminhada', duration_min: 30 } as any, ctx as any)
    expect(deleteCalls).toHaveLength(0)
    const replacedEvent = events.find((e) => e.event === 'tool.workout_replaced')
    expect(replacedEvent).toBeDefined()
    expect(replacedEvent!.properties.old_kcal_sum).toBe(165)
    expect(replacedEvent!.properties.new_duration_min).toBe(30)
    const atomicRpc = rpcCalls.find((call) => call.name === 'register_workout_atomic')
    expect(atomicRpc?.params.p_replace_recent).toBe(true)
    expect(atomicRpc?.params.p_replace_since).toEqual(expect.any(String))
    expect(rpcCalls.some((call) => call.name === 'snapshot_add_workout')).toBe(false)
  })

  it('SEM intenção de correção (msg neutra) → não substitui (delete e evento não disparam)', async () => {
    const { ctx, events, rpcCalls, deleteCalls } = makeReplaceCtx({
      hasOldWorkoutSameType: true,
      correctionMsg: 'Acabei de fazer caminhada de 30 min',
    })
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
// biome-ignore lint/suspicious/noExplicitAny: legacy — see ACT-1 prevention plan 2026-06-16
// biome-ignore lint/suspicious/noExplicitAny: legacy — see ACT-1 prevention plan 2026-06-16
    await registraTreino.execute({ workout_type: 'caminhada', duration_min: 30 } as any, ctx as any)
    expect(deleteCalls.length).toBe(0)
    expect(events.find((e) => e.event === 'tool.workout_replaced')).toBeUndefined()
    const atomicRpc = rpcCalls.find((call) => call.name === 'register_workout_atomic')
    expect(atomicRpc?.params.p_replace_recent).toBe(false)
  })
})
