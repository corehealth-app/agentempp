// The rule lives in @mpp/core (engine/day-status) since 2026-10-04, so the
// shared close function of @mpp/agent calls the same function as this worker.
// This file stays so the worker's imports and its test keep their path.
export { resolveClosedDayStatus } from '@mpp/core'
