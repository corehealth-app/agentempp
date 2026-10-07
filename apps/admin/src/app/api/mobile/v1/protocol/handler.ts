import type { ProtocolMessageLocale } from '@mpp/core'
import { MobileApiError, mobileSuccess } from '@/lib/mobile-api/http'
import { protocolReadModel } from '@/lib/mobile-api/protocol-service'
import { loadProfile, loadToday } from '@/lib/mobile-api/read-model'
import type { MobileRouteContext } from '@/lib/mobile-api/route'

export interface ProtocolRouteDependencies {
  loadProfile: typeof loadProfile
  loadToday: typeof loadToday
}

const defaultDependencies: ProtocolRouteDependencies = { loadProfile, loadToday }

function protocolLocale(locale: string | null): ProtocolMessageLocale {
  if (locale === null || locale === 'pt-BR') return 'pt-BR'
  if (locale === 'en-US') return locale
  throw new MobileApiError(
    409,
    'protocol_locale_unsupported',
    'The objective is not available for this locale',
  )
}

export async function handleProtocolGet(
  context: MobileRouteContext,
  dependencies: ProtocolRouteDependencies = defaultDependencies,
): Promise<Response> {
  const locale = protocolLocale(context.auth.patient.locale)
  // The targets come from the same read as GET /today, so the Profile screen
  // and the Today screen can never show two different numbers.
  const [profile, today] = await Promise.all([
    dependencies.loadProfile(context.supabase, context.auth.userId),
    dependencies.loadToday(
      context.supabase,
      context.auth.userId,
      context.auth.patient.timezone ?? 'UTC',
    ),
  ])

  return mobileSuccess(
    protocolReadModel({
      profile,
      todayTargets: today.targets,
      name: context.auth.patient.name,
      locale,
    }),
    context.requestId,
  )
}
