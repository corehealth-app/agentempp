import { readFile } from 'node:fs/promises'
import {
  type CoachMessageChannel,
  coachMessageChannelSchema,
  coachMessageContextSchema,
  coachMessageLocaleSchema,
  coachPersonalitySchema,
} from '@mpp/core'
import { z } from 'zod'

const inAppRenditionSchema = z.object({ body: z.string().min(1) }).strict()
const pushRenditionSchema = z.object({ title: z.string().min(1), body: z.string().min(1) }).strict()
const emailRenditionSchema = z
  .object({ subject: z.string().min(1), body: z.string().min(1) })
  .strict()

const catalogVariantSchema = z
  .object({
    variant: z.union([z.literal(1), z.literal(2), z.literal(3)]),
    required_variables: z.array(z.string().regex(/^[a-z][a-z0-9_]*$/)),
    renditions: z
      .object({
        in_app: inAppRenditionSchema,
        push: pushRenditionSchema,
        email: emailRenditionSchema,
      })
      .strict(),
  })
  .strict()

const catalogGroupSchema = z
  .object({
    personality: coachPersonalitySchema,
    context: coachMessageContextSchema,
    locale: coachMessageLocaleSchema,
    variants: z.array(catalogVariantSchema).length(3),
  })
  .strict()

export const baselineCoachCatalogSchema = z
  .object({
    schema_version: z.literal('bodyflow.coach-catalog.v1'),
    pack: z
      .object({
        slug: z.literal('bodyflow-baseline-v1'),
        label: z.string().min(1).max(160),
      })
      .strict(),
    groups: z.array(catalogGroupSchema),
  })
  .strict()

export type BaselineCoachCatalog = z.infer<typeof baselineCoachCatalogSchema>

export interface FlattenedCoachCatalogRendition {
  personality: BaselineCoachCatalog['groups'][number]['personality']
  context: BaselineCoachCatalog['groups'][number]['context']
  channel: CoachMessageChannel
  locale: BaselineCoachCatalog['groups'][number]['locale']
  variant: 1 | 2 | 3
  requiredVariables: string[]
  title: string | null
  subject: string | null
  body: string
}

const baselineCatalogUrl = new URL(
  '../../../../../content/coach-messages/bodyflow-baseline-v1.json',
  import.meta.url,
)

export function parseBaselineCoachCatalog(value: unknown): BaselineCoachCatalog {
  return baselineCoachCatalogSchema.parse(value)
}

export async function loadBaselineCoachCatalog(): Promise<BaselineCoachCatalog> {
  const source = await readFile(baselineCatalogUrl, 'utf8')
  return parseBaselineCoachCatalog(JSON.parse(source) as unknown)
}

export function normalizeCoachCopy(value: string): string {
  return value
    .normalize('NFKD')
    .replace(/\p{M}/gu, '')
    .toLocaleLowerCase('en-US')
    .replace(/[^a-z0-9{}]+/g, ' ')
    .trim()
    .replace(/\s+/g, ' ')
}

export function flattenCoachCatalog(
  catalog: BaselineCoachCatalog,
): FlattenedCoachCatalogRendition[] {
  return catalog.groups.flatMap((group) =>
    group.variants.flatMap((variant) =>
      coachMessageChannelSchema.options.map((channel) => {
        const rendition = variant.renditions[channel]
        return {
          personality: group.personality,
          context: group.context,
          channel,
          locale: group.locale,
          variant: variant.variant,
          requiredVariables: variant.required_variables,
          title: channel === 'push' ? variant.renditions.push.title : null,
          subject: channel === 'email' ? variant.renditions.email.subject : null,
          body: rendition.body,
        }
      }),
    ),
  )
}
