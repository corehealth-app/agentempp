#!/usr/bin/env python3
"""Owned local SQL-body lock regression; no runtime lifecycle/cloud/DDL install.
Uses exact extracted R1/R2 bodies with documented temp identifier adapters.
Seed is narrowly committed for A/B visibility; both actors roll back, then owner
is deleted only after exact fixture/actor checks. Never an HTTP/E2E claim.
"""
import argparse, hashlib, json, os, queue, shlex, subprocess, threading, time
from pathlib import Path
from urllib.parse import urlsplit, unquote

OWNER='139c0000-0000-4000-8000-000000000399'
SNAPSHOT='139c0000-0000-4000-8000-000000000398'
EMAIL='workout-r2-lock-only@example.invalid'
STACK='19fd7fee58e80212895d9c88885dcb6a3825525642999f5d07b8dcb63652a79b'
PROFILE='(version 1)(allow default)(deny network*)(allow network* (local ip "localhost:*") (remote ip "localhost:*"))(allow network* (local unix-socket) (remote unix-socket))'
sha=lambda p:hashlib.sha256(Path(p).read_bytes()).hexdigest()
def lit(v):return "'"+str(v).replace("'","''")+"'"
def js(v):return lit(json.dumps(v,separators=(',',':')))+'::jsonb'
def require(v,label):
    if v is not True:raise RuntimeError(label)

class Actor:
    def __init__(self,name,argv,env,out):
        self.name=name;self.serial=0;self.q=queue.Queue();self.err=[]
        self.log=open(out/(name+'.private.log'),'x');os.chmod(self.log.name,0o600)
        self.proc=subprocess.Popen(argv,env={**env,'PGAPPNAME':'workout-r2-lock-'+name},stdin=subprocess.PIPE,stdout=subprocess.PIPE,stderr=subprocess.PIPE,text=True,bufsize=1)
        self.threads=[]
        for stream,error in [(self.proc.stdout,False),(self.proc.stderr,True)]:
            t=threading.Thread(target=self.read,args=(stream,error),daemon=True);t.start();self.threads.append(t)
    def read(self,stream,error):
        for line in stream:
            self.log.write(line);self.log.flush()
            if error:self.err.append(line)
            else:self.q.put(line.rstrip('\n'))
    def send(self,sql):
        self.serial+=1;tag=f'__workout_r2_{self.name}_{self.serial}__'
        self.proc.stdin.write(sql+'\n\\echo '+tag+'\n');self.proc.stdin.flush();return tag
    def receive(self,tag,timeout=6):
        lines=[];end=time.monotonic()+timeout
        while time.monotonic()<end:
            try:x=self.q.get(timeout=min(.05,max(.001,end-time.monotonic())))
            except queue.Empty:
                if self.proc.poll() is not None:raise RuntimeError('actor_ended_'+self.name)
                continue
            if x==tag:
                values=[json.loads(v) for v in lines if v.startswith('{') or v.startswith('[')]
                return values[-1] if values else None
            lines.append(x)
        raise TimeoutError('actor_timeout_'+self.name)
    def run(self,sql,timeout=6):return self.receive(self.send(sql),timeout)
    def close(self):
        if self.proc.poll() is None:
            try:self.proc.stdin.close();self.proc.wait(timeout=2)
            except (subprocess.TimeoutExpired,BrokenPipeError):self.proc.terminate();self.proc.wait(timeout=2)
        for t in self.threads:t.join(timeout=.5)
        self.log.close()

def run(a):
    registry=Path(a.registry);r=json.loads(registry.read_text())
    require(r['exclusive_operation_owner']=='/root/public_fanout_review' and r['running'] and r['paid'] is False,'exclusive_registry')
    require(r['stack_id']==STACK and sha(r['psql'])==r['psql_sha256'],'stack_psql_pin')
    data=Path(r['guard']['data']).resolve();lines=(data/'postmaster.pid').read_text().splitlines();pid=int(lines[0]);require(pid==r['runtime_pid'] and Path(lines[1]).resolve()==data,'postmaster_data')
    require(int(subprocess.check_output(['ps','-p',str(pid),'-o','uid='],text=True))==os.getuid(),'runtime_uid')
    require(Path(subprocess.check_output(['ps','-p',str(pid),'-o','comm='],text=True).strip()).resolve()==Path(r['runtime_executable']).resolve(),'runtime_binary')
    parts=shlex.split(subprocess.check_output(['ps','-p',str(pid),'-o','command='],text=True));dirs=[parts[i+1] for i,v in enumerate(parts[:-1]) if v=='-D']+[v[2:] for v in parts if v.startswith('-D') and len(v)>2];require(bool(dirs) and all(Path(v).resolve()==data for v in dirs),'every_runtime_D')
    private=Path(r['latest_private_start']);start=json.loads(private.read_text());require(start['id']==STACK,'private_stack')
    url=urlsplit(start['env']['DB_URL']);require(url.hostname in ['127.0.0.1','localhost'] and url.port==22981,'loopback')
    env={k:os.environ[k] for k in ['PATH','HOME','LANG','TMPDIR'] if k in os.environ};env.update(PGPASSWORD=unquote(url.password),PGCONNECT_TIMEOUT='5',PGOPTIONS='-c performe.qa_stack_id='+STACK)
    argv=['sandbox-exec','-p',PROFILE,r['psql'],'-w','-X','-q','-A','-t','-v','ON_ERROR_STOP=1','-h',url.hostname,'-p',str(url.port),'-U',url.username or 'postgres','-d',url.path.lstrip('/')]
    out=Path(a.output);out.mkdir(exist_ok=False);actors=[];seeded=False;result={'mode':'actual SQL-body concurrency via pg_temp adapters; not public RPC/HTTP/E2E','cases':[],'fixture_owner':OWNER,'public_DDL_persisted':False,'cleanup':{}}
    try:
        for name in ['A','B','observer']:
            actor=Actor(name,argv,env,out);actors.append(actor)
            actor.run("SET timezone='UTC';SET statement_timeout='8s';SET lock_timeout='4s';SET deadlock_timeout='1s';SET request.jwt.claims='{\"role\":\"service_role\"}'; CREATE FUNCTION pg_temp.attempt(q text) RETURNS jsonb LANGUAGE plpgsql AS $$ DECLARE v jsonb;code text;message text;BEGIN EXECUTE q INTO v;RETURN jsonb_build_object('ok',true,'result',v);EXCEPTION WHEN OTHERS THEN GET STACKED DIAGNOSTICS code=RETURNED_SQLSTATE,message=MESSAGE_TEXT;RETURN jsonb_build_object('ok',false,'sqlstate',code,'message',message);END $$;")
        A,B,C=actors
        identities=[x.run("SELECT jsonb_build_object('pid',pg_backend_pid(),'data',current_setting('data_directory'),'stack',current_setting('performe.qa_stack_id'),'tcp',inet_server_addr(),'cron_off',current_setting('cron.launch_active_jobs')='off','net_zero',current_setting('pg_net.batch_size')='0');") for x in actors]
        require(len({x['pid'] for x in identities})==3 and all(Path(x['data']).resolve()==data and x['stack']==STACK and x['tcp'] is None and x['cron_off'] and x['net_zero'] for x in identities),'distinct_exact_native_backends');pids=[x['pid'] for x in identities];result['backend_pids']=pids
        counts=C.run("SELECT jsonb_build_object('users',(SELECT count(*) FROM public.users),'auth',(SELECT count(*) FROM auth.users),'storage',(SELECT count(*) FROM storage.objects),'owner',(SELECT count(*) FROM public.users WHERE id="+lit(OWNER)+"::uuid),'workout_ddl',to_regclass('private.conversation_workout_command_ids') IS NOT NULL);")
        require(counts=={'users':0,'auth':0,'storage':0,'owner':0,'workout_ddl':False},'empty_owned_baseline');result['before']=counts
        C.run("BEGIN;INSERT INTO public.users(id,email,status,timezone,country,country_confirmed) VALUES("+lit(OWNER)+"::uuid,"+lit(EMAIL)+",'active','UTC','BR',true);INSERT INTO public.user_profiles(user_id,weight_kg,current_protocol,deficit_level) VALUES("+lit(OWNER)+"::uuid,80,'recomposicao',500);INSERT INTO public.daily_snapshots(id,user_id,date,calories_consumed,calories_target,protein_g,protein_target) VALUES("+lit(SNAPSHOT)+"::uuid,"+lit(OWNER)+"::uuid,(clock_timestamp() AT TIME ZONE 'UTC')::date-1,1500,1900,100,120);COMMIT;");seeded=True
        packet=C.run("SELECT jsonb_build_object('snapshot',to_jsonb(d),'profile',to_jsonb(p)) FROM public.daily_snapshots d JOIN public.user_profiles p ON p.user_id=d.user_id WHERE d.id="+lit(SNAPSHOT)+"::uuid AND d.user_id="+lit(OWNER)+"::uuid;");require(isinstance(packet,dict),'fixture_captured')
        defs=[json.loads(Path(p).read_text()) for p in [a.r1,a.r2]];require(defs[0]['base_def']==defs[1]['base_def'],'same_exact_base')
        for definition in defs:
            for field in ['base','mobile']:
                body=definition[field+'_def'].split('AS $function$',1)[1].rsplit('$function$',1)[0]
                require(hashlib.sha256(body.encode()).hexdigest()==definition[field+'_sha'],'extracted_actual_prosrc_sha')
        owner_select='  SELECT * INTO v_user FROM public.users WHERE id = p_user_id FOR SHARE NOWAIT;'
        early_lane="  PERFORM pg_advisory_xact_lock(hashtextextended(p_user_id::text||':workouts',0));\n"
        require(defs[0]['mobile_def'].count(owner_select)==1 and defs[1]['mobile_def']==defs[0]['mobile_def'].replace(owner_select,early_lane+owner_select,1),'only_R2_body_change_is_early_owner_lane')
        base=defs[0]['base_def'];require(base.count('CREATE OR REPLACE FUNCTION public.finalize_daily_close_atomic(')==1,'base_identifier')
        adapted=base.replace('CREATE OR REPLACE FUNCTION public.finalize_daily_close_atomic(','CREATE OR REPLACE FUNCTION pg_temp.actual_base(',1)
        needle='EXISTS(SELECT 1 FROM public.daily_snapshots WHERE id=p_snapshot_id AND user_id=p_user_id AND NOT exercise_energy_complete)';require(adapted.count(needle)==1,'single_coverage_adapter')
        adapted=adapted.replace(needle,needle.replace('public.daily_snapshots','pg_temp.qa_snapshot_coverage'),1)
        A.run("CREATE TEMP VIEW qa_snapshot_coverage AS SELECT d.*,NOT EXISTS(SELECT 1 FROM public.workout_logs w WHERE w.user_id=d.user_id AND w.snapshot_id=d.id AND w.estimated_kcal IS NULL) AS exercise_energy_complete FROM public.daily_snapshots d WHERE d.user_id="+lit(OWNER)+"::uuid;"+adapted.rstrip("; \n")+";")
        names=['p_user_id','p_snapshot_id','p_day_status','p_xp_total','p_level','p_current_streak','p_longest_streak','p_blocks_completed','p_deficit_block','p_badges_earned','p_last_active_date','p_closed_at']
        gate=adapted.replace('CREATE OR REPLACE FUNCTION pg_temp.actual_base(','CREATE OR REPLACE FUNCTION pg_temp.gate_finalizer(',1)
        head,body=gate.split('AS $function$',1);old_body,tail=body.rsplit('$function$',1)
        gate=head+'AS $function$ BEGIN PERFORM pg_advisory_xact_lock(hashtextextended('+lit(OWNER+':r2-probe-gate')+",0)); RETURN pg_temp.actual_base("+','.join(names)+"); END $function$"+tail;A.run(gate.rstrip("; \n")+";")
        result['source_adapters']={'R1_mobile_sha':defs[0]['mobile_sha'],'R2_mobile_sha':defs[1]['mobile_sha'],'base_sha':defs[0]['base_sha'],'base_adapted_sha256':hashlib.sha256(adapted.encode()).hexdigest(),'exact_changes':['public.finalize_daily_close_atomic identifier -> pg_temp.actual_base','one coverage query public.daily_snapshots -> pg_temp.qa_snapshot_coverage (actual owned NULL-row proof, no public column DDL)','mobile function identifier -> pg_temp.mobile_r1/mobile_r2','mobile delegate identifier -> pg_temp.gate_finalizer; gate then calls identical adapted base'],'coverage_view':'actual full owned workout NULL predicate; known fixture, not a fabricated zero/flag','gate_body':gate}
        def state():return C.run("SELECT jsonb_build_object('snapshot',(SELECT to_jsonb(d) FROM public.daily_snapshots d WHERE id="+lit(SNAPSHOT)+"::uuid),'profile',(SELECT to_jsonb(p) FROM public.user_profiles p WHERE user_id="+lit(OWNER)+"::uuid),'workouts',(SELECT count(*) FROM public.workout_logs WHERE user_id="+lit(OWNER)+"::uuid),'progress',(SELECT count(*) FROM public.user_progress WHERE user_id="+lit(OWNER)+"::uuid));")
        original=state()
        def wait_edge(waiter,blocker,advisory=None):
            end=time.monotonic()+1.3
            while time.monotonic()<end:
                q="SELECT jsonb_build_object('edge',"+str(blocker)+"=ANY(pg_blocking_pids("+str(waiter)+")),'advisory',(SELECT count(*) FROM pg_locks WHERE pid="+str(waiter)+" AND locktype='advisory' AND NOT granted));"
                v=C.run(q)
                if v['edge'] and (advisory is None or (v['advisory']>0)==advisory):return v
                time.sleep(.01)
            raise TimeoutError('expected_actual_blocker_edge')
        day=packet['snapshot']['date'];args=','.join([lit(OWNER)+'::uuid',lit(SNAPSHOT)+'::uuid',"'complete'",'10','1','1','1','0','0','ARRAY[]::text[]',lit(day)+'::date','clock_timestamp()',"'UTC'",js(packet['snapshot']),js(packet['profile']),'NULL'])
        adapted_mobiles=[]
        for index,kind in enumerate(['R1_RED','R2_GREEN']):
            mobile=defs[index]['mobile_def'];require(mobile.count('CREATE OR REPLACE FUNCTION public.finalize_mobile_daily_close_atomic(')==1 and mobile.count('public.finalize_daily_close_atomic(')==1,'exact_mobile_identifiers')
            mobile=mobile.replace('CREATE OR REPLACE FUNCTION public.finalize_mobile_daily_close_atomic(','CREATE OR REPLACE FUNCTION pg_temp.mobile_'+str(index)+'(',1).replace('public.finalize_daily_close_atomic(','pg_temp.gate_finalizer(',1);adapted_mobiles.append(mobile);A.run(mobile.rstrip("; \n")+";")
            C.run('SELECT pg_advisory_lock(hashtextextended('+lit(OWNER+':r2-probe-gate')+',0));')
            A.run('BEGIN;');B.run('BEGIN;')
            at=A.send('SELECT pg_temp.attempt('+lit('SELECT pg_temp.mobile_'+str(index)+'('+args+')')+');');wait_edge(pids[0],pids[2],True)
            writer='SELECT public.register_workout_atomic('+','.join([lit(OWNER)+'::uuid',lit(day)+'::date',"'caminhada'",'30','100',"'moderada'",'NULL',lit(day+'T12:00:00Z')+'::timestamptz',lit('workout-r2-lock-'+kind),'1900','120','false','NULL'])+')'
            bt=B.send('SELECT pg_temp.attempt('+lit(writer)+');');edge=wait_edge(pids[1],pids[0],index==1)
            C.run('SELECT pg_advisory_unlock(hashtextextended('+lit(OWNER+':r2-probe-gate')+',0));')
            if index==0:
                ar=A.receive(at);A.run('ROLLBACK;');br=B.receive(bt);B.run('ROLLBACK;');require(any(x.get('sqlstate')=='40P01' for x in [ar,br]),'R1_actual_deadlock_reproduced')
            else:
                ar=A.receive(at);require(ar.get('ok') is True and ar['result'].get('applied') is True,'R2_mobile_completed');A.run('ROLLBACK;');br=B.receive(bt);require(br.get('ok') is True,'R2_known_registrar_completed');B.run('ROLLBACK;')
            require(state()==original,'both_actor_effects_rolled_back')
            result['cases'].append({'case':kind,'B_waits_for_A':edge,'A':ar,'B':br,'fixture_state_unchanged':True})
        (out/'ADAPTED-DEFINITIONS.json').write_text(json.dumps({'base':adapted,'gate':gate,'mobiles':adapted_mobiles,'coverage_view':"SELECT d.*,NOT EXISTS(SELECT 1 FROM public.workout_logs w WHERE w.user_id=d.user_id AND w.snapshot_id=d.id AND w.estimated_kcal IS NULL) AS exercise_energy_complete FROM public.daily_snapshots d WHERE d.user_id="+lit(OWNER)+"::uuid"},indent=2)+'\n')
        result['status']='PASS_RED_DEADLOCK_GREEN_SERIALIZED'
    finally:
        if len(actors)==3:
            A,B,C=actors
            for x in [A,B]:x.close()
            try:
                if seeded:
                    clean=C.run("SELECT jsonb_build_object('safe',count(*)=1 AND bool_and(email="+lit(EMAIL)+" AND auth_user_id IS NULL AND wpp IS NULL),'workouts',(SELECT count(*) FROM public.workout_logs WHERE user_id="+lit(OWNER)+"::uuid),'progress',(SELECT count(*) FROM public.user_progress WHERE user_id="+lit(OWNER)+"::uuid)) FROM public.users WHERE id="+lit(OWNER)+"::uuid;")
                    require(clean=={'safe':True,'workouts':0,'progress':0},'strict_fixture_only_cleanup')
                    C.run('DELETE FROM public.users WHERE id='+lit(OWNER)+'::uuid AND email='+lit(EMAIL)+';')
                final=C.run("SELECT jsonb_build_object('users',(SELECT count(*) FROM public.users),'auth',(SELECT count(*) FROM auth.users),'storage',(SELECT count(*) FROM storage.objects),'actors',(SELECT count(*) FROM pg_stat_activity WHERE pid=ANY(ARRAY["+str(pids[0])+','+str(pids[1])+']))) ;')
                require(final=={'users':0,'auth':0,'storage':0,'actors':0},'owner_auth_storage_and_actor_cleanup');result['cleanup']=final
            finally:C.close()
        else:
            for x in actors:x.close()
        result['actor_clients_ended']=all(x.proc.poll() is not None for x in actors)
        (out/'RESULT.json').write_text(json.dumps(result,indent=2)+'\n')
    print(json.dumps({'status':result['status'],'cases':len(result['cases']),'cleanup':result['cleanup'],'output':str(out)}))

if __name__=='__main__':
    p=argparse.ArgumentParser();p.add_argument('--registry',required=True);p.add_argument('--r1',required=True);p.add_argument('--r2',required=True);p.add_argument('--output',required=True);run(p.parse_args())
