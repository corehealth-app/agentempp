import { inngest } from '../client.js'
import { createWorkerDeps } from '../lib/env.js'

/**
 * Regression beacon (ACT-5 prevention plan 2026-06-16).
 *
 * Roda a cada 1h. Compara métricas críticas da última 1h com a baseline
 * (média/hora dos últimos 7 dias). Se alguma cair > THRESHOLD_DROP (default
 * 50%), manda alerta no Telegram.
 *
 * Objetivo: pegar regressão silenciosa (tipo o selector dead que ficou
 * 36h invisível em 06-13) em 1h em vez de 36h.
 *
 * Métricas monitoradas:
 *  - `curated_phrase.selected` (curated_hit do edu-comment + engagement)
 *  - `vision.analyzed` (todas as fotos)
 *  - `meal_logs INSERT` (pipeline saudável → meal_logs cresce)
 *  - `llm.fake_write_detected` (regressão de PROMPT → sobe MUITO)
 *  - `*.failed` events (catch silencioso instrumentado → sobe se algo
 *     quebrou)
 *
 * GUARD: se a hora atual tem TRÁFEGO baixo (menos de 3 msgs IN total
 * do tracker `users.last_active_date`), pula o alerta — não alertar
 * em madrugada/silêncio natural.
 *
 * Threshold configurável via global_config 'regression_beacon.threshold_pct'
 * (default 50). Pode ser desligado via 'regression_beacon.enabled'=false.
 */
const DEFAULT_THRESHOLD_PCT = 50
const HOURS_BASELINE = 7 * 24 // 7 dias

// CALIBRAÇÃO (audit 06-18): beacon disparou 4× false-positive sobre
// llm.fake_write_detected com %change irreal (+479% = 1→6). Quando baseline
// é pequena, divide-por-pequeno gera ruído. Adicionados 2 guards:
//   - MIN_BASELINE_COUNT_PER_HOUR: baseline (avg/h) precisa ser >= isso pra
//     o cálculo de %change valer. Senão skip+log "unstable_baseline".
//   - MIN_DIFF_ABSOLUTE: além do %, o delta absoluto precisa ser >= isso.
//     1→6 dá +500% mas é diferença pequena em absoluto — não vale alarme.
const MIN_BASELINE_COUNT_PER_HOUR = 0.5 // baseline precisa ter >= 12 eventos em 7d
const MIN_DIFF_ABSOLUTE = 3 // delta count1h vs baseline precisa ser >= 3

interface MetricSpec {
  /** Nome amigável pra alerta. */
  name: string
  /** Função que retorna count last 1h. */
  query1h: (supabase: SupabaseLike) => Promise<number>
  /** Função que retorna AVG/h dos últimos 7 dias. */
  queryBaseline: (supabase: SupabaseLike) => Promise<number>
  /** Direção do alerta: 'down' = alerta se cair, 'up' = alerta se subir. */
  direction: 'down' | 'up'
  /** Query SQL sugerida pra investigar (vai no Telegram). */
  investigation_hint: string
}

// biome-ignore lint/suspicious/noExplicitAny: supabase ServiceClient
type SupabaseLike = any

async function countEvents(
  supabase: SupabaseLike,
  eventName: string,
  sinceIso: string,
): Promise<number> {
  const { count } = await supabase
    .from('product_events')
    .select('id', { count: 'exact', head: true })
    .eq('event', eventName)
    .gte('occurred_at', sinceIso)
  return count ?? 0
}

async function countMealLogs(supabase: SupabaseLike, sinceIso: string): Promise<number> {
  const { count } = await supabase
    .from('meal_logs')
    .select('id', { count: 'exact', head: true })
    .gte('created_at', sinceIso)
  return count ?? 0
}

async function countFailedEvents(supabase: SupabaseLike, sinceIso: string): Promise<number> {
  // Busca todos eventos do tipo *.failed nos últimos 1h
  const { data } = await supabase
    .from('product_events')
    .select('event')
    .like('event', '%.failed')
    .gte('occurred_at', sinceIso)
  return (data ?? []).length
}

/** baseline = média/h dos últimos 7 dias. */
async function baselineAvgHourly(
  supabase: SupabaseLike,
  countFn: (supabase: SupabaseLike, sinceIso: string) => Promise<number>,
): Promise<number> {
  const sinceIso = new Date(Date.now() - HOURS_BASELINE * 60 * 60 * 1000).toISOString()
  const total = await countFn(supabase, sinceIso)
  return total / HOURS_BASELINE
}

const METRICS: MetricSpec[] = [
  {
    name: 'curated_phrase.selected',
    query1h: (s) => {
      const since = new Date(Date.now() - 60 * 60 * 1000).toISOString()
      return countEvents(s, 'edu_comment.curated_hit', since)
    },
    queryBaseline: (s) =>
      baselineAvgHourly(s, (sb, since) => countEvents(sb, 'edu_comment.curated_hit', since)),
    direction: 'down',
    investigation_hint: `SELECT * FROM product_events WHERE event LIKE 'edu_comment%' AND occurred_at >= now() - interval '2h' ORDER BY occurred_at DESC LIMIT 30;`,
  },
  {
    name: 'vision.analyzed',
    query1h: (s) => {
      const since = new Date(Date.now() - 60 * 60 * 1000).toISOString()
      return countEvents(s, 'vision.analyzed', since)
    },
    queryBaseline: (s) =>
      baselineAvgHourly(s, (sb, since) => countEvents(sb, 'vision.analyzed', since)),
    direction: 'down',
    investigation_hint: `SELECT * FROM product_events WHERE event LIKE 'vision%' AND occurred_at >= now() - interval '2h' ORDER BY occurred_at DESC LIMIT 30;`,
  },
  {
    name: 'meal_logs.inserted',
    query1h: (s) => {
      const since = new Date(Date.now() - 60 * 60 * 1000).toISOString()
      return countMealLogs(s, since)
    },
    queryBaseline: (s) => baselineAvgHourly(s, countMealLogs),
    direction: 'down',
    investigation_hint: `SELECT user_id, food_name, meal_type, created_at FROM meal_logs WHERE created_at >= now() - interval '2h' ORDER BY created_at DESC LIMIT 30;`,
  },
  {
    name: 'llm.fake_write_detected',
    query1h: (s) => {
      const since = new Date(Date.now() - 60 * 60 * 1000).toISOString()
      return countEvents(s, 'llm.fake_write_detected', since)
    },
    queryBaseline: (s) =>
      baselineAvgHourly(s, (sb, since) => countEvents(sb, 'llm.fake_write_detected', since)),
    direction: 'up',
    investigation_hint: `SELECT user_id, properties, occurred_at FROM product_events WHERE event = 'llm.fake_write_detected' AND occurred_at >= now() - interval '2h' ORDER BY occurred_at DESC LIMIT 20;`,
  },
  {
    name: 'subsystem.failed',
    query1h: (s) => {
      const since = new Date(Date.now() - 60 * 60 * 1000).toISOString()
      return countFailedEvents(s, since)
    },
    queryBaseline: (s) => baselineAvgHourly(s, countFailedEvents),
    direction: 'up',
    investigation_hint: `SELECT event, count(*), max(occurred_at) FROM product_events WHERE event LIKE '%.failed' AND occurred_at >= now() - interval '2h' GROUP BY 1 ORDER BY 2 DESC;`,
  },
]

interface MetricCheck {
  name: string
  count1h: number
  baselineAvg: number
  direction: 'down' | 'up'
  pctChange: number
  alerted: boolean
  investigation_hint: string
}

export const regressionBeaconFn = inngest.createFunction(
  { id: 'regression-beacon', retries: 1, concurrency: { limit: 1 } },
  { cron: '0 * * * *' }, // a cada 1h em UTC
  async ({ step, logger }) => {
    const { supabase } = createWorkerDeps()

    // Config: enabled + threshold
    const cfg = await step.run('load-config', async () => {
      const { data } = await supabase
        .from('global_config')
        .select('key, value')
        .in('key', ['regression_beacon.enabled', 'regression_beacon.threshold_pct'])
      const map = new Map(
        ((data ?? []) as Array<{ key: string; value: unknown }>).map((r) => [r.key, r.value]),
      )
      const enabledRaw = map.get('regression_beacon.enabled')
      const threshRaw = Number(map.get('regression_beacon.threshold_pct'))
      return {
        enabled: enabledRaw === undefined ? true : Boolean(enabledRaw),
        threshold:
          Number.isFinite(threshRaw) && threshRaw > 0 && threshRaw < 100
            ? threshRaw
            : DEFAULT_THRESHOLD_PCT,
      }
    })
    if (!cfg.enabled) {
      return { skipped: true, reason: 'disabled' }
    }

    // GUARD: silêncio natural (madrugada). Se zero msgs in nas últimas 1h,
    // não alerta — métricas vão estar todas em 0 mas é esperado.
    const since1hIso = new Date(Date.now() - 60 * 60 * 1000).toISOString()
    const { count: inboundCount } = await supabase
      .from('messages')
      .select('id', { count: 'exact', head: true })
      .eq('direction', 'in')
      .gte('created_at', since1hIso)
    if ((inboundCount ?? 0) < 3) {
      await supabase.from('product_events').insert({
        event: 'regression_beacon.skipped_low_traffic',
        properties: { inbound_1h: inboundCount ?? 0 },
      })
      return { skipped: true, reason: 'low_traffic', inbound_1h: inboundCount ?? 0 }
    }

    // Calcula métricas
    const checks: MetricCheck[] = []
    for (const m of METRICS) {
      const [count1h, baselineAvg] = await Promise.all([
        m.query1h(supabase),
        m.queryBaseline(supabase),
      ])
      // Quando baseline é 0 (métrica nova / nunca vista), não tem como comparar.
      if (baselineAvg < 0.1) {
        checks.push({
          name: m.name,
          count1h,
          baselineAvg,
          direction: m.direction,
          pctChange: 0,
          alerted: false,
          investigation_hint: m.investigation_hint,
        })
        continue
      }
      const pctChange = ((count1h - baselineAvg) / baselineAvg) * 100
      // Calibração (audit 06-18): pra evitar false positive sobre baseline
      // pequena (1→6 = +500% mas 5 eventos absolutos não merecem alarme),
      // exige (a) baseline avg/h >= MIN_BASELINE_COUNT_PER_HOUR E (b) delta
      // absoluto >= MIN_DIFF_ABSOLUTE. Falha em qualquer = no alert.
      const absoluteDiff = Math.abs(count1h - baselineAvg)
      const stableBaseline = baselineAvg >= MIN_BASELINE_COUNT_PER_HOUR
      const significantDiff = absoluteDiff >= MIN_DIFF_ABSOLUTE
      const dropAlert =
        m.direction === 'down' &&
        pctChange < -cfg.threshold &&
        stableBaseline &&
        significantDiff
      const riseAlert =
        m.direction === 'up' &&
        pctChange > cfg.threshold &&
        stableBaseline &&
        significantDiff
      checks.push({
        name: m.name,
        count1h,
        baselineAvg,
        direction: m.direction,
        pctChange,
        alerted: dropAlert || riseAlert,
        investigation_hint: m.investigation_hint,
      })
    }

    const alerted = checks.filter((c) => c.alerted)

    // Log SEMPRE o tick — histórico de saúde do sistema
    await supabase.from('product_events').insert({
      event: 'regression_beacon.tick',
      properties: {
        threshold_pct: cfg.threshold,
        inbound_1h: inboundCount ?? 0,
        metrics: checks.map((c) => ({
          name: c.name,
          count1h: c.count1h,
          baseline_avg: +c.baselineAvg.toFixed(2),
          pct_change: +c.pctChange.toFixed(1),
          alerted: c.alerted,
        })),
      },
    })

    if (alerted.length === 0) {
      return { ok: true, alerted: 0, checks: checks.length }
    }

    // Alerta Telegram
    const botToken = process.env.TELEGRAM_BOT_TOKEN
    const adminChatId = process.env.TELEGRAM_ADMIN_CHAT_ID
    if (!botToken || !adminChatId) {
      logger.warn('Telegram credentials ausentes — regressão detectada mas sem alerta', {
        alerted: alerted.map((a) => a.name),
      })
      return { ok: true, alerted: alerted.length, no_telegram: true }
    }

    await step.run('send-telegram-alert', async () => {
      const lines = [
        `⚠️ *Regression beacon* — métricas anômalas na última 1h`,
        '',
        ...alerted.map(
          (a) =>
            `*${a.name}* (${a.direction === 'down' ? '↓' : '↑'} ${a.pctChange.toFixed(0)}%)\n` +
            `  - 1h: ${a.count1h}\n` +
            `  - baseline avg/h: ${a.baselineAvg.toFixed(1)}\n` +
            `  - investigar: \`${a.investigation_hint}\``,
        ),
        '',
        `Threshold: ±${cfg.threshold}%. Desligar via global_config 'regression_beacon.enabled'=false.`,
      ]
      const msg = lines.join('\n')
      const res = await fetch(`https://api.telegram.org/bot${botToken}/sendMessage`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          chat_id: adminChatId,
          text: msg,
          parse_mode: 'Markdown',
          disable_web_page_preview: true,
        }),
      })
      if (!res.ok) {
        logger.warn(`regression-beacon telegram failed: ${res.status}`)
      }
    })

    await supabase.from('product_events').insert({
      event: 'regression_beacon.alert',
      properties: {
        threshold_pct: cfg.threshold,
        alerted_metrics: alerted.map((a) => ({
          name: a.name,
          direction: a.direction,
          pct_change: +a.pctChange.toFixed(1),
        })),
      },
    })

    return { ok: true, alerted: alerted.length, names: alerted.map((a) => a.name) }
  },
)
