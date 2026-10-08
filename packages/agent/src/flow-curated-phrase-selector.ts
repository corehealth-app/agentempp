/** Pure C5 foundation. Callers own authenticated state, persistence and concurrency. */
import { createHash } from 'node:crypto'
import {
  isTemporallyCompatible,
  type PhraseSelectorInput,
  pickAnchorFood,
} from './curated-phrase-selector.js'
import { hasMoralizingEducationalTone } from './educational-comment.js'
import {
  FLOW_CURATED_PHRASE_CATALOG,
  type FlowPhraseCatalog,
  type FlowPhraseMealKind,
} from './flow-curated-phrase-catalog.js'
import { projectFlowPublicNames } from './flow-public-names.js'

type CommonRequest = {
  userId: string
  eventKey: string
  locale: string | null | undefined
  accountName?: string | null
}
export type FlowPhraseRequest = CommonRequest &
  (
    | {
        kind: 'food'
        items: readonly PhraseSelectorInput['items'][number][]
        mealKind: FlowPhraseMealKind
      }
    | { kind: 'incentive'; slot: 'any' | 'continuity' | 'morning' }
    | { kind: 'workout' }
  )

export interface FlowPhraseSelection {
  readonly phrase: string | null
  readonly phraseId: string | null
  readonly sourceText: string | null
  readonly foodCanonicalName: string | null
  readonly reason: string
}

export interface FlowPhraseRotationState {
  readonly schema: 'flow.phrase-state.v1'
  readonly userId: string
  readonly catalogVersion: string
  readonly ordinal: number
  readonly lastTextKey: string | null
  readonly usedTextKeys: readonly string[]
  readonly replayByEventKey: Readonly<
    Record<
      string,
      {
        readonly requestFingerprint: string
        readonly selection: FlowPhraseSelection
      }
    >
  >
}

const mealKinds = ['cafe', 'almoco', 'lanche', 'jantar', 'ceia'] as const
const hash = (text: string) => createHash('sha256').update(text).digest('hex')
const normalize = (text: string) =>
  text
    .toLowerCase()
    .normalize('NFD')
    .replace(/\p{Diacritic}/gu, '')
    .replace(/\s+/gu, ' ')
    .trim()
const nonempty = (value: unknown): value is string =>
  typeof value === 'string' && value.trim().length > 0
const record = (value: unknown): value is Record<string, unknown> => {
  if (typeof value !== 'object' || value === null) return false
  const prototype = Object.getPrototypeOf(value)
  return prototype === Object.prototype || prototype === null
}
const nullableString = (value: unknown) => value === null || typeof value === 'string'
const textKey = (value: unknown): value is string =>
  typeof value === 'string' && /^[a-f0-9]{64}$/u.test(value)

function validRequest(input: FlowPhraseRequest): boolean {
  if (!record(input) || !nonempty(input.userId) || !nonempty(input.eventKey)) return false
  if (input.locale !== null && input.locale !== undefined && typeof input.locale !== 'string')
    return false
  if (
    input.accountName !== null &&
    input.accountName !== undefined &&
    typeof input.accountName !== 'string'
  )
    return false
  if (input.kind === 'workout') return true
  if (input.kind === 'incentive') return ['any', 'continuity', 'morning'].includes(input.slot)
  if (
    input.kind !== 'food' ||
    ![...mealKinds, 'outro'].includes(input.mealKind) ||
    !Array.isArray(input.items)
  )
    return false
  return input.items.every(
    (item) =>
      record(item) &&
      nonempty(item.food_name) &&
      [item.kcal, item.protein_g, item.carbs_g, item.fat_g].every(
        (value) => typeof value === 'number' && Number.isFinite(value) && value >= 0,
      ),
  )
}

function validSelection(value: unknown): value is FlowPhraseSelection {
  if (!record(value)) return false
  return (
    nullableString(value.phrase) &&
    nullableString(value.phraseId) &&
    nullableString(value.sourceText) &&
    nullableString(value.foodCanonicalName) &&
    nonempty(value.reason) &&
    (value.phrase === null
      ? value.phraseId === null && value.sourceText === null
      : nonempty(value.phraseId) && nonempty(value.sourceText))
  )
}

function validState(state: FlowPhraseRotationState): boolean {
  return (
    record(state) &&
    state.schema === 'flow.phrase-state.v1' &&
    nonempty(state.userId) &&
    nonempty(state.catalogVersion) &&
    Number.isSafeInteger(state.ordinal) &&
    state.ordinal >= 0 &&
    (state.lastTextKey === null || textKey(state.lastTextKey)) &&
    Array.isArray(state.usedTextKeys) &&
    state.usedTextKeys.every(textKey) &&
    new Set(state.usedTextKeys).size === state.usedTextKeys.length &&
    record(state.replayByEventKey) &&
    Object.entries(state.replayByEventKey).every(
      ([key, receipt]) =>
        nonempty(key) &&
        record(receipt) &&
        textKey(receipt.requestFingerprint) &&
        validSelection(receipt.selection),
    )
  )
}

export function createFlowPhraseRotationState(
  userId: string,
  catalogVersion: string,
): FlowPhraseRotationState {
  if (!nonempty(userId) || !nonempty(catalogVersion))
    throw new Error('Flow phrase state requires owner and version')
  return {
    schema: 'flow.phrase-state.v1',
    userId,
    catalogVersion,
    ordinal: 0,
    lastTextKey: null,
    usedTextKeys: [],
    replayByEventKey: {},
  }
}

function fingerprint(input: FlowPhraseRequest): string {
  const common = [
    input.userId,
    input.eventKey,
    input.locale?.trim().toLowerCase() ?? null,
    input.accountName ?? null,
    input.kind,
  ]
  return hash(
    JSON.stringify([
      ...common,
      input.kind === 'food'
        ? [
            input.mealKind,
            input.items.map((item) => [
              item.food_name,
              item.kcal,
              item.protein_g,
              item.carbs_g,
              item.fat_g,
            ]),
          ]
        : input.kind === 'incentive'
          ? input.slot
          : null,
    ]),
  )
}

const empty = (reason: string, foodCanonicalName: string | null = null): FlowPhraseSelection => ({
  phrase: null,
  phraseId: null,
  sourceText: null,
  foodCanonicalName,
  reason,
})

/**
 * No IO, clock, random generator or global rotation cache. Old events replay
 * without rewinding the current cursor; callers must retain/provide receipts.
 */
export function selectFlowCuratedPhrase(
  input: FlowPhraseRequest,
  state: FlowPhraseRotationState,
  catalog: FlowPhraseCatalog = FLOW_CURATED_PHRASE_CATALOG,
): FlowPhraseSelection & { nextState: FlowPhraseRotationState } {
  const unchanged = (reason: string) => ({ ...empty(reason), nextState: state })
  if (!validRequest(input)) return unchanged('invalid_input')
  if (!validState(state)) return unchanged('invalid_state')
  if (state.userId !== input.userId) return unchanged('state_owner_mismatch')
  if (state.catalogVersion !== catalog.version) return unchanged('catalog_version_mismatch')
  const anchor = input.kind === 'food' ? pickAnchorFood([...input.items]) : null
  if (anchor && !Number.isFinite(anchor.weight)) return unchanged('invalid_input')
  const requestFingerprint = fingerprint(input)
  if (Object.hasOwn(state.replayByEventKey, input.eventKey)) {
    const receipt = state.replayByEventKey[input.eventKey]
    if (!receipt || receipt.requestFingerprint !== requestFingerprint)
      return unchanged('event_key_conflict')
    return { ...receipt.selection, nextState: state }
  }
  const finish = (selection: FlowPhraseSelection, nextState = state) => ({
    ...selection,
    nextState: {
      ...nextState,
      replayByEventKey: {
        ...state.replayByEventKey,
        [input.eventKey]: { requestFingerprint, selection },
      },
    },
  })
  if (state.ordinal === Number.MAX_SAFE_INTEGER) return finish(empty('rotation_exhausted'))
  const locale = input.locale?.trim().toLowerCase()
  if (locale !== 'pt-br' && locale !== 'pt') return finish(empty('unsupported_language'))

  if (input.kind === 'food' && !anchor) return finish(empty('no_anchor'))
  const foodCanonicalName = anchor ? normalize(anchor.food_name) : null
  const pool = catalog.entries.filter((row) => {
    if (row.locale !== 'pt-BR') return false
    if (input.kind === 'food')
      return (
        row.kind === 'food' &&
        row.foodAliases.some((alias) => normalize(alias) === foodCanonicalName)
      )
    if (row.kind !== 'incentive') return false
    return (
      row.sourceSlot === 'any' ||
      row.sourceSlot === 'continuity' ||
      (row.sourceSlot === 'morning' && input.kind === 'incentive' && input.slot === 'morning') ||
      (row.sourceSlot === 'workout' && input.kind === 'workout')
    )
  })
  if (input.kind === 'food' && pool.length === 0)
    return finish(empty('no_food_match', foodCanonicalName))

  const candidates = new Map<string, { selection: FlowPhraseSelection; key: string }>()
  for (const row of [...pool].sort((a, b) => (a.id < b.id ? -1 : a.id > b.id ? 1 : 0))) {
    if (input.kind === 'food') {
      if (row.allowedMealKinds && !row.allowedMealKinds.includes(input.mealKind)) continue
      const slots = input.mealKind === 'outro' ? mealKinds : [input.mealKind]
      if (!slots.every((slot) => isTemporallyCompatible(row.sourceText, slot).ok)) continue
    }
    if (/\{(?!alimento\})[^{}]*\}/u.test(row.sourceText)) continue
    if (row.sourceText.includes('{alimento}') && !anchor) continue
    const phrase = projectFlowPublicNames(
      row.sourceText.replace(
        /\{alimento\}/gu,
        () => anchor?.food_name.trim().replace(/\s+/gu, ' ') ?? '',
      ),
      { accountName: input.accountName },
    ).text
    if (!phrase.trim() || /[{}]/u.test(phrase) || hasMoralizingEducationalTone(phrase)) continue
    const key = hash(phrase)
    if (!candidates.has(key))
      candidates.set(key, {
        key,
        selection: {
          phrase,
          phraseId: row.id,
          sourceText: row.sourceText,
          foodCanonicalName,
          reason:
            input.kind === 'food'
              ? 'selected_food'
              : input.kind === 'workout'
                ? 'workout_incentive_fallback'
                : 'selected_incentive',
        },
      })
  }
  if (candidates.size === 0) return finish(empty('no_eligible_phrase', foodCanonicalName))
  const notPrevious = [...candidates.values()].filter(
    (candidate) => candidate.key !== state.lastTextKey,
  )
  if (notPrevious.length === 0) return finish(empty('only_previous_phrase', foodCanonicalName))
  let usedTextKeys = [...state.usedTextKeys]
  let available = notPrevious.filter((candidate) => !usedTextKeys.includes(candidate.key))
  if (available.length === 0) {
    usedTextKeys = []
    available = notPrevious
  }
  const seed = createHash('sha256')
    .update(JSON.stringify([input.userId, state.ordinal]))
    .digest()
    .readUInt32BE(0)
  const chosen = available[seed % available.length]
  if (!chosen) return finish(empty('no_eligible_phrase', foodCanonicalName))
  return finish(chosen.selection, {
    ...state,
    ordinal: state.ordinal + 1,
    lastTextKey: chosen.key,
    usedTextKeys: [...usedTextKeys, chosen.key],
  })
}
