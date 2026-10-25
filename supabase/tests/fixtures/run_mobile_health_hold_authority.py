#!/usr/bin/env python3
"""Synthetic n10 SQL authority proof. Inert import; only an owned guarded UNIX socket."""
import argparse
import json
import os
import re
import select
import subprocess
import time
from pathlib import Path

from run_mobile_reevaluation_cycle import LocalCycleDatabase


def require(condition, message):
    if not condition:
        raise AssertionError(message)


def exclusive_json(path, value):
    with os.fdopen(os.open(path, os.O_CREAT | os.O_EXCL | os.O_WRONLY, 0o600), 'w') as stream:
        json.dump(value, stream, indent=2)
        stream.write('\n')


class Sessions:
    def __init__(self, database):
        self.db = database
        self.children = []
        self.buffers = {}

    def spawn(self, sql):
        child = subprocess.Popen(self.db.args, env=self.db.env, stdin=subprocess.PIPE,
                                 stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        self.children.append(child)
        self.buffers[child.pid] = b''
        child.stdin.write(sql.encode())
        child.stdin.flush()
        return child

    def until(self, child, predicate):
        deadline = time.monotonic() + 12
        lines = []
        while time.monotonic() < deadline:
            while b'\n' in self.buffers[child.pid]:
                line, self.buffers[child.pid] = self.buffers[child.pid].split(b'\n', 1)
                line = line.decode()
                lines.append(line)
                if predicate(line):
                    return lines
            if select.select([child.stdout], [], [], 0.05)[0]:
                chunk = os.read(child.stdout.fileno(), 65536)
                if not chunk:
                    raise RuntimeError('Owned SQL client exited before marker')
                self.buffers[child.pid] += chunk
        raise TimeoutError('Owned SQL client marker missing')

    def finish(self, child, ending=''):
        if ending:
            child.stdin.write(ending.encode())
            child.stdin.flush()
        child.stdin.close()
        child.stdin = None
        output, error = child.communicate(timeout=12)
        require(child.returncode == 0 and not error.strip(), 'Owned SQL transaction failed')
        return (self.buffers[child.pid] + output).decode()

    def close(self):
        for child in self.children:
            if child.poll() is None:
                child.terminate()
                try:
                    child.communicate(timeout=3)
                except subprocess.TimeoutExpired:
                    child.kill()
                    child.communicate(timeout=3)


def uid(n):
    return f'b3b01000-0000-4000-8000-{n:012d}'


def declaration(owner, key, item):
    return f"SELECT public.declare_mobile_health_risk('{owner}','{key}',ARRAY['{item}']);"


def run(database, evidence, fixture_path=None):
    root = Path(__file__).resolve().parents[3]
    evidence = Path(evidence).resolve()
    require(not evidence.exists(), 'Evidence path already used')
    fixture = Path(__file__).with_name('mobile_reevaluation_cycle_fixture.sql')
    require(database.query("SELECT to_regnamespace('m3b_cycle_test') IS NULL") == 't', 'Fixture exists')
    require(database.run_file(fixture, str(evidence) + '.setup.log') == 0, 'Fixture setup failed')
    clients = Sessions(database)
    cases = []
    fixture_result = None
    owners = [uid(n) for n in range(750, 757)]
    try:
        database.query('SELECT m3b_cycle_test.seed(n,NULL) FROM generate_series(750,756) n')
        modes = ['same_key', 'different_keys', 'rollback', 'declare_then_reset', 'reset_then_declare', 'clock_after_wait']
        for index, mode in enumerate(modes):
            owner, key = owners[index], uid(850 + index)
            first_sql = declaration(owner, key, 'reduced_intake')
            if mode == 'reset_then_declare':
                first_sql = f"SELECT public.reset_user_conversation_atomic('{owner}',true);"
            if mode == 'clock_after_wait':
                first_sql = f"SELECT id FROM public.users WHERE id='{owner}' FOR UPDATE;"
            first = clients.spawn("BEGIN;\nSELECT jsonb_build_object('holder',pg_backend_pid());\n"
                                  + first_sql + "\nSELECT 'HEALTH_READY';\n")
            lines = clients.until(first, lambda line: line == 'HEALTH_READY')
            holder = json.loads(next(line for line in lines if line.startswith('{"holder"')))['holder']
            first_result = next((json.loads(line) for line in lines if line.startswith('{"state"') or line.startswith('{"version"') or '"receipt"' in line), None)
            second_sql = declaration(owner, uid(950 + index) if mode == 'different_keys' else key,
                                     'professional_diet' if mode == 'different_keys' else 'reduced_intake')
            if mode == 'declare_then_reset':
                second_sql = f"SELECT public.reset_user_conversation_atomic('{owner}',true);"
            second = clients.spawn("SELECT jsonb_build_object('waiter',pg_backend_pid());\n" + second_sql + '\n')
            waiter = json.loads(clients.until(second, lambda line: line.startswith('{"waiter"'))[-1])['waiter']
            deadline = time.monotonic() + 5
            waiting = None
            while time.monotonic() < deadline:
                waiting = json.loads(database.query(f"SELECT jsonb_build_object('lock',wait_event_type='Lock','blockers',pg_blocking_pids(pid)) FROM pg_stat_activity WHERE pid={int(waiter)}"))
                if waiting['lock'] and holder in waiting['blockers']:
                    break
                require(second.poll() is None, 'Waiter exited without the owner lock')
                time.sleep(0.03)
            else:
                raise TimeoutError('Exact owner blocker was not observed')
            boundary = database.query("SELECT to_char(clock_timestamp() AT TIME ZONE 'UTC','YYYY-MM-DD\"T\"HH24:MI:SS.US\"Z\"')")
            clients.finish(first, 'ROLLBACK;\n' if mode == 'rollback' else 'COMMIT;\n')
            output = clients.finish(second)
            result = json.loads(next(line for line in output.splitlines() if line.startswith('{')))
            state = json.loads(database.query(f"SELECT public.get_mobile_health_hold_state('{owner}')"))
            receipts = int(database.query(f"SELECT count(*) FROM private.mobile_health_risk_receipts WHERE user_id='{owner}'"))
            require(state['hold_active'], 'Concurrency lost the declared HOLD')
            require(state['safety_revision'] == ('2' if mode == 'different_keys' else '1'), 'Safety revision differs')
            require(receipts == (2 if mode == 'different_keys' else 1), 'Durable receipt count differs')
            if mode == 'same_key':
                require(first_result['receipt'] == result['receipt'], 'Same key created a second receipt')
            if mode == 'different_keys':
                require([item['code'] for item in state['items']] == ['reduced_intake', 'professional_diet'], 'Concurrent union lost a risk')
            if mode == 'rollback':
                require(first_result['receipt']['id'] != result['receipt']['id'], 'Rolled-back receipt escaped')
            if mode == 'declare_then_reset':
                require(first_result['state'] == state, 'Waiting reset removed health authority')
            if mode == 'clock_after_wait':
                require(result['receipt']['declared_at'] >= boundary, 'Declaration clock was captured before the owner lock')
            cases.append({'case': mode, 'status': 'PASS', 'holder_backend_pid': holder,
                          'waiter_backend_pid': waiter, 'exact_blockers': waiting['blockers']})

        # Direct role checks must execute the RPC itself, not a revoked fixture helper.
        for role in ('anon', 'authenticated'):
            for call in (f"SELECT public.get_mobile_health_hold_state('{owners[0]}')",
                         declaration(owners[0], uid(999), 'reduced_intake')):
                result = subprocess.run(database.args + ['-c', f'SET ROLE {role};{call}'], env=database.env,
                                        text=True, capture_output=True, timeout=10)
                require(result.returncode != 0 and 'permission denied for function' in result.stderr,
                        'Client role reached health authority')
        for call in (f"SELECT public.get_mobile_health_hold_state('{owners[0]}')",
                     declaration(owners[0], uid(999), 'reduced_intake')):
            result = subprocess.run(database.args + ['-c', 'BEGIN ISOLATION LEVEL REPEATABLE READ;' + call],
                                    env=database.env, text=True, capture_output=True, timeout=10)
            require(result.returncode != 0 and 'requires_read_committed' in result.stderr,
                    'Incompatible isolation reached health authority')

        code_source = (root / 'packages/core/src/health-check-contracts.ts').read_text()
        codes = re.findall(r"'([a-z_]+)'", re.search(r'HEALTH_RISK_CODES = Object.freeze\(\[(.*?)\] as const\)', code_source, re.S).group(1))
        actual = json.loads(database.query("SELECT to_jsonb(enum_range(NULL::private.mobile_health_risk_code_v1))"))
        require(len(codes) == 8 and codes == actual, 'SQL enum differs from the shared core catalog')
        owner = owners[-1]
        absent = json.loads(database.query(f"SELECT public.get_mobile_health_hold_state('{owner}')"))
        initial = json.loads(database.query(declaration(owner, uid(996), 'professional_diet')))
        later = json.loads(database.query(declaration(owner, uid(997), 'pregnant_or_breastfeeding')))
        replay = json.loads(database.query(declaration(owner, uid(996), 'professional_diet')))
        fixture_result = {'source': 'actual owned local PostgreSQL authority; synthetic person only',
                          'absent': absent, 'initial': initial, 'later': later, 'replay': replay}
    finally:
        clients.close()
        ids = ','.join(f"'{owner}'::uuid" for owner in owners)
        database.query(f'DELETE FROM public.users WHERE id IN({ids}); DROP SCHEMA m3b_cycle_test CASCADE;')
    require(LocalCycleDatabase(database.config_path).guard == database.guard, 'Runtime changed during proof')
    if fixture_path:
        target = Path(fixture_path).resolve()
        expected = root / 'apps/admin/src/lib/mobile-api/testing/health-hold-fixture.json'
        require(target == expected, 'Unexpected fixture destination')
        exclusive_json(target, fixture_result)
    exclusive_json(evidence, {'status': 'PASS', 'cases': cases, 'shared_catalog_codes': len(codes),
                             'direct_client_acl_checks': 4, 'isolation_checks': 2,
                             'actual_sql_fixture': fixture_result is not None, 'owned_clients_reaped': True})


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--config', required=True)
    parser.add_argument('--expected-runtime', required=True)
    parser.add_argument('--evidence', required=True)
    parser.add_argument('--fixture')
    args = parser.parse_args()
    database = LocalCycleDatabase(args.config)
    database.args.insert(1, '-q')
    require(database.guard == json.loads(Path(args.expected_runtime).read_text())['guard'], 'Runtime generation changed')
    run(database, args.evidence, args.fixture)
    require(LocalCycleDatabase(args.config).guard == database.guard, 'Runtime changed during proof')
    print(json.dumps({'status': 'PASS', 'unix_socket_only': True, 'new_paid_resources': 0}))


if __name__ == '__main__':
    raise SystemExit(main())
