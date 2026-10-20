/** Pure wire parsers only. No repository factory or provider is exposed here. */

export type {
  StrengthWorkoutProjection,
  TrustedStrengthWorkoutCalendarScope,
} from './workout-strength-repository.js'
export {
  parseTrustedStrengthWorkoutCalendarScope,
  parseTrustedStrengthWorkoutProjection,
} from './workout-strength-repository.js'
