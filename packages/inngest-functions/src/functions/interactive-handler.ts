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
import {
  composePostRegistrationMessage,
  registraRefeicao,
  registraTreino,
  type MealItem,
  type MealTotals,
  type RegistrationEntry,
} from '@mpp/agent'
import { createMessagingProvider, sendHumanized } from '@mpp/providers'
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

      // ── CONFIRM (Fase B) ──
      // Marca status, GRAVA de verdade chamando registra_refeicao com items da
      // proposta (bypassando o LLM — items já foram resolvidos no turno original),
      // e responde com o card determinístico igual à Fase 1.
      if (action === 'confirm') {
        await supabase
          .from('pending_registrations')
          .update({ status: 'confirmed', resolved_at: new Date().toISOString() })
          .eq('id', pendingId)

        const proposal = row.proposal as {
          kind?: 'meal' | 'workout'
          mealType?: string
          items?: MealItem[]
          totals?: MealTotals
          workoutType?: string
          durationMin?: number | null
          kcalEst?: number | null
          raw_args?: Record<string, unknown>
          source_provider_message_id?: string
        }

        // Carrega user pra timezone (pra computar a data local no tool)
        const { data: usr } = await supabase
          .from('users')
          .select('timezone, country')
          .eq('id', userId)
          .maybeSingle()
        const userTimezone =
          (usr as { timezone?: string | null } | null)?.timezone ?? 'America/Sao_Paulo'
        const userCountry = (usr as { country?: string | null } | null)?.country ?? 'BR'

        const toolCtx = {
          supabase,
          userId,
          userWpp: wpp,
          userCountry,
          userTimezone,
          providerMessageId: proposal.source_provider_message_id ?? providerMessageId,
          recentUserMessages: [],
        }

        // Chama a tool de gravar diretamente (bypassando LLM) com os dados
        // resolvidos no pending. Branch por kind: meal usa registraRefeicao;
        // workout usa registraTreino. Resultado vai pro mesmo card determinístico.
        let mealToolResult:
          | { success?: boolean; meal?: { items?: MealItem[]; totals?: MealTotals } }
          | null = null
        let workoutToolResult:
          | { success?: boolean; kcal_burned?: number; deduped?: boolean }
          | null = null

        if (proposal.kind === 'workout') {
          const raw = proposal.raw_args ?? {}
          workoutToolResult = (await registraTreino.execute(
            {
              workout_type: proposal.workoutType ?? (raw.workout_type as string) ?? 'treino',
              duration_min:
                proposal.durationMin ?? (raw.duration_min as number | undefined) ?? undefined,
              intensity: (raw.intensity as string | undefined) ?? undefined,
              estimated_kcal_from_image:
                proposal.kcalEst ??
                (raw.estimated_kcal_from_image as number | undefined) ??
                undefined,
            } as never,
            toolCtx as never,
          )) as { success?: boolean; kcal_burned?: number; deduped?: boolean }
        } else {
          // meal (default)
          if (!proposal.items || proposal.items.length === 0) {
            await messaging
              .sendText(wpp, '✅ Registrado.', { replyTo: providerMessageId })
              .catch(() => {})
            return { handled: true, action: 'confirmed_empty', pendingId }
          }
          mealToolResult = (await registraRefeicao.execute(
            {
              meal_type: proposal.mealType ?? 'outro',
              items: proposal.items.map((it) => ({
                food_name: it.name,
                quantity_g: it.quantity_g,
                display_qty: it.display_qty,
                display_unit: it.display_unit,
                kcal: it.kcal,
                protein_g: it.protein_g,
                carbs_g: it.carbs_g,
                fat_g: it.fat_g,
              })),
              replace: false,
            } as never,
            toolCtx as never,
          )) as { success?: boolean; meal?: { items?: MealItem[]; totals?: MealTotals } }
        }

        // Carrega snapshot + progress frescos pro card canônico (mesma fonte do FIX C)
        const todayStr = new Date(
          new Date().toLocaleString('en-US', { timeZone: userTimezone }),
        )
          .toISOString()
          .slice(0, 10)
        const [{ data: snap }, { data: prog }, { data: prof }] = await Promise.all([
          supabase
            .from('daily_snapshots')
            .select(
              'calories_consumed, calories_target, protein_g, protein_target, exercise_calories',
            )
            .eq('user_id', userId)
            .eq('date', todayStr)
            .maybeSingle(),
          supabase
            .from('user_progress')
            .select('deficit_block')
            .eq('user_id', userId)
            .maybeSingle(),
          supabase
            .from('user_profiles')
            .select('current_protocol')
            .eq('user_id', userId)
            .maybeSingle(),
        ])
        const s = (snap ?? {}) as {
          calories_consumed?: number
          calories_target?: number | null
          protein_g?: number
          protein_target?: number | null
          exercise_calories?: number
        }
        const p = (prog ?? {}) as { deficit_block?: number }
        const proto = (prof as { current_protocol?: string | null } | null)?.current_protocol ?? null

        // Constrói a entry de registro pra alimentar composePostRegistrationMessage
        const registrations: RegistrationEntry[] =
          proposal.kind === 'workout'
            ? [
                {
                  tool: 'registra_treino',
                  workoutType: proposal.workoutType ?? null,
                  durationMin: proposal.durationMin ?? null,
                  kcalBurned: workoutToolResult?.kcal_burned ?? proposal.kcalEst ?? 0,
                  alreadyLogged: workoutToolResult?.deduped === true,
                },
              ]
            : [
                {
                  tool: 'registra_refeicao',
                  mealType: proposal.mealType ?? 'outro',
                  items: mealToolResult?.meal?.items ?? proposal.items ?? [],
                  totals:
                    mealToolResult?.meal?.totals ??
                    proposal.totals ?? { kcal: 0, protein_g: 0, carbs_g: 0, fat_g: 0 },
                },
              ]
        const text = composePostRegistrationMessage({
          registrations,
          card: {
            caloriesConsumed: s.calories_consumed ?? 0,
            caloriesTarget: s.calories_target ?? null,
            proteinG: Number(s.protein_g ?? 0),
            proteinTarget: s.protein_target ?? null,
            exerciseCalories: s.exercise_calories ?? 0,
            deficitBlock: p.deficit_block ?? 0,
            protocol:
              (proto as 'recomposicao' | 'ganho_massa' | 'manutencao' | null) ?? null,
          },
        })

        await sendHumanized(messaging, wpp, text, {
          singleMessage: true,
          minDelay: 0,
          maxDelay: 0,
          showTyping: false,
          inReplyTo: providerMessageId,
        }).catch(() => {})

        // Persiste a msg out
        await supabase.from('messages').insert({
          user_id: userId,
          direction: 'out',
          role: 'assistant',
          content_type: 'text',
          content: text,
          provider: 'whatsapp_cloud',
          agent_stage: 'recomposicao',
          delivery_status: 'sent',
        })

        await supabase.from('product_events').insert({
          user_id: userId,
          event: 'pending.confirmed',
          properties:
            proposal.kind === 'workout'
              ? {
                  pendingId,
                  kind: 'workout',
                  workout_type: proposal.workoutType,
                  duration_min: proposal.durationMin,
                  tool_success: workoutToolResult?.success === true,
                }
              : {
                  pendingId,
                  kind: 'meal',
                  meal_type: proposal.mealType,
                  items_count: proposal.items?.length ?? 0,
                  tool_success: mealToolResult?.success === true,
                },
        })
        return { handled: true, action: 'confirmed', pendingId, kind: proposal.kind ?? 'meal' }
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
