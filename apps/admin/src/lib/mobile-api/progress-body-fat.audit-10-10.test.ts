/**
 * Audit 2026-10-10 — Progress shows the body fat the person informed at
 * sign-up (docs/mobile/api-v1.md, "Elegibilidade do Bloco 7.700 em Hoje e
 * Progresso", the `GET /progress` item).
 *
 * This file is the audit golden of the report. It lives here, and not in
 * packages/agent/src/__golden__, because the behaviour belongs to the app's
 * server: importing the read model from the engine package would invert the
 * dependency.
 *
 * THE REPORT, exact. Rehearsal of 2026-10-10 with build 1.0 (3) against the
 * staging server of e725096: an account that informed 15% of body fat at
 * sign-up opens Progresso and reads "Gordura corporal — Não disponível".
 *
 * THE CAUSE. The app shows `current_bf_percent` of `GET /api/mobile/v1/progress`.
 * `loadProgress` copied `user_progress.current_bf_percent`, a column NOTHING
 * in the repository writes with a value (the two reset functions set it to
 * null; the legacy reassessment tool only takes a value of that name as an
 * argument). The value of the sign-up is stored by
 * `complete_mobile_onboarding_atomic` in `user_profiles.body_fat_percent`,
 * the column `GET /profile` already returns.
 *
 * THE FIX. `GET /progress` answers the profile's `body_fat_percent` when
 * `user_progress.current_bf_percent` is null. Same 14 keys, same types, two
 * reads, no write; a stored progress value wins. Only a finite number, or a
 * text in decimal format, becomes a number: anything else is null (a bare
 * conversion would turn an empty text into 0% and `true` into 1%). It is
 * presentation only: no number, threshold or conduct of the method changes.
 *
 * WHOSE DECISION. Answering the profile's value in this field is a decisão do
 * orquestrador, anunciada ao dono em 2026-10-10, que pode riscar qualquer uma.
 * It was not approved in writing by the owner nor by the physician.
 *
 * ASSUMED — declared: only the 15% is in the report. The account, its sex,
 * height, weight and objective are the ones the workout golden of the same
 * day fixes for test account 2 (masculino, 180 cm, 75 kg, ganho_massa); ids
 * and instants are synthetic. The database is in memory: none was read or
 * written, nothing was published.
 *
 * The authentication wrapper is replaced by a pass-through so the handler can
 * be called with a context (the mould of app/api/mobile/v1/progress/route.test.ts);
 * the handler, the on-request close hook (switched off) and the read model are
 * the real ones.
 *
 * > RC BF-1 — cenário conta que informou 15% de gordura no cadastro e lê "Gordura corporal — Não disponível" em Progresso variante cadastro concluído de verdade contra o banco (a função complete_mobile_onboarding_atomic gravando user_profiles.body_fat_percent) e a tela vista no iPhone com o build 1.0 (3) NÃO coberta nesta PR (pendência da audit 2026-10-10). O golden parte do estado que o cadastro deixa (perfil com 15, progresso sem gordura); nenhum banco foi lido e nada foi publicado. Devolver a gordura do perfil quando a do progresso é nula é decisão do orquestrador, anunciada ao dono em 2026-10-10, que pode riscar qualquer uma.
 * > RC BF-2 — cenário gordura corporal em Progresso variante dizer na tela que o número foi informado pela pessoa, e quando (GET /progress não ganhou campo de origem; a linha fica em "Medidas", sem origem nem data) NÃO coberta nesta PR (pendência da audit 2026-10-10)
 * > RC BF-3 — cenário sugestão de cardápio e de treino do Flow para a mesma conta variante o pedido ao gerador, que continua lendo user_progress.current_bf_percent (coluna que nada grava) e envia "Gordura corporal: ?%" no cardápio NÃO coberta nesta PR (pendência da audit 2026-10-10). A causa é a mesma, mas trocar o que o gerador recebe muda o pedido ao modelo e não foi relatado: fica travado como está.
 * > RC BF-4 — cenário gordura corporal em Progresso variante valor mais novo vindo de reavaliação ou de fotos (nenhum caminho do app grava user_progress.current_bf_percent; se um dia gravar, ele vence o do perfil sem comparar datas) NÃO coberta nesta PR (pendência da audit 2026-10-10)
 */
import { readFileSync } from 'node:fs'
import { clearCalcConfigCache } from '@mpp/agent'
import { DayCloseMemoryDb } from '@mpp/agent/testing/day-close-memory-db'
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import type { MobileRouteContext } from '@/lib/mobile-api/route'

vi.mock('@/lib/mobile-api/route', async (importOriginal) => ({
  ...(await importOriginal<typeof import('@/lib/mobile-api/route')>()),
  createMobileRoute: (handler: unknown) => handler,
}))

const { GET } = await import('@/app/api/mobile/v1/progress/route')
const handler = GET as unknown as (context: MobileRouteContext) => Promise<Response>

const USER = '0b9f6f0e-0000-4000-8000-0000000b0f15'
const OTHER = '0b9f6f0e-0000-4000-8000-0000000b0f30'
const STAGING_REF = 'xitugspwfxkcluxvrdeg'
/** 16:00 of 2026-10-10 in America/Sao_Paulo: the afternoon of the rehearsal. */
const NOW = new Date('2026-10-10T19:00:00.000Z')

/** The state the sign-up leaves: the profile carries the body fat, the progress row does not. */
function database(profileBodyFat: unknown = 15) {
  const db = new DayCloseMemoryDb()
  db.addAccount({
    userId: USER,
    profile: {
      sex: 'masculino',
      birth_date: '2000-01-01',
      height_cm: 180,
      weight_kg: 75,
      body_fat_percent: profileBodyFat,
      activity_level: 'moderado',
      training_frequency: 5,
      water_intake: 'moderado',
      hunger_level: 'moderada',
      goal_type: null,
      goal_value: null,
      current_protocol: 'ganho_massa',
      deficit_level: null,
    },
  })
  return db
}

function context(db: DayCloseMemoryDb): MobileRouteContext {
  return {
    request: new Request('https://bodyflow.test/api/mobile/v1/progress'),
    requestId: 'request-progress-body-fat',
    supabase: db.client,
    auth: {
      accessToken: 'redacted',
      authUserId: USER,
      userId: USER,
      identity: { id: USER, email: null, emailConfirmedAt: null },
      patient: {
        id: USER,
        authUserId: USER,
        email: null,
        name: null,
        locale: 'pt-BR',
        timezone: 'America/Sao_Paulo',
        country: 'BR',
        countryConfirmed: true,
        status: 'active',
      },
    },
  }
}

/** The 14 keys of the answer, as app/api/mobile/v1/progress/route.test.ts pins them. */
const PROGRESS_KEYS = [
  'badges_earned',
  'block_7700_enabled',
  'blocks_completed',
  'current_bf_percent',
  'current_protocol',
  'current_streak',
  'current_weight',
  'deficit_block',
  'last_active_date',
  'level',
  'longest_streak',
  'next_reevaluation',
  'updated_at',
  'xp_total',
]

const DECISION = 'decisão do orquestrador, anunciada ao dono em 2026-10-10, que pode riscar qualquer uma'

async function answer(db: DayCloseMemoryDb) {
  const response = await handler(context(db))
  return { status: response.status, body: (await response.json()) as { data: Record<string, unknown> | null } }
}

beforeEach(() => {
  vi.useFakeTimers()
  vi.setSystemTime(NOW)
  clearCalcConfigCache()
  // The on-request day close stays off, as in production without the switch.
  vi.stubEnv('MOBILE_DAY_CLOSE_FROM', '')
  vi.stubEnv('MOBILE_DAY_CLOSE_PROJECT_REF', '')
  vi.stubEnv('NEXT_PUBLIC_SUPABASE_URL', `https://${STAGING_REF}.supabase.co`)
})

afterEach(() => {
  vi.useRealTimers()
  vi.restoreAllMocks()
  vi.unstubAllEnvs()
})

describe('audit 2026-10-10 — GET /api/mobile/v1/progress and the body fat of the sign-up', () => {
  it('G1 the account that informed 15% at sign-up: GET /progress answers current_bf_percent 15', async () => {
    const db = database(15)
    // The setup is the reported state: the sign-up wrote the profile, nothing wrote the progress row.
    expect(db.tables.user_profiles[0]?.body_fat_percent).toBe(15)
    expect(db.progress(USER)?.current_bf_percent).toBeNull()

    const { status, body } = await answer(db)

    expect(status).toBe(200)
    expect(body.data?.current_bf_percent).toBe(15)
    // Same shape: the 14 keys, nothing added.
    expect(Object.keys(body.data ?? {}).sort()).toEqual(PROGRESS_KEYS)
    expect(body.data).toMatchObject({ current_protocol: 'ganho_massa', block_7700_enabled: false })
    // Two reads, both by the authenticated user only, and no write.
    expect(db.writes).toEqual([])
    expect(db.operations.map((operation) => `${operation.kind}:${operation.target}`).sort()).toEqual([
      'select:user_profiles',
      'select:user_progress',
    ])
    for (const operation of db.operations) {
      expect(operation.filters, operation.target).toEqual([{ op: 'eq', column: 'user_id', value: USER }])
    }
    // The stored progress row is not touched: the field is answered, not written.
    expect(db.progress(USER)?.current_bf_percent).toBeNull()
  })

  it('G2 a value stored in the progress row wins over the profile', async () => {
    const db = database(15)
    const saved = db.tables.user_progress[0]
    if (!saved) throw new Error('Missing fixture progress row')
    saved.current_bf_percent = 18.25

    const { body } = await answer(db)

    expect(body.data?.current_bf_percent).toBe(18.25)
    expect(db.writes).toEqual([])
  })

  it('G3 nothing anywhere is null, as before', async () => {
    const { status, body } = await answer(database(null))

    expect(status).toBe(200)
    expect(body.data?.current_bf_percent).toBeNull()
    expect(Object.keys(body.data ?? {}).sort()).toEqual(PROGRESS_KEYS)
  })

  it('G4 no progress row is data:null, even with 15% in the profile', async () => {
    const db = database(15)
    db.tables.user_progress.length = 0

    const { status, body } = await answer(db)

    expect(status).toBe(200)
    expect(body.data).toBeNull()
    expect(db.writes).toEqual([])
  })

  it.each([
    // What the column can carry: a JSON number, or the same number as decimal text.
    [15, 15],
    [15.5, 15.5],
    ['15.50', 15.5],
    ['15', 15],
    [' 15.5 ', 15.5],
    // Anything else is null: never text, never 0% or 1% born of a conversion.
    ['abc', null],
    ['', null],
    ['  ', null],
    [true, null],
    [false, null],
    [[], null],
    [[15], null],
    [{}, null],
    ['15%', null],
    ['1e1', null],
    ['-15', null],
    ['+15', null],
    ['15,5', null],
    ['.5', null],
    ['15.', null],
    ['0x0f', null],
    ['Infinity', null],
    ['NaN', null],
  ] as const)('G5 the profile value %j is answered as %j: a JSON number or null', async (stored, expected) => {
    const { body } = await answer(database(stored))

    const received = body.data?.current_bf_percent
    expect(received).toBe(expected)
    if (expected !== null) expect(typeof received).toBe('number')
  })

  it("G6 another account's profile does not leak into this one", async () => {
    const db = database(null)
    db.addAccount({ userId: OTHER, profile: { body_fat_percent: 30, current_protocol: 'recomposicao' } })

    const { body } = await answer(db)

    expect(body.data?.current_bf_percent).toBeNull()
    expect(body.data).toMatchObject({ current_protocol: 'ganho_massa', block_7700_enabled: false })
  })
})

describe('audit 2026-10-10 — declared pendencies of the body fat in Progress', () => {
  it('G7 every "RC BF" line of this header is in docs/mobile/api-v1.md, identical; and the docs say whose decision it is', () => {
    const header = readFileSync(new URL(import.meta.url), 'utf8')
    const doc = readFileSync(new URL('../../../../../docs/mobile/api-v1.md', import.meta.url), 'utf8')
    const calculation = readFileSync(new URL('../../../../../docs/CALCULO-MPP.md', import.meta.url), 'utf8')
    const fromHeader = Array.from(header.matchAll(/^ \* (> RC BF-\d+ — .*)$/gm), (match) => match[1] ?? '')
    const fromDoc = Array.from(doc.matchAll(/^(> RC BF-\d+ — .*)$/gm), (match) => match[1] ?? '')

    expect(fromHeader).toHaveLength(4)
    expect(fromHeader.map((entry) => entry.match(/^> RC BF-\d+/)?.[0])).toEqual([
      '> RC BF-1',
      '> RC BF-2',
      '> RC BF-3',
      '> RC BF-4',
    ])
    expect(fromDoc).toEqual(fromHeader)
    // The project's mandatory wording of a pendency.
    for (const entry of fromHeader) {
      expect(entry).toMatch(
        /^> RC BF-\d+ — cenário .+ variante .+ NÃO coberta nesta PR \(pendência da audit 2026-10-10\)(?:$|\. \S)/,
      )
    }

    // Whose decision it is, in the item of GET /progress of each doc — and never as an approval.
    const flat = (text: string) => text.replace(/\s+/g, ' ')
    const item = (text: string, from: string, to: string) => {
      const start = text.indexOf(from)
      expect(start, from).toBeGreaterThan(-1)
      const end = text.indexOf(to, start + from.length)
      expect(end, to).toBeGreaterThan(start)
      return flat(text.slice(start, end))
    }
    const apiItem = item(doc, '- `GET /progress`, quando `data` existe,', '\n- Ausência de progresso mantém')
    const calculationItem = item(
      calculation,
      '- `GET /progress` acrescenta `current_protocol`',
      '\n- Snapshot, refeições e treinos são lidos juntos.',
    )
    for (const text of [apiItem, calculationItem]) {
      expect(text).toContain(DECISION)
      expect(text).toContain('`user_profiles.body_fat_percent`')
      expect(text).not.toMatch(/aprovad[oa]s? pel[oa] (?:dono|médico)|o dono aprovou|o médico aprovou/i)
    }
    expect(apiItem).toContain('conserva 11 campos persistidos')
    expect(calculationItem).toContain('nenhuma fórmula, meta, balanço ou bloco muda')
  })
})
