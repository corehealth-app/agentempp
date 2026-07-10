import { describe, expect, it } from 'vitest'
import { decideMealType, detectExplicitMealType } from './meal-type-decision.js'

describe('decideMealType', () => {
  it('corrige mismatch adjacente de lanche para jantar', () => {
    expect(
      decideMealType({
        claimed: 'lanche',
        expected: 'jantar',
        currentUserText: '200g de frango com arroz',
      }),
    ).toMatchObject({ mealType: 'jantar', autoCorrected: true, reason: 'expected_by_routine' })
  })

  it('respeita o tipo explicitamente dito no turno atual', () => {
    expect(
      decideMealType({
        claimed: 'lanche',
        expected: 'lanche',
        currentUserText: 'Esse foi o meu jantar',
      }),
    ).toMatchObject({ mealType: 'jantar', reason: 'explicit_current_text' })
  })

  it('mantem refeicao cobrada por lembrete ativo do mesmo dia', () => {
    expect(
      decideMealType({
        claimed: 'almoco',
        expected: 'jantar',
        currentUserText: 'chicken wings',
        activeReminderMealTypes: ['almoco'],
      }),
    ).toMatchObject({ mealType: 'almoco', autoCorrected: false, reason: 'active_gap_reminder' })
  })

  it('gap sem lembrete ativo nao bloqueia a classificacao pela rotina', () => {
    expect(
      decideMealType({
        claimed: 'almoco',
        expected: 'jantar',
        currentUserText: 'chicken wings',
        activeReminderMealTypes: [],
      }),
    ).toMatchObject({ mealType: 'jantar', autoCorrected: true })
  })

  it('pending confirmado preserva meal_type exibido ao paciente', () => {
    expect(
      decideMealType({
        claimed: 'cafe',
        expected: 'lanche',
        currentUserText: '',
        trustMealType: true,
      }),
    ).toMatchObject({ mealType: 'cafe', reason: 'trusted_pending' })
  })
})

describe('detectExplicitMealType', () => {
  it('usa a afirmacao positiva em "nao foi lanche, foi jantar"', () => {
    expect(detectExplicitMealType('Não foi lanche, foi jantar')).toBe('jantar')
  })

  it('nao usa conversa sem nome de refeicao', () => {
    expect(detectExplicitMealType('frango com arroz e feijao')).toBeNull()
  })

  it('nao confunde cafe solúvel com cafe da manha', () => {
    expect(detectExplicitMealType('200 ml de leite com uma colher de café solúvel')).toBeNull()
  })
})
