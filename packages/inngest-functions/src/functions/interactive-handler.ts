/**
 * Handler do TAP em botão WhatsApp interativo (Roberto 2026-05-28 — Fase A
 * dos botões + modo express, opção #4).
 *
 * Disparado pelo webhook quando o paciente toca em [Sim, registrar] ou
 * [Editar] de uma mensagem `interactive` que o agente mandou. O webhook NÃO
 * passa pelo buffer — tap é ação discreta, handler imediato.
 *
 * Fase A (esta): plumbing apenas — marca o status do pending e responde com
 * ack/pedido-de-correção. A GRAVAÇÃO REAL (chamar registra_refeicao/treino
 * pra mover do pending pro banco) entra na Fase B, quando o pipeline passa a
 * criar pendings em vez de chamar a tool direto.
 *
 * Convenção do button_id:
 *   "confirm_<pending_uuid>"  → confirma → marca status='confirmed'
 *   "edit_<pending_uuid>"     → edita    → marca status='edited'
 *
 * Idempotência: 2º tap no mesmo botão (paciente impaciente clicando 2x) vira
 * no-op (pending já está em estado terminal). Pending expirado / não-existente
 * → mensagem informativa.
 */
import { createMessagingProvider } from '@mpp/providers'
import { inngest } from '../client.js'
import { createWorkerDeps } from '../lib/env.js'

const BUTTON_ID_PATTERN = /^(confirm|edit)_([0-9a-f-]{36})$/

interface PendingRow {
  id: string
  user_id: string
  status: 'pending' | 'confirmed' | 'edited' | 'expired' | 'cancelled'
  expires_at: string
  proposal: Record<string, unknown>
}

export const interactiveButtonHandlerFn = inngest.createFunction(
  {
    id: 'interactive-button-handler',
    retries: 2,
    // Concorrência 1 por usuário evita race em taps rápidos no mesmo pending.
    concurrency: { key: 'event.data.userId', limit: 1 },
  },
  { event: 'interactive.button.tapped' },
  async ({ event, step, logger }) => {
    const data = event.data as {
      userId: string
      wpp: string
      buttonId: string
      buttonTitle?: string
      providerMessageId?: string
    }
    const { userId, wpp, buttonId, providerMessageId } = data
    if (!userId || !buttonId || !wpp) {
      return { handled: false, reason: 'payload incompleto' }
    }

    const messaging = createMessagingProvider({
      MESSAGING_PROVIDER: process.env.MESSAGING_PROVIDER ?? 'whatsapp_cloud',
      META_PHONE_NUMBER_ID: process.env.META_PHONE_NUMBER_ID,
      META_ACCESS_TOKEN: process.env.META_ACCESS_TOKEN,
      META_APP_SECRET: process.env.META_APP_SECRET,
      META_VERIFY_TOKEN: process.env.META_VERIFY_TOKEN,
    })

    return await step.run('handle-tap', async () => {
      const { supabase } = createWorkerDeps()

      const match = buttonId.match(BUTTON_ID_PATTERN)
      if (!match) {
        await supabase.from('product_events').insert({
          user_id: userId,
          event: 'interactive.button_id_unknown',
          properties: { buttonId, providerMessageId },
        })
        logger.warn('button_id desconhecido', { userId, buttonId })
        return { handled: false, reason: 'button_id_pattern_no_match', buttonId }
      }
      const action = match[1] as 'confirm' | 'edit'
      const pendingId = match[2]!

      const { data: pending } = await supabase
        .from('pending_registrations')
        .select('id, user_id, status, expires_at, proposal')
        .eq('id', pendingId)
        .maybeSingle()
      const row = pending as PendingRow | null

      // Pending não existe → talvez tap em msg antiga / dado limpo
      if (!row) {
        await messaging
          .sendText(wpp, 'Esse registro não foi encontrado. Me manda de novo?', {
            replyTo: providerMessageId,
          })
          .catch(() => {})
        await supabase.from('product_events').insert({
          user_id: userId,
          event: 'pending.not_found',
          properties: { pendingId, action, buttonId },
        })
        return { handled: false, reason: 'pending_not_found', pendingId }
      }

      // Segurança: o pending tem que ser do mesmo user que tocou
      if (row.user_id !== userId) {
        logger.error('pending de outro user!', { pendingId, expected: userId, actual: row.user_id })
        return { handled: false, reason: 'user_mismatch' }
      }

      // Pending já resolvido (tap duplo, ou já processado) → no-op idempotente
      if (row.status !== 'pending') {
        await supabase.from('product_events').insert({
          user_id: userId,
          event: 'pending.duplicate_tap',
          properties: { pendingId, action, currentStatus: row.status },
        })
        return { handled: true, action: 'noop', reason: `status=${row.status}` }
      }

      // Expirado → marca expired + avisa
      if (new Date(row.expires_at).getTime() <= Date.now()) {
        await supabase
          .from('pending_registrations')
          .update({ status: 'expired', resolved_at: new Date().toISOString() })
          .eq('id', pendingId)
        await messaging
          .sendText(
            wpp,
            'Esse registro expirou (demorou mais de 30min). Me manda de novo o que comeu?',
            { replyTo: providerMessageId },
          )
          .catch(() => {})
        await supabase.from('product_events').insert({
          user_id: userId,
          event: 'pending.expired_on_tap',
          properties: { pendingId, action },
        })
        return { handled: true, action: 'expired' }
      }

      // ── CONFIRM ──
      // Fase A: marca status, manda ack simples. A gravação real (chamar
      // registra_refeicao/treino com base em row.proposal) entra na Fase B.
      if (action === 'confirm') {
        await supabase
          .from('pending_registrations')
          .update({ status: 'confirmed', resolved_at: new Date().toISOString() })
          .eq('id', pendingId)
        await supabase.from('product_events').insert({
          user_id: userId,
          event: 'pending.confirmed',
          properties: { pendingId, kind: (row.proposal as { kind?: string }).kind ?? 'unknown' },
        })
        // ack mínimo na Fase A; Fase B substitui pela renderização do card oficial
        await messaging.sendText(wpp, '✅ Registrado.', { replyTo: providerMessageId }).catch(() => {})
        return { handled: true, action: 'confirmed', pendingId }
      }

      // ── EDIT ──
      // Marca status, pede correção. Próxima msg do paciente cai no fluxo normal
      // do LLM (que vai re-analisar e propor de novo, criando novo pending).
      await supabase
        .from('pending_registrations')
        .update({ status: 'edited', resolved_at: new Date().toISOString() })
        .eq('id', pendingId)
      await supabase.from('product_events').insert({
        user_id: userId,
        event: 'pending.edited',
        properties: { pendingId, kind: (row.proposal as { kind?: string }).kind ?? 'unknown' },
      })
      await messaging
        .sendText(wpp, 'Beleza, me corrige aí o que tá errado.', {
          replyTo: providerMessageId,
        })
        .catch(() => {})
      return { handled: true, action: 'edited', pendingId }
    })
  },
)
