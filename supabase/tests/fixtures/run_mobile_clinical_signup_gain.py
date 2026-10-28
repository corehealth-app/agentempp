#!/usr/bin/env python3
"""Actual app signup/config publication lock, task-owned local socket only.

Both clients roll back. Fixture DDL/legal/account writes stay in the holder's
transaction, so no trigger bypass or persistent fixture cleanup is needed.
Importing this module is inert.
"""
import argparse
import json
import time
from pathlib import Path

from run_mobile_health_hold_authority import Sessions, exclusive_json, require
from run_mobile_reevaluation_cycle import LocalCycleDatabase


def run(database, output):
    root = Path(__file__).resolve().parents[3]
    output = Path(output).resolve()
    require(not output.exists(), 'Evidence already exists')
    require(database.query("SELECT to_regnamespace('m3b_cycle_test') IS NULL AND "
                           "NOT EXISTS(SELECT 1 FROM public.users)") == 't', 'Owned runtime not clean')
    source = (root / 'supabase/tests/mobile_clinical_signup_gain.sql').read_text()
    helper_start = source.index('CREATE FUNCTION m3b_cycle_test.signup_gain_submission(')
    helper_end = source.index('\n$$;', helper_start) + len('\n$$;')
    helper = source[helper_start:helper_end]
    setup_start = source.index('DO $$')
    setup_end = source.index('\n FOREACH path', setup_start)
    setup = source[setup_start:setup_end] + '\nEND $$;'
    fixture = root / 'supabase/tests/fixtures/mobile_reevaluation_cycle_fixture.sql'
    before = database.query('SELECT jsonb_agg(to_jsonb(c) ORDER BY key) FROM public.global_config c')
    clients = Sessions(database)
    cases = []
    try:
        for mode in ('update_cut', 'insert_new_config'):
            first = clients.spawn("BEGIN; SET LOCAL request.jwt.claim.role='service_role';\n"
                                  + "\\i '" + str(fixture) + "'\n" + helper + '\n' + setup
                                  + "\nSELECT m3b_cycle_test.seed(2200,NULL);"
                                  + "\nSELECT public.complete_mobile_onboarding_atomic("
                                  + "m3b_cycle_test.uid(2200),m3b_cycle_test.signup_gain_submission());"
                                  + "\nSELECT json_build_object('holder',pg_backend_pid());\nSELECT 'GAIN_READY';\n")
            lines = clients.until(first, lambda line: line == 'GAIN_READY')
            holder = json.loads(next(line for line in lines if line.startswith('{"holder"')))['holder']
            completion = json.loads(next(line for line in lines if '"onboarding_completed"' in line))
            require(completion['objective'] == 'ganho_massa', 'Holder did not actually complete valid signup')
            mutation = ("UPDATE public.global_config SET value='4' WHERE key='calc.training_min';"
                        if mode == 'update_cut' else
                        "INSERT INTO public.global_config(key,value) VALUES('calc.synthetic_signup_gain_r237','1');")
            second = clients.spawn("BEGIN; SELECT json_build_object('waiter',pg_backend_pid());\n"
                                   + mutation + "\nSELECT 'CONFIG_READY';\n")
            lines = clients.until(second, lambda line: line.startswith('{"waiter"'))
            waiter = json.loads(lines[-1])['waiter']
            deadline = time.monotonic() + 5
            while time.monotonic() < deadline:
                observed = json.loads(database.query(
                    "SELECT json_build_object('kind',wait_event_type,'blockers',pg_blocking_pids(pid)) "
                    f'FROM pg_stat_activity WHERE pid={int(waiter)}'))
                if observed['kind'] == 'Lock' and holder in observed['blockers']:
                    break
                require(second.poll() is None, 'Config writer unexpectedly finished before signup transaction')
                time.sleep(0.05)
            else:
                raise TimeoutError('Actual config publication lock was not observed')
            clients.finish(first, 'ROLLBACK;\n')
            clients.until(second, lambda line: line == 'CONFIG_READY')
            clients.finish(second, 'ROLLBACK;\n')
            cases.append({'case': mode, 'status': 'PASS', 'actual_signup_completed': True,
                          'holder_pid': holder, 'waiting_pid': waiter,
                          'observed_blockers': observed['blockers']})
    finally:
        clients.close()
    after = database.query('SELECT jsonb_agg(to_jsonb(c) ORDER BY key) FROM public.global_config c')
    clean = database.query("SELECT to_regnamespace('m3b_cycle_test') IS NULL AND "
                           "NOT EXISTS(SELECT 1 FROM public.users) AND "
                           "NOT EXISTS(SELECT 1 FROM public.onboarding_legal_documents WHERE document_key='m3b_gain_test')") == 't'
    require(before == after and clean, 'Rollback did not preserve exact config/fixture state')
    result = {'status': 'PASS', 'cases': cases, 'config_preserved_exact': True,
              'fixtures_rolled_back': clean, 'guard': database.guard,
              'remote_operations': 0, 'provider_operations': 0, 'new_paid_resources': 0}
    exclusive_json(output, result)
    return result


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--config', required=True)
    parser.add_argument('--output', required=True)
    args = parser.parse_args()
    print(json.dumps(run(LocalCycleDatabase(args.config), args.output)))
