import type { ServiceClient } from '@mpp/db'
import { z } from 'zod'
import { createServiceClient } from '../supabase/server'
import type { MobileAuthContext } from './auth'
import { authorizeMobileEntitlement } from './entitlement-service'
import { extractBearerToken, MobileApiError } from './http'
import { socialUUID } from './journey-social-contracts'
import type { MobileRouteRuntime } from './route'
import { createMobileAuthDependencies } from './supabase-auth'

const identitySchema = z
  .object({ id: socialUUID, email: z.string().nullable(), emailConfirmedAt: z.string().nullable() })
  .strict()
const patientSchema = z
  .object({
    id: socialUUID,
    authUserId: socialUUID,
    email: z.string().nullable(),
    name: z.string().nullable(),
    locale: z.string().nullable(),
    timezone: z.string().nullable(),
    country: z.string().nullable(),
    countryConfirmed: z.boolean(),
    status: z.string(),
  })
  .strict()
function unavailable(status: number, code: string): never {
  throw new MobileApiError(status, code, 'The original authenticated patient is required.')
}
export function journeySocialOwner(auth: MobileAuthContext): string {
  if (
    ![
      auth?.userId,
      auth?.authUserId,
      auth?.identity?.id,
      auth?.patient?.id,
      auth?.patient?.authUserId,
    ].every((id) => socialUUID.safeParse(id).success) ||
    auth.userId !== auth.patient.id ||
    auth.authUserId !== auth.identity.id ||
    auth.authUserId !== auth.patient.authUserId ||
    auth.patient.status !== 'active'
  )
    return unavailable(403, 'journey_social_identity_invalid')
  return auth.userId
}
/** Reuse the actual SDK verifier and existing-patient lookup. Deliberately no
 * bootstrap, clinical-state capture, token refresh, epoch or lease RPC. The SQL
 * gateway additionally locks this exact original live login before/after use. */
export async function authenticateJourneySocialPatient(
  request: Request,
  db: ServiceClient,
): Promise<MobileAuthContext> {
  const token = extractBearerToken(request.headers)
  if (!token) return unavailable(401, 'missing_access_token')
  const auth = createMobileAuthDependencies(db)
  let rawIdentity: unknown
  try {
    rawIdentity = await auth.verifyAccessToken(token)
  } catch {
    return unavailable(401, 'invalid_access_token')
  }
  const parsedIdentity = identitySchema.safeParse(rawIdentity)
  if (!parsedIdentity.success) return unavailable(401, 'invalid_access_token')
  const identity = parsedIdentity.data
  if (!identity.email || !identity.emailConfirmedAt) return unavailable(403, 'email_not_confirmed')
  const { data: admin, error } = await db
    .from('admin_users')
    .select('id')
    .eq('id', identity.id)
    .maybeSingle()
  if (error) return unavailable(503, 'patient_profile_unavailable')
  if (admin !== null) return unavailable(403, 'patient_admin_account_conflict')
  let rawPatient: unknown
  try {
    rawPatient = await auth.loadPatient(identity.id)
  } catch {
    return unavailable(503, 'patient_profile_unavailable')
  }
  if (rawPatient === null) return unavailable(403, 'patient_profile_unavailable')
  const parsedPatient = patientSchema.safeParse(rawPatient)
  if (!parsedPatient.success) return unavailable(503, 'patient_profile_unavailable')
  const patient = parsedPatient.data
  if (patient.authUserId !== identity.id) return unavailable(409, 'journey_social_patient_changed')
  if (patient.status !== 'active') return unavailable(403, 'patient_account_inactive')
  const result = Object.freeze({
    accessToken: token,
    authUserId: identity.id,
    userId: patient.id,
    identity: Object.freeze(identity),
    patient: Object.freeze(patient),
  })
  journeySocialOwner(result)
  return result
}
export function createJourneySocialRuntime(): MobileRouteRuntime {
  return Object.freeze({
    createServiceClient,
    authenticate: authenticateJourneySocialPatient,
    authorizeEntitlement: (auth, request, db) =>
      authorizeMobileEntitlement(db, auth.userId, new URL(request.url).pathname),
    createRequestId: (request: Request) => {
      const value = request.headers.get('x-request-id')
      return value && /^[A-Za-z0-9._:-]{8,128}$/u.test(value) ? value : crypto.randomUUID()
    },
  } satisfies MobileRouteRuntime)
}
