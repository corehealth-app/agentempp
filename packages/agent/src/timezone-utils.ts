/**
 * Helpers de timezone — lookups de date no timezone do paciente.
 *
 * Bug histórico: snapshots, meal_logs, workout_logs eram lookupados/inseridos
 * com `new Date().toISOString().slice(0,10)` (UTC). Pra paciente em
 * America/New_York, entre 20h-24h local UTC já virou dia seguinte → snapshot
 * lookup pegava dia errado, perdendo consumo registrado tarde.
 *
 * Use estes helpers em todo lookup/insert que dependa de "data do paciente".
 */

/** Data local do paciente em formato YYYY-MM-DD (pra coluna date do snapshot). */
export function getLocalDateString(tz: string, when: Date = new Date()): string {
  // en-CA produz "YYYY-MM-DD" (formato ISO compatível com SQL date).
  return new Intl.DateTimeFormat('en-CA', {
    timeZone: tz,
    year: 'numeric',
    month: '2-digit',
    day: '2-digit',
  }).format(when)
}

/** Data local do paciente N dias atrás. */
export function getLocalDateMinusDays(tz: string, days: number, when: Date = new Date()): string {
  const past = new Date(when.getTime() - days * 24 * 60 * 60 * 1000)
  return getLocalDateString(tz, past)
}

/** Hora local (0-23) do paciente. */
export function getLocalHour(tz: string, when: Date = new Date()): number {
  const fmt = new Intl.DateTimeFormat('en-US', {
    timeZone: tz,
    hour: '2-digit',
    hour12: false,
  })
  const parts = fmt.formatToParts(when)
  const h = parts.find((p) => p.type === 'hour')?.value ?? '0'
  return Number.parseInt(h, 10)
}

/** Offset ISO ('-04:00') do timezone naquele momento. Lida com DST. */
export function getTzOffset(tz: string, when: Date = new Date()): string {
  // longOffset retorna 'GMT-04:00' (em pt-BR pode vir como 'UTC−04:00')
  const fmt = new Intl.DateTimeFormat('en-US', {
    timeZone: tz,
    timeZoneName: 'longOffset',
  })
  const parts = fmt.formatToParts(when)
  const raw = parts.find((p) => p.type === 'timeZoneName')?.value ?? ''
  const m = raw.match(/(?:GMT|UTC)?([+\-−][0-9]{1,2}:?[0-9]{0,2})/)
  if (!m) return '+00:00'
  return m[1]!
    .replace('−', '-')
    .replace(/^([+-])(\d):/, '$10$2:') // +5:00 → +05:00
    .replace(/^([+-]\d{2})$/, '$1:00') // -04 → -04:00
    .replace(/^([+-]\d{4})$/, (_, s) => `${s.slice(0, 3)}:${s.slice(3)}`) // -0400 → -04:00
}

/**
 * Mapeia ISO alpha-2 country code pro timezone IANA mais comum.
 * Pra países com múltiplos fusos (US, BR, CA, AU, RU), usa o mais populoso.
 * O LLM pode passar timezone específico em `confirma_pais_residencia` quando
 * souber a cidade exata (ex: paciente em Orlando → America/New_York).
 */
export function countryToTimezone(country: string): string {
  const map: Record<string, string> = {
    BR: 'America/Sao_Paulo',
    US: 'America/New_York',
    GB: 'Europe/London',
    PT: 'Europe/Lisbon',
    ES: 'Europe/Madrid',
    FR: 'Europe/Paris',
    DE: 'Europe/Berlin',
    IT: 'Europe/Rome',
    NL: 'Europe/Amsterdam',
    CH: 'Europe/Zurich',
    AT: 'Europe/Vienna',
    BE: 'Europe/Brussels',
    IE: 'Europe/Dublin',
    AR: 'America/Argentina/Buenos_Aires',
    MX: 'America/Mexico_City',
    CL: 'America/Santiago',
    CO: 'America/Bogota',
    PE: 'America/Lima',
    UY: 'America/Montevideo',
    PY: 'America/Asuncion',
    BO: 'America/La_Paz',
    EC: 'America/Guayaquil',
    VE: 'America/Caracas',
    CA: 'America/Toronto',
    AU: 'Australia/Sydney',
    NZ: 'Pacific/Auckland',
    JP: 'Asia/Tokyo',
    CN: 'Asia/Shanghai',
    IN: 'Asia/Kolkata',
    SG: 'Asia/Singapore',
    AE: 'Asia/Dubai',
    IL: 'Asia/Jerusalem',
    ZA: 'Africa/Johannesburg',
  }
  return map[country.toUpperCase()] ?? 'UTC'
}
