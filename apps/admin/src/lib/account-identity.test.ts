import { describe, expect, it } from 'vitest'
import { accountContact, accountDisplayName } from './account-identity'

describe('identidade de conta no painel', () => {
  it('conta legada com número mostra o número', () => {
    expect(accountContact({ wpp: '5511999990000', email: 'a@exemplo.com' })).toBe('+5511999990000')
  })

  it('conta do app (sem número) mostra o e-mail quando a tela o carrega', () => {
    expect(accountContact({ wpp: null, email: 'a@exemplo.com' })).toBe('a@exemplo.com')
  })

  it('sem número e sem e-mail carregado, mostra "conta do app" — nunca "+null"', () => {
    expect(accountContact({ wpp: null })).toBe('conta do app')
    expect(accountContact({ wpp: '', email: '  ' })).toBe('conta do app')
    expect(accountContact({})).toBe('conta do app')
  })

  it('nome de exibição cai no contato quando não há nome', () => {
    expect(accountDisplayName({ name: 'Ana', wpp: null })).toBe('Ana')
    expect(accountDisplayName({ name: null, wpp: null })).toBe('conta do app')
    expect(accountDisplayName({ name: ' ', wpp: null, email: 'a@exemplo.com' })).toBe(
      'a@exemplo.com',
    )
  })
})
