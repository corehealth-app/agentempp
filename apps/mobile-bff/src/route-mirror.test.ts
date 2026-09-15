import { createHash } from 'node:crypto'
import { existsSync, readdirSync, readFileSync } from 'node:fs'
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

describe('dedicated Mobile BFF wrapper mirror', () => {
  test('mirrors every frozen source route with one exact named handler re-export', () => {
    const sources = sourceRecords()
    const wrappers = wrapperRecords()

    console.info(`WRAPPER_ROUTE_EXPORT_COUNT=${wrappers.length}`)
    expect(wrappers, `expected 41 wrappers but observed ${wrappers.length}`).toHaveLength(41)

    expect(wrappers.map(({ path, exports }) => ({ path, exports }))).toEqual(sources)

    for (const wrapper of wrappers) {
      const sourceModule = wrapper.path.replace(/\.ts$/, '')
      expect(wrapper.sourcePath).toBe(`@/app/api/mobile/v1/${sourceModule}`)
    }

    const hash = hashRecords(wrappers)
    console.info(`WRAPPER_ROUTE_EXPORT_STREAM_SHA256=${hash}`)
    expect(hash).toBe('41eef017849c30cda6ee211fe0b71ce3003a2dd1872ecbc0593f6f9340c9ece1')
  })

  test('declares Flow route runtime limits locally for Next static analysis', () => {
    const flowWrapper = readFileSync(resolve(wrapperRoot, 'flow/chat/route.ts'), 'utf8')

    expect(flowWrapper).toContain("export const runtime = 'nodejs'")
    expect(flowWrapper).toContain('export const maxDuration = 300')
    expect(flowWrapper).toContain("export { GET, POST } from '@/app/api/mobile/v1/flow/chat/route'")
  })
})
