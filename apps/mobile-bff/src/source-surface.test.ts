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
  statSync,
  symlinkSync,
  writeFileSync,
} from 'node:fs'
import { tmpdir } from 'node:os'
import { basename, dirname, relative, resolve, sep } from 'node:path'
import { fileURLToPath } from 'node:url'
import * as ts from 'typescript'
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
const nutritionWindowSourceRoute = 'nutrition/window/route.ts'
const nutritionWindowURL = '/api/mobile/v1/nutrition/window'
const nutritionWindowAppPath = `${nutritionWindowURL}/route`
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
const conversationReplyAdditions = [
  'conversation/commands/[commandId]/replies/[replyId]/route.ts',
  'conversation/commands/[commandId]/replies/route.ts',
]
const conversationReadEditAdditions = [
  'conversation/journal/route.ts',
  'conversation/meal-commands/[commandId]/edits/[operationId]/reconcile/route.ts',
  'conversation/meal-commands/[commandId]/edits/[operationId]/route.ts',
  'conversation/meal-commands/[commandId]/meal/route.ts',
]

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

// Exact 13-module extraction observed in the T29 production build. The new
// nutrition helper import makes Webpack split this existing conversation graph.
// These bodies include dormant writer adapters; this certificate never declares
// them absent and never exempts any physical code from the global scans.
function certifyNutritionJournalSplitContent(text: string): void {
  const source = ts.createSourceFile(
    'nutrition-shared.js',
    text,
    ts.ScriptTarget.Latest,
    true,
    ts.ScriptKind.JS,
  )
  const modules: ts.ObjectLiteralExpression[] = []
  const visit = (node: ts.Node) => {
    if (
      ts.isBinaryExpression(node) &&
      node.operatorToken.kind === ts.SyntaxKind.EqualsToken &&
      ts.isPropertyAccessExpression(node.left) &&
      node.left.getText(source) === 'exports.modules' &&
      ts.isObjectLiteralExpression(node.right)
    ) {
      modules.push(node.right)
      return
    }
    ts.forEachChild(node, visit)
  }
  visit(source)
  expect(modules, 'one certified nutrition-shared module table').toHaveLength(1)
  const bodies =
    modules[0]?.properties.map((property) => {
      if (!ts.isPropertyAssignment(property) || !ts.isArrowFunction(property.initializer))
        throw new Error('Unexpected nutrition-shared module shape')
      return { id: property.name.getText(source), body: property.initializer.getText(source) }
    }) ?? []
  expect(bodies, 'certified nutrition-shared module count').toHaveLength(13)
  expect(
    bodies.map(({ id, body }) => `${id}:${createHash('sha256').update(body).digest('hex')}`).sort(),
    'certified nutrition-shared module contents',
  ).toEqual([
    '13300:20fedfa25d9bd861ab851d7e94918af627b1fa5102cf509f796ba219040cd74f',
    '19514:a189839890f820d1a04f8f29b5dd89af51577d935e8af5e7a344cc8a5a9344fd',
    '20853:5e5378aa0bd0fb541859f4fa6a9dc8c853525dcb697ac43864a72c61837772e9',
    '21378:3666116fbbe020c4e11038c8dca63660d541b8bd16140556f52cf892fcebb2f5',
    '36693:9068c240f4c1876773b0af9412297b57d5d55615bbd36e8f0a5a5e5c22bf6be1',
    '52158:129ea4b769605c4e7ddee1f1bc26688f2d09e77a0922726299741a808f4ae420',
    '63980:f72ee9fa08b0b391b72a08dd315418ae96759089e54bc5ed728d37806082807e',
    '65556:67cface7bcca0fbc359c687a3a93842798eb2ad00ab0cbe316e78d18d042cf28',
    '69423:92c1e5942911be88cdfa8be3db786dd90ea4bd441445cc4278f057c779557c1b',
    '69431:22fe4905a8681297dba0a50a7a0a75352d687ff4ea3da18f93310480e3276753',
    '69837:c1f2cd4695fc36a8720f7a56d70f830b15b7056f68902b042e3a03f23a6862f5',
    '78013:3e125f85cbbf10ef184f6c5b9190a447508e4918dbfda0e05fb72eb495c5d1a3',
    '89813:4efdc6ad1e8da72c83ac441a24930a99fc63ac573bdebc1ae0564f434615206d',
  ])
}

function certifiedNutritionJournalSplit(commandRoutes: string[]): string {
  const chunks = semanticChunks([
    'conversation.meal-interpreter.v1',
    'read_mobile_registration_feedback',
    'seal_conversation_meal_decision',
    'commit_conversation_meal_feedback_v2',
  ])
  expect(chunks, 'one exact nutrition/journal extraction').toHaveLength(1)
  const chunk = chunks[0] ?? ''
  certifyNutritionJournalSplitContent(readFileSync(chunk, 'utf8'))
  expect(chunkConsumers(chunk)).toEqual([...commandRoutes, nutritionWindowAppPath].sort())
  for (const route of [...commandRoutes, nutritionWindowAppPath]) {
    expect(
      tracedTargets(route).filter((target) => target === chunk),
      route,
    ).toEqual([chunk])
  }
  return chunk
}

function certifySharedModule(file: string, marker: string, expectedHash: string): void {
  const source = ts.createSourceFile(
    file,
    readFileSync(file, 'utf8'),
    ts.ScriptTarget.Latest,
    true,
    ts.ScriptKind.JS,
  )
  const bodies: string[] = []
  const visit = (node: ts.Node) => {
    if (
      ts.isFunctionLike(node) &&
      ts.isPropertyAssignment(node.parent) &&
      ts.isObjectLiteralExpression(node.parent.parent) &&
      ts.isBinaryExpression(node.parent.parent.parent) &&
      node.parent.parent.parent.left.getText(source) === 'exports.modules'
    ) {
      const text = node.getText(source)
      if (text.includes(marker)) bodies.push(text)
    }
    ts.forEachChild(node, visit)
  }
  visit(source)
  expect(bodies, `one complete qualified ${marker} module`).toHaveLength(1)
  expect(
    createHash('sha256')
      .update(bodies[0] ?? '')
      .digest('hex'),
  ).toBe(expectedHash)
}

function certifiedClinicalPolicySelectorCopies(): string[] {
  // The query selector now also validates the closed day_energy opt-in.
  // Both full module copies must match that reviewed additive parser; the
  // photo chunk still co-locates it with the unchanged project selector.
  const copies = semanticChunks(['invalid_clinical_policy_representation'])
  expect(copies).toHaveLength(2)
  for (const file of copies)
    certifySharedModule(
      file,
      'invalid_clinical_policy_representation',
      'b544bf4ddfa7a5a941baaa9527fc43835826b73036df3cfea287fe5541411547',
    )
  return copies
}

function certifiedWorkoutRepositoryCopies(): string[] {
  const markers = ['admit', 'materialize', 'get', 'edit', 'cancel', 'confirm'].map(
    (operation) => `${operation}_mobile_workout_registration`,
  )
  const copies = semanticChunks(markers)
  expect(copies).toHaveLength(2)
  const bodies = copies.map((path) => {
    const source = ts.createSourceFile(
      path,
      readFileSync(path, 'utf8'),
      ts.ScriptTarget.Latest,
      true,
      ts.ScriptKind.JS,
    )
    const candidates: string[] = []
    const visit = (node: ts.Node) => {
      if (ts.isFunctionLike(node)) {
        const text = node.getText(source)
        if (markers.every((marker) => text.includes(marker))) candidates.push(text)
      }
      ts.forEachChild(node, visit)
    }
    visit(source)
    // The narrow factory and its enclosing Webpack module. Compare the whole
    // module, using syntax/semantics rather than generated module/chunk IDs.
    expect(candidates).toHaveLength(2)
    return candidates.sort((left, right) => left.length - right.length)[1] ?? ''
  })
  expect(bodies[0]).toBe(bodies[1])
  return copies
}

function certifyInlineConversationEditModule(sharedChunk: string, journalRoute: string): void {
  const markers = [
    'conversation.meal-edit-effect-public.v1',
    'conversation.meal-group.v1',
    'conversation.meal-group.v2',
  ]
  const journalEntry = currentAppPathsManifest()[journalRoute]
  expect(journalEntry).toBeTypeOf('string')
  const copies = [sharedChunk, resolve(buildRoot, 'server', journalEntry ?? '')]
  const modules = copies.map((file) => {
    const source = ts.createSourceFile(
      file,
      readFileSync(file, 'utf8'),
      ts.ScriptTarget.Latest,
      true,
      ts.ScriptKind.JS,
    )
    const bodies: string[] = []
    const visit = (node: ts.Node) => {
      if (ts.isFunctionLike(node) && ts.isPropertyAssignment(node.parent)) {
        const body = node.getText(source)
        if (markers.every((marker) => body.includes(marker))) bodies.push(body)
      }
      ts.forEachChild(node, visit)
    }
    visit(source)
    // Compare the entire physical Webpack module, not just DTO marker strings
    // or selected functions. No generated source is omitted from the scans.
    expect(bodies, file).toHaveLength(1)
    return bodies[0]
  })
  expect(modules[0]).toBeTruthy()
  expect(modules[0]).toBe(modules[1])
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
  test('keeps the approved 85-route path and named-export manifest', () => {
    const records = sourceRecords()
    const hash = hashRecords(records)

    console.info(`SOURCE_ROUTE_EXPORT_COUNT=${records.length}`)
    console.info(`SOURCE_ROUTE_EXPORT_STREAM_SHA256=${hash}`)

    expect(records).toHaveLength(85)
    expect(hash).toBe('afb3a6182ad8e1335a24edeb3f2394f411ee6935f9994c1ecfb0c164079c3d12')
    expect(records.find((record) => record.path === nutritionWindowSourceRoute)).toEqual({
      path: nutritionWindowSourceRoute,
      exports: ['GET', 'dynamic', 'runtime'],
    })
    const prior84 = records.filter((record) => record.path !== nutritionWindowSourceRoute)
    expect(prior84).toHaveLength(84)
    expect(hashRecords(prior84)).toBe(
      '092bd3ded789b200042cf29119e279e22d6900f8cdc86889108f28d2764673f3',
    )
    const replies = new Set(conversationReplyAdditions),
      prior82 = prior84.filter((record) => !replies.has(record.path))
    expect(prior82).toHaveLength(82)
    expect(hashRecords(prior82)).toBe(
      '1edcfecc752f7657306d9a4f852c9ff3b37f2770270441a3bb37972366957c98',
    )
    expect(records.filter((record) => replies.has(record.path))).toEqual([
      {
        path: 'conversation/commands/[commandId]/replies/[replyId]/route.ts',
        exports: ['GET', 'maxDuration', 'runtime'],
      },
      {
        path: 'conversation/commands/[commandId]/replies/route.ts',
        exports: ['POST', 'maxDuration', 'runtime'],
      },
    ])
    const extensions = new Set(conversationReadEditAdditions)
    const prior78 = prior82.filter((record) => !extensions.has(record.path))
    expect(prior78).toHaveLength(78)
    expect(hashRecords(prior78)).toBe(
      '3ab0b1fdb146ab6a06846b5702cfa70a1a7b997d73b3235655ec248c32f68874',
    )
    expect(records.filter((record) => extensions.has(record.path))).toEqual(
      conversationReadEditAdditions.map((path) => ({
        path,
        exports: [path.includes('/edits/') ? 'POST' : 'GET', 'maxDuration', 'runtime'],
      })),
    )
    const prior75 = prior84.filter((record) => !record.path.startsWith('conversation/'))
    expect(prior75).toHaveLength(75)
    expect(hashRecords(prior75)).toBe(
      '109cdb03a29399358c586046a6f98aace5eb6628fed4f290e1ca05193cc1a0a1',
    )
    const prior74 = prior75.filter((record) => record.path !== 'auth/password-recovery/route.ts')
    expect(prior74).toHaveLength(74)
    expect(hashRecords(prior74)).toBe(
      '9c7daf99f0c9baab62f037d3d9301417c4a025283e863f44cd4dfab77588e485',
    )
    const additions = new Set<string>(currentClinicalRouteAdditions)
    const prior56 = prior74.filter((record) => !additions.has(record.path))
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
    expect(
      records.find((record) => record.path === 'auth/password-recovery/route.ts')?.exports,
    ).toEqual(['GET', 'HEAD', 'POST', 'dynamic', 'maxDuration', 'runtime'])
  })

  test('keeps the v1 journal source unchanged and read-only Auth factory inert with no journal calls', () => {
    const library = resolve(appRoot, '../admin/src/lib/mobile-api')
    // Exact prior5e8-parent source, independently checked before the new build.
    expect(
      createHash('sha256')
        .update(readFileSync(resolve(library, 'conversation-meal-journal-store.ts')))
        .digest('hex'),
    ).toBe('d006ed0689e1d4043b4fb31bd3c1026313eca2e7ff9c810fe6f3513bffb881b4')
    const parse = (name: string) =>
      ts.createSourceFile(
        name,
        readFileSync(resolve(library, name), 'utf8'),
        ts.ScriptTarget.Latest,
        true,
        ts.ScriptKind.TS,
      )
    const runtime = parse('conversation-meal-readonly-runtime.ts')
    expect(
      runtime.statements
        .filter(ts.isImportDeclaration)
        .map((node) => (node.moduleSpecifier as ts.StringLiteral).text)
        .sort(),
    ).toEqual(
      [
        '../supabase/server',
        './conversation-meal-reply-scope',
        './entitlement-service',
        './route',
        '@mpp/db',
      ].sort(),
    )
    const factory = runtime.statements.find(
      (node): node is ts.FunctionDeclaration =>
        ts.isFunctionDeclaration(node) &&
        node.name?.text === 'createConversationMealReadonlyRuntime',
    )
    expect(factory).toBeDefined()
    if (!factory?.body) throw new Error('Missing actual readonly runtime factory')
    const constructorCalls: string[] = [],
      allCalls: string[] = [],
      constructions: string[] = []
    const visitConstructor = (node: ts.Node) => {
      if (ts.isFunctionLike(node)) return
      if (ts.isCallExpression(node)) constructorCalls.push(node.expression.getText(runtime))
      ts.forEachChild(node, visitConstructor)
    }
    visitConstructor(factory.body)
    expect(constructorCalls).toEqual(['Object.freeze'])
    const visit = (node: ts.Node) => {
      if (ts.isCallExpression(node)) {
        const callee = node.expression
        allCalls.push(
          ts.isPropertyAccessExpression(callee) &&
            callee.expression.kind === ts.SyntaxKind.RegularExpressionLiteral
            ? 'RegExp.test'
            : callee.getText(runtime),
        )
      }
      if (ts.isNewExpression(node)) constructions.push(node.expression.getText(runtime))
      ts.forEachChild(node, visit)
    }
    visit(factory.body)
    expect(allCalls.sort()).toEqual(
      [
        'Object.freeze',
        'authenticateConversationReplyPatient',
        'createConversationMealReplyReadonlyAuth',
        'authorizeMobileEntitlement',
        'request.headers.get',
        'RegExp.test',
        'crypto.randomUUID',
      ].sort(),
    )
    expect(constructions).toEqual(['URL'])
    const scope = parse('conversation-meal-reply-scope.ts'),
      journal = scope.statements.find(
        (node): node is ts.ImportDeclaration =>
          ts.isImportDeclaration(node) &&
          ts.isStringLiteral(node.moduleSpecifier) &&
          node.moduleSpecifier.text === './conversation-meal-journal-store',
      ),
      bindings = journal?.importClause?.namedBindings
    if (!bindings || !ts.isNamedImports(bindings))
      throw new Error('Missing qualified journal helper import')
    expect(bindings.elements.map((node) => (node.propertyName ?? node.name).text).sort()).toEqual([
      'conversationJournalInstant',
      'conversationJournalUUID',
    ])
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
    expect(routesOutsideMobilePrefix).toEqual([
      resolve(dedicatedAppRoot, 'api/webhooks/revenuecat/route.ts'),
    ])
  })

  test('detects a horizontally indented inline Server Action directive', () => {
    const inlineServerAction = ['async function submit() {', "\t'use server';", '}'].join('\n')

    expect(hasServerActionDirective(inlineServerAction)).toBe(true)
  })

  test('preserves 84 prior Mobile routes plus the nutrition window and RevenueCat webhook in the Next build', () => {
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

    expect(surface.routePaths).toHaveLength(86)
    expect(surface.routePathHash).toBe(
      '6cf74c6833a222ddc0b21838a47498a472abaf1cdd7f5bbce1057e0944bc0e3c',
    )
    expect(surface.mobileRoutePaths).toHaveLength(85)
    expect(surface.mobileRoutePathHash).toBe(
      '637c96d6e9baccb01b5b780f73ea89dbb628cb949264620c40ca474b1500b267',
    )
    const prior84Mobile = surface.mobileRoutePaths.filter((path) => path !== nutritionWindowURL)
    const prior85All = surface.routePaths.filter((path) => path !== nutritionWindowURL)
    expect(prior84Mobile).toHaveLength(84)
    expect(
      createHash('sha256')
        .update(prior84Mobile.map((path) => `${path}\n`).join(''))
        .digest('hex'),
    ).toBe('ce7e7f5eeef07c517594e9e5d188e9e469e318eaa5e73788b387254715b56297')
    expect(prior85All).toHaveLength(85)
    expect(
      createHash('sha256')
        .update(prior85All.map((path) => `${path}\n`).join(''))
        .digest('hex'),
    ).toBe('55f824f5d65f2af80403535744fa3e1bf54dc2c01082bfb33276df0b32f665a5')
    const extensions = new Set(
      conversationReadEditAdditions.map(
        (path) => `/api/mobile/v1/${path.replace(/\/route.ts$/, '')}`,
      ),
    )
    const replies = new Set(
      conversationReplyAdditions.map((path) => `/api/mobile/v1/${path.replace(/\/route.ts$/, '')}`),
    )
    const prior82Paths = prior84Mobile.filter((path) => !replies.has(path))
    expect(prior82Paths).toHaveLength(82)
    expect(
      createHash('sha256')
        .update(prior82Paths.map((path) => `${path}\n`).join(''))
        .digest('hex'),
    ).toBe('81cebb1636073fffe9bb8316c11dd5e2aef6603ead95b7007458719d0bcaa53e')
    const prior83All = prior85All.filter((path) => !replies.has(path))
    expect(prior83All).toHaveLength(83)
    expect(
      createHash('sha256')
        .update(prior83All.map((path) => `${path}\n`).join(''))
        .digest('hex'),
    ).toBe('7da84c6d7303c8dc1bccaea6c75f05546d399ebdf794375ead21e186e14bacf9')
    const prior78Paths = prior82Paths.filter((path) => !extensions.has(path))
    expect(prior78Paths).toHaveLength(78)
    expect(
      createHash('sha256')
        .update(prior78Paths.map((path) => `${path}\n`).join(''))
        .digest('hex'),
    ).toBe('feb10dcfc43742d384f5852b573634fc4a5226e52c15856eb24a1f2c5ee9aa54')
    const prior74Paths = prior84Mobile.filter(
      (route) =>
        !route.startsWith('/api/mobile/v1/conversation/') &&
        route !== '/api/mobile/v1/auth/password-recovery',
    )
    expect(prior74Paths).toHaveLength(74)
    expect(
      createHash('sha256')
        .update(prior74Paths.map((route) => `${route}\n`).join(''))
        .digest('hex'),
    ).toBe('266398770b61425d8172e2912eade6187a597060c710c51dcfbaff6fc7c8a272')
    const additions = new Set(
      currentClinicalRouteAdditions.map(
        (path) => `/api/mobile/v1/${path.replace(/\/route.ts$/, '')}`,
      ),
    )
    const prior56 = prior74Paths.filter((route) => !additions.has(route))
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
    expect(surface.routesOutsideMobilePrefix).toEqual(['/api/webhooks/revenuecat'])
    expect(surface.forbiddenAdminRoutes).toEqual([])
    expect(surface.forbiddenInngestRoutes).toEqual([])
    expect(surface.forbiddenStripeRoutes).toEqual([])
    expect(surface.forbiddenAdminMediaRoutes).toEqual([])
    expect(surface.pageRoutes).toEqual([])
    expect(surface.middlewareEntries).toEqual([])
    expect(surface.serverActionReferences).toEqual([])
  })

  test('rejects a changed or additional module in the exact nutrition journal split certificate', () => {
    const chunks = semanticChunks([
      'conversation.meal-interpreter.v1',
      'read_mobile_registration_feedback',
      'seal_conversation_meal_decision',
      'commit_conversation_meal_feedback_v2',
    ])
    expect(chunks).toHaveLength(1)
    const text = readFileSync(chunks[0] ?? '', 'utf8')
    expect(() => certifyNutritionJournalSplitContent(text)).not.toThrow()
    expect(() =>
      certifyNutritionJournalSplitContent(
        text.replace('seal_conversation_meal_decision', 'seal_changed_decision'),
      ),
    ).toThrow(/certified nutrition-shared module contents/)
    expect(() =>
      certifyNutritionJournalSplitContent(
        text.replace('exports.modules={', 'exports.modules={0:()=>{},'),
      ),
    ).toThrow(/certified nutrition-shared module count/)
    expect(() => certifyNutritionJournalSplitContent(text.replace('13300:', '999999:'))).toThrow(
      /certified nutrition-shared module contents/,
    )
  })

  test('keeps the nutrition live call graph on the journal instant helper and readonly runtime only', () => {
    const library = resolve(appRoot, '../admin/src/lib/mobile-api')
    const parse = (name: string) =>
      ts.createSourceFile(
        name,
        readFileSync(resolve(library, name), 'utf8'),
        ts.ScriptTarget.Latest,
        true,
        ts.ScriptKind.TS,
      )
    const source = parse('nutrition-window-service.ts')
    const imports = source.statements.filter(ts.isImportDeclaration).map((node) => ({
      path: (node.moduleSpecifier as ts.StringLiteral).text,
      names:
        node.importClause?.namedBindings && ts.isNamedImports(node.importClause.namedBindings)
          ? node.importClause.namedBindings.elements.map((item) => item.name.text).sort()
          : [],
    }))
    expect(imports).toEqual([
      { path: 'node:crypto', names: ['createHash'] },
      {
        path: '@mpp/agent',
        names: ['addIsoDateDays', 'getLocalDateString', 'getLocalDayUtcBounds'],
      },
      { path: 'zod', names: ['z'] },
      { path: './conversation-meal-journal-store', names: ['conversationJournalInstant'] },
      { path: './http', names: ['MobileApiError'] },
      { path: './idempotency', names: ['hashMobileRequest'] },
    ])
    const calls: ts.CallExpression[] = []
    const visit = (node: ts.Node) => {
      if (ts.isCallExpression(node)) calls.push(node)
      ts.forEachChild(node, visit)
    }
    visit(source)
    expect(
      calls.filter((node) => node.expression.getText(source) === 'conversationJournalInstant'),
    ).toHaveLength(2)
    expect(
      calls
        .filter(
          (node) =>
            ts.isPropertyAccessExpression(node.expression) &&
            ['rpc', 'from', 'insert', 'update', 'upsert', 'delete'].includes(
              node.expression.name.text,
            ),
        )
        .map((node) => node.expression.getText(source).replace(/\s+/g, '')),
    ).toEqual(['Array.from', "createHash('sha256').update"])
    const repository = parse('nutrition-window-repository.ts')
    const rpc: string[] = []
    const visitRPC = (node: ts.Node) => {
      if (
        ts.isCallExpression(node) &&
        ts.isPropertyAccessExpression(node.expression) &&
        node.expression.name.text === 'rpc'
      ) {
        expect(node.arguments[0] && ts.isStringLiteral(node.arguments[0])).toBe(true)
        rpc.push((node.arguments[0] as ts.StringLiteral).text)
      }
      ts.forEachChild(node, visitRPC)
    }
    visitRPC(repository)
    expect(rpc).toEqual(['read_nutrition_window_units'])
    const runtime = parse('nutrition-window-runtime.ts')
    const runtimeFactory = runtime.statements.find(
      (node): node is ts.FunctionDeclaration =>
        ts.isFunctionDeclaration(node) && node.name?.text === 'createNutritionWindowReadService',
    )
    if (!runtimeFactory?.body) throw new Error('Missing actual nutrition readonly runtime')
    const constructorCalls: string[] = []
    const visitConstructor = (node: ts.Node) => {
      if (ts.isFunctionLike(node)) return
      if (ts.isCallExpression(node)) constructorCalls.push(node.expression.getText(runtime))
      ts.forEachChild(node, visitConstructor)
    }
    visitConstructor(runtimeFactory.body)
    expect(constructorCalls).toEqual(['createSupabaseCurrentClinicalStateSource', 'Object.freeze'])
  })

  test('keeps the compiled nutrition reader confined to its GET entry and readonly owned RPC', () => {
    expect(currentAppPathsManifest()[nutritionWindowAppPath]).toBe(
      'app/api/mobile/v1/nutrition/window/route.js',
    )
    expect(tracedTargets(nutritionWindowAppPath).length).toBeGreaterThan(0)
    for (const marker of ['nutrition.window.v1', 'read_nutrition_window_units']) {
      expect(runtimeMarkerRoutes(marker)).toEqual([nutritionWindowAppPath])
    }
    for (const marker of [
      'capture_mobile_clinical_day_close',
      'apply_mobile_clinical_day_close',
      'commit_conversation_meal_item_edit',
      'undo_conversation_meal_registration',
      'commit_mobile_registration_feedback',
    ]) {
      expect(runtimeMarkerRoutes(marker)).not.toContain(nutritionWindowAppPath)
    }
  })

  test.each([
    false,
    true,
  ])('checks the 85 Mobile and 86 total inventory in the synthetic CLI with extra nutrition route=%s', (extraRoute) => {
    const appPaths = Object.fromEntries([
      ...sourceRecords().map(({ path }) => {
        const appPath = `/api/mobile/v1/${path.replace(/\.ts$/, '')}`
        return [appPath, `app${appPath}.js`]
      }),
      ['/api/webhooks/revenuecat/route', 'app/api/webhooks/revenuecat/route.js'],
      ...(extraRoute
        ? [
            [
              '/api/mobile/v1/nutrition/unapproved/route',
              'app/api/mobile/v1/nutrition/unapproved/route.js',
            ],
          ]
        : []),
    ])
    withSyntheticBuild(appPaths, (syntheticBuild) => {
      const root = mkdtempSync(resolve(appRoot, '.mobile-bff-inventory-cli-'))
      try {
        const script = resolve(root, 'scripts/verify-build-surface.mjs')
        mkdirSync(dirname(script), { recursive: true })
        writeFileSync(script, readFileSync(resolve(appRoot, 'scripts/verify-build-surface.mjs')))
        symlinkSync(syntheticBuild, resolve(root, '.next'), 'dir')
        const result = spawnSync(process.execPath, [script], {
          encoding: 'utf8',
          timeout: 30_000,
        })
        expect(result.error).toBeUndefined()
        expect(result.status, result.stderr).toBe(extraRoute ? 1 : 0)
        expect(result.stdout).toContain(`BUILD_MOBILE_ROUTE_PATH_COUNT=${extraRoute ? 86 : 85}`)
        expect(result.stdout).toContain(`BUILD_ROUTE_PATH_COUNT=${extraRoute ? 87 : 86}`)
        if (extraRoute) {
          expect(result.stderr).toContain('BUILD_SURFACE_ERROR=PRIOR84_MOBILE_ROUTE_COUNT:85')
          expect(result.stderr).toContain('BUILD_SURFACE_ERROR=PRIOR84_MOBILE_ROUTE_HASH:')
          expect(result.stdout).not.toContain('BUILD_SURFACE_STATUS=VERIFIED')
        } else {
          expect(result.stderr).toBe('')
          expect(result.stdout).toContain('BUILD_PRIOR84_MOBILE_ROUTE_PATH_COUNT=84')
          expect(result.stdout).toContain('BUILD_PRIOR85_ALL_ROUTE_PATH_COUNT=85')
          expect(result.stdout).toContain(
            'BUILD_MOBILE_ROUTE_PATH_STREAM_SHA256=637c96d6e9baccb01b5b780f73ea89dbb628cb949264620c40ca474b1500b267',
          )
          expect(result.stdout).toContain(
            'BUILD_ROUTE_PATH_STREAM_SHA256=6cf74c6833a222ddc0b21838a47498a472abaf1cdd7f5bbce1057e0944bc0e3c',
          )
        }
      } finally {
        rmSync(root, { recursive: true, force: true })
      }
    })
  })

  test('keeps explicit bounded runtime budgets for the new command mutations and rich journal read', () => {
    const manifest = JSON.parse(
      readFileSync(resolve(buildRoot, 'server/functions-config-manifest.json'), 'utf8'),
    ) as { functions: Record<string, { maxDuration?: number }> }
    const paths = [
      '/api/mobile/v1/conversation/meal-commands',
      ...conversationReadEditAdditions.map(
        (path) => `/api/mobile/v1/${path.replace(/\/route.ts$/, '')}`,
      ),
      ...conversationReplyAdditions.map(
        (path) => `/api/mobile/v1/${path.replace(/\/route.ts$/, '')}`,
      ),
    ]
    for (const path of paths) expect(manifest.functions[path]?.maxDuration, path).toBe(120)
    expect(manifest.functions['/api/mobile/v1/auth/password-recovery']?.maxDuration).toBe(45)
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
  ])('rejects $name while the same 86 URL keys remain', ({
    expectedError,
    mutate,
    omittedTargets,
  }) => {
    const appPaths = mutate(currentAppPathsManifest())

    expect(Object.keys(appPaths)).toHaveLength(86)
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
    // Recovery is now an explicit independent addition. The historical graph below
    // still excludes exactly that route; all routes retain the global security scans.
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
    const allBuildRoutes = Object.keys(currentAppPathsManifest())
    const currentMobileRoutes = allBuildRoutes.filter((route) =>
      route.startsWith('/api/mobile/v1/'),
    )
    expect(currentMobileRoutes).toHaveLength(85)
    expect(
      currentMobileRoutes
        .filter((route) => route.startsWith('/api/mobile/v1/conversation/'))
        .sort(),
    ).toEqual(
      [
        ...conversationReadEditAdditions.map(
          (path) => `/api/mobile/v1/${path.replace(/\.ts$/, '')}`,
        ),
        ...conversationReplyAdditions.map((path) => `/api/mobile/v1/${path.replace(/\.ts$/, '')}`),
        '/api/mobile/v1/conversation/meal-commands/[commandId]/route',
        '/api/mobile/v1/conversation/meal-commands/route',
        '/api/mobile/v1/conversation/session/route',
      ].sort(),
    )
    // Keep the full historical 75-route dependency graph pinned below. The
    // nine conversation routes and the exact nutrition addition remain in every global forbidden scan.
    const allRoutes = currentMobileRoutes.filter(
      (route) =>
        route !== nutritionWindowAppPath && !route.startsWith('/api/mobile/v1/conversation/'),
    )
    expect(allRoutes).toHaveLength(75)
    const recoveryRoute = '/api/mobile/v1/auth/password-recovery/route'
    const priorRoutes = allRoutes.filter((route) => route !== recoveryRoute)
    expect(priorRoutes).toHaveLength(74)
    // Recovery makes Next split its existing HTTP/runtime vendor modules into
    // one shared chunk. Certify this exact extra edge in every route, without
    // exempting it from any of the global security scans above/below.
    const nextHttpSplit = uniqueChunk([
      'middleware-request-page',
      'Headers cannot be modified',
      'NodeNextRequest.stream() can only be called once',
    ])
    expect(chunkConsumers(nextHttpSplit)).toEqual(allBuildRoutes.slice().sort())
    for (const route of allRoutes) {
      expect(
        tracedTargets(route).filter((target) => target === nextHttpSplit),
        route,
      ).toEqual([nextHttpSplit])
    }
    const vendorSource = readFileSync(nextHttpSplit, 'utf8')
    for (const marker of [
      'MOBILE_PASSWORD_RECOVERY_PROJECT_REF',
      'invalid_auth_response',
      'current_clinical_runtime_unavailable',
    ])
      expect(vendorSource).not.toContain(marker)
    const priorTargets = (route: string): string[] =>
      tracedTargets(route).filter((target) => target !== nextHttpSplit)
    // Webpack now compiles the unchanged workout repository twice. Keep all
    // actual trace/consumer/security checks physical. Collapse ONLY these two
    // proven copies for the historical unique-node count, never for semantics.
    const repositoryCopies = certifiedWorkoutRepositoryCopies()
    const repositoryUniqueSize = (targets: string[]) =>
      new Set(
        targets.map((target) =>
          repositoryCopies.includes(target) ? 'logical:unchanged-workout-repository' : target,
        ),
      ).size
    const priorTargetSet = new Set(priorRoutes.flatMap(priorTargets))
    expect(priorRoutes.reduce((sum, route) => sum + priorTargets(route).length, 0)).toBe(8028)
    expect(priorTargetSet.size).toBe(215)
    expect(repositoryUniqueSize([...priorTargetSet])).toBe(214)
    expect(tracedTargets(recoveryRoute)).toHaveLength(100)
    expect(
      [...new Set(allRoutes.flatMap(tracedTargets))]
        .filter((target) => !priorTargetSet.has(target))
        .sort(),
    ).toEqual(
      [
        realpathSync(
          resolve(
            buildRoot,
            'server/app/api/mobile/v1/auth/password-recovery/route_client-reference-manifest.js',
          ),
        ),
        nextHttpSplit,
      ].sort(),
    )
    // All75 keep8202 references. The verified duplicate is217 physical targets,
    // still216 logical identities; the webhook adds only its own manifest.
    const webhookRoute = '/api/webhooks/revenuecat/route'
    const mobileTargets = new Set(allRoutes.flatMap(tracedTargets))
    expect(allRoutes.reduce((sum, route) => sum + tracedTargets(route).length, 0)).toBe(8202)
    expect(mobileTargets.size).toBe(217)
    expect(repositoryUniqueSize([...mobileTargets])).toBe(216)
    expect(tracedTargets(webhookRoute)).toHaveLength(104)
    expect(tracedTargets(webhookRoute).filter((target) => !mobileTargets.has(target))).toEqual([
      realpathSync(
        resolve(buildRoot, 'server/app/api/webhooks/revenuecat/route_client-reference-manifest.js'),
      ),
    ])
    // Existing onboarding trial grant keeps its original writer; the signed
    // provider transport must be reachable only from the new webhook.
    expect(runtimeMarkerRoutes('apply_entitlement_event')).toEqual([
      '/api/mobile/v1/onboarding/route',
      webhookRoute,
    ])
    expect(runtimeMarkerRoutes('x-revenuecat-webhook-signature')).toEqual([webhookRoute])
    const commandRoutes = currentMobileRoutes
      .filter((route) => route.startsWith('/api/mobile/v1/conversation/'))
      .sort()
    const commandChunk = uniqueChunk([
      'conversation.meal-command-result.v1',
      'MOBILE_CONVERSATION_COMMANDS_ENABLED',
      'conversation_admission_rate_limited',
    ])
    expect(chunkConsumers(commandChunk)).toEqual(commandRoutes)
    expect(runtimeMarkerRoutes('conversation_commands_unavailable')).toEqual(commandRoutes)
    const journalRoute = '/api/mobile/v1/conversation/journal/route'
    const editRoutes = conversationReadEditAdditions
      .filter((p) => !p.startsWith('conversation/journal/'))
      .map((p) => `/api/mobile/v1/${p.replace(/\.ts$/, '')}`)
      .sort()
    const replyRoutes = conversationReplyAdditions
      .map((path) => `/api/mobile/v1/${path.replace(/\.ts$/, '')}`)
      .sort()
    const priorReadonlyRoutes = [...replyRoutes, journalRoute, ...editRoutes].sort()
    const readonlyRoutes = [...priorReadonlyRoutes, nutritionWindowAppPath].sort()
    const readonlyScopeChunk = uniqueChunk([
      'conversation_scope_unavailable',
      'patient_admin_account_conflict',
      'read_conversation_meal_journal_page',
    ])
    const replyChunk = uniqueChunk([
      'conversation.meal-reply-result.v1',
      'admit_conversation_meal_reply',
      'commit_conversation_meal_continuation',
    ])
    expect(chunkConsumers(readonlyScopeChunk)).toEqual(readonlyRoutes)
    expect(
      chunkConsumers(readonlyScopeChunk).filter((route) => route !== nutritionWindowAppPath),
    ).toEqual(priorReadonlyRoutes)
    expect(chunkConsumers(replyChunk)).toEqual(replyRoutes)
    for (const route of Object.keys(currentAppPathsManifest())) {
      expect(
        tracedTargets(route).filter((target) => target === readonlyScopeChunk),
        route,
      ).toHaveLength(readonlyRoutes.includes(route) ? 1 : 0)
      expect(
        tracedTargets(route).filter((target) => target === replyChunk),
        route,
      ).toHaveLength(replyRoutes.includes(route) ? 1 : 0)
    }
    const publicEditChunk = uniqueChunk([
      'conversation.meal-edit-effect-public.v1',
      'conversation.meal-group.v1',
      'conversation.meal-group.v2',
    ])
    const editWriterChunk = uniqueChunk([
      'commit_conversation_meal_item_edit',
      'undo_conversation_meal_item_edit',
      'undo_conversation_meal_registration',
      'read_conversation_meal_edit_operation',
    ])
    // Reusing the closed edit JSON boundary in the actual materializer makes
    // Webpack merge the public projection and writer chunks. The journal now
    // embeds one byte-identical public projection module in its own entry.
    // Certify only those four removed trace edges; every physical source and
    // every writer marker remains subject to the original global checks.
    expect(publicEditChunk).toBe(editWriterChunk)
    certifyInlineConversationEditModule(publicEditChunk, journalRoute)
    expect(chunkConsumers(publicEditChunk)).toEqual(editRoutes)
    expect(chunkConsumers(editWriterChunk)).toEqual(editRoutes)
    for (const marker of [
      'conversation.meal-edit-effect-public.v1',
      'conversation.meal-group.v1',
      'conversation.meal-group.v2',
    ])
      expect(runtimeMarkerRoutes(marker)).toEqual([...editRoutes, journalRoute].sort())
    for (const marker of [
      'commit_conversation_meal_item_edit',
      'undo_conversation_meal_item_edit',
      'undo_conversation_meal_registration',
      'read_conversation_meal_edit_operation',
    ])
      expect(runtimeMarkerRoutes(marker)).toEqual(editRoutes)
    // This physical read marker travels with the shared readonly Auth module.
    // The source-level constructor/import guard above prohibits a journal call.
    expect(runtimeMarkerRoutes('read_conversation_meal_journal_page')).toEqual(readonlyRoutes)
    expect(runtimeMarkerRoutes('read_conversation_meal_journal_page_v2')).toEqual([journalRoute])
    for (const marker of [
      'conversation.meal-reply-result.v1',
      'admit_conversation_meal_reply',
      'prepare_conversation_meal_continuation',
      'commit_conversation_meal_continuation',
    ])
      expect(runtimeMarkerRoutes(marker)).toEqual(replyRoutes)
    const expectedCommandCounts = new Map([
      ['/api/mobile/v1/conversation/meal-commands/[commandId]/route', 119],
      ['/api/mobile/v1/conversation/meal-commands/route', 119],
      ['/api/mobile/v1/conversation/session/route', 119],
      [journalRoute, 121],
      ...editRoutes.map((route) => [route, 122] as const),
      ...replyRoutes.map((route) => [route, 121] as const),
    ])
    const nutritionJournalSplit = certifiedNutritionJournalSplit(commandRoutes)
    // Normalize only this certified new edge, for the nine original routes.
    // No route, module, writer marker or trace is removed from global scans.
    const priorCommandTargets = (route: string): string[] =>
      tracedTargets(route).filter((target) => target !== nutritionJournalSplit)
    expect([...expectedCommandCounts.keys()].sort()).toEqual(commandRoutes)
    for (const [route, count] of expectedCommandCounts)
      expect(priorCommandTargets(route), route).toHaveLength(count)
    expect(new Set([commandChunk, publicEditChunk, readonlyScopeChunk, replyChunk]).size).toBe(4)
    const legacyTargets = new Set([...allRoutes, webhookRoute].flatMap(tracedTargets))
    const commandOnlyTargets = [...new Set(commandRoutes.flatMap(priorCommandTargets))]
      .filter((target) => !legacyTargets.has(target))
      .sort()
    expect(commandOnlyTargets).toEqual(
      [
        ...new Set([
          commandChunk,
          publicEditChunk,
          editWriterChunk,
          readonlyScopeChunk,
          replyChunk,
          ...commandRoutes.map((route) =>
            realpathSync(
              resolve(buildRoot, 'server/app', `${route.slice(1)}_client-reference-manifest.js`),
            ),
          ),
        ]),
      ].sort(),
    )
    // Raw totals, without folding any new chunk/edge into historical scopes.
    // Exactly six readonly edges and two reply-writer edges were proved above.
    const priorBuildRoutes = allBuildRoutes.filter((route) => route !== nutritionWindowAppPath)
    const priorBuildTrace = (route: string): string[] =>
      commandRoutes.includes(route) ? priorCommandTargets(route) : tracedTargets(route)
    const priorBuildTargets = new Set(priorBuildRoutes.flatMap(priorBuildTrace))
    expect(priorBuildRoutes.reduce((sum, route) => sum + priorBuildTrace(route).length, 0)).toBe(
      8202 + 104 + 3 * 119 + 3 * 122 + 121 + 2 * 121,
    )
    expect(priorBuildTargets.size).toBe(217 + 1 + 9 + 4)
    expect([...priorBuildTargets].filter((target) => statSync(target).isFile())).toHaveLength(
      215 + 1 + 9 + 4,
    )
    expect([...priorBuildTargets].filter((target) => statSync(target).isDirectory())).toHaveLength(
      2,
    )
    // Only the exact additive route is removed from historical counts. Its full
    // physical graph remains in inspectBuildSurface's security/directory scans.
    const nutritionTargets = tracedTargets(nutritionWindowAppPath)
    const nutritionOnlyTargets = nutritionTargets.filter((target) => !priorBuildTargets.has(target))
    expect(surface.nftReferenceCount).toBe(
      8202 +
        104 +
        3 * 119 +
        3 * 122 +
        121 +
        2 * 121 +
        commandRoutes.length +
        nutritionTargets.length,
    )
    expect(surface.nftUniqueTargetCount).toBe(217 + 1 + 9 + 4 + nutritionOnlyTargets.length)
    expect(surface.nftRegularFileTargetCount).toBe(
      215 + 1 + 9 + 4 + nutritionOnlyTargets.filter((target) => statSync(target).isFile()).length,
    )
    expect(surface.nftDirectoryTargetCount).toBe(2)
    const additions = new Set(
      currentClinicalRouteAdditions.map((path) => `/api/mobile/v1/${path.replace(/\.ts$/, '')}`),
    )
    expect(additions.size).toBe(18)
    expect(allRoutes.filter((route) => additions.has(route))).toHaveLength(18)
    const historicalRoutes = allRoutes.filter(
      (route) => !additions.has(route) && route !== '/api/mobile/v1/auth/password-recovery/route',
    )
    expect(historicalRoutes).toHaveLength(56)
    expect(historicalRoutes.reduce((sum, route) => sum + priorTargets(route).length, 0)).toBe(6089)
    expect(new Set(historicalRoutes.flatMap(priorTargets)).size).toBe(194)
    expect(repositoryUniqueSize(historicalRoutes.flatMap(priorTargets))).toBe(193)
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
        commands: true,
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
        markers: ['MOBILE_CURRENT_CLINICAL_PROJECT_REF', 'invalid_clinical_policy_representation'],
        commands: true,
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
        commands: true,
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
        commands: true,
        // Read-only BF provenance now shares the daily repository with legacy
        // admission. Certify all three ports in that one existing seven-route
        // chunk, while the whole closer retains its original six consumers.
        // Admission is a separate unchanged module; do not assume it stays
        // co-located with the daily reader/protection module.
        admissionMarker: 'admit_mobile_clinical_legacy_generation',
        markers: [
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
      if ('otherAdded' in edge && edge.otherAdded !== undefined) {
        // The same closed selector is compiled once for current clinical
        // routes and once for photos; neither copy may acquire other callers.
        const copies = certifiedClinicalPolicySelectorCopies()
        const historicalCopy = copies.filter((file) =>
          chunkConsumers(file).includes(edge.old[0] ?? ''),
        )
        expect(historicalCopy).toHaveLength(1)
        chunk = historicalCopy[0] ?? ''
        const photoCopy = copies.filter((file) => file !== chunk)
        expect(photoCopy).toHaveLength(1)
        expect(chunkConsumers(photoCopy[0] ?? '')).toEqual(edge.otherAdded)
      } else chunk = uniqueChunk(edge.markers)
      // Preserve every historical consumer exactly; the additive nutrition
      // closure is checked independently above and in the global scans.
      expect(chunkConsumers(chunk).filter((route) => route !== nutritionWindowAppPath)).toEqual(
        [
          ...edge.old,
          ...edge.added,
          ...('commands' in edge && edge.commands ? commandRoutes : []),
        ].sort(),
      )
      if ('otherAdded' in edge && edge.otherAdded !== undefined) {
        // Preserve the original project capability boundary independently of
        // the pure query selector's physical chunk location.
        expect(runtimeMarkerRoutes('MOBILE_CURRENT_CLINICAL_PROJECT_REF')).toEqual(
          [
            ...edge.old,
            ...edge.added,
            ...commandRoutes,
            ...edge.otherAdded,
            '/api/mobile/v1/onboarding/health/route',
            '/api/mobile/v1/onboarding/reconsent/route',
          ].sort(),
        )
        // Webpack extracted the error code separately from the now shared
        // pure selector. Require the original guard in every legacy closure.
        const guarded = runtimeMarkerRoutes('current_clinical_runtime_unavailable')
        for (const route of [...edge.old, ...edge.added, ...(edge.otherAdded ?? [])])
          expect(guarded).toContain(route)
      }
      if ('admissionMarker' in edge && edge.admissionMarker !== undefined) {
        const copies = semanticChunks([edge.admissionMarker])
        expect(copies).toHaveLength(3)
        for (const file of copies)
          certifySharedModule(
            file,
            edge.admissionMarker,
            '0c64099813e18981be9bf9399c12bf706d60648d49146bd754dfb412f8eb827a',
          )
        expect(runtimeMarkerRoutes(edge.admissionMarker)).toEqual(
          [
            ...edge.old,
            ...commandRoutes,
            ...routeNames([
              'reevaluation',
              'reevaluation/start',
              'reevaluation/form',
              'reevaluation/assess',
              'reevaluation/preview',
              'reevaluation/confirm',
              'reevaluation/health',
            ]),
          ].sort(),
        )
        // The reviewed reader now negotiates Today v4 field availability;
        // certify its complete module while retaining all global scans.
        certifySharedModule(
          chunk,
          'clinical_client_update_required',
          '5b0a2553a7042b12554aebdc1e7d10a15150229326a28336a89ea86703d0a61e',
        )
        certifySharedModule(
          chunk,
          'get_mobile_clinical_daily_context',
          'c09b5f9f2cbc0b24316b5699adf421e721d0bbc62122865ea9c203e0feff657f',
        )
      }
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
      priorTargets(route).filter((target) => !exemptions.get(route)?.has(target))
    const historicalConsumers = (chunk: string): string[] =>
      historicalRoutes.filter((route) => historicalTargets(route).includes(chunk)).sort()
    expect([...exemptions.values()].reduce((sum, edges) => sum + edges.size, 0)).toBe(56)
    expect(historicalRoutes.reduce((sum, route) => sum + historicalTargets(route).length, 0)).toBe(
      6033,
    )
    expect(new Set(historicalRoutes.flatMap(historicalTargets)).size).toBe(187)
    expect(repositoryUniqueSize(historicalRoutes.flatMap(historicalTargets))).toBe(186)
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
    const receiptCopies = semanticChunks(['read_mobile_registration_feedback'])
    expect(receiptCopies).toHaveLength(2)
    expect(receiptCopies).toContain(nutritionJournalSplit)
    const legacyReceiptCopies = receiptCopies.filter((chunk) => chunk !== nutritionJournalSplit)
    expect(legacyReceiptCopies).toHaveLength(1)
    const receiptChunk = legacyReceiptCopies[0] ?? ''
    expect(historicalConsumers(receiptChunk)).toEqual([...reviewRoutes, clarificationRoute].sort())
    expect(runtimeMarkerRoutes('read_mobile_registration_feedback')).toEqual(
      [...historyFeedbackRoutes, ...reviewRoutes, ...commandRoutes, nutritionWindowAppPath].sort(),
    )
    expect(runtimeMarkerRoutes('proposal->>source_provider_message_id')).toEqual(
      [...historyFeedbackRoutes, ...editRoutes, journalRoute].sort(),
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
      if (historyFeedbackRoutes.includes(route)) {
        const ownedRepository = repositoryCopies.filter((copy) => raw.includes(copy))
        expect(ownedRepository, route).toHaveLength(1)
        extras.push(ownedRepository[0] ?? '', readModelChunk)
      }
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
    const chunks = certifiedWorkoutRepositoryCopies()
    // One byte-identical module is now emitted twice. Physical consumers are
    // still certified exactly; protected feedback writes remain five reviews.
    for (const chunk of chunks) {
      const source = readFileSync(chunk, 'utf8')
      for (const operation of ['admit', 'materialize', 'get', 'edit', 'cancel', 'confirm']) {
        expect(source).toContain(`${operation}_mobile_workout_registration`)
      }
    }
    const repositoryRoutes = [
      ...reviewRoutes,
      ...historyFeedbackRoutes,
      ...conversationReadEditAdditions.map((p) => `/api/mobile/v1/${p.replace(/\.ts$/, '')}`),
    ].sort()
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
    expect(writerChunks).toHaveLength(1)
    expect(readFileSync(switchChunks[0] ?? '', 'utf8')).toContain('ui-v1')
    // The selector/repository now also serves the protected read question,
    // while the feedback writer remains an independent five-review chunk.
    expect(writerChunks).not.toEqual(switchChunks)
    expect(chunkConsumers(switchChunks[0] ?? '')).toEqual(
      [...reviewRoutes, '/api/mobile/v1/workouts/[id]/strength-clarification/route'].sort(),
    )
    expect(chunkConsumers(writerChunks[0] ?? '')).toEqual(reviewRoutes)
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
