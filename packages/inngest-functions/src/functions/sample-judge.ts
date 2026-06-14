import { inngest } from '../client.js'
import { createWorkerDeps } from '../lib/env.js'
import { buildJudgePrompt, parseJudgeResult } from '@mpp/agent'

/**
 * Worker: LLM-as-Judge. Amostra ~10% das respostas do agente (24h), pede a um
 * modelo barato uma nota 0-10 + raciocínio, e grava em `llm_evaluations` (tela
 * /evaluations do admin). Detecta regressão de qualidade após mudança de prompt.
 *
 * A tela + tabela existiam desde 2026-05-01 mas o worker NUNCA foi construído
 * (ficava "0 avaliações"). Construído 2026-05-22.
 *
 * Custo: modelo barato (gpt-4o-mini), 10% das msgs, cap 15/run, 2×/dia → centavos.
 * Desligável sem deploy via global_config 'llm_judge.enabled'=false.
 * Taxa via 'llm_judge.sample_rate' (0-1, default 0.1).
 */
const JUDGE_MODEL = process.env.JUDGE_MODEL ?? 'openai/gpt-4o-mini'

export const sampleJudgeFn = inngest.createFunction(
  { id: 'sample-judge', retries: 1, concurrency: { limit: 1 } },
  { cron: 'TZ=America/Sao_Paulo 0 10,22 * * *' },
  async ({ step, logger }) => {
    const { supabase, llm } = createWorkerDeps()

    const cfg = await step.run('load-config', async () => {
      const { data } = await supabase
        .from('global_config')
        .select('key, value')
        .in('key', ['llm_judge.enabled', 'llm_judge.sample_rate'])
      const map = new Map(
        ((data ?? []) as Array<{ key: string; value: unknown }>).map((r) => [r.key, r.value]),
      )
      const enabledRaw = map.get('llm_judge.enabled')
      const rate = Number(map.get('llm_judge.sample_rate'))
      return {
        enabled: enabledRaw === undefined ? true : Boolean(enabledRaw),
        rate: Number.isFinite(rate) && rate > 0 && rate <= 1 ? rate : 0.1,
      }
    })
    if (!cfg.enabled) {
      await supabase.from('product_events').insert({
        event: 'sample_judge.skipped',
        properties: { reason: 'disabled' },
      })
      return { skipped: true, reason: 'disabled' }
    }

    const candidates = await step.run('pick-candidates', async () => {
      const since = new Date(Date.now() - 24 * 3600 * 1000).toISOString()
      const { data: msgs } = await supabase
        .from('messages')
        .select('id, user_id, content, agent_stage, created_at')
        .eq('direction', 'out')
        .eq('content_type', 'text')
        .not('agent_stage', 'is', null)
        .gte('created_at', since)
        .order('created_at', { ascending: false })
        .limit(300)
      const rows = (msgs ?? []) as Array<{
        id: string
        user_id: string
        content: string | null
        agent_stage: string | null
        created_at: string
      }>
      const ids = rows.map((r) => r.id)
      const { data: done } = await supabase
        .from('llm_evaluations')
        .select('message_id')
        .in('message_id', ids.length ? ids : ['00000000-0000-0000-0000-000000000000'])
      const doneSet = new Set(((done ?? []) as Array<{ message_id: string }>).map((d) => d.message_id))
      return rows
        .filter((r) => r.content && r.content.trim().length > 20 && !doneSet.has(r.id))
        .filter(() => Math.random() < cfg.rate)
        .slice(0, 15)
    })

    if (candidates.length === 0) {
      await supabase.from('product_events').insert({
        event: 'sample_judge.skipped',
        properties: { reason: 'no_candidates', sample_rate: cfg.rate },
      })
      return { ok: true, judged: 0 }
    }

    let judged = 0
    for (const c of candidates) {
      const did = await step.run(`judge-${c.id}`, async () => {
        const { data: prev } = await supabase
          .from('messages')
          .select('content')
          .eq('user_id', c.user_id)
          .eq('direction', 'in')
          .lt('created_at', c.created_at)
          .order('created_at', { ascending: false })
          .limit(1)
          .maybeSingle()
        const userInput = (prev as { content: string | null } | null)?.content ?? ''
        const { system, user } = buildJudgePrompt({
          userInput,
          agentResponse: c.content as string,
          stage: c.agent_stage,
        })
        const res = await llm.complete({
          model: JUDGE_MODEL,
          systemPrompt: system,
          messages: [{ role: 'user', content: user }],
          temperature: 0,
          maxTokens: 220,
        })
        const parsed = parseJudgeResult(res.content ?? '')
        if (!parsed) return 0
        await supabase.from('llm_evaluations').insert({
          message_id: c.id,
          user_id: c.user_id,
          agent_name: c.agent_stage,
          user_input: userInput.slice(0, 2000),
          response_obtained: (c.content as string).slice(0, 4000),
          score: parsed.score,
          reasoning: parsed.reasoning,
          model_used: JUDGE_MODEL,
        })
        return 1
      })
      judged += did
    }
    logger.info('sample-judge done', { judged, candidates: candidates.length })
    // Telemetria P1 (audit 2026-06-13): antes só logger.info; query
    // `event LIKE '%judge%'` em product_events retornava vazio mesmo com
    // 104 inserts lifetime em llm_evaluations. Agora gera sinal explícito.
    await supabase.from('product_events').insert({
      event: 'sample_judge.completed',
      properties: {
        judged,
        candidates: candidates.length,
        sample_rate: cfg.rate,
        model: JUDGE_MODEL,
      },
    })
    return { ok: true, judged }
  },
)
