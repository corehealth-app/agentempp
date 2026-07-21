import type { ContentCoverCapabilityCodec } from '@/lib/mobile-api/content-cover-capability'
import { createDefaultContentCoverCapabilityCodec } from '@/lib/mobile-api/content-cover-capability'
import type { ContentRepository } from '@/lib/mobile-api/content-service'
import { MobileApiError, mobileErrorResponse } from '@/lib/mobile-api/http'
import {
  createMobileRouteWithContext,
  type MobileRouteContext,
  type MobileRouteRuntime,
} from '@/lib/mobile-api/route'
import { createSupabaseContentDependencies } from '@/lib/mobile-api/supabase-content'

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

type ContentCoverProxyContext = Pick<MobileRouteContext, 'auth' | 'requestId'>

type ProxyFailureOperation =
  | 'capability_open'
  | 'capability_authorization'
  | 'repository_get'
  | 'cover_revalidate'
  | 'storage_download'
  | 'content_type'
  | 'dependency_init'

type ProxyFailureCode =
  | 'invalid_capability'
  | 'not_found'
  | 'repository_error'
  | 'storage_error'
  | 'unsupported_content_type'
  | 'internal_error'

function proxyFailure(
  requestId: string,
  operation: ProxyFailureOperation,
  errorCode: ProxyFailureCode,
): void {
  console.error('[mobile-content-cover] operation_failed', {
    request_id: /^[A-Za-z0-9._:-]{8,128}$/.test(requestId) ? requestId : 'unknown',
    operation,
    error_code: errorCode,
  })
}

function opaqueError(status: 404 | 500, requestId: string): Response {
  const internal = status === 500
  return mobileErrorResponse(
    new MobileApiError(
      status,
      internal ? 'internal_error' : 'content_cover_not_found',
      internal ? 'Unexpected server error' : 'Content cover not found',
    ),
    requestId,
  )
}

export async function handleContentCoverProxy(
  context: ContentCoverProxyContext,
  routeContext: ContentCoverProxyRouteContext,
  dependencies: ContentCoverProxyDependencies,
): Promise<Response> {
  const { token } = await routeContext.params
  let capability: ReturnType<ContentCoverProxyDependencies['capabilities']['open']>
  try {
    capability = dependencies.capabilities.open(token)
  } catch {
    proxyFailure(context.requestId, 'capability_open', 'invalid_capability')
    return opaqueError(404, context.requestId)
  }
  if (capability.userId !== context.auth.userId) {
    proxyFailure(context.requestId, 'capability_authorization', 'not_found')
    return opaqueError(404, context.requestId)
  }

  let record: Awaited<ReturnType<ContentCoverProxyDependencies['repository']['get']>>
  try {
    record = await dependencies.repository.get(context.auth.userId, capability.publicationId)
  } catch {
    proxyFailure(context.requestId, 'repository_get', 'repository_error')
    return opaqueError(500, context.requestId)
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
    proxyFailure(context.requestId, 'cover_revalidate', 'not_found')
    return opaqueError(404, context.requestId)
  }

  let image: Blob
  try {
    image = await dependencies.storage.download(CONTENT_COVERS_BUCKET, record.cover.objectPath)
  } catch {
    proxyFailure(context.requestId, 'storage_download', 'storage_error')
    return opaqueError(404, context.requestId)
  }
  const contentType = image.type.toLowerCase()
  if (!ALLOWED_IMAGE_TYPES.has(contentType)) {
    proxyFailure(context.requestId, 'content_type', 'unsupported_content_type')
    return opaqueError(404, context.requestId)
  }

  return new Response(image, {
    status: 200,
    headers: {
      'Cache-Control': `private, max-age=${remainingSeconds}`,
      'Content-Type': contentType,
      Vary: 'Authorization',
      'X-Content-Type-Options': 'nosniff',
      'X-Request-Id': context.requestId,
    },
  })
}

function createDefaultDependencies(context: MobileRouteContext): ContentCoverProxyDependencies {
  return {
    capabilities: createDefaultContentCoverCapabilityCodec(),
    repository: createSupabaseContentDependencies(context.supabase, {
      requestId: context.requestId,
    }).repository,
    storage: {
      async download(bucketId, objectPath) {
        if (bucketId !== CONTENT_COVERS_BUCKET) throw new Error('Invalid content cover bucket')
        const { data, error } = await context.supabase.storage
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
  mobileRuntime?: MobileRouteRuntime,
  createDependencies: (
    context: MobileRouteContext,
  ) => ContentCoverProxyDependencies = createDefaultDependencies,
) {
  return createMobileRouteWithContext<ContentCoverProxyRouteContext>(
    async (context, routeContext) => {
      let dependencies: ContentCoverProxyDependencies
      try {
        dependencies = createDependencies(context)
      } catch {
        proxyFailure(context.requestId, 'dependency_init', 'internal_error')
        return opaqueError(500, context.requestId)
      }
      return handleContentCoverProxy(context, routeContext, dependencies)
    },
    mobileRuntime,
  )
}
