#!/usr/bin/env python3
"""Real admission/reset races on the guarded owned UNIX socket. Inert import."""
import argparse
import json
from pathlib import Path

from run_mobile_clinical_snapshot import exact_wait
from run_mobile_health_hold_authority import Sessions, exclusive_json, require, uid
from run_mobile_reevaluation_cycle import LocalCycleDatabase


def run(database, evidence):
    evidence = Path(evidence).resolve()
    require(not evidence.exists(), 'Evidence already exists')
    require(database.query("SELECT to_regnamespace('m3b_cycle_test') IS NULL") == 't',
            'Fixture already exists')
    owners = [uid(n) for n in range(2960, 2965)]
    ids = ','.join("'" + owner + "'::uuid" for owner in owners)
    require(database.query(f'SELECT count(*) FROM public.users WHERE id IN({ids})') == '0',
            'Synthetic IDs already exist')
    fixture = Path(__file__).with_name('mobile_reevaluation_cycle_fixture.sql')
    require(database.run_file(fixture, str(evidence) + '.setup.log') == 0, 'Fixture setup failed')
    clients = Sessions(database)
    cases = []
    session = ("SET request.jwt.claims='{\"role\":\"service_role\"}';\n"
               "SET statement_timeout='12s'; SET lock_timeout='8s';\n")
    modes = ['same_epoch_commit', 'first_rollback', 'reset_then_admit',
             'admit_then_reset', 'clock_after_wait']
    try:
        database.query("SELECT m3b_cycle_test.seed(n,'2026-10-01T23:00:00Z',"
                       "'America/Sao_Paulo',false) FROM generate_series(2960,2964) n")
        for owner, mode in zip(owners, modes):
            admit = f"SELECT private.admit_mobile_clinical_legacy_generation_at('{owner}',NULL);"
            reset = f"SELECT public.reset_user_conversation_atomic('{owner}',true);"
            first_sql = reset if mode == 'reset_then_admit' else admit
            if mode == 'clock_after_wait':
                first_sql = f"SELECT id FROM public.users WHERE id='{owner}' FOR UPDATE;"
            first = clients.spawn(session + "BEGIN;\n"
                                  "SELECT jsonb_build_object('holder',pg_backend_pid());\n"
                                  + first_sql + "\nSELECT 'LEGACY_READY';\n")
            lines = clients.until(first, lambda line: line == 'LEGACY_READY')
            holder = json.loads(next(line for line in lines if line.startswith('{"holder"')))['holder']
            first_result = next((json.loads(line) for line in lines
                                 if line.startswith('{') and '"availability"' in line), None)
            second_sql = reset if mode == 'admit_then_reset' else admit
            second = clients.spawn(session + "SELECT jsonb_build_object('waiter',pg_backend_pid());\n"
                                   + second_sql + '\n')
            lines = clients.until(second, lambda line: line.startswith('{"waiter"'))
            waiter = json.loads(lines[-1])['waiter']
            blockers = exact_wait(database, second, holder, waiter)
            released_at = database.query("SELECT to_char(clock_timestamp() AT TIME ZONE 'UTC',"
                                         "'YYYY-MM-DD\"T\"HH24:MI:SS.US\"Z\"')")
            clients.finish(first, 'ROLLBACK;\n' if mode == 'first_rollback' else 'COMMIT;\n')
            output = clients.finish(second)
            result = next(json.loads(line) for line in output.splitlines() if line.startswith('{'))
            observation = database.query(session +
                "SELECT coalesce(private.read_mobile_clinical_legacy_generation_at("
                f"'{owner}',NULL),'null'::jsonb)")
            observed = json.loads(observation.splitlines()[-1])
            if mode == 'reset_then_admit':
                require(result['reason'] == 'onboarding_incomplete' and observed is None,
                        'A waiting admission must honor the committed reset')
            elif mode == 'admit_then_reset':
                require(observed is None, 'A committed reset must revoke observed admission')
                require(database.query(f'SELECT count(*) FROM private.mobile_clinical_legacy_admissions '
                                       f"WHERE user_id='{owner}'") == '1',
                        'Reset must preserve the immutable prior boundary')
            else:
                require(result['availability'] == 'admitted' and result['authority'] == observed,
                        'Waiting admission did not resolve to current authority')
                require(database.query(f'SELECT count(*) FROM private.mobile_clinical_legacy_admissions '
                                       f"WHERE user_id='{owner}'") == '1',
                        'Concurrent admission left duplicate generations')
                if mode == 'same_epoch_commit':
                    require(result == first_result, 'Same epoch did not reuse exact admission')
                elif mode == 'first_rollback':
                    require(result['authority']['generation'] != first_result['authority']['generation'],
                            'Rolled-back admission was reconstructed')
                else:
                    require(result['authority']['admitted_at'] >= released_at,
                            'Admission clock was sampled before the authority wait')
            require(database.query(f'SELECT count(*) FROM private.mobile_signup_strength_completion_receipts '
                                   f"WHERE user_id='{owner}'") == '0',
                    'Legacy admission fabricated a signup receipt')
            cases.append({'case': mode, 'status': 'PASS', 'exact_owner_lock': blockers,
                          'holder_pid': holder, 'waiter_pid': waiter})
    finally:
        clients.close()
        # Only IDs proven absent before this run and seeded here are removed.
        database.query('BEGIN; DO $guard$ BEGIN IF EXISTS(SELECT 1 FROM public.users '
                       f"WHERE id IN({ids}) AND email NOT LIKE 'm3b-cycle-%@example.invalid') "
                       "THEN RAISE EXCEPTION 'Refuse nonfixture owner'; END IF; END $guard$;"
                       f'DELETE FROM public.users WHERE id IN({ids}); '
                       'DROP SCHEMA m3b_cycle_test CASCADE; COMMIT;')
    require(database.query(f'SELECT count(*) FROM public.users WHERE id IN({ids})') == '0',
            'Owned synthetic owners remain')
    require(database.query("SELECT to_regnamespace('m3b_cycle_test') IS NULL") == 't',
            'Owned fixture schema remains')
    exclusive_json(evidence, {'status': 'PASS', 'cases': cases,
                              'owned_clients_reaped': True, 'fixture_removed': True,
                              'target': 'GUARDED_LOCAL_UNIX_SOCKET_ONLY'})


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--config', required=True)
    parser.add_argument('--evidence', required=True)
    args = parser.parse_args()
    run(LocalCycleDatabase(args.config), args.evidence)


if __name__ == '__main__':
    main()
