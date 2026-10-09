import { describe, expect, it } from 'vitest'
import { classifyFlowDayStatusIntent } from './flow-day-status-intent.js'

const PT = [
  'Como está meu dia?',
  'Como está meu dia até agora?',
  'Como está o meu dia?',
  'Como está meu dia hoje?',
  'Como está o meu dia hoje?',
  'Como tá meu dia?',
  'Como tá o meu dia?',
  'Como tá meu dia hoje?',
  'Como tá o meu dia hoje?',
  'Status do dia',
  'Resumo do dia',
] as const

const EN = [
  'How is my day?',
  'How is my day so far?',
  'How is my day today?',
  'How is my day going?',
  'How is my day going today?',
  "How's my day?",
  "How's my day going?",
  'Day status',
  'Daily summary',
] as const

describe('C7 whole-message status intent, before any model/tool decision', () => {
  it.each(PT)('recognizes the entire Portuguese question %s', (text) => {
    expect(classifyFlowDayStatusIntent(text)).toEqual({ kind: 'day_status', locale: 'pt-BR' })
  })

  it.each(EN)('recognizes the entire English question %s', (text) => {
    expect(classifyFlowDayStatusIntent(text)).toEqual({ kind: 'day_status', locale: 'en' })
  })

  it.each([
    '  COMO   ESTÁ O MEU DIA HOJE?!  ',
    'como esta meu dia',
    'Como esta\u0301 meu dia?',
    '\nResumo\t do   dia.\n',
    'Como está meu dia ?  ',
  ])('normalizes casing, accents and whitespace without deleting extra wording: %s', (text) => {
    expect(classifyFlowDayStatusIntent(text)).toEqual({ kind: 'day_status', locale: 'pt-BR' })
  })

  it('accepts a typographic apostrophe, without changing the returned language meaning', () => {
    expect(classifyFlowDayStatusIntent('How’s my day going?')).toEqual({
      kind: 'day_status',
      locale: 'en',
    })
  })

  it.each([
    'Como está meu dia? Posso comer mais?',
    'Como está meu dia? Estou com tontura.',
    'Como está meu dia? Tenho alergia a amendoim.',
    'Como está meu dia? Estou com dor no peito.',
    'Como está meu dia? Não comi nada hoje.',
    'Como está meu dia? E ontem?',
    'Como está meu dia\nPosso comer mais?',
    'Status do dia e sugestão de jantar',
    'Resumo do dia, mas antes registre meu almoço',
    'Quero registrar meu almoço e saber meu status',
    'Quanto falta para eu jantar?',
    'Por que minha meta é essa?',
    'Bom dia, como está meu dia?',
    'Oi! Status do dia',
    'Mostre o resumo do dia anterior',
    'How is my day? Can I eat more?',
    'How is my day? I feel dizzy.',
    'How is my day? I have a peanut allergy.',
    'How is my day? I have chest pain.',
    'How is my day? I skipped breakfast.',
    'How is my day? What about yesterday?',
    'Daily summary and a dinner suggestion',
    'Register my lunch and give me the day status',
    'Hello, how is my day?',
    'How is my day? Please answer in Portuguese.',
    'Como está meu dia? Responda em inglês.',
    'Como tô?',
    'Como estou?',
    'Quanto falta?',
    'Meu bloco',
    'How am I doing?',
    '🥗 Como está meu dia?',
    'Como está meu dia? 🥗',
    'Como está meu dia\u0000',
    'Como está meu dia? ? E ontem?',
    '?Como está meu dia',
    'Como. está meu dia',
  ])('preserves the normal Flow path for mixed, clinical or ambiguous wording: %s', (text) => {
    expect(classifyFlowDayStatusIntent(text)).toBeNull()
  })

  it.each(
    [null, undefined, '', ' ', 0, false, {}, [], ['Status do dia']].map((text) => ({ text })),
  )('does not invent an intent from %j', ({ text }) =>
    expect(classifyFlowDayStatusIntent(text)).toBeNull())

  it('has no mutable selection carried from A to B to A', () => {
    const a = classifyFlowDayStatusIntent('Como está meu dia?')
    expect(a).toEqual({ kind: 'day_status', locale: 'pt-BR' })
    classifyFlowDayStatusIntent('Daily summary')
    expect(classifyFlowDayStatusIntent('Como está meu dia?')).toEqual(a)
  })
})
