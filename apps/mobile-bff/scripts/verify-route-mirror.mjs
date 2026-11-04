import { createHash } from 'node:crypto'
import { existsSync, readdirSync, readFileSync } from 'node:fs'
import { dirname, relative, resolve, sep } from 'node:path'
import { fileURLToPath } from 'node:url'

const expectedCount = 84
const expectedHash = '092bd3ded789b200042cf29119e279e22d6900f8cdc86889108f28d2764673f3'
const previousCount = 78
const previousHash = '3ab0b1fdb146ab6a06846b5702cfa70a1a7b997d73b3235655ec248c32f68874'
const addedReadEditRoutes = new Set([
  'conversation/journal/route.ts',
  'conversation/meal-commands/[commandId]/meal/route.ts',
  'conversation/meal-commands/[commandId]/edits/[operationId]/route.ts',
  'conversation/meal-commands/[commandId]/edits/[operationId]/reconcile/route.ts',
])
const addedReplyRoutes = new Set([
  'conversation/commands/[commandId]/replies/[replyId]/route.ts',
  'conversation/commands/[commandId]/replies/route.ts',
])
const boundedConversationRoutes = new Set([
  'conversation/meal-commands/route.ts',
  ...addedReadEditRoutes,
  ...addedReplyRoutes,
])

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
        .replace(
          relativePath === 'auth/password-recovery/route.ts'
            ? /^export\s+const\s+maxDuration\s*=\s*45\s*;?\s*$/gm
            : boundedConversationRoutes.has(relativePath)
              ? /^export\s+const\s+maxDuration\s*=\s*120\s*;?\s*$/gm
              : /^export\s+const\s+maxDuration\s*=\s*300\s*;?\s*$/gm,
          '',
        )
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

for (const [surface, records] of [
  ['SOURCE', sources],
  ['WRAPPER', wrappers],
]) {
  const prior82 = records.filter((record) => !addedReplyRoutes.has(record.path))
  const prior82Hash = hashRecords(prior82)
  console.info(`${surface}_PRIOR82_ROUTE_EXPORT_COUNT=${prior82.length}`)
  console.info(`${surface}_PRIOR82_ROUTE_EXPORT_STREAM_SHA256=${prior82Hash}`)
  if (prior82.length !== 82) fail(`${surface}_PRIOR82_COUNT:${prior82.length}`)
  if (prior82Hash !== '1edcfecc752f7657306d9a4f852c9ff3b37f2770270441a3bb37972366957c98')
    fail(`${surface}_PRIOR82_HASH:${prior82Hash}`)
  const previous = prior82.filter((record) => !addedReadEditRoutes.has(record.path))
  const hash = hashRecords(previous)
  console.info(`${surface}_PRIOR_ROUTE_EXPORT_COUNT=${previous.length}`)
  console.info(`${surface}_PRIOR_ROUTE_EXPORT_STREAM_SHA256=${hash}`)
  if (previous.length !== previousCount) fail(`${surface}_PRIOR_COUNT:${previous.length}`)
  if (hash !== previousHash) fail(`${surface}_PRIOR_HASH:${hash}`)
}

if (!process.exitCode) console.info('ROUTE_MIRROR_STATUS=VERIFIED')
