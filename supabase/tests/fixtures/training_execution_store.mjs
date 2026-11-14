/** Real PostgreSQL + real TS kernel. Run only in the disposable owned local DB
 * created by the documented arena runner; no cloud URL/credential is accepted. */
import assert from 'node:assert/strict'
import { execFileSync, spawn } from 'node:child_process'
import { readFileSync } from 'node:fs'
import { pathToFileURL } from 'node:url'

const [registryPath, kernelPath] = process.argv.slice(2)
const arena = JSON.parse(readFileSync(registryPath, 'utf8'))
const revision = /^\/root\/R(135|136)$/.exec(arena.owner)?.[1]
assert.ok(revision, 'only the explicitly owned training qualification arenas')
assert.equal(arena.running, true)
assert.equal(arena.paid, false)
assert.equal(arena.test_database, `performe_r${revision}_training`)
assert.ok(arena.socket.startsWith(`/tmp/performe-r${revision}-`))
const env = Object.fromEntries(['PATH', 'HOME', 'LANG', 'TMPDIR'].filter(k => process.env[k]).map(k => [k, process.env[k]]))
const args = ['-p', arena.sandbox_profile, arena.psql, '-w', '-X', '-q', '-A', '-t', '-v', 'ON_ERROR_STOP=1', '-h', arena.socket, '-p', String(arena.port), '-U', 'postgres', '-d', arena.test_database]
const run = sql => execFileSync('/usr/bin/sandbox-exec', args, { input: sql, encoding: 'utf8', env, stdio: ['pipe', 'pipe', 'pipe'] }).trim()
const lit = v => `'${JSON.stringify(v).replaceAll("'", "''")}'::jsonb`
const val = v => `'${String(v).replaceAll("'", "''")}'`
const query = sql => JSON.parse(run(sql))
assert.deepEqual(query("select jsonb_build_object('db',current_database(),'listen',current_setting('listen_addresses'),'sysid',(select system_identifier::text from pg_control_system()))"), { db: arena.test_database, listen: '', sysid: arena.source_sysid })
const { prepareTrainingExecutionMutation: prepare, projectTrainingExecutionPlan: project, parseTrainingExecutionPersistence, createTrainingExecutionStore } = await import(pathToFileURL(kernelPath))
const owner = '13500000-0000-4000-8000-000000000002', auth = '13500000-0000-4000-8000-000000000001'
const session = '13500000-0000-4000-8000-000000000003'
const uuid = n => `13500000-0000-4000-8000-${String(n).padStart(12, '0')}`
run(`insert into auth.users(id,email) values(${val(auth)},'training-r135@example.invalid');
 insert into public.users(id,auth_user_id,name,timezone) values(${val(owner)},${val(auth)},'Synthetic execution','America/Sao_Paulo');
 insert into private.workout_strength_authority_epochs(user_id,epoch,changed_at) values(${val(owner)},${val(uuid(80))},clock_timestamp());
 insert into public.training_plans(id,user_id,plan_type,days_per_week,weekly_schedule,generated_at,active,version)
 values(${val(uuid(4))},${val(owner)},'full_body',2,
 '[{"day":"Sábado","focus":"Força","duration_min":30,"exercises":[{"name":"Supino","sets":3,"reps_range":"8–12"},{"name":"Supino","sets":2}]}]',clock_timestamp()-interval '1 hour',true,2);`)
const capture = (id = session, op = id, o = owner, a = auth) => query(`select public.capture_training_execution_context(${val(o)},${val(a)},${val(id)},${val(op)})`)
const commitSQL = (c, command, prepared) => `select public.commit_training_execution_mutation(${val(owner)},${val(auth)},${lit(command)},${val(c.context_hash)},${val(c.context.scope.observed_at)},${lit(prepared)});`
const commit = (c, command, prepared = prepare({ ...c.context, command })) => query(commitSQL(c, command, prepared))
const c0 = capture(), definition = project(c0.context.plan, c0.context.scope)
const start = { schema: 'training.execution.start.v1', session_id: session, operation_id: session, expected_epoch: c0.context.scope.epoch, expected_local_date: c0.context.scope.current_local_date, plan_id: definition.plan_id, plan_hash: definition.definition_hash, day_index: 0 }
let loseFirstCommitReply = true, committedBeforeLostReply
const store = createTrainingExecutionStore({ rpc: async (name, args) => {
 assert.ok(['capture_training_execution_context', 'commit_training_execution_mutation'].includes(name))
 const params = Object.entries(args).map(([key, value]) => `${key} => ${value !== null && typeof value === 'object' ? lit(value) : val(value)}`)
 const data = query(`select public.${name}(${params.join(',')})`)
 if (name === 'commit_training_execution_mutation' && loseFirstCommitReply) {
  loseFirstCommitReply = false; committedBeforeLostReply = data
  throw Error('Synthetic connection lost AFTER PostgreSQL committed')
 }
 return { data, error: null }
} }, { owner, auth })
await assert.rejects(store.mutate(start), error => error.code === 'training_execution_store_unavailable')
const first = committedBeforeLostReply
assert.equal(first.status, 'created')
const recovered = await store.mutate(start)
assert.equal(recovered.status, 'replayed')
assert.deepEqual(recovered.receipt, first.receipt)
assert.equal(query(`select count(*) from private.training_execution_operations where user_id=${val(owner)}`), 1, 'no automatic retry or duplicate after a lost committed reply')
assert.equal(first.session.revision, 0)
assert.deepEqual(first.session.exercises.map(e => e.sets), [[], []])
assert.equal(first.session.definition.exercises[0].recommended_sets, 3)
assert.notEqual(first.session.definition.exercises[0].fingerprint, first.session.definition.exercises[1].fingerprint)
assert.deepEqual(capture().context.session, first.session, 'reopen reads persisted original state')
assert.deepEqual((await store.read(session)).context.session, first.session, 'original-Auth adapter reloads the durable state')
for (const malformed of [
 { ...first, session: { ...first.session, owner_id: uuid(99) } },
 { ...first, receipt: { ...first.receipt, input_hash: 'f'.repeat(64) } },
 { ...first, receipt: { ...first.receipt, after_revision: 1 } },
 { ...first, audit: { ...first.audit, unexpected: true } },
 { ...first, audit: null },
 { ...first, status: 'updated' },
]) assert.throws(() => parseTrainingExecutionPersistence(malformed, start, { owner, auth }), /Training execution could not be reconciled/)
const update = (op, revision, action) => ({ schema: 'training.execution.update.v1', session_id: session, operation_id: uuid(op), expected_epoch: start.expected_epoch, expected_revision: revision, action })
const set = { id: uuid(5), index: 0, repetitions: 0, load_kg: 12.5, duration_seconds: null, completed: false }
const save = update(6, 0, { kind: 'save_set', exercise_index: 0, set })
const saved = await store.mutate(save)
assert.equal(saved.session.exercises[0].sets[0].repetitions, 0)
assert.equal(saved.session.exercises[0].sets[0].duration_seconds, null)
assert.deepEqual(capture().context.session.exercises[0].sets, [set])
const mark = update(7, 1, { kind: 'mark_exercise', exercise_index: 0, completed: true })
const marked = await store.mutate(mark)
const replay = commit(c0, start, first)
assert.equal(replay.status, 'replayed')
assert.deepEqual(replay.receipt, first.receipt)
assert.deepEqual(replay.session, marked.session, 'start retry returns CURRENT state')
assert.equal(replay.audit, null)
assert.equal(query(`select count(*) from public.workout_logs where user_id=${val(owner)}`), 0)
assert.equal(query(`select count(*) from public.daily_snapshots where user_id=${val(owner)}`), 0)

// Two prepared clients race from revision 2. Exactly one may append a receipt.
const left = update(8, 2, { kind: 'save_set', exercise_index: 0, set: { ...set, repetitions: 10 } })
const right = update(9, 2, { kind: 'mark_exercise', exercise_index: 1, completed: true })
const cl = capture(session, left.operation_id), cr = capture(session, right.operation_id)
const pl = prepare({ ...cl.context, command: left }), pr = prepare({ ...cr.context, command: right })
const concurrent = sql => new Promise(resolve => {
 const child = spawn('/usr/bin/sandbox-exec', args, { env, stdio: ['pipe', 'pipe', 'pipe'] })
 let out = '', err = ''; child.stdout.on('data', b => { out += b }); child.stderr.on('data', b => { err += b })
 child.on('close', code => resolve({ code, out, err })); child.stdin.end(`BEGIN;${sql}select pg_sleep(0.15);COMMIT;`)
})
const raced = await Promise.all([concurrent(commitSQL(cl, left, pl)), concurrent(commitSQL(cr, right, pr))])
assert.deepEqual(raced.map(v => v.code).sort(), [0, 3])
assert.match(raced.find(v => v.code === 3).err, /training_execution_context_changed/)
assert.equal(capture().context.session.revision, 3)
assert.equal(query(`select count(*) from private.training_execution_operations where user_id=${val(owner)}`), 4)
assert.equal(query(`select count(*) from private.training_execution_audit where user_id=${val(owner)}`), 4)

// Force a durable audit failure: state and receipt must roll back together.
const before = capture().context.session
const remove = update(10, 3, { kind: 'remove_set', exercise_index: 0, set_id: set.id })
const cf = capture(session, remove.operation_id)
run(`create function private.r135_reject_audit() returns trigger language plpgsql as $$begin raise exception 'synthetic audit failure';end$$;
 create trigger r135_reject_audit before insert on private.training_execution_audit for each row execute function private.r135_reject_audit();`)
assert.throws(() => commit(cf, remove), /synthetic audit failure/)
run('drop trigger r135_reject_audit on private.training_execution_audit;drop function private.r135_reject_audit();')
assert.deepEqual(capture().context.session, before)
assert.equal(capture(session, remove.operation_id).context.prior_receipt, null)
const removed = commit(capture(session, remove.operation_id), remove)
assert.deepEqual(removed.session.exercises[0].sets, [])

// Captured context cannot override a later close/timezone/plan or another Auth.
const abandon = update(11, 4, { kind: 'abandon' })
const cc = capture(session, abandon.operation_id), pc = prepare({ ...cc.context, command: abandon })
run(`insert into public.daily_snapshots(user_id,date,day_closed) values(${val(owner)},${val(before.local_date)},true);`)
assert.throws(() => commit(cc, abandon, pc), /training_execution_context_changed|training_execution_day_closed/)
assert.deepEqual(commit(c0, start, first).receipt, first.receipt, 'accepted replay survives day closure')
run(`delete from public.daily_snapshots where user_id=${val(owner)};update public.users set timezone='UTC' where id=${val(owner)};`)
assert.throws(() => commit(cc, abandon, pc), /training_execution_context_changed/)
assert.throws(() => commit(c0, start, first), /training_execution_scope_changed/, 'replay cannot bypass a changed original timezone')
run(`update public.users set timezone='America/Sao_Paulo' where id=${val(owner)};`)
assert.throws(() => capture(session, session, owner, uuid(99)), /training_execution_owner_changed/)
run(`insert into auth.users(id,email) values(${val(uuid(90))},'isolated-training-r135@example.invalid');
 insert into public.users(id,auth_user_id,name,timezone) values(${val(uuid(91))},${val(uuid(90))},'Other synthetic owner','America/Sao_Paulo');
 insert into private.workout_strength_authority_epochs(user_id,epoch,changed_at) values(${val(uuid(91))},${val(uuid(92))},clock_timestamp());`)
const isolated = capture(session, session, uuid(91), uuid(90))
assert.equal(isolated.context.session, null)
assert.equal(isolated.context.prior_receipt, null)
assert.equal(isolated.context.plan, null)
run(`delete from public.users where id=${val(uuid(91))};delete from auth.users where id=${val(uuid(90))};`)
const altered = structuredClone(pc); altered.session.definition.day_label = 'forged'
assert.throws(() => commit(capture(session, abandon.operation_id), abandon, altered), /training_execution_invalid_state|training_execution_unexpected_delta/)
const ended = commit(capture(session, abandon.operation_id), abandon)
assert.equal(ended.session.phase, 'abandoned')
assert.equal(commit(c0, start, first).session.phase, 'abandoned')
assert.throws(() => commit(c0, { ...start, day_index: 1 }, first), /training_execution_operation_conflict/)
run(`update private.workout_strength_authority_epochs set epoch=gen_random_uuid() where user_id=${val(owner)};`)
assert.equal(capture().context.session, null)
assert.equal(query(`select count(*) from private.training_execution_operations where user_id=${val(owner)}`), 0)
assert.equal(query(`select count(*) from private.training_execution_audit where user_id=${val(owner)}`), 0)
assert.throws(() => commit(c0, start, first), /training_execution_epoch_changed/)
const nextSession = uuid(20), nextContext = capture(nextSession)
const nextPlan = project(nextContext.context.plan, nextContext.context.scope)
const nextStart = { ...start, session_id: nextSession, operation_id: nextSession,
 expected_epoch: nextContext.context.scope.epoch, plan_hash: nextPlan.definition_hash }
const stalePlanPrepared = prepare({ ...nextContext.context, command: nextStart })
run(`update public.training_plans set version=version+1 where user_id=${val(owner)};`)
assert.throws(() => commit(nextContext, nextStart, stalePlanPrepared), /training_execution_context_changed/)
assert.equal(capture(nextSession).context.session, null, 'stale plan never creates execution')
const refreshed = capture(nextSession), refreshedPlan = project(refreshed.context.plan, refreshed.context.scope)
const refreshedStart = { ...nextStart, plan_hash: refreshedPlan.definition_hash }
await store.mutate(refreshedStart)
assert.equal(query(`select count(*) from private.training_execution_sessions where user_id=${val(owner)}`), 1)
assert.equal(query(`select count(*) from private.training_execution_operations where user_id=${val(owner)}`), 1)
assert.equal(query(`select count(*) from private.training_execution_audit where user_id=${val(owner)}`), 1)
run(`delete from public.users where id=${val(owner)};delete from auth.users where id=${val(auth)};`)
assert.equal(query(`select count(*) from private.training_execution_sessions where user_id=${val(owner)}`), 0)
assert.equal(query(`select count(*) from private.training_execution_operations where user_id=${val(owner)}`), 0)
assert.equal(query(`select count(*) from private.training_execution_audit where user_id=${val(owner)}`), 0)
console.log(JSON.stringify({ status: 'PASS', persistence: true, real_concurrency: true, atomic_audit_failure: true, current_replay: true, closed_day: true, original_auth: true, reset_scrub: true, account_delete_cascade: true, stale_plan: true, no_workout_or_rewards: true }))
