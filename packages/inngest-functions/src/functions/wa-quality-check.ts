import { createMessagingProvider } from '@mpp/providers'
import { inngest } from '../client.js'
import { createWorkerDeps } from '../lib/env.js'

/**
 * Worker: chama Meta API pra ler quality_rating + tier do número
 * e atualiza whatsapp_phone_status. Disparado pelo cron a cada 30min.
 *
 * Sem retry agressivo — se Meta tá fora, próxima janela cobre.
 */
export const waQualityCheckFn = inngest.createFunction(
  { id: 'wa-quality-check', retries: 1 },
  { event: 'wa.quality.check' },
  async ({ step, logger }) => {
    return step.run('check-quality', async () => {
      const messaging = createMessagingProvider({
        MESSAGING_PROVIDER: process.env.MESSAGING_PROVIDER ?? 'whatsapp_cloud',
        META_PHONE_NUMBER_ID: process.env.META_PHONE_NUMBER_ID,
        META_ACCESS_TOKEN: process.env.META_ACCESS_TOKEN,
        META_APP_SECRET: process.env.META_APP_SECRET,
        META_VERIFY_TOKEN: process.env.META_VERIFY_TOKEN,
      })

      try {
        const status = await messaging.getQualityStatus()
        const phoneNumberId = process.env.META_PHONE_NUMBER_ID
        if (!phoneNumberId) {
          logger.warn('META_PHONE_NUMBER_ID ausente — skipping')
          return { ok: false, reason: 'no phone_number_id' }
        }

        const { supabase } = createWorkerDeps()
        const { error } = await supabase.from('whatsapp_phone_status').upsert(
          {
            phone_number_id: phoneNumberId,
            quality_rating: status.rating,
            messaging_limit_tier: status.tier,
            last_checked_at: new Date().toISOString(),
          },
          { onConflict: 'phone_number_id' },
        )
        if (error) {
          logger.error('Falha ao salvar phone status', { error: error.message })
          return { ok: false, reason: error.message }
        }

        // Alerta se mudou pra YELLOW/RED
        if (status.rating === 'YELLOW' || status.rating === 'RED') {
          await supabase.from('product_events').insert({
            event: 'wa.quality.degraded',
            properties: {
              rating: status.rating,
              tier: status.tier,
              phone_number_id: phoneNumberId,
            },
          })
        }

        return { ok: true, rating: status.rating, tier: status.tier }
      } catch (e) {
        logger.error('Quality check falhou', {
          error: e instanceof Error ? e.message : String(e),
        })
        return { ok: false, reason: e instanceof Error ? e.message : String(e) }
      }
    })
  },
)
