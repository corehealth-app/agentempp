import {
  chunkMessage,
  type HumanizeOpts,
  type MessagingProvider,
  type SendOpts,
  sendHumanized,
} from '@mpp/providers'
import { type OutboundDelivery, requireOutboundDelivery } from './outbound-message-rows.js'

export type StepRunner = (
  id: string,
  operation: () => Promise<OutboundDelivery>,
) => Promise<OutboundDelivery>

interface DurableHumanizedSendInput {
  provider: MessagingProvider
  to: string
  text: string
  stepPrefix: string
  runStep: StepRunner
  opts?: HumanizeOpts &
    SendOpts & {
      inReplyTo?: string
    }
}

export async function sendHumanizedDurably(
  input: DurableHumanizedSendInput,
): Promise<OutboundDelivery[]> {
  const chunks = input.opts?.singleMessage ? [input.text.trim()] : chunkMessage(input.text)
  const deliveries: OutboundDelivery[] = []

  for (let index = 0; index < chunks.length; index++) {
    const content = chunks[index]
    if (!content) continue

    const delivery = await input.runStep(`${input.stepPrefix}-chunk-${index + 1}`, async () => {
      const [result] = await sendHumanized(input.provider, input.to, content, {
        ...input.opts,
        inReplyTo: index === 0 ? input.opts?.inReplyTo : undefined,
        replyTo: index === 0 ? input.opts?.replyTo : undefined,
        singleMessage: true,
      })
      if (!result) throw new Error('humanized message produced no delivery result')
      return requireOutboundDelivery(content, result)
    })
    deliveries.push(delivery)
  }

  if (deliveries.length === 0) throw new Error('humanized message produced no chunks')
  return deliveries
}
