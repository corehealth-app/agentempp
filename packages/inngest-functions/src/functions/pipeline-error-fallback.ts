import type { MessagingProvider } from '@mpp/providers'
import type { OutboundDelivery } from './outbound-message-rows.js'

function asDelivery(content: string, result: Awaited<ReturnType<MessagingProvider['sendText']>>) {
  if (result.status === 'failed') {
    throw new Error(result.error ?? 'pipeline fallback delivery failed')
  }
  return {
    content,
    providerMessageId: result.providerMessageId,
    status: result.status,
    error: result.error,
  } satisfies OutboundDelivery
}

export async function sendPipelineErrorFallback(
  messaging: Pick<MessagingProvider, 'sendText'>,
  to: string,
  content: string,
  replyTo: string,
): Promise<OutboundDelivery> {
  try {
    const first = await messaging.sendText(to, content, { replyTo })
    if (first.status !== 'failed') return asDelivery(content, first)
  } catch {
    // Some providers reject an otherwise valid message only because replyTo is stale.
  }

  return asDelivery(content, await messaging.sendText(to, content))
}
