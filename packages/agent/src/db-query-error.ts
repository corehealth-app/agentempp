export function throwIfQueryFailed(error: unknown, fallbackMessage: string): void {
  if (!error) return
  if (typeof error === 'object' && 'message' in error) {
    const message = String((error as { message?: unknown }).message ?? '').trim()
    if (message) throw new Error(message)
  }
  throw new Error(fallbackMessage)
}
