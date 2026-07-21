import { describe, expect, it } from 'vitest'
import type { CoachCatalogEntry } from '@/lib/coach-messages/admin-service'
import {
  describePreviewState,
  groupCatalogEntries,
  packControlAvailability,
  serializeCoachCatalogFilters,
  summarizeValidationIssues,
} from './catalog-presenter'

function entry(variant: 1 | 2 | 3): CoachCatalogEntry {
  return {
    packId: '00000000-0000-0000-0000-000000000701',
    packSlug: 'bodyflow-ui-test',
    packLabel: 'BodyFlow UI test',
    packStatus: 'draft',
    templateId: `00000000-0000-0000-0000-00000000071${variant}`,
    templateKey: `focus.hydration.push.pt-br.v${variant}`,
    personality: 'focus',
    context: 'hydration',
    channel: 'push',
    locale: 'pt-BR',
    variant,
    allowedVariables: ['name', 'water_remaining_ml'],
    requiredVariables: ['name', 'water_remaining_ml'],
    templateVersionId: `00000000-0000-0000-0000-00000000072${variant}`,
    version: 1,
    title: `Água ${variant}`,
    subject: null,
    body: `{{name}}, variante ${variant}: {{water_remaining_ml}} ml restantes.`,
    versionStatus: 'draft',
    provenance: 'human',
    createdAt: '2026-07-20T12:00:00.000Z',
  }
}

describe('coach catalog presenter', () => {
  it('serializes only active URL filters in stable order', () => {
    expect(
      serializeCoachCatalogFilters({
        pack: '00000000-0000-0000-0000-000000000701',
        status: 'all',
        personality: 'focus',
        context: 'all',
        channel: 'push',
        locale: 'pt-BR',
      }),
    ).toBe('pack=00000000-0000-0000-0000-000000000701&personality=focus&channel=push&locale=pt-BR')
  })

  it('groups and orders all three variants for one operational row', () => {
    const groups = groupCatalogEntries([entry(3), entry(1), entry(2)])

    expect(groups).toHaveLength(1)
    expect(groups[0]).toMatchObject({
      key: 'focus|hydration|push|pt-BR',
      personality: 'focus',
      context: 'hydration',
      channel: 'push',
      locale: 'pt-BR',
    })
    expect(groups[0]?.variants.map((candidate) => candidate.variant)).toEqual([1, 2, 3])
  })

  it('disables lifecycle commands for editors while preserving draft editing', () => {
    expect(packControlAvailability('draft', 'content_editor')).toEqual({
      canEdit: true,
      canAssist: true,
      canClone: false,
      canValidate: true,
      canSchedule: false,
      canActivate: false,
      canArchive: false,
      canRollback: false,
    })
    expect(packControlAvailability('draft', 'master_admin')).toMatchObject({
      canEdit: true,
      canClone: false,
      canSchedule: true,
      canActivate: true,
      canArchive: true,
    })
    expect(packControlAvailability('active', 'master_admin')).toMatchObject({ canClone: true })
  })

  it('maps preview states to concise operational labels', () => {
    expect(describePreviewState('idle')).toEqual({ label: 'Não gerada', tone: 'muted' })
    expect(describePreviewState('loading')).toEqual({ label: 'Gerando', tone: 'pending' })
    expect(describePreviewState('ready')).toEqual({ label: 'Pronta', tone: 'success' })
    expect(describePreviewState('error')).toEqual({ label: 'Falhou', tone: 'danger' })
  })

  it('summarizes validation issues without dropping actionable detail', () => {
    const result = summarizeValidationIssues([
      { code: 'snapshot_mismatch', message: 'Snapshot mudou' },
      { code: 'duplicate_variant', message: 'Variante repetida', variant: 3 },
      { code: 'duplicate_variant', message: 'Outra variante repetida', variant: 2 },
    ])

    expect(result.total).toBe(3)
    expect(result.byCode).toEqual([
      { code: 'duplicate_variant', count: 2 },
      { code: 'snapshot_mismatch', count: 1 },
    ])
    expect(result.messages).toEqual([
      'Snapshot mudou',
      'Variante repetida',
      'Outra variante repetida',
    ])
  })
})
