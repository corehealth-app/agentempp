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
})
