import { readFileSync, realpathSync } from 'node:fs'
import { dirname, resolve } from 'node:path'
import { fileURLToPath } from 'node:url'
import { describe, expect, it } from 'vitest'
import { inspectBuildSurface } from '../scripts/verify-build-surface.mjs'

const buildRoot = resolve(dirname(fileURLToPath(import.meta.url)), '../.next')
const serverRoot = resolve(buildRoot, 'server')
const appPaths: Record<string, string> = JSON.parse(
  readFileSync(resolve(serverRoot, 'app-paths-manifest.json'), 'utf8'),
)
const code = new Map<string, string>()

function source(path: string): string {
  const physical = realpathSync(path)
  let value = code.get(physical)
  if (value === undefined) {
    value = readFileSync(physical, 'utf8')
    code.set(physical, value)
  }
  return value
}

function routesReaching(marker: string): string[] {
  return Object.entries(appPaths)
    .filter(([route]) => route.startsWith('/api/mobile/v1/'))
    .filter(([, target]) => {
      const entry = resolve(serverRoot, target)
      const trace: { files: string[] } = JSON.parse(readFileSync(`${entry}.nft.json`, 'utf8'))
      const files = [entry, ...trace.files.map((file) => resolve(dirname(entry), file))]
      return files.some((file) => /\.[cm]?js$/.test(file) && source(file).includes(marker))
    })
    .map(([route]) => route)
    .sort()
}

describe('weekly strength in the real mobile server build', () => {
  it.each([
    'get_mobile_strength_week_context',
    'freeze_mobile_strength_week_target',
    'get_mobile_strength_week_projection',
    'MOBILE_STRENGTH_WEEK_PROJECT_REF',
  ])('limits %s to the Today route, including transitive chunks', (marker) => {
    expect(routesReaching(marker)).toEqual(['/api/mobile/v1/today/route'])
  })

  it('keeps worker, administrative routes and server actions out of the build', () => {
    const surface = inspectBuildSurface(buildRoot)
    expect(surface.routesOutsideMobilePrefix).toEqual([])
    expect(surface.forbiddenAdminRoutes).toEqual([])
    expect(surface.forbiddenInngestRoutes).toEqual([])
    expect(surface.forbiddenStripeRoutes).toEqual([])
    expect(surface.forbiddenAdminMediaRoutes).toEqual([])
    expect(surface.forbiddenWorkerBundleReferences).toEqual([])
    expect(surface.forbiddenWorkerTraceReferences).toEqual([])
    expect(surface.forbiddenAdministrativeBundleReferences).toEqual([])
    expect(surface.forbiddenAdministrativeTraceReferences).toEqual([])
    expect(surface.pageRoutes).toEqual([])
    expect(surface.middlewareEntries).toEqual([])
    expect(surface.serverActionReferences).toEqual([])
  })
})
