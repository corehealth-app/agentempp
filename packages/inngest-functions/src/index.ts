export type { InngestEvents } from './client.js'
export { inngest } from './client.js'

import { bufferListenerFn } from './functions/buffer-listener.js'
import { coachContentPackActivationFn } from './functions/coach-content-pack-activation.js'
import { dailyAuditFn } from './functions/daily-audit.js'
import { dailyCloserFn } from './functions/daily-closer.js'
import { dailyGapCheckerFn } from './functions/daily-gap-checker.js'
import { engagementSenderFn } from './functions/engagement-sender.js'
import { foodDbGapsReportFn } from './functions/food-db-gaps-report.js'
import { interactiveButtonHandlerFn } from './functions/interactive-handler.js'
import { mealGapReminderFn } from './functions/meal-gap-reminder.js'
import { mediaAssetProcessingFn } from './functions/media-asset-processing.js'
import { mediaRetentionCleanupFn } from './functions/media-retention-cleanup.js'
import { openrouterBalanceCheckFn } from './functions/openrouter-balance-check.js'
import { pendingCleanupFn } from './functions/pending-cleanup.js'
import { pipelineHealthFn } from './functions/pipeline-health.js'
import { processMessageFn } from './functions/process-message.js'
import { regressionBeaconFn } from './functions/regression-beacon.js'
import { reminderClaimFn, reminderSchedulerFn } from './functions/reminder-scheduler.js'
import {
  routineOccurrenceSchedulerFn,
  routineSnoozeClaimFn,
} from './functions/routine-occurrence-scheduler.js'
import { sampleJudgeFn } from './functions/sample-judge.js'
import { trainingDailyDeliveryFn } from './functions/training-daily-delivery.js'
import { userDeletionPurgerFn } from './functions/user-deletion-purger.js'
import { waQualityCheckFn } from './functions/wa-quality-check.js'

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
  userDeletionPurgerFn,
  mediaAssetProcessingFn,
  mediaRetentionCleanupFn,
  reminderSchedulerFn,
  reminderClaimFn,
  routineOccurrenceSchedulerFn,
  routineSnoozeClaimFn,
  coachContentPackActivationFn,
]

/**
 * The functions an Inngest endpoint serves. With no set named, every
 * function (production). `media-staging` is the staging worker for the
 * mobile app: only media processing (photos, audio, plan documents), with no
 * cron, no WhatsApp and no reminder function. An unknown name is refused so a
 * typo never widens the set.
 */
const FUNCTION_SETS = {
  'media-staging': [mediaAssetProcessingFn],
} as const

export function functionsForSet(name: string | undefined): readonly (typeof allFunctions)[number][] {
  if (name === undefined || name === '') return allFunctions
  const selected = (FUNCTION_SETS as Record<string, readonly (typeof allFunctions)[number][]>)[name]
  if (!selected) throw new Error(`unknown Inngest function set: ${name}`)
  return selected
}

export {
  bufferListenerFn,
  coachContentPackActivationFn,
  dailyAuditFn,
  dailyCloserFn,
  dailyGapCheckerFn,
  engagementSenderFn,
  foodDbGapsReportFn,
  interactiveButtonHandlerFn,
  mealGapReminderFn,
  mediaAssetProcessingFn,
  mediaRetentionCleanupFn,
  openrouterBalanceCheckFn,
  pendingCleanupFn,
  pipelineHealthFn,
  processMessageFn,
  reminderClaimFn,
  reminderSchedulerFn,
  routineOccurrenceSchedulerFn,
  routineSnoozeClaimFn,
  sampleJudgeFn,
  trainingDailyDeliveryFn,
  userDeletionPurgerFn,
  waQualityCheckFn,
}
