type DeliveryResult = {
  status: 'queued' | 'sent' | 'failed'
  providerMessageId: string | null
  error?: string
}

export type GapReminderDelivery =
  | { sent: true; providerMessageId: string; sentAt: string }
  | { sent: false; error: string }

export function classifyGapReminderDelivery(
  results: DeliveryResult[],
  sentAt: string,
): GapReminderDelivery {
  const result = results.length === 1 ? results[0] : null
  if (
    result?.status === 'sent' &&
    typeof result.providerMessageId === 'string' &&
    result.providerMessageId.length > 0
  ) {
    return { sent: true, providerMessageId: result.providerMessageId, sentAt }
  }
  return {
    sent: false,
    error: result?.error ?? 'provider did not confirm delivery',
  }
}
