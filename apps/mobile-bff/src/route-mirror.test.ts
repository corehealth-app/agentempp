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
        .replace(/^export\s+const\s+maxDuration\s*=\s*300\s*;?\s*$/gm, '')
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

function withAuthComposition<T>(replaceClarification: boolean, inspect: (script: string) => T): T {
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
      const auth = resolve(to, 'auth/password-recovery/route.ts')
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
          : "export { GET, HEAD, POST, dynamic, maxDuration, runtime } from '@/app/api/mobile/v1/auth/password-recovery/route'\n",
      )
    }
    return inspect(script)
  } finally {
    rmSync(root, { recursive: true, force: true })
  }
}

describe('dedicated Mobile BFF wrapper mirror', () => {
  test.each([
    {
      name: 'Auth replacing clarification at the same count',
      replace: true,
      count: 56,
      hash: '44bf6943744d6aa311687a4a11426a42e15d0b09c1bcd69122268c5049a58e1f',
    },
    {
      name: 'Auth added alongside clarification',
      replace: false,
      count: 57,
      hash: 'f56ca450cf29bfd02ba9e06c06876e0e0c475444e461aacc3b218fc31c6d587d',
    },
  ])('rejects $name through the closed inventory', ({ replace, count, hash }) => {
    withAuthComposition(replace, (script) => {
      const result = spawnSync(process.execPath, [script], { encoding: 'utf8', timeout: 30_000 })
      expect(result.error).toBeUndefined()
      expect(result.status).toBe(1)
      for (const surface of ['SOURCE', 'WRAPPER']) {
        expect(result.stdout).toContain(`${surface}_ROUTE_EXPORT_COUNT=${count}`)
        expect(result.stdout).toContain(`${surface}_ROUTE_EXPORT_STREAM_SHA256=${hash}`)
        expect(result.stderr).toContain(`ROUTE_MIRROR_ERROR=${surface}_HASH:${hash}`)
        expect(result.stderr.includes(`ROUTE_MIRROR_ERROR=${surface}_COUNT:`)).toBe(!replace)
      }
      expect(result.stdout).not.toContain('ROUTE_MIRROR_STATUS=VERIFIED')
    })
  })

  test('accepts the approved 56-route mirror with the owned clarification in the CLI gate', () => {
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
    expect(result.stdout).toContain('SOURCE_ROUTE_EXPORT_COUNT=56')
    expect(result.stdout).toContain('WRAPPER_ROUTE_EXPORT_COUNT=56')
    for (const surface of ['SOURCE', 'WRAPPER']) {
      expect(result.stdout).toContain(
        `${surface}_ROUTE_EXPORT_STREAM_SHA256=b88a27d2d694fb0ca539b9075c369978956d51aa25427b52da46983919b7d0e8`,
      )
    }
    expect(result.stdout).toContain('ROUTE_MIRROR_STATUS=VERIFIED')
  })

  test('mirrors every frozen source route with one exact named handler re-export', () => {
    const sources = sourceRecords()
    const wrappers = wrapperRecords()

    console.info(`WRAPPER_ROUTE_EXPORT_COUNT=${wrappers.length}`)
    expect(wrappers, `expected 56 wrappers but observed ${wrappers.length}`).toHaveLength(56)

    expect(wrappers.map(({ path, exports }) => ({ path, exports }))).toEqual(sources)

    for (const wrapper of wrappers) {
      const sourceModule = wrapper.path.replace(/\.ts$/, '')
      expect(wrapper.sourcePath).toBe(`@/app/api/mobile/v1/${sourceModule}`)
    }

    const hash = hashRecords(wrappers)
    console.info(`WRAPPER_ROUTE_EXPORT_STREAM_SHA256=${hash}`)
    expect(hash).toBe('b88a27d2d694fb0ca539b9075c369978956d51aa25427b52da46983919b7d0e8')
  })

  test('declares Flow route runtime limits locally for Next static analysis', () => {
    const flowWrapper = readFileSync(resolve(wrapperRoot, 'flow/chat/route.ts'), 'utf8')

    expect(flowWrapper).toContain("export const runtime = 'nodejs'")
    expect(flowWrapper).toContain('export const maxDuration = 300')
    expect(flowWrapper).toContain("export { GET, POST } from '@/app/api/mobile/v1/flow/chat/route'")
  })
})
