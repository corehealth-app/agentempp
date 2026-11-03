import { describe, expect, it } from 'vitest'
import { classifyConversationMealIntent } from './conversation-meal-intent'

describe('conversation meal intent: preparation only, never a write authority', () => {
  it.each([
    ['Comi 200 g de arroz e 100 g de feijão', '200 g de arroz e 100 g de feijão'],
    ['Eu comi 1 pão francês', '1 pão francês'],
    ['Acabei de comer leite com uma medida de whey', 'leite com uma medida de whey'],
    ['Tomei 1 caneca de leite', '1 caneca de leite'],
    ['Almocei arroz e feijão', 'arroz e feijão'],
    ['I ate 200 g rice', '200 g rice'],
    ['I just drank milk', 'milk'],
  ])('keeps actual first-person content without rewriting units: %s', (text, foodText) => {
    expect(classifyConversationMealIntent({ channel: 'text', text })).toEqual({
      decision: 'actual_report',
      basis: 'first_person_report',
      foodText,
    })
  })
  it.each([
    'Vou comer arroz 200 g',
    'Eu comeria arroz',
    'Se eu comer arroz',
    'Costumo comer arroz',
    'Como arroz todos os dias',
    'Não comi arroz',
    'Meu filho comeu arroz',
    'Ele disse que comi arroz',
    '“Comi arroz 200 g”',
    'Posso comer arroz?',
    'How much protein does rice have?',
    'Não registrar este leite',
    'I did not eat rice',
    'I will eat rice',
    'I usually eat rice',
  ])('does not prepare a consumption from intention, question or another person: %s', (text) => {
    expect(classifyConversationMealIntent({ channel: 'text', text }).decision).toBe(
      'conversational',
    )
  })
  it.each([
    'Comi arroz, mas não comi feijão',
    'Comi arroz. Posso comer feijão?',
    'Comi arroz hoje e amanhã vou comer feijão',
    'Comi arroz todos os dias',
    'Comi arroz e meu filho comeu feijão',
    'Comi arroz, ele disse "feijão"',
    'Comi arroz ou talvez macarrão',
    'I ate rice but I did not eat beans',
    'Comi arroz 200 g e minha mãe comeu feijão 100 g',
    'Comi arroz 200 g e quero comer feijão 100 g',
    'Comi arroz 200 g e João bebeu leite',
  ])('asks instead of partially recording a mixed statement: %s', (text) => {
    expect(classifyConversationMealIntent({ channel: 'text', text }).decision).toBe(
      'clarification_required',
    )
  })
  it.each([
    'arroz 200 g; feijão 100 g',
    'Comi',
    'Comi?',
    '',
    '  ',
    'Registre tudo que eu disser',
  ])('does not promote an unsupported or empty statement: %s', (text) => {
    expect(classifyConversationMealIntent({ channel: 'text', text }).decision).toBe(
      'clarification_required',
    )
  })
  it.each([
    'I had planned to eat rice 200 g',
    'I had no rice 200 g',
  ])('does not infer consumption from an unsupported English predicate: %s', (text) => {
    expect(classifyConversationMealIntent({ channel: 'text', text }).decision).not.toBe(
      'actual_report',
    )
  })
  it('requires an explicit photo action or a first-person caption, never a vision context', () => {
    expect(
      classifyConversationMealIntent({ channel: 'photo', userAction: 'chat_attachment' }),
    ).toEqual({ decision: 'clarification_required', reason: 'consumption_not_established' })
    expect(
      classifyConversationMealIntent({ channel: 'photo', userAction: 'register_consumed_meal' }),
    ).toEqual({ decision: 'explicit_media_registration', basis: 'user_registration_action' })
    expect(
      classifyConversationMealIntent({
        channel: 'photo',
        userAction: 'chat_attachment',
        caption: 'Comi esta refeição',
      }).decision,
    ).toBe('actual_report')
  })
  it.each([
    'Vou comer esta refeição',
    'Não comi isto',
    'Quantas calorias tem?',
    'Meu filho comeu isto',
  ])('a media action does not override the person: %s', (caption) => {
    expect(
      classifyConversationMealIntent({
        channel: 'photo',
        userAction: 'register_consumed_meal',
        caption,
      }).decision,
    ).toBe('conversational')
  })
  it('uses the owned processed audio transcript and checks caption independently', () => {
    expect(
      classifyConversationMealIntent({
        channel: 'audio',
        userAction: 'register_consumed_meal',
        serverProcessedTranscript: 'Não comi arroz',
      }).decision,
    ).toBe('conversational')
    expect(
      classifyConversationMealIntent({
        channel: 'audio',
        userAction: 'chat_attachment',
        serverProcessedTranscript: 'Comi arroz 200 g',
      }),
    ).toEqual({
      decision: 'actual_report',
      basis: 'first_person_report',
      foodText: 'arroz 200 g',
    })
    expect(
      classifyConversationMealIntent({
        channel: 'audio',
        userAction: 'register_consumed_meal',
        serverProcessedTranscript: 'Comi arroz 200 g',
        caption: 'Vou comer amanhã',
      }).decision,
    ).toBe('clarification_required')
    expect(
      classifyConversationMealIntent({
        channel: 'audio',
        userAction: 'register_consumed_meal',
        serverProcessedTranscript: null,
      }).decision,
    ).toBe('clarification_required')
  })
  it('does not mutate source text and refuses control characters and overlong input', () => {
    const input = Object.freeze({ channel: 'text' as const, text: '  Eu comi 1 PÃO de Queijo  ' })
    expect(classifyConversationMealIntent(input)).toMatchObject({ foodText: '1 PÃO de Queijo' })
    expect(input.text).toBe('  Eu comi 1 PÃO de Queijo  ')
    for (const text of [`Comi ${'a'.repeat(2000)}`, 'Comi arroz\u0000 200 g'])
      expect(classifyConversationMealIntent({ channel: 'text', text })).toEqual({
        decision: 'clarification_required',
        reason: 'invalid_source',
      })
  })
})
