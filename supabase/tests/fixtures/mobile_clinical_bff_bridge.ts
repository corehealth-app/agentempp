/** Explicit local QA entrypoint, invoked ONLY by the guarded Python runner.
 * Real injected BFF -> real core -> private owned PostgreSQL; no HTTP/remote. */
import { execFileSync } from 'node:child_process'
import { createHash } from 'node:crypto'
import { readFileSync, statSync } from 'node:fs'
import { dirname, join, resolve } from 'node:path'
import type { ServiceClient } from '@mpp/db'
import type { MobileAuthContext } from '../../../apps/admin/src/lib/mobile-api/auth'
import { createClinicalDailyService } from '../../../apps/admin/src/lib/mobile-api/clinical-daily-service'
import { MobileApiError } from '../../../apps/admin/src/lib/mobile-api/http'
import { createSupabaseClinicalDailyRepository } from '../../../apps/admin/src/lib/mobile-api/supabase-clinical-daily'

const configPath = process.env.PERFORME_CLINICAL_SQL_CONFIG
const expectedStart = process.env.PERFORME_CLINICAL_SQL_START
const transport = process.env.PERFORME_CLINICAL_TRANSPORT ?? 'private'
if (transport !== 'private' && transport !== 'public-rpc') throw new Error('Unknown transport')
if (!configPath || !expectedStart) throw new Error('Explicit owned runtime required')
const config = JSON.parse(readFileSync(configPath, 'utf8'))
const marker = JSON.parse(readFileSync(join(dirname(config.data_directory), 'OWNER.json'), 'utf8'))
if (
  config.task !== 'performe-m3b-cycle-foundation' ||
  config.nonce !== marker.nonce ||
  marker.task !== config.task ||
  resolve(dirname(configPath)) !== resolve(dirname(config.data_directory)) ||
  !config.socket_directory.startsWith('/private/tmp/performe-m3b-') ||
  statSync(config.socket_directory).uid !== process.getuid?.() ||
  (statSync(config.socket_directory).mode & 0o077) !== 0 ||
  config.database !== 'postgres' ||
  config.port !== 22997 ||
  createHash('sha256').update(readFileSync(config.psql)).digest('hex') !== config.psql_sha256
)
  throw new Error('Owned runtime identity refused')
const args = [
  '-q',
  '-w',
  '-X',
  '-A',
  '-t',
  '-v',
  'ON_ERROR_STOP=1',
  '-h',
  config.socket_directory,
  '-p',
  String(config.port),
  '-U',
  'postgres',
  '-d',
  'postgres',
]
function query(sql: string): string {
  return execFileSync(config.psql, [...args, '-c', sql], {
    encoding: 'utf8',
    timeout: 30000,
    maxBuffer: 2 ** 21,
  }).trim()
}
const guard = JSON.parse(
  query(
    "SELECT jsonb_build_object('started',pg_postmaster_start_time()::text,'data',current_setting('data_directory')," +
      "'listen',current_setting('listen_addresses'),'socket',current_setting('unix_socket_directories'),'user',current_user," +
      "'db',current_database(),'tcp',inet_server_addr(),'cron',current_setting('cron.launch_active_jobs')='off'," +
      "'net',current_setting('pg_net.batch_size')='0' AND NOT EXISTS(SELECT 1 FROM net.http_request_queue))",
  ),
)
if (
  guard.started !== expectedStart ||
  resolve(guard.data) !== resolve(config.data_directory) ||
  guard.listen !== '' ||
  guard.socket !== config.socket_directory ||
  guard.user !== 'postgres' ||
  guard.db !== 'postgres' ||
  guard.tcp !== null ||
  !guard.cron ||
  !guard.net
)
  throw new Error('Owned runtime guard refused')
const literal = (value: string) => `'${value.replaceAll("'", "''")}'`
const uid = (n: number) => `b3b01000-0000-4000-8000-${String(n).padStart(12, '0')}`
const owner = uid(1906),
  authId = uid(1907),
  firstKey = uid(1908),
  secondKey = uid(1909),
  staleKey = uid(1910)
const profile = JSON.parse(
  query(
    "SELECT m3b_cycle_test.scheduled(1906,'recomp_to_maintenance',clock_timestamp()-interval '6 days')",
  ),
)
if (profile.user !== owner) throw new Error('Unexpected fixture identity')
query(`UPDATE public.user_profiles SET body_fat_percent=NULL WHERE user_id=${literal(owner)}`)
let captureCalls = 0,
  applyCalls = 0,
  injectRisk = false
const privateRepo = {
  async findReceipt(userId: string, operationKey: string) {
    const raw = query(
      "SELECT jsonb_build_object('user_id',user_id,'operation_key',operation_key,'result',result) " +
        `FROM private.mobile_clinical_daily_keys WHERE user_id=${literal(userId)} AND operation_key=${literal(operationKey)}`,
    )
    return raw ? JSON.parse(raw) : null
  },
  async capture(userId: string) {
    captureCalls++
    return JSON.parse(
      query(
        `SELECT private.capture_mobile_clinical_context_at(${literal(userId)},'APPLICATION',NULL,NULL)`,
      ),
    )
  },
  async apply(userId: string, operationKey: string, contextHash: string, calculation: unknown) {
    applyCalls++
    if (injectRisk) {
      injectRisk = false
      query(
        `SELECT public.declare_mobile_health_risk(${literal(owner)},${literal(uid(1911))},ARRAY['reduced_intake'])`,
      )
    }
    const result = JSON.parse(
      query(
        `SELECT private.apply_mobile_clinical_daily_at(${literal(userId)},${literal(operationKey)},` +
          `${literal(contextHash)},${literal(JSON.stringify(calculation))}::jsonb,NULL)`,
      ),
    )
    return { user_id: userId, operation_key: operationKey, result }
  },
}
// Only the network boundary is replaced: real BFF + calculator + adapter +
// public SQL wrappers execute under the actual backend SQL role and JWT.
const rpcCalls: string[] = []
const publicRepo = createSupabaseClinicalDailyRepository({
  async rpc(name: string, parameters: Record<string, unknown>) {
    const signatures: Record<string, string[]> = {
      get_mobile_clinical_daily_receipt: ['p_operation_key', 'p_user_id'],
      get_mobile_clinical_daily_context: ['p_user_id'],
      apply_mobile_clinical_daily: [
        'p_calculation',
        'p_context_hash',
        'p_operation_key',
        'p_user_id',
      ],
    }
    const expected = signatures[name]
    if (!expected || JSON.stringify(Object.keys(parameters).sort()) !== JSON.stringify(expected))
      throw new Error('Unexpected public RPC scope')
    if (parameters.p_user_id !== owner) throw new Error('Unexpected public RPC owner')
    rpcCalls.push(name)
    let call: string
    if (name === 'get_mobile_clinical_daily_receipt') {
      call = `public.get_mobile_clinical_daily_receipt(${literal(owner)},${literal(String(parameters.p_operation_key))})`
    } else if (name === 'get_mobile_clinical_daily_context') {
      captureCalls++
      call = `public.get_mobile_clinical_daily_context(${literal(owner)})`
    } else {
      applyCalls++
      if (injectRisk) {
        injectRisk = false
        query(
          `SELECT public.declare_mobile_health_risk(${literal(owner)},${literal(uid(1911))},ARRAY['reduced_intake'])`,
        )
      }
      call =
        `public.apply_mobile_clinical_daily(${literal(owner)},${literal(String(parameters.p_operation_key))},` +
        `${literal(String(parameters.p_context_hash))},${literal(JSON.stringify(parameters.p_calculation))}::jsonb)`
    }
    try {
      const raw = execFileSync(
        config.psql,
        [
          ...args,
          '-v',
          'VERBOSITY=sqlstate',
          '-c',
          `BEGIN;SET LOCAL ROLE service_role;SET LOCAL request.jwt.claim.role='service_role';SELECT ${call};COMMIT;`,
        ],
        { encoding: 'utf8', timeout: 30000, maxBuffer: 2 ** 21, stdio: ['pipe', 'pipe', 'pipe'] },
      ).trim()
      return { data: raw ? JSON.parse(raw) : null, error: null }
    } catch (error) {
      const stderr =
        error && typeof error === 'object' && 'stderr' in error ? String(error.stderr) : ''
      const code = /^ERROR:\s+([A-Z0-9]{5})(?:\s|:|$)/m.exec(stderr)?.[1]
      // Do not expose SQL text/details through the RPC error envelope.
      return { data: null, error: { code: code ?? 'LOCAL_TRANSPORT_FAILED' } }
    }
  },
} as unknown as ServiceClient)
const repo = transport === 'public-rpc' ? publicRepo : privateRepo
const auth: MobileAuthContext = {
  userId: owner,
  authUserId: authId,
  accessToken: 'synthetic-no-auth-network',
  identity: {
    id: authId,
    email: 'synthetic@example.invalid',
    emailConfirmedAt: '2026-10-01T00:00:00Z',
  },
  patient: {
    id: owner,
    authUserId: authId,
    email: 'synthetic@example.invalid',
    name: null,
    status: 'active',
    locale: 'pt-BR',
    timezone: 'America/Sao_Paulo',
    country: 'BR',
    countryConfirmed: true,
  },
}
const service = createClinicalDailyService({ enabled: true, repository: repo })
const cases: string[] = []
const historicalSnapshots = () =>
  query(`SELECT coalesce(jsonb_agg(to_jsonb(s) ORDER BY date),'[]'::jsonb)
 FROM public.daily_snapshots s WHERE user_id=${literal(owner)} AND date<(clock_timestamp() AT TIME ZONE 'America/Sao_Paulo')::date`)
const originalHistoricalSnapshots = historicalSnapshots()
function check(value: unknown, name: string) {
  if (!value) throw new Error(`Clinical BFF QA failed: ${name}`)
  cases.push(name)
}
const first = await service.apply(auth, { operationKey: firstKey })
check(
  first.availability === 'applied' && 'state' in first && first.state === 'running',
  `real BFF/core applies daily stage through ${transport}`,
)
const stored = JSON.parse(
  query(
    `SELECT calculation FROM private.mobile_clinical_daily_applications WHERE user_id=${literal(owner)} ORDER BY application_no LIMIT 1`,
  ),
)
check(
  JSON.stringify(Object.keys(stored).sort()) ===
    JSON.stringify(
      [
        'version',
        'formulaKcal',
        'maintenanceKcal',
        'sedentaryKcal',
        'proteinTarget',
        'maintenanceProteinTarget',
      ].sort(),
    ) &&
    stored.formulaKcal === 2713 &&
    stored.maintenanceKcal === 2713 &&
    stored.sedentaryKcal === 2100 &&
    stored.proteinTarget === 144 &&
    stored.maintenanceProteinTarget === 144,
  'actual persisted calculation uses captured real core formula',
)
check(
  'targets' in first &&
    query(`SELECT count(*)=1 AND min(calories_target)=${first.targets.calories_target}
    FROM public.daily_snapshots WHERE user_id=${literal(owner)} AND date=(clock_timestamp() AT TIME ZONE 'America/Sao_Paulo')::date`) ===
      't' &&
    historicalSnapshots() === originalHistoricalSnapshots,
  'daily application materializes exactly its current target and preserves all historical snapshots',
)
check(
  JSON.stringify(await service.apply(auth, { operationKey: firstKey })) === JSON.stringify(first) &&
    captureCalls === 1 &&
    applyCalls === 1,
  'same request returns original without capture or second application',
)
injectRisk = true
let stale = false
try {
  await service.apply(auth, { operationKey: staleKey })
} catch (error) {
  stale =
    transport === 'public-rpc'
      ? error instanceof MobileApiError &&
        error.status === 409 &&
        error.code === 'mobile_clinical_daily_changed' &&
        error.message === 'Clinical update changed; refresh before trying again'
      : error instanceof Error && error.message === 'Clinical update unavailable'
}
check(
  stale &&
    query(
      `SELECT count(*) FROM private.mobile_clinical_daily_applications WHERE user_id=${literal(owner)}`,
    ) === '1',
  'new committed risk between BFF capture and write invalidates the old proposal without an application',
)
const effects = () => query(`SELECT md5(m3b_cycle_test.original_state(${literal(owner)})::text)`)
let beforeReplay = effects(),
  readsBeforeReplay = captureCalls,
  writesBeforeReplay = applyCalls
check(
  JSON.stringify(await service.apply(auth, { operationKey: firstKey })) === JSON.stringify(first) &&
    captureCalls === readsBeforeReplay &&
    applyCalls === writesBeforeReplay &&
    effects() === beforeReplay,
  'original running acknowledgement after new risk precedes recapture and cannot erase the risk',
)
const second = await service.apply(auth, { operationKey: secondKey })
check(
  second.availability === 'applied' &&
    'state' in second &&
    second.state === 'suspended' &&
    second.targets.calories_target === 2100,
  'fresh guarded BFF request suspends at actual current target',
)
check(
  query(
    `SELECT calculation->'formulaKcal'='null'::jsonb FROM private.mobile_clinical_daily_applications WHERE user_id=${literal(owner)} ORDER BY application_no DESC LIMIT 1`,
  ) === 't',
  'guarded suspension stores no newly offered formula',
)
query(
  `SELECT public.declare_mobile_health_risk(${literal(owner)},${literal(uid(1912))},ARRAY['professional_diet'])`,
)
beforeReplay = effects()
readsBeforeReplay = captureCalls
writesBeforeReplay = applyCalls
check(
  JSON.stringify(await service.apply(auth, { operationKey: secondKey })) ===
    JSON.stringify(second) &&
    captureCalls === readsBeforeReplay &&
    applyCalls === writesBeforeReplay &&
    effects() === beforeReplay,
  'original suspension acknowledgement after a newer risk cannot recalculate or change safety',
)
query(`SELECT public.reset_user_conversation_atomic(${literal(owner)},true)`)
beforeReplay = effects()
readsBeforeReplay = captureCalls
writesBeforeReplay = applyCalls
check(
  JSON.stringify(await service.apply(auth, { operationKey: firstKey })) === JSON.stringify(first) &&
    captureCalls === readsBeforeReplay &&
    applyCalls === writesBeforeReplay &&
    effects() === beforeReplay,
  'original acknowledgement survives actual signup reset without resurrecting effects',
)
check(
  JSON.stringify(await service.apply(auth, { operationKey: secondKey })) ===
    JSON.stringify(second) &&
    captureCalls === readsBeforeReplay &&
    applyCalls === writesBeforeReplay &&
    effects() === beforeReplay,
  'original suspended acknowledgement survives reset without resuming an old episode',
)
check(
  query(
    `SELECT count(*) FROM private.mobile_clinical_daily_applications WHERE user_id=${literal(owner)}`,
  ) === '2',
  'replay and stale write add no extra stages',
)
process.stdout.write(
  `${JSON.stringify({
    status:
      transport === 'public-rpc'
        ? 'PASS_INJECTED_BFF_CORE_PUBLIC_RPC_SQL'
        : 'PASS_INJECTED_BFF_CORE_PRIVATE_SQL',
    transport,
    rpcCalls,
    cases,
    captureCalls,
    applyCalls,
    http: false,
    realSignupFullCalculation: false,
    storage: false,
    remote: false,
  })}\n`,
)
