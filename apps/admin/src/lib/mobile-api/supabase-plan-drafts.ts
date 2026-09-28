import type { ServiceClient } from '@mpp/db'
import { createSupabasePlanDraftRepository, type PlanDraftDependencies } from './plan-draft-service'
import { createSupabaseMediaDependencies } from './supabase-media'

export function createSupabasePlanDraftDependencies(supabase: ServiceClient): PlanDraftDependencies {
  const media = createSupabaseMediaDependencies(supabase)
  return {
    repository: createSupabasePlanDraftRepository(supabase),
    media: media.repository,
    events: media.events,
  }
}
