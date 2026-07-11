/**
 * Reparo auditavel do incidente nutricional de 10/07 e da proveniencia
 * contaminada por reuso de estimativas genericas.
 *
 * Default: dry-run read-only.
 * Apply exige as duas flags para evitar execucao acidental:
 *   pnpm --dir scripts repair:nutrition-provenance
 *   pnpm --dir scripts repair:nutrition-provenance -- --apply --confirm=nutrition-provenance-2026-07-11
 */
import { spawnSync } from 'node:child_process'
import { dirname, resolve } from 'node:path'
import { fileURLToPath } from 'node:url'

const here = dirname(fileURLToPath(import.meta.url))
const root = resolve(here, '..')
const supabaseWorkdir = process.env.SUPABASE_WORKDIR ?? root
const apply = process.argv.includes('--apply')
const confirmation = process.argv.find((arg) => arg.startsWith('--confirm='))?.slice(10)

if (apply && confirmation !== 'nutrition-provenance-2026-07-11') {
  throw new Error(
    'Apply bloqueado: use --confirm=nutrition-provenance-2026-07-11',
  )
}

const sqlFile = resolve(
  here,
  apply
    ? 'sql/repair-nutrition-provenance-2026-07-11.apply.sql'
    : 'sql/repair-nutrition-provenance-2026-07-11.dry-run.sql',
)

const result = spawnSync(
  'supabase',
  ['db', 'query', '--linked', '--file', sqlFile, '--output', 'json', '--agent=no'],
  { cwd: supabaseWorkdir, encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'] },
)

if (result.stdout) process.stdout.write(result.stdout)
if (result.stderr) process.stderr.write(result.stderr)
if (result.status !== 0) process.exit(result.status ?? 1)
