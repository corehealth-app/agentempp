import { inngest } from '../client.js'
import { createWorkerDeps } from '../lib/env.js'

/**
 * Worker: monitora saldo OpenRouter, alerta via Telegram se baixo.
 *
 * Disparado 1×/dia (cron 11h UTC = 8h BRT). Caso 2026-05-16: saldo zerou
 * silenciosamente no meio do dia, Amanda+Paulo+Luciana sentiram com 6 erros
 * 402 "Insufficient credits", Roberto descobriu por encaminhar print. Sem
 * monitoramento, problema só aparece com pacientes sentindo.
 *
 * Threshold default: $20 (editável via global_config 'openrouter.alert_threshold_usd').
 * Notifica via @MargotPiper_Bot no chat admin (mesmo bot do Modo A).
 *
 * Loga product_event 'openrouter.balance_checked' SEMPRE (mesmo OK) pra ter
 * histórico de queima ao longo do tempo (gráfico de uso/dia).
 */
export const openrouterBalanceCheckFn = inngest.createFunction(
  { id: 'openrouter-balance-check', retries: 1, concurrency: { limit: 1 } },
  { event: 'openrouter.balance.tick' },
  async ({ step, logger }) => {
    const apiKey = process.env.OPENROUTER_API_KEY
    if (!apiKey) {
      logger.warn('OPENROUTER_API_KEY ausente — pulando balance-check')
      return { skipped: true, reason: 'no_api_key' }
    }

    // Threshold configurável via global_config
    const threshold = await step.run('load-threshold', async () => {
      const { supabase } = createWorkerDeps()
      const { data } = await supabase
        .from('global_config')
        .select('value')
        .eq('key', 'openrouter.alert_threshold_usd')
        .maybeSingle()
      const raw = (data as { value: unknown } | null)?.value
      const n = Number(raw)
      return Number.isFinite(n) && n > 0 ? n : 20
    })

    // Consulta saldo via OpenRouter API
    const balance = await step.run('fetch-balance', async () => {
      const res = await fetch('https://openrouter.ai/api/v1/key', {
        headers: { Authorization: `Bearer ${apiKey}` },
      })
      if (!res.ok) {
        throw new Error(`OpenRouter /key returned ${res.status}: ${await res.text().catch(() => '')}`)
      }
      const body = (await res.json()) as {
        data?: { limit?: number | null; usage?: number; limit_remaining?: number | null }
      }
      return {
        limit_remaining: body.data?.limit_remaining ?? null,
        usage: body.data?.usage ?? null,
        limit: body.data?.limit ?? null,
      }
    })

    // Sempre loga histórico
    await step.run('log-event', async () => {
      const { supabase } = createWorkerDeps()
      await supabase.from('product_events').insert({
        event: 'openrouter.balance_checked',
        properties: {
          limit_remaining_usd: balance.limit_remaining,
          usage_usd: balance.usage,
          limit_usd: balance.limit,
          threshold_usd: threshold,
        },
      })
    })

    const remaining = balance.limit_remaining
    const alertNeeded = remaining != null && remaining < threshold
    if (!alertNeeded) {
      return {
        ok: true,
        alerted: false,
        limit_remaining: remaining,
        threshold,
      }
    }

    // Alerta Telegram via Bot API direto (mais simples que chamar edge function)
    const botToken = process.env.TELEGRAM_BOT_TOKEN
    const adminChatId = process.env.TELEGRAM_ADMIN_CHAT_ID
    if (!botToken || !adminChatId) {
      logger.warn('Telegram credentials ausentes — saldo baixo mas sem alerta', {
        remaining,
        threshold,
      })
      return { ok: true, alerted: false, reason: 'no_telegram_creds', limit_remaining: remaining }
    }

    await step.run('send-telegram-alert', async () => {
      const msg =
        `⚠️ *Saldo OpenRouter BAIXO*\n\n` +
        `Restam: *$${remaining?.toFixed(2)} USD*\n` +
        `Threshold: $${threshold}\n` +
        `Usado total: ${balance.usage != null ? `$${balance.usage.toFixed(2)}` : 'n/d'}\n\n` +
        `Recarregue em: https://openrouter.ai/settings/credits\n` +
        `Sem ação, pipeline LLM vai começar a retornar 402 e pacientes recebem ` +
        `"Tive um problema agora" (Amanda/Paulo/Luciana sentiram em 2026-05-16).`
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
        throw new Error(
          `Telegram sendMessage failed ${res.status}: ${await res.text().catch(() => '')}`,
        )
      }
    })

    return {
      ok: true,
      alerted: true,
      limit_remaining: remaining,
      threshold,
    }
  },
)
