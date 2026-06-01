import { describe, expect, it } from 'vitest'
import {
  makeOnboardingButtonId,
  parseOnboardingButtonId,
  parseOnboardingButtonTag,
} from './onboarding-button.js'

describe('parseOnboardingButtonTag', () => {
  it('parseia tag simples 2 opções (sexo)', () => {
    const r = parseOnboardingButtonTag('Você é homem ou mulher?\n[BTN:sex:Homem=masculino|Mulher=feminino]')
    expect(r).not.toBeNull()
    expect(r!.field).toBe('sex')
    expect(r!.body).toBe('Você é homem ou mulher?')
    expect(r!.options).toEqual([
      { label: 'Homem', value: 'masculino' },
      { label: 'Mulher', value: 'feminino' },
    ])
  })

  it('parseia tag 3 opções (fome)', () => {
    const r = parseOnboardingButtonTag(
      'Como tá sua fome dia a dia?\n[BTN:hunger_level:Pouca=pouca|Moderada=moderada|Muita=muita]',
    )
    expect(r!.options.length).toBe(3)
    expect(r!.options[1]!.value).toBe('moderada')
  })

  it('food_organization aceita sim/nao', () => {
    const r = parseOnboardingButtonTag('Segue plano alimentar?\n[BTN:food_organization:Sigo=sim|Como o que aparece=nao]')
    expect(r).not.toBeNull()
    expect(r!.field).toBe('food_organization')
  })

  it('rejeita field não suportado', () => {
    expect(
      parseOnboardingButtonTag('Qual seu time?\n[BTN:soccer_team:Flamengo=fla|Corinthians=cor]'),
    ).toBeNull()
  })

  it('rejeita valor fora do enum', () => {
    expect(parseOnboardingButtonTag('Sexo?\n[BTN:sex:Homem=masculino|Outro=outro]')).toBeNull()
  })

  it('rejeita label > 20 chars', () => {
    expect(
      parseOnboardingButtonTag(
        'Fome?\n[BTN:hunger_level:Pouca fome no dia inteiro=pouca|Moderada=moderada|Muita=muita]',
      ),
    ).toBeNull()
  })

  it('rejeita só 1 opção ou > 3', () => {
    expect(parseOnboardingButtonTag('Sexo?\n[BTN:sex:Homem=masculino]')).toBeNull()
    expect(
      parseOnboardingButtonTag(
        'Algo?\n[BTN:hunger_level:A=pouca|B=moderada|C=muita|D=muita]',
      ),
    ).toBeNull()
  })

  it('rejeita body vazio', () => {
    expect(parseOnboardingButtonTag('[BTN:sex:Homem=masculino|Mulher=feminino]')).toBeNull()
  })

  it('rejeita tag malformada (sem =)', () => {
    expect(parseOnboardingButtonTag('Sexo?\n[BTN:sex:Homem|Mulher]')).toBeNull()
  })

  it('texto sem tag → null', () => {
    expect(parseOnboardingButtonTag('Texto normal sem tag')).toBeNull()
  })
})

describe('button id round-trip', () => {
  it('makeOnboardingButtonId + parseOnboardingButtonId (sex)', () => {
    const id = makeOnboardingButtonId('sex', 'masculino')
    expect(id).toBe('btn_sex_masculino')
    expect(parseOnboardingButtonId(id)).toEqual({ field: 'sex', value: 'masculino' })
  })

  it('field com underscore (food_organization)', () => {
    const id = makeOnboardingButtonId('food_organization', 'sim')
    expect(id).toBe('btn_food_organization_sim')
    expect(parseOnboardingButtonId(id)).toEqual({ field: 'food_organization', value: 'sim' })
  })

  it('current_protocol com valor underscore (ganho_massa)', () => {
    const id = makeOnboardingButtonId('current_protocol', 'ganho_massa')
    expect(parseOnboardingButtonId(id)).toEqual({ field: 'current_protocol', value: 'ganho_massa' })
  })

  it('ID inválido → null', () => {
    expect(parseOnboardingButtonId('confirm_abc123')).toBeNull()
    expect(parseOnboardingButtonId('btn_invalid_value')).toBeNull()
  })
})
