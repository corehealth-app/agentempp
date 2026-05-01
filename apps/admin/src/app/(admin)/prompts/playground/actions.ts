'use server'
import { createClient, createServiceClient } from '@/lib/supabase/server'
import { processMessage } from '@mpp/agent'
import { OpenRouterLLM } from '@mpp/providers'

async function requireAdmin() {
  const supabase = await createClient()
  const {
    data: { user },
  } = await supabase.auth.getUser()
  if (!user) throw new Error('Não autenticado')
  const svc = createServiceClient()
  const { data: admin } = await svc
    .from('admin_users')
    .select('id, role')
    .eq('id', user.id)
    .maybeSingle()
  if (!admin) throw new Error('Acesso negado')
  return user
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
