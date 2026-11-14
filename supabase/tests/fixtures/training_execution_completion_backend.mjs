/** Actual TS composition -> actual owned PostgreSQL -> actual protected writer.
 * No hosted Auth, HTTP, UI, provider or release claim. Synthetic local only. */
import assert from 'node:assert/strict'
import { execFileSync } from 'node:child_process'
import { createHash } from 'node:crypto'
import { readFileSync, statSync, writeFileSync } from 'node:fs'
import { pathToFileURL } from 'node:url'

const [registry, fixture, bundle, output] = process.argv.slice(2)
const arena = JSON.parse(readFileSync(registry,'utf8'))
assert.equal(arena.owner,'/root/R139'); assert.equal(arena.running,true); assert.equal(arena.paid,false)
assert.equal(arena.test_database,'performe_r139_completion')
assert.ok(arena.socket.startsWith('/tmp/performe-r139-'))
assert.equal(readFileSync(`${arena.data}/postmaster.pid`,'utf8').split('\n')[0],String(arena.pid))
assert.equal(createHash('sha256').update(readFileSync(arena.psql)).digest('hex'),arena.psql_sha256)
assert.equal(statSync(arena.socket).mode & 0o777,0o700)
const env = Object.fromEntries(['PATH','HOME','LANG','TMPDIR'].filter(k=>process.env[k]).map(k=>[k,process.env[k]]))
const args=['-p',arena.sandbox_profile,arena.psql,'-w','-X','-q','-A','-t','-v','ON_ERROR_STOP=1','-h',arena.socket,'-p',String(arena.port),'-U','postgres','-d',arena.test_database]
const run=sql=>execFileSync('/usr/bin/sandbox-exec',args,{input:sql,encoding:'utf8',env,stdio:['pipe','pipe','pipe']}).trim()
const query=sql=>JSON.parse(run(sql)), val=v=>`'${String(v).replaceAll("'","''")}'`, js=v=>`${val(JSON.stringify(v))}::jsonb`
assert.deepEqual(query("SELECT jsonb_build_object('db',current_database(),'sysid',(SELECT system_identifier::text FROM pg_control_system()),'listen',current_setting('listen_addresses'),'other_clients',(SELECT count(*) FROM pg_stat_activity WHERE pid<>pg_backend_pid() AND backend_type='client backend'))"),{db:arena.test_database,sysid:arena.source_sysid,listen:'',other_clients:0})
const {createTrainingExecutionCompletionBackend,bindTrainingExecutionCompletion}=await import(pathToFileURL(bundle))
const owner='13700000-0000-4000-8000-000000000002',auth='13700000-0000-4000-8000-000000000001'
const login='139d0000-0000-4000-8000-000000000005',epoch='13700000-0000-4000-8000-000000000010'
let command={schema:'training.execution.finish.v1',session_id:'13700000-0000-4000-8000-000000000020',operation_id:'139d0000-0000-4000-8000-000000000003',expected_epoch:epoch,expected_revision:0,source:{channel:'text',text:'Fiz full body por 30 min com intensidade moderada.'}}
assert.deepEqual(query(`SELECT jsonb_build_object('owner',(SELECT count(*) FROM public.users WHERE id=${val(owner)}),'auth',(SELECT count(*) FROM auth.users WHERE id=${val(auth)}))`),{owner:0,auth:0})
const names=new Set(['begin_training_execution_completion_authenticated','read_training_execution_completion_authenticated','commit_training_execution_completion_authenticated','cancel_training_execution_completion_authenticated','read_conversation_workout_preparation','admit_conversation_workout_command','capture_conversation_workout_source','prepare_conversation_workout','read_conversation_workout_effect'])
let created=false, lostReply=true, writes=0
const called=[]
try {
  run(readFileSync(fixture,'utf8').split('CREATE TEMP TABLE finish_fixture')[0]+'\nCOMMIT;');created=true
  const port={async rpc(name,body){
    assert.ok(names.has(name),`Only the protected completion lane: ${name}`)
    const params=Object.entries(body).map(([k,v])=>{
      assert.match(k,/^p_[a-z_]+$/)
      return `${k} => ${v===null?'NULL':typeof v==='object'?js(v):val(v)}`
    })
    const data=query(`SELECT public.${name}(${params.join(',')})`);called.push(name)
    if(name==='commit_training_execution_completion_authenticated'){
      writes++;assert.equal(data.action,'committed')
      if(lostReply){lostReply=false;throw Error('Synthetic response lost AFTER real SQL commit')}
    }
    return {data,error:null}
  }}
  const checkCurrentScope=async()=>query(`SELECT jsonb_build_object('valid',EXISTS(SELECT 1 FROM public.users u JOIN auth.sessions s ON s.user_id=u.auth_user_id JOIN private.workout_strength_authority_epochs e ON e.user_id=u.id WHERE u.id=${val(owner)} AND u.auth_user_id=${val(auth)} AND s.id=${val(login)} AND e.epoch=${val(epoch)} AND (s.not_after IS NULL OR s.not_after>clock_timestamp())))`).valid
  const backend=createTrainingExecutionCompletionBackend(port,{owner_id:owner,auth_user_id:auth,auth_session_id:login,checkCurrentScope})
  let bound=bindTrainingExecutionCompletion(owner,`tfinish1:${command.operation_id}`,command)
  query(`SELECT public.begin_training_execution_completion_authenticated(${val(owner)},${val(auth)},${val(login)},${js(command)})`)
  assert.equal((await backend.read(bound)).completion.status,'reserved')
  assert.equal((await backend.cancel(bound)).completion.status,'cancelled')
  assert.deepEqual(await backend.submit(bound),{status:'cancelled'})
  assert.equal(writes,0,'safe cancellation creates no workout')
  command={...command,operation_id:'139d0000-0000-4000-8000-000000000004'}
  bound=bindTrainingExecutionCompletion(owner,`tfinish1:${command.operation_id}`,command)
  const saved=await backend.submit(bound)
  assert.equal(saved.status,'saved');assert.equal(saved.completion.completion.status,'completed')
  assert.equal(saved.effect.receipt.workout_id,saved.completion.completion.receipt.workout.workout_id)
  assert.deepEqual(saved.completion.session.exercises.map(e=>e.sets),[[],[]])
  assert.equal(writes,1,'lost reply reconciles by an independent read, not another write')
  const replay=await backend.submit(bound)
  assert.equal(replay.status,'saved');assert.deepEqual(replay.effect,saved.effect);assert.equal(writes,1)
  const observedCancel=await backend.cancel(bound);assert.equal(observedCancel.completion.status,'completed');assert.equal(writes,1)
  const state=query(`SELECT jsonb_build_object('workouts',(SELECT count(*) FROM public.workout_logs WHERE user_id=${val(owner)}),'receipts',(SELECT count(*) FROM private.conversation_workout_effects WHERE user_id=${val(owner)}),'audits',(SELECT count(*) FROM private.training_execution_completion_events WHERE user_id=${val(owner)}),'phase',(SELECT state->>'phase' FROM private.training_execution_sessions WHERE user_id=${val(owner)}),'rewards',(SELECT count(*) FROM public.user_progress WHERE user_id=${val(owner)}))`)
  assert.deepEqual(state,{workouts:1,receipts:1,audits:4,phase:'completed',rewards:0})
  run(`DELETE FROM auth.sessions WHERE id=${val(login)} AND user_id=${val(auth)};`)
  const before=called.length;await assert.rejects(backend.submit(bound));assert.equal(called.length,before,'a retired original login does not make even a reservation RPC')
  writeFileSync(output,JSON.stringify({status:'PASS',actual_ts_to_sql:true,transport:'owned Unix-only PostgreSQL; no HTTP/provider',lost_committed_reply_reconciled:true,same_operation_replay:true,actual_state:state,physical_commit_calls:writes,original_login_retired:true,cancel_before_effect:true,cancel_after_effect_observational:true,rpc_calls:called.length},null,2)+'\n')
} finally {
  if(created){
    assert.deepEqual(query(`SELECT jsonb_build_object('owner',EXISTS(SELECT 1 FROM public.users WHERE id=${val(owner)} AND auth_user_id=${val(auth)} AND name='Synthetic R139 training completion'),'auth',EXISTS(SELECT 1 FROM auth.users WHERE id=${val(auth)} AND email='r139-training-completion@example.invalid'))`),{owner:true,auth:true})
    run(`BEGIN; DELETE FROM public.users WHERE id=${val(owner)} AND auth_user_id=${val(auth)}; DELETE FROM auth.users WHERE id=${val(auth)} AND email='r139-training-completion@example.invalid'; COMMIT;`)
    assert.deepEqual(query(`SELECT jsonb_build_object('owner',(SELECT count(*) FROM public.users WHERE id=${val(owner)}),'auth',(SELECT count(*) FROM auth.users WHERE id=${val(auth)}),'workouts',(SELECT count(*) FROM public.workout_logs WHERE user_id=${val(owner)}))`),{owner:0,auth:0,workouts:0})
  }
}
process.stdout.write(JSON.stringify({status:'PASS',evidence:output,fixture_removed:created})+'\n')
