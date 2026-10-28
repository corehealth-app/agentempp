#!/usr/bin/env python3
"""Real daily-application races, restricted to the existing owned local DB."""
import argparse
import datetime
import hashlib
import json
import time
from pathlib import Path

from run_mobile_clinical_full import literal
from run_mobile_health_hold_authority import Sessions, exclusive_json, require
from run_mobile_reevaluation_cycle import LocalCycleDatabase


def run(database, output):
    output = Path(output).resolve()
    require(not output.exists(), 'Evidence already exists')
    root = Path(__file__).resolve().parents[3]
    fixture = root / 'supabase/tests/fixtures/mobile_clinical_daily_fixture.sql'
    require(database.query("SELECT to_regnamespace('m3b_cycle_test') IS NULL AND NOT EXISTS(SELECT 1 FROM public.users)") == 't',
            'Owned runtime is not empty')
    require(database.run_file(fixture, str(output) + '.setup.log') == 0, 'Daily fixture setup failed')
    database.query("""
      CREATE FUNCTION m3b_cycle_test.try_command(statement text) RETURNS jsonb
      LANGUAGE plpgsql SET search_path=pg_catalog AS $$
      DECLARE result jsonb;code text;message text;
      BEGIN
       BEGIN EXECUTE statement INTO result;
       EXCEPTION WHEN OTHERS THEN GET STACKED DIAGNOSTICS code=RETURNED_SQLSTATE,message=MESSAGE_TEXT;
        RETURN jsonb_build_object('code',code,'message',message); END;
       RETURN jsonb_build_object('code','00000','result',result);
      END $$;
      REVOKE ALL ON ALL FUNCTIONS IN SCHEMA m3b_cycle_test FROM PUBLIC,anon,authenticated,service_role;
    """)
    sessions = Sessions(database)
    owners = []
    cases = []
    failure = None
    try:
        for n, mode in enumerate(('same_operation', 'competing_operations', 'rollback', 'risk_first',
                                  'daily_then_risk', 'reset_first', 'daily_then_reset', 'weight_first'), 1950):
            owner = f'b3b01000-0000-4000-8000-{n:012d}'
            owners.append(owner)
            database.query(f"SELECT m3b_cycle_test.scheduled({n},'recomp_to_maintenance',clock_timestamp()-interval '28 days')")
            database.query("INSERT INTO public.daily_snapshots(user_id,date,calories_target,protein_target,current_protocol,"
                           "calories_consumed,exercise_calories) VALUES("
                           + literal(owner) + ",(clock_timestamp() AT TIME ZONE 'America/Sao_Paulo')::date,2100,144,'manutencao',500,200)")
            context = json.loads(database.query(
                'SELECT private.capture_mobile_clinical_context_at(' + literal(owner) + ",'APPLICATION',NULL,NULL)"))
            calculation = json.loads(database.query('SELECT m3b_cycle_test.daily_calculation()'))
            operation = f'b3b01000-1000-4000-8000-{n:012d}'

            def application(key):
                return ('SELECT private.apply_mobile_clinical_daily_at('
                        + ','.join(literal(x) for x in (owner, key, context['context_hash'], calculation)) + ',NULL);')

            apply = application(operation)
            first_sql, second_sql = apply, apply
            if mode == 'competing_operations':
                second_sql = application(f'b3b01000-2000-4000-8000-{n:012d}')
            risk = f"SELECT public.declare_mobile_health_risk({literal(owner)},gen_random_uuid(),ARRAY['reduced_intake']);"
            reset = f"SELECT public.reset_user_conversation_atomic({literal(owner)},true);"
            if mode == 'risk_first':
                first_sql = risk
            if mode == 'daily_then_risk':
                second_sql = risk
            if mode == 'reset_first':
                first_sql = reset
            if mode == 'daily_then_reset':
                second_sql = reset
            if mode == 'weight_first':
                first_sql = (f"SELECT public.record_weight_atomic({literal(owner)},50,'kg',clock_timestamp(),"
                             + literal(f'daily-race-weight-{n}') + ');')
            first = sessions.spawn("BEGIN;SELECT jsonb_build_object('holder',pg_backend_pid());\n"
                                   + first_sql + "\nSELECT 'M3B_DAILY_READY';\n")
            lines = sessions.until(first, lambda x: x == 'M3B_DAILY_READY')
            holder = json.loads(next(x for x in lines if x.startswith('{"holder"')))['holder']
            first_result = json.loads(next(x for x in lines if x.startswith('{') and not x.startswith('{"holder"')))
            second = sessions.spawn("SELECT jsonb_build_object('waiter',pg_backend_pid());\n"
                                    'SELECT m3b_cycle_test.try_command(' + literal(second_sql) + ');\n')
            waiter = json.loads(sessions.until(second, lambda x: x.startswith('{"waiter"'))[-1])['waiter']
            deadline = time.monotonic() + 5
            while time.monotonic() < deadline:
                blocking = json.loads(database.query(
                    "SELECT json_build_object('lock',wait_event_type='Lock','blockers',pg_blocking_pids(pid)) "
                    f'FROM pg_stat_activity WHERE pid={int(waiter)}'))
                if blocking['lock'] and holder in blocking['blockers']:
                    break
                require(second.poll() is None, 'Daily waiter exited without its owner lock')
                time.sleep(0.03)
            else:
                raise TimeoutError('Exact daily owner blocker not observed')
            boundary = database.query("SELECT to_char(clock_timestamp() AT TIME ZONE 'UTC','YYYY-MM-DD\"T\"HH24:MI:SS.US\"Z\"')")
            sessions.finish(first, 'ROLLBACK;\n' if mode == 'rollback' else 'COMMIT;\n')
            second_result = json.loads(next(x for x in sessions.finish(second).splitlines() if x.startswith('{')))
            state = json.loads(database.query("SELECT json_build_object('applications',"
                f"(SELECT count(*) FROM private.mobile_clinical_daily_applications WHERE user_id={literal(owner)}),"
                f"'profile',(SELECT json_build_object('phase',current_protocol,'weight',weight_kg) FROM public.user_profiles WHERE user_id={literal(owner)}),"
                f"'hold',public.get_mobile_health_hold_state({literal(owner)}),"
                f"'target',(SELECT calories_target FROM public.daily_snapshots WHERE user_id={literal(owner)} "
                "AND date=(clock_timestamp() AT TIME ZONE 'America/Sao_Paulo')::date))"))
            stale = mode in ('competing_operations', 'risk_first', 'reset_first', 'weight_first')
            require(second_result['code'] == ('40001' if stale else '00000'), f'{mode}: incorrect second result')
            require(state['applications'] == (0 if mode in ('risk_first', 'reset_first', 'weight_first') else 1),
                    f'{mode}: duplicate or stale daily application')
            if mode == 'same_operation':
                require(second_result['result'] == first_result, 'Daily replay changed original result')
                repeated = json.loads(database.query('SELECT m3b_cycle_test.daily_apply('
                                                     + literal(owner) + ',gen_random_uuid(),' + literal(calculation) + ')'))
                require(repeated == first_result, 'Fresh equivalent request reapplied daily effects')
            if mode == 'rollback':
                require(second_result['result']['applied_at'] >= boundary, 'Daily clock was sampled before owner wait')
                require(second_result['result']['application_id'] != first_result['application_id'], 'Rolled back application escaped')
            if mode in ('risk_first', 'daily_then_risk'):
                require(state['hold']['hold_active'] and state['hold']['safety_revision'] == '1', 'Concurrent risk was lost')
            if mode in ('reset_first', 'daily_then_reset'):
                require(state['profile']['phase'] is None, 'Daily application restored reset phase')
            if mode == 'daily_then_reset':
                replay = json.loads(database.query(apply))
                require(replay == first_result, 'Daily original acknowledgement lost after reset')
                require(database.query('SELECT current_protocol IS NULL FROM public.user_profiles WHERE user_id=' + literal(owner)) == 't',
                        'Replay resurrected reset state')
            if mode == 'weight_first':
                require(state['profile']['weight'] == 50, 'Stale daily application overwrote real weight')
            if mode in ('risk_first', 'weight_first'):
                fresh = json.loads(database.query('SELECT m3b_cycle_test.daily_apply('
                                                  + literal(owner) + ',gen_random_uuid(),' + literal(calculation) + ')'))
                require(fresh['state'] == 'suspended' and fresh['targets']['calories_target'] == 2100,
                        'Fresh guarded application failed to suspend at the original target')
            cases.append({'case': mode, 'status': 'PASS', 'holder': holder, 'waiter': waiter,
                          'exact_blockers': blocking['blockers'], 'second_code': second_result['code']})
    except Exception as error:
        failure = {'type': type(error).__name__, 'message': str(error)}
    finally:
        sessions.close()
        ids = ','.join(literal(x) for x in owners)
        require(bool(ids), 'No owned fixture identity admitted for cleanup')
        database.query("BEGIN; DO $guard$ BEGIN IF EXISTS(SELECT 1 FROM public.users WHERE id IN(" + ids
                       + ") AND email NOT LIKE 'm3b-cycle-%@example.invalid') THEN RAISE EXCEPTION 'Unknown fixture owner'; END IF; END $guard$;"
                       + 'DELETE FROM private.mobile_reevaluation_cycles WHERE user_id IN(' + ids + ');'
                       + 'DELETE FROM private.mobile_signup_strength_completion_receipts WHERE user_id IN(' + ids + ');'
                       + 'DELETE FROM public.users WHERE id IN(' + ids + ');'
                       + 'DROP SCHEMA m3b_cycle_test CASCADE; COMMIT;')
    clean = database.query("SELECT to_regnamespace('m3b_cycle_test') IS NULL AND NOT EXISTS(SELECT 1 FROM public.users)") == 't'
    result = {'at_utc': datetime.datetime.now(datetime.timezone.utc).isoformat(),
              'status': 'PASS_PRIVATE_DAILY_SQL_RACES_ONLY' if not failure and clean else 'FAIL',
              'cases': cases, 'failure': failure, 'clean': clean, 'guard': database.guard,
              'fixture_sha256': hashlib.sha256(fixture.read_bytes()).hexdigest(),
              'actual_BFF_QA': False, 'remote_operations': 0, 'provider_operations': 0}
    exclusive_json(output, result)
    require(not failure and clean, str(failure) if failure else 'Daily cleanup incomplete')
    return result


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--config', required=True)
    parser.add_argument('--output', required=True)
    args = parser.parse_args()
    db = LocalCycleDatabase(args.config)
    db.args.insert(1, '-q')
    result = run(db, args.output)
    print(json.dumps({'status': result['status'], 'cases': len(result['cases'])}))
