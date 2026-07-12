export type InboundMediaItem = {
  url: string
  contentType: 'audio' | 'image'
  providerMessageId: string
  timestamp: string
}

type NormalizeMediaInput = {
  mediaItems?: InboundMediaItem[]
  contentType: 'text' | 'audio' | 'image'
  mediaUrl?: string
  mediaUrls?: string[]
  providerMessageId: string
  timestamp: string
}

export function normalizeInboundMediaItems(input: NormalizeMediaInput): InboundMediaItem[] {
  if (Array.isArray(input.mediaItems) && input.mediaItems.length > 0) {
    return input.mediaItems.filter(
      (item) =>
        !!item.url &&
        !!item.providerMessageId &&
        !!item.timestamp &&
        (item.contentType === 'audio' || item.contentType === 'image'),
    )
  }

  if (input.contentType !== 'audio' && input.contentType !== 'image') return []
  const urls =
    input.mediaUrls && input.mediaUrls.length > 0
      ? input.mediaUrls
      : input.mediaUrl
        ? [input.mediaUrl]
        : []
  return urls.map((url) => ({
    url,
    contentType: input.contentType as 'audio' | 'image',
    providerMessageId: input.providerMessageId,
    timestamp: input.timestamp,
  }))
}

export function combinePatientNarrative(
  parts: Array<string | null | undefined>,
): string | undefined {
  const combined = parts
    .map((part) => part?.trim() ?? '')
    .filter(Boolean)
    .join('\n')
  return combined || undefined
}
