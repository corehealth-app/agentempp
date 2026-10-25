#!/usr/bin/env python3
"""Recurring disposal only in the existing guarded socket-only synthetic DB."""
import argparse,json,os,select,subprocess,time
from pathlib import Path
from run_mobile_reevaluation_cycle import LocalCycleDatabase
from run_mobile_reevaluation_photo_consent import cleanup_fixture

if not __debug__:
    raise RuntimeError('Disposition runner refuses optimized Python')

HEADER="SET request.jwt.claims='{\"role\":\"service_role\"}';\n"

def run_races(db,log):
    if db.query('SELECT count(*) FROM public.users')!='0' or db.query("SELECT to_regnamespace('m3b_cycle_test') IS NULL")!='t':
        raise RuntimeError('Disposition races need empty owned runtime')
    if db.run_file(Path(__file__).with_name('mobile_reevaluation_photo_fixture.sql'),str(log)+'.setup.log'):
        raise RuntimeError('Disposition fixture setup failed')
    children,pending,results=[],{},[]
    owners=[f'b3b01000-0000-4000-8000-{n:012d}' for n in range(901,905)]
    def query(sql):return db.query(HEADER+sql)
    def spawn(sql):
        child=subprocess.Popen(db.args,env=db.env,stdin=subprocess.PIPE,stdout=subprocess.PIPE,stderr=subprocess.PIPE)
        children.append(child);pending[child.pid]=b'';child.stdin.write(sql.encode());child.stdin.flush();return child
    def until(child,predicate):
        lines=[];deadline=time.monotonic()+15
        while time.monotonic()<deadline:
            while b'\n' in pending[child.pid]:
                line,pending[child.pid]=pending[child.pid].split(b'\n',1);lines.append(line.decode())
                if predicate(lines[-1]):return lines
            if select.select([child.stdout],[],[],.1)[0]:
                chunk=os.read(child.stdout.fileno(),65536)
                if not chunk:raise RuntimeError('Disposition client ended before barrier')
                pending[child.pid]+=chunk
        raise TimeoutError('Disposition barrier timeout')
    def finish(child,end=''):
        if end:child.stdin.write(end.encode());child.stdin.flush()
        child.stdin.close();child.stdin=None;out,err=child.communicate(timeout=15)
        return child.returncode,(pending[child.pid]+out).decode(),err.decode()
    try:
        for n,mode in zip(range(901,905),('discard_upload','late_ticket_ack','duplicate_ack','media_idle_boundary')):
            if mode=='media_idle_boundary':
                ctx=json.loads(query("""INSERT INTO public.legal_documents(id,document_key,version,locale,body,required_from)
                 VALUES(m3b_cycle_test.uid(502),'body_photo_reevaluation_consent','disposition-race-1','pt-BR','SYNTHETIC LOCAL ONE SECOND DISPOSITION RACE',clock_timestamp()-interval '1second');
                 INSERT INTO private.mobile_reevaluation_photo_policies(document_id,document_key,version,locale,body_hash,idle_timeout_seconds,enabled)
                  SELECT id,document_key,version,locale,body_hash,1,true FROM public.legal_documents WHERE id=m3b_cycle_test.uid(502);
                 SELECT m3b_cycle_test.seed(904,'2026-10-01T23:00:00Z');
                 SELECT public.start_mobile_reevaluation_cycle(m3b_cycle_test.uid(904),gen_random_uuid());
                 SELECT public.accept_mobile_reevaluation_photo_consent(m3b_cycle_test.uid(904),c.cycle_id,1,d.id,d.document_key,d.version,d.locale,d.body_hash,gen_random_uuid())
                  FROM private.mobile_reevaluation_cycles c CROSS JOIN public.legal_documents d WHERE c.user_id=m3b_cycle_test.uid(904) AND d.id=m3b_cycle_test.uid(502);
                 SELECT json_build_object('user',user_id,'cycle',cycle_id,'revision','2','acceptance',acceptance_id) FROM private.mobile_reevaluation_photo_consents WHERE user_id=m3b_cycle_test.uid(904);""").splitlines()[-1])
            else:ctx=json.loads(query(f'SELECT m3b_cycle_test.photo_context({n});'))
            photo=json.loads(query(f"SELECT m3b_cycle_test.allocate('{json.dumps(ctx)}'::jsonb,gen_random_uuid());"));aid=photo['asset']['id'];revision=photo['cycle_revision']
            user,cycle,acc=ctx['user'],ctx['cycle'],ctx['acceptance'];scope=f"'{user}','{cycle}','{acc}'"
            discard=f'SELECT public.discard_mobile_reevaluation_photos({scope},{revision});\n'
            if mode in ('discard_upload','late_ticket_ack'):
                tid=db.query('SELECT gen_random_uuid()')
                query(f"SELECT public.prepare_mobile_reevaluation_photo_upload('{user}','{cycle}','{aid}','{tid}');")
                if mode=='discard_upload':query(f"SELECT public.register_mobile_reevaluation_photo_upload_ticket('{user}','{cycle}','{aid}','{tid}',clock_timestamp()+interval '2hours');")
            if mode in ('late_ticket_ack','duplicate_ack'):
                query(discard);prep=json.loads(query(f'SELECT public.prepare_mobile_reevaluation_photo_disposition({scope});'));h=prep['disposition']
                ack=f"SELECT public.commit_mobile_reevaluation_photo_disposition_page('{user}','{h['id']}',{h['sweep_no']},{h['capability_revision']},NULL,ARRAY['{aid}'::uuid]);\n"
                action=f"SELECT public.register_mobile_reevaluation_photo_upload_ticket('{user}','{cycle}','{aid}','{tid}',clock_timestamp()+interval '2hours');\n" if mode=='late_ticket_ack' else ack
                waiting=ack
            elif mode=='discard_upload':
                action=discard;waiting=f"SELECT public.complete_mobile_reevaluation_photo_upload('{user}','{cycle}','{aid}',1,1200,'image/jpeg',NULL);\n"
            else:action=f"SELECT id FROM public.media_assets WHERE id='{aid}' FOR UPDATE;\n";waiting=discard
            holder=spawn(HEADER+'BEGIN;\nSELECT pg_backend_pid();\n'+action+"SELECT 'DISPOSITION_READY';\n")
            lines=until(holder,lambda line:line=='DISPOSITION_READY');hp=int(next(line for line in lines if line.isdigit()))
            waiter=spawn(HEADER+'SELECT pg_backend_pid();\n'+waiting);wp=int(until(waiter,lambda line:line.isdigit())[-1]);deadline=time.monotonic()+5
            while time.monotonic()<deadline:
                state=json.loads(db.query("SELECT json_build_object('waiting',wait_event_type='Lock','blockers',pg_blocking_pids(pid)) FROM pg_stat_activity WHERE pid="+str(wp)))
                if state['waiting'] and hp in state['blockers']:break
                if waiter.poll() is not None:raise RuntimeError('Disposition waiter ended before exact blocker')
                time.sleep(.03)
            else:raise TimeoutError('Exact disposition blocker not observed')
            if mode=='media_idle_boundary':
                expiry=db.query(f"SELECT retention_until FROM public.media_assets WHERE id='{aid}'");deadline=time.monotonic()+2
                while db.query(f"SELECT clock_timestamp()>='{expiry}'::timestamptz")!='t':
                    if time.monotonic()>deadline:raise TimeoutError('Synthetic idle deadline missing')
                    time.sleep(.03)
            hc,_,he=finish(holder,'COMMIT;\n');rc,out,err=finish(waiter)
            if hc or he.strip():raise RuntimeError('Disposition holder failed:'+he)
            if mode=='media_idle_boundary':
                if rc or err.strip():raise AssertionError('Discard after media wait failed:'+err)
                if db.query(f"SELECT sealed_at>='{expiry}'::timestamptz FROM private.mobile_reevaluation_photo_dispositions WHERE acceptance_id='{acc}'")!='t':raise AssertionError('Sealed clock was not recaptured after media wait')
            else:
                expected='mobile_reevaluation_photo_consent_changed' if mode=='discard_upload' else 'mobile_reevaluation_cleanup_changed'
                if rc!=3 or expected not in err:raise AssertionError('Stale callback/page was not refused:'+err)
            if mode=='discard_upload' and db.query(f"SELECT selected_asset_id IS NULL FROM private.mobile_reevaluation_photo_sources WHERE user_id='{user}'")!='t':raise AssertionError('Discarded upload selected source')
            if mode=='late_ticket_ack' and db.query(f"SELECT capability_revision=2 AND sweep_state='idle' FROM private.mobile_reevaluation_photo_dispositions WHERE acceptance_id='{acc}'")!='t':raise AssertionError('Late ticket proof not reopened')
            if mode=='duplicate_ack' and db.query(f"SELECT sweep_no=1 AND sweep_state='settled' FROM private.mobile_reevaluation_photo_dispositions WHERE acceptance_id='{acc}'")!='t':raise AssertionError('Duplicate ACK changed sweep')
            results.append({'case':mode,'status':'PASS','exact_blocker_observed':True,'holder_backend_pid':hp,'waiter_backend_pid':wp,'blockers':state['blockers']})
    finally:
        for child in children:
            if child.poll() is None:
                child.terminate()
                try:child.wait(timeout=3)
                except subprocess.TimeoutExpired:child.kill();child.wait(timeout=3)
        ids=','.join("'"+x+"'::uuid" for x in owners)
        db.query('BEGIN;'+f'SELECT m3b_cycle_test.remove_photos(ARRAY[{ids}]);COMMIT;')
        cleanup_fixture(db,owners,['b3b01000-0000-4000-8000-000000000501','b3b01000-0000-4000-8000-000000000502'])
    Path(log).write_text(json.dumps({'status':'PASS','cases':results,'owned_clients_reaped':True},indent=2)+'\n')

def main():
    parser=argparse.ArgumentParser();parser.add_argument('--config',required=True);parser.add_argument('--log',required=True);args=parser.parse_args();log=Path(args.log).resolve()
    if log.exists():raise ValueError('Disposition evidence already exists')
    db=LocalCycleDatabase(args.config);db.args.insert(1,'-q')
    if db.run_file(Path(__file__).parents[1]/'mobile_reevaluation_photo_disposition.sql',str(log)+'.behavior.log'):raise RuntimeError('Disposition SQL behavior failed')
    run_races(db,str(log)+'.races.json')
    result={'status':'PASS','behavior_log':str(log)+'.behavior.log','races':str(log)+'.races.json','new_paid_resources':0};log.write_text(json.dumps(result,indent=2)+'\n');print(json.dumps(result))
if __name__=='__main__':main()
