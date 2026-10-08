/** Presentation copies only: exact independent oracles, no nutrition calculation. */
import { normalizeProtocol } from '@mpp/core'
import { describe, expect, it } from 'vitest'
import {
  projectFlowMetricAnswer,
  projectFlowMetricContext,
  projectStoredFlowMetricAnswer,
} from '../flow-public-metrics.js'
import fixtures from './fixtures/c3c4-flow-objective-projection.json'

describe('C3/C4 Flow public objective boundary', () => {
  it.each([
    ['Bloco 7700: (3120 kcal). Evite amendoim.', true],
    ['Orçamento 14 dias: (5850 / 5960 kcal). Evite amendoim.', false],
  ] as const)('keeps a numeric parenthetic value bound to its restricted label: %s', (source, block) => {
    for (const currentProtocol of ['recomposicao', 'ganho_massa', 'manutencao', null] as const) {
      const objective = { currentProtocol }
      if (block && currentProtocol === 'recomposicao') {
        expect(projectFlowMetricContext(source, objective)).toBe(source)
        expect(projectStoredFlowMetricAnswer(source, 'pt-BR', false, objective)).toBe(source)
        continue
      }
      // The existing context marker replaces the complete metric statement,
      // including its punctuation, in both plain and parenthetic values.
      expect(projectFlowMetricContext(source.replace(/[()]/gu, ''), objective)).toBe(
        '[referência interna omitida] Evite amendoim.',
      )
      expect(projectFlowMetricContext(source, objective)).toBe(
        '[referência interna omitida] Evite amendoim.',
      )
      const expected =
        block && currentProtocol !== null
          ? 'Evite amendoim.\n\nO Bloco 7.700 é exibido apenas na recomposição corporal.'
          : 'Evite amendoim.'
      expect(projectStoredFlowMetricAnswer(source, 'pt-BR', false, objective)).toBe(expected)
      expect(projectStoredFlowMetricAnswer(expected, 'pt-BR', false, objective)).toBe(expected)
    }
  })
  it.each([
    [
      'Evite amendoim por sua alergia (Dias acima da meta (dam): 1/2).',
      'Evite amendoim por sua alergia',
      'pt-BR',
    ],
    [
      'Avoid peanuts because of your allergy (Days above target (dam): 1/2).',
      'Avoid peanuts because of your allergy',
      'en',
    ],
  ])('keeps the outer allergy when a qualified DAM count is parenthetic: %s', (source, fact, locale) => {
    for (const currentProtocol of ['recomposicao', 'ganho_massa', 'manutencao', null] as const) {
      const objective = { currentProtocol }
      expect(projectFlowMetricContext(source, objective)).toBe(
        `${fact} ([referência interna omitida]).`,
      )
      expect(projectStoredFlowMetricAnswer(source, locale, false, objective)).toBe(`${fact}.`)
    }
  })
  it.each([
    ['Dias acima da meta (dam): 1/2; evite amendoim por sua alergia.', 'pt-BR'],
    ['Days above target (dam): 1/2; avoid peanuts because of your allergy.', 'en'],
    ['Dias acima da meta (dam): **1/2**; evite amendoim por sua alergia.', 'pt-BR'],
    ['Days above target (dam): **1/2**; avoid peanuts because of your allergy.', 'en'],
  ])('hides a qualified lowercase DAM count without losing the allergy: %s', (source, locale) => {
    const fact =
      locale === 'en' ? 'avoid peanuts because of your allergy.' : 'evite amendoim por sua alergia.'
    for (const currentProtocol of ['recomposicao', 'ganho_massa', 'manutencao', null] as const) {
      const objective = { currentProtocol }
      expect(projectFlowMetricContext(source, objective)).toBe(
        `[referência interna omitida]; ${fact}`,
      )
      expect(projectStoredFlowMetricAnswer(source, locale, false, objective)).toBe(fact)
      expect(projectStoredFlowMetricAnswer(fact, locale, false, objective)).toBe(fact)
    }
  })
  it('preserves the exact relative destination containing block and DAM tokens', () => {
    const source = 'Veja docs/Bloco7700.md?DAM=1/2#help.'
    for (const currentProtocol of ['recomposicao', 'ganho_massa', 'manutencao', null] as const) {
      const objective = { currentProtocol }
      expect(projectFlowMetricContext(source, objective)).toBe(source)
      expect(projectFlowMetricAnswer(source, null, 'pt-BR', false, undefined, objective)).toBe(
        source,
      )
      expect(projectStoredFlowMetricAnswer(source, 'pt-BR', false, objective)).toBe(source)
    }
  })
  it.each([
    ['| Dias acima da meta (dam) | **1/2** |', 'pt-BR'],
    ['| Days above target (dam) | **1/2** |', 'en'],
    ['| Dias acima da meta (DAM) | **1/2** |', 'pt-BR'],
    ['| Days above target (DAM) | **1/2** |', 'en'],
  ])('keeps a qualified lowercase DAM table label with its value: %s', (metric, locale) => {
    for (const currentProtocol of ['recomposicao', 'ganho_massa', 'manutencao', null] as const) {
      const objective = { currentProtocol }
      const fact =
        locale === 'en'
          ? 'Avoid peanuts because of your allergy.'
          : 'Evite amendoim por sua alergia.'
      const source = `${metric}\n${fact}`
      expect(projectFlowMetricContext(source, objective)).toBe(
        `[referência interna omitida]\n${fact}`,
      )
      expect(projectStoredFlowMetricAnswer(source, locale, false, objective)).toBe(fact)
    }
  })
  it.each([
    [
      '7,700 Block: 3,120 kcal.',
      'https://example.invalid/Bloco7700',
      'pt-BR',
      'The 7,700 Block is displayed only for body recomposition.',
      'Your suggestion is ready to review in the app.',
    ],
    [
      'Bloco 7700: 3120 kcal.',
      'https://example.invalid/7700Block',
      'en',
      'O Bloco 7.700 é exibido apenas na recomposição corporal.',
      'Sua sugestão está pronta em "Revisar sugestão".',
    ],
  ])('uses historical prose language without reading reference tokens: %s', (metric, url, locale, explanation, cta) => {
    for (const currentProtocol of ['ganho_massa', 'manutencao'] as const) {
      const objective = { currentProtocol }
      const source = `${metric}\n${url}`
      const expected = `${url}\n\n${explanation}\n\n${cta}`
      expect(projectFlowMetricContext(source, objective)).toBe(
        `[referência interna omitida]\n${url}`,
      )
      expect(projectStoredFlowMetricAnswer(source, locale, true, objective)).toBe(expected)
      expect(projectStoredFlowMetricAnswer(expected, locale, true, objective)).toBe(expected)
      const linked = `${metric}\n[Help](${url})`
      const linkedExpected = `[Help](${url})\n\n${explanation}\n\n${cta}`
      expect(projectStoredFlowMetricAnswer(linked, locale, true, objective)).toBe(linkedExpected)
      expect(projectStoredFlowMetricAnswer(linkedExpected, locale, true, objective)).toBe(
        linkedExpected,
      )
    }
  })
  it.each([
    ['| Bloco 7700 | 3.120 / 7.700 kcal (41%) |', 'ganho_massa', true],
    ['| Bloco 7700 | 3.120 / 7.700 kcal (41%) |', null, false],
    ['| Orçamento 14d | 5.850 / 5.960 kcal |', 'recomposicao', false],
    ['| Orçamento 14d | 5.850 / 5.960 kcal |', 'manutencao', false],
  ] as const)('removes the qualified table label and its value together: %s/%s', (row, protocol, explanation) => {
    const source = `| Alimento | arroz branco, 150 g |\n${row}\n| Restrição | evite amendoim por sua alergia |\n| Consumido | 541 / 2.980 kcal |`
    const publicRows =
      '| Alimento | arroz branco, 150 g |\n| Restrição | evite amendoim por sua alergia |\n| Consumido | 541 / 2.980 kcal |'
    const objective = { currentProtocol: protocol }
    expect(projectFlowMetricContext(source, objective)).toBe(
      publicRows.replace('\n| Restrição', '\n[referência interna omitida]\n| Restrição'),
    )
    expect(projectStoredFlowMetricAnswer(source, 'pt-BR', false, objective)).toBe(
      explanation
        ? `${publicRows}\n\nO Bloco 7.700 é exibido apenas na recomposição corporal.`
        : publicRows,
    )
  })
  it('keeps a block table row intact for the current recomp objective', () => {
    const source =
      '| Bloco 7700 | 3.120 / 7.700 kcal (41%) |\n| Alimento | arroz branco, 150 g, 195 kcal |'
    const objective = { currentProtocol: 'recomposicao' as const }
    expect(projectFlowMetricContext(source, objective)).toBe(source)
    expect(projectStoredFlowMetricAnswer(source, 'pt-BR', false, objective)).toBe(source)
  })
  it.each([
    ['Orçamento para 14 dias: 5.850 / 5.960 kcal (98%).', 'pt-BR'],
    ['Budget for 14 days: 5,850 / 5,960 kcal (98%).', 'en'],
  ])('hides a qualified 14-day budget without a DAM label: %s', (metric, locale) => {
    const publicFact =
      locale === 'en' ? 'Avoid peanuts because of your allergy.' : 'Evite amendoim por sua alergia.'
    for (const protocol of ['recomposicao', 'ganho_massa', 'manutencao', null] as const) {
      const objective = { currentProtocol: protocol }
      expect(projectFlowMetricContext(`${metric}\n${publicFact}`, objective)).toBe(
        `[referência interna omitida]\n${publicFact}`,
      )
      expect(
        projectStoredFlowMetricAnswer(`${metric}\n${publicFact}`, locale, false, objective),
      ).toBe(publicFact)
    }
  })
  it.each([
    ['Déficit acumulado (bloco 7700): 3120 kcal — evite amendoim por sua alergia.', ' — ', true],
    [
      'Déficit acumulado (bloco 7700): **3120** kcal — evite amendoim por sua alergia.',
      ' — ',
      true,
    ],
    ['Dias acima da meta (DAM): 1/2; evite amendoim por sua alergia.', '; ', false],
    ['Days above target (DAM): 1/2; avoid peanuts because of your allergy.', '; ', false],
    ['- Dias acima da meta (DAM): 1/2; evite amendoim por sua alergia.', '; ', false],
    ['- Days above target (DAM): 1/2; avoid peanuts because of your allergy.', '; ', false],
  ] as const)('keeps the allergy following a metric with a parenthetic label: %s', (text, separator, explanation) => {
    const fact = text.includes('Days')
      ? 'avoid peanuts because of your allergy.'
      : 'evite amendoim por sua alergia.'
    const locale = text.includes('Days') ? 'en' : 'pt-BR'
    for (const currentProtocol of ['recomposicao', 'ganho_massa', 'manutencao', null] as const) {
      const objective = { currentProtocol }
      if (explanation && currentProtocol === 'recomposicao') {
        expect(projectFlowMetricContext(text, objective)).toBe(text)
        expect(projectStoredFlowMetricAnswer(text, locale, false, objective)).toBe(text)
        continue
      }
      expect(projectFlowMetricContext(text, objective)).toBe(
        `[referência interna omitida]${separator}${fact}`,
      )
      const answer =
        explanation && (currentProtocol === 'ganho_massa' || currentProtocol === 'manutencao')
          ? `${fact}\n\nO Bloco 7.700 é exibido apenas na recomposição corporal.`
          : fact
      expect(projectStoredFlowMetricAnswer(text, locale, false, objective)).toBe(answer)
    }
  })
  it('preserves streak and XP on the real middot-separated status line', () => {
    const text =
      '🏅 Sequência: **3 dias consecutivos** · Nível 2 (1.240 XP) · Blocos 7700 fechados: 4'
    const objective = { currentProtocol: 'ganho_massa' as const }
    expect(projectFlowMetricContext(text, objective)).toBe(
      '🏅 Sequência: **3 dias consecutivos** · Nível 2 (1.240 XP) · [referência interna omitida]',
    )
    expect(projectStoredFlowMetricAnswer(text, 'pt-BR', false, objective)).toBe(
      '🏅 Sequência: **3 dias consecutivos** · Nível 2 (1.240 XP)\n\nO Bloco 7.700 é exibido apenas na recomposição corporal.',
    )
  })
  it('keeps ordinary English dam wording unchanged', () => {
    const text = 'Walk beside the dam for 14 days, if that suits your routine.'
    const objective = { currentProtocol: 'manutencao' as const }
    expect(projectFlowMetricContext(text, objective)).toBe(text)
    expect(projectStoredFlowMetricAnswer(text, 'en', false, objective)).toBe(text)
  })
  it.each([
    [
      '14-day budget: 5,850 / 5,960 kcal (98%) · DAM: 1/2',
      'pt-BR',
      false,
      'recomposicao',
      'Check your official targets in Today and your objective details in Profile.',
    ],
    [
      'Orçamento 14d: 5.850 / 5.960 kcal (98%) · DAM: 1/2',
      'en',
      false,
      'recomposicao',
      'Confira suas metas oficiais em Hoje e os dados do seu objetivo em Perfil.',
    ],
    [
      'Bloco 7700: 3120 / 7700 kcal (41%)',
      'en',
      true,
      'ganho_massa',
      'Confira suas metas oficiais em Hoje e os dados do seu objetivo em Perfil.\n\nO Bloco 7.700 é exibido apenas na recomposição corporal.\n\nSua sugestão está pronta em "Revisar sugestão".',
    ],
    [
      '7,700 Block: 3,120 / 7,700 kcal (41%)',
      'pt-BR',
      true,
      'manutencao',
      'Check your official targets in Today and your objective details in Profile.\n\nThe 7,700 Block is displayed only for body recomposition.\n\nYour suggestion is ready to review in the app.',
    ],
  ] as const)('recognizes the original historical language without a possessive label: %s', (text, locale, hasSuggestion, protocol, expected) => {
    expect(
      projectStoredFlowMetricAnswer(text, locale, hasSuggestion, { currentProtocol: protocol }),
    ).toBe(expected)
  })
  it('keeps a metric-labelled link destination usable without a metric or invented link label', () => {
    const url = 'https://example.invalid/Bloco7700?DAM=1/2#budget14d'
    const source = `[Bloco 7700: 3120 kcal](${url})\nEvite amendoim.`
    const objective = { currentProtocol: 'ganho_massa' as const }
    expect(projectFlowMetricContext(source, objective)).toBe(
      `[referência interna omitida](${url})\nEvite amendoim.`,
    )
    expect(projectStoredFlowMetricAnswer(source, 'pt-BR', false, objective)).toBe(
      `${url}\nEvite amendoim.\n\nO Bloco 7.700 é exibido apenas na recomposição corporal.`,
    )
  })
  it.each([
    [
      'Sequência atual: 3 dias (recorde 7) | XP: 1240 (nível 2) | Blocos 7700 fechados: 4',
      'Sequência atual: 3 dias (recorde 7) | XP: 1240 (nível 2)',
      'Sequência atual: 3 dias (recorde 7) | XP: 1240 (nível 2) | [referência interna omitida]',
    ],
    [
      'Exercício: 322 kcal _(acelera o bloco 7700)_',
      'Exercício: 322 kcal',
      'Exercício: 322 kcal _([referência interna omitida])_',
    ],
    [
      'DIA INCOMPLETO: paciente não respondeu ao lembrete. Bloco 7700 NÃO foi creditado por esse dia.',
      'DIA INCOMPLETO: paciente não respondeu ao lembrete.',
      'DIA INCOMPLETO: paciente não respondeu ao lembrete. [referência interna omitida]',
    ],
  ])('preserves adjacent public facts in real formatted copy: %s', (text, expected, context) => {
    const objective = { currentProtocol: 'ganho_massa' as const }
    expect(projectFlowMetricContext(text, objective)).toBe(context)
    expect(projectStoredFlowMetricAnswer(text, 'pt-BR', false, objective)).toBe(
      `${expected}\n\nO Bloco 7.700 é exibido apenas na recomposição corporal.`,
    )
  })
  it.each([
    ['📊 Bloco 7700: **3120 / 7700 kcal (41%)**\nEvite amendoim.', 'ganho_massa'],
    [
      'Orçamento 14 dias: **5850 / 5960 kcal (98%)** | DAM: 1/2 dias | janela: 2 dias fechados\nEvite amendoim.',
      'recomposicao',
    ],
    ['14-day budget: **5,850 / 5,960 kcal**\nEvite amendoim.', 'recomposicao'],
  ])('keeps markdown values bound to their restricted labels: %s', (text, protocol) => {
    const objective = { currentProtocol: normalizeProtocol(protocol) }
    const context = projectFlowMetricContext(text, objective)
    expect(context).toBe('[referência interna omitida]\nEvite amendoim.')
    const answer = projectStoredFlowMetricAnswer(text, 'pt-BR', false, objective)
    expect(answer).toBe(
      protocol === 'ganho_massa'
        ? 'Evite amendoim.\n\nO Bloco 7.700 é exibido apenas na recomposição corporal.'
        : 'Evite amendoim.',
    )
  })
  it.each(fixtures.cases)('$id', ({ input, expected_context, expected_answer }) => {
    const original = JSON.stringify(input)
    Object.freeze(input)
    const objective = Object.freeze({ currentProtocol: normalizeProtocol(input.raw_protocol) })
    expect(projectFlowMetricContext(input.text, objective)).toBe(expected_context)
    const answer = () =>
      input.surface === 'new'
        ? projectFlowMetricAnswer(
            input.text,
            input.official_targets ?? null,
            input.locale,
            input.has_suggestion,
            undefined,
            objective,
          )
        : projectStoredFlowMetricAnswer(input.text, input.locale, input.has_suggestion, objective)
    const result = answer()
    expect(result).toBe(expected_answer)
    // The public output can pass the HTTP read boundary again without repeated feedback.
    expect(
      projectStoredFlowMetricAnswer(result, input.locale, input.has_suggestion, objective),
    ).toBe(result)
    expect(JSON.stringify(input)).toBe(original)
  })

  it.each(fixtures.c1_composition)('$id retains the existing metric policy', ({
    input,
    expected,
  }) => {
    const objective = { currentProtocol: normalizeProtocol(input.raw_protocol) }
    expect(
      projectStoredFlowMetricAnswer(input.text, input.locale, input.has_suggestion, objective),
    ).toBe(expected.public_answer)
  })
})
