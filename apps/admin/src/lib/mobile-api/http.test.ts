import { describe, expect, it } from 'vitest'
import {
  extractBearerToken,
  MobileApiError,
  mobileErrorResponse,
  mobileSuccess,
  readJsonBody,
} from './http'

describe('mobile API v1 HTTP boundary', () => {
  it('extracts only a valid bearer token', () => {
    expect(extractBearerToken(new Headers({ authorization: 'Bearer token-value' }))).toBe(
      'token-value',
    )
    expect(extractBearerToken(new Headers({ authorization: 'Basic abc' }))).toBeNull()
    expect(extractBearerToken(new Headers({ authorization: 'Bearer ' }))).toBeNull()
  })

  it('returns a stable success envelope without caching patient data', async () => {
    const response = mobileSuccess({ id: 'patient-1' }, 'request-1')

    expect(response.status).toBe(200)
    expect(response.headers.get('cache-control')).toBe('no-store')
    expect(response.headers.get('x-request-id')).toBe('request-1')
    expect(await response.json()).toEqual({
      data: { id: 'patient-1' },
      meta: { api_version: 'v1', request_id: 'request-1' },
    })
  })

  it('returns a stable error envelope without exposing internal causes', async () => {
    const response = mobileErrorResponse(
      new MobileApiError(401, 'invalid_access_token', 'Authentication required'),
      'request-2',
    )

    expect(response.status).toBe(401)
    expect(await response.json()).toEqual({
      error: {
        code: 'invalid_access_token',
        message: 'Authentication required',
        request_id: 'request-2',
      },
    })
  })

  it('accepts bounded JSON and rejects unsupported bodies', async () => {
    await expect(
      readJsonBody(
        new Request('https://example.test', {
          method: 'POST',
          headers: { 'content-type': 'application/json; charset=utf-8' },
          body: '{"ok":true}',
        }),
      ),
    ).resolves.toEqual({ ok: true })

    await expect(
      readJsonBody(
        new Request('https://example.test', {
          method: 'POST',
          headers: { 'content-type': 'text/plain' },
          body: '{}',
        }),
      ),
    ).rejects.toMatchObject({ status: 415, code: 'unsupported_media_type' })
  })

  it('accepts a syntactically valid quoted utf-8 charset', async () => {
    await expect(
      readJsonBody(
        new Request('https://example.test', {
          method: 'POST',
          headers: { 'content-type': 'application/json; charset="utf-8"' },
          body: '{"ok":true}',
        }),
      ),
    ).resolves.toEqual({ ok: true })
  })

  it.each([
    '{"name":"first","name":"second"}',
    '{"outer":{"name":"first","name":"second"}}',
    '{"name":"first","\\u006eame":"second"}',
  ])('rejects duplicate JSON object keys before information is lost: %s', async (body) => {
    await expect(
      readJsonBody(
        new Request('https://example.test', {
          method: 'POST',
          headers: { 'content-type': 'application/json' },
          body,
        }),
      ),
    ).rejects.toMatchObject({
      status: 400,
      code: 'invalid_json',
      message: 'Request body must contain valid JSON',
    })
  })

  it.each([
    'application/json; text/plain',
    'application/json; charset=latin1',
    'application/json; charset=utf-8; charset=utf-8',
    'application/problem+json',
    'application/json;',
    'application/json;\u00a0charset=utf-8',
  ])('rejects ambiguous or malformed JSON media type: %s', async (contentType) => {
    await expect(
      readJsonBody(
        new Request('https://example.test', {
          method: 'POST',
          headers: { 'content-type': contentType },
          body: '{}',
        }),
      ),
    ).rejects.toMatchObject({ status: 415, code: 'unsupported_media_type' })
  })

  it('stops reading a streamed JSON body as soon as maxBytes is exceeded', async () => {
    let pulls = 0
    const body = new ReadableStream<Uint8Array>(
      {
        pull(controller) {
          pulls++
          if (pulls === 1) {
            controller.enqueue(new TextEncoder().encode('{"too":"large"}'))
            return
          }
          throw new Error('body was read past the byte limit')
        },
      },
      { highWaterMark: 0 },
    )
    const request = new Request('https://example.test', {
      method: 'POST',
      headers: { 'content-type': 'application/json' },
      body,
      duplex: 'half',
    } as RequestInit & { duplex: 'half' })

    await expect(readJsonBody(request, 8)).rejects.toMatchObject({
      status: 413,
      code: 'request_too_large',
    })
    expect(pulls).toBe(1)
  })

  it('rejects whitespace outside the JSON grammar', async () => {
    await expect(
      readJsonBody(
        new Request('https://example.test', {
          method: 'POST',
          headers: { 'content-type': 'application/json' },
          body: '\u00a0{}',
        }),
      ),
    ).rejects.toMatchObject({
      status: 400,
      code: 'invalid_json',
      message: 'Request body must contain valid JSON',
    })
  })
})
