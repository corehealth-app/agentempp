import type { ServiceClient } from '@mpp/db'
import { z } from 'zod'
import type { FinalizationOutcome, FinalizationPhase } from './signup-body-photo-finalization'

const uuid = z.string().uuid()
const instant = z.string().datetime({ offset: true })
const count = z.number().int().nonnegative().max(Number.MAX_SAFE_INTEGER)
const identity = { version: z.literal(1), user_id: uuid }
const prepareSchema = z.discriminatedUnion('kind', [
  z
    .object({ ...identity, kind: z.literal('empty'), current_profile_completed: z.boolean() })
    .strict(),
  z
    .object({
      ...identity,
      kind: z.literal('ready'),
      current_profile_completed: z.boolean(),
      generation: instant,
      policy: z.literal('delete_all_signup_v1'),
      estimate_state: z.enum(['saved', 'unusable']),
      sweep_no: count.min(1),
      cursor: uuid.nullable(),
      manifest_count: count.min(1),
      remaining_count: count.min(1),
    })
    .strict(),
])
const pageSchema = z
  .object({
    ...identity,
    generation: instant,
    sweep_no: count.min(1),
    cursor: uuid.nullable(),
    has_more: z.boolean(),
    items: z
      .array(
        z
          .object({
            asset_id: uuid,
            bucket_id: z.literal('body-checkin-photos'),
            object_path: z.string().min(1),
          })
          .strict(),
      )
      .min(1)
      .max(200),
  })
  .strict()
const assetBase = { asset_id: uuid, processing_result: z.null() }
const acknowledgedAsset = z.discriminatedUnion('state', [
  z
    .object({
      ...assetBase,
      state: z.literal('deleted'),
      newly_deleted: z.boolean(),
      deleted_at: instant,
      failure_stage: z.null(),
      failure_code: z.null(),
    })
    .strict(),
  z
    .object({
      ...assetBase,
      state: z.literal('failed_upload_preserved'),
      newly_deleted: z.literal(false),
      deleted_at: z.null(),
      failure_stage: z.literal('upload'),
      failure_code: z.string().min(1),
    })
    .strict(),
  z
    .object({
      ...assetBase,
      state: z.literal('absent'),
      newly_deleted: z.literal(false),
      deleted_at: z.null(),
      failure_stage: z.null(),
      failure_code: z.null(),
    })
    .strict(),
])
const ackSchema = z
  .object({
    ...identity,
    generation: instant,
    sweep_no: count.min(1),
    previous_cursor: uuid.nullable(),
    cursor: uuid,
    sweep_complete: z.boolean(),
    assets: z.array(acknowledgedAsset).min(1).max(200),
  })
  .strict()

function sameId(a: string | null, b: string | null): boolean {
  return a === null || b === null ? a === b : a.toLowerCase() === b.toLowerCase()
}
function instantKey(value: string): string {
  const fraction = value.match(/\.(\d+)(?:Z|[+-]\d\d:\d\d)$/)?.[1] ?? ''
  return `${String(Date.parse(value))}:${fraction.slice(3).padEnd(6, '0')}`
}
function safePath(owner: string, assetId: string, path: string): boolean {
  const prefix = `${owner}/${assetId}.`
  return path.startsWith(prefix) && /^[a-z0-9]+$/.test(path.slice(prefix.length))
}
function requireMatch(ok: boolean): asserts ok {
  if (!ok) throw new Error('invalid_disposition_receipt')
}

export interface SignupPhotoDispositionOutcome extends FinalizationOutcome {
  readonly completed: boolean
  readonly newlyDeleted: number
}

interface RpcQuery extends PromiseLike<{ data: unknown; error: unknown }> {
  abortSignal(signal: AbortSignal): RpcQuery
}

/** Existing Storage SDK cannot abort remove. One deadline guards every next phase. */
export async function disposeSignupBodyPhotos(
  client: ServiceClient,
  owner: string,
  options: {
    generation?: string
    drainAllGenerations: boolean
    deadline?: number
    requireSealedScope?: boolean
  },
): Promise<SignupPhotoDispositionOutcome> {
  const controller = new AbortController()
  const deadline = Math.min(options.deadline ?? Infinity, performance.now() + 3000)
  let phase: FinalizationPhase = 'persist'
  let outcome: SignupPhotoDispositionOutcome | undefined
  let completed = false
  let newlyDeleted = 0
  let prepared = false
  let removeSent = false
  const sweptThisRequest: string[] = []
  const stop = (reason: 'timeout' | 'error' | 'invalid_receipt') => {
    if (outcome) return outcome
    controller.abort()
    const state =
      phase === 'persist'
        ? 'provenance_unknown'
        : prepared && !removeSent
          ? 'provenance_committed_cleanup_pending'
          : phase === 'read'
            ? 'source_unknown'
            : 'cleanup_unknown'
    outcome = { state, phase, reason, completed, newlyDeleted }
    console.warn('[mobile-signup-body-photos] finalization_incomplete', { state, phase, reason })
    return outcome
  }
  const guard = () => {
    if (outcome || performance.now() >= deadline) {
      stop('timeout')
      throw new Error('disposition_stopped')
    }
  }
  const rpc = async (name: string, params: Record<string, unknown>) => {
    guard()
    const api = client as unknown as {
      rpc(name: string, params: Record<string, unknown>): RpcQuery
    }
    const result = await api.rpc(name, params).abortSignal(controller.signal)
    guard()
    if (!result || result.error !== null) throw new Error('disposition_unavailable')
    return result.data
  }
  const work = async (): Promise<SignupPhotoDispositionOutcome> => {
    try {
      while (true) {
        phase = 'persist'
        const scope = prepareSchema.parse(
          await rpc('prepare_mobile_signup_body_photo_disposition', {
            p_user_id: owner,
            p_generation: options.generation ?? null,
            p_swept_generations: [...sweptThisRequest],
          }),
        )
        guard()
        requireMatch(sameId(scope.user_id, owner))
        completed = scope.current_profile_completed
        if (scope.kind === 'empty') {
          if (options.requireSealedScope && sweptThisRequest.length === 0)
            return stop('invalid_receipt')
          return { state: sweptThisRequest.length ? 'complete' : 'empty', completed, newlyDeleted }
        }
        if (options.generation)
          requireMatch(instantKey(scope.generation) === instantKey(options.generation))
        requireMatch(!sweptThisRequest.some((g) => instantKey(g) === instantKey(scope.generation)))
        prepared = true
        let cursor = scope.cursor
        requireMatch(
          scope.remaining_count <= scope.manifest_count &&
            (cursor !== null || scope.remaining_count === scope.manifest_count),
        )
        let visited = 0
        while (true) {
          phase = 'read'
          const page = pageSchema.parse(
            await rpc('get_mobile_signup_body_photo_disposition_page', {
              p_user_id: owner,
              p_generation: scope.generation,
              p_expected_sweep: scope.sweep_no,
              p_expected_after: cursor,
              p_limit: 200,
            }),
          )
          guard()
          requireMatch(
            sameId(page.user_id, owner) &&
              instantKey(page.generation) === instantKey(scope.generation) &&
              page.sweep_no === scope.sweep_no &&
              sameId(page.cursor, cursor),
          )
          const ids = page.items.map((item) => item.asset_id)
          requireMatch(
            page.items.length <= scope.manifest_count &&
              new Set(ids.map((id) => id.toLowerCase())).size === ids.length &&
              ids.every(
                (id, i) =>
                  id.toLowerCase() > (i ? ids[i - 1].toLowerCase() : (cursor?.toLowerCase() ?? '')),
              ) &&
              page.items.every((item) => safePath(owner, item.asset_id, item.object_path)) &&
              new Set(page.items.map((item) => item.object_path)).size === ids.length,
          )
          visited += ids.length
          requireMatch(
            visited <= scope.remaining_count &&
              (page.has_more ? visited < scope.remaining_count : visited === scope.remaining_count),
          )
          // Freeze the validated paths before the external await.
          const paths = Object.freeze(page.items.map((item) => item.object_path))
          phase = 'remove'
          guard()
          removeSent = true
          const removed = await client.storage.from('body-checkin-photos').remove([...paths])
          guard()
          if (!removed || removed.error !== null) throw new Error('disposition_remove_failed')
          phase = 'mark'
          const ack = ackSchema.parse(
            await rpc('commit_mobile_signup_body_photo_disposition_page', {
              p_user_id: owner,
              p_generation: scope.generation,
              p_expected_sweep: scope.sweep_no,
              p_expected_after: cursor,
              p_asset_ids: ids,
            }),
          )
          guard()
          requireMatch(
            sameId(ack.user_id, owner) &&
              instantKey(ack.generation) === instantKey(scope.generation) &&
              ack.sweep_no === scope.sweep_no &&
              sameId(ack.previous_cursor, cursor) &&
              sameId(ack.cursor, ids.at(-1) ?? null) &&
              ack.sweep_complete === !page.has_more &&
              ack.assets.length === ids.length &&
              ack.assets.every((asset, i) => sameId(asset.asset_id, ids[i])),
          )
          newlyDeleted += ack.assets.filter((asset) => asset.newly_deleted).length
          cursor = ack.cursor
          if (ack.sweep_complete) break
        }
        // Only a strict, observed ACK of the entire sweep permits skipping G.
        sweptThisRequest.push(scope.generation)
        if (!options.drainAllGenerations) return { state: 'complete', completed, newlyDeleted }
        prepared = false
        removeSent = false
      }
    } catch (error) {
      return (
        outcome ??
        stop(
          error instanceof z.ZodError ||
            (error instanceof Error && error.message === 'invalid_disposition_receipt')
            ? 'invalid_receipt'
            : 'error',
        )
      )
    }
  }
  let timer: ReturnType<typeof setTimeout> | undefined
  const timeout = new Promise<SignupPhotoDispositionOutcome>((resolve) => {
    timer = setTimeout(() => resolve(stop('timeout')), Math.max(0, deadline - performance.now()))
  })
  try {
    return await Promise.race([work(), timeout])
  } finally {
    if (timer) clearTimeout(timer)
  }
}
