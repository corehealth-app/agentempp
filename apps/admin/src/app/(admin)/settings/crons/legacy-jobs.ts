/**
 * Quais agendamentos do pg_cron só existem para o canal de WhatsApp, encerrado.
 *
 * - engagement-* → evento engagement.tick → engagement-sender, que ENVIA
 *   mensagem por WhatsApp;
 * - wa-quality-check → qualidade do número na Meta;
 * - buffer-flush → debounce das mensagens recebidas (já desagendado por
 *   migration; entra aqui caso ainda exista em algum banco).
 *
 * A tela rotula esses jobs e não oferece "Rodar agora" nem "Ativar" para
 * eles. Nada é desligado no banco por isso: é só a interface.
 */
export const LEGACY_CRON_LABEL = 'legado (WhatsApp encerrado)'

export function isLegacyWhatsAppCron(jobname: string): boolean {
  return (
    jobname.startsWith('engagement-') ||
    jobname === 'wa-quality-check' ||
    jobname === 'buffer-flush'
  )
}

/**
 * O fechamento do dia é do app, mas o evento que ele dispara (day.close.tick)
 * também aciona o lembrete legado de dia sem registro (daily-gap-checker), que
 * envia WhatsApp onde o canal antigo ainda estiver ligado. "Rodar agora"
 * continua disponível, com esse aviso na confirmação.
 */
export function alsoTriggersLegacyReminder(jobname: string): boolean {
  return jobname.startsWith('daily-closer')
}
