import type { ServiceClient } from '@mpp/db'
import { z } from 'zod'

// G is a literal transport identity. Never parse/re-encode it through JS Date.
export const signupCleanupGenerationSchema = z
  .string()
  .max(35)
  .datetime({ offset: true })
  .regex(/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d{1,6})?(?:Z|[+-](?:[01]\d|2[0-3]):[0-5]\d)$/)
export const signupCleanupScopeSchema = z
  .object({
    generation: signupCleanupGenerationSchema,
    state: z.enum(['not_required', 'pending', 'unknown']),
  })
  .strict()
export type SignupBodyPhotoCleanupScopeDto = z.infer<typeof signupCleanupScopeSchema>
const receiptSchema = signupCleanupScopeSchema
  .extend({ version: z.literal(1), user_id: z.string().uuid() })
  .strict()
interface RpcQuery extends PromiseLike<{ data: unknown; error: unknown }> {
  abortSignal(signal: AbortSignal): RpcQuery
}

/** Technical read only, independent of photos availability. Failure cannot undo completion. */
export async function readSignupBodyPhotoCleanupScope(
  client: ServiceClient,
  owner: string,
  generation: string,
): Promise<SignupBodyPhotoCleanupScopeDto> {
  const unknown: SignupBodyPhotoCleanupScopeDto = { generation, state: 'unknown' }
  if (
    !signupCleanupGenerationSchema.safeParse(generation).success ||
    !z.string().uuid().safeParse(owner).success
  )
    return unknown
  const controller = new AbortController()
  let timer: ReturnType<typeof setTimeout> | undefined
  const timeout = new Promise<SignupBodyPhotoCleanupScopeDto>((resolve) => {
    timer = setTimeout(() => {
      controller.abort()
      resolve(unknown)
    }, 3000)
  })
  const read = async (): Promise<SignupBodyPhotoCleanupScopeDto> => {
    try {
      const api = client as unknown as {
        rpc(name: string, params: Record<string, unknown>): RpcQuery
      }
      const result = await api
        .rpc('get_mobile_signup_body_photo_cleanup_scope', {
          p_user_id: owner,
          p_generation: generation,
        })
        .abortSignal(controller.signal)
      if (controller.signal.aborted || !result || result.error !== null) return unknown
      const parsed = receiptSchema.safeParse(result.data)
      if (
        !parsed.success ||
        parsed.data.user_id.toLowerCase() !== owner.toLowerCase() ||
        parsed.data.generation !== generation
      )
        return unknown
      return { generation, state: parsed.data.state }
    } catch {
      return unknown
    }
  }
  try {
    return await Promise.race([read(), timeout])
  } finally {
    if (timer !== undefined) clearTimeout(timer)
  }
}
