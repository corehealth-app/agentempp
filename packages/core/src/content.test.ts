import { describe, expect, it } from 'vitest'
import {
  contentCategorySchema,
  contentCoverInputSchema,
  contentDraftInputSchema,
  contentListQuerySchema,
  contentLocaleSchema,
  contentOriginSchema,
  contentReadEventSchema,
  contentReadInputSchema,
  contentSaveInputSchema,
  contentSurfaceSchema,
  decodeContentCursor,
  encodeContentCursor,
  validateContentMarkdown,
} from './content.js'

const UUID = '9baf14c8-6376-4a47-a9b8-9fcf2e5cefc1'
const LONG_BODY = 'A alimentação consistente apoia decisões graduais e sustentáveis. '.repeat(3)

function nestedList(depth: number): string {
  return Array.from(
    { length: depth },
    (_, index) => `${'  '.repeat(index)}- ${index === depth - 1 ? LONG_BODY : `Nível ${index + 1}`}`,
  ).join('\n')
}

function validDraft(overrides: Record<string, unknown> = {}) {
  return {
    locale: 'pt-BR',
    category: 'nutrition',
    title: 'Nutrição para a semana',
    excerpt: 'Um guia prático para escolhas alimentares consistentes durante a semana.',
    bodyMarkdown: LONG_BODY,
    tags: ['Nutrição', 'Hábitos saudáveis'],
    featuredToday: false,
    coverAssetId: null,
    targeting: {
      protocols: [],
      plans: [],
      personalities: [],
    },
    ...overrides,
  }
}

describe('content contracts', () => {
  it('exposes the exact public enum values', () => {
    expect(contentLocaleSchema.options).toEqual(['pt-BR', 'en-US'])
    expect(contentCategorySchema.options).toEqual([
      'weight_loss',
      'hypertrophy',
      'nutrition',
      'training',
      'neuroscience',
      'habit_formation',
      'cardiovascular_health',
      'hydration',
      'supplementation',
      'sleep',
      'using_bodyflow',
    ])
    expect(contentSurfaceSchema.options).toEqual(['today', 'library', 'saved'])
    expect(contentOriginSchema.options).toEqual(['today', 'library', 'push'])
    expect(contentReadEventSchema.options).toEqual(['impression', 'opened', 'completed'])
  })

  it('enforces strict draft limits and normalizes unique tag slugs', () => {
    expect(contentDraftInputSchema.parse(validDraft()).tags).toEqual([
      'nutricao',
      'habitos-saudaveis',
    ])
    expect(contentDraftInputSchema.safeParse(validDraft({ title: 'ab' })).success).toBe(false)
    expect(contentDraftInputSchema.safeParse(validDraft({ title: 'a'.repeat(121) })).success).toBe(false)
    expect(contentDraftInputSchema.safeParse(validDraft({ excerpt: 'a'.repeat(19) })).success).toBe(false)
    expect(contentDraftInputSchema.safeParse(validDraft({ excerpt: 'a'.repeat(281) })).success).toBe(false)
    expect(contentDraftInputSchema.safeParse(validDraft({ tags: ['nutrition', 'nutrition'] })).success).toBe(
      false,
    )
    expect(contentDraftInputSchema.safeParse(validDraft({ tags: Array(21).fill('nutrition') })).success).toBe(
      false,
    )
    expect(contentDraftInputSchema.safeParse(validDraft({ unexpected: true })).success).toBe(false)
  })

  it('enforces the Markdown policy and returns canonical Markdown through the draft contract', () => {
    const canonical = contentDraftInputSchema.parse(
      validDraft({ bodyMarkdown: `## Título\r\n\r\n${LONG_BODY}` }),
    )
    expect(canonical.bodyMarkdown).toBe(`## Título\n\n${LONG_BODY.trimEnd()}\n`)

    for (const bodyMarkdown of [
      `<strong>${LONG_BODY}</strong>`,
      `# Duplicated title\n\n${LONG_BODY}`,
      `![cover](https://bodyflow.app/cover.png)\n\n${LONG_BODY}`,
      `Use \`code\` carefully. ${LONG_BODY}`,
      `${LONG_BODY}\n\n---\n\n${LONG_BODY}`,
      `[source](http://bodyflow.app)\n\n${LONG_BODY}`,
      `[source][bodyflow]\n\n[bodyflow]: https://bodyflow.app\n\n${LONG_BODY}`,
      'a'.repeat(50_001),
      `${'> '.repeat(9)}${LONG_BODY}`,
    ]) {
      expect(contentDraftInputSchema.safeParse(validDraft({ bodyMarkdown })).success).toBe(false)
    }
  })

  it('limits cover declarations to approved MIME types and ten MiB', () => {
    for (const mimeType of ['image/jpeg', 'image/png', 'image/webp']) {
      expect(contentCoverInputSchema.safeParse({ mimeType, sizeBytes: 10 * 1024 * 1024 }).success).toBe(true)
    }
    expect(contentCoverInputSchema.safeParse({ mimeType: 'image/svg+xml', sizeBytes: 1 }).success).toBe(
      false,
    )
    expect(
      contentCoverInputSchema.safeParse({ mimeType: 'image/jpeg', sizeBytes: 10 * 1024 * 1024 + 1 }).success,
    ).toBe(false)
    expect(contentCoverInputSchema.safeParse({ mimeType: 'image/jpeg', sizeBytes: 0 }).success).toBe(false)
    expect(contentCoverInputSchema.safeParse({ mimeType: 'image/jpeg', sizeBytes: 1, extra: true }).success).toBe(
      false,
    )
  })

  it('applies list query defaults and rejects unknown query keys', () => {
    expect(contentListQuerySchema.parse({})).toEqual({ surface: 'library', limit: 20 })
    expect(contentListQuerySchema.parse({ surface: 'today', category: 'sleep', limit: '50' })).toEqual({
      surface: 'today',
      category: 'sleep',
      limit: 50,
    })
    expect(contentListQuerySchema.safeParse({ surface: 'library', limit: 0 }).success).toBe(false)
    expect(contentListQuerySchema.safeParse({ surface: 'library', limit: 51 }).success).toBe(false)
    expect(contentListQuerySchema.safeParse({ surface: 'library', unknown: true }).success).toBe(false)
  })

  it('validates strict read and save mutation inputs', () => {
    expect(contentReadInputSchema.parse({ event: 'opened', origin: 'library', version: 3 })).toEqual({
      event: 'opened',
      origin: 'library',
      version: 3,
    })
    expect(contentReadInputSchema.safeParse({ event: 'opened', origin: 'email', version: 3 }).success).toBe(
      false,
    )
    expect(contentReadInputSchema.safeParse({ event: 'opened', origin: 'library', version: 0 }).success).toBe(
      false,
    )
    expect(contentSaveInputSchema.parse({ saved: true, version: 3 })).toEqual({ saved: true, version: 3 })
    expect(contentSaveInputSchema.safeParse({ saved: true, version: 3, extra: true }).success).toBe(false)
  })
})

describe('validateContentMarkdown', () => {
  it('normalizes CRLF and produces the portable allowed AST', () => {
    const result = validateContentMarkdown(
      '## Título\r\n\r\nTexto com **força**, *ênfase* e [fonte](https://bodyflow.app).\r\n\r\n> Conselho seguro.\r\n\r\n1. Primeiro\r\n2. Segundo\r\n\r\n- Terceiro\r\n\r\n' +
        LONG_BODY,
    )

    expect(result.normalized).not.toContain('\r')
    expect(result.blocks).toEqual([
      {
        type: 'heading',
        level: 2,
        children: [{ type: 'text', value: 'Título' }],
      },
      {
        type: 'paragraph',
        children: [
          { type: 'text', value: 'Texto com ' },
          { type: 'strong', children: [{ type: 'text', value: 'força' }] },
          { type: 'text', value: ', ' },
          { type: 'emphasis', children: [{ type: 'text', value: 'ênfase' }] },
          { type: 'text', value: ' e ' },
          {
            type: 'link',
            url: 'https://bodyflow.app',
            children: [{ type: 'text', value: 'fonte' }],
          },
          { type: 'text', value: '.' },
        ],
      },
      {
        type: 'blockquote',
        children: [{ type: 'paragraph', children: [{ type: 'text', value: 'Conselho seguro.' }] }],
      },
      {
        type: 'list',
        ordered: true,
        items: [
          [{ type: 'paragraph', children: [{ type: 'text', value: 'Primeiro' }] }],
          [{ type: 'paragraph', children: [{ type: 'text', value: 'Segundo' }] }],
        ],
      },
      {
        type: 'list',
        ordered: false,
        items: [[{ type: 'paragraph', children: [{ type: 'text', value: 'Terceiro' }] }]],
      },
      { type: 'paragraph', children: [{ type: 'text', value: LONG_BODY.trimEnd() }] },
    ])
    expect(result.wordCount).toBeGreaterThan(0)
    expect(result.readingTimeMinutes).toBe(1)
  })

  it('rounds reading time from 200 words per minute with a one minute minimum', () => {
    expect(validateContentMarkdown('word '.repeat(200))).toMatchObject({ wordCount: 200, readingTimeMinutes: 1 })
    expect(validateContentMarkdown('word '.repeat(201))).toMatchObject({ wordCount: 201, readingTimeMinutes: 2 })
  })

  it.each([
    ['raw HTML', `<strong>${LONG_BODY}</strong>`],
    ['H1', `# Duplicated title\n\n${LONG_BODY}`],
    ['inline code', `Use \`code\` carefully. ${LONG_BODY}`],
    ['code block', `\`\`\`text\nunsafe\n\`\`\`\n\n${LONG_BODY}`],
    ['thematic break', `${LONG_BODY}\n\n---\n\n${LONG_BODY}`],
    ['inline image', `![cover](https://bodyflow.app/cover.png)\n\n${LONG_BODY}`],
    ['nested image link', `[![cover](https://bodyflow.app/cover.png)](https://bodyflow.app)\n\n${LONG_BODY}`],
    ['HTTP link', `[source](http://bodyflow.app)\n\n${LONG_BODY}`],
    ['data URL', `[source](data:text/plain,unsafe)\n\n${LONG_BODY}`],
    ['JavaScript URL', `[source](javascript:alert(1))\n\n${LONG_BODY}`],
    ['protocol-relative URL', `[source](//bodyflow.app)\n\n${LONG_BODY}`],
    ['definition node', `[source][bodyflow]\n\n[bodyflow]: https://bodyflow.app\n\n${LONG_BODY}`],
    ['body under 100 characters', 'Texto curto para validar o mínimo de caracteres exigido pelo conteúdo editorial.'],
    ['body over 50,000 characters', 'a'.repeat(50_001)],
  ])('rejects %s', (_description, value) => {
    expect(() => validateContentMarkdown(value)).toThrow()
  })

  it.each([
    ['blockquotes', `${'> '.repeat(8)}${LONG_BODY}`],
    ['lists', nestedList(8)],
  ])('accepts exactly eight nested %s', (_description, value) => {
    expect(() => validateContentMarkdown(value)).not.toThrow()
  })

  it.each([
    ['blockquotes', `${'> '.repeat(9)}${LONG_BODY}`],
    ['lists', nestedList(9)],
  ])('rejects nine nested %s', (_description, value) => {
    expect(() => validateContentMarkdown(value)).toThrow()
  })

  it('rejects an ordered list that starts after one', () => {
    expect(() => validateContentMarkdown(`3. Terceiro item\n\n${LONG_BODY}`)).toThrow()
  })

  it('rejects more than eight nested inline nodes', () => {
    const nestedInlineMarkdown = `${'**'.repeat(9)}texto${'**'.repeat(9)}\n\n${LONG_BODY}`

    expect(() => validateContentMarkdown(nestedInlineMarkdown)).toThrow()
  })
})

describe('content cursors', () => {
  it('round-trips an opaque publication cursor', () => {
    const cursor = encodeContentCursor({ publishAt: '2026-07-21T15:00:00.000Z', publicationId: UUID })

    expect(cursor).not.toContain('{')
    expect(decodeContentCursor(cursor)).toEqual({
      publishAt: '2026-07-21T15:00:00.000Z',
      publicationId: UUID,
    })
  })

  it.each([
    ['malformed', 'not-base64url'],
    ['oversized', 'a'.repeat(513)],
    [
      'non UUID',
      Buffer.from(
        JSON.stringify({ publishAt: '2026-07-21T15:00:00.000Z', publicationId: 'abc' }),
      ).toString('base64url'),
    ],
    [
      'non ISO date',
      Buffer.from(JSON.stringify({ publishAt: 'tomorrow', publicationId: UUID })).toString('base64url'),
    ],
  ])('rejects a %s cursor', (_description, cursor) => {
    expect(() => decodeContentCursor(cursor)).toThrow()
  })
})
