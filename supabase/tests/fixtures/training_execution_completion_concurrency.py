#!/usr/bin/env python3
"""Exact owned local R139 copy only; real concurrent SQL actors. No cloud.
The synthetic fixture is briefly committed for visibility, then removed by its
exact owner/Auth IDs. The source database and any other actor are out of scope.
"""
import hashlib
import json
import os
from pathlib import Path
import queue
import subprocess
import sys
import threading
import time

registry, fixture, golden, output = map(Path, sys.argv[1:])
r = json.loads(registry.read_text())
assert r['owner'] == '/root/R139' and r['running'] and r['paid'] is False
assert r['test_database'] == 'performe_r139_completion'
assert r['socket'].startswith('/tmp/performe-r139-')
assert (Path(r['data'])/'postmaster.pid').read_text().splitlines()[0] == str(r['pid'])
assert hashlib.sha256(Path(r['psql']).read_bytes()).hexdigest() == r['psql_sha256']
assert Path(r['socket']).stat().st_mode & 0o777 == 0o700
g = json.loads(golden.read_text())
owner, auth = g['begin']['scope']['owner_id'], g['begin']['scope']['auth_user_id']
assert owner == '13700000-0000-4000-8000-000000000002'
assert auth == '13700000-0000-4000-8000-000000000001'
login = '139d0000-0000-4000-8000-000000000005'
args = ['/usr/bin/sandbox-exec','-p',r['sandbox_profile'],r['psql'],'-w','-X','-q','-A','-t','-v','ON_ERROR_STOP=1',
        '-h',r['socket'],'-p',str(r['port']),'-U','postgres','-d',r['test_database']]
env = {k:os.environ[k] for k in ['PATH','HOME','LANG','TMPDIR'] if k in os.environ}
lit = lambda v: "'" + str(v).replace("'","''") + "'"
js = lambda v: lit(json.dumps(v,ensure_ascii=False,separators=(',',':'))) + '::jsonb'
def once(sql):
    p = subprocess.run(args,input=sql,text=True,capture_output=True,env={**env,'PGAPPNAME':'r139-completion-observer'},timeout=10)
    assert p.returncode == 0, p.stderr
    return [json.loads(s) for s in p.stdout.splitlines() if s.startswith('{')]

identity = once("SELECT jsonb_build_object('db',current_database(),'data',current_setting('data_directory'),'sysid',(SELECT system_identifier::text FROM pg_control_system()),'listen',current_setting('listen_addresses'),'other_clients',(SELECT count(*) FROM pg_stat_activity WHERE pid<>pg_backend_pid() AND backend_type='client backend')); ")[0]
assert identity == {'db':r['test_database'],'data':r['data'],'sysid':r['source_sysid'],'listen':'','other_clients':0}, identity
assert once(f"SELECT jsonb_build_object('owners',(SELECT count(*) FROM public.users WHERE id={lit(owner)}),'auth',(SELECT count(*) FROM auth.users WHERE id={lit(auth)}));")[0] == {'owners':0,'auth':0}
output.mkdir(parents=True,exist_ok=False)

class Actor:
    def __init__(self,name):
        self.name=name; self.serial=0; self.q=queue.Queue(); self.errors=[]
        self.log=(output/(name+'.log')).open('x');os.chmod(self.log.name,0o600)
        self.p=subprocess.Popen(args,stdin=subprocess.PIPE,stdout=subprocess.PIPE,stderr=subprocess.PIPE,
            text=True,bufsize=1,env={**env,'PGAPPNAME':'r139-completion-'+name})
        self.threads=[]
        for stream,error in [(self.p.stdout,False),(self.p.stderr,True)]:
            t=threading.Thread(target=self.read,args=(stream,error),daemon=True);t.start();self.threads.append(t)
    def read(self,stream,error):
        for line in stream:
            self.log.write(line);self.log.flush()
            if error:self.errors.append(line)
            else:self.q.put(line.strip())
    def send(self,sql):
        self.serial+=1;tag=f'__r139_{self.name}_{self.serial}__'
        self.p.stdin.write(sql+'\n\\echo '+tag+'\n');self.p.stdin.flush();return tag
    def receive(self,tag):
        data=[];until=time.monotonic()+8
        while time.monotonic()<until:
            try:x=self.q.get(timeout=.05)
            except queue.Empty:
                if self.p.poll() is not None:raise RuntimeError('Actor ended: '+''.join(self.errors))
                continue
            if x==tag:return data[-1] if data else None
            if x.startswith('{'):data.append(json.loads(x))
        raise TimeoutError(self.name)
    def run(self,sql):return self.receive(self.send(sql))
    def close(self):
        if self.p.poll() is None:
            try:self.p.stdin.close();self.p.wait(timeout=3)
            except (subprocess.TimeoutExpired,BrokenPipeError):self.p.terminate();self.p.wait(timeout=3)
        for t in self.threads:t.join(timeout=.5)
        self.log.close()

def begin(command):
    return f"public.begin_training_execution_completion_authenticated({lit(owner)},{lit(auth)},{lit(login)},{js(command)})"
def commit(x,command):
    return f"public.commit_training_execution_completion_authenticated({lit(owner)},{lit(auth)},{lit(login)},{lit(command['operation_id'])},{lit(x['begin']['completion']['input_hash'])},{lit(x['source']['source_hash'])},{lit(x['prepared']['prepared_hash'])},{js(x['prepared']['prepared'])})"
def cancel(x,command):
    return f"public.cancel_training_execution_completion_authenticated({lit(owner)},{lit(auth)},{lit(login)},{lit(command['operation_id'])},{lit(x['begin']['completion']['input_hash'])})"
def waiting(actor):
    until=time.monotonic()+5
    while time.monotonic()<until:
        observed=once(f"SELECT jsonb_build_object('waiting',EXISTS(SELECT 1 FROM pg_stat_activity WHERE application_name={lit('r139-completion-'+actor.name)} AND wait_event_type='Lock')); ")[0]
        if observed['waiting']:return
        time.sleep(.05)
    raise AssertionError('second owned actor never waited on the real lock')

actors=[];created=False
try:
    seed=fixture.read_text().split('CREATE TEMP TABLE finish_fixture')[0]+'\nCOMMIT;'
    once(seed);created=True
    a=Actor('A');b=Actor('B');actors.extend([a,b]);command=g['command']
    first=a.run('BEGIN; SELECT '+begin(command)+';');assert first['action']=='reserved'
    different={**command,'operation_id':'139d0000-0000-4000-8000-000000000088'}
    b.send('BEGIN; SELECT '+begin(different)+'; COMMIT;');waiting(b)
    a.run('COMMIT;');b.p.wait(timeout=8)
    assert b.p.returncode==3 and any('training_completion_in_progress_or_operation_used' in e for e in b.errors)
    b.close();actors.remove(b)
    once('SELECT '+cancel({'begin':first},command)+';')
    # New accepted operation after safe cancellation. All preparation is real SQL.
    command={**command,'operation_id':'139d0000-0000-4000-8000-000000000099'}
    x=once(f"WITH b AS MATERIALIZED(SELECT {begin(command)} value), s AS MATERIALIZED(SELECT public.capture_conversation_workout_source({lit(owner)},{lit(command['operation_id'])},b.value#>>'{{completion,workout_hash}}',{lit(command['expected_epoch'])}) value FROM b), p AS MATERIALIZED(SELECT public.prepare_conversation_workout({lit(owner)},{lit(command['operation_id'])},b.value#>>'{{completion,workout_hash}}',s.value->>'source_hash',{lit(command['expected_epoch'])},private.conversation_workout_report_v2(s.value->'context',s.value->>'source_hash')) value FROM b,s) SELECT jsonb_build_object('begin',b.value,'source',s.value,'prepared',p.value) FROM b,s,p;")[0]
    assert x['prepared']['prepared']['status']=='ready'
    b=Actor('cancel');actors.append(b)
    committed=a.run('BEGIN; SELECT '+commit(x,command)+';');assert committed['action']=='committed'
    tag=b.send('BEGIN; SELECT '+cancel(x,command)+'; COMMIT;');waiting(b)
    a.run('COMMIT;');c=b.receive(tag)
    assert c['action']=='completed' and c['receipt']['workout']==committed['receipt']
    b.close();actors.remove(b)
    # Reverse order on another explicit owned execution: cancellation commits
    # first and the already prepared late finisher must be refused.
    second='13700000-0000-4000-8000-000000000021'
    once(f"INSERT INTO private.training_execution_sessions(user_id,session_id,epoch,revision,state) SELECT user_id,{lit(second)},epoch,0,jsonb_set(frozen_state,'{{id}}',to_jsonb({lit(second)}::text)) FROM private.training_execution_completions WHERE user_id={lit(owner)} AND completion_id='139d0000-0000-4000-8000-000000000003';")
    command={**command,'session_id':second,'operation_id':'139d0000-0000-4000-8000-000000000098'}
    x=once(f"WITH b AS MATERIALIZED(SELECT {begin(command)} value), s AS MATERIALIZED(SELECT public.capture_conversation_workout_source({lit(owner)},{lit(command['operation_id'])},b.value#>>'{{completion,workout_hash}}',{lit(command['expected_epoch'])}) value FROM b), p AS MATERIALIZED(SELECT public.prepare_conversation_workout({lit(owner)},{lit(command['operation_id'])},b.value#>>'{{completion,workout_hash}}',s.value->>'source_hash',{lit(command['expected_epoch'])},private.conversation_workout_report_v2(s.value->'context',s.value->>'source_hash')) value FROM b,s) SELECT jsonb_build_object('begin',b.value,'source',s.value,'prepared',p.value) FROM b,s,p;")[0]
    assert x['prepared']['prepared']['status']=='ready'
    cancelled=a.run('BEGIN; SELECT '+cancel(x,command)+';');assert cancelled['action']=='cancelled'
    b=Actor('late-finish');actors.append(b)
    b.send('BEGIN; SELECT '+commit(x,command)+'; COMMIT;');waiting(b)
    a.run('COMMIT;');b.p.wait(timeout=8)
    assert b.p.returncode==3 and any('training_completion_cancelled' in e for e in b.errors)
    for actor in actors:actor.close()
    actors=[]
    proof=once(f"SELECT jsonb_build_object('workouts',(SELECT count(*) FROM public.workout_logs WHERE user_id={lit(owner)}),'finishes',(SELECT count(*) FROM private.training_execution_completions WHERE user_id={lit(owner)} AND status='completed'),'completion_events',(SELECT count(*) FROM private.training_execution_completion_events WHERE user_id={lit(owner)} AND kind='completed'));")[0]
    assert proof=={'workouts':1,'finishes':1,'completion_events':1},proof
    (output/'RESULT.json').write_text(json.dumps({'status':'PASS','new_nonce_race':'real lock observed; one reservation; other refused','commit_cancel_race':'both real lock orders observed; winner preserved; cancelled late finisher refused','proof':proof},indent=2)+'\n')
finally:
    for actor in actors:actor.close()
    if created:
        # Exact synthetic identity proof, never broad cleanup.
        before=once(f"SELECT jsonb_build_object('owner',EXISTS(SELECT 1 FROM public.users WHERE id={lit(owner)} AND auth_user_id={lit(auth)} AND name='Synthetic R139 training completion'),'auth',EXISTS(SELECT 1 FROM auth.users WHERE id={lit(auth)} AND email='r139-training-completion@example.invalid'));")[0]
        assert before=={'owner':True,'auth':True},before
        once(f"BEGIN; DELETE FROM public.users WHERE id={lit(owner)} AND auth_user_id={lit(auth)}; DELETE FROM auth.users WHERE id={lit(auth)} AND email='r139-training-completion@example.invalid'; COMMIT;")
        after=once(f"SELECT jsonb_build_object('owners',(SELECT count(*) FROM public.users WHERE id={lit(owner)}),'auth',(SELECT count(*) FROM auth.users WHERE id={lit(auth)}),'completions',(SELECT count(*) FROM private.training_execution_completions WHERE user_id={lit(owner)}),'workouts',(SELECT count(*) FROM public.workout_logs WHERE user_id={lit(owner)}));")[0]
        assert after=={'owners':0,'auth':0,'completions':0,'workouts':0},after
        (output/'FIXTURE-CLOSED.json').write_text(json.dumps(after)+'\n')
print(json.dumps({'status':'PASS','result':str(output/'RESULT.json'),'fixture_removed':created}))
