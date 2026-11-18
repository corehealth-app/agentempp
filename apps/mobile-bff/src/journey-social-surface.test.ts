import { createHash } from 'node:crypto'
import { spawnSync } from 'node:child_process'
import { existsSync, readFileSync, realpathSync } from 'node:fs'
import { dirname, resolve } from 'node:path'
import { fileURLToPath } from 'node:url'
import { describe, expect, it } from 'vitest'

const app = resolve(dirname(fileURLToPath(import.meta.url)), '..')
const routes = new Map([
  ['profile/journey-social/route.ts', ['GET', 'PATCH', 'dynamic', 'runtime']],
  ['profile/journey-social/blocks/route.ts', ['GET', 'POST', 'dynamic', 'runtime']],
  ['profile/journey-social/reports/route.ts', ['POST', 'dynamic', 'runtime']],
  ['journey/ranking/route.ts', ['GET', 'dynamic', 'runtime']],
])
function exportsOf(source: string) {
  return [...source.matchAll(/^export (?:const|function) ([A-Za-z_$][\w$]*)/gm)]
    .map((m) => m[1])
    .sort()
}
describe('closed additive Journey social API surface', () => {
  it('mounts exactly the four patient transports with closed exports and named wrappers', () => {
    for (const [path, methods] of routes) {
      const original = resolve(app, '../admin/src/app/api/mobile/v1', path),
        wrapper = resolve(app, 'src/app/api/mobile/v1', path)
      expect(existsSync(original), path).toBe(true)
      expect(existsSync(wrapper), path).toBe(true)
      expect(exportsOf(readFileSync(original, 'utf8'))).toEqual(methods)
      const forwarding = readFileSync(wrapper, 'utf8')
      expect(forwarding).not.toMatch(/export\s+\*/u)
      expect(forwarding).toContain(`@/app/api/mobile/v1/${path.slice(0, -3)}`)
    }
  })
  it('seals the complete new graph and confines its service-only RPC to these four transports', () => {
    const root = resolve(app, '.next/server'),
      manifest = JSON.parse(readFileSync(resolve(root, 'app-paths-manifest.json'), 'utf8')) as Record<string, string>,
      expected = [...routes.keys()].map((path) => `/api/mobile/v1/${path.replace(/\.ts$/, '')}`).sort(),
      oldTargets = new Set<string>(), newTargets = new Set<string>(), consumers: string[] = []
    for (const [route, target] of Object.entries(manifest)) {
      const file = resolve(root, target),
        trace = JSON.parse(readFileSync(`${file}.nft.json`, 'utf8')) as { files: string[] },
        targets = trace.files.map((path) => realpathSync(resolve(dirname(file), path))),
        social = expected.includes(route)
      if (social) expect(targets, route).toHaveLength(105)
      for (const path of targets) (social ? newTargets : oldTargets).add(path)
      if ([file, ...targets].filter((path) => path.endsWith('.js')).some((path) =>
        readFileSync(path, 'utf8').includes('journey_social_patient_authenticated'))) consumers.push(route)
    }
    expect(consumers.sort()).toEqual(expected)
    const exclusive = [...newTargets].filter((path) => !oldTargets.has(path)),
      chunks = exclusive.filter((path) => path.startsWith(`${root}/chunks/`))
    expect(exclusive).toHaveLength(5)
    expect(chunks).toHaveLength(1)
    expect(exclusive.filter((path) => !chunks.includes(path)).sort()).toEqual(expected.map((route) =>
      realpathSync(resolve(root, `app${route}_client-reference-manifest.js`))).sort())
    const chunk = readFileSync(chunks[0], 'utf8')
    expect(createHash('sha256').update(chunk).digest('hex')).toBe('27c1e0830c0344c7f98696d580c82d4ef652d484ab4e67d2bb4ce76ebbb1dee7')
    for (const forbidden of ['capture_mobile_clinical_day_close', 'journey_social_moderate', 'processMessageFn'])
      expect(chunk).not.toContain(forbidden)
  })
  it('retains the whole pinned101/96/93 chain and requires the new four independently', () => {
    const result = spawnSync(process.execPath, ['scripts/verify-route-mirror.mjs'], {
      cwd: app,
      encoding: 'utf8',
      timeout: 30000,
    })
    expect(result.status, result.stderr).toBe(0)
    expect(result.stdout).toContain('SOURCE_SOCIAL_CURRENT_ROUTE_EXPORT_COUNT=105')
    expect(result.stdout).toContain('SOURCE_COMPLETION_CURRENT_ROUTE_EXPORT_COUNT=101')
    expect(result.stdout).toContain('SOURCE_CURRENT_ROUTE_EXPORT_COUNT=96')
    expect(result.stdout).toContain('SOURCE_ROUTE_EXPORT_COUNT=93')
  })
})
