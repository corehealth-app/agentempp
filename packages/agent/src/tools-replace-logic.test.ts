import type { ServiceClient } from '@mpp/db'
import { describe, expect, it } from 'vitest'
import { registraRefeicao } from './tools.js'

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

type RecentLog = {
  id?: string
  food_name: string
  quantity_g: number
  meal_type?: string
  kcal?: number
  protein_g?: number
  carbs_g?: number
  fat_g?: number
  consumed_at?: string
  raw_provider_message_id?: string | null
}

interface MockOptions {
  /** Logs dentro da janela de 30min (consultados via .gte('created_at')) —
   * alimentam a detecção objetiva de correção por overlap. */
  recentLogs?: RecentLog[]
  /** Logs já registrados HOJE no snapshot (consultados sem .gte) — alimentam a
   * 4ª camada de dedup contra o dia (caso Paulo 2026-05-24). Fora da janela
   * de 30min, então NÃO aparecem em recentLogs. Default: igual recentLogs. */
  dayLogs?: RecentLog[]
  recentUserMessages?: string[]
  llmSentReplace?: boolean
  editedPendings?: Array<{
    id: string
    resolved_at?: string | null
    proposal?: Record<string, unknown>
  }>
  providerMessageId?: string
  mealQueryErrors?: {
    idempotency?: string
    recentCorrection?: string
    sameDay?: string
  }
  foodCorrectionErrors?: {
    lookup?: string
    write?: string
  }
  currentUserText?: string
}

interface CapturedEvent {
  event: string
  properties: Record<string, unknown>
}

function makeContextAndSupabase(opts: MockOptions) {
  const events: CapturedEvent[] = []
  const rpcCalls: Array<{ fn: string; params: Record<string, unknown> }> = []
  const mealInserts: Array<Record<string, unknown>> = []
  const foodCorrectionWrites: Array<Record<string, unknown>> = []
  const finalReplace: boolean | undefined = opts.llmSentReplace

  // Helper que retorna chain "Supabase-like" que ignora qualquer método
  // e termina com data fornecida. Suporta await (thenable).
  const chain = (rows: unknown): unknown => {
    const obj: Record<string, unknown> = { data: rows, error: null }
    for (const m of [
      'select',
      'eq',
      'ilike',
      'like',
      'gte',
      'gt',
      'lt',
      'lte',
      'neq',
      'in',
      'is',
      'or',
      'order',
      'limit',
      'range',
      'maybeSingle',
      'single',
    ]) {
      obj[m] = () => chain(rows)
    }
    obj.then = (cb: (v: { data: unknown; error: null }) => unknown) =>
      Promise.resolve(cb({ data: rows, error: null }))
    return obj
  }

  const resultChain = (rows: unknown, errorMessage?: string): unknown => {
    const obj: Record<string, unknown> = {
      data: errorMessage ? null : rows,
      error: errorMessage ? { message: errorMessage } : null,
    }
    for (const m of [
      'select',
      'eq',
      'or',
      'neq',
      'gte',
      'order',
      'limit',
      'single',
      'maybeSingle',
    ]) {
      obj[m] = () => resultChain(rows, errorMessage)
    }
    obj.then = (cb: (v: { data: unknown; error: { message: string } | null }) => unknown) =>
      Promise.resolve(
        cb(
          errorMessage
            ? { data: null, error: { message: errorMessage } }
            : { data: rows, error: null },
        ),
      )
    return obj
  }

  const supabase = {
    from: (table: string) => {
      if (table === 'meal_logs') {
        // O execute() chama várias vezes meal_logs com queries diferentes:
        //  - detecção objetiva por overlap: .gte('created_at', 30minAgo).limit() → janela 30min.
        //  - 4ª camada de dedup contra o dia: .eq('snapshot_id').eq('meal_type') SEM .gte → dia inteiro.
        //  - idempotência: .eq('raw_provider_message_id', X) (sem providerMessageId, não pega).
        //  - replace block: deleta — fingir 0 rows.
        // Roteia por presença de .gte(): com gte → recentLogs (janela), sem gte → dayLogs (dia).
        const enrichLogs = (rows: RecentLog[]) =>
          rows.map((row, index) => ({
            id: row.id ?? `meal-log-${index + 1}`,
            kcal: row.kcal ?? 100,
            protein_g: row.protein_g ?? 10,
            carbs_g: row.carbs_g ?? 10,
            fat_g: row.fat_g ?? 5,
            consumed_at: row.consumed_at ?? '2026-07-13T20:00:00Z',
            raw_provider_message_id: row.raw_provider_message_id ?? 'provider-registration-default',
            ...row,
          }))
        const dayLogs = enrichLogs(opts.dayLogs ?? opts.recentLogs ?? [])
        const recentLogs = enrichLogs(opts.recentLogs ?? [])
        // Chain stateful que lembra os filtros usados para devolver o dataset
        // ou a falha correspondente à etapa que está sendo exercitada.
        const mealChain = (state: {
          usedGte: boolean
          rawProviderMessage: boolean
          snapshot: boolean
        }): unknown => {
          const obj: Record<string, unknown> = {}
          for (const m of [
            'select',
            'ilike',
            'like',
            'gt',
            'lt',
            'lte',
            'neq',
            'in',
            'is',
            'not',
            'or',
            'order',
            'limit',
            'range',
            'maybeSingle',
            'single',
          ]) {
            obj[m] = () => mealChain(state)
          }
          obj.eq = (column: string) =>
            mealChain({
              ...state,
              rawProviderMessage: state.rawProviderMessage || column === 'raw_provider_message_id',
              snapshot: state.snapshot || column === 'snapshot_id',
            })
          obj.gte = () => mealChain({ ...state, usedGte: true })
          obj.then = (cb: (v: { data: unknown; error: { message: string } | null }) => unknown) => {
            const errorMessage = state.rawProviderMessage
              ? opts.mealQueryErrors?.idempotency
              : state.usedGte
                ? opts.mealQueryErrors?.recentCorrection
                : state.snapshot
                  ? opts.mealQueryErrors?.sameDay
                  : undefined
            return Promise.resolve(
              cb(
                errorMessage
                  ? { data: null, error: { message: errorMessage } }
                  : {
                      data: state.usedGte ? recentLogs : dayLogs,
                      error: null,
                    },
              ),
            )
          }
          return obj
        }
        return {
          ...(mealChain({
            usedGte: false,
            rawProviderMessage: false,
            snapshot: false,
          }) as object),
          insert: (row: Record<string, unknown> | Record<string, unknown>[]) => {
            for (const r of Array.isArray(row) ? row : [row]) mealInserts.push(r)
            return chain([])
          },
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
      if (table === 'user_food_corrections') {
        const correctionLookupChain = (usedOr: boolean): unknown => {
          const obj: Record<string, unknown> = {}
          for (const method of ['select', 'eq', 'neq', 'gte', 'order', 'limit']) {
            obj[method] = () => correctionLookupChain(usedOr)
          }
          obj.or = () => correctionLookupChain(true)
          obj.then = (
            cb: (value: { data: unknown; error: { message: string } | null }) => unknown,
          ) => {
            const errorMessage = usedOr ? undefined : opts.foodCorrectionErrors?.lookup
            return Promise.resolve(
              cb(
                errorMessage
                  ? { data: null, error: { message: errorMessage } }
                  : { data: [], error: null },
              ),
            )
          }
          return obj
        }
        return {
          ...(correctionLookupChain(false) as object),
          insert: (row: Record<string, unknown>) => {
            foodCorrectionWrites.push(row)
            return resultChain([], opts.foodCorrectionErrors?.write)
          },
          update: (row: Record<string, unknown>) => {
            foodCorrectionWrites.push(row)
            return resultChain([], opts.foodCorrectionErrors?.write)
          },
        }
      }
      if (table === 'pending_registrations') {
        return {
          ...(chain(opts.editedPendings ?? []) as object),
          insert: () => chain([]),
          update: () => chain([]),
          delete: () => chain([]),
        }
      }
      // daily_snapshots → retorna snapshot mock (precisa pra path do replace)
      if (table === 'daily_snapshots') {
        return {
          ...(chain({ id: 'snap-mock' }) as object),
          insert: () => chain({ id: 'snap-mock' }),
          update: () => chain({ id: 'snap-mock' }),
          upsert: () => chain({ id: 'snap-mock' }),
        }
      }
      // outros — stub vazio
      return {
        ...(chain([]) as object),
        insert: () => chain([]),
        update: () => chain([]),
        delete: () => chain([]),
        upsert: () => chain([]),
      }
    },
    rpc: async (fn: string, params?: Record<string, unknown>) => {
      rpcCalls.push({ fn, params: params ?? {} })
      if (fn === 'search_food_trgm') return { data: [], error: null }
      if (fn === 'snapshot_add_meal')
        return {
          data: {
            id: 'snap-mock',
            calories_consumed: 0,
            protein_g: 0,
            calories_target: null,
            protein_target: null,
            daily_balance: 0,
          },
          error: null,
        }
      if (fn === 'register_meal_atomic' || fn === 'register_meal_atomic_scoped') {
        const items = (params?.p_items ?? []) as Array<Record<string, unknown>>
        mealInserts.push(
          ...items.map((item) => ({
            ...item,
            meal_type: params?.p_meal_type ?? null,
            consumed_at: params?.p_consumed_at ?? null,
          })),
        )
        return {
          data: {
            snapshot_id: 'snap-mock',
            inserted_count: items.length,
            inserted_food_names: items.map((item) => String(item.food_name)),
            replaced_count: Number(params?.p_replace ? 1 : 0),
            calories_consumed: items.reduce((sum, item) => sum + Number(item.kcal ?? 0), 0),
            protein_g: items.reduce((sum, item) => sum + Number(item.protein_g ?? 0), 0),
            carbs_g: items.reduce((sum, item) => sum + Number(item.carbs_g ?? 0), 0),
            fat_g: items.reduce((sum, item) => sum + Number(item.fat_g ?? 0), 0),
            calories_target: null,
            protein_target: null,
            daily_balance: 0,
          },
          error: null,
        }
      }
      return { data: null, error: null }
    },
  } as unknown as ServiceClient

  return {
    supabase,
    events,
    rpcCalls,
    mealInserts,
    foodCorrectionWrites,
    ctx: {
      supabase,
      userId: 'user-test',
      userWpp: '5511999999999',
      userCountry: 'BR',
      userTimezone: 'America/Sao_Paulo',
      recentUserMessages: opts.recentUserMessages ?? [],
      currentUserText: opts.currentUserText,
      providerMessageId: opts.providerMessageId,
    },
    getFinalReplace: () => finalReplace,
  }
}

describe('registra_refeicao — decisão de replace (bug Paulo + esposa Roberto)', () => {
  it('troca salame por calabresa sem reinserir os itens inalterados do jantar — caso Roberto 15/07', async () => {
    const { ctx, rpcCalls } = makeContextAndSupabase({
      recentLogs: [
        {
          id: 'rap10-log',
          food_name: 'rap10',
          quantity_g: 35,
          kcal: 70,
          meal_type: 'jantar',
          raw_provider_message_id: 'dinner-registration',
        },
        {
          id: 'egg-log',
          food_name: 'ovo cozido',
          quantity_g: 100,
          kcal: 146,
          meal_type: 'jantar',
          raw_provider_message_id: 'dinner-registration',
        },
        {
          id: 'salami-log',
          food_name: 'salame fatiado',
          quantity_g: 60,
          kcal: 201.6,
          meal_type: 'jantar',
          raw_provider_message_id: 'dinner-registration',
        },
        {
          id: 'tomato-log',
          food_name: 'tomate cereja',
          quantity_g: 40,
          kcal: 7.2,
          meal_type: 'jantar',
          raw_provider_message_id: 'dinner-registration',
        },
        {
          id: 'cheese-log',
          food_name: 'queijo derretido',
          quantity_g: 30,
          kcal: 87,
          meal_type: 'jantar',
          raw_provider_message_id: 'dinner-registration',
        },
      ],
      currentUserText: 'Digo, salame por calabresa',
      recentUserMessages: ['Digo, salame por calabresa'],
      llmSentReplace: true,
    })

    await registraRefeicao.execute(
      {
        meal_type: 'jantar',
        replace: true,
        items: [
          { food_name: 'rap10', quantity_g: 35 },
          { food_name: 'ovo cozido', quantity_g: 100 },
          { food_name: 'calabresa fatiada', quantity_g: 60 },
          { food_name: 'tomate cereja', quantity_g: 40 },
          { food_name: 'queijo derretido', quantity_g: 30 },
        ],
        corrections: [{ de: 'salame fatiado', para: 'calabresa fatiada' }],
      },
      ctx,
    )

    const atomic = rpcCalls.find((call) => call.fn === 'register_meal_atomic_scoped')
    expect(atomic?.params.p_replace_log_ids).toEqual(['salami-log'])
    expect(
      (atomic?.params.p_items as Array<{ food_name: string }>).map((item) => item.food_name),
    ).toEqual(['calabresa fatiada'])
  })

  it('corrige somente o leite em pó e nunca apaga almoço/lanche inteiros — caso Roberto', async () => {
    const { ctx, events, rpcCalls } = makeContextAndSupabase({
      recentLogs: [
        {
          id: 'milk-log',
          food_name: 'leite em pó desnatado',
          quantity_g: 30,
          kcal: 108,
          meal_type: 'almoco',
          consumed_at: '2026-07-13T20:10:24Z',
          raw_provider_message_id: 'milk-add',
        },
      ],
      dayLogs: [
        {
          id: 'breakfast',
          food_name: 'café da manhã',
          quantity_g: 300,
          kcal: 593,
          meal_type: 'cafe',
        },
        { id: 'lunch', food_name: 'almoço', quantity_g: 500, kcal: 639, meal_type: 'almoco' },
        {
          id: 'kumis',
          food_name: 'iogurte kumis',
          quantity_g: 150,
          kcal: 125,
          meal_type: 'lanche',
        },
        {
          id: 'milk-log',
          food_name: 'leite em pó desnatado',
          quantity_g: 30,
          kcal: 108,
          meal_type: 'almoco',
          consumed_at: '2026-07-13T20:10:24Z',
          raw_provider_message_id: 'milk-add',
        },
      ],
      currentUserText: '30 gramas do leite em pó que usei tem apenas 85 kcal',
      recentUserMessages: ['30 gramas do leite em pó que usei tem apenas 85 kcal'],
      llmSentReplace: true,
    })

    await registraRefeicao.execute(
      {
        meal_type: 'lanche',
        replace: true,
        items: [{ food_name: 'leite em pó desnatado', quantity_g: 30, user_kcal: 85 }],
      },
      ctx,
    )

    const atomic = rpcCalls.find((call) => call.fn === 'register_meal_atomic_scoped')
    expect(atomic?.params.p_replace_log_ids).toEqual(['milk-log'])
    expect(atomic?.params.p_replace_meal_types).toBeNull()
    expect(events.find((event) => event.event === 'tool.replace_item_scoped')).toMatchObject({
      properties: {
        target_log_ids: ['milk-log'],
        from_meal_type: 'almoco',
        to_meal_type: 'lanche',
      },
    })
    expect(events.find((event) => event.event === 'tool.replace_cross_meal_type')).toBeUndefined()
  })

  it('correção explícita da refeição inteira apaga somente o registro alvo', async () => {
    const { ctx, rpcCalls } = makeContextAndSupabase({
      recentLogs: [
        {
          id: 'fried',
          food_name: 'frango frito',
          quantity_g: 120,
          meal_type: 'almoco',
          consumed_at: '2026-07-13T18:00:00Z',
          raw_provider_message_id: 'lunch-registration',
        },
        {
          id: 'rice',
          food_name: 'arroz branco',
          quantity_g: 100,
          meal_type: 'almoco',
          consumed_at: '2026-07-13T18:00:00Z',
          raw_provider_message_id: 'lunch-registration',
        },
      ],
      currentUserText: 'Corrige o almoço inteiro',
      recentUserMessages: ['Corrige o almoço inteiro'],
      llmSentReplace: true,
    })

    await registraRefeicao.execute(
      {
        meal_type: 'almoco',
        replace: true,
        items: [{ food_name: 'frango grelhado', quantity_g: 120 }],
      },
      ctx,
    )

    const atomic = rpcCalls.find((call) => call.fn === 'register_meal_atomic_scoped')
    expect(atomic?.params.p_replace_log_ids).toEqual(['fried', 'rice'])
    expect(atomic?.params.p_replace_meal_types).toBeNull()
  })

  it('vincula leite adicionado ao iogurte ao lanche, apesar da rotina sugerir almoço', async () => {
    const { ctx, events, rpcCalls } = makeContextAndSupabase({
      recentLogs: [
        {
          id: 'kumis-log',
          food_name: 'iogurte kumis',
          quantity_g: 150,
          meal_type: 'lanche',
          consumed_at: new Date(Date.now() - 2 * 60_000).toISOString(),
          raw_provider_message_id: 'kumis-confirm',
        },
      ],
      currentUserText: 'Adicionei 30g de leite em pó desnatado ao iogurte',
      recentUserMessages: ['Adicionei 30g de leite em pó desnatado ao iogurte'],
    })

    await registraRefeicao.execute(
      {
        meal_type: 'almoco',
        replace: false,
        items: [{ food_name: 'leite em pó desnatado', quantity_g: 30 }],
      },
      ctx,
    )

    const atomic = rpcCalls.find((call) => call.fn === 'register_meal_atomic')
    expect(atomic?.params.p_meal_type).toBe('lanche')
    expect(events.find((event) => event.event === 'tool.meal_type_linked_addition')).toMatchObject({
      properties: { linked_meal_type: 'lanche', matched_log_id: 'kumis-log' },
    })
  })

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

  it('replace=true + pending editado recente + item diferente NÃO apaga jantar anterior — caso Roberto torta', async () => {
    const { ctx, events, rpcCalls, mealInserts } = makeContextAndSupabase({
      dayLogs: [
        {
          id: 'meal-bolo',
          food_name: 'bolo salgado de frango',
          quantity_g: 130,
          meal_type: 'jantar',
          kcal: 210,
          protein_g: 18,
          carbs_g: 20,
          fat_g: 8,
        },
        {
          id: 'meal-requeijao',
          food_name: 'requeijão cremoso',
          quantity_g: 40,
          meal_type: 'jantar',
          kcal: 107,
          protein_g: 3,
          carbs_g: 2,
          fat_g: 10,
        },
      ],
      recentLogs: [],
      editedPendings: [
        {
          id: 'pending-foto-editado',
          resolved_at: new Date().toISOString(),
          proposal: {
            kind: 'meal',
            mealType: 'jantar',
            items: [{ name: 'couve-flor grelhada', quantity_g: 150 }],
          },
        },
      ],
      recentUserMessages: ['Torta de frango'],
      llmSentReplace: true,
    })

    await registraRefeicao.execute(
      {
        meal_type: 'jantar',
        replace: true,
        items: [{ food_name: 'torta de frango', quantity_g: 150 }],
      },
      ctx,
    )

    expect(
      events.find((e) => e.event === 'tool.replace_ratified_by_proposal_context'),
    ).toBeUndefined()
    expect(events.find((e) => e.event === 'tool.replace_blocked_no_correction')).toBeDefined()
    expect(events.find((e) => e.event === 'tool.replace_blocked_weak_evidence')).toBeDefined()
    expect(rpcCalls.find((c) => c.fn === 'register_meal_atomic')?.params.p_replace).toBe(false)
    expect(mealInserts.some((r) => r.food_name === 'torta de frango')).toBe(true)
  })

  it('replace=true + intenção de adição explícita força INSERT, mesmo se LLM pediu replace', async () => {
    const { ctx, events, rpcCalls } = makeContextAndSupabase({
      dayLogs: [
        {
          id: 'meal-torta-1',
          food_name: 'torta de frango',
          quantity_g: 150,
          meal_type: 'jantar',
          kcal: 435,
        },
      ],
      recentLogs: [
        {
          id: 'meal-torta-1',
          food_name: 'torta de frango',
          quantity_g: 150,
          meal_type: 'jantar',
          kcal: 435,
        },
      ],
      recentUserMessages: ['comi mais um pedaço de torta de frango'],
      llmSentReplace: true,
    })

    await registraRefeicao.execute(
      {
        meal_type: 'jantar',
        replace: true,
        items: [{ food_name: 'torta de frango', quantity_g: 150 }],
      },
      ctx,
    )

    expect(events.find((e) => e.event === 'tool.replace_blocked_addition_intent')).toBeDefined()
    expect(rpcCalls.find((c) => c.fn === 'register_meal_atomic')?.params.p_replace).toBe(false)
  })

  it('preserva user_kcal aprovado no pending ao gravar pela tool', async () => {
    const { ctx, mealInserts, rpcCalls } = makeContextAndSupabase({
      recentLogs: [],
      dayLogs: [],
      recentUserMessages: [],
    })

    await registraRefeicao.execute(
      {
        meal_type: 'lanche',
        replace: false,
        items: [{ food_name: 'goiaba', quantity_g: 150, user_kcal: 95 }],
      } as never,
      ctx,
    )

    expect(Number(mealInserts[0]?.kcal)).toBe(95)
    const atomicCall = rpcCalls.find((c) => c.fn === 'register_meal_atomic')
    expect((atomicCall?.params.p_items as Array<{ kcal: number }>)[0]?.kcal).toBe(95)
  })

  it('propaga food_db_id aprovado no pending até register_meal_atomic', async () => {
    const { ctx, rpcCalls } = makeContextAndSupabase({
      recentLogs: [],
      dayLogs: [],
      recentUserMessages: [],
    })

    await registraRefeicao.execute(
      {
        meal_type: 'lanche',
        replace: false,
        items: [
          {
            food_name: 'sorvete',
            quantity_g: 120,
            approved_nutrition: {
              food_db_id: 379,
              kcal: 252,
              protein_g: 4.2,
              carbs_g: 28.8,
              fat_g: 13.2,
            },
          },
        ],
      } as never,
      ctx,
    )

    const atomicCall = rpcCalls.find((call) => call.fn === 'register_meal_atomic')
    const item = (atomicCall?.params.p_items as Array<Record<string, unknown>> | undefined)?.[0]
    expect(item).toMatchObject({
      food_db_id: 379,
      source: 'pending_approved',
      kcal: 252,
    })
  })

  it('preserva kcal explícita de mensagem anterior quando confirmação curta diz "Sim isso" — caso Luciana', async () => {
    const { ctx, mealInserts, rpcCalls, events } = makeContextAndSupabase({
      recentLogs: [],
      dayLogs: [],
      recentUserMessages: ['Torta de legumes 80 calorias\nPão baguete 60 calorias', 'Sim isso'],
    })

    await registraRefeicao.execute(
      {
        meal_type: 'lanche',
        replace: false,
        items: [
          { food_name: 'torta de legumes', quantity_g: 100 },
          { food_name: 'pão baguete', quantity_g: 50 },
        ],
      } as never,
      ctx,
    )

    expect(Number(mealInserts.find((r) => r.food_name === 'torta de legumes')?.kcal)).toBe(80)
    expect(Number(mealInserts.find((r) => r.food_name === 'pão baguete')?.kcal)).toBe(60)
    const atomicCall = rpcCalls.find((c) => c.fn === 'register_meal_atomic')
    expect(
      (atomicCall?.params.p_items as Array<{ kcal: number }>).reduce(
        (sum, item) => sum + item.kcal,
        0,
      ),
    ).toBe(140)
    expect(events.find((e) => e.event === 'pipeline.user_kcal_override')).toBeDefined()
  })

  it('não transforma o Total de um resumo nutricional em kcal do último item — caso Roberto', async () => {
    const summary = `• pão francês (1 pão) — 150 kcal
• ovo frito (1 unidade) — 94 kcal
• queijo mussarela (30g) — 84 kcal
• leite com whey (240 ml) — 228 kcal
• geleia (15g) — 38 kcal
Total: 593 kcal | 41.6g proteína | 51.8g carboidrato | 22.6g gordura`
    const { ctx, mealInserts, rpcCalls, events } = makeContextAndSupabase({
      recentLogs: [],
      dayLogs: [],
      recentUserMessages: [summary],
    })

    await registraRefeicao.execute(
      {
        meal_type: 'cafe',
        replace: false,
        items: [
          { food_name: 'pão francês', quantity_g: 50 },
          { food_name: 'ovo frito', quantity_g: 50 },
          { food_name: 'queijo mussarela', quantity_g: 30 },
          { food_name: 'leite com whey', quantity_g: 240 },
          { food_name: 'geleia', quantity_g: 15 },
        ],
      } as never,
      ctx,
    )

    expect(Number(mealInserts.find((row) => row.food_name === 'geleia')?.kcal)).toBe(39)
    const atomicCall = rpcCalls.find((call) => call.fn === 'register_meal_atomic')
    expect(atomicCall).toBeDefined()
    const savedItems = (atomicCall?.params.p_items as Array<{ kcal: number }> | undefined) ?? []
    expect(savedItems.reduce((sum, item) => sum + item.kcal, 0)).not.toBe(593)
    expect(events.find((event) => event.event === 'pipeline.user_kcal_override')).toBeUndefined()
  })

  // BUG do PAULO 2026-05-13 18:43-19:15 (cross-meal-type):
  // Foto chegou 15:43 BRT → registrada como 'lanche'. Paulo corrigiu, LLM
  // mandou meal_type='almoco' + replace=true. Antes: detector filtrava só
  // pelo mesmo meal_type → não viu o 'lanche' → bloqueou → SOMOU.
  // Agora: detector olha qualquer meal_type recente e captura cross.
  it('replace=true + overlap em meal_type DIFERENTE (cross-meal-type) — bug do PAULO', async () => {
    const { ctx, events } = makeContextAndSupabase({
      recentLogs: [
        { food_name: 'carne assada', quantity_g: 150, meal_type: 'lanche' },
        { food_name: 'ovo frito', quantity_g: 100, meal_type: 'lanche' },
        { food_name: 'arroz cozido', quantity_g: 150, meal_type: 'lanche' },
        { food_name: 'lentilha cozida', quantity_g: 50, meal_type: 'lanche' },
        { food_name: 'couve refogada', quantity_g: 50, meal_type: 'lanche' },
      ],
      // Menciona "almoço" pra suprimir o autocorrect de meal_type por hora —
      // sem isso o teste é flaky (ex: rodando 19h+ BRT, almoço→jantar).
      recentUserMessages: ['no almoço os ovos fritos foram sem gordura'],
      llmSentReplace: true,
    })
    await registraRefeicao.execute(
      {
        meal_type: 'almoco', // LLM corrigiu lanche → almoco
        replace: true,
        items: [
          { food_name: 'carne assada', quantity_g: 150 },
          { food_name: 'ovos fritos sem gordura', quantity_g: 100 },
          { food_name: 'arroz cozido', quantity_g: 150 },
          { food_name: 'lentilha cozida', quantity_g: 50 },
          { food_name: 'couve refogada', quantity_g: 50 },
        ],
      },
      ctx,
    )
    // Deve ratificar via overlap (cross-meal-type)
    expect(events.find((e) => e.event === 'tool.replace_ratified_by_overlap')).toBeDefined()
    // E NÃO deve ter sido blocked
    expect(events.find((e) => e.event === 'tool.replace_blocked_no_correction')).toBeUndefined()
    // O cross-meal existe, mas o delete fica restrito aos IDs do registro.
    const scoped = events.find((e) => e.event === 'tool.replace_item_scoped')
    expect(scoped).toBeDefined()
    expect(scoped?.properties.from_meal_type).toBe('lanche')
    expect(scoped?.properties.to_meal_type).toBe('almoco')
    expect(scoped?.properties.target_log_ids).toHaveLength(5)
    expect(events.find((e) => e.event === 'tool.replace_cross_meal_type')).toBeUndefined()
  })

  it('mesmo meal_type prevalece quando há logs em ambos (não confunde cross)', async () => {
    // Se há logs em lanche E em almoco recentes, e LLM manda almoco com overlap
    // alto no almoco, NÃO deve marcar cross — usa só o mesmo meal_type.
    const { ctx, events } = makeContextAndSupabase({
      recentLogs: [
        { food_name: 'biscoito', quantity_g: 30, meal_type: 'lanche' }, // sem overlap
        { food_name: 'arroz', quantity_g: 100, meal_type: 'almoco' }, // overlap
        { food_name: 'feijão', quantity_g: 80, meal_type: 'almoco' }, // overlap
      ],
      recentUserMessages: ['era 150g de arroz, não 100'],
      llmSentReplace: true,
    })
    await registraRefeicao.execute(
      {
        meal_type: 'almoco',
        replace: true,
        items: [
          { food_name: 'arroz', quantity_g: 150 },
          { food_name: 'feijão', quantity_g: 80 },
        ],
      },
      ctx,
    )
    // Deve ratificar mas NÃO deve marcar cross-meal-type (mesmo tipo prevalece)
    expect(events.find((e) => e.event === 'tool.replace_ratified_by_overlap')).toBeDefined()
    expect(events.find((e) => e.event === 'tool.replace_cross_meal_type')).toBeUndefined()
  })

  // BUG da AMANDA 2026-05-15: ela mandou "É cuscuz, não farofa" + "Apenas 1
  // unidade nessa foto". Verbal NÃO matchou (formas naturais que o detector
  // não cobria), overlap só 25-40% (corrige 1 item por vez de uma refeição
  // de 3+ itens). Resultado: blocker derrubava replace, consumido somava
  // a cada correção. Fix: se LLM preencheu corrections[] não-vazio, isso já
  // é evidência objetiva — bypass do blocker.
  it('corrections[] não-vazio bypassa o blocker mesmo sem verbal/overlap — bug da AMANDA', async () => {
    const { ctx, events } = makeContextAndSupabase({
      recentLogs: [
        { food_name: 'pão sírio tostado', quantity_g: 50, meal_type: 'cafe' },
        { food_name: 'ovo mexido', quantity_g: 100, meal_type: 'cafe' },
        { food_name: 'farofa', quantity_g: 120, meal_type: 'cafe' },
      ],
      recentUserMessages: ['É cuscuz, não farofa'],
      llmSentReplace: true,
    })
    await registraRefeicao.execute(
      {
        meal_type: 'cafe',
        replace: true,
        items: [
          { food_name: 'pão francês', quantity_g: 50 },
          { food_name: 'ovo mexido', quantity_g: 100 },
          { food_name: 'cuscuz', quantity_g: 120 },
        ],
        // LLM preencheu corrections[] declarando explicitamente a correção
        corrections: [{ de: 'farofa', para: 'cuscuz' }],
      },
      ctx,
    )
    // NÃO deve ser blocked — corrections[] preenchido é evidência objetiva
    expect(events.find((e) => e.event === 'tool.replace_blocked_no_correction')).toBeUndefined()
    // Captura da correção deve ter rodado
    expect(events.find((e) => e.event === 'food_correction.learned')).toBeDefined()
  })

  // BUG da AMANDA 2026-05-15 19:11: ela mandou "Burrito de filé\n1 coca 250ml".
  // LLM duplicou: items=[burrito,burrito,coca,coca] → 1.110 kcal em vez de 555.
  // Luciana 2026-05-11 14:09: 4x cenoura/tomate/alface/arroz num único almoço
  // (snapshot calorias_consumed=3424 vs real ~1156). Fix: dedup intra-array
  // antes do calcMealMacros — cópias idênticas devem ser colapsadas, não
  // somadas. Somar 300+300 preservava justamente a duplicação que o guard
  // deveria remover.
  it('items idênticos no mesmo call mantêm uma única porção — bug da AMANDA/LUCIANA', async () => {
    const { ctx, events } = makeContextAndSupabase({
      recentLogs: [],
      recentUserMessages: ['Burrito de filé\n1 coca 250ml'],
      llmSentReplace: false,
    })
    await registraRefeicao.execute(
      {
        meal_type: 'jantar',
        replace: false,
        items: [
          { food_name: 'burrito de filé', quantity_g: 300 },
          { food_name: 'coca-cola', quantity_g: 250 },
          { food_name: 'Burrito de Filé', quantity_g: 300 }, // mesmo (case/normalize)
          { food_name: 'coca-cola', quantity_g: 250 }, // mesmo
        ],
      },
      ctx,
    )
    const deduped = events.find((e) => e.event === 'tool.items_deduped')
    expect(deduped).toBeDefined()
    expect(deduped?.properties.original_count).toBe(4)
    expect(deduped?.properties.merged_count).toBe(2)
    const dups = deduped?.properties.duplicates as Array<{
      food_name: string
      repeated: number
      result_g: number
      strategy: string
    }>
    expect(dups).toHaveLength(2)
    expect(dups[0]?.repeated).toBe(2)
    expect(dups[0]?.result_g).toBe(300)
    expect(dups[0]?.strategy).toBe('collapsed_identical')
  })

  it('quantidade inválida é rejeitada antes de tocar o banco', () => {
    const schema = registraRefeicao.parameters

    expect(
      schema.safeParse({
        meal_type: 'lanche',
        items: [{ food_name: 'chocolate', quantity_g: 0 }],
      }).success,
    ).toBe(false)
    expect(
      schema.safeParse({
        meal_type: 'lanche',
        items: [{ food_name: 'chocolate', quantity_g: -10 }],
      }).success,
    ).toBe(false)
    expect(
      schema.safeParse({
        meal_type: 'lanche',
        items: [{ food_name: 'chocolate', quantity_g: 10_001 }],
      }).success,
    ).toBe(false)
  })

  // BUG do PAULO 2026-05-24 (4ª camada — re-inserção fantasma contra o dia):
  // Café (whey 114g + leite 70g) registrado 08:44. Às 12:28 Paulo mandou FOTO
  // do almoço; o LLM RE-INSERIU whey+leite em meal_type='cafe' → café contado
  // em dobro. As 3 dedups anteriores não pegam (idempotência só por msg, janela
  // de correção 30min, dedup intra-array). Fix: dedup determinística contra os
  // meal_logs JÁ registrados hoje no mesmo (snapshot, meal_type), por nome+qtd.
  it('item idêntico (nome+qtd) já registrado hoje no MESMO meal_type por msg anterior (>30min) → NÃO reinsere — bug do PAULO', async () => {
    const { ctx, events } = makeContextAndSupabase({
      // dayLogs = registrado no café às 08:44 (fora da janela de 30min, então
      // NÃO entra em recentLogs — só no dataset do dia).
      dayLogs: [
        { food_name: 'whey protein', quantity_g: 114, meal_type: 'cafe' },
        { food_name: 'leite integral', quantity_g: 70, meal_type: 'cafe' },
      ],
      recentLogs: [], // nada nos últimos 30min → sem evidência de correção
      recentUserMessages: ['mandei foto do almoço'],
      llmSentReplace: false,
    })
    await registraRefeicao.execute(
      {
        meal_type: 'cafe',
        replace: false,
        items: [
          { food_name: 'Whey Protein', quantity_g: 114 }, // mesmo (case/normalize) + mesma qtd
          { food_name: 'leite integral', quantity_g: 70 }, // idêntico
        ],
      },
      ctx,
    )
    // Deve ter pulado os itens duplicados (não reinsere)
    const redup = events.find((e) => e.event === 'tool.meal_item_redup_skipped')
    expect(redup).toBeDefined()
    expect(redup?.properties.skipped_count).toBe(2)
    // NÃO deve ter virado replace (não é correção)
    expect(events.find((e) => e.event === 'tool.replace_implicit_detected')).toBeUndefined()
  })

  it('mesmo item em QUANTIDADE diferente → insere normal (não bloqueia) — não-regressão', async () => {
    const { ctx, events } = makeContextAndSupabase({
      dayLogs: [{ food_name: 'whey protein', quantity_g: 114, meal_type: 'cafe' }],
      recentLogs: [],
      // menciona "café" pra fixar meal_type (suprime autocorrect por hora).
      recentUserMessages: ['tomei mais um whey no café agora'],
      llmSentReplace: false,
    })
    await registraRefeicao.execute(
      {
        meal_type: 'cafe',
        replace: false,
        items: [
          { food_name: 'whey protein', quantity_g: 60 }, // MESMO nome, qtd DIFERENTE
        ],
      },
      ctx,
    )
    // Quantidade diferente → não é o mesmo registro → NÃO pula
    expect(events.find((e) => e.event === 'tool.meal_item_redup_skipped')).toBeUndefined()
  })

  it('items SEM duplicação NÃO dispara dedup event', async () => {
    const { ctx, events } = makeContextAndSupabase({
      recentLogs: [],
      recentUserMessages: ['café com 2 ovos e 1 pão'],
      llmSentReplace: false,
    })
    await registraRefeicao.execute(
      {
        meal_type: 'cafe',
        replace: false,
        items: [
          { food_name: 'ovo mexido', quantity_g: 100 },
          { food_name: 'pão francês', quantity_g: 50 },
        ],
      },
      ctx,
    )
    expect(events.find((e) => e.event === 'tool.items_deduped')).toBeUndefined()
  })
})

describe('registra_refeicao — persistência transacional', () => {
  it('envia itens e replace em uma única RPC atômica', async () => {
    const { ctx, rpcCalls } = makeContextAndSupabase({
      recentLogs: [{ food_name: 'frango frito', quantity_g: 120, meal_type: 'almoco' }],
      dayLogs: [{ food_name: 'frango frito', quantity_g: 120, meal_type: 'almoco' }],
      recentUserMessages: ['corrige o almoço, o frango era grelhado'],
      llmSentReplace: true,
    })

    await registraRefeicao.execute(
      {
        meal_type: 'almoco',
        replace: true,
        items: [{ food_name: 'frango grelhado', quantity_g: 120 }],
      },
      ctx,
    )

    const atomicCall = rpcCalls.find((call) => call.fn === 'register_meal_atomic_scoped')
    expect(atomicCall).toBeDefined()
    expect(atomicCall?.params).toMatchObject({
      p_user_id: 'user-test',
      p_meal_type: 'almoco',
      p_replace: true,
      p_replace_log_ids: ['meal-log-1'],
    })
    expect(atomicCall?.params.p_items).toEqual([
      expect.objectContaining({ food_name: 'frango grelhado', quantity_g: 120 }),
    ])
    expect(rpcCalls.some((call) => call.fn === 'snapshot_add_meal')).toBe(false)
  })
})

describe('registra_refeicao — consumed_date (Fix B 2026-05-25: refeição de dia anterior)', () => {
  it('consumed_date de ontem → snapshot e consumed_at no DIA CERTO, não no dia da gravação', async () => {
    const { ctx, rpcCalls, mealInserts } = makeContextAndSupabase({})
    await registraRefeicao.execute(
      {
        meal_type: 'jantar',
        items: [{ food_name: 'arroz branco cozido', quantity_g: 100 }],
        consumed_date: '2026-05-20',
      },
      ctx,
    )
    const add = rpcCalls.find((c) => c.fn === 'register_meal_atomic')
    expect(add?.params.p_date).toBe('2026-05-20')
    // o meal_log gravado deve ter consumed_at caindo no dia 20
    expect(mealInserts.length).toBeGreaterThan(0)
    expect(String(mealInserts[0]?.consumed_at)).toContain('2026-05-20')
  })

  it('sem consumed_date → usa HOJE (não 2026-05-20)', async () => {
    const { ctx, rpcCalls } = makeContextAndSupabase({})
    await registraRefeicao.execute(
      { meal_type: 'jantar', items: [{ food_name: 'arroz branco cozido', quantity_g: 100 }] },
      ctx,
    )
    const add = rpcCalls.find((c) => c.fn === 'register_meal_atomic')
    expect(add?.params.p_date).not.toBe('2026-05-20')
    expect(add?.params.p_date).toMatch(/^\d{4}-\d{2}-\d{2}$/)
  })

  it('usa o horario original do provider para o dia local e consumed_at', async () => {
    const { ctx, rpcCalls, mealInserts } = makeContextAndSupabase({})
    ctx.userTimezone = 'America/New_York'
    const eventTimeCtx = {
      ...ctx,
      referenceTimestamp: new Date('2026-07-10T03:19:45.000Z'),
    }

    await registraRefeicao.execute(
      {
        meal_type: 'ceia',
        items: [{ food_name: 'leite integral', quantity_g: 200 }],
      },
      eventTimeCtx,
    )

    const add = rpcCalls.find((c) => c.fn === 'register_meal_atomic')
    expect(add?.params.p_date).toBe('2026-07-09')
    expect(mealInserts[0]?.consumed_at).toBe('2026-07-10T03:19:45.000Z')
  })

  it('consumed_date inválido (formato errado) → cai pra hoje (ignora)', async () => {
    const { ctx, rpcCalls } = makeContextAndSupabase({})
    await registraRefeicao.execute(
      {
        meal_type: 'jantar',
        items: [{ food_name: 'arroz branco cozido', quantity_g: 100 }],
        consumed_date: 'ontem',
      },
      ctx,
    )
    const add = rpcCalls.find((c) => c.fn === 'register_meal_atomic')
    expect(add?.params.p_date).toMatch(/^\d{4}-\d{2}-\d{2}$/)
    expect(add?.params.p_date).not.toBe('ontem')
  })
})

describe('registra_refeicao — classificacao automatica por horario local', () => {
  it('caso Roberto: registro das 20:13 ET nao permanece como lanche', async () => {
    const { ctx, mealInserts, events } = makeContextAndSupabase({
      recentUserMessages: ['frango com arroz'],
    })
    const eventTimeCtx = {
      ...ctx,
      userTimezone: 'America/New_York',
      referenceTimestamp: new Date('2026-07-10T00:13:00.000Z'),
      currentUserText: 'frango com arroz',
    }

    await registraRefeicao.execute(
      {
        meal_type: 'lanche',
        items: [{ food_name: 'frango assado', quantity_g: 200 }],
      },
      eventTimeCtx,
    )

    expect(mealInserts[0]?.meal_type).toBe('jantar')
    expect(events).toContainEqual(
      expect.objectContaining({
        event: 'tool.meal_type_autocorrected',
        properties: expect.objectContaining({
          claimed: 'lanche',
          decided: 'jantar',
          reason: 'expected_by_routine',
        }),
      }),
    )
  })
})

describe('registra_refeicao — falha fechada em leituras que protegem calorias', () => {
  it('não registra quando a consulta de idempotência falha', async () => {
    const { ctx, rpcCalls } = makeContextAndSupabase({
      providerMessageId: 'provider-message-test',
      mealQueryErrors: { idempotency: 'idempotency unavailable' },
    })

    await expect(
      registraRefeicao.execute(
        {
          meal_type: 'almoco',
          items: [{ food_name: 'frango grelhado', quantity_g: 120 }],
        },
        ctx,
      ),
    ).rejects.toThrow('idempotency unavailable')
    expect(rpcCalls.some((call) => call.fn === 'register_meal_atomic')).toBe(false)
  })

  it('não transforma correção em adição quando a busca de evidência recente falha', async () => {
    const { ctx, rpcCalls } = makeContextAndSupabase({
      recentUserMessages: ['corrige o almoço, o frango era grelhado'],
      llmSentReplace: true,
      mealQueryErrors: { recentCorrection: 'recent correction unavailable' },
    })

    await expect(
      registraRefeicao.execute(
        {
          meal_type: 'almoco',
          replace: true,
          items: [{ food_name: 'frango grelhado', quantity_g: 120 }],
        },
        ctx,
      ),
    ).rejects.toThrow('recent correction unavailable')
    expect(rpcCalls.some((call) => call.fn === 'register_meal_atomic')).toBe(false)
  })

  it('não insere novamente quando a leitura de deduplicação do dia falha', async () => {
    const { ctx, rpcCalls } = makeContextAndSupabase({
      dayLogs: [{ food_name: 'chocolate', quantity_g: 10, meal_type: 'lanche' }],
      mealQueryErrors: { sameDay: 'same-day dedup unavailable' },
    })

    await expect(
      registraRefeicao.execute(
        {
          meal_type: 'lanche',
          replace: false,
          items: [{ food_name: 'chocolate', quantity_g: 10 }],
        },
        ctx,
      ),
    ).rejects.toThrow('same-day dedup unavailable')
    expect(rpcCalls.some((call) => call.fn === 'register_meal_atomic')).toBe(false)
  })
})

describe('registra_refeicao — aprendizado de correções não corrompe o fluxo principal', () => {
  const correctionArgs = {
    meal_type: 'almoco' as const,
    items: [{ food_name: 'frango grelhado', quantity_g: 120 }],
    corrections: [{ de: 'frango frito', para: 'frango grelhado' }],
  }

  it('não cria memória nem evento de sucesso quando a leitura da memória falha', async () => {
    const { ctx, events, foodCorrectionWrites, rpcCalls } = makeContextAndSupabase({
      foodCorrectionErrors: { lookup: 'food correction lookup unavailable' },
      recentLogs: [{ food_name: 'frango frito', quantity_g: 120, meal_type: 'almoco' }],
    })

    await registraRefeicao.execute(correctionArgs, ctx)

    expect(foodCorrectionWrites).toHaveLength(0)
    expect(events.some((entry) => entry.event === 'food_correction.learned')).toBe(false)
    expect(events).toContainEqual(
      expect.objectContaining({
        event: 'food_correction.learning_failed',
        properties: expect.objectContaining({ stage: 'lookup' }),
      }),
    )
    expect(rpcCalls.some((call) => call.fn.startsWith('register_meal_atomic'))).toBe(true)
  })

  it('não emite evento de sucesso quando a gravação da memória falha', async () => {
    const { ctx, events, foodCorrectionWrites, rpcCalls } = makeContextAndSupabase({
      foodCorrectionErrors: { write: 'food correction write unavailable' },
      recentLogs: [{ food_name: 'frango frito', quantity_g: 120, meal_type: 'almoco' }],
    })

    await registraRefeicao.execute(correctionArgs, ctx)

    expect(foodCorrectionWrites).toHaveLength(1)
    expect(events.some((entry) => entry.event === 'food_correction.learned')).toBe(false)
    expect(events).toContainEqual(
      expect.objectContaining({
        event: 'food_correction.learning_failed',
        properties: expect.objectContaining({ stage: 'insert' }),
      }),
    )
    expect(rpcCalls.some((call) => call.fn.startsWith('register_meal_atomic'))).toBe(true)
  })
})
