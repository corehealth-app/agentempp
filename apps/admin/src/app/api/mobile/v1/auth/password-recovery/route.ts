import {
  makePasswordRecoveryHandlers,
  passwordRecoveryConfiguration,
} from '@/lib/mobile-api/password-recovery'

export const runtime = 'nodejs'
export const dynamic = 'force-dynamic'
// Two bounded Auth calls (10s each) and best-effort local logout (3s).
export const maxDuration = 45

export async function GET(request: Request): Promise<Response> {
  return makePasswordRecoveryHandlers(passwordRecoveryConfiguration(process.env)).GET(request)
}

export async function HEAD(request: Request): Promise<Response> {
  return makePasswordRecoveryHandlers(passwordRecoveryConfiguration(process.env)).HEAD(request)
}

export async function POST(request: Request): Promise<Response> {
  return makePasswordRecoveryHandlers(passwordRecoveryConfiguration(process.env)).POST(request)
}
