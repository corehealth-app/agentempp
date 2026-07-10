const MAX_FUTURE_MS = 5 * 60 * 1000
const MAX_AGE_MS = 30 * 24 * 60 * 60 * 1000

export type ProviderTimestampResolution = {
  timestamp: string
  serverReceivedAt: string
  source: 'provider' | 'server_fallback'
  fallbackReason: 'invalid_timestamp' | 'future_timestamp' | 'stale_timestamp' | null
}

export function resolveProviderTimestamp(
  rawTimestamp: unknown,
  serverReceivedAt: Date = new Date(),
): ProviderTimestampResolution {
  const serverMs = serverReceivedAt.getTime()
  const epochSeconds =
    typeof rawTimestamp === 'string' || typeof rawTimestamp === 'number'
      ? Number(rawTimestamp)
      : Number.NaN
  const providerMs = epochSeconds * 1000

  let fallbackReason: ProviderTimestampResolution['fallbackReason'] = null
  if (!Number.isFinite(providerMs) || providerMs <= 0) {
    fallbackReason = 'invalid_timestamp'
  } else if (providerMs > serverMs + MAX_FUTURE_MS) {
    fallbackReason = 'future_timestamp'
  } else if (providerMs < serverMs - MAX_AGE_MS) {
    fallbackReason = 'stale_timestamp'
  }

  return {
    timestamp: new Date(fallbackReason ? serverMs : providerMs).toISOString(),
    serverReceivedAt: serverReceivedAt.toISOString(),
    source: fallbackReason ? 'server_fallback' : 'provider',
    fallbackReason,
  }
}
