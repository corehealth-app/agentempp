'use server'

import { revalidatePath } from 'next/cache'
import { isAdminRole } from '@/lib/admin-rbac'
import {
  type CoachCatalogFilters,
  createSupabaseCoachCatalogRepository,
} from '@/lib/coach-messages/admin-service'
import { createOpenRouterAssistedRewriteProvider } from '@/lib/coach-messages/assisted-rewrite'
import { createClient, createServiceClient } from '@/lib/supabase/server'
import {
  type CoachMessageAction,
  type CoachMessageActionDependencies,
  executeCoachMessageAction,
} from './actions-core'

function productionDependencies(): CoachMessageActionDependencies {
  return {
    async loadAuthenticatedAdmin() {
      const supabase = await createClient()
      const {
        data: { user },
        error: authError,
      } = await supabase.auth.getUser()
      if (authError || !user) throw new Error('Não autenticado')

      const authenticatedRoleReader = supabase as unknown as {
        from(table: 'admin_users'): {
          select(columns: 'id, role'): {
            eq(
              column: 'id',
              value: string,
            ): {
              maybeSingle(): Promise<{
                data: { id: string; role: string } | null
                error: { message: string } | null
              }>
            }
          }
        }
      }
      const { data: admin, error: roleError } = await authenticatedRoleReader
        .from('admin_users')
        .select('id, role')
        .eq('id', user.id)
        .maybeSingle()
      if (roleError || !admin || !isAdminRole(admin.role)) throw new Error('Acesso negado')
      return { id: admin.id, role: admin.role }
    },

    createServiceContext() {
      const client = createServiceClient()
      return {
        repository: createSupabaseCoachCatalogRepository(client),
        async getOpenRouterCredential() {
          const { data, error } = await client
            .from('service_credentials')
            .select('value')
            .eq('service', 'openrouter')
            .eq('key_name', 'api_key')
            .eq('is_active', true)
            .maybeSingle()
          if (error) throw new Error('Não foi possível carregar a credencial do provedor')
          return data?.value ?? process.env.OPENROUTER_API_KEY ?? null
        },
        async recordAssistedTelemetry(input) {
          const { error } = await client.from('audit_log').insert({
            actor_id: input.actorId,
            action: `coach_assisted_rewrite.${input.status}`,
            entity: 'coach_message_group',
            entity_id: `${input.packId}:${input.groupKey}`,
            after: {
              pack_id: input.packId,
              group_key: input.groupKey,
              status: input.status,
              model: input.model,
              prompt_tokens: input.promptTokens,
              completion_tokens: input.completionTokens,
              cost_usd: input.costUsd,
              latency_ms: input.latencyMs,
            },
          })
          if (error) throw new Error('Não foi possível registrar a telemetria editorial')
        },
      }
    },

    createAssistedProvider: createOpenRouterAssistedRewriteProvider,
  }
}

async function runProductionAction(action: CoachMessageAction, revalidate = false) {
  try {
    const data = await executeCoachMessageAction(action, productionDependencies())
    if (revalidate) revalidatePath('/settings/coach-messages')
    return { ok: true as const, data }
  } catch (error) {
    return {
      ok: false as const,
      error: error instanceof Error ? error.message : 'Falha inesperada no catálogo',
    }
  }
}

export async function listCoachContentPacksAction() {
  return runProductionAction({ type: 'listPacks' })
}

export async function listCoachCatalogAction(input: CoachCatalogFilters) {
  return runProductionAction({ type: 'listCatalog', input })
}

export async function listCoachTemplateVersionsAction(input: { templateId: string }) {
  return runProductionAction({ type: 'listTemplateVersions', input })
}

export async function getCoachUsageSummaryAction() {
  return runProductionAction({ type: 'getUsageSummary' })
}

export async function previewCoachDraftAction(
  input: Extract<CoachMessageAction, { type: 'previewDraft' }>['input'],
) {
  return runProductionAction({ type: 'previewDraft', input })
}

export async function reviseCoachDraftAction(
  input: Extract<CoachMessageAction, { type: 'reviseDraft' }>['input'],
) {
  return runProductionAction({ type: 'reviseDraft', input }, true)
}

export async function cloneCoachContentPackAction(
  input: Extract<CoachMessageAction, { type: 'cloneActivePack' }>['input'],
) {
  return runProductionAction({ type: 'cloneActivePack', input }, true)
}

export async function validateCoachContentPackAction(input: { packId: string }) {
  return runProductionAction({ type: 'validatePack', input })
}

export async function scheduleCoachContentPackAction(
  input: Extract<CoachMessageAction, { type: 'schedulePack' }>['input'],
) {
  return runProductionAction({ type: 'schedulePack', input }, true)
}

export async function activateCoachContentPackAction(input: { packId: string }) {
  return runProductionAction({ type: 'activatePack', input }, true)
}

export async function archiveCoachContentPackAction(input: { packId: string }) {
  return runProductionAction({ type: 'archivePack', input }, true)
}

export async function rollbackCoachContentPackAction(input: { packId: string }) {
  return runProductionAction({ type: 'rollbackPack', input }, true)
}

export async function requestCoachAssistedRewriteAction(
  input: Extract<CoachMessageAction, { type: 'assistedRewrite' }>['input'],
) {
  return runProductionAction({ type: 'assistedRewrite', input }, true)
}
