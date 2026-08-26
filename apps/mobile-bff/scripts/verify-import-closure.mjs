import { builtinModules } from 'node:module'
import { existsSync, readFileSync, readdirSync, statSync } from 'node:fs'
import { dirname, extname, relative, resolve, sep } from 'node:path'
import { fileURLToPath } from 'node:url'

const scriptDirectory = dirname(fileURLToPath(import.meta.url))
const appRoot = resolve(scriptDirectory, '..')
const repositoryRoot = resolve(appRoot, '../..')
const adminSourceRoot = resolve(repositoryRoot, 'apps/admin/src')
const mobileSourceRoot = resolve(adminSourceRoot, 'app/api/mobile/v1')
const wrapperRoot = resolve(appRoot, 'src/app/api/mobile/v1')
const inngestPackageRoot = resolve(repositoryRoot, 'packages/inngest-functions/src')
const inngestClientSource = resolve(inngestPackageRoot, 'client.ts')
const resolvableExtensions = ['.ts', '.tsx', '.js', '.jsx', '.mjs', '.cjs', '.json']
const builtins = new Set(builtinModules.flatMap((name) => [name, `node:${name}`]))
const panelCallbacks = new Set([
  'apps/admin/src/app/(admin)/content/actions.ts',
  'apps/admin/src/app/(admin)/settings/coach-messages/actions.ts',
])

function walkFiles(root) {
  if (!existsSync(root)) return []

  return readdirSync(root, { withFileTypes: true }).flatMap((entry) => {
    const path = resolve(root, entry.name)
    return entry.isDirectory() ? walkFiles(path) : [path]
  })
}

function repositoryPath(path) {
  return relative(repositoryRoot, path).split(sep).join('/')
}

function isInside(root, path) {
  const pathFromRoot = relative(root, path)
  return pathFromRoot === '' || (!pathFromRoot.startsWith(`..${sep}`) && pathFromRoot !== '..')
}

function resolveFile(candidate) {
  const candidates = extname(candidate)
    ? [candidate]
    : [
        candidate,
        ...resolvableExtensions.map((extension) => `${candidate}${extension}`),
        ...resolvableExtensions.map((extension) => resolve(candidate, `index${extension}`)),
      ]

  return candidates.find(
    (path) => existsSync(path) && statSync(path).isFile(),
  )
}

function importedSpecifiers(source) {
  const patterns = [
    /(?:import|export)\s+(?:type\s+)?(?:[^'";]*?\s+from\s*)?['"]([^'"]+)['"]/gs,
    /import\s*\(\s*['"]([^'"]+)['"]\s*\)/g,
    /require\s*\(\s*['"]([^'"]+)['"]\s*\)/g,
  ]

  return Array.from(
    new Set(patterns.flatMap((pattern) => Array.from(source.matchAll(pattern), (match) => match[1]))),
  ).sort((left, right) => left.localeCompare(right, 'en'))
}

function packageName(specifier) {
  if (specifier.startsWith('@')) return specifier.split('/').slice(0, 2).join('/')
  return specifier.split('/')[0]
}

export function hasServerActionDirective(source) {
  return /^[\t ]*["']use server["'];?/m.test(source)
}

function deniedClassification(path, source) {
  const pathFromRepository = repositoryPath(path)
  const fileName = pathFromRepository.split('/').at(-1) ?? ''

  if (!isInside(repositoryRoot, path)) return 'denied-outside-repository'
  if (isInside(inngestPackageRoot, path) && path !== inngestClientSource) {
    return 'denied-inngest-worker-transitive'
  }
  if (pathFromRepository.includes('/public/')) return 'denied-public-file'
  if (/^middleware\.[cm]?[jt]sx?$/.test(fileName)) return 'denied-middleware'
  if (/^(?:page|layout)\.[cm]?[jt]sx?$/.test(fileName)) return 'denied-page-layout'
  if (fileName === 'public-api-path.ts') return 'denied-public-api-path'
  if (panelCallbacks.has(pathFromRepository)) return 'denied-panel-callback'
  if (pathFromRepository.includes('/webhooks/')) return 'denied-webhook'
  if (
    hasServerActionDirective(source) &&
    !isInside(mobileSourceRoot, path)
  ) {
    return 'denied-server-action'
  }
  if (
    pathFromRepository.startsWith('apps/admin/src/app/api/') &&
    !isInside(mobileSourceRoot, path)
  ) {
    return 'denied-admin-api'
  }
  if (
    pathFromRepository.startsWith('apps/admin/src/app/') &&
    !isInside(mobileSourceRoot, path)
  ) {
    return 'denied-admin-app-surface'
  }

  return null
}

function allowedClassification(path) {
  if (path === inngestClientSource) return 'published-inngest-client'
  if (isInside(wrapperRoot, path)) return 'mobile-wrapper'
  if (isInside(mobileSourceRoot, path)) {
    return /^route\.[cm]?[jt]sx?$/.test(path.split(sep).at(-1) ?? '')
      ? 'mobile-route'
      : 'mobile-route-support'
  }

  const pathFromRepository = repositoryPath(path)
  if (pathFromRepository.startsWith('apps/admin/src/lib/mobile-api/')) {
    return 'mobile-api-lib'
  }
  if (pathFromRepository === 'apps/admin/src/lib/supabase/server.ts') {
    return 'approved-server-lib'
  }
  if (pathFromRepository.startsWith('apps/admin/src/lib/')) return 'non-surface-lib'
  if (isInside(adminSourceRoot, path)) return 'non-surface-module'

  return 'denied-unclassified-local'
}

function localImport(importer, specifier) {
  if (
    specifier === '@mpp/inngest-functions' ||
    specifier === '@mpp/inngest-functions/client'
  ) {
    return inngestClientSource
  }
  if (specifier.startsWith('@/')) {
    return resolveFile(resolve(adminSourceRoot, specifier.slice(2)))
  }
  if (specifier.startsWith('.')) {
    return resolveFile(resolve(dirname(importer), specifier))
  }
  return null
}

function verifyImportClosure() {
  const records = new Set()
  const queued = walkFiles(wrapperRoot)
    .filter((path) => path.endsWith(`${sep}route.ts`))
    .sort((left, right) => repositoryPath(left).localeCompare(repositoryPath(right), 'en'))
  const visited = new Set()
  let denied = false

  while (queued.length > 0) {
    const path = queued.shift()
    if (visited.has(path)) continue
    visited.add(path)

    const source = readFileSync(path, 'utf8')
    const classification = deniedClassification(path, source) ?? allowedClassification(path)
    if (classification.startsWith('denied-')) denied = true
    records.add(`${classification}\t${repositoryPath(path)}`)

    for (const specifier of importedSpecifiers(source)) {
      if (builtins.has(specifier)) {
        records.add(`node-builtin\t${specifier}`)
        continue
      }

      if (
        specifier.startsWith('.') ||
        specifier.startsWith('@/') ||
        specifier === '@mpp/inngest-functions' ||
        specifier === '@mpp/inngest-functions/client'
      ) {
        const resolvedImport = localImport(path, specifier)
        if (!resolvedImport) {
          denied = true
          records.add(`denied-unresolved-local\t${repositoryPath(path)} -> ${specifier}`)
          continue
        }
        if (!visited.has(resolvedImport)) queued.push(resolvedImport)
        continue
      }

      records.add(`external-package\t${packageName(specifier)}`)
    }

    queued.sort((left, right) => repositoryPath(left).localeCompare(repositoryPath(right), 'en'))
  }

  const manifest = [...records].sort((left, right) => left.localeCompare(right, 'en'))
  if (manifest.length > 0) process.stdout.write(`${manifest.join('\n')}\n`)
  if (denied) process.exitCode = 1
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  verifyImportClosure()
}
