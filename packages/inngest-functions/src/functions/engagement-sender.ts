import {
  getLocalDateMinusDays,
  getLocalDateString,
  getLocalHour,
  getMealPattern,
  getTzOffset,
  loadCalcConfig,
  loadDailyTargets,
  loadFilteredSystemPrompt,
  reconcileBlocoMention,
  reconcileRealDeficitProse,
  reevaluationKickoff,
} from '@mpp/agent'
import { realDailyDeficit } from '@mpp/core'
import {
  createMessagingProvider,
  sendHumanized,
  TTSRouter,
  rewriteForTTS,
} from '@mpp/providers'
import { inngest } from '../client.js'
import { createWorkerDeps, loadCredential } from '../lib/env.js'
import { loadHumanizerConfig } from '../lib/runtime-config.js'

/**
 * Worker: envia mensagens proativas de engajamento.
 *
 * Disparado 5×/dia (07:07, 11:16, 14:09, 18:30, 21:27).
 * Para cada usuário ativo:
 *   1. Verifica se já mandou mensagem hoje (skip se sim — evita spam)
 *   2. Verifica horário local: skip se for noite (entre 22h e 06h)
 *   3. Lê estado (XP, streak, último snapshot)
 *   4. LLM gera mensagem com prompt do stage 'engajamento'
 *   5. Envia via messaging provider (console no dev, WA Cloud em prod)
 *   6. Persiste em messages
 */
export const engagementSenderFn = inngest.createFunction(
  { id: 'engagement-sender', retries: 1, concurrency: { limit: 5 } },
  { event: 'engagement.tick' },
  async ({ event, step, logger }) => {
    const { slot } = event.data
    logger.info('Engagement tick', { slot })

    const users = await step.run('list-eligible', async () => {
      const { supabase } = createWorkerDeps()
      const { data } = await supabase
        .from('users')
        .select('id, wpp, name, timezone')
        .eq('status', 'active')
      // Filtra só quem TEM perfil + onboarding completo + protocolo definido
      const ids = (data ?? []).map((u) => u.id)
      if (ids.length === 0) return []
      const { data: profiles } = await supabase
        .from('user_profiles')
        .select('user_id, current_protocol, onboarding_completed')
        .in('user_id', ids)
        .eq('onboarding_completed', true)
        .not('current_protocol', 'is', null)
      const eligibleIds = new Set((profiles ?? []).map((p) => p.user_id))
      return (data ?? []).filter((u) => eligibleIds.has(u.id))
    })

    let sent = 0
    let skipped = 0

    for (const user of users) {
      try {
        const result = await step.run(`engage-${user.id}`, async () =>
          maybeEngageUser(user.id, user.wpp, user.timezone ?? 'America/Sao_Paulo', slot),
        )
        if (result.sent) sent++
        else skipped++
      } catch (e) {
        logger.error('engagement failed', { userId: user.id, error: String(e) })
      }
    }

    return { sent, skipped, total: users.length }
  },
)

async function maybeEngageUser(
  userId: string,
  wpp: string,
  userTimezone: string,
  cronSlotLabel: string,
): Promise<{ sent: boolean; reason?: string }> {
  const { supabase, llm } = createWorkerDeps()

  // Hora local do user — fonte da verdade pra slot e contexto LLM
  const localHour = getLocalHour(userTimezone)
  // Carrega config (cache 60s), deriva slot+hint da hora local
  const engagementConfig = await loadEngagementConfig(supabase)
  const { slot, meal_hint: mealHint, silent: slotSilent } = resolveSlot(localHour, engagementConfig.slots)

  async function logEvent(event: string, properties: Record<string, unknown>) {
    await supabase.from('product_events').insert({
      user_id: userId,
      event,
      properties: { slot, cron_slot: cronSlotLabel, local_hour: localHour, wpp, ...properties },
    })
  }

  // SLOT SILENCIOSO — pula ANTES de qualquer outra checagem.
  // Caso Amanda 2026-05-16: wake_time=03:00 (provável erro de onboarding) →
  // janela ativa virou 04h-20h → slot=madrugada caiu dentro → enviou às 04:07.
  // SlotDef.silent=true pra madrugada/noite garante que mesmo com janela ativa
  // mal-configurada, esses slots nunca disparam. Defesa contra dado errado de
  // profile, sem precisar consertar cada profile individual.
  if (slotSilent) {
    await logEvent('engagement.skipped', {
      reason: 'slot silencioso (madrugada/noite) — não envia',
      slot_silent: true,
    })
    return { sent: false, reason: 'slot silencioso' }
  }

  // Pausa ativa? respeita
  const { data: u } = await supabase
    .from('users')
    .select('metadata, status, name, locale, country')
    .eq('id', userId)
    .maybeSingle()
  const meta = (u as { metadata: Record<string, unknown> | null } | null)?.metadata
  const userTyped = u as {
    metadata: Record<string, unknown> | null
    status: string | null
    name: string | null
    locale: string | null
    country: string | null
  } | null
  const userCountry = userTyped?.country ?? 'BR'
  const countryToLanguage: Record<string, string> = {
    BR: 'pt-BR',
    PT: 'pt-PT',
    US: 'en',
    GB: 'en',
    CA: 'en',
    AU: 'en',
    ES: 'es',
    MX: 'es',
    AR: 'es',
  }
  const userLanguage = userTyped?.locale ?? countryToLanguage[userCountry] ?? 'pt-BR'
  const pausedUntil = meta?.paused_until as string | undefined
  if (pausedUntil && new Date(pausedUntil) > new Date()) {
    await logEvent('engagement.skipped', { reason: 'paused', paused_until: pausedUntil })
    return { sent: false, reason: 'paciente pausado' }
  }

  // Janela ativa do paciente (wake_time → bedtime do user_profiles).
  // Offsets + fallbacks editáveis via /settings/global → engagement.*
  const { data: profileTime } = await supabase
    .from('user_profiles')
    .select('wake_time, bedtime')
    .eq('user_id', userId)
    .maybeSingle()
  const window = activeWindow(
    (profileTime as { wake_time: string | null; bedtime: string | null } | null)?.wake_time,
    (profileTime as { wake_time: string | null; bedtime: string | null } | null)?.bedtime,
    engagementConfig,
  )
  if (!isWithinActiveWindow(localHour, window)) {
    await logEvent('engagement.skipped', {
      reason: 'fora da janela ativa do paciente',
      local_hour: localHour,
      window_start: window.start,
      window_end: window.end,
    })
    return { sent: false, reason: 'fora da janela ativa' }
  }

  // A1: já enviou engajamento hoje? Se sim, pula. (NÃO conta conversa do user.)
  //
  // BUG corrigido (2026-05-18): query usava `.gte('created_at', startOfDay)`
  // mas a coluna real em product_events é `occurred_at`. PostgREST ignorava
  // filtro de coluna inexistente → checagem sempre retornava 0 → bot enviava
  // engajamento em TODOS os 5 slots/dia. Gleidson recebeu 4 msgs em 16/05
  // (07h, 10h, 14h, 17h). Custo colateral: ~$1.75/dia de Haiku desperdiçado.
  const todayLocal = getLocalDate(userTimezone)
  const startOfDay = `${todayLocal}T00:00:00${tzOffset(userTimezone)}`
  const { count: engagementsToday } = await supabase
    .from('product_events')
    .select('id', { count: 'exact', head: true })
    .eq('user_id', userId)
    .eq('event', 'engagement.sent')
    .gte('occurred_at', startOfDay)

  if ((engagementsToday ?? 0) > 0) {
    await logEvent('engagement.skipped', {
      reason: 'engajamento já enviado hoje',
      engagements_today: engagementsToday,
    })
    return { sent: false, reason: 'engajamento já enviado hoje' }
  }

  // Se paciente já registrou refeição correspondente ao slot atual, pula.
  // Evita msgs constrangedoras tipo "café passou batido?" depois do paciente
  // ter acabado de registrar o café. Mapeamento slot → meal_type esperado:
  const SLOT_TO_MEAL_TYPE: Record<string, string | null> = {
    cafe_da_manha: 'cafe',
    meio_da_manha: 'lanche',
    almoco: 'almoco',
    pos_almoco: null, // só checkin de balanço, não meal-specific
    lanche_tarde: 'lanche',
    jantar: 'jantar',
    noite: null,
    madrugada: null,
  }
  const expectedMealType = SLOT_TO_MEAL_TYPE[slot] ?? null

  // REFATOR ENGAJAMENTO (Roberto 2026-05-18): se o slot é meal-specific,
  // só envia se a refeição é ESPERADA pelo padrão do paciente (últimos 14d).
  // Sem isso, paciente que faz jejum (sem café) recebia engajamento de café
  // toda manhã. Aproveita getMealPattern (já usado pelo gap-checker).
  if (expectedMealType) {
    const pattern = await getMealPattern(supabase, userId, userTimezone)
    // Só pula se pattern foi inferido (paciente tem histórico) E meal não
    // está em expected. Paciente novo (fallback) recebe normal pra não
    // ficar sem comunicação no início.
    if (
      !pattern.fallbackUsed &&
      !pattern.expected.has(expectedMealType as 'cafe' | 'almoco' | 'lanche' | 'jantar')
    ) {
      await logEvent('engagement.skipped', {
        reason: 'meal_type não está no padrão do paciente (últimos 14d)',
        slot,
        expected_meal_type: expectedMealType,
        pattern_active_days: pattern.activeDays,
      })
      return { sent: false, reason: `${expectedMealType} fora do padrão` }
    }

    // Se paciente já registrou esse meal_type hoje, pula (não cobra de novo).
    const todayLocalEarly = getLocalDate(userTimezone)
    const { data: snapEarly } = await supabase
      .from('daily_snapshots')
      .select('id')
      .eq('user_id', userId)
      .eq('date', todayLocalEarly)
      .maybeSingle()
    const snapIdEarly = (snapEarly as { id: string } | null)?.id ?? null
    if (snapIdEarly) {
      const { data: mealsForSlot } = await supabase
        .from('meal_logs')
        .select('id')
        .eq('user_id', userId)
        .eq('snapshot_id', snapIdEarly)
        .eq('meal_type', expectedMealType as 'cafe' | 'almoco' | 'lanche' | 'jantar')
        .limit(1)
      if (mealsForSlot && mealsForSlot.length > 0) {
        await logEvent('engagement.skipped', {
          reason: 'meal_type do slot já registrado hoje',
          slot,
          expected_meal_type: expectedMealType,
        })
        return { sent: false, reason: `${expectedMealType} já registrado hoje` }
      }
    }
  }

  // Carrega config do agente engajamento
  const { data: prompt } = await supabase
    .from('v_active_prompts')
    .select('*')
    .eq('stage', 'engajamento')
    .single()

  if (!prompt || !prompt.model || prompt.temperature == null) {
    return { sent: false, reason: 'sem prompt engajamento' }
  }

  // ECONOMIA DE TOKEN #1: filtra as regras do prompt pelo idioma do paciente
  // (mesmo helper do pipeline). Paciente pt-BR não carrega as duplicatas en/es.
  // Fallback pro prompt cheio da view se a query falhar.
  const filteredSystem =
    (await loadFilteredSystemPrompt(supabase, 'engajamento', userTyped?.locale)) ??
    prompt.system_prompt ??
    ''

  // Estado do user
  const { data: progress } = await supabase
    .from('user_progress')
    .select('*')
    .eq('user_id', userId)
    .maybeSingle()

  // Metas calóricas + balanço de hoje (snapshot do dia local).
  // Sem isso o LLM ALUCINA valores plausíveis ("2.500 kcal, 160g").
  const todayLocalDate = getLocalDate(userTimezone)
  const calcCfg = await loadCalcConfig(supabase)
  const targets = await loadDailyTargets(supabase, userId, calcCfg)
  const { data: snapToday } = await supabase
    .from('daily_snapshots')
    .select('calories_consumed, protein_g, carbs_g, fat_g, exercise_calories, daily_balance')
    .eq('user_id', userId)
    .eq('date', todayLocalDate)
    .maybeSingle()
  const consumedKcal = (snapToday as { calories_consumed?: number } | null)?.calories_consumed ?? 0
  const consumedProtein = (snapToday as { protein_g?: number } | null)?.protein_g ?? 0
  const exerciseKcal = (snapToday as { exercise_calories?: number } | null)?.exercise_calories ?? 0

  // Snapshot do dia anterior — pra "déficit de ontem" no engajamento da manhã.
  // BUG I1 (review adversarial 2026-06-15): a lógica manual via
  // new Date(`${todayLocal}T00:00:00${tzOffset(userTimezone)}`).setDate(-1)
  // estava ERRADA por -1 dia em timezones POSITIVOS (Asia/*, Australia/*,
  // etc) porque Node em UTC reinterpretava a data instanciada. Em prod Brasil
  // (-03:00) nunca disparou, mas é regressão latente. getLocalDateMinusDays
  // usa Intl.DateTimeFormat (timezone-aware) e bate em qualquer offset.
  const yesterdayLocalDate = getLocalDateMinusDays(userTimezone, 1)
  const { data: snapYesterday } = await supabase
    .from('daily_snapshots')
    .select('calories_consumed, calories_target, daily_balance, exercise_calories, day_status')
    .eq('user_id', userId)
    .eq('date', yesterdayLocalDate)
    .maybeSingle()
  const yesterdayBalance = (snapYesterday as { daily_balance?: number } | null)?.daily_balance
  // GUARD dia incompleto (Erika 2026-05-27): a Erika não registrou nada ontem
  // (consumido=0, day_status='pending_close'), mas daily_balance=0 → realDef=500
  // → a matinal disse "fechou com 500 kcal de déficit" + parabéns. Déficit
  // FABRICADO. Só afirmamos balanço de ontem se o dia teve consumo real E não
  // ficou incompleto/sem fechar (mesma régua do crédito do bloco no closer).
  const yConsumed = (snapYesterday as { calories_consumed?: number } | null)?.calories_consumed ?? 0
  const yStatus = (snapYesterday as { day_status?: string } | null)?.day_status
  const yTarget = (snapYesterday as { calories_target?: number } | null)?.calories_target ?? null
  const yExerciseY =
    (snapYesterday as { exercise_calories?: number } | null)?.exercise_calories ?? 0
  // BALANÇO DE COMIDA (consumido − meta, SEM exercício) — é o número que
  // o paciente vê como "Excedente/Restam" no card do dia. daily_balance
  // do snapshot é NET (com exercício) e serve só pra realDailyDeficit.
  // Misturar os dois é a "confusão nº 1 da história deste agente"
  // (CLAUDE.md). Bug Paulo 2026-06-17: msg disse "+460 kcal" (NET) onde
  // paciente esperava "+542" (COMIDA — diff de consumed-target=1579-1037).
  const yEating = yTarget != null ? yConsumed - yTarget : null

  // Déficit programado (embutido na meta) — pra calcular o déficit REAL de ontem.
  const { data: profileRow } = await supabase
    .from('user_profiles')
    .select('current_protocol, deficit_level')
    .eq('user_id', userId)
    .maybeSingle()
  const designDeficit =
    (profileRow as { current_protocol?: string | null } | null)?.current_protocol === 'recomposicao'
      ? ((profileRow as { deficit_level?: number | null } | null)?.deficit_level ?? 500)
      : 0

  // ── BUG I1 (Luciana 2026-06-14/15) ──
  // Engagement matinal aluc**inava sobre o fechamento de ontem ("saldo positivo",
  // "1º bloco completo", "dentro da meta") quando ontem foi SUB-REGISTRO, dia
  // INCOMPLETO ou EXCEDENTE. Causa: o LLM só recebia yesterdayLabel (positivo
  // quando havia balanço) ou "Sem dados de ontem" — sem distinguir os ramos
  // críticos. Agora consultamos bloco7700.skipped_* events do dia anterior e
  // montamos um VEREDITO objetivo que o LLM SÓ pode reportar (regra
  // inviolável no prompt — ver linha do "REGRA INVIOLÁVEL SOBRE ONTEM").
  const since36hIso = new Date(Date.now() - 36 * 60 * 60 * 1000).toISOString()
  const { data: evRawRow } = await supabase
    .from('product_events')
    .select('event, properties, occurred_at')
    .eq('user_id', userId)
    .in('event', [
      'bloco7700.skipped_subregistro',
      'bloco7700.skipped_incomplete_day',
      'bloco7700.skipped_inactive_day',
      'bloco7700.block_completed',
    ])
    .gte('occurred_at', since36hIso)
    .order('occurred_at', { ascending: false })
  const yEvents =
    (evRawRow as Array<{
      event: string
      properties: Record<string, unknown> | null
      occurred_at: string
    }> | null) ?? []
  const yEventByName = (name: string) =>
    yEvents.find(
      (e) =>
        e.event === name &&
        ((e.properties?.date ?? e.properties?.snapshot_date) as string | undefined) ===
          yesterdayLocalDate,
    )
  const skSub = yEventByName('bloco7700.skipped_subregistro')
  const skInc = yEventByName('bloco7700.skipped_incomplete_day')
  const skIna = yEventByName('bloco7700.skipped_inactive_day')
  const blkOk = yEventByName('bloco7700.block_completed')
  const anySkipped = !!(skSub || skInc || skIna)
  const isIncompleteStatus =
    yStatus === 'incomplete_no_response' || yStatus === 'pending_close'
  const isInactive = yConsumed <= 0
  // Audit 06-18 (bug Paulo): EXCEDENTE é definido pelo balanço de COMIDA
  // (consumed − target), não pelo NET (com exercício). Exercício acelera
  // o bloco mas NÃO converte excedente alimentar em "dentro da meta"
  // (CLAUDE.md — regra inviolável).
  const isOverTarget = typeof yEating === 'number' && yEating > 100

  // FIX #3 (Paulo 2026-05-20 11:17): o LLM recebia o balanço cru ("458 kcal,
  // negativo=déficit") e mesmo assim chamou +458 (superávit) de "déficit". Agora
  // o RÓTULO é decidido em código e entregue pronto — o LLM não decide o sinal.
  // Déficit REAL de ontem = vs MANUTENÇÃO (o que de fato emagrece e o bloco
  // credita), NÃO o saldo vs meta. Decisão Roberto 2026-05-22: comunicar o real
  // (ex: 897), não o 397; e creditar o exercício quando houve.
  let yesterdayLabel: string | null = null
  let yesterdayRealDef: number | null = null
  const yesterdayClosedOk =
    !anySkipped && yStatus === 'complete' && yConsumed > 0 && !isOverTarget
  if (yesterdayBalance != null && yesterdayClosedOk) {
    const realDef = Math.round(realDailyDeficit(designDeficit, yesterdayBalance))
    yesterdayRealDef = realDef
    const yExercise =
      (snapYesterday as { exercise_calories?: number } | null)?.exercise_calories ?? 0
    const treinoAjudou = yExercise > 0 ? ' — o treino ajudou a chegar nesse total' : ''
    yesterdayLabel =
      realDef > 50
        ? `déficit real de ${realDef} kcal vs manutenção (o que de fato emagrece e alimenta o bloco 7700)${treinoAjudou}`
        : realDef < -50
          ? `superávit de ${Math.abs(realDef)} kcal acima da manutenção (comeu mais do que gastou — NÃO chame de déficit)`
          : `praticamente em manutenção (${Math.abs(realDef)} kcal de diferença)`
  }

  // Veredito objetivo do dia anterior. Ordem de prioridade: skipped > inativo >
  // excedente > fechou OK > sem dados. O LLM SÓ pode usar essa string como
  // verdade sobre ontem — regra inviolável injetada abaixo no prompt.
  let yesterdayVerdict: string
  if (!snapYesterday) {
    yesterdayVerdict =
      `Ontem (${yesterdayLocalDate}): SEM DADOS — não fale como se o dia tivesse fechado. ` +
      `Convide o paciente a registrar hoje sem afirmar nada sobre ontem.`
  } else if (skSub) {
    const pct = (skSub.properties?.pct ?? skSub.properties?.completion_pct) as number | undefined
    yesterdayVerdict =
      `Ontem (${yesterdayLocalDate}): SUB-REGISTRO (consumido ${yConsumed} kcal vs meta ${yTarget ?? '?'} kcal` +
      (pct != null ? `, ${pct}%` : '') +
      `). O sistema NÃO creditou bloco 7700. ` +
      `NÃO fale "fechou bem" / "déficit" / "bloco completo". ` +
      `Convide a retomar hoje sem cobrar.`
  } else if (skInc || isIncompleteStatus) {
    yesterdayVerdict =
      `Ontem (${yesterdayLocalDate}): DIA INCOMPLETO (paciente não respondeu lembretes / fechamento parcial). ` +
      `O sistema NÃO creditou bloco. ` +
      `NÃO finja fechamento. Convide a retomar com leveza.`
  } else if (skIna || isInactive) {
    yesterdayVerdict =
      `Ontem (${yesterdayLocalDate}): SEM ATIVIDADE (zero registros). ` +
      `NÃO fale em "fechamento" nem "déficit". ` +
      `Reconheça que ontem foi inativo e convide a começar hoje.`
  } else if (isOverTarget && typeof yEating === 'number') {
    // Bug Paulo 2026-06-17 (audit 06-18): engagement disse "+460 kcal" usando
    // NET (com exercício); paciente lê como comida e estranha porque no card
    // ao vivo viu +542. Solução: comunicar SEMPRE yEating (consumed−target,
    // SEM exercício). Se houve treino, citar em frase SEPARADA com os dois
    // números sem somar (CLAUDE.md: "exercício acelera bloco, NÃO libera
    // comer mais").
    const treinoNota =
      yExerciseY > 0
        ? ` O treino compensou ${yExerciseY} kcal, mas o consumo passou ${yEating} kcal da meta — exercício acelera o bloco, não libera comer mais.`
        : ''
    yesterdayVerdict =
      `Ontem (${yesterdayLocalDate}): EXCEDENTE (consumiu ${yConsumed} kcal vs meta ${yTarget ?? '?'} kcal — comida +${yEating} kcal acima da meta).${treinoNota} ` +
      `NÃO chame de "dentro da meta" nem "déficit". ` +
      `Use SEMPRE o número da COMIDA (+${yEating}) ao falar do excedente — é o que o paciente vê no card. NÃO use o saldo NET (com exercício). ` +
      `Reconheça sem julgar e convide a retomar hoje.`
  } else if (yesterdayLabel != null) {
    yesterdayVerdict =
      `Ontem (${yesterdayLocalDate}): FECHOU OK — ${yesterdayLabel}` +
      (blkOk ? '. BLOCO 7700 FECHADO ontem (marco grande do método).' : '.')
  } else {
    yesterdayVerdict =
      `Ontem (${yesterdayLocalDate}): dados insuficientes — não invente fechamento.`
  }

  const targetKcal = targets.calories_target ?? '(não calculado — perfil incompleto)'
  const targetProtein = targets.protein_target ?? '(não calculado — perfil incompleto)'

  // REAVALIAÇÃO 14 DIAS (Roberto 2026-05-20): se o daily-closer marcou
  // `reevaluation.due` (não resolvida nas últimas 36h) E é o slot matinal,
  // injeta instrução pro LLM pedir o peso atualizado. Quando paciente responde
  // com peso, cadastra_dados_iniciais recalcula meta/protocolo automaticamente.
  // REAVALIAÇÃO 14 DIAS: o daily-closer marca `reevaluation.due`. ANTES a gente
  // injetava a instrução no prompt, mas o LLM IGNORAVA (Roberto 22/05 — mandou só
  // "bom dia" sem pedir o peso). AGORA só marcamos o flag e ANEXAMOS uma linha
  // fixa garantida ao final do texto (o LLM não decide se manda).
  // 2026-06-05: BUG observado Roberto recebeu reevaluação 04/06 E 05/06.
  // Causa: a query antiga só checava "tem reevaluation.due nas últimas 36h",
  // sem confirmar se já foi consumida. Como o evento .due fica disparado por
  // dias, toda manhã dentro da janela disparava reavaliação de novo. Fix: só
  // dispara se o .due mais recente ainda não tem .prompt_appended posterior.
  let reevaluationDue = false
  if (slot === 'cafe_da_manha') {
    const { data: dueEvents } = await supabase
      .from('product_events')
      .select('occurred_at')
      .eq('user_id', userId)
      .eq('event', 'reevaluation.due')
      .gte('occurred_at', new Date(Date.now() - 36 * 3600 * 1000).toISOString())
      .order('occurred_at', { ascending: false })
      .limit(1)
    const lastDueAt = ((dueEvents ?? []) as Array<{ occurred_at: string }>)[0]?.occurred_at
    if (lastDueAt) {
      const { data: appendedEvents } = await supabase
        .from('product_events')
        .select('id')
        .eq('user_id', userId)
        .eq('event', 'reevaluation.prompt_appended')
        .gte('occurred_at', lastDueAt)
        .limit(1)
      reevaluationDue = !appendedEvents || appendedEvents.length === 0
    }
  }

  // Eduardo 2026-06-03: destaca quando paciente fechou bloco novo na noite
  // anterior. daily-closer emite `bloco7700.block_completed` quando
  // blocks_completed incrementa. Engagement matinal seguinte pega + injeta no
  // contexto pro LLM mencionar com destaque (marco do método MPP).
  // 2026-06-04: gate era `slot === 'manha'` mas esse slot não existe na config
  // (slots reais: cafe_da_manha, meio_da_manha, almoco, ...). Bug detectado no
  // Bom dia do Roberto 04/06 que omitiu os 3 blocos acumulados.
  let blockCompletedHighlight = ''
  if (slot === 'cafe_da_manha' || slot === 'meio_da_manha') {
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    const { data: blockEvents } = await (supabase as any)
      .from('product_events')
      .select('properties')
      .eq('user_id', userId)
      .eq('event', 'bloco7700.block_completed')
      .gte('occurred_at', new Date(Date.now() - 24 * 60 * 60 * 1000).toISOString())
      .order('occurred_at', { ascending: false })
      .limit(1)
    const be = (blockEvents?.[0]?.properties ?? null) as {
      new_count?: number
      previous_count?: number
    } | null
    if (be?.new_count && be.new_count > (be.previous_count ?? 0)) {
      // Modo "fechou ontem" — celebração forte
      blockCompletedHighlight = `\n\n🎉 MARCO IMPORTANTE: o paciente FECHOU O ${be.new_count}º BLOCO DO 7700 ontem (acumulou ${be.new_count} × 7.700 kcal de déficit líquido, equivalente a ~${be.new_count} kg de gordura no modelo MPP). DESTAQUE isso na mensagem matinal — celebra de verdade, ancora identidade ("você está construindo isso há ${be.new_count} blocos"), MAS SEM exagero (não invente número de kg perdido na balança — é estimativa do modelo, não medição). Use só uma linha bem feita, não vire palestra. NUNCA invente outro número (% gordura, kg balança) — só o número de blocos é o destaque.`
    } else {
      // Modo "acumulado" (Roberto 2026-06-03): se NÃO fechou bloco novo ontem
      // MAS já tem ≥1 bloco fechado, MENCIONA no Bom dia como marco de
      // constância (uma linha discreta). Antes o Haiku às vezes ignorava
      // (caso real: Roberto 3 blocos sem menção no engagement).
      const blocksAcumulados = (progress as { blocks_completed?: number } | null)?.blocks_completed ?? 0
      if (blocksAcumulados >= 1) {
        blockCompletedHighlight = `\n\nDESTAQUE OBRIGATÓRIO: o paciente já tem **${blocksAcumulados} bloco(s) completo(s) do 7700** acumulado(s) (~${blocksAcumulados} kg de gordura no modelo MPP — estimativa do método, NÃO inventar número de balança). Mencione esse marco no Bom dia como prova de constância — UMA linha curta, sem virar palestra. NÃO invente outro número (% gordura, kg medido). Se já mencionou em mensagens anteriores, varie a forma (não repete a mesma frase todo dia).`
      }
    }
  }

  // Sugestão de frase de continuidade do banco curado (Roberto 2026-06-13).
  // LRU + sorteio entre as 20 menos usadas pra evitar repetição. Não força:
  // LLM pode usar/adaptar/ignorar. Reduz custo de generation e mantém Roberto
  // no controle do tom.
  //
  // SLOT MAPPING (review 4 medium):
  //   - cafe_da_manha/meio_da_manha → ['morning', 'continuity', 'any']
  //   - QUALQUER slot quando exerciseKcal > 0 → adiciona 'workout' (libera as 12
  //     frases de movimento que ficavam órfãs antes)
  //   - demais slots → ['continuity', 'any']
  let motivationalSuggestion = ''
  let pickedPhraseId: string | null = null
  try {
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    const sp = supabase as any
    const eligibleSlots: string[] =
      slot === 'cafe_da_manha' || slot === 'meio_da_manha'
        ? ['morning', 'continuity', 'any']
        : ['continuity', 'any']
    if (typeof exerciseKcal === 'number' && exerciseKcal > 0) {
      eligibleSlots.push('workout')
    }
    // Tiebreak por id quando last_used_at empata (jitter inicial já atenua,
    // mas o tiebreak protege rotação após gerações futuras).
    const { data: phrases } = await sp
      .from('engagement_phrases')
      .select('id, phrase, picked_count')
      .eq('active', true)
      .eq('language', userLanguage)
      .in('slot', eligibleSlots)
      .order('last_used_at', { ascending: true, nullsFirst: true })
      .order('id', { ascending: true })
      .limit(20)
    let pool = (phrases ?? []) as Array<{ id: string; phrase: string; picked_count: number }>
    // Cooldown user×phrase (7 dias) — review high #3 do audit.
    if (pool.length > 0) {
      const cooldownSince = new Date(Date.now() - 7 * 24 * 3600 * 1000).toISOString()
      const phraseIds = pool.map((p) => p.id)
      const { data: recent } = await sp
        .from('user_phrase_cooldown')
        .select('phrase_id')
        .eq('user_id', userId)
        .eq('phrase_table', 'engagement')
        .gte('last_seen_at', cooldownSince)
        .in('phrase_id', phraseIds)
      const seenIds = new Set((recent ?? []).map((r: { phrase_id: string }) => r.phrase_id))
      const notRecent = pool.filter((p) => !seenIds.has(p.id))
      if (notRecent.length > 0) pool = notRecent
    }
    if (pool.length > 0) {
      // Sorteio determinístico (review medium): retries inngest re-executam
      // step.run em throw, Math.random pegaria frase diferente. Hash por
      // (userId + slot + date) — mesma frase no retry, rotação por dia.
      const dayKey = new Date().toISOString().slice(0, 10)
      const seedStr = `${userId}|${slot}|${dayKey}`
      let seed = 0
      for (let i = 0; i < seedStr.length; i++) seed = (seed * 31 + seedStr.charCodeAt(i)) & 0xffffffff
      const picked = pool[Math.abs(seed) % Math.min(pool.length, 5)]
      if (picked) {
        motivationalSuggestion = picked.phrase
        pickedPhraseId = picked.id
        // Incrementa picked_count + atualiza last_used_at imediatamente.
        // used_count fica pra depois (substring match no texto final do LLM).
        await sp
          .from('engagement_phrases')
          .update({
            picked_count: picked.picked_count + 1,
            last_used_at: new Date().toISOString(),
          })
          .eq('id', picked.id)
        // Cooldown user×phrase (engagement)
        await sp.from('user_phrase_cooldown').upsert(
          {
            user_id: userId,
            phrase_table: 'engagement',
            phrase_id: picked.id,
            last_seen_at: new Date().toISOString(),
          },
          { onConflict: 'user_id,phrase_table,phrase_id' },
        )
      }
    }
  } catch (err) {
    // eslint-disable-next-line no-console
    console.warn('[engagement] falha ao buscar frase curada (segue sem):', err)
  }
  const motivationalLine = motivationalSuggestion
    ? `\n\n💡 SUGESTÃO de frase de continuidade do banco curado do Roberto (use TEXTUALMENTE OU ADAPTE se encaixar naturalmente; se não couber no fluxo, ignore): "${motivationalSuggestion}"`
    : ''

  // C: contexto rico pro LLM — hora local + REFEIÇÃO típica + DADOS REAIS do paciente
  const userContext = `
⚠️ IDIOMA DO PACIENTE: **${userLanguage}** (locale salvo). Responda nesse idioma. Não infira pelo timezone — paciente pode morar fora mas falar outra língua.
País do paciente: ${userCountry}
Nome: ${userTyped?.name ?? '(sem nome)'}
Hora local do paciente: ${String(localHour).padStart(2, '0')}:00 (timezone ${userTimezone})
Período do dia: ${slot}
Refeição típica desse horário: ${mealHint}

DADOS REAIS DO DIA — USE ESTES VALORES, NÃO INVENTE:
- Meta calórica de hoje: ${targetKcal} kcal
- Meta de proteína de hoje: ${targetProtein}${typeof targetProtein === 'number' ? ' g' : ''}
- Consumido até agora: ${consumedKcal} kcal | ${consumedProtein} g proteína
- Exercício hoje: ${exerciseKcal} kcal queimadas
- ${yesterdayVerdict}

Sequência atual: ${progress?.current_streak ?? 0} dias consecutivos
XP: ${progress?.xp_total ?? 0} (nível ${progress?.level ?? 1})
Última atividade: ${progress?.last_active_date ?? 'nunca'}
Blocos completos: ${progress?.blocks_completed ?? 0}

⚠️ REGRA INVIOLÁVEL SOBRE ONTEM (bug I1 — Luciana 2026-06-14/15): se a linha "Ontem" acima disser SUB-REGISTRO, DIA INCOMPLETO, SEM ATIVIDADE, EXCEDENTE ou SEM DADOS, você está PROIBIDO de dizer "fechou bem", "saldo positivo", "bloco completo", "dentro da meta", "déficit" ou qualquer coisa que sugira sucesso no fechamento de ontem. SÓ celebre fechamento quando a linha disser FECHOU OK.

⚠️ IMPORTANTE: ao escrever a mensagem, use SOMENTE português. Não use "streak" (escreva "sequência" ou "dias consecutivos"). Não use "level" (escreva "nível"). Não use "workout/mindset/timing/boost/craving" ou qualquer palavra em inglês. Tradução obrigatória — veja a regra idioma-do-paciente.${blockCompletedHighlight}${motivationalLine}
`.trim()

  const result = await llm.complete({
    model: prompt.model,
    systemPrompt: filteredSystem,
    messages: [
      {
        role: 'user',
        content:
          `${userContext}\n\nGere uma mensagem curta e motivacional pra esse momento. ` +
          `Use a hora local e a refeição típica acima — NÃO assuma horário pelo nome do slot.`,
      },
    ],
    temperature: Number(prompt.temperature),
    // max_tokens vem de agent_configs (editável em /settings/agents).
    // Fallback 500 só quando registro não tem o campo (não deveria ocorrer).
    maxTokens: Number(prompt.max_tokens ?? 500),
    userId,
    metadata: { Stage: 'engajamento', Slot: slot, LocalHour: String(localHour) },
  })

  let text = (result.content ?? '').trim()
  if (!text) {
    await logEvent('engagement.skipped', { reason: 'LLM vazio' })
    return { sent: false, reason: 'LLM vazio' }
  }

  // ANTI-ALUCINAÇÃO no engagement (Roberto 2026-05-20 / 2026-05-25): o "Bom dia"
  // do Haiku disse "saldo de 5.029 kcal no bloco" quando o real era 5.586; e
  // depois "2.958 / 7.700 (38%)" quando o real era 1.235. O engagement-sender
  // não passa pelo pipeline.ts (que tem o card canônico + reconciliação), então
  // o NÚMERO DO BLOCO que o LLM escreve aqui ficava SEM validação contra o banco.
  // Fix (E): o número do bloco vira DETERMINÍSTICO igual aos outros rótulos
  // (realDailyDeficit, yesterdayLabel) — vem do user_progress.deficit_block, não
  // do LLM. reconcileBlocoMention substitui qualquer menção pelo valor canônico
  // (com % recalculado); se o texto não menciona bloco, fica inalterado.
  const progDeficitBlock = (progress as { deficit_block?: number } | null)?.deficit_block
  if (progDeficitBlock != null) {
    const before = text
    text = reconcileBlocoMention(before, { deficitBlock: progDeficitBlock })
    if (text !== before) {
      // Evento de auditoria do fix (E): a auditoria mede quantas vezes o número
      // alucinado do bloco precisou ser corrigido pelo valor do banco (old/new).
      await logEvent('engagement.bloco_reconciled', {
        context: 'engagement',
        deficit_block: progDeficitBlock,
        blocks_completed: (progress as { blocks_completed?: number } | null)?.blocks_completed ?? 0,
        old: before,
        new: text,
      })
      // Mantém o evento legado pra contagem no daily-audit (llm.loose_bloco_replaced).
      await logEvent('llm.loose_bloco_replaced', {
        context: 'engagement',
        replacements: 1,
      })
    }
  }

  // FIX #3 (guard): se mesmo com o rótulo pronto o LLM inverter déficit/superávit
  // na prosa, corrige antes de enviar. Usa o DÉFICIT REAL vs manutenção (não o
  // daily_balance vs meta) — Paulo 2026-05-27: daily_balance +119 = "excedente"
  // vs meta, mas realDef +381 = déficit real; o LLM escreveu "excedente de 119
  // real" e o reconciliador-por-saldo NÃO pegava (pior: corromperia o correto
  // "déficit real de 381"). reconcileRealDeficitProse valida pelo realDef.
  if (yesterdayRealDef != null) {
    const balFix = reconcileRealDeficitProse(text, yesterdayRealDef)
    if (balFix.replacements > 0) {
      text = balFix.text
      await logEvent('llm.balance_prose_reconciled', {
        context: 'engagement',
        replacements: balFix.replacements,
        real_deficit: yesterdayRealDef,
        daily_balance: yesterdayBalance ?? null,
      })
    }
  }

  // ── BUG I1 hallucination guard (review adversarial 2026-06-15) ──
  // Quando o veredito de ontem é negativo (SUB-REGISTRO / DIA INCOMPLETO /
  // SEM ATIVIDADE / EXCEDENTE / SEM DADOS), a regra no prompt PROÍBE o LLM
  // de celebrar fechamento. Mas Haiku às vezes ignora regras "PROIBIDO" no
  // prompt (~5-10% das gerações). Hard-guard pós-LLM: escaneia frases
  // proibidas no texto e, se achar, substitui por fallback determinístico
  // (mesmo padrão do reconcileBlocoMention).
  const verdictIsNegative =
    yesterdayVerdict.startsWith('Ontem') &&
    (yesterdayVerdict.includes('SUB-REGISTRO') ||
      yesterdayVerdict.includes('DIA INCOMPLETO') ||
      yesterdayVerdict.includes('SEM ATIVIDADE') ||
      yesterdayVerdict.includes('EXCEDENTE') ||
      yesterdayVerdict.includes('SEM DADOS') ||
      yesterdayVerdict.includes('dados insuficientes'))
  if (verdictIsNegative) {
    // Padrões que indicam alucinação de fechamento positivo. Case-insensitive.
    const HALLUCINATION_RE =
      /\b(fechou\s+(bem|com\s+deficit|com\s+saldo|dentro\s+da\s+meta)|saldo\s+positivo|bloco(?:\s+(?:de\s+7\.?700)?)?\s+(?:completo|fechado)|completou\s+(?:o\s+)?bloco|dentro\s+da\s+meta|deficit\s+real\s+de|deficit\s+de\s+\d|superavit|excedeu\s+a\s+meta\s+e\s+ainda\s+assim)/i
    const noAccent = text.normalize('NFD').replace(/\p{Diacritic}/gu, '')
    if (HALLUCINATION_RE.test(noAccent)) {
      const fallback =
        yesterdayVerdict.includes('SUB-REGISTRO')
          ? 'Bom dia! Ontem ficou só com registro parcial — o que importa é retomar hoje sem cobrar. Manda o que comer, vamos juntos.'
          : yesterdayVerdict.includes('DIA INCOMPLETO')
            ? 'Bom dia! Ontem o dia ficou em aberto — sem drama, hoje a gente retoma o ritmo. Manda o primeiro registro quando comer.'
            : yesterdayVerdict.includes('SEM ATIVIDADE')
              ? 'Bom dia! Ontem foi um dia parado por aqui — acontece. Hoje a gente recomeça: manda o primeiro registro quando comer.'
              : yesterdayVerdict.includes('EXCEDENTE')
                ? 'Bom dia! Ontem o consumo passou um pouco da meta — sem julgar, faz parte. Hoje a gente retoma; manda os registros e seguimos.'
                : 'Bom dia! Sobre ontem não tenho dados certos pra comentar. Hoje recomeçamos do zero — manda o primeiro registro quando comer.'
      await logEvent('engagement.hallucinated_closure', {
        verdict: yesterdayVerdict.slice(0, 200),
        original_preview: text.slice(0, 300),
        replaced_with: 'deterministic_fallback',
      })
      text = fallback
    }
  }

  // REAVALIAÇÃO 14 DIAS — linha DETERMINÍSTICA (Roberto 2026-05-22). O LLM
  // ignorava a instrução injetada no prompt; agora o pedido de peso é GARANTIDO.
  // Anexa só no slot matinal quando o daily-closer marcou reevaluation.due.
  if (reevaluationDue) {
    // Script oficial do manual por protocolo (peso + 3 fotos + Q3 específica:
    // fome/treinos/atividade). Antes pedia "peso e BF%/medidas" — fora do manual.
    // Roberto 2026-06-03: adiciona Q4 OPCIONAL "sua meta de peso continua sendo
    // Xkg ou mudou?" — só se paciente já tem meta de peso definida
    // (goal_type='peso_kg'). Reusa tool define_meta_peso pra processar resposta.
    const proto = (profileRow as { current_protocol?: string | null } | null)
      ?.current_protocol as 'recomposicao' | 'ganho_massa' | 'manutencao' | null | undefined
    const profTyped = profileRow as {
      goal_type?: string | null
      goal_value?: number | null
    } | null
    const currentTargetWeightKg =
      profTyped?.goal_type === 'peso_kg' && typeof profTyped?.goal_value === 'number'
        ? Number(profTyped.goal_value)
        : null
    text += '\n\n' + reevaluationKickoff(proto, { currentTargetWeightKg })
    await logEvent('reevaluation.prompt_appended', {
      slot,
      protocol: proto ?? null,
      has_target_weight: currentTargetWeightKg != null,
    })
  }

  // ENVIA pelo WhatsApp via messaging provider
  const messaging = createMessagingProvider({
    MESSAGING_PROVIDER: process.env.MESSAGING_PROVIDER ?? 'whatsapp_cloud',
    META_PHONE_NUMBER_ID: process.env.META_PHONE_NUMBER_ID,
    META_ACCESS_TOKEN: process.env.META_ACCESS_TOKEN,
    META_APP_SECRET: process.env.META_APP_SECRET,
    META_VERIFY_TOKEN: process.env.META_VERIFY_TOKEN,
  })

  // Humanizer params editáveis via /settings/global → humanizer.*
  const humanizer = await loadHumanizerConfig(supabase)

  // Áudio motivacional: probabilidade configurável (default 25%). Roberto pediu
  // (2026-05-15) que nem todo engajamento seja texto — "de vez em quando" áudio
  // dá um tom mais humano nas mensagens motivacionais.
  // Configurável em global_config.engagement.audio_probability (0.0 a 1.0).
  const { data: audioProbRow } = await supabase
    .from('global_config')
    .select('value')
    .eq('key', 'engagement.audio_probability')
    .maybeSingle()
  const audioProbabilityRaw =
    (audioProbRow as { value?: unknown } | null)?.value ?? 0.25
  const audioProbability =
    typeof audioProbabilityRaw === 'number'
      ? audioProbabilityRaw
      : Number(audioProbabilityRaw) || 0.25
  const elevenlabsKey = await loadCredential(supabase, 'ELEVENLABS_API_KEY', 'elevenlabs', 'api_key')
  const elevenlabsVoice = await loadCredential(supabase, 'ELEVENLABS_VOICE_ID', 'elevenlabs', 'voice_id')
  const canSendAudio = !!elevenlabsKey && !!elevenlabsVoice
  const sendAsAudio = canSendAudio && Math.random() < audioProbability

  let deliveryStatus: 'sent' | 'failed' = 'sent'
  let deliveryError: string | undefined
  let contentType: 'text' | 'audio' = 'text'
  let ttsMediaId: string | undefined

  // Detecta se LLM aproveitou a sugestão curada — ANTES do branch
  // audio/texto (review low: detector estava só no else=texto, ~25% das
  // execuções com audio_probability default subestimavam used_count).
  if (pickedPhraseId && motivationalSuggestion && text) {
    const needle = motivationalSuggestion.slice(0, 30).toLowerCase()
    const usedInText = needle.length >= 15 && text.toLowerCase().includes(needle)
    if (usedInText) {
      try {
        // eslint-disable-next-line @typescript-eslint/no-explicit-any
        const sp = supabase as any
        const { data: cur } = await sp
          .from('engagement_phrases')
          .select('used_count')
          .eq('id', pickedPhraseId)
          .maybeSingle()
        await sp
          .from('engagement_phrases')
          .update({ used_count: (cur?.used_count ?? 0) + 1 })
          .eq('id', pickedPhraseId)
      } catch {
        // ignora
      }
    }
  }

  try {
    if (sendAsAudio) {
      contentType = 'audio'
      // TTS via ElevenLabs (com fallback pra Cartesia se configurado)
      const cartesiaKey = await loadCredential(supabase, 'CARTESIA_API_KEY', 'cartesia', 'api_key')
      const cartesiaVoice = await loadCredential(supabase, 'CARTESIA_VOICE_ID', 'cartesia', 'voice_id')
      const tts = new TTSRouter({
        elevenlabs: { apiKey: elevenlabsKey!, voiceId: elevenlabsVoice! },
        cartesia:
          cartesiaKey && cartesiaVoice
            ? { apiKey: cartesiaKey, voiceId: cartesiaVoice }
            : undefined,
      })
      const { llm } = createWorkerDeps()
      const speechText = await rewriteForTTS(llm, text).catch(() => text)
      const { result: ttsResult, provider: ttsProvider } = await tts.synthesize(speechText, 'standard')
      const blob = new Blob([new Uint8Array(ttsResult.audio)], { type: ttsResult.mimeType })
      const mediaId = await messaging.uploadMedia(blob, ttsResult.mimeType)
      ttsMediaId = mediaId
      const sendResult = await messaging.sendAudio(wpp, mediaId)
      if (sendResult.status !== 'sent') {
        deliveryStatus = 'failed'
        deliveryError = sendResult.error
      }
      // Loga evento TTS
      await supabase.from('product_events').insert({
        user_id: userId,
        event: deliveryStatus === 'sent' ? 'tts.generated' : 'tts.failed',
        properties: {
          context: 'engagement',
          slot,
          tts_provider: ttsProvider,
          tts_latency_ms: ttsResult.durationMs,
          chars: speechText.length,
          media_id: mediaId,
        },
      })
    } else {
      const sendResults = await sendHumanized(messaging, wpp, text, {
        showTyping: false,
        minDelay: humanizer.min_delay_ms,
        maxDelay: humanizer.max_delay_ms,
        charsPerSecond: humanizer.chars_per_second,
      })
      if (sendResults.some((r) => r.status !== 'sent')) {
        deliveryStatus = 'failed'
        deliveryError = sendResults.find((r) => r.error)?.error
      }
    }
  } catch (e) {
    deliveryStatus = 'failed'
    deliveryError = e instanceof Error ? e.message : String(e)
  }

  // Persiste OUT (com delivery_status real)
  await supabase.from('messages').insert({
    user_id: userId,
    direction: 'out',
    role: 'assistant',
    content_type: contentType,
    content: text,
    media_url: ttsMediaId ?? null,
    provider: process.env.MESSAGING_PROVIDER ?? 'whatsapp_cloud',
    agent_stage: 'engajamento',
    model_used: result.model,
    prompt_tokens: result.promptTokens,
    completion_tokens: result.completionTokens,
    cost_usd: result.costUsd,
    latency_ms: result.latencyMs,
    delivery_status: deliveryStatus,
    delivery_error: deliveryError ? { msg: deliveryError } : null,
    raw_payload: { engagement_slot: slot },
  })

  await logEvent(deliveryStatus === 'sent' ? 'engagement.sent' : 'engagement.failed', {
    chars: text.length,
    cost_usd: result.costUsd,
    model: result.model,
    error: deliveryError,
  })

  return { sent: deliveryStatus === 'sent', reason: deliveryError }
}

/**
 * Janela ativa do paciente, derivada de wake_time/bedtime do user_profiles.
 *
 * Política (offsets editáveis via /settings/global → engagement.*):
 *   - start = wake_time + engagement.wake_offset_min  (default 60min)
 *   - end   = bedtime  - engagement.bed_offset_min   (default 60min)
 *   - sem wake → engagement.fallback_wake_hour (default 6h)
 *   - sem bed  → engagement.fallback_bed_hour  (default 22h)
 *   - suporta janelas que cruzam meia-noite (plantonistas: dorme 04h, acorda 12h)
 */
interface ActiveWindow {
  start: number // hora inteira inclusive
  end: number // hora inteira exclusive
  crossesMidnight: boolean
}

interface SlotDef {
  until_hour: number
  slot: string
  meal_hint: string
  /** Se false, NUNCA envia engajamento nesse slot mesmo quando a janela
   * ativa do paciente permitir. Default true. Usado pra slots de "madrugada"
   * e "noite" — Amanda 2026-05-16 recebeu engajamento às 04:07 BRT porque
   * o wake_time dela tava 03:00 (erro provável no onboarding) → janela ativa
   * virou 04h-20h → slot=madrugada caiu dentro → enviou. meal_hint dizia
   * "não envia" mas era só string, ninguém checava. */
  silent?: boolean
}

interface EngagementConfig {
  wake_offset_min: number
  bed_offset_min: number
  fallback_wake_hour: number
  fallback_bed_hour: number
  slots: SlotDef[]
}

const DEFAULT_SLOTS: SlotDef[] = [
  { until_hour: 6, slot: 'madrugada', meal_hint: 'madrugada — não envia', silent: true },
  { until_hour: 9, slot: 'cafe_da_manha', meal_hint: 'café da manhã (jejum, primeira refeição do dia)' },
  { until_hour: 11, slot: 'meio_da_manha', meal_hint: 'meio da manhã (lanche entre café e almoço, ou check-in pré-almoço)' },
  { until_hour: 14, slot: 'almoco', meal_hint: 'almoço (refeição principal do meio-dia)' },
  { until_hour: 16, slot: 'pos_almoco', meal_hint: 'pós-almoço (digestão, balanço parcial do dia)' },
  { until_hour: 19, slot: 'lanche_tarde', meal_hint: 'lanche da tarde (entre almoço e jantar)' },
  { until_hour: 22, slot: 'jantar', meal_hint: 'jantar (última refeição do dia)' },
  { until_hour: 24, slot: 'noite', meal_hint: 'noite — não envia', silent: true },
]

const DEFAULT_ENGAGEMENT_CONFIG: EngagementConfig = {
  wake_offset_min: 60,
  bed_offset_min: 60,
  fallback_wake_hour: 6,
  fallback_bed_hour: 22,
  slots: DEFAULT_SLOTS,
}

function activeWindow(
  wakeTime: string | null | undefined,
  bedtime: string | null | undefined,
  config: EngagementConfig,
): ActiveWindow {
  const wake = parseHour(wakeTime, config.fallback_wake_hour)
  const bed = parseHour(bedtime, config.fallback_bed_hour)
  const wakeOffsetH = config.wake_offset_min / 60
  const bedOffsetH = config.bed_offset_min / 60
  // Arredonda pra hora inteira mais próxima (round half-up)
  const start = Math.round((wake + wakeOffsetH + 24) % 24)
  const end = Math.round((bed - bedOffsetH + 24) % 24)
  const crossesMidnight = start > end
  return { start, end, crossesMidnight }
}

function isWithinActiveWindow(hour: number, w: ActiveWindow): boolean {
  if (w.crossesMidnight) {
    // janela cruza 00h: fora dela é só [end, start)
    return hour >= w.start || hour < w.end
  }
  return hour >= w.start && hour < w.end
}

/**
 * Carrega config do engagement (offsets + fallbacks + slots) do global_config.
 * Cache 60s — mudanças via UI propagam em ≤1min.
 */
let cachedEngagementConfig: { config: EngagementConfig; expiresAt: number } | null = null
const ENGAGEMENT_CACHE_TTL_MS = 60_000

async function loadEngagementConfig(
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  svc: any,
): Promise<EngagementConfig> {
  const now = Date.now()
  if (cachedEngagementConfig && cachedEngagementConfig.expiresAt > now) {
    return cachedEngagementConfig.config
  }

  const { data, error } = (await svc
    .from('global_config')
    .select('key, value')
    .like('key', 'engagement.%')) as { data: Array<{ key: string; value: unknown }> | null; error: unknown }

  if (error || !data || data.length === 0) {
    cachedEngagementConfig = {
      config: DEFAULT_ENGAGEMENT_CONFIG,
      expiresAt: now + ENGAGEMENT_CACHE_TTL_MS,
    }
    return DEFAULT_ENGAGEMENT_CONFIG
  }

  const merged: EngagementConfig = { ...DEFAULT_ENGAGEMENT_CONFIG, slots: [...DEFAULT_SLOTS] }
  for (const row of data) {
    const subKey = row.key.replace(/^engagement\./, '')
    if (subKey === 'slots' && Array.isArray(row.value)) {
      // Valida shape básico antes de aceitar
      const slots = (row.value as unknown[]).filter(
        (s): s is SlotDef =>
          typeof s === 'object' &&
          s !== null &&
          typeof (s as SlotDef).until_hour === 'number' &&
          typeof (s as SlotDef).slot === 'string' &&
          typeof (s as SlotDef).meal_hint === 'string',
      )
      if (slots.length > 0) merged.slots = slots
    } else if (subKey in DEFAULT_ENGAGEMENT_CONFIG && subKey !== 'slots') {
      const num = Number(row.value)
      if (Number.isFinite(num)) {
        ;(merged as unknown as Record<string, number>)[subKey] = num
      }
    }
  }

  cachedEngagementConfig = { config: merged, expiresAt: now + ENGAGEMENT_CACHE_TTL_MS }
  return merged
}

/**
 * Resolve slot + meal_hint pra hora local atual usando config dinâmico.
 * Percorre slots (ordenados por until_hour ASC) e retorna o 1º cuja
 * until_hour > hour. Fallback pro último.
 */
function resolveSlot(hour: number, slots: SlotDef[]): { slot: string; meal_hint: string; silent: boolean } {
  // Ordena defensivamente — se admin mexer e desordenar, ainda funciona
  const sorted = [...slots].sort((a, b) => a.until_hour - b.until_hour)
  for (const s of sorted) {
    if (hour < s.until_hour) return { slot: s.slot, meal_hint: s.meal_hint, silent: s.silent ?? false }
  }
  const last = sorted[sorted.length - 1]
  return last
    ? { slot: last.slot, meal_hint: last.meal_hint, silent: last.silent ?? false }
    : { slot: 'desconhecido', meal_hint: '', silent: false }
}

function parseHour(timeStr: string | null | undefined, fallback: number): number {
  if (!timeStr) return fallback
  const m = timeStr.match(/^(\d{1,2})/)
  if (!m || !m[1]) return fallback
  const h = Number(m[1])
  return Number.isFinite(h) && h >= 0 && h <= 23 ? h : fallback
}

// Helpers de timezone agora vêm de @mpp/agent (timezone-utils.ts).
const getLocalDate = getLocalDateString
const tzOffset = getTzOffset
