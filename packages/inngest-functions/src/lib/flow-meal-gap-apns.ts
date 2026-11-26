import { createPrivateKey, sign } from 'node:crypto'
import { connect, sensitiveHeaders } from 'node:http2'

interface FlowMealGapPushConfig {
  privateKey: string
  keyId: string
  teamId: string
  topic: string
}

export interface FlowMealGapPushNotice {
  environment: 'sandbox' | 'production'
  token: string
  id: string
  ownerKey: string
  language: 'pt-BR' | 'en-US'
  expiresAt: number
}

export type FlowMealGapPushOutcome = 'accepted' | 'retry' | 'unregistered' | 'rejected' | 'expired'

interface PushRequest {
  host: string
  headers: Record<string, string> & { authorization: string }
  body: string
}

type Exchange = (request: PushRequest) => Promise<{ status: number; reason: string | null }>

const providers = {
  sandbox: 'https://api.sandbox.push.apple.com',
  production: 'https://api.push.apple.com',
}
const attemptId = /^[\da-f]{8}(?:-[\da-f]{4}){3}-[\da-f]{12}$/u

function sendOverHttp2(input: PushRequest): ReturnType<Exchange> {
  return new Promise((resolve, reject) => {
    const session = connect(input.host, { minVersion: 'TLSv1.2' })
    const fail = () => {
      clearTimeout(deadline)
      session.destroy()
      reject(new Error('Meal reminder push connection failed'))
    }
    const deadline = setTimeout(fail, 8000)
    let status = 0
    let body = ''
    session.once('error', fail)
    const stream = session.request({
      ...input.headers,
      [sensitiveHeaders]: [':path', 'authorization'],
    })
    stream.once('error', fail)
    stream.once('aborted', fail)
    stream.once('response', (headers) => {
      status = Number(headers[':status'])
    })
    stream.setEncoding('utf8')
    stream.on('data', (chunk: string) => {
      body += chunk
      if (body.length > 4096) fail()
    })
    stream.once('end', () => {
      clearTimeout(deadline)
      session.close()
      let reason: string | null = null
      if (body) {
        try {
          const value = JSON.parse(body)
          if (typeof value?.reason === 'string') reason = value.reason
        } catch {
          // An unparseable body cannot authorize invalidation of the device.
        }
      }
      resolve({ status, reason })
    })
    stream.end(input.body)
  })
}

const encode = (value: object) => Buffer.from(JSON.stringify(value)).toString('base64url')

export function createFlowMealGapPush(
  config: FlowMealGapPushConfig,
  exchange: Exchange = sendOverHttp2,
  clock: () => number = Date.now,
) {
  const { keyId, teamId, topic } = config
  if (
    !/^[A-Z0-9]{10}$/u.test(keyId) ||
    !/^[A-Z0-9]{10}$/u.test(teamId) ||
    !/^[A-Za-z0-9-]+(?:\.[A-Za-z0-9-]+)+$/u.test(topic)
  ) {
    throw new Error('Invalid meal reminder push configuration')
  }
  const key = createPrivateKey(config.privateKey)
  if (key.asymmetricKeyType !== 'ec' || key.asymmetricKeyDetails?.namedCurve !== 'prime256v1') {
    throw new Error('Invalid meal reminder push signing key')
  }
  let authorization: { issuedAt: number; value: string } | undefined
  function providerToken(now: number) {
    const iat = Math.floor(now / 1000)
    if (!authorization || iat < authorization.issuedAt || iat - authorization.issuedAt >= 45 * 60) {
      const bytes = encode({ alg: 'ES256', kid: keyId }) + '.' + encode({ iss: teamId, iat })
      const signature = sign('sha256', Buffer.from(bytes), {
        key,
        dsaEncoding: 'ieee-p1363',
      }).toString('base64url')
      authorization = { issuedAt: iat, value: 'bearer ' + bytes + '.' + signature }
    }
    return authorization.value
  }

  return async (notice: FlowMealGapPushNotice): Promise<FlowMealGapPushOutcome> => {
    const now = clock()
    const expiresAt = Math.floor(notice.expiresAt / 1000)
    if (!Number.isFinite(expiresAt) || expiresAt <= Math.floor(now / 1000)) return 'expired'
    if (
      (notice.environment !== 'sandbox' && notice.environment !== 'production') ||
      !/^(?:[\da-f]{2}){32,256}$/u.test(notice.token) ||
      !attemptId.test(notice.id) ||
      !/^[\da-f]{8}$/u.test(notice.ownerKey)
    )
      throw new Error('Invalid meal reminder device')

    try {
      const response = await exchange({
        host: providers[notice.environment],
        headers: {
          ':method': 'POST',
          ':path': '/3/device/' + notice.token,
          authorization: providerToken(now),
          'content-type': 'application/json',
          'apns-id': notice.id,
          'apns-collapse-id': notice.id,
          'apns-topic': topic,
          'apns-push-type': 'alert',
          'apns-priority': '10',
          'apns-expiration': String(expiresAt),
        },
        body: JSON.stringify({
          aps: {
            alert: {
              title: 'Performe AI',
              body:
                notice.language === 'en-US'
                  ? 'You have a message from Flow.'
                  : 'Você tem uma mensagem do Flow.',
            },
          },
          flow_meal_gap: notice.id,
          owner: notice.ownerKey,
        }),
      })
      if (response.status === 200) return 'accepted'
      if (response.status === 410 && response.reason === 'Unregistered') return 'unregistered'
      if (response.status === 403 && response.reason === 'ExpiredProviderToken') {
        authorization = undefined
        return 'retry'
      }
      if (!response.status || response.status === 429 || response.status >= 500) return 'retry'
      return 'rejected'
    } catch {
      // The provider may have accepted the request before the connection closed.
      return 'retry'
    }
  }
}
