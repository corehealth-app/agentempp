#!/usr/bin/env python3
"""Real whole-close SQL races, synthetic effects, owned UNIX-socket DB only.

This does not prove the BFF/core calculator, HTTP, Storage or deployed UI.
Import is inert. Every session, user and helper belongs to this run.
"""
import argparse
import json
import time
from pathlib import Path

from run_mobile_clinical_full import literal
from run_mobile_health_hold_authority import Sessions, exclusive_json, require
from run_mobile_reevaluation_cycle import LocalCycleDatabase


JWT = "SET request.jwt.claim='{\"role\":\"service_role\"}';\n"


def run(database, output):
    output = Path(output).resolve()
    require(not output.exists(), 'Evidence already exists')
    root = Path(__file__).resolve().parents[3]
    fixture = Path(__file__).with_name('mobile_clinical_day_close_fixture.sql')
    require(database.query("SELECT to_regnamespace('m3b_cycle_test') IS NULL AND NOT EXISTS(SELECT 1 FROM public.users)") == 't',
            'Owned database is not empty')
    require(database.run_file(fixture, str(output) + '.setup.log') == 0, 'Fixture setup failed')
    database.query("""
      CREATE FUNCTION m3b_cycle_test.try_command(statement text) RETURNS jsonb
      LANGUAGE plpgsql SET search_path=pg_catalog AS $$
      DECLARE result jsonb;code text;
      BEGIN
       BEGIN EXECUTE statement INTO result;
       EXCEPTION WHEN OTHERS THEN GET STACKED DIAGNOSTICS code=RETURNED_SQLSTATE;
        RETURN jsonb_build_object('code',code); END;
       RETURN jsonb_build_object('code','00000','result',result);
      END $$;
      REVOKE ALL ON ALL FUNCTIONS IN SCHEMA m3b_cycle_test FROM PUBLIC,anon,authenticated,service_role;
    """)
    sessions = Sessions(database)
    owners, cases = [], []
    failure = None

    def seed(n):
        q = json.loads(database.query(f'SELECT m3b_cycle_test.close_seed({n})'))
        owners.append(q['user'])
        return q

    def capture(q):
        return json.loads(database.query(f'SELECT m3b_cycle_test.close_capture({literal(q)})'))

    def apply(q, c, key):
        return f'SELECT m3b_cycle_test.close_apply({literal(q)},{literal(c)},{literal(key)})'

    def attempted(sql):
        return 'SELECT m3b_cycle_test.try_command(' + literal(sql) + ')'

    def holder(sql):
        child = sessions.spawn(JWT + "BEGIN;SELECT jsonb_build_object('holder',pg_backend_pid());\n"
                               + sql + ";SELECT 'CLOSE_READY';\n")
        lines = sessions.until(child, lambda x: x == 'CLOSE_READY')
        pid = json.loads(next(x for x in lines if x.startswith('{"holder"')))['holder']
        return child, pid, lines

    def waiter(sql, holder_pid):
        child = sessions.spawn(JWT + "SELECT jsonb_build_object('waiter',pg_backend_pid());\n" + sql + ';\n')
        lines = sessions.until(child, lambda x: x.startswith('{"waiter"'))
        pid = json.loads(lines[-1])['waiter']
        deadline = time.monotonic() + 5
        while time.monotonic() < deadline:
            state = json.loads(database.query(
                f"SELECT json_build_object('wait',wait_event_type='Lock','blockers',pg_blocking_pids(pid)) "
                f'FROM pg_stat_activity WHERE pid={int(pid)}'))
            if state['wait'] and holder_pid in state['blockers']:
                return child, pid
            require(child.poll() is None, 'Waiter exited before the real lock was observed')
            time.sleep(0.03)
        raise TimeoutError('Expected real blocker was not observed')

    def response(child):
        text = sessions.finish(child)
        return json.loads(next(line for line in text.splitlines() if line.startswith('{"code"')))

    def original(q):
        return database.query(f"SELECT m3b_cycle_test.original_state({literal(q['user'])})")

    try:
        for n, mode in enumerate(('same_key', 'different_keys', 'first_rollback', 'health_first', 'epoch_first'), 3200):
            q = seed(n)
            c = capture(q)
            key = f'b3b01000-9000-4000-8000-{n:012d}'
            other_key = key if mode != 'different_keys' else f'b3b01000-9001-4000-8000-{n:012d}'
            first_sql = apply(q, c, key)
            if mode == 'health_first':
                first_sql = f"SELECT public.declare_mobile_health_risk({literal(q['user'])},gen_random_uuid(),ARRAY['reduced_intake'])"
            if mode == 'epoch_first':
                first_sql = f"SELECT public.reset_user_conversation_atomic({literal(q['user'])},true)"
            first, first_pid, first_lines = holder(first_sql)
            second, second_pid = waiter(attempted(apply(q, c, other_key)), first_pid)
            sessions.finish(first, 'ROLLBACK;\n' if mode == 'first_rollback' else 'COMMIT;\n')
            result = response(second)
            success = mode in ('same_key', 'first_rollback')
            require(result['code'] == ('00000' if success else '40001'), 'Unexpected competing close outcome')
            if mode == 'same_key':
                original_result = json.loads(next(x for x in first_lines if x.startswith('{"result"') or x.startswith('{"request"')
                                                 or x.startswith('{"user_id"')))
                require(original_result == result['result'], 'Replay changed original envelope')
            counts = json.loads(database.query(f"SELECT json_build_object('keys',"
                f"(SELECT count(*) FROM private.mobile_clinical_day_close_keys WHERE user_id={literal(q['user'])}),"
                f"'completed',(SELECT count(*) FROM public.product_events WHERE user_id={literal(q['user'])} AND event='daily_closer.completed'))"))
            expected = 0 if mode in ('health_first', 'epoch_first') else 1
            require(counts == {'keys': expected, 'completed': expected}, 'Repeated or refused operation left effects')
            if mode in ('health_first', 'epoch_first'):
                require(database.query(f"SELECT NOT EXISTS(SELECT 1 FROM public.daily_snapshots WHERE user_id={literal(q['user'])} AND day_closed)") == 't',
                        'Clinical refusal closed a day')
            cases.append({'case': mode, 'owner_lock_observed': True, 'holder_pid': first_pid,
                          'waiter_pid': second_pid, 'code': result['code'], 'counts': counts, 'status': 'PASS'})

        for n, mode in enumerate(('insert_after_capture', 'move_after_capture',
                                  'workout_insert_after_capture', 'workout_move_after_capture'), 3210):
            q = seed(n)
            moved_id = None
            if mode == 'move_after_capture':
                moved_id = database.query(f"INSERT INTO public.meal_logs(user_id,meal_type,food_name,quantity_g,kcal,protein_g,carbs_g,fat_g,consumed_at) "
                    f"VALUES({literal(q['user'])},'almoco','synthetic moving row',100,50,0,0,0,"
                    f"({literal(q['date'])}::date+2+time '12:00') AT TIME ZONE 'America/Sao_Paulo') RETURNING id").splitlines()[0]
            if mode == 'workout_move_after_capture':
                moved_id = database.query(
                    'INSERT INTO public.workout_logs(user_id,snapshot_id,workout_type,duration_min,estimated_kcal,performed_at) '
                    f"VALUES({literal(q['user'])},{literal(q['snapshot'])},'QA close moving workout',12,50,"
                    f"({literal(q['date'])}::date+2+time '12:00') AT TIME ZONE 'America/Sao_Paulo') RETURNING id").splitlines()[0]
            c = capture(q)
            first, first_pid, _ = holder(f'SELECT m3b_cycle_test.close_capture({literal(q)})')
            if mode == 'workout_move_after_capture':
                writer = (f"UPDATE public.workout_logs SET performed_at=({literal(q['date'])}::date+time '13:00') "
                          f"AT TIME ZONE 'America/Sao_Paulo' WHERE id={literal(moved_id)} AND user_id={literal(q['user'])}")
            elif mode == 'workout_insert_after_capture':
                writer = ('INSERT INTO public.workout_logs(user_id,snapshot_id,workout_type,duration_min,estimated_kcal,performed_at) '
                          f"VALUES({literal(q['user'])},{literal(q['snapshot'])},'QA close blocked workout',12,50,"
                          f"({literal(q['date'])}::date+time '13:00') AT TIME ZONE 'America/Sao_Paulo')")
            elif moved_id:
                writer = f"UPDATE public.meal_logs SET consumed_at=({literal(q['date'])}::date+time '13:00') AT TIME ZONE 'America/Sao_Paulo' WHERE id={literal(moved_id)}"
            else:
                writer = f"INSERT INTO public.meal_logs(user_id,meal_type,food_name,quantity_g,kcal,protein_g,carbs_g,fat_g,consumed_at) VALUES(" \
                    f"{literal(q['user'])},'almoco','synthetic blocked insert',100,50,0,0,0,({literal(q['date'])}::date+time '13:00') AT TIME ZONE 'America/Sao_Paulo')"
            second, second_pid = waiter(writer, first_pid)
            sessions.finish(first, 'COMMIT;\n')
            sessions.finish(second)
            before = original(q)
            result = json.loads(database.query(attempted(apply(q, c, 'b3b01000-9000-4000-8000-000000009999'))))
            require(result['code'] == '40001' and before == original(q), 'New membership did not invalidate old close without effects')
            cases.append({'case': mode, 'lock_observed': True, 'holder_pid': first_pid,
                          'waiter_pid': second_pid, 'status': 'PASS'})

        q = seed(3220)
        first, _, _ = holder(f"UPDATE public.meal_logs SET consumed_at=consumed_at+interval '1 hour' WHERE user_id={literal(q['user'])}")
        # Existing subordinate activity is NOWAIT, never an owner-lock wait.
        start = time.monotonic()
        result = json.loads(database.query(attempted(f'SELECT m3b_cycle_test.close_capture({literal(q)})')))
        elapsed = time.monotonic() - start
        require(result['code'] == '55P03' and elapsed < 2, 'Subordinate mutation did not refuse promptly')
        sessions.finish(first, 'ROLLBACK;\n')
        cases.append({'case': 'existing_activity_writer_first', 'code': result['code'], 'elapsed_seconds': elapsed, 'status': 'PASS'})

        q = seed(3221)
        first, _, _ = holder('LOCK TABLE public.global_config IN ROW EXCLUSIVE MODE')
        result = json.loads(database.query(attempted(f'SELECT m3b_cycle_test.close_capture({literal(q)})')))
        require(result['code'] == '55P03', 'Configuration publication was not fenced')
        sessions.finish(first, 'ROLLBACK;\n')
        cases.append({'case': 'configuration_writer_first', 'code': result['code'], 'status': 'PASS'})

        q = seed(3222)
        first, first_pid, _ = holder(f"SELECT id FROM public.users WHERE id={literal(q['user'])} FOR UPDATE")
        second, second_pid = waiter(attempted(f'SELECT m3b_cycle_test.close_capture({literal(q)})'), first_pid)
        released = sessions.finish(first, "SELECT jsonb_build_object('release_at',clock_timestamp());COMMIT;\n")
        released_at = json.loads(next(x for x in released.splitlines() if x.startswith('{"release_at"')))['release_at']
        result = response(second)
        observed = result['result']['observed_at']
        require(result['code'] == '00000' and database.query(f"SELECT {literal(observed)}::timestamptz>={literal(released_at)}::timestamptz") == 't',
                'Capture reused a pre-wait clock')
        cases.append({'case': 'fresh_clock_after_owner_wait', 'owner_lock_observed': True,
                      'holder_pid': first_pid, 'waiter_pid': second_pid, 'status': 'PASS'})

        q = seed(3223)
        first, first_pid, _ = holder(f"SELECT id FROM public.users WHERE id={literal(q['user'])} FOR UPDATE")
        start = time.monotonic()
        public_capture = f"SELECT public.capture_mobile_clinical_day_close({literal(q['user'])},{literal(q['from'])},{literal(q['date'])},{literal(q['zone'])})"
        second, second_pid = waiter(attempted(public_capture), first_pid)
        result = response(second)
        elapsed = time.monotonic() - start
        require(result['code'] == '55P03' and elapsed < 4, 'Public owner wait exceeded the mobile bound')
        sessions.finish(first, 'ROLLBACK;\n')
        cases.append({'case': 'public_owner_wait_timeout', 'owner_lock_observed': True,
                      'holder_pid': first_pid, 'waiter_pid': second_pid, 'elapsed_seconds': elapsed,
                      'code': result['code'], 'status': 'PASS'})
    except BaseException as error:
        failure = type(error).__name__ + ': ' + str(error)
    finally:
        sessions.close()
        ids = ','.join(literal(owner) for owner in owners)
        # Same ordered purge used by existing local authority fixtures.
        if ids:
            database.query('BEGIN;DELETE FROM private.mobile_reevaluation_cycles WHERE user_id IN(' + ids + ');'
                           'DELETE FROM private.mobile_signup_strength_completion_receipts WHERE user_id IN(' + ids + ');'
                           'DELETE FROM public.users WHERE id IN(' + ids + ');DROP SCHEMA m3b_cycle_test CASCADE;COMMIT;')
        clean = database.query("SELECT NOT EXISTS(SELECT 1 FROM public.users) AND to_regnamespace('m3b_cycle_test') IS NULL "
                               'AND NOT EXISTS(SELECT 1 FROM net.http_request_queue)') == 't'
        report = {'status': 'FAIL' if failure or not clean else 'PASS', 'failure': failure,
                  'guard': database.guard, 'cases': cases, 'clean': clean,
                  'limitations': ['Synthetic trusted effect payloads; no BFF/core formula proof',
                                  'Owned local PostgreSQL only; no HTTP, Storage or remote mutation']}
        exclusive_json(output, report)
    require(failure is None and clean, failure or 'Cleanup failed')
    return report


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--config', required=True)
    parser.add_argument('--output', required=True)
    args = parser.parse_args()
    report = run(LocalCycleDatabase(args.config), args.output)
    print(json.dumps({'status': report['status'], 'cases': len(report['cases']), 'clean': report['clean']}))
