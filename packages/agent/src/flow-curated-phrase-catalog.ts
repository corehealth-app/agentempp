/** Flow-only static sources. Extraction phases are not clinical protocols. */
import { createHash } from 'node:crypto'
import engagement from './data/flow-curated-phrases/curated-phrases-engagement.json'
import foodA from './data/flow-curated-phrases/curated-phrases-food.json'
import foodB from './data/flow-curated-phrases/curated-phrases-food-phase-b.json'
import foodC from './data/flow-curated-phrases/curated-phrases-food-phase-c.json'
import foodC2 from './data/flow-curated-phrases/curated-phrases-food-phase-c2.json'
import foodD from './data/flow-curated-phrases/curated-phrases-food-phase-d.json'
import foodE from './data/flow-curated-phrases/curated-phrases-food-phase-e.json'
import foodF from './data/flow-curated-phrases/curated-phrases-food-phase-f.json'
import foodG from './data/flow-curated-phrases/curated-phrases-food-phase-g.json'

export type FlowPhraseMealKind = 'cafe' | 'almoco' | 'lanche' | 'jantar' | 'ceia' | 'outro'
export type FlowPhraseSourceSlot = 'any' | 'continuity' | 'morning' | 'workout'

export interface FlowPhraseEntry {
  readonly id: string
  readonly kind: 'food' | 'incentive'
  readonly locale: 'pt-BR'
  readonly sourceText: string
  readonly foodAliases: readonly string[]
  readonly sourceSlot?: FlowPhraseSourceSlot
  /** Explicit future restriction by source ID; not inferred from clinical metadata. */
  readonly allowedMealKinds?: readonly FlowPhraseMealKind[]
  readonly source: {
    readonly file: string
    readonly blockId?: string
    readonly phraseIndex: number
  }
}

export interface FlowPhraseCatalog {
  readonly version: string
  readonly entries: readonly FlowPhraseEntry[]
  readonly sources: readonly {
    readonly file: string
    readonly sha256: string
    readonly data: unknown
  }[]
}

const sources = [
  {
    file: 'curated-phrases-engagement.json',
    sha256: 'f8df3c9b1be8f40ead0bff1f97888cfe3d2534c05d928fd50892487f8f61f54c',
    data: engagement,
  },
  {
    file: 'curated-phrases-food.json',
    sha256: 'd411b0afce13b8f3bc5fba7cb970e7edf49780cc79eca7b312071fc24b7612ca',
    data: foodA,
  },
  {
    file: 'curated-phrases-food-phase-b.json',
    sha256: '90ed182a90681cdec3d8e6d83f3340645ee645570e3fd9d4530386551cacf222',
    data: foodB,
  },
  {
    file: 'curated-phrases-food-phase-c.json',
    sha256: '56905ce0fd4438534587b025adb423ece63edb515f07d417af45966709036d70',
    data: foodC,
  },
  {
    file: 'curated-phrases-food-phase-c2.json',
    sha256: '246c9650e28788ef6b9181986a04a04894dea5a8da8ee52fd9ed25b1e982a304',
    data: foodC2,
  },
  {
    file: 'curated-phrases-food-phase-d.json',
    sha256: '1f1ffc4c83bbda18db2b4966fb7a2275f2321ef5c4f09b8dfe53afa31ab73577',
    data: foodD,
  },
  {
    file: 'curated-phrases-food-phase-e.json',
    sha256: '1048d3e3fba17d5f667270ae5d80973c2f2031c27fd78b2dee2418ca6847af33',
    data: foodE,
  },
  {
    file: 'curated-phrases-food-phase-f.json',
    sha256: '991d1a9e3af61a5ef0b11914b1abdeebb6042df242d67681fc0cc85df4554af0',
    data: foodF,
  },
  {
    file: 'curated-phrases-food-phase-g.json',
    sha256: 'ce31c1e42ffdb715ed38b0961efb341ac730a2c4c809e13027576cb1fa172923',
    data: foodG,
  },
]

function freeze<T>(value: T): T {
  if (typeof value === 'object' && value !== null && !Object.isFrozen(value)) {
    for (const child of Object.values(value)) freeze(child)
    Object.freeze(value)
  }
  return value
}

function sourceSlot(value: string): FlowPhraseSourceSlot {
  if (value === 'any' || value === 'continuity' || value === 'morning' || value === 'workout')
    return value
  throw new Error('Unreviewed Flow phrase slot')
}

const entries: FlowPhraseEntry[] = []
for (const source of sources) {
  if (source.data._language !== 'pt-BR') throw new Error('Unreviewed Flow phrase locale')
  if ('phrases' in source.data) {
    source.data.phrases.forEach((phrase, index) => {
      entries.push({
        id: `engagement:${String(index).padStart(3, '0')}`,
        kind: 'incentive',
        locale: 'pt-BR',
        sourceText: phrase.phrase,
        foodAliases: [],
        sourceSlot: sourceSlot(phrase.slot),
        source: { file: source.file, phraseIndex: index },
      })
    })
  } else {
    const phase = source.file.match(/phase-([a-z0-9]+)\.json$/u)?.[1] ?? 'a'
    source.data.blocks.forEach((block) => {
      block.frases.forEach((text, index) => {
        entries.push({
          id: `food:${phase}:${block.bloco_id}:${String(index).padStart(3, '0')}`,
          kind: 'food',
          locale: 'pt-BR',
          sourceText: text,
          foodAliases: block.alimentos,
          source: { file: source.file, blockId: block.bloco_id, phraseIndex: index },
        })
      })
    })
  }
}

const digest = createHash('sha256')
  .update(JSON.stringify(sources.map(({ file, sha256 }) => [file, sha256])))
  .digest('hex')

/** Immutable shared data only; no per-person state, IO, ingestion or consumer activation. */
export const FLOW_CURATED_PHRASE_CATALOG: FlowPhraseCatalog = freeze({
  version: `flow-curated.v1:${digest}`,
  sources,
  entries,
})
