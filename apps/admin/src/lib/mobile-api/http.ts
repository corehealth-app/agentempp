import type { ZodError } from 'zod'

export class MobileApiError extends Error {
  constructor(
    readonly status: number,
    readonly code: string,
    message: string,
    readonly details?: unknown,
  ) {
    super(message)
    this.name = 'MobileApiError'
  }
}

function responseHeaders(requestId: string): HeadersInit {
  return {
    'Cache-Control': 'no-store',
    'Content-Type': 'application/json; charset=utf-8',
    Vary: 'Authorization',
    'X-Request-Id': requestId,
  }
}

export function extractBearerToken(headers: Headers): string | null {
  const authorization = headers.get('authorization')
  if (!authorization) return null
  const match = authorization.match(/^Bearer ([^\s,]+)$/)
  return match?.[1] ?? null
}

export async function readJsonBody(request: Request, maxBytes = 64 * 1024): Promise<unknown> {
  const contentType = request.headers.get('content-type')?.split(';', 1)[0]?.trim().toLowerCase()
  if (contentType !== 'application/json') {
    throw new MobileApiError(415, 'unsupported_media_type', 'Content-Type must be application/json')
  }

  const contentLength = request.headers.get('content-length')
  if (contentLength && Number(contentLength) > maxBytes) {
    throw new MobileApiError(413, 'request_too_large', 'Request body is too large')
  }

  const text = await request.text()
  if (new TextEncoder().encode(text).byteLength > maxBytes) {
    throw new MobileApiError(413, 'request_too_large', 'Request body is too large')
  }
  if (!text.trim()) throw new MobileApiError(400, 'invalid_json', 'JSON body is required')

  try {
    return JSON.parse(text)
  } catch {
    throw new MobileApiError(400, 'invalid_json', 'Request body must contain valid JSON')
  }
}

export function mobileSuccess<T>(
  data: T,
  requestId: string,
  status = 200,
  additionalHeaders?: HeadersInit,
): Response {
  return Response.json(
    { data, meta: { api_version: 'v1', request_id: requestId } },
    {
      status,
      headers: { ...responseHeaders(requestId), ...additionalHeaders },
    },
  )
}

export function mobileErrorResponse(error: MobileApiError, requestId: string): Response {
  return Response.json(
    {
      error: {
        code: error.code,
        message: error.message,
        request_id: requestId,
        ...(error.details === undefined ? {} : { details: error.details }),
      },
    },
    { status: error.status, headers: responseHeaders(requestId) },
  )
}

export function validationError(error: ZodError): MobileApiError {
  return new MobileApiError(422, 'validation_failed', 'Request validation failed', {
    fields: error.issues.map((issue) => ({
      path: issue.path.join('.'),
      code: issue.code,
      message: issue.message,
    })),
  })
}
