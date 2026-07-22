import {
  type RoutineItemType,
  routineHistoryQuerySchema,
  routineItemCreateInputSchema,
  routineItemListQuerySchema,
  routineItemPatchInputSchema,
} from '@mpp/core'
import type { ServiceClient } from '@mpp/db'
import { z } from 'zod'
import { resourceIdSchema } from './contracts'
import { mobileSuccess, readJsonBody } from './http'
import { executeSupabaseIdempotent, hashMobileRequest } from './idempotency'
import {
  createMobileRoute,
  createMobileRouteWithContext,
  type MobileRouteContext,
  type MobileRouteRuntime,
} from './route'
import {
  archiveRoutineItem,
  createRoutineItem,
  listRoutineItemHistory,
  listRoutineItems,
  type RoutineItemServiceDependencies,
  updateRoutineItem,
} from './routine-item-service'
import { createSupabaseRoutineItemDependencies } from './supabase-routine-items'

export interface RoutineItemRouteContext {
  params: Promise<{ id: string }>
}

export interface RoutineRouteDependencies {
  createRoutineItemDependencies(
    supabase: ServiceClient,
    requestId: string,
  ): RoutineItemServiceDependencies
  executeIdempotent: typeof executeSupabaseIdempotent
  now(): Date
}

const defaultDependencies: RoutineRouteDependencies = {
  createRoutineItemDependencies: (supabase, requestId) =>
    createSupabaseRoutineItemDependencies(supabase, { requestId }),
  executeIdempotent: executeSupabaseIdempotent,
  now: () => new Date(),
}

const emptyJsonBodySchema = z.object({}).strict()

function queryRecord(searchParams: URLSearchParams): Record<string, unknown> {
  const result: Record<string, unknown> = {}
  for (const [key, value] of searchParams) {
    const existing = result[key]
    result[key] =
      existing === undefined
        ? value
        : Array.isArray(existing)
          ? [...existing, value]
          : [existing, value]
  }
  return result
}

function serviceDependencies(
  context: MobileRouteContext,
  dependencies: RoutineRouteDependencies,
): RoutineItemServiceDependencies {
  return dependencies.createRoutineItemDependencies(context.supabase, context.requestId)
}

export async function handleRoutineCollectionGet(
  context: MobileRouteContext,
  itemType: RoutineItemType,
  dependencies: RoutineRouteDependencies = defaultDependencies,
): Promise<Response> {
  const query = routineItemListQuerySchema.parse(
    queryRecord(new URL(context.request.url).searchParams),
  )
  return mobileSuccess(
    await listRoutineItems(
      serviceDependencies(context, dependencies),
      context.auth,
      itemType,
      query,
      dependencies.now(),
    ),
    context.requestId,
  )
}

export async function handleRoutineCollectionPost(
  context: MobileRouteContext,
  itemType: RoutineItemType,
  dependencies: RoutineRouteDependencies = defaultDependencies,
): Promise<Response> {
  const input = routineItemCreateInputSchema.parse(await readJsonBody(context.request))
  const hashInput = { item_type: itemType, ...input }
  return dependencies.executeIdempotent(context, hashInput, async (idempotencyKey) =>
    mobileSuccess(
      await createRoutineItem(
        serviceDependencies(context, dependencies),
        context.auth,
        itemType,
        input,
        idempotencyKey,
        hashMobileRequest(hashInput),
      ),
      context.requestId,
      201,
    ),
  )
}

export async function handleRoutineItemPatch(
  context: MobileRouteContext,
  routeContext: RoutineItemRouteContext,
  itemType: RoutineItemType,
  dependencies: RoutineRouteDependencies = defaultDependencies,
): Promise<Response> {
  const { id: rawId } = await routeContext.params
  const routineItemId = resourceIdSchema.parse(rawId)
  const input = routineItemPatchInputSchema.parse(await readJsonBody(context.request))
  const hashInput = { item_type: itemType, routine_item_id: routineItemId, ...input }
  return dependencies.executeIdempotent(context, hashInput, async (idempotencyKey) =>
    mobileSuccess(
      await updateRoutineItem(
        serviceDependencies(context, dependencies),
        context.auth,
        itemType,
        routineItemId,
        input,
        idempotencyKey,
        hashMobileRequest(hashInput),
        dependencies.now(),
      ),
      context.requestId,
    ),
  )
}

export async function handleRoutineItemArchive(
  context: MobileRouteContext,
  routeContext: RoutineItemRouteContext,
  itemType: RoutineItemType,
  dependencies: RoutineRouteDependencies = defaultDependencies,
): Promise<Response> {
  const { id: rawId } = await routeContext.params
  const routineItemId = resourceIdSchema.parse(rawId)
  emptyJsonBodySchema.parse(await readJsonBody(context.request))
  const hashInput = { item_type: itemType, routine_item_id: routineItemId }
  return dependencies.executeIdempotent(context, hashInput, async (idempotencyKey) =>
    mobileSuccess(
      await archiveRoutineItem(
        serviceDependencies(context, dependencies),
        context.auth,
        itemType,
        routineItemId,
        idempotencyKey,
        hashMobileRequest(hashInput),
        dependencies.now(),
      ),
      context.requestId,
    ),
  )
}

export async function handleRoutineItemHistory(
  context: MobileRouteContext,
  routeContext: RoutineItemRouteContext,
  itemType: RoutineItemType,
  dependencies: RoutineRouteDependencies = defaultDependencies,
): Promise<Response> {
  const { id: rawId } = await routeContext.params
  const routineItemId = resourceIdSchema.parse(rawId)
  const query = routineHistoryQuerySchema.parse(
    queryRecord(new URL(context.request.url).searchParams),
  )
  return mobileSuccess(
    await listRoutineItemHistory(
      serviceDependencies(context, dependencies),
      context.auth,
      itemType,
      routineItemId,
      query,
    ),
    context.requestId,
  )
}

export function createRoutineCollectionGetRoute(
  itemType: RoutineItemType,
  mobileRuntime?: MobileRouteRuntime,
  dependencies: RoutineRouteDependencies = defaultDependencies,
) {
  return createMobileRoute(
    (context) => handleRoutineCollectionGet(context, itemType, dependencies),
    mobileRuntime,
  )
}

export function createRoutineCollectionPostRoute(
  itemType: RoutineItemType,
  mobileRuntime?: MobileRouteRuntime,
  dependencies: RoutineRouteDependencies = defaultDependencies,
) {
  return createMobileRoute(
    (context) => handleRoutineCollectionPost(context, itemType, dependencies),
    mobileRuntime,
  )
}

export function createRoutineItemPatchRoute(
  itemType: RoutineItemType,
  mobileRuntime?: MobileRouteRuntime,
  dependencies: RoutineRouteDependencies = defaultDependencies,
) {
  return createMobileRouteWithContext<RoutineItemRouteContext>(
    (context, routeContext) =>
      handleRoutineItemPatch(context, routeContext, itemType, dependencies),
    mobileRuntime,
  )
}

export function createRoutineItemArchiveRoute(
  itemType: RoutineItemType,
  mobileRuntime?: MobileRouteRuntime,
  dependencies: RoutineRouteDependencies = defaultDependencies,
) {
  return createMobileRouteWithContext<RoutineItemRouteContext>(
    (context, routeContext) =>
      handleRoutineItemArchive(context, routeContext, itemType, dependencies),
    mobileRuntime,
  )
}

export function createRoutineItemHistoryRoute(
  itemType: RoutineItemType,
  mobileRuntime?: MobileRouteRuntime,
  dependencies: RoutineRouteDependencies = defaultDependencies,
) {
  return createMobileRouteWithContext<RoutineItemRouteContext>(
    (context, routeContext) =>
      handleRoutineItemHistory(context, routeContext, itemType, dependencies),
    mobileRuntime,
  )
}
