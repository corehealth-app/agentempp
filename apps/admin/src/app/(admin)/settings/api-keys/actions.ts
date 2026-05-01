'use server'
import { createClient, createServiceClient } from '@/lib/supabase/server'
import { revalidatePath } from 'next/cache'

interface SaveInput {
  service: string
  key_name: string
  value: string
}

async function requireAdmin() {
  const supabase = await createClient()
  const {
    data: { user },
  } = await supabase.auth.getUser()
  if (!user) throw new Error('Não autenticado')
  const svc = createServiceClient()
  const { data: admin } = await svc
    .from('admin_users')
    .select('id, role, email')
    .eq('id', user.id)
    .maybeSingle()
  if (!admin || admin.role !== 'admin') throw new Error('Acesso negado')
  return { user, admin }
}

export async function saveCredential(input: SaveInput) {
  try {
    const { user } = await requireAdmin()
    const svc = createServiceClient()

    const { data: existing } = await svc
      .from('service_credentials')
      .select('*')
      .eq('service', input.service)
      .eq('key_name', input.key_name)
      .maybeSingle()

    if (existing) {
      const { error } = await svc
        .from('service_credentials')
        .update({
          value: input.value,
          updated_by: user.id,
          updated_at: new Date().toISOString(),
          last_tested_at: null,
          last_test_result: null,
        })
        .eq('id', existing.id)
      if (error) return { error: error.message }
    } else {
      const { error } = await svc.from('service_credentials').insert({
        service: input.service,
        key_name: input.key_name,
        value: input.value,
        is_active: true,
        updated_by: user.id,
      })
      if (error) return { error: error.message }
    }

    await svc.from('audit_log').insert({
      actor_id: user.id,
      actor_email: user.email,
      action: existing ? 'credential.update' : 'credential.create',
      entity: 'service_credentials',
      entity_id: `${input.service}:${input.key_name}`,
      after: { service: input.service, key_name: input.key_name },
    })

    revalidatePath('/settings/api-keys')
    return { ok: true }
  } catch (e) {
    return { error: e instanceof Error ? e.message : String(e) }
  }
}

export async function deleteCredential(input: { service: string; key_name: string }) {
  try {
    const { user } = await requireAdmin()
    const svc = createServiceClient()

    const { error } = await svc
      .from('service_credentials')
      .delete()
      .eq('service', input.service)
      .eq('key_name', input.key_name)
    if (error) return { error: error.message }

    await svc.from('audit_log').insert({
      actor_id: user.id,
      actor_email: user.email,
      action: 'credential.delete',
      entity: 'service_credentials',
      entity_id: `${input.service}:${input.key_name}`,
    })

    revalidatePath('/settings/api-keys')
    return { ok: true }
  } catch (e) {
    return { error: e instanceof Error ? e.message : String(e) }
  }
}

export async function testCredential(service: string) {
  try {
    await requireAdmin()
    const svc = createServiceClient()

    const { data: rows } = await svc
      .from('service_credentials')
      .select('key_name, value')
      .eq('service', service)
    const creds = new Map((rows ?? []).map((r) => [r.key_name, r.value]))

    let result: 'ok' | string = 'unknown'

    if (service === 'openrouter') {
      const key = creds.get('api_key')
      if (!key) return { error: 'api_key não configurada' }
      const r = await fetch('https://openrouter.ai/api/v1/auth/key', {
        headers: { Authorization: `Bearer ${key}` },
      })
      result = r.ok ? 'ok' : `error: HTTP ${r.status}`
    } else if (service === 'groq') {
      const key = creds.get('api_key')
      if (!key) return { error: 'api_key não configurada' }
      const r = await fetch('https://api.groq.com/openai/v1/models', {
        headers: { Authorization: `Bearer ${key}` },
      })
      result = r.ok ? 'ok' : `error: HTTP ${r.status}`
    } else if (service === 'elevenlabs') {
      const key = creds.get('api_key')
      if (!key) return { error: 'api_key não configurada' }
      const r = await fetch('https://api.elevenlabs.io/v1/user', {
        headers: { 'xi-api-key': key },
      })
      result = r.ok ? 'ok' : `error: HTTP ${r.status}`
    } else if (service === 'cartesia') {
      const key = creds.get('api_key')
      if (!key) return { error: 'api_key não configurada' }
      const r = await fetch('https://api.cartesia.ai/voices', {
        headers: { 'X-API-Key': key, 'Cartesia-Version': '2024-06-10' },
      })
      result = r.ok ? 'ok' : `error: HTTP ${r.status}`
    } else if (service === 'meta_whatsapp') {
      const token = creds.get('access_token')
      const phoneId = creds.get('phone_number_id')
      if (!token || !phoneId) return { error: 'access_token e phone_number_id necessários' }
      const r = await fetch(`https://graph.facebook.com/v21.0/${phoneId}`, {
        headers: { Authorization: `Bearer ${token}` },
      })
      result = r.ok ? 'ok' : `error: HTTP ${r.status}`
    } else {
      return { error: `Serviço ${service} não tem teste implementado` }
    }

    // Atualiza todas as keys do serviço com o resultado
    await svc
      .from('service_credentials')
      .update({
        last_tested_at: new Date().toISOString(),
        last_test_result: result,
      })
      .eq('service', service)

    revalidatePath('/settings/api-keys')
    return { ok: true, result }
  } catch (e) {
    return { error: e instanceof Error ? e.message : String(e) }
  }
}
