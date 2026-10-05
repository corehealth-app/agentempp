import { describe, expect, it } from 'vitest'
import {
  accountNameCarriesPhysicianSurname,
  LEGACY_PERSONA_NAME_PATTERN,
  projectFlowPublicNames,
} from './flow-public-names.js'

const names = (text: string, accountName?: string | null) =>
  projectFlowPublicNames(text, accountName === undefined ? {} : { accountName })

const NONE = { method: 0, personaSelf: 0, personaOther: 0, personaFirstNameOnly: 0 }

// ── The table of the decision of 2026-10-05 (review NOT_YET → closed vocabulary)
// Every line is an exact sentence of the decision, with the output it locked.
// The same table runs through the real entry point in
// __golden__/audit-10-05-flow-never-names-the-method.test.ts.
describe('projectFlowPublicNames — the decision table of 2026-10-05', () => {
  it.each([
    // The title and/or the first name WITHOUT the surname: never replaced.
    'Bom treino, Dr. Roberto!',
    'Perfeito, Dr. Roberto. Registrei seu almoço.',
    'Dr. Roberto\nSeu almoço foi registrado.',
    'Fale com seu médico, o Dr. Roberto Silva.',
    'Dr. Roberto Carlos, seu cardiologista',
    // Another person who carries the surname.
    'Dra. Roberta Menescal',
    // Not his name at all.
    'Roberto Carlos canta bem.',
    'Boa, Roberto!',
    'Dr. Robertson',
    'Dr. Roberta cuida disso.',
    // Looks like the acronym, is not.
    'M P Pereira',
    // Outside the closed vocabulary (RC FN-4).
    'Menescau',
    'Dr. Róberto',
    'Método do Dr. Fulano',
    // A segment of a URL, of a path or of an identifier.
    'https://example.com/mpp/guia',
    'https://mpp.example.com/guia',
    'docs/CALCULO-MPP.md',
    'MPP-2',
    '@mpp/agent',
    'mppx',
    'agentempp',
    'mpp_mensal_v1',
  ])('unchanged: %j', (answer) => {
    const result = names(answer)
    expect(result.text).toBe(answer)
    expect(result).toMatchObject({ method: 0, personaSelf: 0, personaOther: 0 })
  })

  it.each([
    ['Sou o Dr. Roberto Menescal.', 'Sou o Flow.'],
    ['O método foi criado pelo Dr. Roberto Menescal.', 'O método foi criado pelo Performe AI.'],
    ['É o M.P.P., sim.', 'É o Performe AI, sim.'],
    ['É o M.P.P.', 'É o Performe AI.'],
    ['É o M. P. P.', 'É o Performe AI.'],
    ['É o M P P', 'É o Performe AI'],
    ['MPPs', 'Performe AI'],
    ['Muscular-Power-Plant', 'Performe AI'],
    ['MuscularPowerPlant', 'Performe AI'],
    // Each name becomes "Performe AI": two names, two replacements.
    ['MPP (Muscular Power Plant)', 'Performe AI (Performe AI)'],
  ])('%j → %j', (answer, expected) => {
    expect(names(answer).text).toBe(expected)
  })

  const GREETING = 'Bom dia, Roberto Menescal! Vamos registrar o almoço?'

  it.each([
    'Roberto Menescal',
    'Dr. Roberto Menescal',
    'ROBERTO MENESCAL',
    'roberto menéscal',
    'Ana Paula de Menescal Souza',
  ])('the greeting is unchanged for the account registered as %j', (accountName) => {
    expect(names(GREETING, accountName)).toEqual({ text: GREETING, ...NONE })
  })

  it.each([
    'QA A',
    'Roberto',
    'Menescau',
    '',
    null,
    undefined,
  ])('the greeting loses the name for the account registered as %j', (accountName) => {
    expect(names(GREETING, accountName)).toEqual({
      text: 'Bom dia, Performe AI! Vamos registrar o almoço?',
      ...NONE,
      personaOther: 1,
    })
  })
})

// ── (a) The method ──────────────────────────────────────────────────────────
describe('projectFlowPublicNames — the method', () => {
  it.each([
    ['Seguimos o método MPP.', 'Seguimos o método Performe AI.'],
    ['É o mpp, o Mpp e o MPP!', 'É o Performe AI, o Performe AI e o Performe AI!'],
    ['Os MPPs e os mpps.', 'Os Performe AI e os Performe AI.'],
    ['Seguimos o Muscular Power Plant.', 'Seguimos o Performe AI.'],
    ['MUSCULAR POWER PLANT', 'Performe AI'],
    ['muscular power plant', 'Performe AI'],
    ['Muscular\u00A0Power\u00A0Plant', 'Performe AI'],
    ['Muscular - Power - Plant', 'Performe AI'],
    [
      'No protocolo mpp o bloco é de 7700 kcal.',
      'No protocolo Performe AI o bloco é de 7700 kcal.',
    ],
    // Each name is replaced where it stands; nothing around it is rewritten.
    ['É o Método MPP (Muscular Power Plant).', 'É o Método Performe AI (Performe AI).'],
    ['É o Muscular Power Plant (MPP).', 'É o Performe AI (Performe AI).'],
    ['MPP — Muscular Power Plant, em resumo.', 'Performe AI — Performe AI, em resumo.'],
    [
      'We follow the MPP Method (Muscular  Power\nPlant).',
      'We follow the Performe AI Method (Performe AI).',
    ],
    ['O método MPP do Performe AI.', 'O método Performe AI do Performe AI.'],
    // Sentence punctuation around the name.
    ['É o MPP.', 'É o Performe AI.'],
    ['É o MPP. Sim.', 'É o Performe AI. Sim.'],
    ['É o MPP...', 'É o Performe AI...'],
    ['(MPP)', '(Performe AI)'],
    ['"MPP"', '"Performe AI"'],
    ['**MPP**', '**Performe AI**'],
    // The last dot of the dotted form: part of the name when the sentence goes on.
    ['O M.P.P. é o método.', 'O Performe AI é o método.'],
    ['É o M.P.P. Sim, é isso.', 'É o Performe AI. Sim, é isso.'],
    ['É o M.P.P!', 'É o Performe AI!'],
    ['É o "M.P.P.".', 'É o "Performe AI".'],
    ['É o M.\u00A0P.\u00A0P.', 'É o Performe AI.'],
    ['É o M\u00A0P\u00A0P.', 'É o Performe AI.'],
  ])('%j → %j', (answer, expected) => {
    expect(names(answer).text).toBe(expected)
  })

  it('counts every name, the acronym and its expansion apart', () => {
    expect(names('MPP (Muscular Power Plant). O MPP. Muscular Power Plant. M.P.P.')).toEqual({
      text: 'Performe AI (Performe AI). O Performe AI. Performe AI. Performe AI.',
      ...NONE,
      method: 5,
    })
  })

  it.each([
    // A word that only contains the letters.
    'Use o app para ver seu IMPPULSO e o campo BMPP1.',
    'MuscularPowerPlants',
    // Glued to / . @ - _ : a segment, not the name.
    'Veja https://example.com/mpp/guia e https://mpp.example.com/guia.',
    'O arquivo é docs/CALCULO-MPP.md, do pacote @mpp/agent.',
    'Plano MPP-2, chave mpp_mensal_v1, conta mpp@example.com.',
    'www.mpp.com.br',
    'MPP.md',
    '__MPP__',
    'pré-MPP',
    // RC FN-4: the two names joined by a slash are glued too.
    'MPP/Muscular Power Plant',
    // The dotted and the spaced forms are the capital ones only.
    'm.p.p. e m p p',
    'M P Pereira',
    'M.P.P.x',
    'Tamanhos M P PP',
    // Never across a line break.
    'Opção M\nP\nP',
  ])('unchanged: %j', (answer) => {
    expect(names(answer)).toEqual({ text: answer, ...NONE })
  })
})

// ── (b) The physician: only with the surname ────────────────────────────────
describe('projectFlowPublicNames — the physician', () => {
  it.each([
    ['Sou o Dr. Roberto Menescal.', 'Sou o Flow.'],
    ['Eu sou o Dr. Roberto Menescal, seu coach.', 'Eu sou o Flow, seu coach.'],
    ['Sou Roberto Menescal.', 'Sou Flow.'],
    ['Sou Menescal.', 'Sou Flow.'],
    ['Aqui é o Dr. Roberto Menescal!', 'Aqui é o Flow!'],
    ['Aqui é Doutor Roberto Menescal.', 'Aqui é Flow.'],
    ['Me chamo Doutor Roberto Menescal.', 'Me chamo Flow.'],
    ['Meu nome é Roberto Menescal.', 'Meu nome é Flow.'],
    ['I am Dr. Robert Menescal.', 'I am Flow.'],
    ["Hi, I'm Dr. Robert Menescal.", "Hi, I'm Flow."],
    ['Hi, I’m Doctor Robert Menescal.', 'Hi, I’m Flow.'],
    ['This is Dr. Robert Menescal.', 'This is Flow.'],
    ['Sou o **Dr. Roberto Menescal**.', 'Sou o **Flow**.'],
    ['SOU O DR. ROBERTO MENESCAL.', 'SOU O Flow.'],
  ])('introducing itself: %j → %j', (answer, expected) => {
    expect(names(answer)).toEqual({ text: expected, ...NONE, personaSelf: 1 })
  })

  it.each([
    ['O método do Dr. Roberto Menescal é simples.', 'O método do Performe AI é simples.'],
    ['Criado por Roberto Menescal.', 'Criado por Performe AI.'],
    ['Criado por Robert Menescal.', 'Criado por Performe AI.'],
    ['criado por roberto menescal', 'criado por Performe AI'],
    ['Fale com o Dr Menescal.', 'Fale com o Performe AI.'],
    ['Fale com a Dra. Menescal.', 'Fale com a Performe AI.'],
    ['O doutor Roberto Menescal recomenda água.', 'O Performe AI recomenda água.'],
    ['Dr.Robert Menescal wrote it.', 'Performe AI wrote it.'],
    ['Doctor Menescal wrote it.', 'Performe AI wrote it.'],
    ['O Menescal recomenda água.', 'O Performe AI recomenda água.'],
    ['Entendi. Menescal é quem criou.', 'Entendi. Performe AI é quem criou.'],
    ['Assinado\nMenescal', 'Assinado\nPerforme AI'],
    // A denied name is not an introduction.
    ['Não sou o Dr. Roberto Menescal; sou o Flow.', 'Não sou o Performe AI; sou o Flow.'],
    ['Nunca sou o Dr. Roberto Menescal.', 'Nunca sou o Performe AI.'],
    ['I am not Dr. Robert Menescal.', 'I am not Performe AI.'],
    // A lead outside the closed list is not an introduction.
    ['Soy el Dr. Roberto Menescal.', 'Soy el Performe AI.'],
    ['My name is Dr. Robert Menescal.', 'My name is Performe AI.'],
    // No reading of the wording around the name: a "signature" is a name like any other.
    ['Conte comigo.\n— Dr. Roberto Menescal', 'Conte comigo.\n— Performe AI'],
    ['Um abraço, Dr. Roberto Menescal.', 'Um abraço, Performe AI.'],
  ])('anywhere else: %j → %j', (answer, expected) => {
    expect(names(answer)).toEqual({ text: expected, ...NONE, personaOther: 1 })
  })

  it.each([
    'Bom treino, Dr. Roberto!',
    'Perfeito, Dr. Roberto. Registrei seu almoço.',
    'Dr. Roberto\nSeu almoço foi registrado.',
    'Fale com seu médico, o Dr. Roberto Silva.',
    'Dr. Roberto Carlos, seu cardiologista',
    'Eu sou o Dr. Roberto, seu coach.',
    'Me chamo Doutor Roberto.',
    'I am Dr. Robert.',
    'I am Doctor Robert.',
    'Quem criou foi o Dr Roberto.',
    'Conte comigo.\nDr. Roberto',
    'Um abraço, Dr. Roberto.',
    'O Dr. Roberto é o médico que criou o método.',
    'A Dra. Roberto atende amanhã.',
  ])('title + first name, no surname: %j is not replaced, and is counted', (answer) => {
    expect(names(answer)).toEqual({ text: answer, ...NONE, personaFirstNameOnly: 1 })
  })

  it('counts each "title + first name" without the surname, and none with it', () => {
    expect(
      names('O Dr. Roberto disse. O Doutor Roberto confirmou. O Dr. Roberto Menescal assinou.'),
    ).toEqual({
      text: 'O Dr. Roberto disse. O Doutor Roberto confirmou. O Performe AI assinou.',
      ...NONE,
      personaOther: 1,
      personaFirstNameOnly: 2,
    })
  })

  it.each([
    // The first name alone: a person's name.
    'Boa, Roberto! Vamos nessa.',
    'Roberto, sua meta de hoje é 2.980 kcal.',
    'Roberto Carlos canta bem.',
    'O método foi criado pelo médico Roberto, nutrólogo.',
    // A different name.
    'Fale com o Dr. Robertson ou com a Dra. Roberta.',
    'Dr. Roberta cuida disso.',
    'Converse com seu médico, o Dr. João.',
    'A dieta do Dr. Atkins não é o que seguimos aqui.',
    'Dr. Róberto',
    'Menescau',
    'Método do Dr. Fulano',
    // Another person who carries the surname.
    'Dra. Roberta Menescal',
    'Ana Menescal é minha esposa.',
    'A Ana Paula Menescal treina comigo.',
    'Roberto Carlos Menescal',
    'Sou a Ana Menescal.',
    'Aqui é Ana Menescal.',
    // RC FN-4: a capitalised word that is not a first name blocks it too.
    'Segundo Menescal, é assim.',
    // Glued: a handle, a domain, a double surname.
    'Siga @menescal e veja menescal.com.br',
    'Menescal-Silva',
    'drmenescal',
  ])('not his full name, stays: %j', (answer) => {
    expect(names(answer)).toEqual({ text: answer, ...NONE })
  })
})

// ── (c) The account guard ───────────────────────────────────────────────────
describe('projectFlowPublicNames — an account that carries the surname', () => {
  it.each([
    ['Roberto Menescal', true],
    ['ROBERTO MENESCAL', true],
    ['roberto menéscal', true],
    ['Ana Paula de Menescal Souza', true],
    ['Roberto', false],
    ['Menescau', false],
    ['QA A', false],
    ['', false],
    [null, false],
    [undefined, false],
  ])('registered as %j → %j', (accountName, expected) => {
    expect(accountNameCarriesPhysicianSurname(accountName)).toBe(expected)
  })

  it("skips the physician's name for the turn, in every form, and counts nothing of it", () => {
    const answer = 'Sou o Dr. Roberto Menescal. Bom dia, Roberto Menescal! Fale com o Dr. Roberto.'
    expect(names(answer, 'Dr. Roberto MENESCAL')).toEqual({ text: answer, ...NONE })
    expect(names(answer, 'QA A')).toEqual({
      text: 'Sou o Flow. Bom dia, Performe AI! Fale com o Dr. Roberto.',
      ...NONE,
      personaSelf: 1,
      personaOther: 1,
      personaFirstNameOnly: 1,
    })
  })

  it('still projects the method names', () => {
    expect(
      names('Roberto Menescal, pelo método MPP (Muscular Power Plant).', 'Roberto Menescal'),
    ).toEqual({
      text: 'Roberto Menescal, pelo método Performe AI (Performe AI).',
      ...NONE,
      method: 2,
    })
  })
})

describe('projectFlowPublicNames — everything else', () => {
  it('returns the same string when there is nothing to replace', () => {
    const answer = 'O Performe AI organiza suas metas — Performe AI, sempre. Eu sou o Flow.'
    expect(names(answer)).toEqual({ text: answer, ...NONE })
    expect(names('')).toEqual({ text: '', ...NONE })
  })

  it('gives the same result when called twice in a row (no state between calls)', () => {
    const answer = 'Sou o Dr. Roberto Menescal, do método MPP.'
    expect(names(answer)).toEqual(names(answer))
    expect(names(answer).text).toBe('Sou o Flow, do método Performe AI.')
  })

  it('"Método MPP do Dr. Roberto Menescal": every name is replaced, the wording stays', () => {
    expect(names('É o Método MPP do Dr. Roberto Menescal.')).toEqual({
      text: 'É o Método Performe AI do Performe AI.',
      ...NONE,
      method: 1,
      personaOther: 1,
    })
  })

  it('the pattern of the prompt context is the one HEAD had', () => {
    expect(LEGACY_PERSONA_NAME_PATTERN.source).toBe(
      String.raw`\bDr\.?\s+Robert(?:o)?(?:\s+Menescal)?\b`,
    )
    expect(LEGACY_PERSONA_NAME_PATTERN.flags).toBe('gi')
  })
})
