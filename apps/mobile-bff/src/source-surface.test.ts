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
import { currentClinicalRouteAdditions } from './current-clinical-route-inventory'

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
const reviewRoutes = [
  'me',
  'pending',
  'registrations/[id]/confirm',
  'registrations/[id]',
  'registrations/propose',
]
  .map((name) => `/api/mobile/v1/${name}/route`)
  .sort()
const historyFeedbackRoutes = [
  '/api/mobile/v1/meal-records/[id]/route',
  '/api/mobile/v1/workouts/[id]/strength-clarification/route',
]
const catalogRoutes = ['/api/mobile/v1/flow/chat/route', ...reviewRoutes].sort()

function tracedTargets(route: string): string[] {
  const target = currentAppPathsManifest()[route]
  expect(target, route).toBeTypeOf('string')
  const tracePath = resolve(buildRoot, 'server', `${target}.nft.json`)
  const trace: { files: string[] } = JSON.parse(readFileSync(tracePath, 'utf8'))
  return trace.files.map((reference) => realpathSync(resolve(dirname(tracePath), reference)))
}

function semanticChunks(markers: string[]): string[] {
  const chunksRoot = realpathSync(resolve(buildRoot, 'server/chunks'))
  return walkFiles(resolve(buildRoot, 'server/chunks'))
    .filter((path) => {
      if (!path.endsWith('.js')) return false
      const source = readFileSync(path, 'utf8')
      return markers.every((marker) => source.includes(marker))
    })
    .map((path) => {
      const physical = realpathSync(path)
      expect(relative(chunksRoot, physical), path).toMatch(/^[\w.-]+\.js$/)
      return physical
    })
}

function chunkConsumers(chunk: string): string[] {
  return Object.keys(currentAppPathsManifest())
    .filter((route) => tracedTargets(route).includes(chunk))
    .sort()
}

function runtimeMarkerRoutes(marker: string): string[] {
  const sources = new Map<string, string>()
  return Object.entries(currentAppPathsManifest())
    .filter(([route, target]) =>
      [resolve(buildRoot, 'server', target), ...tracedTargets(route)].some((path) => {
        if (!path.endsWith('.js')) return false
        if (!sources.has(path)) sources.set(path, readFileSync(path, 'utf8'))
        return sources.get(path)?.includes(marker)
      }),
    )
    .map(([route]) => route)
    .sort()
}

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
  test('keeps the approved 74-route path and named-export manifest', () => {
    const records = sourceRecords()
    const hash = hashRecords(records)

    console.info(`SOURCE_ROUTE_EXPORT_COUNT=${records.length}`)
    console.info(`SOURCE_ROUTE_EXPORT_STREAM_SHA256=${hash}`)

    expect(records).toHaveLength(74)
    expect(hash).toBe('9c7daf99f0c9baab62f037d3d9301417c4a025283e863f44cd4dfab77588e485')
    const additions = new Set<string>(currentClinicalRouteAdditions)
    const prior56 = records.filter((record) => !additions.has(record.path))
    expect(prior56).toHaveLength(56)
    expect(hashRecords(prior56)).toBe(
      'b88a27d2d694fb0ca539b9075c369978956d51aa25427b52da46983919b7d0e8',
    )
    const beforeIntents = prior56.filter(
      (record) => record.path !== 'onboarding/completion-intent/route.ts',
    )
    expect(beforeIntents).toHaveLength(55)
    expect(hashRecords(beforeIntents)).toBe(
      '96da71b91e2f8f7a730c98b2388128fdd840846437a4bbcf238dd8dd2fb4a62d',
    )
    const previous = beforeIntents.filter(
      (record) => record.path !== 'workouts/[id]/strength-clarification/route.ts',
    )
    expect(previous).toHaveLength(54)
    expect(hashRecords(previous)).toBe(
      '0f076fc83228e8742e107ba4bb9631019b6d1e6edc74fbd36039c574b228c1a3',
    )
    expect(records.some((record) => record.path === 'auth/password-recovery/route.ts')).toBe(false)
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

  test('keeps the structured Next build surface limited to the 74 Mobile API routes', () => {
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

    expect(surface.routePaths).toHaveLength(74)
    expect(surface.routePathHash).toBe(
      '266398770b61425d8172e2912eade6187a597060c710c51dcfbaff6fc7c8a272',
    )
    const additions = new Set(
      currentClinicalRouteAdditions.map(
        (path) => `/api/mobile/v1/${path.replace(/\/route.ts$/, '')}`,
      ),
    )
    const prior56 = surface.routePaths.filter((route) => !additions.has(route))
    expect(prior56).toHaveLength(56)
    expect(
      createHash('sha256')
        .update(prior56.map((route) => `${route}\n`).join(''))
        .digest('hex'),
    ).toBe('75c8979e64a793a209a621914eec758d1b061820b30c68488622900c2b3bf71a')
    const beforeIntents = prior56.filter(
      (route) => route !== '/api/mobile/v1/onboarding/completion-intent',
    )
    expect(beforeIntents).toHaveLength(55)
    expect(
      createHash('sha256')
        .update(beforeIntents.map((route) => `${route}\n`).join(''))
        .digest('hex'),
    ).toBe('5518c2a2938b4d95b86d7ac6c00d20b1dd2cdb4cfd716d141682708edbabd1b7')
    const previous = beforeIntents.filter(
      (route) => route !== '/api/mobile/v1/workouts/[id]/strength-clarification',
    )
    expect(previous).toHaveLength(54)
    expect(
      createHash('sha256')
        .update(previous.map((route) => `${route}\n`).join(''))
        .digest('hex'),
    ).toBe('575bdb7757a730761d443ee35ee9749c90df5e85263e482e5bd70446bfef3d2b')
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
  ])('rejects $name while the same 74 URL keys remain', ({
    expectedError,
    mutate,
    omittedTargets,
  }) => {
    const appPaths = mutate(currentAppPathsManifest())

    expect(Object.keys(appPaths)).toHaveLength(74)
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
    // Baseline54: 5320 + 1 + 107 + 3 x 109 = 5755 references/181 targets.
    // Clarification adds105 references/its manifest; the pure fact parser adds
    // one reference to each of six old routes and one unique chunk.
    // Current55: 5755 + 105 + 6 = 5866 references/183 targets.
    // Completion intent adds104 references and only its own manifest target.
    // Every previous route keeps its exact reference count, and the original50
    // semantic graph below remains5320 references/175 targets.
    // Current56 before quantity display:5866+104=5970 references/184 targets.
    // Milk/whey quantity display moves the existing draft/media modules into
    // one shared chunk, adding one reference to exactly six original routes.
    // The frozen E2 comparison found no other target addition or removal.
    // Current56:5970+6=5976 references/185 targets; reachability is locked below.
    // Auth is excluded. Its observed vendor split is not this release surface.
    // The agent manifest already belongs to the original50: no new unique target.
    // C13 adds57 references:45 catalog JSONs in five review routes, six
    // selector references, two History receipt references and four existing
    // read-model/state/legacy-selector references newly reached by History.
    // The workout RW chunk replaces its predecessor with zero net references.
    // Every contribution is identified by semantics and exact consumers below;
    // normalization must reproduce the prior per-route counts and semantic
    // boundaries below; it is not byte identity of compiled JavaScript.
    // R301 adds one 104-reference documents-only entry. Current admission and
    // calculation/runtime splits add 20 historical and 17 clinical references;
    // each new edge is tied to named semantics and exact consumers below.
    expect(surface.nftReferenceCount).toBe(8028)
    expect(surface.nftUniqueTargetCount).toBe(214)
    expect(surface.nftRegularFileTargetCount).toBe(212)
    expect(surface.nftDirectoryTargetCount).toBe(2)

    const bodyPhotoRoutes = [
      '/api/mobile/v1/onboarding/body-photos/route',
      '/api/mobile/v1/onboarding/body-photos/consent/route',
      '/api/mobile/v1/onboarding/body-photos/[id]/complete/route',
    ]
    const clarificationRoute = '/api/mobile/v1/workouts/[id]/strength-clarification/route'
    const addedRoutes: Record<string, number> = {
      [clarificationRoute]: 105,
      '/api/mobile/v1/onboarding/completion-intent/route': 104,
      '/api/mobile/v1/meal-records/[id]/route': 107,
      ...Object.fromEntries(bodyPhotoRoutes.map((route) => [route, 109])),
    }
    const uniqueChunk = (markers: string[]): string => {
      const chunks = semanticChunks(markers)
      expect(chunks, markers.join(', ')).toHaveLength(1)
      return chunks[0] ?? ''
    }
    // M3B adds18 known routes. Explicit admission splits calculation/runtime
    // and moves five feedback handlers out of the now shared workout reader.
    // Removing precisely the 56 certified historical edges restores the same
    // per-route count stream; workout reader duplication is consolidated once.
    const allRoutes = Object.keys(currentAppPathsManifest())
    const additions = new Set(
      currentClinicalRouteAdditions.map((path) => `/api/mobile/v1/${path.replace(/\.ts$/, '')}`),
    )
    expect(additions.size).toBe(18)
    expect(allRoutes.filter((route) => additions.has(route))).toHaveLength(18)
    const historicalRoutes = allRoutes.filter((route) => !additions.has(route))
    expect(historicalRoutes).toHaveLength(56)
    expect(historicalRoutes.reduce((sum, route) => sum + tracedTargets(route).length, 0)).toBe(6089)
    expect(new Set(historicalRoutes.flatMap(tracedTargets)).size).toBe(193)
    const routeNames = (names: string[]) =>
      names.map((name) => `/api/mobile/v1/${name}/route`).sort()
    const clinicalEdges = [
      {
        markers: ['capture_mobile_clinical_day_close', 'apply_mobile_clinical_day_close'],
        old: routeNames(['flow/chat', 'plan', 'progress', 'protocol', 'today', 'trends']),
        added: [] as string[],
      },
      {
        markers: ['get_mobile_current_clinical_state', 'mobile_current_clinical_'],
        old: routeNames([
          'flow/chat',
          'onboarding',
          'onboarding/eligibility',
          'plan',
          'progress',
          'protocol',
          'today',
          'trends',
        ]),
        added: routeNames([
          'reevaluation',
          'reevaluation/start',
          'reevaluation/form',
          'reevaluation/assess',
          'reevaluation/preview',
          'reevaluation/confirm',
          'reevaluation/health',
        ]),
      },
      {
        markers: [
          'MOBILE_CURRENT_CLINICAL_PROJECT_REF',
          'current_clinical_runtime_unavailable',
          'invalid_clinical_policy_representation',
        ],
        otherAdded: routeNames([
          'reevaluation/[cycleId]/photos',
          'reevaluation/[cycleId]/photos/consent',
          'reevaluation/[cycleId]/photos/discard',
          'reevaluation/[cycleId]/photos/[assetId]/upload',
          'reevaluation/[cycleId]/photos/[assetId]/complete',
          'reevaluation/[cycleId]/photos/[assetId]/process',
        ]),
        old: routeNames([
          'flow/chat',
          'onboarding',
          'onboarding/eligibility',
          'plan',
          'progress',
          'protocol',
          'today',
          'trends',
        ]),
        added: routeNames([
          'protocol/first-phase',
          'protocol/first-phase/preview',
          'protocol/first-phase/confirm',
          'reevaluation',
          'reevaluation/start',
          'reevaluation/form',
          'reevaluation/assess',
          'reevaluation/preview',
          'reevaluation/confirm',
          'reevaluation/health',
        ]),
      },
      {
        markers: ['Invalid clinical calculation context'],
        old: routeNames([
          'flow/chat',
          'onboarding',
          'plan',
          'progress',
          'protocol',
          'today',
          'trends',
        ]),
        added: routeNames([
          'protocol/first-phase',
          'protocol/first-phase/preview',
          'protocol/first-phase/confirm',
          'reevaluation',
          'reevaluation/start',
          'reevaluation/form',
          'reevaluation/assess',
          'reevaluation/preview',
          'reevaluation/confirm',
          'reevaluation/health',
        ]),
      },
      {
        // Read-only BF provenance now shares the daily repository with legacy
        // admission. Certify all three ports in that one existing seven-route
        // chunk, while the whole closer retains its original six consumers.
        markers: [
          'admit_mobile_clinical_legacy_generation',
          'clinical_client_update_required',
          'get_mobile_clinical_daily_context',
          'get_mobile_clinical_daily_receipt',
          'apply_mobile_clinical_daily',
        ],
        old: routeNames([
          'flow/chat',
          'onboarding',
          'plan',
          'progress',
          'protocol',
          'today',
          'trends',
        ]),
        added: [] as string[],
      },
      {
        markers: [
          'Feedback requires an owned confirmed registration',
          'Invalid official day facts',
        ],
        old: reviewRoutes,
        added: [] as string[],
      },
    ]
    const exemptions = new Map<string, Set<string>>()
    const removeHistoricalEdge = (route: string, target: string) => {
      expect(
        tracedTargets(route).filter((file) => file === target),
        route,
      ).toEqual([target])
      const set = exemptions.get(route) ?? new Set<string>()
      expect(set.has(target)).toBe(false)
      set.add(target)
      exemptions.set(route, set)
    }
    for (const edge of clinicalEdges) {
      let chunk: string
      if ('otherAdded' in edge) {
        // The same closed selector is compiled once for current clinical
        // routes and once for photos; neither copy may acquire other callers.
        const copies = semanticChunks(edge.markers)
        expect(copies).toHaveLength(2)
        const historicalCopy = copies.filter((file) =>
          chunkConsumers(file).includes(edge.old[0] ?? ''),
        )
        expect(historicalCopy).toHaveLength(1)
        chunk = historicalCopy[0] ?? ''
        const photoCopy = copies.filter((file) => file !== chunk)
        expect(photoCopy).toHaveLength(1)
        expect(chunkConsumers(photoCopy[0] ?? '')).toEqual(edge.otherAdded)
      } else chunk = uniqueChunk(edge.markers)
      expect(chunkConsumers(chunk)).toEqual([...edge.old, ...edge.added].sort())
      for (const route of edge.old) removeHistoricalEdge(route, chunk)
    }
    const contractsChunk = uniqueChunk([
      'Photo source IDs must be distinct',
      'Development documents are not accepted',
    ])
    const contractsAdded = routeNames([
      'content/[id]',
      'history',
      'plan-drafts',
      'plan',
      'progress',
      'protocol',
      'today',
      'trends',
      'workouts/[id]/strength-clarification',
    ])
    expect(chunkConsumers(contractsChunk).filter((route) => additions.has(route))).toEqual(
      [...additions].sort(),
    )
    expect(
      chunkConsumers(contractsChunk).filter((route) => historicalRoutes.includes(route)),
    ).toHaveLength(50)
    for (const route of contractsAdded) removeHistoricalEdge(route, contractsChunk)
    const routineSplit = uniqueChunk([
      '[mobile-routine] database_failure',
      'Routine schedules must be updated through the item contract',
      'Unable to release mobile request claim',
    ])
    const routineConsumers = routeNames([
      'devices',
      'devices/[id]',
      'notification-preferences',
      'reminders',
      'reminders/[id]',
      'routine/hydration',
    ])
    expect(chunkConsumers(routineSplit)).toEqual(routineConsumers)
    for (const route of routineConsumers) removeHistoricalEdge(route, routineSplit)
    const historicalTargets = (route: string): string[] =>
      tracedTargets(route).filter((target) => !exemptions.get(route)?.has(target))
    const historicalConsumers = (chunk: string): string[] =>
      historicalRoutes.filter((route) => historicalTargets(route).includes(chunk)).sort()
    expect([...exemptions.values()].reduce((sum, edges) => sum + edges.size, 0)).toBe(56)
    expect(historicalRoutes.reduce((sum, route) => sum + historicalTargets(route).length, 0)).toBe(
      6033,
    )
    expect(new Set(historicalRoutes.flatMap(historicalTargets)).size).toBe(186)
    expect(
      createHash('sha256')
        .update(
          historicalRoutes
            .slice()
            .sort()
            .map((route) => `${route}\0${historicalTargets(route).length}\n`)
            .join(''),
        )
        .digest('hex'),
    ).toBe('4f8ba431b512f3a6660c4e57f32c1a42bedadbefc5deaf0c2b19945ff6e0876c')
    expect(
      createHash('sha256')
        .update(
          historicalConsumers(contractsChunk)
            .map((route) => `${route}\n`)
            .join(''),
        )
        .digest('hex'),
    ).toBe('990dab7866e742a93fa70f3c9a407b4215b8c0059a1299d253842eb99f174a92')

    const catalogChunk = uniqueChunk([
      'curated-phrases-food.json',
      'read_flow_shared_phrase_cursor',
    ])
    expect(historicalConsumers(catalogChunk)).toEqual(catalogRoutes)
    // The historical read now shares the same repository as the five reviews;
    // its query selector stays inline in precisely the two History entries.
    const receiptChunk = uniqueChunk(['read_mobile_registration_feedback'])
    expect(historicalConsumers(receiptChunk)).toEqual(
      [...historyFeedbackRoutes, ...reviewRoutes].sort(),
    )
    expect(runtimeMarkerRoutes('proposal->>source_provider_message_id')).toEqual(
      [...historyFeedbackRoutes].sort(),
    )
    const readModelChunk = uniqueChunk(['Pending registration lookup', 'Trends snapshot lookup'])
    expect(historicalConsumers(readModelChunk)).toEqual(
      [
        'flow/chat',
        'history',
        'me',
        'meal-records/[id]',
        'onboarding',
        'pending',
        'plan',
        'profile',
        'progress',
        'protocol',
        'registrations/[id]/confirm',
        'registrations/[id]',
        'registrations/propose',
        'today',
        'trends',
        'workouts/[id]/strength-clarification',
      ]
        .map((name) => `/api/mobile/v1/${name}/route`)
        .sort(),
    )
    const officialStateChunk = uniqueChunk([
      'DailyStateReadChangedError',
      'daily state consistency lookup',
    ])
    const databaseSelectorChunk = uniqueChunk([
      'curated phrase embedding lookup failed',
      '[curated-phrase] embedding cascade failed:',
    ])
    const officialConsumers = [
      'flow/chat',
      'history',
      'me',
      'meal-drafts',
      'meal-records/[id]',
      'onboarding/eligibility',
      'onboarding',
      'pending',
      'plan-drafts/[id]/confirm',
      'plan-drafts/[id]',
      'plan-drafts',
      'plan-imports',
      'plan',
      'profile',
      'progress',
      'protocol',
      'registrations/[id]/confirm',
      'registrations/[id]',
      'registrations/propose',
      'today',
      'trends',
      'workouts/[id]/strength-clarification',
    ]
      .map((name) => `/api/mobile/v1/${name}/route`)
      .sort()
    expect(historicalConsumers(officialStateChunk)).toEqual(officialConsumers)
    expect(historicalConsumers(databaseSelectorChunk)).toEqual(officialConsumers)
    expect(
      new Set([
        catalogChunk,
        receiptChunk,
        readModelChunk,
        officialStateChunk,
        databaseSelectorChunk,
      ]).size,
    ).toBe(5)

    const catalogRoot = realpathSync(
      resolve(appRoot, '../../packages/agent/src/data/flow-curated-phrases'),
    )
    const extrasByRoute = new Map<string, Set<string>>()
    for (const route of historicalRoutes) {
      const raw = historicalTargets(route)
      const extras: string[] = []
      if (catalogRoutes.includes(route)) extras.push(catalogChunk)
      if (reviewRoutes.includes(route)) {
        const catalogs = raw.filter((target) => dirname(target) === catalogRoot)
        expect(catalogs, route).toHaveLength(9)
        extras.push(...catalogs)
      }
      if (historyFeedbackRoutes.includes(route)) extras.push(receiptChunk, readModelChunk)
      if (route === clarificationRoute) extras.push(officialStateChunk, databaseSelectorChunk)
      expect(new Set(extras).size, route).toBe(extras.length)
      for (const target of extras)
        expect(
          raw.filter((path) => path === target),
          route,
        ).toEqual([target])
      extrasByRoute.set(route, new Set(extras))
    }
    expect([...extrasByRoute.values()].reduce((sum, extras) => sum + extras.size, 0)).toBe(57)
    const physicalTargets = (route: string): string[] =>
      historicalTargets(route).filter((target) => !extrasByRoute.get(route)?.has(target))
    const normalized = historicalRoutes
      .sort()
      .map((route) => [route, physicalTargets(route)] as const)
    expect(normalized.reduce((sum, [, targets]) => sum + targets.length, 0)).toBe(5976)
    expect(new Set(normalized.flatMap(([, targets]) => targets)).size).toBe(185)
    // Frozen count stream from the complete pre-C13 56-route build, not a
    // number calculated from current observed-minus-expected differences.
    expect(
      createHash('sha256')
        .update(normalized.map(([route, targets]) => `${route}\0${targets.length}\n`).join(''))
        .digest('hex'),
    ).toBe('a89cfdaa746fd822c59908f78e15920a97edcf500b09e60490693b32a287ac7c')
    const ownManifest = (route: string): string =>
      realpathSync(
        resolve(
          buildRoot,
          `server/app${route.slice(0, -'/route'.length)}/route_client-reference-manifest.js`,
        ),
      )

    // Approve the moved modules by semantics and exact consumers, never by a
    // generated chunk number or by accepting any six additional references.
    const draftChunks = walkFiles(resolve(buildRoot, 'server/chunks')).filter((path) => {
      if (!path.endsWith('.js')) return false
      const source = readFileSync(path, 'utf8')
      return ['[mobile-meal-drafts] extraction_failed', 'MealExtractionContentError'].every(
        (marker) => source.includes(marker),
      )
    })
    expect(draftChunks).toHaveLength(1)
    const draftChunk = realpathSync(draftChunks[0])
    const draftRoutes = [
      '/api/mobile/v1/me/route',
      '/api/mobile/v1/meal-drafts/route',
      '/api/mobile/v1/pending/route',
      '/api/mobile/v1/registrations/propose/route',
      '/api/mobile/v1/registrations/[id]/route',
      '/api/mobile/v1/registrations/[id]/confirm/route',
    ].sort()
    expect(
      historicalRoutes.filter((route) => physicalTargets(route).includes(draftChunk)).sort(),
    ).toEqual(draftRoutes)
    for (const route of draftRoutes) {
      expect(
        physicalTargets(route).filter((target) => target === draftChunk),
        route,
      ).toEqual([draftChunk])
    }

    // Identify the pure fact parser by stable semantics and exact reachability.
    // Generated chunk numbers are never an allowlist.
    const factChunks = walkFiles(resolve(buildRoot, 'server/chunks')).filter((path) => {
      if (!path.endsWith('.js')) return false
      const source = readFileSync(path, 'utf8')
      return ['provider_type_dedup', 'recent6h_dedup', 'catalogue_incomplete'].every((marker) =>
        source.includes(marker),
      )
    })
    expect(factChunks).toHaveLength(1)
    const factChunk = realpathSync(factChunks[0])
    const factRoutes = [
      '/api/mobile/v1/me/route',
      '/api/mobile/v1/pending/route',
      '/api/mobile/v1/registrations/[id]/confirm/route',
      '/api/mobile/v1/registrations/[id]/route',
      '/api/mobile/v1/registrations/propose/route',
      '/api/mobile/v1/today/route',
      clarificationRoute,
    ].sort()
    expect(
      historicalRoutes.filter((route) => physicalTargets(route).includes(factChunk)).sort(),
    ).toEqual(factRoutes)
    for (const route of factRoutes) {
      expect(
        physicalTargets(route).filter((target) => target === factChunk),
        route,
      ).toEqual([factChunk])
    }

    // Identify the sole new chunk by physical identity, not a generated number.
    // The original49 other routes cannot reference it; the onboarding manifest
    // is still its separate existing unique file.
    const onboardingRoute = '/api/mobile/v1/onboarding/route'
    const otherOriginalTargets = new Set(
      historicalRoutes
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
      historicalRoutes
        .filter((route) => physicalTargets(route).includes(finalizationChunk))
        .sort(byName),
    ).toEqual([onboardingRoute, ...bodyPhotoRoutes].sort(byName))

    const baselineTargets = new Set<string>()
    let baselineReferences = 0
    for (const route of historicalRoutes) {
      if (Object.hasOwn(addedRoutes, route)) continue
      const targets = physicalTargets(route).filter(
        (target) => target !== finalizationChunk && target !== factChunk,
      )
      baselineReferences += targets.length
      for (const target of targets) baselineTargets.add(target)
    }
    expect(baselineReferences).toBe(5326)
    expect(baselineTargets.size).toBe(176)
    // Removing only the separately authorized six references reproduces E2's
    // original50 graph. All other historical graph assertions stay intact.
    expect(baselineReferences - draftRoutes.length).toBe(5320)
    expect([...baselineTargets].filter((target) => target !== draftChunk)).toHaveLength(175)

    const beyondBaseline = (route: string): string[] =>
      [...new Set(physicalTargets(route))].filter((target) => !baselineTargets.has(target))
    for (const [addedRoute, references] of Object.entries(addedRoutes)) {
      expect(physicalTargets(addedRoute), addedRoute).toHaveLength(references)
    }
    expect(beyondBaseline('/api/mobile/v1/meal-records/[id]/route')).toEqual([
      ownManifest('/api/mobile/v1/meal-records/[id]/route'),
    ])

    expect(beyondBaseline('/api/mobile/v1/onboarding/completion-intent/route')).toEqual([
      ownManifest('/api/mobile/v1/onboarding/completion-intent/route'),
    ])

    expect(beyondBaseline(clarificationRoute).sort(byName)).toEqual(
      [ownManifest(clarificationRoute), factChunk].sort(byName),
    )

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
      historicalRoutes.filter((route) => physicalTargets(route).includes(sharedChunk)).sort(byName),
    ).toEqual([...bodyPhotoRoutes].sort(byName))
  })

  test('limits feedback writes to five reviews and preserves protected workout capability consumers', () => {
    const chunks = semanticChunks(['get_mobile_workout_registration'])
    // One shared repository now replaces its two compiled copies. Exact seven
    // consumers and every protected operation below remain unchanged.
    expect(chunks).toHaveLength(1)
    for (const chunk of chunks) {
      const source = readFileSync(chunk, 'utf8')
      for (const operation of ['admit', 'materialize', 'get', 'edit', 'cancel', 'confirm']) {
        expect(source).toContain(`${operation}_mobile_workout_registration`)
      }
    }
    const repositoryRoutes = [...reviewRoutes, ...historyFeedbackRoutes].sort()
    expect([...new Set(chunks.flatMap(chunkConsumers))].sort()).toEqual(repositoryRoutes)
    for (const route of Object.keys(currentAppPathsManifest())) {
      expect(
        tracedTargets(route).filter((path) => chunks.includes(path)),
        route,
      ).toHaveLength(repositoryRoutes.includes(route) ? 1 : 0)
    }
    const switchChunks = semanticChunks(['MOBILE_WORKOUT_REGISTRATION_PROJECT_REF'])
    const writerChunks = semanticChunks(['commit_mobile_registration_feedback'])
    expect(switchChunks).toHaveLength(1)
    expect(readFileSync(switchChunks[0] ?? '', 'utf8')).toContain('ui-v1')
    expect(writerChunks).toEqual(switchChunks)
    expect(chunkConsumers(switchChunks[0] ?? '')).toEqual(reviewRoutes)
    // Include entries as well as NFTs. The clarification entry already used
    // this flag before C13; its protected question is not a feedback writer.
    expect(runtimeMarkerRoutes('MOBILE_WORKOUT_REGISTRATION_PROJECT_REF')).toEqual(
      [...reviewRoutes, '/api/mobile/v1/workouts/[id]/strength-clarification/route'].sort(),
    )
    expect(runtimeMarkerRoutes('commit_mobile_registration_feedback')).toEqual(reviewRoutes)
  })

  test('keeps both History feedback reads free of catalog, cursor and feedback writer dependencies', () => {
    for (const route of historyFeedbackRoutes) {
      const target = currentAppPathsManifest()[route]
      const source = [resolve(buildRoot, 'server', target), ...tracedTargets(route)]
        .filter((path) => path.endsWith('.js'))
        .map((path) => readFileSync(path, 'utf8'))
        .join('\n')
      expect(source, route).toContain('read_mobile_registration_feedback')
      for (const marker of [
        'commit_mobile_registration_feedback',
        'read_flow_shared_phrase_cursor',
        'commit_flow_shared_phrase_reply',
        'curated-phrases-food.json',
      ])
        expect(source, `${route}: ${marker}`).not.toContain(marker)
      expect(
        tracedTargets(route).filter((path) => path.includes('/data/flow-curated-phrases/')),
        route,
      ).toEqual([])
    }
  })

  test('traces the nine byte-exact approved catalogs only from Flow and five review routes', () => {
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
    const approvedCatalogs = {
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
    }
    expect(actual).toEqual(
      Object.fromEntries(catalogRoutes.map((route) => [route, approvedCatalogs])),
    )
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
