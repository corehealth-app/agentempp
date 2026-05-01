export { inngest } from './client.js'
export type { InngestEvents } from './client.js'

import { processMessageFn } from './functions/process-message.js'
import { dailyCloserFn } from './functions/daily-closer.js'
import { engagementSenderFn } from './functions/engagement-sender.js'
import { bufferListenerFn } from './functions/buffer-listener.js'

export const allFunctions = [
  processMessageFn,
  dailyCloserFn,
  engagementSenderFn,
  bufferListenerFn,
]

export {
  processMessageFn,
  dailyCloserFn,
  engagementSenderFn,
  bufferListenerFn,
}
