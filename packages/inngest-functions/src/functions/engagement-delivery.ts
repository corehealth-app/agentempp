type ProviderDelivery = {
  content: string
  status: 'queued' | 'sent' | 'failed'
  providerMessageId: string | null
  error?: string
}

type AudioProviderDelivery = Omit<ProviderDelivery, 'content'>

export type PersistableEngagementDelivery = {
  content: string
  contentType: 'text' | 'audio'
  mediaUrl: string | null
  providerMessageId: string
}

export type EngagementDeliveryResult =
  | {
      sent: true
      sentAt: string
      deliveries: PersistableEngagementDelivery[]
    }
  | { sent: false; error: string }

export function classifyTextEngagementDelivery(
  results: ProviderDelivery[],
  sentAt: string,
): EngagementDeliveryResult {
  if (results.length === 0) return { sent: false, error: 'provider returned no deliveries' }

  const invalid = results.find(
    (result) =>
      result.status !== 'sent' ||
      !result.providerMessageId ||
      !result.content ||
      !result.content.trim(),
  )
  if (invalid) {
    return {
      sent: false,
      error: invalid.error ?? 'provider did not confirm every engagement delivery',
    }
  }

  return {
    sent: true,
    sentAt,
    deliveries: results.map((result) => ({
      content: result.content,
      contentType: 'text',
      mediaUrl: null,
      providerMessageId: result.providerMessageId as string,
    })),
  }
}

export function classifyAudioEngagementDelivery(
  result: AudioProviderDelivery,
  content: string,
  mediaUrl: string,
  sentAt: string,
): EngagementDeliveryResult {
  if (result.status !== 'sent' || !result.providerMessageId) {
    return {
      sent: false,
      error: result.error ?? 'provider did not confirm engagement audio delivery',
    }
  }
  return {
    sent: true,
    sentAt,
    deliveries: [
      {
        content,
        contentType: 'audio',
        mediaUrl,
        providerMessageId: result.providerMessageId,
      },
    ],
  }
}

export function shouldSendEngagementAsAudio(
  userId: string,
  localDate: string,
  probability: number,
): boolean {
  if (probability <= 0) return false
  if (probability >= 1) return true

  let hash = 2166136261
  const seed = `${userId}|${localDate}|engagement-audio`
  for (let index = 0; index < seed.length; index++) {
    hash ^= seed.charCodeAt(index)
    hash = Math.imul(hash, 16777619)
  }
  return (hash >>> 0) / 4294967296 < probability
}
