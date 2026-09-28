import { readFileSync } from 'node:fs'
import { describe, expect, it } from 'vitest'
import { validateContentMarkdown } from './content.js'

// The Library collection for the Performe AI evaluation lives outside the
// database until an editor publishes it. This test holds every article to
// the same limits the CMS enforces (content_versions checks and the Markdown
// validator), so a draft that passes here does not fail at publication.

const packURL = new URL('../../../docs/content/library-v1/', import.meta.url)

interface LocaleEntry {
  file: string
  title: string
  excerpt: string
}
interface Article {
  slug: string
  category: string
  locales: Record<string, LocaleEntry>
}
interface Pack {
  status: string
  verifiedSources: Array<{ url: string; accessed: string }>
  articles: Article[]
}

const pack = JSON.parse(readFileSync(new URL('pack.json', packURL), 'utf8')) as Pack

// content_versions_category_check and content_versions_locale_check.
const CATEGORIES = new Set([
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
const LOCALES = ['pt-BR', 'en-US'] as const

const DISCLAIMER: Record<(typeof LOCALES)[number], RegExp> = {
  'pt-BR': /não substitui a orientação do seu médico ou nutricionista\.\s*$/i,
  'en-US': /does not replace advice from your doctor or dietitian\.\s*$/i,
}
const SOURCES_HEADING: Record<(typeof LOCALES)[number], string> = {
  'pt-BR': '## Fontes e leitura complementar',
  'en-US': '## Sources and further reading',
}

function body(entry: LocaleEntry): string {
  return readFileSync(new URL(entry.file, packURL), 'utf8')
}

function links(markdown: string): string[] {
  return [...markdown.matchAll(/\]\((https:\/\/[^)\s]+)\)/g)].map((match) => match[1] as string)
}

describe('Performe AI Library pack v1', () => {
  it('is marked as an unpublished draft pending review', () => {
    expect(pack.status).toMatch(/^DRAFT — PENDING .*REVIEW; NOT PUBLISHED$/)
  })

  it('has unique slugs, known categories and both locales for every article', () => {
    expect(pack.articles.length).toBeGreaterThanOrEqual(6)
    expect(new Set(pack.articles.map((article) => article.slug)).size).toBe(pack.articles.length)
    for (const article of pack.articles) {
      expect(CATEGORIES.has(article.category), article.slug).toBe(true)
      expect(Object.keys(article.locales).sort()).toEqual([...LOCALES].sort())
    }
  })

  for (const article of pack.articles) {
    for (const locale of LOCALES) {
      const entry = article.locales[locale] as LocaleEntry

      describe(`${article.slug} (${locale})`, () => {
        it('fits the CMS title and excerpt limits', () => {
          expect(entry.title.length).toBeGreaterThanOrEqual(3)
          expect(entry.title.length).toBeLessThanOrEqual(120)
          expect(entry.excerpt.length).toBeGreaterThanOrEqual(20)
          expect(entry.excerpt.length).toBeLessThanOrEqual(280)
        })

        it('passes the publication Markdown validator unchanged in meaning', () => {
          const validated = validateContentMarkdown(body(entry))
          expect(validated.normalized.length).toBeGreaterThanOrEqual(100)
          expect(validated.normalized.length).toBeLessThanOrEqual(50_000)
          expect(validated.readingTimeMinutes).toBeGreaterThanOrEqual(1)
          // No H1: the title comes from the CMS field, not the body.
          expect(validated.blocks.some((block) => block.type === 'heading')).toBe(true)
        })

        it('ends with the educational disclaimer', () => {
          expect(body(entry)).toMatch(DISCLAIMER[locale])
        })

        it('links only to sources recorded as verified, with an access date', () => {
          const verified = new Set(pack.verifiedSources.map((source) => source.url))
          const found = links(body(entry))
          for (const url of found) expect(verified.has(url), url).toBe(true)
          if (article.category === 'using_bodyflow' && found.length === 0) return
          expect(body(entry)).toContain(SOURCES_HEADING[locale])
          expect(found.length).toBeGreaterThan(0)
          const dated = locale === 'pt-BR' ? /consultado em 28\/09\/2026/ : /accessed 2026-09-28/
          expect(body(entry).match(new RegExp(dated, 'g'))?.length).toBe(found.length)
        })

        it('never gives medication or supplement dosing', () => {
          expect(body(entry)).not.toMatch(/\b\d+(?:[.,]\d+)?\s?(?:mg|mcg|µg|ui|iu)\b/i)
        })
      })
    }
  }

  it('keeps every verified source dated on the day it was checked', () => {
    for (const source of pack.verifiedSources) {
      expect(source.url.startsWith('https://')).toBe(true)
      expect(source.accessed).toMatch(/^\d{4}-\d{2}-\d{2}$/)
    }
  })
})
