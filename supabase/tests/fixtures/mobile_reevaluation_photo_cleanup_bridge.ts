/** Existing worker -> actual owned SQL. Storage is an explicit synthetic port,
 * not a claim of provider deletion or a deployed worker. */
import assert from 'node:assert/strict'
import { createInterface } from 'node:readline'
import type { ServiceClient } from '@mpp/db'
import { cleanupReevaluationPhotos } from '../../../packages/inngest-functions/src/lib/reevaluation-photo-cleanup.js'
import { createReevaluationPhotoCleanupDependencies } from '../../../packages/inngest-functions/src/lib/supabase-reevaluation-photo-cleanup.js'

if (process.env.PERFORME_PHOTO_CLEANUP_QA !== 'owned-local-rollback' || process.stdin.isTTY)
  throw new Error('Explicit owned rollback parent required')
const iterator = createInterface({ input: process.stdin, crlfDelay: Infinity })[
  Symbol.asyncIterator
]()
async function request(packet: object): Promise<unknown> {
  process.stdout.write(`${JSON.stringify(packet)}\n`)
  const reply = await iterator.next()
  if (reply.done) throw new Error('Owned parent closed')
  return JSON.parse(reply.value)
}
async function main() {
  const client = {
    rpc: (name: string, args: Record<string, unknown>) => ({
      abortSignal: async (signal: AbortSignal) => {
        assert(signal instanceof AbortSignal && !signal.aborted)
        return request({ type: 'rpc', name, args })
      },
    }),
    storage: {
      from: (bucket: string) => ({
        remove: async (paths: string[]) => request({ type: 'remove', bucket, paths }),
      }),
    },
  } as unknown as ServiceClient
  const result = await cleanupReevaluationPhotos(createReevaluationPhotoCleanupDependencies(client))
  assert.deepEqual(result, {
    attempted: 2,
    live: 0,
    waiting: 0,
    settled: 1,
    incomplete: 1,
    newlyDeleted: 1,
    hasMore: false,
    stopped: 'retry_deferred',
  })
  assert(!JSON.stringify(result).includes('b3b01000'))
  process.stdout.write(
    `${JSON.stringify({ type: 'result', status: 'PASS_LOCAL_WORKER_SQL_SYNTHETIC_STORAGE', result })}\n`,
  )
}
main().catch((error) => {
  process.stderr.write(String(error))
  process.stdout.write(`${JSON.stringify({ type: 'failure' })}\n`)
  process.exitCode = 1
})
