/** Real HTTP factories/adapters/owned SQL; explicit synthetic Storage and AI. */
import assert from 'node:assert/strict'
import { createInterface } from 'node:readline'
import type { ServiceClient } from '@mpp/db'
import { createReevaluationPhotoConsentRoutes } from '../../../apps/admin/src/lib/mobile-api/reevaluation-photo-consent-http.js'
import { createSupabaseReevaluationPhotoLifecycleOperations } from '../../../apps/admin/src/lib/mobile-api/reevaluation-photo-lifecycle.js'
import { createReevaluationPhotoLifecycleRoutes } from '../../../apps/admin/src/lib/mobile-api/reevaluation-photo-lifecycle-http.js'
import type { MobileRouteRuntime } from '../../../apps/admin/src/lib/mobile-api/route.js'
import {
  consentAuth,
  uid,
} from '../../../apps/admin/src/lib/mobile-api/testing/reevaluation-photo-consent-fixture.js'

if (process.env.PERFORME_PHOTO_HTTP_QA !== 'owned-local-rollback' || process.stdin.isTTY)
  throw new Error('Explicit owned rollback parent required')
const lines = createInterface({ input: process.stdin, crlfDelay: Infinity })[Symbol.asyncIterator]()
async function parent(packet: object): Promise<unknown> {
  process.stdout.write(`${JSON.stringify(packet)}\n`)
  const line = await lines.next()
  assert(!line.done, 'Owned parent closed')
  return JSON.parse(line.value)
}
async function main() {
  const init = (await parent({ type: 'init' })) as { owner: string; cycle: string }
  const origin = 'https://synthetic-owned-project.supabase.co'
  const assets = new Map<
    string,
    { id: string; pose: string; mime_type: string; size_bytes: number }
  >()
  const uploaded = new Set<string>()
  let downloads = 0,
    analyses = 0
  const client = {
    rpc(name: string, args: Record<string, unknown>) {
      // Direct await and the drainer's abortSignal share one real Promise.
      const pending = parent({ type: 'rpc', name, args })
      return Object.assign(pending, {
        abortSignal: (signal: AbortSignal) => {
          assert(!signal.aborted)
          return pending
        },
      })
    },
    storage: {
      from(bucket: string) {
        assert.equal(bucket, 'body-checkin-photos')
        return {
          async createSignedUploadUrl(path: string, options: { upsert: boolean }) {
            assert.equal(options.upsert, false)
            assert(assets.has(path))
            const encode = (value: unknown) =>
              Buffer.from(JSON.stringify(value)).toString('base64url')
            const token = `${encode({ alg: 'HS256' })}.${encode({ exp: Math.floor(Date.now() / 1000) + 7200, url: `${bucket}/${path}`, upsert: false })}.${Buffer.from('synthetic-signature').toString('base64url')}`
            return {
              data: {
                path,
                token,
                signedUrl: `${origin}/storage/v1/object/upload/sign/${bucket}/${path}?token=${token}`,
              },
              error: null,
            }
          },
          async info(path: string) {
            assert(uploaded.has(path))
            return { data: { size: 1200, contentType: 'image/jpeg', etag: null }, error: null }
          },
          async download(path: string) {
            assert(uploaded.has(path))
            const asset = assets.get(path)
            assert(asset)
            const bytes = new Uint8Array(1200)
            bytes.set([255, 216, 255, ['front', 'side', 'back'].indexOf(asset.pose)])
            downloads++
            return { data: new Blob([bytes], { type: 'image/jpeg' }), error: null }
          },
          async remove(paths: string[]) {
            for (const path of paths) assert(uploaded.has(path))
            return parent({ type: 'remove', bucket, paths })
          },
        }
      },
    },
  } as unknown as ServiceClient
  const auth = structuredClone(consentAuth)
  auth.userId = init.owner
  auth.patient.id = init.owner
  const runtime: MobileRouteRuntime = {
    authenticate: async () => structuredClone(auth),
    authorizeEntitlement: async () => {},
    createServiceClient: () => client,
    createRequestId: () => 'owned-recurring-photo-http',
  }
  const consent = createReevaluationPhotoConsentRoutes({ enabled: true }, runtime)
  const lifecycle = createReevaluationPhotoLifecycleRoutes(
    {
      enabled: true,
      createOperations: (value) =>
        createSupabaseReevaluationPhotoLifecycleOperations(value, {
          storageOrigin: origin,
          analyze: async (bytes, mime, budget) => {
            assert.equal(bytes.byteLength, 1200)
            assert.equal(mime, 'image/jpeg')
            assert(!budget.signal.aborted && budget.timeoutMs > 0)
            const pose = ['front', 'side', 'back'][bytes[3]]
            assert(pose)
            await parent({ type: 'analyze', pose })
            analyses++
            return { type: 'body', view: pose, bf_percent_estimate: [22, 24, 26][bytes[3]] }
          },
        }),
    },
    runtime,
  )
  const ctx = (assetId?: string) => ({
    params: Promise.resolve({ cycleId: init.cycle, ...(assetId ? { assetId } : {}) }),
  })
  const get = () =>
    new Request(`https://owned.test/api/mobile/v1/reevaluation/${init.cycle}/photos`)
  const post = (input: unknown, key: string) =>
    new Request(get().url, {
      method: 'POST',
      headers: { 'content-type': 'application/json', 'idempotency-key': key },
      body: JSON.stringify(input),
    })
  async function data(response: Response) {
    assert.equal(response.status, 200, `HTTP ${response.status}`)
    return (await response.json()).data
  }
  const initial = await data(await consent.GET(get(), ctx()))
  assert.equal(initial.availability, 'unavailable')
  assert.equal(initial.unavailable_reason, 'consent_required')
  assert.equal(initial.cycle_revision, '1')
  assert.equal(initial.document.idle_timeout_seconds, 86400)
  const doc = initial.document,
    acceptInput = {
      expectedRevision: initial.cycle_revision,
      document: {
        id: doc.id,
        documentKey: doc.document_key,
        version: doc.version,
        locale: doc.locale,
        bodyHash: doc.body_hash,
      },
    }
  const accepted = await data(await consent.ACCEPT(post(acceptInput, uid(5710)), ctx()))
  assert.equal(accepted.cycle_revision, '2')
  assert.deepEqual(await data(await consent.ACCEPT(post(acceptInput, uid(5710)), ctx())), accepted)
  // Isolate the legal change while the original acceptance/cycle are still
  // usable. A later discard would independently reject replay and mask this.
  await parent({ type: 'change_document' })
  assert.equal((await consent.ACCEPT(post(acceptInput, uid(5710)), ctx())).status, 409)
  await parent({ type: 'restore_document' })
  const acceptanceID = accepted.acceptance.acceptance_id
  let revision = accepted.cycle_revision
  for (const [index, pose] of ['front', 'side', 'back'].entries()) {
    const input = {
      expectedRevision: revision,
      acceptanceId: acceptanceID,
      pose,
      mimeType: 'image/jpeg',
      sizeBytes: 1200,
    }
    const allocated = await data(await lifecycle.ALLOCATE(post(input, uid(5720 + index)), ctx()))
    assert.equal(allocated.cycle_revision, revision)
    assert.equal(allocated.asset.pose, pose)
    assert.deepEqual(
      await data(await lifecycle.ALLOCATE(post(input, uid(5720 + index)), ctx())),
      allocated,
    )
    const asset = allocated.asset,
      path = `${init.owner}/${asset.id}.jpg`
    assets.set(path, asset)
    const ticket = await data(await lifecycle.UPLOAD(post({}, uid(5730 + index)), ctx(asset.id)))
    assert.equal(ticket.upload.method, 'PUT')
    assert.deepEqual(ticket.upload.headers, { 'Content-Type': 'image/jpeg', 'x-upsert': 'false' })
    await parent({ type: 'put', path })
    uploaded.add(path)
    const completed = await data(
      await lifecycle.COMPLETE(post({}, uid(5740 + index)), ctx(asset.id)),
    )
    revision = String(3 + index)
    assert.equal(completed.cycle_revision, revision)
    const process = () => lifecycle.PROCESS(post({}, uid(5750 + index)), ctx(asset.id))
    assert.equal((await data(await process())).status, 'processed')
    if (index === 0) {
      assert.equal((await data(await process())).status, 'processed')
      assert.equal(analyses, 1)
      assert.equal(downloads, 1)
    }
  }
  const snapshot = await data(await lifecycle.GET(get(), ctx()))
  assert.equal(snapshot.cycle_revision, '5')
  assert.equal(snapshot.acceptance_id, acceptanceID)
  assert.deepEqual(
    snapshot.photos.map((p: { pose: string; asset: { status: string } }) => [
      p.pose,
      p.asset.status,
    ]),
    [
      ['front', 'processed'],
      ['side', 'processed'],
      ['back', 'processed'],
    ],
  )
  for (const privateKey of [
    'user_id',
    'signup_generation',
    'bf_percent_estimate',
    'body_hash',
    'object_path',
    'analysis',
  ])
    assert(!JSON.stringify(snapshot).includes(privateKey))
  const discarded = await data(
    await lifecycle.DISCARD(
      post({ acceptanceId: acceptanceID, expectedRevision: revision }, uid(5760)),
      ctx(),
    ),
  )
  assert.equal(discarded.status, 'discard_requested')
  assert.equal(discarded.deletion, 'waiting')
  assert(!Object.hasOwn(discarded, 'cycle_revision'))
  assert.equal(downloads, 3)
  assert.equal(analyses, 3)
  process.stdout.write(
    `${JSON.stringify({ type: 'result', status: 'PASS_LOCAL_HTTP_SQL_SYNTHETIC_MEDIA', analyses, downloads, poses: assets.size })}\n`,
  )
}
main().catch((error) => {
  process.stderr.write(String(error))
  process.stdout.write(`${JSON.stringify({ type: 'failure' })}\n`)
  process.exitCode = 1
})
