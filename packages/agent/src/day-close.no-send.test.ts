/**
 * Static proof that the day close for app accounts cannot send anything.
 *
 * WHY A STATIC TEST. The close runs on the test environment precisely because
 * the worker there must not be able to send a WhatsApp reminder. The mobile
 * BFF's build guards are separate scripts run by hand at deploy time, they do
 * not look inside `@mpp/agent`, and their marker list has no send function.
 * So the claim "this code only talks to the database it is handed" is checked
 * here, on the source, on every test run:
 *  - packages/agent/src/day-close.ts and everything it imports by relative
 *    path;
 *  - the mobile API hook (apps/admin/src/lib/mobile-api/day-close-on-request.ts);
 *  - the operator script (scripts/close-open-days.ts).
 *
 * The literals the mobile BFF build forbids are read from its verify script,
 * not copied here.
 */
import { existsSync, readFileSync } from 'node:fs'
import { dirname, resolve } from 'node:path'
import { fileURLToPath } from 'node:url'
import { describe, expect, it } from 'vitest'

const here = dirname(fileURLToPath(import.meta.url))
const repository = resolve(here, '../../..')
const DAY_CLOSE = resolve(here, 'day-close.ts')
const HOOK = resolve(repository, 'apps/admin/src/lib/mobile-api/day-close-on-request.ts')
const SCRIPT = resolve(repository, 'scripts/close-open-days.ts')
const BFF_GUARD = resolve(repository, 'apps/mobile-bff/scripts/verify-build-surface.mjs')

interface ImportLine {
  specifier: string
  typeOnly: boolean
}

function imports(source: string): ImportLine[] {
  const found: ImportLine[] = []
  const pattern = /^(import|export)\s+(type\s+)?[^'"]*?from\s+['"]([^'"]+)['"]/gms
  for (const match of source.matchAll(pattern)) {
    found.push({ specifier: match[3] as string, typeOnly: Boolean(match[2]) })
  }
  // Side-effect and dynamic imports would bypass the list above.
  expect(source).not.toMatch(/^import\s+['"]/m)
  expect(source).not.toMatch(/\bimport\s*\(/)
  expect(source).not.toMatch(/\brequire\s*\(/)
  return found
}

function resolveRelative(importer: string, specifier: string): string {
  const path = resolve(dirname(importer), specifier.replace(/\.js$/, '.ts'))
  return existsSync(path) ? path : `${path}.ts`
}

/** The file and every file it reaches through relative imports. */
function closure(entry: string): string[] {
  const seen = new Set<string>()
  const queue = [entry]
  while (queue.length > 0) {
    const file = queue.shift() as string
    if (seen.has(file)) continue
    seen.add(file)
    for (const { specifier } of imports(readFileSync(file, 'utf8'))) {
      if (specifier.startsWith('.')) queue.push(resolveRelative(file, specifier))
    }
  }
  return [...seen].sort()
}

function forbiddenBuildLiterals(): string[] {
  const guard = readFileSync(BFF_GUARD, 'utf8')
  const literals: string[] = []
  for (const name of ['workerBundleMarkers', 'administrativeBundleMarkers']) {
    const block = guard.match(new RegExp(`const ${name} = \\[([^\\]]*)\\]`))
    if (!block) throw new Error(`${name} not found in the BFF build guard`)
    literals.push(...Array.from((block[1] as string).matchAll(/'([^']+)'/g), (m) => m[1] as string))
  }
  return literals
}

/** Anything that could reach a person or another system. */
const SEND_PATTERNS: Array<[string, RegExp]> = [
  ['the event bus', /inngest/i],
  ['the provider package', /@mpp\/providers/],
  ['a provider factory', /createMessagingProvider|sendHumanized|MessagingProvider/],
  ['an HTTP call', /\bfetch\s*\(/],
  ['an HTTP client', /\b(?:axios|undici|XMLHttpRequest|node:https?)\b/],
  ['the event dispatch RPC', /dispatch_\w*event/i],
  ['a model call', /openrouter|\bllm\s*\.|\.complete\s*\(/i],
  ['a push or mail sender', /\b(?:sendPush|sendMail|apns|nodemailer)\b/i],
]

describe('packages/agent/src/day-close.ts', () => {
  const files = closure(DAY_CLOSE)

  it('reaches only its four read helpers', () => {
    expect(files.map((file) => file.slice(here.length + 1))).toEqual([
      'calc-config-loader.ts',
      'calc-targets.ts',
      'day-close.ts',
      'meal-patterns.ts',
      'timezone-utils.ts',
    ])
  })

  it('imports nothing outside @mpp/core and the TYPES of @mpp/db, in the whole closure', () => {
    for (const file of files) {
      for (const line of imports(readFileSync(file, 'utf8'))) {
        if (line.specifier.startsWith('.')) continue
        expect(['@mpp/core', '@mpp/db'], `${file} imports ${line.specifier}`).toContain(
          line.specifier,
        )
        if (line.specifier === '@mpp/db') {
          expect(line.typeOnly, `${file} imports a value from @mpp/db`).toBe(true)
        }
      }
    }
  })

  it('@mpp/core itself depends on no workspace package and no HTTP or event library', () => {
    const manifest = JSON.parse(
      readFileSync(resolve(repository, 'packages/core/package.json'), 'utf8'),
    ) as { dependencies?: Record<string, string> }
    const dependencies = Object.keys(manifest.dependencies ?? {})
    expect(dependencies.length).toBeGreaterThan(0)
    for (const dependency of dependencies) {
      expect(dependency).not.toMatch(
        /^@mpp\/|^@supabase\/|inngest|openai|anthropic|axios|undici|node-fetch|\bgot\b|twilio|nodemailer/,
      )
    }
  })

  it.each(SEND_PATTERNS)('has no trace of %s, in the whole closure', (_name, pattern) => {
    for (const file of files) {
      expect(readFileSync(file, 'utf8'), file).not.toMatch(pattern)
    }
  })

  it('reads no environment variable and names no URL', () => {
    for (const file of files) {
      const source = readFileSync(file, 'utf8')
      expect(source, file).not.toMatch(/process\.env/)
      expect(source, file).not.toMatch(/https?:\/\//)
    }
  })

  it('calls exactly two RPCs, the two the production closer calls', () => {
    const source = readFileSync(DAY_CLOSE, 'utf8')
    const called = Array.from(source.matchAll(/\.rpc\(\s*'([^']+)'/g), (match) => match[1]).sort()
    expect(called).toEqual(['advance_reevaluation_schedule', 'finalize_daily_close_atomic'])
    for (const file of files.filter((candidate) => candidate !== DAY_CLOSE)) {
      expect(readFileSync(file, 'utf8'), file).not.toMatch(/\.rpc\(/)
    }
  })

  it('writes to three tables only: the day, the progress and the telemetry', () => {
    const source = readFileSync(DAY_CLOSE, 'utf8')
    const written = new Set<string>()
    const pattern = /\.from\('(\w+)'\)(?:\s*\/\/[^\n]*\n|\s)*\.(insert|update|upsert|delete)\(/g
    for (const match of source.matchAll(pattern)) written.add(match[1] as string)
    expect([...written].sort()).toEqual(['daily_snapshots', 'product_events', 'user_progress'])
    expect(source).not.toMatch(/\.delete\(/)
    expect(source).not.toMatch(/\.from\('messages'\)(?:\s)*\.(insert|update|upsert)/)
  })

  it('carries none of the literals the mobile BFF build forbids, not even in a comment', () => {
    const literals = forbiddenBuildLiterals()
    expect(literals.length).toBeGreaterThan(10)
    for (const file of files) {
      const source = readFileSync(file, 'utf8')
      for (const literal of literals) expect(source, `${file}: ${literal}`).not.toContain(literal)
    }
  })
})

describe('apps/admin/src/lib/mobile-api/day-close-on-request.ts (the hook)', () => {
  const source = readFileSync(HOOK, 'utf8')

  it('imports the close function from @mpp/agent and, beyond that, only the route wrapper', () => {
    expect(imports(source)).toEqual([
      { specifier: '@mpp/agent', typeOnly: false },
      { specifier: './route', typeOnly: true },
      { specifier: './route', typeOnly: false },
    ])
    expect(source).toMatch(/import \{ closePastOpenDays \} from '@mpp\/agent'/)
    expect(source).toMatch(/import \{ safeUnexpectedErrorName \} from '.\/route'/)
  })

  it.each(SEND_PATTERNS)('has no trace of %s', (_name, pattern) => {
    expect(source).not.toMatch(pattern)
  })

  it('makes no RPC call and one table read of its own (the account)', () => {
    expect(source).not.toMatch(/\.rpc\(/)
    expect(Array.from(source.matchAll(/\.from\('(\w+)'\)/g), (match) => match[1])).toEqual([
      'users',
    ])
    expect(source).not.toMatch(/\.(insert|update|upsert|delete)\(/)
  })

  it('reads exactly three environment variables', () => {
    const read = Array.from(source.matchAll(/process\.env\.(\w+)/g), (match) => match[1]).sort()
    expect(read).toEqual([
      'MOBILE_DAY_CLOSE_FROM',
      'MOBILE_DAY_CLOSE_PROJECT_REF',
      'NEXT_PUBLIC_SUPABASE_URL',
    ])
  })

  it('carries none of the literals the mobile BFF build forbids', () => {
    for (const literal of forbiddenBuildLiterals()) expect(source).not.toContain(literal)
  })
})

describe('scripts/close-open-days.ts (the operator script)', () => {
  const source = readFileSync(SCRIPT, 'utf8')

  it('imports the database client factory, the close function and two node built-ins', () => {
    expect(
      imports(source)
        .map((line) => line.specifier)
        .sort(),
    ).toEqual(['../packages/agent/src/day-close.js', '@mpp/db', '@mpp/db', 'node:path', 'node:url'])
  })

  it.each(SEND_PATTERNS)('has no trace of %s', (_name, pattern) => {
    expect(source).not.toMatch(pattern)
  })

  it('writes nothing by itself: every write goes through the shared function', () => {
    expect(source).not.toMatch(/\.(insert|update|upsert|delete|rpc)\(/)
  })
})
