import type { AdminRole } from '@/lib/admin-rbac'
import type {
  CoachCatalogEntry,
  CoachCatalogValidationIssue,
  CoachPackStatus,
} from '@/lib/coach-messages/admin-service'

export interface CoachCatalogFilterState {
  pack?: string
  status?: string
  personality?: string
  context?: string
  channel?: string
  locale?: string
}

const FILTER_KEYS = ['pack', 'status', 'personality', 'context', 'channel', 'locale'] as const

export function serializeCoachCatalogFilters(filters: CoachCatalogFilterState): string {
  const params = new URLSearchParams()
  for (const key of FILTER_KEYS) {
    const value = filters[key]
    if (value && value !== 'all') params.set(key, value)
  }
  return params.toString()
}

export interface CoachCatalogGroup {
  key: string
  personality: CoachCatalogEntry['personality']
  context: CoachCatalogEntry['context']
  channel: CoachCatalogEntry['channel']
  locale: CoachCatalogEntry['locale']
  variants: CoachCatalogEntry[]
}

export function groupCatalogEntries(entries: readonly CoachCatalogEntry[]): CoachCatalogGroup[] {
  const groups = new Map<string, CoachCatalogGroup>()
  for (const entry of entries) {
    const key = [entry.personality, entry.context, entry.channel, entry.locale].join('|')
    const group = groups.get(key) ?? {
      key,
      personality: entry.personality,
      context: entry.context,
      channel: entry.channel,
      locale: entry.locale,
      variants: [],
    }
    group.variants.push(entry)
    groups.set(key, group)
  }

  return [...groups.values()]
    .map((group) => ({
      ...group,
      variants: [...group.variants].sort((left, right) => left.variant - right.variant),
    }))
    .sort((left, right) => left.key.localeCompare(right.key))
}

export interface PackControlAvailability {
  canEdit: boolean
  canAssist: boolean
  canClone: boolean
  canValidate: boolean
  canSchedule: boolean
  canActivate: boolean
  canArchive: boolean
  canRollback: boolean
}

export function packControlAvailability(
  status: CoachPackStatus,
  role: AdminRole,
): PackControlAvailability {
  const canEditContent = role === 'content_editor' || role === 'master_admin'
  const canManageLifecycle = role === 'master_admin'
  return {
    canEdit: canEditContent && status === 'draft',
    canAssist: canEditContent && status === 'draft',
    canClone: canEditContent && status === 'active',
    canValidate: canEditContent && status === 'draft',
    canSchedule: canManageLifecycle && status === 'draft',
    canActivate: canManageLifecycle && (status === 'draft' || status === 'scheduled'),
    canArchive: canManageLifecycle && (status === 'draft' || status === 'scheduled'),
    canRollback: canManageLifecycle && status === 'archived',
  }
}

export type PreviewState = 'idle' | 'loading' | 'ready' | 'error'

export function describePreviewState(state: PreviewState): {
  label: string
  tone: 'muted' | 'pending' | 'success' | 'danger'
} {
  switch (state) {
    case 'idle':
      return { label: 'Não gerada', tone: 'muted' }
    case 'loading':
      return { label: 'Gerando', tone: 'pending' }
    case 'ready':
      return { label: 'Pronta', tone: 'success' }
    case 'error':
      return { label: 'Falhou', tone: 'danger' }
  }
}

export function summarizeValidationIssues(issues: readonly CoachCatalogValidationIssue[]): {
  total: number
  byCode: Array<{ code: string; count: number }>
  messages: string[]
} {
  const counts = new Map<string, number>()
  for (const issue of issues) counts.set(issue.code, (counts.get(issue.code) ?? 0) + 1)
  return {
    total: issues.length,
    byCode: [...counts.entries()]
      .map(([code, count]) => ({ code, count }))
      .sort((left, right) => left.code.localeCompare(right.code)),
    messages: issues.map((issue) => issue.message),
  }
}
