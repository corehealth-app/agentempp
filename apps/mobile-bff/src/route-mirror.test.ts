import { spawnSync } from 'node:child_process'
import { createHash } from 'node:crypto'
import {
  existsSync,
  mkdirSync,
  mkdtempSync,
  readdirSync,
  readFileSync,
  rmSync,
  writeFileSync,
} from 'node:fs'
import { dirname, relative, resolve, sep } from 'node:path'
import { fileURLToPath } from 'node:url'
import { describe, expect, test } from 'vitest'

const testDirectory = dirname(fileURLToPath(import.meta.url))
const sourceRoot = resolve(testDirectory, '../../admin/src/app/api/mobile/v1')
const wrapperRoot = resolve(testDirectory, 'app/api/mobile/v1')

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
const nutritionWindowRoute = 'nutrition/window/route.ts'
const boundedConversationRoutes = new Set([
  'conversation/meal-commands/route.ts',
  ...addedReadEditRoutes,
  ...addedReplyRoutes,
])

interface RouteRecord {
  path: string
  exports: string[]
  sourcePath?: string
}

function walkFiles(root: string): string[] {
  if (!existsSync(root)) return []

  return readdirSync(root, { withFileTypes: true }).flatMap((entry) => {
    const path = resolve(root, entry.name)
    return entry.isDirectory() ? walkFiles(path) : [path]
  })
}

function sourceExports(source: string): string[] {
  return Array.from(
    source.matchAll(/^export\s+(?:const|async\s+function|function)\s+([A-Za-z_$][\w$]*)/gm),
    (match) => match[1],
  ).sort()
}

function sourceRecords(): RouteRecord[] {
  return walkFiles(sourceRoot)
    .filter((path) => path.endsWith(`${sep}route.ts`))
    .map((path) => ({
      path: relative(sourceRoot, path).split(sep).join('/'),
      exports: sourceExports(readFileSync(path, 'utf8')),
    }))
    .sort((left, right) => left.path.localeCompare(right.path, 'en'))
}

function wrapperRecords(): RouteRecord[] {
  return walkFiles(wrapperRoot)
    .filter((path) => path.endsWith(`${sep}route.ts`))
    .map((path) => {
      const relativePath = relative(wrapperRoot, path).split(sep).join('/')
      const wrapper = readFileSync(path, 'utf8')
      expect(wrapper).not.toMatch(/export\s+\*/)
      const statements = Array.from(
        wrapper.matchAll(/^export\s*\{\s*([^}]+?)\s*\}\s*from\s*['"]([^'"]+)['"]\s*;?\s*$/gm),
      )
      expect(statements, `single named re-export required in ${path}`).toHaveLength(1)
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
      expect(residue, `only static route config may accompany ${path}`).toBe('')

      return {
        path: relative(wrapperRoot, path).split(sep).join('/'),
        exports: [
          ...statement[1]
            .split(',')
            .map((name) => name.trim())
            .filter(Boolean),
          ...sourceExports(wrapper),
        ].sort(),
        sourcePath: statement[2],
      }
    })
    .sort((left, right) => left.path.localeCompare(right.path, 'en'))
}

function hashRecords(records: RouteRecord[]) {
  const canonicalStream = records
    .map((record) => `${record.path}\0${record.exports.join(',')}\n`)
    .join('')
  return createHash('sha256').update(canonicalStream).digest('hex')
}

function withUnexpectedAuthComposition<T>(
  replaceClarification: boolean,
  inspect: (script: string) => T,
): T {
  const root = mkdtempSync(resolve(testDirectory, '../.mobile-bff-mirror-scope-'))
  try {
    const script = resolve(root, 'apps/mobile-bff/scripts/verify-route-mirror.mjs')
    mkdirSync(dirname(script), { recursive: true })
    writeFileSync(
      script,
      readFileSync(resolve(testDirectory, '../scripts/verify-route-mirror.mjs')),
    )
    for (const [from, to] of [
      [sourceRoot, resolve(root, 'apps/admin/src/app/api/mobile/v1')],
      [wrapperRoot, resolve(root, 'apps/mobile-bff/src/app/api/mobile/v1')],
    ] as const) {
      for (const file of walkFiles(from).filter((path) => path.endsWith(`${sep}route.ts`))) {
        const target = resolve(to, relative(from, file))
        mkdirSync(dirname(target), { recursive: true })
        writeFileSync(target, readFileSync(file))
      }
      if (replaceClarification) {
        rmSync(resolve(to, 'workouts/[id]/strength-clarification/route.ts'))
      }
      const auth = resolve(to, 'auth/unapproved-recovery/route.ts')
      mkdirSync(dirname(auth), { recursive: true })
      writeFileSync(
        auth,
        from === sourceRoot
          ? [
              "export const runtime = 'nodejs'",
              "export const dynamic = 'force-dynamic'",
              'export const maxDuration = 30',
              'export function GET() {}',
              'export function HEAD() {}',
              'export function POST() {}',
            ].join('\n')
          : "export { GET, HEAD, POST, dynamic, maxDuration, runtime } from '@/app/api/mobile/v1/auth/unapproved-recovery/route'\n",
      )
    }
    return inspect(script)
  } finally {
    rmSync(root, { recursive: true, force: true })
  }
}

function withNutritionMutation<T>(
  mutation: 'method' | 'extra-route',
  inspect: (script: string) => T,
): T {
  const root = mkdtempSync(resolve(testDirectory, '../.mobile-bff-nutrition-scope-'))
  try {
    const script = resolve(root, 'apps/mobile-bff/scripts/verify-route-mirror.mjs')
    mkdirSync(dirname(script), { recursive: true })
    writeFileSync(
      script,
      readFileSync(resolve(testDirectory, '../scripts/verify-route-mirror.mjs')),
    )
    for (const [from, to] of [
      [sourceRoot, resolve(root, 'apps/admin/src/app/api/mobile/v1')],
      [wrapperRoot, resolve(root, 'apps/mobile-bff/src/app/api/mobile/v1')],
    ] as const) {
      for (const file of walkFiles(from).filter((path) => path.endsWith(`${sep}route.ts`))) {
        const target = resolve(to, relative(from, file))
        mkdirSync(dirname(target), { recursive: true })
        writeFileSync(target, readFileSync(file))
      }
      if (mutation === 'method') {
        const target = resolve(to, nutritionWindowRoute)
        writeFileSync(target, readFileSync(target, 'utf8').replace(/\bGET\b/g, 'POST'))
      } else {
        const target = resolve(to, 'nutrition/unapproved/route.ts')
        mkdirSync(dirname(target), { recursive: true })
        writeFileSync(
          target,
          from === sourceRoot
            ? "export const runtime = 'nodejs'\nexport function GET() {}\n"
            : "export { GET, runtime } from '@/app/api/mobile/v1/nutrition/unapproved/route'\n",
        )
      }
    }
    return inspect(script)
  } finally {
    rmSync(root, { recursive: true, force: true })
  }
}

describe('dedicated Mobile BFF wrapper mirror', () => {
  test('adds only the readonly nutrition GET while preserving all 84 prior exports', () => {
    for (const records of [sourceRecords(), wrapperRecords()]) {
      expect(records.find((record) => record.path === nutritionWindowRoute)).toMatchObject({
        path: nutritionWindowRoute,
        exports: ['GET', 'dynamic', 'runtime'],
      })
      const prior84 = records.filter((record) => record.path !== nutritionWindowRoute)
      expect(prior84).toHaveLength(84)
      expect(hashRecords(prior84)).toBe(
        '092bd3ded789b200042cf29119e279e22d6900f8cdc86889108f28d2764673f3',
      )
    }
  })

  test.each([
    'method',
    'extra-route',
  ] as const)('rejects an unapproved nutrition %s without excluding the nutrition namespace', (mutation) => {
    withNutritionMutation(mutation, (script) => {
      const result = spawnSync(process.execPath, [script], { encoding: 'utf8', timeout: 30_000 })
      expect(result.error).toBeUndefined()
      expect(result.status).toBe(1)
      for (const surface of ['SOURCE', 'WRAPPER']) {
        expect(result.stderr).toContain(`ROUTE_MIRROR_ERROR=${surface}_HASH:`)
        if (mutation === 'method') {
          expect(result.stderr).toContain(
            `ROUTE_MIRROR_ERROR=${surface}_NUTRITION_EXPORTS:["POST","dynamic","runtime"]`,
          )
          expect(result.stdout).toContain(`${surface}_PRIOR84_ROUTE_EXPORT_COUNT=84`)
          expect(result.stdout).toContain(
            `${surface}_PRIOR84_ROUTE_EXPORT_STREAM_SHA256=092bd3ded789b200042cf29119e279e22d6900f8cdc86889108f28d2764673f3`,
          )
        } else {
          expect(result.stderr).toContain(`ROUTE_MIRROR_ERROR=${surface}_COUNT:86`)
          expect(result.stderr).toContain(`ROUTE_MIRROR_ERROR=${surface}_PRIOR84_COUNT:85`)
          expect(result.stderr).toContain(`ROUTE_MIRROR_ERROR=${surface}_PRIOR84_HASH:`)
        }
      }
      expect(result.stdout).not.toContain('ROUTE_MIRROR_STATUS=VERIFIED')
    })
  })

  test('adds only password recovery while preserving every approved 74-route export', () => {
    const records = sourceRecords()
    expect(records.find((record) => record.path === 'auth/password-recovery/route.ts')).toEqual({
      path: 'auth/password-recovery/route.ts',
      exports: ['GET', 'HEAD', 'POST', 'dynamic', 'maxDuration', 'runtime'],
    })
    const legacy = records.filter(
      (record) => record.path !== nutritionWindowRoute && !record.path.startsWith('conversation/'),
    )
    expect(legacy).toHaveLength(75)
    expect(hashRecords(legacy)).toBe(
      '109cdb03a29399358c586046a6f98aace5eb6628fed4f290e1ca05193cc1a0a1',
    )
    const previous = legacy.filter((record) => record.path !== 'auth/password-recovery/route.ts')
    expect(previous).toHaveLength(74)
    expect(hashRecords(previous)).toBe(
      '9c7daf99f0c9baab62f037d3d9301417c4a025283e863f44cd4dfab77588e485',
    )
  })

  test('preserves all 78 previously approved route exports exactly', () => {
    for (const records of [sourceRecords(), wrapperRecords()]) {
      const previous = records.filter(
        (record) =>
          record.path !== nutritionWindowRoute &&
          !addedReadEditRoutes.has(record.path) &&
          !addedReplyRoutes.has(record.path),
      )
      expect(previous).toHaveLength(78)
      expect(hashRecords(previous)).toBe(
        '3ab0b1fdb146ab6a06846b5702cfa70a1a7b997d73b3235655ec248c32f68874',
      )
    }
  })

  test('preserves all 82 prior routes and adds only the two closed reply exports', () => {
    for (const records of [sourceRecords(), wrapperRecords()]) {
      const previous = records.filter(
        (record) => record.path !== nutritionWindowRoute && !addedReplyRoutes.has(record.path),
      )
      expect(previous).toHaveLength(82)
      expect(hashRecords(previous)).toBe(
        '1edcfecc752f7657306d9a4f852c9ff3b37f2770270441a3bb37972366957c98',
      )
      expect(
        records
          .filter((record) => addedReplyRoutes.has(record.path))
          .map(({ path, exports }) => ({ path, exports })),
      ).toEqual([
        {
          path: 'conversation/commands/[commandId]/replies/[replyId]/route.ts',
          exports: ['GET', 'maxDuration', 'runtime'],
        },
        {
          path: 'conversation/commands/[commandId]/replies/route.ts',
          exports: ['POST', 'maxDuration', 'runtime'],
        },
      ])
    }
  })

  test.each([
    {
      name: 'Unapproved Auth replacing clarification at the same count',
      replace: true,
      count: 84,
      hash: 'c3635c150461af36b4593ce6c2f7621e59a19a2e45482b50ad82f1f6c022cd2b',
      currentHash: '770a26fb2fd006344ae6b731550cf9c2bf24593093604d0309c8028ddb96627b',
    },
    {
      name: 'Unapproved Auth added alongside clarification',
      replace: false,
      count: 85,
      hash: '18329037e36d0abc3dc1cf713945338caffce15b37fd214fd50567484c3dcc91',
      currentHash: 'dc5e369c46fc5c31fb3814f3b76d9b4dd4f4f38bd8d20a3eeaaf143e6f246f96',
    },
  ])('rejects $name through the closed inventory', ({ replace, count, hash, currentHash }) => {
    withUnexpectedAuthComposition(replace, (script) => {
      const result = spawnSync(process.execPath, [script], { encoding: 'utf8', timeout: 30_000 })
      expect(result.error).toBeUndefined()
      expect(result.status).toBe(1)
      for (const surface of ['SOURCE', 'WRAPPER']) {
        expect(result.stdout).toContain(`${surface}_ROUTE_EXPORT_COUNT=${count + 1}`)
        expect(result.stdout).toContain(`${surface}_ROUTE_EXPORT_STREAM_SHA256=${currentHash}`)
        expect(result.stderr).toContain(`ROUTE_MIRROR_ERROR=${surface}_HASH:${currentHash}`)
        expect(result.stderr.includes(`ROUTE_MIRROR_ERROR=${surface}_COUNT:`)).toBe(!replace)
        expect(result.stdout).toContain(`${surface}_PRIOR84_ROUTE_EXPORT_COUNT=${count}`)
        expect(result.stdout).toContain(`${surface}_PRIOR84_ROUTE_EXPORT_STREAM_SHA256=${hash}`)
        expect(result.stderr).toContain(`ROUTE_MIRROR_ERROR=${surface}_PRIOR84_HASH:${hash}`)
      }
      expect(result.stdout).not.toContain('ROUTE_MIRROR_STATUS=VERIFIED')
    })
  })

  test('accepts the approved 85-route mirror with the readonly nutrition window in the CLI gate', () => {
    const registration = sourceRecords().find(
      (record) => record.path === 'registrations/[id]/route.ts',
    )
    expect(registration?.exports).toEqual(['DELETE', 'GET', 'PATCH', 'runtime'])

    const result = spawnSync(
      process.execPath,
      [resolve(testDirectory, '../scripts/verify-route-mirror.mjs')],
      { encoding: 'utf8', timeout: 30_000 },
    )

    expect(result.error).toBeUndefined()
    expect(result.status, result.stderr).toBe(0)
    expect(result.stdout).toContain('SOURCE_ROUTE_EXPORT_COUNT=85')
    expect(result.stdout).toContain('WRAPPER_ROUTE_EXPORT_COUNT=85')
    for (const surface of ['SOURCE', 'WRAPPER']) {
      expect(result.stdout).toContain(
        `${surface}_ROUTE_EXPORT_STREAM_SHA256=afb3a6182ad8e1335a24edeb3f2394f411ee6935f9994c1ecfb0c164079c3d12`,
      )
    }
    for (const surface of ['SOURCE', 'WRAPPER']) {
      expect(result.stdout).toContain(`${surface}_PRIOR_ROUTE_EXPORT_COUNT=78`)
      expect(result.stdout).toContain(
        `${surface}_PRIOR_ROUTE_EXPORT_STREAM_SHA256=3ab0b1fdb146ab6a06846b5702cfa70a1a7b997d73b3235655ec248c32f68874`,
      )
    }
    for (const surface of ['SOURCE', 'WRAPPER']) {
      expect(result.stdout).toContain(`${surface}_PRIOR82_ROUTE_EXPORT_COUNT=82`)
      expect(result.stdout).toContain(
        `${surface}_PRIOR82_ROUTE_EXPORT_STREAM_SHA256=1edcfecc752f7657306d9a4f852c9ff3b37f2770270441a3bb37972366957c98`,
      )
    }
    expect(result.stdout).toContain('ROUTE_MIRROR_STATUS=VERIFIED')
  })

  test('mirrors every frozen source route with one exact named handler re-export', () => {
    const sources = sourceRecords()
    const wrappers = wrapperRecords()

    console.info(`WRAPPER_ROUTE_EXPORT_COUNT=${wrappers.length}`)
    expect(wrappers, `expected 85 wrappers but observed ${wrappers.length}`).toHaveLength(85)

    expect(wrappers.map(({ path, exports }) => ({ path, exports }))).toEqual(sources)

    for (const wrapper of wrappers) {
      const sourceModule = wrapper.path.replace(/\.ts$/, '')
      expect(wrapper.sourcePath).toBe(`@/app/api/mobile/v1/${sourceModule}`)
    }

    const hash = hashRecords(wrappers)
    console.info(`WRAPPER_ROUTE_EXPORT_STREAM_SHA256=${hash}`)
    expect(hash).toBe('afb3a6182ad8e1335a24edeb3f2394f411ee6935f9994c1ecfb0c164079c3d12')
  })

  test.each([...boundedConversationRoutes])('declares bounded timeout locally for %s', (path) => {
    const wrapper = readFileSync(resolve(wrapperRoot, path), 'utf8')
    if (path === 'conversation/meal-commands/route.ts') {
      expect(wrapper).toContain("export const runtime = 'nodejs'")
    }
    expect(wrapper).toContain('export const maxDuration = 120')
    const config = JSON.parse(
      readFileSync(
        resolve(testDirectory, '../.next/server/functions-config-manifest.json'),
        'utf8',
      ),
    )
    expect(config.functions[`/api/mobile/v1/${path.replace(/\/route\.ts$/, '')}`].maxDuration).toBe(
      120,
    )
  })
  test('declares Flow route runtime limits locally for Next static analysis', () => {
    const flowWrapper = readFileSync(resolve(wrapperRoot, 'flow/chat/route.ts'), 'utf8')

    expect(flowWrapper).toContain("export const runtime = 'nodejs'")
    expect(flowWrapper).toContain('export const maxDuration = 300')
    expect(flowWrapper).toContain("export { GET, POST } from '@/app/api/mobile/v1/flow/chat/route'")
  })

  test('publishes the recovery timeout as 45 seconds in the actual Next build', () => {
    const config = JSON.parse(
      readFileSync(
        resolve(testDirectory, '../.next/server/functions-config-manifest.json'),
        'utf8',
      ),
    ) as { functions: Record<string, { maxDuration?: number }> }
    expect(config.functions['/api/mobile/v1/auth/password-recovery']?.maxDuration).toBe(45)
    expect(config.functions['/api/mobile/v1/flow/chat']?.maxDuration).toBe(300)
  })
})
