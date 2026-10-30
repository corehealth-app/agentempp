import { mkdirSync, mkdtempSync, rmSync, writeFileSync } from 'node:fs'
import { dirname, resolve } from 'node:path'
import { fileURLToPath } from 'node:url'
import { describe, expect, it } from 'vitest'
import { inspectBuildSurface } from '../scripts/verify-build-surface.mjs'

const appRoot = resolve(dirname(fileURLToPath(import.meta.url)), '..')
const webhook = '/api/webhooks/revenuecat/route'
const target = 'app/api/webhooks/revenuecat/route.js'

function inspect(
  entries: Record<string, string> = { [webhook]: target },
  contents: Record<string, string> = {},
  omit: string[] = [],
  dependencies: Record<string, string> = {},
) {
  const root = mkdtempSync(resolve(appRoot, '.mobile-bff-webhook-build-'))
  try {
    const server = resolve(root, 'server')
    mkdirSync(server, { recursive: true })
    for (const [file, value] of Object.entries({
      'server/app-paths-manifest.json': entries,
      'routes-manifest.json': { staticRoutes: [], dynamicRoutes: [], dataRoutes: [] },
      'server/middleware-manifest.json': { middleware: {} },
      'server/server-reference-manifest.json': { node: {}, edge: {} },
    }))
      writeFileSync(resolve(root, file), JSON.stringify(value))
    for (const file of new Set(Object.values(entries))) {
      if (omit.includes(file)) continue
      const path = resolve(server, file)
      mkdirSync(dirname(path), { recursive: true })
      writeFileSync(path, contents[file] ?? 'export {}')
      writeFileSync(
        `${path}.nft.json`,
        JSON.stringify({ version: 1, files: Object.keys(dependencies) }),
      )
      for (const [reference, source] of Object.entries(dependencies)) {
        const dependency = resolve(dirname(path), reference)
        mkdirSync(dirname(dependency), { recursive: true })
        writeFileSync(dependency, source)
      }
    }
    return inspectBuildSurface(root)
  } finally {
    rmSync(root, { recursive: true, force: true })
  }
}

describe('closed RevenueCat build boundary', () => {
  it('allows only the exact webhook URL and target with its own literal route identities', () => {
    const surface = inspect(undefined, {
      [target]:
        'const path="/api/webhooks/revenuecat"; const module="/api/webhooks/revenuecat/route"',
    })
    expect(surface.routePaths).toEqual(['/api/webhooks/revenuecat'])
    expect(surface.routesOutsideMobilePrefix).toEqual(['/api/webhooks/revenuecat'])
    expect(surface.forbiddenAdministrativeBundleReferences).toEqual([])
  })

  it.each([
    ['other webhook', '/api/webhooks/stripe/route', 'app/api/webhooks/stripe/route.js'],
    [
      'prefix lookalike',
      '/api/webhooks/revenuecat-evil/route',
      'app/api/webhooks/revenuecat-evil/route.js',
    ],
    ['wrong target', webhook, 'app/api/webhooks/revenuecat-evil/route.js'],
  ])('rejects %s', (_, path, file) => {
    expect(() => inspect({ [path]: file })).toThrow(/APP_PATH_BUNDLE_TARGET_OUTSIDE_MOBILE_ROUTE/)
  })

  it('rejects the exact URL with a missing compiled entry', () => {
    expect(() => inspect(undefined, {}, [target])).toThrow(/APP_PATH_BUNDLE_TARGET_MISSING/)
  })

  it('rejects a target shared with a Mobile URL', () => {
    expect(() => inspect({ [webhook]: target, '/api/mobile/v1/me/route': target })).toThrow(
      /APP_PATH_BUNDLE_TARGET_DUPLICATE/,
    )
  })

  it.each([
    '/api/webhooks/stripe',
    '/api/webhooks/revenuecat/extra',
    'prefix/api/webhooks/revenuecat',
  ])('still detects an embedded foreign identity %s', (path) => {
    const surface = inspect(undefined, { [target]: `const path=${JSON.stringify(path)}` })
    expect(surface.forbiddenAdministrativeBundleReferences).toEqual([`${target}:/webhooks/`])
  })

  it('does not exempt a Mobile bundle containing the webhook identity', () => {
    const mobile = 'app/api/mobile/v1/me/route.js'
    const surface = inspect(
      { '/api/mobile/v1/me/route': mobile },
      {
        [mobile]: 'const path="/api/webhooks/revenuecat"',
      },
    )
    expect(surface.forbiddenAdministrativeBundleReferences).toEqual([`${mobile}:/webhooks/`])
  })

  it('allows the exact own Next client manifest but still scans its contents', () => {
    const name = 'route_client-reference-manifest.js'
    const surface = inspect(undefined, {}, [], {
      [name]: 'globalThis.__RSC_MANIFEST["/api/webhooks/revenuecat/route"]={}',
    })
    expect(surface.forbiddenAdministrativeBundleReferences).toEqual([])
    const foreign = inspect(undefined, {}, [], { [name]: 'const path="/api/webhooks/stripe"' })
    expect(foreign.forbiddenAdministrativeBundleReferences).toEqual([
      `${target}:${name}:/webhooks/`,
    ])
  })

  it('denies even its own route identity in an arbitrary transitive chunk', () => {
    const surface = inspect(undefined, {}, [], {
      'shared.js': 'const path="/api/webhooks/revenuecat"',
    })
    expect(surface.forbiddenAdministrativeBundleReferences).toEqual([
      `${target}:shared.js:/webhooks/`,
    ])
  })
})
