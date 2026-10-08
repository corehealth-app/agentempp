import { describe, expect, it } from 'vitest'
import {
  FLOW_CURATED_PHRASE_CATALOG,
  type FlowPhraseCatalog,
  type FlowPhraseEntry,
} from './flow-curated-phrase-catalog.js'
import type { FlowPhraseRequest, FlowPhraseRotationState } from './flow-curated-phrase-selector.js'

const entry = (id: string): FlowPhraseEntry => {
  const found = FLOW_CURATED_PHRASE_CATALOG.entries.find((row) => row.id === id)
  if (!found) throw new Error(`Missing real source fixture: ${id}`)
  return found
}
const catalogOf = (...entries: FlowPhraseEntry[]): FlowPhraseCatalog => ({
  version: 'qa-fixture.v1',
  entries,
  sources: [],
})
const mechanical = (
  id: string,
  sourceText: string,
  overrides: Partial<FlowPhraseEntry> = {},
): FlowPhraseEntry => ({
  id,
  sourceText,
  kind: 'incentive',
  locale: 'pt-BR',
  foodAliases: [],
  sourceSlot: 'any',
  source: { file: 'synthetic-policy-only', phraseIndex: 0 },
  ...overrides,
})
const mealItem = (food_name = 'iogurte natural', kcal = 100) => ({
  food_name,
  kcal,
  protein_g: 10,
  carbs_g: 10,
  fat_g: 2,
})
const incentive = (eventKey = 'event-1'): Extract<FlowPhraseRequest, { kind: 'incentive' }> => ({
  userId: 'qa-A',
  eventKey,
  locale: 'pt-BR',
  kind: 'incentive',
  slot: 'any',
})
const food = (
  name = 'iogurte natural',
  mealKind: 'cafe' | 'almoco' | 'lanche' | 'jantar' | 'ceia' | 'outro' = 'cafe',
): Extract<FlowPhraseRequest, { kind: 'food' }> => ({
  userId: 'qa-A',
  eventKey: 'meal-1',
  locale: 'pt-BR',
  kind: 'food',
  items: [mealItem(name)],
  mealKind,
})
const stateFor = (catalog: FlowPhraseCatalog): FlowPhraseRotationState => ({
  schema: 'flow.phrase-state.v1',
  userId: 'qa-A',
  catalogVersion: catalog.version,
  ordinal: 0,
  lastTextKey: null,
  usedTextKeys: [],
  replayByEventKey: {},
})
async function select(
  input: FlowPhraseRequest,
  catalog: FlowPhraseCatalog = FLOW_CURATED_PHRASE_CATALOG,
  state = stateFor(catalog),
) {
  const { selectFlowCuratedPhrase } = await import('./flow-curated-phrase-selector.js')
  return selectFlowCuratedPhrase(input, state, catalog)
}

describe('C5: seleção literal, contexto e rodízio explícito', () => {
  it('fonte exata iogurte de manhã não é escolhida no jantar', async () => {
    const catalog = catalogOf(entry('food:b:bom_iogurtes_proteicos:005'))
    const morning = await select(food(), catalog)
    expect(morning.phrase).toBe(
      'iogurte natural é uma escolha inteligente para lanches ou café da manhã. A presença de proteínas favorece uma digestão mais lenta e prolonga a sensação de satisfação.',
    )
    expect(morning.sourceText).toBe(
      '{alimento} é uma escolha inteligente para lanches ou café da manhã. A presença de proteínas favorece uma digestão mais lenta e prolonga a sensação de satisfação.',
    )
    expect(morning.reason).toBe('selected_food')
    const dinner = await select(food('iogurte natural', 'jantar'), catalog)
    expect(dinner.phrase).toBeNull()
    expect(dinner.reason).toBe('no_eligible_phrase')
  })

  it('fonte exata peixe para jantar não aparece no café', async () => {
    const catalog = catalogOf(entry('food:f:bom_peixes:014'))
    expect((await select(food('salmão', 'jantar'), catalog)).phrase).toBe(
      'salmão é uma proteína de digestão geralmente mais leve, o que pode ser uma boa opção para o jantar.',
    )
    expect((await select(food('salmão', 'cafe'), catalog)).phrase).toBeNull()
  })

  it('incentivo de manhã fica fora do contexto genérico', async () => {
    const catalog = catalogOf(entry('engagement:011'))
    expect((await select({ ...incentive(), slot: 'morning' }, catalog)).phrase).toBe(
      'Hoje é mais uma chance de investir na sua saúde.',
    )
    expect((await select(incentive(), catalog)).phrase).toBeNull()
  })

  it('fonte versátil de verduras continua elegível nos cinco horários e outro', async () => {
    const catalog = catalogOf(entry('food:g:bom_verduras:001'))
    for (const slot of ['cafe', 'almoco', 'lanche', 'jantar', 'ceia', 'outro'] as const) {
      expect((await select(food('alface', slot), catalog)).phrase).toBeTruthy()
    }
    expect(entry('food:c2:bom_verduras:007').allowedMealKinds).toBeUndefined()
  })

  it('política futura por ID só libera lanche, sem inventar a frase ausente', async () => {
    const catalog = catalogOf(
      mechanical('synthetic-slot-policy', 'FIXTURE_SLOT_ONLY', {
        kind: 'food',
        foodAliases: ['qa-alimento'],
        allowedMealKinds: ['lanche'],
      }),
    )
    expect((await select(food('qa-alimento', 'lanche'), catalog)).phrase).toBe('FIXTURE_SLOT_ONLY')
    for (const slot of ['cafe', 'almoco', 'jantar', 'ceia', 'outro'] as const) {
      expect((await select(food('qa-alimento', slot), catalog)).phrase).toBeNull()
    }
  })

  it('usa âncora real e normalização exata, sem mudar a fórmula existente', async () => {
    const request: FlowPhraseRequest = {
      ...food(),
      kind: 'food',
      mealKind: 'almoco',
      items: [
        { food_name: 'arroz', kcal: 130, protein_g: 3, carbs_g: 28, fat_g: 0 },
        { food_name: '  PEITO   DE FRANGO  ', kcal: 200, protein_g: 30, carbs_g: 0, fat_g: 8 },
      ],
    }
    const result = await select(request)
    expect(result.foodCanonicalName).toBe('peito de frango')
    expect(result.phraseId).toMatch(/^food:[a-z0-9]+:bom_proteina_magra:/u)
    expect((await select(food(' SALMÃO ', 'jantar'))).foodCanonicalName).toBe('salmao')
  })

  it('não troca alimento principal desconhecido por ingrediente secundário conhecido', async () => {
    const request: FlowPhraseRequest = {
      ...food(),
      kind: 'food',
      mealKind: 'almoco',
      items: [mealItem('alimento-desconhecido-qa', 2000), mealItem('peito de frango', 100)],
    }
    const result = await select(request)
    expect(result.phrase).toBeNull()
    expect(result.reason).toBe('no_food_match')
  })

  it('empate mantém o primeiro alimento; vazio ou calorias zero não tem âncora', async () => {
    const request: FlowPhraseRequest = {
      ...food(),
      kind: 'food',
      mealKind: 'almoco',
      items: [mealItem('salmão'), mealItem('peito de frango')],
    }
    expect((await select(request)).foodCanonicalName).toBe('salmao')
    for (const items of [[], [mealItem('água', 0)]]) {
      const result = await select({ ...food(), kind: 'food', mealKind: 'cafe', items })
      expect(result.phrase).toBeNull()
      expect(result.reason).toBe('no_anchor')
    }
  })

  it.each([
    'leite desnatado',
    'ovinho',
    'peito de frango ao molho desconhecido',
  ])('não faz match semântico ou pluralização para %s', async (name) => {
    const result = await select(food(name, 'almoco'))
    expect(result.phrase).toBeNull()
    expect(result.reason).toBe('no_food_match')
  })

  it('preserva diferenças de preparo e leite da fonte', async () => {
    expect((await select(food('frango frito', 'almoco'))).phraseId).toMatch(
      /:ruim_fritos_imersao:/u,
    )
    expect((await select(food('peito de frango', 'almoco'))).phraseId).toMatch(
      /:bom_proteina_magra:/u,
    )
    expect((await select(food('leite condensado', 'lanche'))).phraseId).toMatch(/:ruim_/u)
  })

  it.each([
    { ...mealItem(), food_name: '' },
    { ...mealItem(), food_name: 42 },
    { ...mealItem(), kcal: Number.NaN },
    { ...mealItem(), kcal: Number.POSITIVE_INFINITY },
    { ...mealItem(), protein_g: -1 },
    { ...mealItem(), fat_g: Number.NaN },
  ])('rejeita shape e macros inválidos sem alterar entrada: %j', async (item) => {
    const request = { ...food(), items: [item] } as unknown as FlowPhraseRequest
    const before = structuredClone(request)
    const result = await select(request)
    expect(result.phrase).toBeNull()
    expect(result.reason).toBe('invalid_input')
    expect(request).toEqual(before)
  })

  it('deduplica o texto final entre fases, sem tratar ID diferente como alternativa', async () => {
    const catalog = catalogOf(entry('food:b:ruim_sorvetes:011'), entry('food:c2:ruim_sorvetes:010'))
    const first = await select(food('sorvete', 'lanche'), catalog)
    expect(first.phrase).toBeTruthy()
    const next = await select(
      { ...food('sorvete', 'lanche'), eventKey: 'meal-2' },
      catalog,
      first.nextState,
    )
    expect(next.phrase).toBeNull()
    expect(next.reason).toBe('only_previous_phrase')
    expect(next.nextState.ordinal).toBe(1)
  })

  it('roda o ciclo sem repetir a anterior nem mutar o estado fornecido', async () => {
    const catalog = catalogOf(
      mechanical('a', 'FIXTURE_A'),
      mechanical('b', 'FIXTURE_B'),
      mechanical('c', 'FIXTURE_C'),
    )
    let state = stateFor(catalog)
    const texts: Array<string | null> = []
    for (let index = 1; index <= 4; index += 1) {
      const before = structuredClone(state)
      const result = await select(incentive(`event-${index}`), catalog, state)
      expect(state).toEqual(before)
      expect(result.nextState.ordinal).toBe(index)
      texts.push(result.phrase)
      state = result.nextState
    }
    expect(new Set(texts.slice(0, 3))).toEqual(new Set(['FIXTURE_A', 'FIXTURE_B', 'FIXTURE_C']))
    expect(texts[3]).not.toBe(texts[2])
  })

  it('mesma entrada e estado têm resultado determinístico', async () => {
    const catalog = catalogOf(mechanical('a', 'FIXTURE_A'), mechanical('b', 'FIXTURE_B'))
    const request = Object.freeze(incentive())
    const state = Object.freeze(stateFor(catalog))
    expect(await select(request, catalog, state)).toEqual(await select(request, catalog, state))
    expect(state.ordinal).toBe(0)
    expect(state.replayByEventKey).toEqual({})
  })

  it('replay atual e antigo preserva seleção original e estado corrente', async () => {
    const catalog = catalogOf(mechanical('a', 'FIXTURE_A'), mechanical('b', 'FIXTURE_B'))
    const first = await select(incentive(), catalog)
    const replay = await select(incentive(), catalog, first.nextState)
    expect(replay.phrase).toBe(first.phrase)
    expect(replay.nextState).toEqual(first.nextState)
    const second = await select(incentive('event-2'), catalog, first.nextState)
    const oldReplay = await select(incentive(), catalog, second.nextState)
    expect(oldReplay.phrase).toBe(first.phrase)
    expect(oldReplay.nextState).toEqual(second.nextState)
    expect(oldReplay.nextState.ordinal).toBe(2)
  })

  it('mesmo evento com payload diferente é conflito, inclusive resultado vazio', async () => {
    const catalog = catalogOf(entry('engagement:011'))
    const empty = await select(incentive(), catalog)
    expect(empty.phrase).toBeNull()
    const conflict = await select({ ...incentive(), slot: 'morning' }, catalog, empty.nextState)
    expect(conflict.reason).toBe('event_key_conflict')
    expect(conflict.nextState).toEqual(empty.nextState)
  })

  it('chaves de evento não usam propriedades herdadas do objeto', async () => {
    const catalog = catalogOf(mechanical('a', 'FIXTURE_A'))
    const first = await select(incentive('__proto__'), catalog)
    const replay = await select(incentive('__proto__'), catalog, first.nextState)
    expect(first.phrase).toBe('FIXTURE_A')
    expect(replay.phrase).toBe(first.phrase)
    expect(replay.nextState.ordinal).toBe(1)
  })

  it('sucessor no teto seguro preserva replay e não incrementa para inteiro inseguro', async () => {
    const catalog = catalogOf(mechanical('a', 'FIXTURE_A'), mechanical('b', 'FIXTURE_B'))
    const state = { ...stateFor(catalog), ordinal: Number.MAX_SAFE_INTEGER - 1 }
    const first = await select(incentive(), catalog, state)
    expect(first.phrase).toBeTruthy()
    expect(first.nextState.ordinal).toBe(Number.MAX_SAFE_INTEGER)
    const replay = await select(incentive(), catalog, first.nextState)
    expect(replay.phrase).toBe(first.phrase)
    expect(replay.phraseId).toBe(first.phraseId)
    expect(replay.nextState).toBe(first.nextState)
    const exhausted = await select(incentive('event-2'), catalog, first.nextState)
    expect(exhausted.phrase).toBeNull()
    expect(exhausted.reason).toBe('rotation_exhausted')
    expect(exhausted.nextState.ordinal).toBe(Number.MAX_SAFE_INTEGER)
    expect(exhausted.nextState.lastTextKey).toBe(first.nextState.lastTextKey)
    const exhaustedReplay = await select(incentive('event-2'), catalog, exhausted.nextState)
    expect(exhaustedReplay.reason).toBe('rotation_exhausted')
    expect(exhaustedReplay.nextState).toBe(exhausted.nextState)
  })

  it('estado de outra pessoa ou versão nunca é resetado nem usado', async () => {
    const catalog = catalogOf(mechanical('a', 'FIXTURE_A'))
    const state = stateFor(catalog)
    const wrongOwner = await select({ ...incentive(), userId: 'qa-B' }, catalog, state)
    expect(wrongOwner.reason).toBe('state_owner_mismatch')
    expect(wrongOwner.nextState).toBe(state)
    const oldVersion = { ...state, catalogVersion: 'old' }
    expect((await select(incentive(), catalog, oldVersion)).reason).toBe('catalog_version_mismatch')
    for (const invalid of [
      { ...state, ordinal: Number.NaN },
      { ...state, ordinal: -1 },
      { ...state, replayByEventKey: null },
    ]) {
      expect(
        (await select(incentive(), catalog, invalid as unknown as FlowPhraseRotationState)).reason,
      ).toBe('invalid_state')
    }
  })

  it.each([
    'pt-BR',
    'pt',
    ' PT-br ',
  ])('usa somente cobertura curada conhecida: %s', async (locale) => {
    const catalog = catalogOf(mechanical('a', 'FIXTURE_A'))
    expect((await select({ ...incentive(), locale }, catalog)).phrase).toBe('FIXTURE_A')
  })
  it.each([
    null,
    undefined,
    '',
    'en-US',
    'es',
    'de',
  ])('não traduz nem presume idioma não coberto: %s', async (locale) => {
    const catalog = catalogOf(mechanical('a', 'FIXTURE_A'))
    const result = await select({ ...incentive(), locale }, catalog)
    expect(result.phrase).toBeNull()
    expect(result.reason).toBe('unsupported_language')
  })

  it('treino usa incentivo existente sem inventar biblioteca específica', async () => {
    const catalog = catalogOf(entry('engagement:086'))
    const result = await select(
      { userId: 'qa-A', eventKey: 'workout-1', locale: 'pt-BR', kind: 'workout' },
      catalog,
    )
    expect(result.phrase).toBe('Cada treino realizado fortalece mais do que seus músculos.')
    expect(result.reason).toBe('workout_incentive_fallback')
    expect((await select(incentive(), catalog)).phrase).toBeNull()
  })

  it('placeholder substituído literalmente e projeção pública deduplicada, fonte intacta', async () => {
    const catalog = catalogOf(
      mechanical('a', '{alimento} / {alimento}', { kind: 'food', foodAliases: ['$& $1'] }),
    )
    expect((await select(food('$& $1'), catalog)).phrase).toBe('$& $1 / $& $1')
    expect(catalog.entries[0]?.sourceText).toBe('{alimento} / {alimento}')
    const brands = catalogOf(mechanical('a', 'Usina muscular'), mechanical('b', 'Performe AI'))
    const first = await select(incentive(), brands)
    expect(first.phrase).toBe('Performe AI')
    expect((await select(incentive('event-2'), brands, first.nextState)).reason).toBe(
      'only_previous_phrase',
    )
  })

  it('não relaxa tom, horário ausente ou placeholder desconhecido para fabricar texto', async () => {
    for (const text of [
      'Esse é o padrão de quem realmente leva a saúde a sério.',
      '{nome} ausente',
    ]) {
      const result = await select(incentive(), catalogOf(mechanical('qa', text)))
      expect(result.phrase).toBeNull()
      expect(result.reason).toBe('no_eligible_phrase')
    }
    expect(
      (await select({ ...food(), mealKind: undefined } as unknown as FlowPhraseRequest)).reason,
    ).toBe('invalid_input')
  })

  it('fábrica de estado pertence à pessoa e versão, com cursor explícito', async () => {
    const { createFlowPhraseRotationState } = await import('./flow-curated-phrase-selector.js')
    expect(createFlowPhraseRotationState('qa-A', 'qa-fixture.v1')).toEqual(stateFor(catalogOf()))
  })

  it('rejeita peso derivado infinito mesmo quando cada macro de entrada é finito', async () => {
    const request = { ...food(), items: [{ ...mealItem(), protein_g: Number.MAX_VALUE }] }
    expect((await select(request)).reason).toBe('invalid_input')
  })

  it('rejeita Date como mapa de replay em vez de aceitar estado malformado', async () => {
    const catalog = catalogOf(mechanical('a', 'FIXTURE_A'))
    const state = {
      ...stateFor(catalog),
      replayByEventKey: new Date(0),
    } as unknown as FlowPhraseRotationState
    expect((await select(incentive(), catalog, state)).reason).toBe('invalid_state')
  })

  it('não entrega frase com placeholder alimentar quando não existe âncora', async () => {
    const catalog = catalogOf(mechanical('a', 'PREFIX {alimento} SUFFIX'))
    const result = await select(incentive(), catalog)
    expect(result.phrase).toBeNull()
    expect(result.reason).toBe('no_eligible_phrase')
  })
})
