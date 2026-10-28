/** Explicit local BFF/core/adapter/public SQL QA; not HTTP or deployed QA. */
import assert from 'node:assert/strict'
import { execFileSync } from 'node:child_process'
import { createHash } from 'node:crypto'
import { readFileSync, statSync } from 'node:fs'
import { dirname, join, resolve } from 'node:path'
import type { ServiceClient } from '@mpp/db'
import type { MobileAuthContext } from '../../../apps/admin/src/lib/mobile-api/auth'
import { createClinicalCloseDaysEffect } from '../../../apps/admin/src/lib/mobile-api/clinical-close-days-effect'
import { clinicalClosedResultSchema } from '../../../apps/admin/src/lib/mobile-api/clinical-day-close-contracts'
import { createClinicalDayCloseService } from '../../../apps/admin/src/lib/mobile-api/clinical-day-close-service'
import { createCurrentClinicalReadModel } from '../../../apps/admin/src/lib/mobile-api/current-clinical-read-model'
import { MobileApiError } from '../../../apps/admin/src/lib/mobile-api/http'
import { createSupabaseClinicalDayCloseRepository } from '../../../apps/admin/src/lib/mobile-api/supabase-clinical-day-close'
import { createSupabaseCurrentClinicalStateSource } from '../../../apps/admin/src/lib/mobile-api/supabase-current-clinical-state'

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
  '-v',
  'VERBOSITY=verbose',
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

if (transport !== 'public-rpc') throw new Error('Whole-close QA requires public backend RPC')
const cases: string[] = []
const calls: string[] = []
const savedConfig = query(
  "SELECT jsonb_agg(to_jsonb(c) ORDER BY key) FROM public.global_config c WHERE key IN('calc.xp_rules','calc.kcal_block')",
)
let activeOwner = ''
let beforeApply: (() => void) | null = null
const sqlLiteral = (v: unknown) =>
  v === null ? 'NULL' : literal(typeof v === 'string' ? v : JSON.stringify(v))
const rpcClient = {
  async rpc(name: string, args: Record<string, unknown>) {
    const signatures: Record<string, string[]> = {
      get_mobile_current_clinical_state: ['p_body', 'p_expected', 'p_mode', 'p_user_id'],
      get_mobile_clinical_day_close_receipt: ['p_operation_key', 'p_user_id'],
      capture_mobile_clinical_day_close: [
        'p_close_date',
        'p_expected_timezone',
        'p_from',
        'p_user_id',
      ],
      apply_mobile_clinical_day_close: [
        'p_close_date',
        'p_context_hash',
        'p_effect',
        'p_expected_timezone',
        'p_from',
        'p_operation_key',
        'p_user_id',
      ],
    }
    assert.deepEqual(Object.keys(args).sort(), signatures[name])
    assert.equal(args.p_user_id, activeOwner)
    calls.push(name)
    let expression: string
    if (name === 'get_mobile_current_clinical_state')
      expression = `public.${name}(${sqlLiteral(args.p_user_id)},${sqlLiteral(args.p_mode)},${sqlLiteral(args.p_body)}::jsonb,${sqlLiteral(args.p_expected)}::jsonb)`
    else if (name === 'get_mobile_clinical_day_close_receipt')
      expression = `public.${name}(${sqlLiteral(args.p_user_id)},${sqlLiteral(args.p_operation_key)})`
    else if (name === 'capture_mobile_clinical_day_close')
      expression = `public.${name}(${sqlLiteral(args.p_user_id)},${sqlLiteral(args.p_from)},${sqlLiteral(args.p_close_date)},${sqlLiteral(args.p_expected_timezone)})`
    else {
      if (beforeApply) {
        const action = beforeApply
        beforeApply = null
        action()
      }
      expression = `public.${name}(${sqlLiteral(args.p_user_id)},${sqlLiteral(args.p_operation_key)},${sqlLiteral(args.p_from)},${sqlLiteral(args.p_close_date)},${sqlLiteral(args.p_expected_timezone)},${sqlLiteral(args.p_context_hash)},${sqlLiteral(args.p_effect)}::jsonb)`
    }
    try {
      const raw = query(
        `BEGIN;SET LOCAL ROLE service_role;SET LOCAL request.jwt.claim='{"role":"service_role"}';SELECT ${expression};COMMIT;`,
      )
      return { data: raw ? JSON.parse(raw) : null, error: null }
    } catch (error) {
      const stderr =
        error && typeof error === 'object' && 'stderr' in error ? String(error.stderr) : ''
      return {
        data: null,
        error: { code: /ERROR:\s+([A-Z0-9]{5}):/.exec(stderr)?.[1] ?? 'unknown' },
      }
    }
  },
}
const repo = createSupabaseClinicalDayCloseRepository(rpcClient as unknown as ServiceClient)
const service = createClinicalDayCloseService({ enabled: true, repository: repo })
function seed(n: number, deficit = 500) {
  activeOwner = uid(n)
  const q = JSON.parse(
    query(`SELECT m3b_cycle_test.close_seed(${n},'recomposicao',${deficit})`),
  ) as {
    user: string
    from: string
    date: string
    zone: string
  }
  assert.equal(q.user, activeOwner)
  const auth: MobileAuthContext = {
    userId: q.user,
    authUserId: uid(3499),
    accessToken: 'synthetic-only',
    identity: {
      id: uid(3499),
      email: 'qa@example.invalid',
      emailConfirmedAt: '2026-10-01T00:00:00Z',
    },
    patient: {
      id: q.user,
      authUserId: uid(3499),
      email: 'qa@example.invalid',
      name: null,
      locale: 'pt-BR',
      timezone: q.zone,
      country: 'BR',
      countryConfirmed: true,
      status: 'active',
    },
  }
  const command = {
    operationKey: uid(n + 100),
    from: q.from,
    date: q.date as string | null,
    timezone: q.zone,
  }
  return { q, auth, command }
}
const state = () => query(`SELECT m3b_cycle_test.original_state(${literal(activeOwner)})`)
async function expectChanged(action: () => Promise<unknown>) {
  try {
    await action()
  } catch (error) {
    assert(
      error instanceof MobileApiError &&
        error.status === 409 &&
        error.code === 'mobile_clinical_close_changed',
    )
    return
  }
  throw new Error('Expected whole-close conflict')
}
const first = seed(3450)
const firstResult = clinicalClosedResultSchema.parse(await service.run(first.auth, first.command))
assert.equal(firstResult.detail.xpEarned, 15)
assert.equal(firstResult.detail.blockCredit, 900)
assert.equal(firstResult.detail.blockCreditStatus, 'calculated')
assert.equal(firstResult.detail.progress.deficitBlock, 900)
assert.deepEqual(calls.slice(-3), [
  'get_mobile_clinical_day_close_receipt',
  'capture_mobile_clinical_day_close',
  'apply_mobile_clinical_day_close',
])
assert.equal(
  query(
    `SELECT day_closed AND calories_consumed=1600 AND calories_target=2000 AND protein_target=130 AND water_consumed_ml=777 FROM public.daily_snapshots WHERE user_id=${literal(activeOwner)}`,
  ),
  't',
)
cases.push('actual_core_fields_XP_credit_progress_atomic_SQL')
let before = state(),
  offset = calls.length
assert.deepEqual(await service.run(first.auth, first.command), firstResult)
assert.equal(state(), before)
assert.deepEqual(calls.slice(offset), ['get_mobile_clinical_day_close_receipt'])
cases.push('original_receipt_no_duplicate_or_recapture')
query(`SELECT public.reset_user_conversation_atomic(${literal(activeOwner)},true)`)
before = state()
offset = calls.length
assert.deepEqual(await service.run(first.auth, first.command), firstResult)
assert.equal(state(), before)
assert.deepEqual(calls.slice(offset), ['get_mobile_clinical_day_close_receipt'])
cases.push('original_receipt_after_actual_signup_reset')
const switched = seed(3470, 400)
query(`SELECT m3b_cycle_test.close_switch_to_maintenance(${sqlLiteral(switched.q)}::jsonb)`)
const currentPhaseAndTarget = () =>
  query(`SELECT jsonb_build_object('profile',to_jsonb(p),'today',to_jsonb(s))
 FROM public.user_profiles p JOIN public.daily_snapshots s ON s.user_id=p.user_id
 AND s.date=(clock_timestamp() AT TIME ZONE 'America/Sao_Paulo')::date WHERE p.user_id=${literal(activeOwner)}`)
const currentAfterSwitch = currentPhaseAndTarget()
assert.equal(JSON.parse(currentAfterSwitch).profile.current_protocol, 'manutencao')
const switchedResult = clinicalClosedResultSchema.parse(
  await service.run(switched.auth, switched.command),
)
assert.equal(switchedResult.detail.caloriesTarget, 2000)
assert.equal(switchedResult.detail.proteinTarget, 130)
assert.equal(switchedResult.detail.blockCredit, 800)
assert.equal(switchedResult.detail.blockCreditStatus, 'calculated')
assert.equal(currentPhaseAndTarget(), currentAfterSwitch)
assert.equal(
  query(
    `SELECT current_protocol FROM public.daily_snapshots WHERE user_id=${literal(activeOwner)} AND date=${literal(switched.q.date)}`,
  ),
  'recomposicao',
)
cases.push(
  'historical_400_recomposition_survives_real_current_FULL_maintenance_and_keeps_today_unchanged',
)
const proteinOnly = seed(3471)
query(`UPDATE public.daily_snapshots SET protein_target=125 WHERE user_id=${literal(activeOwner)}`)
const proteinResult = clinicalClosedResultSchema.parse(
  await service.run(proteinOnly.auth, proteinOnly.command),
)
assert.equal(proteinResult.detail.proteinTarget, 125)
assert.equal(proteinResult.detail.blockCredit, 900)
assert.equal(proteinResult.detail.blockCreditStatus, 'calculated')
cases.push('protein_only_historical_correction_preserves_calorie_deficit_origin')
const unknown = seed(3472)
query(`UPDATE public.daily_snapshots SET calories_target=2001 WHERE user_id=${literal(activeOwner)};
 UPDATE public.daily_snapshots SET calories_target=2000 WHERE user_id=${literal(activeOwner)};
 INSERT INTO public.user_progress(user_id,xp_total,blocks_completed,deficit_block) VALUES(${literal(activeOwner)},90,1,400)`)
const unknownResult = clinicalClosedResultSchema.parse(
  await service.run(unknown.auth, unknown.command),
)
assert.equal(unknownResult.detail.caloriesTarget, 2000)
assert.equal(unknownResult.detail.xpEarned, 15)
assert.equal(unknownResult.detail.progress.xpTotal, 105)
assert.equal(unknownResult.detail.blockCredit, 0)
assert.equal(unknownResult.detail.blockCreditStatus, 'preserved_unknown')
assert.equal(unknownResult.detail.progress.blocksCompleted, 1)
assert.equal(unknownResult.detail.progress.deficitBlock, 400)
cases.push('edited_restored_calories_have_unknown_origin_close_XP_preserve_prior_block')
const noPhase = seed(3473)
query(
  `UPDATE public.daily_snapshots SET current_protocol=NULL WHERE user_id=${literal(activeOwner)}`,
)
const noPhaseResult = clinicalClosedResultSchema.parse(
  await service.run(noPhase.auth, noPhase.command),
)
assert.equal(noPhaseResult.detail.blockCredit, 0)
assert.equal(noPhaseResult.detail.blockCreditStatus, 'preserved_unknown')
assert.equal(noPhaseResult.detail.xpEarned, 15)
assert.equal(
  query(
    `SELECT day_closed AND current_protocol IS NULL AND calories_target=2000 FROM public.daily_snapshots WHERE user_id=${literal(activeOwner)}`,
  ),
  't',
)
cases.push('unknown_historical_phase_remains_NULL_without_defaulting_current_recomposition')
const originRace = seed(3474)
let afterOrigin = ''
beforeApply = () => {
  query(`UPDATE public.daily_snapshots SET calories_target=2001 WHERE user_id=${literal(activeOwner)};
   UPDATE public.daily_snapshots SET calories_target=2000 WHERE user_id=${literal(activeOwner)}`)
  afterOrigin = state()
}
await expectChanged(() => service.run(originRace.auth, originRace.command))
assert.equal(state(), afterOrigin)
cases.push('calorie_origin_invalidated_after_capture_refuses_whole_close_without_partial_effects')
const highDeficit = seed(3475, 600)
const highDeficitResult = clinicalClosedResultSchema.parse(
  await service.run(highDeficit.auth, highDeficit.command),
)
assert.equal(highDeficitResult.detail.blockCredit, 1000)
assert.equal(highDeficitResult.detail.blockCreditStatus, 'calculated')
cases.push('historical_600_deficit_uses_its_own_applied_source')
const risk = seed(3451)
let afterRisk = ''
beforeApply = () => {
  query(
    `SELECT public.declare_mobile_health_risk(${literal(activeOwner)},${literal(uid(3651))},ARRAY['reduced_intake'])`,
  )
  afterRisk = state()
}
await expectChanged(() => service.run(risk.auth, risk.command))
assert.equal(state(), afterRisk)
cases.push('new_health_revision_no_partial_fields_progress_events_or_receipt')
const manual = seed(3452)
query(
  `UPDATE public.user_profiles SET body_fat_percent=24 WHERE user_id=${literal(activeOwner)};UPDATE public.daily_snapshots SET calories_target=NULL WHERE user_id=${literal(activeOwner)}`,
)
const manualResult = clinicalClosedResultSchema.parse(
  await service.run(manual.auth, manual.command),
)
assert.equal(manualResult.detail.caloriesTarget, null)
assert.equal(manualResult.detail.proteinTarget, 130)
cases.push('unproven_report_does_not_fill_absent_historical_target')
const held = seed(3453)
query(
  `UPDATE public.daily_snapshots SET calories_target=NULL,protein_target=NULL WHERE user_id=${literal(activeOwner)};SELECT public.declare_mobile_health_risk(${literal(activeOwner)},${literal(uid(3653))},ARRAY['professional_diet'])`,
)
const heldResult = clinicalClosedResultSchema.parse(await service.run(held.auth, held.command))
assert.equal(heldResult.detail.caloriesTarget, null)
assert.equal(heldResult.detail.proteinTarget, null)
assert.equal(heldResult.detail.xpEarned, 15)
assert.equal(heldResult.detail.blockCredit, 0)
assert.equal(heldResult.detail.blockCreditStatus, 'preserved_unknown')
cases.push('HOLD_absent_targets_existing_protein_XP_unknown_deficit_preserves_block')
const xp = seed(3454)
query(
  `UPDATE public.global_config SET value='{"base":10,"training_bonus":5,"protein_bonus":5,"protein_threshold_g":100,"meal_xp":2,"protein_meta_xp":7}',updated_at=clock_timestamp() WHERE key='calc.xp_rules';INSERT INTO public.meal_logs(user_id,snapshot_id,meal_type,food_name,quantity_g,kcal,protein_g,carbs_g,fat_g,consumed_at) SELECT user_id,snapshot_id,meal_type,food_name,quantity_g,kcal,protein_g,carbs_g,fat_g,consumed_at FROM public.meal_logs WHERE user_id=${literal(activeOwner)}`,
)
const xpResult = clinicalClosedResultSchema.parse(await service.run(xp.auth, xp.command))
assert.equal(xpResult.detail.xpEarned, 11)
assert.equal(xpResult.detail.blockCredit, -700)
cases.push('fresh_MPP_config_two_food_rows_same_meal_and_negative_credit')
const configRace = seed(3455)
let afterConfig = ''
beforeApply = () => {
  query(
    `UPDATE public.global_config SET value='7701',updated_at=clock_timestamp() WHERE key='calc.kcal_block'`,
  )
  afterConfig = state()
}
await expectChanged(() => service.run(configRace.auth, configRace.command))
assert.equal(state(), afterConfig)
cases.push('configuration_changed_after_real_core_calculation_refuses_all_effects')
const reset = seed(3456)
query(
  `DELETE FROM public.meal_logs WHERE user_id=${literal(activeOwner)};DELETE FROM public.daily_snapshots WHERE user_id=${literal(activeOwner)};INSERT INTO public.user_progress(user_id,current_streak,longest_streak,last_active_date,xp_total) VALUES(${literal(activeOwner)},4,9,${literal(reset.q.date)}::date-3,90)`,
)
reset.command.date = null
const resetResult = await service.run(reset.auth, reset.command)
assert.equal(
  query(
    `SELECT current_streak=0 AND longest_streak=9 AND xp_total=90 FROM public.user_progress WHERE user_id=${literal(activeOwner)}`,
  ),
  't',
)
before = state()
offset = calls.length
assert.deepEqual(await service.run(reset.auth, reset.command), resetResult)
assert.equal(state(), before)
assert.deepEqual(calls.slice(offset), ['get_mobile_clinical_day_close_receipt'])
cases.push('empty_discovery_atomic_inactivity_reset_and_original_replay')
const pending = seed(3457)
query(
  `DELETE FROM public.meal_logs WHERE user_id=${literal(activeOwner)};DELETE FROM public.daily_snapshots WHERE user_id=${literal(activeOwner)};INSERT INTO public.user_progress(user_id,current_streak,longest_streak,last_active_date,xp_total) VALUES(${literal(activeOwner)},4,9,${literal(pending.q.date)}::date-3,90)`,
)
pending.command.date = null
let afterPending = ''
beforeApply = () => {
  query(
    `INSERT INTO public.meal_logs(user_id,meal_type,food_name,quantity_g,kcal,protein_g,carbs_g,fat_g,consumed_at) VALUES(${literal(activeOwner)},'almoco','synthetic pending',100,50,0,0,0,(${literal(pending.q.date)}::date+time '12:00') AT TIME ZONE 'America/Sao_Paulo')`,
  )
  afterPending = state()
}
await expectChanged(() => service.run(pending.auth, pending.command))
assert.equal(state(), afterPending)
cases.push('new_activity_after_reset_capture_cannot_erase_streak')
const fractional = seed(3458)
query(`UPDATE public.meal_logs SET kcal=999.90 WHERE user_id=${literal(activeOwner)}`)
const fractionalResult = clinicalClosedResultSchema.parse(
  await service.run(fractional.auth, fractional.command),
)
assert.equal(fractionalResult.detail.caloriesConsumed, 1000)
assert.equal(fractionalResult.detail.blockCredit, 500)
cases.push('raw_underregistration_boundary_before_rounding')

// Use the production discovery script and both clinical ports together. The
// shim replaces only PostgREST transport with SELECTs in this owned runtime;
// there is deliberately no legacy writer, generic RPC or arbitrary table API.
const discoveryReads: string[] = []
const columns: Record<string, readonly string[]> = {
  users: ['id', 'wpp', 'timezone'],
  user_progress: ['user_id', 'current_streak', 'last_active_date', 'updated_at'],
  daily_snapshots: ['user_id', 'date', 'day_closed'],
  meal_logs: ['user_id', 'consumed_at'],
  workout_logs: ['user_id', 'performed_at'],
  messages: ['user_id', 'created_at', 'direction'],
}
function discoveryQuery(table: string) {
  const allowed = columns[table]
  assert(allowed, 'Discovery table refused')
  let selected: string[] = [],
    filters: string[] = [],
    ordering = '',
    limit = 1000
  let ownerChecked = false,
    single = false
  const column = (name: string) => {
    assert(allowed.includes(name), 'Discovery column refused')
    return `"${name}"`
  }
  const filter = (name: string, operator: string, value: unknown) => {
    if (name === (table === 'users' ? 'id' : 'user_id') && operator === '=') {
      assert.equal(value, activeOwner)
      ownerChecked = true
    }
    assert(typeof value === 'string' || typeof value === 'boolean')
    filters.push(
      `${column(name)}${operator}${typeof value === 'boolean' ? String(value) : literal(value)}`,
    )
    return builder
  }
  const read = async () => {
    assert(ownerChecked && selected.length > 0, 'Owner-scoped SELECT required')
    const sql = `SELECT coalesce(jsonb_agg(to_jsonb(r)),'[]'::jsonb) FROM (SELECT ${selected.join(',')} FROM public."${table}" WHERE ${filters.join(' AND ')}${ordering} LIMIT ${limit}) r`
    const rows = JSON.parse(
      query(
        `BEGIN;SET LOCAL ROLE service_role;SET LOCAL request.jwt.claim='{"role":"service_role"}';${sql};COMMIT;`,
      ),
    ) as unknown[]
    discoveryReads.push(table)
    if (single) assert(rows.length <= 1, 'Multiple discovery rows refused')
    return { data: single ? (rows[0] ?? null) : rows, error: null }
  }
  // All fluent calls above the await run synchronously, before this microtask.
  // Keep a real Promise rather than installing a custom then property.
  const builder = Object.assign(Promise.resolve().then(read), {
    select(names: string) {
      selected = names.split(',').map((name) => column(name.trim()))
      return builder
    },
    eq(name: string, value: unknown) {
      return filter(name, '=', value)
    },
    gte(name: string, value: unknown) {
      return filter(name, '>=', value)
    },
    lte(name: string, value: unknown) {
      return filter(name, '<=', value)
    },
    lt(name: string, value: unknown) {
      return filter(name, '<', value)
    },
    order(name: string, options: { ascending: boolean }) {
      ordering = ` ORDER BY ${column(name)} ${options.ascending ? 'ASC' : 'DESC'}`
      return builder
    },
    limit(value: number) {
      assert(Number.isInteger(value) && value > 0 && value <= 1000)
      limit = value
      return builder
    },
    maybeSingle() {
      single = true
      return builder
    },
  })
  return builder
}
query(
  `UPDATE public.global_config c SET value=s.value,updated_at=s.updated_at FROM jsonb_to_recordset(${literal(savedConfig)}::jsonb) AS s(key text,value jsonb,updated_at timestamptz) WHERE c.key=s.key`,
)
const sweep = seed(3460)
query(`INSERT INTO public.daily_snapshots(user_id,date,calories_target,protein_target,water_consumed_ml)
  SELECT ${literal(activeOwner)},${literal(sweep.q.date)}::date-n,2000,130,777 FROM generate_series(1,3) n;
  INSERT INTO public.meal_logs(user_id,snapshot_id,meal_type,food_name,quantity_g,kcal,protein_g,carbs_g,fat_g,consumed_at)
  SELECT user_id,id,'almoco','synthetic sweep meal',600,1600,100,90,20,(date+time '12:00') AT TIME ZONE 'America/Sao_Paulo'
  FROM public.daily_snapshots WHERE user_id=${literal(activeOwner)} AND date<${literal(sweep.q.date)}::date`)
const discoveryClient = {
  rpc: rpcClient.rpc.bind(rpcClient),
  from: discoveryQuery,
} as unknown as ServiceClient
const current = createCurrentClinicalReadModel(
  discoveryClient,
  createSupabaseCurrentClinicalStateSource(discoveryClient),
)
const url = 'https://bodyflow.test/api/mobile/v1/today?clinical_policy=current_clinical_v1'
const admission = await current.preflight(sweep.auth, url, 'today')
let operation = 3700
const effect = createClinicalCloseDaysEffect({
  env: {
    MOBILE_DAY_CLOSE_FROM: sweep.q.from,
    MOBILE_DAY_CLOSE_PROJECT_REF: 'xitugspwfxkcluxvrdeg',
    NEXT_PUBLIC_SUPABASE_URL: 'https://xitugspwfxkcluxvrdeg.supabase.co',
  },
  now: new Date(admission.state.observed_at),
  nextOperationKey: () => uid(++operation),
})
offset = calls.length
const scope = { auth: sweep.auth, supabase: discoveryClient, url, admission }
await effect(scope)
assert.equal(
  query(
    `SELECT count(*) FROM public.daily_snapshots WHERE user_id=${literal(activeOwner)} AND day_closed`,
  ),
  '3',
)
assert.equal(
  calls.slice(offset).filter((name) => name === 'apply_mobile_clinical_day_close').length,
  3,
)
assert.equal(operation, 3703, 'Pending date must prevent inactivity reset')
await effect(scope)
assert.equal(
  query(
    `SELECT count(*) FROM public.daily_snapshots WHERE user_id=${literal(activeOwner)} AND day_closed`,
  ),
  '4',
)
assert.equal(
  query(
    `SELECT xp_total=60 AND deficit_block=900 AND current_streak=4 FROM public.user_progress WHERE user_id=${literal(activeOwner)}`,
  ),
  't',
)
assert.equal(
  query(
    `SELECT count(*) FROM public.product_events WHERE user_id=${literal(activeOwner)} AND event='daily_closer.completed'`,
  ),
  '4',
)
before = state()
offset = calls.length
await effect(scope)
assert.equal(state(), before)
assert.deepEqual(calls.slice(offset), [], 'Completed sweep must not repeat SQL applications')
assert(discoveryReads.includes('users') && discoveryReads.includes('messages'))
cases.push('actual_preflight_HTTP_effect_paired_sweep_three_day_budget_resume_no_legacy_writes')
console.log(
  JSON.stringify({
    status: 'PASS_ACTUAL_CLOSER_BFF_CORE_PUBLIC_RPC_SQL',
    cases,
    public_rpc_calls: calls.length,
    discovery_reads: discoveryReads.length,
    remote_operations: 0,
    HTTP_QA: false,
    Storage_QA: false,
    synthetic_accounts_only: true,
  }),
)
