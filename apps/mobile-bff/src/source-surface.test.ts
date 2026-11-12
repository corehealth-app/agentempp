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
// Only these three transports are subtracted at the historical 85/86 boundary.
// All current routes remain inputs to the global source/build/transitive scans.
const conversationWorkoutAdditions = [
  'conversation/workout-commands/[commandId]/route.ts',
  'conversation/workout-commands/route.ts',
  'conversation/workout-session/route.ts',
]
const conversationWorkoutSourcePaths = new Set(conversationWorkoutAdditions)
const conversationWorkoutURLs = new Set(
  conversationWorkoutAdditions.map((path) => `/api/mobile/v1/${path.replace(/\/route.ts$/, '')}`),
)
const conversationWorkoutAppPaths = new Set(
  [...conversationWorkoutURLs].map((path) => `${path}/route`),
)
const conversationIntakeAdditions = [
  'conversation/intakes/[intakeId]/route.ts',
  'conversation/intakes/route.ts',
  'conversation/intakes/session/route.ts',
]
const conversationIntakeSourcePaths = new Set(conversationIntakeAdditions)
const conversationIntakeURLs = new Set(
  conversationIntakeAdditions.map((path) => `/api/mobile/v1/${path.replace(/\/route.ts$/, '')}`),
)
const conversationIntakeAppPaths = new Set(
  [...conversationIntakeURLs].map((path) => `${path}/route`),
)
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

const exactStringCache = new Map<string, { text: string; values: ReadonlySet<string> }>()
function containsExactJSString(file: string, value: string): boolean {
  const text = readFileSync(file, 'utf8'),
    prior = exactStringCache.get(file)
  if (prior?.text === text) return prior.values.has(value)
  const source = ts.createSourceFile(file, text, ts.ScriptTarget.Latest, true, ts.ScriptKind.JS),
    values = new Set<string>()
  const visit = (node: ts.Node) => {
    if (ts.isStringLiteralLike(node)) values.add(node.text)
    ts.forEachChild(node, visit)
  }
  visit(source)
  exactStringCache.set(file, { text, values })
  return values.has(value)
}
function exactStringChunks(value: string): string[] {
  return walkFiles(resolve(buildRoot, 'server/chunks'))
    .filter((file) => file.endsWith('.js') && containsExactJSString(file, value))
    .map((file) => realpathSync(file))
    .sort()
}
function runtimeExactStringRoutes(value: string): string[] {
  return Object.entries(currentAppPathsManifest())
    .filter(([route, target]) =>
      [resolve(buildRoot, 'server', target), ...tracedTargets(route)].some(
        (file) => file.endsWith('.js') && containsExactJSString(file, value),
      ),
    )
    .map(([route]) => route)
    .sort()
}

// Exact T36 extraction: all16 previously certified module bodies are byte-identical.
// Default existing-account Auth additionally co-locates the unchanged reply-scope
// aliases and readonly runtime (previously in reply/edit chunks). No source body
// or physical route/NFT consumer was discarded by this packaging translation.
// These bodies include dormant writer adapters; this certificate never declares
// them absent and never exempts any physical code from the global scans.
// T40 exposes three existing pure Auth decoders for the request-owned refusal
// latch. Only module11098 changes; the other17 bodies and exact consumers stay
// pinned. Source qualification proves the three extractions are otherwise exact.
// T43's actual intake runtime retains those three exports. The same source SHA
// is sealed below; module11098 is newly certified in full, with the other17
// compiled bodies still byte-identical. No old raw module body is claimed here.
function certifyNutritionJournalSplitContent(text: string): void {
  // T52/R79 extend the report prefix; R82 also permits pure punctuation in `other`.
  // R81 records closed guard reasons; R82 changes only its punctuation predicate.
  // Reversing the R82 compiled predicate restores the R81 module byte-exactly.
  // R79 adds the optional current-day adjunct; reversing that sole compiled delta
  // reproduces the prior module hash exactly. No other module body changed.
  // Seal the reviewed validator source before accepting its complete compiled body;
  // the other18 module identities, table/count and negative controls stay literal.
  // R95 accounts for the complete trailing current-meal context. Module65556's
  // helper/guard plus compiler-local renaming reverse byte-exactly to R82;
  // all other18 compiled bodies remain byte-identical. No consumer is exempted.
  // R98 also accounts for the separately labeled whole leading meal adjunct.
  // Removing only that helper/skip and reversing AST-local identifier allocation
  // restores the complete R95 body byte-exactly; the other18 bodies are unchanged.
  expect(
    createHash('sha256')
      .update(
        readFileSync(
          resolve(
            appRoot,
            '../admin/src/lib/mobile-api/conversation-meal-interpretation-validation.ts',
          ),
        ),
      )
      .digest('hex'),
  ).toBe('6f7fbb52eb0146e579c18c8f9f80159b0abe3d0862af5a9f2beaeeeb0af85c21')
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
  expect(bodies, 'certified nutrition-shared module count').toHaveLength(19)
  expect(
    bodies.map(({ id, body }) => `${id}:${createHash('sha256').update(body).digest('hex')}`).sort(),
    'certified nutrition-shared module contents',
  ).toEqual(
    [
      '11098:d8cccef169992ad42803f27d81d5b753a50e5798e8f649ad3acd7aea98fa6925',
      '40747:411b3586832f4b981362200d53a3836cff6395e29cee48554464d97d48fa94a9',
      '93639:ce2fe7a229147bad36167351267198cbd255aa881701566612da47ce193e2e04',
      '49634:fc711f099281a69d5ecf62a254ec8ffcfe202d33a181bcefae7d82d7e7e7dfe6',
      '85685:41deccfd9e90c2b6a6de3cf6e0493c94e9776c8a1bbc1f5fe4ee3bfe76475b1a',
      '13300:038a23c34b65eb1d040fa3bdf37dc2ca1f9da72a3b4460f16b263cf7b7880ccf',
      '19514:a189839890f820d1a04f8f29b5dd89af51577d935e8af5e7a344cc8a5a9344fd',
      '20853:5e5378aa0bd0fb541859f4fa6a9dc8c853525dcb697ac43864a72c61837772e9',
      '21378:3666116fbbe020c4e11038c8dca63660d541b8bd16140556f52cf892fcebb2f5',
      '36693:0c869a1e452f5f2f166dc854005dc68c8113771fe7c761aaeefcdf45f52d42dd',
      '52158:129ea4b769605c4e7ddee1f1bc26688f2d09e77a0922726299741a808f4ae420',
      '61104:b0cda866116f43ab0a961ecb885bce7cd7808cef006d23f98d37faa66a9db3dc',
      '63980:f72ee9fa08b0b391b72a08dd315418ae96759089e54bc5ed728d37806082807e',
      '65556:bc8a85d99b59cacdfaa40f396e9b30a23ac696f60563c519a8c28bff12e3f81b',
      '69423:37ddc2d0a8b30f80f4fa3636ccf2f406ebf262172e88117949b472d070fbc7a3',
      '69431:22fe4905a8681297dba0a50a7a0a75352d687ff4ea3da18f93310480e3276753',
      '69837:de43933bd7d89880c4ff178067cc8261700f1b969bdbbfa605c385ba219b1f77',
      '78013:384b82901395609752c82c968d6bcd54d37d7680cbf4c165b7c8d44d328810d4',
      '89813:4efdc6ad1e8da72c83ac441a24930a99fc63ac573bdebc1ae0564f434615206d',
    ].sort(),
  )
}

// T44/T45 introduce genuine internal media execution and historical reads.
// Eleven R58 bodies remain literal; seven changed bodies are recertified in
// full above, plus the new closed61104 lineage validator. No changed raw body
// is presented as byte-identical. Independent Git13 trace proof attributes
// every new physical edge; global scans below still inspect the entire graph.
function certifyExactSharedTable(
  file: string,
  pins: readonly (readonly [string, string])[],
): ReadonlyMap<string, string> {
  const source = ts.createSourceFile(
    file,
    readFileSync(file, 'utf8'),
    ts.ScriptTarget.Latest,
    true,
    ts.ScriptKind.JS,
  )
  const tables: ts.ObjectLiteralExpression[] = []
  const visit = (node: ts.Node) => {
    if (
      ts.isBinaryExpression(node) &&
      ts.isPropertyAccessExpression(node.left) &&
      node.left.getText(source) === 'exports.modules' &&
      ts.isObjectLiteralExpression(node.right)
    )
      tables.push(node.right)
    ts.forEachChild(node, visit)
  }
  visit(source)
  expect(tables).toHaveLength(1)
  const bodies = new Map<string, string>()
  const observed =
    tables[0]?.properties.map((property) => {
      if (!ts.isPropertyAssignment(property) || !ts.isArrowFunction(property.initializer))
        throw new Error('Unexpected shared module shape')
      const id = property.name.getText(source)
      const body = property.initializer.getText(source)
      bodies.set(id, body)
      return [id, createHash('sha256').update(body).digest('hex')].join(':')
    }) ?? []
  expect(observed.sort()).toEqual(pins.map(([id, hash]) => `${id}:${hash}`).sort())
  return bodies
}
/** T48 imports the existing intake capability predicate into a second route.
 * Webpack adds only its named export; every preexisting executable byte stays
 * equal to the independently preserved R63 module, not a normalized body. */
function certifyT48IntakeCapabilityExport(body: string): void {
  expect(
    createHash('sha256')
      .update(
        readFileSync(resolve(appRoot, '../admin/src/lib/mobile-api/conversation-intake-routes.ts')),
      )
      .digest('hex'),
  ).toBe('bfca54ddc258bdabf290483ef7a4b9817ca2cdf2bf5ba0bccbbfaae3b076e17c')
  expect(body.startsWith('(a,b,c)=>{c.d(b,{o:()=>ak,K:()=>an});')).toBe(true)
  expect(body.split('o:()=>ak,')).toHaveLength(2)
  // T52 changes only this compiler loader link. Retain the complete pre-T48
  // executable-body certificate after reversing that single proven change.
  expect(body.split('c(76697)')).toHaveLength(2)
  const beforeLabels = body.replace('c(76697)', 'c(56304)')
  expect(createHash('sha256').update(beforeLabels).digest('hex')).toBe(
    'dcaaecf8c587b9413c83a5fa8645a6803b789f71176f3622709150dca34cc0f1',
  )
  expect(beforeLabels.split('c(56304)')).toHaveLength(2)
  const preservedBody = beforeLabels.replace('c(56304)', 'c(66320)')
  expect(createHash('sha256').update(preservedBody.replace('o:()=>ak,', '')).digest('hex')).toBe(
    'bcfdd2d7bb47f1acdc50ebf2f7272d167b2e404523eb98f282dfa2b9239ebfb4',
  )
}
/** New shared read edge, extracted from the previous inline journal entry.
 * Certify complete current bodies and their unchanged authoritative sources;
 * keep every physical consumer and global forbidden scan independently checked. */
function certifyT48OriginPageChunk(chunk: string): void {
  for (const [name, hash] of [
    [
      'conversation-journal-v3-contracts.ts',
      'b2e87ddb1d6782371c4ec6b09553bd9de58457f53aa9cc5a0cf5e97d63907e12',
    ],
    [
      'conversation-journal-v3-store.ts',
      '0d8d4c37089a2294c4ce8a5897a47ace7d492c6e5e2bb9b4451b060c29765d42',
    ],
    [
      'conversation-meal-thread-page-store.ts',
      '49c9d4b0d281f757b4275bbe95f1f83d6426c67e07844dfd44b0ac0c30cdfd40',
    ],
  ] as const)
    expect(
      createHash('sha256')
        .update(readFileSync(resolve(appRoot, '../admin/src/lib/mobile-api', name)))
        .digest('hex'),
    ).toBe(hash)
  certifyExactSharedTable(chunk, [
    ['11127', 'af1048cd20f83493747e07f281dda8c9d5adebf9888864a6460321ab95afc9bf'],
    ['46469', 'de989ba8a001d564412cfc74ea06cb434909299a19c1dd6cd6af7416e68c1d11'],
    ['58670', 'c4f78ed80cc83d026c3a0079b132b7951835b782e969029c94fb4129d8c00e1b'],
  ])
}
const photoPurposeRoutesR59 = [
  '/api/mobile/v1/conversation/commands/[commandId]/replies/[replyId]/route',
  '/api/mobile/v1/conversation/commands/[commandId]/replies/route',
  '/api/mobile/v1/conversation/intakes/[intakeId]/route',
  '/api/mobile/v1/conversation/intakes/route',
  '/api/mobile/v1/conversation/intakes/session/route',
  '/api/mobile/v1/conversation/journal/route',
  '/api/mobile/v1/conversation/meal-commands/[commandId]/edits/[operationId]/reconcile/route',
  '/api/mobile/v1/conversation/meal-commands/[commandId]/edits/[operationId]/route',
  '/api/mobile/v1/conversation/meal-commands/[commandId]/meal/route',
  '/api/mobile/v1/conversation/meal-commands/[commandId]/origin/route',
  '/api/mobile/v1/conversation/meal-commands/[commandId]/route',
  '/api/mobile/v1/conversation/meal-commands/route',
  '/api/mobile/v1/conversation/session/route',
  '/api/mobile/v1/flow/chat/route',
  '/api/mobile/v1/meal-drafts/route',
  '/api/mobile/v1/reevaluation/[cycleId]/photos/[assetId]/complete/route',
  '/api/mobile/v1/reevaluation/[cycleId]/photos/[assetId]/process/route',
  '/api/mobile/v1/reevaluation/[cycleId]/photos/[assetId]/upload/route',
  '/api/mobile/v1/reevaluation/[cycleId]/photos/consent/route',
  '/api/mobile/v1/reevaluation/[cycleId]/photos/discard/route',
  '/api/mobile/v1/reevaluation/[cycleId]/photos/route',
]
const photoManifestRoutesR59 = [
  '/api/mobile/v1/media/[id]/complete/route',
  '/api/mobile/v1/media/[id]/process/route',
  '/api/mobile/v1/media/[id]/route',
  '/api/mobile/v1/media/route',
  '/api/mobile/v1/onboarding/body-photos/[id]/complete/route',
  '/api/mobile/v1/onboarding/body-photos/consent/route',
  '/api/mobile/v1/onboarding/body-photos/route',
  '/api/mobile/v1/onboarding/route',
]
/** T51 adds the explicit OpenAI structured-output helper to the interpreter.
 * This one closed chunk has exactly12 interpreter consumers and no ordinary
 * media/workout edge. Every physical target remains in the global scans. */
function certifyStructuredMealHelperT51() {
  const chunks = semanticChunks(['strict:!0', 'json_schema', 'ZodObject'])
  expect(chunks).toHaveLength(1)
  const chunk = chunks[0] ?? ''
  expect(createHash('sha256').update(readFileSync(chunk)).digest('hex')).toBe(
    '244d387b273017361f6b2325eee2f4a8df6c59a98813b12a29aceb81cb40c767',
  )
  certifyExactSharedTable(chunk, [
    ['69725', '05baadb1daac3f593c2b929f33b08e833c6de075d41caebcbbae406ed9dd7f0d'],
  ])
  const interpreter = readFileSync(
    resolve(appRoot, '../admin/src/lib/mobile-api/conversation-meal-interpreter.ts'),
    'utf8',
  )
  expect(createHash('sha256').update(interpreter).digest('hex')).toBe(
    '50d604e2c9c48c7c134bcbda298f55c779682c1b0f423fd7e5bd78d1b2366baa',
  )
  // R80 adds closed enum/count observations only for completed ambiguities.
  // R81 adds closed screening reason codes and JSON encoding of this safe projection.
  // R83 changes only the literal role-boundary prompt; source identity stays sealed.
  // R95 adds one literal trailing-context/missing-quantity paragraph only;
  // removing that paragraph restores the reviewed prior source byte-exactly.
  // A retained233-file physical baseline proves the prompt/loader deltas only.
  // Helper bytes, exact route consumers and global scans remain enforced.
  // T53 replaces private literal replay with source-owned token labels on the same edge.
  expect(
    createHash('sha256')
      .update(
        readFileSync(
          resolve(appRoot, '../admin/src/lib/mobile-api/conversation-meal-source-labels.ts'),
        ),
      )
      .digest('hex'),
  ).toBe('b997c78ea98e695e1d1afa58abc65fce27aec3df5f5ef24408e719725aae8d46')
  expect(interpreter.split("import { zodResponseFormat } from 'openai/helpers/zod'")).toHaveLength(
    2,
  )
  for (const [name, hash] of [
    ['helpers/zod.js', '3b5de7cb2ef3225031f111c77d5ccdc81f61c4c711d415affcd55fcff3e7cf6c'],
    ['helpers/zod.mjs', '2ca84cb18fccda7f081f7e5226c93895fec896328b099f789f7ecb07572b1a89'],
    ['package.json', 'c9fccdc76efa16a6979dbeae4c991d2c0e3983e2d546aeafc1d37fbb1510b424'],
  ])
    expect(
      createHash('sha256')
        .update(readFileSync(resolve(appRoot, '../admin/node_modules/openai', name ?? '')))
        .digest('hex'),
    ).toBe(hash)
  const consumers = [
    '/api/mobile/v1/conversation/commands/[commandId]/replies/[replyId]/route',
    '/api/mobile/v1/conversation/commands/[commandId]/replies/route',
    '/api/mobile/v1/conversation/intakes/[intakeId]/route',
    '/api/mobile/v1/conversation/intakes/route',
    '/api/mobile/v1/conversation/intakes/session/route',
    '/api/mobile/v1/conversation/journal/route',
    '/api/mobile/v1/conversation/meal-commands/[commandId]/edits/[operationId]/reconcile/route',
    '/api/mobile/v1/conversation/meal-commands/[commandId]/edits/[operationId]/route',
    '/api/mobile/v1/conversation/meal-commands/[commandId]/meal/route',
    '/api/mobile/v1/conversation/meal-commands/[commandId]/origin/route',
    '/api/mobile/v1/conversation/meal-commands/[commandId]/route',
    '/api/mobile/v1/conversation/meal-commands/route',
    '/api/mobile/v1/conversation/session/route',
  ]
  expect(chunkConsumers(chunk)).toEqual(consumers)
  return {
    chunk,
    isEdge: (route: string, target: string) => consumers.includes(route) && target === chunk,
  }
}

function certifyPhotoPurposeEdgesR62() {
  const chunks = semanticChunks(['analyzeConversationImage', 'conversation.image-result.v1'])
  expect(chunks).toHaveLength(1)
  const chunk = chunks[0] ?? ''
  const bodies = certifyExactSharedTable(chunk, [
    ['84359', '1cca149ffc7a9278307e03f6771ba28c93f3b19eae40409afb60f8e623d203ab'],
    ['63867', 'bca65f93158ff60efe08f14a45537b8db4e719a9deb863c2b452b37a11862673'],
  ])
  // R62's routing diagnostics import the existing OpenAI error classes directly.
  // Webpack factors that SDK differently: Gemini changes only this loader ID.
  // Reverse exactly one link to retain the independent full R59 body pin; no
  // raw code or transitive is removed from the physical/global scans below.
  const gemini = bodies.get('84359') ?? ''
  // R98 reallocates the byte-identical image-result module from86248 to63867.
  // Reverse precisely that one loader link to retain the full prior body proof.
  const imageResultLinkR98 = 'd=c(63867)'
  expect(gemini.split(imageResultLinkR98)).toHaveLength(2)
  const geminiR95 = gemini.replace(imageResultLinkR98, 'd=c(86248)')
  expect(createHash('sha256').update(geminiR95).digest('hex')).toBe(
    'f3c74b65ac87a664ca460702b4dfc99fc11a910983a3a751a240f2239c16b4ed',
  )
  // T51's explicit OpenAI Zod helper changes only the one SDK loader link.
  // Reverse it to the preserved full R62 body before the independent R59 proof.
  const sdkLinkT51 = 'e=c(43296)'
  expect(geminiR95.split(sdkLinkT51)).toHaveLength(2)
  const geminiR62 = geminiR95.replace(sdkLinkT51, 'e=c(86603)')
  expect(createHash('sha256').update(geminiR62).digest('hex')).toBe(
    'd5cd1170f272342d9e151612ecaaa64bee38e42f0f28189555cddae46c764ff8',
  )
  const sdkLinkR62 = 'e=c(86603)'
  expect(geminiR62.split(sdkLinkR62)).toHaveLength(2)
  expect(
    createHash('sha256').update(geminiR62.replace(sdkLinkR62, 'e=c(15361)')).digest('hex'),
  ).toBe('e4ee0d8f1f9944845cba5265618eea34ea63840f275167b99585d6371bc44574')
  for (const [source, hash] of [
    ['vision/gemini.ts', '111500130aeef167929b5eff7f1f1783d99be104286e20a33ddb0c6f9a6f09aa'],
    [
      'vision/conversation-image-result.ts',
      '017483921854a10bef5184714894b616141512097e1633ee6bad680c168e17bc',
    ],
  ])
    expect(
      createHash('sha256')
        .update(readFileSync(resolve(appRoot, '../../packages/providers/src', source ?? '')))
        .digest('hex'),
    ).toBe(hash)
  expect(chunkConsumers(chunk)).toEqual(photoPurposeRoutesR59)
  const manifest = realpathSync(resolve(appRoot, '../../packages/providers/package.json'))
  expect(createHash('sha256').update(readFileSync(manifest)).digest('hex')).toBe(
    '705df5b7b1aec5addc632e8caf0d013bd7f7d9c7a0376ce588148140d6cc7c98',
  )
  for (const route of photoManifestRoutesR59) {
    expect(tracedTargets(route).filter((file) => file === manifest)).toEqual([manifest])
    expect(runtimeMarkerRoutes('https://openrouter.ai/api/v1')).not.toContain(route)
  }
  // Only named edges can be projected for the older historical count streams.
  // The real current graph, Gemini body, pure parser and vendor boundaries are
  // certified in full; no physical code is exempted from global scans.
  return {
    chunk,
    isEdge: (route: string, file: string) =>
      (photoPurposeRoutesR59.includes(route) && file === chunk) ||
      (photoManifestRoutesR59.includes(route) && file === manifest),
  }
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

const absorbedSelectorRoutes = new Set([
  ...reviewRoutes,
  '/api/mobile/v1/workouts/[id]/strength-clarification/route',
])
function certifyPhysicalModule(file: string, id: string, allowedHashes: readonly string[]): void {
  const text = readFileSync(file, 'utf8'),
    source = ts.createSourceFile(file, text, ts.ScriptTarget.Latest, true, ts.ScriptKind.JS)
  const found: ts.ArrowFunction[] = []
  const visit = (node: ts.Node) => {
    if (
      ts.isPropertyAssignment(node) &&
      node.name.getText(source) === id &&
      ts.isArrowFunction(node.initializer)
    )
      found.push(node.initializer)
    ts.forEachChild(node, visit)
  }
  visit(source)
  expect(found, `one physical reviewed module ${id}`).toHaveLength(1)
  const body = found[0]?.getText(source) ?? ''
  expect(allowedHashes).toContain(createHash('sha256').update(body).digest('hex'))
  expect(text.startsWith('"use strict";') || body.startsWith('(a,b,c)=>{"use strict";')).toBe(true)
}
function certifyAbsorbedWorkoutSelector(): void {
  const copies = semanticChunks(['MOBILE_WORKOUT_REGISTRATION_PROJECT_REF']),
    entry = currentAppPathsManifest()['/api/mobile/v1/workouts/[id]/strength-clarification/route']
  expect(copies).toHaveLength(2)
  if (!entry) throw new Error('Missing protected clarification entry')
  for (const file of [...copies, resolve(buildRoot, 'server', entry)])
    certifyPhysicalModule(file, '47804', [
      '09553b4b4395aa7bbb18baaf1991e1fd6086fd58cd64de575a16dba316741806',
      '5d69e37d38dfebebad9a617cc333686fdeee9e6797e6640d8c595b97f1b7d209',
    ])
  expect(runtimeMarkerRoutes('MOBILE_WORKOUT_REGISTRATION_PROJECT_REF')).toEqual(
    [
      ...absorbedSelectorRoutes,
      ...conversationWorkoutAppPaths,
      ...conversationIntakeAppPaths,
    ].sort(),
  )
}
const absorbedReferences = (routes: readonly string[]) =>
  routes.filter((route) => absorbedSelectorRoutes.has(route)).length

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
    const module = candidates.sort((left, right) => left.length - right.length)[1] ?? ''
    const hash = createHash('sha256').update(module).digest('hex')
    expect([
      'babb0feec0652c4cd31dc1dc36dbb98f9414262aa1361c1d43a7a59b56ddf733',
      'a023ad0988d9517992016e45acb6fc52741d468bf27c49538d31aab3b0140415',
    ]).toContain(hash)
    // The identical reviewed repository is strict in both physical copies:
    // one inherits the file directive, the other carries it in this module.
    expect(
      readFileSync(path, 'utf8').startsWith('"use strict";') ||
        module.startsWith('(a,b,c)=>{"use strict";'),
    ).toBe(true)
    return module.replace(/^\(a,b,c\)=>\{"use strict";/, '(a,b,c)=>{')
  })
  expect(bodies[0]).toBe(bodies[1])
  const entry =
    currentAppPathsManifest()['/api/mobile/v1/workouts/[id]/strength-clarification/route']
  if (!entry) throw new Error('Missing clarification entry')
  certifyPhysicalModule(resolve(buildRoot, 'server', entry), '32072', [
    'babb0feec0652c4cd31dc1dc36dbb98f9414262aa1361c1d43a7a59b56ddf733',
  ])
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
  test('rejects changed or additional modules in the T48 shared read-page extraction', () => {
    const chunks = semanticChunks([
      'read_conversation_journal_page_v3',
      'read_conversation_meal_journal_page_v2',
    ])
    expect(chunks).toHaveLength(1)
    const chunk = chunks[0] ?? '',
      text = readFileSync(chunk, 'utf8'),
      root = mkdtempSync(resolve(tmpdir(), 'performe-t48-read-chunk-')),
      changed = resolve(root, 'chunk.js')
    try {
      expect(() => certifyT48OriginPageChunk(chunk)).not.toThrow()
      for (const mutation of [
        text.replace('read_conversation_journal_page_v3', 'unapproved_rpc'),
        text.replace('11127:', '999998:'),
        text.replace('exports.modules={', 'exports.modules={999999:(a,b,c)=>{},'),
      ]) {
        writeFileSync(changed, mutation)
        expect(() => certifyT48OriginPageChunk(changed)).toThrow()
      }
    } finally {
      rmSync(root, { recursive: true, force: true })
    }
  })
  test('rejects changed exports or executable bytes around the exact T48 intake capability export', () => {
    const chunks = semanticChunks([
      'conversation.intake-result.v1',
      'read_conversation_intake_routing_result',
      'reconcile_conversation_intake_routing',
    ])
    expect(chunks).toHaveLength(1)
    const bodies = certifyExactSharedTable(chunks[0] ?? '', [
        ['34168', '5c180f5861365e95d2485fc2d0348dd3b1405695cbb1441dad80341cf593a67b'],
        ['47804', '5d69e37d38dfebebad9a617cc333686fdeee9e6797e6640d8c595b97f1b7d209'],
        ['50522', 'bced34a3d3a43ba50d1205c55bd2ead6cd4dbc8fc679a8ab5c46e9ed4af692e5'],
        ['69520', 'f4cd688e76a4fe531bfb190f98c8f2abfebaff9d2422c91eaf5bc99c60c32aa0'],
      ]),
      body = bodies.get('69520') ?? ''
    expect(() => certifyT48IntakeCapabilityExport(body)).not.toThrow()
    for (const changed of [
      body.replace('o:()=>ak,', ''),
      body.replace('o:()=>ak,', 'o:()=>ak,x:()=>ak,'),
      body.replace('MOBILE_CONVERSATION_INTAKES_ENABLED', 'MOBILE_CONVERSATION_UNREVIEWED'),
    ])
      expect(() => certifyT48IntakeCapabilityExport(changed)).toThrow()
  })
  test('distinguishes an exact legacy RPC from its v3 successor and invalidates changed-file cache', () => {
    const root = mkdtempSync(resolve(tmpdir(), 'performe-exact-rpc-')),
      file = resolve(root, 'rpc.js')
    try {
      writeFileSync(file, 'db.rpc("commit_mobile_registration_feedback_v3")')
      expect(containsExactJSString(file, 'commit_mobile_registration_feedback')).toBe(false)
      expect(containsExactJSString(file, 'commit_mobile_registration_feedback_v3')).toBe(true)
      writeFileSync(file, 'db.rpc(`commit_mobile_registration_feedback`)')
      expect(containsExactJSString(file, 'commit_mobile_registration_feedback')).toBe(true)
      expect(containsExactJSString(file, 'commit_mobile_registration_feedback_v3')).toBe(false)
    } finally {
      rmSync(root, { recursive: true, force: true })
    }
  })
  test('keeps the additive 92-route manifest and exact prior88 and prior85 export streams', () => {
    const records = sourceRecords()
    const hash = hashRecords(records)

    console.info(`SOURCE_ROUTE_EXPORT_COUNT=${records.length}`)
    console.info(`SOURCE_ROUTE_EXPORT_STREAM_SHA256=${hash}`)

    expect(records).toHaveLength(92)
    expect(hash).toBe('d59c9ee8bdb67a450c40c45bdc4f287233a2fe21aaa531c7ae08c19b23342152')
    const beforeLinked = records.filter(
      (record) => record.path !== 'conversation/meal-commands/[commandId]/origin/route.ts',
    )
    expect(beforeLinked).toHaveLength(91)
    expect(hashRecords(beforeLinked)).toBe(
      '161783e0c88223e0df8271ed658399734242dcb588e16128a3febd70527379a7',
    )
    const beforeOrigins = beforeLinked.map((record) =>
      record.path === 'conversation/intakes/route.ts'
        ? { ...record, exports: record.exports.filter((name) => name !== 'GET') }
        : record,
    )
    expect(hashRecords(beforeOrigins)).toBe(
      '1aee269695cf61901f5ecb802e8509ae9004481024926043353d1f7cf32db9f7',
    )
    expect(
      records.find((record) => record.path === 'conversation/commands/[commandId]/replies/route.ts')
        ?.exports,
    ).toEqual(['GET', 'POST', 'maxDuration', 'runtime'])
    const prior91 = beforeOrigins.map((record) =>
      record.path === 'conversation/commands/[commandId]/replies/route.ts'
        ? { ...record, exports: record.exports.filter((name) => name !== 'GET') }
        : record,
    )
    expect(hashRecords(prior91)).toBe(
      '93200635df44342607fb57b71a1b623e1dbd1ff442f6fdbe5997a9f7fe81dd67',
    )
    expect(records.filter((record) => conversationIntakeSourcePaths.has(record.path))).toEqual([
      {
        path: 'conversation/intakes/[intakeId]/route.ts',
        exports: ['GET', 'maxDuration', 'runtime'],
      },
      { path: 'conversation/intakes/route.ts', exports: ['GET', 'POST', 'maxDuration', 'runtime'] },
      { path: 'conversation/intakes/session/route.ts', exports: ['GET', 'dynamic', 'runtime'] },
    ])
    const prior88 = prior91.filter((record) => !conversationIntakeSourcePaths.has(record.path))
    expect(prior88).toHaveLength(88)
    expect(hashRecords(prior88)).toBe(
      '99623e7e5caf5d3b3df20eeb6bf840e6fb416f5e489498232a0c984a0a6e53b4',
    )
    expect(records.filter((record) => conversationWorkoutSourcePaths.has(record.path))).toEqual([
      {
        path: 'conversation/workout-commands/[commandId]/route.ts',
        exports: ['GET', 'maxDuration', 'runtime'],
      },
      {
        path: 'conversation/workout-commands/route.ts',
        exports: ['POST', 'maxDuration', 'runtime'],
      },
      { path: 'conversation/workout-session/route.ts', exports: ['GET', 'maxDuration', 'runtime'] },
    ])
    const prior85 = prior88.filter((record) => !conversationWorkoutSourcePaths.has(record.path))
    expect(prior85).toHaveLength(85)
    expect(hashRecords(prior85)).toBe(
      'afb3a6182ad8e1335a24edeb3f2394f411ee6935f9994c1ecfb0c164079c3d12',
    )
    expect(records.find((record) => record.path === nutritionWindowSourceRoute)).toEqual({
      path: nutritionWindowSourceRoute,
      exports: ['GET', 'dynamic', 'runtime'],
    })
    const prior84 = prior85.filter((record) => record.path !== nutritionWindowSourceRoute)
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
        exports: ['GET', 'POST', 'maxDuration', 'runtime'],
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
    // The reviewed extraction keeps the public aliases in the reply boundary
    // and moves the same readonly Auth/clock observer into one shared module.
    // Seal both modules; keep the original journal and inert-factory checks.
    const facade = parse('conversation-meal-reply-scope.ts')
    expect(createHash('sha256').update(facade.text).digest('hex')).toBe(
      '9731da3c0ff8ad9eae1248aa1d3b6f0d9026aba200dc241b41adca410d7bf6e8',
    )
    const delegated = facade.statements.find(
      (node): node is ts.ExportDeclaration =>
        ts.isExportDeclaration(node) &&
        node.moduleSpecifier !== undefined &&
        ts.isStringLiteral(node.moduleSpecifier) &&
        node.moduleSpecifier.text === './conversation-current-scope',
    )
    if (!delegated?.exportClause || !ts.isNamedExports(delegated.exportClause))
      throw new Error('Missing qualified readonly Auth aliases')
    expect(
      delegated.exportClause.elements.map((node) => [
        (node.propertyName ?? node.name).text,
        node.name.text,
      ]),
    ).toEqual([
      ['authenticateConversationPatientReadonly', 'authenticateConversationReplyPatient'],
      ['createConversationReadonlyAuth', 'createConversationMealReplyReadonlyAuth'],
    ])
    const scope = parse('conversation-current-scope.ts')
    expect(createHash('sha256').update(scope.text).digest('hex')).toBe(
      'f8106d2f19e5085c099719c736a396ed428f10349bc25ed9b7b04959e6697aed',
    )
    const journal = scope.statements.find(
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

  test('preserves the prior88 Mobile and prior89 total streams within the additive 91/92 build', () => {
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

    expect(surface.routePaths).toHaveLength(93)
    expect(surface.routePathHash).toBe(
      'e5d968718a4e2130b59bea56f3e9050d1cdbcc099b74bed5da94825c0308858e',
    )
    expect(surface.mobileRoutePaths).toHaveLength(92)
    expect(surface.mobileRoutePathHash).toBe(
      'e040081491bac0281bba6c8694893386c0d41958ed70767fea712d16212d5e54',
    )
    expect(surface.mobileRoutePaths.filter((path) => conversationIntakeURLs.has(path))).toEqual(
      [...conversationIntakeURLs].sort(),
    )
    const prior88Mobile = surface.mobileRoutePaths.filter(
        (path) =>
          path !== '/api/mobile/v1/conversation/meal-commands/[commandId]/origin' &&
          !conversationIntakeURLs.has(path),
      ),
      prior89All = surface.routePaths.filter(
        (path) =>
          path !== '/api/mobile/v1/conversation/meal-commands/[commandId]/origin' &&
          !conversationIntakeURLs.has(path),
      )
    expect(prior88Mobile).toHaveLength(88)
    expect(
      createHash('sha256')
        .update(prior88Mobile.map((path) => `${path}\n`).join(''))
        .digest('hex'),
    ).toBe('bc55eaf07caffd4b70de61dcc3a6b00d9e10cb8eb7e9cfe6996716e9bf981b05')
    expect(prior89All).toHaveLength(89)
    expect(
      createHash('sha256')
        .update(prior89All.map((path) => `${path}\n`).join(''))
        .digest('hex'),
    ).toBe('030d287839ebf4191e33357d3f5bfada7d405e1ab0b18a1367018d9311392b87')
    expect(surface.mobileRoutePaths.filter((path) => conversationWorkoutURLs.has(path))).toEqual(
      [...conversationWorkoutURLs].sort(),
    )
    const prior85Mobile = prior88Mobile.filter((path) => !conversationWorkoutURLs.has(path))
    const prior86All = prior89All.filter((path) => !conversationWorkoutURLs.has(path))
    expect(prior85Mobile).toHaveLength(85)
    expect(
      createHash('sha256')
        .update(prior85Mobile.map((path) => `${path}\n`).join(''))
        .digest('hex'),
    ).toBe('637c96d6e9baccb01b5b780f73ea89dbb628cb949264620c40ca474b1500b267')
    expect(prior86All).toHaveLength(86)
    expect(
      createHash('sha256')
        .update(prior86All.map((path) => `${path}\n`).join(''))
        .digest('hex'),
    ).toBe('6cf74c6833a222ddc0b21838a47498a472abaf1cdd7f5bbce1057e0944bc0e3c')
    const prior84Mobile = prior85Mobile.filter((path) => path !== nutritionWindowURL)
    const prior85All = prior86All.filter((path) => path !== nutritionWindowURL)
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

  test('keeps ordinary media validation off the model SDK barrel', () => {
    const providerRoutes = runtimeMarkerRoutes('https://openrouter.ai/api/v1')
    for (const suffix of [
      'media',
      'media/[id]',
      'media/[id]/complete',
      'media/[id]/process',
      'onboarding',
      'onboarding/body-photos',
      'onboarding/body-photos/consent',
      'onboarding/body-photos/[id]/complete',
    ])
      expect(providerRoutes).not.toContain(`/api/mobile/v1/${suffix}/route`)
  })

  test('keeps the photo-purpose opt-in local to its upload transport', () => {
    expect(runtimeMarkerRoutes('MOBILE_CONVERSATION_PHOTOS_ENABLED')).toEqual([
      '/api/mobile/v1/media/route',
    ])
    expect(runtimeMarkerRoutes('MOBILE_CONVERSATION_INTAKES_ENABLED')).toEqual(
      [...conversationIntakeAppPaths, '/api/mobile/v1/media/route'].sort(),
    )
    const entry = currentAppPathsManifest()['/api/mobile/v1/media/route']
    expect(entry).toBeTypeOf('string')
    certifyPhysicalModule(resolve(buildRoot, 'server', entry ?? ''), '8135', [
      '541137bac128a8705a63063545655a6aa9c9f2fe90ee53e6d01b391f02993ac7',
    ])
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
  ])('checks the 91 Mobile and 92 total inventory in the synthetic CLI with extra nutrition route=%s', (extraRoute) => {
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
        expect(result.stdout).toContain(`BUILD_MOBILE_ROUTE_PATH_COUNT=${extraRoute ? 93 : 92}`)
        expect(result.stdout).toContain(`BUILD_ROUTE_PATH_COUNT=${extraRoute ? 94 : 93}`)
        if (extraRoute) {
          expect(result.stderr).toContain('BUILD_SURFACE_ERROR=PRIOR88_MOBILE_ROUTE_COUNT:89')
          expect(result.stderr).toContain('BUILD_SURFACE_ERROR=PRIOR89_ALL_ROUTE_COUNT:90')
          expect(result.stderr).toContain('BUILD_SURFACE_ERROR=PRIOR85_MOBILE_ROUTE_COUNT:86')
          expect(result.stderr).toContain('BUILD_SURFACE_ERROR=PRIOR84_MOBILE_ROUTE_COUNT:85')
          expect(result.stderr).toContain('BUILD_SURFACE_ERROR=PRIOR84_MOBILE_ROUTE_HASH:')
          expect(result.stdout).not.toContain('BUILD_SURFACE_STATUS=VERIFIED')
        } else {
          expect(result.stderr).toBe('')
          expect(result.stdout).toContain('BUILD_PRIOR88_MOBILE_ROUTE_PATH_COUNT=88')
          expect(result.stdout).toContain('BUILD_PRIOR89_ALL_ROUTE_PATH_COUNT=89')
          expect(result.stdout).toContain(
            'BUILD_PRIOR88_MOBILE_ROUTE_PATH_STREAM_SHA256=bc55eaf07caffd4b70de61dcc3a6b00d9e10cb8eb7e9cfe6996716e9bf981b05',
          )
          expect(result.stdout).toContain(
            'BUILD_PRIOR89_ALL_ROUTE_PATH_STREAM_SHA256=030d287839ebf4191e33357d3f5bfada7d405e1ab0b18a1367018d9311392b87',
          )
          expect(result.stdout).toContain('BUILD_PRIOR85_MOBILE_ROUTE_PATH_COUNT=85')
          expect(result.stdout).toContain('BUILD_PRIOR86_ALL_ROUTE_PATH_COUNT=86')
          expect(result.stdout).toContain(
            'BUILD_PRIOR85_MOBILE_ROUTE_PATH_STREAM_SHA256=637c96d6e9baccb01b5b780f73ea89dbb628cb949264620c40ca474b1500b267',
          )
          expect(result.stdout).toContain(
            'BUILD_PRIOR86_ALL_ROUTE_PATH_STREAM_SHA256=6cf74c6833a222ddc0b21838a47498a472abaf1cdd7f5bbce1057e0944bc0e3c',
          )
          expect(result.stdout).toContain('BUILD_PRIOR84_MOBILE_ROUTE_PATH_COUNT=84')
          expect(result.stdout).toContain('BUILD_PRIOR85_ALL_ROUTE_PATH_COUNT=85')
          expect(result.stdout).toContain(
            'BUILD_MOBILE_ROUTE_PATH_STREAM_SHA256=e040081491bac0281bba6c8694893386c0d41958ed70767fea712d16212d5e54',
          )
          expect(result.stdout).toContain(
            'BUILD_ROUTE_PATH_STREAM_SHA256=e5d968718a4e2130b59bea56f3e9050d1cdbcc099b74bed5da94825c0308858e',
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
      ...conversationWorkoutURLs,
      '/api/mobile/v1/conversation/intakes',
      '/api/mobile/v1/conversation/intakes/[intakeId]',
      ...conversationReadEditAdditions.map(
        (path) => `/api/mobile/v1/${path.replace(/\/route.ts$/, '')}`,
      ),
      ...conversationReplyAdditions.map(
        (path) => `/api/mobile/v1/${path.replace(/\/route.ts$/, '')}`,
      ),
    ]
    for (const path of paths) expect(manifest.functions[path]?.maxDuration, path).toBe(120)
    expect(
      manifest.functions['/api/mobile/v1/conversation/intakes/session']?.maxDuration,
    ).toBeUndefined()
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
  ])('rejects $name while the same 92 URL keys remain', ({
    expectedError,
    mutate,
    omittedTargets,
  }) => {
    const appPaths = mutate(currentAppPathsManifest())

    expect(Object.keys(appPaths)).toHaveLength(93)
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
    expect(currentMobileRoutes).toHaveLength(92)
    expect(
      currentMobileRoutes
        .filter((route) => route.startsWith('/api/mobile/v1/conversation/'))
        .sort(),
    ).toEqual(
      [
        '/api/mobile/v1/conversation/meal-commands/[commandId]/origin/route',
        ...conversationWorkoutAppPaths,
        ...conversationIntakeAppPaths,
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
    // fifteen conversation routes and the exact nutrition addition remain in every global forbidden scan.
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
    const { isEdge: purposeEdge, chunk: ordinaryPhotoChunk } = certifyPhotoPurposeEdgesR62()
    const priorTargets = (route: string): string[] =>
      tracedTargets(route).filter(
        (target) => target !== nextHttpSplit && !purposeEdge(route, target),
      )
    // Webpack now compiles the unchanged workout repository twice. Keep all
    // actual trace/consumer/security checks physical. Collapse ONLY these two
    // proven copies for the historical unique-node count, never for semantics.
    const repositoryCopies = certifiedWorkoutRepositoryCopies()
    certifyAbsorbedWorkoutSelector()
    const repositoryUniqueSize = (targets: string[]) =>
      new Set(
        targets.map((target) =>
          repositoryCopies.includes(target) ? 'logical:unchanged-workout-repository' : target,
        ),
      ).size
    const priorTargetSet = new Set(priorRoutes.flatMap(priorTargets))
    expect(
      priorRoutes.reduce((sum, route) => sum + priorTargets(route).length, 0) +
        absorbedReferences(priorRoutes),
    ).toBe(8028)
    expect(priorTargetSet.size + 1).toBe(215)
    expect(repositoryUniqueSize([...priorTargetSet]) + 1).toBe(214)
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
        ordinaryPhotoChunk,
      ].sort(),
    )
    // All75 keep8202 references. The verified duplicate is217 physical targets,
    // still216 logical identities; the webhook adds only its own manifest.
    const webhookRoute = '/api/webhooks/revenuecat/route'
    const mobileTargets = new Set(allRoutes.flatMap(tracedTargets))
    expect(
      allRoutes.reduce((sum, route) => sum + tracedTargets(route).length, 0) +
        absorbedReferences(allRoutes),
    ).toBe(8202 + 16)
    expect(mobileTargets.size + 1).toBe(218)
    expect(repositoryUniqueSize([...mobileTargets]) + 1).toBe(217)
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
    // Current conversation closure, certified physically in this actual build.
    // Historical meal counts are retained with only the explicitly qualified
    // extraction1098 and three new common2279 edges accounted for below.
    const linkedOriginRoute = '/api/mobile/v1/conversation/meal-commands/[commandId]/origin/route'
    const commandRoutes = currentMobileRoutes
        .filter((route) => route.startsWith('/api/mobile/v1/conversation/'))
        .sort(),
      historicalMealCommandRoutes = commandRoutes.filter(
        (route) =>
          route !== linkedOriginRoute &&
          !conversationWorkoutAppPaths.has(route) &&
          !conversationIntakeAppPaths.has(route),
      ),
      workoutRoutes = [...conversationWorkoutAppPaths].sort(),
      intakeRoutes = [...conversationIntakeAppPaths].sort(),
      mealCommandConsumers = [
        ...historicalMealCommandRoutes,
        ...intakeRoutes,
        linkedOriginRoute,
      ].sort(),
      workoutCommandConsumers = [...workoutRoutes, ...intakeRoutes].sort(),
      journalRoute = '/api/mobile/v1/conversation/journal/route',
      editRoutes = conversationReadEditAdditions
        .filter((p) => !p.startsWith('conversation/journal/'))
        .map((p) => `/api/mobile/v1/${p.replace(/\.ts$/, '')}`)
        .sort(),
      replyRoutes = conversationReplyAdditions
        .map((p) => `/api/mobile/v1/${p.replace(/\.ts$/, '')}`)
        .sort(),
      rootRoutes = [
        '/api/mobile/v1/conversation/meal-commands/[commandId]/route',
        '/api/mobile/v1/conversation/meal-commands/route',
        '/api/mobile/v1/conversation/session/route',
      ].sort()
    expect(commandRoutes).toHaveLength(16)
    expect(historicalMealCommandRoutes).toEqual(
      [...rootRoutes, journalRoute, ...editRoutes, ...replyRoutes].sort(),
    )
    const mealChunk = uniqueChunk([
        'conversation_admission_rate_limited',
        'conversation_commands_unavailable',
      ]),
      commonChunk = uniqueChunk([
        'read_mobile_registration_feedback_v3',
        'commit_mobile_registration_feedback_v3',
      ]),
      workoutChunk = uniqueChunk([
        'conversation.workout-session.v1',
        'reconcile_conversation_workout',
      ]),
      scopeChunk = certifiedNutritionJournalSplit(commandRoutes),
      replyChunk = uniqueChunk([
        'conversation.meal-reply-result.v1',
        'admit_conversation_meal_reply',
        'commit_conversation_meal_continuation',
      ]),
      publicEditChunk = uniqueChunk([
        'conversation.meal-edit-effect-public.v1',
        'conversation.meal-group.v1',
        'conversation.meal-group.v2',
      ]),
      editWriterChunk = uniqueChunk([
        'commit_conversation_meal_item_edit',
        'undo_conversation_meal_item_edit',
        'undo_conversation_meal_registration',
        'read_conversation_meal_edit_operation',
      ]),
      intakeChunk = uniqueChunk([
        'conversation.intake-result.v1',
        'read_conversation_intake_routing_result',
        'reconcile_conversation_intake_routing',
      ])
    // R62 qualifies the router's closed failure diagnostics and existing SDK
    // error-class imports against this exact source and complete module body.
    // Independent R59 body: 1ad24d6589b874c420dbfc09b405b86c331378f98a646adf764ea0e8bf60a855.
    // The other three modules stay byte-exact; no physical/global scan changes.
    expect(
      createHash('sha256')
        .update(
          readFileSync(
            resolve(appRoot, '../admin/src/lib/mobile-api/conversation-intake-router.ts'),
          ),
        )
        .digest('hex'),
    ).toBe('59468451392c18de6c80d7e4820d1bdb43eee9f5e9043996ecd5e70c8226a044')
    const intakeBodies = certifyExactSharedTable(intakeChunk, [
      ['34168', '5c180f5861365e95d2485fc2d0348dd3b1405695cbb1441dad80341cf593a67b'],
      ['47804', '5d69e37d38dfebebad9a617cc333686fdeee9e6797e6640d8c595b97f1b7d209'],
      ['50522', 'bced34a3d3a43ba50d1205c55bd2ead6cd4dbc8fc679a8ab5c46e9ed4af692e5'],
      ['69520', 'f4cd688e76a4fe531bfb190f98c8f2abfebaff9d2422c91eaf5bc99c60c32aa0'],
    ])
    const intakeBody = intakeBodies.get('69520') ?? ''
    expect(intakeBody.split('c(76697)')).toHaveLength(2)
    const intakeBeforeLabels = intakeBody.replace('c(76697)', 'c(56304)')
    expect(createHash('sha256').update(intakeBeforeLabels).digest('hex')).toBe(
      'dcaaecf8c587b9413c83a5fa8645a6803b789f71176f3622709150dca34cc0f1',
    )
    expect(intakeBeforeLabels.split('c(56304)')).toHaveLength(2)
    expect(
      createHash('sha256').update(intakeBeforeLabels.replace('c(56304)', 'c(66320)')).digest('hex'),
    ).toBe('fbca2d1d44287900ae260889c29202df5ca7f1128e1122ac5ec8c1c08f633445')
    certifyT48IntakeCapabilityExport(intakeBodies.get('69520') ?? '')
    // Full typed service code remains physically present, including dormant
    // writers. Journal3 invokes only read through its tested closed RPC port.
    certifySharedModule(
      workoutChunk,
      'reconcile_conversation_workout',
      '4fccbc5add63f82c43a05756fb7717bfa501b0f19ab0961ccc1e8b002321dd49',
    )
    // T48's lookup-only GET reuses the same qualified STABLE history reader.
    // The two new public markers must remain confined to that parent entry;
    // child intake/session and every unrelated route still lack this RPC.
    const originsRoute = '/api/mobile/v1/conversation/intakes/route'
    const originsPageChunk = uniqueChunk([
      'read_conversation_journal_page_v3',
      'read_conversation_meal_journal_page_v2',
    ])
    certifyT48OriginPageChunk(originsPageChunk)
    expect(chunkConsumers(originsPageChunk)).toEqual([originsRoute, journalRoute])
    expect(runtimeExactStringRoutes('read_conversation_journal_page_v3')).toEqual([
      originsRoute,
      journalRoute,
    ])
    expect(runtimeExactStringRoutes('conversation.meal-question-origins.v1')).toEqual([
      originsRoute,
    ])
    expect(runtimeExactStringRoutes('intake-question-origins-v1')).toEqual([originsRoute])
    expect(
      new Set([
        mealChunk,
        commonChunk,
        workoutChunk,
        scopeChunk,
        replyChunk,
        publicEditChunk,
        intakeChunk,
      ]).size,
    ).toBe(7)
    expect(publicEditChunk).toBe(editWriterChunk)
    certifyInlineConversationEditModule(publicEditChunk, journalRoute)
    for (const [chunk, routes] of [
      [mealChunk, mealCommandConsumers],
      [commonChunk, commandRoutes],
      [workoutChunk, [...workoutCommandConsumers, journalRoute].sort()],
      [scopeChunk, [...commandRoutes, nutritionWindowAppPath].sort()],
      [replyChunk, replyRoutes],
      [publicEditChunk, editRoutes],
      [intakeChunk, intakeRoutes],
    ] as const)
      expect(chunkConsumers(chunk)).toEqual(routes)
    for (const [marker, routes] of [
      ['conversation_commands_unavailable', mealCommandConsumers],
      ['read_conversation_meal_journal_page', [...commandRoutes, nutritionWindowAppPath].sort()],
      ['read_conversation_meal_journal_page_v2', [originsRoute, journalRoute]],
      [
        'conversation.meal-edit-effect-public.v1',
        [...editRoutes, originsRoute, journalRoute].sort(),
      ],
      ...['conversation.meal-group.v1', 'conversation.meal-group.v2'].map(
        (marker) => [marker, [...editRoutes, journalRoute].sort()] as const,
      ),
      ...[
        'commit_conversation_meal_item_edit',
        'undo_conversation_meal_item_edit',
        'undo_conversation_meal_registration',
        'read_conversation_meal_edit_operation',
      ].map((marker) => [marker, editRoutes] as const),
      ...[
        'conversation.meal-reply-result.v1',
        'admit_conversation_meal_reply',
        'prepare_conversation_meal_continuation',
        'commit_conversation_meal_continuation',
      ].map((marker) => [marker, replyRoutes] as const),
    ] as const)
      expect(runtimeMarkerRoutes(marker)).toEqual(routes)
    for (const rpc of [
      'admit_conversation_intake',
      'capture_conversation_intake_source',
      'claim_conversation_intake_routing',
      'seal_conversation_intake_routing',
      'read_conversation_intake',
      'read_conversation_intake_routing_result',
      'reconcile_conversation_intake_routing',
    ])
      expect(runtimeExactStringRoutes(rpc), rpc).toEqual(intakeRoutes)
    for (const route of allBuildRoutes) {
      for (const [chunk, consumers] of [
        [originsPageChunk, [originsRoute, journalRoute]],
        [mealChunk, mealCommandConsumers],
        [commonChunk, commandRoutes],
        [workoutChunk, [...workoutCommandConsumers, journalRoute].sort()],
        [scopeChunk, [...commandRoutes, nutritionWindowAppPath]],
        [replyChunk, replyRoutes],
        [editWriterChunk, editRoutes],
        [intakeChunk, intakeRoutes],
      ] as const)
        expect(
          tracedTargets(route).filter((target) => target === chunk),
          route,
        ).toHaveLength(consumers.some((consumer) => consumer === route) ? 1 : 0)
    }
    const structuredMealHelper = certifyStructuredMealHelperT51()
    const nutritionJournalSplit = scopeChunk
    const expectedCommandCounts = new Map([
      ...rootRoutes.map((route) => [route, 119] as const),
      [journalRoute, 121],
      ...editRoutes.map((route) => [route, 122] as const),
      ...replyRoutes.map((route) => [route, 121] as const),
    ])
    for (const [route, count] of expectedCommandCounts)
      expect(
        tracedTargets(route).filter(
          (target) =>
            target !== scopeChunk &&
            !structuredMealHelper.isEdge(route, target) &&
            !(rootRoutes.includes(route) && target === commonChunk) &&
            !purposeEdge(route, target) &&
            !(route === journalRoute && target === originsPageChunk) &&
            !(route === journalRoute && target === workoutChunk),
        ),
        route,
      ).toHaveLength(count)
    const currentCounts = new Map([
      [linkedOriginRoute, 123],
      ...rootRoutes.map((route) => [route, 122 + 1] as const),
      [journalRoute, 125 + 1],
      ...editRoutes.map((route) => [route, 124 + 1] as const),
      ...replyRoutes.map((route) => [route, 123 + 1] as const),
      ...workoutRoutes.map((route) => [route, 117] as const),
      ...intakeRoutes.map((route) => [route, route === originsRoute ? 125 + 1 : 124 + 1] as const),
    ])
    expect([...currentCounts.keys()].sort()).toEqual(commandRoutes)
    for (const [route, count] of currentCounts)
      expect(tracedTargets(route), route).toHaveLength(count)
    const legacyTargets = new Set([...allRoutes, webhookRoute].flatMap(tracedTargets)),
      commandOnlyTargets = [...new Set(commandRoutes.flatMap(tracedTargets))]
        .filter((target) => !legacyTargets.has(target))
        .sort()
    expect(commandOnlyTargets).toEqual(
      [
        ...new Set([
          mealChunk,
          commonChunk,
          workoutChunk,
          scopeChunk,
          replyChunk,
          publicEditChunk,
          intakeChunk,
          originsPageChunk,
          structuredMealHelper.chunk,
          ...commandRoutes.map((route) =>
            realpathSync(
              resolve(buildRoot, 'server/app', `${route.slice(1)}_client-reference-manifest.js`),
            ),
          ),
        ]),
      ].sort(),
    )
    expect(legacyTargets.size).toBe(218) // one absorbed selector target vs original218
    expect(
      [...allRoutes, webhookRoute].reduce((sum, route) => sum + tracedTargets(route).length, 0) +
        absorbedReferences(allRoutes),
    ).toBe(8202 + 16 + 104)
    expect(tracedTargets(nutritionWindowAppPath)).toHaveLength(115)
    // T48 extracts the three unchanged read-page modules certified above into
    // one new regular file, reached exactly once by each of the two readers.
    // Preserve the complete pre-T48 totals and account only for those two edges.
    // T51 adds only the closed helper above:12 edges, one regular target.
    // Historical counts project that exact edge only; all raw scans include it.
    expect(surface.nftReferenceCount).toBe(
      8202 +
        104 -
        6 +
        3 * 121 +
        122 +
        3 * 123 +
        2 * 122 +
        3 * 117 +
        3 * 123 +
        115 +
        28 +
        1 +
        2 +
        12 +
        123, // R93: exactly the new read-only origin route NFT edges.
    )
    expect(surface.nftUniqueTargetCount).toBe(217 + 15 + 7 + 1 + 1 + 1 + 1 + 1)
    expect(surface.nftRegularFileTargetCount).toBe(215 + 15 + 7 + 1 + 1 + 1 + 1 + 1)
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
    expect(
      historicalRoutes.reduce((sum, route) => sum + priorTargets(route).length, 0) +
        absorbedReferences(historicalRoutes),
    ).toBe(6089)
    expect(new Set(historicalRoutes.flatMap(priorTargets)).size + 1).toBe(194)
    expect(repositoryUniqueSize(historicalRoutes.flatMap(priorTargets)) + 1).toBe(193)
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
      } else {
        // New canonical/read-only adapters may contain the same RPC name in
        // their closed allowlist. The historical clinical reader is selected
        // by its original consumer; every complete physical graph stays scanned.
        const candidates = semanticChunks(edge.markers).filter((file) =>
          chunkConsumers(file).includes(edge.old[0] ?? ''),
        )
        expect(candidates, edge.markers.join(', ')).toHaveLength(1)
        chunk = candidates[0] ?? ''
      }
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
            '/api/mobile/v1/media/route',
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
            ...mealCommandConsumers,
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
    expect(
      historicalRoutes.reduce((sum, route) => sum + historicalTargets(route).length, 0) +
        absorbedReferences(historicalRoutes),
    ).toBe(6033)
    expect(new Set(historicalRoutes.flatMap(historicalTargets)).size + 1).toBe(187)
    // Removing the qualified legacy-facts module now also removes its second
    // co-located repository copy from this historical projection. Its missing
    // duplicate offsets the absorbed selector node in the old logical count;
    // both actual copies remain checked globally before any projection.
    expect(
      new Set(historicalRoutes.flatMap(historicalTargets)).has(repositoryCopies[0] ?? '') !==
        new Set(historicalRoutes.flatMap(historicalTargets)).has(repositoryCopies[1] ?? ''),
    ).toBe(true)
    expect(repositoryUniqueSize(historicalRoutes.flatMap(historicalTargets))).toBe(186)
    expect(
      createHash('sha256')
        .update(
          historicalRoutes
            .slice()
            .sort()
            .map(
              (route) =>
                `${route}\0${historicalTargets(route).length + (absorbedSelectorRoutes.has(route) ? 1 : 0)}\n`,
            )
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
    const receiptCopies = exactStringChunks('read_mobile_registration_feedback')
    expect(receiptCopies).toHaveLength(2)
    expect(receiptCopies).toContain(nutritionJournalSplit)
    const legacyReceiptCopies = receiptCopies.filter((chunk) => chunk !== nutritionJournalSplit)
    expect(legacyReceiptCopies).toHaveLength(1)
    const receiptChunk = legacyReceiptCopies[0] ?? ''
    // Both History endpoints now inline exactly the same qualified reader.
    // Include that actual module, rather than inventing a missing NFT edge.
    for (const file of [
      nutritionJournalSplit,
      receiptChunk,
      ...historyFeedbackRoutes.map((route) => {
        const target = currentAppPathsManifest()[route]
        if (!target) throw new Error('Missing protected History entry')
        return resolve(buildRoot, 'server', target)
      }),
    ])
      certifyPhysicalModule(file, '63980', [
        'f72ee9fa08b0b391b72a08dd315418ae96759089e54bc5ed728d37806082807e',
        '578c992110323cefc0434b5aa193a8fbb16132af1125dca06743123b04535cd1',
      ])
    expect([...chunkConsumers(receiptChunk), clarificationRoute].sort()).toEqual(
      [...reviewRoutes, clarificationRoute].sort(),
    )
    expect(runtimeExactStringRoutes('read_mobile_registration_feedback')).toEqual(
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
        if (route === clarificationRoute) {
          // Qualified module32072 is inline here. Its prior NFT edge is
          // absent, with its exact complete body already checked above.
          expect(ownedRepository, route).toHaveLength(0)
          extras.push(readModelChunk)
        } else {
          expect(ownedRepository, route).toHaveLength(1)
          extras.push(ownedRepository[0] ?? '', readModelChunk)
        }
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
    expect([...extrasByRoute.values()].reduce((sum, extras) => sum + extras.size, 0) + 1).toBe(57)
    const physicalTargets = (route: string): string[] =>
      historicalTargets(route).filter((target) => !extrasByRoute.get(route)?.has(target))
    const normalized = historicalRoutes
      .sort()
      .map((route) => [route, physicalTargets(route)] as const)
    expect(
      normalized.reduce((sum, [, targets]) => sum + targets.length, 0) +
        absorbedReferences(historicalRoutes) -
        1,
    ).toBe(5976)
    expect(new Set(normalized.flatMap(([, targets]) => targets)).size + 1).toBe(185)
    // Frozen count stream from the complete pre-C13 56-route build, not a
    // number calculated from current observed-minus-expected differences.
    expect(
      createHash('sha256')
        .update(
          normalized
            .map(
              ([route, targets]) =>
                `${route}\0${targets.length + (absorbedSelectorRoutes.has(route) && route !== clarificationRoute ? 1 : 0)}\n`,
            )
            .join(''),
        )
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
    const absorbedBaseline = absorbedReferences(
      historicalRoutes.filter((route) => !Object.hasOwn(addedRoutes, route)),
    )
    expect(baselineReferences + absorbedBaseline).toBe(5326)
    expect(baselineTargets.size + 1).toBe(176)
    // Removing only the separately authorized six references reproduces E2's
    // original50 graph. All other historical graph assertions stay intact.
    expect(baselineReferences + absorbedBaseline - draftRoutes.length).toBe(5320)
    expect([...baselineTargets].filter((target) => target !== draftChunk).length + 1).toBe(175)

    const beyondBaseline = (route: string): string[] =>
      [...new Set(physicalTargets(route))].filter((target) => !baselineTargets.has(target))
    for (const [addedRoute, references] of Object.entries(addedRoutes)) {
      expect(
        physicalTargets(addedRoute).length +
          (absorbedSelectorRoutes.has(addedRoute) && addedRoute !== clarificationRoute ? 1 : 0),
        addedRoute,
      ).toBe(references)
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
    expect(
      [
        ...new Set(chunks.flatMap(chunkConsumers)),
        '/api/mobile/v1/workouts/[id]/strength-clarification/route',
      ].sort(),
    ).toEqual(repositoryRoutes)
    for (const route of Object.keys(currentAppPathsManifest())) {
      expect(
        tracedTargets(route).filter((path) => chunks.includes(path)),
        route,
      ).toHaveLength(
        repositoryRoutes.includes(route) &&
          route !== '/api/mobile/v1/workouts/[id]/strength-clarification/route'
          ? 1
          : 0,
      )
    }
    const switchChunks = semanticChunks(['MOBILE_WORKOUT_REGISTRATION_PROJECT_REF'])
    const writerChunks = exactStringChunks('commit_mobile_registration_feedback')
    expect(switchChunks).toHaveLength(2)
    expect(writerChunks).toHaveLength(1)
    const reviewSwitch = switchChunks.filter((chunk) =>
      chunkConsumers(chunk).includes(reviewRoutes[0] ?? ''),
    )
    expect(reviewSwitch).toHaveLength(1)
    expect(readFileSync(reviewSwitch[0] ?? '', 'utf8')).toContain('ui-v1')
    // The selector/repository now also serves the protected read question,
    // while the feedback writer remains an independent five-review chunk.
    expect(writerChunks).not.toEqual(switchChunks)
    certifyAbsorbedWorkoutSelector()
    expect(
      switchChunks.map(chunkConsumers).sort((a, b) => a.join().localeCompare(b.join())),
    ).toEqual(
      [[...conversationIntakeAppPaths].sort(), reviewRoutes].sort((a, b) =>
        a.join().localeCompare(b.join()),
      ),
    )
    // The same private capability modules are now inline in all3 workout
    // entries, rather than a shared intake/workout chunk. Certify full copies.
    for (const route of conversationWorkoutAppPaths) {
      const entry = resolve(buildRoot, 'server', currentAppPathsManifest()[route] ?? '')
      certifyPhysicalModule(entry, '34168', [
        '5c180f5861365e95d2485fc2d0348dd3b1405695cbb1441dad80341cf593a67b',
      ])
      certifyPhysicalModule(entry, '47804', [
        '5d69e37d38dfebebad9a617cc333686fdeee9e6797e6640d8c595b97f1b7d209',
      ])
    }
    expect(chunkConsumers(writerChunks[0] ?? '')).toEqual(reviewRoutes)
    // Include entries as well as NFTs. The clarification entry already used
    // this flag before C13; its protected question is not a feedback writer.
    expect(runtimeMarkerRoutes('MOBILE_WORKOUT_REGISTRATION_PROJECT_REF')).toEqual(
      [
        ...reviewRoutes,
        '/api/mobile/v1/workouts/[id]/strength-clarification/route',
        ...conversationWorkoutAppPaths,
        ...conversationIntakeAppPaths,
      ].sort(),
    )
    expect(runtimeExactStringRoutes('commit_mobile_registration_feedback')).toEqual(reviewRoutes)
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
