import { describe, expect, it } from 'vitest'
import { buildVisionEventDedupeKey } from './vision-event-key.js'

describe('buildVisionEventDedupeKey', () => {
  it('permanece estável quando o mesmo evento é reprocessado', () => {
    expect(buildVisionEventDedupeKey('wamid.photo-1', 'meal', 0)).toBe(
      buildVisionEventDedupeKey('wamid.photo-1', 'meal', 0),
    )
  })

  it('separa mensagens, tipos e posições diferentes do burst', () => {
    const keys = new Set([
      buildVisionEventDedupeKey('wamid.photo-1', 'meal', 0),
      buildVisionEventDedupeKey('wamid.photo-2', 'meal', 0),
      buildVisionEventDedupeKey('wamid.photo-1', 'body', 0),
      buildVisionEventDedupeKey('wamid.photo-1', 'meal', 1),
    ])

    expect(keys.size).toBe(4)
  })
})
