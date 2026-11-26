import { generateKeyPairSync, verify } from 'node:crypto'
import { describe, expect, it, vi } from 'vitest'
import { createFlowMealGapPush } from './flow-meal-gap-apns.js'

const keys = generateKeyPairSync('ec', { namedCurve: 'P-256' })
const config = {
  privateKey: keys.privateKey.export({ type: 'pkcs8', format: 'pem' }).toString(),
  keyId: 'SYNTHETIC1',
  teamId: 'SYNTHETIC2',
  topic: 'com.example.performe.qa',
}
const notice = {
  environment: 'sandbox' as const,
  token: 'a'.repeat(64),
  id: 'c342ba13-15b0-4b1c-b56a-e2208a77cf14',
  ownerKey: 'ef7eaf73',
  language: 'pt-BR' as const,
  expiresAt: Date.parse('2026-11-26T20:45:00Z'),
}
const now = Date.parse('2026-11-26T20:30:00Z')

describe('meal reminder device push', () => {
  it('signs a valid token and sends a quiet-preview-safe payload with a stable collapse identifier', async () => {
    const exchange = vi.fn<NonNullable<Parameters<typeof createFlowMealGapPush>[1]>>(async () => ({
      status: 200,
      reason: null,
    }))
    const send = createFlowMealGapPush(config, exchange, () => now)
    expect(await send(notice)).toBe('accepted')
    const request = exchange.mock.calls[0]![0]
    expect(request.host).toBe('https://api.sandbox.push.apple.com')
    expect(request.headers).toMatchObject({
      ':method': 'POST',
      ':path': '/3/device/' + notice.token,
      'apns-id': notice.id,
      'apns-collapse-id': notice.id,
      'apns-topic': config.topic,
      'apns-push-type': 'alert',
      'apns-expiration': String(notice.expiresAt / 1000),
    })
    const [header, claims, signature] = request.headers.authorization.slice(7).split('.') as [
      string,
      string,
      string,
    ]
    expect(JSON.parse(Buffer.from(header, 'base64url').toString())).toEqual({
      alg: 'ES256',
      kid: config.keyId,
    })
    expect(JSON.parse(Buffer.from(claims, 'base64url').toString())).toEqual({
      iss: config.teamId,
      iat: now / 1000,
    })
    expect(
      verify(
        'sha256',
        Buffer.from(header + '.' + claims),
        { key: keys.publicKey, dsaEncoding: 'ieee-p1363' },
        Buffer.from(signature, 'base64url'),
      ),
    ).toBe(true)
    expect(JSON.parse(request.body)).toEqual({
      aps: { alert: { title: 'Performe AI', body: 'Você tem uma mensagem do Flow.' } },
      flow_meal_gap: notice.id,
      owner: notice.ownerKey,
    })
    await send({ ...notice, environment: 'production' })
    expect(exchange).toHaveBeenLastCalledWith(
      expect.objectContaining({
        host: 'https://api.push.apple.com',
        headers: expect.objectContaining({ authorization: request.headers.authorization }),
      }),
    )
  })

  it.each([
    [410, 'Unregistered', 'unregistered'],
    [400, 'BadDeviceToken', 'rejected'],
    [403, 'ExpiredProviderToken', 'retry'],
    [429, 'TooManyRequests', 'retry'],
    [503, 'Shutdown', 'retry'],
  ] as const)('classifies APNs status %i without propagating response details', async (status, reason, expected) => {
    const send = createFlowMealGapPush(
      config,
      async () => ({ status, reason }),
      () => now,
    )
    expect(await send(notice)).toBe(expected)
  })

  it('does not ask APNs to send a stale reminder or a malformed device token', async () => {
    const exchange = vi.fn<NonNullable<Parameters<typeof createFlowMealGapPush>[1]>>(async () => ({
      status: 200,
      reason: null,
    }))
    const send = createFlowMealGapPush(config, exchange, () => now)
    expect(await send({ ...notice, expiresAt: now })).toBe('expired')
    await expect(send({ ...notice, token: '../other' })).rejects.toThrow(
      'Invalid meal reminder device',
    )
    expect(exchange).not.toHaveBeenCalled()
  })

  it('treats disconnect as uncertain and leaves replay with the same id to the worker', async () => {
    const send = createFlowMealGapPush(
      config,
      async () => {
        throw new Error('connection lost')
      },
      () => now,
    )
    expect(await send(notice)).toBe('retry')
  })
})
