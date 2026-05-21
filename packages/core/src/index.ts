export * from './types.js'
export * from './calc-config.js'
export * from './nutrition.js'
export * from './protocol-router.js'
export * from './progress-calc.js'
// engine/bloco exporta KCAL_BLOCK canônico; progress-calc também o exporta como
// @deprecated — excluímos o de bloco do barrel para evitar ambiguidade até a
// migração dos chamadores (próxima tarefa).
export { creditDayToBloco, accumulateBloco, type DayCreditInput, type DayStatus } from './engine/bloco.js'
export * from './engine/balance.js'
