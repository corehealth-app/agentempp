import { describe, expect, it } from 'vitest'
import { combinePatientNarrative, normalizeInboundMediaItems } from './media-burst.js'

describe('normalizeInboundMediaItems', () => {
  it('preserva mídias mistas tipadas na ordem do burst', () => {
    const result = normalizeInboundMediaItems({
      mediaItems: [
        {
          url: 'image-1',
          contentType: 'image',
          providerMessageId: 'image-pmid',
          timestamp: '2026-07-12T12:00:00.000Z',
        },
        {
          url: 'audio-1',
          contentType: 'audio',
          providerMessageId: 'audio-pmid',
          timestamp: '2026-07-12T12:00:02.000Z',
        },
      ],
      contentType: 'audio',
      providerMessageId: 'audio-pmid',
      timestamp: '2026-07-12T12:00:02.000Z',
    })

    expect(result.map((item) => item.contentType)).toEqual(['image', 'audio'])
  })

  it('mantém compatibilidade com eventos antigos de uma mídia', () => {
    expect(
      normalizeInboundMediaItems({
        contentType: 'image',
        mediaUrl: 'legacy-image',
        providerMessageId: 'legacy-pmid',
        timestamp: '2026-07-12T12:00:00.000Z',
      }),
    ).toEqual([
      {
        url: 'legacy-image',
        contentType: 'image',
        providerMessageId: 'legacy-pmid',
        timestamp: '2026-07-12T12:00:00.000Z',
      },
    ])
  })
})

describe('combinePatientNarrative', () => {
  it('combina texto e todas as transcrições sem sobrescrever nenhuma parte', () => {
    expect(
      combinePatientNarrative(['a foto é do jantar', 'primeiro áudio', 'segundo áudio']),
    ).toBe('a foto é do jantar\nprimeiro áudio\nsegundo áudio')
  })

  it('ignora partes vazias', () => {
    expect(combinePatientNarrative([undefined, '  ', 'conteúdo'])).toBe('conteúdo')
  })
})
