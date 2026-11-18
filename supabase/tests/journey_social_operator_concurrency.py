#!/usr/bin/env python3
"""Real connection races in an already owned, network-isolated local QA copy.

Does not create/drop a database, start/stop a service, or access hosted data.
Fixtures are uniquely generated and removed exactly, including audit fences.
"""
import argparse
import concurrent.futures
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

    identity = json.loads(checked("SELECT jsonb_build_object('db',current_database(),'data',current_setting('data_directory'),"
                                 "'listen',current_setting('listen_addresses'),'sysid',(SELECT system_identifier::text FROM pg_control_system()));"))
    assert identity == {'db': registry['test_database'], 'data': str(data), 'listen': '', 'sysid': registry['source_sysid']}
    actor, auth, user, login, new_login, operation, cancelled, participation = [str(uuid.uuid4()) for _ in range(8)]
    checked(f"""BEGIN;
INSERT INTO auth.users(id,email,email_confirmed_at) VALUES('{actor}','{actor}@example.invalid',clock_timestamp()),('{auth}','{auth}@example.invalid',clock_timestamp());
INSERT INTO public.admin_users(id,email,role) VALUES('{actor}','{actor}@example.invalid','operations_admin');
INSERT INTO auth.sessions(id,user_id,created_at) VALUES('{login}','{actor}',clock_timestamp());
INSERT INTO public.users(id,auth_user_id,name) VALUES('{user}','{auth}','Synthetic operator race');
COMMIT;""")
    holder = None

    def begin_held(query):
        nonlocal holder
        holder = subprocess.Popen(args, stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, env=env)
        holder.stdin.write('BEGIN; ' + query + " SELECT 'HELD';\n")
        holder.stdin.flush()
        with selectors.DefaultSelector() as selector:
            selector.register(holder.stdout, selectors.EVENT_READ)
            assert selector.select(timeout=8), 'Owned transaction did not become ready'
        # Consume the query's JSON result as well as the explicit readiness marker.
        assert holder.stdout.readline().strip().startswith('{')
        assert holder.stdout.readline().strip() == 'HELD'

    def finish_held():
        nonlocal holder
        holder.stdin.write('COMMIT;\n'); holder.stdin.flush()
        out, error = holder.communicate(timeout=10)
        assert holder.returncode == 0, error
        holder = None

    def wait_for_blocked(pattern, minimum):
        deadline = time.monotonic() + 8
        while time.monotonic() < deadline:
            waiting = int(checked("SELECT count(*) FROM pg_stat_activity WHERE pid<>pg_backend_pid() AND wait_event_type='Lock' "
                                  f"AND query LIKE '{pattern}%';"))
            if waiting >= minimum:
                return
            time.sleep(.03)
        raise AssertionError('Expected actual live PostgreSQL lock wait not observed')

    def gateway(action, command, session=login):
        body = json.dumps(command, separators=(',', ':'))
        return f"SELECT public.journey_social_operator_authenticated('{actor}','{session}','{action}','{body}'::jsonb);"

    try:
        profile = json.loads(checked(f"SELECT public.mutate_journey_social_profile('{user}','{auth}','{participation}',0,true,'Pessoa teste','journey-social.v1');"))
        member = profile['profile']['member_id']
        command = {'operation_id': operation, 'member_id': member, 'expected_revision': 1, 'action': 'suspend'}
        begin_held(gateway('profile.moderate', command))
        # Competing gateway calls return a conflict; they never retry implicitly.
        conflict = sql(gateway('profile.moderate', command))
        assert conflict.returncode != 0 and 'PT409' in conflict.stderr
        with concurrent.futures.ThreadPoolExecutor(max_workers=2) as executor:
            logout = executor.submit(sql, f"DELETE FROM auth.sessions WHERE id='{login}';")
            revoke = executor.submit(sql, f"UPDATE public.admin_users SET role='support' WHERE id='{actor}';")
            wait_for_blocked('DELETE FROM auth.sessions', 1)
            wait_for_blocked('UPDATE public.admin_users', 1)
            finish_held()
            assert logout.result().returncode == revoke.result().returncode == 0
        assert checked(f"SELECT count(*) FROM private.journey_social_moderation_operations WHERE actor_id='{actor}';") == '1'
        assert checked(f"SELECT revision||':'||moderation FROM private.journey_social_profiles WHERE user_id='{user}';") == '2:suspended'
        denied = sql(gateway('profile.moderate', command))
        assert denied.returncode != 0 and '42501' in denied.stderr
        print('PASS actual writer holds role/session against concurrent revocation/logout; conflict has one effect/receipt')

        checked(f"UPDATE public.admin_users SET role='operations_admin' WHERE id='{actor}'; INSERT INTO auth.sessions(id,user_id,created_at) VALUES('{new_login}','{actor}',clock_timestamp());")
        denied = sql(gateway('profile.moderate', command))
        assert denied.returncode != 0 and 'PT401' in denied.stderr
        recovered = json.loads(checked(gateway('operation.resolve', {'kind': 'profile', 'command': command}, new_login)))
        assert recovered['status'] == 'applied' and recovered['receipt']['operation_id'] == operation
        assert checked(f"SELECT revision FROM private.journey_social_profiles WHERE user_id='{user}';") == '2'
        print('PASS revoked old login cannot replay; explicit new-login recovery reads the immutable receipt without another effect')

        cancelled_command = {'operation_id': cancelled, 'member_id': member, 'expected_revision': 2, 'action': 'restore'}
        begin_held(gateway('operation.resolve', {'kind': 'profile', 'command': cancelled_command}, new_login))
        # A legacy lower-level writer already queued before the fence commits
        # must roll back its actual update, not merely fail receipt insertion.
        with concurrent.futures.ThreadPoolExecutor(max_workers=1) as executor:
            delayed = executor.submit(sql, f"SELECT public.moderate_journey_social_profile('{actor}','{cancelled}','{member}',2,'restore');")
            wait_for_blocked('SELECT public.moderate_journey_social_profile', 1)
            finish_held()
            result = delayed.result()
            assert result.returncode != 0 and 'PT409' in result.stderr
        assert checked(f"SELECT revision||':'||moderation FROM private.journey_social_profiles WHERE user_id='{user}';") == '2:suspended'
        assert checked(f"SELECT count(*) FROM private.journey_social_moderation_operations WHERE actor_id='{actor}';") == '1'
        assert checked(f"SELECT count(*) FROM public.daily_snapshots WHERE user_id='{user}';") == '0'
        assert checked(f"SELECT count(*) FROM public.user_progress WHERE user_id='{user}';") == '0'
        print('PASS committed fence cancels queued lower-level writer with full rollback and no XP/health writes')
    finally:
        if holder is not None and holder.poll() is None:
            holder.stdin.write('ROLLBACK;\n'); holder.stdin.flush(); holder.communicate(timeout=10)
        checked(f"""BEGIN;
DELETE FROM private.journey_social_moderation_fences WHERE actor_id='{actor}';
DELETE FROM private.journey_social_moderation_operations WHERE actor_id='{actor}';
DELETE FROM public.users WHERE id='{user}' AND auth_user_id='{auth}';
DELETE FROM public.admin_users WHERE id='{actor}' AND email='{actor}@example.invalid';
DELETE FROM auth.users WHERE (id='{actor}' AND email='{actor}@example.invalid') OR (id='{auth}' AND email='{auth}@example.invalid');
DELETE FROM public.audit_log WHERE entity='admin_users' AND entity_id::text='{actor}'
 AND (before->>'email'='{actor}@example.invalid' OR after->>'email'='{actor}@example.invalid');
COMMIT;""")
        assert checked(f"SELECT count(*) FROM auth.users WHERE id IN('{actor}','{auth}');") == '0'
        assert checked(f"SELECT count(*) FROM public.audit_log WHERE entity='admin_users' AND entity_id::text='{actor}';") == '0'
        print('PASS exact synthetic fixture closeout')


if __name__ == '__main__':
    main()
