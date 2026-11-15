/** Actual new HTTP handlers -> real runtime/protected writer -> owned Unix PG.
 * External token verification only is synthetic. No hosted/native/release claim. */
import assert from 'node:assert/strict'
import { execFileSync } from 'node:child_process'
import { createHash } from 'node:crypto'
import { readFileSync, statSync, writeFileSync } from 'node:fs'
import { createRequire } from 'node:module'

const [registry, fixture, bundle, output] = process.argv.slice(2),
  arena = JSON.parse(readFileSync(registry, 'utf8'))
assert.equal(arena.owner, '/root/R140')
assert.equal(arena.running, true)
assert.equal(arena.paid, false)
assert.equal(arena.test_database, 'performe_r140_completion')
assert.match(arena.socket, /^\/tmp\/performe-r140-/)
assert.equal(readFileSync(`${arena.data}/postmaster.pid`, 'utf8').split('\n')[0], String(arena.pid))
assert.equal(createHash('sha256').update(readFileSync(arena.psql)).digest('hex'), arena.psql_sha256)
assert.equal(statSync(arena.socket).mode & 0o777, 0o700)
const env = Object.fromEntries(
  ['PATH', 'HOME', 'LANG', 'TMPDIR'].filter((k) => process.env[k]).map((k) => [k, process.env[k]]),
)
const args = [
  '-p',
  arena.sandbox_profile,
  arena.psql,
  '-w',
  '-X',
  '-q',
  '-A',
  '-t',
  '-v',
  'ON_ERROR_STOP=1',
  '-v',
  'VERBOSITY=verbose',
  '-h',
  arena.socket,
  '-p',
  String(arena.port),
  '-U',
  'postgres',
  '-d',
  arena.test_database,
]
const run = (sql) =>
  execFileSync('/usr/bin/sandbox-exec', args, {
    input: sql,
    encoding: 'utf8',
    env,
    stdio: ['pipe', 'pipe', 'pipe'],
  }).trim()
const query = (sql) => JSON.parse(run(sql)),
  val = (v) =>
    v === null
      ? 'NULL'
      : typeof v === 'object'
        ? `'${JSON.stringify(v).replaceAll("'", "''")}'::jsonb`
        : `'${String(v).replaceAll("'", "''")}'`
assert.deepEqual(
  query(
    "SELECT jsonb_build_object('db',current_database(),'sysid',(SELECT system_identifier::text FROM pg_control_system()),'listen',current_setting('listen_addresses'),'clients',(SELECT count(*) FROM pg_stat_activity WHERE pid<>pg_backend_pid() AND backend_type='client backend'))",
  ),
  { db: arena.test_database, sysid: arena.source_sysid, listen: '', clients: 0 },
)
const {
  createTrainingExecutionCompletionRoutes,
  createTrainingExecutionCompletionService,
  bindTrainingExecutionCompletion,
} = createRequire(import.meta.url)(bundle)
const owner = '13700000-0000-4000-8000-000000000002',
  auth = '13700000-0000-4000-8000-000000000001',
  login = '139d0000-0000-4000-8000-000000000005',
  epoch = '13700000-0000-4000-8000-000000000010',
  session = '13700000-0000-4000-8000-000000000020'
const token = `e30.${Buffer.from(JSON.stringify({ sub: auth, session_id: login })).toString('base64url')}.synthetic`
const command = {
  schema: 'training.execution.finish.v1',
  session_id: session,
  operation_id: '139d0000-0000-4000-8000-000000000003',
  expected_epoch: epoch,
  expected_revision: 0,
  source: { channel: 'text', text: 'Fiz full body por 30 min com intensidade moderada.' },
}
const counts = {},
  errors = [],
  timings = []
let commits = 0,
  loseReply = true,
  created = false
const names = new Set([
  'begin_training_execution_completion_authenticated',
  'read_training_execution_completion_authenticated',
  'commit_training_execution_completion_authenticated',
  'cancel_training_execution_completion_authenticated',
  'read_conversation_workout_preparation',
  'admit_conversation_workout_command',
  'capture_conversation_workout_source',
  'prepare_conversation_workout',
  'read_conversation_workout_effect',
  'reconcile_conversation_workout',
  'get_mobile_current_clinical_state',
  'read_training_execution_state_v2_authenticated',
  'read_training_execution_home_v2_authenticated',
  'read_mobile_registration_feedback_v3',
  'capture_mobile_registration_feedback_v3',
  'commit_mobile_registration_feedback_v3',
])
const db = {
  from() {
    throw Error('Unexpected table transport; only closed actual SQL RPCs allowed')
  },
  async rpc(name, params) {
    assert.ok(names.has(name), `Unqualified RPC ${name}`)
    counts[name] = (counts[name] || 0) + 1
    let data
    try {
      data = query(
        `SELECT public.${name}(${Object.entries(params)
          .map(([k, v]) => {
            assert.match(k, /^p_[a-z_]+$/)
            return `${k} => ${val(v)}`
          })
          .join(',')})`,
      )
    } catch (e) {
      const code = /ERROR:\s+([0-9A-Z]{5}):/.exec(String(e.stderr))?.[1] ?? 'XX000'
      errors.push({ name, code })
      return { data: null, error: { code } }
    }
    if (name === 'commit_training_execution_completion_authenticated') {
      commits++
      if (loseReply) {
        loseReply = false
        throw Error('Synthetic lost reply AFTER real domain commit')
      }
    }
    return { data, error: null }
  },
}
const identity = { id: auth, email: 'qa@example.invalid', emailConfirmedAt: '2026-11-14T00:00:00Z' }
const patient = () =>
  query(
    `SELECT jsonb_build_object('id',id,'authUserId',auth_user_id,'email',email,'name',name,'locale',locale,'timezone',timezone,'country',country,'countryConfirmed',country_confirmed,'status',status) FROM public.users WHERE id=${val(owner)}`,
  )
const verified = {
  verifyAccessToken: async (t) => {
    assert.equal(t, token)
    return identity
  },
  loadPatient: async (id) => {
    assert.equal(id, auth)
    return patient()
  },
  isAdmin: async () => false,
}
const runtime = {
  createServiceClient: () => db,
  createRequestId: () => 'r140-local-pg',
  authorizeEntitlement: async () => {},
  authenticate: async (request) => {
    assert.equal(request.headers.get('Authorization'), `Bearer ${token}`)
    return { accessToken: token, authUserId: auth, userId: owner, identity, patient: patient() }
  },
}
const routes = createTrainingExecutionCompletionRoutes(
  {
    enabled: () => true,
    service: (db, who, authorize) =>
      createTrainingExecutionCompletionService(db, who, authorize, {
        auth: verified,
        feedbackV3WriterEnabled: () => true,
      }),
  },
  runtime,
)
const headers = () => ({
  Authorization: `Bearer ${token}`,
  'Content-Type': 'application/json',
  'X-Training-Owner': owner,
  'X-Training-Epoch': epoch,
})
const send = async (method, path, body, key, hash) => {
  const start = performance.now(),
    request = new Request(`https://unit.invalid/api/mobile/v1/training/execution-v2${path}`, {
      method: body === null ? 'GET' : 'POST',
      headers: {
        ...headers(),
        ...(key ? { 'Idempotency-Key': key } : {}),
        ...(hash ? { 'X-Training-Completion-Hash': hash } : {}),
      },
      ...(body === null ? {} : { body: JSON.stringify(body) }),
    })
  const response = await routes[method](request, {
      params: Promise.resolve({ sessionId: session, completionId: command.operation_id }),
    }),
    value = await response.json()
  timings.push({ method, status: response.status, ms: Math.round(performance.now() - start) })
  assert.equal(response.headers.get('Cache-Control'), 'no-store')
  return { response, value }
}
try {
  assert.equal(query(`SELECT count(*) FROM public.users WHERE id=${val(owner)}`), 0)
  run(readFileSync(fixture, 'utf8').split('CREATE TEMP TABLE finish_fixture')[0])
  created = true
  const first = await send('HOME', '', null)
  assert.equal(first.response.status, 200, JSON.stringify(first.value))
  assert.equal(first.value.data.sessions.length, 1)
  const bound = bindTrainingExecutionCompletion(owner, `tfinish1:${command.operation_id}`, command)
  await db.rpc('begin_training_execution_completion_authenticated', {
    p_user_id: owner,
    p_auth_user_id: auth,
    p_auth_session_id: login,
    p_command: command,
  })
  const reserved = await send('STATE', `/${session}`, null)
  assert.equal(reserved.response.status, 200, JSON.stringify(reserved.value))
  assert.equal(reserved.value.data.completion.status, 'reserved')
  const cancelled = await send(
    'CANCEL',
    `/${session}/completions/${command.operation_id}/cancel`,
    {
      schema: 'training.execution.finish-cancel.v1',
      session_id: session,
      completion_id: command.operation_id,
      expected_epoch: epoch,
      input_hash: bound.inputHash,
    },
    `tcancel1:${command.operation_id}`,
  )
  assert.equal(cancelled.response.status, 200, JSON.stringify(cancelled.value))
  assert.equal(cancelled.value.data.status, 'cancelled')
  assert.equal(commits, 0)
  assert.equal(
    query(
      `SELECT count(*) FROM private.conversation_journal_events_v3(${val(owner)},${val(epoch)}) WHERE command_id=${val(command.operation_id)}`,
    ),
    0,
  )
  command.operation_id = '139d0000-0000-4000-8000-000000000004'
  const saved = await send('POST', '/completions', command, `tfinish1:${command.operation_id}`)
  assert.equal(saved.response.status, 200, JSON.stringify(saved.value))
  assert.equal(saved.value.data.status, 'completed')
  assert.equal(commits, 1)
  assert.equal(saved.value.data.workout.duration_min, 30)
  assert.deepEqual(
    saved.value.data.session.exercises.map((e) => e.sets),
    [[], []],
  )
  const replay = await send('POST', '/completions', command, `tfinish1:${command.operation_id}`)
  assert.equal(replay.response.status, 200, JSON.stringify(replay.value))
  assert.deepEqual(replay.value.data.receipt, saved.value.data.receipt)
  assert.equal(commits, 1)
  const cold = await send('STATE', `/${session}`, null)
  assert.equal(cold.response.status, 200, JSON.stringify(cold.value))
  assert.equal(cold.value.data.session.phase, 'completed')
  assert.deepEqual(cold.value.data.completion.receipt, saved.value.data.receipt)
  const h = await send('HOME', '', null)
  assert.equal(h.response.status, 200)
  assert.equal(h.value.data.sessions[0].phase, 'completed')
  assert.equal(h.value.data.sessions[0].completed_exercises, 0)
  const facts = query(
    `SELECT jsonb_build_object('workouts',(SELECT count(*) FROM public.workout_logs WHERE user_id=${val(owner)}),'receipts',(SELECT count(*) FROM private.conversation_workout_effects WHERE user_id=${val(owner)}),'feedback',(SELECT count(*) FROM private.mobile_registration_feedback_v3 WHERE user_id=${val(owner)}),'journal',(SELECT count(*) FROM private.conversation_journal_events_v3(${val(owner)},${val(epoch)}) WHERE command_id=${val(command.operation_id)}))`,
  )
  assert.equal(facts.workouts, 1)
  assert.equal(facts.receipts, 1)
  assert.equal(facts.journal, 1)
  assert.ok(
    !/"(frozen_state|source_input|prepared|auth_session_id|workout_hash)":/.test(
      JSON.stringify(saved.value),
    ),
  )
  run(`DELETE FROM auth.sessions WHERE id=${val(login)} AND user_id=${val(auth)}`)
  const retired = await send('STATE', `/${session}`, null)
  assert.equal(retired.response.status, 401, JSON.stringify(retired.value))
  assert.equal(commits, 1)
  writeFileSync(
    output,
    JSON.stringify(
      {
        status: 'PASS',
        qualification: 'LOCAL_HTTP_HANDLER_REAL_SERVICE_REAL_SQL_EXTERNAL_AUTH_SYNTHETIC',
        facts,
        commits,
        lostReplyRecovered: true,
        coldRecovery: true,
        cancellation: true,
        expiredLoginFenced: true,
        feedbackPresent: saved.value.data.feedback !== null,
        errors,
        counts,
        timings,
      },
      null,
      2,
    ) + '\n',
  )
} finally {
  if (created) {
    assert.deepEqual(
      query(
        `SELECT jsonb_build_object('owner',EXISTS(SELECT 1 FROM public.users WHERE id=${val(owner)} AND auth_user_id=${val(auth)} AND name='Synthetic R139 training completion'),'auth',EXISTS(SELECT 1 FROM auth.users WHERE id=${val(auth)} AND email='r139-training-completion@example.invalid'))`,
      ),
      { owner: true, auth: true },
    )
    run(
      `BEGIN;DELETE FROM public.users WHERE id=${val(owner)} AND auth_user_id=${val(auth)};DELETE FROM auth.users WHERE id=${val(auth)} AND email='r139-training-completion@example.invalid';COMMIT;`,
    )
    assert.equal(query(`SELECT count(*) FROM public.workout_logs WHERE user_id=${val(owner)}`), 0)
  }
}
console.log(JSON.stringify({ status: 'PASS', output, fixtureRemoved: created }))
