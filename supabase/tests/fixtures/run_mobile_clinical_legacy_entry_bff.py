#!/usr/bin/env python3
"""Actual entry runtime -> public service RPC -> owned SQL, all rolled back."""
import argparse
import json
import select
import shutil
import subprocess
from pathlib import Path
from run_mobile_clinical_http import literal
from run_mobile_health_hold_authority import Sessions, exclusive_json, require
from run_mobile_reevaluation_cycle import LocalCycleDatabase


def run(database, output):
    root = Path(__file__).resolve().parents[3]
    folder = Path(__file__).parent
    output = Path(output).resolve()
    require(not output.exists(), 'Evidence exists')
    clean = "SELECT NOT EXISTS(SELECT 1 FROM public.users) AND to_regnamespace('m3b_cycle_test') IS NULL AND NOT EXISTS(SELECT 1 FROM net.http_request_queue)"
    require(database.query(clean) == 't', 'Owned database not clean')
    runners = list((root / 'node_modules/.pnpm').glob('vite-node@*/node_modules/vite-node/vite-node.mjs'))
    node = shutil.which('node')
    require(node and len(runners) == 1, 'Runtime missing or ambiguous')
    signatures = {
        'get_mobile_current_clinical_state': ['p_user_id', 'p_mode', 'p_body', 'p_expected'],
        'admit_mobile_clinical_legacy_generation': ['p_user_id'],
        'get_mobile_reevaluation_cycle': ['p_user_id'],
        'start_mobile_clinical_full': ['p_user_id', 'p_operation_key', 'p_reason'],
    }
    owners = [f'b3b01000-0000-4000-8000-{n:012d}' for n in range(5100, 5105)]
    sessions, child = Sessions(database), None
    calls, result, failure, counts = 0, None, None, None
    try:
        fixture = folder / 'mobile_reevaluation_cycle_fixture.sql'
        session = sessions.spawn("BEGIN;SET LOCAL request.jwt.claims='" + '{"role":"service_role"}' + "';\n\\i '" + str(fixture) + "'\n" + '''
          CREATE TEMP TABLE original_legacy_rows(owner uuid,state jsonb);
          DO $seed$ DECLARE n integer;a uuid;BEGIN FOR n IN 5100..5104 LOOP
           a:=m3b_cycle_test.seed(n,CASE WHEN n%2=0 THEN '2026-10-01T23:00:00Z'::timestamptz END,'America/Sao_Paulo',n=5104);
           UPDATE public.user_profiles SET onboarding_completed=true,sex='masculino',birth_date='1990-01-01',height_cm=180,
            weight_kg=80,body_fat_percent=24,training_frequency=4,activity_level='moderado',hunger_level='moderada',
            current_protocol=CASE WHEN n<5102 OR n=5104 THEN 'recomposicao'::public.protocol_enum END,
            deficit_level=CASE WHEN n<5102 OR n=5104 THEN 500 END WHERE user_id=a;
           INSERT INTO public.daily_snapshots(user_id,date,calories_target,protein_target,calories_consumed,exercise_calories)
            VALUES(a,(clock_timestamp() AT TIME ZONE 'America/Sao_Paulo')::date,1700,120,333,44);
           INSERT INTO pg_temp.original_legacy_rows VALUES(a,m3b_cycle_test.original_state(a));
          END LOOP;END $seed$;
          CREATE FUNCTION pg_temp.entry_rpc(statement text) RETURNS jsonb LANGUAGE plpgsql AS $rpc$
          DECLARE data jsonb;BEGIN EXECUTE statement INTO data;RETURN jsonb_build_object('data',data,'error',NULL);
          EXCEPTION WHEN OTHERS THEN RETURN jsonb_build_object('data',NULL,'error',jsonb_build_object('code',SQLSTATE));END $rpc$;
          GRANT EXECUTE ON FUNCTION pg_temp.entry_rpc(text) TO service_role;
          SELECT 'READY';
        ''')
        sessions.until(session, lambda line: line == 'READY')
        child = subprocess.Popen([node, str(runners[0]), '--script', str(folder / 'mobile_clinical_legacy_entry_bff_bridge.ts')],
            cwd=root, env=dict(database.env, PERFORME_LEGACY_ENTRY_QA='owned-local-rollback'),
            stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        while True:
            require(select.select([child.stdout], [], [], 20)[0], 'Child timeout')
            line = child.stdout.readline(); require(line, 'Child ended before result'); packet = json.loads(line)
            if packet['type'] == 'done': result = packet; break
            require(packet['type'] == 'rpc', 'Child assertion failed')
            calls += 1; require(calls <= 40, 'RPC bound exceeded')
            name, args = packet['name'], packet['args']
            require(name in signatures and set(args) == set(signatures[name]) and args['p_user_id'] in owners, 'Scope refused')
            if name == 'get_mobile_current_clinical_state':
                require(args['p_mode'] == 'profile' and args['p_body'] is None and
                    (args['p_expected'] is None or set(args['p_expected']) == {'epoch'}), 'Current override refused')
            if name == 'start_mobile_clinical_full': require(args['p_reason'] is None, 'Reason override refused')
            statement = 'SELECT public.' + name + '(' + ','.join(literal(args[key]) for key in signatures[name]) + ')'
            sql = 'SET LOCAL ROLE service_role;SELECT pg_temp.entry_rpc(' + literal(statement) + ");RESET ROLE;\nSELECT 'REPLY';\n"
            session.stdin.write(sql.encode()); session.stdin.flush()
            rows = sessions.until(session, lambda value: value == 'REPLY')
            values = [value for value in rows if value.startswith('{')]; require(len(values) == 1, 'Unexpected SQL shape')
            child.stdin.write(values[0] + '\n'); child.stdin.flush()
        child.stdin.close(); child.wait(timeout=10)
        require(child.returncode == 0 and result['status'] == 'PASS_ACTUAL_LEGACY_ENTRY_RUNTIME_SQL' and len(result['cases']) == 15 and calls == 33, 'Bridge failed')
        sql = '''SELECT json_build_object('preserved',bool_and(o.state-ARRAY['private.workout_strength_authority_epochs',
          'private.mobile_clinical_generation_sources','private.mobile_clinical_legacy_admissions','private.mobile_clinical_start_requests']
          =m3b_cycle_test.original_state(o.owner)-ARRAY['private.workout_strength_authority_epochs',
          'private.mobile_clinical_generation_sources','private.mobile_clinical_legacy_admissions','private.mobile_clinical_start_requests']),
          'legacy',(SELECT count(*) FROM private.mobile_clinical_legacy_admissions),
          'cycles',(SELECT count(*) FROM private.mobile_reevaluation_cycles),
          'signup',(SELECT count(*) FROM private.mobile_signup_strength_completion_receipts),
          'photos',(SELECT count(*) FROM private.mobile_reevaluation_photo_assets),
          'FULL',(SELECT count(*) FROM private.mobile_clinical_full_receipts)) FROM pg_temp.original_legacy_rows o;
          SELECT 'COUNTS';
        '''
        session.stdin.write(sql.encode()); session.stdin.flush()
        rows = sessions.until(session, lambda line: line == 'COUNTS'); counts = json.loads(next(line for line in rows if line.startswith('{')))
        require(counts == {'preserved': True, 'legacy': 4, 'cycles': 5, 'signup': 1, 'photos': 0, 'FULL': 0}, 'Unexpected admission effects')
        sessions.finish(session, 'ROLLBACK;\n')
    except Exception as error:
        failure = str(error)
    finally:
        if child and child.poll() is None: child.terminate(); child.wait(timeout=5)
        if child:
            with Path(str(output) + '.child.log').open('x') as log: log.write(child.stderr.read())
        sessions.close()
    rolled_back = database.query(clean) == 't'
    evidence = {'status': 'PASS' if failure is None and rolled_back else 'FAIL', 'failure': failure,
        'bridge': result, 'rpc_calls': calls, 'counts': counts, 'guard': database.guard,
        'all_rolled_back': rolled_back, 'remote_operations': 0, 'new_paid_resources': 0,
        'Auth': False, 'deployed_HTTP': False, 'PostgREST': False, 'Storage': False}
    exclusive_json(output, evidence); require(evidence['status'] == 'PASS', 'Legacy entry QA failed; inspect evidence')
    return evidence


if __name__ == '__main__':
    parser = argparse.ArgumentParser(); parser.add_argument('--config', required=True); parser.add_argument('--output', required=True)
    args = parser.parse_args(); result = run(LocalCycleDatabase(args.config), args.output)
    print(json.dumps({'status': result['status'], 'RPCs': result['rpc_calls']}))
