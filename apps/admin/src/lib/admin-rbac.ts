export const ADMIN_ROLES = [
  'support',
  'content_editor',
  'nutrition_admin',
  'operations_admin',
  'master_admin',
] as const

export type AdminRole = (typeof ADMIN_ROLES)[number]

export const MASTER_ADMIN_ROLES = ['master_admin'] as const satisfies readonly AdminRole[]
export const CONTENT_ADMIN_ROLES = [
  'content_editor',
  'master_admin',
] as const satisfies readonly AdminRole[]
export const CONTENT_AUTHOR_ROLES = ['content_editor'] as const satisfies readonly AdminRole[]
export const CONTENT_REVIEW_ROLES = ['nutrition_admin'] as const satisfies readonly AdminRole[]
export const CONTENT_PUBLISH_ROLES = ['master_admin'] as const satisfies readonly AdminRole[]
export const CONTENT_MODULE_ROLES = [
  'content_editor',
  'nutrition_admin',
  'master_admin',
] as const satisfies readonly AdminRole[]
export const PATIENT_SUPPORT_ROLES = [
  'support',
  'nutrition_admin',
  'operations_admin',
  'master_admin',
] as const satisfies readonly AdminRole[]
export const OPERATIONS_ADMIN_ROLES = [
  'operations_admin',
  'master_admin',
] as const satisfies readonly AdminRole[]
export const AI_PLAYGROUND_ROLES = [
  'content_editor',
  'nutrition_admin',
  'master_admin',
] as const satisfies readonly AdminRole[]

/**
 * Publishing an approved content version: master_admin, or a content_editor
 * the database marks with `can_publish_content` (the editorial owner who also
 * publishes; review by an independent nutrition_admin stays mandatory).
 * Archiving stays master_admin only.
 */
export function canPublishContent(role: AdminRole, canPublishContentFlag: boolean): boolean {
  return (
    (CONTENT_PUBLISH_ROLES as readonly string[]).includes(role) ||
    (role === 'content_editor' && canPublishContentFlag)
  )
}

export function isAdminRole(value: string): value is AdminRole {
  return (ADMIN_ROLES as readonly string[]).includes(value)
}

export function hasAdminRole(
  value: string | null | undefined,
  allowed: readonly AdminRole[],
): value is AdminRole {
  return value !== null && value !== undefined && isAdminRole(value) && allowed.includes(value)
}
