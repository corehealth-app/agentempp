/**
 * WhatsApp lock for the audit of 2026-10-04 (iPhone, staging, Flow chat).
 *
 * The report: in the app's Flow chat the patient wrote
 *   "Treinei musculacao hoje e gastei 322 kcal. Posso comer 322 kcal a mais?"
 * (messages.provider 'mobile_flow', created 2026-10-04T15:03:40.503Z) and Flow
 * answered "Sim! Sua meta já considera esse gasto…". The fix is Flow-only.
 *
 * This file pins the WhatsApp side of the same scenario byte for byte, so the
 * production channel provably did not change. It imports ONLY modules that
 * existed before the fix (pipeline.js, tools.js): it is green on the commit
 * before the fix and must stay green after it.
 *
 * > RC A — canal WhatsApp NÃO coberto nesta PR (pendência da audit 2026-10-04).
 * The tests below are a CHARACTERIZATION of that open item: WhatsApp still
 * hands the model only the net balance (with exercise) under a generic label,
 * and still sends whatever the model answers. Invert them when the channel is
 * fixed (needs Eduardo/Roberto's decision and its own golden).
 */
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import { clearCalcConfigCache } from '../calc-config-loader.js'
import type { PipelineDeps } from '../pipeline.js'
import { processMessage } from '../pipeline.js'
import { resetRouterFlagCacheForTests } from '../router-flag.js'
import { consultaProgresso } from '../tools.js'

// Exact turn of the report, read from staging `messages` (no accents typed).
const NOW = new Date('2026-10-04T15:03:40.503Z')
const PHRASE = 'Treinei musculacao hoje e gastei 322 kcal. Posso comer 322 kcal a mais?'
// Exact reply stored at 2026-10-04T15:03:50.524Z (anthropic/claude-sonnet-4.6).
const REPLY =
  'Sim! Sua meta já considera esse gasto — o balanço de hoje já está com as 322 kcal do treino descontadas.\n\nEntão tecnicamente você tem espaço pra comer um pouco mais, mas não precisa "repor" as 322 kcal separadamente. O sistema já ajustou tudo na meta de 2.980 kcal.'

const USER_ID = 'qa-a'

// Profile of the QA account on staging at that turn. The birth date was not
// part of the readout (same placeholder as the audit of 2026-10-01).
const PROFILE = {
  sex: 'masculino',
  birth_date: '2000-01-01',
  height_cm: 185,
  weight_kg: 80.5,
  body_fat_percent: null,
  activity_level: 'moderado',
  training_frequency: 4,
  water_intake: 'moderado',
  hunger_level: 'moderada',
  current_protocol: 'ganho_massa',
  goal_type: null,
  goal_value: null,
  deficit_level: null,
}

// daily_snapshots row of 2026-10-04 at that turn (staging).
const SNAPSHOT: Record<string, unknown> = {
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

const PROGRESS = {
  current_streak: 0,
  longest_streak: 0,
  xp_total: 0,
  level: 1,
  blocks_completed: 0,
  deficit_block: 0,
  last_active_date: null,
}

interface Read {
  table: string
  columns: string
  filters: Record<string, unknown>
}

interface Harness {
  deps: PipelineDeps
  inserts: Array<{ table: string; row: Record<string, unknown> }>
  llmCalls: Array<{ systemPrompt: unknown; messages: unknown[] }>
}

/**
 * Fake client that honours the filters the pipeline sends. The day row answers
 * only the read of that date, projected to the columns asked; the 14-day
 * window (`day_closed = true`) gets no rows, as on staging (day still open).
 */
function harness(day: Record<string, unknown> | null, replies: string[]): Harness {
  const inserts: Harness['inserts'] = []
  const llmCalls: Harness['llmCalls'] = []

  const rowsFor = (read: Read): unknown => {
    switch (read.table) {
      case 'users':
        return {
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
      case 'user_profiles':
        return PROFILE
      case 'user_progress':
        return PROGRESS
      case 'messages':
        // The inbound row is already stored when the pipeline runs.
        return [
          {
            direction: 'in',
            content: PHRASE,
            content_type: 'text',
            created_at: NOW.toISOString(),
            provider_message_id: 'wamid.audit-10-04',
          },
        ]
      case 'daily_snapshots': {
        if (read.filters.day_closed === true) return []
        if (!day || read.filters.date !== '2026-10-04') return null
        if (read.columns.trim() === '*') return day
        return Object.fromEntries(
          read.columns.split(',').map((key) => [key.trim(), day[key.trim()] ?? null]),
        )
      }
      case 'global_config':
        // Staging override of the protein factors (same as audit 2026-10-01).
        if (read.filters.key === 'router.haiku_enabled') return null
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
          stage: 'ganho_massa',
          model: 'anthropic/claude-sonnet-4.6',
          temperature: 0,
          max_tokens: 512,
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
      const result = () => {
        const data = rowsFor(read)
        return { data, error: null }
      }
      const one = async () => {
        const { data } = result()
        return { data: Array.isArray(data) ? (data[0] ?? null) : data, error: null }
      }
      const chain = Promise.resolve().then(result) as Promise<{ data: unknown; error: null }> &
        Record<string, unknown>
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
        'update',
        'upsert',
        'delete',
      ]) {
        chain[method] = () => chain
      }
      chain.select = (columns?: string) => {
        if (typeof columns === 'string') read.columns = columns
        return chain
      }
      chain.eq = (key: string, value: unknown) => {
        read.filters[key] = value
        return chain
      }
      chain.insert = (row: Record<string, unknown>) => {
        inserts.push({ table, row })
        return chain
      }
      chain.single = one
      chain.maybeSingle = one
      return chain
    },
    rpc: async (name: string) => ({
      data: name === 'match_method_chunks' ? [] : USER_ID,
      error: null,
    }),
  } as unknown as PipelineDeps['supabase']

  let call = 0
  const llm = {
    complete: async (input: { systemPrompt: unknown; messages: unknown[] }) => {
      llmCalls.push({ systemPrompt: input.systemPrompt, messages: [...input.messages] })
      const content = replies[Math.min(call, replies.length - 1)] ?? ''
      call += 1
      return {
        content,
        toolCalls: [],
        model: 'anthropic/claude-sonnet-4.6',
        promptTokens: 11024,
        completionTokens: 95,
        costUsd: 0,
      }
    },
  } as unknown as PipelineDeps['llm']

  return { deps: { supabase, llm, maxToolIterations: 3 }, inserts, llmCalls }
}

function flattenSystemPrompt(value: unknown): string {
  if (typeof value === 'string') return value
  if (!Array.isArray(value)) return ''
  return value
    .map((part) =>
      typeof part === 'object' && part !== null && 'text' in part
        ? String((part as { text: unknown }).text)
        : '',
    )
    .join('')
}

/** The numeric section of the per-turn context, line by line. */
function numericSection(prompt: string): string[] {
  const start = prompt.indexOf('### Dados numéricos REAIS')
  const end = prompt.indexOf('### Regras importantes')
  expect(start).toBeGreaterThan(-1)
  expect(end).toBeGreaterThan(start)
  return prompt.slice(start, end).trimEnd().split('\n')
}

function whatsapp(h: Harness) {
  return processMessage(h.deps, {
    from: '5511999999999',
    providerMessageId: 'wamid.audit-10-04',
    text: PHRASE,
    contentType: 'text',
    provider: 'whatsapp',
    timestamp: NOW,
  })
}

function eventNames(h: Harness): string[] {
  return h.inserts
    .filter((entry) => entry.table === 'product_events')
    .map((entry) => String(entry.row.event))
}

beforeEach(() => {
  vi.useFakeTimers()
  vi.setSystemTime(NOW)
  clearCalcConfigCache()
  resetRouterFlagCacheForTests()
})
afterEach(() => {
  vi.useRealTimers()
  clearCalcConfigCache()
  resetRouterFlagCacheForTests()
})

describe('audit 2026-10-04 — WhatsApp context lock (RC A NÃO coberto neste canal)', () => {
  it('the numeric context of the same scenario is the legacy text, byte for byte', async () => {
    const h = harness(SNAPSHOT, [REPLY])
    await whatsapp(h)

    const prompt = flattenSystemPrompt(h.llmCalls[0]?.systemPrompt)
    expect(numericSection(prompt)).toEqual([
      '### Dados numéricos REAIS do paciente (use estes, NÃO INVENTE)',
      '⚠️ Estes valores são canônicos — calculados pelo sistema. NUNCA recalcule meta/balanço/streak na cabeça nem invente números diferentes destes.',
      '',
      // The legacy channel prints the target computed from the live profile
      // (80.5 kg → 2988 / 144.9), not the one stored in the day row (2980 /
      // 144, which Today and Flow use). Pinned as it is today.
      '- Meta calórica de hoje: **2988 kcal**',
      '- Meta de proteína de hoje: **144.9 g**',
      '- Consumido hoje: 541 kcal | 59.03 g proteína | 47.32g carbo | 10.27g gordura',
      '- Exercício hoje: 322 kcal queimadas',
      '- Balanço calórico de hoje: -2761 kcal (negativo=déficit, positivo=superávit)',
      '- Sequência atual: 0 dias consecutivos (recorde 0) | XP: 0 (nível 1) | Blocos 7700 fechados: 0',
      '- Bloco 7700 em andamento: **0 kcal de 7700** (0%)',
    ])
    // None of the Flow-only labels leaks into the production channel.
    expect(prompt).not.toContain('Para COMIDA')
    expect(prompt).not.toContain('COM exercício')
    expect(prompt).not.toContain('- REGRA: exercício')
  })

  it('with nothing registered today the legacy context keeps its single line', async () => {
    const h = harness(null, [REPLY])
    await whatsapp(h)

    const lines = numericSection(flattenSystemPrompt(h.llmCalls[0]?.systemPrompt))
    expect(lines).toContain('- Consumo hoje: 0 kcal (nada registrado ainda)')
    expect(lines.some((line) => line.startsWith('- Exercício hoje'))).toBe(false)
    expect(lines.some((line) => line.startsWith('- Balanço calórico de hoje'))).toBe(false)
    expect(lines.join('\n')).not.toContain('Para COMIDA')
    expect(lines.join('\n')).not.toContain('- REGRA: exercício')
  })

  it('WhatsApp ainda enviaria o texto errado — RC A não coberto: the model is called and its answer is sent as is', async () => {
    const h = harness(SNAPSHOT, [REPLY])
    const output = await whatsapp(h)

    expect(output.text).toBe(REPLY)
    expect(h.llmCalls).toHaveLength(1)
    expect(h.llmCalls[0]?.messages.at(-1)).toEqual({ role: 'user', content: PHRASE })
    expect(eventNames(h)).not.toContain('pipeline.deterministic_exercise_food')
  })

  it('consulta_progresso on the legacy channel returns the raw day row, daily_balance included', async () => {
    const h = harness(SNAPSHOT, [])
    const output = await consultaProgresso.execute(
      {},
      {
        supabase: h.deps.supabase,
        userId: USER_ID,
        userWpp: '5511999999999',
        llm: {} as never,
        userTimezone: 'America/Sao_Paulo',
        referenceTimestamp: NOW,
        // Even with day targets present, only the server-set Flow identity
        // switches the shape.
        flowDailyTargets: { calories_target: 2980, protein_target: 144 },
      },
    )

    expect(output).toEqual({
      progresso: {
        xp: 0,
        nivel: 1,
        sequencia_dias_consecutivos: 0,
        recorde_sequencia: 0,
        blocos_7700_completos: 0,
        deficit_no_bloco_atual: 0,
        conquistas: [],
      },
      hoje: SNAPSHOT,
    })
    expect(output).not.toHaveProperty('energia_hoje')
  })
})
