import { describe, expect, it } from 'vitest'
import { alsoTriggersLegacyReminder, isLegacyWhatsAppCron } from './legacy-jobs'

describe('agendamentos do canal de WhatsApp encerrado', () => {
  it('rotula os jobs que só existem para o WhatsApp', () => {
    for (const job of [
      'engagement-morning',
      'engagement-late-morning',
      'engagement-afternoon',
      'engagement-evening',
      'engagement-night',
      'wa-quality-check',
      'buffer-flush',
    ]) {
      expect(isLegacyWhatsAppCron(job), job).toBe(true)
    }
  })

  it('não rotula o que o app usa', () => {
    for (const job of [
      'daily-closer-0030',
      'daily-closer-2330',
      'refresh-mv-kpis-daily',
      'attention-cleanup',
      'pipeline-health-tick',
      'cleanup-processed-messages',
    ]) {
      expect(isLegacyWhatsAppCron(job), job).toBe(false)
    }
  })

  it('avisa que o fechamento do dia também aciona o lembrete legado', () => {
    expect(alsoTriggersLegacyReminder('daily-closer-2130')).toBe(true)
    expect(alsoTriggersLegacyReminder('refresh-mv-kpis-daily')).toBe(false)
    expect(alsoTriggersLegacyReminder('engagement-night')).toBe(false)
  })
})
