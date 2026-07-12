/**
 * Tool guards — hard-guard pós-LLM (ACT-3 prevention plan 2026-06-16).
 *
 * Cada guard valida `validated args` ANTES do tool.execute(). Rejeições
 * viram product_event `tool_rejected_by_guard` + retry message dirigido.
 *
 * Padrão pra cada tool nova:
 *   1. arquivo `tools/<tool_name>-guard.ts` com função
 *      `validate<ToolName>(args, ctx): GuardResult`
 *   2. registrar no GUARDS registry abaixo
 *   3. pipeline.ts chama runToolGuard(name, args, ctx) antes de execute
 *
 * Motivação: defesa em prompt é estatística (Haiku ignora regra "PROIBIDO"
 * 5-10%). Hard-guard pós-LLM é determinístico — recusa e força retry com
 * mensagem específica.
 */

import type { ServiceClient } from '@mpp/db'
import { validateRegistraRefeicao } from './registra_refeicao-guard.js'
import { validateMarcaRefeicaoPulada } from './marca_refeicao_pulada-guard.js'

export interface GuardContext {
  supabase: ServiceClient
  userId: string
  userTimezone?: string
  referenceTimestamp?: Date
  /** Quando true, paciente VIU o pending e CLICOU pra confirmar — guards
   *  podem ser mais permissivos (paciente já validou visualmente). */
  trustedTap?: boolean
  /** Foto pendente de registro (FIX 4 audit 06-16) — relevante pro
   *  marca_refeicao_pulada guard. */
  // biome-ignore lint/suspicious/noExplicitAny: VisionPending estrutura definida em pipeline.ts; evita dependência circular
  visionPending?: any
}

export type GuardResult =
  | { ok: true }
  | { ok: false; reason: string; details?: Record<string, unknown>; retry_hint?: string }

export interface GuardRegistry {
  [toolName: string]: (
    args: Record<string, unknown>,
    ctx: GuardContext,
  ) => Promise<GuardResult> | GuardResult
}

/** Registry central. Adicionar novo guard aqui ao criar arquivo. */
export const GUARDS: GuardRegistry = {
  registra_refeicao: validateRegistraRefeicao,
  marca_refeicao_pulada: validateMarcaRefeicaoPulada,
}

/**
 * Despacha guard por tool name. Se não há guard registrado, retorna ok=true
 * (no-op — tools sem guard são permitidas; gradualmente migramos todas).
 *
 * Emite `tool_rejected_by_guard` em product_events quando guard recusa.
 */
export async function runToolGuard(
  toolName: string,
  args: Record<string, unknown>,
  ctx: GuardContext,
): Promise<GuardResult> {
  const guard = GUARDS[toolName]
  if (!guard) return { ok: true }
  const result = await guard(args, ctx)
  if (!result.ok) {
    try {
      // Cast pra Json — supabase v2 tipa properties como Json (não Record);
      // shapes simples como esses sempre serializam, mas o compilador
      // não sabe. Safe cast: estrutura é JSON-clean (string/null/object plain).
      const properties = {
        tool: toolName,
        reason: result.reason,
        details: result.details ?? null,
        args_shape: Object.fromEntries(
          Object.entries(args).map(([k, v]) => [k, typeof v]),
        ),
        // biome-ignore lint/suspicious/noExplicitAny: Json type do supabase v2
      } as any
      // biome-ignore lint/suspicious/noExplicitAny: supabase ServiceClient
      const sp = ctx.supabase as any
      await sp.from('product_events').insert({
        user_id: ctx.userId,
        event: 'tool_rejected_by_guard',
        properties,
      })
    } catch {
      // never block — telemetria não pode derrubar a tool
    }
  }
  return result
}
