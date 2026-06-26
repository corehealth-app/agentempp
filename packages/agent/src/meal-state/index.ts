/**
 * MealState canônico — exports públicos do módulo.
 * Audit 06-26 Layer 2.2 prevention plan.
 */
export type { MealState, MealStateInput, MealStateResult, StateProvenance } from './types.js'
export { deriveMealState, classifyByPendingStatus } from './derive.js'
export {
  assertValidTransition,
  listValidTransitions,
  isTerminal,
  TERMINAL_STATES,
  type TransitionResult,
} from './state-machine.js'
