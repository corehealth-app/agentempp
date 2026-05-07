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
