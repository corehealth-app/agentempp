/**
 * What the Profile screen of the app reads about the objective
 * (GET /protocol): the protocol the profile holds, the day's targets and the
 * entry message of that protocol (docs/mobile/api-v1.md "Objetivo atual").
 *
 * Read only. There is no change of objective here: the client said the change
 * of protocol belongs to a reassessment (docs/CALCULO-MPP.md §10).
 */
import { type Protocol, type ProtocolMessageLocale, protocolWelcomeMessage } from '@mpp/core'

const PROTOCOLS: readonly string[] = ['recomposicao', 'ganho_massa', 'manutencao']

function asProtocol(value: unknown): Protocol | null {
  return typeof value === 'string' && PROTOCOLS.includes(value) ? (value as Protocol) : null
}

export interface ProtocolReadSources {
  /** The `user_profiles` row as GET /profile reads it; null when there is none. */
  profile: Record<string, unknown> | null
  /** The targets of the official daily state, as GET /today returns them. */
  todayTargets: { calories_kcal: number | null; protein_g: number | null }
  /** The registered name of the account. */
  name: string | null
  locale: ProtocolMessageLocale
}

/**
 * `targets` are the ones of the Today screen, taken from the same daily state
 * and never recomputed here: the target stored on today's row when the day
 * already has one, otherwise the one calculated from the profile.
 *
 * An account whose profile holds no protocol (sign-up not completed yet) gets
 * `current_protocol: null` and `welcome: null`, as the other reads of the API
 * answer what is not there yet; `targets` stay whatever the Today screen shows
 * for that account.
 */
export function protocolReadModel(sources: ProtocolReadSources) {
  const currentProtocol = asProtocol(sources.profile?.current_protocol)
  return {
    current_protocol: currentProtocol,
    targets: {
      calories: sources.todayTargets.calories_kcal,
      protein_g: sources.todayTargets.protein_g,
    },
    welcome: currentProtocol
      ? {
          protocol: currentProtocol,
          paragraphs: protocolWelcomeMessage(currentProtocol, sources.name, sources.locale),
        }
      : null,
  }
}
