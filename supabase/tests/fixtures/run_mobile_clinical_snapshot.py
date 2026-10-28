#!/usr/bin/env python3
"""Real snapshot lock/clock proof; inert import, guarded owned UNIX socket only."""
import argparse
import json
import time
from pathlib import Path

from run_mobile_reevaluation_cycle import LocalCycleDatabase
from run_mobile_reevaluation_photo_consent import cleanup_fixture
from run_mobile_health_hold_authority import Sessions, exclusive_json, require, uid


def marker_session(clients, sql):
    child = clients.spawn("BEGIN;\nSELECT jsonb_build_object('pid',pg_backend_pid());\n"
                          + sql + "\nSELECT 'SNAPSHOT_READY';\n")
    lines = clients.until(child, lambda line: line == 'SNAPSHOT_READY')
    pid = json.loads(next(line for line in lines if line.startswith('{"pid"')))['pid']
    return child, pid


def exact_wait(db, child, holder_pid, waiter_pid):
    deadline = time.monotonic() + 6
    while time.monotonic() < deadline:
        state = json.loads(db.query(
            "SELECT json_build_object('waiting',wait_event_type='Lock','blockers',pg_blocking_pids(pid)) "
            f"FROM pg_stat_activity WHERE pid={int(waiter_pid)}"))
        if state['waiting'] and holder_pid in state['blockers']:
            return state
        require(child.poll() is None, 'Waiter exited before the exact authority lock')
        time.sleep(0.025)
    raise TimeoutError('Exact snapshot blocker not observed')


def run(db, evidence):
    evidence = Path(evidence).resolve()
    require(not evidence.exists(), 'Evidence already exists')
    require(db.query("SELECT to_regnamespace('m3b_cycle_test') IS NULL") == 't', 'Fixture already exists')
    fixture = Path(__file__).with_name('mobile_reevaluation_photo_fixture.sql')
    require(db.run_file(fixture, str(evidence) + '.setup.log') == 0, 'Fixture setup failed')
    clients = Sessions(db)
    modes = ['risk_then_context', 'reset_then_context', 'weight_then_context', 'profile_busy',
             'weight_advisory_busy', 'day_advisory_busy', 'close_advisory_busy', 'media_busy',
             'legal_clock_after_wait', 'config_publication']
    owners = [uid(n) for n in range(1100, 1100 + len(modes))]
    cases = []
    try:
        db.query("""CREATE FUNCTION m3b_cycle_test.capture_clinical(owner_id uuid,cycle uuid)
          RETURNS jsonb LANGUAGE plpgsql SET search_path=pg_catalog AS $$
          DECLARE result jsonb; code text; message text;
          BEGIN
           result:=private.capture_mobile_clinical_context_at(owner_id,'REGULAR',cycle,NULL);
           RETURN jsonb_build_object('result',result);
          EXCEPTION WHEN OTHERS THEN
           GET STACKED DIAGNOSTICS code=RETURNED_SQLSTATE,message=MESSAGE_TEXT;
           RETURN jsonb_build_object('error',code,'message',message);
          END $$;""")
        contexts = [json.loads(db.query(f'SELECT m3b_cycle_test.ready_photo({1100+i})'))
                    for i in range(len(modes))]
        for i, mode in enumerate(modes):
            owner, context = owners[i], contexts[i]
            cycle, asset = context['cycle'], context['asset']
            boundary = None
            busy = mode.endswith('_busy')
            if mode == 'risk_then_context':
                holder_sql = f"SELECT public.declare_mobile_health_risk('{owner}','{uid(1200)}',ARRAY['reduced_intake']);"
            elif mode == 'reset_then_context':
                holder_sql = f"SELECT public.reset_user_conversation_atomic('{owner}',true);"
            elif mode == 'weight_then_context':
                holder_sql = f"SELECT public.record_weight_atomic('{owner}',80,'kg',clock_timestamp()-interval '1 hour','snapshot-race-weight');"
            elif mode == 'profile_busy':
                holder_sql = f"SELECT user_id FROM public.user_profiles WHERE user_id='{owner}' FOR UPDATE;"
            elif mode == 'media_busy':
                holder_sql = f"SELECT id FROM public.media_assets WHERE id='{asset}' FOR UPDATE;"
            elif mode == 'legal_clock_after_wait':
                boundary = db.query("SELECT clock_timestamp()+interval '1.2 seconds'")
                db.query("INSERT INTO public.legal_documents(id,document_key,version,locale,body,required_from) "
                         f"VALUES('{uid(1115)}','body_photo_reevaluation_consent','snapshot-race-future','pt-BR',"
                         f"'SYNTHETIC LOCAL SNAPSHOT RACE','{boundary}');")
                holder_sql = 'LOCK TABLE public.legal_documents IN ROW EXCLUSIVE MODE;'
            elif mode == 'config_publication':
                holder_sql = "INSERT INTO public.global_config(key,value) VALUES('calc.m3b_snapshot_race','1'::jsonb);"
            else:
                suffix = ':weight' if mode == 'weight_advisory_busy' else ':daily-close'
                if mode == 'day_advisory_busy':
                    day = db.query(f"SELECT (clock_timestamp() AT TIME ZONE timezone)::date FROM public.users WHERE id='{owner}'")
                    suffix = ':' + day
                holder_sql = f"SELECT pg_advisory_xact_lock(hashtextextended('{owner}{suffix}',0));"
            holder, holder_pid = marker_session(clients, holder_sql)
            waiter = clients.spawn("SELECT jsonb_build_object('pid',pg_backend_pid());\n"
                                   f"SELECT m3b_cycle_test.capture_clinical('{owner}','{cycle}');\n")
            lines = clients.until(waiter, lambda line: line.startswith('{"pid"'))
            waiter_pid = json.loads(lines[-1])['pid']
            blockers = None
            if busy:
                output = clients.finish(waiter)
                result = json.loads(next(line for line in output.splitlines() if line.startswith('{')))
                require(result == {'error': '55P03', 'message': 'mobile_clinical_busy'}, 'Contended legacy writer must fail fast')
                clients.finish(holder, 'COMMIT;\n')
            else:
                blockers = exact_wait(db, waiter, holder_pid, waiter_pid)
                if boundary:
                    deadline = time.monotonic() + 4
                    while db.query(f"SELECT clock_timestamp()>='{boundary}'::timestamptz") != 't':
                        require(time.monotonic() < deadline, 'Legal boundary did not arrive')
                        time.sleep(0.025)
                released_at = db.query("SELECT to_char(clock_timestamp() AT TIME ZONE 'UTC','YYYY-MM-DD\"T\"HH24:MI:SS.US\"Z\"')")
                clients.finish(holder, 'COMMIT;\n')
                output = clients.finish(waiter)
                result = json.loads(next(line for line in output.splitlines() if line.startswith('{')))
                if mode == 'reset_then_context':
                    require(result == {'error': '40001', 'message': 'mobile_clinical_anchor_unavailable'}, 'Reset must invalidate the waiting clinical context')
                else:
                    answer = result['result']
                    require(answer['observed_at'] >= released_at, 'Clinical clock was sampled before authority waits')
                    if mode == 'risk_then_context':
                        require(answer['facts']['safety']['hold_active'] and answer['facts']['safety']['safety_revision'] == '1', 'Waiting context lost a new risk')
                    elif mode == 'weight_then_context':
                        require(answer['facts']['profile']['weight_kg'] == 80 and len(answer['facts']['weight_history']) == 1, 'Waiting context missed a genuine weight')
                    elif mode == 'legal_clock_after_wait':
                        require(answer['facts']['photo_authority']['consent_state']['unavailable_reason'] == 'policy_unavailable', 'Future legal effect was checked before waiting')
                    elif mode == 'config_publication':
                        require(any(c['key'] == 'calc.m3b_snapshot_race' for c in answer['facts']['calculation_config']), 'Snapshot missed a calc set insertion')
            cases.append({'case': mode, 'status': 'PASS', 'holder_backend_pid': holder_pid,
                          'waiter_backend_pid': waiter_pid, 'exact_blockers': blockers,
                          'busy_without_holder_release': busy})
        # Execute actual private entrypoints as client roles, not fixture wrappers.
        for role in ('anon', 'authenticated', 'service_role'):
            require(db.query(f"SELECT NOT has_function_privilege('{role}','private.capture_mobile_clinical_context_at(uuid,text,uuid,timestamptz)','EXECUTE')") == 't', 'Private context callable by a role')
    finally:
        clients.close()
        owner_sql = ','.join(f"'{u}'::uuid" for u in owners)
        db.query(f"SELECT m3b_cycle_test.remove_photos(ARRAY[{owner_sql}]);"
                 "DELETE FROM public.global_config WHERE key='calc.m3b_snapshot_race';")
        cleanup_fixture(db, owners, [uid(501), uid(1115)])
    require(LocalCycleDatabase(db.config_path).guard == db.guard, 'Runtime changed during snapshot races')
    require(db.query("SELECT count(*) FROM public.users") == '0', 'Synthetic owners remain')
    exclusive_json(evidence, {'status': 'PASS', 'cases': cases, 'owned_clients_reaped': True,
                             'fixture_removed': True, 'runtime_guard': db.guard})


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--config', required=True)
    parser.add_argument('--expected-runtime', required=True)
    parser.add_argument('--evidence', required=True)
    args = parser.parse_args()
    db = LocalCycleDatabase(args.config)
    db.args.insert(1, '-q')
    require(db.guard == json.loads(Path(args.expected_runtime).read_text())['guard'], 'Runtime observation differs')
    run(db, args.evidence)


if __name__ == '__main__':
    main()
