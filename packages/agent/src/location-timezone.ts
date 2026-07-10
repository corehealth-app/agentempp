import { countryToTimezone } from './timezone-utils.js'

const MULTI_TIMEZONE_COUNTRIES = new Set([
  'AU',
  'BR',
  'CA',
  'CL',
  'EC',
  'ES',
  'ID',
  'MX',
  'NZ',
  'PT',
  'RU',
  'US',
])

const KNOWN_COUNTRY_TIMEZONES: Partial<Record<string, Set<string>>> = {
  US: new Set([
    'America/Adak',
    'America/Anchorage',
    'America/Boise',
    'America/Chicago',
    'America/Denver',
    'America/Detroit',
    'America/Indiana/Indianapolis',
    'America/Indiana/Knox',
    'America/Indiana/Marengo',
    'America/Indiana/Petersburg',
    'America/Indiana/Tell_City',
    'America/Indiana/Vevay',
    'America/Indiana/Vincennes',
    'America/Indiana/Winamac',
    'America/Juneau',
    'America/Kentucky/Louisville',
    'America/Kentucky/Monticello',
    'America/Los_Angeles',
    'America/Menominee',
    'America/Metlakatla',
    'America/New_York',
    'America/Nome',
    'America/North_Dakota/Beulah',
    'America/North_Dakota/Center',
    'America/North_Dakota/New_Salem',
    'America/Phoenix',
    'America/Sitka',
    'America/Yakutat',
    'Pacific/Honolulu',
  ]),
  BR: new Set([
    'America/Araguaina',
    'America/Bahia',
    'America/Belem',
    'America/Boa_Vista',
    'America/Campo_Grande',
    'America/Cuiaba',
    'America/Eirunepe',
    'America/Fortaleza',
    'America/Maceio',
    'America/Manaus',
    'America/Noronha',
    'America/Porto_Velho',
    'America/Recife',
    'America/Rio_Branco',
    'America/Santarem',
    'America/Sao_Paulo',
  ]),
  CA: new Set([
    'America/Atikokan',
    'America/Blanc-Sablon',
    'America/Cambridge_Bay',
    'America/Creston',
    'America/Dawson',
    'America/Dawson_Creek',
    'America/Edmonton',
    'America/Fort_Nelson',
    'America/Glace_Bay',
    'America/Goose_Bay',
    'America/Halifax',
    'America/Inuvik',
    'America/Iqaluit',
    'America/Moncton',
    'America/Rankin_Inlet',
    'America/Regina',
    'America/Resolute',
    'America/St_Johns',
    'America/Swift_Current',
    'America/Toronto',
    'America/Vancouver',
    'America/Whitehorse',
    'America/Winnipeg',
    'America/Yellowknife',
  ]),
  AU: new Set([
    'Australia/Adelaide',
    'Australia/Brisbane',
    'Australia/Broken_Hill',
    'Australia/Darwin',
    'Australia/Eucla',
    'Australia/Hobart',
    'Australia/Lindeman',
    'Australia/Lord_Howe',
    'Australia/Melbourne',
    'Australia/Perth',
    'Australia/Sydney',
  ]),
  MX: new Set([
    'America/Bahia_Banderas',
    'America/Cancun',
    'America/Chihuahua',
    'America/Ciudad_Juarez',
    'America/Hermosillo',
    'America/Matamoros',
    'America/Mazatlan',
    'America/Merida',
    'America/Mexico_City',
    'America/Monterrey',
    'America/Ojinaga',
    'America/Tijuana',
  ]),
}

export function isIanaTimezone(timezone: string | null | undefined): timezone is string {
  if (!timezone) return false
  try {
    new Intl.DateTimeFormat('en-US', { timeZone: timezone }).format()
    return true
  } catch {
    return false
  }
}

export function isMultiTimezoneCountry(country: string): boolean {
  return MULTI_TIMEZONE_COUNTRIES.has(country.toUpperCase())
}

/** null significa que o pais ainda nao tem whitelist deterministica. */
export function isTimezoneCompatibleWithCountry(country: string, timezone: string): boolean | null {
  if (!isIanaTimezone(timezone)) return false
  const known = KNOWN_COUNTRY_TIMEZONES[country.toUpperCase()]
  return known ? known.has(timezone) : null
}

export type ResidenceTimezoneResolution =
  | { ok: true; timezone: string; source: 'explicit' | 'existing_confirmed' | 'country_default' }
  | {
      ok: false
      reason: 'invalid_timezone' | 'country_timezone_mismatch' | 'location_required'
    }

export function resolveResidenceTimezone(input: {
  country: string
  requestedTimezone?: string | null
  existingCountry?: string | null
  existingTimezone?: string | null
  existingTimezoneConfirmed?: boolean
  locationProvided?: boolean
}): ResidenceTimezoneResolution {
  const country = input.country.toUpperCase()
  if (input.requestedTimezone) {
    if (!isIanaTimezone(input.requestedTimezone)) return { ok: false, reason: 'invalid_timezone' }
    if (isTimezoneCompatibleWithCountry(country, input.requestedTimezone) === false) {
      return { ok: false, reason: 'country_timezone_mismatch' }
    }
    if (isMultiTimezoneCountry(country) && !input.locationProvided) {
      return { ok: false, reason: 'location_required' }
    }
    return { ok: true, timezone: input.requestedTimezone, source: 'explicit' }
  }

  if (
    input.existingTimezoneConfirmed &&
    input.existingCountry?.toUpperCase() === country &&
    input.existingTimezone &&
    isIanaTimezone(input.existingTimezone) &&
    isTimezoneCompatibleWithCountry(country, input.existingTimezone) !== false
  ) {
    return { ok: true, timezone: input.existingTimezone, source: 'existing_confirmed' }
  }

  if (isMultiTimezoneCountry(country)) return { ok: false, reason: 'location_required' }
  const timezone = countryToTimezone(country)
  return { ok: true, timezone, source: 'country_default' }
}

export interface TimezoneCountryUser {
  id: string
  country: string | null
  timezone: string | null
  country_confirmed: boolean | null
}

export function findTimezoneCountryMismatches(users: TimezoneCountryUser[]) {
  return users.flatMap((user) => {
    if (!user.country_confirmed || !user.country || !user.timezone) return []
    if (isTimezoneCompatibleWithCountry(user.country, user.timezone) !== false) return []
    return [{ id: user.id, country: user.country, timezone: user.timezone }]
  })
}
