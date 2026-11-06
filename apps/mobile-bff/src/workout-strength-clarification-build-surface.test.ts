import { createHash } from 'node:crypto'
import { readdirSync, readFileSync, realpathSync } from 'node:fs'
import { dirname, relative, resolve } from 'node:path'
import { fileURLToPath } from 'node:url'
import { describe, expect, it } from 'vitest'
import { currentClinicalRouteAdditions } from './current-clinical-route-inventory'

const root = resolve(dirname(fileURLToPath(import.meta.url)), '../.next/server')
function currentAppPaths(): Record<string, string> {
  return JSON.parse(readFileSync(resolve(root, 'app-paths-manifest.json'), 'utf8'))
}
const cache = new Map<string, string>()
const addition = 'workouts/[id]/strength-clarification/route.ts'
const intakeTransportAdditions = new Set([
  'conversation/intakes/route.ts',
  'conversation/intakes/[intakeId]/route.ts',
  'conversation/intakes/session/route.ts',
])
const workoutTransportAdditions = new Set([
  'conversation/workout-commands/[commandId]/route.ts',
  'conversation/workout-commands/route.ts',
  'conversation/workout-session/route.ts',
])
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
  return Object.entries(currentAppPaths())
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
  it('keeps all91 mirrored exports, exact3 neutral intakes and prior88/workout additions while preserving every historical stream', () => {
    const appRoot = resolve(root, '../..')
    const source = exportStream(resolve(appRoot, '../admin/src/app/api/mobile/v1'), false)
    const mirror = exportStream(resolve(appRoot, 'src/app/api/mobile/v1'), true)
    expect(source).toEqual(mirror)
    expect(
      source.find((record) => record.path === 'auth/password-recovery/route.ts')?.exports,
    ).toEqual(['GET', 'HEAD', 'POST', 'dynamic', 'maxDuration', 'runtime'])
    expect(source).toHaveLength(91)
    expect(
      createHash('sha256')
        .update(source.map((record) => `${record.path}\0${record.exports.join(',')}\n`).join(''))
        .digest('hex'),
    ).toBe('1aee269695cf61901f5ecb802e8509ae9004481024926043353d1f7cf32db9f7')
    expect(
      source.find((record) => record.path === 'conversation/commands/[commandId]/replies/route.ts')
        ?.exports,
    ).toEqual(['GET', 'POST', 'maxDuration', 'runtime'])
    const prior91 = source.map((record) =>
      record.path === 'conversation/commands/[commandId]/replies/route.ts'
        ? { ...record, exports: record.exports.filter((name) => name !== 'GET') }
        : record,
    )
    expect(
      createHash('sha256')
        .update(prior91.map((record) => `${record.path}\0${record.exports.join(',')}\n`).join(''))
        .digest('hex'),
    ).toBe('93200635df44342607fb57b71a1b623e1dbd1ff442f6fdbe5997a9f7fe81dd67')
    const prior88 = prior91.filter((record) => !intakeTransportAdditions.has(record.path))
    expect(prior88).toHaveLength(88)
    expect(
      createHash('sha256')
        .update(prior88.map((record) => `${record.path}\0${record.exports.join(',')}\n`).join(''))
        .digest('hex'),
    ).toBe('99623e7e5caf5d3b3df20eeb6bf840e6fb416f5e489498232a0c984a0a6e53b4')
    expect(source.filter((record) => workoutTransportAdditions.has(record.path))).toEqual([
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
    const prior85 = prior88.filter((record) => !workoutTransportAdditions.has(record.path))
    expect(prior85).toHaveLength(85)
    expect(
      createHash('sha256')
        .update(prior85.map((record) => `${record.path}\0${record.exports.join(',')}\n`).join(''))
        .digest('hex'),
    ).toBe('afb3a6182ad8e1335a24edeb3f2394f411ee6935f9994c1ecfb0c164079c3d12')
    expect(source.find((record) => record.path === 'nutrition/window/route.ts')).toEqual({
      path: 'nutrition/window/route.ts',
      exports: ['GET', 'dynamic', 'runtime'],
    })
    const prior84 = prior85.filter((record) => record.path !== 'nutrition/window/route.ts')
    expect(prior84).toHaveLength(84)
    expect(
      createHash('sha256')
        .update(prior84.map((record) => `${record.path}\0${record.exports.join(',')}\n`).join(''))
        .digest('hex'),
    ).toBe('092bd3ded789b200042cf29119e279e22d6900f8cdc86889108f28d2764673f3')
    const replies = new Set([
      'conversation/commands/[commandId]/replies/[replyId]/route.ts',
      'conversation/commands/[commandId]/replies/route.ts',
    ])
    const prior82 = prior84.filter((record) => !replies.has(record.path))
    expect(prior82).toHaveLength(82)
    expect(
      createHash('sha256')
        .update(prior82.map((record) => `${record.path}\0${record.exports.join(',')}\n`).join(''))
        .digest('hex'),
    ).toBe('1edcfecc752f7657306d9a4f852c9ff3b37f2770270441a3bb37972366957c98')
    const prior75 = prior84.filter((record) => !record.path.startsWith('conversation/'))
    expect(prior75).toHaveLength(75)
    expect(
      createHash('sha256')
        .update(prior75.map((record) => `${record.path}\0${record.exports.join(',')}\n`).join(''))
        .digest('hex'),
    ).toBe('109cdb03a29399358c586046a6f98aace5eb6628fed4f290e1ca05193cc1a0a1')
    const prior74 = prior75.filter((record) => record.path !== 'auth/password-recovery/route.ts')
    expect(prior74).toHaveLength(74)
    expect(
      createHash('sha256')
        .update(prior74.map((record) => `${record.path}\0${record.exports.join(',')}\n`).join(''))
        .digest('hex'),
    ).toBe('9c7daf99f0c9baab62f037d3d9301417c4a025283e863f44cd4dfab77588e485')
    expect(source.find((record) => record.path === addition)).toEqual({
      path: addition,
      exports: ['GET', 'POST', 'runtime'],
    })
    const additions = new Set<string>(currentClinicalRouteAdditions)
    const prior56 = prior74.filter((record) => !additions.has(record.path))
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
