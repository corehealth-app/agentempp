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

class StrictJsonParser {
  private position = 0

  constructor(private readonly source: string) {}

  parse(): unknown {
    this.skipWhitespace()
    const value = this.parseValue(0)
    this.skipWhitespace()
    if (this.position !== this.source.length) throw new SyntaxError('Unexpected JSON suffix')
    return value
  }

  private parseValue(depth: number): unknown {
    if (depth > 128) throw new SyntaxError('JSON nesting limit exceeded')
    const character = this.source[this.position]
    if (character === '{') return this.parseObject(depth + 1)
    if (character === '[') return this.parseArray(depth + 1)
    if (character === '"') return this.parseString()
    if (character === 't') return this.parseLiteral('true', true)
    if (character === 'f') return this.parseLiteral('false', false)
    if (character === 'n') return this.parseLiteral('null', null)
    return this.parseNumber()
  }

  private parseObject(depth: number): Record<string, unknown> {
    this.position++
    this.skipWhitespace()
    const result: Record<string, unknown> = {}
    const keys = new Set<string>()
    if (this.consume('}')) return result

    while (true) {
      if (this.source[this.position] !== '"') throw new SyntaxError('JSON object key required')
      const key = this.parseString()
      if (keys.has(key)) throw new SyntaxError('Duplicate JSON object key')
      keys.add(key)
      this.skipWhitespace()
      if (!this.consume(':')) throw new SyntaxError('JSON object colon required')
      this.skipWhitespace()
      const value = this.parseValue(depth)
      Object.defineProperty(result, key, {
        value,
        enumerable: true,
        configurable: true,
        writable: true,
      })
      this.skipWhitespace()
      if (this.consume('}')) return result
      if (!this.consume(',')) throw new SyntaxError('JSON object comma required')
      this.skipWhitespace()
    }
  }

  private parseArray(depth: number): unknown[] {
    this.position++
    this.skipWhitespace()
    const result: unknown[] = []
    if (this.consume(']')) return result

    while (true) {
      result.push(this.parseValue(depth))
      this.skipWhitespace()
      if (this.consume(']')) return result
      if (!this.consume(',')) throw new SyntaxError('JSON array comma required')
      this.skipWhitespace()
    }
  }

  private parseString(): string {
    const start = this.position
    this.position++
    while (this.position < this.source.length) {
      const character = this.source[this.position]
      if (character === '"') {
        this.position++
        return JSON.parse(this.source.slice(start, this.position)) as string
      }
      if (character === '\\') {
        this.position++
        const escapeCode = this.source[this.position]
        if (escapeCode === 'u') {
          const codePoint = this.source.slice(this.position + 1, this.position + 5)
          if (!/^[0-9A-Fa-f]{4}$/.test(codePoint)) throw new SyntaxError('Invalid JSON escape')
          this.position += 5
          continue
        }
        if (!escapeCode || !'"\\/bfnrt'.includes(escapeCode))
          throw new SyntaxError('Invalid JSON escape')
        this.position++
        continue
      }
      if (character.charCodeAt(0) <= 0x1f) throw new SyntaxError('Invalid JSON string')
      this.position++
    }
    throw new SyntaxError('Unterminated JSON string')
  }

  private parseLiteral<T>(literal: string, value: T): T {
    if (!this.source.startsWith(literal, this.position))
      throw new SyntaxError('Invalid JSON literal')
    this.position += literal.length
    return value
  }

  private parseNumber(): number {
    const match = this.source
      .slice(this.position)
      .match(/^-?(?:0|[1-9][0-9]*)(?:\.[0-9]+)?(?:[eE][+-]?[0-9]+)?/)
    if (!match) throw new SyntaxError('Invalid JSON number')
    this.position += match[0].length
    return Number(match[0])
  }

  private consume(character: string): boolean {
    if (this.source[this.position] !== character) return false
    this.position++
    return true
  }

  private skipWhitespace(): void {
    while (
      this.source[this.position] === ' ' ||
      this.source[this.position] === '\t' ||
      this.source[this.position] === '\r' ||
      this.source[this.position] === '\n'
    ) {
      this.position++
    }
  }
}

async function readBoundedUtf8Body(request: Request, maxBytes: number): Promise<string> {
  if (!request.body) return ''
  const reader = request.body.getReader()
  const decoder = new TextDecoder('utf-8', { fatal: true })
  let byteLength = 0
  let text = ''

  while (true) {
    const { done, value } = await reader.read()
    if (done) break
    byteLength += value.byteLength
    if (byteLength > maxBytes) {
      await reader.cancel().catch(() => undefined)
      throw new MobileApiError(413, 'request_too_large', 'Request body is too large')
    }
    text += decoder.decode(value, { stream: true })
  }
  return text + decoder.decode()
}

export async function readJsonBody(request: Request, maxBytes = 64 * 1024): Promise<unknown> {
  const contentType = request.headers.get('content-type')
  if (
    !contentType ||
    !/^[ \t]*application\/json(?:[ \t]*;[ \t]*charset[ \t]*=[ \t]*(?:utf-8|"utf-8"))?[ \t]*$/i.test(
      contentType,
    )
  ) {
    throw new MobileApiError(415, 'unsupported_media_type', 'Content-Type must be application/json')
  }

  const contentLength = request.headers.get('content-length')
  if (contentLength && Number(contentLength) > maxBytes) {
    throw new MobileApiError(413, 'request_too_large', 'Request body is too large')
  }

  let text: string
  try {
    text = await readBoundedUtf8Body(request, maxBytes)
  } catch (error) {
    if (error instanceof MobileApiError) throw error
    throw new MobileApiError(400, 'invalid_json', 'Request body must contain valid JSON')
  }
  if (!text || /^[ \t\r\n]*$/.test(text))
    throw new MobileApiError(400, 'invalid_json', 'JSON body is required')

  try {
    return new StrictJsonParser(text).parse()
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
