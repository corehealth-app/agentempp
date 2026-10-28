import { requiresReevaluationPhotos } from '@mpp/core/reevaluation-form'
/** Backend-only FULL RPC transport. No default route, client effect, clock,
 * capture-before-replay, direct table access, fallback or automatic retry. */

import { isDeepStrictEqual } from 'node:util'
import type { ServiceClient } from '@mpp/db'
import { z } from 'zod'
import { readClinicalFullContext } from './clinical-full-authority'
import { normalizeClinicalFullCommand } from './clinical-full-command'
import {
  type ClinicalFullPackage,
  type ClinicalFullScope,
  clinicalFullError,
  fullCommandPreparedSchema,
  fullCommandReceiptSchema,
  fullCommandSchema,
  fullConfirmedSchema,
  fullHash,
  fullPackageSchema,
  fullPreparedSchema,
  fullPresentationSchema,
  fullReceiptSchema,
  type fullResultSchema,
  fullScopeSchema,
} from './clinical-full-contracts'
import { reevaluationCycleUuidSchema as uuid } from './reevaluation-cycle-contracts'

type RpcName =
  | 'get_mobile_clinical_full_context'
  | 'prepare_mobile_clinical_full'
  | 'get_mobile_clinical_full_receipt'
  | 'confirm_mobile_clinical_full'
  | 'get_mobile_clinical_full_command'
  | 'prepare_mobile_clinical_full_command'
  | 'prepare_mobile_clinical_full_presented_command'
  | 'get_mobile_clinical_full_command_receipt'
  | 'confirm_mobile_clinical_full_command'
type Rpc = (name: RpcName, args: Record<string, unknown>) => PromiseLike<unknown>
const same = (a: string, b: string) => a.toLowerCase() === b.toLowerCase()
const sameCycle = (a: string | null, b: string | null) =>
  a === null ? b === null : b !== null && same(a, b)
function freeze<T>(value: T): T {
  if (value && typeof value === 'object') {
    for (const child of Object.values(value)) freeze(child)
    Object.freeze(value)
  }
  return value
}
function unavailable(): never {
  throw clinicalFullError('unavailable')
}
function parse<S extends z.ZodTypeAny>(schema: S, raw: unknown): z.infer<S> {
  const parsed = schema.safeParse(structuredClone(raw))
  if (!parsed.success) return unavailable()
  return parsed.data
}
function packageInput(raw: unknown) {
  const bundle = parse(fullPackageSchema, raw)
  // Draft normalization belongs before calculation/hashing. At this private
  // boundary even a benign default must not alter an original replay package.
  if (!isDeepStrictEqual(bundle, raw)) return unavailable()
  if (
    Buffer.byteLength(JSON.stringify(bundle.form)) > 65536 ||
    Buffer.byteLength(JSON.stringify(bundle.intent)) > 8192 ||
    Buffer.byteLength(JSON.stringify(bundle.proposal)) > 65536
  )
    return unavailable()
  return bundle
}
function commandInput(raw: unknown, bundle: ClinicalFullPackage) {
  const command = parse(fullCommandSchema, raw)
  if (
    !isDeepStrictEqual(command, raw) ||
    !isDeepStrictEqual(command.form, bundle.form) ||
    !isDeepStrictEqual(command.bodyFat, bundle.intent.bodyFat ?? null) ||
    Buffer.byteLength(JSON.stringify(command)) > 81920
  )
    return unavailable()
  return command
}
function commandPrepared(raw: unknown, user: string) {
  const packet = parse(fullCommandPreparedSchema, raw)
  if (
    !isDeepStrictEqual(packet, raw) ||
    !same(packet.user_id, user) ||
    !same(packet.preview.user_id, user) ||
    packet.preview.review_kind !== packet.command.form.kind
  )
    return unavailable()
  const bundle = packageInput(packet.package)
  commandInput(packet.command, bundle)
  try {
    if (
      !isDeepStrictEqual(
        normalizeClinicalFullCommand(packet.command, packet.normalization_context).command,
        packet.command,
      )
    )
      return unavailable()
  } catch {
    return unavailable()
  }
  return packet
}
function bindResult(
  result: z.infer<typeof fullResultSchema>,
  user: string,
  preview: string,
  bundle: ClinicalFullPackage,
  scope?: ClinicalFullScope,
) {
  if (
    !same(result.user_id, user) ||
    !same(result.review_id, preview) ||
    result.kind !== bundle.form.kind ||
    result.principal !== bundle.proposal.principal ||
    Object.entries(result.targets).some(
      ([key, value]) => value !== bundle.proposal.targets[key as keyof typeof result.targets],
    ) ||
    (scope &&
      (scope.kind !== result.kind ||
        (scope.kind !== 'SAFETY' && !sameCycle(result.cycle_id, scope.cycleId)))) ||
    (requiresReevaluationPhotos(result.kind) &&
      result.body_fat_percent !== (bundle.intent.bodyFat?.meanHundredths ?? 0) / 100)
  )
    return unavailable()
}

export function createSupabaseClinicalFullRepository(supabase: ServiceClient) {
  const rpc = supabase.rpc.bind(supabase) as unknown as Rpc
  async function call(name: RpcName, args: Record<string, unknown>, nullable = false) {
    let raw: unknown
    try {
      raw = await rpc(name, freeze(args))
    } catch {
      return unavailable()
    }
    if (
      !raw ||
      typeof raw !== 'object' ||
      Array.isArray(raw) ||
      !Object.hasOwn(raw, 'data') ||
      !Object.hasOwn(raw, 'error')
    )
      return unavailable()
    const reply = raw as { data: unknown; error: unknown }
    if (reply.error !== null) {
      const code =
        reply.error &&
        typeof reply.error === 'object' &&
        !Array.isArray(reply.error) &&
        Object.hasOwn(reply.error, 'code')
          ? (reply.error as { code: unknown }).code
          : null
      throw clinicalFullError(
        code === '40001' ? 'changed' : code === '55P03' ? 'busy' : 'unavailable',
      )
    }
    if (nullable && reply.data === null) return null
    if (!reply.data || typeof reply.data !== 'object' || Array.isArray(reply.data))
      return unavailable()
    return structuredClone(reply.data)
  }
  const identity = (raw: string) => parse(uuid, raw).toLowerCase()
  function scopeInput(raw: unknown) {
    const scope = parse(fullScopeSchema, raw)
    return {
      ...scope,
      userId: scope.userId.toLowerCase(),
      cycleId: scope.cycleId?.toLowerCase() ?? null,
    }
  }
  const packageArgs = (bundle: ClinicalFullPackage) => ({
    p_form: bundle.form,
    p_intent: bundle.intent,
    p_proposal: bundle.proposal,
  })
  return Object.freeze({
    async findPrepared(userId: string, rawLookup: unknown) {
      const user = identity(userId)
      const lookup = parse(
        z.union([
          z.object({ previewId: uuid }).strict(),
          z.object({ prepareOperationKey: uuid }).strict(),
        ]),
        rawLookup,
      )
      const preview = 'previewId' in lookup ? identity(lookup.previewId) : null
      const key = 'prepareOperationKey' in lookup ? identity(lookup.prepareOperationKey) : null
      const raw = await call(
        'get_mobile_clinical_full_command',
        {
          p_user_id: user,
          p_preview_id: preview,
          p_prepare_operation_key: key,
        },
        true,
      )
      if (raw === null) return null
      const packet = commandPrepared(raw, user)
      if (
        (preview && !same(packet.preview.preview_id, preview)) ||
        (key && !same(packet.operation_key, key))
      )
        return unavailable()
      return packet
    },
    async prepareCommand(
      rawScope: unknown,
      key: string,
      contextHash: string,
      rawCommand: unknown,
      rawPackage: unknown,
      rawPresentation?: unknown,
    ) {
      const scope = scopeInput(rawScope),
        operation = identity(key)
      const bundle = packageInput(rawPackage),
        command = commandInput(rawCommand, bundle)
      const hash = parse(fullHash, contextHash)
      const presentation =
        rawPresentation === undefined ? undefined : parse(fullPresentationSchema, rawPresentation)
      if (command.form.kind !== scope.kind) return unavailable()
      const packet = commandPrepared(
        await call(
          presentation === undefined
            ? 'prepare_mobile_clinical_full_command'
            : 'prepare_mobile_clinical_full_presented_command',
          {
            p_user_id: scope.userId,
            p_kind: scope.kind,
            p_cycle_id: scope.cycleId,
            p_operation_key: operation,
            p_context_hash: hash,
            p_command: command,
            ...packageArgs(bundle),
            ...(presentation === undefined ? {} : { p_presentation: presentation }),
          },
        ),
        scope.userId,
      )
      // A racing same-command request can return its ORIGINAL package/hash.
      // Bind identity/scope, without replacing that ACK with current effects.
      if (
        !same(packet.operation_key, operation) ||
        packet.preview.review_kind !== scope.kind ||
        !sameCycle(packet.preview.cycle_id, scope.cycleId) ||
        !isDeepStrictEqual(packet.command, command)
      )
        return unavailable()
      return packet
    },
    async findCommandReceipt(userId: string, previewId: string, key: string) {
      const user = identity(userId),
        preview = identity(previewId),
        operation = identity(key)
      const raw = await call(
        'get_mobile_clinical_full_command_receipt',
        {
          p_user_id: user,
          p_preview_id: preview,
          p_operation_key: operation,
        },
        true,
      )
      if (raw === null) return null
      const packet = parse(fullCommandReceiptSchema, raw)
      if (
        !isDeepStrictEqual(packet, raw) ||
        !same(packet.user_id, user) ||
        !same(packet.preview_id, preview) ||
        !same(packet.operation_key, operation)
      )
        return unavailable()
      const prepared = commandPrepared(packet.prepared, user)
      if (!same(prepared.preview.preview_id, preview)) return unavailable()
      const bundle = packageInput({
        form: packet.form,
        intent: packet.intent,
        proposal: packet.proposal,
      })
      if (!isDeepStrictEqual(bundle, prepared.package)) return unavailable()
      bindResult(packet.result, user, preview, bundle)
      return packet
    },
    async confirmCommand(
      rawScope: unknown,
      previewId: string,
      key: string,
      rawCommand: unknown,
      rawPackage: unknown,
    ) {
      const scope = scopeInput(rawScope),
        preview = identity(previewId),
        operation = identity(key)
      const bundle = packageInput(rawPackage),
        command = commandInput(rawCommand, bundle)
      if (command.form.kind !== scope.kind) return unavailable()
      const packet = parse(
        fullConfirmedSchema,
        await call('confirm_mobile_clinical_full_command', {
          p_user_id: scope.userId,
          p_preview_id: preview,
          p_operation_key: operation,
          p_command: command,
          ...packageArgs(bundle),
        }),
      )
      if (
        !same(packet.user_id, scope.userId) ||
        !same(packet.preview_id, preview) ||
        !same(packet.operation_key, operation)
      )
        return unavailable()
      bindResult(packet.result, scope.userId, preview, bundle, scope)
      return packet
    },
    async capture(rawScope: unknown) {
      const scope = scopeInput(rawScope)
      const raw = await call('get_mobile_clinical_full_context', {
        p_user_id: scope.userId,
        p_kind: scope.kind,
        p_cycle_id: scope.cycleId,
      })
      try {
        readClinicalFullContext(raw, scope)
      } catch {
        return unavailable()
      }
      // Keep the full backend wire for other strict consumers, including the
      // actual calculator. This object is never a public response DTO.
      return raw
    },
    async prepare(rawScope: unknown, key: string, contextHash: string, rawPackage: unknown) {
      const scope = scopeInput(rawScope),
        operation = identity(key)
      const bundle = packageInput(rawPackage),
        hash = parse(fullHash, contextHash)
      if (bundle.form.kind !== scope.kind) return unavailable()
      const packet = parse(
        fullPreparedSchema,
        await call('prepare_mobile_clinical_full', {
          p_user_id: scope.userId,
          p_kind: scope.kind,
          p_cycle_id: scope.cycleId,
          p_operation_key: operation,
          p_context_hash: hash,
          ...packageArgs(bundle),
        }),
      )
      const preview = packet.preview
      if (
        !same(packet.user_id, scope.userId) ||
        !same(preview.user_id, scope.userId) ||
        !same(packet.operation_key, operation) ||
        preview.review_kind !== scope.kind ||
        !sameCycle(preview.cycle_id, scope.cycleId) ||
        preview.context_hash !== hash
      )
        return unavailable()
      return packet
    },
    async findReceipt(userId: string, previewId: string, key: string) {
      const user = identity(userId),
        preview = identity(previewId),
        operation = identity(key)
      const raw = await call(
        'get_mobile_clinical_full_receipt',
        {
          p_user_id: user,
          p_preview_id: preview,
          p_operation_key: operation,
        },
        true,
      )
      if (raw === null) return null
      const packet = parse(fullReceiptSchema, raw)
      if (!isDeepStrictEqual(packet, raw)) return unavailable()
      if (
        !same(packet.user_id, user) ||
        !same(packet.preview_id, preview) ||
        !same(packet.operation_key, operation)
      )
        return unavailable()
      const bundle = packageInput({
        form: packet.form,
        intent: packet.intent,
        proposal: packet.proposal,
      })
      bindResult(packet.result, user, preview, bundle)
      // operation_matched=false remains a READ: caller must confirm once with
      // this original package to bind an alias, before any current capture.
      return packet
    },
    async confirm(rawScope: unknown, previewId: string, key: string, rawPackage: unknown) {
      const scope = scopeInput(rawScope),
        preview = identity(previewId),
        operation = identity(key)
      const bundle = packageInput(rawPackage)
      if (bundle.form.kind !== scope.kind) return unavailable()
      const packet = parse(
        fullConfirmedSchema,
        await call('confirm_mobile_clinical_full', {
          p_user_id: scope.userId,
          p_preview_id: preview,
          p_operation_key: operation,
          ...packageArgs(bundle),
        }),
      )
      if (
        !same(packet.user_id, scope.userId) ||
        !same(packet.preview_id, preview) ||
        !same(packet.operation_key, operation)
      )
        return unavailable()
      bindResult(packet.result, scope.userId, preview, bundle, scope)
      return packet
    },
  })
}
