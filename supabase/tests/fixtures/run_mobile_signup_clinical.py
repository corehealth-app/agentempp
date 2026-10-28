#!/usr/bin/env python3
"""Atomic signup clocks after actual config-lock waits. Owned local rollback only."""
import argparse
import json
import time
from pathlib import Path
from run_mobile_health_hold_authority import Sessions, exclusive_json, require
from run_mobile_reevaluation_cycle import LocalCycleDatabase


def run(database, output):
    root = Path(__file__).resolve().parents[3]
    output = Path(output).resolve()
    require(not output.exists(), 'Evidence exists')
    clean = "SELECT to_regnamespace('m3b_cycle_test') IS NULL AND NOT EXISTS(SELECT 1 FROM public.users)"
    require(database.query(clean) == 't', 'Owned runtime not empty')
    fixture = Path(__file__).with_name('mobile_signup_health_fixture.sql')
    source = (root / 'supabase/tests/mobile_signup_clinical_safety.sql').read_text()
    start = source.index('CREATE FUNCTION m3b_cycle_test.clinical_signup_submission(')
    end = source.index('\n$$;', start) + len('\n$$;')
    helper = source[start:end]
    clients = Sessions(database)
    cases = []
    try:
        for temporal_policy in (False, True):
            first = clients.spawn("BEGIN; LOCK TABLE public.global_config IN ROW EXCLUSIVE MODE;\n"
                                  "SELECT json_build_object('holder',pg_backend_pid());\nSELECT 'CONFIG_HELD';\n")
            lines = clients.until(first, lambda line: line == 'CONFIG_HELD')
            holder = json.loads(next(line for line in lines if line.startswith('{"holder"')))['holder']
            setup = "BEGIN; SET LOCAL request.jwt.claim.role='service_role';\n\\i '" + str(fixture) + "'\n" + helper + """
              SELECT m3b_cycle_test.seed(2700,NULL);
              CREATE TEMP TABLE signup_clinical_request AS SELECT m3b_cycle_test.clinical_signup_submission() s;
            """
            if temporal_policy:
                setup += """
                  INSERT INTO public.onboarding_legal_documents(id,document_key,version,locale,body,content_hash,purpose,action_type,required,effective_at)
                  VALUES(m3b_cycle_test.uid(206),'evaluation_4_sensitive_data_consent','synthetic-future-2','pt-BR','SYNTHETIC FUTURE',
                   encode(extensions.digest('SYNTHETIC FUTURE','sha256'),'hex'),'closed_evaluation_sensitive_health_data_processing',
                   'consent',true,clock_timestamp()+interval '2 seconds');
                  SELECT public.publish_onboarding_legal_document(m3b_cycle_test.uid(206));
                """
            setup += "SELECT json_build_object('waiter',pg_backend_pid(), 'future_epoch'," + (
                "(SELECT extract(epoch FROM effective_at)::text FROM public.onboarding_legal_documents WHERE id=m3b_cycle_test.uid(206))"
                if temporal_policy else 'NULL') + ");\nSELECT 'BEFORE_COMPLETE';\n"
            second = clients.spawn(setup)
            lines = clients.until(second, lambda line: line == 'BEFORE_COMPLETE')
            timing = json.loads(next(line for line in lines if line.startswith('{"waiter"')))
            sql = ("""
              DO $$ DECLARE message text; BEGIN
               BEGIN PERFORM public.complete_mobile_onboarding_atomic(m3b_cycle_test.uid(2700),(SELECT s FROM signup_clinical_request));
               EXCEPTION WHEN check_violation THEN GET STACKED DIAGNOSTICS message=MESSAGE_TEXT; END;
               IF message IS DISTINCT FROM 'onboarding_document_version_mismatch' THEN
                RAISE EXCEPTION 'stale pre-wait policy was accepted'; END IF;
               IF EXISTS(SELECT 1 FROM public.user_onboarding_legal_actions WHERE user_id=m3b_cycle_test.uid(2700))
                OR EXISTS(SELECT 1 FROM public.user_profiles WHERE user_id=m3b_cycle_test.uid(2700) AND onboarding_completed)
                THEN RAISE EXCEPTION 'stale policy left partial effects'; END IF;
              END $$;
            """ if temporal_policy else
                "SELECT public.complete_mobile_onboarding_atomic(m3b_cycle_test.uid(2700),(SELECT s FROM signup_clinical_request));\n")
            second.stdin.write((sql + "SELECT 'COMPLETION_DONE';\n").encode()); second.stdin.flush()
            deadline = time.monotonic() + 5
            while time.monotonic() < deadline:
                observed = json.loads(database.query("SELECT json_build_object('kind',wait_event_type,'blockers',pg_blocking_pids(pid)) "
                                                    f"FROM pg_stat_activity WHERE pid={int(timing['waiter'])}"))
                if observed['kind'] == 'Lock' and holder in observed['blockers']:
                    break
                require(second.poll() is None, 'Completion ended before observing contention')
                time.sleep(0.03)
            else:
                raise TimeoutError('Actual config fence not observed')
            if temporal_policy:
                due = float(timing['future_epoch'])
                while time.time() <= due + 0.03:
                    time.sleep(0.03)
            released_after = database.query("SELECT to_char(clock_timestamp() AT TIME ZONE 'UTC','YYYY-MM-DD\"T\"HH24:MI:SS.US\"Z\"')")
            clients.finish(first, 'ROLLBACK;\n')
            lines = clients.until(second, lambda line: line == 'COMPLETION_DONE')
            if not temporal_policy:
                reply = json.loads(next(line for line in lines if '"clinical_safety"' in line))
                require(reply['clinical_safety']['observed_at'] >= released_after, 'Clinical decision clock preceded config wait')
                require(reply['objective'] == 'manutencao', 'Valid original choice not recorded')
            clients.finish(second, 'ROLLBACK;\n')
            cases.append({'case': 'policy_becomes_effective_during_config_wait' if temporal_policy else 'clock_after_config_wait',
                          'status': 'PASS', 'actual_blockers': observed['blockers'], 'both_rolled_back': True,
                          'limitation': 'Config publisher table mode exercised; no config COMMIT or clinical birthday wait is claimed.'})
    finally:
        clients.close()
    require(database.query(clean) == 't', 'Owned fixture did not roll back')
    result = {'status': 'PASS', 'cases': cases, 'guard': database.guard, 'remote_operations': 0, 'new_paid_resources': 0,
              'fixtures_rolled_back': True}
    exclusive_json(output, result)
    return result


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--config', required=True)
    parser.add_argument('--output', required=True)
    args = parser.parse_args()
    print(json.dumps(run(LocalCycleDatabase(args.config), args.output)))
