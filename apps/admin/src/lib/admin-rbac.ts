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

export function isAdminRole(value: string): value is AdminRole {
  return (ADMIN_ROLES as readonly string[]).includes(value)
}

export function hasAdminRole(
  value: string | null | undefined,
  allowed: readonly AdminRole[],
): value is AdminRole {
  return value !== null && value !== undefined && isAdminRole(value) && allowed.includes(value)
}
