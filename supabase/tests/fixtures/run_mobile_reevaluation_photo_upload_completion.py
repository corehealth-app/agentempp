#!/usr/bin/env python3
"""Completion races against real owner/media waits in the guarded local database."""
import argparse
import json
import os
import select
import subprocess
import time
from pathlib import Path
from run_mobile_reevaluation_cycle import LocalCycleDatabase
from run_mobile_reevaluation_photo_consent import cleanup_fixture


def run_races(db, log):
    if db.query("SELECT count(*) FROM public.users") != '0' or db.query("SELECT to_regnamespace('m3b_cycle_test') IS NULL") != 't':
        raise RuntimeError('Completion races need empty owned database')
    if db.run_file(Path(__file__).with_name('mobile_reevaluation_photo_fixture.sql'), str(log)+'.setup.log'):
        raise RuntimeError('Completion fixture setup failed')
    children, pending, results = [], {}, []
    owners = [f'b3b01000-0000-4000-8000-{n:012d}' for n in range(631,635)]
    header = "SET request.jwt.claims='{\"role\":\"service_role\"}';\n"
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
        for n, mode in zip(range(631,635), ('same_completion','newer_allocation','reset','media_expiry')):
            if mode=='media_expiry':
                # A dedicated one-second synthetic policy makes the real clock
                # cross the boundary under a held media lock, without backdate.
                sql="""DO $$ BEGIN
                  INSERT INTO public.legal_documents(id,document_key,version,locale,body,required_from)
                    VALUES(m3b_cycle_test.uid(502),'body_photo_reevaluation_consent','completion-race-1','pt-BR',
                      'SYNTHETIC LOCAL ONE SECOND LOCK RACE',clock_timestamp()-interval '1second');
                  INSERT INTO private.mobile_reevaluation_photo_policies(document_id,document_key,version,locale,body_hash,idle_timeout_seconds,enabled)
                    SELECT id,document_key,version,locale,body_hash,1,true FROM public.legal_documents WHERE id=m3b_cycle_test.uid(502);
                END $$;
                SELECT m3b_cycle_test.seed(634,'2026-10-01T23:00:00Z');
                SELECT public.start_mobile_reevaluation_cycle(m3b_cycle_test.uid(634),gen_random_uuid());
                SELECT public.accept_mobile_reevaluation_photo_consent(m3b_cycle_test.uid(634),c.cycle_id,1,
                  d.id,d.document_key,d.version,d.locale,d.body_hash,gen_random_uuid())
                  FROM private.mobile_reevaluation_cycles c CROSS JOIN public.legal_documents d
                  WHERE c.user_id=m3b_cycle_test.uid(634) AND d.id=m3b_cycle_test.uid(502);
                SELECT json_build_object('user',user_id,'cycle',cycle_id,'revision','2','acceptance',acceptance_id)
                  FROM private.mobile_reevaluation_photo_consents WHERE user_id=m3b_cycle_test.uid(634);"""
                ctx=json.loads(db.query(header+sql).splitlines()[-1])
            else:
                ctx=json.loads(db.query(header+f'SELECT m3b_cycle_test.photo_context({n});'))
            photo=json.loads(db.query(header+f"SELECT m3b_cycle_test.allocate('{json.dumps(ctx)}'::jsonb,gen_random_uuid());"))
            aid=photo['asset']['id']; tid=db.query('SELECT gen_random_uuid()')
            db.query(header+f"SELECT public.prepare_mobile_reevaluation_photo_upload('{ctx['user']}','{ctx['cycle']}','{aid}','{tid}');"
                     +f"SELECT public.register_mobile_reevaluation_photo_upload_ticket('{ctx['user']}','{ctx['cycle']}','{aid}','{tid}',clock_timestamp()+interval '2hours');")
            complete=f"SELECT public.complete_mobile_reevaluation_photo_upload('{ctx['user']}','{ctx['cycle']}','{aid}',1,1200,'image/jpeg',NULL);\n"
            if mode=='same_completion': action=complete
            elif mode=='newer_allocation': action=f"SELECT m3b_cycle_test.allocate('{json.dumps(ctx)}'::jsonb,gen_random_uuid());\n"
            elif mode=='reset': action=f"SELECT public.reset_user_conversation_atomic('{ctx['user']}',true);\n"
            else: action=f"SELECT id FROM public.media_assets WHERE id='{aid}' FOR UPDATE;\n"
            holder=spawn(header+'BEGIN;\nSELECT pg_backend_pid();\n'+action+"SELECT 'TICKET_READY';\n")
            lines=until(holder,lambda line:line=='TICKET_READY'); holder_pid=int(next(line for line in lines if line.isdigit()))
            waiter=spawn(header+'SELECT pg_backend_pid();\n'+complete)
            waiter_pid=int(until(waiter,lambda line:line.isdigit())[-1])
            deadline=time.monotonic()+5
            while time.monotonic()<deadline:
                state=json.loads(db.query("SELECT json_build_object('waiting',wait_event_type='Lock','blockers',pg_blocking_pids(pid)) FROM pg_stat_activity WHERE pid="+str(waiter_pid)))
                if state['waiting'] and holder_pid in state['blockers']:break
                if waiter.poll() is not None:raise RuntimeError('Completion waiter failed before observable lock')
                time.sleep(.03)
            else:raise TimeoutError('Completion blocker not observed')
            if mode=='media_expiry':
                expires=db.query(f"SELECT retention_until FROM public.media_assets WHERE id='{aid}'")
                # Bounded <2s real clock wait. No table writes or fake clock.
                deadline=time.monotonic()+2
                while db.query(f"SELECT clock_timestamp()>='{expires}'::timestamptz")!='t':
                    if time.monotonic()>deadline:raise TimeoutError('Synthetic expiry did not arrive')
                    time.sleep(.05)
            hc,_,he=finish(holder,'COMMIT;\n'); code,out,err=finish(waiter)
            if hc or he.strip():raise RuntimeError('Holder failed:'+he)
            if code!=3 or ('mobile_reevaluation_photo_source_changed' not in err and 'mobile_reevaluation_cycle_changed' not in err and 'mobile_reevaluation_photo_consent_changed' not in err):
                raise AssertionError('Delayed completion was not refused: '+err)
            expected=1 if mode=='same_completion' else 0
            if db.query(f"SELECT count(*) FROM private.mobile_reevaluation_photo_sources WHERE user_id='{ctx['user']}' AND selected_asset_id IS NOT NULL")!=str(expected):
                raise AssertionError('Unexpected selected source after race')
            if mode=='same_completion':
                replay=db.query(header+complete.replace(',1,1200',',2,1200'))
                if json.loads(replay)['source_revision']!='2':raise AssertionError('Replay changed source revision')
            results.append({'case':mode,'status':'PASS','blocker_observed':True,'holder_backend_pid':holder_pid,'waiter_backend_pid':waiter_pid,'blockers':state['blockers']})
    finally:
        for child in children:
            if child.poll() is None:
                child.terminate()
                try:child.wait(timeout=3)
                except subprocess.TimeoutExpired:child.kill();child.wait(timeout=3)
        ids=','.join("'"+owner+"'::uuid" for owner in owners)
        db.query('BEGIN;'+f'DELETE FROM private.mobile_reevaluation_photo_sources WHERE user_id IN({ids});'
                 +f'DELETE FROM private.mobile_reevaluation_photo_upload_tickets WHERE user_id IN({ids});'
                 +'DELETE FROM public.media_assets m USING private.mobile_reevaluation_photo_assets l '
                 +f'WHERE m.id=l.asset_id AND m.user_id=l.user_id AND l.user_id IN({ids});'
                 +f'DELETE FROM private.mobile_reevaluation_photo_assets WHERE user_id IN({ids});COMMIT;')
        cleanup_fixture(db,owners,['b3b01000-0000-4000-8000-000000000501','b3b01000-0000-4000-8000-000000000502'])
    Path(log).write_text(json.dumps({'status':'PASS','cases':results,'owned_clients_reaped':True},indent=2)+'\n')


def main():
    parser=argparse.ArgumentParser();parser.add_argument('--config',required=True);parser.add_argument('--log',required=True);args=parser.parse_args()
    log=Path(args.log).resolve()
    if log.exists():raise ValueError('Completion evidence already exists')
    db=LocalCycleDatabase(args.config);db.args.insert(1,'-q')
    code=db.run_file(Path(__file__).parents[1]/'mobile_reevaluation_photo_upload_completion.sql',str(log)+'.behavior.log')
    if code:raise RuntimeError('Completion behavior failed; inspect log')
    run_races(db,str(log)+'.races.json')
    result={'status':'PASS','behavior_log':str(log)+'.behavior.log','race_log':str(log)+'.races.json','new_paid_resources':0}
    log.write_text(json.dumps(result,indent=2)+'\n');print(json.dumps(result))


if __name__=='__main__':main()
