#!/usr/bin/env python3
"""Real S17D/FULL binding races, only the existing task-owned local socket."""
import argparse
import json
import time
from decimal import Decimal
from pathlib import Path

from run_mobile_reevaluation_cycle import LocalCycleDatabase
from run_mobile_health_hold_authority import Sessions, exclusive_json, require
from run_mobile_clinical_full import confirmation, literal
from run_mobile_reevaluation_photo_consent import cleanup_fixture


def run(database, output):
    output = Path(output).resolve()
    require(not output.exists(), "Evidence already exists")
    root = Path(__file__).resolve().parents[3]
    folder = Path(__file__).resolve().parent
    require(database.query("SELECT NOT EXISTS(SELECT 1 FROM public.users) AND "
                           "to_regnamespace('m3b_cycle_test') IS NULL AND "
                           "to_regnamespace('c59s17d_fixture') IS NULL AND "
                           "to_regnamespace('c59p10b_fixture') IS NULL") == 't', "Fixture collision")
    require(database.run_file(folder / 'mobile_clinical_legacy_transition_fixture.sql',
                              str(output) + '.clinical-setup.log') == 0, "Clinical fixture failed")
    require(database.run_file(folder / 'mobile_workout_strength_clarification_fixture.sql',
                              str(output) + '.workout-setup.log') == 0, "Workout fixture failed")
    clients, owners, cases, last_observation = Sessions(database), [], [], None
    try:
        for index, mode in enumerate(('same_confirmation', 'rollback_then_confirmation',
                                      'confirmation_then_reset', 'reset_then_confirmation')):
            n = 5580 + index
            c = json.loads(database.query("SELECT m3b_cycle_test.process_clinical_photos("
                f"m3b_cycle_test.legacy_photo_context({n}))"), parse_float=Decimal)
            owner = c['user']
            owners.append(owner)
            q = json.loads(database.query("SELECT m3b_cycle_test.legacy_clinical_request("
                                          + literal(c) + "::jsonb)"), parse_float=Decimal)
            database.query(confirmation(owner, q, f'b3b01000-1000-4000-8000-{n:012d}'))
            ui = database.query("SELECT c59s17d_fixture.member(" + literal(owner) + ","
                f"c59s17d_fixture.key({n}),c59s17d_fixture.input(40,'qa-full-week-race-{n}'))")
            sql = database.query("SELECT c59s17d_fixture.confirm_sql(" + literal(owner)
                + ",(v->>'registrationID')::uuid,0,c59s17d_fixture.legacy_arguments(" + literal(owner)
                + ",v->'proposal'),o,c59s17d_fixture.catalogue_decision(o,v#>>'{proposal,workoutType}'))"
                + " FROM (SELECT " + literal(ui) + "::jsonb v,public.get_workout_strength_catalogue_context() o) x")
            require(sql.startswith('SELECT public.confirm_mobile_workout_registration('),
                    "Unexpected confirmation text")
            command = sql.strip().removeprefix('SELECT ').removesuffix(';')
            reset = f"public.reset_user_conversation_atomic({literal(owner)},true)"
            first_command = reset if mode == 'reset_then_confirmation' else command
            second_command = reset if mode == 'confirmation_then_reset' else command
            first = clients.spawn("BEGIN;SET LOCAL request.jwt.claim.role='service_role';SET LOCAL ROLE service_role;\n"
                "SELECT json_build_object('holder',pg_backend_pid());\n"
                "SELECT json_build_object('command_result'," + first_command + ");\n"
                "SELECT 'WEEK_READY';\n")
            lines = clients.until(first, lambda line: line == 'WEEK_READY')
            holder = json.loads(next(line for line in lines if line.startswith('{"holder"')))['holder']
            first_result = json.loads(next(line for line in lines if line.startswith('{"command_result"')))['command_result']
            second = clients.spawn("SET request.jwt.claim.role='service_role';SET ROLE service_role;\n"
                "SELECT json_build_object('waiter',pg_backend_pid());\n"
                "SELECT json_build_object('command_result'," + second_command + ");\n")
            waiter = json.loads(clients.until(second, lambda line: line.startswith('{"waiter"'))[-1])['waiter']
            deadline, waiting = time.monotonic() + 5, None
            while time.monotonic() < deadline:
                waiting = json.loads(database.query(
                    "SELECT json_build_object('lock',wait_event_type='Lock','blockers',pg_blocking_pids(pid)) "
                    f"FROM pg_stat_activity WHERE pid={int(waiter)}"))
                if waiting['lock'] and holder in waiting['blockers']:
                    break
                require(second.poll() is None, "Waiter terminated before actual lock")
                time.sleep(0.03)
            else:
                raise TimeoutError("Exact blocker not observed")
            boundary = database.query("SELECT to_char(clock_timestamp() AT TIME ZONE 'UTC',"
                                      "'YYYY-MM-DD\"T\"HH24:MI:SS.US\"Z\"')")
            clients.finish(first, "ROLLBACK;\n" if mode == 'rollback_then_confirmation' else "COMMIT;\n")
            raw = clients.finish(second)
            result = json.loads(next(line for line in raw.splitlines()
                                     if line.startswith('{"command_result"')))['command_result']
            state = json.loads(database.query("SELECT json_build_object("
                "'bindings',(SELECT count(*) FROM private.mobile_clinical_strength_week_bindings WHERE user_id="
                + literal(owner) + "),'open_scopes',(SELECT count(*) FROM private.strength_week_scopes WHERE user_id="
                + literal(owner) + " AND closed_at IS NULL),"
                "'capture_ops',(SELECT count(*) FROM private.workout_strength_operations WHERE user_id="
                + literal(owner) + " AND operation_kind='capture'),"
                "'binding_clock',(SELECT to_char(bound_at AT TIME ZONE 'UTC','YYYY-MM-DD\"T\"HH24:MI:SS.US\"Z\"') "
                "FROM private.mobile_clinical_strength_week_bindings WHERE user_id=" + literal(owner) + "),"
                "'profile_completed',(SELECT onboarding_completed FROM public.user_profiles WHERE user_id="
                + literal(owner) + "))"))
            last_observation = {'mode': mode, 'first': first_result,
                                'second': result, 'state': state}
            if mode == 'reset_then_confirmation':
                require(result == {'status': 'forbidden', 'reason': 'stale_epoch'}, "Stale S17D revived after reset")
                require(state['bindings'] == 0 and state['open_scopes'] == 0
                        and state['capture_ops'] == 0 and not state['profile_completed'], "Reset state changed")
            elif mode == 'confirmation_then_reset':
                require(first_result['status'] == 'confirmed' and state['bindings'] == 1
                        and state['open_scopes'] == 0 and not state['profile_completed'],
                        "Reset lost immutable binding or left live authority")
            else:
                expected_status = 'reused' if mode == 'same_confirmation' else 'confirmed'
                require(result['status'] == expected_status and state['bindings'] == 1
                        and state['open_scopes'] == 1 and state['capture_ops'] == 1,
                        "Concurrent S17D duplicated binding/capture")
                if mode == 'same_confirmation':
                    require(first_result['status'] == 'confirmed'
                            and first_result['registration']['id'] == result['registration']['id']
                            and first_result['capture']['legacy_result'] == result['capture']['legacy_result'],
                            "Replay did not preserve the exact original workout result")
                if mode == 'rollback_then_confirmation':
                    require(state['binding_clock'] >= boundary, "Binding sampled before rollback wait")
            cases.append({'case': mode, 'status': 'PASS', 'holder': holder, 'waiter': waiter,
                          'exact_blockers': waiting['blockers'], 'final_state': state})
    except Exception as error:
        exclusive_json(str(output) + '.failure.json', {'error': str(error), 'completed': cases,
                                                      'last_observation': last_observation})
        raise
    finally:
        clients.close()
        if owners:
            database.query('SELECT m3b_cycle_test.remove_photos(ARRAY['
                           + ','.join(literal(x) for x in owners) + ']::uuid[])')
            cleanup_fixture(database, owners, ('b3b01000-0000-4000-8000-000000000501',))
        database.query('DROP SCHEMA c59p10b_fixture CASCADE; DROP SCHEMA c59s17d_fixture CASCADE')
    require(database.query("SELECT NOT EXISTS(SELECT 1 FROM public.users) AND "
                           "to_regnamespace('m3b_cycle_test') IS NULL AND "
                           "to_regnamespace('c59s17d_fixture') IS NULL AND "
                           "to_regnamespace('c59p10b_fixture') IS NULL") == 't', "Fixture cleanup incomplete")
    value = {'status': 'PASS_REAL_LOCAL_FULL_S17D_BINDING_RACES', 'cases': cases,
             'guard': database.guard, 'remote_operations': 0, 'provider_operations': 0,
             'cleanup': 'PASS_SYNTHETIC_FIXTURE_ONLY_NOT_CUSTOMER_PURGE'}
    exclusive_json(output, value)
    return value


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--config', required=True)
    parser.add_argument('--output', required=True)
    args = parser.parse_args()
    db = LocalCycleDatabase(args.config)
    db.args.insert(1, '-q')
    result = run(db, args.output)
    print(json.dumps({'status': result['status'], 'cases': len(result['cases'])}))

