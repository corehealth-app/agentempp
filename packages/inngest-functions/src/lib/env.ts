/**
 * Helper único para construir os clients (Supabase, LLM) lendo do env.
 * Workers Inngest podem rodar em Vercel ou local — buscam env vars padrão.
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

export { processMessage }
