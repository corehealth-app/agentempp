import { spawnSync } from 'node:child_process'
import { createHash } from 'node:crypto'
import {
  existsSync,
  mkdirSync,
  mkdtempSync,
  readdirSync,
  readFileSync,
  realpathSync,
  rmSync,
  symlinkSync,
  writeFileSync,
} from 'node:fs'
import { tmpdir } from 'node:os'
import { basename, dirname, relative, resolve, sep } from 'node:path'
import { fileURLToPath } from 'node:url'
import { describe, expect, test } from 'vitest'
import { inspectBuildSurface } from '../scripts/verify-build-surface.mjs'

const sourceRoot = resolve(
  dirname(fileURLToPath(import.meta.url)),
  '../../admin/src/app/api/mobile/v1',
)
const appRoot = resolve(dirname(fileURLToPath(import.meta.url)), '..')
const dedicatedSourceRoot = resolve(appRoot, 'src')
const dedicatedAppRoot = resolve(dedicatedSourceRoot, 'app')
const mobileRouteRoot = resolve(dedicatedAppRoot, 'api/mobile/v1')
const publicRoot = resolve(appRoot, 'public')
const buildRoot = resolve(appRoot, '.next')
const appPathsManifestPath = resolve(buildRoot, 'server/app-paths-manifest.json')

const allowedRouteExports = new Set([
  'GET',
  'POST',
  'PUT',
  'PATCH',
  'DELETE',
  'HEAD',
  'OPTIONS',
  'runtime',
  'dynamic',
  'revalidate',
  'fetchCache',
  'preferredRegion',
  'maxDuration',
  'dynamicParams',
])

function walkFiles(root: string): string[] {
  if (!existsSync(root)) return []

  return readdirSync(root, { withFileTypes: true }).flatMap((entry) => {
    const path = resolve(root, entry.name)
    return entry.isDirectory() ? walkFiles(path) : [path]
  })
}

function routeExports(source: string): string[] {
  return Array.from(
    source.matchAll(/^export\s+(?:const|async\s+function|function)\s+([A-Za-z_$][\w$]*)/gm),
    (match) => match[1],
  ).sort()
}

function hasServerActionDirective(source: string): boolean {
  return /^[\t ]*["']use server["'];?/m.test(source)
}

function sourceRecords(): Array<{ path: string; exports: string[] }> {
  return walkFiles(sourceRoot)
    .filter((path) => path.endsWith(`${sep}route.ts`))
    .map((path) => ({
      path: relative(sourceRoot, path).split(sep).join('/'),
      exports: routeExports(readFileSync(path, 'utf8')),
    }))
    .sort((left, right) => left.path.localeCompare(right.path, 'en'))
}

function hashRecords(records: Array<{ path: string; exports: string[] }>) {
  const canonicalStream = records
    .map((record) => `${record.path}\0${record.exports.join(',')}\n`)
    .join('')
  return createHash('sha256').update(canonicalStream).digest('hex')
}

function currentAppPathsManifest(): Record<string, string> {
  return JSON.parse(readFileSync(appPathsManifestPath, 'utf8'))
}

function withSyntheticBuild<T>(
  appPaths: Record<string, string>,
  inspect: (root: string) => T,
  omittedTargets: string[] = [],
  targetContents: Record<string, string> = {},
  traceFilesByTarget: Record<string, string[]> = {},
  prepare?: (root: string) => void,
): T {
  const root = mkdtempSync(resolve(appRoot, '.mobile-bff-build-surface-'))
  try {
    const serverRoot = resolve(root, 'server')
    mkdirSync(serverRoot, { recursive: true })
    writeFileSync(resolve(serverRoot, 'app-paths-manifest.json'), JSON.stringify(appPaths))
    writeFileSync(
      resolve(root, 'routes-manifest.json'),
      JSON.stringify({ staticRoutes: [], dynamicRoutes: [], dataRoutes: [] }),
    )
    writeFileSync(
      resolve(serverRoot, 'middleware-manifest.json'),
      JSON.stringify({ middleware: {} }),
    )
    writeFileSync(
      resolve(serverRoot, 'server-reference-manifest.json'),
      JSON.stringify({ node: {}, edge: {} }),
    )

    for (const target of new Set(Object.values(appPaths))) {
      if (omittedTargets.includes(target)) continue
      const targetPath = resolve(serverRoot, target)
      mkdirSync(dirname(targetPath), { recursive: true })
      writeFileSync(targetPath, targetContents[target] ?? 'export {}\n')
      writeFileSync(
        `${targetPath}.nft.json`,
        JSON.stringify({ version: 1, files: traceFilesByTarget[target] ?? [] }),
      )
    }

    prepare?.(root)

    return inspect(root)
  } finally {
    rmSync(root, { recursive: true, force: true })
  }
}

describe('authoritative Mobile API source surface', () => {
  test('keeps the frozen 54-route path and named-export manifest', () => {
    const records = sourceRecords()
    const hash = hashRecords(records)

    console.info(`SOURCE_ROUTE_EXPORT_COUNT=${records.length}`)
    console.info(`SOURCE_ROUTE_EXPORT_STREAM_SHA256=${hash}`)

    expect(records).toHaveLength(54)
    expect(hash).toBe('0f076fc83228e8742e107ba4bb9631019b6d1e6edc74fbd36039c574b228c1a3')
  })

  test('contains no export outside the Next Route Handler allowlist', () => {
    const invalidExports = sourceRecords().flatMap((record) =>
      record.exports
        .filter((name) => !allowedRouteExports.has(name))
        .map((name) => `${record.path}:${name}`),
    )

    console.info(`SOURCE_ROUTE_INVALID_EXPORT_COUNT=${invalidExports.length}`)
    expect(invalidExports).toEqual([])
  })

  test('keeps the dedicated app free of forbidden Next surfaces', () => {
    const sourceFiles = walkFiles(dedicatedSourceRoot)
    const appFiles = walkFiles(dedicatedAppRoot)
    const pages = appFiles.filter((path) => /^page\.[cm]?[jt]sx?$/.test(basename(path)))
    const layouts = appFiles.filter((path) => /^layout\.[cm]?[jt]sx?$/.test(basename(path)))
    const middleware = sourceFiles.filter((path) =>
      /^middleware\.[cm]?[jt]sx?$/.test(basename(path)),
    )
    const serverActions = sourceFiles.filter((path) =>
      hasServerActionDirective(readFileSync(path, 'utf8')),
    )
    const publicFiles = walkFiles(publicRoot)
    const routesOutsideMobilePrefix = appFiles.filter(
      (path) =>
        /^route\.[cm]?[jt]sx?$/.test(basename(path)) &&
        relative(mobileRouteRoot, path).startsWith(`..${sep}`),
    )

    console.info(`SOURCE_PAGE_FILE_COUNT=${pages.length}`)
    console.info(`SOURCE_LAYOUT_FILE_COUNT=${layouts.length}`)
    console.info(`SOURCE_MIDDLEWARE_FILE_COUNT=${middleware.length}`)
    console.info(`SOURCE_SERVER_ACTION_FILE_COUNT=${serverActions.length}`)
    console.info(`SOURCE_PUBLIC_FILE_COUNT=${publicFiles.length}`)
    console.info(`SOURCE_OUT_OF_PREFIX_ROUTE_FILE_COUNT=${routesOutsideMobilePrefix.length}`)

    expect(pages).toEqual([])
    expect(layouts).toEqual([])
    expect(middleware).toEqual([])
    expect(serverActions).toEqual([])
    expect(publicFiles).toEqual([])
    expect(routesOutsideMobilePrefix).toEqual([])
  })

  test('detects a horizontally indented inline Server Action directive', () => {
    const inlineServerAction = ['async function submit() {', "\t'use server';", '}'].join('\n')

    expect(hasServerActionDirective(inlineServerAction)).toBe(true)
  })

  test('keeps the structured Next build surface limited to the 54 Mobile API routes', () => {
    const surface = inspectBuildSurface(buildRoot)

    console.info(`BUILD_ROUTE_PATH_COUNT=${surface.routePaths.length}`)
    console.info(`BUILD_ROUTE_PATH_STREAM_SHA256=${surface.routePathHash}`)
    console.info(`BUILD_FORBIDDEN_ADMIN_ROUTE_COUNT=${surface.forbiddenAdminRoutes.length}`)
    console.info(`BUILD_FORBIDDEN_INNGEST_ROUTE_COUNT=${surface.forbiddenInngestRoutes.length}`)
    console.info(`BUILD_FORBIDDEN_STRIPE_ROUTE_COUNT=${surface.forbiddenStripeRoutes.length}`)
    console.info(
      `BUILD_FORBIDDEN_ADMIN_MEDIA_ROUTE_COUNT=${surface.forbiddenAdminMediaRoutes.length}`,
    )
    console.info(`BUILD_PAGE_ROUTE_COUNT=${surface.pageRoutes.length}`)
    console.info(`BUILD_MIDDLEWARE_COUNT=${surface.middlewareEntries.length}`)
    console.info(`BUILD_SERVER_ACTION_REFERENCE_COUNT=${surface.serverActionReferences.length}`)

    expect(surface.routePaths).toHaveLength(54)
    expect(surface.routePathHash).toBe(
      '575bdb7757a730761d443ee35ee9749c90df5e85263e482e5bd70446bfef3d2b',
    )
    expect(surface.routesOutsideMobilePrefix).toEqual([])
    expect(surface.forbiddenAdminRoutes).toEqual([])
    expect(surface.forbiddenInngestRoutes).toEqual([])
    expect(surface.forbiddenStripeRoutes).toEqual([])
    expect(surface.forbiddenAdminMediaRoutes).toEqual([])
    expect(surface.pageRoutes).toEqual([])
    expect(surface.middlewareEntries).toEqual([])
    expect(surface.serverActionReferences).toEqual([])
  })

  test.each([
    {
      name: 'a coherent-looking target assigned to the wrong URL',
      expectedError: /APP_PATH_BUNDLE_TARGET_MISMATCH/,
      mutate: (appPaths: Record<string, string>) => ({
        ...appPaths,
        '/api/mobile/v1/today/route': 'app/api/mobile/v1/today-wrong/route.js',
      }),
      omittedTargets: [] as string[],
    },
    {
      name: 'one target shared by two application routes',
      expectedError: /APP_PATH_BUNDLE_TARGET_DUPLICATE/,
      mutate: (appPaths: Record<string, string>) => ({
        ...appPaths,
        '/api/mobile/v1/today/route': appPaths['/api/mobile/v1/me/route'],
      }),
      omittedTargets: [] as string[],
    },
    {
      name: 'a target outside app/api/mobile/v1',
      expectedError: /APP_PATH_BUNDLE_TARGET_OUTSIDE_MOBILE_ROUTE/,
      mutate: (appPaths: Record<string, string>) => ({
        ...appPaths,
        '/api/mobile/v1/today/route': 'app/api/admin/route.js',
      }),
      omittedTargets: [] as string[],
    },
    {
      name: 'a coherent target missing below the build server root',
      expectedError: /APP_PATH_BUNDLE_TARGET_MISSING/,
      mutate: (appPaths: Record<string, string>) => ({ ...appPaths }),
      omittedTargets: ['app/api/mobile/v1/today/route.js'],
    },
  ])('rejects $name while the same 54 URL keys remain', ({
    expectedError,
    mutate,
    omittedTargets,
  }) => {
    const appPaths = mutate(currentAppPathsManifest())

    expect(Object.keys(appPaths)).toHaveLength(54)
    expect(() => withSyntheticBuild(appPaths, inspectBuildSurface, omittedTargets)).toThrow(
      expectedError,
    )
  })

  test('excludes only the exact internal not-found page without rewriting other page identities', () => {
    const appPaths = {
      ...currentAppPathsManifest(),
      '/_not-found/page': 'app/_not-found/page.js',
      '/_not-found': 'app/_not-found.js',
      '/page': 'app/page.js',
    }

    const surface = withSyntheticBuild(appPaths, inspectBuildSurface)

    expect(surface.pageRoutes).toContain('/_not-found')
    expect(surface.pageRoutes).toContain('/page')
    expect(surface.pageRoutes).not.toContain('/_not-found/page')
    expect(surface.pageRoutes).not.toContain('/')
  })

  test('rejects a worker graph marker embedded in a Mobile route bundle', () => {
    const appPaths = currentAppPathsManifest()
    const target = appPaths['/api/mobile/v1/media/route']
    const surface = withSyntheticBuild(appPaths, inspectBuildSurface, [], {
      [target]: 'const worker = processMessageFn\n',
    })

    expect(surface.forbiddenWorkerBundleReferences).toEqual([`${target}:processMessageFn`])
  })

  test('rejects a worker source recorded in a Mobile route trace', () => {
    const appPaths = currentAppPathsManifest()
    const target = appPaths['/api/mobile/v1/media/route']
    const surface = withSyntheticBuild(
      appPaths,
      inspectBuildSurface,
      [],
      {},
      {
        [target]: [
          resolve(appRoot, '../../packages/inngest-functions/src/functions/process-message.ts'),
        ],
      },
    )

    expect(surface.forbiddenWorkerTraceReferences).toEqual([
      `${target}:packages/inngest-functions/src/functions/process-message.ts`,
    ])
  })

  test('rejects an administrative route marker embedded in a Mobile bundle', () => {
    const appPaths = currentAppPathsManifest()
    const target = appPaths['/api/mobile/v1/me/route']
    const surface = withSyntheticBuild(appPaths, inspectBuildSurface, [], {
      [target]: 'const forbidden = "/api/admin/users"\n',
    })

    expect(surface.forbiddenAdministrativeBundleReferences).toEqual([`${target}:/api/admin/`])
  })

  test('keeps worker and administrative transitives out of the real build graph', () => {
    const surface = inspectBuildSurface(buildRoot)

    expect(surface.forbiddenWorkerBundleReferences).toEqual([])
    expect(surface.forbiddenWorkerTraceReferences).toEqual([])
    expect(surface.forbiddenAdministrativeBundleReferences).toEqual([])
    expect(surface.forbiddenAdministrativeTraceReferences).toEqual([])
    // Original50, excluding the single approved B4a finalization chunk, retain
    // 5320 references/175 targets. The provenance/read-model split adds one
    // chunk reference to 11 routes. Workout capability in /me and /pending
    // adds three more each: its chunk, the existing media/client chunk and
    // the Inngest package manifest. No new non-chunk target is introduced.
    // C11 adds107 references and its manifest.
    // Each body-photo route adds109: the106 media references, its prior shared
    // handler chunk, B4a's finalization chunk, and the agent package manifest
    // needed by the pure signup-body-fat-estimate leaf (no agent barrel chunks).
    // That finalization chunk is
    // referenced by exactly onboarding plus the three body-photo routes.
    // 5320 + 1 + 107 + 3 x 109 = 5755 references; 175 + 1 + 1 + 3 + 1 = 181 targets.
    // The agent manifest already belongs to the original50: no new unique target.
    // Keep exact totals, original50 sans this chunk, nine Flow catalogs and guards.
    expect(surface.nftReferenceCount).toBe(5755)
    expect(surface.nftUniqueTargetCount).toBe(181)
    expect(surface.nftRegularFileTargetCount).toBe(179)
    expect(surface.nftDirectoryTargetCount).toBe(2)

    const bodyPhotoRoutes = [
      '/api/mobile/v1/onboarding/body-photos/route',
      '/api/mobile/v1/onboarding/body-photos/consent/route',
      '/api/mobile/v1/onboarding/body-photos/[id]/complete/route',
    ]
    const addedRoutes: Record<string, number> = {
      '/api/mobile/v1/meal-records/[id]/route': 107,
      ...Object.fromEntries(bodyPhotoRoutes.map((route) => [route, 109])),
    }
    const physicalTargets = (route: string): string[] => {
      const target = currentAppPathsManifest()[route]
      expect(target, route).toBeTypeOf('string')
      const tracePath = resolve(buildRoot, 'server', `${target}.nft.json`)
      const trace: { files: string[] } = JSON.parse(readFileSync(tracePath, 'utf8'))
      return trace.files.map((reference) => realpathSync(resolve(dirname(tracePath), reference)))
    }
    const ownManifest = (route: string): string =>
      realpathSync(
        resolve(
          buildRoot,
          `server/app${route.slice(0, -'/route'.length)}/route_client-reference-manifest.js`,
        ),
      )

    // Identify the sole new chunk by physical identity, not a generated number.
    // The original49 other routes cannot reference it; the onboarding manifest
    // is still its separate existing unique file.
    const onboardingRoute = '/api/mobile/v1/onboarding/route'
    const otherOriginalTargets = new Set(
      Object.keys(currentAppPathsManifest())
        .filter((route) => !Object.hasOwn(addedRoutes, route) && route !== onboardingRoute)
        .flatMap(physicalTargets),
    )
    const finalizationChunks = [...new Set(physicalTargets(onboardingRoute))].filter(
      (target) => !otherOriginalTargets.has(target) && target !== ownManifest(onboardingRoute),
    )
    expect(finalizationChunks).toHaveLength(1)
    const [finalizationChunk = ''] = finalizationChunks
    expect(relative(resolve(buildRoot, 'server/chunks'), finalizationChunk)).toMatch(
      /^[\w.-]+\.js$/,
    )
    const finalizationSource = readFileSync(finalizationChunk, 'utf8')
    // Task4 replaces the deferred default with the strict durable RPC protocol.
    // Keep the physical chunk boundary and every original graph guard below.
    expect(finalizationSource).not.toContain('deferred_rule')
    expect(finalizationSource).toContain('prepare_mobile_signup_body_photo_disposition')
    expect(finalizationSource).toContain('get_mobile_signup_body_photo_disposition_page')
    expect(finalizationSource).toContain('commit_mobile_signup_body_photo_disposition_page')
    expect(finalizationSource).toContain('delete_all_signup_v1')
    expect(finalizationSource).toContain('remaining_count')
    expect(finalizationSource).toContain('body_photo_cleanup_pending')
    const byName = (left: string, right: string) => left.localeCompare(right, 'en')
    expect(
      Object.keys(currentAppPathsManifest())
        .filter((route) => physicalTargets(route).includes(finalizationChunk))
        .sort(byName),
    ).toEqual([onboardingRoute, ...bodyPhotoRoutes].sort(byName))

    const baselineTargets = new Set<string>()
    let baselineReferences = 0
    for (const route of Object.keys(currentAppPathsManifest())) {
      if (Object.hasOwn(addedRoutes, route)) continue
      const targets = physicalTargets(route).filter((target) => target !== finalizationChunk)
      baselineReferences += targets.length
      for (const target of targets) baselineTargets.add(target)
    }
    expect(baselineReferences).toBe(5320)
    expect(baselineTargets.size).toBe(175)

    const beyondBaseline = (route: string): string[] =>
      [...new Set(physicalTargets(route))].filter((target) => !baselineTargets.has(target))
    for (const [addedRoute, references] of Object.entries(addedRoutes)) {
      expect(physicalTargets(addedRoute), addedRoute).toHaveLength(references)
    }
    expect(beyondBaseline('/api/mobile/v1/meal-records/[id]/route')).toEqual([
      ownManifest('/api/mobile/v1/meal-records/[id]/route'),
    ])

    // The one chunk the three body-photo routes share, whatever number the
    // bundler gives it: inside the build's own chunks, and of these three only.
    const sharedChunks = new Set<string>()
    const agentManifest = realpathSync(resolve(appRoot, '../../packages/agent/package.json'))
    expect(baselineTargets.has(agentManifest)).toBe(true)
    for (const route of bodyPhotoRoutes) {
      expect(
        physicalTargets(route).filter((target) => target === agentManifest),
        route,
      ).toEqual([agentManifest])
      const extras = beyondBaseline(route).filter(
        (target) => target !== ownManifest(route) && target !== finalizationChunk,
      )
      expect(extras, route).toHaveLength(1)
      expect(beyondBaseline(route), route).toHaveLength(3)
      expect(beyondBaseline(route), route).toContain(finalizationChunk)
      expect(beyondBaseline(route), route).toContain(ownManifest(route))
      sharedChunks.add(extras[0] ?? '')
    }
    expect(sharedChunks.size).toBe(1)
    const [sharedChunk = ''] = [...sharedChunks]
    expect(relative(resolve(buildRoot, 'server/chunks'), sharedChunk)).toMatch(/^[\w.-]+\.js$/)
    expect(
      Object.keys(currentAppPathsManifest())
        .filter((route) => physicalTargets(route).includes(sharedChunk))
        .sort(byName),
    ).toEqual([...bodyPhotoRoutes].sort(byName))
  })

  test('limits the versioned workout capability chunk to its five review routes', () => {
    const chunks = walkFiles(resolve(buildRoot, 'server/chunks')).filter(
      (path) =>
        path.endsWith('.js') &&
        readFileSync(path, 'utf8').includes('get_mobile_workout_registration'),
    )
    expect(chunks).toHaveLength(1)
    const workoutChunk = realpathSync(chunks[0])
    const source = readFileSync(workoutChunk, 'utf8')
    for (const operation of ['admit', 'materialize', 'get', 'edit', 'cancel', 'confirm']) {
      expect(source).toContain(`${operation}_mobile_workout_registration`)
    }
    expect(source).toContain('MOBILE_WORKOUT_REGISTRATION_PROJECT_REF')
    expect(source).toContain('ui-v1')

    const routes = Object.entries(currentAppPathsManifest())
      .filter(([, target]) => {
        const tracePath = resolve(buildRoot, 'server', `${target}.nft.json`)
        const trace: { files: string[] } = JSON.parse(readFileSync(tracePath, 'utf8'))
        return trace.files.some(
          (reference) => realpathSync(resolve(dirname(tracePath), reference)) === workoutChunk,
        )
      })
      .map(([route]) => route)
      .sort()
    expect(routes).toEqual([
      '/api/mobile/v1/me/route',
      '/api/mobile/v1/pending/route',
      '/api/mobile/v1/registrations/[id]/confirm/route',
      '/api/mobile/v1/registrations/[id]/route',
      '/api/mobile/v1/registrations/propose/route',
    ])
  })

  test('traces the nine byte-exact approved catalogs only from the Flow route', () => {
    const repositoryRoot = resolve(appRoot, '../..')
    const catalogPrefix = 'packages/agent/src/data/flow-curated-phrases/'
    const actual: Record<string, Record<string, string>> = {}
    for (const [route, target] of Object.entries(currentAppPathsManifest())) {
      const tracePath = resolve(buildRoot, 'server', `${target}.nft.json`)
      const trace: { files: string[] } = JSON.parse(readFileSync(tracePath, 'utf8'))
      for (const reference of trace.files) {
        const physical = realpathSync(resolve(dirname(tracePath), reference))
        const repositoryPath = relative(repositoryRoot, physical).split(sep).join('/')
        if (!repositoryPath.startsWith(catalogPrefix)) continue
        actual[route] ??= {}
        const name = repositoryPath.slice(catalogPrefix.length)
        expect(Object.hasOwn(actual[route], name)).toBe(false)
        actual[route][name] = createHash('sha256').update(readFileSync(physical)).digest('hex')
      }
    }
    expect(actual).toEqual({
      '/api/mobile/v1/flow/chat/route': {
        'curated-phrases-engagement.json':
          'f8df3c9b1be8f40ead0bff1f97888cfe3d2534c05d928fd50892487f8f61f54c',
        'curated-phrases-food-phase-b.json':
          '90ed182a90681cdec3d8e6d83f3340645ee645570e3fd9d4530386551cacf222',
        'curated-phrases-food-phase-c.json':
          '56905ce0fd4438534587b025adb423ece63edb515f07d417af45966709036d70',
        'curated-phrases-food-phase-c2.json':
          '246c9650e28788ef6b9181986a04a04894dea5a8da8ee52fd9ed25b1e982a304',
        'curated-phrases-food-phase-d.json':
          '1f1ffc4c83bbda18db2b4966fb7a2275f2321ef5c4f09b8dfe53afa31ab73577',
        'curated-phrases-food-phase-e.json':
          '1048d3e3fba17d5f667270ae5d80973c2f2031c27fd78b2dee2418ca6847af33',
        'curated-phrases-food-phase-f.json':
          '991d1a9e3af61a5ef0b11914b1abdeebb6042df242d67681fc0cc85df4554af0',
        'curated-phrases-food-phase-g.json':
          'ce31c1e42ffdb715ed38b0961efb341ac730a2c4c809e13027576cb1fa172923',
        'curated-phrases-food.json':
          'd411b0afce13b8f3bc5fba7cb970e7edf49780cc79eca7b312071fc24b7612ca',
      },
    })
  })

  test('rejects an NFT target that is absent', () => {
    const appPaths = currentAppPathsManifest()
    const target = appPaths['/api/mobile/v1/today/route']

    expect(() =>
      withSyntheticBuild(
        appPaths,
        inspectBuildSurface,
        [],
        {},
        { [target]: ['missing-dependency.js'] },
      ),
    ).toThrow(/NFT_TARGET_MISSING:.*missing-dependency\.js/)
  })

  test('rejects an arbitrary internal NFT directory', () => {
    const appPaths = currentAppPathsManifest()
    const target = appPaths['/api/mobile/v1/today/route']

    expect(() =>
      withSyntheticBuild(
        appPaths,
        inspectBuildSurface,
        [],
        {},
        { [target]: ['structural-package'] },
        (root) => {
          mkdirSync(resolve(root, 'server', dirname(target), 'structural-package'))
        },
      ),
    ).toThrow(/NFT_DIRECTORY_NOT_LEXICAL_SYMLINK:.*structural-package/)
  })

  test.each([
    {
      name: 'worker functions root',
      reference: resolve(appRoot, '../../packages/inngest-functions/src/functions'),
      expectedError:
        /NFT_DIRECTORY_FORBIDDEN_WORKER:.*packages\/inngest-functions\/src\/functions\//,
    },
    {
      name: 'worker lib root',
      reference: resolve(appRoot, '../../packages/inngest-functions/src/lib'),
      expectedError: /NFT_DIRECTORY_FORBIDDEN_WORKER:.*packages\/inngest-functions\/src\/lib\//,
    },
    {
      name: 'admin root',
      reference: resolve(appRoot, '../admin/src/app/(admin)'),
      expectedError: /NFT_DIRECTORY_FORBIDDEN_ADMINISTRATIVE:.*apps\/admin\/src\/app\/\(admin\)\//,
    },
  ])('rejects an NFT directory at the $name', ({ reference, expectedError }) => {
    const appPaths = currentAppPathsManifest()
    const target = appPaths['/api/mobile/v1/today/route']

    expect(() =>
      withSyntheticBuild(appPaths, inspectBuildSurface, [], {}, { [target]: [reference] }),
    ).toThrow(expectedError)
  })

  test('rejects an existing internal NFT special file', () => {
    const appPaths = currentAppPathsManifest()
    const target = appPaths['/api/mobile/v1/today/route']

    expect(() =>
      withSyntheticBuild(
        appPaths,
        inspectBuildSurface,
        [],
        {},
        { [target]: ['special-dependency'] },
        (root) => {
          const specialPath = resolve(root, 'server', dirname(target), 'special-dependency')
          const result = spawnSync('mkfifo', [specialPath], { encoding: 'utf8' })
          expect(result.status, result.stderr).toBe(0)
        },
      ),
    ).toThrow(/NFT_TARGET_UNSUPPORTED_TYPE:.*special-dependency/)
  })

  test('rejects an NFT JavaScript target whose realpath leaves the monorepo', () => {
    const externalRoot = mkdtempSync(resolve(tmpdir(), 'mobile-bff-external-target-'))
    const externalFile = resolve(externalRoot, 'external-dependency.js')
    writeFileSync(externalFile, 'export {}\n')

    try {
      const appPaths = currentAppPathsManifest()
      const target = appPaths['/api/mobile/v1/today/route']

      expect(() =>
        withSyntheticBuild(
          appPaths,
          inspectBuildSurface,
          [],
          {},
          { [target]: ['external-dependency.js'] },
          (root) => {
            symlinkSync(
              externalFile,
              resolve(root, 'server', dirname(target), 'external-dependency.js'),
            )
          },
        ),
      ).toThrow(/NFT_TARGET_EXTERNAL:.*external-dependency\.js/)
    } finally {
      rmSync(externalRoot, { recursive: true, force: true })
    }
  })
})
