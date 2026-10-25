#!/usr/bin/env python3
"""Private processing authority on the existing guarded socket-only database."""
import argparse,json,os,select,subprocess,time
from pathlib import Path
from run_mobile_reevaluation_cycle import LocalCycleDatabase
from run_mobile_reevaluation_photo_consent import cleanup_fixture


def run_races(db,log):
    if db.query('SELECT count(*) FROM public.users')!='0' or db.query("SELECT to_regnamespace('m3b_cycle_test') IS NULL")!='t':
        raise RuntimeError('Processing races require empty owned runtime')
    if db.run_file(Path(__file__).with_name('mobile_reevaluation_photo_fixture.sql'),str(log)+'.setup.log'):
        raise RuntimeError('Processing fixture setup failed')
    children,pending,results=[],{},[]
    owners=[f'b3b01000-0000-4000-8000-{n:012d}' for n in range(841,846)]
    header="SET request.jwt.claims='{\"role\":\"service_role\"}';\n"
    def spawn(sql):
        child = subprocess.Popen(db.args, env=db.env, stdin=subprocess.PIPE,
                                 stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        children.append(child)
        pending[child.pid] = b''
        child.stdin.write(sql.encode())
        child.stdin.flush()
        return child

    def until(child, predicate):
        lines, deadline = [], time.monotonic()+15
        while time.monotonic() < deadline:
            while b'\n' in pending[child.pid]:
                line, pending[child.pid] = pending[child.pid].split(b'\n', 1)
                lines.append(line.decode())
                if predicate(lines[-1]):
                    return lines
            if select.select([child.stdout], [], [], 0.1)[0]:
                chunk = os.read(child.stdout.fileno(), 65536)
                if not chunk:
                    raise RuntimeError('Ticket client exited before marker')
                pending[child.pid] += chunk
        raise TimeoutError('Ticket marker timeout')

    def finish(child, end=''):
        if end:
            child.stdin.write(end.encode())
            child.stdin.flush()
        child.stdin.close()
        child.stdin = None
        out, err = child.communicate(timeout=15)
        return child.returncode, (pending[child.pid]+out).decode(), err.decode()

    try:
        for n,mode in zip(range(841,846),('same_claim','same_authorize','replacement','reset','media_expiry')):
            if mode=='media_expiry':
                sql="""DO $$ BEGIN
                  INSERT INTO public.legal_documents(id,document_key,version,locale,body,required_from)
                    VALUES(m3b_cycle_test.uid(502),'body_photo_reevaluation_consent','processing-race-1','pt-BR',
                      'SYNTHETIC LOCAL ONE SECOND PROCESSING RACE',clock_timestamp()-interval '1second');
                  INSERT INTO private.mobile_reevaluation_photo_policies(document_id,document_key,version,locale,body_hash,idle_timeout_seconds,enabled)
                    SELECT id,document_key,version,locale,body_hash,1,true FROM public.legal_documents WHERE id=m3b_cycle_test.uid(502);
                END $$;
                SELECT m3b_cycle_test.seed(845,'2026-10-01T23:00:00Z');
                SELECT public.start_mobile_reevaluation_cycle(m3b_cycle_test.uid(845),gen_random_uuid());
                SELECT public.accept_mobile_reevaluation_photo_consent(m3b_cycle_test.uid(845),c.cycle_id,1,
                  d.id,d.document_key,d.version,d.locale,d.body_hash,gen_random_uuid())
                  FROM private.mobile_reevaluation_cycles c CROSS JOIN public.legal_documents d
                  WHERE c.user_id=m3b_cycle_test.uid(845) AND d.id=m3b_cycle_test.uid(502);
                SELECT json_build_object('user',user_id,'cycle',cycle_id,'revision','2','acceptance',acceptance_id)
                  FROM private.mobile_reevaluation_photo_consents WHERE user_id=m3b_cycle_test.uid(845);"""
                ctx=json.loads(db.query(header+sql).splitlines()[-1]);photo=json.loads(db.query(header+f"SELECT m3b_cycle_test.allocate('{json.dumps(ctx)}'::jsonb,gen_random_uuid());"))
                aid=photo['asset']['id'];tid=db.query('SELECT gen_random_uuid()')
                db.query(header+f"SELECT public.prepare_mobile_reevaluation_photo_upload('{ctx['user']}','{ctx['cycle']}','{aid}','{tid}');"
                         +f"SELECT public.register_mobile_reevaluation_photo_upload_ticket('{ctx['user']}','{ctx['cycle']}','{aid}','{tid}',clock_timestamp()+interval '2hours');"
                         +f"SELECT public.complete_mobile_reevaluation_photo_upload('{ctx['user']}','{ctx['cycle']}','{aid}',1,1200,'image/jpeg',NULL);")
                ctx.update(asset=aid,revision='3')
            else:ctx=json.loads(db.query(header+f'SELECT m3b_cycle_test.ready_photo({n});'));aid=ctx['asset']
            rid=db.query('SELECT gen_random_uuid()');scope=f"'{ctx['user']}','{ctx['cycle']}','{aid}','{rid}'"
            claim=f'SELECT public.claim_mobile_reevaluation_photo_processing({scope});\n'
            authorize=f'SELECT public.authorize_mobile_reevaluation_photo_provider({scope});\n'
            complete=f"SELECT public.complete_mobile_reevaluation_photo_processing({scope},'{{\"type\":\"body\",\"view\":\"front\",\"bf_percent_estimate\":20}}'::jsonb);\n"
            if mode!='same_claim':db.query(header+claim)
            if mode not in ('same_claim','same_authorize'):db.query(header+authorize)
            if mode=='same_claim':action=claim; waiting=claim
            elif mode=='same_authorize':action=authorize;waiting=authorize
            elif mode=='replacement':action=f"SELECT m3b_cycle_test.allocate('{json.dumps(ctx)}'::jsonb,gen_random_uuid());\n";waiting=complete
            elif mode=='reset':action=f"SELECT public.reset_user_conversation_atomic('{ctx['user']}',true);\n";waiting=complete
            else:action=f"SELECT id FROM public.media_assets WHERE id='{aid}' FOR UPDATE;\n";waiting=complete
            holder=spawn(header+'BEGIN;\nSELECT pg_backend_pid();\n'+action+"SELECT 'TICKET_READY';\n")
            lines=until(holder,lambda line:line=='TICKET_READY');hp=int(next(line for line in lines if line.isdigit()))
            waiter=spawn(header+'SELECT pg_backend_pid();\n'+waiting);wp=int(until(waiter,lambda line:line.isdigit())[-1])
            deadline=time.monotonic()+5
            while time.monotonic()<deadline:
                state=json.loads(db.query("SELECT json_build_object('waiting',wait_event_type='Lock','blockers',pg_blocking_pids(pid)) FROM pg_stat_activity WHERE pid="+str(wp)))
                if state['waiting'] and hp in state['blockers']:break
                if waiter.poll() is not None:raise RuntimeError('Processing waiter terminated before observed blocker')
                time.sleep(.03)
            else:raise TimeoutError('Processing blocker not observed')
            if mode=='media_expiry':
                expiry=db.query(f"SELECT retention_until FROM public.media_assets WHERE id='{aid}'");deadline=time.monotonic()+2
                while db.query(f"SELECT clock_timestamp()>='{expiry}'::timestamptz")!='t':
                    if time.monotonic()>deadline:raise TimeoutError('Synthetic processing expiry missing')
                    time.sleep(.05)
            hc,_,he=finish(holder,'COMMIT;\n');rc,out,err=finish(waiter)
            if hc or he.strip():raise RuntimeError('Processing holder failed:'+he)
            if mode in ('same_claim','same_authorize'):
                if rc or err.strip() or any(line.startswith('{') for line in out.splitlines()):raise AssertionError('Duplicate processing permission was issued')
                if db.query(f"SELECT count(*) FROM private.mobile_reevaluation_photo_processing_attempts WHERE user_id='{ctx['user']}'")!='1':raise AssertionError('Duplicate attempt stored')
            elif rc!=3 or not any(x in err for x in ('mobile_reevaluation_photo_source_changed','mobile_reevaluation_cycle_changed','mobile_reevaluation_photo_consent_changed')):
                raise AssertionError('Stale processing result not refused:'+err)
            if db.query(f"SELECT count(*) FROM private.mobile_reevaluation_photo_processing_attempts WHERE user_id='{ctx['user']}' AND result IS NOT NULL")!='0':raise AssertionError('Unexpected race result')
            results.append({'case':mode,'status':'PASS','blocker_observed':True,'holder_backend_pid':hp,'waiter_backend_pid':wp,'blockers':state['blockers']})
    finally:
        for child in children:
            if child.poll() is None:
                child.terminate()
                try:child.wait(timeout=3)
                except subprocess.TimeoutExpired:child.kill();child.wait(timeout=3)
        ids=','.join("'"+o+"'::uuid" for o in owners)
        db.query('BEGIN;'+f'SELECT m3b_cycle_test.remove_photos(ARRAY[{ids}]);COMMIT;')
        cleanup_fixture(db,owners,['b3b01000-0000-4000-8000-000000000501','b3b01000-0000-4000-8000-000000000502'])
    Path(log).write_text(json.dumps({'status':'PASS','cases':results,'owned_clients_reaped':True},indent=2)+'\n')


def export_candidate_fixture(db,path):
    if db.query('SELECT count(*) FROM public.users')!='0':raise RuntimeError('Snapshot fixture needs empty runtime')
    if db.run_file(Path(__file__).with_name('mobile_reevaluation_photo_fixture.sql'),str(path)+'.setup.log'):raise RuntimeError('Snapshot setup failed')
    header="SET request.jwt.claims='{\"role\":\"service_role\"}';"
    ctx=None
    try:
        ctx=json.loads(db.query(header+'SELECT m3b_cycle_test.ready_photo(850);'))
        for pose,reading in [('front',22),('side',24),('back',26)]:
            if pose=='front':aid=ctx['asset']
            else:
                photo=json.loads(db.query(header+f"SELECT m3b_cycle_test.allocate('{json.dumps(ctx)}'::jsonb,gen_random_uuid(),'{pose}');"));aid=photo['asset']['id'];tid=db.query('SELECT gen_random_uuid()')
                done=json.loads(db.query(header+f"SELECT public.prepare_mobile_reevaluation_photo_upload('{ctx['user']}','{ctx['cycle']}','{aid}','{tid}');"
                  +f"SELECT public.register_mobile_reevaluation_photo_upload_ticket('{ctx['user']}','{ctx['cycle']}','{aid}','{tid}',clock_timestamp()+interval '2hours');"
                  +f"SELECT public.complete_mobile_reevaluation_photo_upload('{ctx['user']}','{ctx['cycle']}','{aid}',1,1200,'image/jpeg',NULL);").splitlines()[-1]);ctx['revision']=done['cycle_revision']
            rid=db.query('SELECT gen_random_uuid()');scope=f"'{ctx['user']}','{ctx['cycle']}','{aid}','{rid}'"
            data=json.dumps({'type':'body','view':pose,'bf_percent_estimate':reading})
            db.query(header+f"SELECT public.claim_mobile_reevaluation_photo_processing({scope});SELECT public.authorize_mobile_reevaluation_photo_provider({scope});SELECT public.complete_mobile_reevaluation_photo_processing({scope},'{data}'::jsonb);")
        snap=json.loads(db.query(header+f"SELECT public.get_mobile_reevaluation_photo_snapshot('{ctx['user']}','{ctx['cycle']}');"));c=snap['consent']
        expected={'userId':ctx['user'],'signupGeneration':snap['signup_generation'],'cycleId':ctx['cycle'],'cycleRevision':snap['cycle_revision'],
                  'currentConsent':{'documentId':c['document_id'],'documentKey':c['document_key'],'version':c['version'],'locale':c['locale'],'bodyHash':c['body_hash']}}
        Path(path).write_text(json.dumps({'provenance':'Owned local PostgreSQL; synthetic provider readings22/24/26; no actual photos/AI','context':expected,'snapshot':snap,'expected_mean':24},indent=2)+'\n')
    finally:
        if ctx:
            db.query(header+f"SELECT m3b_cycle_test.remove_photos(ARRAY['{ctx['user']}'::uuid]);")
            cleanup_fixture(db,[ctx['user']],['b3b01000-0000-4000-8000-000000000501'])


def main():
    p=argparse.ArgumentParser();p.add_argument('--config',required=True);p.add_argument('--log',required=True);p.add_argument('--export-snapshot');a=p.parse_args();log=Path(a.log).resolve()
    if log.exists():raise ValueError('Processing evidence already exists')
    db=LocalCycleDatabase(a.config);db.args.insert(1,'-q')
    rc=db.run_file(Path(__file__).parents[1]/'mobile_reevaluation_photo_processing.sql',str(log)+'.behavior.log')
    if rc:raise RuntimeError('Processing behavior failed; inspect log')
    run_races(db,str(log)+'.races.json')
    if a.export_snapshot:
        export=Path(a.export_snapshot).resolve()
        if export.exists():raise ValueError('Snapshot evidence already exists')
        export_candidate_fixture(db,export)
    result={'status':'PASS','behavior_log':str(log)+'.behavior.log','race_log':str(log)+'.races.json','new_paid_resources':0}
    log.write_text(json.dumps(result,indent=2)+'\n');print(json.dumps(result))


if __name__=='__main__':main()
