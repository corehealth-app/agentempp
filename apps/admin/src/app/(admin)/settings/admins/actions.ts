'use server'
import { createClient, createServiceClient } from '@/lib/supabase/server'
import { revalidatePath } from 'next/cache'

interface AddInput {
  email: string
  name: string
  role: string
}

export async function addAdmin(input: AddInput) {
  try {
    const supabase = await createClient()
    const {
      data: { user },
    } = await supabase.auth.getUser()
    if (!user) return { error: 'Não autenticado' }

    const svc = createServiceClient()
    const { data: me } = await svc
      .from('admin_users')
      .select('role')
      .eq('id', user.id)
      .maybeSingle()
    if (!me || me.role !== 'admin') return { error: 'Apenas admin pode adicionar' }

    // Tenta achar o auth.users.id pelo email (via auth admin API)
    const { data: authUsers } = await svc.auth.admin.listUsers({ page: 1, perPage: 200 })
    const found = authUsers?.users?.find((u) => u.email === input.email)
    if (!found) {
      return {
        error: `Usuário ${input.email} ainda não existe em auth.users — peça para ele fazer login no /login primeiro`,
      }
    }

    const { error } = await svc.from('admin_users').upsert({
      id: found.id,
      email: input.email,
      name: input.name || null,
      role: input.role,
      updated_at: new Date().toISOString(),
    })
    if (error) return { error: error.message }

    revalidatePath('/settings/admins')
    return { ok: true }
  } catch (e) {
    return { error: e instanceof Error ? e.message : String(e) }
  }
}
