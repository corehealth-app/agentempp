/**
 * The switch of the body photos of the sign-up: off unless the environment
 * lists the project ref of the configured database, and never on the old
 * production database, which is refused in code
 * (docs/mobile/api-v1.md, "Fotos do corpo no cadastro").
 *
 * The switch being born OFF is a decisão do orquestrador, anunciada ao dono em
 * 2026-10-10/11, que pode riscar qualquer uma. The refs below are identifiers
 * of projects, not credentials; every URL here is only parsed, never called.
 */
import { readFileSync } from 'node:fs'
import { afterEach, describe, expect, it, vi } from 'vitest'
import { projectRefFromUrl as dayCloseProjectRefFromUrl } from './day-close-on-request'
import { projectRefFromUrl as evaluationProjectRefFromUrl } from './evaluation-access'
import {
  projectRefFromUrl,
  resolveSignupBodyPhotos,
  SIGNUP_BODY_PHOTOS_PROJECT_REF_ENV,
  signupBodyPhotosEnabled,
} from './signup-body-photo-switch'

const STAGING_REF = 'xitugspwfxkcluxvrdeg'
const PRODUCTION_REF = 'xuxehkhdvjivitduarvb'
const OTHER_REF = 'abcdefghijklmnopqrst'
const STAGING_URL = `https://${STAGING_REF}.supabase.co`
const PRODUCTION_URL = `https://${PRODUCTION_REF}.supabase.co`

/** `url: null` is an environment without the database URL (a default parameter would hide `undefined`). */
function env(listed: string | undefined, url: string | null = STAGING_URL) {
  return {
    [SIGNUP_BODY_PHOTOS_PROJECT_REF_ENV]: listed,
    NEXT_PUBLIC_SUPABASE_URL: url ?? undefined,
  }
}

afterEach(() => {
  vi.unstubAllEnvs()
})

describe('the switch of the sign-up body photos', () => {
  it('is named MOBILE_SIGNUP_BODY_PHOTOS_PROJECT_REF', () => {
    expect(SIGNUP_BODY_PHOTOS_PROJECT_REF_ENV).toBe('MOBILE_SIGNUP_BODY_PHOTOS_PROJECT_REF')
  })

  it('is ON when the variable lists the ref of the configured database', () => {
    expect(resolveSignupBodyPhotos(env(STAGING_REF))).toBe(true)
    // A list, with commas or spaces, and spaces around it.
    expect(resolveSignupBodyPhotos(env(` ${OTHER_REF}, ${STAGING_REF} `))).toBe(true)
    expect(resolveSignupBodyPhotos(env(`${OTHER_REF} ${STAGING_REF}`))).toBe(true)
  })

  it.each([
    ['the variable is absent', env(undefined)],
    ['the variable is empty', env('')],
    ['the variable is only spaces', env('   ')],
    ['the variable lists another ref (the wrong ref)', env(OTHER_REF)],
    ['the listed ref differs in case', env(STAGING_REF.toUpperCase())],
    ['the database URL is absent', env(STAGING_REF, null)],
    ['the database URL is not a hosted project', env(STAGING_REF, 'http://localhost:54321')],
    ['the database URL is plain http', env(STAGING_REF, `http://${STAGING_REF}.supabase.co`)],
    [
      'the ref is only the beginning of another host',
      env(STAGING_REF, `https://${STAGING_REF}.supabase.co.example.com`),
    ],
  ])('is OFF when %s', (_label, environment) => {
    expect(resolveSignupBodyPhotos(environment)).toBe(false)
  })

  it('is OFF on the old production database, whatever the variable says: the ref is refused in code', () => {
    // The production ref listed, on the production database.
    expect(resolveSignupBodyPhotos(env(PRODUCTION_REF, PRODUCTION_URL))).toBe(false)
    expect(resolveSignupBodyPhotos(env(`${STAGING_REF},${PRODUCTION_REF}`, PRODUCTION_URL))).toBe(
      false,
    )
    // Listing the production ref is a configuration mistake: nothing is
    // trusted, not even on the test database.
    expect(resolveSignupBodyPhotos(env(`${STAGING_REF},${PRODUCTION_REF}`, STAGING_URL))).toBe(
      false,
    )
  })

  it('reads the process environment at request time: off without the variable, on with the test ref, off with the production ref', () => {
    vi.stubEnv('NEXT_PUBLIC_SUPABASE_URL', STAGING_URL)
    vi.stubEnv(SIGNUP_BODY_PHOTOS_PROJECT_REF_ENV, '')
    expect(signupBodyPhotosEnabled()).toBe(false)

    vi.stubEnv(SIGNUP_BODY_PHOTOS_PROJECT_REF_ENV, STAGING_REF)
    expect(signupBodyPhotosEnabled()).toBe(true)

    vi.stubEnv('NEXT_PUBLIC_SUPABASE_URL', PRODUCTION_URL)
    vi.stubEnv(SIGNUP_BODY_PHOTOS_PROJECT_REF_ENV, PRODUCTION_REF)
    expect(signupBodyPhotosEnabled()).toBe(false)
  })

  it('reads the project ref of a database URL exactly as the other two switches of the app server do', () => {
    const urls = [
      STAGING_URL,
      `${STAGING_URL}/`,
      PRODUCTION_URL,
      undefined,
      '',
      'not a url',
      `http://${STAGING_REF}.supabase.co`,
      'https://db.example.com',
      `https://${STAGING_REF}.supabase.co.example.com`,
      'http://localhost:54321',
      `https://${STAGING_REF.toUpperCase()}.supabase.co`,
      'https://short.supabase.co',
    ]
    for (const url of urls) {
      expect(projectRefFromUrl(url), String(url)).toBe(dayCloseProjectRefFromUrl(url))
      expect(projectRefFromUrl(url), String(url)).toBe(evaluationProjectRefFromUrl(url))
    }
    expect(projectRefFromUrl(STAGING_URL)).toBe(STAGING_REF)
    expect(projectRefFromUrl(PRODUCTION_URL)).toBe(PRODUCTION_REF)
  })
})

describe('the switch module on its own', () => {
  const source = readFileSync(new URL('./signup-body-photo-switch.ts', import.meta.url), 'utf8')

  it('imports nothing: it reaches no other module of the app server, and the other switches are not touched', () => {
    expect(source).not.toMatch(/^\s*import\s/m)
    expect(source).not.toMatch(/\brequire\s*\(/)
    // The evaluation access and the on-request day close each lock who may
    // import them, by file name: this module does not name either.
    expect(source).not.toMatch(/evaluation-access/)
    expect(source).not.toMatch(/day-close-on-request/)
  })

  it('names the old production ref once, as the constant that refuses it', () => {
    expect(source.match(/xuxehkhdvjivitduarvb/g) ?? []).toHaveLength(1)
    expect(source).toMatch(/const PRODUCTION_PROJECT_REF = 'xuxehkhdvjivitduarvb'/)
    expect(source).toMatch(/ref === PRODUCTION_PROJECT_REF\) return false/)
    expect(source).toMatch(/allowedRefs\.includes\(PRODUCTION_PROJECT_REF\)\) return false/)
  })

  it('reads nothing but its own variable and the database URL, and writes no log', () => {
    const variables = Array.from(
      source.matchAll(/process\.env\.([A-Z0-9_]+)/g),
      (match) => match[1],
    )
    expect([...new Set(variables)].sort()).toEqual([
      'MOBILE_SIGNUP_BODY_PHOTOS_PROJECT_REF',
      'NEXT_PUBLIC_SUPABASE_URL',
    ])
    expect(source).not.toMatch(/console\./)
  })
})
