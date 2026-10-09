import { createHash } from 'node:crypto'
import { describe, expect, it } from 'vitest'
import { FLOW_CURATED_PHRASE_CATALOG } from './flow-curated-phrase-catalog.js'
import { createFlowPhraseRotationState } from './flow-curated-phrase-selector.js'
import type {
  FlowStatusPhraseCursor,
  FlowStatusPhraseReplyRequest,
} from './flow-curated-phrases.js'

const owner = '00000000-0000-0000-0000-00000000c501'
const request = {
  userId: owner,
  eventKey: `mobile_flow/${owner}/c5-event-0001`,
  locale: 'pt-BR',
  accountName: 'Pessoa sintética',
  kind: 'incentive' as const,
  slot: 'any' as const,
  statusText: 'Status oficial de hoje.',
  authority: {
    currentProtocol: 'recomposicao' as const,
    dailyTargets: { calories_target: 2400, protein_target: 150 },
  },
}
// A runtime import makes the missing integration an individual RED, not a
// transform/dependency error that prevents the existing selector from loading.
async function subject() {
  const path = './flow-curated-phrases.js'
  return import(path)
}

describe('C5: prepare one private durable status packet', () => {
  it('selects the literal first phrase and returns its rendered hash and own receipt', async () => {
    const { prepareFlowStatusPhraseReply } = await subject()
    const result = prepareFlowStatusPhraseReply(request, null)
    expect(result.content).toBe(
      'Status oficial de hoje.\n\nConsistência vale mais do que perfeição.',
    )
    expect(result.nextCursor).toEqual({
      schema: 'flow.phrase-state.v1',
      userId: owner,
      catalogVersion: FLOW_CURATED_PHRASE_CATALOG.version,
      ordinal: 1,
      lastTextKey: '972da9d0303d445a31ba14f93f6e7fcd29f5e625b274244313c6bbe65fc45a24',
      usedTextKeys: ['972da9d0303d445a31ba14f93f6e7fcd29f5e625b274244313c6bbe65fc45a24'],
    })
    expect(result.receipt).toEqual({
      eventKey: request.eventKey,
      requestFingerprint: 'ad21dd91df986aaf7ffbce6760ecfcfc0df4bb223481946e208b4d17e292e580',
      selection: {
        phrase: 'Consistência vale mais do que perfeição.',
        phraseId: 'engagement:002',
        sourceText: 'Consistência vale mais do que perfeição.',
        foodCanonicalName: null,
        reason: 'selected_incentive',
      },
    })
    expect(Object.keys(result).sort()).toEqual(['content', 'nextCursor', 'receipt'])
    expect(result.nextCursor).not.toHaveProperty('replayByEventKey')
  })

  it('preserves the input cursor and appends the actual next phrase after a CAS reread', async () => {
    const { prepareFlowStatusPhraseReply } = await subject()
    const first = prepareFlowStatusPhraseReply(request, null)
    const saved = structuredClone(first.nextCursor)
    const next = prepareFlowStatusPhraseReply(
      { ...request, eventKey: `mobile_flow/${owner}/c5-event-0002` },
      first.nextCursor,
    )
    expect(next.content).toBe(
      'Status oficial de hoje.\n\nVocê está aprendendo que equilíbrio vale mais do que restrição.',
    )
    expect(next.nextCursor.ordinal).toBe(2)
    expect(next.nextCursor.lastTextKey).toBe(
      'd8159ddab0b631622ffe4bca81e41e5565e2ed10d44d125937e3f881f0558175',
    )
    expect(first.nextCursor).toEqual(saved)
  })

  it('produces a durable empty English receipt without advancing the ordinal', async () => {
    const { prepareFlowStatusPhraseReply } = await subject()
    const result = prepareFlowStatusPhraseReply(
      { ...request, locale: 'en', statusText: 'Today’s official status.' },
      null,
    )
    expect(result.content).toBe('Today’s official status.')
    expect(result.nextCursor.ordinal).toBe(0)
    expect(result.nextCursor.lastTextKey).toBeNull()
    expect(result.receipt.selection).toEqual({
      phrase: null,
      phraseId: null,
      sourceText: null,
      foodCanonicalName: null,
      reason: 'unsupported_language',
    })
    expect(result.receipt.eventKey).toBe(request.eventKey)
  })

  it('does not silently initialize a cursor belonging to another account or catalog', async () => {
    const { prepareFlowStatusPhraseReply } = await subject()
    const { replayByEventKey: _receipts, ...cursor } = createFlowPhraseRotationState(
      owner,
      FLOW_CURATED_PHRASE_CATALOG.version,
    )
    expect(() =>
      prepareFlowStatusPhraseReply(request, { ...cursor, userId: 'other-owner' }),
    ).toThrow()
    expect(() =>
      prepareFlowStatusPhraseReply(request, { ...cursor, catalogVersion: 'unapproved' }),
    ).toThrow()
    expect(() => prepareFlowStatusPhraseReply(request, { ...cursor, ordinal: -1 })).toThrow()
  })

  it('rejects a runtime workout request instead of publishing its incentive fallback', async () => {
    const { prepareFlowStatusPhraseReply } = await subject()
    expect(() =>
      prepareFlowStatusPhraseReply(
        { ...request, kind: 'workout' } as unknown as FlowStatusPhraseReplyRequest,
        null,
      ),
    ).toThrow()
  })

  it('rejects a runtime morning slot even when a real morning source is available', async () => {
    const { prepareFlowStatusPhraseReply } = await subject()
    const morning = FLOW_CURATED_PHRASE_CATALOG.entries.find(
      (entry) => entry.kind === 'incentive' && entry.sourceSlot === 'morning',
    )
    expect(morning).toBeDefined()
    if (!morning) throw new Error('Missing real morning source')
    expect(() =>
      prepareFlowStatusPhraseReply(
        { ...request, slot: 'morning' } as unknown as FlowStatusPhraseReplyRequest,
        null,
        { ...FLOW_CURATED_PHRASE_CATALOG, entries: [morning] },
      ),
    ).toThrow()
  })

  it('rejects a runtime continuity slot while retaining continuity as an any source', async () => {
    const { prepareFlowStatusPhraseReply } = await subject()
    expect(() =>
      prepareFlowStatusPhraseReply(
        { ...request, slot: 'continuity' } as unknown as FlowStatusPhraseReplyRequest,
        null,
      ),
    ).toThrow()
  })

  it.each([
    false,
    0,
    '',
    undefined,
  ])('rejects the corrupt runtime cursor %s instead of restarting its rotation', async (cursor) => {
    const { prepareFlowStatusPhraseReply } = await subject()
    expect(() =>
      prepareFlowStatusPhraseReply(request, cursor as unknown as FlowStatusPhraseCursor),
    ).toThrow()
  })

  for (const mismatch of ['owner', 'catalog'] as const) {
    it.each([
      'constructor',
      '__proto__',
      'toString',
    ])(`rejects an inherited event receipt after a ${mismatch} mismatch for %s`, async (eventKey) => {
      const { prepareFlowStatusPhraseReply } = await subject()
      const { replayByEventKey: _receipts, ...cursor } = createFlowPhraseRotationState(
        mismatch === 'owner' ? 'other-owner' : owner,
        mismatch === 'catalog' ? 'unapproved' : FLOW_CURATED_PHRASE_CATALOG.version,
      )
      expect(() => prepareFlowStatusPhraseReply({ ...request, eventKey }, cursor)).toThrow()
    })
  }

  for (const currentProtocol of ['recomposicao', 'ganho_massa', 'manutencao', null] as const) {
    it(`keeps the rendered hash of every eligible any/continuity phrase under ${currentProtocol ?? 'unknown'} authority`, async () => {
      const { prepareFlowStatusPhraseReply } = await subject()
      const pool = FLOW_CURATED_PHRASE_CATALOG.entries.filter(
        (entry) =>
          entry.kind === 'incentive' &&
          (entry.sourceSlot === 'any' || entry.sourceSlot === 'continuity'),
      )
      expect(pool).toHaveLength(187)
      const rendered = new Set<string>()
      for (const entry of pool) {
        const result = prepareFlowStatusPhraseReply(
          {
            ...request,
            eventKey: `mobile_flow/${owner}/pool-${entry.id}`,
            authority: { ...request.authority, currentProtocol },
          },
          null,
          { ...FLOW_CURATED_PHRASE_CATALOG, entries: [entry] },
        )
        const phrase = result.receipt.selection.phrase
        // All187 source entries were independently characterized through the
        // unchanged pure selector before this facade: no filtered/empty entries.
        expect(phrase, entry.id).not.toBeNull()
        if (phrase === null) throw new Error(`Missing eligible source: ${entry.id}`)
        expect(result.content.endsWith(`\n\n${phrase}`), entry.id).toBe(true)
        expect(createHash('sha256').update(phrase).digest('hex'), entry.id).toBe(
          result.nextCursor.lastTextKey,
        )
        expect(result.content, entry.id).not.toMatch(
          /\b(?:MPP|DAM)\b|orçamento de 14 dias|days above target/i,
        )
        rendered.add(phrase)
      }
      expect(rendered.size).toBe(187)
    })
  }
})
