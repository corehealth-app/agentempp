export { inngest } from './client.js'
export type { InngestEvents } from './client.js'

import { processMessageFn } from './functions/process-message.js'
import { dailyCloserFn } from './functions/daily-closer.js'
import { dailyGapCheckerFn } from './functions/daily-gap-checker.js'
import { engagementSenderFn } from './functions/engagement-sender.js'
import { bufferListenerFn } from './functions/buffer-listener.js'
import { waQualityCheckFn } from './functions/wa-quality-check.js'
import { pipelineHealthFn } from './functions/pipeline-health.js'

export const allFunctions = [
  processMessageFn,
  dailyCloserFn,
  dailyGapCheckerFn,
  engagementSenderFn,
  bufferListenerFn,
  waQualityCheckFn,
  pipelineHealthFn,
]

export {
  processMessageFn,
  dailyCloserFn,
  dailyGapCheckerFn,
  engagementSenderFn,
  bufferListenerFn,
  waQualityCheckFn,
  pipelineHealthFn,
}
