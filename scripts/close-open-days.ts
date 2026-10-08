/**
 * Closes the past open days of the app accounts of the TEST environment,
 * with the same function the mobile API uses on request
 * (`closePastOpenDays`, packages/agent/src/day-close.ts; rules in
 * docs/CALCULO-MPP.md §3a). Nothing is sent to anyone: the function only
 * reads and writes the database.
 *
 * DRY RUN BY DEFAULT. Without `--apply` nothing is written: the script prints,
 * per account alias and per day, what the close would write. Writing to
 * patient data needs Eduardo's explicit authorization naming the accounts and
 * the values (CLAUDE.md): run the simulation, hand him the output, and only
 * then run with `--apply`.
 *
 * It refuses any database other than the staging project, refuses the
 * production project by name, and refuses a URL that is not https (the service
 * key would travel in clear). It must run with TZ=UTC, as the servers do: the
 * streak rule compares dates with the process's local getters.
 *
 * From the repository root (`tsx` is installed in the `scripts` package only,
 * so `pnpm tsx scripts/...` does not start), with SUPABASE_URL and
 * SUPABASE_SERVICE_ROLE_KEY of the staging project already in the shell (the
 * repository ships no staging env file):
 *
 *   TZ=UTC pnpm --dir scripts exec tsx close-open-days.ts --from 2026-09-22
 *   TZ=UTC pnpm --dir scripts exec tsx close-open-days.ts --from 2026-09-22 --account conta-10
 *   TZ=UTC pnpm --dir scripts exec tsx close-open-days.ts --from 2026-09-22 --apply
 *
 * Options:
 *   --from YYYY-MM-DD        first local date that may be closed (required)
 *   --account conta-NN       only that account (alias printed by a dry run)
 *   --apply                  write
 *   --advance-reevaluation   also advance the 14-day reassessment schedule, as
 *                            the production closer does (off by default: it
 *                            switches the reassessment context on in the Flow)
 *
 * The output carries no name, no e-mail, no phone number and no account id:
 * accounts are numbered by creation order.
 */
import { resolve } from 'node:path'
import { fileURLToPath } from 'node:url'
import type { ServiceClient } from '@mpp/db'
import { createServiceClient } from '@mpp/db'
import {
  type ClosePastOpenDaysResult,
  closePastOpenDays,
  type DayCloseResult,
} from '../packages/agent/src/day-close.js'

const STAGING_PROJECT_REF = 'xitugspwfxkcluxvrdeg'
const PRODUCTION_PROJECT_REF = 'xuxehkhdvjivitduarvb'

export interface CloseOpenDaysOptions {
  from: string
  apply: boolean
  account: string | null
  advanceReevaluation: boolean
}

export interface CloseOpenDaysSummary {
  accounts: number
  skippedAccounts: number
  daysClosed: number
  streakResets: number
}

export function parseArguments(argv: string[]): CloseOpenDaysOptions {
  const options: CloseOpenDaysOptions = {
    from: '',
    apply: false,
    account: null,
    advanceReevaluation: false,
  }
  for (let index = 0; index < argv.length; index++) {
    const argument = argv[index]
    if (argument === '--apply') options.apply = true
    else if (argument === '--advance-reevaluation') options.advanceReevaluation = true
    else if (argument === '--from') options.from = argv[++index] ?? ''
    else if (argument === '--account') options.account = argv[++index] ?? ''
    else throw new Error(`argumento desconhecido: ${argument}`)
  }
  const parsedFrom = new Date(`${options.from}T00:00:00.000Z`)
  if (
    !/^\d{4}-\d{2}-\d{2}$/.test(options.from) ||
    Number.isNaN(parsedFrom.getTime()) ||
    parsedFrom.toISOString().slice(0, 10) !== options.from
  ) {
    throw new Error('--from YYYY-MM-DD é obrigatório')
  }
  if (options.account !== null && !/^conta-\d{2,}$/.test(options.account)) {
    throw new Error('--account espera um apelido como conta-10')
  }
  return options
}

/**
 * Throws unless the URL is the staging project's, over https. Production is
 * named, not just excluded, whatever the scheme.
 */
export function assertStagingProject(url: string | undefined): void {
  let parsed: URL
  try {
    parsed = new URL(url ?? '')
  } catch {
    throw new Error('URL do banco ausente ou inválida')
  }
  const ref = parsed.hostname.match(/^([a-z0-9]{20})\.supabase\.co$/)?.[1] ?? null
  if (ref === PRODUCTION_PROJECT_REF) {
    throw new Error('RECUSADO: este script nunca roda contra o banco de produção')
  }
  if (ref !== STAGING_PROJECT_REF) {
    throw new Error(`RECUSADO: o banco não é o projeto de staging (${STAGING_PROJECT_REF})`)
  }
  // The service role key goes in a header of every request: never in clear.
  if (parsed.protocol !== 'https:') {
    throw new Error('RECUSADO: a URL do banco precisa ser https')
  }
}

export function assertUtcProcess(timezone: string | undefined): void {
  if (timezone !== 'UTC') throw new Error('RECUSADO: rode com TZ=UTC')
}

function value(number: number | null): string {
  return number === null ? '—' : String(number)
}

export function formatDay(day: DayCloseResult): string {
  if (!day.detail) return `  ${day.date}  não fecha (${day.reason ?? 'sem motivo'})`
  const d = day.detail
  const badges = d.newBadges.length > 0 ? `  medalha: ${d.newBadges.join(', ')}` : ''
  return (
    `  ${day.date}${day.late ? ' (atrasado)' : ''}  ` +
    `consumido ${d.caloriesConsumed}  exercício ${d.exerciseCalories}  ` +
    `meta gravada ${value(d.storedCaloriesTarget)} → meta do fechamento ${value(d.caloriesTarget)}  ` +
    `proteína gravada ${value(d.storedProteinTarget)} → ${value(d.proteinTarget)}  ` +
    `status ${d.dayStatus}  XP +${d.xpEarned} (total ${d.progress.xpTotal}, nível ${d.progress.level})  ` +
    `bloco ${d.blockCredit >= 0 ? '+' : ''}${d.blockCredit} (${d.progress.deficitBlock}/7700, ${d.progress.blocksCompleted} completo(s))  ` +
    `sequência ${d.progress.currentStreak} (maior ${d.progress.longestStreak})${badges}`
  )
}

export function formatAccountTail(result: ClosePastOpenDaysResult): string[] {
  const lines: string[] = []
  if (result.streakReset) {
    lines.push(
      `  sequência zerada por inatividade: ${result.streakReset.previousStreak} → 0 ` +
        `(último dia ativo ${result.streakReset.lastActiveDate}, ${result.streakReset.gapDays} dias)` +
        (result.streakReset.applied ? '' : ' [não gravado]'),
    )
  }
  if (result.staleOpenDates.length > 0) {
    lines.push(
      `  ficam ABERTOS (anteriores ao último dia já fechado): ${result.staleOpenDates.join(', ')}`,
    )
  }
  if (result.inactiveOpenDates.length > 0) {
    lines.push(
      `  linhas abertas sem refeição, treino nem mensagem (não visitadas, ficam abertas): ${result.inactiveOpenDates.join(', ')}`,
    )
  }
  if (result.pendingDates.length > 0) {
    lines.push(`  pendentes para a próxima rodada: ${result.pendingDates.join(', ')}`)
  }
  return lines
}

export async function runCloseOpenDays(
  supabase: ServiceClient,
  options: CloseOpenDaysOptions,
  print: (line: string) => void,
  now: Date = new Date(),
): Promise<CloseOpenDaysSummary> {
  // Aliases follow the creation order of ALL accounts, so they stay the same
  // whichever accounts are active today.
  const { data: users, error: usersError } = await supabase
    .from('users')
    .select('id, status, timezone')
    .order('created_at', { ascending: true })
    .order('id', { ascending: true })
  if (usersError) throw new Error(usersError.message)
  // Asked as a filter so no phone number is ever loaded.
  const { data: appOnly, error: appOnlyError } = await supabase
    .from('users')
    .select('id')
    .is('wpp', null)
  if (appOnlyError) throw new Error(appOnlyError.message)
  const appOnlyIds = new Set((appOnly ?? []).map((row) => row.id))

  const summary: CloseOpenDaysSummary = {
    accounts: 0,
    skippedAccounts: 0,
    daysClosed: 0,
    streakResets: 0,
  }
  print(
    `── Fechamento de dias abertos — ${options.apply ? 'GRAVANDO' : 'SIMULAÇÃO (nada é gravado)'} — a partir de ${options.from} ──`,
  )

  for (const [index, user] of (users ?? []).entries()) {
    const alias = `conta-${String(index + 1).padStart(2, '0')}`
    if (options.account !== null && options.account !== alias) continue
    if (user.status !== 'active' || !appOnlyIds.has(user.id) || !user.timezone) {
      summary.skippedAccounts += 1
      const reason =
        user.status !== 'active'
          ? 'não está ativa'
          : !user.timezone
            ? 'sem fuso'
            : 'tem número de WhatsApp'
      print(`${alias}: pulada (${reason})`)
      continue
    }

    const result = await closePastOpenDays(supabase, {
      userId: user.id,
      timezone: user.timezone,
      now,
      from: options.from,
      dryRun: !options.apply,
      block7700Policy: 'flow-recomposition-v1',
      advanceReevaluation: options.advanceReevaluation,
    })
    summary.accounts += 1
    const closed = result.days.filter((day) => day.closed)
    summary.daysClosed += closed.length
    if (result.streakReset) summary.streakResets += 1

    print(
      `${alias}: ${closed.length} dia(s) ${options.apply ? 'fechado(s)' : 'a fechar'} ` +
        `(até ${result.latestClosableDate})`,
    )
    for (const day of result.days) print(formatDay(day))
    for (const line of formatAccountTail(result)) print(line)
  }

  print(
    `── ${summary.accounts} conta(s) avaliada(s), ${summary.skippedAccounts} pulada(s), ` +
      `${summary.daysClosed} dia(s) ${options.apply ? 'fechado(s)' : 'a fechar'}, ` +
      `${summary.streakResets} sequência(s) zerada(s) ──`,
  )
  if (!options.apply) {
    print('Simulação: nada foi gravado. Gravar exige --apply e autorização nomeada do Eduardo.')
  }
  return summary
}

async function main(): Promise<void> {
  const options = parseArguments(process.argv.slice(2))
  assertUtcProcess(process.env.TZ)
  const url = process.env.SUPABASE_URL ?? process.env.NEXT_PUBLIC_SUPABASE_URL
  assertStagingProject(url)
  const serviceRoleKey = process.env.SUPABASE_SERVICE_ROLE_KEY
  if (!url || !serviceRoleKey) throw new Error('SUPABASE_URL/SUPABASE_SERVICE_ROLE_KEY ausente')

  const supabase = createServiceClient({ url, serviceRoleKey })
  await runCloseOpenDays(supabase, options, (line) => console.log(line))
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  main().catch((error) => {
    console.error(error instanceof Error ? error.message : error)
    process.exit(1)
  })
}
