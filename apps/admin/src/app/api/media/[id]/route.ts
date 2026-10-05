/**
 * GET /api/media/[id]
 * Proxy pra baixar mídia do WhatsApp Cloud API. O mediaId vem dos webhooks
 * (raw_payload.image.id ou raw_payload.audio.id), e o admin precisa do
 * access_token pra resolver a URL real e baixar bytes.
 *
 * Esta rota fica atrás da tela Conversas (é a prévia de mídia de uma
 * mensagem): só passa quem pode abrir a tela, pela mesma regra do guarda da
 * página. Até 2026-10-05 bastava ter uma linha em admin_users, com qualquer
 * papel.
 */
import type { NextRequest } from 'next/server'
import { checkAdminPageAccess } from '@/lib/admin-page-guard'
import { createServiceClient } from '@/lib/supabase/server'

export const runtime = 'nodejs'

async function loadMetaCredentials() {
  const svc = createServiceClient()
  const { data } = await svc
    .from('service_credentials')
    .select('key_name, value')
    .eq('service', 'meta_whatsapp')
    .eq('is_active', true)
    .in('key_name', ['access_token'])
  const map = new Map<string, string>()
  for (const r of data ?? []) {
    map.set((r as { key_name: string }).key_name, (r as { value: string }).value)
  }
  return { accessToken: map.get('access_token') ?? null }
}

export async function GET(
  _req: NextRequest,
  { params }: { params: Promise<{ id: string }> },
) {
  const { id } = await params

  // Auth: quem pode abrir Conversas.
  const access = await checkAdminPageAccess('/messages')
  if (!access.ok) {
    return access.reason === 'anonymous'
      ? new Response('unauthenticated', { status: 401 })
      : new Response('forbidden', { status: 403 })
  }

  // Credenciais
  const { accessToken } = await loadMetaCredentials()
  if (!accessToken) return new Response('Meta access_token not configured', { status: 500 })

  // 1. Resolve URL via Graph API
  const metaRes = await fetch(`https://graph.facebook.com/v21.0/${id}`, {
    headers: { Authorization: `Bearer ${accessToken}` },
  })
  if (!metaRes.ok) {
    const err = await metaRes.text()
    return new Response(`Failed to resolve media ${id}: ${err}`, { status: 502 })
  }
  const meta = (await metaRes.json()) as { url?: string; mime_type?: string }
  if (!meta.url) return new Response('No URL returned by Meta', { status: 502 })

  // 2. Download bytes
  const blobRes = await fetch(meta.url, {
    headers: { Authorization: `Bearer ${accessToken}` },
  })
  if (!blobRes.ok) {
    return new Response(`Failed to download: ${blobRes.status}`, { status: 502 })
  }

  const blob = await blobRes.blob()
  const buffer = await blob.arrayBuffer()

  return new Response(buffer, {
    headers: {
      'Content-Type': meta.mime_type ?? blobRes.headers.get('content-type') ?? 'application/octet-stream',
      'Cache-Control': 'private, max-age=3600',
      'Content-Disposition': 'inline',
    },
  })
}
