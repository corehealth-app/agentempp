import type { ServiceClient } from '@mpp/db'
import type { ContentCoverCapabilityCodec } from '@/lib/mobile-api/content-cover-capability'
import { createDefaultContentCoverCapabilityCodec } from '@/lib/mobile-api/content-cover-capability'
import type { ContentRepository } from '@/lib/mobile-api/content-service'
import { createSupabaseContentDependencies } from '@/lib/mobile-api/supabase-content'
import { createServiceClient } from '@/lib/supabase/server'

const CONTENT_COVERS_BUCKET = 'content-covers'
const ALLOWED_IMAGE_TYPES = new Set(['image/jpeg', 'image/png', 'image/webp'])

export interface ContentCoverProxyRouteContext {
  params: Promise<{ token: string }>
}

export interface ContentCoverProxyDependencies {
  capabilities: Pick<ContentCoverCapabilityCodec, 'open'>
  repository: Pick<ContentRepository, 'get'>
  storage: {
    download(bucketId: string, objectPath: string): Promise<Blob>
  }
  clock: () => number
}

function opaqueError(status: 404 | 500): Response {
  const internal = status === 500
  return Response.json(
    {
      error: {
        code: internal ? 'internal_error' : 'content_cover_not_found',
        message: internal ? 'Unexpected server error' : 'Content cover not found',
      },
    },
    {
      status,
      headers: {
        'Cache-Control': 'no-store',
        'Content-Type': 'application/json; charset=utf-8',
      },
    },
  )
}

export async function handleContentCoverProxy(
  routeContext: ContentCoverProxyRouteContext,
  dependencies: ContentCoverProxyDependencies,
): Promise<Response> {
  const { token } = await routeContext.params
  let capability: ReturnType<ContentCoverProxyDependencies['capabilities']['open']>
  try {
    capability = dependencies.capabilities.open(token)
  } catch {
    return opaqueError(404)
  }

  let record: Awaited<ReturnType<ContentCoverProxyDependencies['repository']['get']>>
  try {
    record = await dependencies.repository.get(capability.userId, capability.publicationId)
  } catch {
    return opaqueError(500)
  }

  const remainingSeconds = capability.expiresAt - Math.floor(dependencies.clock() / 1000)
  if (
    !record ||
    record.publicationId !== capability.publicationId ||
    record.version !== capability.version ||
    !record.cover ||
    record.cover.bucketId !== CONTENT_COVERS_BUCKET ||
    remainingSeconds <= 0 ||
    remainingSeconds > 300
  ) {
    return opaqueError(404)
  }

  let image: Blob
  try {
    image = await dependencies.storage.download(CONTENT_COVERS_BUCKET, record.cover.objectPath)
  } catch {
    return opaqueError(404)
  }
  const contentType = image.type.toLowerCase()
  if (!ALLOWED_IMAGE_TYPES.has(contentType)) return opaqueError(404)

  return new Response(image, {
    status: 200,
    headers: {
      'Cache-Control': `private, max-age=${remainingSeconds}`,
      'Content-Type': contentType,
      'X-Content-Type-Options': 'nosniff',
    },
  })
}

function createDefaultDependencies(): ContentCoverProxyDependencies {
  const supabase: ServiceClient = createServiceClient()
  return {
    capabilities: createDefaultContentCoverCapabilityCodec(),
    repository: createSupabaseContentDependencies(supabase).repository,
    storage: {
      async download(bucketId, objectPath) {
        if (bucketId !== CONTENT_COVERS_BUCKET) throw new Error('Invalid content cover bucket')
        const { data, error } = await supabase.storage
          .from(CONTENT_COVERS_BUCKET)
          .download(objectPath)
        if (error || !data) throw new Error('Content cover download failed')
        return data
      },
    },
    clock: Date.now,
  }
}

export function createContentCoverProxyRoute(
  createDependencies: () => ContentCoverProxyDependencies = createDefaultDependencies,
) {
  return (_request: Request, routeContext: ContentCoverProxyRouteContext): Promise<Response> =>
    handleContentCoverProxy(routeContext, createDependencies())
}
