import { describe, expect, it } from 'vitest'
import { projectFlowPublicNames } from '../flow-public-names.js'

describe('C2: expressão de marca Usina muscular no texto recebido pelo app', () => {
  it.each([
    'Usina muscular',
    'Usina Muscular',
    'USINA MUSCULAR',
    'usina muscular',
    'Usina\u00a0muscular',
    'Usina-muscular',
    'UsinaMuscular',
  ])('projeta somente a expressão completa %s', (name) => {
    const output = projectFlowPublicNames(`As orientações seguem ${name}.`)
    expect(output.text).toBe('As orientações seguem Performe AI.')
    expect(output.method).toBe(1)
  })

  it('projeta a marca na pergunta exata encontrada pela revisão', () => {
    const output = projectFlowPublicNames('Você conhece a Usina muscular?')
    expect(output.text).toBe('Você conhece a Performe AI?')
    expect(output.method).toBe(1)
  })

  it.each([
    'https://example.test/guia?ref=(Usina-muscular)',
    'https://example.test/guia#section:Usina-muscular',
    "https://example.test/guia?ref='Usina-muscular'",
  ])('preserva o endereço completo encontrado pela revisão: %s', (url) => {
    const output = projectFlowPublicNames(url)
    expect(output.text).toBe(url)
    expect(output.method).toBe(0)
  })

  it('projeta a marca entre aspas na prosa fora de um endereço', () => {
    expect(projectFlowPublicNames("Você conhece 'Usina muscular'?").text).toBe(
      "Você conhece 'Performe AI'?",
    )
  })

  it.each([
    '[guia](/guia?ref=(Usina-muscular))',
    '[guia](./guia?ref=(Usina-muscular))',
    '[guia](guia?ref=(Usina-muscular))',
    '/guia?ref=(Usina-muscular)',
  ])('preserva destinos relativos com delimitadores: %s', (text) => {
    expect(projectFlowPublicNames(text).text).toBe(text)
  })

  it('preserva a expressão no URL original mesmo com projeção legada antes dela', () => {
    const output = projectFlowPublicNames(
      'https://example.test/guia?ref=mpp&label=(Usina-muscular)',
    )
    // A transformação de MPP preexistente continua igual, sem troca adicional de Usina.
    expect(output.text).toBe('https://example.test/guia?ref=Performe AI&label=(Usina-muscular)')
    expect(output.method).toBe(1)
  })

  it('preserva o destino do link e projeta a marca na prosa do mesmo texto', () => {
    const output = projectFlowPublicNames(
      'Usina muscular: [guia](https://example.test/guia?ref=(Usina-muscular)). Usina muscular?',
    )
    expect(output.text).toBe(
      'Performe AI: [guia](https://example.test/guia?ref=(Usina-muscular)). Performe AI?',
    )
    expect(output.method).toBe(2)
  })

  it.each([
    'Seu corpo é uma usina: consistência é o combustível.',
    'A força muscular depende do treino.',
    'https://example.test/usina-muscular/guia',
    'https://example.test/guia?ref=Usina-muscular',
    'https://example.test/guia#Usina-muscular',
    'docs/Usina-muscular.md',
    'C:\\docs\\Usina-muscular\\guia.md',
    'usina_muscular_v1',
    'Usina-muscular-2',
    'Dr. Roberto',
    'Dra. Roberta Menescal',
    'Ana Menescal',
  ])('preserva palavras genéricas, pessoa ou identificador: %s', (text) => {
    expect(projectFlowPublicNames(text).text).toBe(text)
  })

  it('preserva o nome da pessoa cadastrada e continua projetando a marca', () => {
    const output = projectFlowPublicNames('Roberto Menescal, seguimos Usina muscular.', {
      accountName: 'Roberto Menescal',
    })
    expect(output.text).toBe('Roberto Menescal, seguimos Performe AI.')
    expect(output.method).toBe(1)
    expect(output.personaOther).toBe(0)
  })
})
