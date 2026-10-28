#!/usr/bin/env python3
"""Actual catalog waits, current legal clock, all fixtures rolled back. Inert import."""
import argparse
import json
import time
from pathlib import Path

from run_mobile_health_hold_authority import Sessions, exclusive_json, require
from run_mobile_reevaluation_cycle import LocalCycleDatabase
from run_mobile_signup_health import blocked


def run(database, output):
    output = Path(output).resolve()
    require(not output.exists(), 'Evidence already exists')
    clean = "SELECT NOT EXISTS(SELECT 1 FROM public.users) AND to_regnamespace('m3b_cycle_test') IS NULL"
    require(database.query(clean) == 't', 'Owned fixture not clean')
    catalogs = "SELECT jsonb_build_object('documents',(SELECT coalesce(jsonb_agg(to_jsonb(d) ORDER BY id),'[]') FROM public.onboarding_legal_documents d),'requirements',(SELECT coalesce(jsonb_agg(to_jsonb(q) ORDER BY id),'[]') FROM public.onboarding_legal_requirement_sets q))"
    before = database.query(catalogs)
    fixture = Path(__file__).with_name('mobile_signup_health_fixture.sql')
    setup = "BEGIN;SET LOCAL request.jwt.claims='" + '{"role":"service_role"}' + "';\n\\i '" + str(fixture) + "'\n" + """
      SELECT m3b_cycle_test.seed(5400,NULL,'America/Sao_Paulo',false);
      UPDATE public.user_profiles SET onboarding_completed=true WHERE user_id=m3b_cycle_test.uid(5400);
      SELECT public.admit_mobile_clinical_legacy_generation(m3b_cycle_test.uid(5400));
      CREATE TEMP TABLE legal_command AS SELECT jsonb_build_object('version',1,'operation_key',gen_random_uuid(),
       'locale','pt-BR','document_actions',jsonb_agg(jsonb_build_object('document_key',document_key,'version',version,
        'locale',locale,'content_hash',content_hash,'action',action_type) ORDER BY document_key COLLATE "C")) c
       FROM public.onboarding_legal_documents WHERE publication_status='published' AND locale='pt-BR';
    """
    clients = Sessions(database)
    cases = []
    try:
        for table in ('onboarding_legal_documents', 'onboarding_legal_requirement_sets'):
            first = clients.spawn(setup + """
              SELECT public.accept_mobile_clinical_legacy_documents(m3b_cycle_test.uid(5400),(SELECT c FROM legal_command));
              SELECT json_build_object('holder',pg_backend_pid());SELECT 'ACCEPTED';
            """)
            lines = clients.until(first, lambda line: line == 'ACCEPTED')
            holder = json.loads(next(line for line in lines if line.startswith('{"holder"')))['holder']
            receipt = json.loads(next(line for line in lines if '"document_actions"' in line))
            require(len(receipt['receipt']['document_actions']) == 4, 'No actual accepted actions')
            require(database.query(f"SELECT EXISTS(SELECT 1 FROM pg_locks WHERE pid={int(holder)} AND relation='public.{table}'::regclass AND mode='ExclusiveLock' AND granted)") == 't', 'Exact catalog fence absent')
            second = clients.spawn("BEGIN;SELECT json_build_object('waiter',pg_backend_pid());\n"
                + f"LOCK TABLE public.{table} IN ROW EXCLUSIVE MODE;SELECT 'WRITER_READY';\n")
            rows = clients.until(second, lambda line: line.startswith('{"waiter"'))
            waiter = json.loads(rows[-1])['waiter']
            wait = blocked(database, clients, second, waiter, holder)
            clients.finish(first, 'ROLLBACK;\n')
            clients.until(second, lambda line: line == 'WRITER_READY')
            clients.finish(second, 'ROLLBACK;\n')
            cases.append({'case': 'documents_command_fences_' + table, 'status': 'PASS',
                'blockers': wait['blockers'], 'exact_ExclusiveLock': True, 'both_rolled_back': True})

        first = clients.spawn("BEGIN;LOCK TABLE public.onboarding_legal_documents IN ROW SHARE MODE;\n"
            "SELECT json_build_object('holder',pg_backend_pid());SELECT 'PUBLISHER_READY';\n")
        rows = clients.until(first, lambda line: line == 'PUBLISHER_READY')
        holder = json.loads(next(line for line in rows if line.startswith('{"holder"')))['holder']
        second = clients.spawn(setup + """
          INSERT INTO public.onboarding_legal_documents(id,document_key,version,locale,body,content_hash,purpose,action_type,required,effective_at)
          SELECT m3b_cycle_test.uid(5401),document_key,'synthetic-future-2',locale,'SYNTHETIC FUTURE',
           encode(extensions.digest('SYNTHETIC FUTURE','sha256'),'hex'),purpose,action_type,required,clock_timestamp()+interval '2 seconds'
           FROM public.onboarding_legal_documents WHERE id=m3b_cycle_test.uid(204);
          SELECT public.publish_onboarding_legal_document(m3b_cycle_test.uid(5401));
          SELECT json_build_object('waiter',pg_backend_pid(),'before_effective',clock_timestamp()<effective_at,
           'future_epoch',extract(epoch FROM effective_at)::text) FROM public.onboarding_legal_documents WHERE id=m3b_cycle_test.uid(5401);
          SELECT 'BEFORE_WAIT';
        """)
        rows = clients.until(second, lambda line: line == 'BEFORE_WAIT')
        timing = json.loads(next(line for line in rows if line.startswith('{"waiter"')))
        require(timing['before_effective'], 'Future version was not future before wait')
        second.stdin.write(b"""
          DO $$ DECLARE msg text;BEGIN
           BEGIN PERFORM public.accept_mobile_clinical_legacy_documents(m3b_cycle_test.uid(5400),(SELECT c FROM legal_command));
           EXCEPTION WHEN check_violation THEN GET STACKED DIAGNOSTICS msg=MESSAGE_TEXT;END;
           IF msg IS DISTINCT FROM 'onboarding_document_version_mismatch' THEN RAISE EXCEPTION 'Fresh post-wait policy not enforced';END IF;
           IF EXISTS(SELECT 1 FROM private.mobile_clinical_legacy_document_receipts)
            OR EXISTS(SELECT 1 FROM public.user_onboarding_legal_actions) THEN RAISE EXCEPTION 'Refusal left legal side effects';END IF;
          END $$;SELECT 'FRESH_POLICY_REFUSED';
        """)
        second.stdin.flush()
        wait = blocked(database, clients, second, timing['waiter'], holder)
        delay = float(timing['future_epoch']) - time.time() + 0.05
        require(delay < 3, 'Unexpected clock delay')
        if delay > 0:
            time.sleep(delay)
        clients.finish(first, 'ROLLBACK;\n')
        clients.until(second, lambda line: line == 'FRESH_POLICY_REFUSED')
        clients.finish(second, 'ROLLBACK;\n')
        cases.append({'case': 'new_legal_version_becomes_effective_during_actual_wait',
            'status': 'PASS', 'blockers': wait['blockers'], 'clock_after_wait': True,
            'no_partial_legal_actions_or_receipt': True, 'both_rolled_back': True})
    finally:
        clients.close()
    require(database.query(clean) == 't' and database.query(catalogs) == before, 'Fixture/catalog rollback failed')
    result = {'status': 'PASS', 'cases': cases, 'catalogs_preserved_exact': True,
        'all_rolled_back': True, 'remote_operations': 0, 'guard': database.guard}
    exclusive_json(output, result)
    return result


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--config', required=True)
    parser.add_argument('--output', required=True)
    args = parser.parse_args()
    result = run(LocalCycleDatabase(args.config), args.output)
    print(json.dumps({'status': result['status'], 'cases': len(result['cases'])}))
