import { describe, it, expect } from 'vitest'
import { registraRefeicao } from './tools.js'
import type { ServiceClient } from '@mpp/db'

// Tests focados na decisão de replace=true/false (defesa em profundidade).
//
// Bugs reais cobertos:
//   - 2026-05-12 esposa do Roberto: foto detectou 200g arroz / 180g carne (errado).
//     Ela respondeu "100g arroz, 100g carne" sem dizer "corrige". LLM mandou
//     replace=false. Sistema antigo SOMOU. Fix: detecção implícita por overlap.
//   - 2026-05-13 sogro do Roberto Paulo: foto identificou bebida láctea zerada.
//     Paulo respondeu "Leite semi desnatado com café". LLM mandou replace=true
//     CORRETAMENTE. Sistema antigo derrubou pra false porque msg não tinha
//     palavra "corrige". Fix: aceita evidência objetiva (overlap) também.
//
// Cobertura das 4 combinações:
//   replace= | verbal | overlap | esperado
//   false    | -      | sim     | auto-true (implicit_detected)
//   true     | sim    | -       | kept (sem downgrade)
//   true     | não    | sim     | kept (ratified_by_overlap) ← bug Paulo
//   true     | não    | não     | downgrade (blocked_no_correction)

type RecentLog = { food_name: string; quantity_g: number }

interface MockOptions {
  recentLogs?: RecentLog[]
  recentUserMessages?: string[]
  llmSentReplace?: boolean
}

interface CapturedEvent {
  event: string
  properties: Record<string, unknown>
}

function makeContextAndSupabase(opts: MockOptions) {
  const events: CapturedEvent[] = []
  let finalReplace: boolean | undefined = opts.llmSentReplace

  // Helper que retorna chain "Supabase-like" que ignora qualquer método
  // e termina com data fornecida. Suporta await (thenable).
  const chain = (rows: unknown): unknown => {
    const obj: Record<string, unknown> = { data: rows, error: null }
    for (const m of ['select', 'eq', 'ilike', 'like', 'gte', 'gt', 'lt', 'lte', 'neq', 'in', 'is', 'or', 'order', 'limit', 'range', 'maybeSingle', 'single']) {
      obj[m] = () => chain(rows)
    }
    obj.then = (cb: (v: { data: unknown; error: null }) => unknown) =>
      Promise.resolve(cb({ data: rows, error: null }))
    return obj
  }

  const supabase = {
    from: (table: string) => {
      if (table === 'meal_logs') {
        // O execute() chama várias vezes meal_logs com queries diferentes.
        // Mais simples: retornar os logs configurados pra qualquer query.
        // O bloco de detecção objetiva usa .eq('meal_type', X).gte('created_at').limit().
        // Idempotência usa .eq('raw_provider_message_id', X).
        // Sem providerMessageId, idempotência não pega. Replace block deleta — fingir 0 rows.
        return {
          ...((chain(opts.recentLogs ?? []) as object)),
          insert: () => chain([]),
          delete: () => chain([]),
        }
      }
      if (table === 'product_events') {
        return {
          insert: (e: CapturedEvent | CapturedEvent[]) => {
            const arr = Array.isArray(e) ? e : [e]
            for (const ev of arr) events.push(ev)
            return chain(null)
          },
        }
      }
      // daily_snapshots, users, etc — stub vazio
      return {
        ...((chain([]) as object)),
        insert: () => chain([]),
        update: () => chain([]),
        delete: () => chain([]),
        upsert: () => chain([]),
      }
    },
    rpc: async (fn: string) => {
      if (fn === 'search_food_trgm') return { data: [], error: null }
      if (fn === 'snapshot_add_meal')
        return {
          data: { id: 'snap-mock', calories_consumed: 0, protein_g: 0, calories_target: null, protein_target: null, daily_balance: 0 },
          error: null,
        }
      return { data: null, error: null }
    },
  } as unknown as ServiceClient

  return {
    supabase,
    events,
    ctx: {
      supabase,
      userId: 'user-test',
      userWpp: '5511999999999',
      userCountry: 'BR',
      userTimezone: 'America/Sao_Paulo',
      recentUserMessages: opts.recentUserMessages ?? [],
    },
    getFinalReplace: () => finalReplace,
  }
}

describe('registra_refeicao — decisão de replace (bug Paulo + esposa Roberto)', () => {
  it('replace=false + overlap >=50% → auto-aplica replace=true (implicit detected)', async () => {
    const { ctx, events } = makeContextAndSupabase({
      recentLogs: [
        { food_name: 'arroz branco', quantity_g: 200 },
        { food_name: 'carne assada', quantity_g: 180 },
      ],
      recentUserMessages: ['100g arroz, 100g carne'],
      llmSentReplace: false,
    })
    await registraRefeicao.execute(
      {
        meal_type: 'almoco',
        replace: false,
        items: [
          { food_name: 'arroz branco', quantity_g: 100 },
          { food_name: 'carne assada', quantity_g: 100 },
        ],
      },
      ctx,
    )
    // Deve ter detectado implicit replace
    const implicit = events.find((e) => e.event === 'tool.replace_implicit_detected')
    expect(implicit).toBeDefined()
    expect(implicit?.properties.overlap_ratio).toBe(1)
    // NÃO deve ter blocked event
    expect(events.find((e) => e.event === 'tool.replace_blocked_no_correction')).toBeUndefined()
  })

  it('replace=true + palavra-chave verbal ("corrige") → mantém, sem downgrade', async () => {
    const { ctx, events } = makeContextAndSupabase({
      recentLogs: [],
      recentUserMessages: ['Corrige aí, era frango não peixe'],
      llmSentReplace: true,
    })
    await registraRefeicao.execute(
      {
        meal_type: 'almoco',
        replace: true,
        items: [{ food_name: 'frango grelhado', quantity_g: 150 }],
      },
      ctx,
    )
    // Sem evento de blocked nem downgrade
    expect(events.find((e) => e.event === 'tool.replace_blocked_no_correction')).toBeUndefined()
  })

  it('replace=true + SEM palavra-chave + overlap >=50% → mantém (ratified_by_overlap) — bug do PAULO', async () => {
    // Cenário do Paulo: foto identificou itens errados. Paulo respondeu re-listando
    // com correção. LLM mandou replace=true certo. Antes: downgrade. Agora: ratified.
    const { ctx, events } = makeContextAndSupabase({
      recentLogs: [
        { food_name: 'pão de forma integral', quantity_g: 60 },
        { food_name: 'requeijão', quantity_g: 30 },
        { food_name: 'bebida láctea com espuma', quantity_g: 200 },
      ],
      recentUserMessages: ['Leite semi desnatado com café'],
      llmSentReplace: true,
    })
    await registraRefeicao.execute(
      {
        meal_type: 'cafe',
        replace: true,
        items: [
          { food_name: 'pão de forma integral', quantity_g: 60 },
          { food_name: 'requeijão', quantity_g: 30 },
          { food_name: 'leite semi desnatado', quantity_g: 200 },
          { food_name: 'café preto', quantity_g: 5 },
        ],
      },
      ctx,
    )
    // Deve ter evento ratified, NÃO blocked
    expect(events.find((e) => e.event === 'tool.replace_ratified_by_overlap')).toBeDefined()
    expect(events.find((e) => e.event === 'tool.replace_blocked_no_correction')).toBeUndefined()
  })

  it('replace=true + SEM palavra-chave + SEM overlap → downgrade (blocked)', async () => {
    // Cenário: LLM hallucinou replace=true sem motivo. Defesa derruba pra false.
    const { ctx, events } = makeContextAndSupabase({
      recentLogs: [],
      recentUserMessages: ['mandei foto do café'],
      llmSentReplace: true,
    })
    await registraRefeicao.execute(
      {
        meal_type: 'cafe',
        replace: true,
        items: [{ food_name: 'pão', quantity_g: 50 }],
      },
      ctx,
    )
    const blocked = events.find((e) => e.event === 'tool.replace_blocked_no_correction')
    expect(blocked).toBeDefined()
    expect(blocked?.properties.overlap_ratio).toBe(0)
  })
})
