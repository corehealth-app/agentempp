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
    const r = (await registraTreino.execute({ workout_type: 'caminhada', duration_min: 60 } as any, ctx as any)) as {
      deduped?: boolean
    }
    expect(r.deduped).toBe(true)
    expect(events.find((e) => e.event === 'tool.workout_redup_skipped')).toBeDefined()
  })
})
