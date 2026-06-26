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
  adaptToolItemsToEduInput,
  cadastraDadosIniciais,
  composePostRegistrationMessage,
  embedEduComment,
  generateEducationalComment,
  getLocalDateString,
  getTzOffset,
  parseOnboardingButtonId,
  registraRefeicao,
  registraTreino,
  splitRegistrationParts,
  type EduCommentInput,
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

      // Roberto 2026-06-01: botão de onboarding (`btn_<field>_<value>`)
      // dispara cadastra_dados_iniciais direto. Padrão diferente do
      // confirm/edit (que envolvem pending_registrations).
      const onbBtn = parseOnboardingButtonId(buttonId)
      if (onbBtn) {
        try {
          await cadastraDadosIniciais.execute(
            { [onbBtn.field]: onbBtn.value } as never,
            { supabase, userId, userWpp: wpp, userCountry: 'BR', userTimezone: 'America/Sao_Paulo', providerMessageId, recentUserMessages: [] } as never,
          )
        } catch (err) {
          const msg = err instanceof Error ? err.message : String(err)
          await supabase.from('product_events').insert({
            user_id: userId,
            event: 'interactive.onboarding_tap_failed',
            properties: { buttonId, field: onbBtn.field, value: onbBtn.value, error: msg },
          })
          logger.error('onboarding cadastra falhou', { userId, buttonId, error: msg })
          throw err
        }
        await supabase.from('product_events').insert({
          user_id: userId,
          event: 'interactive.onboarding_tap',
          properties: { buttonId, field: onbBtn.field, value: onbBtn.value },
        })
        // Dispara nova mensagem in pra próxima iteração do LLM continuar onboarding
        // com o dado já gravado. Texto descritivo pro LLM saber o que aconteceu.
        await inngest.send({
          name: 'message.received',
          data: {
            userId,
            wpp,
            text: `[Paciente respondeu via botão: ${onbBtn.field}=${onbBtn.value}]`,
            timestamp: new Date().toISOString(),
            providerMessageId: providerMessageId ?? `onb_tap_${Date.now()}`,
            provider: 'whatsapp_cloud',
            contentType: 'text',
          },
        })
        return { handled: true, action: 'onboarding_tap', field: onbBtn.field, value: onbBtn.value }
      }

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
            'Esse registro expirou (demorou mais de 1 dia). Me manda de novo o que comeu?',
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
          /** Roberto 2026-06-01: pending de correção. Quando true, o execute
           * precisa receber replace=true pra SUBSTITUIR a refeição do dia em
           * vez de inserir nova. Salvo no pipeline quando args.replace=true. */
          replace?: boolean
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
          // Bug I2 (Luciana 2026-06-14 15:44 BRT, pending bfdad07b): tap em
          // pending antigo gravava meal_type ERRADO. proposal.mealType='cafe'
          // (salvo às 13h) virava 'lanche' no DB (autocorrect por localHour=15),
          // enquanto o card mostrava "Café registrado". Quando há mealType
          // explícito no proposal — paciente VIU e CLICOU pra confirmar —
          // ele é canônico: desliga autocorrect na tool. workout não usa.
          trustMealType:
            proposal.kind !== 'workout' && typeof proposal.mealType === 'string',
        }

        // Chama a tool de gravar diretamente (bypassando LLM) com os dados
        // resolvidos no pending. Branch por kind: meal usa registraRefeicao;
        // workout usa registraTreino. Resultado vai pro mesmo card determinístico.
        let mealToolResult:
          | {
              success?: boolean
              already_logged?: boolean
              meal?: { items?: MealItem[]; totals?: MealTotals }
            }
          | null = null
        let workoutToolResult:
          | { success?: boolean; kcal_burned?: number; deduped?: boolean }
          | null = null

        if (proposal.kind === 'workout') {
          const raw = proposal.raw_args ?? {}
          try {
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
          } catch (err) {
            const msg = err instanceof Error ? err.message : String(err)
            await supabase.from('product_events').insert({
              user_id: userId,
              event: 'interactive.handler.tool_failed',
              properties: {
                pendingId,
                kind: 'workout',
                workout_type: proposal.workoutType,
                provider_message_id: toolCtx.providerMessageId,
                error: msg,
              },
            })
            await supabase
              .from('pending_registrations')
              .update({ status: 'pending', resolved_at: null })
              .eq('id', pendingId)
              .eq('status', 'confirmed')
            logger.error('registraTreino.execute throw no tap', { pendingId, userId, error: msg })
            throw err
          }
        } else {
          // meal (default)
          if (!proposal.items || proposal.items.length === 0) {
            await messaging
              .sendText(wpp, '✅ Registrado.', { replyTo: providerMessageId })
              .catch(() => {})
            return { handled: true, action: 'confirmed_empty', pendingId }
          }
          // ── BUG I4 (Roberto 2026-06-14 17:05 BRT — macarronada 350g) ──
          // Itens "zerados" por composite_rejected/no_match no meal-pipeline
          // chegam aqui com kcal=0 mas quantity_g cheio (sólido), e o tap
          // inseria meal_log com 0 kcal — paciente sub-declarava sem rastro.
          // Regra: sólidos com >30g e 0 kcal SÃO erro de parsing (água/chá/
          // refri-zero/gelo/condimento podem ter 0 kcal legítimo e são
          // tratados pelo whitelist de nome).
          //
          // Estratégia (review adversarial 2026-06-15):
          //   1ª tentativa: bloquear all-or-nothing, pedir correção textual.
          //   2ª tentativa (paciente reta'pa): degradar pra best-effort —
          //   registra só os itens OK, ignora os suspeitos e avisa.
          //
          // Normalização NFD remove diacríticos ANTES da regex — `\b` em JS
          // sem flag `u` trata 'á/ã/ç' como NON-WORD; sem isso o whitelist
          // ficava DEAD pra qualquer alimento PT-BR acentuado (review CRITICAL).
          const stripAccents = (s: string): string =>
            s
              .normalize('NFD')
              .replace(/\p{Diacritic}/gu, '')
              .toLowerCase()
          // Whitelist de zero-cal legítimos. Tudo já normalizado pra ASCII.
          const ZERO_CAL_NAME_RE =
            /\b(agua|gelo|gelos|cha|chas|cafe\s+preto|cafe\s+sem\s+acucar|cafe\s+sem|mostarda|vinagre|limao|shoyu|molho\s+shoyu|sal|pimenta|gengibre|alho|acafrao|canela|oregano|salsinha|cebolinha|coentro|manjericao|hortela|aji-no-moto|caldo\s+knorr|caldo\s+de\s+galinha|caldo\s+de\s+legumes)\b/
          // Bebidas zero/diet/light — qualifier + keyword de bebida. Pega
          // Coca/Guaraná/Pepsi/Sprite/Fanta/Schweppes/Powerade/Gatorade/Red
          // Bull/H2O/isotônico/etc sem precisar listar cada marca.
          const ZERO_CAL_DRINK_QUALIFIER_RE =
            /\b(zero|diet|light|sem\s+acucar|sem\s+adocante)\b/
          const DRINK_KEYWORD_RE =
            /\b(refri\w*|refrigerante|coca|coca-cola|guarana|pepsi|sprite|fanta|schweppes|powerade|gatorade|red\s*bull|skol|brahma|antarctica|sukita|tonica|isotonico|energetico|soda|h2o|monster|burn|aguardente)\b/
          const isLegitZeroCal = (name: string): boolean => {
            const n = stripAccents(name)
            if (ZERO_CAL_NAME_RE.test(n)) return true
            if (ZERO_CAL_DRINK_QUALIFIER_RE.test(n) && DRINK_KEYWORD_RE.test(n)) return true
            return false
          }
          const suspiciousItems = proposal.items.filter((it) => {
            const kcal = Number(it.kcal ?? 0)
            const qty = Number(it.quantity_g ?? 0)
            if (kcal > 0) return false
            if (qty <= 30) return false
            const nm = String(it.name ?? '')
            if (isLegitZeroCal(nm)) return false
            return true
          })
          // Verifica se já bloqueamos esse pending nas últimas 4h —
          // sinal de retry. Evita loop infinito de block quando paciente
          // insiste em re-confirmar via texto curto.
          let isRetryAfterBlock = false
          if (suspiciousItems.length > 0) {
            const since4hIso = new Date(Date.now() - 4 * 60 * 60 * 1000).toISOString()
            const { data: prevBlock } = await supabase
              .from('product_events')
              .select('id')
              .eq('user_id', userId)
              .eq('event', 'tap.blocked_zero_kcal')
              .gte('occurred_at', since4hIso)
              .filter('properties->>pendingId', 'eq', pendingId)
              .limit(1)
            isRetryAfterBlock = ((prevBlock ?? []) as Array<{ id: string }>).length > 0
          }
          if (suspiciousItems.length > 0 && !isRetryAfterBlock) {
            await supabase
              .from('pending_registrations')
              .update({ status: 'pending', resolved_at: null })
              .eq('id', pendingId)
              .eq('status', 'confirmed')

            await supabase.from('product_events').insert({
              user_id: userId,
              event: 'tap.blocked_zero_kcal',
              properties: {
                pendingId,
                meal_type: proposal.mealType ?? null,
                provider_message_id: providerMessageId ?? null,
                suspicious_items: suspiciousItems.map((it) => ({
                  name: it.name,
                  quantity_g: it.quantity_g,
                })),
                ok_items_count: proposal.items.length - suspiciousItems.length,
                total_items: proposal.items.length,
                note:
                  'item sólido com >30g e 0 kcal indica composite_rejected/no_match no parser — não grava com zeros (bug I4 Roberto 2026-06-14)',
              },
            })

            const namesList = suspiciousItems
              .map((it) => `"${it.name}" (${Math.round(Number(it.quantity_g ?? 0))}g)`)
              .join(', ')
            const askText =
              suspiciousItems.length === 1
                ? `Não consegui calcular ${namesList} direito (deu 0 kcal). Me diz o que tinha de mais perto, ou estima kcal/proteína? Se quiser registrar assim mesmo, é só me responder "registra mesmo assim".`
                : `Não consegui calcular esses itens direito: ${namesList}. Me diz o que tinha de mais perto em cada um, ou estima kcal/proteína? Se quiser registrar assim mesmo, é só responder "registra mesmo assim".`
            await messaging
              .sendText(wpp, askText, { replyTo: providerMessageId })
              .catch(() => {})

            await supabase.from('messages').insert({
              user_id: userId,
              direction: 'out',
              role: 'assistant',
              content_type: 'text',
              content: askText,
              provider: 'whatsapp_cloud',
              agent_stage: 'recomposicao',
              delivery_status: 'sent',
            })

            return {
              handled: true,
              action: 'blocked_zero_kcal',
              pendingId,
              suspicious_count: suspiciousItems.length,
            }
          }
          // RETRY após block — best-effort: grava só os itens OK e avisa
          // que os suspeitos foram ignorados. Se TODOS são suspeitos,
          // confirma como veio (paciente insistiu, melhor 0 kcal
          // visível que silêncio).
          if (suspiciousItems.length > 0 && isRetryAfterBlock) {
            const okItems = proposal.items.filter((it) => !suspiciousItems.includes(it))
            await supabase.from('product_events').insert({
              user_id: userId,
              event: 'tap.blocked_zero_kcal_retry',
              properties: {
                pendingId,
                ok_items_count: okItems.length,
                suspicious_count: suspiciousItems.length,
                action: okItems.length > 0 ? 'register_ok_drop_suspicious' : 'register_as_is',
              },
            })
            if (okItems.length > 0) {
              // Reescreve proposal.items pra só conter os OK — flui pro
              // path normal do registraRefeicao abaixo.
              proposal.items = okItems
              const skipNames = suspiciousItems
                .map((it) => `"${it.name}"`)
                .join(', ')
              const warnText = `Beleza, vou registrar o que consegui calcular. ${skipNames} ficou de fora (não consegui estimar). Se quiser, manda só ${skipNames} de novo com estimativa de kcal/proteína.`
              await messaging
                .sendText(wpp, warnText, { replyTo: providerMessageId })
                .catch(() => {})
              await supabase.from('messages').insert({
                user_id: userId,
                direction: 'out',
                role: 'assistant',
                content_type: 'text',
                content: warnText,
                provider: 'whatsapp_cloud',
                agent_stage: 'recomposicao',
                delivery_status: 'sent',
              })
            }
            // Se okItems.length === 0, segue com proposal.items original
            // (todos zerados) — paciente insistiu, registro best-effort.
          }
          // Audit 06-25 Bug D Camada C (Luciana 25/06 lanche pão): tap-handler
          // confirma card que SUBSTITUI proposta anterior do mesmo meal_type+
          // date — antes apenas usava proposal.replace explícito, mas o pipeline
          // raramente seta replace=true no pending. Resultado: tap inseria
          // 270 kcal SOMANDO em cima dos 540 já gravados. Fix: inferir
          // effectiveReplace quando há (a) meal_log do mesmo meal_type hoje
          // E (b) pending anterior status='edited' nos últimos 30min (sinal
          // que paciente já interagiu com proposta antes desse tap).
          let effectiveReplace = proposal.replace === true
          if (!effectiveReplace && proposal.kind === 'meal' && proposal.mealType) {
            try {
              // Audit 06-26 sprint pendentes: extraído pra helpers canônicos
              // @mpp/agent timezone-utils — antes era parser inline duplicado
              // que falhava em alguns formatos de longOffset (review HIGH MED).
              const todayLocal = getLocalDateString(userTimezone)
              const tzOff = getTzOffset(userTimezone)
              const validMealTypes = ['cafe', 'almoco', 'lanche', 'jantar', 'ceia', 'outro'] as const
              type MT = (typeof validMealTypes)[number]
              const propMealType: MT | null = validMealTypes.includes(proposal.mealType as MT)
                ? (proposal.mealType as MT)
                : null
              if (!propMealType) {
                throw new Error(`invalid meal_type: ${proposal.mealType}`)
              }
              const [sameDayRes, priorEditedRes] = await Promise.all([
                supabase
                  .from('meal_logs')
                  .select('id')
                  .eq('user_id', userId)
                  .eq('meal_type', propMealType)
                  .gte('consumed_at', `${todayLocal}T00:00:00${tzOff}`)
                  .lt('consumed_at', `${todayLocal}T23:59:59.999${tzOff}`)
                  .limit(1),
                supabase
                  .from('pending_registrations')
                  .select('id')
                  .eq('user_id', userId)
                  .eq('status', 'edited')
                  // Review HIGH 2 (audit 06-25): filtra por mealType MATCHING
                  // pra evitar inferir replace quando paciente editou pending
                  // de OUTRO meal_type. Caso adversarial: 2 lanches legítimos
                  // no mesmo dia + edit de jantar pendente → antes inferia
                  // replace e deletava o 1º lanche.
                  .eq('proposal->>mealType', propMealType)
                  .gte(
                    'resolved_at',
                    new Date(Date.now() - 30 * 60 * 1000).toISOString(),
                  )
                  .neq('id', pendingId)
                  .limit(1),
              ])
              const hasPriorMealOfSameType = (sameDayRes.data ?? []).length > 0
              const hasPriorEdited = (priorEditedRes.data ?? []).length > 0
              if (hasPriorMealOfSameType && hasPriorEdited) {
                effectiveReplace = true
                await supabase.from('product_events').insert({
                  user_id: userId,
                  event: 'tap.replace_inferred_after_edit',
                  properties: {
                    pendingId,
                    meal_type: proposal.mealType,
                  },
                })
              }
            } catch (e) {
              // eslint-disable-next-line no-console
              console.warn('[interactive-handler] replace inference failed (non-fatal):', e)
            }
          }

          // Bug Roberto 2026-05-29 21:37: tool retornava success=true mesmo
          // com 0 inserts (loop sem error check em tools.ts:1097 — corrigido).
          // Aqui também: try/catch que LOGA + RE-THROW pra Inngest retry +
          // alerta no Telegram quando o tap falhar.
          try {
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
                replace: effectiveReplace,
              } as never,
              toolCtx as never,
            )) as {
              success?: boolean
              already_logged?: boolean
              meal?: { items?: MealItem[]; totals?: MealTotals }
            }
          } catch (err) {
            const msg = err instanceof Error ? err.message : String(err)
            await supabase.from('product_events').insert({
              user_id: userId,
              event: 'interactive.handler.tool_failed',
              properties: {
                pendingId,
                kind: 'meal',
                meal_type: proposal.mealType,
                items_count: proposal.items?.length ?? 0,
                provider_message_id: toolCtx.providerMessageId,
                error: msg,
              },
            })
            // Desfaz o confirmed pra paciente conseguir tentar de novo
            await supabase
              .from('pending_registrations')
              .update({ status: 'pending', resolved_at: null })
              .eq('id', pendingId)
              .eq('status', 'confirmed')
            logger.error('registraRefeicao.execute throw no tap', {
              pendingId,
              userId,
              error: msg,
            })
            throw err
          }
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
        const textBase = composePostRegistrationMessage({
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

        // Roberto 2026-06-01: chama Haiku pra gerar comentário educativo
        // 2-4 frases (microvitória → identidade → orientação) que entra
        // entre tabela e card. Degradação graciosa: se falhar/timeout,
        // segue sem comentário.
        const { llm, supabase: deps2Supabase, embeddings: deps2Embeddings } = createWorkerDeps()
        // Guard caller-side (bug Roberto 2026-06-16): quando a tool retornou
        // already_logged=true (dedup parcial OU total), o card diz "já estava
        // registrado". Chamar Haiku aqui com items vazios (dedup 100%) gera
        // improviso contradizendo o card; chamar com items só parciais gera
        // comentário sobre refeição "nova" que não é nova. Mais defensivo:
        // qualquer already_logged=true pula o Haiku.
        // Review HIGH H4: condição anterior exigia items.length===0 também,
        // o que falhava em dedup parcial. Agora só already_logged é
        // suficiente. Defesa em camadas com o guard interno de
        // generateEducationalComment.
        const skipEdu =
          proposal.kind !== 'workout' && mealToolResult?.already_logged === true
        if (skipEdu) {
          await supabase.from('product_events').insert({
            user_id: userId,
            event: 'edu_comment.skipped_dedup',
            properties: {
              pendingId,
              meal_type: proposal.mealType ?? null,
              proposed_items_count: proposal.items?.length ?? 0,
              stage: 'interactive-handler',
            },
          })
        }
        const eduComment = skipEdu
          ? ''
          : await generateEducationalComment(
          llm,
          {
            kind:
              proposal.kind === 'workout'
                ? 'treino'
                : ((proposal.mealType as EduCommentInput['kind']) ?? 'outro'),
            // Adapter (P0 audit 2026-06-13): tool retorna items com chave
            // `name`, EduCommentInput espera `food_name`. Fallback proposal.items
            // quando a tool deduplica tudo (mesmo padrão de L401).
            items:
              proposal.kind !== 'workout'
                ? adaptToolItemsToEduInput(
                    (mealToolResult?.meal?.items as Parameters<
                      typeof adaptToolItemsToEduInput
                    >[0]) ??
                      (proposal.items as Parameters<typeof adaptToolItemsToEduInput>[0]),
                  )
                : undefined,
            totals:
              proposal.kind !== 'workout'
                ? (mealToolResult?.meal?.totals as EduCommentInput['totals']) ?? undefined
                : undefined,
            workout:
              proposal.kind === 'workout'
                ? {
                    type: proposal.workoutType ?? 'treino',
                    durationMin: proposal.durationMin,
                    kcalBurned: workoutToolResult?.kcal_burned ?? proposal.kcalEst ?? 0,
                  }
                : undefined,
            protocol:
              (proto as 'recomposicao' | 'ganho_massa' | 'manutencao' | null) ?? null,
          },
          {
            // ATIVA curated-phrase path (review CRITICAL).
            supabase: deps2Supabase,
            userId,
            state: {
              protocol:
                (proto as 'recomposicao' | 'ganho_massa' | 'manutencao' | null) ?? null,
            },
            // Cascade semântica pra resolver foods compostos.
            embeddings: deps2Embeddings,
          },
        )

        // embedEduComment é função pura testável (invariante: eduComment
        // não-vazio ⇒ marker presente). Antes era código duplicado entre
        // pipeline.ts e este handler — 52% dos registros saíam sem
        // comentário em prod e não havia teste do invariante.
        const text = embedEduComment(textBase, eduComment)

        // Roberto 2026-06-01: divide em ATÉ 3 bolhas — tabela | comentário
        // educativo | card de balanço — pra cada parte ter respiro próprio.
        // Antes a tabela+comentário ia numa bolha só, ficava densa demais
        // (almoço 8 itens + 4 linhas de comentário = 1.4kb numa msg). Se
        // não houver comentário (Haiku falhou), splitRegistrationParts
        // devolve comment=null e envia 2 bolhas (tabela | card).
        const { meal: mealPart, comment: commentPart, card: cardPart } = splitRegistrationParts(text)
        await sendHumanized(messaging, wpp, mealPart, {
          singleMessage: true,
          minDelay: 0,
          maxDelay: 0,
          showTyping: false,
          inReplyTo: providerMessageId,
        }).catch(() => {})
        if (commentPart) {
          await new Promise((res) => setTimeout(res, 1500))
          await sendHumanized(messaging, wpp, commentPart, {
            singleMessage: true,
            minDelay: 0,
            maxDelay: 0,
            showTyping: false,
          }).catch(() => {})
        }
        if (cardPart) {
          await new Promise((res) => setTimeout(res, 1500))
          await sendHumanized(messaging, wpp, cardPart, {
            singleMessage: true,
            minDelay: 0,
            maxDelay: 0,
            showTyping: false,
          }).catch(() => {})
        }

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
