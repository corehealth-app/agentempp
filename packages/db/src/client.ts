import { createClient } from '@supabase/supabase-js'
import type { Database } from './generated/database.js'

export function createServiceClient(env: { url: string; serviceRoleKey: string }) {
  return createClient<Database>(env.url, env.serviceRoleKey, {
    auth: { persistSession: false, autoRefreshToken: false },
    db: { schema: 'public' },
  })
}

export function createPublicClient(env: { url: string; anonKey: string }) {
  return createClient<Database>(env.url, env.anonKey)
}

export type ServiceClient = ReturnType<typeof createServiceClient>
export type PublicClient = ReturnType<typeof createPublicClient>
