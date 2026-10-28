#!/usr/bin/env python3
"""Real first-transition races on the existing guarded socket. Inert import."""
import argparse
import datetime
import json
from pathlib import Path

from run_mobile_clinical_snapshot import exact_wait
from run_mobile_health_hold_authority import Sessions, exclusive_json, require, uid
from run_mobile_reevaluation_cycle import LocalCycleDatabase


def run(database, evidence):
    evidence = Path(evidence).resolve()
    require(not evidence.exists(), 'Evidence already exists')
    require(database.query("SELECT to_regnamespace('m3b_cycle_test') IS NULL") == 't',
            'Fixture schema already exists')
    owners = [uid(n) for n in range(2980, 2985)]
    ids = ','.join("'" + owner + "'::uuid" for owner in owners)
    require(database.query(f'SELECT count(*) FROM public.users WHERE id IN({ids})') == '0',
            'Synthetic owner IDs already exist')
    fixture = Path(__file__).with_name('mobile_reevaluation_cycle_fixture.sql')
    require(database.run_file(fixture, str(evidence) + '.setup.log') == 0, 'Fixture setup failed')
    session = ("SET request.jwt.claims='{\"role\":\"service_role\"}';\n"
               "SET statement_timeout='12s'; SET lock_timeout='8s';\n")
    clients = Sessions(database)
    cases = []
    try:
        database.query(session + "SELECT m3b_cycle_test.seed(n,'2026-10-01T23:00:00Z',"
                       "'America/Sao_Paulo',false) FROM generate_series(2980,2984) n;"
                       f'SELECT private.admit_mobile_clinical_legacy_generation_at(id,NULL) '
                       f'FROM public.users WHERE id IN({ids});')
        # Only the observer catches an error; production entrypoints stay strict.
        database.query("""CREATE FUNCTION m3b_cycle_test.observed_transition(a uuid,k uuid)
          RETURNS jsonb LANGUAGE plpgsql SET search_path=pg_catalog AS $$
          BEGIN RETURN jsonb_build_object('state',private.start_mobile_reevaluation_cycle_at(a,k,NULL));
          EXCEPTION WHEN OTHERS THEN RETURN jsonb_build_object('error',SQLSTATE,'message',SQLERRM); END $$;
          CREATE FUNCTION m3b_cycle_test.observed_legacy_context(a uuid)
          RETURNS jsonb LANGUAGE plpgsql SET search_path=pg_catalog AS $$
          BEGIN RETURN jsonb_build_object('context',private.mobile_reevaluation_context_at(a,NULL));
          EXCEPTION WHEN OTHERS THEN RETURN jsonb_build_object('error',SQLSTATE,'message',SQLERRM); END $$;
          REVOKE ALL ON FUNCTION m3b_cycle_test.observed_transition(uuid,uuid),
           m3b_cycle_test.observed_legacy_context(uuid) FROM PUBLIC,anon,authenticated,service_role;""")
        modes = ['same_key_commit', 'different_keys_commit', 'first_rollback', 'reset',
                 'clock_after_wait']
        for index, (owner, mode) in enumerate(zip(owners, modes)):
            key_a, key_b = uid(3080 + index), uid(3180 + index)
            start_a = f"SELECT m3b_cycle_test.observed_transition('{owner}','{key_a}');"
            first_sql = start_a
            if mode == 'reset':
                database.query(session + start_a)
                first_sql = f"SELECT public.reset_user_conversation_atomic('{owner}',true);"
            elif mode == 'clock_after_wait':
                first_sql = f"SELECT id FROM public.users WHERE id='{owner}' FOR UPDATE;"
            first = clients.spawn(session + "BEGIN; SELECT jsonb_build_object('holder',pg_backend_pid());\n"
                                  + first_sql + "\nSELECT 'TRANSITION_READY';\n")
            lines = clients.until(first, lambda line: line == 'TRANSITION_READY')
            holder = json.loads(next(line for line in lines if line.startswith('{"holder"')))['holder']
            initial = next((json.loads(line) for line in lines if line.startswith('{"state"')), None)
            selected_key = key_b if mode == 'different_keys_commit' else key_a
            next_sql = f"SELECT m3b_cycle_test.observed_transition('{owner}','{selected_key}');"
            if mode == 'clock_after_wait':
                next_sql = f"SELECT m3b_cycle_test.observed_legacy_context('{owner}');"
            second = clients.spawn(session + "SELECT jsonb_build_object('waiter',pg_backend_pid());\n"
                                   + next_sql + '\n')
            waiter = json.loads(clients.until(second, lambda line: line.startswith('{"waiter"'))[-1])['waiter']
            blockers = exact_wait(database, second, holder, waiter)
            release = database.query("SELECT to_char(clock_timestamp() AT TIME ZONE 'UTC',"
                                     "'YYYY-MM-DD\"T\"HH24:MI:SS.US\"Z\"')")
            clients.finish(first, 'ROLLBACK;\n' if mode == 'first_rollback' else 'COMMIT;\n')
            output = clients.finish(second)
            result = next(json.loads(line) for line in output.splitlines() if line.startswith('{'))
            if mode == 'reset':
                require(result.get('error') == '40001'
                        and result.get('message') == 'mobile_reevaluation_generation_changed',
                        'Reset did not invalidate the original transition key')
            elif mode == 'clock_after_wait':
                context = result['context']
                parse = lambda value: datetime.datetime.fromisoformat(value.replace('Z', '+00:00'))
                require(parse(context['observed_at']) >= parse(release),
                        'Transition context sampled its clock before the owner wait')
                require(context['authority']['kind'] == 'legacy_transition'
                        and context['next_kind'] == 'TRANSITION_FULL', 'Waiting context lost its source')
            else:
                state = result['state']
                require(state['cycle']['kind'] == 'TRANSITION_FULL'
                        and state['clock']['base_date'] == state['clock']['due_date'],
                        'Transition was relabelled as a fortnight')
                first_id, final_id = initial['state']['cycle']['id'], state['cycle']['id']
                require((first_id != final_id) if mode == 'first_rollback' else (first_id == final_id),
                        'Concurrent cycle identity did not follow its commit outcome')
                require(database.query(f"SELECT count(*) FROM private.mobile_reevaluation_cycles WHERE user_id='{owner}'") == '1',
                        'Concurrent start created duplicate occurrences')
                expected_keys = '2' if mode == 'different_keys_commit' else '1'
                require(database.query(f"SELECT count(*) FROM private.mobile_reevaluation_start_keys WHERE user_id='{owner}'") == expected_keys,
                        'Concurrent start duplicated or lost a key')
            require(database.query(f"SELECT count(*) FROM private.mobile_signup_strength_completion_receipts WHERE user_id='{owner}'") == '0',
                    'Transition fabricated an original signup receipt')
            cases.append({'case': mode, 'status': 'PASS', 'holder_pid': holder,
                          'waiter_pid': waiter, 'exact_owner_blocker': blockers})
    finally:
        clients.close()
        database.query('BEGIN; DO $guard$ BEGIN IF EXISTS(SELECT 1 FROM public.users '
                       f"WHERE id IN({ids}) AND email NOT LIKE 'm3b-cycle-%@example.invalid') "
                       "THEN RAISE EXCEPTION 'Refuse nonfixture owner'; END IF; END $guard$;"
                       f'DELETE FROM public.users WHERE id IN({ids}); '
                       'DROP SCHEMA m3b_cycle_test CASCADE; COMMIT;')
    require(database.query(f'SELECT count(*) FROM public.users WHERE id IN({ids})') == '0',
            'Owned test owners remain')
    require(database.query("SELECT to_regnamespace('m3b_cycle_test') IS NULL") == 't', 'Fixture remains')
    exclusive_json(evidence, {'status': 'PASS', 'cases': cases, 'owned_clients_reaped': True,
                              'fixture_removed': True, 'not_proof_of_HTTP_or_FULL': True})


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--config', required=True)
    parser.add_argument('--evidence', required=True)
    args = parser.parse_args()
    run(LocalCycleDatabase(args.config), args.evidence)


if __name__ == '__main__':
    main()
