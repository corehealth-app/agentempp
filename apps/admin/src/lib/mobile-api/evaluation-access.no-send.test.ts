/**
 * Static proof that the automatic evaluation access can only talk to the
 * database it is handed.
 *
 * WHY A STATIC TEST. The module runs inside the onboarding request of the
 * mobile API, whose build is guarded by scripts run by hand at deploy time;
 * those do not look for a send function. So the claims of the module header
 * ("it only calls the database it was handed, and sends nothing") are checked
 * here, on the source, on every test run: what it imports, which tables and
 * functions it names, which environment variables it reads.
 *
 * The literals the mobile BFF build forbids are read from its verify script,
 * not copied here.
 */
import { readFileSync } from 'node:fs'
import { dirname, resolve } from 'node:path'
import { fileURLToPath } from 'node:url'
import { describe, expect, it } from 'vitest'

const here = dirname(fileURLToPath(import.meta.url))
const repository = resolve(here, '../../../../..')
const MODULE = resolve(here, 'evaluation-access.ts')
const BFF_GUARD = resolve(repository, 'apps/mobile-bff/scripts/verify-build-surface.mjs')

const source = readFileSync(MODULE, 'utf8')

interface ImportLine {
  specifier: string
  typeOnly: boolean
}

function imports(text: string): ImportLine[] {
  const found: ImportLine[] = []
  const pattern = /^(import|export)\s+(type\s+)?[^'"]*?from\s+['"]([^'"]+)['"]/gms
  for (const match of text.matchAll(pattern)) {
    found.push({ specifier: match[3] as string, typeOnly: Boolean(match[2]) })
  }
  return found
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
  ['the agent package', /@mpp\/agent/],
  ['a provider factory', /createMessagingProvider|sendHumanized|MessagingProvider/],
  ['an HTTP call', /\bfetch\s*\(/],
  ['an HTTP client', /\b(?:axios|undici|XMLHttpRequest|node:https?)\b/],
  ['a client of its own', /createClient|createServiceClient|supabase-js/],
  ['the event dispatch RPC', /dispatch_\w*event/i],
  ['a model call', /openrouter|\bllm\s*\.|\.complete\s*\(/i],
  ['a push or mail sender', /\b(?:sendPush|sendMail|apns|nodemailer)\b/i],
]

describe('apps/admin/src/lib/mobile-api/evaluation-access.ts', () => {
  it('imports the route wrapper and nothing else', () => {
    expect(imports(source)).toEqual([
      { specifier: './route', typeOnly: true },
      { specifier: './route', typeOnly: false },
    ])
    expect(source).toMatch(/import type \{ MobileRouteContext \} from '.\/route'/)
    expect(source).toMatch(/import \{ safeUnexpectedErrorName \} from '.\/route'/)
    // Side-effect and dynamic imports would bypass the list above.
    expect(source).not.toMatch(/^import\s+['"]/m)
    expect(source).not.toMatch(/\bimport\s*\(/)
    expect(source).not.toMatch(/\brequire\s*\(/)
  })

  it.each(SEND_PATTERNS)('has no trace of %s', (_name, pattern) => {
    expect(source).not.toMatch(pattern)
  })

  it('calls exactly two RPCs: the resolver and the entitlement event', () => {
    const called = Array.from(source.matchAll(/\.rpc\(\s*'([^']+)'/g), (match) => match[1])
    expect(called).toEqual(['resolve_user_entitlement', 'apply_entitlement_event'])
    // No RPC name built at run time.
    expect(source.match(/\.rpc\(/g)).toHaveLength(2)
  })

  it('reads two tables and writes to none directly', () => {
    const read = Array.from(source.matchAll(/\.from\('(\w+)'\)/g), (match) => match[1])
    expect(read).toEqual(['entitlement_events', 'user_profiles'])
    expect(source.match(/\.from\(/g)).toHaveLength(2)
    expect(source).not.toMatch(/\.(insert|update|upsert|delete)\(/)
  })

  it('reads exactly four environment variables', () => {
    const read = Array.from(source.matchAll(/process\.env\.(\w+)/g), (match) => match[1]).sort()
    expect(read).toEqual([
      'MOBILE_EVALUATION_ACCESS_ACTOR_ID',
      'MOBILE_EVALUATION_ACCESS_DAYS',
      'MOBILE_EVALUATION_ACCESS_PROJECT_REF',
      'NEXT_PUBLIC_SUPABASE_URL',
    ])
    expect(source).not.toMatch(/process\.env\[/)
    expect(source).not.toMatch(/process\.env\b(?!\.)/)
  })

  it('names the production project only to refuse it', () => {
    expect(source.match(/xuxehkhdvjivitduarvb/g)).toHaveLength(1)
    expect(source).toMatch(/const PRODUCTION_PROJECT_REF = 'xuxehkhdvjivitduarvb'/)
    expect(source).toMatch(/ref === PRODUCTION_PROJECT_REF\) return null/)
    expect(source).toMatch(/allowedRefs\.includes\(PRODUCTION_PROJECT_REF\)\) return null/)
    // No project is allowed by a literal: the allowed ref only comes from the variable.
    expect(source).not.toContain('xitugspwfxkcluxvrdeg')
  })

  it('logs a request id, a stage and a count: no account, no actor, no database text', () => {
    const logged = Array.from(
      source.matchAll(/console\.(info|error)\(\s*'([^']+)',\s*\{([^}]*)\}/g),
      (match) => [
        match[1],
        match[2],
        Array.from((match[3] as string).matchAll(/^\s*(\w+)\s*[:,]/gm), (key) => key[1]),
      ],
    )
    expect(logged).toEqual([
      [
        'error',
        '[mobile-api] evaluation_access_failed',
        ['request_id', 'scope', 'stage', 'error_name'],
      ],
      ['info', '[mobile-api] evaluation_access', ['request_id', 'scope', 'result']],
      ['info', '[mobile-api] evaluation_access', ['request_id', 'scope', 'result', 'days']],
    ])
    expect(source.match(/console\./g)).toHaveLength(3)
    // The stage is one of the module's own words and the name comes from the
    // shared allow-list: the text of a database error is never read.
    expect(source).not.toMatch(/\.message\b/)
    expect(source).toMatch(/error_name: safeUnexpectedErrorName\(error\)/)
  })

  it('carries none of the literals the mobile BFF build forbids, not even in a comment', () => {
    const literals = forbiddenBuildLiterals()
    expect(literals.length).toBeGreaterThan(10)
    for (const literal of literals) expect(source, literal).not.toContain(literal)
  })
})
