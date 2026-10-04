/**
 * Types compartilhados entre tools — extraídos de tools.ts pra permitir
 * split incremental (audit 06-26 Layer 2.1 prevention plan). Sem mudança de
 * lógica — só relocation. tools.ts re-exporta pra preservar API pública.
 */

import type { DailyTargets } from '@mpp/core'
import type { ServiceClient } from '@mpp/db'
import type { z } from 'zod'
import type { FlowDayBalanceInputs } from '../flow-energy-context.js'

/** Who a plan generator speaks as. 'legacy' is the current WhatsApp identity. */
export type GeneratorIdentity = 'legacy' | 'flow'

export interface ToolContext {
  supabase: ServiceClient
  userId: string
  userWpp: string
  /** LLM disponível pra tools que precisam gerar conteúdo (gera_dieta,
   * gera_treino). Injetado pelo pipeline. Opcional pra retrocompatibilidade. */
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  // biome-ignore lint/suspicious/noExplicitAny: legacy — see ACT-1 prevention plan 2026-06-16
  llm?: any
  /** ISO alpha-2 do país de residência (pra TACO/USDA, persona, idioma). */
  userCountry?: string
  /** Timezone IANA do paciente (default America/Sao_Paulo). Usado pra
   * computar a data LOCAL ao buscar/inserir snapshot. Antes usava UTC
   * → paciente em New_York perdia consumo registrado entre 20h-24h. */
  userTimezone?: string
  /** ID da mensagem que originou o turno (provider_message_id). Usado pra
   * dedup de inserts em logs (meal_logs, workout_logs) — protege contra
   * dupla contagem em retentativas do Inngest. */
  providerMessageId?: string
  /** Instante original da mensagem no provider. Data/hora de gravações deve
   * derivar daqui, não do momento em que o worker terminou de processar. */
  referenceTimestamp?: Date
  /** Texto agregado do turno atual, sem mensagens históricas. */
  currentUserText?: string
  /** Últimas N mensagens do PACIENTE (direção 'in') no turno atual.
   * Usado pra validação semântica determinística — ex: detectar se
   * `replace=true` em registra_refeicao é legítimo (paciente disse
   * "corrige", "errei", etc) ou bug do LLM (foto nova classificada como
   * correção). NÃO substitui prompt rule, é defesa em profundidade. */
  recentUserMessages?: string[]
  /** Quando true, `registra_refeicao` NÃO aplica autocorrect de meal_type
   * pela hora local. Setado SÓ pelo caminho do tap de botão (interactive-
   * handler `action='confirm'`), onde `proposal.mealType` veio de uma
   * proposta explícita que o paciente clicou. Bug I2 (Luciana 2026-06-14
   * 15:44 BRT, pending bfdad07b): pending criado às 13h com mealType='cafe',
   * paciente clicou 2h47min depois (localHour=15) → autocorrect virava pra
   * 'lanche' silenciosamente, divergindo do card "Café registrado". */
  trustMealType?: boolean
  /** Each confirmed proposal is a NEW record. Set ONLY by the mobile BFF
   * (`confirmRegistration`) for a proposal the app itself built
   * (`registration_origin: 'mobile_app'`). With it `registra_refeicao` does
   * not promote `replace` from a name overlap in the last 30 min and does not
   * drop an item as a duplicate of the day; both are only counted
   * (`tool.replace_implicit_skipped_additive_confirmation`,
   * `tool.same_day_duplicate_kept_additive_confirmation`), and a failed read
   * or insert of that telemetry never fails the confirmation. The idempotency
   * by `providerMessageId` still holds, so a retry of the same proposal never
   * doubles. Never set by the WhatsApp pipeline or its button tap, and never
   * read from a payload. Defect B (iPhone, staging, 2026-10-04): the app
   * context has no patient text, so a second identical lunch confirmed one
   * minute later silently replaced the first row (541 kcal instead of 780). */
  additiveConfirmation?: boolean
  /** Set by the pipeline from the server-side channel only ('flow' on the
   * mobile Flow). Absent = the legacy identity. Never read from a payload. */
  assistantIdentity?: GeneratorIdentity
  /** Intraday targets from the authenticated Flow context. Server-owned;
   * never supplied by tool arguments or used by the legacy channel. */
  flowDailyTargets?: DailyTargets
  /** Effective protocol, gain multiplier, programmed deficit and the verdict
   * about the day's stored target (false on the day the protocol changed) of
   * the authenticated Flow context, for the per-protocol day balance
   * (docs/CALCULO-MPP.md §2c). Server-owned; set only by the pipeline on the
   * Flow channel. Absent = the legacy net balance against the target. */
  flowDayBalance?: FlowDayBalanceInputs
}

export interface ToolDefinition<T extends z.ZodTypeAny = z.ZodTypeAny> {
  name: string
  description: string
  parameters: T
  execute: (args: z.infer<T>, ctx: ToolContext) => Promise<Record<string, unknown>>
  /** Top-level arguments the model may send as null meaning "none"; they are
   * dropped before validation. Only tools that opt in (the Flow proposals). */
  nullMeansAbsent?: readonly string[]
}

/** Arguments as the tool validates them (see `nullMeansAbsent`). */
export function normalizeToolArguments(tool: Pick<ToolDefinition, 'nullMeansAbsent'>, raw: unknown): unknown {
  if (!tool.nullMeansAbsent?.length || !raw || typeof raw !== 'object' || Array.isArray(raw)) return raw
  const args = { ...(raw as Record<string, unknown>) }
  for (const key of tool.nullMeansAbsent) if (args[key] === null) delete args[key]
  return args
}
