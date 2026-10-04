import { existsSync, readFileSync } from 'node:fs'
import { dirname, resolve } from 'node:path'
import { fileURLToPath } from 'node:url'
import { describe, expect, test } from 'vitest'

const appRoot = resolve(dirname(fileURLToPath(import.meta.url)), '..')
const adminRoot = resolve(appRoot, '../admin')

function readJson(path: string): unknown {
  return JSON.parse(readFileSync(path, 'utf8'))
}

describe('Mobile BFF function region', () => {
  test('runs the functions in São Paulo and configures nothing else', () => {
    // Both Supabase databases are in sa-east-1 and a Flow turn makes dozens
    // of sequential round trips, so the function has to run beside them. Any
    // other key here would change behaviour beyond the region.
    expect(readJson(resolve(appRoot, 'vercel.json'))).toEqual({
      $schema: 'https://openapi.vercel.sh/vercel.json',
      regions: ['gru1'],
    })
  })

  test('keeps the file in the Next app root that the Vercel project builds', () => {
    // Vercel only honours vercel.json inside the project's Root Directory,
    // which is this package (the one that owns `next build`).
    expect(readJson(resolve(appRoot, 'package.json'))).toMatchObject({
      name: '@mpp/mobile-bff',
      scripts: { build: 'next build' },
    })
    expect(existsSync(resolve(appRoot, 'next.config.mjs'))).toBe(true)
  })

  test('does not move the admin project, which serves the WhatsApp pipeline', () => {
    // The admin region is an owner decision; this change must not ride along.
    const adminConfigPath = resolve(adminRoot, 'vercel.json')
    const adminConfig = existsSync(adminConfigPath) ? readJson(adminConfigPath) : {}

    expect(adminConfig).not.toHaveProperty('regions')
  })
})
