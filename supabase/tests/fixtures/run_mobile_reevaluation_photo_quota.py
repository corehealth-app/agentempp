#!/usr/bin/env python3
"""Real quota behavior and exact-owner races; owned local UNIX socket only."""
import argparse
import json
import subprocess
import time
from pathlib import Path

from run_mobile_reevaluation_cycle import LocalCycleDatabase
from run_mobile_reevaluation_photo_consent import cleanup_fixture
from run_mobile_health_hold_authority import Sessions, require, exclusive_json, uid


def allocate(ctx, key):
    return ("SELECT public.create_mobile_reevaluation_photo_asset("
            f"'{ctx['user']}','{ctx['cycle']}',{ctx['revision']},'{ctx['acceptance']}',"
            f"'front','image/jpeg',1200,'{key}');\n")


def wire(lines):
    return next(json.loads(line) for line in lines if line.startswith('{"asset"') or
                (line.startswith('{') and '"asset":' in line))


def finish_result(clients, child):
    child.stdin.close()
    child.stdin = None
    output, error = child.communicate(timeout=12)
    return child.returncode, (clients.buffers[child.pid] + output).decode(), error.decode()


def run_races(database, evidence):
    require(database.query('SELECT count(*) FROM public.users') == '0', 'Nonempty owned test DB')
    require(database.query("SELECT to_regnamespace('m3b_cycle_test') IS NULL") == 't', 'Fixture already exists')
    require(database.run_file(Path(__file__).with_name('mobile_reevaluation_photo_fixture.sql'),
                             str(evidence) + '.setup.log') == 0, 'Fixture setup failed')
    clients = Sessions(database)
    contexts = []
    results = []
    header = "SET request.jwt.claims='{\"role\":\"service_role\"}';\n"
    try:
        for index, mode in enumerate(('different_keys', 'same_key', 'rollback', 'clock_after_wait')):
            n = 1210 + index
            ctx = json.loads(database.query(f'SELECT m3b_cycle_test.photo_context({n})'))
            contexts.append(ctx)
            database.query("DO $$BEGIN FOR i IN 1..5 LOOP PERFORM m3b_cycle_test.allocate("
                           f"'{json.dumps(ctx)}'::jsonb,gen_random_uuid()); END LOOP;END$$;")
            key = uid(1300 + index)
            first_action = (f"SELECT id FROM public.users WHERE id='{ctx['user']}' FOR UPDATE;\n"
                            if mode == 'clock_after_wait' else allocate(ctx, key))
            first = clients.spawn(header + "BEGIN;\nSELECT jsonb_build_object('holder',pg_backend_pid());\n"
                                  + first_action + "SELECT 'QUOTA_READY';\n")
            first_lines = clients.until(first, lambda line: line == 'QUOTA_READY')
            holder = json.loads(next(line for line in first_lines if line.startswith('{"holder"')))['holder']
            second_key = uid(1400 + index) if mode == 'different_keys' else key
            second = clients.spawn(header + "SELECT jsonb_build_object('waiter',pg_backend_pid());\n"
                                   + allocate(ctx, second_key))
            waiter = json.loads(clients.until(second, lambda line: line.startswith('{"waiter"'))[-1])['waiter']
            deadline = time.monotonic() + 5
            while time.monotonic() < deadline:
                waiting = json.loads(database.query("SELECT jsonb_build_object('lock',wait_event_type='Lock',"
                    f"'blockers',pg_blocking_pids(pid)) FROM pg_stat_activity WHERE pid={int(waiter)}"))
                if waiting['lock'] and holder in waiting['blockers']:
                    break
                require(second.poll() is None, 'Quota waiter exited before exact owner lock')
                time.sleep(0.03)
            else:
                raise TimeoutError('Quota exact owner blocker not observed')
            boundary = database.query("SELECT to_char(clock_timestamp() AT TIME ZONE 'UTC',"
                                      "'YYYY-MM-DD\"T\"HH24:MI:SS.US\"Z\"')")
            clients.finish(first, 'ROLLBACK;\n' if mode == 'rollback' else 'COMMIT;\n')
            code, output, error = finish_result(clients, second)
            if mode == 'different_keys':
                require(code == 3 and 'mobile_reevaluation_photo_limit_reached' in error,
                        'Two concurrent requests obtained the sixth slot')
            else:
                require(code == 0 and not error.strip(), 'Legitimate replay/rollback/wait failed')
                result = wire(output.splitlines())
                if mode == 'same_key':
                    require(result == wire(first_lines), 'Concurrent replay is not same asset')
                if mode == 'rollback':
                    require(result['asset']['id'] != wire(first_lines)['asset']['id'], 'Rolled back identity escaped')
                if mode in ('rollback', 'clock_after_wait'):
                    require(result['asset']['created_at'] >= boundary, 'Clock captured before owner lock')
            for table in ('private.mobile_reevaluation_photo_assets', 'public.media_assets'):
                require(database.query(f"SELECT count(*) FROM {table} WHERE user_id='{ctx['user']}'") == '6',
                        'Quota did not preserve exactly six committed assets')
            require(database.query(f"SELECT source_revision FROM private.mobile_reevaluation_photo_sources WHERE user_id='{ctx['user']}'") == '6',
                    'Rejected/replayed request changed source revision')
            results.append({'case': mode, 'status': 'PASS', 'holder_backend_pid': holder,
                            'waiter_backend_pid': waiter, 'exact_blockers': waiting['blockers']})

        ctx = contexts[-1]
        request = {'cycleId': ctx['cycle'], 'expectedRevision': ctx['revision'],
                   'acceptanceId': ctx['acceptance'], 'pose': 'front', 'mimeType': 'image/jpeg',
                   'sizeBytes': 1200, 'requestKey': uid(1303)}
        exported = json.loads(database.query(allocate(ctx, request['requestKey'])))
        exclusive_json(str(evidence) + '.wire.json', {'owner': ctx['user'], 'request': request, 'response': exported})
        # No anon/authenticated route to allocation or ledger writes.
        for role in ('anon', 'authenticated'):
            response = subprocess.run(database.args + ['-c', f'SET ROLE {role};' + allocate(ctx, uid(1500))],
                                      env=database.env, capture_output=True, text=True, timeout=10)
            require(response.returncode != 0 and 'permission denied for function' in response.stderr,
                    'Client reached allocation authority')
        return {'races': results, 'direct_client_acl_checks': 2, 'wire': str(evidence) + '.wire.json'}
    finally:
        clients.close()
        if contexts:
            ids = ','.join(f"'{ctx['user']}'::uuid" for ctx in contexts)
            database.query('BEGIN;'+f'SELECT m3b_cycle_test.remove_photos(ARRAY[{ids}]);COMMIT;')
        cleanup_fixture(database, [ctx['user'] for ctx in contexts], [uid(501)])


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--config', required=True)
    parser.add_argument('--expected-runtime', required=True)
    parser.add_argument('--evidence', required=True)
    args = parser.parse_args()
    evidence = Path(args.evidence).resolve()
    require(not evidence.exists(), 'Evidence already exists')
    database = LocalCycleDatabase(args.config)
    require(database.guard == json.loads(Path(args.expected_runtime).read_text())['guard'], 'Runtime generation changed')
    database.args.insert(1, '-q')
    behavior = str(evidence) + '.behavior.log'
    require(database.run_file(Path(__file__).parents[1] / 'mobile_reevaluation_photo_quota.sql', behavior) == 0,
            'Quota behavior failed; inspect local log')
    result = run_races(database, evidence)
    result.update(status='PASS', behavior_log=behavior, unix_socket_only=True, new_paid_resources=0)
    exclusive_json(evidence, result)
    print(json.dumps({'status': 'PASS', 'real_owner_races': len(result['races']), 'new_paid_resources': 0}))


if __name__ == '__main__':
    main()
