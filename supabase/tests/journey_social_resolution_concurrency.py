#!/usr/bin/env python3
"""Two real PostgreSQL connections: original writer versus receipt/fence recovery.

Requires an already owned, network-isolated local copy. Never creates/drops a
database or changes a service. Every fixture has fresh UUIDs and exact cleanup.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import selectors
import subprocess
import time
import uuid


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--registry', type=Path, required=True)
    registry = json.loads(parser.parse_args().registry.read_text())
    data, socket = Path(registry['data']), Path(registry['socket'])
    assert registry['running'] and registry['test_copy_created'] and not registry['test_copy_closed']
    assert not registry['paid'] and registry['test_database'].startswith('performe_')
    assert not data.is_symlink() and data.stat().st_uid == os.getuid()
    assert not socket.is_symlink() and socket.stat().st_mode & 0o777 == 0o700
    assert (data / 'postmaster.pid').read_text().splitlines()[0] == str(registry['pid'])
    assert hashlib.sha256(Path(registry['psql']).read_bytes()).hexdigest() == registry['psql_sha256']
    sandbox = '(version 1)(allow default)(deny network*)(allow network* (local unix-socket) (remote unix-socket))'
    args = ['/usr/bin/sandbox-exec', '-p', sandbox, registry['psql'], '-w', '-X', '-qAt',
            '-v', 'ON_ERROR_STOP=1', '-v', 'VERBOSITY=sqlstate', '-h', str(socket),
            '-p', str(registry['port']), '-U', 'postgres', '-d', registry['test_database']]
    env = {k: os.environ[k] for k in ['PATH', 'HOME', 'LANG', 'TMPDIR'] if k in os.environ}

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
    results = []
    for order in ['writer_first', 'resolver_first', 'two_resolvers']:
        auth, user, login, next_login, operation = [str(uuid.uuid4()) for _ in range(5)]
        assert checked(f"SELECT count(*) FROM auth.users WHERE id='{auth}';") == '0'
        checked(f"""BEGIN;
INSERT INTO auth.users(id,email,email_confirmed_at) VALUES('{auth}','{auth}@example.invalid',clock_timestamp());
INSERT INTO public.users(id,auth_user_id,name) VALUES('{user}','{auth}','Synthetic recovery race');
INSERT INTO auth.sessions(id,user_id,created_at) VALUES('{login}','{auth}',clock_timestamp()),('{next_login}','{auth}',clock_timestamp());
COMMIT;""")
        command = json.dumps({'operation_id': operation, 'expected_revision': 0, 'opted_in': True,
                              'nickname': 'Synthetic', 'consent_version': 'journey-social.v1'})
        writer = f"SELECT public.journey_social_patient_authenticated('{user}','{auth}','{login}','profile.update','{command}');"
        resolver = f"SELECT public.resolve_journey_social_operation_authenticated('{user}','{auth}','{next_login}','profile','{command}');"
        first, second = ((writer, resolver) if order == 'writer_first' else
                         (resolver, writer) if order == 'resolver_first' else (resolver, resolver))
        holder = waiter = None
        try:
            holder = subprocess.Popen(args, stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                                      stderr=subprocess.PIPE, text=True, env=env)
            holder.stdin.write("BEGIN; " + first + " SELECT 'HELD';\n")
            holder.stdin.flush()
            with selectors.DefaultSelector() as selector:
                selector.register(holder.stdout, selectors.EVENT_READ)
                assert selector.select(timeout=8), 'First original operation did not reach its lock'
            initial = json.loads(holder.stdout.readline())
            assert holder.stdout.readline().strip() == 'HELD'
            waiter = subprocess.Popen(args, stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                                      stderr=subprocess.PIPE, text=True, env=env)
            waiter.stdin.write(second + '\n')
            waiter.stdin.close()
            deadline = time.monotonic() + 8
            waiting = 0
            while time.monotonic() < deadline:
                waiting = int(checked("SELECT count(*) FROM pg_stat_activity WHERE pid<>pg_backend_pid() "
                                      f"AND wait_event_type='Lock' AND query LIKE '%{operation}%';"))
                if waiting == 1:
                    break
                time.sleep(.05)
            assert waiting == 1, 'Second real connection must overlap behind the first operation'
            holder.stdin.write('COMMIT;\n\\q\n')
            holder.stdin.flush()
            holder.wait(timeout=5)
            assert holder.returncode == 0, holder.stderr.read()
            waiter.wait(timeout=10)
            output, error = waiter.stdout.read().strip(), waiter.stderr.read()
            if order == 'writer_first':
                assert waiter.returncode == 0, error
                observed = json.loads(output)
                assert initial['status'] == observed['status'] == 'applied'
                assert observed['receipt'] == initial['receipt']
                assert observed['profile']['revision'] == 1
                expected = {'profiles': 1, 'receipts': 1, 'fences': 0}
            elif order == 'resolver_first':
                assert initial['status'] == 'fenced' and initial['receipt'] is None
                assert waiter.returncode != 0 and 'PT409' in error, error
                assert json.loads(checked(resolver)) == initial
                expected = {'profiles': 0, 'receipts': 0, 'fences': 1}
            else:
                assert waiter.returncode == 0, error
                assert initial == json.loads(output) and initial['status'] == 'fenced'
                expected = {'profiles': 0, 'receipts': 0, 'fences': 1}
            counts = json.loads(checked(f"SELECT jsonb_build_object('profiles',(SELECT count(*) FROM private.journey_social_profiles WHERE user_id='{user}'),'receipts',(SELECT count(*) FROM private.journey_social_operations WHERE user_id='{user}'),'fences',(SELECT count(*) FROM private.journey_social_operation_fences WHERE user_id='{user}'));"))
            assert counts == expected, counts
            results.append({'order': order, 'overlap_proved': True, 'counts': counts, 'status': 'PASS'})
        finally:
            # Release only subprocesses and fresh fixtures created in this case.
            for child in [holder, waiter]:
                if child and child.poll() is None:
                    child.terminate()
                    child.wait(timeout=5)
            checked(f"BEGIN;DELETE FROM public.users WHERE id='{user}' AND auth_user_id='{auth}';DELETE FROM auth.users WHERE id='{auth}';COMMIT;")
            assert checked(f"SELECT count(*) FROM private.journey_social_operation_fences WHERE user_id='{user}';") == '0'
    print(json.dumps({'status': 'PASS', 'real_connection_races': results, 'own_fixtures_closed': True}))


if __name__ == '__main__':
    main()
