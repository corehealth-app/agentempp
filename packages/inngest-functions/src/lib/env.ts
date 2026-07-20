/**
 * Helper único para construir clients (Supabase, LLM) lendo do env.
 * Credenciais "secundárias" (TTS, Meta) podem ser carregadas sob demanda
 * via loadCredentials() — busca em service_credentials caso env esteja vazio.
 */
import { processMessage } from '@mpp/agent'
import type { ServiceClient } from '@mpp/db'
import { createServiceClient } from '@mpp/db'
import { OpenRouterEmbeddings, OpenRouterLLM } from '@mpp/providers'

export interface WorkerDeps {
  supabase: ServiceClient
  llm: OpenRouterLLM
  embeddings: OpenRouterEmbeddings
}

export function createWorkerSupabase(): ServiceClient {
  const url = process.env.SUPABASE_URL ?? process.env.NEXT_PUBLIC_SUPABASE_URL
  const serviceRoleKey = process.env.SUPABASE_SERVICE_ROLE_KEY

  if (!url) throw new Error('SUPABASE_URL ausente')
  if (!serviceRoleKey) throw new Error('SUPABASE_SERVICE_ROLE_KEY ausente')

  return createServiceClient({ url, serviceRoleKey })
}

export function createWorkerDeps(): WorkerDeps {
  const openrouterKey = process.env.OPENROUTER_API_KEY
  if (!openrouterKey) throw new Error('OPENROUTER_API_KEY ausente')

  return {
    supabase: createWorkerSupabase(),
    llm: new OpenRouterLLM({
      apiKey: openrouterKey,
      heliconeApiKey: process.env.HELICONE_API_KEY,
    }),
    embeddings: new OpenRouterEmbeddings({ apiKey: openrouterKey, dimensions: 1024 }),
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
