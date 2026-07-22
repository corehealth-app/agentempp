import { describe, expect, it } from 'vitest'
import {
  type AdminRole,
  CONTENT_ADMIN_ROLES,
  CONTENT_AUTHOR_ROLES,
  CONTENT_MODULE_ROLES,
  CONTENT_PUBLISH_ROLES,
  CONTENT_REVIEW_ROLES,
  hasAdminRole,
} from './admin-rbac'

describe('content admin RBAC', () => {
  it('preserves the coach-message CONTENT_ADMIN_ROLES contract literally', () => {
    expect(CONTENT_ADMIN_ROLES).toEqual(['content_editor', 'master_admin'])
  })

  it('separates module read, author, review, and publish responsibilities', () => {
    expect(CONTENT_MODULE_ROLES).toEqual(['content_editor', 'nutrition_admin', 'master_admin'])
    expect(CONTENT_AUTHOR_ROLES).toEqual(['content_editor'])
    expect(CONTENT_REVIEW_ROLES).toEqual(['nutrition_admin'])
    expect(CONTENT_PUBLISH_ROLES).toEqual(['master_admin'])

    const roles: AdminRole[] = [
      'support',
      'content_editor',
      'nutrition_admin',
      'operations_admin',
      'master_admin',
    ]
    expect(roles.map((role) => hasAdminRole(role, CONTENT_MODULE_ROLES))).toEqual([
      false,
      true,
      true,
      false,
      true,
    ])
    expect(roles.map((role) => hasAdminRole(role, CONTENT_AUTHOR_ROLES))).toEqual([
      false,
      true,
      false,
      false,
      false,
    ])
    expect(roles.map((role) => hasAdminRole(role, CONTENT_REVIEW_ROLES))).toEqual([
      false,
      false,
      true,
      false,
      false,
    ])
    expect(roles.map((role) => hasAdminRole(role, CONTENT_PUBLISH_ROLES))).toEqual([
      false,
      false,
      false,
      false,
      true,
    ])
  })
})
