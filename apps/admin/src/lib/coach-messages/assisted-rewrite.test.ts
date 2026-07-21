import { describe, expect, it, vi } from 'vitest'
import {
  ASSISTED_REWRITE_MAX_TOKENS,
  ASSISTED_REWRITE_MODEL,
  type AssistedRewriteProvider,
  type AssistedRewriteRequest,
  type CoachCatalogVariant,
  generateAssistedCoachRewrite,
} from './assisted-rewrite'

function sourceVariant(variant: 1 | 2 | 3): CoachCatalogVariant {
  const suffix = ['um', 'dois', 'três'][variant - 1]
  return {
    variant,
    personality: 'focus',
    context: 'hydration',
    locale: 'pt-BR',
    renditions: {
      in_app: {
        templateId: `00000000-0000-0000-0000-0000000001${variant}1`,
        templateVersionId: `00000000-0000-0000-0000-0000000002${variant}1`,
        channel: 'in_app',
        title: null,
        subject: null,
        body: `{{name}}, hidratação ${suffix}: faltam {{water_remaining_ml}} ml.`,
        allowedVariables: ['name', 'water_remaining_ml'],
        requiredVariables: ['name', 'water_remaining_ml'],
      },
      push: {
        templateId: `00000000-0000-0000-0000-0000000001${variant}2`,
        templateVersionId: `00000000-0000-0000-0000-0000000002${variant}2`,
        channel: 'push',
        title: `Hidratação ${suffix}`,
        subject: null,
        body: `{{name}}, ainda faltam {{water_remaining_ml}} ml.`,
        allowedVariables: ['name', 'water_remaining_ml'],
        requiredVariables: ['name', 'water_remaining_ml'],
      },
      email: {
        templateId: `00000000-0000-0000-0000-0000000001${variant}3`,
        templateVersionId: `00000000-0000-0000-0000-0000000002${variant}3`,
        channel: 'email',
        title: null,
        subject: `Hidratação ${suffix}`,
        body: `Olá, {{name}}. O exemplo indica {{water_remaining_ml}} ml restantes.`,
        allowedVariables: ['name', 'water_remaining_ml'],
        requiredVariables: ['name', 'water_remaining_ml'],
      },
    },
  }
}

function request(): AssistedRewriteRequest {
  return {
    packId: '00000000-0000-0000-0000-000000000401',
    personality: 'focus',
    context: 'hydration',
    locale: 'pt-BR',
    sourceVersions: [sourceVariant(1), sourceVariant(2), sourceVariant(3)],
  }
}

function validGeneratedJson(): string {
  return JSON.stringify({
    variants: [1, 2, 3].map((variant) => ({
      variant,
      renditions: {
        in_app: {
          title: null,
          subject: null,
          body: `{{name}}, foco ${variant}: complete os {{water_remaining_ml}} ml restantes com calma.`,
        },
        push: {
          title: `Água em foco ${variant}`,
          subject: null,
          body: `{{name}}, são {{water_remaining_ml}} ml para completar sua meta.`,
        },
        email: {
          title: null,
          subject: `Seu plano de hidratação ${variant}`,
          body: `Olá, {{name}}. Organize os {{water_remaining_ml}} ml restantes ao longo do dia.`,
        },
      },
    })),
  })
}

function provider(content = validGeneratedJson()): AssistedRewriteProvider {
  return {
    complete: vi.fn(async () => ({
      content,
      promptTokens: 520,
      completionTokens: 610,
      costUsd: 0.0012,
      model: ASSISTED_REWRITE_MODEL,
      latencyMs: 340,
    })),
  }
}

describe('bounded coach catalog assisted rewrite', () => {
  it('uses the bounded JSON-only model contract and excludes technical identifiers', async () => {
    const input = request()
    const llm = provider()

    const result = await generateAssistedCoachRewrite(input, llm)

    expect(result.variants).toHaveLength(3)
    expect(result.model).toBe(ASSISTED_REWRITE_MODEL)
    expect(llm.complete).toHaveBeenCalledOnce()
    const call = vi.mocked(llm.complete).mock.calls[0]?.[0]
    expect(call).toMatchObject({
      model: ASSISTED_REWRITE_MODEL,
      temperature: 0.3,
      maxTokens: ASSISTED_REWRITE_MAX_TOKENS,
      responseFormat: { type: 'json_object' },
    })
    expect(call?.temperature).toBeLessThanOrEqual(0.4)
    const serialized = JSON.stringify(call)
    expect(serialized).not.toContain(input.packId)
    expect(serialized).not.toContain(input.sourceVersions[0].renditions.in_app.templateId)
    expect(serialized).not.toContain(input.sourceVersions[0].renditions.in_app.templateVersionId)
  })

  it('preserves source placeholders and immutable rendition identity', async () => {
    const input = request()

    const result = await generateAssistedCoachRewrite(input, provider())

    expect(result.variants[0].renditions.in_app).toMatchObject({
      templateId: input.sourceVersions[0].renditions.in_app.templateId,
      templateVersionId: input.sourceVersions[0].renditions.in_app.templateVersionId,
      channel: 'in_app',
      allowedVariables: ['name', 'water_remaining_ml'],
      requiredVariables: ['name', 'water_remaining_ml'],
    })
    expect(result.variants[0].renditions.in_app.body).toContain('{{name}}')
    expect(result.variants[0].renditions.in_app.body).toContain('{{water_remaining_ml}}')
  })

  it('rejects a request that mixes personality, context, locale, variants, or channels', async () => {
    const input = request()
    input.sourceVersions[1].renditions.push.channel = 'in_app'

    await expect(generateAssistedCoachRewrite(input, provider())).rejects.toThrow(
      'exactly one personality, context, locale group',
    )
  })

  it('rejects non-JSON provider output', async () => {
    await expect(
      generateAssistedCoachRewrite(request(), provider('Aqui estão as sugestões.')),
    ).rejects.toThrow('valid JSON')
  })

  it('rejects generated copy that changes placeholders', async () => {
    const generated = JSON.parse(validGeneratedJson())
    generated.variants[0].renditions.in_app.body = '{{name}}, beba água agora.'

    await expect(
      generateAssistedCoachRewrite(request(), provider(JSON.stringify(generated))),
    ).rejects.toThrow('preserve placeholders')
  })

  it('rejects repeated variants before any draft can be stored', async () => {
    const generated = JSON.parse(validGeneratedJson())
    generated.variants[2].renditions.push = generated.variants[1].renditions.push

    await expect(
      generateAssistedCoachRewrite(request(), provider(JSON.stringify(generated))),
    ).rejects.toThrow('three distinct variants')
  })

  it('rejects unsafe generated language through the shared catalog linter', async () => {
    const generated = JSON.parse(validGeneratedJson())
    generated.variants[0].renditions.in_app.body =
      'Sem desculpas, {{name}}: faltam {{water_remaining_ml}} ml.'

    await expect(
      generateAssistedCoachRewrite(request(), provider(JSON.stringify(generated))),
    ).rejects.toThrow('unsafe_language')
  })

  it('fails closed when the provider fails', async () => {
    const llm: AssistedRewriteProvider = {
      complete: vi.fn(async () => {
        throw new Error('provider unavailable')
      }),
    }

    await expect(generateAssistedCoachRewrite(request(), llm)).rejects.toThrow(
      'provider unavailable',
    )
  })
})
