import { createHash } from 'node:crypto'
import { readFileSync } from 'node:fs'
import { describe, expect, it } from 'vitest'

const files = [
  'curated-phrases-engagement.json',
  'curated-phrases-food.json',
  'curated-phrases-food-phase-b.json',
  'curated-phrases-food-phase-c.json',
  'curated-phrases-food-phase-c2.json',
  'curated-phrases-food-phase-d.json',
  'curated-phrases-food-phase-e.json',
  'curated-phrases-food-phase-f.json',
  'curated-phrases-food-phase-g.json',
]

describe('C5: catálogo local fiel aos nove JSON versionados', () => {
  it('entrega cada fonte literal e seu fingerprint sem depender de scripts no runtime', async () => {
    const { FLOW_CURATED_PHRASE_CATALOG: catalog } = await import(
      './flow-curated-phrase-catalog.js'
    )
    expect(catalog.sources.map((source) => source.file)).toEqual(files)
    for (const source of catalog.sources) {
      const original = readFileSync(
        new URL(`../../../scripts/data/${source.file}`, import.meta.url),
      )
      const copy = readFileSync(
        new URL(`./data/flow-curated-phrases/${source.file}`, import.meta.url),
      )
      expect(copy.equals(original), source.file).toBe(true)
      expect(source.sha256).toBe(createHash('sha256').update(original).digest('hex'))
      expect(source.data).toEqual(JSON.parse(original.toString('utf8')))
    }
  })

  it('disponibiliza todas as entradas e proveniências, inclusive C2 e duplicatas', async () => {
    const { FLOW_CURATED_PHRASE_CATALOG: catalog } = await import(
      './flow-curated-phrase-catalog.js'
    )
    const food = catalog.entries.filter((entry) => entry.kind === 'food')
    const incentive = catalog.entries.filter((entry) => entry.kind === 'incentive')
    expect(food).toHaveLength(1321)
    expect(incentive).toHaveLength(200)
    expect(new Set(food.map((entry) => entry.sourceText)).size).toBe(1262)
    expect(new Set(food.map((entry) => entry.source.blockId)).size).toBe(27)
    expect(new Set(catalog.entries.map((entry) => entry.id)).size).toBe(1521)
    const normalize = (name: string) =>
      name
        .normalize('NFD')
        .replace(/\p{Diacritic}/gu, '')
        .toLowerCase()
        .trim()
        .replace(/\s+/gu, ' ')
    expect(new Set(food.flatMap((entry) => entry.foodAliases.map(normalize))).size).toBe(214)
    expect(incentive.filter((entry) => entry.sourceSlot === 'any')).toHaveLength(163)
    expect(incentive.filter((entry) => entry.sourceSlot === 'continuity')).toHaveLength(24)
    expect(incentive.filter((entry) => entry.sourceSlot === 'workout')).toHaveLength(12)
    expect(incentive.filter((entry) => entry.sourceSlot === 'morning')).toHaveLength(1)
    expect(catalog.entries.find((entry) => entry.id === 'food:c2:bom_verduras:007')).toBeDefined()
    const duplicated = ['food:b:ruim_sorvetes:011', 'food:c2:ruim_sorvetes:010'].map((id) =>
      catalog.entries.find((entry) => entry.id === id),
    )
    expect(duplicated[0]?.sourceText).toBe(duplicated[1]?.sourceText)
    expect(duplicated[0]?.sourceText).toBe(
      '{alimento} é uma opção que desperta prazer imediato, mas tende a saciar menos do que alimentos ricos em proteínas e fibras.',
    )
    expect(duplicated[0]?.source.file).not.toBe(duplicated[1]?.source.file)
  })

  it('mantém texto, gatilhos, slots e referência exatos para cada consumidor', async () => {
    const { FLOW_CURATED_PHRASE_CATALOG: catalog } = await import(
      './flow-curated-phrase-catalog.js'
    )
    for (const entry of catalog.entries) {
      const raw = JSON.parse(
        readFileSync(
          new URL(`../../../scripts/data/${entry.source.file}`, import.meta.url),
          'utf8',
        ),
      )
      if (entry.kind === 'food') {
        const block = raw.blocks.find(
          (row: { bloco_id: string }) => row.bloco_id === entry.source.blockId,
        )
        expect(entry.sourceText).toBe(block.frases[entry.source.phraseIndex])
        expect(entry.foodAliases).toEqual(block.alimentos)
      } else {
        expect(entry.sourceText).toBe(raw.phrases[entry.source.phraseIndex].phrase)
        expect(entry.sourceSlot).toBe(raw.phrases[entry.source.phraseIndex].slot)
      }
      expect(entry.locale).toBe(raw._language)
    }
  })

  it('não deixa um consumidor alterar o catálogo compartilhado', async () => {
    const { FLOW_CURATED_PHRASE_CATALOG: catalog } = await import(
      './flow-curated-phrase-catalog.js'
    )
    const entry = catalog.entries[0]
    expect(entry).toBeDefined()
    expect(() => Object.defineProperty(entry, 'sourceText', { value: 'alterado' })).toThrow()
    expect(() => Object.defineProperty(catalog.entries, '0', { value: {} })).toThrow()
  })

  it('não transforma lacunas reais em frases públicas ou traduções inventadas', async () => {
    const { FLOW_CURATED_PHRASE_CATALOG: catalog } = await import(
      './flow-curated-phrase-catalog.js'
    )
    expect(
      catalog.entries.some((entry) => /\brefei[cç][aã]o pr[aá]tica\b/iu.test(entry.sourceText)),
    ).toBe(false)
    expect(new Set(catalog.entries.map((entry) => entry.locale))).toEqual(new Set(['pt-BR']))
    expect(catalog.entries.some((entry) => entry.id === 'synthetic-slot-policy')).toBe(false)
    expect(
      catalog.entries.some((entry) =>
        /\bMPP\b|Muscular Power Plant|Menescal|Usina[ -]+muscular/iu.test(entry.sourceText),
      ),
    ).toBe(false)
  })
})
