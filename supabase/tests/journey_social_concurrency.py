#!/usr/bin/env python3
"""Real connection regression for moderation retries and reciprocal blocks.

Requires an already owned, network-isolated local QA copy. Does not create/drop
any database or stop any service. Fixtures use new UUIDs and are removed exactly.
Usage: python3 journey_social_concurrency.py --registry /private/LOCAL-ARENA.json
"""
import argparse
import concurrent.futures
import hashlib
import json
import os
import selectors
from pathlib import Path
import subprocess
import time
import uuid


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--registry', type=Path, required=True)
    options = parser.parse_args()
    registry = json.loads(options.registry.read_text())
    data = Path(registry['data'])
    socket = Path(registry['socket'])
    assert registry['running'] and registry['test_copy_created'] and not registry['test_copy_closed']
    assert not registry['paid'] and registry['test_database'].startswith('performe_')
    assert not data.is_symlink() and data.stat().st_uid == os.getuid()
    assert not socket.is_symlink() and socket.stat().st_mode & 0o777 == 0o700
    assert (data / 'postmaster.pid').read_text().splitlines()[0] == str(registry['pid'])
    binary = Path(registry['psql'])
    assert hashlib.sha256(binary.read_bytes()).hexdigest() == registry['psql_sha256']
    sandbox = '(version 1)(allow default)(deny network*)(allow network* (local unix-socket) (remote unix-socket))'
    args = ['/usr/bin/sandbox-exec', '-p', sandbox, str(binary), '-w', '-X', '-qAt',
            '-v', 'ON_ERROR_STOP=1', '-v', 'VERBOSITY=sqlstate', '-h', str(socket),
            '-p', str(registry['port']), '-U', 'postgres', '-d', registry['test_database']]
    env = {key: os.environ[key] for key in ['PATH', 'HOME', 'LANG', 'TMPDIR'] if key in os.environ}

    def sql(query):
        return subprocess.run(args, input=query, text=True, capture_output=True, env=env, timeout=20)

    def checked(query):
        result = sql(query)
        assert result.returncode == 0, result.stderr
        return result.stdout.strip()

    identity = json.loads(checked("SELECT jsonb_build_object('db',current_database(),'data',"
                                 "current_setting('data_directory'),'listen',current_setting('listen_addresses'),"
                                 "'sysid',(SELECT system_identifier::text FROM pg_control_system()));"))
    assert identity == {'db': registry['test_database'], 'data': str(data), 'listen': '',
                        'sysid': registry['source_sysid']}
    auth_a, auth_b, actor, user_a, user_b = [str(uuid.uuid4()) for _ in range(5)]
    assert checked(f"SELECT count(*) FROM auth.users WHERE id IN('{auth_a}','{auth_b}','{actor}');") == '0'
    assert checked(f"SELECT count(*) FROM public.users WHERE id IN('{user_a}','{user_b}');") == '0'
    # Setup is one transaction: if a constraint fails nothing becomes owned.
    checked(f"""BEGIN;
INSERT INTO auth.users(id,email) VALUES
 ('{auth_a}','{auth_a}@example.invalid'),('{auth_b}','{auth_b}@example.invalid'),('{actor}','{actor}@example.invalid');
INSERT INTO public.users(id,auth_user_id,name) VALUES
 ('{user_a}','{auth_a}','Synthetic Journey concurrency'),('{user_b}','{auth_b}','Synthetic Journey concurrency');
INSERT INTO public.admin_users(id,email,role) VALUES('{actor}','{actor}@example.invalid','operations_admin');
COMMIT;""")
    holder = None

    def overlap(held_query, command_a, command_b, query_pattern):
        nonlocal holder
        holder = subprocess.Popen(args, stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                                  stderr=subprocess.PIPE, text=True, env=env)
        holder.stdin.write('BEGIN; ' + held_query + "SELECT 'HELD';\n")
        holder.stdin.flush()
        with selectors.DefaultSelector() as selector:
            selector.register(holder.stdout, selectors.EVENT_READ)
            assert selector.select(timeout=8), 'Owned lock holder did not become ready'
        assert holder.stdout.readline().strip() == 'HELD'
        with concurrent.futures.ThreadPoolExecutor(max_workers=2) as executor:
            first = executor.submit(sql, command_a)
            second = executor.submit(sql, command_b)
            deadline = time.monotonic() + 8
            waiting = 0
            while time.monotonic() < deadline:
                waiting = int(checked("SELECT count(*) FROM pg_stat_activity WHERE pid<>pg_backend_pid() "
                                      f"AND wait_event_type='Lock' AND query LIKE '{query_pattern}%';"))
                if waiting == 2:
                    break
                time.sleep(.05)
            assert waiting == 2, 'Both real commands must overlap behind the held row'
            holder.stdin.write('COMMIT;\n\\q\n')
            holder.stdin.flush()
            holder.wait(timeout=5)
            results = [first.result(), second.result()]
        assert all(result.returncode == 0 for result in results), [result.stderr for result in results]
        return [json.loads(result.stdout.strip()) for result in results]

    try:
        for user, auth in [(user_a, auth_a), (user_b, auth_b)]:
            checked(f"SELECT public.mutate_journey_social_profile('{user}','{auth}','{uuid.uuid4()}',0,true,'Pessoa QA','journey-social.v1');")
        member_a = checked(f"SELECT member_id FROM private.journey_social_profiles WHERE user_id='{user_a}';")
        member_b = checked(f"SELECT member_id FROM private.journey_social_profiles WHERE user_id='{user_b}';")
        report = json.loads(checked(f"SELECT public.submit_journey_social_report('{user_a}','{auth_a}','{uuid.uuid4()}',1,'{member_b}','nickname');"))['receipt']['report_id']
        operation = str(uuid.uuid4())
        command = f"SELECT public.resolve_journey_social_report('{actor}','{operation}','{report}',1,'dismissed');"
        # Hold the report so both real requests are admitted concurrently.
        results = overlap(f"DO $$BEGIN PERFORM 1 FROM private.journey_social_reports WHERE id='{report}' FOR UPDATE;END$$; ",
                          command, command, 'SELECT public.resolve_journey_social_report')
        assert sorted(result['status'] for result in results) == ['applied', 'replayed']
        assert results[0]['receipt'] == results[1]['receipt']
        assert checked(f"SELECT count(*) FROM private.journey_social_moderation_operations WHERE actor_id='{actor}';") == '1'
        print('PASS identical concurrent moderation: applied/replayed, one immutable receipt')
        commands = [f"SELECT public.mutate_journey_social_block('{user_a}','{auth_a}','{uuid.uuid4()}',2,'{member_b}',true);",
                    f"SELECT public.mutate_journey_social_block('{user_b}','{auth_b}','{uuid.uuid4()}',1,'{member_a}',true);"]
        results = overlap(f"DO $$BEGIN PERFORM 1 FROM public.users WHERE id IN('{user_a}','{user_b}') ORDER BY id FOR NO KEY UPDATE;END$$; ",
                          *commands, 'SELECT public.mutate_journey_social_block')
        assert all(result['status'] == 'applied' for result in results)
        assert checked(f"SELECT count(*) FROM private.journey_social_blocks WHERE blocker_id IN('{user_a}','{user_b}');") == '2'
        assert checked(f"SELECT count(*) FROM public.daily_snapshots WHERE user_id IN('{user_a}','{user_b}');") == '0'
        assert checked(f"SELECT count(*) FROM public.user_progress WHERE user_id IN('{user_a}','{user_b}');") == '0'
        print('PASS reciprocal concurrent blocking: both committed, no deadlock or XP writes')
    finally:
        if holder is not None and holder.poll() is None:
            holder.stdin.write('ROLLBACK;\n\\q\n')
            holder.stdin.flush()
            try:
                holder.wait(timeout=5)
            except subprocess.TimeoutExpired:
                # Only this test-owned psql holder; its transaction holds locks only.
                holder.terminate()
                try:
                    holder.wait(timeout=5)
                except subprocess.TimeoutExpired:
                    holder.kill()
                    holder.wait(timeout=5)
        checked(f"""BEGIN;
DELETE FROM public.users WHERE id IN('{user_a}','{user_b}') AND auth_user_id IN('{auth_a}','{auth_b}');
DELETE FROM public.admin_users WHERE id='{actor}' AND email='{actor}@example.invalid';
DELETE FROM auth.users WHERE id IN('{auth_a}','{auth_b}','{actor}') AND email=id::text||'@example.invalid';
DELETE FROM public.audit_log WHERE entity='admin_users' AND entity_id::text='{actor}'
 AND (before->>'email'='{actor}@example.invalid' OR after->>'email'='{actor}@example.invalid');
COMMIT;""")
        assert checked(f"SELECT (SELECT count(*) FROM auth.users WHERE id IN('{auth_a}','{auth_b}','{actor}'))"
                       f"+(SELECT count(*) FROM public.users WHERE id IN('{user_a}','{user_b}'))"
                       f"+(SELECT count(*) FROM private.journey_social_moderation_operations WHERE actor_id='{actor}')"
                       f"+(SELECT count(*) FROM public.audit_log WHERE entity='admin_users' AND entity_id::text='{actor}');") == '0'
        print('CLOSED exact owned synthetic fixtures; no service or database removed')


if __name__ == '__main__':
    main()
