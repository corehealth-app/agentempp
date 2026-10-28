import { createHash } from 'node:crypto'
import { readdirSync, readFileSync, realpathSync } from 'node:fs'
import { dirname, relative, resolve } from 'node:path'
import { fileURLToPath } from 'node:url'
import { describe, expect, it } from 'vitest'
import { currentClinicalRouteAdditions } from './current-clinical-route-inventory'

const root = resolve(dirname(fileURLToPath(import.meta.url)), '../.next/server')
const paths: Record<string, string> = JSON.parse(
  readFileSync(resolve(root, 'app-paths-manifest.json'), 'utf8'),
)
const cache = new Map<string, string>()
const addition = 'workouts/[id]/strength-clarification/route.ts'
function routeFiles(root: string): string[] {
  return readdirSync(root, { withFileTypes: true }).flatMap((entry) => {
    const path = resolve(root, entry.name)
    return entry.isDirectory() ? routeFiles(path) : entry.name === 'route.ts' ? [path] : []
  })
}
function exportStream(root: string, wrapper: boolean) {
  return routeFiles(root)
    .map((file) => {
      const source = readFileSync(file, 'utf8')
      const imports = wrapper
        ? Array.from(
            source.matchAll(/^export\s*\{\s*([^}]+?)\s*\}\s*from\s*['"][^'"]+['"]/gm),
          ).flatMap((match) =>
            match[1]
              .split(',')
              .map((name) => name.trim())
              .filter(Boolean),
          )
        : []
      const declarations = Array.from(
        source.matchAll(/^export\s+(?:const|async\s+function|function)\s+([A-Za-z_$][\w$]*)/gm),
        (match) => match[1],
      )
      const names = [...declarations, ...imports]
      return { path: relative(root, file), exports: names.sort() }
    })
    .sort((a, b) => a.path.localeCompare(b.path, 'en'))
}
function routesReaching(marker: string) {
  return Object.entries(paths)
    .filter(([route, target]) => {
      if (!route.startsWith('/api/mobile/v1/')) return false
      const entry = resolve(root, target)
      const trace: { files: string[] } = JSON.parse(readFileSync(`${entry}.nft.json`, 'utf8'))
      return [entry, ...trace.files.map((file) => resolve(dirname(entry), file))].some((file) => {
        if (!/\.[cm]?js$/.test(file)) return false
        const physical = realpathSync(file)
        let source = cache.get(physical)
        if (source === undefined) {
          source = readFileSync(physical, 'utf8')
          cache.set(physical, source)
        }
        return source.includes(marker)
      })
    })
    .map(([route]) => route)
    .sort()
}

describe('current-authority clarification in the fresh mobile server build', () => {
  it('adds exactly one mirrored route while preserving the prior 54-route export stream and the independent completion-intent addition', () => {
    const appRoot = resolve(root, '../..')
    const source = exportStream(resolve(appRoot, '../admin/src/app/api/mobile/v1'), false)
    const mirror = exportStream(resolve(appRoot, 'src/app/api/mobile/v1'), true)
    expect(source).toEqual(mirror)
    expect(source.some((record) => record.path === 'auth/password-recovery/route.ts')).toBe(false)
    expect(source).toHaveLength(74)
    expect(source.find((record) => record.path === addition)).toEqual({
      path: addition,
      exports: ['GET', 'POST', 'runtime'],
    })
    const additions = new Set<string>(currentClinicalRouteAdditions)
    const prior56 = source.filter((record) => !additions.has(record.path))
    expect(prior56).toHaveLength(56)
    expect(
      createHash('sha256')
        .update(prior56.map((record) => `${record.path}\0${record.exports.join(',')}\n`).join(''))
        .digest('hex'),
    ).toBe('b88a27d2d694fb0ca539b9075c369978956d51aa25427b52da46983919b7d0e8')
    const beforeIntents = prior56.filter(
      (record) => record.path !== 'onboarding/completion-intent/route.ts',
    )
    expect(beforeIntents).toHaveLength(55)
    const previousStream = beforeIntents
      .map((record) => `${record.path}\0${record.exports.join(',')}\n`)
      .join('')
    expect(createHash('sha256').update(previousStream).digest('hex')).toBe(
      '96da71b91e2f8f7a730c98b2388128fdd840846437a4bbcf238dd8dd2fb4a62d',
    )
    const old = beforeIntents.filter((record) => record.path !== addition)
    expect(old).toHaveLength(54)
    const stream = old.map((record) => `${record.path}\0${record.exports.join(',')}\n`).join('')
    expect(createHash('sha256').update(stream).digest('hex')).toBe(
      '0f076fc83228e8742e107ba4bb9631019b6d1e6edc74fbd36039c574b228c1a3',
    )
    expect(readFileSync(resolve(appRoot, 'src/app/api/mobile/v1', addition), 'utf8').trim()).toBe(
      "export { GET, POST, runtime } from '@/app/api/mobile/v1/workouts/[id]/strength-clarification/route'",
    )
  })
  it.each([
    'get_mobile_workout_strength_clarification',
    'answer_mobile_workout_strength_clarification',
  ])('keeps %s reachable only in the dedicated route, including traced chunks', (marker) => {
    expect(routesReaching(marker)).toEqual([
      '/api/mobile/v1/workouts/[id]/strength-clarification/route',
    ])
  })
  it.each([
    'resolve_confirmed_workout_strength_capture',
    'answer_confirmed_workout_strength',
    'prepare_workout_strength_calendar_scope',
    'get_confirmed_workouts_for_strength_week',
  ])('does not include old repository factory RPC %s in any route', (marker) => {
    expect(routesReaching(marker)).toEqual([])
  })
})
