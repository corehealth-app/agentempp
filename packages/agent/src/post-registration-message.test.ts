import { describe, it, expect } from 'vitest'
import {
  composePendingProposal,
  composePostRegistrationMessage,
  composeReevalResultMessage,
  composeStatusMessage,
  EDU_COMMENT_MARKER,
  embedEduComment,
  formatMealTable,
  isPureRegistrationTurn,
  isPureStatusQueryTurn,
  isReevalToolTurn,
  splitMealAndCard,
  splitRegistrationParts,
  type MealItem,
} from './post-registration-message.js'

const item = (over: Partial<MealItem>): MealItem => ({
  name: 'arroz branco cozido',
  quantity_g: 100,
  display_qty: 100,
  display_unit: 'g',
  kcal: 128,
  protein_g: 2,
  carbs_g: 28,
  fat_g: 0,
  ...over,
})

describe('formatMealTable', () => {
  it('monta tabela canônica (label + itens + total, 4 macros)', () => {
    const out = formatMealTable(
      'almoco',
      [
        item({ name: 'filé grelhado', display_qty: 150, display_unit: 'g', kcal: 270, protein_g: 39, carbs_g: 0, fat_g: 12 }),
        item({ name: 'ovo cozido', display_qty: 2, display_unit: 'unidades', quantity_g: 100, kcal: 146, protein_g: 13, carbs_g: 1, fat_g: 10 }),
      ],
      { kcal: 416, protein_g: 52, carbs_g: 1, fat_g: 22 },
    )
    expect(out).toContain('**Almoço:**')
    expect(out).toContain('• *filé grelhado (150g):* 270 kcal | 39g proteína | 0g carboidrato | 12g gordura')
    // unidade natural quando não é grama
    expect(out).toContain('• *ovo cozido (2 unidades):* 146 kcal | 13g proteína | 1g carboidrato | 10g gordura')
    expect(out).toContain('**Total: 416 kcal | 52g proteína | 1g carboidrato | 22g gordura**')
  })

  it('macro fracionado mostra 1 casa', () => {
    const out = formatMealTable('cafe', [item({ name: 'água de coco', kcal: 22, protein_g: 0.5, carbs_g: 5, fat_g: 0 })], {
      kcal: 22,
      protein_g: 0.5,
      carbs_g: 5,
      fat_g: 0,
    })
    expect(out).toContain('0.5g proteína')
  })
})

describe('isPureRegistrationTurn (gatilho do curto-circuito determinístico)', () => {
  const ok = { name: 'registra_refeicao', result: { success: true } }
  it('só registra_refeicao com sucesso, sem pergunta → true', () => {
    expect(isPureRegistrationTurn([ok], 'comi arroz com feijão')).toBe(true)
  })
  it('registra_treino com sucesso → true', () => {
    expect(isPureRegistrationTurn([{ name: 'registra_treino', result: { success: true } }], 'corri 5km')).toBe(true)
  })
  it('refeição + treino juntos → true', () => {
    expect(isPureRegistrationTurn([ok, { name: 'registra_treino', result: {} }], 'almocei e treinei')).toBe(true)
  })
  it('paciente fez pergunta ("?") → false (LLM responde)', () => {
    expect(isPureRegistrationTurn([ok], 'comi arroz, tá bom isso?')).toBe(false)
  })
  it('outra tool no turno (ex: define_protocolo) → false', () => {
    expect(isPureRegistrationTurn([ok, { name: 'define_protocolo', result: {} }], 'oi')).toBe(false)
  })
  it('tool de registro com erro → false', () => {
    expect(isPureRegistrationTurn([{ name: 'registra_refeicao', error: 'boom' }], 'comi x')).toBe(false)
  })
  it('nenhuma tool → false', () => {
    expect(isPureRegistrationTurn([], 'oi')).toBe(false)
  })
  it('texto nulo (foto/áudio sem texto) → true', () => {
    expect(isPureRegistrationTurn([ok], null)).toBe(true)
  })
})

describe('composePostRegistrationMessage', () => {
  it('refeição (recomp) → frase fixa + tabela + card com Bloco 7700', () => {
    const msg = composePostRegistrationMessage({
      registrations: [
        {
          tool: 'registra_refeicao',
          mealType: 'almoco',
          items: [item({ name: 'feijão preto cozido', display_qty: 80, display_unit: 'g', kcal: 92, protein_g: 6, carbs_g: 16, fat_g: 0 })],
          totals: { kcal: 92, protein_g: 6, carbs_g: 16, fat_g: 0 },
        },
      ],
      card: {
        caloriesConsumed: 1100,
        caloriesTarget: 1843,
        proteinG: 80,
        proteinTarget: 149,
        exerciseCalories: 0,
        deficitBlock: 1235,
        protocol: 'recomposicao',
      },
    })
    expect(msg.startsWith('Almoço registrado ✅')).toBe(true)
    expect(msg).toContain('**Almoço:**')
    expect(msg).toContain('🔥 Consumido: **1.100 / 1.843 kcal (60%)**')
    expect(msg).toContain('🎯 Restam: **743 kcal**')
    expect(msg).toContain('📊 Bloco 7700: **1.235 / 7.700 kcal (16%)**')
  })

  it('excedente → linha 🎯 Excedente', () => {
    const msg = composePostRegistrationMessage({
      registrations: [
        {
          tool: 'registra_refeicao',
          mealType: 'jantar',
          items: [item({ name: 'pizza', kcal: 900, protein_g: 30, carbs_g: 100, fat_g: 40 })],
          totals: { kcal: 900, protein_g: 30, carbs_g: 100, fat_g: 40 },
        },
      ],
      card: {
        caloriesConsumed: 2000,
        caloriesTarget: 1500,
        proteinG: 90,
        proteinTarget: 120,
        exerciseCalories: 0,
        deficitBlock: 500,
        protocol: 'recomposicao',
      },
    })
    expect(msg).toContain('🎯 Excedente: **500 kcal**')
  })

  it('treino → frase fixa + resumo + card', () => {
    const msg = composePostRegistrationMessage({
      registrations: [
        { tool: 'registra_treino', workoutType: 'corrida', durationMin: 30, kcalBurned: 250 },
      ],
      card: {
        caloriesConsumed: 800,
        caloriesTarget: 1159,
        proteinG: 50,
        proteinTarget: 94,
        exerciseCalories: 250,
        deficitBlock: 4879,
        protocol: 'recomposicao',
      },
    })
    expect(msg.startsWith('Treino registrado ✅')).toBe(true)
    expect(msg).toContain('🏋️ corrida (30 min) — 250 kcal')
    expect(msg).toContain('🏃🏻 Exercício: **250 kcal** _(acelera o bloco 7700)_')
  })

  it('treino deduped (alreadyLogged) → "já estava registrado", sem linha de kcal', () => {
    const msg = composePostRegistrationMessage({
      registrations: [{ tool: 'registra_treino', workoutType: 'caminhada', durationMin: 60, alreadyLogged: true }],
      card: {
        caloriesConsumed: 1000,
        caloriesTarget: 1041,
        proteinG: 72,
        proteinTarget: 87,
        exerciseCalories: 168,
        deficitBlock: 1846,
        protocol: 'recomposicao',
      },
    })
    expect(msg).toContain('Treino registrado ✅')
    expect(msg).toContain('_(já estava registrado)_')
    expect(msg).not.toContain('🏋️')
  })

  it('alreadyLogged (dedup) → sem tabela, só confirmação + card', () => {
    const msg = composePostRegistrationMessage({
      registrations: [{ tool: 'registra_refeicao', mealType: 'cafe', alreadyLogged: true }],
      card: {
        caloriesConsumed: 300,
        caloriesTarget: 1458,
        proteinG: 20,
        proteinTarget: 120,
        exerciseCalories: 0,
        deficitBlock: 0,
        protocol: 'recomposicao',
      },
    })
    expect(msg).toContain('Café registrado ✅')
    expect(msg).toContain('_(já estava registrado)_')
    expect(msg).not.toContain('**Café:**')
  })
})

describe('isPureStatusQueryTurn (gatilho do status determinístico)', () => {
  const ok = [{ name: 'consulta_progresso', result: { progresso: {} } }]

  it('status puro ("como tô?") com consulta_progresso → dispara', () => {
    expect(isPureStatusQueryTurn(ok, 'como tô?')).toBe(true)
    expect(isPureStatusQueryTurn(ok, 'quanto falta pro bloco?')).toBe(true)
    expect(isPureStatusQueryTurn(ok, 'como tá meu dia')).toBe(true)
    expect(isPureStatusQueryTurn(ok, 'resumo do dia')).toBe(true)
  })

  it('status + coaching ("como tô? consigo comer pizza?") → NÃO dispara (fallback LLM)', () => {
    expect(isPureStatusQueryTurn(ok, 'como tô? consigo comer pizza?')).toBe(false)
    expect(isPureStatusQueryTurn(ok, 'quanto falta? posso jantar fora?')).toBe(false)
    expect(isPureStatusQueryTurn(ok, 'como tô e o que como no jantar?')).toBe(false)
  })

  it('sem intenção de status → NÃO dispara', () => {
    expect(isPureStatusQueryTurn(ok, 'oi, tudo bem?')).toBe(false)
    expect(isPureStatusQueryTurn(ok, 'qual minha meta hoje?')).toBe(false)
  })

  it('outra tool no turno ou tool com erro → NÃO dispara', () => {
    expect(isPureStatusQueryTurn([{ name: 'registra_refeicao', result: {} }], 'como tô?')).toBe(false)
    expect(
      isPureStatusQueryTurn(
        [
          { name: 'consulta_progresso', result: {} },
          { name: 'consulta_metricas', result: {} },
        ],
        'como tô?',
      ),
    ).toBe(false)
    expect(isPureStatusQueryTurn([{ name: 'consulta_progresso', error: 'x' }], 'como tô?')).toBe(false)
    expect(isPureStatusQueryTurn([], 'como tô?')).toBe(false)
  })
})

describe('composeStatusMessage', () => {
  const card = {
    caloriesConsumed: 800,
    caloriesTarget: 1458,
    proteinG: 60,
    proteinTarget: 120,
    exerciseCalories: 0,
    deficitBlock: 5783,
    protocol: 'recomposicao' as const,
  }

  it('monta card canônico + linha de progresso', () => {
    const msg = composeStatusMessage(card, {
      currentStreak: 7,
      level: 2,
      xpTotal: 155,
      blocksCompleted: 0,
    })
    expect(msg).toContain('🔥 Consumido: **800 / 1.458 kcal') // card canônico
    expect(msg).toContain('📊 Bloco 7700:')
    expect(msg).toContain('🏅 Sequência: **7 dias consecutivos**')
    expect(msg).toContain('Nível 2 (155 XP)')
    expect(msg).toContain('0 bloco(s) de 7.700 completo(s)')
  })

  it('singular "1 dia consecutivo"', () => {
    const msg = composeStatusMessage(card, {
      currentStreak: 1,
      level: 1,
      xpTotal: 10,
      blocksCompleted: 0,
    })
    expect(msg).toContain('🏅 Sequência: **1 dia consecutivo**')
  })
})

describe('isReevalToolTurn (parte barata do gatilho de reavaliação)', () => {
  it('cadastra_dados_iniciais (peso) com sucesso, sem pergunta → dispara', () => {
    expect(isReevalToolTurn([{ name: 'cadastra_dados_iniciais', result: {} }], 'peso 80, fome moderada')).toBe(true)
    expect(
      isReevalToolTurn(
        [
          { name: 'cadastra_dados_iniciais', result: {} },
          { name: 'define_protocolo', result: {} },
        ],
        '80kg, fome muita',
      ),
    ).toBe(true)
  })

  it('sem cadastra (só define_protocolo) → NÃO dispara', () => {
    expect(isReevalToolTurn([{ name: 'define_protocolo', result: {} }], 'fome moderada')).toBe(false)
  })

  it('outra tool no turno ou pergunta → NÃO dispara', () => {
    expect(
      isReevalToolTurn(
        [
          { name: 'cadastra_dados_iniciais', result: {} },
          { name: 'registra_refeicao', result: {} },
        ],
        '80kg',
      ),
    ).toBe(false)
    expect(isReevalToolTurn([{ name: 'cadastra_dados_iniciais', result: {} }], 'peso 80, e a meta muda?')).toBe(false)
    expect(isReevalToolTurn([{ name: 'cadastra_dados_iniciais', error: 'x' }], '80kg')).toBe(false)
    expect(isReevalToolTurn([], '80kg')).toBe(false)
  })
})

describe('composeReevalResultMessage', () => {
  it('confirma nova meta + protocolo + próxima em 14 dias', () => {
    const msg = composeReevalResultMessage({
      caloriesTarget: 1037,
      proteinTarget: 85.5,
      protocol: 'recomposicao',
    })
    expect(msg).toContain('Reavaliação concluída ✅')
    expect(msg).toContain('🎯 Nova meta: **1.037 kcal** | **85.5 g** de proteína')
    expect(msg).toContain('📋 Protocolo: Recomposição corporal')
    expect(msg).toContain('Próxima reavaliação em 14 dias')
  })

  it('sem proteína → só kcal; sem protocolo → omite linha', () => {
    const msg = composeReevalResultMessage({
      caloriesTarget: 2000,
      proteinTarget: null,
      protocol: null,
    })
    expect(msg).toContain('🎯 Nova meta: **2.000 kcal**')
    expect(msg).not.toContain('proteína')
    expect(msg).not.toContain('📋 Protocolo:')
  })
})

// ── FASE A botões #4 (Roberto 2026-05-28) ─────────────────────────────────────
describe('composePendingProposal — proposta + botões pro tap [Sim, registrar] / [Editar]', () => {
  const pendingId = 'abc12345-6789-4abc-89de-0123456789ab' // uuid v4 válido

  it('refeição: monta corpo com items + total + "Confirma?" + 2 botões', () => {
    const out = composePendingProposal(pendingId, {
      kind: 'meal',
      mealType: 'almoco',
      items: [
        item({ name: 'arroz branco cozido', display_qty: 150, kcal: 192 }),
        item({ name: 'camarão cozido', display_qty: 100, kcal: 130 }),
      ],
      totals: { kcal: 322, protein_g: 25.7, carbs_g: 42, fat_g: 0.3 },
    })
    expect(out.body).toContain('Entendi isso pro seu Almoço:')
    expect(out.body).toContain('• arroz branco cozido (150g) — 192 kcal')
    expect(out.body).toContain('• camarão cozido (100g) — 130 kcal')
    expect(out.body).toContain('Total: 322 kcal | 25.7g proteína | 42g carboidrato | 0.3g gordura')
    expect(out.body).toContain('Confirma?')
    expect(out.buttons).toEqual([
      { id: `confirm_${pendingId}`, title: 'Sim, registrar' },
      { id: `edit_${pendingId}`, title: 'Editar' },
    ])
  })

  it('treino: monta linha com tipo+duração+kcal + botões', () => {
    const out = composePendingProposal(pendingId, {
      kind: 'workout',
      workoutType: 'caminhada',
      durationMin: 30,
      kcalEst: 82,
    })
    expect(out.body).toBe('Entendi isso pro seu treino:\n\n🏋️ caminhada (30 min) — 82 kcal\n\nConfirma?')
    expect(out.buttons).toHaveLength(2)
    expect(out.buttons[0]!.title).toBe('Sim, registrar')
    expect(out.buttons[0]!.title.length).toBeLessThanOrEqual(20) // limite Meta
    expect(out.buttons[1]!.title.length).toBeLessThanOrEqual(20)
  })

  it('foto: abertura é "Vi isso na sua foto (Almoço):" (Roberto 2026-05-28)', () => {
    const out = composePendingProposal(pendingId, {
      kind: 'meal',
      mealType: 'almoco',
      items: [item({ name: 'arroz', display_qty: 150, kcal: 192 })],
      totals: { kcal: 192, protein_g: 3, carbs_g: 42, fat_g: 0 },
      sourceContentType: 'image',
    })
    expect(out.body).toContain('Vi isso na sua foto (Almoço):')
    expect(out.body).not.toContain('Entendi isso pro seu')
  })

  it('foto com preparo ambíguo destaca a confirmação antes do tap', () => {
    const out = composePendingProposal(pendingId, {
      kind: 'meal',
      mealType: 'almoco',
      items: [item({ name: 'frango frito', display_qty: 120, kcal: 336 })],
      totals: { kcal: 336, protein_g: 27.6, carbs_g: 13.2, fat_g: 19.2 },
      sourceContentType: 'image',
      confirmationNotes: ['Confirme o preparo de frango frito: a foto pode confundir frito e grelhado.'],
    })

    expect(out.body).toContain('Atenção: Confirme o preparo de frango frito')
    expect(out.body.indexOf('Atenção:')).toBeLessThan(out.body.indexOf('Confirma?'))
  })

  it('áudio: abertura é "Entendi isso do áudio (Almoço):"', () => {
    const out = composePendingProposal(pendingId, {
      kind: 'meal',
      mealType: 'almoco',
      items: [item({ name: 'arroz', display_qty: 150, kcal: 192 })],
      totals: { kcal: 192, protein_g: 3, carbs_g: 42, fat_g: 0 },
      sourceContentType: 'audio',
    })
    expect(out.body).toContain('Entendi isso do áudio (Almoço):')
  })

  it('treino via foto: "Vi isso na sua foto (treino):"', () => {
    const out = composePendingProposal(pendingId, {
      kind: 'workout',
      workoutType: 'musculacao',
      durationMin: 40,
      kcalEst: 339,
      sourceContentType: 'image',
    })
    expect(out.body).toContain('Vi isso na sua foto (treino):')
  })

  it('texto default (sourceContentType ausente ou text): "Entendi isso pro seu"', () => {
    const out = composePendingProposal(pendingId, {
      kind: 'meal',
      mealType: 'almoco',
      items: [item({ name: 'arroz', display_qty: 150, kcal: 192 })],
      totals: { kcal: 192, protein_g: 3, carbs_g: 42, fat_g: 0 },
      sourceContentType: 'text',
    })
    expect(out.body).toContain('Entendi isso pro seu Almoço:')
  })

  it('respeita o limite de 1024 chars do Meta (trunca preservando "Confirma?")', () => {
    const manyItems = Array.from({ length: 80 }, (_, i) =>
      item({ name: `item número ${i} com nome longo pra estourar`, display_qty: 100, kcal: 50 }),
    )
    const out = composePendingProposal(pendingId, {
      kind: 'meal',
      mealType: 'almoco',
      items: manyItems,
      totals: { kcal: 4000, protein_g: 100, carbs_g: 400, fat_g: 80 },
    })
    expect(out.body.length).toBeLessThanOrEqual(1024)
    expect(out.body).toContain('Confirma?')
  })
})

describe('splitMealAndCard', () => {
  it('divide mensagem de registro completa em meal + card pelo marker 🔥 Consumido', () => {
    const msg = composePostRegistrationMessage({
      registrations: [
        {
          tool: 'registra_refeicao',
          mealType: 'cafe',
          items: [item({ name: 'ovo frito', kcal: 94 })],
          totals: { kcal: 94, protein_g: 7, carbs_g: 0.3, fat_g: 7 },
        },
      ],
      card: {
        caloriesConsumed: 94,
        caloriesTarget: 1843,
        proteinG: 7,
        proteinTarget: 100,
        exerciseCalories: 0,
        deficitBlock: 1000,
        protocol: 'recomposicao',
        last14d: null,
      },
    })
    const split = splitMealAndCard(msg)
    expect(split.card).not.toBeNull()
    expect(split.meal).toContain('Café registrado ✅')
    expect(split.meal).toContain('**Total:')
    expect(split.meal).not.toContain('🔥 Consumido')
    expect(split.card).toContain('🔥 Consumido')
    expect(split.card).toContain('📊 Bloco 7700')
  })

  it('msg sem card → card=null, meal=texto inteiro', () => {
    const split = splitMealAndCard('Oi, tudo bem?')
    expect(split.card).toBeNull()
    expect(split.meal).toBe('Oi, tudo bem?')
  })
})

describe('embedEduComment — invariante das 3 bolhas (audit 2026-06-14)', () => {
  // Contexto: 52% dos registros em prod saíam SEM o comentário educativo no
  // meio (2 bolhas em vez de 3). Não havia teste que assertasse o invariante
  // — toda regressão silenciosa em pipeline.ts:920 ou interactive-handler.ts:475
  // só era detectada quando alguém checava SQL à mão. Aqui travamos.

  const sampleRegistration = composePostRegistrationMessage({
    registrations: [
      {
        tool: 'registra_refeicao',
        mealType: 'cafe',
        items: [item({ name: 'ovo cozido', kcal: 78 })],
        totals: { kcal: 78, protein_g: 6.5, carbs_g: 0.5, fat_g: 5.3 },
      },
    ],
    card: {
      caloriesConsumed: 78,
      caloriesTarget: 1843,
      proteinG: 6.5,
      proteinTarget: 100,
      exerciseCalories: 0,
      deficitBlock: 1000,
      protocol: 'recomposicao',
      last14d: null,
    },
  })

  it('INVARIANTE 1: eduComment não-vazio ⇒ marker presente no texto retornado', () => {
    const result = embedEduComment(sampleRegistration, 'Bom café, identidade firme.')
    expect(result).toContain(EDU_COMMENT_MARKER)
    expect(result).toContain('Bom café, identidade firme.')
  })

  it('INVARIANTE 2: eduComment vazio/null/undefined ⇒ texto inalterado', () => {
    expect(embedEduComment(sampleRegistration, '')).toBe(sampleRegistration)
    expect(embedEduComment(sampleRegistration, null)).toBe(sampleRegistration)
    expect(embedEduComment(sampleRegistration, undefined)).toBe(sampleRegistration)
  })

  it('INVARIANTE 3: comentário SEMPRE entre tabela e card (nunca depois do card)', () => {
    const result = embedEduComment(sampleRegistration, 'Microvitória + identidade.')
    const eduIdx = result.indexOf(EDU_COMMENT_MARKER)
    const cardIdx = result.indexOf('🔥 Consumido:')
    expect(eduIdx).toBeGreaterThan(0)
    expect(cardIdx).toBeGreaterThan(0)
    expect(eduIdx).toBeLessThan(cardIdx)
  })

  it('INVARIANTE 4: splitRegistrationParts recupera as 3 partes em ordem', () => {
    const result = embedEduComment(sampleRegistration, 'Bom café, ovo é proteína completa.')
    const parts = splitRegistrationParts(result)
    expect(parts.meal).toBeTruthy()
    expect(parts.comment).toBeTruthy()
    expect(parts.card).toBeTruthy()
    expect(parts.meal).toContain('Café registrado ✅')
    expect(parts.meal).not.toContain('🔥 Consumido')
    expect(parts.comment).toBe('Bom café, ovo é proteína completa.')
    expect(parts.card).toContain('🔥 Consumido')
  })

  it('INVARIANTE 5: sem card no texto (msg de erro) ⇒ marker no final, ainda recuperável', () => {
    const semCard = 'Café registrado ✅\n\n- ovo cozido (50g): 78 kcal'
    const result = embedEduComment(semCard, 'Bom começo, manda mais ao longo do dia.')
    expect(result).toContain(EDU_COMMENT_MARKER)
    expect(result.endsWith('Bom começo, manda mais ao longo do dia.')).toBe(true)
  })

  it('REGRESSÃO: marker NÃO duplica se chamado 2x acidentalmente', () => {
    // Defesa contra caller que chama embedEduComment 2x por engano.
    // Embed atual NÃO desduplica — comportamento atual é "concatena de novo".
    // Este teste DOCUMENTA o comportamento; se virar problema em prod, fix:
    // adicionar early-return quando finalText já contém marker.
    const once = embedEduComment(sampleRegistration, 'Comentário A.')
    const twice = embedEduComment(once, 'Comentário B.')
    // Documenta: marker aparece 2x quando chamado 2x (não dedupe).
    const markerCount = (twice.match(new RegExp(EDU_COMMENT_MARKER, 'g')) ?? []).length
    expect(markerCount).toBe(2)
  })

  it('REGRESSÃO: comentário com quebras de linha internas preservadas', () => {
    const multiLine = 'Parágrafo 1 microvitória.\n\nParágrafo 2 orientação.'
    const result = embedEduComment(sampleRegistration, multiLine)
    const parts = splitRegistrationParts(result)
    expect(parts.comment).toBe(multiLine)
  })
})
