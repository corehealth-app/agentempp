export * from './calc-config.js'
export * from './coach-messages.js'
export * from './content.js'
export * from './daily-state.js'
export * from './engine/aggregates.js'
export * from './engine/balance.js'
// engine/bloco exporta KCAL_BLOCK canônico; progress-calc também o exporta como
// @deprecated — excluímos o de bloco do barrel para evitar ambiguidade até a
// migração dos chamadores (próxima tarefa).
export {
  accumulateBloco,
  creditDayToBloco,
  type DayCreditInput,
  type DayStatus,
} from './engine/bloco.js'
export * from './engine/protocols.js'
export * from './engine/targets.js'
export * from './entitlements.js'
export * from './nutrition.js'
export * from './progress-calc.js'
export * from './protocol-router.js'
export * from './routine.js'
export * from './types.js'
