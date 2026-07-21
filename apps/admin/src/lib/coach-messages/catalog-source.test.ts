import {
  COACH_CONTEXT_ALLOWED_VARIABLES,
  coachMessageChannelSchema,
  coachMessageContextSchema,
  coachMessageLocaleSchema,
  coachPersonalitySchema,
  lintCoachTemplate,
} from '@mpp/core'
import { describe, expect, it } from 'vitest'
import { flattenCoachCatalog, loadBaselineCoachCatalog, normalizeCoachCopy } from './catalog-source'

describe('BodyFlow baseline coach catalog', () => {
  it('contains the exact complete 1,080-rendition matrix', async () => {
    const catalog = await loadBaselineCoachCatalog()
    const renditions = flattenCoachCatalog(catalog)

    expect(catalog.schema_version).toBe('bodyflow.coach-catalog.v1')
    expect(catalog.pack.slug).toBe('bodyflow-baseline-v1')
    expect(catalog.groups).toHaveLength(120)
    expect(catalog.groups.flatMap((group) => group.variants)).toHaveLength(360)
    expect(renditions).toHaveLength(1080)

    const expectedGroups = new Set<string>()
    for (const personality of coachPersonalitySchema.options) {
      for (const context of coachMessageContextSchema.options) {
        for (const locale of coachMessageLocaleSchema.options) {
          expectedGroups.add(`${personality}:${context}:${locale}`)
        }
      }
    }

    expect(
      new Set(
        catalog.groups.map((group) => `${group.personality}:${group.context}:${group.locale}`),
      ),
    ).toEqual(expectedGroups)

    for (const group of catalog.groups) {
      expect(group.variants.map((variant) => variant.variant)).toEqual([1, 2, 3])
      for (const channel of coachMessageChannelSchema.options) {
        const normalized = group.variants.map((variant) =>
          normalizeCoachCopy(variant.renditions[channel].body),
        )
        expect(
          new Set(normalized).size,
          `${group.personality}:${group.context}:${group.locale}:${channel}`,
        ).toBe(3)
      }
    }
  })

  it('passes every rendition through the shared safety and placeholder linter', async () => {
    const catalog = await loadBaselineCoachCatalog()

    for (const rendition of flattenCoachCatalog(catalog)) {
      const allowedVariables = COACH_CONTEXT_ALLOWED_VARIABLES[rendition.context]
      const issues = lintCoachTemplate({
        context: rendition.context,
        channel: rendition.channel,
        locale: rendition.locale,
        title: rendition.title,
        subject: rendition.subject,
        body: rendition.body,
        allowedVariables,
        requiredVariables: rendition.requiredVariables,
      })

      expect(
        issues,
        `${rendition.personality}:${rendition.context}:${rendition.channel}:${rendition.locale}:v${rendition.variant}`,
      ).toEqual([])
    }
  })

  it('keeps channel-specific fields complete and mutually exclusive', async () => {
    const renditions = flattenCoachCatalog(await loadBaselineCoachCatalog())

    for (const rendition of renditions) {
      if (rendition.channel === 'in_app') {
        expect(rendition.title).toBeNull()
        expect(rendition.subject).toBeNull()
      } else if (rendition.channel === 'push') {
        expect(rendition.title?.length).toBeGreaterThan(0)
        expect(rendition.subject).toBeNull()
      } else {
        expect(rendition.title).toBeNull()
        expect(rendition.subject?.length).toBeGreaterThan(0)
      }
    }
  })
})
