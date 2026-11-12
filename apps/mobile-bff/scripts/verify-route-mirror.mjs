import { createHash } from 'node:crypto'
import { existsSync, readdirSync, readFileSync } from 'node:fs'
import { dirname, relative, resolve, sep } from 'node:path'
import { fileURLToPath } from 'node:url'

const expectedCount = 92
const expectedHash = 'd59c9ee8bdb67a450c40c45bdc4f287233a2fe21aaa531c7ae08c19b23342152'
const linkedOriginRoute = 'conversation/meal-commands/[commandId]/origin/route.ts'
const mealQuestionRoute = 'conversation/commands/[commandId]/replies/route.ts'
const originsRoute = 'conversation/intakes/route.ts'
const intakeTransports = new Map([
  ['conversation/intakes/route.ts', ['GET', 'POST', 'maxDuration', 'runtime']],
  ['conversation/intakes/[intakeId]/route.ts', ['GET', 'maxDuration', 'runtime']],
  ['conversation/intakes/session/route.ts', ['GET', 'dynamic', 'runtime']],
])
const workoutTransports = new Map([
  ['conversation/workout-session/route.ts', 'GET'],
  ['conversation/workout-commands/route.ts', 'POST'],
  ['conversation/workout-commands/[commandId]/route.ts', 'GET'],
])
const nutritionWindowRoute = 'nutrition/window/route.ts'
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
  linkedOriginRoute,
  ...addedReadEditRoutes,
  ...addedReplyRoutes,
  ...workoutTransports.keys(),
  'conversation/intakes/route.ts',
  'conversation/intakes/[intakeId]/route.ts',
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
          relativePath === 'conversation/intakes/session/route.ts'
            ? /^export\s+const\s+dynamic\s*=\s*['"]force-dynamic['"]\s*;?\s*$/gm
            : /$^/,
          '',
        )
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
  // T48 adds only the cold-origin GET beside the original intake POST.
  // Freeze the full T47 stream before applying any older historical boundary.
  const beforeLinked = records.filter((record) => record.path !== linkedOriginRoute)
  if (
    beforeLinked.length !== 91 ||
    hashRecords(beforeLinked) !== '161783e0c88223e0df8271ed658399734242dcb588e16128a3febd70527379a7'
  )
    fail(`${surface}_PRE_LINKED_ORIGIN_CHANGED`)
  const linkedOrigin = records.find((record) => record.path === linkedOriginRoute)
  if (JSON.stringify(linkedOrigin?.exports) !== JSON.stringify(['GET', 'maxDuration', 'runtime']))
    fail(`${surface}_LINKED_ORIGIN_EXPORTS`)
  const beforeOrigins = beforeLinked.map((record) =>
    record.path === originsRoute
      ? { ...record, exports: record.exports.filter((name) => name !== 'GET') }
      : record,
  )
  const beforeOriginsHash = hashRecords(beforeOrigins)
  console.info(`${surface}_PRE_T48_ROUTE_EXPORT_COUNT=${beforeOrigins.length}`)
  console.info(`${surface}_PRE_T48_ROUTE_EXPORT_STREAM_SHA256=${beforeOriginsHash}`)
  if (beforeOrigins.length !== 91) fail(`${surface}_PRE_T48_COUNT:${beforeOrigins.length}`)
  if (beforeOriginsHash !== '1aee269695cf61901f5ecb802e8509ae9004481024926043353d1f7cf32db9f7')
    fail(`${surface}_PRE_T48_HASH:${beforeOriginsHash}`)
  const question = records.find((record) => record.path === mealQuestionRoute)
  if (
    JSON.stringify(question?.exports) !== JSON.stringify(['GET', 'POST', 'maxDuration', 'runtime'])
  )
    fail(`${surface}_MEAL_QUESTION_EXPORTS:${JSON.stringify(question?.exports)}`)
  // T47 adds exactly GET to one existing path. Every prior method/configuration
  // remains frozen, including all 91 routes before this one additive method.
  const prior91 = beforeOrigins.map((record) =>
    record.path === mealQuestionRoute
      ? { ...record, exports: record.exports.filter((name) => name !== 'GET') }
      : record,
  )
  const prior91Hash = hashRecords(prior91)
  console.info(`${surface}_PRIOR91_ROUTE_EXPORT_COUNT=${prior91.length}`)
  console.info(`${surface}_PRIOR91_ROUTE_EXPORT_STREAM_SHA256=${prior91Hash}`)
  if (prior91.length !== 91) fail(`${surface}_PRIOR91_COUNT:${prior91.length}`)
  if (prior91Hash !== '93200635df44342607fb57b71a1b623e1dbd1ff442f6fdbe5997a9f7fe81dd67')
    fail(`${surface}_PRIOR91_HASH:${prior91Hash}`)
  for (const [path, exports] of intakeTransports) {
    const record = records.find((record) => record.path === path)
    if (JSON.stringify(record?.exports) !== JSON.stringify(exports))
      fail(`${surface}_INTAKE_EXPORTS:${path}:${JSON.stringify(record?.exports)}`)
  }
  const prior88 = prior91.filter((record) => !intakeTransports.has(record.path))
  const prior88Hash = hashRecords(prior88)
  console.info(`${surface}_PRIOR88_ROUTE_EXPORT_COUNT=${prior88.length}`)
  console.info(`${surface}_PRIOR88_ROUTE_EXPORT_STREAM_SHA256=${prior88Hash}`)
  if (prior88.length !== 88) fail(`${surface}_PRIOR88_COUNT:${prior88.length}`)
  if (prior88Hash !== '99623e7e5caf5d3b3df20eeb6bf840e6fb416f5e489498232a0c984a0a6e53b4')
    fail(`${surface}_PRIOR88_HASH:${prior88Hash}`)
  for (const [path, method] of workoutTransports) {
    const record = records.find((record) => record.path === path)
    if (JSON.stringify(record?.exports) !== JSON.stringify([method, 'maxDuration', 'runtime']))
      fail(`${surface}_WORKOUT_EXPORTS:${path}:${JSON.stringify(record?.exports)}`)
  }
  const prior85 = prior88.filter((record) => !workoutTransports.has(record.path))
  const prior85Hash = hashRecords(prior85)
  console.info(`${surface}_PRIOR85_ROUTE_EXPORT_COUNT=${prior85.length}`)
  console.info(`${surface}_PRIOR85_ROUTE_EXPORT_STREAM_SHA256=${prior85Hash}`)
  if (prior85.length !== 85) fail(`${surface}_PRIOR85_COUNT:${prior85.length}`)
  if (prior85Hash !== 'afb3a6182ad8e1335a24edeb3f2394f411ee6935f9994c1ecfb0c164079c3d12')
    fail(`${surface}_PRIOR85_HASH:${prior85Hash}`)
  const nutrition = records.find((record) => record.path === nutritionWindowRoute)
  if (JSON.stringify(nutrition?.exports) !== JSON.stringify(['GET', 'dynamic', 'runtime']))
    fail(`${surface}_NUTRITION_EXPORTS:${JSON.stringify(nutrition?.exports)}`)
  const prior84 = prior85.filter((record) => record.path !== nutritionWindowRoute)
  const prior84Hash = hashRecords(prior84)
  console.info(`${surface}_PRIOR84_ROUTE_EXPORT_COUNT=${prior84.length}`)
  console.info(`${surface}_PRIOR84_ROUTE_EXPORT_STREAM_SHA256=${prior84Hash}`)
  if (prior84.length !== 84) fail(`${surface}_PRIOR84_COUNT:${prior84.length}`)
  if (prior84Hash !== '092bd3ded789b200042cf29119e279e22d6900f8cdc86889108f28d2764673f3')
    fail(`${surface}_PRIOR84_HASH:${prior84Hash}`)
  const prior82 = prior84.filter((record) => !addedReplyRoutes.has(record.path))
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
