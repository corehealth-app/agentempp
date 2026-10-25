#!/usr/bin/env python3
"""Real ticket transactions in the existing guarded, socket-only database."""
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
    if db.query("SELECT count(*) FROM public.users") != '0':
        raise RuntimeError('Ticket races need the empty owned synthetic database')
    if db.query("SELECT to_regnamespace('m3b_cycle_test') IS NULL") != 't':
        raise RuntimeError('Existing ticket fixture must not be reused')
    if db.run_file(Path(__file__).with_name('mobile_reevaluation_photo_fixture.sql'), str(log)+'.setup.log'):
        raise RuntimeError('Ticket fixture setup failed')
    children, pending, results = [], {}, []
    owners = [f'b3b01000-0000-4000-8000-{n:012d}' for n in range(411, 415)]
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
        for n, mode in zip(range(411, 415), ('same_expiry', 'different_expiry', 'rollback', 'reset')):
            ctx = json.loads(db.query(header+f'SELECT m3b_cycle_test.photo_context({n});'))
            photo = json.loads(db.query(header+f"SELECT m3b_cycle_test.allocate('{json.dumps(ctx)}'::jsonb,gen_random_uuid());"))
            aid = photo['asset']['id']
            tid = db.query('SELECT gen_random_uuid()')
            prep = json.loads(db.query(header+"SELECT public.prepare_mobile_reevaluation_photo_upload("
                                      f"'{ctx['user']}','{ctx['cycle']}','{aid}','{tid}');"))
            prepared_at = prep['ticket']['prepared_at']

            def register(extra=''):
                return ('SELECT public.register_mobile_reevaluation_photo_upload_ticket('
                        f"'{ctx['user']}','{ctx['cycle']}','{aid}','{tid}',"
                        f"'{prepared_at}'::timestamptz+interval '2hours'{extra});\n")

            action = (f"SELECT public.reset_user_conversation_atomic('{ctx['user']}',true);\n"
                      if mode == 'reset' else register())
            holder = spawn(header+'BEGIN;\nSELECT pg_backend_pid();\n'+action+"SELECT 'TICKET_READY';\n")
            lines = until(holder, lambda line: line == 'TICKET_READY')
            holder_pid = int(next(line for line in lines if line.isdigit()))
            waiter = spawn(header+'SELECT pg_backend_pid();\n'+register("+interval '1second'" if mode == 'different_expiry' else ''))
            waiter_pid = int(until(waiter, lambda line: line.isdigit())[-1])
            deadline = time.monotonic()+5
            while time.monotonic() < deadline:
                state = json.loads(db.query("SELECT json_build_object('waiting',wait_event_type='Lock',"
                                           f"'blockers',pg_blocking_pids(pid)) FROM pg_stat_activity WHERE pid={waiter_pid}"))
                if state['waiting'] and holder_pid in state['blockers']:
                    break
                if waiter.poll() is not None:
                    raise RuntimeError('Ticket waiter did not block on owner')
                time.sleep(0.05)
            else:
                raise TimeoutError('Ticket owner lock not observed')
            released = db.query('SELECT clock_timestamp()')
            holder_code, _, holder_err = finish(holder, 'ROLLBACK;\n' if mode == 'rollback' else 'COMMIT;\n')
            code, out, err = finish(waiter)
            if holder_code or holder_err.strip():
                raise RuntimeError('Ticket holder failed: '+holder_err)
            if mode == 'different_expiry':
                if code != 3 or 'mobile_reevaluation_photo_upload_ticket_changed' not in err:
                    raise AssertionError('Different expiry was not refused')
            else:
                if code or err.strip():
                    raise RuntimeError('Ticket waiter failed: '+err)
                receipt = json.loads(next(line for line in out.splitlines() if line.startswith('{')))
                if receipt['ticket']['id'] != tid:
                    raise AssertionError('Ticket receipt changed identity')
                if mode in ('rollback', 'reset') and db.query(
                    f"SELECT registered_at>='{released}'::timestamptz FROM private.mobile_reevaluation_photo_upload_tickets WHERE ticket_id='{tid}'") != 't':
                    raise AssertionError('Registration clock captured before lock wait')
                if mode == 'reset':
                    result = subprocess.run(db.args+['-c', header+f"SELECT public.get_mobile_reevaluation_photo_asset('{ctx['user']}','{ctx['cycle']}','{aid}');"],
                                            env=db.env, capture_output=True, text=True, timeout=15)
                    if result.returncode != 1 or 'mobile_reevaluation_cycle_changed' not in result.stderr:
                        raise AssertionError('Reset failed to close live authority')
            if db.query(f"SELECT count(*) FROM private.mobile_reevaluation_photo_upload_tickets WHERE user_id='{ctx['user']}' AND provider_expires_at IS NOT NULL") != '1':
                raise AssertionError('Ticket registration duplicated or disappeared')
            results.append({'case': mode, 'status': 'PASS', 'owner_lock_observed': True,
                            'holder_backend_pid': holder_pid, 'waiter_backend_pid': waiter_pid,
                            'blockers': state['blockers']})
    finally:
        for child in children:
            if child.poll() is None:
                child.terminate()
                try:
                    child.wait(timeout=3)
                except subprocess.TimeoutExpired:
                    child.kill()
                    child.wait(timeout=3)
        ids = ','.join("'"+owner+"'::uuid" for owner in owners)
        db.query('BEGIN;'+f'DELETE FROM private.mobile_reevaluation_photo_upload_tickets WHERE user_id IN({ids});'
                 'DELETE FROM public.media_assets m USING private.mobile_reevaluation_photo_assets l '
                 f'WHERE m.id=l.asset_id AND m.user_id=l.user_id AND l.user_id IN({ids});'
                 f'DELETE FROM private.mobile_reevaluation_photo_assets WHERE user_id IN({ids});COMMIT;')
        cleanup_fixture(db, owners, ['b3b01000-0000-4000-8000-000000000501'])
    Path(log).write_text(json.dumps({'status': 'PASS', 'cases': results, 'owned_clients_reaped': True}, indent=2)+'\n')


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--config', required=True)
    parser.add_argument('--log', required=True)
    args = parser.parse_args()
    log = Path(args.log).resolve()
    if log.exists():
        raise ValueError('Ticket evidence already exists')
    db = LocalCycleDatabase(args.config)
    db.args.insert(1, '-q')
    code = db.run_file(Path(__file__).parents[1]/'mobile_reevaluation_photo_upload_tickets.sql', str(log)+'.behavior.log')
    if code:
        raise RuntimeError('Ticket behavior failed; inspect log')
    run_races(db, str(log)+'.races.json')
    result = {'status': 'PASS', 'exit': 0, 'behavior_log': str(log)+'.behavior.log', 'race_log': str(log)+'.races.json', 'new_paid_resources': 0}
    log.write_text(json.dumps(result, indent=2)+'\n')
    print(json.dumps(result))


if __name__ == '__main__':
    main()
