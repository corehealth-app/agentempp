#!/usr/bin/env python3
"""Actual Auth-row revocation races in an owned Unix-only local test copy.

No runtime/database creation, hosted access, or real account mutation.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import selectors
import subprocess
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
    args = ['/usr/bin/sandbox-exec', '-p', registry['sandbox_profile'], registry['psql'],
            '-w', '-X', '-qAt', '-v', 'ON_ERROR_STOP=1', '-v', 'VERBOSITY=sqlstate',
            '-h', str(socket), '-p', str(registry['port']), '-U', 'postgres', '-d', registry['test_database']]
    assert registry['sandbox_profile'] == '(version 1)(allow default)(deny network*)(allow network* (local unix-socket) (remote unix-socket))'
    env = {k: os.environ[k] for k in ['PATH', 'HOME', 'LANG', 'TMPDIR'] if k in os.environ}

    def sql(query):
        return subprocess.run(args, input=query, text=True, capture_output=True, env=env, timeout=12)

    def checked(query):
        result = sql(query)
        assert result.returncode == 0, result.stderr
        return result.stdout.strip()

    identity = json.loads(checked("SELECT jsonb_build_object('db',current_database(),'data',current_setting('data_directory'),"
                                 "'listen',current_setting('listen_addresses'),'sysid',(SELECT system_identifier::text FROM pg_control_system()));"))
    assert identity == {'db': registry['test_database'], 'data': str(data), 'listen': '', 'sysid': registry['source_sysid']}
    auth, owner, operator, login, operator_login = [str(uuid.uuid4()) for _ in range(5)]
    checked(f"""BEGIN;
INSERT INTO auth.users(id,email,email_confirmed_at) VALUES('{auth}','{auth}@example.invalid',clock_timestamp()),('{operator}','{operator}@example.invalid',clock_timestamp());
INSERT INTO public.users(id,auth_user_id,name) VALUES('{owner}','{auth}','Synthetic Auth revocation race');
INSERT INTO public.admin_users(id,email,role) VALUES('{operator}','{operator}@example.invalid','operations_admin');
INSERT INTO auth.sessions(id,user_id,created_at) VALUES('{login}','{auth}',clock_timestamp()),('{operator_login}','{operator}',clock_timestamp());
COMMIT;""")
    holder = None
    failures = []

    def begin_held(query):
        nonlocal holder
        holder = subprocess.Popen(args, stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, env=env)
        holder.stdin.write('BEGIN; ' + query + " SELECT 'HELD';\n")
        holder.stdin.flush()
        with selectors.DefaultSelector() as selector:
            selector.register(holder.stdout, selectors.EVENT_READ)
            assert selector.select(timeout=8), 'Owned transaction did not become ready'
        assert holder.stdout.readline().strip().startswith('{')
        assert holder.stdout.readline().strip() == 'HELD'

    def finish_held():
        nonlocal holder
        holder.stdin.write('ROLLBACK;\n'); holder.stdin.flush()
        _, error = holder.communicate(timeout=10)
        assert holder.returncode == 0, error
        holder = None

    patient = f"SELECT public.journey_social_patient_authenticated('{owner}','{auth}','{login}','profile.read','{{}}');"
    staff = f"SELECT public.journey_social_operator_authenticated('{operator}','{operator_login}','queue.read','{{\"limit\":20,\"cursor\":null}}');"
    try:
        for label, query, actor in [('patient', patient, auth), ('operator', staff, operator)]:
            begin_held(query)
            result = sql(f"SET lock_timeout='200ms'; UPDATE auth.users SET banned_until=clock_timestamp()+interval '1 hour' WHERE id='{actor}';")
            if result.returncode == 0 or '55P03' not in result.stderr:
                failures.append(label + ' did not serialize Auth revocation')
            finish_held()
            checked(f"UPDATE auth.users SET banned_until=NULL WHERE id='{actor}';")
            begin_held(f"UPDATE auth.users SET banned_until=clock_timestamp()+interval '1 hour' WHERE id='{actor}' RETURNING jsonb_build_object('owned',true);")
            result = sql(query)
            if result.returncode == 0 or 'PT409' not in result.stderr:
                failures.append(label + ' entered while Auth revocation was in progress')
            finish_held()
        assert checked(f"SELECT count(*) FROM private.journey_social_profiles WHERE user_id='{owner}';") == '0'
        assert checked(f"SELECT count(*) FROM public.daily_snapshots WHERE user_id='{owner}';") == '0'
    finally:
        if holder is not None:
            holder.stdin.write('ROLLBACK;\n'); holder.stdin.flush(); holder.communicate(timeout=10)
        checked(f"""BEGIN;
DELETE FROM public.users WHERE id='{owner}' AND auth_user_id='{auth}' AND name='Synthetic Auth revocation race';
DELETE FROM public.admin_users WHERE id='{operator}' AND email='{operator}@example.invalid';
DELETE FROM auth.users WHERE id IN('{auth}','{operator}') AND email=id::text||'@example.invalid';
DELETE FROM public.audit_log WHERE entity='admin_users' AND entity_id::text='{operator}' AND(before->>'email'='{operator}@example.invalid' OR after->>'email'='{operator}@example.invalid');
COMMIT;""")
        assert checked(f"SELECT (SELECT count(*) FROM auth.users WHERE id IN('{auth}','{operator}'))+(SELECT count(*) FROM public.users WHERE id='{owner}')+(SELECT count(*) FROM public.audit_log WHERE entity='admin_users' AND entity_id::text='{operator}');") == '0'
        print('CLOSED exact owned synthetic Auth revocation fixtures')
    assert not failures, '; '.join(failures)
    print('PASS patient/operator serialize Auth ban in both orders; no profile, reward or cross-account effects')


if __name__ == '__main__':
    main()
