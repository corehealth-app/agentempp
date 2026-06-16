/**
 * Telemetria centralizada (ACT-2 prevention plan 2026-06-16).
 *
 * Antes desta migração, cada subsistema do agente reinventava o padrão de
 * gravar evento em `product_events` — alguns com try/catch silencioso
 * engolindo o erro, outros sem catch nenhum (propagando exceção pra cima e
 * derrubando o turno todo). Resultado: bugs como o selector dead 36h
 * (audit 06-13) ficaram invisíveis porque o catch silencioso engolia o
 * erro original.
 *
 * Este módulo expõe UMA função `emitEvent()` que:
 *  - nunca lança (silencia internamente; loga via console.warn em dev)
 *  - aceita supabase/userId opcionais (no-op se ausentes)
 *  - normaliza shape do insert
 *  - permite stage override em properties pra dashboards filtrarem
 *
 * Substitui o helper `emitEdu()` privado do educational-comment.ts (que
 * será refatorado pra usar este). Pattern a seguir em TODO novo subsistema:
 *
 *   import { emitEvent } from '@mpp/agent/telemetry'
 *   ...
 *   try {
 *     await doRiskyThing()
 *   } catch (err) {
 *     await emitEvent({
 *       supabase, userId,
 *       event: '<subsystem>.failed',
 *       properties: { error: String(err).slice(0, 300) },
 *       level: 'error',
 *     })
 *     // re-throw, return fallback, etc — comportamento explícito
 *   }
 *
 * Lint rule `no-silent-catch` (próxima fase) vai forçar este pattern em
 * todos os catches novos.
 */

export type EmitEventLevel = 'info' | 'warn' | 'error'

export interface EmitEventOpts {
  // biome-ignore lint/suspicious/noExplicitAny: supabase ServiceClient — tipado em @mpp/db, mas pra evitar dependência circular do package agent → db aceita any aqui
  supabase?: any
  userId?: string
  event: string
  properties?: Record<string, unknown>
  /** Nível do evento. Default 'info'. Afeta apenas as propriedades adicionadas
   * (não muda destino). Dashboards/alertas filtram por isso. */
  level?: EmitEventLevel
  /** Stage de origem (ex: 'edu-comment', 'meal-pipeline', 'vision'). Vai
   * pras properties pra facilitar filtragem no dashboard. */
  stage?: string
}

/**
 * Emite product_event de forma never-throw. Quando supabase ou userId não
 * estão disponíveis, faz no-op silencioso (usado em paths que rodam SEM
 * usuário, ex: cron sem user_id).
 *
 * Performance: 1 insert. Sob carga, considerar batch fire-and-forget
 * (próxima fase com queue).
 */
export async function emitEvent(opts: EmitEventOpts): Promise<void> {
  if (!opts.supabase || !opts.userId) return
  const level = opts.level ?? 'info'
  const properties: Record<string, unknown> = {
    level,
    ...(opts.stage ? { stage: opts.stage } : {}),
    ...(opts.properties ?? {}),
  }
  try {
    const { error } = await opts.supabase.from('product_events').insert({
      user_id: opts.userId,
      event: opts.event,
      properties,
    })
    if (error) {
      // supabase-js v2 retorna error em vez de lançar — capturar pra não
      // perder sinal silenciosamente. logger.warn aqui evita spam em prod
      // (uso em ambiente dev/test com console.warn).
      console.warn(
        `[telemetry] insert error for event=${opts.event}: ${error.code} ${error.message}`,
      )
    }
  } catch (insertErr) {
    // never block — telemetria não pode derrubar o pipeline. Mas registra
    // localmente pra dev/test pegar.
    console.warn(
      `[telemetry] throw on event=${opts.event}: ${insertErr instanceof Error ? insertErr.message : String(insertErr)}`,
    )
  }
}

/**
 * Helper específico pra eventos de erro com convenção `<subsystem>.failed`.
 * Açúcar sintático em volta de emitEvent — não muda comportamento.
 */
export async function emitFailedEvent(
  opts: Omit<EmitEventOpts, 'level' | 'event'> & { subsystem: string; error: unknown },
): Promise<void> {
  const { subsystem, error, ...rest } = opts
  await emitEvent({
    ...rest,
    event: `${subsystem}.failed`,
    level: 'error',
    properties: {
      ...(rest.properties ?? {}),
      error: String(error instanceof Error ? error.message : error).slice(0, 300),
    },
  })
}
