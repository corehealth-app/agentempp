/** Actual v2 handlers, original progress kernel, protected completion and
 * canonical feedback, all against disposable Unix-only PG. External Auth/entitlement
 * is synthetic; no provider/native/hosted release qualification is claimed. */
import assert from 'node:assert/strict'
import {execFileSync} from 'node:child_process'
import {createHash} from 'node:crypto'
import {readFileSync,writeFileSync,statSync} from 'node:fs'
import {createRequire} from 'node:module'
const [registry,bundle,output,oracle]=process.argv.slice(2),arena=JSON.parse(readFileSync(registry,'utf8'))
assert.equal(arena.owner,'/root/R141');assert.equal(arena.running,true);assert.equal(arena.paid,false)
assert.equal(arena.test_database,'performe_r141_completion');assert.match(arena.socket,/^\/tmp\/performe-r141-/)
assert.equal(readFileSync(`${arena.data}/postmaster.pid`,'utf8').split('\n')[0],String(arena.pid))
assert.equal(createHash('sha256').update(readFileSync(arena.psql)).digest('hex'),arena.psql_sha256)
assert.equal(statSync(arena.socket).mode&0o777,0o700)
const env=Object.fromEntries(['PATH','HOME','LANG','TMPDIR'].filter(k=>process.env[k]).map(k=>[k,process.env[k]]))
const args=['-p',arena.sandbox_profile,arena.psql,'-w','-X','-q','-A','-t','-v','ON_ERROR_STOP=1','-v','VERBOSITY=verbose','-h',arena.socket,'-p',String(arena.port),'-U','postgres','-d',arena.test_database]
const run=sql=>execFileSync('/usr/bin/sandbox-exec',args,{input:sql,encoding:'utf8',env,stdio:['pipe','pipe','pipe']}).trim()
const query=sql=>JSON.parse(run(sql)),val=v=>v===null?'NULL':typeof v==='object'?`'${JSON.stringify(v).replaceAll("'","''")}'::jsonb`:`'${String(v).replaceAll("'","''")}'`
assert.deepEqual(query("SELECT jsonb_build_object('db',current_database(),'sysid',(SELECT system_identifier::text FROM pg_control_system()),'listen',current_setting('listen_addresses'),'clients',(SELECT count(*) FROM pg_stat_activity WHERE pid<>pg_backend_pid() AND backend_type='client backend'))"),{db:arena.test_database,sysid:arena.source_sysid,listen:'',clients:0})
const {createTrainingExecutionCompletionRoutes,createTrainingExecutionCompletionService,bindTrainingExecutionCompletion}=createRequire(import.meta.url)(bundle)
const id=n=>`14110000-0000-4000-8000-${String(n).padStart(12,'0')}`,auth=id(1),owner=id(2),login=id(3),epoch=id(10),session=id(20),finishID=id(50)
const token=`e30.${Buffer.from(JSON.stringify({sub:auth,session_id:login})).toString('base64url')}.synthetic`
const counts={},errors=[],timings=[];let domainCommits=0,progressCommits=0,loseReply=true,created=false
const names=new Set(['reconcile_training_execution_progress_authenticated','capture_training_execution_context_authenticated','commit_training_execution_mutation_authenticated','begin_training_execution_completion_authenticated','read_training_execution_completion_authenticated','commit_training_execution_completion_authenticated','cancel_training_execution_completion_authenticated','read_conversation_workout_preparation','admit_conversation_workout_command','capture_conversation_workout_source','prepare_conversation_workout','read_conversation_workout_effect','reconcile_conversation_workout','get_mobile_current_clinical_state','read_training_execution_state_v2_authenticated','read_training_execution_home_v2_authenticated','read_mobile_registration_feedback_v3','capture_mobile_registration_feedback_v3','commit_mobile_registration_feedback_v3'])
const db={from(){throw Error('Only actual closed RPC transport is allowed')},async rpc(name,params){
 assert.ok(names.has(name),`Unqualified RPC ${name}`);counts[name]=(counts[name]||0)+1
 let data
 try{data=query(`SELECT public.${name}(${Object.entries(params).map(([k,v])=>{assert.match(k,/^p_[a-z_]+$/);return `${k} => ${val(v)}`}).join(',')})`)}
 catch(e){const code=/ERROR:\s+([0-9A-Z]{5}):/.exec(String(e.stderr))?.[1]??'XX000';errors.push({name,code});return{data:null,error:{code}}}
 if(name==='commit_training_execution_mutation_authenticated')progressCommits++
 if(name==='commit_training_execution_completion_authenticated'){domainCommits++;if(loseReply){loseReply=false;throw Error('Synthetic response lost AFTER real protected workout commit')}}
 return{data,error:null}
}}
const identity={id:auth,email:'qa@example.invalid',emailConfirmedAt:'2026-11-14T00:00:00Z'}
const patient=()=>query(`SELECT jsonb_build_object('id',id,'authUserId',auth_user_id,'email',email,'name',name,'locale',locale,'timezone',timezone,'country',country,'countryConfirmed',country_confirmed,'status',status) FROM public.users WHERE id=${val(owner)}`)
const verified={verifyAccessToken:async t=>{assert.equal(t,token);return identity},loadPatient:async id=>{assert.equal(id,auth);return patient()},isAdmin:async()=>false}
const runtime={createServiceClient:()=>db,createRequestId:()=> 'r141-local-pg',authorizeEntitlement:async()=>{},authenticate:async request=>{assert.equal(request.headers.get('Authorization'),`Bearer ${token}`);return{accessToken:token,authUserId:auth,userId:owner,identity,patient:patient()}}}
const routes=createTrainingExecutionCompletionRoutes({enabled:()=>true,service:(db,who,authorize)=>createTrainingExecutionCompletionService(db,who,authorize,{auth:verified,feedbackV3WriterEnabled:()=>true})},runtime)
async function send(method,body=null,hash=null,target={session,completionID:finishID}){
 const sid=target.session,cid=target.completionID
 const path=method==='HOME'?'':method==='POST'?'/completions':method==='READ'||method==='CANCEL'?`/${sid}/completions/${cid}${method==='CANCEL'?'/cancel':''}`:`/${sid}`
 const key=method==='PROGRESS'?`texecution1:${body.operation_id}`:method==='POST'?`tfinish1:${body.operation_id}`:method==='CANCEL'?`tcancel1:${body.completion_id}`:null
 const request=new Request(`https://unit.invalid/api/mobile/v1/training/execution-v2${path}`,{method:body===null?'GET':'POST',headers:{Authorization:`Bearer ${token}`,'Content-Type':'application/json','X-Training-Owner':owner,'X-Training-Epoch':epoch,...(key?{'Idempotency-Key':key}:{}),...(hash?{'X-Training-Completion-Hash':hash}:{})},...(body===null?{}:{body:JSON.stringify(body)})})
 const start=performance.now(),response=await routes[method](request,{params:Promise.resolve({sessionId:sid,completionId:cid})}),value=await response.json()
 timings.push({method,status:response.status,ms:Math.round(performance.now()-start)});assert.equal(response.headers.get('Cache-Control'),'no-store')
 assert.equal(response.status,200,JSON.stringify(value));return value.data
}
try{
 assert.equal(query(`SELECT count(*) FROM public.users WHERE id=${val(owner)}`),0)
 run(`BEGIN;
 INSERT INTO auth.users(id,email) VALUES(${val(auth)},'r141-progress-completion@example.invalid');
 INSERT INTO public.users(id,auth_user_id,name,timezone) VALUES(${val(owner)},${val(auth)},'Synthetic R141 progress completion','America/Sao_Paulo');
 INSERT INTO public.user_profiles(user_id,weight_kg) VALUES(${val(owner)},80);
 INSERT INTO auth.sessions(id,user_id,created_at) VALUES(${val(login)},${val(auth)},clock_timestamp());
 INSERT INTO private.workout_strength_authority_epochs(user_id,epoch,changed_at) VALUES(${val(owner)},${val(epoch)},clock_timestamp());
 INSERT INTO public.training_plans(id,user_id,plan_type,days_per_week,weekly_schedule,generated_at,active,version)
 VALUES(${val(id(4))},${val(owner)},'full_body',2,'[{"day":"Sábado","exercises":[{"name":"Supino","sets":3,"reps_range":"8–12"},{"name":"Supino","sets":2,"reps_range":"6–8"}]}]',clock_timestamp()-interval '1 hour',true,1);
 COMMIT;`);created=true
 const home=await send('HOME');assert.equal(home.sessions.length,0)
 const start={schema:'training.execution.start.v1',session_id:session,operation_id:session,expected_epoch:epoch,
  expected_local_date:home.scope.current_local_date,plan_id:home.plan.plan_id,plan_hash:home.plan.definition_hash,day_index:0}
 const started=await send('PROGRESS',start);assert.equal(started.status,'created');assert.equal(started.receipt.after_revision,0)
 const save={schema:'training.execution.update.v1',session_id:session,operation_id:id(31),expected_epoch:epoch,expected_revision:0,
  action:{kind:'save_set',exercise_index:0,set:{id:id(30),index:0,repetitions:8,load_kg:15.5,duration_seconds:null,completed:true}}}
 const saved=await send('PROGRESS',save);assert.equal(saved.status,'updated');assert.equal(saved.current.session.revision,1)
 const stateProgress=await send('STATE')
 const finish={schema:'training.execution.finish.v1',session_id:session,operation_id:finishID,expected_epoch:epoch,expected_revision:1,source:{channel:'text',text:'Fiz full body por 30 min com intensidade moderada.'}}
 const bound=bindTrainingExecutionCompletion(owner,`tfinish1:${finishID}`,finish)
 await db.rpc('begin_training_execution_completion_authenticated',{p_user_id:owner,p_auth_user_id:auth,p_auth_session_id:login,p_command:finish})
 const reserved=(await send('STATE')).completion;assert.equal(reserved.status,'reserved')
 const reservedOld=await send('PROGRESS',save);assert.equal(reservedOld.status,'replayed');assert.deepEqual(reservedOld.receipt,saved.receipt);assert.equal(reservedOld.current.completion.status,'reserved')
 const waiting={...save,operation_id:id(32),expected_revision:1,action:{kind:'mark_exercise',exercise_index:0,completed:true}}
 const pending=await send('PROGRESS',waiting);assert.equal(pending.status,'pending');assert.equal(pending.receipt,null);assert.equal(progressCommits,2)
 const completed=await send('POST',finish);assert.equal(completed.status,'completed');assert.equal(domainCommits,1);assert.equal(completed.session.revision,2);assert.ok(completed.feedback)
 const replay=await send('PROGRESS',save);assert.equal(replay.status,'replayed');assert.deepEqual(replay.receipt,saved.receipt);assert.equal(replay.current.session.phase,'completed');assert.equal(replay.current.session.revision,2)
 const refused=await send('PROGRESS',waiting);assert.equal(refused.status,'not_applied');assert.equal(refused.receipt,null);assert.equal(refused.current.session.phase,'completed');assert.equal(progressCommits,2)
 const cold=await send('STATE'),history=await send('HOME');assert.equal(cold.session.phase,'completed');assert.equal(history.sessions[0].completed_exercises,0)
 const read=await send('READ',null,bound.inputHash);assert.deepEqual(read.receipt,completed.receipt)
 const cancelled=await send('CANCEL',{schema:'training.execution.finish-cancel.v1',session_id:session,completion_id:finishID,expected_epoch:epoch,input_hash:bound.inputHash});assert.equal(cancelled.status,'completed');assert.deepEqual(cancelled.receipt,completed.receipt)
 assert.equal(domainCommits,1);assert.equal(progressCommits,2)
 const alternate={session:id(70),completionID:id(71)}
 const altStart={...start,session_id:alternate.session,operation_id:alternate.session}
 await send('PROGRESS',altStart,null,alternate)
 const cancelFinish={...finish,session_id:alternate.session,operation_id:alternate.completionID,expected_revision:0}
 const cancelBound=bindTrainingExecutionCompletion(owner,`tfinish1:${alternate.completionID}`,cancelFinish)
 await db.rpc('begin_training_execution_completion_authenticated',{p_user_id:owner,p_auth_user_id:auth,p_auth_session_id:login,p_command:cancelFinish})
 const cancelledBeforeEffect=await send('CANCEL',{schema:'training.execution.finish-cancel.v1',session_id:alternate.session,completion_id:alternate.completionID,expected_epoch:epoch,input_hash:cancelBound.inputHash},null,alternate)
 assert.equal(cancelledBeforeEffect.status,'cancelled');assert.equal(cancelledBeforeEffect.workout,null);assert.equal(domainCommits,1)
 const cancelledCurrent=await send('STATE',null,null,alternate);assert.equal(cancelledCurrent.session.phase,'in_progress');assert.equal(cancelledCurrent.completion,null)
 const facts=query(`SELECT jsonb_build_object('workouts',(SELECT count(*) FROM public.workout_logs WHERE user_id=${val(owner)}),'progress_receipts',(SELECT count(*) FROM private.training_execution_operations WHERE user_id=${val(owner)}),'workout_receipts',(SELECT count(*) FROM private.conversation_workout_effects WHERE user_id=${val(owner)}),'feedback',(SELECT count(*) FROM private.mobile_registration_feedback_v3 WHERE user_id=${val(owner)}),'journal',(SELECT count(*) FROM private.conversation_journal_events_v3(${val(owner)},${val(epoch)}) WHERE command_id=${val(finishID)}))`)
 assert.deepEqual(facts,{workouts:1,progress_receipts:3,workout_receipts:1,feedback:1,journal:1})
 const fixture={provenance:{kind:'SYNTHETIC_ACTUAL_HTTP_SERVICE_SQL_CAPTURE_EXTERNAL_AUTH_ENTITLEMENT_INJECTED',native_or_hosted_qa:false},home,started,saved,state_progress:stateProgress,reserved_completion:reserved,completed_completion:completed,state_completed:cold,home_completed:history,progress_replay_completed:replay,progress_not_applied:refused,progress_pending:pending,reserved_old_progress:reservedOld,completion_after_cancel:cancelled,cancelled_before_effect:cancelledBeforeEffect,cancelled_current:cancelledCurrent,commands:{start,save,waiting,finish,cancelFinish},finish_hash:bound.inputHash}
 assert.ok(!/"(frozen_state|source_input|prepared|workout_hash|auth_session_id|accessToken)":/.test(JSON.stringify(fixture)))
 writeFileSync(oracle,JSON.stringify(fixture,null,2)+'\n')
 writeFileSync(output,JSON.stringify({status:'PASS',scope:'LOCAL_REAL_HANDLER_SERVICE_SQL_EXTERNAL_AUTH_ENTITLEMENT_SYNTHETIC',facts,domainCommits,progressCommits,oldReceiptWithCurrentCompleted:true,absenceNotReceipt:true,liveReservationRetainsPending:true,completionLostReplyRecovered:true,commands:counts,errors,timings,fixture:oracle},null,2)+'\n')
}finally{
 if(created){assert.deepEqual(query(`SELECT jsonb_build_object('owner',EXISTS(SELECT 1 FROM public.users WHERE id=${val(owner)} AND auth_user_id=${val(auth)} AND name='Synthetic R141 progress completion'),'auth',EXISTS(SELECT 1 FROM auth.users WHERE id=${val(auth)} AND email='r141-progress-completion@example.invalid'))`),{owner:true,auth:true});run(`BEGIN;DELETE FROM public.users WHERE id=${val(owner)} AND auth_user_id=${val(auth)};DELETE FROM auth.users WHERE id=${val(auth)} AND email='r141-progress-completion@example.invalid';COMMIT;`);assert.equal(query(`SELECT count(*) FROM private.training_execution_sessions WHERE user_id=${val(owner)}`),0)}
}
console.log(JSON.stringify({status:'PASS',output,oracle,syntheticFixtureRemoved:created}))
