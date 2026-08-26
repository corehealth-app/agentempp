import { createHash } from 'node:crypto'
import { existsSync, lstatSync, readFileSync, realpathSync, statSync } from 'node:fs'
import { dirname, extname, relative, resolve, sep } from 'node:path'
import { fileURLToPath } from 'node:url'

const expectedRouteCount = 40
const expectedRouteHash = 'abc24332fd370b5d7940ca56b18530a3659ba39b5205faeb2bf36771aa6f3c3a'
const internalNotFoundAppPath = '/_not-found/page'
const internalNotFoundRoute = '/_not-found'
const workerBundleMarkers = [
  'allFunctions',
  'buffer.flush',
  'bufferListenerFn',
  'createWorkerDeps',
  'day.close.tick',
  'openrouter.balance.tick',
  'openrouterBalanceCheckFn',
  'pipeline.health.tick',
  'pipelineHealthFn',
  'processMessageFn',
  'wa.quality.check',
]
const administrativeBundleMarkers = [
  '/(admin)/',
  '/api/admin/',
  '/api/inngest',
  '/api/media/',
  '/api/stripe',
  '/webhooks/',
]
const workerTracePattern = /(?:^|\/)packages\/inngest-functions\/src\/(?:index\.ts|functions\/|lib\/)/
const administrativeTracePattern = /(?:^|\/)apps\/admin\/src\/(?:middleware\.[cm]?[jt]sx?|app\/(?:\(admin\)\/|api\/(?:admin|inngest|stripe|media|webhooks)(?:\/|$)))/
const allowedStructuralDirectoryPackages = new Set([
  '@opentelemetry/api',
  'next',
])

function sha256(content) {
  return createHash('sha256').update(content).digest('hex')
}

function isRecord(value) {
  return value !== null && typeof value === 'object' && !Array.isArray(value)
}

function readJsonManifest(buildRoot, relativePath) {
  const path = resolve(buildRoot, relativePath)
  if (!existsSync(path)) throw new Error(`MANIFEST_MISSING:${relativePath}`)

  const bytes = readFileSync(path)
  let manifest
  try {
    manifest = JSON.parse(bytes.toString('utf8'))
  } catch {
    throw new Error(`MANIFEST_INVALID_JSON:${relativePath}`)
  }
  if (!isRecord(manifest)) throw new Error(`MANIFEST_INVALID_SHAPE:${relativePath}`)

  return { bytes, manifest, relativePath }
}

function sortedUnique(values) {
  return [...new Set(values)].sort((left, right) => left.localeCompare(right, 'en'))
}

function classifyAppPath(appPath, target) {
  if (appPath === internalNotFoundAppPath) {
    return { kind: 'internal', path: appPath, target }
  }
  if (appPath.endsWith('/route')) {
    return {
      kind: 'route',
      path: appPath.slice(0, -'/route'.length) || '/',
      appPath,
      target,
    }
  }
  return { kind: 'page', path: appPath, target }
}

function isMobileRouteBundleTarget(target) {
  const prefix = 'app/api/mobile/v1/'
  const suffix = '/route.js'
  if (!target.startsWith(prefix) || !target.endsWith(suffix) || target.includes('\\')) {
    return false
  }

  const routeSegments = target.slice(prefix.length, -suffix.length).split('/')
  return routeSegments.length > 0 && routeSegments.every(
    (segment) => segment !== '' && segment !== '.' && segment !== '..',
  )
}

function validateApplicationRouteBundles(buildRoot, entries) {
  const serverRoot = resolve(buildRoot, 'server')
  const targets = new Map()

  for (const entry of entries) {
    if (!isMobileRouteBundleTarget(entry.target)) {
      throw new Error(`APP_PATH_BUNDLE_TARGET_OUTSIDE_MOBILE_ROUTE:${entry.appPath}`)
    }
    if (targets.has(entry.target)) {
      throw new Error(`APP_PATH_BUNDLE_TARGET_DUPLICATE:${entry.target}`)
    }
    targets.set(entry.target, entry.appPath)

    const expectedTarget = `app${entry.appPath}.js`
    if (entry.target !== expectedTarget) {
      throw new Error(`APP_PATH_BUNDLE_TARGET_MISMATCH:${entry.appPath}`)
    }

    const targetPath = resolve(serverRoot, entry.target)
    if (!existsSync(targetPath) || !statSync(targetPath).isFile()) {
      throw new Error(`APP_PATH_BUNDLE_TARGET_MISSING:${entry.appPath}`)
    }
  }
}

function canonicalTraceReference(reference) {
  return reference
    .split('\\').join('/')
    .replace(/^(?:\.\.\/)+/, '')
    .replace(/^\.\//, '')
}

function isInside(root, path) {
  const pathFromRoot = relative(root, path)
  return pathFromRoot === '' || (
    pathFromRoot !== '..' &&
    !pathFromRoot.startsWith(`..${sep}`)
  )
}

function filesystemErrorCode(error) {
  return isRecord(error) && typeof error.code === 'string'
    ? error.code
    : 'UNKNOWN'
}

function verifyStructuralDirectory(
  repositoryRoot,
  repositoryRealRoot,
  lexicalTarget,
  physicalTarget,
  entryTarget,
  canonicalReference,
) {
  const repositoryPath = relative(repositoryRealRoot, physicalTarget)
    .split(sep).join('/')
  const virtualDirectoryPath = `${repositoryPath.replace(/\/$/, '')}/`

  if (workerTracePattern.test(virtualDirectoryPath)) {
    throw new Error(
      `NFT_DIRECTORY_FORBIDDEN_WORKER:${entryTarget}:${virtualDirectoryPath}`,
    )
  }
  if (administrativeTracePattern.test(virtualDirectoryPath)) {
    throw new Error(
      `NFT_DIRECTORY_FORBIDDEN_ADMINISTRATIVE:${entryTarget}:${virtualDirectoryPath}`,
    )
  }
  if (!isInside(repositoryRoot, lexicalTarget)) {
    throw new Error(`NFT_DIRECTORY_LEXICAL_EXTERNAL:${entryTarget}:${canonicalReference}`)
  }

  let lexicalStat
  try {
    lexicalStat = lstatSync(lexicalTarget)
  } catch (error) {
    throw new Error(
      `NFT_DIRECTORY_LSTAT_ERROR:${entryTarget}:${canonicalReference}:${filesystemErrorCode(error)}`,
    )
  }
  if (!lexicalStat.isSymbolicLink()) {
    throw new Error(
      `NFT_DIRECTORY_NOT_LEXICAL_SYMLINK:${entryTarget}:${canonicalReference}`,
    )
  }

  const packageManifest = resolve(physicalTarget, 'package.json')
  let packageManifestReal
  try {
    packageManifestReal = realpathSync(packageManifest)
  } catch (error) {
    throw new Error(
      `NFT_DIRECTORY_PACKAGE_MANIFEST_ERROR:${entryTarget}:${canonicalReference}:${filesystemErrorCode(error)}`,
    )
  }
  if (
    !isInside(repositoryRealRoot, packageManifestReal) ||
    !isInside(physicalTarget, packageManifestReal) ||
    !statSync(packageManifestReal).isFile()
  ) {
    throw new Error(
      `NFT_DIRECTORY_PACKAGE_MANIFEST_INVALID:${entryTarget}:${canonicalReference}`,
    )
  }

  let packageRecord
  try {
    packageRecord = JSON.parse(readFileSync(packageManifestReal, 'utf8'))
  } catch {
    throw new Error(
      `NFT_DIRECTORY_PACKAGE_MANIFEST_INVALID:${entryTarget}:${canonicalReference}`,
    )
  }
  if (
    !isRecord(packageRecord) ||
    typeof packageRecord.name !== 'string' ||
    !allowedStructuralDirectoryPackages.has(packageRecord.name)
  ) {
    throw new Error(
      `NFT_DIRECTORY_PACKAGE_IDENTITY_DENIED:${entryTarget}:${canonicalReference}`,
    )
  }

  return packageRecord.name
}

function inspectApplicationRouteTransitives(buildRoot, entries) {
  const serverRoot = resolve(buildRoot, 'server')
  const repositoryRoot = resolve(buildRoot, '../../..')
  const repositoryRealRoot = realpathSync(repositoryRoot)
  const forbiddenWorkerBundleReferences = new Set()
  const forbiddenAdministrativeBundleReferences = new Set()
  const forbiddenWorkerTraceReferences = new Set()
  const forbiddenAdministrativeTraceReferences = new Set()
  const nftTargets = new Map()
  const nftStructuralDirectoryPackages = new Map()
  let nftReferenceCount = 0

  for (const entry of [...entries].sort((left, right) =>
    left.target.localeCompare(right.target, 'en'),
  )) {
    const bundlePath = resolve(serverRoot, entry.target)
    const tracePath = `${bundlePath}.nft.json`
    if (!existsSync(tracePath) || !statSync(tracePath).isFile()) {
      throw new Error(`APP_PATH_BUNDLE_TRACE_MISSING:${entry.appPath}`)
    }

    const trace = readJsonManifest(buildRoot, relative(buildRoot, tracePath))
    if (!Array.isArray(trace.manifest.files) || trace.manifest.files.some(
      (reference) => typeof reference !== 'string',
    )) {
      throw new Error(`APP_PATH_BUNDLE_TRACE_INVALID:${entry.appPath}`)
    }

    const contentFiles = new Map([[entry.target, bundlePath]])
    for (const reference of [...trace.manifest.files].sort((left, right) =>
      left.localeCompare(right, 'en'),
    )) {
      nftReferenceCount += 1
      const canonicalReference = canonicalTraceReference(reference)

      const tracedPath = resolve(dirname(tracePath), reference)
      let physicalTarget
      try {
        physicalTarget = realpathSync(tracedPath)
      } catch (error) {
        const code = filesystemErrorCode(error)
        if (code === 'ENOENT' || code === 'ENOTDIR') {
          throw new Error(`NFT_TARGET_MISSING:${entry.target}:${canonicalReference}`)
        }
        throw new Error(
          `NFT_TARGET_REALPATH_ERROR:${entry.target}:${canonicalReference}:${code}`,
        )
      }

      if (!isInside(repositoryRealRoot, physicalTarget)) {
        throw new Error(`NFT_TARGET_EXTERNAL:${entry.target}:${canonicalReference}`)
      }

      let targetStat
      try {
        targetStat = statSync(physicalTarget)
      } catch (error) {
        const code = filesystemErrorCode(error)
        if (code === 'ENOENT' || code === 'ENOTDIR') {
          throw new Error(`NFT_TARGET_MISSING:${entry.target}:${canonicalReference}`)
        }
        throw new Error(
          `NFT_TARGET_STAT_ERROR:${entry.target}:${canonicalReference}:${code}`,
        )
      }

      const targetKind = targetStat.isFile()
        ? 'regular-file'
        : targetStat.isDirectory()
          ? 'directory'
          : null
      if (!targetKind) {
        throw new Error(
          `NFT_TARGET_UNSUPPORTED_TYPE:${entry.target}:${canonicalReference}`,
        )
      }
      nftTargets.set(physicalTarget, targetKind)

      if (targetKind === 'directory') {
        const packageName = verifyStructuralDirectory(
          repositoryRoot,
          repositoryRealRoot,
          tracedPath,
          physicalTarget,
          entry.target,
          canonicalReference,
        )
        nftStructuralDirectoryPackages.set(physicalTarget, packageName)
      }

      const repositoryPath = relative(repositoryRealRoot, physicalTarget)
        .split(sep).join('/')
      if (workerTracePattern.test(repositoryPath)) {
        forbiddenWorkerTraceReferences.add(`${entry.target}:${repositoryPath}`)
      }
      if (administrativeTracePattern.test(repositoryPath)) {
        forbiddenAdministrativeTraceReferences.add(`${entry.target}:${repositoryPath}`)
      }
      if (
        targetKind === 'regular-file' &&
        ['.js', '.mjs', '.cjs'].includes(extname(physicalTarget))
      ) {
        contentFiles.set(canonicalReference, physicalTarget)
      }
    }

    for (const [reference, path] of contentFiles) {
      if (!existsSync(path) || !statSync(path).isFile()) continue
      const source = readFileSync(path, 'utf8')
      for (const marker of workerBundleMarkers) {
        if (source.includes(marker)) {
          const suffix = reference === entry.target ? marker : `${reference}:${marker}`
          forbiddenWorkerBundleReferences.add(`${entry.target}:${suffix}`)
        }
      }
      for (const marker of administrativeBundleMarkers) {
        if (source.includes(marker)) {
          const suffix = reference === entry.target ? marker : `${reference}:${marker}`
          forbiddenAdministrativeBundleReferences.add(`${entry.target}:${suffix}`)
        }
      }
    }
  }

  return {
    forbiddenWorkerBundleReferences: sortedUnique(forbiddenWorkerBundleReferences),
    forbiddenAdministrativeBundleReferences: sortedUnique(
      forbiddenAdministrativeBundleReferences,
    ),
    forbiddenWorkerTraceReferences: sortedUnique(forbiddenWorkerTraceReferences),
    forbiddenAdministrativeTraceReferences: sortedUnique(
      forbiddenAdministrativeTraceReferences,
    ),
    nftReferenceCount,
    nftUniqueTargetCount: nftTargets.size,
    nftRegularFileTargetCount: [...nftTargets.values()].filter(
      (kind) => kind === 'regular-file',
    ).length,
    nftDirectoryTargetCount: [...nftTargets.values()].filter(
      (kind) => kind === 'directory',
    ).length,
    nftAllowlistedDirectoryTargetCount: nftStructuralDirectoryPackages.size,
  }
}

function routeManifestPaths(manifest) {
  const paths = []
  for (const field of ['staticRoutes', 'dynamicRoutes', 'dataRoutes']) {
    const records = manifest[field]
    if (!Array.isArray(records)) throw new Error(`ROUTES_MANIFEST_INVALID_FIELD:${field}`)
    for (const record of records) {
      if (!isRecord(record) || typeof record.page !== 'string') {
        throw new Error(`ROUTES_MANIFEST_INVALID_RECORD:${field}`)
      }
      paths.push(record.page)
    }
  }
  return sortedUnique(paths)
}

function forbiddenRoutes(paths, pattern) {
  return paths.filter((path) => pattern.test(path))
}

export function inspectBuildSurface(buildRoot) {
  const appPathsReceipt = readJsonManifest(buildRoot, 'server/app-paths-manifest.json')
  const routesReceipt = readJsonManifest(buildRoot, 'routes-manifest.json')
  const middlewareReceipt = readJsonManifest(buildRoot, 'server/middleware-manifest.json')
  const serverReferenceReceipt = readJsonManifest(
    buildRoot,
    'server/server-reference-manifest.json',
  )

  const appEntries = Object.entries(appPathsReceipt.manifest)
  if (appEntries.some(([key, value]) => !key.startsWith('/') || typeof value !== 'string')) {
    throw new Error('APP_PATHS_MANIFEST_INVALID_ENTRY')
  }

  const normalizedAppEntries = appEntries.map(([appPath, target]) =>
    classifyAppPath(appPath, target),
  )
  const applicationRouteBundles = normalizedAppEntries.filter(
    (entry) => entry.kind === 'route',
  )
  validateApplicationRouteBundles(buildRoot, applicationRouteBundles)
  const transitiveSurface = inspectApplicationRouteTransitives(
    buildRoot,
    applicationRouteBundles,
  )
  const routePaths = sortedUnique(applicationRouteBundles.map((entry) => entry.path))
  const appPageRoutes = normalizedAppEntries
    .filter((entry) => entry.kind === 'page')
    .map((entry) => entry.path)
  const observedRoutesManifestPaths = routeManifestPaths(routesReceipt.manifest).filter(
    (path) => path !== internalNotFoundRoute,
  )
  const pageRoutes = sortedUnique([
    ...appPageRoutes,
    ...observedRoutesManifestPaths.filter((path) => !routePaths.includes(path)),
  ])

  if (!isRecord(middlewareReceipt.manifest.middleware)) {
    throw new Error('MIDDLEWARE_MANIFEST_INVALID_MIDDLEWARE')
  }
  const middlewareEntries = Object.keys(middlewareReceipt.manifest.middleware).sort((left, right) =>
    left.localeCompare(right, 'en'),
  )

  const serverActionReferences = []
  for (const runtime of ['node', 'edge']) {
    const references = serverReferenceReceipt.manifest[runtime]
    if (!isRecord(references)) {
      throw new Error(`SERVER_REFERENCE_MANIFEST_INVALID_${runtime.toUpperCase()}`)
    }
    serverActionReferences.push(
      ...Object.keys(references).map((reference) => `${runtime}:${reference}`),
    )
  }
  serverActionReferences.sort((left, right) => left.localeCompare(right, 'en'))

  const allObservedPaths = sortedUnique([
    ...routePaths,
    ...pageRoutes,
    ...observedRoutesManifestPaths,
  ])
  const routesOutsideMobilePrefix = routePaths.filter(
    (path) => !path.startsWith('/api/mobile/v1/'),
  )
  const forbiddenAdminRoutes = forbiddenRoutes(allObservedPaths, /^\/api\/admin(?:\/|$)/)
  const forbiddenInngestRoutes = forbiddenRoutes(allObservedPaths, /^\/api\/inngest(?:\/|$)/)
  const forbiddenStripeRoutes = forbiddenRoutes(allObservedPaths, /^\/api\/stripe(?:\/|$)/)
  const forbiddenAdminMediaRoutes = forbiddenRoutes(allObservedPaths, /^\/api\/media(?:\/|$)/)

  const routePathStream = routePaths.map((path) => `${path}\n`).join('')
  const bundleSurfaceStream = [
    ...applicationRouteBundles.map(
      ({ path, target }) => `application-route\0${path}\0${target}\n`,
    ),
    ...pageRoutes.map((path) => `page-route\0${path}\n`),
    ...middlewareEntries.map((path) => `middleware\0${path}\n`),
    ...serverActionReferences.map((reference) => `server-action\0${reference}\n`),
  ]
    .sort((left, right) => left.localeCompare(right, 'en'))
    .join('')

  return {
    routePaths,
    applicationRouteBundles,
    routePathHash: sha256(routePathStream),
    routesOutsideMobilePrefix,
    forbiddenAdminRoutes,
    forbiddenInngestRoutes,
    forbiddenStripeRoutes,
    forbiddenAdminMediaRoutes,
    pageRoutes,
    middlewareEntries,
    serverActionReferences,
    ...transitiveSurface,
    bundleSurfaceHash: sha256(bundleSurfaceStream),
    manifestHashes: {
      appPaths: sha256(appPathsReceipt.bytes),
      routes: sha256(routesReceipt.bytes),
      middleware: sha256(middlewareReceipt.bytes),
      serverReferences: sha256(serverReferenceReceipt.bytes),
    },
  }
}

function fail(message) {
  console.error(`BUILD_SURFACE_ERROR=${message}`)
  process.exitCode = 1
}

function verifyBuildSurface() {
  const scriptDirectory = dirname(fileURLToPath(import.meta.url))
  const buildRoot = resolve(scriptDirectory, '../.next')
  let surface
  try {
    surface = inspectBuildSurface(buildRoot)
  } catch (error) {
    fail(error instanceof Error ? error.message : 'UNKNOWN')
    return
  }

  console.info(`BUILD_ROUTE_PATH_COUNT=${surface.routePaths.length}`)
  console.info(`BUILD_ROUTE_PATH_STREAM_SHA256=${surface.routePathHash}`)
  console.info(`BUILD_BUNDLE_SURFACE_STREAM_SHA256=${surface.bundleSurfaceHash}`)
  console.info(`BUILD_APP_PATHS_MANIFEST_SHA256=${surface.manifestHashes.appPaths}`)
  console.info(`BUILD_ROUTES_MANIFEST_SHA256=${surface.manifestHashes.routes}`)
  console.info(`BUILD_MIDDLEWARE_MANIFEST_SHA256=${surface.manifestHashes.middleware}`)
  console.info(`BUILD_SERVER_REFERENCE_MANIFEST_SHA256=${surface.manifestHashes.serverReferences}`)
  console.info(`BUILD_OUT_OF_PREFIX_ROUTE_COUNT=${surface.routesOutsideMobilePrefix.length}`)
  console.info(`BUILD_FORBIDDEN_ADMIN_ROUTE_COUNT=${surface.forbiddenAdminRoutes.length}`)
  console.info(`BUILD_FORBIDDEN_INNGEST_ROUTE_COUNT=${surface.forbiddenInngestRoutes.length}`)
  console.info(`BUILD_FORBIDDEN_STRIPE_ROUTE_COUNT=${surface.forbiddenStripeRoutes.length}`)
  console.info(`BUILD_FORBIDDEN_ADMIN_MEDIA_ROUTE_COUNT=${surface.forbiddenAdminMediaRoutes.length}`)
  console.info(`BUILD_PAGE_ROUTE_COUNT=${surface.pageRoutes.length}`)
  console.info(`BUILD_MIDDLEWARE_COUNT=${surface.middlewareEntries.length}`)
  console.info(`BUILD_SERVER_ACTION_REFERENCE_COUNT=${surface.serverActionReferences.length}`)
  console.info(`BUILD_FORBIDDEN_WORKER_BUNDLE_REFERENCE_COUNT=${surface.forbiddenWorkerBundleReferences.length}`)
  console.info(`BUILD_FORBIDDEN_WORKER_TRACE_REFERENCE_COUNT=${surface.forbiddenWorkerTraceReferences.length}`)
  console.info(`BUILD_FORBIDDEN_ADMINISTRATIVE_BUNDLE_REFERENCE_COUNT=${surface.forbiddenAdministrativeBundleReferences.length}`)
  console.info(`BUILD_FORBIDDEN_ADMINISTRATIVE_TRACE_REFERENCE_COUNT=${surface.forbiddenAdministrativeTraceReferences.length}`)
  console.info(`BUILD_NFT_REFERENCE_COUNT=${surface.nftReferenceCount}`)
  console.info(`BUILD_NFT_UNIQUE_TARGET_COUNT=${surface.nftUniqueTargetCount}`)
  console.info(`BUILD_NFT_REGULAR_FILE_TARGET_COUNT=${surface.nftRegularFileTargetCount}`)
  console.info(`BUILD_NFT_DIRECTORY_TARGET_COUNT=${surface.nftDirectoryTargetCount}`)
  console.info(`BUILD_NFT_ALLOWLISTED_DIRECTORY_TARGET_COUNT=${surface.nftAllowlistedDirectoryTargetCount}`)

  if (surface.routePaths.length !== expectedRouteCount) {
    fail(`ROUTE_COUNT:${surface.routePaths.length}`)
  }
  if (surface.routePathHash !== expectedRouteHash) fail(`ROUTE_HASH:${surface.routePathHash}`)
  if (surface.routesOutsideMobilePrefix.length !== 0) {
    fail(`OUT_OF_PREFIX_ROUTES:${surface.routesOutsideMobilePrefix.length}`)
  }
  if (surface.forbiddenAdminRoutes.length !== 0) {
    fail(`ADMIN_ROUTES:${surface.forbiddenAdminRoutes.length}`)
  }
  if (surface.forbiddenInngestRoutes.length !== 0) {
    fail(`INNGEST_ROUTES:${surface.forbiddenInngestRoutes.length}`)
  }
  if (surface.forbiddenStripeRoutes.length !== 0) {
    fail(`STRIPE_ROUTES:${surface.forbiddenStripeRoutes.length}`)
  }
  if (surface.forbiddenAdminMediaRoutes.length !== 0) {
    fail(`ADMIN_MEDIA_ROUTES:${surface.forbiddenAdminMediaRoutes.length}`)
  }
  if (surface.pageRoutes.length !== 0) fail(`PAGE_ROUTES:${surface.pageRoutes.length}`)
  if (surface.middlewareEntries.length !== 0) {
    fail(`MIDDLEWARE:${surface.middlewareEntries.length}`)
  }
  if (surface.serverActionReferences.length !== 0) {
    fail(`SERVER_ACTION_REFERENCES:${surface.serverActionReferences.length}`)
  }
  if (surface.forbiddenWorkerBundleReferences.length !== 0) {
    fail(`WORKER_BUNDLE_REFERENCES:${surface.forbiddenWorkerBundleReferences.length}`)
  }
  if (surface.forbiddenWorkerTraceReferences.length !== 0) {
    fail(`WORKER_TRACE_REFERENCES:${surface.forbiddenWorkerTraceReferences.length}`)
  }
  if (surface.forbiddenAdministrativeBundleReferences.length !== 0) {
    fail(`ADMINISTRATIVE_BUNDLE_REFERENCES:${surface.forbiddenAdministrativeBundleReferences.length}`)
  }
  if (surface.forbiddenAdministrativeTraceReferences.length !== 0) {
    fail(`ADMINISTRATIVE_TRACE_REFERENCES:${surface.forbiddenAdministrativeTraceReferences.length}`)
  }

  if (!process.exitCode) console.info('BUILD_SURFACE_STATUS=VERIFIED')
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  verifyBuildSurface()
}
