#!/usr/bin/env python3
"""Physical canonical-claim concurrency proof, never an RPC/HTTP/E2E claim.
Actual trigger body + exact INSERT statements extracted from all three writers.
Only arena identifiers change; admission/source/shape/CAS wrappers are separately
qualified with their complete real bodies in rollback SQL. This arena persists
synthetic metadata temporarily for cross-connection MVCC visibility, then drops
ONLY the predeclared owned objects. No application/Auth/Storage rows are written.
"""
import argparse, hashlib, importlib.util, json, os, shlex, subprocess, time
from pathlib import Path
from urllib.parse import urlsplit, unquote

HERE=Path(__file__).resolve().parent
spec=importlib.util.spec_from_file_location('owned_actor',HERE/'conversation_workout_mobile_close_concurrency.py')
module=importlib.util.module_from_spec(spec);spec.loader.exec_module(module)
Actor=module.Actor
SCHEMA='qa_feedback_v3_139f_r1'
OWNER='139f0000-0000-4000-8000-000000000090'
REGISTRATION='139f0000-0000-4000-8000-000000000091'
STACK='19fd7fee58e80212895d9c88885dcb6a3825525642999f5d07b8dcb63652a79b'
PROFILE=module.PROFILE
sha=lambda value:hashlib.sha256(value.encode()).hexdigest()
def require(value,label):
    if value is not True:raise RuntimeError(label)
def lit(value):return "'"+str(value).replace("'","''")+"'"
def js(value):return lit(json.dumps(value,separators=(',',':')))+'::jsonb'
def section(text,start,end):
    require(text.count(start)==1,'single_source_start:'+start)
    tail=text[text.index(start):];require(end in tail,'source_end:'+end)
    return tail[:tail.index(end)+len(end)]

def run(args):
    out=Path(args.output);out.mkdir(exist_ok=False)
    source=Path(args.migration).read_text();old=json.loads(Path(args.legacy).read_text())
    trigger=section(source,'CREATE FUNCTION private.claim_mobile_registration_feedback()', 'END $$;')
    adapted=trigger
    replacements={'private.claim_mobile_registration_feedback':SCHEMA+'.claim_mobile_registration_feedback','public.users':SCHEMA+'.users','private.mobile_registration_feedback_claims':SCHEMA+'.mobile_registration_feedback_claims'}
    for before,after in replacements.items():
        require(adapted.count(before)==1,'single_trigger_adapter:'+before);adapted=adapted.replace(before,after)
    v1=next(v['definition'] for k,v in old.items() if k.startswith('commit_mobile_registration_feedback('))
    v2=next(v['definition'] for k,v in old.items() if k.startswith('commit_mobile_registration_feedback_v2('))
    inserts=[section(v1,' INSERT INTO private.mobile_registration_feedback(', 'v_revision+1,p_feedback,p_steps);'),section(v2,' INSERT INTO private.mobile_registration_feedback_v2(', "'hex'),p_feedback);"),section(source,' INSERT INTO private.mobile_registration_feedback_v3(', "'hex'),p_feedback);")]
    bodies=[]
    for index,statement in enumerate(inserts,1):
        changed=statement.replace('private.mobile_registration_feedback',SCHEMA+'.mobile_registration_feedback')
        common="DECLARE p_user_id uuid:=u;p_registration_id uuid:=r;p_origin text:=o;p_feedback jsonb:=jsonb_build_object('schema','registration.feedback.v"+str(index)+"');"
        if index==1:common+='v_pending '+SCHEMA+".pending_registrations%ROWTYPE;v_revision bigint:=0;p_steps jsonb:='[]';BEGIN SELECT * INTO STRICT v_pending FROM "+SCHEMA+'.pending_registrations WHERE id=r AND user_id=u;'
        else:common+="c jsonb:=jsonb_build_object('confirmed',jsonb_build_object('proposal',jsonb_build_object('kind','workout')),'event_hash',repeat('a',64));binding jsonb:='{}';meal uuid;BEGIN "
        bodies.append('CREATE FUNCTION pg_temp.insert_v'+str(index)+'(u uuid,r uuid,o text) RETURNS jsonb LANGUAGE plpgsql AS $body$ '+common+changed+" RETURN jsonb_build_object('inserted',"+str(index)+");END $body$;")
    # The exact claim DDL/unique index and v3 metadata DDL retain all constraints.
    claim_ddl=section(source,'CREATE TABLE private.mobile_registration_feedback_claims (','\n);').replace('private.',SCHEMA+'.')
    claim_fks=section(source,'ALTER TABLE private.mobile_registration_feedback_claims\n','REFERENCES private.conversation_workout_command_ids ON DELETE CASCADE;').replace('private.',SCHEMA+'.').replace('public.',SCHEMA+'.')
    receipt_ddl=section(source,'CREATE TABLE private.mobile_registration_feedback_v3 (','\n);').replace('private.',SCHEMA+'.').replace('public.',SCHEMA+'.')
    tables=['users','pending_registrations','conversation_workout_command_ids','conversation_meal_effects','conversation_workout_effects','mobile_registration_feedback_claims','mobile_registration_feedback','mobile_registration_feedback_v2','mobile_registration_feedback_v3']
    manifest={'owner':'/root/public_fanout_review','classification':'DISPOSABLE_SYNTHETIC','schema':SCHEMA,'tables':tables,'function':'claim_mobile_registration_feedback','fixture_owner':OWNER,'fixture_registration':REGISTRATION,'purpose':'bounded unique-index MVCC arbitration; not complete writer/RPC/E2E','maximum_metadata_rows_at_once':2,'maximum_parent_rows_at_once':4,'no_application_rows':True,'source_sha256':sha(source),'trigger_source_sha256':sha(trigger),'trigger_adapted_sha256':sha(adapted),'identifier_changes':replacements,'insert_source_sha256':[sha(s) for s in inserts],'insert_adapter':'private metadata table schema -> exact owned arena schema; unchanged columns/values/ordering','cleanup_order':'metadata tables, claims, effect/ID/pending/user parents, trigger function, schema; RESTRICT only'}
    (out/'MANIFEST-BEFORE.json').write_text(json.dumps(manifest,indent=2)+'\n')
    (out/'ADAPTED-SOURCES.json').write_text(json.dumps({'trigger_source':trigger,'trigger_adapted':adapted,'insert_statements':inserts,'candidate_adapters':bodies,'claims':claim_ddl,'claim_fks':claim_fks,'v3_receipt':receipt_ddl},indent=2)+'\n')
    r=json.loads(Path(args.registry).read_text())
    require(r['exclusive_operation_owner']=='/root/public_fanout_review' and r['running'] and r['paid'] is False,'exclusive_owner')
    require(r['stack_id']==STACK and hashlib.sha256(Path(r['psql']).read_bytes()).hexdigest()==r['psql_sha256'],'stack_psql')
    require(hashlib.sha256(Path(r['runtime_executable']).read_bytes()).hexdigest()=='acbf2c5c218837bc8f098d631091854569db5b791cb475f5f943e49f8d4cd053','runtime_sha')
    data=Path(r['guard']['data']).resolve();pidlines=(data/'postmaster.pid').read_text().splitlines();pid=int(pidlines[0])
    require(pid==r['runtime_pid'] and Path(pidlines[1]).resolve()==data,'runtime_data_pid')
    require(int(subprocess.check_output(['ps','-p',str(pid),'-o','uid='],text=True))==os.getuid(),'runtime_uid')
    require(Path(subprocess.check_output(['ps','-p',str(pid),'-o','comm='],text=True).strip()).resolve()==Path(r['runtime_executable']).resolve(),'runtime_binary')
    argv=shlex.split(subprocess.check_output(['ps','-p',str(pid),'-o','command='],text=True));dirs=[argv[i+1] for i,x in enumerate(argv[:-1]) if x=='-D']+[x[2:] for x in argv if x.startswith('-D') and len(x)>2]
    require(bool(dirs) and all(Path(p).resolve()==data for p in dirs),'every_D')
    private=json.loads(Path(r['latest_private_start']).read_text());url=urlsplit(private['env']['DB_URL']);require(private['id']==STACK and url.hostname in ['localhost','127.0.0.1'] and url.port==22981,'local_only')
    env={k:os.environ[k] for k in ['PATH','HOME','LANG','TMPDIR'] if k in os.environ};env.update(PGPASSWORD=unquote(url.password),PGCONNECT_TIMEOUT='5',PGOPTIONS='-c performe.qa_stack_id='+STACK)
    argv=['sandbox-exec','-p',PROFILE,r['psql'],'-w','-X','-q','-A','-t','-v','ON_ERROR_STOP=1','-h',url.hostname,'-p',str(url.port),'-U',url.username or 'postgres','-d',url.path.lstrip('/')]
    actors=[];created=False;result={'cases':[],'scope':manifest['purpose'],'source_adapters':manifest,'cleanup':{}}
    try:
        for name in ['A','B','observer']:
            actor=Actor(name,argv,env,out);actors.append(actor)
            actor.run("SET statement_timeout='8s';SET lock_timeout='5s';SET timezone='UTC';SET request.jwt.claims='{\"role\":\"service_role\"}';CREATE FUNCTION pg_temp.attempt(q text) RETURNS jsonb LANGUAGE plpgsql AS $$DECLARE x jsonb;code text;BEGIN EXECUTE q INTO x;RETURN jsonb_build_object('ok',true,'result',x);EXCEPTION WHEN OTHERS THEN GET STACKED DIAGNOSTICS code=RETURNED_SQLSTATE;RETURN jsonb_build_object('ok',false,'sqlstate',code);END $$;")
        A,B,C=actors
        identities=[actor.run("SELECT jsonb_build_object('pid',pg_backend_pid(),'data',current_setting('data_directory'),'tcp',inet_server_addr(),'stack',current_setting('performe.qa_stack_id'),'cron_off',current_setting('cron.launch_active_jobs')='off','net_zero',current_setting('pg_net.batch_size')='0');") for actor in actors]
        require(len({x['pid'] for x in identities})==3 and all(Path(x['data']).resolve()==data and x['tcp'] is None and x['stack']==STACK and x['cron_off'] and x['net_zero'] for x in identities),'three_guarded_backends');pids=[x['pid'] for x in identities];result['pids']=pids
        require(C.run("SELECT jsonb_build_object('schema_absent',NOT EXISTS(SELECT 1 FROM pg_namespace WHERE nspname="+lit(SCHEMA)+"),'users',(SELECT count(*) FROM public.users),'auth',(SELECT count(*) FROM auth.users),'storage',(SELECT count(*) FROM storage.objects));")=={'schema_absent':True,'users':0,'auth':0,'storage':0},'preflight_identity_empty')
        fingerprint=Path(args.global_sql).read_text();definition=fingerprint.split('BEGIN;',1)[1].split(';SELECT pg_temp.workout_global_fingerprint()',1)[0]+';'
        C.run(definition);before=C.run('SELECT pg_temp.workout_global_fingerprint();');require(len(before)==214,'global214');result['global_before_sha256']=sha(json.dumps(before,sort_keys=True))
        ddl='CREATE SCHEMA '+SCHEMA+';REVOKE ALL ON SCHEMA '+SCHEMA+' FROM PUBLIC,anon,authenticated,service_role;CREATE TABLE '+SCHEMA+'.users(id uuid PRIMARY KEY);CREATE TABLE '+SCHEMA+'.pending_registrations(id uuid PRIMARY KEY,user_id uuid NOT NULL,proposal jsonb NOT NULL);CREATE TABLE '+SCHEMA+'.conversation_workout_command_ids(user_id uuid,command_id uuid,PRIMARY KEY(user_id,command_id));'
        for table in ['conversation_meal_effects','conversation_workout_effects']:ddl+='CREATE TABLE '+SCHEMA+'.'+table+'(user_id uuid,command_id uuid,PRIMARY KEY(user_id,command_id));'
        ddl+=claim_ddl+claim_fks
        for table in ['mobile_registration_feedback','mobile_registration_feedback_v2']:ddl+='CREATE TABLE '+SCHEMA+'.'+table+'(LIKE private.'+table+' INCLUDING ALL);'
        ddl+=receipt_ddl+adapted
        C.run('BEGIN;'+ddl+'COMMIT;');created=True
        C.run('INSERT INTO '+SCHEMA+'.users VALUES('+lit(OWNER)+'::uuid);INSERT INTO '+SCHEMA+'.pending_registrations VALUES('+lit(REGISTRATION)+'::uuid,'+lit(OWNER)+'::uuid,\'{"kind":"workout"}\');INSERT INTO '+SCHEMA+'.conversation_workout_command_ids VALUES('+lit(OWNER)+'::uuid,'+lit(REGISTRATION)+'::uuid);INSERT INTO '+SCHEMA+'.conversation_workout_effects VALUES('+lit(OWNER)+'::uuid,'+lit(REGISTRATION)+'::uuid);')
        for actor in [A,B]:actor.run(''.join(bodies))
        def triggers(enabled):
            for version in [1,2,3]:
                table='mobile_registration_feedback'+('' if version==1 else '_v'+str(version))
                if enabled:C.run('CREATE TRIGGER canonical_v'+str(version)+' BEFORE INSERT ON '+SCHEMA+'.'+table+' FOR EACH ROW EXECUTE FUNCTION '+SCHEMA+'.claim_mobile_registration_feedback();')
                else:C.run('DROP TRIGGER canonical_v'+str(version)+' ON '+SCHEMA+'.'+table+';')
        def candidate(version,origin='pending_registration'):
            return 'SELECT pg_temp.insert_v'+str(version)+'('+lit(OWNER)+'::uuid,'+lit(REGISTRATION)+'::uuid,'+lit(origin)+')'
        def attempt(actor,version,origin='pending_registration'):return actor.send('SELECT pg_temp.attempt('+lit(candidate(version,origin))+');')
        def state():
            return C.run('SELECT jsonb_build_object('+','.join(lit('v'+str(v))+',(SELECT count(*) FROM '+SCHEMA+'.mobile_registration_feedback'+('' if v==1 else '_v'+str(v))+')' for v in [1,2,3])+",'claims',(SELECT count(*) FROM "+SCHEMA+'.mobile_registration_feedback_claims));')
        def clear():
            for table in ['mobile_registration_feedback','mobile_registration_feedback_v2','mobile_registration_feedback_v3','mobile_registration_feedback_claims']:C.run('DELETE FROM '+SCHEMA+'.'+table+' WHERE user_id='+lit(OWNER)+'::uuid;')
            require(state()=={'v1':0,'v2':0,'v3':0,'claims':0},'only_arena_cleanup')
        # Negative control: both extracted physical INSERTs commit without claim.
        A.run('BEGIN ISOLATION LEVEL REPEATABLE READ;SELECT count(*) FROM '+SCHEMA+'.mobile_registration_feedback;')
        B.run('BEGIN;'+candidate(3)+';COMMIT;')
        a=A.receive(attempt(A,1));A.run('COMMIT;');require(a['ok'] and state()=={'v1':1,'v2':0,'v3':1,'claims':0},'RED_unguarded_boundary_duplicates');result['cases'].append({'case':'RED_UNGUARDED_STALE_RR','A':a,'state':state()});clear();triggers(True)
        for level in ['REPEATABLE READ','SERIALIZABLE']:
            for winner in [2,3]:
                A.run('BEGIN ISOLATION LEVEL '+level+';SELECT count(*) FROM '+SCHEMA+'.mobile_registration_feedback_claims;')
                B.run('BEGIN;'+candidate(winner)+';COMMIT;')
                a=A.receive(attempt(A,1));A.run('ROLLBACK;');expected={'v1':0,'v2':int(winner==2),'v3':int(winner==3),'claims':1}
                require(a=={'ok':False,'sqlstate':'40001'} and state()==expected,'GREEN_stale_snapshot_unique');result['cases'].append({'case':level+'_V1_vs_'+str(winner),'A':a,'state':state()});clear()
        # Deterministic owner-row blocking shows simultaneous physical attempts.
        for winner,loser in [(1,2),(2,1),(1,3),(3,1),(2,3),(3,2),(3,3)]:
            A.run('BEGIN;');a=A.receive(attempt(A,winner));require(a['ok'],'first_insert')
            B.run('BEGIN;');tag=attempt(B,loser);end=time.monotonic()+2;edge=False
            while time.monotonic()<end:
                edge=C.run('SELECT jsonb_build_object(\'edge\','+str(pids[0])+'=ANY(pg_blocking_pids('+str(pids[1])+')));')['edge']
                if edge:break
                time.sleep(.01)
            require(edge,'actual_wait_edge');A.run('COMMIT;');b=B.receive(tag);B.run('ROLLBACK;')
            require(b=={'ok':False,'sqlstate':'23505'} and state()['claims']==1 and sum(state()['v'+str(v)] for v in [1,2,3])==1,'RC_one_physical_winner');result['cases'].append({'case':'RC_'+str(winner)+'_before_'+str(loser),'B_waited_for_A':edge,'B':b,'state':state()});clear()
        A.run('BEGIN;'+candidate(3)+';COMMIT;');B.run('BEGIN;'+candidate(3,'conversation_workout')+';COMMIT;')
        require(state()=={'v1':0,'v2':0,'v3':2,'claims':2},'real_origins_distinct');result['cases'].append({'case':'SAME_UUID_DISTINCT_ORIGINS','state':state()});clear()
        require(C.run('SELECT jsonb_build_object(\'same\',pg_temp.workout_global_fingerprint()='+js(before)+');')['same'],'global_unchanged_during_arena')
        result['status']='PASS_PHYSICAL_BOUNDARY_RED_GREEN'
    finally:
        if len(actors)==3:
            A,B,C=actors
            for actor in [A,B]:actor.close()
            try:
                if created:
                    actual=C.run("SELECT jsonb_build_object('tables',(SELECT jsonb_agg(c.relname ORDER BY c.relname) FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname="+lit(SCHEMA)+" AND c.relkind='r'),'outsiders',(SELECT count(*) FROM "+SCHEMA+'.users WHERE id<>'+lit(OWNER)+'::uuid));')
                    require(actual['tables']==sorted(tables) and actual['outsiders']==0,'exact_declared_arena_before_drop')
                    for table in ['mobile_registration_feedback_v3','mobile_registration_feedback_v2','mobile_registration_feedback','mobile_registration_feedback_claims','conversation_workout_effects','conversation_meal_effects','conversation_workout_command_ids','pending_registrations','users']:C.run('DROP TABLE '+SCHEMA+'.'+table+' RESTRICT;')
                    C.run('DROP FUNCTION '+SCHEMA+'.claim_mobile_registration_feedback() RESTRICT;DROP SCHEMA '+SCHEMA+' RESTRICT;')
                final=C.run("SELECT jsonb_build_object('schema_absent',NOT EXISTS(SELECT 1 FROM pg_namespace WHERE nspname="+lit(SCHEMA)+"),'global',pg_temp.workout_global_fingerprint(),'actors',(SELECT count(*) FROM pg_stat_activity WHERE pid=ANY(ARRAY["+str(pids[0])+','+str(pids[1])+'])));')
                require(final['schema_absent'] and final['global']==before and final['actors']==0,'arena_absent_exact214_and_actors_ended');result['cleanup']={'schema_absent':True,'global214_exact':True,'Auth0':True,'Storage0':True,'actor_backends':0}
            finally:C.close()
        else:
            for actor in actors:actor.close()
        result['all_clients_ended']=all(actor.proc.poll() is not None for actor in actors)
        (out/'RESULT.json').write_text(json.dumps(result,indent=2)+'\n')
    print(json.dumps({'status':result['status'],'cases':len(result['cases']),'cleanup':result['cleanup'],'output':str(out)}))
if __name__=='__main__':
    p=argparse.ArgumentParser();p.add_argument('--registry',required=True);p.add_argument('--migration',required=True);p.add_argument('--legacy',required=True);p.add_argument('--global-sql',required=True);p.add_argument('--output',required=True);run(p.parse_args())
