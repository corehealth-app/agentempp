'use server'

import { revalidatePath } from 'next/cache'
import { isAdminRole } from '@/lib/admin-rbac'
import { createContentAdminService } from '@/lib/content/admin-service'
import {
  type ContentSupabaseClient,
  createSupabaseContentAdminDependencies,
} from '@/lib/content/supabase-repository'
import { createClient, createServiceClient } from '@/lib/supabase/server'
import { ContentActionAuthError, runContentAdminAction } from './actions-core'

function productionDependencies() {
  return {
    async loadAuthenticatedAdmin() {
      const supabase = await createClient()
      const {
        data: { user },
        error: authError,
      } = await supabase.auth.getUser()
      if (authError || !user) throw new ContentActionAuthError('unauthenticated')

      const roleReader = supabase as unknown as {
        from(table: 'admin_users'): {
          select(columns: 'id, role'): {
            eq(
              column: 'id',
              value: string,
            ): {
              maybeSingle(): Promise<{
                data: { id: string; role: string } | null
                error: unknown
              }>
            }
          }
        }
      }
      const { data: admin, error: roleError } = await roleReader
        .from('admin_users')
        .select('id, role')
        .eq('id', user.id)
        .maybeSingle()
      if (roleError || !admin || !isAdminRole(admin.role)) {
        throw new ContentActionAuthError('forbidden')
      }
      return { id: admin.id, role: admin.role }
    },

    createService() {
      const client = createServiceClient() as unknown as ContentSupabaseClient
      return createContentAdminService(createSupabaseContentAdminDependencies(client))
    },

    async revalidatePath(path: string, type?: 'page') {
      if (type) revalidatePath(path, type)
      else revalidatePath(path)
    },
  }
}

async function run(action: unknown) {
  return runContentAdminAction(action, productionDependencies())
}

export async function listContentPublicationsAction(input: unknown) {
  return run({ type: 'list', input })
}

export async function getContentPublicationAction(input: unknown) {
  return run({ type: 'get', input })
}

export async function createContentPublicationAction(input: unknown) {
  return run({ type: 'createPublication', input })
}

export async function createContentDraftAction(input: unknown) {
  return run({ type: 'createDraft', input })
}

export async function saveContentDraftAction(input: unknown) {
  return run({ type: 'saveDraft', input })
}

export async function submitContentVersionAction(input: unknown) {
  return run({ type: 'submit', input })
}

export async function reviewContentVersionAction(input: unknown) {
  return run({ type: 'review', input })
}

export async function publishContentVersionAction(input: unknown) {
  return run({ type: 'publish', input })
}

export async function archiveContentPublicationAction(input: unknown) {
  return run({ type: 'archive', input })
}

export async function createContentCoverAction(input: unknown) {
  return run({ type: 'createCover', input })
}

export async function completeContentCoverAction(input: unknown) {
  return run({ type: 'completeCover', input })
}

export async function deleteContentCoverAction(input: unknown) {
  return run({ type: 'deleteCover', input })
}
