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
import {
  completionBuildPaths,
  completionTransports,
} from '../scripts/training-completion-surface.mjs'
import { inspectBuildSurface } from '../scripts/verify-build-surface.mjs'
import { journeySocialTransports, journeySocialBuildPaths } from '../scripts/journey-social-surface.mjs'
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

function tracedTargets(route: string, includeExecution = false): string[] {
  const manifest = includeExecution
    ? JSON.parse(readFileSync(appPathsManifestPath, 'utf8'))
    : currentAppPathsManifest()
  const target = manifest[route]
  expect(target, route).toBeTypeOf('string')
  const tracePath = resolve(buildRoot, 'server', `${target}.nft.json`)
  const trace: { files: string[] } = JSON.parse(readFileSync(tracePath, 'utf8'))
  return trace.files.map((reference) => realpathSync(resolve(dirname(tracePath), reference)))
}

function semanticChunks(markers: string[]): string[] {
  const chunksRoot = realpathSync(resolve(buildRoot, 'server/chunks'))
  return (
    walkFiles(resolve(buildRoot, 'server/chunks'))
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
      // These historical certificates cover the frozen93 graph. The additive
      // completion-only chunk is independently scanned by the full101 gate.
      .filter((physical) =>
        Object.entries(
          JSON.parse(readFileSync(appPathsManifestPath, 'utf8')) as Record<string, string>,
        ).some(
          ([route]) =>
            !completionBuildPaths.has(route.replace(/\/route$/, '')) &&
            !journeySocialBuildPaths.has(route.replace(/\/route$/, '')) &&
            route.endsWith('/route') &&
            tracedTargets(route, true).includes(physical),
        ),
      )
  )
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

/** R102 intentionally extends the closed ordinary-purpose observation seam.
 * Pin every changed runtime source; no legacy provider/worker/writer capability
 * or physical graph edge is exempted by the complete body certificates. */
/** R168 admits only the explicit private-version field and its pairing check.
 * Pin the whole new source before reversing those exact additions. */
function legacyPrivateMediaSourceR168(name: string, text: string): string {
  const pins: Record<string, { hash: string; additions: readonly (readonly [string, number])[] }> =
    {
      'conversation-intake-contracts.ts': {
        hash: '109337a08ea493451154ff2ab1664cbe88b8bcaf067b6a23fad0c06974a79c37',
        additions: [['    catalog_version: z.literal(2).optional(),\n', 1]],
      },
      'conversation-intake-media-origin.ts': {
        hash: '1144988dc4826d4f8fcef7da6efd11ac3f653466c8cfde85ee3f0a6ba138efc9',
        additions: [
          ['        catalog_version: z.literal(2).optional(),\n', 2],
          ['    projection.media.catalog_version !== media.catalog_version ||\n', 1],
        ],
      },
      'conversation-meal-interpretation-contracts.ts': {
        hash: 'c7395069566844e764eed2bc5b212e490e9e831710d9a20a1184e1cd28b57013',
        additions: [
          ['        catalog_version: z.literal(2).optional(),\n', 1],
          ['    catalog_version: z.literal(2).optional(),\n', 1],
          ['        ...(m.catalog_version === 2 ? { catalog_version: 2 as const } : {}),\n', 1],
        ],
      },
      'conversation-meal-writer-contracts.ts': {
        hash: 'd20b68f55ed3a0e6b623c9f12f5add1fee7c9ddbc4f8c6a2abe9018709b937fb',
        additions: [['    catalog_version: z.literal(2).optional(),\n', 1]],
      },
      'conversation-workout-contracts.ts': {
        hash: 'eb2806dc5fa361f63c36e939ae2ebde8500ce23279bbb93aeb575efbc32cef8a',
        additions: [['    catalog_version: z.literal(2).optional(),\n', 1]],
      },
    }
  const pin = pins[name]
  if (!pin) return text
  expect(createHash('sha256').update(text).digest('hex')).toBe(pin.hash)
  let restored = text
  for (const [addition, count] of pin.additions) {
    expect(restored.split(addition)).toHaveLength(count + 1)
    restored = restored.split(addition).join('')
  }
  return restored
}

/** Whole fresh compiled bodies were compared. The declared literal additions
 * reverse to all four historical body hashes; no module/export is excluded. */
function restorePrivateMediaContractR168(id: string, body: string): string {
  const pins: Record<
    string,
    { hash: string; previous: string; additions: readonly (readonly [string, number])[] }
  > = {
    '50522': {
      hash: '0039979f25f5e30108abbe1d31a3d4a07b3ffabd719dc826bedc78469faf349f',
      previous: 'a5d450bd9b7267e8756ae2f7b5a6910ead5d90ff83fe073d39b7f6ad278b3633',
      additions: [['catalog_version:f.eu(2).optional(),', 1]],
    },
    '13300': {
      hash: '23c99d32164b96a9017a02630f0856e118cc2237c314440a876c2e01ad5fc4c8',
      previous: '6447848bbd6a737c168e7027e61dc5c57a12e9881a8104ffbc9829810b07122c',
      additions: [
        ['catalog_version:f.eu(2).optional(),', 2],
        ['...2===a.catalog_version?{catalog_version:2}:{},', 1],
      ],
    },
    '36693': {
      hash: 'ca39947b0c6c40c0cc6f8341db3c453bd02d3e833c635dfe97dd83f957eb837f',
      previous: 'a67fde03374f03e52ce2cc12031cb0be06174e20443bb57226f2ef986828389c',
      additions: [['catalog_version:e.eu(2).optional(),', 1]],
    },
    '61104': {
      hash: '2b991e02d5f7c042c60dfd16fac08ae6a3eb0bd4417714ec4c8f3f7413c748c0',
      previous: 'a5837ab85a3c9a5854d506aa241669b72c961101c6b69234a59e42576cfb4037',
      additions: [
        ['catalog_version:f.eu(2).optional(),', 2],
        ['||i.media.catalog_version!==k.catalog_version', 1],
      ],
    },
  }
  const pin = pins[id]
  if (!pin) return body
  expect(
    createHash('sha256').update(body).digest('hex'),
    'exact private media compiled delta',
  ).toBe(pin.hash)
  let restored = body
  for (const [addition, count] of pin.additions) {
    expect(restored.split(addition)).toHaveLength(count + 1)
    restored = restored.split(addition).join('')
  }
  expect(createHash('sha256').update(restored).digest('hex')).toBe(pin.previous)
  return restored
}

function certifyOrdinaryPhotoSourcesR102(): void {
  // R165 adds only the exact app-only whey protein alias. All377 actual module
  // identities were compared:375 whole bodies remain byte-identical; the two
  // changed bodies (agent export/consumer) are sealed in full, with no edge or
  // executable-byte exemption. Legacy lookup source remains unchanged in logic.
  for (const [name, hash] of [
    [
      'everyday-food-defaults.ts',
      '6ab28a7063eba8ccd3d5a50e1c23165a62da29517883b68edd1fe3d82abb44fb',
    ],
    ['meal-pipeline.ts', '73c3df3f60f415a2bd718604f694304746b10bb33094ac76cd08b67f32f723a9'],
  ])
    expect(
      createHash('sha256')
        .update(readFileSync(resolve(appRoot, '../../packages/agent/src', name ?? '')))
        .digest('hex'),
    ).toBe(hash)
  for (const [id, hash] of [
    ['26432', 'a480fe25475fdd2728097553d30170e46e0595cd101f7cb6ca15eaa88c951da2'],
    ['69702', '9ecc51ff37b728c9b9c5a0fad60663f69af28cf5f0895464ec4ab3606b9cb7da'],
  ]) {
    const copies = walkFiles(resolve(buildRoot, 'server/chunks')).filter(
      (file) =>
        file.endsWith('.js') && new RegExp(`(?:^|[,;{])${id}:`).test(readFileSync(file, 'utf8')),
    )
    expect(copies).toHaveLength(1)
    for (const file of copies) certifyPhysicalModule(file, id ?? '', [hash ?? ''])
  }
  for (const [name, hash] of [
    [
      'conversation-intake-contracts.ts',
      'c37a0d57c17f236aa247925a9f2edbbd5a322789c5149ae19262da61692927c6',
    ],
    [
      'conversation-intake-media-origin.ts',
      '5ee3e02da419d2763d965b8f951c7a09bbd7bd865fdf84a8260f0ea5e49795da',
    ],
    [
      'conversation-intake-router.ts',
      'd4a62d927c1f3fc8006f4c0701fff0163fb812a422a5833f64ccafb527a5faae',
    ],
    [
      'conversation-meal-interpretation-contracts.ts',
      'da551a890a824c75df16d6563920c811b86bf4acc83adfcd142b8cefd0ed588c',
    ],
    [
      'conversation-meal-materialization.ts',
      '6f23187323798d4752f84c47e8cb464f6ee95d8b3eddb982bed069717ca3e4e3',
    ],
    [
      'conversation-meal-source.ts',
      '1fe53d5e5f25a6896c92d3d8c5c1c7efdca8225b1b9ede3c697c856d48f5763e',
    ],
    [
      'conversation-meal-writer-contracts.ts',
      '6085f9076990de801ec388e36d60563e9a014929642b2bb1ebfd837899400487',
    ],
    [
      'conversation-workout-contracts.ts',
      '990941bc8761a32e9ab3b0e717adcd63de7dee8eaa067e74916da4d0374c9df4',
    ],
    [
      'conversation-photo-observations.ts',
      '669909481ebd34f04c2bf423c33029319aa0486b120647cc67f8aed56ce7780f',
    ],
  ])
    expect(
      createHash('sha256')
        .update(
          legacyPrivateMediaSourceR168(
            name ?? '',
            readFileSync(resolve(appRoot, '../admin/src/lib/mobile-api', name ?? ''), 'utf8'),
          ),
        )
        .digest('hex'),
    ).toBe(hash)
}

// Exact T36 extraction: all16 previously certified module bodies are byte-identical.
// Default existing-account Auth additionally co-locates the unchanged reply-scope
// aliases and readonly runtime (previously in reply/edit chunks). No source body
// or physical route/NFT consumer was discarded by this packaging translation.
// R102 adds one pure ordinary-photo observation helper to this exact table.
// Three existing source/interpretation bodies intentionally change; the other16
// stay byte-identical, and all complete identities/negative controls remain.
// These bodies include dormant writer adapters; this certificate never declares
// them absent and never exempts any physical code from the global scans.
// T40 exposes three existing pure Auth decoders for the request-owned refusal
// latch. Only module11098 changes; the other17 bodies and exact consumers stay
// pinned. Source qualification proves the three extractions are otherwise exact.
// T43's actual intake runtime retains those three exports. The same source SHA
// is sealed below; module11098 is newly certified in full, with the other17
// compiled bodies still byte-identical. No old raw module body is claimed here.
/** R106 changes no intake/nutrition/provider source here. The image-result
 * parser moved from86248 to63867 when Storage issuance was factored. Reverse
 * exactly one loader link, asserting both complete raw and restored bodies. */
function restoreImageParserLinkR106(id: '6535' | '67584', body: string): string {
  const pins =
    id === '6535'
      ? [
          'n=c(63867)',
          'n=c(86248)',
          '5dd4d1f49929e7180eecb655ba7279484d185a2e85a4a6d3059df70635462933',
          'e5a83319c16c8c143001215de4824db60fd1e9b27472edc1593070057d3641d1',
        ]
      : [
          'd=c(63867)',
          'd=c(86248)',
          '6a25ab4c20db09c31ca9d83123c2257bbdaf65293f54863daab1250b130c6c45',
          'ff042cee49ac972821a92bd39b840a0e19208a3580392eb75625de480f75ee1e',
        ]
  const [from, to, current, previous] = pins
  // Both actual builds were compared: Webpack's cached module allocation may
  // retain the previous ID or relocate it. Only these two whole-body hashes
  // qualify; every other executable-byte difference still fails.
  if (createHash('sha256').update(body).digest('hex') === previous) return body
  if (!from || !to) throw new Error('Missing exact parser link')
  expect(
    createHash('sha256').update(body).digest('hex'),
    'certified nutrition-shared module contents / exact parser loader body',
  ).toBe(current)
  expect(body.split(from)).toHaveLength(2)
  const restored = body.replace(from, to)
  expect(createHash('sha256').update(restored).digest('hex')).toBe(previous)
  return restored
}

/** R186 accounts only for a terminal current-time adjunct on an already
 * reported complete photo pointer. Reverse that sole source/build delta before
 * every older complete-body pin; unknown or additional changes still fail. */
function restoreCurrentPhotoAdjunctR186(text: string, kind: 'source' | 'build'): string {
  expect(
    createHash('sha256').update(text).digest('hex'),
    'certified nutrition-shared module contents / current photo adjunct',
  ).toBe(
    kind === 'source'
      ? 'db5efe55cca713eaf204c29d6270c4f9fccd4ea6d044fb322f2b50e2cf7c3892'
      : '28958721de3d1f152c2a213787e046b5d4f205c66bdfa519d604f12029fe6530',
  )
  const current =
    kind === 'source'
      ? "  // A current-time adjunct belongs to the same complete, already reported\n  // photo pointer. Only these exact terminal words are inert: questions,\n  // quantities, other dates and additional clauses remain fully accounted for.\n  const tailText = plain(text.slice(report.end)).replace(/ (?:agora|hoje)([.!]?)$/u, '$1')\n"
      : '.replace(/ (?:agora|hoje)([.!]?)$/u,"$1")'
  const prior = kind === 'source' ? '  const tailText = plain(text.slice(report.end))\n' : ''
  expect(text.split(current)).toHaveLength(2)
  const restored = text.replace(current, prior)
  expect(createHash('sha256').update(restored).digest('hex')).toBe(
    kind === 'source'
      ? '6cdfdcf826ad75e03b2ee7e73f1f46a3060c24373c45c21030bfac0d0ed5308a'
      : 'a5af333ad6fb31be8e67604e1c8db7d05b7403359d573e3b3a49080aae17b9b4',
  )
  return restored
}

/** R163 additionally accounts for a positive bound-photo report whose caption
 * is labeled media_pointer and retains its genuine consumption predicate.
 * The entire actual module table was compared: only65556 changes; the other19
 * complete certified bodies and moved parser still match. Pin the whole new
 * source/body; retain every consumer scan and executable-tampering refusal. */
function certifyPhotoReportR163(body: string): string {
  body = restoreCurrentPhotoAdjunctR186(body, 'build')
  expect(
    createHash('sha256').update(body).digest('hex'),
    'certified nutrition-shared module contents / complete photo report validator',
  ).toBe('a5af333ad6fb31be8e67604e1c8db7d05b7403359d573e3b3a49080aae17b9b4')
  return body
}

function certifyNutritionJournalSplitContent(text: string): void {
  certifyOrdinaryPhotoSourcesR102()
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
  // R121 adds a bounded completed-report + trailing photo pointer. This module
  // now has a complete new source/body pin; no prior guards are projected away.
  expect(
    createHash('sha256')
      .update(
        restoreCurrentPhotoAdjunctR186(
          readFileSync(
            resolve(
              appRoot,
              '../admin/src/lib/mobile-api/conversation-meal-interpretation-validation.ts',
            ),
            'utf8',
          ),
          'source',
        ),
      )
      .digest('hex'),
  ).toBe('6cdfdcf826ad75e03b2ee7e73f1f46a3060c24373c45c21030bfac0d0ed5308a')
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
  const physicalBodies =
    modules[0]?.properties.map((property) => {
      if (!ts.isPropertyAssignment(property) || !ts.isArrowFunction(property.initializer))
        throw new Error('Unexpected nutrition-shared module shape')
      return { id: property.name.getText(source), body: property.initializer.getText(source) }
    }) ?? []
  // R136's three execution routes also consume existing readonly Auth. Webpack
  // may move the unchanged vision parser from the photo table into this shared
  // table. Certify that ENTIRE moved body before projecting the frozen20;
  // unknown additions, changed bytes and missing old modules still fail.
  const movedParser = physicalBodies.find(({ id }) => id === '86248' || id === '63867')
  if (movedParser) {
    expect(physicalBodies, 'certified nutrition-shared module count / moved parser').toHaveLength(
      21,
    )
    expect(createHash('sha256').update(movedParser.body).digest('hex')).toBe(
      'bca65f93158ff60efe08f14a45537b8db4e719a9deb863c2b452b37a11862673',
    )
  }
  const bodies = physicalBodies.filter((value) => value !== movedParser)
  expect(bodies, 'certified nutrition-shared module count').toHaveLength(20)
  expect(
    bodies
      .map(
        ({ id, body }) =>
          `${id}:${createHash('sha256')
            .update(
              id === '67584'
                ? restoreImageParserLinkR106('67584', body)
                : id === '65556'
                  ? certifyPhotoReportR163(body)
                  : restorePrivateMediaContractR168(id, body),
            )
            .digest('hex')}`,
      )
      .sort(),
    'certified nutrition-shared module contents',
  ).toEqual(
    [
      '11098:d8cccef169992ad42803f27d81d5b753a50e5798e8f649ad3acd7aea98fa6925',
      '40747:411b3586832f4b981362200d53a3836cff6395e29cee48554464d97d48fa94a9',
      '93639:ce2fe7a229147bad36167351267198cbd255aa881701566612da47ce193e2e04',
      '49634:fc711f099281a69d5ecf62a254ec8ffcfe202d33a181bcefae7d82d7e7e7dfe6',
      '85685:41deccfd9e90c2b6a6de3cf6e0493c94e9776c8a1bbc1f5fe4ee3bfe76475b1a',
      '13300:6447848bbd6a737c168e7027e61dc5c57a12e9881a8104ffbc9829810b07122c',
      '19514:a189839890f820d1a04f8f29b5dd89af51577d935e8af5e7a344cc8a5a9344fd',
      '20853:5e5378aa0bd0fb541859f4fa6a9dc8c853525dcb697ac43864a72c61837772e9',
      '21378:3666116fbbe020c4e11038c8dca63660d541b8bd16140556f52cf892fcebb2f5',
      '36693:a67fde03374f03e52ce2cc12031cb0be06174e20443bb57226f2ef986828389c',
      '52158:129ea4b769605c4e7ddee1f1bc26688f2d09e77a0922726299741a808f4ae420',
      '61104:a5837ab85a3c9a5854d506aa241669b72c961101c6b69234a59e42576cfb4037',
      '63980:f72ee9fa08b0b391b72a08dd315418ae96759089e54bc5ed728d37806082807e',
      '65556:a5af333ad6fb31be8e67604e1c8db7d05b7403359d573e3b3a49080aae17b9b4',
      '69423:37ddc2d0a8b30f80f4fa3636ccf2f406ebf262172e88117949b472d070fbc7a3',
      '69431:22fe4905a8681297dba0a50a7a0a75352d687ff4ea3da18f93310480e3276753',
      '67584:ff042cee49ac972821a92bd39b840a0e19208a3580392eb75625de480f75ee1e',
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
/** R128 changes only the router provider wire/schema and required-null
 * translation. All three neighboring intake modules, canonical contracts,
 * source/epoch fences, exact consumers and forbidden scans remain unchanged.
 * Certify the entire new executable body; do not normalize away the change. */
/** R140 only relinks the unchanged workout facade after webpack extracts
 * the now-shared current-scope module. Full new executable bodies and original
 * source bytes are checked before restoring that ONE import for the old pins. */
/** Exact-commit rebuild selected the existing second allocation of the same
 * image parser. Full raw bodies prove that only one loader changes in each;
 * the entire parser module and its physical consumers stay certified. */
function restoreConversationParserLinkR173(body: string): string {
  const pins: Record<string, string> = {
    fe642a40ae21d4e12f92e31a16bf51b6a46fbc1bed6beb30067abea2cb151f62:
      'd8d52b26943275b18cb25243a733b9b6b6689c7ba0ea77ccddca788d2f8885c4',
    fe8eda698679f08fbd8d6ccc0abc03c8f2d8da9b594a566d291f1819294647b6:
      'ca5389d90fb7906310441d177e724fbc5547520ca2283da641e7e9c947cf8fea',
    be5fa17528984de08eae8d24774f443ae08de1e292e13bcdc6cb3663063142a4:
      '7b598d18a05f0abdf8cc2670d5e4219754b6c0df263bc884ff723bdf04e9f89c',
  }
  const previous = pins[createHash('sha256').update(body).digest('hex')]
  if (!previous) return body
  expect(body.split('c(86248)')).toHaveLength(2)
  const restored = body.replace('c(86248)', 'c(63867)')
  expect(createHash('sha256').update(restored).digest('hex')).toBe(previous)
  return restored
}
/** R173 factors the unchanged media factory behind one new loader. Each of
 * these four WHOLE raw consumers differs only by that one link. No executable
 * delta is removed from the new processing route or shared owned helper. */
function restoreMediaFactoryLinkR173(body: string): string {
  const linked = createHash('sha256').update(body).digest('hex')
  if (
    linked === 'f6eba0b2cc582c7f3afe3badd780b72178cd5e9475f975483c8e6d4a08ce080a' ||
    linked === 'd61677cc7ff6be2275ddd822631f4ec6ff98f0356fec7857a11335ede96b00f2'
  ) {
    // R174 extracts the unchanged namespace from the sealed pure catalog.
    // These two COMPLETE consumers differ only by the catalog module loader.
    expect(body.split('c(33413)')).toHaveLength(2)
    body = body.replace('c(33413)', 'c(8184)')
    expect(createHash('sha256').update(body).digest('hex')).toBe(
      linked === 'd61677cc7ff6be2275ddd822631f4ec6ff98f0356fec7857a11335ede96b00f2'
        ? '022a8bd63f33d23df8b9f02947b3b05b8c3275dacd24f793e4228196456378f1'
        : 'fe8eda698679f08fbd8d6ccc0abc03c8f2d8da9b594a566d291f1819294647b6',
    )
  }
  body = restoreConversationParserLinkR173(body)
  const pins: Record<string, string> = {
    ca5389d90fb7906310441d177e724fbc5547520ca2283da641e7e9c947cf8fea:
      'f456e38b9523c617019f033f6a770eb2288fa43217b5a7238680b521bb595702',
    b4eba16d2b1b66e6ad96cf99b426fef6b7e12e3a5852f463d3cdeb77641d5fab:
      'cbdd3c53fddf88403fda23bd63c48c38b13d69a83955edf471a1a9130e23c9f0',
    '7c54e57dbc315c9e1e31192e79633fea869f505a31eb8b326e55f1942457c3ca':
      '14150a04c5bc2a47b5ef13db44bb5b2d70381a7880681ae3f6dae09facdf6c94',
    f996a5ba7ec71870baa069e5b896bc8d78d51aca41c5de5bf65100e0bde33fa3:
      '3f32995297bba5cb0b17ede719a874dedafe9d6fd5a2fe1805be665d8997fcf6',
  }
  const previous = pins[createHash('sha256').update(body).digest('hex')]
  if (!previous) return body
  expect(body.split('c(22693)')).toHaveLength(2)
  const restored = body.replace('c(22693)', 'c(97281)')
  expect(createHash('sha256').update(restored).digest('hex')).toBe(previous)
  return restored
}
function restoreWorkoutFacadeLinkR140(body: string): string {
  body = restoreMediaFactoryLinkR173(body)
  if (!body.includes('c(93498)')) return body
  for (const [name, hash] of [
    [
      'conversation-current-scope.ts',
      'f8106d2f19e5085c099719c736a396ed428f10349bc25ed9b7b04959e6697aed',
    ],
    [
      'conversation-workout-command-service.ts',
      'dee0b58351a9423feabae7d1516de9735b2427c7369913fd30dbec203855613a',
    ],
  ])
    expect(
      createHash('sha256')
        .update(readFileSync(resolve(appRoot, '../admin/src/lib/mobile-api', name)))
        .digest('hex'),
    ).toBe(hash)
  for (const [id, hash] of [
    ['93498', '21239d114e06d780ee4e5221fd60a783b3540a02209e36c0b687c64ea0bda359'],
    ['72820', '97188fca6a52a4948cc0bf3f1a12004529a82d634d6547441780dfdc73a2dc7e'],
  ]) {
    const copies = walkFiles(resolve(buildRoot, 'server/chunks')).filter(
      (file) =>
        file.endsWith('.js') && new RegExp(`(?:^|[,;{])${id}:`).test(readFileSync(file, 'utf8')),
    )
    expect(copies.length).toBeGreaterThan(0)
    for (const file of copies) certifyPhysicalModule(file, id, [hash])
  }
  expect(body.split('c(93498)')).toHaveLength(2)
  return body.replace('c(93498)', 'c(73772)')
}
function certifyStructuredIntakeRouterR128(body: string): string {
  body = restoreWorkoutFacadeLinkR140(body)
  // R141's organized additive imports change only Webpack's allocation of
  // the already-certified byte-identical image parser. Certify the complete
  // raw router AND every complete moved parser body before restoring exactly
  // one loader edge; never bless an arbitrary changed body or skip a scan.
  if (body.includes('n=c(63867)')) {
    expect(createHash('sha256').update(body).digest('hex')).toBe(
      '4d88e8a1503d7960ffc7ce0cdda285739c07b0a9540ff77b524f44661518abf0',
    )
    const copies = walkFiles(resolve(buildRoot, 'server/chunks')).filter(
      (file) => file.endsWith('.js') && /(?:^|[,;{])63867:/.test(readFileSync(file, 'utf8')),
    )
    expect(copies.length).toBeGreaterThan(0)
    for (const file of copies)
      certifyPhysicalModule(file, '63867', [
        'bca65f93158ff60efe08f14a45537b8db4e719a9deb863c2b452b37a11862673',
        // The fourth physical copy owns its strict directive; the other three
        // inherit it from their chunk. Both COMPLETE raw bodies are pinned.
        '4a9a1600a8698bc89125fc32271a3b823506085f83b490db4ddb534089fc8916',
      ])
    expect(body.split('n=c(63867)')).toHaveLength(2)
    body = body.replace('n=c(63867)', 'n=c(86248)')
  }
  expect(createHash('sha256').update(body).digest('hex')).toBe(
    '2eef75ca30d2cfabb2e71e2e652c8b41d0b884572469eed6424484a5b45969f3',
  )
  return body
}
function certifyExactSharedTable(
  file: string,
  pins: readonly (readonly [string, string])[],
  restore?: (id: string, body: string) => string,
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
      const certifiedBody = restore ? restore(id, body) : body
      return [
        id,
        createHash('sha256')
          .update(
            id === '6535'
              ? certifyStructuredIntakeRouterR128(certifiedBody)
              : restoreWorkoutFacadeLinkR140(certifiedBody),
          )
          .digest('hex'),
      ].join(':')
    }) ?? []
  expect(observed.sort()).toEqual(pins.map(([id, hash]) => `${id}:${hash}`).sort())
  return bodies
}
/** R172 adds only atomic versioned admission and its sticky request policy.
 * Seal the full new body and every source; reconstruct the exact original
 * runtime/routes/store below. Historical R128/R168 certificates stay intact. */
function originalIntakeSourceR172(name: string): string {
  let text = readFileSync(resolve(appRoot, '../admin/src/lib/mobile-api', name), 'utf8')
  const pins: Record<string, string> = {
    'conversation-intake-routes.ts':
      '749ead1f22675a3b1ec88e20e74284461683ec2a2b08d5f1ca4fc7bfb4664804',
    'conversation-intake-store.ts':
      '5c7badf31dc9b71a2fe362cbd258f2458f8b6453d353bf606663f5dc1a35086f',
    'conversation-intake-runtime.ts':
      '0f2b74c31332e637c711e42feb2ec77f0db907f3681810c10b3f441716a13a36',
    'versioned-conversation-intake-port.ts':
      '53cec7b8ce91a41968a0f39425fee966c0885ab0d123a9a40402d903bb83a60e',
  }
  const deltas: Record<string, readonly (readonly [string, string])[]> = {
    'conversation-intake-routes.ts': [
      [
        "          privateMediaCatalogEnabled: () =>\n            process.env.MOBILE_CONVERSATION_PRIVATE_CATALOG_ENABLED === 'true',\n",
        '',
      ],
    ],
    'conversation-intake-store.ts': [
      [
        "refusal(['stale_epoch', 'input_conflict', 'rate_limited', 'media_unavailable'])",
        "refusal(['stale_epoch', 'input_conflict', 'rate_limited'])",
      ],
    ],
    'conversation-intake-runtime.ts': [
      [
        "import { createVersionedConversationIntakePort } from './versioned-conversation-intake-port'\n",
        '',
      ],
      [
        '  /** Atomic catalog dispatcher capability, selected by server policy only. */\n  readonly privateMediaCatalogEnabled?: () => boolean\n',
        '',
      ],
      [
        '    trustedMediaEnabled = ports.mediaEnabled?.bind(ports) ?? (() => false),\n    trustedPrivateCatalogEnabled = ports.privateMediaCatalogEnabled?.bind(ports) ?? (() => false),\n    privateCatalogBound = trustedPrivateCatalogEnabled() === true',
        '    trustedMediaEnabled = ports.mediaEnabled?.bind(ports) ?? (() => false)',
      ],
      [
        '      if (mediaAuthorityRequired && privateCatalogBound && trustedPrivateCatalogEnabled() !== true)\n        throw unavailable()\n',
        '',
      ],
      [
        '    store = createConversationIntakeStore(\n      createVersionedConversationIntakePort(\n        { rpc },\n        {\n          enabled: trustedPrivateCatalogEnabled,\n          beforeAdmission: () => {\n            // A private media write requires this same sticky policy on every\n            // original Auth/owner/epoch observation, including recovery.\n            mediaAuthorityRequired = true\n            available()\n          },\n        },\n      ),\n      scopePort,\n    ),\n',
        '    store = createConversationIntakeStore({ rpc }, scopePort),\n',
      ],
    ],
  }
  if (pins[name]) expect(createHash('sha256').update(text).digest('hex')).toBe(pins[name])
  for (const [old, replacement] of deltas[name] ?? []) {
    expect(text.split(old)).toHaveLength(2)
    text = text.replace(old, replacement)
  }
  return text
}
function certifyVersionedIntakeBridgeR172(body: string): void {
  body = restoreWorkoutFacadeLinkR140(body)
  expect(createHash('sha256').update(body).digest('hex')).toBe(
    '921228c6a39061e494283bd41e527304958de5a19654e998855fd9d567adfe1f',
  )
  certifyOrdinaryPhotoSourcesR102()
  for (const [name, hash] of [
    [
      'conversation-intake-runtime.ts',
      '673be3b703dd77d4ed98f5201e0a003dd55c2b829149554241a46b1cfe88958f',
    ],
    [
      'conversation-intake-routes.ts',
      '0a51079f077e44a40915e874c6da3321e0773397be1bbb37bff1a5bae86f2e7c',
    ],
    [
      'conversation-intake-store.ts',
      '41da3706c059a0c7c96696be35052364a2f28aac001d999ef9add79224436527',
    ],
    [
      'conversation-intake-driver.ts',
      '4ccd96a847ab7cff5c0b659239576f3e52d5cc96939c7e6d7610950a0d0ec4f7',
    ],
    [
      'conversation-intake-router.ts',
      'd4a62d927c1f3fc8006f4c0701fff0163fb812a422a5833f64ccafb527a5faae',
    ],
  ])
    expect(
      createHash('sha256')
        .update(originalIntakeSourceR172(name ?? ''))
        .digest('hex'),
    ).toBe(hash)
  originalIntakeSourceR172('versioned-conversation-intake-port.ts')
  for (const marker of [
    'admit_conversation_versioned_media_intake_v2',
    'X-Conversation-Media-Provenance',
    'MOBILE_CONVERSATION_MEDIA_PROTOCOL_ENABLED',
    'conversation.intake-result.v2',
    'media_temporarily_unavailable',
  ])
    expect(body).toContain(marker)
}
/** R99 adds opt-in media projection and request-owned fencing. R101 corrects
 * temporary-capability/unselected-original recovery; GET remains read-only.
 * Certify the complete reviewed sources and current executable body. The other
 * two unchanged shared modules retain their byte-exact pins; R102 also
 * recertifies the ordinary-kind workout codec in full. No global scan or
 * physical consumer assertion is exempted by this certificate. */
function certifyIntakeMediaBridgeR102(body: string): void {
  if (body.includes('admit_conversation_versioned_media_intake_v2')) {
    certifyVersionedIntakeBridgeR172(body)
    return
  }
  body = certifyStructuredIntakeRouterR128(body)
  certifyOrdinaryPhotoSourcesR102()
  for (const [name, hash] of [
    [
      'conversation-intake-driver.ts',
      '4ccd96a847ab7cff5c0b659239576f3e52d5cc96939c7e6d7610950a0d0ec4f7',
    ],
    [
      'conversation-intake-runtime.ts',
      '673be3b703dd77d4ed98f5201e0a003dd55c2b829149554241a46b1cfe88958f',
    ],
    [
      'conversation-intake-routes.ts',
      '0a51079f077e44a40915e874c6da3321e0773397be1bbb37bff1a5bae86f2e7c',
    ],
    [
      'conversation-intake-media-negotiation.ts',
      '3011cb873524dbbcea7412621c8cc89fa11be7a372b388317047dd1813dfba41',
    ],
  ])
    expect(
      createHash('sha256')
        .update(readFileSync(resolve(appRoot, '../admin/src/lib/mobile-api', name ?? '')))
        .digest('hex'),
    ).toBe(hash)
  expect(createHash('sha256').update(body).digest('hex')).toBe(
    '2eef75ca30d2cfabb2e71e2e652c8b41d0b884572469eed6424484a5b45969f3',
  )
  expect(body.startsWith('(a,b,c)=>{c.d(b,{o:()=>ao,K:()=>ar});')).toBe(true)
  for (const marker of [
    'X-Conversation-Media-Provenance',
    'MOBILE_CONVERSATION_MEDIA_PROTOCOL_ENABLED',
    'conversation.intake-result.v2',
    'conversation_intake_media_unavailable',
    'media_temporarily_unavailable',
  ])
    expect(body).toContain(marker)
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
/** R184 bounds only private label grammar; canonical source/materialization
 * and every historical source/build pin are restored byte-for-byte below. */
function restoreBoundedMealGrammarR184(text: string, kind: 'source' | 'build'): string {
  if (kind === 'source') {
    expect(createHash('sha256').update(text).digest('hex')).toBe(
      '6e71f4044afe6489a1a5b40c6e10a320c495090c5b8a5b753996025d13703f2a',
    )
    for (const [current, prior] of [
      [
        "          .filter(\n            ([key]) => !['minimum', 'maximum', 'maxItems', 'definitions', '$defs'].includes(key),\n          )\n",
        "          .filter(([key]) => !['minimum', 'maximum', 'maxItems'].includes(key))\n",
      ],
      [
        "      // Source-owned token keys still belong to the canonical schema. On the\n      // provider wire, one array item grammar replaces an object per token.\n      // This keeps grammar size independent of the source's token count.\n      const properties = projected.properties\n      if (\n        projected.type === 'object' &&\n        properties !== null &&\n        typeof properties === 'object' &&\n        !Array.isArray(properties) &&\n        isDeepStrictEqual(Object.keys(properties).sort(), ['classification', 'labels'])\n      ) {\n        const fields = properties as Record<string, unknown>,\n          labels = fields.labels\n        if (\n          labels === null ||\n          typeof labels !== 'object' ||\n          !('properties' in labels) ||\n          labels.properties === null ||\n          typeof labels.properties !== 'object' ||\n          Array.isArray(labels.properties)\n        )\n          return interpretationUnavailable()\n        const entries = Object.values(labels.properties)\n        if (entries.some((label) => !isDeepStrictEqual(label, entries[0])))\n          return interpretationUnavailable()\n        fields.labels = { type: 'array', items: entries[0] ?? { type: 'null' } }\n      }\n",
        '',
      ],
      ["  input: ReturnType<typeof prepareConversationMealSourceLabels>['input'],\n", ''],
      [
        '  for (const [unit, source] of Object.entries(value.sources)) {\n    const original = input.sources.find((item) => item.unit === unit)\n    if (\n      !original ||\n      !record(source) ||\n      !Array.isArray(source.labels) ||\n      source.labels.length !== original.tokens.length\n    )\n      return reject()\n    const labels = source.labels\n    source.labels = Object.fromEntries(original.tokens.map(([key], i) => [key, labels[i]]))\n    if (!record(source.labels)) return reject()\n',
        '  for (const source of Object.values(value.sources)) {\n    if (!record(source) || !record(source.labels)) return reject()\n',
      ],
      [
        "          systemPrompt: MEAL_INTERPRETER_PROMPT.replaceAll('null', '-1')\n            .replace(\n              'labels é um objeto com TODAS as chaves t0,t1,... fornecidas naquela unidade. Cada valor tem exatamente kind e food_index.',\n              'labels é um array na ordem EXATA das chaves t0,t1,... fornecidas naquela unidade, com exatamente um item por chave. Cada item tem exatamente kind e food_index. Não escreva as chaves no array.',\n            )\n            .replace(\n              'classification é visual e labels é objeto vazio',\n              'classification é visual e labels é array vazio',\n            ),\n",
        "          systemPrompt: MEAL_INTERPRETER_PROMPT.replaceAll('null', '-1'),\n",
      ],
      [
        '          decodeMealProviderIndices(decoded, onFailure, packet.input),\n',
        '          decodeMealProviderIndices(decoded, onFailure),\n',
      ],
    ] as const) {
      expect(text.split(current)).toHaveLength(2)
      text = text.replace(current, prior)
    }
    expect(createHash('sha256').update(text).digest('hex')).toBe(
      '91a1d79b35daf2a3ea788a1ac10ac90275f88171f16338849a49c7ec208042eb',
    )
  }
  if (kind === 'build') {
    expect(createHash('sha256').update(text).digest('hex')).toBe(
      '056663c4f528c4c4455c032f8126b170e5e62f60931671d8890a0ae837952b41',
    )
    for (const [current, prior] of [
      [
        'function(a){let b=(0,S.AS)(a,"conversation_meal_source_labels_v1"),c=(a,e=[])=>{if(Array.isArray(a))return a.map(a=>c(a,e));if(null!==a&&"object"==typeof a){if("$ref"in a){let{$ref:d,...f}=a;if("string"!=typeof d||!d.startsWith("#/")||e.includes(d))return(0,z.v8)();let g=b.json_schema.schema;for(let a of d.slice(2).split("/")){let b=a.replaceAll("~1","/").replaceAll("~0","~");if(null===g||"object"!=typeof g||!Object.hasOwn(g,b))return(0,z.v8)();g=g[b]}return null===g||"object"!=typeof g||Array.isArray(g)?(0,z.v8)():c({...g,...f},[...e,d])}let f=Object.fromEntries(Object.entries(a).filter(([a])=>!["minimum","maximum","maxItems","definitions","$defs"].includes(a)).map(([a,b])=>[a,c(b,e)])),g=f.properties;if("object"===f.type&&null!==g&&"object"==typeof g&&!Array.isArray(g)&&(0,d.isDeepStrictEqual)(Object.keys(g).sort(),["classification","labels"])){let a=g.labels;if(null===a||"object"!=typeof a||!("properties"in a)||null===a.properties||"object"!=typeof a.properties||Array.isArray(a.properties))return(0,z.v8)();let b=Object.values(a.properties);if(b.some(a=>!(0,d.isDeepStrictEqual)(a,b[0])))return(0,z.v8)();g.labels={type:"array",items:b[0]??{type:"null"}}}return(0,d.isDeepStrictEqual)(f,{anyOf:[{type:"integer"},{type:"null"}]})?{type:"integer"}:f}return a};return{...b,json_schema:{...b.json_schema,schema:c(b.json_schema.schema)}}}(k.schema)',
        'function(a){let b=(0,S.AS)(a,"conversation_meal_source_labels_v1"),c=(a,e=[])=>{if(Array.isArray(a))return a.map(a=>c(a,e));if(null!==a&&"object"==typeof a){if("$ref"in a){let{$ref:d,...f}=a;if("string"!=typeof d||!d.startsWith("#/")||e.includes(d))return(0,z.v8)();let g=b.json_schema.schema;for(let a of d.slice(2).split("/")){let b=a.replaceAll("~1","/").replaceAll("~0","~");if(null===g||"object"!=typeof g||!Object.hasOwn(g,b))return(0,z.v8)();g=g[b]}return null===g||"object"!=typeof g||Array.isArray(g)?(0,z.v8)():c({...g,...f},[...e,d])}let f=Object.fromEntries(Object.entries(a).filter(([a])=>!["minimum","maximum","maxItems"].includes(a)).map(([a,b])=>[a,c(b,e)]));return(0,d.isDeepStrictEqual)(f,{anyOf:[{type:"integer"},{type:"null"}]})?{type:"integer"}:f}return a};return{...b,json_schema:{...b.json_schema,schema:c(b.json_schema.schema)}}}(k.schema)',
      ],
      [
        'function(a,b,c){let d=a=>null!==a&&"object"==typeof a&&!Array.isArray(a),e=()=>(b("model_schema"),(0,z.v8)()),f=structuredClone(a);if(!d(f)||!d(f.sources)||!Array.isArray(f.foods))return e();function g(a,b){if(!d(a))return e();let c=a[b];if("number"!=typeof c||!Number.isInteger(c)||c<-1||c>29)return e();-1===c&&(a[b]=null)}for(let[a,b]of Object.entries(f.sources)){let f=c.sources.find(b=>b.unit===a);if(!f||!d(b)||!Array.isArray(b.labels)||b.labels.length!==f.tokens.length)return e();let h=b.labels;if(b.labels=Object.fromEntries(f.tokens.map(([a],b)=>[a,h[b]])),!d(b.labels))return e();for(let a of Object.values(b.labels))g(a,"food_index")}for(let a of f.foods)g(a,"visual_index");return f}(p,q,k.input)',
        'function(a,b){let c=a=>null!==a&&"object"==typeof a&&!Array.isArray(a),d=()=>(b("model_schema"),(0,z.v8)()),e=structuredClone(a);if(!c(e)||!c(e.sources)||!Array.isArray(e.foods))return d();function f(a,b){if(!c(a))return d();let e=a[b];if("number"!=typeof e||!Number.isInteger(e)||e<-1||e>29)return d();-1===e&&(a[b]=null)}for(let a of Object.values(e.sources)){if(!c(a)||!c(a.labels))return d();for(let b of Object.values(a.labels))f(b,"food_index")}for(let a of e.foods)f(a,"visual_index");return e}(p,q)',
      ],
      [
        'Y.replaceAll("null","-1").replace("labels \\xe9 um objeto com TODAS as chaves t0,t1,... fornecidas naquela unidade. Cada valor tem exatamente kind e food_index.","labels \\xe9 um array na ordem EXATA das chaves t0,t1,... fornecidas naquela unidade, com exatamente um item por chave. Cada item tem exatamente kind e food_index. N\\xe3o escreva as chaves no array.").replace("classification \\xe9 visual e labels \\xe9 objeto vazio","classification \\xe9 visual e labels \\xe9 array vazio")',
        'Y.replaceAll("null","-1")',
      ],
    ] as const) {
      expect(text.split(current)).toHaveLength(2)
      text = text.replace(current, prior)
    }
    expect(createHash('sha256').update(text).digest('hex')).toBe(
      'fac0e87fa7358859d3bfc3fbfe86e304a6115ee9915f69d1b802e3a80fb407b3',
    )
  }
  return text
}

/** R183 adds fixed SDK error-type/vendor/technical-term observations only.
 * Seal and reverse this complete diagnostic delta before every R182/older check. */
function restoreProviderErrorShapeR183(text: string, kind: 'source' | 'build'): string {
  text = restoreBoundedMealGrammarR184(text, kind)
  if (kind === 'source') {
    expect(createHash('sha256').update(text).digest('hex')).toBe(
      '91a1d79b35daf2a3ea788a1ac10ac90275f88171f16338849a49c7ec208042eb',
    )
    for (const [current, prior] of [
      [
        "  readonly provider_error?: Readonly<{\n    raw_kind: 'absent' | 'string' | 'object' | 'other'\n    error_type?:\n      | 'invalid_request'\n      | 'invalid_prompt'\n      | 'context_length_exceeded'\n      | 'max_tokens_exceeded'\n      | 'token_limit_exceeded'\n      | 'string_too_long'\n      | 'payload_too_large'\n      | 'unprocessable'\n      | 'unmapped'\n    provider?: 'anthropic' | 'bedrock' | 'azure' | 'google'\n    terms: readonly (\n      | 'additionalproperties'\n      | 'allof'\n      | 'anyof'\n      | 'array'\n      | 'body'\n      | 'budget'\n      | 'compilation'\n      | 'complex'\n      | 'const'\n      | 'constraint'\n      | 'credit'\n      | 'definitions'\n      | 'empty'\n      | 'enum'\n      | 'exceed'\n      | 'exceeds'\n      | 'format'\n      | 'grammar'\n      | 'integer'\n      | 'invalid'\n      | 'items'\n      | 'json'\n      | 'large'\n      | 'length'\n      | 'limit'\n      | 'long'\n      | 'maximum'\n      | 'maxitems'\n      | 'max_tokens'\n      | 'minimum'\n      | 'minitems'\n      | 'missing'\n      | 'null'\n      | 'object'\n      | 'oneof'\n      | 'parameter'\n      | 'pattern'\n      | 'properties'\n      | 'provider'\n      | 'ref'\n      | 'required'\n      | 'response_format'\n      | 'schema'\n      | 'size'\n      | 'string'\n      | 'temperature'\n      | 'tokens'\n      | 'type'\n      | 'unsupported'\n      | 'validation'\n    )[]\n  }>\n",
        '',
      ],
      [
        "  // Observe only fixed technical terms and published error/vendor enums when\n  // the phrase classifier cannot identify a category. Upstream raw may be an\n  // object, not a string. Never enumerate arbitrary keys or evaluate getters.\n  const providerDetails = (): ConversationMealInterpreterDiagnostic['provider_error'] => {\n    if (rejection || stage !== 'provider' || ownData(error, 'status') !== 400) return undefined\n    const inner = ownData(error, 'error'),\n      metadata = ownData(inner, 'metadata') ?? ownData(error, 'metadata'),\n      raw = ownData(metadata, 'raw'),\n      messages = [\n        ownData(error, 'message'),\n        ownData(inner, 'message'),\n        raw,\n        ownData(raw, 'message'),\n        ownData(ownData(raw, 'error'), 'message'),\n      ],\n      vocabulary = [\n        'additionalproperties',\n        'allof',\n        'anyof',\n        'array',\n        'body',\n        'budget',\n        'compilation',\n        'complex',\n        'const',\n        'constraint',\n        'credit',\n        'definitions',\n        'empty',\n        'enum',\n        'exceed',\n        'exceeds',\n        'format',\n        'grammar',\n        'integer',\n        'invalid',\n        'items',\n        'json',\n        'large',\n        'length',\n        'limit',\n        'long',\n        'maximum',\n        'maxitems',\n        'max_tokens',\n        'minimum',\n        'minitems',\n        'missing',\n        'null',\n        'object',\n        'oneof',\n        'parameter',\n        'pattern',\n        'properties',\n        'provider',\n        'ref',\n        'required',\n        'response_format',\n        'schema',\n        'size',\n        'string',\n        'temperature',\n        'tokens',\n        'type',\n        'unsupported',\n        'validation',\n      ] as const,\n      allowedTerms = new Set<string>(vocabulary),\n      words = new Set<string>()\n    if (\n      (inner === null || typeof inner !== 'object') &&\n      (metadata === null || typeof metadata !== 'object')\n    )\n      return undefined\n    for (const message of messages) {\n      if (typeof message !== 'string' || message.length > 65_536) continue\n      for (const word of message.toLowerCase().split(/[^a-z_]+/u))\n        if (allowedTerms.has(word)) words.add(word)\n    }\n    const terms = Object.freeze(vocabulary.filter((term) => words.has(term))),\n      error_type = (\n        [\n          'invalid_request',\n          'invalid_prompt',\n          'context_length_exceeded',\n          'max_tokens_exceeded',\n          'token_limit_exceeded',\n          'string_too_long',\n          'payload_too_large',\n          'unprocessable',\n          'unmapped',\n        ] as const\n      ).find((type) => type === ownData(metadata, 'error_type')),\n      providerName = ownData(metadata, 'provider_name'),\n      provider =\n        typeof providerName === 'string' && providerName.length <= 50\n          ? (\n              [\n                ['anthropic', 'anthropic'],\n                ['amazon bedrock', 'bedrock'],\n                ['amazon-bedrock', 'bedrock'],\n                ['azure', 'azure'],\n                ['google', 'google'],\n                ['google vertex', 'google'],\n              ] as const\n            ).find(([name]) => name === providerName.toLowerCase())?.[1]\n          : undefined\n    if (!terms.length && !error_type && !provider && raw === undefined) return undefined\n    return Object.freeze({\n      raw_kind:\n        raw === undefined\n          ? 'absent'\n          : typeof raw === 'string'\n            ? 'string'\n            : raw !== null && typeof raw === 'object'\n              ? 'object'\n              : 'other',\n      ...(error_type ? { error_type } : {}),\n      ...(provider ? { provider } : {}),\n      terms,\n    })\n  }\n  const details = providerDetails()\n",
        '',
      ],
      ['      ...(details ? { provider_error: details } : {}),\n', ''],
    ] as const) {
      expect(text.split(current)).toHaveLength(2)
      text = text.replace(current, prior)
    }
    expect(createHash('sha256').update(text).digest('hex')).toBe(
      'ee9eef413e471687491523cf15386c9bcb4b514c77acade2b9aa0edc33f14d69',
    )
  }
  if (kind === 'build') {
    expect(createHash('sha256').update(text).digest('hex')).toBe(
      'fac0e87fa7358859d3bfc3fbfe86e304a6115ee9915f69d1b802e3a80fb407b3',
    )
    for (const [current, prior] of [
      [
        'function _(a,b,c,d){let e=(()=>{if("provider"!==a||400!==$(b,"status"))return;let c=$(b,"error");for(let a of[$(b,"message"),$(c,"message"),$($(b,"metadata"),"raw"),$($(c,"metadata"),"raw")]){if("string"!=typeof a||a.length>65536)continue;let b=a.toLowerCase();if(/(schema|grammar).{0,120}(complex|compil|too many|exceed|limit)/u.test(b))return"schema_complexity";if(/(unsupported|not supported|not permitted|not allowed).{0,80}(keyword|schema)|(?:keyword).{0,80}(unsupported|not supported|not permitted|not allowed)/u.test(b))return"schema_keyword";if(/(invalid|malformed).{0,40}(json.?schema|schema)|(?:schema).{0,40}(invalid|malformed)/u.test(b))return"schema_invalid";if(/(not support|unsupported).{0,80}(structured|response_format)|(?:structured|response_format).{0,80}(not support|unsupported)/u.test(b))return"structured_output_unsupported";if(/(max_tokens|output token).{0,80}(exceed|limit|maximum)|(?:exceed|maximum).{0,80}(max_tokens|output token)/u.test(b))return"output_token_limit"}})(),f=(()=>{if(e||"provider"!==a||400!==$(b,"status"))return;let c=$(b,"error"),d=$(c,"metadata")??$(b,"metadata"),f=$(d,"raw"),g=[$(b,"message"),$(c,"message"),f,$(f,"message"),$($(f,"error"),"message")],h=["additionalproperties","allof","anyof","array","body","budget","compilation","complex","const","constraint","credit","definitions","empty","enum","exceed","exceeds","format","grammar","integer","invalid","items","json","large","length","limit","long","maximum","maxitems","max_tokens","minimum","minitems","missing","null","object","oneof","parameter","pattern","properties","provider","ref","required","response_format","schema","size","string","temperature","tokens","type","unsupported","validation"],i=new Set(h),j=new Set;if((null===c||"object"!=typeof c)&&(null===d||"object"!=typeof d))return;for(let a of g)if("string"==typeof a&&!(a.length>65536))for(let b of a.toLowerCase().split(/[^a-z_]+/u))i.has(b)&&j.add(b);let k=Object.freeze(h.filter(a=>j.has(a))),l=["invalid_request","invalid_prompt","context_length_exceeded","max_tokens_exceeded","token_limit_exceeded","string_too_long","payload_too_large","unprocessable","unmapped"].find(a=>a===$(d,"error_type")),m=$(d,"provider_name"),n="string"==typeof m&&m.length<=50?[["anthropic","anthropic"],["amazon bedrock","bedrock"],["amazon-bedrock","bedrock"],["azure","azure"],["google","google"],["google vertex","google"]].find(([a])=>a===m.toLowerCase())?.[1]:void 0;if(k.length||l||n||void 0!==f)return Object.freeze({raw_kind:void 0===f?"absent":"string"==typeof f?"string":null!==f&&"object"==typeof f?"object":"other",...l?{error_type:l}:{},...n?{provider:n}:{},terms:k})})(),g=$(b,"name");if(void 0===g&&null!==b&&"object"==typeof b)try{g=$($(Object.getPrototypeOf(b),"constructor"),"name")}catch{}let h=$(b,"status"),i=Object.freeze({event:"conversation_meal_interpreter_failure",stage:a,error_name:Z.find(a=>a===g)??"UnknownError",...e?{provider_rejection:e}:{},...f?{provider_error:f}:{},..."validation"===a?{validation_reason:T.U.find(a=>a===d)??"validation_internal"}:{},..."number"==typeof h&&Number.isInteger(h)&&h>=100&&h<=599?{http_status:h}:{}});try{c(i)}catch{}}',
        'function _(a,b,c,d){let e=(()=>{if("provider"!==a||400!==$(b,"status"))return;let c=$(b,"error");for(let a of[$(b,"message"),$(c,"message"),$($(b,"metadata"),"raw"),$($(c,"metadata"),"raw")]){if("string"!=typeof a||a.length>65536)continue;let b=a.toLowerCase();if(/(schema|grammar).{0,120}(complex|compil|too many|exceed|limit)/u.test(b))return"schema_complexity";if(/(unsupported|not supported|not permitted|not allowed).{0,80}(keyword|schema)|(?:keyword).{0,80}(unsupported|not supported|not permitted|not allowed)/u.test(b))return"schema_keyword";if(/(invalid|malformed).{0,40}(json.?schema|schema)|(?:schema).{0,40}(invalid|malformed)/u.test(b))return"schema_invalid";if(/(not support|unsupported).{0,80}(structured|response_format)|(?:structured|response_format).{0,80}(not support|unsupported)/u.test(b))return"structured_output_unsupported";if(/(max_tokens|output token).{0,80}(exceed|limit|maximum)|(?:exceed|maximum).{0,80}(max_tokens|output token)/u.test(b))return"output_token_limit"}})(),f=$(b,"name");if(void 0===f&&null!==b&&"object"==typeof b)try{f=$($(Object.getPrototypeOf(b),"constructor"),"name")}catch{}let g=$(b,"status"),h=Object.freeze({event:"conversation_meal_interpreter_failure",stage:a,error_name:Z.find(a=>a===f)??"UnknownError",...e?{provider_rejection:e}:{},..."validation"===a?{validation_reason:T.U.find(a=>a===d)??"validation_internal"}:{},..."number"==typeof g&&Number.isInteger(g)&&g>=100&&g<=599?{http_status:g}:{}});try{c(h)}catch{}}',
      ],
    ] as const) {
      expect(text.split(current)).toHaveLength(2)
      text = text.replace(current, prior)
    }
    expect(createHash('sha256').update(text).digest('hex')).toBe(
      'cf311a5996ea1dd3e4752bd495ae51c5df9c72ba2a7ddb4d24fbf179028120d3',
    )
  }
  return text
}

/** R182 adds closed provider-rejection observations only. Reverse the complete
 * sealed diagnostic delta before every R181 and historical source/build check. */
function restoreProviderDiagnosticR182(text: string, kind: 'source' | 'build'): string {
  text = restoreProviderErrorShapeR183(text, kind)
  if (kind === 'source') {
    expect(createHash('sha256').update(text).digest('hex')).toBe(
      'ee9eef413e471687491523cf15386c9bcb4b514c77acade2b9aa0edc33f14d69',
    )
    for (const [current, prior] of [
      [
        "  readonly provider_rejection?:\n    | 'schema_complexity'\n    | 'schema_keyword'\n    | 'schema_invalid'\n    | 'structured_output_unsupported'\n    | 'output_token_limit'\n",
        '',
      ],
      [
        "  // Classify bounded SDK data in memory; only this closed enum may escape.\n  // Neither raw provider messages nor user-controlled text enter the sink.\n  const providerRejection = (): ConversationMealInterpreterDiagnostic['provider_rejection'] => {\n    if (stage !== 'provider' || ownData(error, 'status') !== 400) return undefined\n    const inner = ownData(error, 'error')\n    const candidates = [\n      ownData(error, 'message'),\n      ownData(inner, 'message'),\n      ownData(ownData(error, 'metadata'), 'raw'),\n      ownData(ownData(inner, 'metadata'), 'raw'),\n    ]\n    for (const raw of candidates) {\n      if (typeof raw !== 'string' || raw.length > 65_536) continue\n      const text = raw.toLowerCase()\n      if (/(schema|grammar).{0,120}(complex|compil|too many|exceed|limit)/u.test(text))\n        return 'schema_complexity'\n      if (\n        /(unsupported|not supported|not permitted|not allowed).{0,80}(keyword|schema)|(?:keyword).{0,80}(unsupported|not supported|not permitted|not allowed)/u.test(\n          text,\n        )\n      )\n        return 'schema_keyword'\n      if (\n        /(invalid|malformed).{0,40}(json.?schema|schema)|(?:schema).{0,40}(invalid|malformed)/u.test(\n          text,\n        )\n      )\n        return 'schema_invalid'\n      if (\n        /(not support|unsupported).{0,80}(structured|response_format)|(?:structured|response_format).{0,80}(not support|unsupported)/u.test(\n          text,\n        )\n      )\n        return 'structured_output_unsupported'\n      if (\n        /(max_tokens|output token).{0,80}(exceed|limit|maximum)|(?:exceed|maximum).{0,80}(max_tokens|output token)/u.test(\n          text,\n        )\n      )\n        return 'output_token_limit'\n    }\n    return undefined\n  }\n  const rejection = providerRejection()\n",
        '',
      ],
      ['      ...(rejection ? { provider_rejection: rejection } : {}),\n', ''],
    ] as const) {
      expect(text.split(current)).toHaveLength(2)
      text = text.replace(current, prior)
    }
    expect(createHash('sha256').update(text).digest('hex')).toBe(
      '6ad76cadf7ca119afac675aeeed3a09962684f165a480072c20289af068d63c7',
    )
  }
  if (kind === 'build') {
    expect(createHash('sha256').update(text).digest('hex')).toBe(
      'cf311a5996ea1dd3e4752bd495ae51c5df9c72ba2a7ddb4d24fbf179028120d3',
    )
    for (const [current, prior] of [
      [
        'function _(a,b,c,d){let e=(()=>{if("provider"!==a||400!==$(b,"status"))return;let c=$(b,"error");for(let a of[$(b,"message"),$(c,"message"),$($(b,"metadata"),"raw"),$($(c,"metadata"),"raw")]){if("string"!=typeof a||a.length>65536)continue;let b=a.toLowerCase();if(/(schema|grammar).{0,120}(complex|compil|too many|exceed|limit)/u.test(b))return"schema_complexity";if(/(unsupported|not supported|not permitted|not allowed).{0,80}(keyword|schema)|(?:keyword).{0,80}(unsupported|not supported|not permitted|not allowed)/u.test(b))return"schema_keyword";if(/(invalid|malformed).{0,40}(json.?schema|schema)|(?:schema).{0,40}(invalid|malformed)/u.test(b))return"schema_invalid";if(/(not support|unsupported).{0,80}(structured|response_format)|(?:structured|response_format).{0,80}(not support|unsupported)/u.test(b))return"structured_output_unsupported";if(/(max_tokens|output token).{0,80}(exceed|limit|maximum)|(?:exceed|maximum).{0,80}(max_tokens|output token)/u.test(b))return"output_token_limit"}})(),f=$(b,"name");if(void 0===f&&null!==b&&"object"==typeof b)try{f=$($(Object.getPrototypeOf(b),"constructor"),"name")}catch{}let g=$(b,"status"),h=Object.freeze({event:"conversation_meal_interpreter_failure",stage:a,error_name:Z.find(a=>a===f)??"UnknownError",...e?{provider_rejection:e}:{},..."validation"===a?{validation_reason:T.U.find(a=>a===d)??"validation_internal"}:{},..."number"==typeof g&&Number.isInteger(g)&&g>=100&&g<=599?{http_status:g}:{}});try{c(h)}catch{}}',
        'function _(a,b,c,d){let e=$(b,"name");if(void 0===e&&null!==b&&"object"==typeof b)try{e=$($(Object.getPrototypeOf(b),"constructor"),"name")}catch{}let f=$(b,"status"),g=Object.freeze({event:"conversation_meal_interpreter_failure",stage:a,error_name:Z.find(a=>a===e)??"UnknownError",..."validation"===a?{validation_reason:T.U.find(a=>a===d)??"validation_internal"}:{},..."number"==typeof f&&Number.isInteger(f)&&f>=100&&f<=599?{http_status:f}:{}});try{c(g)}catch{}}',
      ],
    ] as const) {
      expect(text.split(current)).toHaveLength(2)
      text = text.replace(current, prior)
    }
    expect(createHash('sha256').update(text).digest('hex')).toBe(
      '6b9684163de94810e5702c60980d35d1a2a04eb7367b15c55fc74a4424fb5d20',
    )
  }
  return text
}

/** R181 changes only private provider wire indices. Seal the full current
 * source/build, then reverse the three reviewed compiled expressions and the
 * source projection. Every historical hash and raw graph scan remains active. */
function certifyMealProviderWireR181(): string {
  const chunks = semanticChunks(['.replaceAll("null","-1")', 'conversation.meal-source-labels.v1'])
  expect(chunks).toHaveLength(1)
  const chunk = chunks[0] ?? ''
  let text = restoreProviderDiagnosticR182(readFileSync(chunk, 'utf8'), 'build')
  expect(createHash('sha256').update(text).digest('hex')).toBe(
    '6b9684163de94810e5702c60980d35d1a2a04eb7367b15c55fc74a4424fb5d20',
  )
  for (const [current, prior] of [
    ['.replaceAll("null","-1")', ''],
    [
      'function(a){let b=(0,S.AS)(a,"conversation_meal_source_labels_v1"),c=(a,e=[])=>{if(Array.isArray(a))return a.map(a=>c(a,e));if(null!==a&&"object"==typeof a){if("$ref"in a){let{$ref:d,...f}=a;if("string"!=typeof d||!d.startsWith("#/")||e.includes(d))return(0,z.v8)();let g=b.json_schema.schema;for(let a of d.slice(2).split("/")){let b=a.replaceAll("~1","/").replaceAll("~0","~");if(null===g||"object"!=typeof g||!Object.hasOwn(g,b))return(0,z.v8)();g=g[b]}return null===g||"object"!=typeof g||Array.isArray(g)?(0,z.v8)():c({...g,...f},[...e,d])}let f=Object.fromEntries(Object.entries(a).filter(([a])=>!["minimum","maximum","maxItems"].includes(a)).map(([a,b])=>[a,c(b,e)]));return(0,d.isDeepStrictEqual)(f,{anyOf:[{type:"integer"},{type:"null"}]})?{type:"integer"}:f}return a};return{...b,json_schema:{...b.json_schema,schema:c(b.json_schema.schema)}}}(k.schema)',
      'function(a){let b=(0,S.AS)(a,"conversation_meal_source_labels_v1"),c=a=>Array.isArray(a)?a.map(c):null!==a&&"object"==typeof a?Object.fromEntries(Object.entries(a).filter(([a])=>!["minimum","maximum","maxItems"].includes(a)).map(([a,b])=>[a,c(b)])):a;return{...b,json_schema:{...b.json_schema,schema:c(b.json_schema.schema)}}}(k.schema)',
    ],
    [
      'function(a,b){let c=a=>null!==a&&"object"==typeof a&&!Array.isArray(a),d=()=>(b("model_schema"),(0,z.v8)()),e=structuredClone(a);if(!c(e)||!c(e.sources)||!Array.isArray(e.foods))return d();function f(a,b){if(!c(a))return d();let e=a[b];if("number"!=typeof e||!Number.isInteger(e)||e<-1||e>29)return d();-1===e&&(a[b]=null)}for(let a of Object.values(e.sources)){if(!c(a)||!c(a.labels))return d();for(let b of Object.values(a.labels))f(b,"food_index")}for(let a of e.foods)f(a,"visual_index");return e}(p,q)',
      'p',
    ],
  ] as const) {
    expect(text.split(current)).toHaveLength(2)
    text = text.replace(current, prior)
  }
  expect(createHash('sha256').update(text).digest('hex')).toBe(
    '41cfeaa189a954a60be85ea522189b6fa692e3297dc06b87d7b2b2dffeccac04',
  )
  return chunk
}
function restoreMealProviderWireSourceR181(text: string): string {
  text = restoreProviderDiagnosticR182(text, 'source')
  expect(createHash('sha256').update(text).digest('hex')).toBe(
    '6ad76cadf7ca119afac675aeeed3a09962684f165a480072c20289af068d63c7',
  )
  const projectStart = text.indexOf('  const project = '),
    projectEnd = text.indexOf('\n  return {\n    ...format,', projectStart)
  expect(projectStart).toBeGreaterThan(0)
  expect(projectEnd).toBeGreaterThan(projectStart)
  expect(createHash('sha256').update(text.slice(projectStart, projectEnd)).digest('hex')).toBe(
    '69b5db01934bf69a36ca30c4721ed3b9ddad809ee3bc4fb286a50ba0c10b71ed',
  )
  text =
    text.slice(0, projectStart) +
    "  const project = (value: unknown): unknown => {\n    if (Array.isArray(value)) return value.map(project)\n    if (value !== null && typeof value === 'object')\n      return Object.fromEntries(\n        Object.entries(value)\n          .filter(([key]) => !['minimum', 'maximum', 'maxItems'].includes(key))\n          .map(([key, item]) => [key, project(item)]),\n      )\n    return value\n  }" +
    text.slice(projectEnd)
  const decoderStart = text.indexOf('function decodeMealProviderIndices('),
    decoderEnd = text.indexOf('export interface ConversationMealInterpreter', decoderStart)
  expect(decoderStart).toBeGreaterThan(0)
  expect(decoderEnd).toBeGreaterThan(decoderStart)
  expect(createHash('sha256').update(text.slice(decoderStart, decoderEnd)).digest('hex')).toBe(
    '5261b6b7e842249ec7c5b65a39f5086998184ac8173e00ec73c592b304c701d1',
  )
  text = text.slice(0, decoderStart) + text.slice(decoderEnd)
  for (const [current, prior] of [
    [
      "systemPrompt: MEAL_INTERPRETER_PROMPT.replaceAll('null', '-1'),",
      'systemPrompt: MEAL_INTERPRETER_PROMPT,',
    ],
    [
      'const canonical = packet.materialize(\n          decodeMealProviderIndices(decoded, onFailure),\n          onFailure,\n        )',
      'const canonical = packet.materialize(decoded, onFailure)',
    ],
  ] as const) {
    expect(text.split(current)).toHaveLength(2)
    text = text.replace(current, prior)
  }
  return text
}

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
  const providerWireChunk = certifyMealProviderWireR181()
  const interpreter = restoreMealProviderWireSourceR181(
    readFileSync(
      resolve(appRoot, '../admin/src/lib/mobile-api/conversation-meal-interpreter.ts'),
      'utf8',
    ),
  )
  expect(createHash('sha256').update(interpreter).digest('hex')).toBe(
    'fbeb7ccbd4e0850bcc1f6d4cc203c2b08067cd40410f2e050c8c68a2f18f0d6c',
  )
  // R127 changes only the complete-photo example in the literal prompt; pin
  // its entire new source. Provider helper bytes, parsing and route consumers
  // are unchanged and independently certified below.
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
  expect(chunkConsumers(providerWireChunk)).toEqual(consumers)
  expect(chunkConsumers(chunk)).toEqual(consumers)
  return {
    chunk,
    isEdge: (route: string, target: string) => consumers.includes(route) && target === chunk,
  }
}

/** Seal the complete new provider body before reversing only its optional
 * constructor transport hook. Every historical hash and raw global scan stays. */
function restoreVisionFetchBodyR180(body: string): string {
  expect(createHash('sha256').update(body).digest('hex')).toBe(
    '05919b779e5b031625cf474dfd3edeee917b42723c92a685ff72e1c13e38e224',
  )
  const addition = '...a.fetch?{fetch:a.fetch}:{},'
  expect(body.split(addition)).toHaveLength(2)
  const original = body.replace(addition, '')
  expect(createHash('sha256').update(original).digest('hex')).toBe(
    'f3c74b65ac87a664ca460702b4dfc99fc11a910983a3a751a240f2239c16b4ed',
  )
  return original
}
function restoreVisionFetchSourceR180(text: string): string {
  expect(createHash('sha256').update(text).digest('hex')).toBe(
    '5b55db8304b128582609b88eb76a4937634f6707abd4c6724d841916c5225506',
  )
  for (const addition of [
    '  /** Optional caller transport; defaults retain the installed SDK behavior. */\n  fetch?: typeof globalThis.fetch\n',
    '      ...(cfg.fetch ? { fetch: cfg.fetch } : {}),\n',
  ]) {
    expect(text.split(addition)).toHaveLength(2)
    text = text.replace(addition, '')
  }
  expect(createHash('sha256').update(text).digest('hex')).toBe(
    '111500130aeef167929b5eff7f1f1783d99be104286e20a33ddb0c6f9a6f09aa',
  )
  return text
}
function restorePrivateProcessingDeltaR180(file: string, text: string): string {
  if (file !== 'apps/admin/src/lib/mobile-api/versioned-media-processing-response.ts') return text
  expect(createHash('sha256').update(text).digest('hex')).toBe(
    '413a3642d1a5e0f74062923ae5e4bf0e88e1ffadd2e394ab0df0d231ef8eb1a4',
  )
  const addedImport = "import { z } from 'zod'\n"
  expect(text.split(addedImport)).toHaveLength(2)
  text = text.replace(addedImport, '')
  const schemaStart = text.indexOf('const jobSchema = z\n'),
    schemaEnd = text.indexOf('/** A queue capability')
  expect(schemaStart).toBeGreaterThan(0)
  expect(schemaEnd).toBeGreaterThan(schemaStart)
  text = text.slice(0, schemaStart) + text.slice(schemaEnd)
  const start = text.indexOf(
      "      if (env.MOBILE_CONVERSATION_PROCESSING_BRIDGE_ENABLED === 'true') {\n",
    ),
    end = text.indexOf('      await inngest.send({', start)
  expect(start).toBeGreaterThan(0)
  expect(end).toBeGreaterThan(start)
  text = text.slice(0, start) + text.slice(end)
  // No byte of the legacy default event, gate, Auth or response may change.
  expect(createHash('sha256').update(text).digest('hex')).toBe(
    'ee59ae33a664677b3df4b7f5c61eb39adec5a03417d2bf9915922306983fecb6',
  )
  return text
}

/** This one process module adds only a sealed durable-enqueue branch/schema.
 * Reverse that addition and the deterministic local minifier bindings, then
 * prove all 6,403 historical callback/wrapper bytes match the prior artifact. */
function restorePrivateProcessBodyR180(body: string): string {
  expect(createHash('sha256').update(body).digest('hex')).toBe(
    'ac34282e9cc85e9554b8890ad95640724b352993c611d9a262771a17ca51d7d5',
  )
  const addedLoader = 'B=c(47504),'
  expect(body.split(addedLoader)).toHaveLength(2)
  body = body.replace(addedLoader, '')
  const schemaStart = body.indexOf('let D=B.Ik('),
    schemaEnd = body.indexOf(',E="nodejs"', schemaStart)
  expect(schemaStart).toBeGreaterThan(0)
  expect(schemaEnd).toBeGreaterThan(schemaStart)
  body =
    body.slice(0, schemaStart) + 'let E="nodejs"' + body.slice(schemaEnd + ',E="nodejs"'.length)
  const start = body.indexOf('if("true"===d.MOBILE_CONVERSATION_PROCESSING_BRIDGE_ENABLED)'),
    end = body.indexOf('await A.V.send(', start)
  expect(start).toBeGreaterThan(0)
  expect(end).toBeGreaterThan(start)
  body = body.slice(0, start) + body.slice(end)
  const handler = body.indexOf('async function L(a,b,c)')
  expect(handler).toBeGreaterThan(0)
  const bindings: Record<string, string> = {
    C: 'B',
    E: 'C',
    F: 'D',
    G: 'E',
    H: 'F',
    I: 'G',
    J: 'H',
    K: 'I',
    L: 'J',
  }
  const prefix = body.slice(0, handler).replace(/\b[C-L]\b/g, (name) => bindings[name] ?? name)
  const localBindings: Record<string, string> = { E: 'F', F: 'G', G: 'E' }
  const tail = body
    .slice(handler)
    .replace('async function L(a,b,c)', 'async function J(a,b,c)')
    .replace(/\b[EFG]\b/g, (name) => localBindings[name] ?? name)
  body = prefix + tail
  const enqueue =
    'async enqueue(b){await A.V.send({id:`conversation-media-v2:${b.assetId}:${b.requestId}`,name:"conversation.media.private.process.requested",data:{schema:"conversation.media-process.v2",catalogVersion:2,...b}})}'
  expect(body.split(enqueue)).toHaveLength(2)
  body = body.replace(enqueue, enqueue.replace(/\bb\b/g, 'a'))
  expect(createHash('sha256').update(body).digest('hex')).toBe(
    '7b0cddcee34fc1887c109d933b0f0ac48b815bbd7c35de35b777afb6bfef1fb7',
  )
  return body
}

function certifyPhotoPurposeEdgesR62() {
  const chunks = semanticChunks(['analyzeConversationImage', 'conversation.image-result.v1'])
  expect(chunks).toHaveLength(1)
  const chunk = chunks[0] ?? ''
  const text = readFileSync(chunk, 'utf8')
  const parserCoLocated = text.includes('86248:') || text.includes('63867:')
  const parserId = text.includes('86248:') || text.includes('d=c(86248)') ? '86248' : '63867'
  if (!parserCoLocated) {
    const shared = semanticChunks([
      'conversation.meal-interpreter.v1',
      'read_mobile_registration_feedback',
      'seal_conversation_meal_decision',
      'commit_conversation_meal_feedback_v2',
    ])
    expect(shared).toHaveLength(1)
    const sharedText = readFileSync(shared[0] ?? '', 'utf8')
    expect(sharedText).toContain(`${parserId}:`)
    certifyNutritionJournalSplitContent(sharedText)
  }
  const bodies = certifyExactSharedTable(chunk, [
    [
      '84359',
      parserId === '86248'
        ? 'f3c74b65ac87a664ca460702b4dfc99fc11a910983a3a751a240f2239c16b4ed'
        : '1cca149ffc7a9278307e03f6771ba28c93f3b19eae40409afb60f8e623d203ab',
    ],
    ...(parserCoLocated
      ? [
          [parserId, 'bca65f93158ff60efe08f14a45537b8db4e719a9deb863c2b452b37a11862673'] as [
            string,
            string,
          ],
        ]
      : []),
  ], (id, body) => id === '84359' ? restoreVisionFetchBodyR180(body) : body)
  // R62's routing diagnostics import the existing OpenAI error classes directly.
  // Webpack factors that SDK differently: Gemini changes only this loader ID.
  // Reverse exactly one link to retain the independent full R59 body pin; no
  // raw code or transitive is removed from the physical/global scans below.
  const currentGeminiR106 = restoreVisionFetchBodyR180(bodies.get('84359') ?? '')
  expect(currentGeminiR106.split(`d=c(${parserId})`)).toHaveLength(2)
  const rawGeminiR102 =
    parserId === '63867' ? currentGeminiR106.replace('d=c(63867)', 'd=c(86248)') : currentGeminiR106
  expect(createHash('sha256').update(rawGeminiR102).digest('hex')).toBe(
    'f3c74b65ac87a664ca460702b4dfc99fc11a910983a3a751a240f2239c16b4ed',
  )
  // The R102 reviewed writer now shares the pure observation helper. Webpack
  // relocates the byte-identical parser to86248; reverse exactly one loader
  // link to the complete R101 body before retaining every older proof below.
  expect(rawGeminiR102.split('d=c(86248)')).toHaveLength(2)
  const rawGeminiR101 = rawGeminiR102.replace('d=c(86248)', 'd=c(63867)')
  expect(createHash('sha256').update(rawGeminiR101).digest('hex')).toBe(
    '1cca149ffc7a9278307e03f6771ba28c93f3b19eae40409afb60f8e623d203ab',
  )
  // R101 restores the exact R98 packaging (parser63867). Normalize its one
  // loader link to R99, retaining the entire historical proof below.
  expect(rawGeminiR101.split('d=c(63867)')).toHaveLength(2)
  const rawGemini = rawGeminiR101.replace('d=c(63867)', 'd=c(86248)')
  expect(createHash('sha256').update(rawGemini).digest('hex')).toBe(
    'f3c74b65ac87a664ca460702b4dfc99fc11a910983a3a751a240f2239c16b4ed',
  )
  // R99 moves the identical image-result body back to86248. Reverse one
  // loader link to the exact R98 body before retaining its prior proof below.
  expect(rawGemini.split('d=c(86248)')).toHaveLength(2)
  const gemini = rawGemini.replace('d=c(86248)', 'd=c(63867)')
  expect(createHash('sha256').update(gemini).digest('hex')).toBe(
    '1cca149ffc7a9278307e03f6771ba28c93f3b19eae40409afb60f8e623d203ab',
  )
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
        .update(source === 'vision/gemini.ts'
          ? restoreVisionFetchSourceR180(readFileSync(resolve(appRoot, '../../packages/providers/src', source), 'utf8'))
          : readFileSync(resolve(appRoot, '../../packages/providers/src', source ?? '')))
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
  // R118 adds one read-only consumer. The complete 20-module bodies above
  // remain frozen; new training sources are independently constrained below.
  expect(chunkConsumers(chunk)).toEqual(
    [...commandRoutes, nutritionWindowAppPath, '/api/mobile/v1/training/window/route'].sort(),
  )
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
function restoreMediaFactoryLinkR170(body: string): string {
  const pins = [
    [
      '7f0d18531e2756edef8820d14e93ca67f6ca5b0696ff9747f7704bb7e05975a2',
      '2142720a3775b78022d343173a090529e6215d164c1a49051af37d889adad139',
    ],
    [
      '25e50a979249c1b64541c8e45fdd72a529d02d0b6506d8e63ed10b4e6efdb682',
      '8dc0e654afd13a863be5a9bddb9fb0a7b61c1a29254208c428c3f10feeb4a7e6',
    ],
  ]
  const hash = createHash('sha256').update(body).digest('hex')
  if (pins.some((pair) => pair[1] === hash)) return body
  const pair = pins.find((pair) => pair[0] === hash)
  expect(pair, 'complete old GET/complete body with one relocated factory loader').toBeDefined()
  expect(body.split('c(97281)')).toHaveLength(2)
  const restored = body.replace('c(97281)', 'c(83201)')
  expect(createHash('sha256').update(restored).digest('hex')).toBe(pair?.[1])
  return restored
}
/** Seal the complete R173 additions before removing only the explicit process
 * capability. The original GET/complete implementations and legacy processing
 * callback must reconstruct byte for byte, including idempotency and Auth. */
function originalPrivateDeletionSourceR174(file: string, text: string): string {
  text = restorePrivateProcessingDeltaR180(file, text)
  const pins: Record<string, readonly [string, string]> = {
    'packages/core/package.json': [
      '54fbc47f234eb7a995c339436b07928ba9edbb9abc32bc4bf6791d0c69e5b1be',
      'f2fa7be7329060f8aecb18b04d7d8ce90d81e5c7fc36e651c32c004fddaf72fc',
    ],
    'apps/admin/src/lib/mobile-api/private-conversation-media-owned.ts': [
      '2dbd8dca6bb9a4498f07bc247cc691ff1fc1b41e360f1820f009a50b618b74c9',
      'd054b7b5dedbec616e9136c01dd6c1b56f71e885011779612b351f7ae9a582fa',
    ],
    'apps/admin/src/lib/mobile-api/versioned-media-owned-response.ts': [
      'e487c5a3a65afe191a84166dcf411dd32d19bc6f648588be0dcfbd88d75c8305',
      '1d5cdc2cef774902393c674263154b490c6930fe4db95de53e33e114b0a20b70',
    ],
    'apps/admin/src/app/api/mobile/v1/media/[id]/route.ts': [
      '4fb01b09ad1274dc9bb83448a0dbd1aca380b7950180d2e0d97e2b86645a438a',
      '93ab2c148718d4a2381019cf41ad0aa9f7efd45e451d3a77bfa3383457bf83ae',
    ],
  }
  const pin = pins[file]
  if (!pin) return text
  expect(createHash('sha256').update(text).digest('hex')).toBe(pin[0])
  const replace = (from: string, to: string) => {
    expect(text.split(from)).toHaveLength(2)
    text = text.replace(from, to)
  }
  if (file === 'packages/core/package.json') {
    replace('    "./conversation-media-disposal": "./src/conversation-media-disposal.ts",\n', '')
  } else if (file.endsWith('/private-conversation-media-owned.ts')) {
    replace(
      "  /** A single committed revocation; never the worker's global sweep. */\n  dispose?(identity: ConversationMediaIdentityV2): Promise<void>\n",
      '',
    )
    replace(
      "  operation: 'read' | 'complete' | 'process' | 'delete',",
      "  operation: 'read' | 'complete' | 'process',",
    )
    replace(
      "(operation !== 'delete' && kind === 'conversation_photo' && ports.photoEnabled() !== true)",
      "(kind === 'conversation_photo' && ports.photoEnabled() !== true)",
    )
    replace(
      "      if (\n        operation !== 'delete' &&\n        row.status !== 'deleted' &&\n        Date.parse(row.retention_until) <= at\n      )",
      "      if (row.status !== 'deleted' && Date.parse(row.retention_until) <= at)",
    )
    const start = text.indexOf("    if (operation === 'delete') {\n"),
      end = text.indexOf("    if (operation === 'process') {\n", start)
    expect(start).toBeGreaterThan(0)
    expect(end).toBeGreaterThan(start)
    text = text.slice(0, start) + text.slice(end)
  } else if (file.endsWith('/versioned-media-owned-response.ts')) {
    replace(
      "import {\n  type OwnedConversationMediaPorts,\n  ownedConversationMediaOperation,\n} from './private-conversation-media-owned'",
      "import { ownedConversationMediaOperation } from './private-conversation-media-owned'",
    )
    replace(
      "  operation: 'read' | 'complete' | 'process' | 'delete',",
      "  operation: 'read' | 'complete' | 'process',",
    )
    replace("  disposal?: { dispose: NonNullable<OwnedConversationMediaPorts['dispose']> },\n", '')
    replace('        ...(disposal ? { dispose: disposal.dispose } : {}),\n', '')
  } else {
    replace(
      "import { versionedMediaDisposalResponse } from '@/lib/mobile-api/versioned-media-disposal-response'\n",
      '',
    )
    const prefix = '      versionedMediaDisposalResponse(context, id, async () =>\n',
      start = text.indexOf(prefix),
      end = text.indexOf('\n      ),\n    )', start)
    expect(text.split(prefix)).toHaveLength(2)
    expect(end).toBeGreaterThan(start)
    text =
      text.slice(0, start) +
      text
        .slice(start + prefix.length, end)
        .split('\n')
        .map((line) => line.slice(2))
        .join('\n') +
      text.slice(end + '\n      ),'.length)
  }
  expect(createHash('sha256').update(text).digest('hex')).toBe(pin[1])
  return text
}
function originalProcessingSourceR173(name: string): string {
  const pins: Record<string, readonly [string, string]> = {
    'private-conversation-media-owned.ts': [
      'd054b7b5dedbec616e9136c01dd6c1b56f71e885011779612b351f7ae9a582fa',
      '8d1702c2f5c8bc791086993a837b6074183b5d825680a960efcc2f8b5a7593f7',
    ],
    'versioned-media-owned-response.ts': [
      '1d5cdc2cef774902393c674263154b490c6930fe4db95de53e33e114b0a20b70',
      'd24b3c0dae9f824ad3438c7c75f8d33da176975e931dd0c0275fa9c9a40e438e',
    ],
    'media/[id]/process/route.ts': [
      '61ad1de472370c7446cf4a0f94ce24826b6b4b62f411c1ad4b575a0e92a4955a',
      '2d87df63df3c983c52b6378529ea83a79f5699f3a00868cb59f6824a4c09c697',
    ],
  }
  const pin = pins[name]
  if (!pin) throw new Error('Unreviewed processing source')
  let text = originalPrivateDeletionSourceR174(
    name.startsWith('media/')
      ? `apps/admin/src/app/api/mobile/v1/${name}`
      : `apps/admin/src/lib/mobile-api/${name}`,
    readFileSync(
      resolve(
        appRoot,
        '../admin/src',
        name.startsWith('media/') ? 'app/api/mobile/v1' : 'lib/mobile-api',
        name,
      ),
      'utf8',
    ),
  )
  expect(createHash('sha256').update(text).digest('hex')).toBe(pin[0])
  const replace = (from: string, to: string) => {
    expect(text.split(from)).toHaveLength(2)
    text = text.replace(from, to)
  }
  if (name === 'private-conversation-media-owned.ts') {
    replace("import { createHash } from 'node:crypto'\n", '')
    replace(
      "import { idempotencyKeySchema, resourceIdSchema } from './contracts'",
      "import { resourceIdSchema } from './contracts'",
    )
    replace(
      '  /** Available only to the explicit processing route; no fact writer. */\n  enqueue?(input: { userId: string; assetId: string; requestId: string }): Promise<void>\n',
      '',
    )
    replace(
      "  operation: 'read' | 'complete' | 'process',\n  requestKey?: string,",
      "  operation: 'read' | 'complete',",
    )
    const start = text.indexOf("    if (operation === 'process') {\n"),
      end = text.indexOf("    if (operation === 'complete') {\n", start)
    expect(start).toBeGreaterThan(0)
    expect(end).toBeGreaterThan(start)
    text = text.slice(0, start) + text.slice(end)
  } else if (name === 'versioned-media-owned-response.ts') {
    replace("  operation: 'read' | 'complete' | 'process',", "  operation: 'read' | 'complete',")
    replace(
      '  processing?: {\n    requestKey: string\n    enqueue(input: { userId: string; assetId: string; requestId: string }): Promise<void>\n  },\n',
      '',
    )
    replace('        ...(processing ? { enqueue: processing.enqueue } : {}),\n', '')
    replace('      processing?.requestKey,\n', '')
    replace(
      "mobileSuccess(result.value, context.requestId, operation === 'process' ? 202 : 200)",
      'mobileSuccess(result.value, context.requestId)',
    )
  } else {
    replace(
      "import { versionedMediaProcessingResponse } from '@/lib/mobile-api/versioned-media-processing-response'\n",
      '',
    )
    const prefix = '      versionedMediaProcessingResponse(context, id, async () =>\n',
      start = text.indexOf(prefix),
      end = text.indexOf('\n      ),\n    )', start)
    expect(text.split(prefix)).toHaveLength(2)
    expect(end).toBeGreaterThan(start)
    const inner = text
      .slice(start + prefix.length, end)
      .split('\n')
      .map((line) => line.slice(2))
      .join('\n')
    text = text.slice(0, start) + inner + text.slice(end + '\n      ),'.length)
  }
  expect(createHash('sha256').update(text).digest('hex')).toBe(pin[1])
  return text
}
/** R171 intentionally changes only GET/complete composition. Pin each whole
 * new route body; the unchanged old source/callback is reconstructed below.
 * Historical R170 loader certificates remain available for their old bodies. */
function certifyOwnedMediaBodyR171(body: string): string {
  expect([
    '14150a04c5bc2a47b5ef13db44bb5b2d70381a7880681ae3f6dae09facdf6c94',
    '3f32995297bba5cb0b17ede719a874dedafe9d6fd5a2fe1805be665d8997fcf6',
  ]).toContain(createHash('sha256').update(body).digest('hex'))
  return body
}
function certifyOwnedMediaBodyR174(body: string): string {
  expect(createHash('sha256').update(body).digest('hex')).toBe(
    '9837023bab44ba7527434737f7b19d4d9f5f1acd80ab224af49470476e8fd2e7',
  )
  return body
}
function certifyPhysicalModule(
  file: string,
  id: string,
  allowedHashes: readonly string[],
  restore?: (body: string) => string,
): string {
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
  const raw = restoreMediaFactoryLinkR173(found[0]?.getText(source) ?? '')
  const body = restoreWorkoutFacadeLinkR140(restore ? restore(raw) : raw)
  expect(allowedHashes).toContain(createHash('sha256').update(body).digest('hex'))
  expect(text.startsWith('"use strict";') || body.startsWith('(a,b,c)=>{"use strict";')).toBe(true)
  return body
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

const executionRouteFiles = new Set([
  'training/execution/route.ts',
  'training/execution/[sessionId]/route.ts',
  'training/execution/commands/route.ts',
])

function sourceRecords(): Array<{ path: string; exports: string[] }> {
  return walkFiles(sourceRoot)
    .filter((path) => path.endsWith(`${sep}route.ts`))
    .filter(
      (path) =>
        !executionRouteFiles.has(relative(sourceRoot, path).split(sep).join('/')) &&
        !completionTransports.has(relative(sourceRoot, path).split(sep).join('/')) &&
        !journeySocialTransports.has(relative(sourceRoot, path).split(sep).join('/')),
    )
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
  return Object.fromEntries(
    Object.entries(
      JSON.parse(readFileSync(appPathsManifestPath, 'utf8')) as Record<string, string>,
    ).filter(
      ([path]) =>
        !executionRouteFiles.has(path.replace('/api/mobile/v1/', '') + '.ts') &&
        !completionTransports.has(path.replace('/api/mobile/v1/', '') + '.ts') &&
        !journeySocialTransports.has(path.replace('/api/mobile/v1/', '') + '.ts'),
    ),
  )
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
  test('preserves exact old owned operations and processing callback under the private capability', () => {
    for (const name of [
      'private-conversation-media-owned.ts',
      'versioned-media-owned-response.ts',
      'media/[id]/process/route.ts',
    ])
      expect(originalProcessingSourceR173(name)).toBeTypeOf('string')
    const entry = currentAppPathsManifest()['/api/mobile/v1/media/[id]/process/route']
    const file = resolve(buildRoot, 'server', entry ?? '')
    const body = certifyPhysicalModule(file, '40550', [
      '7b0cddcee34fc1887c109d933b0f0ac48b815bbd7c35de35b777afb6bfef1fb7',
    ], restorePrivateProcessBodyR180)
    certifyPhysicalModule(file, '72262', [
      'c50d3d95cbb616ce76dd8d84d9312750bdd67047b88fdb489e12f94a8deaf1e0',
    ])
    const certify = (value: string) =>
      expect(createHash('sha256').update(value).digest('hex')).toBe(
        '7b0cddcee34fc1887c109d933b0f0ac48b815bbd7c35de35b777afb6bfef1fb7',
      )
    for (const mutation of [
      body.replace('conversation.media.private.process.requested', 'media.asset.process.requested'),
      body.replace('catalogVersion:2', 'catalogVersion:1'),
      body.replace('c(46337)', 'c(999999)'),
      `${body};void 0`,
    ])
      expect(() => certify(mutation)).toThrow()
  })
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
  test('rejects changed loader or executable bytes in the relocated legacy media routes', () => {
    const target = currentAppPathsManifest()['/api/mobile/v1/media/[id]/route']
    const file = resolve(buildRoot, 'server', target ?? '')
    if (readFileSync(file, 'utf8').includes('77344:')) {
      const body = certifyPhysicalModule(file, '77344', [
        '9837023bab44ba7527434737f7b19d4d9f5f1acd80ab224af49470476e8fd2e7',
      ])
      for (const changed of [
        body.replace(
          'claim_conversation_media_owned_disposal_v2',
          'claim_conversation_media_disposal_batch_v2',
        ),
        body.replace('media_asset_id', 'unapproved_asset_id'),
        body.replace('c(22693)', 'c(999999)'),
        `${body};void 0`,
      ])
        expect(() => certifyOwnedMediaBodyR174(changed)).toThrow()
      return
    }
    const body = certifyPhysicalModule(resolve(buildRoot, 'server', target ?? ''), '82635', [
      '7f0d18531e2756edef8820d14e93ca67f6ca5b0696ff9747f7704bb7e05975a2',
      '2142720a3775b78022d343173a090529e6215d164c1a49051af37d889adad139',
      '14150a04c5bc2a47b5ef13db44bb5b2d70381a7880681ae3f6dae09facdf6c94',
    ])
    const verify = body.includes('c(72262)')
      ? certifyOwnedMediaBodyR171
      : restoreMediaFactoryLinkR170
    expect(() => verify(body)).not.toThrow()
    const loader = body.includes('c(97281)') ? 'c(97281)' : 'c(83201)'
    for (const changed of [
      body.replace(loader, 'c(999999)'),
      body.replace('media_asset_id', 'unapproved_asset_id'),
      `${body};void 0`,
    ])
      expect(() => verify(changed)).toThrow()
  })
  test('rejects changed exports or executable bytes in the exact negotiated media bridge', () => {
    const chunks = semanticChunks([
      'conversation.intake-result.v1',
      'read_conversation_intake_routing_result',
      'reconcile_conversation_intake_routing',
    ])
    expect(chunks).toHaveLength(1)
    const bodies = certifyExactSharedTable(
        chunks[0] ?? '',
        [
          ['34168', '5c180f5861365e95d2485fc2d0348dd3b1405695cbb1441dad80341cf593a67b'],
          ['47804', '5d69e37d38dfebebad9a617cc333686fdeee9e6797e6640d8c595b97f1b7d209'],
          ['50522', 'a5d450bd9b7267e8756ae2f7b5a6910ead5d90ff83fe073d39b7f6ad278b3633'],
          ...(readFileSync(chunks[0] ?? '', 'utf8').includes('32978:')
            ? [
                [
                  '32978',
                  '921228c6a39061e494283bd41e527304958de5a19654e998855fd9d567adfe1f',
                ] as const,
              ]
            : [
                [
                  '6535',
                  '2eef75ca30d2cfabb2e71e2e652c8b41d0b884572469eed6424484a5b45969f3',
                ] as const,
              ]),
        ],
        restorePrivateMediaContractR168,
      ),
      body = bodies.get('32978') ?? bodies.get('6535') ?? ''
    expect(() => certifyIntakeMediaBridgeR102(body)).not.toThrow()
    for (const changed of [
      body.replace('o:()=>ao,', ''),
      body.replace('o:()=>ao,', 'o:()=>ao,x:()=>ao,'),
      body.replace('MOBILE_CONVERSATION_INTAKES_ENABLED', 'MOBILE_CONVERSATION_UNREVIEWED'),
      body.replace('X-Conversation-Media-Provenance', 'X-Unapproved-Provenance'),
      body.replace('conversation.intake-result.v2', 'conversation.intake-result.v1'),
      body.replace('media_temporarily_unavailable', 'media_projection_required'),
      body.replace('label_product_required', 'routing_unavailable'),
      body.replace('image_description_required', 'routing_unavailable'),
      body.replace(/n=c\((?:63867|86248)\)/, 'n=c(86249)'),
    ])
      expect(() => certifyIntakeMediaBridgeR102(changed)).toThrow()
  })
  test('refuses removal or substitution of the exact private media version checks', () => {
    const chunks = semanticChunks([
      'conversation.meal-interpreter.v1',
      'read_mobile_registration_feedback',
      'seal_conversation_meal_decision',
      'commit_conversation_meal_feedback_v2',
    ])
    expect(chunks).toHaveLength(1)
    const body = certifyPhysicalModule(chunks[0] ?? '', '61104', [
      '2b991e02d5f7c042c60dfd16fac08ae6a3eb0bd4417714ec4c8f3f7413c748c0',
    ])
    for (const changed of [
      body.replace('catalog_version:f.eu(2).optional(),', ''),
      body.replace('catalog_version:f.eu(2).optional(),', 'catalog_version:f.eu(1).optional(),'),
      body.replace('||i.media.catalog_version!==k.catalog_version', ''),
      body.replace(
        '||i.media.catalog_version!==k.catalog_version',
        '||i.media.catalog_version===k.catalog_version',
      ),
    ])
      expect(() => restorePrivateMediaContractR168('61104', changed)).toThrow()
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
  test('keeps the additive 93-route manifest and exact prior88 and prior85 export streams', () => {
    const records = sourceRecords()
    const hash = hashRecords(records)

    console.info(`SOURCE_ROUTE_EXPORT_COUNT=${records.length}`)
    console.info(`SOURCE_ROUTE_EXPORT_STREAM_SHA256=${hash}`)

    expect(records).toHaveLength(93)
    expect(hash).toBe('379b260d910f1364041880fb6aab30c458c9a8b511760735a9396aa8a058b5cf')
    const beforeLinked = records.filter(
      (record) =>
        record.path !== 'training/window/route.ts' &&
        record.path !== 'conversation/meal-commands/[commandId]/origin/route.ts',
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

  test('preserves the prior88 Mobile and prior89 total streams within the additive 93/94 build', () => {
    const currentSurface = inspectBuildSurface(buildRoot)
    const paths = currentSurface.routePaths.filter(
      (path) =>
        !executionRouteFiles.has(path.replace('/api/mobile/v1/', '') + '/route.ts') &&
        !completionBuildPaths.has(path) && !journeySocialBuildPaths.has(path),
    )
    const mobile = currentSurface.mobileRoutePaths.filter(
      (path) =>
        !executionRouteFiles.has(path.replace('/api/mobile/v1/', '') + '/route.ts') &&
        !completionBuildPaths.has(path) && !journeySocialBuildPaths.has(path),
    )
    const digest = (values: string[]) =>
      createHash('sha256')
        .update(values.map((p) => `${p}\n`).join(''))
        .digest('hex')
    const surface = {
      ...currentSurface,
      routePaths: paths,
      mobileRoutePaths: mobile,
      routePathHash: digest(paths),
      mobileRoutePathHash: digest(mobile),
    }

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

    expect(surface.routePaths).toHaveLength(94)
    expect(surface.routePathHash).toBe(
      '4ff0c3610291b53b1a8245597f673be4443dcace0b6aae86a819e63a3629c3ab',
    )
    expect(surface.mobileRoutePaths).toHaveLength(93)
    expect(surface.mobileRoutePathHash).toBe(
      '22926ab33b91fc36dde1834843c56d38fb6b06fe00de0294fe79e54529ba3013',
    )
    expect(surface.mobileRoutePaths.filter((path) => conversationIntakeURLs.has(path))).toEqual(
      [...conversationIntakeURLs].sort(),
    )
    const prior88Mobile = surface.mobileRoutePaths.filter(
        (path) =>
          path !== '/api/mobile/v1/training/window' &&
          path !== '/api/mobile/v1/conversation/meal-commands/[commandId]/origin' &&
          !conversationIntakeURLs.has(path),
      ),
      prior89All = surface.routePaths.filter(
        (path) =>
          path !== '/api/mobile/v1/training/window' &&
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
    const currentPhotoAdjunct = '.replace(/ (?:agora|hoje)([.!]?)$/u,"$1")'
    expect(text.split(currentPhotoAdjunct)).toHaveLength(2)
    expect(() =>
      certifyNutritionJournalSplitContent(
        text.replace(currentPhotoAdjunct, '.replace(/ (?:amanha|hoje)([.!]?)$/u,"$1")'),
      ),
    ).toThrow(/certified nutrition-shared module contents/)
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
    expect(text.split('["reported","media_pointer"].includes')).toHaveLength(2)
    expect(() =>
      certifyNutritionJournalSplitContent(
        text.replace(
          '["reported","media_pointer"].includes',
          '["reported","nominal_list"].includes',
        ),
      ),
    ).toThrow(/certified nutrition-shared module contents/)
    expect(text.split('quantity_g_estimate:0,confidence:')).toHaveLength(2)
    expect(() =>
      certifyNutritionJournalSplitContent(
        text.replace('quantity_g_estimate:0,confidence:', 'quantity_g_estimate:30,confidence:'),
      ),
    ).toThrow(/certified nutrition-shared module contents/)
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

  test('keeps ordinary image validation from adding image execution to readonly nutrition or workout routes', () => {
    const routes = runtimeMarkerRoutes('analyzeConversationImage')
    for (const route of [nutritionWindowAppPath, ...conversationWorkoutAppPaths])
      expect(routes).not.toContain(route)
  })

  test('confines the durable private processing transport to the owned process POST', () => {
    for (const marker of ['enqueue_conversation_media_processing_job_v2', 'dispatch_due_conversation_media_processing_v2'])
      expect(runtimeExactStringRoutes(marker)).toEqual(['/api/mobile/v1/media/[id]/process/route'])
    expect(runtimeMarkerRoutes('MOBILE_CONVERSATION_PROCESSING_BRIDGE_ENABLED')).toEqual([
      '/api/mobile/v1/media/[id]/process/route',
    ])
  })

  test('keeps photo-purpose and disposal gates on the closed media transports', () => {
    // R167 adds one pure private-media subpath and exports one unchanged URL
    // parser. Seal the full new sources, then reconstruct the exact historical
    // inputs below. No legacy source assertion or compiled certificate is lost.
    for (const [file, hash] of [
      [
        'packages/core/package.json',
        'f2fa7be7329060f8aecb18b04d7d8ce90d81e5c7fc36e651c32c004fddaf72fc',
      ],
      [
        'packages/core/src/conversation-media.ts',
        '16e18d3553cdb34a0d60586a7e727d85df33c6d49661e829c9b3f8d845904237',
      ],
      [
        'packages/core/src/conversation-media-namespace.ts',
        'c53addbd89eba7f608bcf2133cf6c4db1723563d735087455e0d45db5f8a92a7',
      ],
      [
        'packages/core/src/conversation-media-catalog.ts',
        '44cef2a5d67776ab703a50160a36664a6864113aa0d58c58dae3720df0d6943b',
      ],
      [
        'packages/core/src/conversation-media-lifecycle.ts',
        'c63a71aaaf9346c4f394f34fab438023637c5e922f6691f75b7882a20fc4c79b',
      ],
      [
        'apps/admin/src/lib/mobile-api/ordinary-media-upload.ts',
        '10222c3bbce4d628118d5a0cfc00ec08eba748ba2199ca500eaa15ae9ba02aad',
      ],
      [
        'apps/admin/src/app/api/mobile/v1/media/route.ts',
        '62b5b20738e5cc7c35fd5b65183d54a7e8b8222c7bb1beffdfabd6527d698de3',
      ],
      [
        'apps/admin/src/lib/mobile-api/private-conversation-media-api.ts',
        'faa2bbccd78c08628829b360632b7025d7854eccc7b5e0bd76f79edfd102ef84',
      ],
      [
        'apps/admin/src/lib/mobile-api/versioned-media-upload-response.ts',
        '5b6edbc324a4a747007a819dd599afcb73660ac2ee2c7cf6f9923ccff01dc8e2',
      ],
      [
        'apps/admin/src/lib/mobile-api/private-conversation-media-upload.ts',
        'da31de004fd23ff406a18330c4d118c944cd563f933aa7547065bc44e5b52550',
      ],
      [
        'apps/admin/src/lib/mobile-api/supabase-private-conversation-media.ts',
        '703bbf815853aac41720dcbc6ec1730c9c525f2236b6c249a61ea0a28a7e68d3',
      ],
      [
        'apps/admin/src/lib/mobile-api/private-conversation-media-owned.ts',
        'd054b7b5dedbec616e9136c01dd6c1b56f71e885011779612b351f7ae9a582fa',
      ],
      [
        'apps/admin/src/lib/mobile-api/versioned-media-owned-response.ts',
        '1d5cdc2cef774902393c674263154b490c6930fe4db95de53e33e114b0a20b70',
      ],
      [
        'apps/admin/src/lib/mobile-api/versioned-media-processing-response.ts',
        'ee59ae33a664677b3df4b7f5c61eb39adec5a03417d2bf9915922306983fecb6',
      ],
      [
        'apps/admin/src/app/api/mobile/v1/media/[id]/process/route.ts',
        '61ad1de472370c7446cf4a0f94ce24826b6b4b62f411c1ad4b575a0e92a4955a',
      ],
      [
        'apps/admin/src/app/api/mobile/v1/media/[id]/route.ts',
        '93ab2c148718d4a2381019cf41ad0aa9f7efd45e451d3a77bfa3383457bf83ae',
      ],
      [
        'apps/admin/src/app/api/mobile/v1/media/[id]/complete/route.ts',
        '6baabe3b095741d8c23c660c285ad59f87adc65c01d4fe4d082aaca86fbeacfa',
      ],
      [
        'packages/core/src/conversation-media-disposal.ts',
        '62cd28b2c705b4bf5898a7f5653b7d00c6bb4c88361e463528e3b98e33a269a1',
      ],
      [
        'apps/admin/src/lib/mobile-api/private-conversation-media-disposal.ts',
        'e293c53fb04c15a62ea8398714a87f10021769e6c41b98847417cac5e3d7fd08',
      ],
      [
        'apps/admin/src/lib/mobile-api/versioned-media-disposal-response.ts',
        '8a1a56729c947f70d334b7a6bb7aaaa284d3d251b5a19e6929ac2f9a0965bd56',
      ],
    ])
      expect(
        createHash('sha256')
          .update(
            originalPrivateDeletionSourceR174(
              file ?? '',
              readFileSync(resolve(appRoot, '../..', file ?? ''), 'utf8'),
            ),
          )
          .digest('hex'),
      ).toBe(hash)
    const legacySource = (file: string) => {
      const text = originalPrivateDeletionSourceR174(
        file,
        readFileSync(resolve(appRoot, '../..', file), 'utf8'),
      )
      if (file === 'packages/core/package.json') {
        const addition = '    "./conversation-media": "./src/conversation-media.ts",\n'
        expect(text.split(addition)).toHaveLength(2)
        return text.replace(addition, '')
      }
      if (file === 'apps/admin/src/lib/mobile-api/ordinary-media-upload.ts') {
        const addition = 'export function providerExpiry('
        expect(text.split(addition)).toHaveLength(2)
        return text.replace(addition, 'function providerExpiry(')
      }
      if (file === 'apps/admin/src/app/api/mobile/v1/media/route.ts') {
        const imports =
          "import { versionedMediaUploadResponse } from '@/lib/mobile-api/versioned-media-upload-response'\n"
        const binding =
          '  const configuredResponse = () => versionedMediaUploadResponse(context, input, createResponse)\n'
        expect(text.split(imports)).toHaveLength(2)
        expect(text.split(binding)).toHaveLength(2)
        return text
          .replace(imports, '')
          .replace(binding, '')
          .replace(
            'executeSupabaseIdempotent(context, input, configuredResponse,',
            'executeSupabaseIdempotent(context, input, createResponse,',
          )
          .replace('refreshReplay: configuredResponse,', 'refreshReplay: createResponse,')
      }
      if (
        file === 'apps/admin/src/app/api/mobile/v1/media/[id]/route.ts' ||
        file === 'apps/admin/src/app/api/mobile/v1/media/[id]/complete/route.ts'
      ) {
        const imports =
          "import { versionedOwnedMediaResponse } from '@/lib/mobile-api/versioned-media-owned-response'\n"
        expect(text.split(imports)).toHaveLength(2)
        const plain = text.replace(imports, '')
        const isRead = file.endsWith('/[id]/route.ts')
        const prefix = isRead
          ? "  versionedOwnedMediaResponse(context, await mediaId(routeContext), 'read', async () =>\n"
          : "          return await versionedOwnedMediaResponse(context, id, 'complete', async () =>\n"
        expect(plain.split(prefix)).toHaveLength(2)
        const start = plain.indexOf(prefix)
        const suffix = isRead
          ? '\n  ),\n)\n\nexport const DELETE'
          : '\n          )\n        } catch'
        const end = plain.indexOf(suffix, start)
        expect(end).toBeGreaterThan(start)
        let inner = plain
          .slice(start + prefix.length, end)
          .split('\n')
          .map((line) => line.slice(2))
          .join('\n')
        if (!isRead) {
          expect(inner.endsWith('),')).toBe(true)
          inner = inner
            .replace('          mobileSuccess(', '          return mobileSuccess(')
            .slice(0, -1)
        }
        return (
          plain.slice(0, start) +
          inner +
          plain.slice(end + (isRead ? '\n  ),'.length : '\n          )'.length))
        )
      }
      return text
    }
    // R173 adds processing only to the existing default-OFF versioned graph.
    // The event producer is confined to process; no worker/model factory is
    // imported. DELETE behavior, clinical and unrelated entries stay unchanged.
    for (const marker of [
      'conversation-v2/',
      'prepare_conversation_media_upload_v2',
      'claim_conversation_media_processing_v2',
      'resolve_conversation_media_catalog_v2',
    ])
      expect(runtimeMarkerRoutes(marker)).toEqual([
        '/api/mobile/v1/media/[id]/complete/route',
        '/api/mobile/v1/media/[id]/process/route',
        '/api/mobile/v1/media/[id]/route',
        '/api/mobile/v1/media/route',
      ])
    expect(runtimeMarkerRoutes('MOBILE_CONVERSATION_PRIVATE_CATALOG_ENABLED')).toEqual(
      [
        ...conversationIntakeAppPaths,
        '/api/mobile/v1/media/[id]/complete/route',
        '/api/mobile/v1/media/[id]/process/route',
        '/api/mobile/v1/media/[id]/route',
        '/api/mobile/v1/media/route',
      ].sort(),
    )
    expect(runtimeExactStringRoutes('admit_conversation_versioned_media_intake_v2')).toEqual(
      [...conversationIntakeAppPaths].sort(),
    )
    expect(runtimeMarkerRoutes('close_conversation_media_v2')).toEqual([
      '/api/mobile/v1/media/[id]/complete/route',
      '/api/mobile/v1/media/[id]/process/route',
      '/api/mobile/v1/media/[id]/route',
    ])
    expect(runtimeExactStringRoutes('conversation.media.private.process.requested')).toEqual([
      '/api/mobile/v1/media/[id]/process/route',
    ])
    expect(runtimeExactStringRoutes('conversation.media-process.v2')).toEqual([
      '/api/mobile/v1/media/[id]/process/route',
    ])
    for (const marker of [
      'claim_conversation_media_owned_disposal_v2',
      'inspect_conversation_media_disposal_v2',
      'acknowledge_conversation_media_disposal_v2',
    ])
      expect(runtimeExactStringRoutes(marker)).toEqual(['/api/mobile/v1/media/[id]/route'])
    for (const marker of [
      'claim_conversation_media_disposal_batch_v2',
      'prepare_conversation_media_account_purge_v2',
    ])
      expect(runtimeExactStringRoutes(marker)).toEqual([])
    // R111 shares the unchanged purpose module with the two disposal entries.
    // Whole source certificates below bind their calls to the ticket gate, not
    // photo analysis; the new privileged RPC graph is restricted separately.
    const disposalRoutes = [
      '/api/mobile/v1/media/[id]/complete/route',
      '/api/mobile/v1/media/[id]/route',
    ]
    expect(runtimeMarkerRoutes('MOBILE_CONVERSATION_PHOTOS_ENABLED')).toEqual(
      [
        ...disposalRoutes,
        '/api/mobile/v1/media/[id]/process/route',
        '/api/mobile/v1/media/route',
      ].sort(),
    )
    for (const marker of [
      'claim_conversation_media_disposal',
      'inspect_conversation_media_payload_revocation',
      'acknowledge_conversation_media_expiry_sweep',
    ])
      expect(runtimeMarkerRoutes(marker)).toEqual(disposalRoutes.slice().sort())
    expect(runtimeMarkerRoutes('MOBILE_CONVERSATION_INTAKES_ENABLED')).toEqual(
      [
        ...conversationIntakeAppPaths,
        ...disposalRoutes,
        '/api/mobile/v1/media/[id]/process/route',
        '/api/mobile/v1/media/route',
      ].sort(),
    )
    // Exact reviewed R111 sources; no broad source/hash exemptions.
    for (const [file, hash] of [
      [
        'apps/admin/src/app/api/mobile/v1/media/[id]/route.ts',
        '1ddf7ae3a7c583a7328f219060c4b62e9c42d82fe595767282e6b415e0472058',
      ],
      [
        'apps/admin/src/app/api/mobile/v1/media/[id]/complete/route.ts',
        'b5067a20e3a88265e4365a61ee944f138701eb49e7e5744458d36e85bfc53c4b',
      ],
      [
        'apps/admin/src/lib/mobile-api/ordinary-media-disposal.ts',
        'e055f56af6b7db1f52301bf787424cd7f4a6c9d2659a118b7514d03c172a15b4',
      ],
      [
        'packages/core/src/conversation-media-revocation.ts',
        '4445c13dfb17813e42c555a598ccdffc939c34fa48c92587995000ef97eccb12',
      ],
      [
        'packages/core/package.json',
        '65017035408828386d6f7ff67f2ebbd472408bd0feecd01e11c74e56af84cbea',
      ],
    ])
      expect(
        createHash('sha256')
          .update(legacySource(file ?? ''))
          .digest('hex'),
      ).toBe(hash)
    // R106 intentionally adds the isolated issuance gate and SDK/ticket handoff.
    // Seal its complete source as well as the one changed physical route body.
    for (const [file, hash] of [
      [
        'apps/admin/src/app/api/mobile/v1/media/route.ts',
        '11d9c9291b8560b1df7c69a566f05619dc90124b463f98275be36912b1715925',
      ],
      [
        'apps/admin/src/lib/mobile-api/media-service.ts',
        '4ee5784c6795abf56f9e72034e58ca2200288dd0936525d2b6543158611e710c',
      ],
      [
        'apps/admin/src/lib/mobile-api/supabase-media.ts',
        '39495666e1e6866ab1eb6e3deee25d7f6ded58534153358b53c24b4eaf4d06ee',
      ],
      [
        'apps/admin/src/lib/mobile-api/ordinary-media-upload.ts',
        'a93401a85b521e39f2fc8d84254c592a21a1dffc89b8c06c97c8179170c415c2',
      ],
      [
        'apps/admin/src/lib/mobile-api/supabase-ordinary-media-upload.ts',
        '7057bda7cb70e34c335616fa448f32349e65ab1b29da4f550de2ebc8ad179c91',
      ],
      [
        'packages/core/src/conversation-photo-purpose.ts',
        '807949006001d7d235cb8c9bcdf017b4b0d0187c698824df29637ea9362080ca',
      ],
    ])
      expect(
        createHash('sha256')
          .update(legacySource(file ?? ''))
          .digest('hex'),
      ).toBe(hash)
    const entry = currentAppPathsManifest()['/api/mobile/v1/media/route']
    expect(entry).toBeTypeOf('string')
    const uploadEntry = resolve(buildRoot, 'server', entry ?? '')
    if (readFileSync(uploadEntry, 'utf8').includes('69499:'))
      certifyPhysicalModule(uploadEntry, '69499', [
        'f456e38b9523c617019f033f6a770eb2288fa43217b5a7238680b521bb595702',
      ])
    else if (readFileSync(uploadEntry, 'utf8').includes('19414:'))
      certifyPhysicalModule(uploadEntry, '19414', [
        '358f40b48ec781b778bb9ccffb002886326e472692a7c596dd5227664823680b',
      ])
    else
      certifyPhysicalModule(uploadEntry, '49777', [
        '8ca9a3e581e81d73eb2d620974c424df5333fc088d0ef345315aa19d467e0112',
      ])
    for (const [route, id, hash] of [
      [
        '/api/mobile/v1/media/[id]/route',
        '82635',
        '2142720a3775b78022d343173a090529e6215d164c1a49051af37d889adad139',
      ],
      [
        '/api/mobile/v1/media/[id]/complete/route',
        '49523',
        '8dc0e654afd13a863be5a9bddb9fb0a7b61c1a29254208c428c3f10feeb4a7e6',
      ],
    ]) {
      const target = currentAppPathsManifest()[route ?? '']
      expect(target).toBeTypeOf('string')
      const file = resolve(buildRoot, 'server', target ?? '')
      if (readFileSync(file, 'utf8').includes('77344:')) {
        certifyPhysicalModule(
          file,
          '77344',
          ['9837023bab44ba7527434737f7b19d4d9f5f1acd80ab224af49470476e8fd2e7'],
          certifyOwnedMediaBodyR174,
        )
        certifyPhysicalModule(file, '72262', [
          'c50d3d95cbb616ce76dd8d84d9312750bdd67047b88fdb489e12f94a8deaf1e0',
        ])
      } else if (readFileSync(file, 'utf8').includes('72262:')) {
        certifyPhysicalModule(
          file,
          id ?? '',
          [
            route === '/api/mobile/v1/media/[id]/route'
              ? '14150a04c5bc2a47b5ef13db44bb5b2d70381a7880681ae3f6dae09facdf6c94'
              : '3f32995297bba5cb0b17ede719a874dedafe9d6fd5a2fe1805be665d8997fcf6',
          ],
          certifyOwnedMediaBodyR171,
        )
        certifyPhysicalModule(file, '72262', [
          'c50d3d95cbb616ce76dd8d84d9312750bdd67047b88fdb489e12f94a8deaf1e0',
        ])
      } else certifyPhysicalModule(file, id ?? '', [hash ?? ''], restoreMediaFactoryLinkR170)
      // Complete neutral revocation primitive + real SDK adapter, with no
      // worker import, is the same closed body in these two entries only.
      certifyPhysicalModule(file, '2464', [
        '947188b98e60791650095e03225fc49cbc290e63a72757e59eec21fcaecefa75',
      ])
    }
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
        names: ['getLocalDateString', 'getLocalDayUtcBounds'],
      },
      { path: 'zod', names: ['z'] },
      { path: './conversation-meal-journal-store', names: ['conversationJournalInstant'] },
      { path: './http', names: ['MobileApiError'] },
      { path: './idempotency', names: ['hashMobileRequest'] },
      {
        path: './owned-clinical-window',
        names: [
          'OwnedClinicalWindowScope',
          'nutritionWindowDates',
          'parseOwnedClinicalWindowScope',
        ],
      },
    ])
    const common = parse('owned-clinical-window.ts')
    expect(
      common.statements.filter(ts.isImportDeclaration).map((node) => ({
        path: (node.moduleSpecifier as ts.StringLiteral).text,
        names:
          node.importClause?.namedBindings && ts.isNamedImports(node.importClause.namedBindings)
            ? node.importClause.namedBindings.elements.map((item) => item.name.text).sort()
            : [],
      })),
    ).toEqual([
      { path: '@mpp/agent', names: ['addIsoDateDays', 'getLocalDayUtcBounds'] },
      { path: 'zod', names: ['z'] },
    ])
    const calls: ts.CallExpression[] = []
    const visit = (node: ts.Node) => {
      if (ts.isCallExpression(node)) calls.push(node)
      ts.forEachChild(node, visit)
    }
    visit(source)
    visit(common)
    expect(
      calls.filter(
        (node) => node.expression.getText(node.getSourceFile()) === 'conversationJournalInstant',
      ),
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
        .map((node) => node.expression.getText(node.getSourceFile()).replace(/\s+/g, ''))
        .sort(),
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

  test('keeps the compiled recorded-training reader inside its GET without registration or day-close writers', () => {
    const route = '/api/mobile/v1/training/window/route'
    expect(currentAppPathsManifest()[route]).toBe('app/api/mobile/v1/training/window/route.js')
    expect(runtimeMarkerRoutes('training.window.v1')).toEqual([route])
    for (const marker of [
      'capture_mobile_clinical_day_close',
      'apply_mobile_clinical_day_close',
      'commit_conversation_meal_item_edit',
      'undo_conversation_meal_registration',
      'commit_mobile_registration_feedback',
    ])
      expect(runtimeMarkerRoutes(marker)).not.toContain(route)
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
  ])('checks current96 and exact frozen93 inventory in the synthetic CLI with extra nutrition route=%s', (extraRoute) => {
    const appPaths = Object.fromEntries([
      ...sourceRecords().map(({ path }) => {
        const appPath = `/api/mobile/v1/${path.replace(/\.ts$/, '')}`
        return [appPath, `app${appPath}.js`]
      }),
      ...[...executionRouteFiles, ...completionTransports.keys(), ...journeySocialTransports.keys()].map((path) => {
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
        writeFileSync(
          resolve(dirname(script), 'training-completion-surface.mjs'),
          readFileSync(resolve(appRoot, 'scripts/training-completion-surface.mjs')),
        )
        writeFileSync(resolve(dirname(script), 'journey-social-surface.mjs'), readFileSync(resolve(appRoot, 'scripts/journey-social-surface.mjs')))
        symlinkSync(syntheticBuild, resolve(root, '.next'), 'dir')
        const result = spawnSync(process.execPath, [script], {
          encoding: 'utf8',
          timeout: 30_000,
        })
        expect(result.error).toBeUndefined()
        expect(result.status, result.stderr).toBe(extraRoute ? 1 : 0)
        expect(result.stdout).toContain(
          `BUILD_CURRENT_MOBILE_ROUTE_PATH_COUNT=${extraRoute ? 97 : 96}`,
        )
        expect(result.stdout).toContain(`BUILD_MOBILE_ROUTE_PATH_COUNT=${extraRoute ? 94 : 93}`)
        expect(result.stdout).toContain(`BUILD_ROUTE_PATH_COUNT=${extraRoute ? 95 : 94}`)
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
            'BUILD_MOBILE_ROUTE_PATH_STREAM_SHA256=22926ab33b91fc36dde1834843c56d38fb6b06fe00de0294fe79e54529ba3013',
          )
          expect(result.stdout).toContain(
            'BUILD_ROUTE_PATH_STREAM_SHA256=4ff0c3610291b53b1a8245597f673be4443dcace0b6aae86a819e63a3629c3ab',
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
  ])('rejects $name while the same 93 URL keys remain', ({
    expectedError,
    mutate,
    omittedTargets,
  }) => {
    const appPaths = mutate(currentAppPathsManifest())

    expect(Object.keys(appPaths)).toHaveLength(94)
    expect(() => withSyntheticBuild(appPaths, inspectBuildSurface, omittedTargets)).toThrow(
      expectedError,
    )
  })

  test.each([
    false,
    true,
  ])('detects duplicate bundle targets independently of manifest order (%s)', (reverse) => {
    const entries = Object.entries(currentAppPathsManifest()).sort(([a], [b]) => a.localeCompare(b))
    if (reverse) entries.reverse()
    const appPaths = Object.fromEntries(entries)
    appPaths['/api/mobile/v1/today/route'] = appPaths['/api/mobile/v1/me/route']
    expect(() => withSyntheticBuild(appPaths, inspectBuildSurface)).toThrow(
      /APP_PATH_BUNDLE_TARGET_DUPLICATE/,
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
    expect(currentMobileRoutes).toHaveLength(93)
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
    // conversation routes and the exact nutrition/training additions remain in every global forbidden scan.
    const allRoutes = currentMobileRoutes.filter(
      (route) =>
        route !== nutritionWindowAppPath &&
        route !== '/api/mobile/v1/training/window/route' &&
        !route.startsWith('/api/mobile/v1/conversation/'),
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
    // R106's actual HEAD baseline/current NFT comparison proves only17 edges
    // to the newly factored issuer chunk: six replace2339, eleven are additive.
    // Pin full physical code + exact consumers; project only those eleven for
    // historical counts. Raw global scans and current totals still include all.
    const ordinaryIssuerChunk = uniqueChunk([
      'prepare_conversation_media_upload',
      'register_conversation_media_upload',
      'ordinary_media_upload_unavailable',
    ])
    if (readFileSync(ordinaryIssuerChunk, 'utf8').includes('83201:')) {
      certifyExactSharedTable(ordinaryIssuerChunk, [
        ['83201', '0ed6623bafb670f6e71c132424f9807fe6f7ea0f30e562976cfa6613a3e3581a'],
      ])
      // Retain the full old compiler certificate and its exact reconstruction.
      const factory = certifyPhysicalModule(ordinaryIssuerChunk, '83201', [
        '0ed6623bafb670f6e71c132424f9807fe6f7ea0f30e562976cfa6613a3e3581a',
      ])
      const addition = '...b.ordinaryDisposals?{ordinaryDisposals:b.ordinaryDisposals}:{},'
      expect(factory.split(addition)).toHaveLength(2)
      expect(createHash('sha256').update(factory.replace(addition, '')).digest('hex')).toBe(
        '48a22f1ec3e0a816eb14e62793c70d5719a040bccd022583021dbb6c28577811',
      )
    } else if (readFileSync(ordinaryIssuerChunk, 'utf8').includes('22693:')) {
      // R173 extracts the same Inngest client constructor for the new event
      // producer. All three full modules and exact physical consumers are
      // certified; original factory/issuer source remains pinned above.
      certifyExactSharedTable(ordinaryIssuerChunk, [
        ['75005', '506e25555771cfc370edf36ab8b58b839b4f165f006f112660e639417314377a'],
        ['22693', 'a162d8f173a0244855f0651272172e33d64f462e343097a9cd97982065509bb1'],
        ['46337', 'a72746cec4b0cfb0daaf01e7bd495699990b7daeab0ff0ae36c630c382aa2496'],
      ])
    } else {
      // R170's second URL-parser consumer factors the SAME sealed issuer and
      // public factory into two modules. Pin the entire table, not a prefix or
      // module exemption. Their source hashes above remain the original ones.
      certifyExactSharedTable(ordinaryIssuerChunk, [
        ['75005', '506e25555771cfc370edf36ab8b58b839b4f165f006f112660e639417314377a'],
        ['97281', 'fb25c188fd7607bbddd51345ff737c21cd8596451cb8e00b6e07641540b141f6'],
      ])
    }
    const privateCatalog = uniqueChunk([
      'prepare_conversation_media_upload_v2',
      'claim_conversation_media_processing_v2',
    ])
    const privateParserId = readFileSync(privateCatalog, 'utf8').includes('63867:')
      ? '63867'
      : '86248'
    const privateCorePins: readonly (readonly [string, string])[] = readFileSync(
      privateCatalog,
      'utf8',
    ).includes('33413:')
      ? [
          ['33413', 'f1a60695a4dd1b066bd4191c00aa127b79db5ff86d6a6ae6ffd2b6bc8fdbfa06'],
          ['41485', '531f91864c8ccd0ee1503b3055f3e4aad94173314ee67c416ebb3c43b12f005a'],
        ]
      : [['8184', 'f0a7d67c29acabae8f1e15dd98b2b2d0296dd2c562ca4a50991f15a28e9eba72']]
    certifyExactSharedTable(privateCatalog, [
      ['18975', '19a5f8d0ee0d0ce97fdea1a8b499a8ac2993a3d7c5d19135f128dd57e779bc23'],
      ['36715', '022a8bd63f33d23df8b9f02947b3b05b8c3275dacd24f793e4228196456378f1'],
      ['61344', '4b71f9b6820568692cbe7a42d2ff7605dfcc80b962cb060b442500c85156d14d'],
      [privateParserId, '4a9a1600a8698bc89125fc32271a3b823506085f83b490db4ddb534089fc8916'],
      ['89164', '14f14635e834fe65206cd266f21a2b1c548b48a685e1a95dc94c16dbcf31f519'],
      ...privateCorePins,
      [
        '77576',
        privateParserId === '63867'
          ? 'a8fd4ec43e7887b9a028cbf89ba0bc668e6119a0bfc92a8f100a2cc76a3fe27b'
          : '5ce0c7686ec2b7a43dbabcdac472056addaa75460aff070783ca62e3018dd5d9',
      ],
    ])
    expect(chunkConsumers(privateCatalog)).toEqual([
      '/api/mobile/v1/media/[id]/complete/route',
      '/api/mobile/v1/media/[id]/process/route',
      '/api/mobile/v1/media/[id]/route',
      '/api/mobile/v1/media/route',
    ])
    const issuerReplacementRoutes = new Set([
      '/api/mobile/v1/me/route',
      '/api/mobile/v1/meal-drafts/route',
      '/api/mobile/v1/pending/route',
      '/api/mobile/v1/registrations/[id]/confirm/route',
      '/api/mobile/v1/registrations/[id]/route',
      '/api/mobile/v1/registrations/propose/route',
    ])
    const issuerAddedRoutes = new Set([
      '/api/mobile/v1/media/[id]/complete/route',
      '/api/mobile/v1/media/[id]/process/route',
      '/api/mobile/v1/media/[id]/route',
      '/api/mobile/v1/media/route',
      '/api/mobile/v1/onboarding/body-photos/[id]/complete/route',
      '/api/mobile/v1/onboarding/body-photos/consent/route',
      '/api/mobile/v1/onboarding/body-photos/route',
      '/api/mobile/v1/plan-drafts/[id]/confirm/route',
      '/api/mobile/v1/plan-drafts/[id]/route',
      '/api/mobile/v1/plan-drafts/route',
      '/api/mobile/v1/plan-imports/route',
    ])
    expect(issuerReplacementRoutes.size).toBe(6)
    expect(issuerAddedRoutes.size).toBe(11)
    expect(chunkConsumers(ordinaryIssuerChunk)).toEqual(
      [...issuerReplacementRoutes, ...issuerAddedRoutes].sort(),
    )
    // R111's new shared table adds precisely three NFT edges. The helpers
    // are now factored out of their old inline copies; all five modules are
    // closed here. Three are literal prior bodies. The media service changes
    // reconstruct the complete prior body after removing the two reviewed
    // disposal branches. The new 574-byte module contains only existing flags.
    const disposalSharedChunk = uniqueChunk([
      'MOBILE_CONVERSATION_PHOTOS_ENABLED',
      'media_disposal_unavailable',
      'media_in_use_by_plan_draft',
    ])
    // The existing byte-identical parser has the same two compiler allocation
    // choices already certified for the nutrition modules. Bind the entire
    // service body for each choice, then reverse its one loader link below.
    const disposalParserId = readFileSync(disposalSharedChunk, 'utf8').includes('63867:')
      ? '63867'
      : '86248'
    const disposalServiceHash =
      disposalParserId === '63867'
        ? 'a8fd4ec43e7887b9a028cbf89ba0bc668e6119a0bfc92a8f100a2cc76a3fe27b'
        : '5ce0c7686ec2b7a43dbabcdac472056addaa75460aff070783ca62e3018dd5d9'
    certifyExactSharedTable(disposalSharedChunk, [
      // R171 factors the private catalog and unchanged SDK constructor into
      // this same whole table. Both extra bodies and exact consumers are sealed.
      ...(disposalSharedChunk === privateCatalog
        ? [
            ...privateCorePins,
            ['36715', '022a8bd63f33d23df8b9f02947b3b05b8c3275dacd24f793e4228196456378f1'] as const,
          ]
        : []),
      ['18975', '19a5f8d0ee0d0ce97fdea1a8b499a8ac2993a3d7c5d19135f128dd57e779bc23'],
      ['61344', '4b71f9b6820568692cbe7a42d2ff7605dfcc80b962cb060b442500c85156d14d'],
      ['77576', disposalServiceHash],
      [disposalParserId, '4a9a1600a8698bc89125fc32271a3b823506085f83b490db4ddb534089fc8916'],
      ['89164', '14f14635e834fe65206cd266f21a2b1c548b48a685e1a95dc94c16dbcf31f519'],
    ])
    expect(chunkConsumers(disposalSharedChunk)).toEqual([
      '/api/mobile/v1/media/[id]/complete/route',
      '/api/mobile/v1/media/[id]/process/route',
      '/api/mobile/v1/media/[id]/route',
      '/api/mobile/v1/media/route',
    ])
    let priorService = certifyPhysicalModule(disposalSharedChunk, '77576', [disposalServiceHash])
    if (disposalParserId === '63867') {
      expect(priorService.split('c(63867)')).toHaveLength(2)
      priorService = priorService.replace('c(63867)', 'c(86248)')
      expect(createHash('sha256').update(priorService).digest('hex')).toBe(
        '5ce0c7686ec2b7a43dbabcdac472056addaa75460aff070783ca62e3018dd5d9',
      )
    }
    const mismatchInsertion =
      '.ordinaryDisposals&&["conversation_photo","audio_note"].includes(g.kind)?await a.ordinaryDisposals.dispose(g):(a'
    expect(priorService.split(mismatchInsertion)).toHaveLength(2)
    priorService = priorService.replace(mismatchInsertion, '')
    const deleteInsertion =
      'if(a.ordinaryDisposals&&["conversation_photo","audio_note"].includes(e.kind)){await a.ordinaryDisposals.dispose(e);let d=l(await a.repository.findOwned(b,c));if("deleted"!==d.status)throw new f.t0(503,"media_disposal_unavailable","Media deletion unavailable");return j(d)}'
    expect(priorService.split(deleteInsertion)).toHaveLength(2)
    priorService = priorService.replace(deleteInsertion, '')
    const closedMismatch = 'markUploadFailed(b,c,"metadata_mismatch"))'
    expect(priorService.split(closedMismatch)).toHaveLength(2)
    priorService = priorService.replace(closedMismatch, 'markUploadFailed(b,c,"metadata_mismatch")')
    expect(createHash('sha256').update(priorService).digest('hex')).toBe(
      'f1bae64338d545292a31d72af6e2b3d20f428fa2035b695667fdd12438c642bc',
    )
    const priorTargets = (route: string): string[] =>
      tracedTargets(route).filter(
        (target) =>
          target !== nextHttpSplit &&
          target !== disposalSharedChunk &&
          !purposeEdge(route, target) &&
          !(target === ordinaryIssuerChunk && issuerAddedRoutes.has(route)),
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
      [...new Set(allRoutes.flatMap((route) => tracedTargets(route)))]
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
        disposalSharedChunk,
      ].sort(),
    )
    // All75 keep8202 references. The verified duplicate is217 physical targets,
    // still216 logical identities; the webhook adds only its own manifest.
    const webhookRoute = '/api/webhooks/revenuecat/route'
    const mobileTargets = new Set(allRoutes.flatMap((route) => tracedTargets(route)))
    // R173 adds precisely the existing private-catalog chunk to process; its
    // exact four consumers and all seven complete modules are bound above.
    expect(
      allRoutes.reduce((sum, route) => sum + tracedTargets(route).length, 0) +
        absorbedReferences(allRoutes),
    ).toBe(8202 + 16 + 11 + 4)
    expect(mobileTargets.size + 1).toBe(219)
    expect(repositoryUniqueSize([...mobileTargets]) + 1).toBe(218)
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
    // R102 adds ordinary classified observations and refuses unsupported images.
    // Router/workout codec bodies are recertified in full; two other shared
    // modules remain byte-exact. No physical/global scan is bypassed.
    expect(
      createHash('sha256')
        .update(
          readFileSync(
            resolve(appRoot, '../admin/src/lib/mobile-api/conversation-intake-router.ts'),
          ),
        )
        .digest('hex'),
    ).toBe('d4a62d927c1f3fc8006f4c0701fff0163fb812a422a5833f64ccafb527a5faae')
    const intakeBodies = certifyExactSharedTable(
      intakeChunk,
      [
        ['34168', '5c180f5861365e95d2485fc2d0348dd3b1405695cbb1441dad80341cf593a67b'],
        ['47804', '5d69e37d38dfebebad9a617cc333686fdeee9e6797e6640d8c595b97f1b7d209'],
        ['50522', 'a5d450bd9b7267e8756ae2f7b5a6910ead5d90ff83fe073d39b7f6ad278b3633'],
        ...(readFileSync(intakeChunk, 'utf8').includes('32978:')
          ? [['32978', '921228c6a39061e494283bd41e527304958de5a19654e998855fd9d567adfe1f'] as const]
          : [
              ['6535', '2eef75ca30d2cfabb2e71e2e652c8b41d0b884572469eed6424484a5b45969f3'] as const,
            ]),
      ],
      restorePrivateMediaContractR168,
    )
    certifyIntakeMediaBridgeR102(intakeBodies.get('32978') ?? intakeBodies.get('6535') ?? '')
    // Full typed service code remains physically present, including dormant
    // writers. Journal3 invokes only read through its tested closed RPC port.
    certifySharedModule(
      workoutChunk,
      'reconcile_conversation_workout',
      // R140 full re-certification after shared current-scope extraction.
      // Old96 same-path baseline retained 4fccbc5a...; source bytes are
      // unchanged and BOTH replacement modules are pinned above.
      '21239d114e06d780ee4e5221fd60a783b3540a02209e36c0b687c64ea0bda359',
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
      [
        scopeChunk,
        [...commandRoutes, nutritionWindowAppPath, '/api/mobile/v1/training/window/route'].sort(),
      ],
      [replyChunk, replyRoutes],
      [publicEditChunk, editRoutes],
      [intakeChunk, intakeRoutes],
    ] as const)
      expect(chunkConsumers(chunk)).toEqual(routes)
    for (const [marker, routes] of [
      ['conversation_commands_unavailable', mealCommandConsumers],
      [
        'read_conversation_meal_journal_page',
        [...commandRoutes, nutritionWindowAppPath, '/api/mobile/v1/training/window/route'].sort(),
      ],
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
        [
          scopeChunk,
          [...commandRoutes, nutritionWindowAppPath, '/api/mobile/v1/training/window/route'],
        ],
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
      ...workoutRoutes.map((route) => [route, 118] as const),
      ...intakeRoutes.map((route) => [route, route === originsRoute ? 125 + 1 : 124 + 1] as const),
    ])
    // R102 adds only the providers package manifest on these four physical
    // traces through the pure image-result leaf. Pin it and independently keep
    // image execution off these routes; no extra JS/worker boundary is exempted.
    const ordinaryManifest = realpathSync(resolve(appRoot, '../../packages/providers/package.json'))
    expect(createHash('sha256').update(readFileSync(ordinaryManifest)).digest('hex')).toBe(
      '705df5b7b1aec5addc632e8caf0d013bd7f7d9c7a0376ce588148140d6cc7c98',
    )
    for (const route of [...workoutRoutes, nutritionWindowAppPath]) {
      expect(tracedTargets(route).filter((target) => target === ordinaryManifest)).toEqual([
        ordinaryManifest,
      ])
      expect(runtimeMarkerRoutes('analyzeConversationImage')).not.toContain(route)
    }
    expect([...currentCounts.keys()].sort()).toEqual(commandRoutes)
    for (const [route, count] of currentCounts)
      expect(tracedTargets(route), route).toHaveLength(count)
    const legacyTargets = new Set(
        [...allRoutes, webhookRoute].flatMap((route) => tracedTargets(route)),
      ),
      commandOnlyTargets = [...new Set(commandRoutes.flatMap((route) => tracedTargets(route)))]
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
    expect(legacyTargets.size).toBe(219) // R111: exactly one qualified shared target added
    expect(
      [...allRoutes, webhookRoute].reduce((sum, route) => sum + tracedTargets(route).length, 0) +
        absorbedReferences(allRoutes),
    ).toBe(8202 + 16 + 104 + 11 + 4)
    expect(tracedTargets(nutritionWindowAppPath)).toHaveLength(116)
    expect(tracedTargets('/api/mobile/v1/training/window/route')).toHaveLength(116)
    // T48 extracts the three unchanged read-page modules certified above into
    // one new regular file, reached exactly once by each of the two readers.
    // Preserve the complete pre-T48 totals and account only for those two edges.
    // T51 adds only the closed helper above:12 edges, one regular target.
    // Historical counts project that exact edge only; all raw scans include it.
    // The four separately sealed social routes add4*105 references and five
    // targets. Their entire raw graph remains in every global forbidden scan.
    expect(surface.nftReferenceCount - 4 * 105).toBe(
      8202 +
        104 -
        6 +
        3 * 121 +
        122 +
        3 * 123 +
        2 * 122 +
        3 * 118 +
        3 * 123 +
        116 +
        28 +
        1 +
        2 +
        12 +
        123 + // R93: exactly the new read-only origin route NFT edges.
        11 + // R106: exact newly factored issuer edges, independently pinned above.
        3 + // R111: closed five-module shared table, exact three media consumers.
        1 + // R173: same sealed private-catalog chunk, process is its fourth consumer.
        116 + // R118: exactly the new read-only training entry, independently bounded above.
        3 * 114 + // R136: original execution route traces remain exact.
        5 * 120, // R140: five explicit completion traces; all included in scans.
    )
    expect(surface.nftUniqueTargetCount - 5).toBe(217 + 15 + 7 + 1 + 1 + 1 + 1 + 1 + 1 + 1 + 4 + 6)
    expect(surface.nftRegularFileTargetCount - 5).toBe(215 + 15 + 7 + 1 + 1 + 1 + 1 + 1 + 1 + 1 + 4 + 6)
    expect(surface.nftDirectoryTargetCount).toBe(2)

    // The three new routes add exactly one fully certified shared chunk and
    // their three client-reference manifests. Every old raw graph is preserved
    // by the independent legacy checks above; ALL routes remain in global scans.
    const executionRoutes = [
      '/api/mobile/v1/training/execution/route',
      '/api/mobile/v1/training/execution/[sessionId]/route',
      '/api/mobile/v1/training/execution/commands/route',
    ]
    const executionChunks = semanticChunks([
      'MOBILE_TRAINING_EXECUTION_ENABLED',
      'training.execution-home.v1',
      'training.execution.start.v1',
    ])
    expect(executionChunks).toHaveLength(1)
    const executionChunk = executionChunks[0] ?? ''
    certifyExactSharedTable(executionChunk, [
      // R140 compiler extraction of the same five source-pinned modules.
      ['19521', 'c46d66b4179746bd8802a67e6c5ce569b51de781c352325bfe880f57417689e9'],
      // R146: complete new-server HTTP adapter wire and PT409 classifier;
      // original SQL and the three neighbouring execution modules stay pinned.
      ['70091', 'f62e14e3ea1167771f07f43c5db03d7e32773b0b2c48a1f3d075a3bfb34b9547'],
      ['88551', 'b559f2b47031c5be3cbcd27819010f548026f104945bac04a2df3bbb40f0a3b4'],
      ['93288', 'c592e7ebe24caf41c29cd98ad49e0c401416db555ca98261c64e7b53561d9588'],
    ])
    const sourcePins = {
      'training-execution-routes.ts':
        '69f1ad82de3147f9997daf2d7286936f71854dcbbd7ac9efb8b34d6d018fefea',
      'training-execution-runtime.ts':
        '50cf5e7771fb0cc8d765591071978e25c9cddf145e848d329e7abe0631e3ae40',
      'training-execution-kernel.ts':
        '71258be869c607366b756cf5ce4bf65318e59e41297a455dc28b60ca33919ce2',
      'training-execution-store.ts':
        'fc120c17e51b88bd5a2a6cf1589acb38ebf4d3fbadf4b0598653b708655cc905',
      'training-execution-instant.ts':
        '28046c38ed63533de67172c74b75c9f002801d52b217c9f4bf563960b061de82',
    }
    for (const [name, pin] of Object.entries(sourcePins))
      expect(
        createHash('sha256')
          .update(readFileSync(resolve(appRoot, '../admin/src/lib/mobile-api', name)))
          .digest('hex'),
      ).toBe(pin)
    for (const route of executionRoutes) expect(tracedTargets(route, true)).toHaveLength(114)
    const oldPhysicalTargets = new Set(
      [...Object.keys(currentAppPathsManifest())]
        .filter((route) => route.endsWith('/route'))
        .flatMap((route) => tracedTargets(route)),
    )
    const onlyExecutionTargets = [
      ...new Set(executionRoutes.flatMap((route) => tracedTargets(route, true))),
    ]
      .filter((target) => !oldPhysicalTargets.has(target))
      .sort()
    expect(onlyExecutionTargets).toEqual(
      [
        executionChunk,
        ...executionRoutes.map((route) =>
          realpathSync(
            resolve(buildRoot, 'server/app', `${route.slice(1)}_client-reference-manifest.js`),
          ),
        ),
      ].sort(),
    )

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
      let historicalFragment: string | undefined
      const inlineSelectorRoutes: string[] = []
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
        // R136 changes webpack factoring, not the selector or its callers.
        // Eligibility embeds the EXACT same complete module in its entry.
        // Certify the body before accounting for that one physical relocation;
        // do not invent an NFT edge to a shared chunk it no longer loads.
        const inlineRoute = '/api/mobile/v1/onboarding/eligibility/route'
        const inlineEntry = currentAppPathsManifest()[inlineRoute]
        expect(inlineEntry).toBeDefined()
        certifyPhysicalModule(resolve(buildRoot, 'server', inlineEntry ?? ''), '36431', [
          'b544bf4ddfa7a5a941baaa9527fc43835826b73036df3cfea287fe5541411547',
        ])
        expect(tracedTargets(inlineRoute)).not.toContain(chunk)
        inlineSelectorRoutes.push(inlineRoute)
        // The other five original selector-chunk modules remain byte-exact in
        // their own fragment; the pure selector moved into the calculation
        // chunk. Remove THIS fragment at the historical selector boundary,
        // and remove the calculation chunk once at its existing boundary.
        // Otherwise the same physical edge would be subtracted twice.
        historicalFragment = uniqueChunk([
          'Invalid clinical generation authority',
          'mobile_reevaluation_identity_invalid',
        ])
        certifyExactSharedTable(historicalFragment, [
          ['18975', 'e18d0b6d04c5e579801d94cb78b5b369ca915baadde89aa70f606d8dce7e7808'],
          ['7338', '69ad10295e9280fbbe81fc4180850664c502c3134cc83f415ad09f09d16f7788'],
          ['74546', 'bd9b97ece0f59cb6177967c4356911f1b03f02b8365deab09edddd2d83b99793'],
          ['75972', '71e754d42ef616311ff02338cc97e84f8ba11a13d428ffdb2775d21b245d1861'],
          ['99930', '85bdeef1541b3b11277af45c9ec7d27fad8d6041bbd9deac65a8cc638ef30f34'],
        ])
        certifyExactSharedTable(chunk, [
          ['36431', 'b544bf4ddfa7a5a941baaa9527fc43835826b73036df3cfea287fe5541411547'],
          ['83335', '9fe1bdf65ac4e6f3b7fae74d11d8d53ab87e46dd38f9a63a9b056e643df2858c'],
          ['84022', 'a5c019ba46a46f3bfad538e3a32b1580d053e5bc6a3a58b4ed281b218a27e5be'],
          ['97104', 'f78e1a125b6e1445f539948e5cbe3f155fb165bee2eb187728b3632432da2c14'],
        ])
        expect(
          chunkConsumers(historicalFragment).filter(
            (route) =>
              route !== nutritionWindowAppPath && route !== '/api/mobile/v1/training/window/route',
          ),
        ).toEqual([...edge.old, ...edge.added, ...commandRoutes].sort())
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
      expect(
        [
          ...chunkConsumers(chunk).filter(
            (route) =>
              route !== nutritionWindowAppPath && route !== '/api/mobile/v1/training/window/route',
          ),
          ...inlineSelectorRoutes,
        ].sort(),
      ).toEqual(
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
            // R111: same exact project flag gates only these two disposal entries;
            // their clinical-reader graph is unchanged and checked separately.
            '/api/mobile/v1/media/[id]/complete/route',
            // R173: same trusted upload policy now also bounds processing.
            '/api/mobile/v1/media/[id]/process/route',
            '/api/mobile/v1/media/[id]/route',
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
      for (const route of edge.old) removeHistoricalEdge(route, historicalFragment ?? chunk)
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
      [
        ...historyFeedbackRoutes,
        ...reviewRoutes,
        ...commandRoutes,
        nutritionWindowAppPath,
        '/api/mobile/v1/training/window/route',
      ].sort(),
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
    // R106 factors the media factory out of old2339. Its unchanged draft
    // module98163 now co-locates in an existing trace for five routes and is
    // inline in meal-drafts. The actual baseline comparison shows no added
    // draft edge. Prove all six complete bodies, including prior raw bytes.
    const inlineDraftRoute = '/api/mobile/v1/meal-drafts/route'
    expect(chunkConsumers(draftChunk)).toEqual(
      draftRoutes.filter((route) => route !== inlineDraftRoute),
    )
    const inlineDraftEntry = currentAppPathsManifest()[inlineDraftRoute]
    if (!inlineDraftEntry) throw new Error('Missing existing draft entry')
    for (const file of [draftChunk, resolve(buildRoot, 'server', inlineDraftEntry)]) {
      const body = certifyPhysicalModule(file, '98163', [
        '36a92c5c57d553e0046193480d1b34db62d1ddc8309ce2e31c577b954f39b172',
        '051bbb7642daacf8399d07c53a4e26b501db653607ac00cd0b79e448e26c2510',
      ])
      // The chunk has a local directive; the inline copy inherits the entry's
      // directive. certifyPhysicalModule requires strict mode for both forms.
      if (body.startsWith('(a,b,c)=>{"use strict";'))
        expect(body.split('(a,b,c)=>{"use strict";')).toHaveLength(2)
      expect(
        createHash('sha256')
          .update(body.replace('(a,b,c)=>{"use strict";', '(a,b,c)=>{'))
          .digest('hex'),
      ).toBe('051bbb7642daacf8399d07c53a4e26b501db653607ac00cd0b79e448e26c2510')
    }
    expect(
      historicalRoutes
        .filter((route) => route === inlineDraftRoute || tracedTargets(route).includes(draftChunk))
        .sort(),
    ).toEqual(draftRoutes)

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
    // The six replacement references now hold the factored issuer, while the
    // unchanged draft body is co-located/inline as proved above. Only that
    // exact six-route slot is projected from E2's original50 graph.
    expect(
      historicalRoutes
        .filter(
          (route) =>
            !Object.hasOwn(addedRoutes, route) &&
            physicalTargets(route).includes(ordinaryIssuerChunk),
        )
        .sort(),
    ).toEqual(draftRoutes)
    expect(baselineReferences + absorbedBaseline - draftRoutes.length).toBe(5320)
    expect([...baselineTargets].filter((target) => target !== ordinaryIssuerChunk).length + 1).toBe(
      175,
    )

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

// New execution bundles are checked as part of the COMPLETE graph. Historical
// tests above intentionally project their exact frozen93 paths, without changing
// any old hashes, forbidden-import checks or negative fixtures.
describe('current96 execution build extension', () => {
  test('builds all three required execution routes and scans their entire transitive graph', () => {
    const surface = inspectBuildSurface(buildRoot)
    expect(surface.mobileRoutePaths).toHaveLength(105)
    expect(surface.routePaths).toHaveLength(106)
    expect(surface.mobileRoutePaths.filter((path) => !completionBuildPaths.has(path) && !journeySocialBuildPaths.has(path))).toHaveLength(
      96,
    )
    for (const path of [...completionBuildPaths, ...journeySocialBuildPaths]) expect(surface.mobileRoutePaths).toContain(path)
    for (const path of [
      '/api/mobile/v1/training/execution',
      '/api/mobile/v1/training/execution/[sessionId]',
      '/api/mobile/v1/training/execution/commands',
    ])
      expect(surface.mobileRoutePaths).toContain(path)
    expect(surface.forbiddenWorkerBundleReferences).toEqual([])
    expect(surface.forbiddenWorkerTraceReferences).toEqual([])
    expect(surface.forbiddenAdministrativeBundleReferences).toEqual([])
    expect(surface.forbiddenAdministrativeTraceReferences).toEqual([])
  })
})
