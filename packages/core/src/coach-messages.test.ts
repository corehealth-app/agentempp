import { describe, expect, it } from 'vitest'
import {
  COACH_CONTEXT_ALLOWED_VARIABLES,
  type CoachTemplateLintInput,
  chooseLeastRecentlyUsedVariant,
  coachMessageChannelSchema,
  coachMessageContextSchema,
  coachMessageLocaleSchema,
  coachPersonalitySchema,
  extractCoachPlaceholders,
  lintCoachTemplate,
  renderCoachTemplate,
  selectableCoachPersonalitySchema,
} from './coach-messages.js'

const validTemplate: CoachTemplateLintInput = {
  context: 'progress',
  channel: 'in_app',
  locale: 'pt-BR',
  title: null,
  subject: null,
  body: '{{name}}, seu progresso chegou a {{block_progress_percent}}%.',
  allowedVariables: ['name', 'block_progress_percent'],
  requiredVariables: ['name', 'block_progress_percent'],
}

describe('coach message contracts', () => {
  it('keeps balanced internal and exposes only three selectable personalities', () => {
    expect(coachPersonalitySchema.options).toEqual(['balanced', 'focus', 'impulse', 'zen'])
    expect(selectableCoachPersonalitySchema.options).toEqual(['focus', 'impulse', 'zen'])
    expect(selectableCoachPersonalitySchema.safeParse('balanced').success).toBe(false)
  })

  it('locks the approved contexts, channels, and locales', () => {
    expect(coachMessageContextSchema.options).toEqual([
      'onboarding',
      'meal_pending',
      'registration_confirmed',
      'error_corrected',
      'hydration',
      'supplement',
      'medication',
      'workout',
      'progress',
      'day_incomplete',
      'reevaluation',
      'reengagement',
      'trial',
      'paywall',
      'return_after_abandonment',
    ])
    expect(coachMessageChannelSchema.options).toEqual(['in_app', 'push', 'email'])
    expect(coachMessageLocaleSchema.options).toEqual(['pt-BR', 'en-US'])
  })

  it('owns a fixed variable allowlist for every context', () => {
    expect(Object.keys(COACH_CONTEXT_ALLOWED_VARIABLES).sort()).toEqual(
      [...coachMessageContextSchema.options].sort(),
    )
    expect(COACH_CONTEXT_ALLOWED_VARIABLES.progress).toEqual([
      'name',
      'protein_remaining_g',
      'kcal_remaining',
      'block_progress_percent',
    ])
  })
})

describe('coach template placeholders', () => {
  it('extracts unique snake_case placeholders in first-seen order', () => {
    expect(
      extractCoachPlaceholders(
        '{{name}}, faltam {{protein_remaining_g}}g. {{name}}, siga no seu ritmo.',
      ),
    ).toEqual(['name', 'protein_remaining_g'])
  })

  it('rejects malformed and unknown placeholders', () => {
    const issues = lintCoachTemplate({
      ...validTemplate,
      body: '{{ user.name }} chegou a {{unknown_value}}%.',
    })

    expect(issues.map((issue) => issue.code)).toEqual([
      'invalid_placeholder',
      'unknown_variable',
      'missing_required_variable',
      'missing_required_variable',
    ])
  })

  it('rejects dangling placeholder syntax and required variables outside the allowlist', () => {
    const issues = lintCoachTemplate({
      ...validTemplate,
      body: '{{name}, progresso registrado.',
      allowedVariables: ['name'],
      requiredVariables: ['name', 'block_progress_percent'],
    })

    expect(issues).toEqual(
      expect.arrayContaining([
        expect.objectContaining({ code: 'invalid_placeholder', field: 'body' }),
        expect.objectContaining({
          code: 'unknown_variable',
          field: 'variables',
          message: expect.stringContaining('block_progress_percent'),
        }),
      ]),
    )
  })

  it('rejects a declared variable that does not belong to the message context', () => {
    const issues = lintCoachTemplate({
      ...validTemplate,
      body: '{{medication_name}} foi registrado.',
      allowedVariables: ['medication_name'],
      requiredVariables: ['medication_name'],
    })

    expect(issues).toContainEqual(
      expect.objectContaining({
        code: 'unknown_variable',
        field: 'variables',
        message: expect.stringContaining('progress'),
      }),
    )
  })

  it('rejects required variables that are absent from the copy', () => {
    expect(
      lintCoachTemplate({
        ...validTemplate,
        body: '{{name}}, continue acompanhando seu progresso.',
      }),
    ).toContainEqual(
      expect.objectContaining({
        code: 'missing_required_variable',
        field: 'variables',
        message: expect.stringContaining('block_progress_percent'),
      }),
    )
  })

  it('rejects control characters and channel lengths', () => {
    const issues = lintCoachTemplate({
      ...validTemplate,
      channel: 'push',
      title: 'T'.repeat(61),
      body: `Progresso\u0000 ${'x'.repeat(181)}`,
    })

    expect(issues).toEqual(
      expect.arrayContaining([
        expect.objectContaining({ code: 'control_character', field: 'body' }),
        expect.objectContaining({ code: 'channel_length', field: 'title' }),
        expect.objectContaining({ code: 'channel_length', field: 'body' }),
      ]),
    )
  })

  it.each([
    ['pt-BR', 'Você fracassou e deveria sentir vergonha. O resultado é garantido.'],
    ['pt-BR', 'Você foi preguiçoso hoje.'],
    ['en-US', 'You failed because you are lazy. Weight loss is guaranteed.'],
  ] as const)('rejects unsafe %s language', (locale, body) => {
    const issues = lintCoachTemplate({
      ...validTemplate,
      locale,
      body,
      requiredVariables: [],
    })

    expect(issues).toContainEqual(expect.objectContaining({ code: 'unsafe_language' }))
  })
})

describe('coach template rendering', () => {
  it('renders plain text after sanitizing user-originated values', () => {
    expect(
      renderCoachTemplate(validTemplate, {
        name: '  Ana\u0000\nSilva {{ignored}}  ',
        block_progress_percent: 72,
      }),
    ).toEqual({
      title: null,
      subject: null,
      body: 'Ana Silva ignored, seu progresso chegou a 72%.',
    })
  })

  it('limits a substituted string to 200 characters', () => {
    const rendered = renderCoachTemplate(
      {
        ...validTemplate,
        body: '{{name}}',
        allowedVariables: ['name'],
        requiredVariables: ['name'],
      },
      { name: 'a'.repeat(250) },
    )

    expect(rendered.body).toHaveLength(200)
  })

  it('removes every forbidden control character from a substituted value', () => {
    const rendered = renderCoachTemplate(
      {
        ...validTemplate,
        body: '{{name}}',
        allowedVariables: ['name'],
        requiredVariables: ['name'],
      },
      { name: 'A\u0000B\u0001C\u007fD' },
    )

    expect(rendered.body).toBe('ABCD')
  })

  it('fails closed when a required value is unavailable', () => {
    expect(() => renderCoachTemplate(validTemplate, { name: 'Ana' })).toThrow(
      'Missing required coach template variable: block_progress_percent',
    )
  })
})

describe('coach message variant rotation', () => {
  const neverUsed = [
    { id: 'version-c', variant: 3 as const, lastUsedAt: null },
    { id: 'version-a', variant: 1 as const, lastUsedAt: null },
    { id: 'version-b', variant: 2 as const, lastUsedAt: null },
  ]

  it('uses a stable id tie-break for never-used variants', () => {
    expect(chooseLeastRecentlyUsedVariant(neverUsed, null).id).toBe('version-a')
  })

  it('does not immediately repeat when another variant exists', () => {
    expect(chooseLeastRecentlyUsedVariant(neverUsed, 'version-a').id).toBe('version-b')
  })

  it('chooses the least recently used variant after exhaustion', () => {
    const selected = chooseLeastRecentlyUsedVariant(
      [
        { id: 'version-a', variant: 1 as const, lastUsedAt: '2026-07-20T12:00:00.000Z' },
        { id: 'version-b', variant: 2 as const, lastUsedAt: '2026-07-18T12:00:00.000Z' },
        { id: 'version-c', variant: 3 as const, lastUsedAt: '2026-07-19T12:00:00.000Z' },
      ],
      'version-a',
    )

    expect(selected.id).toBe('version-b')
  })

  it('rejects an empty candidate set', () => {
    expect(() => chooseLeastRecentlyUsedVariant([], null)).toThrow(
      'No eligible coach message variants',
    )
  })
})
