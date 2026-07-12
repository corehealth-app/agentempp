export function buildVisionEventDedupeKey(
  providerMessageId: string,
  visionType: string,
  imageIndex: number,
): string {
  return `vision:${providerMessageId}:${visionType}:${imageIndex}`
}
