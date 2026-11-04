import { describe, expect, it } from 'vitest'
import {
  writerCommand,
  writerResolved,
  writerSource,
} from './__fixtures__/conversation-meal-writer'

import { parseConversationResolvedMeal } from './conversation-meal-writer-contracts'

type Mutable = ReturnType<typeof writerResolved>
function parse(raw: unknown, binding = { command: writerCommand(), source: writerSource() }) {
  return parseConversationResolvedMeal(raw, binding)
}
describe('closed SQL resolved meal codec', () => {
  it('accepts the real capture factory structural superset without cloning or invoking its ports', () => {
    const source = {
      ...writerSource(),
      action: 'captured' as const,
      sourceReader: {
        ownerId: writerCommand().ownerId,
        asOf: writerSource().capturedAt,
        read() {
          throw new Error('unexpected lookup')
        },
      },
      sourceReceipts() {
        throw new Error('unexpected receipt lookup')
      },
      auditSink() {
        throw new Error('unexpected audit')
      },
      auditEvents() {
        throw new Error('unexpected audit lookup')
      },
    }
    expect(parse(writerResolved(), { command: writerCommand(), source })).toEqual(writerResolved())
  })
  it('accepts exact SQL decimal density boundary without IEEE rounding refusal', () => {
    const v = writerResolved()
    Object.assign(v.items[0], {
      quantity_g: 0.076,
      kcal: 5.722,
      protein_g: 0,
      carbs_g: 0,
      fat_g: 0,
    })
    v.totals = { kcal: 5.7, protein_g: 0, carbs_g: 0, fat_g: 0 }
    expect(parse(v)).toEqual(v)
  })
  it('preserves exact unrounded saved facts and deep detaches the source-bound payload', () => {
    const raw = writerResolved()
    raw.items[0].kcal = 128.04
    const result = parse(raw)
    expect(result).toEqual(raw)
    raw.items[0].name = 'mutated'
    expect(result?.items[0]?.name).toBe('Arroz branco cozido')
    expect(Object.isFrozen(result?.items[0]?.input_indexes)).toBe(true)
  })
  it.each([
    [
      'unknown root key',
      (v: Mutable) => {
        Object.assign(v, { injected: true })
      },
    ],
    [
      'missing explicit nullable',
      (v: Mutable) => {
        Reflect.deleteProperty(v.items[0], 'confidence')
      },
    ],
    [
      'wrong source',
      (v: Mutable) => {
        v.source_hash = 'd'.repeat(64)
      },
    ],
    [
      'wrong proof input',
      (v: Mutable) => {
        v.semantic_proof.input_hash = 'd'.repeat(64)
      },
    ],
    [
      'missing source unit',
      (v: Mutable) => {
        v.semantic_proof.source_units = []
      },
    ],
    [
      'incomplete coverage',
      (v: Mutable) => {
        v.semantic_proof.input_count = 2
      },
    ],
    [
      'repeated index',
      (v: Mutable) => {
        v.items[0].input_indexes = [0, 0]
      },
    ],
    [
      'out of range index',
      (v: Mutable) => {
        v.items[0].input_indexes = [1]
      },
    ],
    [
      'duplicate name',
      (v: Mutable) => {
        v.items.push({ ...v.items[0] })
      },
    ],
    [
      'invalid source enum',
      (v: Mutable) => {
        v.items[0].nutrition_source = 'pending_approved'
      },
    ],
    [
      'canonical without reference',
      (v: Mutable) => {
        v.items[0].food_db_id = null
      },
    ],
    [
      'history without reference',
      (v: Mutable) => {
        v.items[0].nutrition_source = 'history'
        v.items[0].food_db_id = null
      },
    ],
    [
      'impossible density',
      (v: Mutable) => {
        v.items[0].kcal = 960
        v.totals.kcal = 960
      },
    ],
    [
      'negative macro',
      (v: Mutable) => {
        v.items[0].protein_g = -1
      },
    ],
    [
      'unrounded total',
      (v: Mutable) => {
        v.totals.kcal = 128.01
      },
    ],
    [
      'inconsistent total',
      (v: Mutable) => {
        v.totals.kcal = 128.1
      },
    ],
    [
      'wrong meal type',
      (v: Mutable) => {
        v.meal_type = 'jantar'
      },
    ],
    [
      'blank name',
      (v: Mutable) => {
        v.items[0].name = ' '
      },
    ],
    [
      'trimmed name',
      (v: Mutable) => {
        v.items[0].name = ' arroz'
      },
    ],
    [
      'unknown annotation key',
      (v: Mutable) => {
        Reflect.set(v, 'preparation_annotations', [{ x: 1 }])
      },
    ],
    [
      'foreign annotation index',
      (v: Mutable) => {
        v.preparation_annotations = [
          {
            schema: 'consumed.preparation.v1',
            kind: 'default_cooked',
            input_indexes: [1],
            food_name: v.items[0].name,
            policy: 'consumed-meal-v1',
            reference_id: 'food_db:1',
          },
        ]
      },
    ],
    [
      'duplicate receipt',
      (v: Mutable) => {
        v.source_receipts = Array(2).fill({
          id: '00000000-0000-0000-0000-000000000000',
          hash: 'e'.repeat(64),
        })
      },
    ],
  ])('rejects %s', (_name, mutate) => {
    const v = writerResolved()
    mutate(v)
    expect(() => parse(v)).toThrow()
  })
  it('accepts complete generic subset indices and SQL-supported overlapping cross-item provenance', () => {
    const v = writerResolved()
    v.semantic_proof.input_count = 3
    v.items[0].input_indexes = [0, 2]
    v.items.push({ ...v.items[0], name: 'Feijão', input_indexes: [1, 2] })
    v.totals = { kcal: 256, protein_g: 5, carbs_g: 56.2, fat_g: 0.4 }
    v.preparation_annotations.push({
      schema: 'consumed.preparation.v1',
      kind: 'default_cooked',
      input_indexes: [2],
      food_name: 'Arroz branco cozido',
      policy: 'consumed-meal-v1',
      reference_id: 'food_db:1',
    })
    expect(parse(v)).toEqual(v)
  })
  it.each([
    'owner_id',
    'command_id',
    'input_hash',
    'epoch',
  ])('refuses altered stored source %s', (field) => {
    const source = writerSource()
    Object.assign(source.context, { [field]: '0'.repeat(64) })
    expect(() => parse(writerResolved(), { command: writerCommand(), source })).toThrow()
  })
  it.each([
    'owner',
    'day',
    'catalog',
    'source_evidence',
  ])('rejects unknown stored %s keys rather than rewriting private context', (field) => {
    const source = writerSource()
    Object.assign(source.context[field as 'owner'], { untrusted: 1 })
    expect(() => parse(writerResolved(), { command: writerCommand(), source })).toThrow()
  })
})
