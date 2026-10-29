import { execFileSync } from 'node:child_process'
import { fileURLToPath } from 'node:url'
import { expect, it } from 'vitest'

it('revalidates billing origin after Next compiles public environment constants', () => {
  const script = fileURLToPath(
    new URL('../scripts/verify-billing-runtime-env.mjs', import.meta.url),
  )
  const output = execFileSync(process.execPath, [script], { encoding: 'utf8', timeout: 30000 })
  const result = JSON.parse(output)
  expect(result.observed).toEqual([true, false, false, true])
  expect(result.constantControlWasInlined).toBe(true)
  expect(result.cleanup).toBe('complete')
  expect(result.bundleSha256).toMatch(/^[a-f0-9]{64}$/)
})
