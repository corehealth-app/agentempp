#!/usr/bin/env python3
"""Real concurrent weight/receipt/reset proof in the guarded owned socket only."""
import argparse
import json
import time
from pathlib import Path

from run_mobile_reevaluation_cycle import LocalCycleDatabase
from run_mobile_health_hold_authority import Sessions, exclusive_json, require, uid


def record(owner, instant, key='race-weight-key', value=80):
    return f"SELECT m3b_cycle_test.capture_weight('{owner}',{value},'{instant}','{key}');"


def wait_owner(db, clients, holder, waiter):
    deadline = time.monotonic() + 6
    while time.monotonic() < deadline:
        result = json.loads(db.query(
            "SELECT json_build_object('waiting',wait_event_type='Lock','blockers',pg_blocking_pids(pid)) "
            f"FROM pg_stat_activity WHERE pid={waiter}"))
        if result['waiting'] and holder in result['blockers']:
            return result
        time.sleep(0.025)
    raise TimeoutError('Actual weight owner blocker not observed')


def start(clients, sql):
    child = clients.spawn("BEGIN;\nSELECT jsonb_build_object('pid',pg_backend_pid());\n" + sql + "\nSELECT 'WEIGHT_READY';\n")
    lines = clients.until(child, lambda line: line == 'WEIGHT_READY')
    pid = json.loads(next(line for line in lines if line.startswith('{"pid"')))['pid']
    return child, pid, lines


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--config', required=True)
    parser.add_argument('--log', required=True)
    args = parser.parse_args()
    db = LocalCycleDatabase(args.config)
    db.args.insert(1, '-q')
    evidence = Path(args.log).resolve()
    require(not evidence.exists(), 'Evidence already exists')
    require(db.query("SELECT to_regnamespace('m3b_cycle_test') IS NULL") == 't', 'Fixture exists')
    fixture = Path(__file__).with_name('mobile_reevaluation_cycle_fixture.sql')
    require(db.run_file(fixture, str(evidence) + '.setup.log') == 0, 'Fixture setup failed')
    clients = Sessions(db)
    cases = []
    owners = [uid(n) for n in range(920, 930)]
    try:
        db.query("""CREATE FUNCTION m3b_cycle_test.capture_weight(owner_id uuid,weight numeric,instant timestamptz,key text)
          RETURNS jsonb LANGUAGE plpgsql SET search_path=pg_catalog AS $$
          DECLARE answer jsonb; code text; message text;
          BEGIN
            answer:=public.record_weight_atomic(owner_id,weight,'kg',instant,key);
            RETURN jsonb_build_object('result',answer);
          EXCEPTION WHEN OTHERS THEN
            GET STACKED DIAGNOSTICS code=RETURNED_SQLSTATE,message=MESSAGE_TEXT;
            RETURN jsonb_build_object('error',code,'message',message);
          END $$;
          SELECT m3b_cycle_test.seed(n,NULL) FROM generate_series(920,929) n;""")
        for index, mode in enumerate(['same_key', 'different_keys', 'rollback', 'weight_then_reset',
                                      'reset_then_replay', 'inactive_after_wait', 'clock_after_wait',
                                      'profile_busy', 'advisory_busy', 'delete_then_weight']):
            owner = owners[index]
            instant = db.query("SELECT date_trunc('second',clock_timestamp()-interval '1 hour')::text")
            original = None
            if mode == 'reset_then_replay':
                original = json.loads(db.query(record(owner, instant)))['result']
                holder_sql = f"SELECT public.reset_user_conversation_atomic('{owner}',true);"
            elif mode == 'inactive_after_wait':
                holder_sql = f"UPDATE public.users SET status='blocked' WHERE id='{owner}';"
            elif mode == 'clock_after_wait':
                instant = db.query("SELECT (clock_timestamp()-interval '7 days'+interval '1 second')::text")
                holder_sql = f"SELECT id FROM public.users WHERE id='{owner}' FOR UPDATE;"
            elif mode == 'profile_busy':
                holder_sql = f"SELECT user_id FROM public.user_profiles WHERE user_id='{owner}' FOR UPDATE;"
            elif mode == 'advisory_busy':
                holder_sql = f"SELECT pg_advisory_xact_lock(hashtextextended('{owner}:weight',0));"
            elif mode == 'delete_then_weight':
                holder_sql = f"DELETE FROM public.users WHERE id='{owner}';"
            else:
                holder_sql = record(owner, instant)
            holder, holder_pid, holder_lines = start(clients, holder_sql)
            waiter_sql = (f"SELECT public.reset_user_conversation_atomic('{owner}',true);"
                          if mode == 'weight_then_reset' else record(owner, instant,
                            'race-weight-other' if mode == 'different_keys' else 'race-weight-key'))
            waiter = clients.spawn("SELECT jsonb_build_object('pid',pg_backend_pid());\n" + waiter_sql + '\n')
            waiter_lines = clients.until(waiter, lambda line: line.startswith('{"pid"'))
            waiter_pid = json.loads(waiter_lines[-1])['pid']
            if mode in ('profile_busy', 'advisory_busy'):
                output = clients.finish(waiter)
                result = json.loads(next(line for line in output.splitlines() if line.startswith('{')))
                require(result == {'error': '55P03', 'message': 'mobile_weight_busy'}, 'Contention must fail fast with a named busy result')
                clients.finish(holder, 'COMMIT;\n')
                cases.append({'case': mode, 'status': 'PASS', 'failed_without_waiting_for_holder_release': True})
            else:
                blocker = wait_owner(db, clients, holder_pid, waiter_pid)
                if mode == 'clock_after_wait':
                    deadline = time.monotonic() + 3
                    while db.query(f"SELECT clock_timestamp()>'{instant}'::timestamptz+interval '7 days'") != 't':
                        require(time.monotonic() < deadline, 'Window boundary did not arrive')
                        time.sleep(0.025)
                clients.finish(holder, ('ROLLBACK' if mode == 'rollback' else 'COMMIT') + ';\n')
                output = clients.finish(waiter)
                result = json.loads(next(line for line in output.splitlines() if line.startswith('{')))
                if mode in ('inactive_after_wait', 'delete_then_weight'):
                    require(result == {'error': '22023', 'message': 'invalid weight payload'}, 'Active person must be checked after owner wait')
                elif mode == 'clock_after_wait':
                    require(result == {'error': '22023', 'message': 'mobile_weight_measured_at_out_of_range'}, 'Offline window must use the fresh post-lock clock')
                elif mode == 'weight_then_reset':
                    require(db.query(f"SELECT weight_kg IS NULL FROM public.user_profiles WHERE user_id='{owner}'") == 't', 'Reset must win after recorded weight')
                elif mode == 'reset_then_replay':
                    require(result['result'] == original, 'Replay must acknowledge its original result')
                    require(db.query(f"SELECT weight_kg IS NULL FROM public.user_profiles WHERE user_id='{owner}'") == 't', 'Replay must not resurrect reset weight')
                else:
                    first_result = json.loads(next(line for line in holder_lines if line.startswith('{"result"')))['result']
                    require('result' in result, 'Waiting writer failed')
                    if mode == 'different_keys':
                        require(result['result']['reason'] == 'same_measurement', 'New key must acknowledge the same physical measurement')
                    elif mode == 'same_key':
                        require(result['result'] == first_result, 'Concurrent same-key replay changed result')
                    else:
                        require(result['result']['applied'], 'Rolled-back receipt must not survive')
                cases.append({'case': mode, 'status': 'PASS', 'owner_wait_observed': True,
                              'holder_backend_pid': holder_pid, 'waiter_backend_pid': waiter_pid,
                              'observed_blockers': blocker['blockers']})
            counts = json.loads(db.query("SELECT json_build_object('measurements',(SELECT count(*) FROM private.mobile_weight_measurements "
                f"WHERE user_id='{owner}'),'receipts',(SELECT count(*) FROM private.mobile_weight_request_receipts WHERE user_id='{owner}'))"))
            expected = 0 if mode in ('inactive_after_wait', 'clock_after_wait', 'profile_busy', 'advisory_busy', 'delete_then_weight') else 1
            require(counts['measurements'] == expected and counts['receipts'] == (2 if mode == 'different_keys' else expected), 'Physical/request counts incorrect after race')
    finally:
        clients.close()
        ids = ','.join("'" + owner + "'::uuid" for owner in owners)
        db.query(f"DELETE FROM public.users WHERE id IN({ids}); DROP SCHEMA m3b_cycle_test CASCADE;")
    exclusive_json(evidence, {'status': 'PASS', 'guard': db.guard, 'cases': cases, 'owned_clients_reaped': True})
    print(f'PASS {len(cases)} real weight races')


if __name__ == '__main__':
    main()
