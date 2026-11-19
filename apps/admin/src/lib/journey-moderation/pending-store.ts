import { z } from 'zod'
import { type OperatorContext, operatorContext } from './action-contracts'
import { recoverModerationCommand } from './contracts'

const payload = z
  .object({ version: z.literal(1), context: operatorContext, request: recoverModerationCommand })
  .strict()
export const moderationPending = payload
  .extend({ checksum: z.string().regex(/^[0-9a-f]{64}$/u) })
  .strict()
export type ModerationPending = z.infer<typeof moderationPending>
export class ModerationStorageError extends Error {
  constructor(readonly code: 'pending' | 'corrupt' | 'changed' | 'unavailable') {
    super('Não foi possível conferir a pendência local. Nenhuma nova ação será enviada.')
  }
}
export interface ModerationStorageDriver {
  origin: string
  get(key: string): string | null
  set(key: string, value: string): void
  remove(key: string): void
  hash(value: string): Promise<string>
  withLock<T>(name: string, work: () => Promise<T>): Promise<T>
}
function immutable<T>(value: T): T {
  if (value && typeof value === 'object') {
    for (const child of Object.values(value)) immutable(child)
    Object.freeze(value)
  }
  return value
}
export class ModerationPendingStore {
  private readonly context: OperatorContext
  readonly key: string
  constructor(
    context: OperatorContext,
    private readonly driver: ModerationStorageDriver,
  ) {
    this.context = immutable(operatorContext.parse(context))
    if (context.origin !== driver.origin) throw new ModerationStorageError('corrupt')
    this.key = `performe:journey-moderation:v1:${context.owner}`
  }
  private async safe<T>(work: () => Promise<T>): Promise<T> {
    try {
      return await work()
    } catch (error) {
      if (error instanceof ModerationStorageError) throw error
      throw new ModerationStorageError('unavailable')
    }
  }
  private async checked(raw: unknown): Promise<ModerationPending> {
    const parsed = moderationPending.safeParse(raw)
    if (!parsed.success) throw new ModerationStorageError('corrupt')
    const value = parsed.data
    const body = payload.parse({
      version: value.version,
      context: value.context,
      request: value.request,
    })
    if (
      value.context.origin !== this.context.origin ||
      value.context.owner !== this.context.owner ||
      value.checksum !== (await this.driver.hash(JSON.stringify(body)))
    )
      throw new ModerationStorageError('corrupt')
    return immutable(value)
  }
  async read(): Promise<ModerationPending | null> {
    return this.safe(async () => {
      const raw = this.driver.get(this.key)
      if (raw === null) return null
      if (raw.length > 8192) throw new ModerationStorageError('corrupt')
      let parsed: unknown
      try {
        parsed = JSON.parse(raw)
      } catch {
        throw new ModerationStorageError('corrupt')
      }
      return this.checked(parsed)
    })
  }
  async reserve(request: unknown): Promise<ModerationPending> {
    return this.safe(() =>
      this.driver.withLock(this.key, async () => {
        if (await this.read()) throw new ModerationStorageError('pending')
        const body = payload.parse({
          version: 1,
          context: this.context,
          request: recoverModerationCommand.parse(request),
        })
        const pending = await this.checked({
          ...body,
          checksum: await this.driver.hash(JSON.stringify(body)),
        })
        this.driver.set(this.key, JSON.stringify(pending))
        const actual = await this.read()
        if (!actual || JSON.stringify(actual) !== JSON.stringify(pending))
          throw new ModerationStorageError('changed')
        return actual
      }),
    )
  }
  async acknowledge(raw: unknown): Promise<void> {
    return this.safe(() =>
      this.driver.withLock(this.key, async () => {
        const expected = await this.checked(raw),
          actual = await this.read()
        if (!actual || JSON.stringify(actual) !== JSON.stringify(expected))
          throw new ModerationStorageError('changed')
        this.driver.remove(this.key)
        if (this.driver.get(this.key) !== null) throw new ModerationStorageError('changed')
      }),
    )
  }
}
export async function browserModerationHash(value: string): Promise<string> {
  const digest = await crypto.subtle.digest('SHA-256', new TextEncoder().encode(value))
  return [...new Uint8Array(digest)].map((x) => x.toString(16).padStart(2, '0')).join('')
}
export function createBrowserModerationStore(context: OperatorContext) {
  return new ModerationPendingStore(context, {
    origin: window.location.origin,
    get: (key) => window.localStorage.getItem(key),
    set: (key, value) => window.localStorage.setItem(key, value),
    remove: (key) => window.localStorage.removeItem(key),
    hash: browserModerationHash,
    withLock: async (name, work) => {
      if (!navigator.locks) throw new ModerationStorageError('unavailable')
      const controller = new AbortController(),
        timer = setTimeout(() => controller.abort(), 8000)
      try {
        return await navigator.locks.request(
          name,
          { mode: 'exclusive', signal: controller.signal },
          work,
        )
      } finally {
        clearTimeout(timer)
      }
    },
  })
}
