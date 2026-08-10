import { readFileSync } from 'node:fs'
import { describe, expect, it } from 'vitest'
import { validateContentMarkdown, type ContentMarkdownBlock } from './content.js'

type NativeExpectation =
  | 'parse_normalized'
  | 'reject_source'
  | 'backend_canonicalization_only'

interface MarkdownCompatibilityFixture {
  name: string
  source: string
  accepted: boolean
  nativeExpectation: NativeExpectation
  normalized?: string
  document?: {
    blocks: ContentMarkdownBlock[]
  }
}

const corpusURL = new URL(
  '../../../apps/ios/BodyFlow/BodyFlowTests/Fixtures/Prompt14MarkdownCompatibility.json',
  import.meta.url,
)
const backendCanonicalizationOnlyNames = new Set([
  'normalized-body-under-100-characters',
  'normalized-body-over-50000-characters',
  'normalized-crlf-over-50000-utf16-units',
])

function readCorpus(value: unknown): MarkdownCompatibilityFixture[] {
  if (!Array.isArray(value)) throw new Error('Markdown compatibility corpus must be an array')

  const corpus = value.map((entry, index) => readFixture(entry, index))
  if (corpus.length !== 50) throw new Error(`Expected 50 Markdown fixtures, received ${corpus.length}`)
  if (new Set(corpus.map(({ name }) => name)).size !== corpus.length) {
    throw new Error('Markdown compatibility fixture names must be unique')
  }

  const counts = corpus.reduce(
    (result, fixture) => {
      result[fixture.nativeExpectation] += 1
      return result
    },
    { parse_normalized: 0, reject_source: 0, backend_canonicalization_only: 0 },
  )
  if (
    counts.parse_normalized !== 11 ||
    counts.reject_source !== 36 ||
    counts.backend_canonicalization_only !== 3
  ) {
    throw new Error(`Expected native expectation distribution 11/36/3, received ${JSON.stringify(counts)}`)
  }

  return corpus
}

function readFixture(value: unknown, index: number): MarkdownCompatibilityFixture {
  if (value === null || typeof value !== 'object' || Array.isArray(value)) {
    throw new Error(`Fixture ${index} must be an object`)
  }
  const fixture = value as Record<string, unknown>
  if (typeof fixture.name !== 'string' || typeof fixture.source !== 'string' || typeof fixture.accepted !== 'boolean') {
    throw new Error(`Fixture ${index} must provide string name/source and boolean accepted`)
  }
  if (
    fixture.native_expectation !== 'parse_normalized' &&
    fixture.native_expectation !== 'reject_source' &&
    fixture.native_expectation !== 'backend_canonicalization_only'
  ) {
    throw new Error(`Fixture ${fixture.name} has invalid native_expectation`)
  }
  const allowedFields = new Set(['name', 'source', 'accepted', 'native_expectation', 'normalized', 'document'])
  const unexpectedField = Object.keys(fixture).find((field) => !allowedFields.has(field))
  if (unexpectedField) throw new Error(`Fixture ${index} has unexpected field ${unexpectedField}`)

  const nativeExpectation = fixture.native_expectation
  const hasNormalized = Object.hasOwn(fixture, 'normalized')
  const hasDocument = Object.hasOwn(fixture, 'document')

  if (fixture.accepted) {
    if (nativeExpectation !== 'parse_normalized' || typeof fixture.normalized !== 'string' || !hasDocument) {
      throw new Error(`Accepted fixture ${fixture.name} must provide parse_normalized, normalized, and document`)
    }
    return {
      name: fixture.name,
      source: fixture.source,
      accepted: true,
      nativeExpectation,
      normalized: fixture.normalized,
      document: readPortableDocument(fixture.document, fixture.name),
    }
  }

  if (nativeExpectation === 'parse_normalized' || hasNormalized || hasDocument) {
    throw new Error(`Rejected fixture ${fixture.name} must not provide accepted-only fields`)
  }
  if (
    nativeExpectation === 'backend_canonicalization_only' &&
    !backendCanonicalizationOnlyNames.has(fixture.name)
  ) {
    throw new Error(`Only the approved size fixtures may be backend_canonicalization_only: ${fixture.name}`)
  }
  if (
    nativeExpectation !== 'backend_canonicalization_only' &&
    backendCanonicalizationOnlyNames.has(fixture.name)
  ) {
    throw new Error(`Approved size fixture must be backend_canonicalization_only: ${fixture.name}`)
  }

  return { name: fixture.name, source: fixture.source, accepted: false, nativeExpectation }
}

function readPortableDocument(value: unknown, name: string): { blocks: ContentMarkdownBlock[] } {
  if (value === null || typeof value !== 'object' || Array.isArray(value)) {
    throw new Error(`Accepted fixture ${name} must provide a portable document object`)
  }
  const document = value as Record<string, unknown>
  if (Object.keys(document).length !== 1 || !Object.hasOwn(document, 'blocks') || !Array.isArray(document.blocks)) {
    throw new Error(`Accepted fixture ${name} document must use the portable { blocks: [...] } wire shape`)
  }
  return { blocks: document.blocks as ContentMarkdownBlock[] }
}

const corpus = readCorpus(JSON.parse(readFileSync(corpusURL, 'utf8')))

describe('iOS Markdown compatibility corpus', () => {
  it('matches the backend Markdown authority exactly', () => {
    for (const fixture of corpus) {
      switch (fixture.nativeExpectation) {
      case 'parse_normalized':
        expect(validateContentMarkdown(fixture.source), fixture.name).toEqual({
          normalized: fixture.normalized!,
          blocks: fixture.document!.blocks,
          wordCount: expect.any(Number),
          readingTimeMinutes: expect.any(Number),
        })
        break
      case 'reject_source':
        expect(() => validateContentMarkdown(fixture.source), fixture.name).toThrow()
        break
      case 'backend_canonicalization_only':
        expect(() => validateContentMarkdown(fixture.source), fixture.name).toThrow()
        expect(() => validateContentMarkdown(fixture.source), fixture.name).toThrow(
          'normalized body must be between 100 and 50000 characters',
        )
        break
      }
    }
  })
})
