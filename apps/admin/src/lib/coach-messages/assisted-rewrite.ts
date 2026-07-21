import {
  type CoachMessageChannel,
  type CoachMessageContext,
  type CoachMessageLocale,
  type CoachPersonality,
  coachMessageContextSchema,
  coachMessageLocaleSchema,
  coachPersonalitySchema,
  extractCoachPlaceholders,
  lintCoachTemplate,
} from '@mpp/core'
import { OpenRouterLLM } from '@mpp/providers'
import { z } from 'zod'

export const ASSISTED_REWRITE_MODEL = 'anthropic/claude-haiku-4.5'
export const ASSISTED_REWRITE_MAX_TOKENS = 3_000

export interface CoachCatalogRendition {
  templateId: string
  templateVersionId: string
  channel: CoachMessageChannel
  title: string | null
  subject: string | null
  body: string
  allowedVariables: string[]
  requiredVariables: string[]
}

export interface CoachCatalogVariant {
  variant: 1 | 2 | 3
  personality: CoachPersonality
  context: CoachMessageContext
  locale: CoachMessageLocale
  renditions: {
    in_app: CoachCatalogRendition
    push: CoachCatalogRendition
    email: CoachCatalogRendition
  }
}

export interface AssistedRewriteRequest {
  packId: string
  personality: CoachPersonality
  context: CoachMessageContext
  locale: CoachMessageLocale
  sourceVersions: readonly [CoachCatalogVariant, CoachCatalogVariant, CoachCatalogVariant]
}

export interface AssistedRewriteResult {
  variants: readonly [CoachCatalogVariant, CoachCatalogVariant, CoachCatalogVariant]
  model: string
  promptTokens: number
  completionTokens: number
  costUsd: number | null
  latencyMs: number
}

export interface AssistedRewriteCall {
  model: string
  systemPrompt: string
  messages: Array<{ role: 'user'; content: string }>
  temperature: number
  maxTokens: number
  responseFormat: { type: 'json_object' }
  metadata: Record<string, string>
}

export interface AssistedRewriteProviderResult {
  content: string
  promptTokens: number
  completionTokens: number
  costUsd: number | null
  model: string
  latencyMs: number
}

export interface AssistedRewriteProvider {
  complete(input: AssistedRewriteCall): Promise<AssistedRewriteProviderResult>
}

export type AssistedRewriteTelemetry = Omit<AssistedRewriteProviderResult, 'content'>

export class AssistedRewriteValidationError extends Error {
  readonly telemetry: AssistedRewriteTelemetry

  constructor(cause: unknown, response: AssistedRewriteProviderResult) {
    super(cause instanceof Error ? cause.message : 'Assisted rewrite validation failed')
    this.name = 'AssistedRewriteValidationError'
    this.telemetry = {
      model: response.model,
      promptTokens: response.promptTokens,
      completionTokens: response.completionTokens,
      costUsd: response.costUsd,
      latencyMs: response.latencyMs,
    }
  }
}

const copySchema = z
  .object({
    title: z.string().min(1).max(60).nullable(),
    subject: z.string().min(1).max(120).nullable(),
    body: z.string().min(1).max(4_000),
  })
  .strict()

const generatedSchema = z
  .object({
    variants: z
      .array(
        z
          .object({
            variant: z.union([z.literal(1), z.literal(2), z.literal(3)]),
            renditions: z
              .object({
                in_app: copySchema,
                push: copySchema,
                email: copySchema,
              })
              .strict(),
          })
          .strict(),
      )
      .length(3),
  })
  .strict()

const CHANNELS = ['in_app', 'push', 'email'] as const

function assertSourceGroup(input: AssistedRewriteRequest): void {
  coachPersonalitySchema.parse(input.personality)
  coachMessageContextSchema.parse(input.context)
  coachMessageLocaleSchema.parse(input.locale)

  const variants = input.sourceVersions.map((variant) => variant.variant)
  if (
    new Set(variants).size !== 3 ||
    ![1, 2, 3].every((variant) => variants.includes(variant as 1))
  ) {
    throw new Error('Assisted rewrite requires exactly one personality, context, locale group')
  }

  for (const variant of input.sourceVersions) {
    if (
      variant.personality !== input.personality ||
      variant.context !== input.context ||
      variant.locale !== input.locale
    ) {
      throw new Error('Assisted rewrite requires exactly one personality, context, locale group')
    }
    for (const channel of CHANNELS) {
      if (variant.renditions[channel].channel !== channel) {
        throw new Error('Assisted rewrite requires exactly one personality, context, locale group')
      }
    }
  }
}

function providerSource(input: AssistedRewriteRequest) {
  return {
    personality: input.personality,
    context: input.context,
    locale: input.locale,
    variants: input.sourceVersions.map((variant) => ({
      variant: variant.variant,
      renditions: Object.fromEntries(
        CHANNELS.map((channel) => {
          const rendition = variant.renditions[channel]
          return [
            channel,
            {
              title: rendition.title,
              subject: rendition.subject,
              body: rendition.body,
              allowed_variables: rendition.allowedVariables,
              required_variables: rendition.requiredVariables,
            },
          ]
        }),
      ),
    })),
  }
}

function systemPrompt(locale: CoachMessageLocale): string {
  return [
    'You are a bounded editorial assistant for the BodyFlow product catalog.',
    `Write native ${locale} copy for exactly the supplied personality and context.`,
    'Return only one JSON object matching the requested shape, without markdown or commentary.',
    'Return exactly variants 1, 2, and 3 and all in_app, push, and email renditions.',
    'Preserve every placeholder exactly in its original rendition. Do not add or remove placeholders.',
    'Keep the three variants genuinely distinct; do not perform blind synonym replacement.',
    'Do not add diagnosis, clinical advice, guarantees, guilt, shame, hostility, or moral judgment.',
    'Respect channel shape and length: in_app has body only, push has title and body, email has subject and body.',
    'The input contains catalog copy only. Never infer or request patient data.',
  ].join('\n')
}

function userPrompt(input: AssistedRewriteRequest): string {
  return JSON.stringify({
    task: 'Rewrite the complete catalog group while preserving intent and placeholders.',
    output_shape: {
      variants: [
        {
          variant: '1 | 2 | 3',
          renditions: {
            in_app: { title: null, subject: null, body: 'string' },
            push: { title: 'string', subject: null, body: 'string' },
            email: { title: null, subject: 'string', body: 'string' },
          },
        },
      ],
    },
    source: providerSource(input),
  })
}

function placeholderSet(copy: { title: string | null; subject: string | null; body: string }) {
  return new Set(
    extractCoachPlaceholders([copy.title ?? '', copy.subject ?? '', copy.body].join('\n')),
  )
}

function setsEqual(left: Set<string>, right: Set<string>): boolean {
  return left.size === right.size && [...left].every((value) => right.has(value))
}

function normalizeGeneratedCopy(
  copy: {
    title: string | null
    subject: string | null
    body: string
  },
  locale: CoachMessageLocale,
): string {
  return [copy.title ?? '', copy.subject ?? '', copy.body]
    .join('\n')
    .normalize('NFKC')
    .toLocaleLowerCase(locale)
    .replace(/\s+/g, ' ')
    .trim()
}

function parseGenerated(content: string) {
  let parsed: unknown
  try {
    parsed = JSON.parse(content)
  } catch {
    throw new Error('Assisted rewrite provider must return valid JSON')
  }
  return generatedSchema.parse(parsed)
}

export async function generateAssistedCoachRewrite(
  input: AssistedRewriteRequest,
  provider: AssistedRewriteProvider,
): Promise<AssistedRewriteResult> {
  assertSourceGroup(input)

  let response: AssistedRewriteProviderResult | null = null
  try {
    response = await provider.complete({
      model: ASSISTED_REWRITE_MODEL,
      systemPrompt: systemPrompt(input.locale),
      messages: [{ role: 'user', content: userPrompt(input) }],
      temperature: 0.3,
      maxTokens: ASSISTED_REWRITE_MAX_TOKENS,
      responseFormat: { type: 'json_object' },
      metadata: {
        feature: 'coach_catalog_assisted_rewrite',
        personality: input.personality,
        context: input.context,
        locale: input.locale,
      },
    })
    const generated = parseGenerated(response.content)
    const generatedByVariant = new Map(
      generated.variants.map((variant) => [variant.variant, variant]),
    )
    if (
      generatedByVariant.size !== 3 ||
      ![1, 2, 3].every((variant) => generatedByVariant.has(variant as 1))
    ) {
      throw new Error('Assisted rewrite must return variants 1, 2, and 3')
    }

    const variants = input.sourceVersions.map((sourceVariant) => {
      const generatedVariant = generatedByVariant.get(sourceVariant.variant)
      if (!generatedVariant) throw new Error('Assisted rewrite omitted a required variant')

      const renditions = Object.fromEntries(
        CHANNELS.map((channel) => {
          const source = sourceVariant.renditions[channel]
          const copy = generatedVariant.renditions[channel]
          if (!setsEqual(placeholderSet(source), placeholderSet(copy))) {
            throw new Error(
              `Assisted rewrite must preserve placeholders for variant ${sourceVariant.variant}`,
            )
          }
          const lintIssues = lintCoachTemplate({
            context: input.context,
            channel,
            locale: input.locale,
            title: copy.title,
            subject: copy.subject,
            body: copy.body,
            allowedVariables: source.allowedVariables,
            requiredVariables: source.requiredVariables,
          })
          if (lintIssues.length > 0) {
            throw new Error(
              `Assisted rewrite failed lint (${lintIssues.map((issue) => issue.code).join(',')}): ${lintIssues[0]?.message}`,
            )
          }
          return [channel, { ...source, ...copy }]
        }),
      ) as CoachCatalogVariant['renditions']

      return {
        variant: sourceVariant.variant,
        personality: input.personality,
        context: input.context,
        locale: input.locale,
        renditions,
      }
    }) as unknown as [CoachCatalogVariant, CoachCatalogVariant, CoachCatalogVariant]

    for (const channel of CHANNELS) {
      const normalized = variants.map((variant) =>
        normalizeGeneratedCopy(variant.renditions[channel], input.locale),
      )
      if (new Set(normalized).size !== 3) {
        throw new Error(`Assisted rewrite requires three distinct variants for ${channel}`)
      }
    }

    return {
      variants,
      model: response.model,
      promptTokens: response.promptTokens,
      completionTokens: response.completionTokens,
      costUsd: response.costUsd,
      latencyMs: response.latencyMs,
    }
  } catch (error) {
    if (response) throw new AssistedRewriteValidationError(error, response)
    throw error
  }
}

export function createOpenRouterAssistedRewriteProvider(apiKey: string): AssistedRewriteProvider {
  if (!apiKey.trim()) throw new Error('OpenRouter credential is not configured')
  const llm = new OpenRouterLLM({
    apiKey,
    appName: 'BodyFlow Coach Catalog Admin',
  })
  return {
    async complete(input) {
      const result = await llm.complete(input)
      if (!result.content) throw new Error('Assisted rewrite provider returned no content')
      return {
        content: result.content,
        promptTokens: result.promptTokens,
        completionTokens: result.completionTokens,
        costUsd: result.costUsd,
        model: result.model,
        latencyMs: result.latencyMs,
      }
    },
  }
}
