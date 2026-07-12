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
  type EduCommentInput,
  embedEduComment,
  generateEducationalComment,
  getLocalDateString,
  getTzOffset,
  type MealItem,
  type MealTotals,
  type PendingFoodCorrection,
  parseOnboardingButtonId,
  type RegistrationEntry,
  registraRefeicao,
  registraTreino,
  shouldInferReplaceAfterEdit,
  splitRegistrationParts,
} from '@mpp/agent'
import { createMessagingProvider, sendHumanized } from '@mpp/providers'
import { inngest } from '../client.js'
import { createWorkerDeps } from '../lib/env.js'
import { throwIfQueryFailed } from '../lib/query-error.js'
import { reopenLossyCancellationPending } from './lossy-cancellation-recovery.js'
import { persistOutboundMessage } from './outbound-message-persistence.js'
import { buildOutboundMessageRows } from './outbound-message-rows.js'
import {
  buildConfirmedMealArgs,
  buildConfirmedMealRegistrationEntry,
  shouldBlockEffectiveReplace,
} from './pending-meal-confirmation.js'
import { decidePendingMealItems } from './pending-meal-item-policy.js'
import { transitionPendingStatus } from './pending-status-transition.js'

const BUTTON_ID_PATTERN = /^(confirm|edit)_([0-9a-f-]{36})$/

interface PendingRow {
  id: string
  user_id: string
  status: 'pending' | 'confirmed' | 'edited' | 'expired' | 'cancelled'
  expires_at: string
  proposal: Record<string, unknown>
  created_at: string
  resolved_at: string | null
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
      tappedAt?: string
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
      const providerName = process.env.MESSAGING_PROVIDER ?? 'whatsapp_cloud'
      const persistDeliveries = async (
        deliveries: Array<{
          content: string
          providerMessageId: string | null
          status: 'queued' | 'sent' | 'failed'
          error?: string
        }>,
        responsePart: string,
      ) => {
        const failed = deliveries.find((delivery) => delivery.status === 'failed')
        if (failed) throw new Error(failed.error ?? 'interactive response delivery failed')
        const rows = buildOutboundMessageRows({
          userId,
          provider: providerName,
          contentType: 'text',
          stage: 'recomposicao',
          modelUsed: null,
          promptTokens: null,
          completionTokens: null,
          costUsd: null,
          latencyMs: null,
          metadata: { pending_id: buttonId, response_part: responsePart },
          deliveries,
        })
        for (const row of rows) await persistOutboundMessage(supabase, row)
      }
      const wasPartDelivered = async (responsePart: string) => {
        const { data: existing, error: deliveryLookupError } = await supabase
          .from('messages')
          .select('id')
          .eq('user_id', userId)
          .eq('direction', 'out')
          .filter('raw_payload->>pending_id', 'eq', buttonId)
          .filter('raw_payload->>response_part', 'eq', responsePart)
          .neq('delivery_status', 'failed')
          .limit(1)
        throwIfQueryFailed(deliveryLookupError, 'interactive delivery lookup failed')
        return (existing ?? []).length > 0
      }
      const sendTextTracked = async (content: string, responsePart: string) => {
        if (await wasPartDelivered(responsePart)) return
        const delivery = await messaging.sendText(wpp, content, {
          replyTo: providerMessageId,
        })
        await persistDeliveries(
          [
            {
              content,
              providerMessageId: delivery.providerMessageId,
              status: delivery.status,
              error: delivery.error,
            },
          ],
          responsePart,
        )
      }
      const sendHumanizedTracked = async (
        content: string,
        options: Parameters<typeof sendHumanized>[3],
        responsePart: string,
      ) => {
        if (await wasPartDelivered(responsePart)) return
        const results = await sendHumanized(messaging, wpp, content, options)
        await persistDeliveries(
          results.map((delivery) => ({
            content: delivery.content,
            providerMessageId: delivery.providerMessageId,
            status: delivery.status,
            error: delivery.error,
          })),
          responsePart,
        )
      }

      // Roberto 2026-06-01: botão de onboarding (`btn_<field>_<value>`)
      // dispara cadastra_dados_iniciais direto. Padrão diferente do
      // confirm/edit (que envolvem pending_registrations).
      const onbBtn = parseOnboardingButtonId(buttonId)
      if (onbBtn) {
        try {
          await cadastraDadosIniciais.execute(
            { [onbBtn.field]: onbBtn.value } as never,
            {
              supabase,
              userId,
              userWpp: wpp,
              userCountry: 'BR',
              userTimezone: 'America/Sao_Paulo',
              providerMessageId,
              recentUserMessages: [],
            } as never,
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

      const { data: pending, error: pendingLookupError } = await supabase
        .from('pending_registrations')
        .select('id, user_id, status, expires_at, proposal, created_at, resolved_at')
        .eq('id', pendingId)
        .maybeSingle()
      throwIfQueryFailed(pendingLookupError, 'interactive pending lookup failed')
      const row = pending as PendingRow | null

      // Pending não existe → talvez tap em msg antiga / dado limpo
      if (!row) {
        await sendTextTracked(
          'Esse registro não foi encontrado. Me manda de novo?',
          'pending_not_found',
        )
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
        // Audit 06-26 Layer 3 pizza-race recovery: quando status=cancelled E
        // tap recente (<120s) E há meal_log subset gravado pelo express path
        // entre pending.created_at e resolved_at, RECUPERA: reabre o pending e
        // deixa a troca para register_meal_atomic. Caso Luciana 23/06 pizza
        // (já mitigado por Layer 1 mas residual existe quando subset-check
        // falha por normalização/sinônimo/plural).
        const RECOVERY_WINDOW_MS = 120_000
        const proposal = row.proposal as {
          kind?: 'meal' | 'workout'
          items?: Array<{ name?: string; food_name?: string; quantity_g?: number; kcal?: number }>
          mealType?: string
          totals?: { kcal?: number }
          source_provider_message_id?: string
        }
        const resolvedAt = row.resolved_at
        const recoveryEligible =
          action === 'confirm' &&
          row.status === 'cancelled' &&
          proposal?.kind === 'meal' &&
          Array.isArray(proposal.items) &&
          proposal.items.length >= 2 &&
          typeof resolvedAt === 'string' &&
          Date.now() - new Date(resolvedAt).getTime() <= RECOVERY_WINDOW_MS
        if (recoveryEligible && typeof resolvedAt === 'string') {
          try {
            const stripAccents = (s: string) =>
              s
                .toLowerCase()
                .normalize('NFD')
                .replace(/\p{Diacritic}/gu, '')
                .trim()
            const proposalNamesSet = new Set(
              (proposal.items ?? [])
                .map((it) => stripAccents(it.name ?? it.food_name ?? ''))
                .filter(Boolean),
            )
            const proposalKcalTotal = proposal.totals?.kcal ?? 0
            const validMealTypes = ['cafe', 'almoco', 'lanche', 'jantar', 'ceia', 'outro'] as const
            type MT = (typeof validMealTypes)[number]
            // Review MED 2 (audit 06-26 review): se proposal.mealType
            // inválido/ausente, ABORTA recovery — não fallback p/ 'outro'
            // (puxaria meal_logs de qualquer refeição "outro" no intervalo,
            // arriscando deletar/reabrir item alheio). Skip silencioso é
            // mais seguro que recovery agressivo num cenário ambíguo.
            const mealTypeOk = validMealTypes.includes(proposal.mealType as MT)
            if (!mealTypeOk) {
              await supabase.from('product_events').insert({
                user_id: userId,
                event: 'tap.recovery_skipped',
                properties: {
                  pendingId,
                  reason: 'invalid_proposal_meal_type',
                  raw_meal_type: String(proposal.mealType ?? ''),
                },
              })
            }
            const candMealType: MT | null = mealTypeOk ? (proposal.mealType as MT) : null
            // Busca meal_logs do mesmo user+meal_type no intervalo
            // [pending.created_at, pending.resolved_at + 5s].
            const startIso = new Date(row.created_at).toISOString()
            const endIso = new Date(new Date(resolvedAt).getTime() + 5000).toISOString()
            // Se mealType inválido (MED 2), pula query → cands=[] → fresh=[]
            // → recoveryCandidateOk=false → segue noop original (skip seguro).
            let candidates: unknown[] = []
            if (candMealType) {
              // eslint-disable-next-line @typescript-eslint/no-explicit-any
              const { data: candidateRows, error: candidatesError } = await (supabase as any)
                .from('meal_logs')
                .select('id, food_name, kcal, created_at, raw_provider_message_id')
                .eq('user_id', userId)
                .eq('meal_type', candMealType)
                .gte('created_at', startIso)
                .lte('created_at', endIso)
              throwIfQueryFailed(candidatesError, 'lossy cancellation candidates lookup failed')
              candidates = candidateRows ?? []
            }
            const cands = (candidates ?? []) as Array<{
              id: string
              food_name: string
              kcal: number | string
              created_at: string
              raw_provider_message_id: string | null
            }>
            // Guard pmid: ignora se mesmo pmid da foto-fonte (é o pending de outro caminho).
            // (meal_logs não tem updated_at — guard de edição não aplicável aqui.)
            const fresh = cands.filter((c) => {
              if (
                proposal.source_provider_message_id &&
                c.raw_provider_message_id === proposal.source_provider_message_id
              ) {
                return false
              }
              return true
            })
            // Verifica subset: 80% dos nomes em fresh ∈ proposalNames
            let subsetMatchCount = 0
            for (const c of fresh) {
              if (proposalNamesSet.has(stripAccents(c.food_name))) subsetMatchCount++
            }
            const subsetRatio = fresh.length > 0 ? subsetMatchCount / fresh.length : 0
            const subsetKcalTotal = fresh.reduce((a, c) => a + (Number(c.kcal) || 0), 0)
            const sanityKcalOk =
              proposalKcalTotal > 0 ? subsetKcalTotal <= proposalKcalTotal * 0.6 : true
            const recoveryCandidateOk = fresh.length > 0 && subsetRatio >= 0.8 && sanityKcalOk
            await supabase.from('product_events').insert({
              user_id: userId,
              event: 'tap.recovery_candidate_evaluated',
              properties: {
                pendingId,
                subset_fresh_count: fresh.length,
                subset_match_ratio: subsetRatio,
                subset_kcal_total: subsetKcalTotal,
                proposal_kcal_total: proposalKcalTotal,
                sanity_kcal_ok: sanityKcalOk,
                resolved_at_age_ms: Date.now() - new Date(resolvedAt).getTime(),
                decision: recoveryCandidateOk ? 'run' : 'skip',
              },
            })
            if (recoveryCandidateOk) {
              const subsetIds = fresh.map((candidate) => candidate.id)
              // Não toca em meal_logs/snapshot aqui. Se qualquer etapa seguinte
              // falhar, os dados anteriores continuam íntegros; a confirmação
              // executa substituição + recálculo na RPC transacional.
              const reopened = await reopenLossyCancellationPending(supabase, {
                userId,
                pendingId,
                subsetMealLogIds: subsetIds,
                subsetKcalTotal,
                proposalKcalTotal,
                subsetMatchRatio: subsetRatio,
                resolvedAtAgeMs: Date.now() - new Date(resolvedAt).getTime(),
              })
              if (reopened) {
                // Marca row como pending pra fluxo CONFIRM normal abaixo.
                row.status = 'pending'
                row.resolved_at = null
                // Força replace=true no proposal pra o execute abaixo
                // deletar resíduos remanescentes e inserir proposal completa.
                const recoveredProposal = row.proposal as {
                  replace?: boolean
                  replace_evidence?: string
                }
                recoveredProposal.replace = true
                recoveredProposal.replace_evidence = 'lossy_cancellation_recovery'
              }
            }
          } catch (e) {
            logger.error('cancelled pending recovery failed', {
              pendingId,
              userId,
              error: e instanceof Error ? e.message : String(e),
            })
            throw e
          }
        }

        // Se não houve recovery, segue noop original.
        if (row.status !== 'pending') {
          await supabase.from('product_events').insert({
            user_id: userId,
            event: 'pending.duplicate_tap',
            properties: { pendingId, action, currentStatus: row.status },
          })
          return { handled: true, action: 'noop', reason: `status=${row.status}` }
        }
      }

      // Expirado → marca expired + avisa
      if (new Date(row.expires_at).getTime() <= Date.now()) {
        await sendTextTracked(
          'Esse registro expirou (demorou mais de 1 dia). Me manda de novo o que comeu?',
          'pending_expired',
        )
        await transitionPendingStatus(supabase, {
          pendingId,
          from: 'pending',
          to: 'expired',
          resolvedAt: new Date().toISOString(),
        })
        await supabase.from('product_events').insert({
          user_id: userId,
          event: 'pending.expired_on_tap',
          properties: { pendingId, action },
        })
        return { handled: true, action: 'expired' }
      }

      // ── CONFIRM (Fase B) ──
      // GRAVA de verdade chamando registra_refeicao com items da proposta
      // (bypassando o LLM — items já foram resolvidos no turno original),
      // responde com o card e só então marca confirmed. Assim, retry de qualquer
      // etapa ainda encontra o pending aberto e as tools idempotentes retomam.
      if (action === 'confirm') {
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
          source_text?: string | null
          source_timestamp?: string
          source_timezone?: string
          source_local_date?: string
          corrections?: PendingFoodCorrection[]
          /** Roberto 2026-06-01: pending de correção. Quando true, o execute
           * precisa receber replace=true pra SUBSTITUIR a refeição do dia em
           * vez de inserir nova. Salvo no pipeline quando args.replace=true. */
          replace?: boolean
          replace_evidence?: string
        }

        // Carrega user pra timezone (pra computar a data local no tool)
        const { data: usr, error: userLookupError } = await supabase
          .from('users')
          .select('timezone, country')
          .eq('id', userId)
          .maybeSingle()
        throwIfQueryFailed(userLookupError, 'interactive user lookup failed')
        if (!usr) throw new Error('interactive user not found')
        const userTimezone =
          (usr as { timezone?: string | null } | null)?.timezone ?? 'America/Sao_Paulo'
        const userCountry = (usr as { country?: string | null } | null)?.country ?? 'BR'
        const parsedSourceTimestamp = proposal.source_timestamp
          ? new Date(proposal.source_timestamp)
          : null
        const referenceTimestamp =
          parsedSourceTimestamp && Number.isFinite(parsedSourceTimestamp.getTime())
            ? parsedSourceTimestamp
            : new Date(data.tappedAt ?? row.created_at ?? Date.now())
        const sourceLocalDate =
          typeof proposal.source_local_date === 'string' &&
          /^\d{4}-\d{2}-\d{2}$/.test(proposal.source_local_date)
            ? proposal.source_local_date
            : getLocalDateString(userTimezone, referenceTimestamp)

        const toolCtx = {
          supabase,
          userId,
          userWpp: wpp,
          userCountry,
          userTimezone,
          providerMessageId: proposal.source_provider_message_id ?? providerMessageId,
          referenceTimestamp,
          currentUserText: proposal.source_text ?? '',
          recentUserMessages:
            typeof proposal.source_text === 'string' && proposal.source_text.trim()
              ? [proposal.source_text]
              : [],
          // Bug I2 (Luciana 2026-06-14 15:44 BRT, pending bfdad07b): tap em
          // pending antigo gravava meal_type ERRADO. proposal.mealType='cafe'
          // (salvo às 13h) virava 'lanche' no DB (autocorrect por localHour=15),
          // enquanto o card mostrava "Café registrado". Quando há mealType
          // explícito no proposal — paciente VIU e CLICOU pra confirmar —
          // ele é canônico: desliga autocorrect na tool. workout não usa.
          trustMealType: proposal.kind !== 'workout' && typeof proposal.mealType === 'string',
        }

        // Chama a tool de gravar diretamente (bypassando LLM) com os dados
        // resolvidos no pending. Branch por kind: meal usa registraRefeicao;
        // workout usa registraTreino. Resultado vai pro mesmo card determinístico.
        let mealToolResult: {
          success?: boolean
          already_logged?: boolean
          meal?: { items?: MealItem[]; totals?: MealTotals }
        } | null = null
        let workoutToolResult: {
          success?: boolean
          kcal_burned?: number
          deduped?: boolean
        } | null = null

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
            logger.error('registraTreino.execute throw no tap', { pendingId, userId, error: msg })
            throw err
          }
        } else {
          // meal (default)
          const proposedItems = proposal.items ?? []
          let itemDecision = decidePendingMealItems(proposedItems, false)
          if (itemDecision.action === 'reject_empty') {
            await sendTextTracked(
              'Não consegui recuperar os itens desse registro, então não gravei nada. Me manda a refeição de novo que eu recalculo certinho.',
              'confirmation_invalid_empty',
            )
            await transitionPendingStatus(supabase, {
              pendingId,
              from: 'pending',
              to: 'edited',
              resolvedAt: new Date().toISOString(),
            })
            await supabase.from('product_events').insert({
              user_id: userId,
              event: 'pending.invalid_empty_proposal',
              properties: { pendingId, meal_type: proposal.mealType ?? null },
            })
            return { handled: true, action: 'rejected_empty', pendingId }
          }

          // Itens não reconhecidos com 0 kcal nunca são gravados como se o
          // cálculo fosse válido. Zeros legítimos são classificados no helper.
          // Verifica se já bloqueamos esse pending nas últimas 4h —
          // sinal de retry. Evita loop infinito de block quando paciente
          // insiste em re-confirmar via texto curto.
          let isRetryAfterBlock = false
          if (itemDecision.suspiciousItems.length > 0) {
            const since4hIso = new Date(Date.now() - 4 * 60 * 60 * 1000).toISOString()
            const { data: prevBlock, error: previousBlockError } = await supabase
              .from('product_events')
              .select('id')
              .eq('user_id', userId)
              .eq('event', 'tap.blocked_zero_kcal')
              .gte('occurred_at', since4hIso)
              .filter('properties->>pendingId', 'eq', pendingId)
              .limit(1)
            throwIfQueryFailed(previousBlockError, 'zero kcal retry lookup failed')
            isRetryAfterBlock = ((prevBlock ?? []) as Array<{ id: string }>).length > 0
            itemDecision = decidePendingMealItems(proposedItems, isRetryAfterBlock)
          }
          if (itemDecision.action === 'block') {
            const namesList = itemDecision.suspiciousItems
              .map((it) => `"${it.name}" (${Math.round(Number(it.quantity_g ?? 0))}g)`)
              .join(', ')
            const invalidText =
              itemDecision.suspiciousItems.length === 1
                ? `Não consegui calcular ${namesList} direito (deu 0 kcal).`
                : `Não consegui calcular estes itens direito: ${namesList}.`
            const askText =
              itemDecision.validItems.length > 0
                ? `${invalidText} Me diga os valores ou responda "registra mesmo assim" para eu registrar somente os outros itens calculados.`
                : `${invalidText} Me diga o alimento mais próximo ou uma estimativa de kcal e proteína; sem isso eu não consigo registrar com segurança.`
            await sendTextTracked(askText, 'zero_kcal_block')

            const { error: blockedEventError } = await supabase.from('product_events').insert({
              user_id: userId,
              event: 'tap.blocked_zero_kcal',
              properties: {
                pendingId,
                meal_type: proposal.mealType ?? null,
                provider_message_id: providerMessageId ?? null,
                suspicious_items: itemDecision.suspiciousItems.map((it) => ({
                  name: it.name,
                  quantity_g: it.quantity_g,
                })),
                ok_items_count: itemDecision.validItems.length,
                total_items: proposedItems.length,
                note: 'item não reconhecido com 0 kcal não pode ser tratado como cálculo válido',
              },
            })
            throwIfQueryFailed(blockedEventError, 'zero kcal block persistence failed')

            return {
              handled: true,
              action: 'blocked_zero_kcal',
              pendingId,
              suspicious_count: itemDecision.suspiciousItems.length,
            }
          }
          if (itemDecision.action === 'reject_all') {
            await sendTextTracked(
              'Ainda não tenho um valor válido para registrar essa refeição e não vou salvar como 0 kcal. Me manda os itens de novo com quantidade ou uma estimativa de calorias.',
              'zero_kcal_rejected_all',
            )
            await transitionPendingStatus(supabase, {
              pendingId,
              from: 'pending',
              to: 'edited',
              resolvedAt: new Date().toISOString(),
            })
            await supabase.from('product_events').insert({
              user_id: userId,
              event: 'tap.rejected_all_zero_kcal',
              properties: {
                pendingId,
                suspicious_count: itemDecision.suspiciousItems.length,
              },
            })
            return { handled: true, action: 'rejected_all_zero_kcal', pendingId }
          }
          proposal.items = itemDecision.validItems
          if (itemDecision.action === 'register_valid_only') {
            await supabase.from('product_events').insert({
              user_id: userId,
              event: 'tap.blocked_zero_kcal_retry',
              properties: {
                pendingId,
                ok_items_count: itemDecision.validItems.length,
                suspicious_count: itemDecision.suspiciousItems.length,
                action: 'register_ok_drop_suspicious',
              },
            })
            const skipNames = itemDecision.suspiciousItems.map((it) => `"${it.name}"`).join(', ')
            const warnText = `Beleza, vou registrar o que consegui calcular. ${skipNames} ficou de fora (não consegui estimar). Se quiser, manda só ${skipNames} de novo com estimativa de kcal/proteína.`
            await sendTextTracked(warnText, 'zero_kcal_retry_warning')
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
          if (proposal.kind === 'meal' && proposal.mealType) {
            try {
              // Audit 06-26 sprint pendentes: extraído pra helpers canônicos
              // @mpp/agent timezone-utils — antes era parser inline duplicado
              // que falhava em alguns formatos de longOffset (review HIGH MED).
              const todayLocal = sourceLocalDate
              const tzOff = getTzOffset(userTimezone, referenceTimestamp)
              const validMealTypes = [
                'cafe',
                'almoco',
                'lanche',
                'jantar',
                'ceia',
                'outro',
              ] as const
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
                  .select('id, proposal')
                  .eq('user_id', userId)
                  .eq('status', 'edited')
                  // Review HIGH 2 (audit 06-25): filtra por mealType MATCHING
                  // pra evitar inferir replace quando paciente editou pending
                  // de OUTRO meal_type. Caso adversarial: 2 lanches legítimos
                  // no mesmo dia + edit de jantar pendente → antes inferia
                  // replace e deletava o 1º lanche.
                  .eq('proposal->>mealType', propMealType)
                  .gte('resolved_at', new Date(Date.now() - 30 * 60 * 1000).toISOString())
                  .neq('id', pendingId)
                  .limit(1),
              ])
              throwIfQueryFailed(sameDayRes.error, 'same-day meal lookup failed')
              throwIfQueryFailed(priorEditedRes.error, 'edited pending lookup failed')
              const hasPriorMealOfSameType = (sameDayRes.data ?? []).length > 0
              const priorEditedRows = (priorEditedRes.data ?? []) as Array<{
                id?: string | null
                proposal?: {
                  items?: Array<{ name?: string; food_name?: string; quantity_g?: number }>
                } | null
              }>
              const hasPriorEdited = priorEditedRows.length > 0
              const decision = shouldInferReplaceAfterEdit({
                hasPriorMealOfSameType,
                hasPriorEditedPending: hasPriorEdited,
                recentUserMessages:
                  typeof proposal.source_text === 'string' && proposal.source_text.trim()
                    ? [proposal.source_text]
                    : [],
                newItems: (proposal.items ?? []).map((it) => ({
                  food_name: it.name,
                  quantity_g: it.quantity_g,
                })),
                editedPendingItems: (priorEditedRows[0]?.proposal?.items ?? []).map((it) => ({
                  food_name: it.food_name ?? it.name,
                  quantity_g: it.quantity_g,
                })),
              })
              if (!effectiveReplace && decision.inferReplace) {
                effectiveReplace = true
                await supabase.from('product_events').insert({
                  user_id: userId,
                  event: 'tap.replace_inferred_after_edit',
                  properties: {
                    pendingId,
                    meal_type: proposal.mealType,
                    reason: decision.reason,
                    overlap_ratio: decision.overlapRatio,
                  },
                })
              } else if (
                shouldBlockEffectiveReplace({
                  effectiveReplace,
                  hasPriorMealOfSameType,
                  hasPriorEditedPending: hasPriorEdited,
                  inferredReplace: decision.inferReplace,
                  replaceEvidence: proposal.replace_evidence,
                })
              ) {
                effectiveReplace = false
                await supabase.from('product_events').insert({
                  user_id: userId,
                  event: 'tap.replace_blocked_weak_evidence',
                  properties: {
                    pendingId,
                    meal_type: proposal.mealType,
                    prior_edited_pending_id: priorEditedRows[0]?.id ?? null,
                    reason: decision.reason,
                    overlap_ratio: decision.overlapRatio,
                  },
                })
              }
            } catch (e) {
              logger.error('replace inference failed', {
                pendingId,
                userId,
                error: e instanceof Error ? e.message : String(e),
              })
              throw e
            }
          }

          // Bug Roberto 2026-05-29 21:37: tool retornava success=true mesmo
          // com 0 inserts (loop sem error check em tools.ts:1097 — corrigido).
          // Aqui também: try/catch que LOGA + RE-THROW pra Inngest retry +
          // alerta no Telegram quando o tap falhar.
          try {
            mealToolResult = (await registraRefeicao.execute(
              buildConfirmedMealArgs(
                {
                  mealType: proposal.mealType,
                  items: proposal.items,
                  corrections: proposal.corrections,
                },
                effectiveReplace,
                sourceLocalDate,
              ) as never,
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
            logger.error('registraRefeicao.execute throw no tap', {
              pendingId,
              userId,
              error: msg,
            })
            throw err
          }
        }

        // Carrega snapshot + progress frescos pro card canônico (mesma fonte do FIX C)
        const todayStr = sourceLocalDate
        const [snapshotResult, progressResult, profileResult] = await Promise.all([
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
        throwIfQueryFailed(snapshotResult.error, 'confirmation snapshot lookup failed')
        throwIfQueryFailed(progressResult.error, 'confirmation progress lookup failed')
        throwIfQueryFailed(profileResult.error, 'confirmation profile lookup failed')
        const snap = snapshotResult.data
        const prog = progressResult.data
        const prof = profileResult.data
        if (!snap) throw new Error('confirmation snapshot not found')
        if (!prog) throw new Error('confirmation progress not found')
        if (!prof) throw new Error('confirmation profile not found')
        const s = (snap ?? {}) as {
          calories_consumed?: number
          calories_target?: number | null
          protein_g?: number
          protein_target?: number | null
          exercise_calories?: number
        }
        const p = (prog ?? {}) as { deficit_block?: number }
        const proto =
          (prof as { current_protocol?: string | null } | null)?.current_protocol ?? null

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
                buildConfirmedMealRegistrationEntry(
                  {
                    mealType: proposal.mealType,
                    items: proposal.items,
                    totals: proposal.totals,
                  },
                  mealToolResult,
                ),
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
            protocol: (proto as 'recomposicao' | 'ganho_massa' | 'manutencao' | null) ?? null,
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
        const skipEdu = proposal.kind !== 'workout' && mealToolResult?.already_logged === true
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
                        >[0]) ?? (proposal.items as Parameters<typeof adaptToolItemsToEduInput>[0]),
                      )
                    : undefined,
                totals:
                  proposal.kind !== 'workout'
                    ? ((mealToolResult?.meal?.totals as EduCommentInput['totals']) ?? undefined)
                    : undefined,
                workout:
                  proposal.kind === 'workout'
                    ? {
                        type: proposal.workoutType ?? 'treino',
                        durationMin: proposal.durationMin,
                        kcalBurned: workoutToolResult?.kcal_burned ?? proposal.kcalEst ?? 0,
                      }
                    : undefined,
                protocol: (proto as 'recomposicao' | 'ganho_massa' | 'manutencao' | null) ?? null,
              },
              {
                // ATIVA curated-phrase path (review CRITICAL).
                supabase: deps2Supabase,
                userId,
                state: {
                  protocol: (proto as 'recomposicao' | 'ganho_massa' | 'manutencao' | null) ?? null,
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
        const {
          meal: mealPart,
          comment: commentPart,
          card: cardPart,
        } = splitRegistrationParts(text)
        try {
          await sendHumanizedTracked(
            mealPart,
            {
              singleMessage: true,
              minDelay: 0,
              maxDelay: 0,
              showTyping: false,
              inReplyTo: providerMessageId,
            },
            'confirmation_meal',
          )
          if (commentPart) {
            await new Promise((resolve) => setTimeout(resolve, 1500))
            await sendHumanizedTracked(
              commentPart,
              {
                singleMessage: true,
                minDelay: 0,
                maxDelay: 0,
                showTyping: false,
              },
              'confirmation_comment',
            )
          }
          if (cardPart) {
            await new Promise((resolve) => setTimeout(resolve, 1500))
            await sendHumanizedTracked(
              cardPart,
              {
                singleMessage: true,
                minDelay: 0,
                maxDelay: 0,
                showTyping: false,
              },
              'confirmation_card',
            )
          }
        } catch (error) {
          await supabase.from('product_events').insert({
            user_id: userId,
            event: 'interactive.handler.delivery_failed',
            properties: {
              pendingId,
              kind: proposal.kind ?? 'meal',
              error: error instanceof Error ? error.message : String(error),
            },
          })
          throw error
        }

        await transitionPendingStatus(supabase, {
          pendingId,
          from: 'pending',
          to: 'confirmed',
          resolvedAt: new Date().toISOString(),
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
      // Pede correção e só então marca status. Próxima msg do paciente cai no
      // fluxo normal do LLM (que vai re-analisar e criar novo pending).
      await sendTextTracked('Beleza, me corrige aí o que tá errado.', 'edit_prompt')
      await transitionPendingStatus(supabase, {
        pendingId,
        from: 'pending',
        to: 'edited',
        resolvedAt: new Date().toISOString(),
      })
      await supabase.from('product_events').insert({
        user_id: userId,
        event: 'pending.edited',
        properties: { pendingId, kind: (row.proposal as { kind?: string }).kind ?? 'unknown' },
      })
      return { handled: true, action: 'edited', pendingId }
    })
  },
)
