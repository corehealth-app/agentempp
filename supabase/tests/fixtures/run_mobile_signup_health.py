#!/usr/bin/env python3
"""Publication fences and fresh-clock admission; owned Unix socket and verified cleanup.

Import is inert. No trigger bypass, permanent fixture, cloud or provider call.
"""
import argparse
import json
import time
from pathlib import Path

from run_mobile_health_hold_authority import Sessions, exclusive_json, require
from run_mobile_reevaluation_cycle import LocalCycleDatabase


def blocked(database, clients, process, waiter, holder):
    deadline = time.monotonic() + 5
    while time.monotonic() < deadline:
        observed = json.loads(database.query(
            "SELECT json_build_object('kind',wait_event_type,'blockers',pg_blocking_pids(pid)) "
            f'FROM pg_stat_activity WHERE pid={int(waiter)}'))
        if observed['kind'] == 'Lock' and holder in observed['blockers']:
            return observed
        require(process.poll() is None, 'Waiter unexpectedly terminated')
        time.sleep(0.03)
    raise TimeoutError('Actual catalog lock not observed')


def run(database, output):
    root = Path(__file__).resolve().parents[3]
    output = Path(output).resolve()
    require(not output.exists(), 'Evidence already exists')
    clean_sql = "SELECT to_regnamespace('m3b_cycle_test') IS NULL AND NOT EXISTS(SELECT 1 FROM public.users)"
    require(database.query(clean_sql) == 't', 'Owned runtime not clean')
    before = database.query("SELECT jsonb_build_object('documents',(SELECT coalesce(jsonb_agg(to_jsonb(d) ORDER BY id),'[]') "
                            "FROM public.onboarding_legal_documents d),'requirements',(SELECT coalesce(jsonb_agg(to_jsonb(q) ORDER BY id),'[]') "
                            "FROM public.onboarding_legal_requirement_sets q))")
    fixture = root / 'supabase/tests/fixtures/mobile_signup_health_fixture.sql'
    setup = "BEGIN; SET LOCAL request.jwt.claim.role='service_role';\n\\i '" + str(fixture) + "'\n"
    own_doc = """
      INSERT INTO public.onboarding_legal_documents(document_key,version,locale,body,content_hash,purpose,action_type,required,effective_at)
      VALUES('race_qa_notice','synthetic-race-1','pt-BR','SYNTHETIC RACE',encode(extensions.digest('SYNTHETIC RACE','sha256'),'hex'),
       'synthetic_local_notice','acknowledgement',true,clock_timestamp()-interval '1 second');
      SELECT public.publish_onboarding_legal_document(id) FROM public.onboarding_legal_documents WHERE document_key='race_qa_notice';
    """
    clients = Sessions(database)
    cases = []
    # This one minimal owner has to be visible to two independent backends to
    # exercise an actual profile row lock. No legal/health act is committed.
    row_owner = 'b3b01000-0000-4000-8000-000000002420'
    row_email = 'signup-health-row-lock-2420@example.invalid'
    row_created = False
    try:
        for catalog in ('documents', 'requirements'):
            first = clients.spawn(setup + "SELECT m3b_cycle_test.seed(2400,NULL);\n"
                "SELECT private.admit_mobile_signup_health(m3b_cycle_test.uid(2400),"
                "m3b_cycle_test.signup_health_command(m3b_cycle_test.uid(2400),m3b_cycle_test.uid(2401),m3b_cycle_test.uid(2402)));\n"
                "SELECT json_build_object('holder',pg_backend_pid());\nSELECT 'ADMITTED';\n")
            lines = clients.until(first, lambda line: line == 'ADMITTED')
            holder = json.loads(next(line for line in lines if line.startswith('{"holder"')))['holder']
            acknowledgement = json.loads(next(line for line in lines if '"health_operation_key"' in line))
            require(acknowledgement['declaration']['state']['hold_active'], 'No actual health admission')
            mutation = own_doc if catalog == 'documents' else """
              INSERT INTO public.onboarding_legal_requirement_sets(version,locale,document_keys,effective_at)
              VALUES('synthetic-race-1','pt-BR',ARRAY['race_qa_notice'],clock_timestamp()-interval '1 second');
            """ + own_doc + """
              SELECT public.publish_onboarding_legal_requirement_set(id) FROM public.onboarding_legal_requirement_sets WHERE version='synthetic-race-1';
            """
            second = clients.spawn("BEGIN; SET LOCAL request.jwt.claim.role='service_role';\n"
                "SELECT json_build_object('waiter',pg_backend_pid());\n" + mutation + "\nSELECT 'PUBLISHED';\n")
            lines = clients.until(second, lambda line: line.startswith('{"waiter"'))
            waiter = json.loads(lines[-1])['waiter']
            observed = blocked(database, clients, second, waiter, holder)
            clients.finish(first, 'ROLLBACK;\n')
            lines = clients.until(second, lambda line: line == 'PUBLISHED')
            require(any('"outcome": "published"' in line for line in lines), 'Writer did not actually publish')
            clients.finish(second, 'ROLLBACK;\n')
            cases.append({'case': 'admission_fences_' + catalog, 'status': 'PASS',
                          'holder_pid': holder, 'waiter_pid': waiter, 'blockers': observed['blockers'],
                          'actual_admission': True, 'publication_after_release': True, 'both_rolled_back': True})

        # A prior publisher's table-lock mode must finish before admission takes
        # its EXCLUSIVE fence. A future consent version becomes effective while
        # it waits: using a pre-wait clock would incorrectly accept the old hash.
        first = clients.spawn("BEGIN; LOCK TABLE public.onboarding_legal_documents IN ROW SHARE MODE;\n"
                              "SELECT json_build_object('holder',pg_backend_pid());\nSELECT 'ROW_SHARE_READY';\n")
        lines = clients.until(first, lambda line: line == 'ROW_SHARE_READY')
        holder = json.loads(next(line for line in lines if line.startswith('{"holder"')))['holder']
        second = clients.spawn(setup + """
          SELECT m3b_cycle_test.seed(2410,NULL);
          CREATE TEMP TABLE signup_health_command AS SELECT m3b_cycle_test.signup_health_command(
           m3b_cycle_test.uid(2410),m3b_cycle_test.uid(2411),m3b_cycle_test.uid(2412)) c;
          INSERT INTO public.onboarding_legal_documents(id,document_key,version,locale,body,content_hash,purpose,action_type,required,effective_at)
          VALUES(m3b_cycle_test.uid(206),'evaluation_4_sensitive_data_consent','synthetic-future-2','pt-BR','SYNTHETIC FUTURE',
           encode(extensions.digest('SYNTHETIC FUTURE','sha256'),'hex'),'closed_evaluation_sensitive_health_data_processing',
           'consent',true,clock_timestamp()+interval '2 seconds');
          SELECT public.publish_onboarding_legal_document(m3b_cycle_test.uid(206));
          SELECT json_build_object('waiter',pg_backend_pid(),
           'starts_before_effective',clock_timestamp()<(SELECT effective_at FROM public.onboarding_legal_documents WHERE id=m3b_cycle_test.uid(206)),
           'future_epoch',(SELECT extract(epoch FROM effective_at)::text FROM public.onboarding_legal_documents WHERE id=m3b_cycle_test.uid(206)));
          SELECT 'TEMPORAL_READY';
        """)
        lines = clients.until(second, lambda line: line == 'TEMPORAL_READY')
        timing = json.loads(next(line for line in lines if line.startswith('{"waiter"')))
        require(timing['starts_before_effective'], 'Future version was not future at admission start')
        second.stdin.write(b"""
          DO $$ DECLARE message text; BEGIN
           BEGIN PERFORM private.admit_mobile_signup_health(m3b_cycle_test.uid(2410),(SELECT c FROM signup_health_command));
           EXCEPTION WHEN check_violation THEN GET STACKED DIAGNOSTICS message=MESSAGE_TEXT; END;
           IF message IS DISTINCT FROM 'onboarding_document_version_mismatch' THEN
            RAISE EXCEPTION 'fresh clock did not see newly effective consent'; END IF;
           IF EXISTS(SELECT 1 FROM private.mobile_signup_health_receipts WHERE user_id=m3b_cycle_test.uid(2410))
            OR EXISTS(SELECT 1 FROM public.user_onboarding_legal_actions WHERE user_id=m3b_cycle_test.uid(2410)) THEN
            RAISE EXCEPTION 'version changed while waiting left a partial admission'; END IF;
          END $$;
          SELECT 'TEMPORAL_REFUSED';
        """)
        second.stdin.flush()
        observed = blocked(database, clients, second, timing['waiter'], holder)
        # This is only a wait deadline, not a clinical timestamp conversion.
        # PostgreSQL supplies the exact boolean above and rechecks after wait.
        due = float(timing['future_epoch'])
        while time.time() <= due + 0.03:
            time.sleep(0.03)
        clients.finish(first, 'ROLLBACK;\n')
        clients.until(second, lambda line: line == 'TEMPORAL_REFUSED')
        clients.finish(second, 'ROLLBACK;\n')
        cases.append({'case': 'prior_rowshare_and_effective_time_after_wait', 'status': 'PASS',
                      'actual_blockers': observed['blockers'], 'old_version_refused': True, 'both_rolled_back': True,
                      'limitation': 'Prior table mode reproduced; no committed publisher row/lifecycle race is claimed.'})

        database.query("BEGIN; SET LOCAL request.jwt.claim.role='service_role';"
                       "INSERT INTO public.users(id,email,locale,timezone,country,status) VALUES('" + row_owner
                       + "','" + row_email + "','pt-BR','America/Sao_Paulo','BR','active');"
                       "INSERT INTO public.user_profiles(user_id) VALUES('" + row_owner + "');"
                       "SELECT public.begin_mobile_signup_completion_intent('" + row_owner
                       + "','b3b01000-0000-4000-8000-000000002421');COMMIT;")
        row_created = True
        intent = json.loads(database.query("SELECT jsonb_build_object('id',intent_id,'key',request_key) "
                                          "FROM private.mobile_signup_completion_intents WHERE user_id='" + row_owner + "'"))
        command = {'version': 1, 'operation_key': 'b3b01000-0000-4000-8000-000000002422',
                   'intent_id': intent['id'], 'request_key': intent['key'], 'locale': 'pt-BR',
                   'document_actions': [{'document_key': 'evaluation_4_sensitive_data_consent', 'version': 'synthetic-1',
                                         'locale': 'pt-BR', 'content_hash': 'a' * 64, 'action': 'consent'}],
                   'risks': ['reduced_intake']}
        first = clients.spawn("BEGIN; SELECT user_id FROM public.user_profiles WHERE user_id='" + row_owner
                              + "' FOR UPDATE;\nSELECT 'PROFILE_LOCKED';\n")
        clients.until(first, lambda line: line == 'PROFILE_LOCKED')
        encoded = json.dumps(command).replace("'", "''")
        second = clients.spawn("BEGIN; SET LOCAL request.jwt.claim.role='service_role';\nDO $$ DECLARE refused boolean:=false; BEGIN "
            "BEGIN PERFORM private.admit_mobile_signup_health('" + row_owner + "','" + encoded + "');"
            "EXCEPTION WHEN lock_not_available THEN refused:=true; END;"
            "IF NOT refused THEN RAISE EXCEPTION 'profile contention was not refused with NOWAIT'; END IF;"
            "IF EXISTS(SELECT 1 FROM private.mobile_signup_health_receipts WHERE user_id='" + row_owner + "') "
            "OR EXISTS(SELECT 1 FROM public.user_onboarding_legal_actions WHERE user_id='" + row_owner + "') "
            "THEN RAISE EXCEPTION 'profile contention left partial admission'; END IF; END $$;\nSELECT 'PROFILE_REFUSED';\n")
        clients.until(second, lambda line: line == 'PROFILE_REFUSED')
        clients.finish(second, 'ROLLBACK;\n')
        clients.finish(first, 'ROLLBACK;\n')
        cases.append({'case': 'actual_profile_row_lock_refused_without_wait', 'status': 'PASS',
                      'sqlstate': '55P03', 'no_partial_admission': True, 'both_contenders_rolled_back': True})
    finally:
        clients.close()
        if row_created:
            database.query("DO $$ BEGIN IF EXISTS(SELECT 1 FROM public.users WHERE id='" + row_owner
                           + "' AND email IS DISTINCT FROM '" + row_email + "') "
                           "OR EXISTS(SELECT 1 FROM public.user_onboarding_legal_actions WHERE user_id='" + row_owner + "') "
                           "OR EXISTS(SELECT 1 FROM private.mobile_health_risk_receipts WHERE user_id='" + row_owner + "') "
                           "THEN RAISE EXCEPTION 'owned minimal fixture cleanup refused'; END IF;"
                           "DELETE FROM public.users WHERE id='" + row_owner + "' AND email='" + row_email + "'; END $$;")
    after = database.query("SELECT jsonb_build_object('documents',(SELECT coalesce(jsonb_agg(to_jsonb(d) ORDER BY id),'[]') "
                           "FROM public.onboarding_legal_documents d),'requirements',(SELECT coalesce(jsonb_agg(to_jsonb(q) ORDER BY id),'[]') "
                           "FROM public.onboarding_legal_requirement_sets q))")
    require(before == after and database.query(clean_sql) == 't', 'Fixture rollback did not preserve catalogs/users')
    result = {'status': 'PASS', 'cases': cases, 'catalogs_preserved_exact': True, 'fixtures_rolled_back': True,
              'minimal_row_fixture_created_deleted_verified': row_created,
              'guard': database.guard, 'remote_operations': 0, 'new_paid_resources': 0}
    exclusive_json(output, result)
    return result


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--config', required=True)
    parser.add_argument('--output', required=True)
    args = parser.parse_args()
    print(json.dumps(run(LocalCycleDatabase(args.config), args.output)))
