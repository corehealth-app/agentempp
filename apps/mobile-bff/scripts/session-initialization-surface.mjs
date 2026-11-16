// Exactly one additive POST. Validate its complete surface before projecting
// the historical GET-only stream; no other path or export is subtracted.
/**
 * @template {{path: string, exports: string[]}} T
 * @param {T[]} records
 * @returns {(Omit<T, 'exports'> & {exports: string[]})[]}
 */
export function priorSessionObservationRecords(records) {
  const path = 'conversation/session/route.ts'
  const found = records.filter((record) => record.path === path)
  if (
    found.length !== 1 ||
    JSON.stringify(found[0].exports) !== JSON.stringify(['GET', 'POST', 'dynamic', 'runtime'])
  ) {
    throw Error('SESSION_INITIALIZATION_EXPORTS')
  }
  return records.map((record) =>
    record.path === path ? { ...record, exports: ['GET', 'dynamic', 'runtime'] } : record,
  )
}
