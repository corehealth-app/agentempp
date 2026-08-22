'use server'
import { revalidatePath } from 'next/cache'
import { hasAdminRole, isAdminRole, MASTER_ADMIN_ROLES } from '@/lib/admin-rbac'
import { createClient, createServiceClient } from '@/lib/supabase/server'

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
    if (!me || !hasAdminRole(me.role, MASTER_ADMIN_ROLES)) {
      return { error: 'Apenas master admin pode adicionar' }
    }

    if (!isAdminRole(input.role)) return { error: 'Papel administrativo invalido' }

    // Tenta achar o auth.users.id pelo email (via auth admin API)
    const { data: authUsers } = await svc.auth.admin.listUsers({ page: 1, perPage: 200 })
    const found = authUsers?.users?.find((u) => u.email === input.email)
    if (!found) {
      return {
        error: `Usuário ${input.email} ainda não existe em auth.users — peça para ele fazer login no /login primeiro`,
      }
    }

    const { data: patientAccount, error: patientError } = await svc
      .from('users')
      .select('id')
      .eq('auth_user_id', found.id)
      .maybeSingle()
    if (patientError) return { error: patientError.message }
    if (patientAccount) {
      return { error: 'Use uma conta de e-mail separada para paciente e administrador' }
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
