/**
 * Types compartilhados entre tools — extraídos de tools.ts pra permitir
 * split incremental (audit 06-26 Layer 2.1 prevention plan). Sem mudança de
 * lógica — só relocation. tools.ts re-exporta pra preservar API pública.
 */
import type { ServiceClient } from '@mpp/db'
import type { z } from 'zod'

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
  /** Set by the pipeline from the server-side channel only ('flow' on the
   * mobile Flow). Absent = the legacy identity. Never read from a payload. */
  assistantIdentity?: GeneratorIdentity
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
