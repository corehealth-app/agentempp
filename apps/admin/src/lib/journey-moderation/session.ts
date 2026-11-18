import { z } from 'zod'
import { socialUUID } from '../mobile-api/journey-social-contracts'
import {
  createJourneyModerationService,
  JourneyModerationError,
  type JourneyModerationRPCPort,
} from './service'

export interface JourneyModerationSessionDependencies {
  enabled(): boolean
  expectedIssuer: string
  now(): number
  readCookieAccessToken(): Promise<string | null>
  /** Must call the configured project's Auth.getUser(exactToken). */
  verifyAccessToken(token: string): Promise<{ id: string } | null>
  readOperatorRole(actor: string): Promise<unknown>
  createRPCPort(): JourneyModerationRPCPort
}
const claims = z
  .object({
    sub: socialUUID,
    session_id: socialUUID,
    iss: z.string(),
    aud: z.union([
      z.literal('authenticated'),
      z.array(z.string()).refine((v) => v.includes('authenticated')),
    ]),
    role: z.literal('authenticated'),
    is_anonymous: z.literal(false).optional(),
    exp: z.number().int().safe(),
    nbf: z.number().int().safe().optional(),
  })
  .passthrough()
const operator = z
  .object({ id: socialUUID, role: z.enum(['operations_admin', 'master_admin']) })
  .strict()

/** Cookie content supplies no authority. Verify its exact access token first;
 * decoded claims only bind that verified user to the login SQL will lock. */
export async function createJourneyModerationSession(deps: JourneyModerationSessionDependencies) {
  async function admit() {
    if (!deps.enabled()) throw new JourneyModerationError('unavailable')
    const token = await deps.readCookieAccessToken()
    if (!token) throw new JourneyModerationError('unauthorized')
    const user = await deps.verifyAccessToken(token)
    if (!user) throw new JourneyModerationError('unauthorized')
    let body: z.infer<typeof claims>
    try {
      const parts = token.split('.')
      if (parts.length !== 3 || parts.some((p) => !/^[\w-]+$/u.test(p)))
        throw new Error('Invalid token shape')
      body = claims.parse(JSON.parse(Buffer.from(parts[1] ?? '', 'base64url').toString('utf8')))
    } catch {
      throw new JourneyModerationError('unauthorized')
    }
    if (
      body.sub !== user.id.toLowerCase() ||
      body.iss !== deps.expectedIssuer ||
      body.exp <= deps.now() ||
      (body.nbf !== undefined && body.nbf > deps.now())
    )
      throw new JourneyModerationError('unauthorized')
    const role = operator.safeParse(await deps.readOperatorRole(body.sub))
    if (!role.success || role.data.id !== body.sub) throw new JourneyModerationError('forbidden')
    return Object.freeze({ actor: body.sub, login: body.session_id })
  }
  const identity = await admit()
  const service = createJourneyModerationService(deps.createRPCPort(), identity, async () => {
    const current = await admit()
    if (current.actor !== identity.actor || current.login !== identity.login)
      throw new JourneyModerationError('unauthorized')
  })
  return Object.freeze({ identity, service })
}
