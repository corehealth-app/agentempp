import { describe, expect, it } from 'vitest'
import { filterAndFormatRules, normalizeRuleLang, type RuleRow } from './prompt-rules.js'

describe('normalizeRuleLang', () => {
  it('mapeia locale → idioma da regra (pt-BR default)', () => {
    expect(normalizeRuleLang('pt-BR')).toBe('pt-BR')
    expect(normalizeRuleLang('pt')).toBe('pt-BR')
    expect(normalizeRuleLang('en-US')).toBe('en')
    expect(normalizeRuleLang('en')).toBe('en')
    expect(normalizeRuleLang('es-419')).toBe('es')
    expect(normalizeRuleLang(null)).toBe('pt-BR')
    expect(normalizeRuleLang(undefined)).toBe('pt-BR')
    expect(normalizeRuleLang('fr')).toBe('pt-BR') // idioma não suportado → base
  })
})

describe('filterAndFormatRules', () => {
  const rows: RuleRow[] = [
    { topic: 'Persona', content: 'persona...', language: 'pt-BR' },
    { topic: 'Método', content: 'método...', language: null }, // agnóstica
    { topic: 'When to show balance', content: 'when...', language: 'en' },
    { topic: 'Cuándo mostrar', content: 'cuando...', language: 'es' },
  ]

  it('paciente pt-BR: mantém pt-BR + null, DROPA en/es', () => {
    const out = filterAndFormatRules(rows, 'pt-BR')
    if (!out) throw new Error('expected filtered prompt')
    expect(out).toContain('## Persona')
    expect(out).toContain('## Método')
    expect(out).not.toContain('When to show')
    expect(out).not.toContain('Cuándo')
  })

  it('paciente en: mantém pt-BR (base do método) + en + null, DROPA es', () => {
    const out = filterAndFormatRules(rows, 'en')
    if (!out) throw new Error('expected filtered prompt')
    expect(out).toContain('## Persona') // base do método em pt-BR fica
    expect(out).toContain('## When to show balance')
    expect(out).not.toContain('Cuándo')
  })

  it('trata language=pt como alias da base pt-BR para qualquer paciente', () => {
    const legacyPtRule: RuleRow = {
      topic: 'Regra crítica legada',
      content: 'não pode ser descartada',
      language: 'pt',
    }

    expect(filterAndFormatRules([legacyPtRule], 'pt-BR')).toContain('Regra crítica legada')
    expect(filterAndFormatRules([legacyPtRule], 'en')).toContain('Regra crítica legada')
    expect(filterAndFormatRules([legacyPtRule], 'es')).toContain('Regra crítica legada')
  })

  it('formato idêntico ao da view: "## topic\\n\\ncontent" juntado por "\\n\\n---\\n\\n"', () => {
    const out = filterAndFormatRules(
      [
        { topic: 'A', content: 'aaa', language: 'pt-BR' },
        { topic: 'B', content: 'bbb', language: null },
      ],
      'pt-BR',
    )
    expect(out).toBe('## A\n\naaa\n\n---\n\n## B\n\nbbb')
  })

  it('nada sobra → null (caller usa fallback do prompt cheio)', () => {
    expect(filterAndFormatRules([{ topic: 'X', content: 'x', language: 'en' }], 'pt-BR')).toBe(null)
    expect(filterAndFormatRules([], 'pt-BR')).toBe(null)
  })
})
