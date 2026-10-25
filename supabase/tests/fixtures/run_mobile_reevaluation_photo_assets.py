#!/usr/bin/env python3
"""Exercise new asset allocation in real local transactions and owner races."""
import argparse
import json
import os
import select
import subprocess
import time
from pathlib import Path

from run_mobile_reevaluation_cycle import LocalCycleDatabase
from run_mobile_reevaluation_photo_consent import cleanup_fixture


def run_races(database, log):
    if database.query("SELECT count(*) FROM public.users") != "0":
        raise RuntimeError("Asset races require the empty owned local test database")
    if database.query("SELECT to_regnamespace('m3b_cycle_test') IS NULL") != "t":
        raise RuntimeError("Asset race fixture already exists")
    fixture = Path(__file__).with_name('mobile_reevaluation_photo_fixture.sql')
    if database.run_file(fixture, str(log) + '.setup.log'):
        raise RuntimeError("Asset fixture setup failed")
    owners = [f'b3b01000-0000-4000-8000-{n:012d}' for n in range(211, 215)]
    key_a = 'b3b01000-1000-4000-8000-000000000211'
    key_b = 'b3b01000-1000-4000-8000-000000000212'
    children = []
    pending = {}
    results = []

    def spawn(sql):
        child = subprocess.Popen(database.args, env=database.env, stdin=subprocess.PIPE,
                                 stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        children.append(child)
        pending[child.pid] = b''
        child.stdin.write(sql.encode())
        child.stdin.flush()
        return child

    def until(child, predicate):
        lines = []
        deadline = time.monotonic() + 15
        while time.monotonic() < deadline:
            while b'\n' in pending[child.pid]:
                line, pending[child.pid] = pending[child.pid].split(b'\n', 1)
                lines.append(line.decode())
                if predicate(lines[-1]):
                    return lines
            if select.select([child.stdout], [], [], 0.1)[0]:
                chunk = os.read(child.stdout.fileno(), 65536)
                if not chunk:
                    raise RuntimeError('Asset client exited before marker')
                pending[child.pid] += chunk
        raise TimeoutError('Asset client marker timeout')

    def finish(child, end=''):
        if end:
            child.stdin.write(end.encode())
            child.stdin.flush()
        child.stdin.close()
        child.stdin = None
        out, err = child.communicate(timeout=15)
        return child.returncode, (pending[child.pid] + out).decode(), err.decode()

    def allocation(ctx, key):
        return ("SELECT public.create_mobile_reevaluation_photo_asset("
                f"'{ctx['user']}','{ctx['cycle']}',2,'{ctx['acceptance']}',"
                f"'front','image/jpeg',1200,'{key}');\n")

    def asset_result(lines):
        for line in lines:
            if line.startswith('{'):
                value = json.loads(line)
                if value.get('version') == 1 and isinstance(value.get('asset'), dict):
                    return value
        raise RuntimeError('Missing versioned asset result')

    try:
        contexts = [json.loads(line) for line in database.query(
            'SELECT m3b_cycle_test.photo_context(n) FROM generate_series(211,214) n').splitlines()]
        for ctx, mode in zip(contexts, ('same_key', 'different_keys', 'rollback', 'reset')):
            action = (f"SELECT public.reset_user_conversation_atomic('{ctx['user']}',true);\n"
                      if mode == 'reset' else allocation(ctx, key_a))
            header = "SET request.jwt.claims='{\"role\":\"service_role\"}';\n"
            holder = spawn(header + "BEGIN;\nSELECT json_build_object('holder_pid',pg_backend_pid());\n"
                           + action + "SELECT 'ASSET_READY';\n")
            holder_lines = until(holder, lambda line: line == 'ASSET_READY')
            holder_pid = json.loads(next(line for line in holder_lines if line.startswith('{"holder_pid"')))['holder_pid']
            first_asset = None if mode == 'reset' else asset_result(holder_lines)['asset']['id']
            waiter = spawn(header + "SELECT json_build_object('waiter_pid',pg_backend_pid());\n"
                           + allocation(ctx, key_b if mode == 'different_keys' else key_a))
            waiter_lines = until(waiter, lambda line: line.startswith('{"waiter_pid"'))
            waiter_pid = json.loads(waiter_lines[-1])['waiter_pid']
            deadline = time.monotonic() + 5
            while time.monotonic() < deadline:
                state = json.loads(database.query(
                    "SELECT json_build_object('waiting',wait_event_type='Lock','blockers',pg_blocking_pids(pid)) "
                    f'FROM pg_stat_activity WHERE pid={int(waiter_pid)}'))
                if state['waiting'] and holder_pid in state['blockers']:
                    break
                if waiter.poll() is not None:
                    raise RuntimeError('Asset waiter did not wait on owner')
                time.sleep(0.05)
            else:
                raise TimeoutError('Asset owner blocker was not observed')
            released_at = database.query("SELECT clock_timestamp() AT TIME ZONE 'UTC'")
            holder_exit, _, holder_err = finish(holder, 'ROLLBACK;\n' if mode == 'rollback' else 'COMMIT;\n')
            waiter_exit, waiter_out, waiter_err = finish(waiter)
            if holder_exit or holder_err.strip():
                raise RuntimeError('Asset holder failed: ' + holder_err)
            if mode == 'reset':
                if waiter_exit != 3 or 'mobile_reevaluation_cycle_changed' not in waiter_err:
                    raise AssertionError('Reset did not reject waiting allocation')
                wanted = '0'
            else:
                if waiter_exit or waiter_err.strip():
                    raise RuntimeError('Asset waiter failed: ' + waiter_err)
                second_asset = asset_result(waiter_out.splitlines())['asset']['id']
                same = first_asset == second_asset
                if same != (mode == 'same_key'):
                    raise AssertionError('Asset identity does not match idempotency/rollback outcome')
                if mode == 'rollback' and database.query(
                    f"SELECT created_at AT TIME ZONE 'UTC'>='{released_at}'::timestamp "
                    f"FROM private.mobile_reevaluation_photo_assets WHERE asset_id='{second_asset}'") != 't':
                    raise AssertionError('Asset clock was captured before waiting')
                wanted = '2' if mode == 'different_keys' else '1'
                if database.query(f"SELECT revision FROM private.mobile_reevaluation_cycles WHERE cycle_id='{ctx['cycle']}'") != '2':
                    raise AssertionError('Pending allocation changed clinical revision')
            for table in ('public.media_assets', 'private.mobile_reevaluation_photo_assets'):
                if database.query(f"SELECT count(*) FROM {table} WHERE user_id='{ctx['user']}'") != wanted:
                    raise AssertionError('Asset/ledger count differs from transaction outcome')
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
        ids = ','.join("'" + owner + "'::uuid" for owner in owners)
        # The asset->ledger FK is immediate; the reverse is deferred. Remove
        # only membership-proven synthetic media, then its ledger, in one txn.
        database.query('BEGIN;'
                       'DELETE FROM public.media_assets m USING private.mobile_reevaluation_photo_assets l '
                       f'WHERE m.id=l.asset_id AND m.user_id=l.user_id AND l.user_id IN({ids});'
                       f'DELETE FROM private.mobile_reevaluation_photo_assets WHERE user_id IN({ids});COMMIT;')
        cleanup_fixture(database, owners, ['b3b01000-0000-4000-8000-000000000501'])
    Path(log).write_text(json.dumps({'status': 'PASS', 'cases': results, 'owned_clients_reaped': True}, indent=2) + '\n')


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--config', required=True)
    parser.add_argument('--log', required=True)
    args = parser.parse_args()
    result_path = Path(args.log).resolve()
    if result_path.exists():
        raise ValueError('Asset evidence path already exists')
    database = LocalCycleDatabase(args.config)
    database.args.insert(1, '-q')
    behavior_log = str(result_path) + '.behavior.log'
    code = database.run_file(Path(__file__).parents[1] / 'mobile_reevaluation_photo_assets.sql', behavior_log)
    if code == 0:
        run_races(database, str(result_path) + '.races.json')
    result = {'exit': code, 'behavior_log': behavior_log, 'race_log': str(result_path) + '.races.json',
              'unix_socket_only': True, 'new_paid_resources': 0}
    result_path.write_text(json.dumps(result, indent=2) + '\n')
    print(json.dumps(result))
    return code


if __name__ == '__main__':
    raise SystemExit(main())
