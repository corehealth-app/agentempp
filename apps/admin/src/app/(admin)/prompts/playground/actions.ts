'use server'
import { processMessage } from '@mpp/agent'
import { OpenRouterLLM } from '@mpp/providers'
import { checkAdminPageAccess } from '@/lib/admin-page-guard'
import { AI_PLAYGROUND_ROLES } from '@/lib/admin-rbac'
import { createServiceClient } from '@/lib/supabase/server'

/**
 * Estas ações ficam atrás da tela do Playground: só passa quem pode abri-la
 * (mesma regra do guarda da página). A lista que elas já tinham
 * (`AI_PLAYGROUND_ROLES`) continua valendo e nunca alarga: o resultado é a
 * interseção. Até 2026-10-05 o `content_editor` passava aqui sem poder abrir
 * a tela.
 */
async function requireAdmin() {
  const access = await checkAdminPageAccess('/prompts/playground', AI_PLAYGROUND_ROLES)
  if (!access.ok) {
    throw new Error(access.reason === 'anonymous' ? 'Não autenticado' : 'Acesso negado')
  }
  return access.admin
}

export async function runPlayground(input: { from: string; text: string }) {
  try {
    await requireAdmin()
    const supabase = createServiceClient()

    // Lê API key do banco (com fallback para env)
    let apiKey = process.env.OPENROUTER_API_KEY ?? ''
    const { data: cred } = await supabase
      .from('service_credentials')
      .select('value')
      .eq('service', 'openrouter')
      .eq('key_name', 'api_key')
      .eq('is_active', true)
      .maybeSingle()
    if (cred?.value) apiKey = cred.value

    if (!apiKey) {
      return {
        error: 'OpenRouter API key não configurada (nem em /settings/api-keys nem em env)',
      }
    }

    const llm = new OpenRouterLLM({ apiKey })
    const result = await processMessage(
      { supabase, llm },
      {
        from: input.from,
        providerMessageId: `playground_${Date.now()}`,
        text: input.text,
        contentType: 'text',
        provider: 'admin_playground',
        timestamp: new Date(),
      },
    )

    return {
      text: result.text,
      stage: result.stage,
      model: result.modelUsed,
      prompt_tokens: result.promptTokens,
      completion_tokens: result.completionTokens,
      cost_usd: result.costUsd,
      latency_ms: result.latencyMs,
      tools: result.toolCalls.map((t) => ({ name: t.name, success: !t.error })),
    }
  } catch (e) {
    return { error: e instanceof Error ? e.message : String(e) }
  }
}

export async function resetPlaygroundUser(wpp: string) {
  try {
    await requireAdmin()
    const svc = createServiceClient()
    const { data: u } = await svc.from('users').select('id').eq('wpp', wpp).maybeSingle()
    if (u) {
      await svc.from('users').delete().eq('id', u.id)
    }
    return { ok: true }
  } catch (e) {
    return { error: e instanceof Error ? e.message : String(e) }
  }
}
