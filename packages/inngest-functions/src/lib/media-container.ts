/** Inert media container validation shared by processing transports.
 * No scheduler, provider client or database composition is loaded here. */
/** Same limit the app enforces while recording or importing. */
export const MAX_AUDIO_DURATION_SECONDS = 180

export async function measureAudioDurationFromContainer(input: {
  bytes: Uint8Array
  mimeType: string
}): Promise<number | null> {
  try {
    const { parseBuffer } = await import('music-metadata')
    const metadata = await parseBuffer(
      input.bytes,
      { mimeType: input.mimeType },
      { duration: true, skipCovers: true },
    )
    const seconds = metadata.format.duration
    return typeof seconds === 'number' && Number.isFinite(seconds) && seconds > 0 ? seconds : null
  } catch {
    return null
  }
}

function ascii(bytes: Uint8Array, start: number, length: number): string {
  return String.fromCharCode(...bytes.slice(start, start + length))
}

function hasPrefix(bytes: Uint8Array, prefix: number[]): boolean {
  return prefix.every((value, index) => bytes[index] === value)
}

function isIsoBaseMedia(bytes: Uint8Array): boolean {
  return bytes.length >= 12 && ascii(bytes, 4, 4) === 'ftyp'
}

export function mediaSignatureMatches(bytes: Uint8Array, mimeType: string): boolean {
  if (mimeType === 'application/pdf') return ascii(bytes, 0, 5) === '%PDF-'
  if (mimeType === 'image/jpeg') return hasPrefix(bytes, [0xff, 0xd8, 0xff])
  if (mimeType === 'image/png') {
    return hasPrefix(bytes, [0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a])
  }
  if (mimeType === 'image/webp') {
    return bytes.length >= 12 && ascii(bytes, 0, 4) === 'RIFF' && ascii(bytes, 8, 4) === 'WEBP'
  }
  if (mimeType === 'image/heic' || mimeType === 'image/heif') {
    if (!isIsoBaseMedia(bytes)) return false
    return ['heic', 'heix', 'hevc', 'hevx', 'mif1', 'msf1'].includes(ascii(bytes, 8, 4))
  }
  if (mimeType === 'audio/mpeg') {
    return (
      ascii(bytes, 0, 3) === 'ID3' ||
      (bytes.length >= 2 && bytes[0] === 0xff && ((bytes[1] ?? 0) & 0xe0) === 0xe0)
    )
  }
  if (mimeType === 'audio/mp4' || mimeType === 'audio/x-m4a') return isIsoBaseMedia(bytes)
  if (mimeType === 'audio/aac') {
    return bytes.length >= 2 && bytes[0] === 0xff && ((bytes[1] ?? 0) & 0xf6) === 0xf0
  }
  if (mimeType === 'audio/wav' || mimeType === 'audio/x-wav') {
    return bytes.length >= 12 && ascii(bytes, 0, 4) === 'RIFF' && ascii(bytes, 8, 4) === 'WAVE'
  }
  if (mimeType === 'audio/ogg') return ascii(bytes, 0, 4) === 'OggS'
  return false
}
