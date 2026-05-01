/**
 * Bootstrap do primeiro admin.
 *
 * Uso:
 *   ADMIN_EMAIL=gestao@excluvia.com.br pnpm --filter @mpp/scripts bootstrap-admin
 *
 * Pré-requisito: o usuário deve ter feito login pelo menos uma vez via /login
 * (Magic link). O auth.users.id deve existir.
 */
import { createClient } from '@supabase/supabase-js'
import type { Database } from '@mpp/db'

function env(k: string): string {
  const v = process.env[k]
  if (!v) throw new Error(`Missing env ${k}`)
  return v
}

async function main() {
  const email = env('ADMIN_EMAIL')
  console.log(`━━━ Bootstrap admin: ${email} ━━━\n`)

  const svc = createClient<Database>(env('SUPABASE_URL'), env('SUPABASE_SERVICE_ROLE_KEY'), {
    auth: { persistSession: false, autoRefreshToken: false },
  })

  const { data: list, error } = await svc.auth.admin.listUsers({ page: 1, perPage: 200 })
  if (error) throw error

  const user = list.users.find((u) => u.email === email)
  if (!user) {
    console.error(
      `❌ Usuário ${email} não existe em auth.users. Faça login uma vez em /login primeiro.`,
    )
    process.exit(1)
  }

  console.log(`✓ Achei auth.users.id=${user.id}`)

  const { error: upsertErr } = await svc.from('admin_users').upsert(
    {
      id: user.id,
      email,
      role: 'admin',
      updated_at: new Date().toISOString(),
    },
    { onConflict: 'id' },
  )
  if (upsertErr) throw upsertErr

  console.log(`✅ ${email} promovido a admin.`)
}

main().catch((e) => {
  console.error('💥', e)
  process.exit(1)
})
