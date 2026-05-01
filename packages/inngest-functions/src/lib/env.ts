/**
 * Helper único para construir clients (Supabase, LLM) lendo do env.
 * Credenciais "secundárias" (TTS, Meta) podem ser carregadas sob demanda
 * via loadCredentials() — busca em service_credentials caso env esteja vazio.
 */
import { processMessage } from '@mpp/agent'
import { createServiceClient } from '@mpp/db'
import { OpenRouterLLM } from '@mpp/providers'
import type { ServiceClient } from '@mpp/db'

export interface WorkerDeps {
  supabase: ServiceClient
  llm: OpenRouterLLM
}

export function createWorkerDeps(): WorkerDeps {
  const url = process.env.SUPABASE_URL ?? process.env.NEXT_PUBLIC_SUPABASE_URL
  const serviceRoleKey = process.env.SUPABASE_SERVICE_ROLE_KEY
  const openrouterKey = process.env.OPENROUTER_API_KEY

  if (!url) throw new Error('SUPABASE_URL ausente')
  if (!serviceRoleKey) throw new Error('SUPABASE_SERVICE_ROLE_KEY ausente')
  if (!openrouterKey) throw new Error('OPENROUTER_API_KEY ausente')

  return {
    supabase: createServiceClient({ url, serviceRoleKey }),
    llm: new OpenRouterLLM({
      apiKey: openrouterKey,
      heliconeApiKey: process.env.HELICONE_API_KEY,
    }),
  }
}

/**
 * Carrega uma credencial: env → service_credentials (DB).
 * Retorna null se não existir em nenhum lugar.
 */
export async function loadCredential(
  supabase: ServiceClient,
  envKey: string,
  service: string,
  keyName: string,
): Promise<string | null> {
  const fromEnv = process.env[envKey]
  if (fromEnv) return fromEnv

  const { data } = await supabase
    .from('service_credentials')
    .select('value')
    .eq('service', service)
    .eq('key_name', keyName)
    .eq('is_active', true)
    .maybeSingle()
  return (data as { value: string } | null)?.value ?? null
}

export { processMessage }
