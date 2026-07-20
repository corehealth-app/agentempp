import { extractBearerToken, MobileApiError } from './http'

export interface MobileAuthIdentity {
  id: string
  email: string | null
  emailConfirmedAt: string | null
}

export interface MobilePatient {
  id: string
  authUserId: string
  email: string | null
  name: string | null
  locale: string | null
  timezone: string | null
  country: string | null
  status: string
}

export interface MobileAuthDependencies {
  verifyAccessToken(token: string): Promise<MobileAuthIdentity | null>
  bootstrapPatient(token: string): Promise<string>
  loadPatient(authUserId: string): Promise<MobilePatient | null>
}

export interface MobileAuthContext {
  accessToken: string
  authUserId: string
  userId: string
  identity: MobileAuthIdentity
  patient: MobilePatient
}

function mapBootstrapError(error: unknown): MobileApiError {
  const message = error instanceof Error ? error.message : ''
  if (
    message.includes('legacy_identity_conflict') ||
    message.includes('existing domain user requires explicit identity migration')
  ) {
    return new MobileApiError(
      409,
      'identity_migration_required',
      'An existing account requires a reviewed identity migration',
    )
  }
  if (message.includes('admin and patient accounts must be separate')) {
    return new MobileApiError(
      403,
      'patient_admin_account_conflict',
      'Patient and administrator accounts must be separate',
    )
  }
  if (message.includes('confirmed email required')) {
    return new MobileApiError(403, 'email_not_confirmed', 'Confirm your email before continuing')
  }
  return new MobileApiError(
    500,
    'patient_bootstrap_failed',
    'Patient profile initialization failed',
  )
}

export async function authenticatePatient(
  request: Request,
  dependencies: MobileAuthDependencies,
): Promise<MobileAuthContext> {
  const accessToken = extractBearerToken(request.headers)
  if (!accessToken) {
    throw new MobileApiError(401, 'missing_access_token', 'Authentication required')
  }

  let identity: MobileAuthIdentity | null
  try {
    identity = await dependencies.verifyAccessToken(accessToken)
  } catch {
    throw new MobileApiError(401, 'invalid_access_token', 'Authentication required')
  }
  if (!identity) {
    throw new MobileApiError(401, 'invalid_access_token', 'Authentication required')
  }
  if (!identity.email || !identity.emailConfirmedAt) {
    throw new MobileApiError(403, 'email_not_confirmed', 'Confirm your email before continuing')
  }

  let patientId: string
  try {
    patientId = await dependencies.bootstrapPatient(accessToken)
  } catch (error) {
    throw mapBootstrapError(error)
  }

  const patient = await dependencies.loadPatient(identity.id)
  if (!patient || patient.id !== patientId || patient.authUserId !== identity.id) {
    throw new MobileApiError(403, 'patient_profile_unavailable', 'Patient profile unavailable')
  }

  return {
    accessToken,
    authUserId: identity.id,
    userId: patient.id,
    identity,
    patient,
  }
}
