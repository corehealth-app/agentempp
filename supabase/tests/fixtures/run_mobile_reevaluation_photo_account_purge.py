#!/usr/bin/env python3
"""Purge behavior and real owner-lock races, only in the guarded owned DB."""
import argparse
import json
import os
import select
import subprocess
import time
from pathlib import Path
from run_mobile_reevaluation_cycle import LocalCycleDatabase
from run_mobile_reevaluation_photo_consent import cleanup_fixture

if not __debug__:
    raise RuntimeError('Account purge runner refuses optimized Python')
HEADER = "SET request.jwt.claims='{\"role\":\"service_role\"}';\n"


def run_races(db, log):
    if db.query('SELECT count(*) FROM public.users') != '0' or db.query("SELECT to_regnamespace('m3b_cycle_test') IS NULL") != 't':
        raise RuntimeError('Account purge races require the empty owned runtime')
    fixture = Path(__file__).with_name('mobile_reevaluation_photo_fixture.sql')
    if db.run_file(fixture, str(log)+'.setup.log'):
        raise RuntimeError('Account purge fixture setup failed')
    children, buffers, cases = [], {}, []
    owners = [f'b3b01000-0000-4000-8000-{n:012d}' for n in (926, 927)]

    def query(sql):
        return db.query(HEADER+sql)

    def spawn(sql):
        child = subprocess.Popen(db.args, env=db.env, stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        children.append(child)
        buffers[child.pid] = b''
        child.stdin.write(sql.encode())
        child.stdin.flush()
        return child

    def until(child, marker):
        lines, deadline = [], time.monotonic()+15
        while time.monotonic() < deadline:
            while b'\n' in buffers[child.pid]:
                line, buffers[child.pid] = buffers[child.pid].split(b'\n', 1)
                lines.append(line.decode())
                if marker(lines[-1]):
                    return lines
            if select.select([child.stdout], [], [], .1)[0]:
                data = os.read(child.stdout.fileno(), 65536)
                if not data:
                    raise RuntimeError('Purge client ended before barrier')
                buffers[child.pid] += data
        raise TimeoutError('Purge barrier timeout')

    def finish(child, ending=''):
        if ending:
            child.stdin.write(ending.encode())
            child.stdin.flush()
        child.stdin.close()
        child.stdin = None
        out, err = child.communicate(timeout=15)
        if child.returncode or err.strip():
            raise RuntimeError('Owned purge session failed:'+err.decode()[-1500:])
        return (buffers[child.pid]+out).decode()

    try:
        for n, mode in ((926, 'eligibility_changed'), (927, 'duplicate_purge')):
            ctx = json.loads(query(f'SELECT m3b_cycle_test.photo_context({n});'))
            asset = json.loads(query(f"SELECT m3b_cycle_test.allocate('{json.dumps(ctx)}',gen_random_uuid());"))['asset']['id']
            user, cycle, acceptance = ctx['user'], ctx['cycle'], ctx['acceptance']
            query(f"UPDATE public.users SET status='deleted' WHERE id='{user}';")
            h = json.loads(query(f"SELECT public.prepare_mobile_reevaluation_photo_disposition('{user}','{cycle}','{acceptance}');"))['disposition']
            query(f"SELECT public.commit_mobile_reevaluation_photo_disposition_page('{user}','{h['id']}',{h['sweep_no']},{h['capability_revision']},NULL,ARRAY['{asset}'::uuid]);")
            cutoff = db.query('SELECT clock_timestamp()')
            purge = f"SELECT public.purge_mobile_reevaluation_photo_catalog_for_deleted_user('{user}','{cutoff}');\n"
            action = f"UPDATE public.users SET status='active' WHERE id='{user}';\n" if mode == 'eligibility_changed' else purge
            holder = spawn(HEADER+'BEGIN;\nSELECT pg_backend_pid();\n'+action+"SELECT 'PURGE_READY';\n")
            lines = until(holder, lambda s: s == 'PURGE_READY')
            holder_pid = int(next(s for s in lines if s.isdigit()))
            waiter = spawn(HEADER+'SELECT pg_backend_pid();\n'+purge)
            waiter_pid = int(until(waiter, lambda s: s.isdigit())[-1])
            deadline = time.monotonic()+5
            while time.monotonic() < deadline:
                state = json.loads(db.query("SELECT json_build_object('lock',wait_event_type='Lock','blockers',pg_blocking_pids(pid)) FROM pg_stat_activity WHERE pid="+str(waiter_pid)))
                if state['lock'] and holder_pid in state['blockers']:
                    break
                if waiter.poll() is not None:
                    raise RuntimeError('Purge waiter ended before exact owner blocker')
                time.sleep(.03)
            else:
                raise TimeoutError('Purge exact blocker not observed')
            finish(holder, 'COMMIT;\n')
            result = finish(waiter).strip()
            if result != ('f' if mode == 'eligibility_changed' else 't'):
                raise RuntimeError('Unexpected serialized purge result')
            retained = db.query(f"SELECT EXISTS(SELECT 1 FROM public.media_assets WHERE id='{asset}') AND EXISTS(SELECT 1 FROM private.mobile_reevaluation_photo_disposition_assets WHERE asset_id='{asset}')")
            if mode == 'eligibility_changed' and retained != 't':
                raise RuntimeError('Changed eligibility lost durable media authority')
            if mode == 'duplicate_purge' and db.query(f"SELECT count(*) FROM private.mobile_reevaluation_photo_assets WHERE user_id='{user}'") != '0':
                raise RuntimeError('Serialized purge left recurring catalog')
            cases.append({'case': mode, 'status': 'PASS', 'exact_blocker_observed': True, 'holder_pid': holder_pid, 'waiter_pid': waiter_pid})
    finally:
        for child in children:
            if child.poll() is None:
                child.terminate()
                try:
                    child.wait(timeout=3)
                except subprocess.TimeoutExpired:
                    child.kill()
                    child.wait(timeout=3)
        ids = ','.join("'"+x+"'::uuid" for x in owners)
        db.query('BEGIN;'+f'SELECT m3b_cycle_test.remove_photos(ARRAY[{ids}]);COMMIT;')
        cleanup_fixture(db, owners, ['b3b01000-0000-4000-8000-000000000501'])
    Path(log).write_text(json.dumps({'status': 'PASS', 'cases': cases, 'owned_clients_reaped': True}, indent=2)+'\n')


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--config', required=True)
    parser.add_argument('--log', required=True)
    args = parser.parse_args()
    log = Path(args.log).resolve()
    if log.exists():
        raise ValueError('Account purge evidence already exists')
    db = LocalCycleDatabase(args.config)
    db.args.insert(1, '-q')
    if db.run_file(Path(__file__).parents[1]/'mobile_reevaluation_photo_account_purge.sql', str(log)+'.behavior.log'):
        raise RuntimeError('Account purge SQL behavior failed')
    run_races(db, str(log)+'.races.json')
    result = {'status': 'PASS', 'behavior_log': str(log)+'.behavior.log', 'races': str(log)+'.races.json', 'new_paid_resources': 0}
    log.write_text(json.dumps(result, indent=2)+'\n')
    print(json.dumps(result))


if __name__ == '__main__':
    main()
