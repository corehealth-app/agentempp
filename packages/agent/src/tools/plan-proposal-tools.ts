/**
 * Propostas de plano pelo Flow (C4 da beta funcional).
 *
 * `propoe_plano_treino` e `propoe_plano_dieta` usam os mesmos geradores, as
 * mesmas validações e os mesmos limites de `gera_treino`/`gera_dieta`, mas
 * gravam SOMENTE um rascunho (`create_plan_draft_atomic`). Nada aqui grava em
 * `training_plans` ou `prescriptions`, e não existe ferramenta que confirme:
 * o rascunho só vira plano quando o paciente confirma no app.
 *
 * Audit 2026-10-10: os textos da sugestão de TREINO passam, uma vez e antes de
 * gravar, pelo vocabulário fechado de linguagem simples do Flow
 * (`../flow-plain-training-language.ts`): números e estrutura não mudam. A
 * sugestão de cardápio não passa por ele.
 */
import type { z } from 'zod'
import { loadCalcConfig } from '../calc-config-loader.js'
import { loadDailyTargets } from '../calc-targets.js'
import {
  bindMobileFlowClinicalPort,
  flowClinicalProposalAllowed,
  type MobileFlowClinicalPort,
} from '../flow-current-clinical.js'
import { projectFlowPlainTrainingDraft } from '../flow-plain-training-language.js'
import { assessPlanDraftPayload, type PlanDraftDomain } from '../plan-draft.js'
import { nutritionSuggestionText, trainingSuggestionText } from '../plan-suggestion-text.js'
import type { ToolContext, ToolDefinition } from './types.js'

export const PROPOSE_TRAINING_PLAN_TOOL = 'propoe_plano_treino'
export const PROPOSE_DIET_PLAN_TOOL = 'propoe_plano_dieta'

const REQUEST_KEY_PATTERN = /^[A-Za-z0-9._:/-]{8,200}$/

interface DraftOutcome {
  id: string
  status: string
  inserted: boolean
  /** O conteúdo gravado, que é o que o paciente revisa. */
  payload: Record<string, unknown> | null
}

interface StoredDraft {
  id: string
  status: string
  payload?: unknown
}

// biome-ignore lint/suspicious/noExplicitAny: cliente sem tipos gerados para as tabelas novas
type Untyped = any

function requestKey(ctx: ToolContext, tool: string): string | null {
  const turn = ctx.providerMessageId
  if (!turn) return null
  const key = `${turn}:${tool}`
  return REQUEST_KEY_PATTERN.test(key) ? key : null
}

async function existingDraft(
  ctx: ToolContext,
  key: string,
  domain: PlanDraftDomain,
  clinical?: MobileFlowClinicalPort,
): Promise<StoredDraft | null> {
  if (clinical) {
    if (!clinical.drafts) throw new Error('Current Flow draft writer unavailable')
    return clinical.drafts.lookup({ domain, requestKey: key })
  }
  const { data, error } = await (ctx.supabase as Untyped)
    .from('plan_drafts')
    .select('id, status, payload')
    .eq('user_id', ctx.userId)
    .eq('request_key', key)
    .maybeSingle()
  if (error) throw new Error('plan draft lookup failed')
  return data ?? null
}

/** A draft of this turn the patient can no longer review is said as such. */
function closedDraft(draft: { status: string }): Record<string, unknown> | null {
  if (draft.status === 'needs_completion' || draft.status === 'ready_for_review') return null
  return {
    success: false,
    retry_tool: false,
    error:
      'A sugestão criada neste turno não está mais disponível para revisão. Explique isso ao paciente e ofereça criar outra em uma nova mensagem. Não apresente um plano.',
  }
}

async function turnMessageId(ctx: ToolContext): Promise<string | null> {
  if (!ctx.providerMessageId) return null
  const { data } = await (ctx.supabase as Untyped)
    .from('messages')
    .select('id')
    .eq('user_id', ctx.userId)
    .eq('provider', 'mobile_flow')
    .eq('provider_message_id', ctx.providerMessageId)
    .maybeSingle()
  return typeof data?.id === 'string' ? data.id : null
}

async function recentEvents(ctx: ToolContext, events: string[], hours: number): Promise<number> {
  const since = new Date(Date.now() - hours * 3600 * 1000).toISOString()
  const { data, error } = await (ctx.supabase as Untyped)
    .from('product_events')
    .select('id')
    .eq('user_id', ctx.userId)
    .in('event', events)
    .gte('occurred_at', since)
  if (error) throw new Error('plan proposal cooldown lookup failed')
  return (data ?? []).length
}

const OPEN_DRAFT_LIMIT = 20
const FAILED_PROPOSALS_PER_HOUR = 3

/**
 * Checked BEFORE the paid generation: a proposal that could not be stored
 * (too many open drafts, repeated failures) is not generated at all.
 */
async function generationBlocked(ctx: ToolContext, failureEvent: string): Promise<boolean> {
  if ((await recentEvents(ctx, [failureEvent], 1)) >= FAILED_PROPOSALS_PER_HOUR) return true
  const { data, error } = await (ctx.supabase as Untyped)
    .from('plan_drafts')
    .select('id')
    .eq('user_id', ctx.userId)
    .in('status', ['extracting', 'generating', 'needs_completion', 'ready_for_review'])
    .gte('expires_at', new Date().toISOString())
    .limit(OPEN_DRAFT_LIMIT)
  if (error) throw new Error('plan draft lookup failed')
  return (data ?? []).length >= OPEN_DRAFT_LIMIT
}

const BLOCKED = {
  success: false,
  retry_tool: false,
  error:
    'Não é possível criar outra sugestão agora. Explique ao paciente que ele pode revisar, confirmar ou descartar as sugestões que já existem no app, e tentar de novo mais tarde. Não chame a ferramenta de novo e não apresente um plano. Não sugira outro caminho, tela ou recurso para gerar o plano: não existe.',
}

async function record(
  ctx: ToolContext,
  event: string,
  properties: Record<string, unknown>,
): Promise<void> {
  const { error } = await ctx.supabase
    .from('product_events')
    .insert({ user_id: ctx.userId, event, properties: properties as never })
  // The event is what the limits count: losing it silently would lift them.
  if (error) throw new Error('plan proposal event was not stored')
}

async function createDraft(
  ctx: ToolContext,
  domain: PlanDraftDomain,
  candidate: Record<string, unknown>,
  key: string,
  detail: Record<string, unknown>,
  clinical?: MobileFlowClinicalPort,
): Promise<DraftOutcome | null> {
  const assessment = assessPlanDraftPayload(domain, candidate, 'flow')
  if (clinical) {
    if (!clinical.drafts) throw new Error('Current Flow draft writer unavailable')
    return clinical.drafts.create({
      domain,
      requestKey: key,
      status: assessment.complete ? 'ready_for_review' : 'needs_completion',
      payload: assessment.payload,
      uncertainFields: assessment.uncertain_fields,
      originDetail: detail,
    })
  }
  const { data, error } = await (ctx.supabase as Untyped).rpc('create_plan_draft_atomic', {
    p_user_id: ctx.userId,
    p_domain: domain,
    p_origin: 'flow_generated',
    p_status: assessment.complete ? 'ready_for_review' : 'needs_completion',
    p_payload: assessment.payload,
    p_extraction_payload: null,
    p_uncertain_fields: assessment.uncertain_fields,
    p_unrecognized_segments: [],
    p_source_media_asset_id: null,
    p_source_message_id: await turnMessageId(ctx),
    p_origin_detail: detail,
    p_request_key: key,
  })
  if (error || typeof data?.id !== 'string') return null
  const inserted = data.inserted === true
  // Outra chamada do mesmo turno pode ter gravado primeiro: vale o que está gravado.
  const payload = inserted
    ? assessment.payload
    : (((await existingDraft(ctx, key, domain))?.payload as Record<string, unknown> | undefined) ??
      null)
  return { id: data.id, status: String(data.status), inserted, payload }
}

const REVIEW_INSTRUCTION =
  'A sugestão foi criada como RASCUNHO e ainda NÃO é o plano do paciente. ' +
  'Chame-a de "sugestão", nunca de "proposta". ' +
  'Abra com UMA frase curta dizendo que a sugestão está pronta. Em seguida, copie o campo `sugestao` ' +
  'EXATAMENTE como veio: os mesmos itens, na mesma ordem, com as mesmas quantidades, séries, ' +
  'repetições e números. Não resuma, não arredonde, não acrescente nem remova itens e não use Markdown. ' +
  'Termine dizendo que ele deve tocar em "Revisar sugestão" no app para conferir, ajustar e confirmar. ' +
  'NÃO diga que o plano foi salvo, ativado, registrado ou que já está valendo, e NÃO diga que foi ' +
  'revisado por um profissional.'

const REVIEW_INSTRUCTION_WITHOUT_TEXT =
  'A sugestão foi criada como RASCUNHO e ainda NÃO é o plano do paciente. ' +
  'Chame-a de "sugestão", nunca de "proposta". ' +
  'Diga que a sugestão está pronta e que ele deve tocar em "Revisar sugestão" no app para conferir, ' +
  'completar o que faltar e confirmar. NÃO apresente itens do plano no texto. NÃO diga que o plano ' +
  'foi salvo, ativado, registrado ou que já está valendo, e NÃO diga que foi revisado por um profissional.'

const NEEDS_COMPLETION_NOTE =
  ' Alguns campos ficaram para o paciente completar na revisão: diga isso em uma frase.'

/** O texto do chat vem do rascunho gravado; o modelo só o reproduz. */
function suggestionResult(
  domain: PlanDraftDomain,
  status: string,
  payload: unknown,
): { sugestao?: string; message: string } {
  const suggestion =
    payload && typeof payload === 'object'
      ? domain === 'training'
        ? trainingSuggestionText(payload)
        : nutritionSuggestionText(payload)
      : ''
  const note = status === 'needs_completion' ? NEEDS_COMPLETION_NOTE : ''
  return suggestion
    ? { sugestao: suggestion, message: REVIEW_INSTRUCTION + note }
    : { message: REVIEW_INSTRUCTION_WITHOUT_TEXT }
}

function replayed(draft: StoredDraft, domain: PlanDraftDomain) {
  return {
    success: true,
    draft_id: draft.id,
    domain,
    status: draft.status,
    replayed: true,
    ...suggestionResult(domain, draft.status, draft.payload),
  }
}

const UNAVAILABLE = {
  success: false,
  retry_tool: false,
  error:
    'Não foi possível criar a sugestão agora. Explique ao paciente que houve um problema técnico e peça para tentar de novo em alguns minutos. Não apresente um plano. Não sugira outro caminho, tela ou recurso para gerar o plano: não existe.',
}

function ageAt(reference: Date, birthDate: string | null | undefined): number | null {
  return birthDate
    ? Math.floor((reference.getTime() - new Date(birthDate).getTime()) / 31557600000)
    : null
}

export function createPlanProposalTools<
  TrainingParameters extends z.ZodTypeAny,
  DietParameters extends z.ZodTypeAny,
>(parameters: {
  training: TrainingParameters
  diet: DietParameters
}): [ToolDefinition<TrainingParameters>, ToolDefinition<DietParameters>] {
  const proposeTraining: ToolDefinition<TrainingParameters> = {
    name: PROPOSE_TRAINING_PLAN_TOOL,
    description:
      'Cria uma SUGESTÃO de plano de treino semanal (rascunho) para o paciente revisar no app. ' +
      'Use APENAS depois de perguntar e confirmar com o paciente: (1) equipamentos disponíveis, ' +
      '(2) quantos dias por semana, (3) nível atual (iniciante, intermediário ou avançado). ' +
      'Nunca chute o nível — pergunte. A sugestão é um rascunho: só vira plano quando o paciente ' +
      'confirma no app. Se receber {success:false}, NÃO apresente plano nenhum.',
    parameters: parameters.training,
    // Audit 2026-09-28: the model writes null for "none"; optional only.
    nullMeansAbsent: ['training_days', 'goes_to_failure', 'limitations', 'priority_muscles'],
    execute: async (args, ctx) => {
      const clinical =
        ctx.assistantIdentity === 'flow' && ctx.flowClinical
          ? bindMobileFlowClinicalPort(ctx.flowClinical)
          : undefined
      if (clinical && !clinical.drafts) return UNAVAILABLE
      const current = clinical ? await clinical.read() : undefined
      if (current && !flowClinicalProposalAllowed(current, 'training'))
        return { success: false, retry_tool: false, error: 'clinical_guidance_unavailable' }
      const key = requestKey(ctx, PROPOSE_TRAINING_PLAN_TOOL)
      if (!key || !ctx.llm) return UNAVAILABLE
      const existing = await existingDraft(ctx, key, 'training', clinical)
      if (clinical) await clinical.revalidate()
      if (existing) return closedDraft(existing) ?? replayed(existing, 'training')

      // O mesmo limite de gera_treino, somando gerações e propostas.
      if (
        (await recentEvents(ctx, ['training.plan_generated', 'training.plan_proposed'], 24)) >= 1
      ) {
        return {
          success: false,
          retry_tool: false,
          error:
            'Já foi criado um plano ou uma sugestão de treino nas últimas 24h. Explique ao paciente que ele pode revisar a sugestão existente no app ou pedir outra amanhã. Não chame a ferramenta de novo.',
        }
      }
      if (await generationBlocked(ctx, 'training.proposal_failed')) return BLOCKED

      const sp = ctx.supabase as Untyped
      const [user, profile, progress] = current
        ? [
            { data: { name: current.profile.name }, error: null },
            {
              data: {
                ...current.profile,
                birth_date: null,
                current_protocol: current.profile.protocol,
                body_fat_percent: current.profile.bf_percent,
                activity_level: null,
              },
              error: null,
            },
            { data: { current_bf_percent: current.profile.bf_percent }, error: null },
          ]
        : await Promise.all([
            sp.from('users').select('name').eq('id', ctx.userId).maybeSingle(),
            sp
              .from('user_profiles')
              .select('sex, birth_date, weight_kg, height_cm, current_protocol, body_fat_percent')
              .eq('user_id', ctx.userId)
              .maybeSingle(),
            sp
              .from('user_progress')
              .select('current_bf_percent')
              .eq('user_id', ctx.userId)
              .maybeSingle(),
          ])
      if (user.error ?? profile.error ?? progress.error) {
        throw new Error('training proposal profile lookup failed')
      }

      const input = args as {
        available_equipment: string[]
        location: 'academia_completa' | 'academia_limitada' | 'casa'
        days_per_week: number
        training_days?: string[]
        training_level: 'iniciante' | 'intermediario' | 'avancado'
        goes_to_failure?: boolean
        limitations?: string[]
        priority_muscles?: string[]
      }
      const { generateTrainingPlan } = await import('../training-plan-generator.js')
      if (clinical) await clinical.revalidate()
      const plan = await generateTrainingPlan(ctx.llm, ctx.supabase, {
        userId: ctx.userId,
        identity: 'flow',
        profile: {
          name: user.data?.name ?? null,
          sex: profile.data?.sex ?? null,
          age: current
            ? current.profile.age
            : ageAt(ctx.referenceTimestamp ?? new Date(), profile.data?.birth_date),
          weight_kg: profile.data?.weight_kg ?? null,
          height_cm: profile.data?.height_cm ?? null,
          protocol: profile.data?.current_protocol ?? null,
          bf_percent: progress.data?.current_bf_percent ?? profile.data?.body_fat_percent ?? null,
          training_level: input.training_level,
          limitations: input.limitations ?? [],
          priority_muscles: input.priority_muscles ?? [],
        },
        days_per_week: input.days_per_week,
        training_days: input.training_days,
        available_equipment: input.available_equipment,
        location: input.location,
        goes_to_failure: input.goes_to_failure,
      })
      if (clinical) await clinical.revalidate()
      if (!plan) return UNAVAILABLE

      // Audit 2026-10-10: the texts of the suggestion are stored in plain
      // words (closed vocabulary, numbers and structure untouched). Once,
      // here, before the draft is assessed: the chat text is rendered from
      // the stored draft, so the chat and the Plan tab show the same words.
      // The menu proposal below never goes through it.
      const candidate = {
        plan_type: plan.plan_type,
        equipment_summary: plan.equipment_summary,
        weekly_schedule: plan.weekly_schedule,
        progression_rule: plan.progression_rule,
        notes: plan.notes,
      }
      const plainWords = projectFlowPlainTrainingDraft(candidate)
      const draft = await createDraft(
        ctx,
        'training',
        plainWords.payload as Record<string, unknown>,
        key,
        { method: 'training_plan_generator', identity: 'flow' },
        clinical,
      )
      if (clinical) await clinical.revalidate()
      if (!draft) {
        await record(ctx, 'training.proposal_failed', { days_per_week: plan.days_per_week })
        return UNAVAILABLE
      }
      // Outra chamada deste turno gravou primeiro e o rascunho já foi fechado.
      if (!draft.inserted) {
        const closed = closedDraft(draft)
        if (closed) return closed
      }
      if (draft.inserted) {
        await record(ctx, 'training.plan_proposed', {
          draft_id: draft.id,
          plan_type: plan.plan_type,
          days_per_week: plan.days_per_week,
          location: input.location,
          // Numbers only: what the plain-language vocabulary did to this draft.
          plain_terms_replaced: plainWords.termsReplaced,
          plain_sentences_kept: plainWords.sentencesKeptAsGenerated,
          plain_fields_kept: plainWords.fieldsKeptAsGenerated,
        })
      }
      return {
        success: true,
        draft_id: draft.id,
        domain: 'training',
        status: draft.status,
        plan_type: plan.plan_type,
        days_per_week: plan.days_per_week,
        ...suggestionResult('training', draft.status, draft.payload),
      }
    },
  }

  const proposeDiet: ToolDefinition<DietParameters> = {
    name: PROPOSE_DIET_PLAN_TOOL,
    description:
      'Cria uma SUGESTÃO de cardápio (rascunho, com lista de compras) para o paciente revisar no app. ' +
      'Use APENAS quando o paciente pedir explicitamente para montar/gerar agora. Se ele só estiver ' +
      'tirando dúvida, responda e pergunte se quer que você crie a sugestão. A sugestão é um ' +
      'rascunho: só vira plano quando o paciente confirma no app. ' +
      'Se receber {success:false}, NÃO apresente cardápio nenhum.',
    parameters: parameters.diet,
    // Audit 2026-09-28: "sem restrições" arrived as null and refused the call.
    nullMeansAbsent: ['horizon', 'meals_per_day', 'restrictions', 'preferences'],
    execute: async (args, ctx) => {
      const clinical =
        ctx.assistantIdentity === 'flow' && ctx.flowClinical
          ? bindMobileFlowClinicalPort(ctx.flowClinical)
          : undefined
      if (clinical && !clinical.drafts) return UNAVAILABLE
      const current = clinical ? await clinical.read() : undefined
      if (current && !flowClinicalProposalAllowed(current, 'nutrition'))
        return { success: false, retry_tool: false, error: 'clinical_guidance_unavailable' }
      const key = requestKey(ctx, PROPOSE_DIET_PLAN_TOOL)
      if (!key || !ctx.llm) return UNAVAILABLE
      const existing = await existingDraft(ctx, key, 'nutrition', clinical)
      if (clinical) await clinical.revalidate()
      if (existing) return closedDraft(existing) ?? replayed(existing, 'nutrition')

      // O mesmo limite de gera_dieta, somando gerações e propostas.
      if ((await recentEvents(ctx, ['diet.generated', 'diet.proposed'], 2)) >= 2) {
        return {
          success: false,
          retry_tool: false,
          error:
            'Já foram criados 2 cardápios ou sugestões nas últimas 2h. Explique ao paciente que ele pode revisar as sugestões existentes no app ou pedir outra mais tarde. Não chame a ferramenta de novo.',
        }
      }
      if (await generationBlocked(ctx, 'diet.proposal_failed')) return BLOCKED

      const sp = ctx.supabase as Untyped
      const [user, profile, progress] = current
        ? [
            { data: { name: current.profile.name }, error: null },
            {
              data: {
                ...current.profile,
                birth_date: null,
                current_protocol: current.profile.protocol,
                body_fat_percent: current.profile.bf_percent,
                activity_level: null,
              },
              error: null,
            },
            { data: { current_bf_percent: current.profile.bf_percent }, error: null },
          ]
        : await Promise.all([
            sp.from('users').select('name').eq('id', ctx.userId).maybeSingle(),
            sp
              .from('user_profiles')
              .select(
                'sex, birth_date, weight_kg, height_cm, activity_level, current_protocol, body_fat_percent',
              )
              .eq('user_id', ctx.userId)
              .maybeSingle(),
            sp
              .from('user_progress')
              .select('current_bf_percent')
              .eq('user_id', ctx.userId)
              .maybeSingle(),
          ])
      if (user.error ?? profile.error ?? progress.error) {
        throw new Error('diet proposal profile lookup failed')
      }
      // Metas oficiais, como em gera_dieta; nada é recalculado aqui.
      const targets = current
        ? {
            calories_target: current.today.targets.calories_kcal,
            protein_target: current.today.targets.protein_g,
          }
        : await loadDailyTargets(ctx.supabase, ctx.userId, await loadCalcConfig(ctx.supabase))

      const since = new Date(Date.now() - 30 * 24 * 3600 * 1000).toISOString()
      const history = await sp
        .from('meal_logs')
        .select('food_name')
        .eq('user_id', ctx.userId)
        .gte('created_at', since)
      if (history.error) throw new Error('diet proposal history lookup failed')
      const frequency = new Map<string, number>()
      for (const row of (history.data ?? []) as Array<{ food_name: string }>) {
        const name = row.food_name.toLowerCase().trim()
        frequency.set(name, (frequency.get(name) ?? 0) + 1)
      }

      const input = args as {
        horizon?: 'daily' | 'weekly'
        meals_per_day?: number
        restrictions?: string[]
        preferences?: string[]
      }
      const { generateDietPlan } = await import('../diet-generator.js')
      if (clinical) await clinical.revalidate()
      const plan = await generateDietPlan(ctx.llm, ctx.supabase, {
        userId: ctx.userId,
        identity: 'flow',
        profile: {
          name: user.data?.name ?? null,
          sex: profile.data?.sex ?? null,
          age: current
            ? current.profile.age
            : ageAt(ctx.referenceTimestamp ?? new Date(), profile.data?.birth_date),
          weight_kg: profile.data?.weight_kg ?? null,
          height_cm: profile.data?.height_cm ?? null,
          activity_level: profile.data?.activity_level ?? null,
          protocol: profile.data?.current_protocol ?? null,
          meta_kcal: targets.calories_target ?? null,
          meta_protein_g: targets.protein_target ?? null,
          bf_percent: progress.data?.current_bf_percent ?? profile.data?.body_fat_percent ?? null,
          restrictions: input.restrictions ?? [],
          preferences: input.preferences ?? [],
        },
        historical_foods: Array.from(frequency.entries())
          .sort((left, right) => right[1] - left[1])
          .slice(0, 30)
          .map(([food_name, count]) => ({ food_name, frequency: count })),
        meals_per_day: input.meals_per_day,
        mode: 'referencia',
        horizon: input.horizon ?? 'daily',
      })
      if (clinical) await clinical.revalidate()
      if (!plan) return UNAVAILABLE

      const draft = await createDraft(
        ctx,
        'nutrition',
        {
          mode: plan.mode,
          horizon: plan.horizon,
          meta_kcal: plan.meta_kcal,
          meta_protein_g: plan.meta_protein_g,
          daily_meals: plan.daily_meals,
          shopping_list: plan.shopping_list,
          notes: plan.notes,
        },
        key,
        { method: 'diet_generator', identity: 'flow' },
        clinical,
      )
      if (clinical) await clinical.revalidate()
      if (!draft) {
        await record(ctx, 'diet.proposal_failed', { horizon: plan.horizon })
        return UNAVAILABLE
      }
      // Outra chamada deste turno gravou primeiro e o rascunho já foi fechado.
      if (!draft.inserted) {
        const closed = closedDraft(draft)
        if (closed) return closed
      }
      if (draft.inserted) {
        await record(ctx, 'diet.proposed', {
          draft_id: draft.id,
          horizon: plan.horizon,
          meals_count: plan.daily_meals.length,
        })
      }
      return {
        success: true,
        draft_id: draft.id,
        domain: 'nutrition',
        status: draft.status,
        horizon: plan.horizon,
        meals_count: plan.daily_meals.length,
        ...suggestionResult('nutrition', draft.status, draft.payload),
      }
    },
  }

  return [proposeTraining, proposeDiet]
}
