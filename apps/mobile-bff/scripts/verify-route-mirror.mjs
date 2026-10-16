import { createHash } from 'node:crypto'
import { existsSync, readdirSync, readFileSync } from 'node:fs'
import { dirname, relative, resolve, sep } from 'node:path'
import { fileURLToPath } from 'node:url'

const expectedCount = 54
const expectedHash = '0f076fc83228e8742e107ba4bb9631019b6d1e6edc74fbd36039c574b228c1a3'
const scriptDirectory = dirname(fileURLToPath(import.meta.url))
const appRoot = resolve(scriptDirectory, '..')
const sourceRoot = resolve(appRoot, '../admin/src/app/api/mobile/v1')
const wrapperRoot = resolve(appRoot, 'src/app/api/mobile/v1')
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

function fail(message) {
  console.error(`ROUTE_MIRROR_ERROR=${message}`)
  process.exitCode = 1
}

function walkFiles(root) {
  if (!existsSync(root)) return []

  return readdirSync(root, { withFileTypes: true }).flatMap((entry) => {
    const path = resolve(root, entry.name)
    return entry.isDirectory() ? walkFiles(path) : [path]
  })
}

function exportedNames(source) {
  return Array.from(
    source.matchAll(/^export\s+(?:const|async\s+function|function)\s+([A-Za-z_$][\w$]*)/gm),
    (match) => match[1],
  ).sort()
}

function sourceRecords() {
  return walkFiles(sourceRoot)
    .filter((path) => path.endsWith(`${sep}route.ts`))
    .map((path) => ({
      path: relative(sourceRoot, path).split(sep).join('/'),
      exports: exportedNames(readFileSync(path, 'utf8')),
    }))
    .sort((left, right) => left.path.localeCompare(right.path, 'en'))
}

function wrapperRecords() {
  return walkFiles(wrapperRoot)
    .filter((path) => path.endsWith(`${sep}route.ts`))
    .map((path) => {
      const relativePath = relative(wrapperRoot, path).split(sep).join('/')
      const wrapper = readFileSync(path, 'utf8')
      if (/export\s+\*/.test(wrapper)) {
        fail(`EXPORT_STAR:${relativePath}`)
        return null
      }

      const statements = Array.from(
        wrapper.matchAll(/^export\s*\{\s*([^}]+?)\s*\}\s*from\s*['"]([^'"]+)['"]\s*;?\s*$/gm),
      )
      if (statements.length !== 1) {
        fail(`INVALID_WRAPPER:${relativePath}`)
        return null
      }
      const statement = statements[0]

      const residue = wrapper
        .replace(statement[0], '')
        .replace(/^export\s+const\s+runtime\s*=\s*['"]nodejs['"]\s*;?\s*$/gm, '')
        .replace(/^export\s+const\s+maxDuration\s*=\s*300\s*;?\s*$/gm, '')
        .replace(/^\s*\/\/[^\n]*$/gm, '')
        .trim()
      if (residue) {
        fail(`INVALID_WRAPPER_BODY:${relativePath}`)
        return null
      }

      return {
        path: relativePath,
        exports: [
          ...statement[1]
            .split(',')
            .map((name) => name.trim())
            .filter(Boolean),
          ...exportedNames(wrapper),
        ].sort(),
        sourcePath: statement[2],
      }
    })
    .filter(Boolean)
    .sort((left, right) => left.path.localeCompare(right.path, 'en'))
}

function hashRecords(records) {
  const canonicalStream = records
    .map((record) => `${record.path}\0${record.exports.join(',')}\n`)
    .join('')
  return createHash('sha256').update(canonicalStream).digest('hex')
}

const sources = sourceRecords()
const wrappers = wrapperRecords()
const sourceHash = hashRecords(sources)
const wrapperHash = hashRecords(wrappers)
const invalidSourceExports = sources.flatMap((record) =>
  record.exports.filter((name) => !allowedRouteExports.has(name)),
)
const sourceByPath = new Map(sources.map((record) => [record.path, record]))
const wrapperByPath = new Map(wrappers.map((record) => [record.path, record]))
const extras = wrappers.filter((record) => !sourceByPath.has(record.path))
const omissions = sources.filter((record) => !wrapperByPath.has(record.path))
const exportMismatches = wrappers.filter((wrapper) => {
  const source = sourceByPath.get(wrapper.path)
  return source && JSON.stringify(source.exports) !== JSON.stringify(wrapper.exports)
})
const sourcePathMismatches = wrappers.filter((wrapper) => {
  const expectedSourcePath = `@/app/api/mobile/v1/${wrapper.path.replace(/\.ts$/, '')}`
  return wrapper.sourcePath !== expectedSourcePath
})

console.info(`SOURCE_ROUTE_EXPORT_COUNT=${sources.length}`)
console.info(`SOURCE_ROUTE_INVALID_EXPORT_COUNT=${invalidSourceExports.length}`)
console.info(`SOURCE_ROUTE_EXPORT_STREAM_SHA256=${sourceHash}`)
console.info(`WRAPPER_ROUTE_EXPORT_COUNT=${wrappers.length}`)
console.info(`WRAPPER_ROUTE_EXPORT_STREAM_SHA256=${wrapperHash}`)
console.info(`WRAPPER_ROUTE_EXTRA_COUNT=${extras.length}`)
console.info(`WRAPPER_ROUTE_OMITTED_COUNT=${omissions.length}`)
console.info(`WRAPPER_ROUTE_EXPORT_MISMATCH_COUNT=${exportMismatches.length}`)
console.info(`WRAPPER_ROUTE_SOURCE_PATH_MISMATCH_COUNT=${sourcePathMismatches.length}`)

if (sources.length !== expectedCount) fail(`SOURCE_COUNT:${sources.length}`)
if (wrappers.length !== expectedCount) fail(`WRAPPER_COUNT:${wrappers.length}`)
if (invalidSourceExports.length !== 0) fail(`INVALID_SOURCE_EXPORTS:${invalidSourceExports.length}`)
if (sourceHash !== expectedHash) fail(`SOURCE_HASH:${sourceHash}`)
if (wrapperHash !== expectedHash) fail(`WRAPPER_HASH:${wrapperHash}`)
if (extras.length !== 0) fail(`EXTRA_WRAPPERS:${extras.length}`)
if (omissions.length !== 0) fail(`OMITTED_WRAPPERS:${omissions.length}`)
if (exportMismatches.length !== 0) fail(`EXPORT_MISMATCHES:${exportMismatches.length}`)
if (sourcePathMismatches.length !== 0) fail(`SOURCE_PATH_MISMATCHES:${sourcePathMismatches.length}`)

if (!process.exitCode) console.info('ROUTE_MIRROR_STATUS=VERIFIED')
