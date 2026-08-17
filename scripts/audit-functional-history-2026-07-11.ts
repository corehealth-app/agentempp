/**
 * Read-only audit of confirmed functional-history inconsistencies.
 * There is intentionally no apply mode: production repair must happen only
 * after the corrected application code is deployed and a fresh preview passes.
 */
import { spawnSync } from 'node:child_process'
import { dirname, resolve } from 'node:path'
import { fileURLToPath } from 'node:url'

if (process.argv.includes('--apply')) {
  throw new Error('Apply is not available for this audit. Run the dry-run only.')
}

const here = dirname(fileURLToPath(import.meta.url))
const root = resolve(here, '..')
const supabaseWorkdir = process.env.SUPABASE_WORKDIR ?? root
const sqlFile = resolve(here, 'sql/audit-functional-history-2026-07-11.dry-run.sql')

const result = spawnSync(
  'supabase',
  ['db', 'query', '--linked', '--file', sqlFile, '--output', 'json', '--agent=no'],
  { cwd: supabaseWorkdir, encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'] },
)

if (result.stdout) process.stdout.write(result.stdout)
if (result.stderr) process.stderr.write(result.stderr)
if (result.status !== 0) process.exit(result.status ?? 1)
