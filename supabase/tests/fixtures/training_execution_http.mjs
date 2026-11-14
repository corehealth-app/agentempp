/** Offline HTTP handler -> real service/kernel -> real owned PostgreSQL.
 * Only the external Auth/entitlement provider is injected with synthetic known
 * tokens; the current auth.sessions row, ownership and every write remain real.
 * This is not a claim of hosted Supabase Auth/native E2E qualification. */
import assert from 'node:assert/strict'
import { execFileSync, spawn } from 'node:child_process'
import { readFileSync } from 'node:fs'
import { createRequire } from 'node:module'
const [registryPath,bundle] = process.argv.slice(2), arena=JSON.parse(readFileSync(registryPath,'utf8'))
assert.equal(arena.owner,'/root/R136');assert.equal(arena.running,true);assert.equal(arena.paid,false)
assert.equal(arena.test_database,'performe_r136_training');assert.match(arena.socket,/^\/tmp\/performe-r136-/)
const env=Object.fromEntries(['PATH','HOME','LANG','TMPDIR'].filter(k=>process.env[k]).map(k=>[k,process.env[k]]))
const args=['-p',arena.sandbox_profile,arena.psql,'-w','-X','-q','-A','-t','-v','ON_ERROR_STOP=1','-v','VERBOSITY=verbose','-h',arena.socket,'-p',String(arena.port),'-U','postgres','-d',arena.test_database]
const run=sql=>execFileSync('/usr/bin/sandbox-exec',args,{input:sql,encoding:'utf8',env,stdio:['pipe','pipe','pipe']}).trim()
const query=sql=>JSON.parse(run(sql)), val=v=>v===null?'NULL':typeof v==='object'?`'${JSON.stringify(v).replaceAll("'","''")}'::jsonb`:`'${String(v).replaceAll("'","''")}'`
assert.deepEqual(query("select jsonb_build_object('listen',current_setting('listen_addresses'),'sysid',(select system_identifier::text from pg_control_system()),'db',current_database())"),{listen:'',sysid:arena.source_sysid,db:arena.test_database})
const {createTrainingExecutionRoutes}=createRequire(import.meta.url)(bundle)
const id=n=>`13600000-0000-4000-8000-${String(n).padStart(12,'0')}`
const auth=id(1),owner=id(2),login=id(3),epoch=id(10),execution=id(20)
const tokenFor=s=>`e30.${Buffer.from(JSON.stringify({sub:auth,session_id:s})).toString('base64url')}.synthetic`
const tokens=new Map([[tokenFor(login),login]])
let token=tokenFor(login), revokeBeforeCommit=false, loseCommitReply=false, lostReply, calls=0
run(`insert into auth.users(id,email) values(${val(auth)},'http-training-r136@example.invalid');
 insert into public.users(id,auth_user_id,name,timezone) values(${val(owner)},${val(auth)},'HTTP synthetic training','America/Sao_Paulo');
 insert into private.workout_strength_authority_epochs(user_id,epoch,changed_at) values(${val(owner)},${val(epoch)},clock_timestamp());
 insert into auth.sessions(id,user_id,created_at) values(${val(login)},${val(auth)},clock_timestamp());
 insert into public.training_plans(id,user_id,plan_type,days_per_week,weekly_schedule,generated_at,active,version)
 values(${val(id(4))},${val(owner)},'full_body',2,'[{"day":"Sábado","exercises":[{"name":"Supino","sets":3,"reps_range":"8–12"}]}]',clock_timestamp()-interval '1 hour',true,1);`)
const db={rpc:async(name,params)=>{
 assert.ok(['capture_training_execution_context_authenticated','commit_training_execution_mutation_authenticated','read_training_execution_home_authenticated'].includes(name))
 calls++
 if(name==='commit_training_execution_mutation_authenticated' && revokeBeforeCommit){
  revokeBeforeCommit=false;run(`delete from auth.sessions where id=${val(login)}`)
 }
 let data
 try{data=query(`select public.${name}(${Object.entries(params).map(([k,v])=>`${k} => ${val(v)}`).join(',')})`)}
 catch(e){return{data:null,error:{code:/ERROR:\s+([0-9A-Z]{5}):/.exec(String(e.stderr))?.[1]??'XX000'}}}
 if(name==='commit_training_execution_mutation_authenticated' && loseCommitReply){loseCommitReply=false;lostReply=data;throw Error('synthetic lost reply after actual commit')}
 return{data,error:null}
}}
const runtime={createServiceClient:()=>db,createRequestId:()=> 'r136-http-real-pg',authorizeEntitlement:async()=>{},authenticate:async request=>{
 const bearer=request.headers.get('Authorization')?.replace(/^Bearer /,'');assert.ok(tokens.has(bearer),'only known synthetic verified-token fixture')
 return {accessToken:bearer,authUserId:auth,userId:owner,identity:{id:auth,email:'qa@example.invalid',emailConfirmedAt:'2026-11-14T00:00:00Z'},patient:{id:owner,authUserId:auth,status:'active'}}
}}
const routes=createTrainingExecutionRoutes({enabled:()=>true},runtime)
const headers=()=>({Authorization:`Bearer ${token}`,'X-Training-Owner':owner})
const home=async cursor=>{
 const q=cursor?`?${new URLSearchParams({cursor:JSON.stringify(cursor)})}`:''
 const r=await routes.HOME(new Request(`https://unit.invalid/api/mobile/v1/training/execution${q}`,{headers:headers()}));return{r,body:await r.json()}
}
const post=async command=>{
 const r=await routes.POST(new Request('https://unit.invalid/api/mobile/v1/training/execution/commands',{method:'POST',headers:{...headers(),'Content-Type':'application/json','X-Training-Epoch':epoch,'Idempotency-Key':`texecution1:${command.operation_id}`},body:JSON.stringify(command)}));return{r,body:await r.json()}
}
const read=async session=>{
 const r=await routes.GET(new Request(`https://unit.invalid/api/mobile/v1/training/execution/${session}`,{headers:headers()}),{params:Promise.resolve({sessionId:session})});return{r,body:await r.json()}
}
const first=await home();assert.equal(first.r.status,200);assert.equal(first.body.data.schema,'training.execution-home.v1')
assert.deepEqual(first.body.data.sessions,[])
assert.equal(query(`select count(*) from private.training_execution_sessions where user_id=${val(owner)}`),0,'home creates no session')
assert.equal(query(`select count(*) from private.training_execution_operations where user_id=${val(owner)}`),0,'home creates no operation')
const plan=first.body.data.plan
const start={schema:'training.execution.start.v1',session_id:execution,operation_id:execution,expected_epoch:epoch,expected_local_date:first.body.data.scope.current_local_date,plan_id:plan.plan_id,plan_hash:plan.definition_hash,day_index:0}
assert.equal((await post(start)).r.status,200)
const actualSet={id:id(30),index:0,repetitions:8,load_kg:15.5,duration_seconds:null,completed:true}
const update=(op,rev,action)=>({schema:'training.execution.update.v1',session_id:execution,operation_id:id(op),expected_epoch:epoch,expected_revision:rev,action})
assert.equal((await post(update(31,0,{kind:'save_set',exercise_index:0,set:actualSet}))).r.status,200)
const cold=await read(execution);assert.equal(cold.r.status,200)
assert.deepEqual(cold.body.data.session.exercises[0].sets,[actualSet]);assert.equal(cold.body.data.session.revision,1)
const retryCommand=update(32,1,{kind:'mark_exercise',exercise_index:0,completed:true})
loseCommitReply=true;assert.equal((await post(retryCommand)).r.status,503)
const recovered=await post(retryCommand);assert.equal(recovered.r.status,200);assert.equal(recovered.body.data.status,'replayed')
assert.deepEqual(recovered.body.data.receipt,lostReply.receipt)
assert.equal(query(`select count(*) from private.training_execution_operations where user_id=${val(owner)}`),3)
// Simulate expiry DURING the atomic writer. The post-write login fence must
// abort state + receipt + audit together, including the synthetic expiry.
run(`create function private.r136_expire_before_audit() returns trigger language plpgsql as $$begin update auth.sessions set not_after=clock_timestamp()-interval '1 second' where id='${login}'::uuid;return new;end$$;
 create trigger r136_expire_before_audit before insert on private.training_execution_audit for each row execute function private.r136_expire_before_audit();`)
let duringExpiry
try{duringExpiry=await post(update(36,2,{kind:'mark_exercise',exercise_index:0,completed:false}))}
finally{run('drop trigger r136_expire_before_audit on private.training_execution_audit;drop function private.r136_expire_before_audit();')}
assert.equal(duringExpiry.r.status,401,'expiry during the writer must roll back the entire operation')
assert.equal(query(`select count(*) from private.training_execution_operations where user_id=${val(owner)}`),3)
assert.equal(query(`select to_jsonb(not_after is null) from auth.sessions where id=${val(login)}`),true,'failed transaction rolls back the synthetic expiry too')
// A pending not_after update must fence capture too, not just session deletion.
const held=spawn('/usr/bin/sandbox-exec',args,{env,stdio:['pipe','pipe','pipe']})
const heldExit=new Promise(resolve=>held.on('close',resolve))
let output='';const heldReady=new Promise((resolve,reject)=>{
 const timeout=setTimeout(()=>reject(Error('Auth row lock fixture did not become ready')),5000)
 held.stdout.on('data',b=>{output+=b;if(output.includes('AUTH_ROW_HELD')){clearTimeout(timeout);resolve()}})
 held.on('error',reject)
})
held.stdin.write(`BEGIN;UPDATE auth.sessions SET not_after=clock_timestamp()-interval '1 hour' WHERE id=${val(login)};\n\\echo AUTH_ROW_HELD\n`)
let whileRevoking
try{await heldReady;whileRevoking=await post(update(35,2,{kind:'mark_exercise',exercise_index:0,completed:false}))}
finally{held.stdin.end('ROLLBACK;\n');await heldExit}
assert.equal(whileRevoking.r.status,409,'a concurrent non-key Auth expiry update must hold all training writes')
assert.equal(query(`select count(*) from private.training_execution_operations where user_id=${val(owner)}`),3)
revokeBeforeCommit=true
assert.equal((await post(update(33,2,{kind:'abandon'}))).r.status,401,'a crypto-valid original token cannot write after its live session is removed')
assert.equal((await read(execution)).r.status,401)
assert.equal(query(`select count(*) from private.training_execution_operations where user_id=${val(owner)}`),3)
const newLogin=id(90);run(`insert into auth.sessions(id,user_id,created_at) values(${val(newLogin)},${val(auth)},clock_timestamp())`)
token=tokenFor(newLogin);tokens.set(token,newLogin)
assert.equal((await read(execution)).body.data.session.revision,2,'a fresh valid same-account login can read durable progress')
assert.equal((await post(update(34,2,{kind:'abandon'}))).r.status,200)
assert.equal((await home()).body.data.sessions.length,0,'abandoned execution is readable but not resumable')
for(let n=200;n<222;n++){
 const command={...start,session_id:id(n),operation_id:id(n)}
 assert.equal((await post(command)).r.status,200)
}
const page1=await home(),page2=await home(page1.body.data.next_cursor)
assert.equal(page1.r.status,200);assert.equal(page2.r.status,200)
assert.equal(page1.body.data.sessions.length,20);assert.equal(page2.body.data.sessions.length,2)
assert.equal(new Set([...page1.body.data.sessions,...page2.body.data.sessions].map(s=>s.id)).size,22)
assert.equal(page2.body.data.next_cursor,null)
run(`update public.users set timezone='UTC' where id=${val(owner)}`)
assert.equal((await home(page1.body.data.next_cursor)).r.status,409,'old timezone cursor cannot silently rebind')
assert.equal(query(`select count(*) from public.workout_logs where user_id=${val(owner)}`),0)
assert.equal(query(`select count(*) from public.daily_snapshots where user_id=${val(owner)}`),0)
run(`delete from public.users where id=${val(owner)};delete from auth.users where id=${val(auth)}`)
assert.equal(query(`select count(*) from private.training_execution_sessions where user_id=${val(owner)}`),0)
console.log(JSON.stringify({status:'PASS',actual_http_service_pg:true,provider_auth:'SYNTHETIC_INJECTED_NOT_HOSTED_AUTH_PROOF',real_login_row_revocation:true,read_creates_nothing:true,cold_reload:true,lost_commit_reply:true,resume_pages:2,resume_count:22,timezone_cursor_fenced:true,no_workout_energy_xp:true,rpc_calls:calls}))
