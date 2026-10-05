/**
 * The operator script scripts/close-open-days.ts: dry run by default, refuses
 * every database but the staging project, refuses a process outside TZ=UTC,
 * and prints no name, e-mail, phone number or account id.
 *
 * The script is loaded from its file and its exported functions run against
 * the in-memory database. It is NOT executed as a program here and no real
 * database is reached. The project refs are identifiers, not credentials.
 */
import { readFileSync } from 'node:fs'
import { dirname, resolve } from 'node:path'
import { fileURLToPath, pathToFileURL } from 'node:url'
import type { ServiceClient } from '@mpp/db'
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import { clearCalcConfigCache } from './calc-config-loader.js'
import { DayCloseMemoryDb } from './testing/day-close-memory-db.js'

interface ScriptOptions {
  from: string
  apply: boolean
  account: string | null
  advanceReevaluation: boolean
}

interface ScriptModule {
  parseArguments(argv: string[]): ScriptOptions
  assertStagingProject(url: string | undefined): void
  assertUtcProcess(timezone: string | undefined): void
  runCloseOpenDays(
    supabase: ServiceClient,
    options: ScriptOptions,
    print: (line: string) => void,
    now?: Date,
  ): Promise<{
    accounts: number
    skippedAccounts: number
    daysClosed: number
    streakResets: number
  }>
}

// Loaded by URL: the script lives outside this package's source root.
const scriptUrl = pathToFileURL(
  resolve(dirname(fileURLToPath(import.meta.url)), '../../../scripts/close-open-days.ts'),
).href
const script = (await import(/* @vite-ignore */ scriptUrl)) as ScriptModule

const APP_ACCOUNT = '0b9f6f0e-0000-4000-8000-0000000005c1'
const WHATSAPP_ACCOUNT = '0b9f6f0e-0000-4000-8000-0000000005c2'
const BLOCKED_ACCOUNT = '0b9f6f0e-0000-4000-8000-0000000005c3'
const PHONE = '5511999990000'
/** 08:00 of 2026-10-05 in America/Sao_Paulo. */
const NOW = new Date('2026-10-05T11:00:00.000Z')

const PROFILE = {
  sex: 'masculino',
  birth_date: '1986-01-01',
  height_cm: 180,
  weight_kg: 80,
  body_fat_percent: null,
  activity_level: 'leve',
  training_frequency: 3,
  water_intake: 'moderado',
  hunger_level: 'moderada',
  goal_type: null,
  goal_value: null,
  current_protocol: 'recomposicao',
  deficit_level: 500,
}

function database() {
  const db = new DayCloseMemoryDb()
  db.addAccount({ userId: BLOCKED_ACCOUNT, status: 'blocked', profile: PROFILE })
  db.addAccount({ userId: WHATSAPP_ACCOUNT, wpp: PHONE, profile: PROFILE })
  db.addAccount({ userId: APP_ACCOUNT, profile: PROFILE })
  for (const user of [BLOCKED_ACCOUNT, WHATSAPP_ACCOUNT, APP_ACCOUNT]) {
    for (const date of ['2026-10-03', '2026-10-04']) {
      db.registerMeal({
        userId: user,
        date,
        consumedAt: `${date}T15:00:00.000Z`,
        kcal: 1500,
        proteinG: 110,
        caloriesTarget: date === '2026-10-03' ? 1700 : 1576,
        proteinTarget: 120,
      })
    }
  }
  return db
}

beforeEach(() => {
  vi.useFakeTimers()
  vi.setSystemTime(NOW)
  clearCalcConfigCache()
})

afterEach(() => {
  vi.useRealTimers()
})

describe('arguments', () => {
  it('is a dry run unless --apply is given', () => {
    expect(script.parseArguments(['--from', '2026-09-22'])).toEqual({
      from: '2026-09-22',
      apply: false,
      account: null,
      advanceReevaluation: false,
    })
    expect(script.parseArguments(['--from', '2026-09-22', '--apply']).apply).toBe(true)
    expect(script.parseArguments(['--from', '2026-09-22', '--account', 'conta-10']).account).toBe(
      'conta-10',
    )
  })

  it('requires the first date and rejects anything it does not know', () => {
    expect(() => script.parseArguments([])).toThrow('--from')
    expect(() => script.parseArguments(['--from', '22/09/2026'])).toThrow('--from')
    expect(() => script.parseArguments(['--from', '2026-02-31'])).toThrow('--from')
    expect(() => script.parseArguments(['--from', '2026-09-22', '--force'])).toThrow('desconhecido')
    expect(() => script.parseArguments(['--from', '2026-09-22', '--account', 'Maria'])).toThrow(
      'conta-10',
    )
  })
})

describe('refusals', () => {
  it('accepts only the staging project', () => {
    expect(() =>
      script.assertStagingProject('https://xitugspwfxkcluxvrdeg.supabase.co'),
    ).not.toThrow()
    expect(() => script.assertStagingProject('https://xuxehkhdvjivitduarvb.supabase.co')).toThrow(
      'produção',
    )
    expect(() => script.assertStagingProject('https://abcdefghijklmnopqrst.supabase.co')).toThrow(
      'staging',
    )
    expect(() => script.assertStagingProject('http://localhost:54321')).toThrow('staging')
    expect(() =>
      script.assertStagingProject('https://xitugspwfxkcluxvrdeg.supabase.co.example.com'),
    ).toThrow('staging')
    expect(() => script.assertStagingProject(undefined)).toThrow('inválida')
    expect(() => script.assertStagingProject('')).toThrow('inválida')
  })

  it('refuses the staging project over anything but https (the service key would go in clear)', () => {
    expect(() => script.assertStagingProject('http://xitugspwfxkcluxvrdeg.supabase.co')).toThrow(
      'precisa ser https',
    )
    expect(() => script.assertStagingProject('ws://xitugspwfxkcluxvrdeg.supabase.co')).toThrow(
      'precisa ser https',
    )
    // Production is still refused by name, whatever the scheme.
    expect(() => script.assertStagingProject('http://xuxehkhdvjivitduarvb.supabase.co')).toThrow(
      'produção',
    )
    expect(() =>
      script.assertStagingProject('https://xitugspwfxkcluxvrdeg.supabase.co/'),
    ).not.toThrow()
  })

  it('the header documents a command that exists: tsx is a dependency of the scripts package only', () => {
    const repository = resolve(dirname(fileURLToPath(import.meta.url)), '../../..')
    const header = readFileSync(resolve(repository, 'scripts/close-open-days.ts'), 'utf8')
    const scriptsPackage = JSON.parse(
      readFileSync(resolve(repository, 'scripts/package.json'), 'utf8'),
    ) as { devDependencies?: Record<string, string> }
    const rootPackage = JSON.parse(readFileSync(resolve(repository, 'package.json'), 'utf8')) as {
      dependencies?: Record<string, string>
      devDependencies?: Record<string, string>
    }
    expect(scriptsPackage.devDependencies).toHaveProperty('tsx')
    expect({ ...rootPackage.dependencies, ...rootPackage.devDependencies }).not.toHaveProperty(
      'tsx',
    )
    const commands = header.match(/^ \* {3}TZ=UTC .*$/gm) ?? []
    expect(commands).toHaveLength(3)
    for (const command of commands) {
      expect(command).toContain('TZ=UTC pnpm --dir scripts exec tsx close-open-days.ts --from ')
    }
    const apiDoc = readFileSync(resolve(repository, 'docs/mobile/api-v1.md'), 'utf8')
    expect(apiDoc).toContain(
      'TZ=UTC pnpm --dir scripts exec tsx close-open-days.ts --from 2026-09-22',
    )
    expect(`${header}\n${apiDoc}`).not.toMatch(/pnpm tsx scripts\/close-open-days/)
  })

  it('accepts only a UTC process', () => {
    expect(() => script.assertUtcProcess('UTC')).not.toThrow()
    expect(() => script.assertUtcProcess(undefined)).toThrow('TZ=UTC')
    expect(() => script.assertUtcProcess('America/Sao_Paulo')).toThrow('TZ=UTC')
  })
})

describe('run', () => {
  it('dry run: prints every day with both targets and writes nothing', async () => {
    const db = database()
    const lines: string[] = []
    const summary = await script.runCloseOpenDays(
      db.client,
      script.parseArguments(['--from', '2026-09-22']),
      (line) => lines.push(line),
      NOW,
    )

    expect(db.writes).toEqual([])
    expect(summary).toEqual({ accounts: 1, skippedAccounts: 2, daysClosed: 2, streakResets: 0 })
    expect(lines).toEqual([
      '── Fechamento de dias abertos — SIMULAÇÃO (nada é gravado) — a partir de 2026-09-22 ──',
      'conta-01: pulada (não está ativa)',
      'conta-02: pulada (tem número de WhatsApp)',
      'conta-03: 2 dia(s) a fechar (até 2026-10-04)',
      // Late day: the stored 1700 is kept. credit = 500 − (1500 − 1700) = 700.
      '  2026-10-03 (atrasado)  consumido 1500  exercício 0  meta gravada 1700 → meta do fechamento 1700  proteína gravada 120 → 120  status complete  XP +15 (total 15, nível 1)  bloco +700 (700/7700, 0 completo(s))  sequência 1 (maior 1)',
      // Yesterday at 08:00, past production's window: late too, stored 1576
      // kept. credit = 500 − (1500 − 1576) = 576.
      '  2026-10-04 (atrasado)  consumido 1500  exercício 0  meta gravada 1576 → meta do fechamento 1576  proteína gravada 120 → 120  status complete  XP +15 (total 30, nível 1)  bloco +576 (1276/7700, 0 completo(s))  sequência 2 (maior 2)',
      '── 1 conta(s) avaliada(s), 2 pulada(s), 2 dia(s) a fechar, 0 sequência(s) zerada(s) ──',
      'Simulação: nada foi gravado. Gravar exige --apply e autorização nomeada do Eduardo.',
    ])
  })

  it('an open row with water only is not visited and is listed as left open', async () => {
    const db = database()
    db.tables.daily_snapshots.push(
      db.withDefaults('daily_snapshots', {
        user_id: APP_ACCOUNT,
        date: '2026-10-02',
        water_consumed_ml: 1500,
      }),
    )
    const lines: string[] = []
    await script.runCloseOpenDays(
      db.client,
      script.parseArguments(['--from', '2026-09-22']),
      (line) => lines.push(line),
      NOW,
    )
    expect(lines.filter((line) => line.includes('2026-10-02'))).toEqual([
      '  linhas abertas sem refeição, treino nem mensagem (não visitadas, ficam abertas): 2026-10-02',
    ])
    expect(lines).toContain('conta-03: 2 dia(s) a fechar (até 2026-10-04)')
  })

  it("inside the production closer's window (00:30 local) yesterday is not marked late", async () => {
    const db = database()
    const lines: string[] = []
    const night = new Date('2026-10-05T03:30:00.000Z')
    vi.setSystemTime(night)
    await script.runCloseOpenDays(
      db.client,
      script.parseArguments(['--from', '2026-09-22']),
      (line) => lines.push(line),
      night,
    )
    // 03/10 is before yesterday: late. 04/10 is yesterday inside the window.
    expect(
      lines
        .filter((line) => line.startsWith('  2026-'))
        .map((line) => [line.slice(2, 12), line.includes('(atrasado)')]),
    ).toEqual([
      ['2026-10-03', true],
      ['2026-10-04', false],
    ])
  })

  it('the output and the queries carry no account id and no phone number', async () => {
    const db = database()
    const lines: string[] = []
    await script.runCloseOpenDays(
      db.client,
      script.parseArguments(['--from', '2026-09-22']),
      (line) => lines.push(line),
      NOW,
    )
    const output = lines.join('\n')
    for (const secret of [APP_ACCOUNT, WHATSAPP_ACCOUNT, BLOCKED_ACCOUNT, PHONE]) {
      expect(output).not.toContain(secret)
    }
    // The phone column is only ever used as a filter, never selected.
    const userReads = db.operations.filter((operation) => operation.target === 'users')
    expect(userReads.map((operation) => operation.filters)).toEqual([
      [],
      [{ op: 'is.null', column: 'wpp', value: null }],
    ])
  })

  it('--apply writes exactly what the dry run announced, for the app account only', async () => {
    const db = database()
    const simulated: string[] = []
    const applied: string[] = []
    await script.runCloseOpenDays(
      db.client,
      script.parseArguments(['--from', '2026-09-22']),
      (line) => simulated.push(line),
      NOW,
    )
    await script.runCloseOpenDays(
      db.client,
      script.parseArguments(['--from', '2026-09-22', '--apply']),
      (line) => applied.push(line),
      NOW,
    )

    expect(applied.slice(4, 6)).toEqual(simulated.slice(4, 6))
    expect(db.progress(APP_ACCOUNT)).toMatchObject({
      xp_total: 30,
      current_streak: 2,
      deficit_block: 1276,
      next_reevaluation: null,
    })
    for (const untouched of [WHATSAPP_ACCOUNT, BLOCKED_ACCOUNT]) {
      expect(db.progress(untouched)).toMatchObject({ xp_total: 0, last_active_date: null })
      expect(db.snapshot(untouched, '2026-10-04')).toMatchObject({ day_closed: false })
    }
  })

  it('--account limits the run to one alias', async () => {
    const db = database()
    const lines: string[] = []
    const summary = await script.runCloseOpenDays(
      db.client,
      script.parseArguments(['--from', '2026-09-22', '--account', 'conta-02']),
      (line) => lines.push(line),
      NOW,
    )
    expect(summary).toMatchObject({ accounts: 0, skippedAccounts: 1, daysClosed: 0 })
    expect(lines.filter((line) => line.startsWith('conta-'))).toEqual([
      'conta-02: pulada (tem número de WhatsApp)',
    ])
  })
})
