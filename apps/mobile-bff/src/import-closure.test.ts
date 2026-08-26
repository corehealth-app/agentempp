import { spawnSync } from 'node:child_process'
import { dirname, resolve } from 'node:path'
import { fileURLToPath } from 'node:url'
import { describe, expect, test } from 'vitest'
import { hasServerActionDirective } from '../scripts/verify-import-closure.mjs'

const appRoot = resolve(dirname(fileURLToPath(import.meta.url)), '..')
const verifier = resolve(appRoot, 'scripts/verify-import-closure.mjs')

describe('dedicated Mobile BFF import closure', () => {
  test('resolves relative and alias imports into an allowlisted classified manifest', () => {
    const result = spawnSync(process.execPath, [verifier], {
      cwd: appRoot,
      encoding: 'utf8',
    })

    expect(result.status, result.stderr).toBe(0)
    expect(result.stderr).toBe('')

    const records = result.stdout.trim().split('\n')
    expect(records.length).toBeGreaterThan(40)
    expect(records).toEqual([...records].sort((left, right) => left.localeCompare(right, 'en')))
    expect(new Set(records).size).toBe(records.length)
    expect(records.every((record) => /^[a-z][a-z-]*\t[^\t\r\n]+$/.test(record))).toBe(true)

    expect(records).toContain(
      'mobile-wrapper\tapps/mobile-bff/src/app/api/mobile/v1/today/route.ts',
    )
    expect(records).toContain(
      'mobile-route\tapps/admin/src/app/api/mobile/v1/content/route.ts',
    )
    expect(records).toContain(
      'mobile-route-support\tapps/admin/src/app/api/mobile/v1/content/handlers.ts',
    )
    expect(records).toContain(
      'mobile-api-lib\tapps/admin/src/lib/mobile-api/route.ts',
    )
    expect(records).toContain(
      'approved-server-lib\tapps/admin/src/lib/supabase/server.ts',
    )
    expect(records).toContain(
      'published-inngest-client\tpackages/inngest-functions/src/client.ts',
    )
    expect(records).not.toContain('external-package\t@mpp/inngest-functions')
    expect(
      records.some((record) =>
        /packages\/inngest-functions\/src\/(?:index\.ts|functions\/|lib\/)/.test(record),
      ),
    ).toBe(false)
    expect(records.some((record) => record.startsWith('external-package\t'))).toBe(true)
    expect(records.some((record) => record.startsWith('denied-'))).toBe(false)
  })

  test('detects a horizontally indented inline Server Action directive', () => {
    const inlineServerAction = [
      'async function submit() {',
      "  'use server'",
      '}',
    ].join('\n')

    expect(hasServerActionDirective(inlineServerAction)).toBe(true)
  })
})
