import { readFileSync, realpathSync } from 'node:fs'
import { dirname, resolve } from 'node:path'
import { fileURLToPath } from 'node:url'
import { describe, expect, it } from 'vitest'

const serverRoot = resolve(dirname(fileURLToPath(import.meta.url)), '../.next/server')
const paths: Record<string, string> = JSON.parse(
  readFileSync(resolve(serverRoot, 'app-paths-manifest.json'), 'utf8'),
)
const code = new Map<string, string>()

function routesReaching(marker: string): string[] {
  return Object.entries(paths)
    .filter(([route]) => route.startsWith('/api/mobile/v1/'))
    .filter(([, target]) => {
      const entry = resolve(serverRoot, target)
      const trace: { files: string[] } = JSON.parse(readFileSync(`${entry}.nft.json`, 'utf8'))
      return [entry, ...trace.files.map((file) => resolve(dirname(entry), file))].some((file) => {
        if (!/\.[cm]?js$/.test(file)) return false
        const physical = realpathSync(file)
        let source = code.get(physical)
        if (source === undefined) {
          source = readFileSync(physical, 'utf8')
          code.set(physical, source)
        }
        return source.includes(marker)
      })
    })
    .map(([route]) => route)
    .sort()
}

describe('signup completion in the fresh mobile server build', () => {
  it.each([
    'begin_mobile_signup_completion_intent',
    'resolve_mobile_signup_completion_intent',
    'verify_mobile_signup_completion_intent',
    'MOBILE_SIGNUP_COMPLETION_INTENTS_PROJECT_REF',
  ])('limits %s to the two signup routes including traced chunks', (marker) => {
    expect(routesReaching(marker)).toEqual([
      '/api/mobile/v1/onboarding/completion-intent/route',
      '/api/mobile/v1/onboarding/route',
    ])
  })
})
