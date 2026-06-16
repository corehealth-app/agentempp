export { inngest } from './client.js'
export type { InngestEvents } from './client.js'

import { processMessageFn } from './functions/process-message.js'
import { dailyCloserFn } from './functions/daily-closer.js'
import { dailyGapCheckerFn } from './functions/daily-gap-checker.js'
import { engagementSenderFn } from './functions/engagement-sender.js'
import { bufferListenerFn } from './functions/buffer-listener.js'
import { waQualityCheckFn } from './functions/wa-quality-check.js'
import { pipelineHealthFn } from './functions/pipeline-health.js'
import { openrouterBalanceCheckFn } from './functions/openrouter-balance-check.js'
import { dailyAuditFn } from './functions/daily-audit.js'
import { sampleJudgeFn } from './functions/sample-judge.js'
import { interactiveButtonHandlerFn } from './functions/interactive-handler.js'
import { pendingCleanupFn } from './functions/pending-cleanup.js'
import { foodDbGapsReportFn } from './functions/food-db-gaps-report.js'
import { mealGapReminderFn } from './functions/meal-gap-reminder.js'
import { trainingDailyDeliveryFn } from './functions/training-daily-delivery.js'
import { regressionBeaconFn } from './functions/regression-beacon.js'

export const allFunctions = [
  processMessageFn,
  dailyCloserFn,
  dailyGapCheckerFn,
  engagementSenderFn,
  bufferListenerFn,
  waQualityCheckFn,
  pipelineHealthFn,
  openrouterBalanceCheckFn,
  dailyAuditFn,
  sampleJudgeFn,
  interactiveButtonHandlerFn,
  pendingCleanupFn,
  foodDbGapsReportFn,
  mealGapReminderFn,
  trainingDailyDeliveryFn,
  regressionBeaconFn,
]

export {
  processMessageFn,
  dailyCloserFn,
  dailyGapCheckerFn,
  engagementSenderFn,
  bufferListenerFn,
  waQualityCheckFn,
  pipelineHealthFn,
  openrouterBalanceCheckFn,
  dailyAuditFn,
  sampleJudgeFn,
  interactiveButtonHandlerFn,
  pendingCleanupFn,
  foodDbGapsReportFn,
  mealGapReminderFn,
  trainingDailyDeliveryFn,
}
