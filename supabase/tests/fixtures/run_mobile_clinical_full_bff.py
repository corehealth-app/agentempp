#!/usr/bin/env python3
"""Actual REGULAR evaluator/adapter/SQL in one owned ROLLBACK session."""
import argparse
import datetime
import json
import select
import shutil
import subprocess
from pathlib import Path

from run_mobile_clinical_http import literal
from run_mobile_health_hold_authority import Sessions, exclusive_json, require
from run_mobile_reevaluation_cycle import LocalCycleDatabase


def run(database, output, scenario="regular", entry_phase="recomposicao"):
    require(entry_phase in ("recomposicao","ganho_massa","manutencao") and (entry_phase=="recomposicao" or scenario=="legacy_unassigned"), "Entry phase/scenario refused")
    require(scenario in ("regular", "legacy_transition", "legacy_unassigned"), "Unsupported explicit scenario")
    root = Path(__file__).resolve().parents[3]
    folder = Path(__file__).resolve().parent
    output = Path(output).resolve()
    require(not output.exists(), 'Evidence already exists')
    clean_sql = "SELECT NOT EXISTS(SELECT 1 FROM public.users) AND to_regnamespace('m3b_cycle_test') IS NULL AND NOT EXISTS(SELECT 1 FROM net.http_request_queue)"
    require(database.query(clean_sql) == 't', 'Owned database not empty')
    config_sql = "SELECT jsonb_build_object(" + ','.join(
        literal(table) + ",coalesce((SELECT md5(jsonb_agg(to_jsonb(x) ORDER BY " + order + ")::text) FROM public."
        + table + " x),'empty')" for table, order in (
            ('global_config', 'key'), ('onboarding_legal_documents', 'id'),
            ('onboarding_legal_requirement_sets', 'id'), ('audit_log', 'id'))) + ')' 
    original_config = database.query(config_sql)
    runners = list((root / 'node_modules/.pnpm').glob('vite-node@*/node_modules/vite-node/vite-node.mjs'))
    node = shutil.which('node')
    require(node and len(runners) == 1, 'Runtime missing/ambiguous')
    a, b = 'b3b01000-0000-4000-8000-000000004200', 'b3b01000-0000-4000-8000-000000004201'
    signatures = {
        'get_mobile_current_clinical_state': ['p_user_id','p_mode','p_body','p_expected'],
        'get_mobile_reevaluation_cycle': ['p_user_id'],
        'start_mobile_clinical_full': ['p_user_id', 'p_operation_key', 'p_reason'],
        'get_mobile_clinical_full_context': ['p_user_id', 'p_kind', 'p_cycle_id'],
        'get_mobile_clinical_full_command': ['p_user_id', 'p_preview_id', 'p_prepare_operation_key'],
        'prepare_mobile_clinical_full_command': ['p_user_id', 'p_kind', 'p_cycle_id', 'p_operation_key', 'p_context_hash', 'p_command', 'p_form', 'p_intent', 'p_proposal'],
        'prepare_mobile_clinical_full_presented_command': ['p_user_id', 'p_kind', 'p_cycle_id', 'p_operation_key', 'p_context_hash', 'p_command', 'p_form', 'p_intent', 'p_proposal', 'p_presentation'],
        'declare_mobile_health_risk': ['p_user_id', 'p_operation_key', 'p_items'],
        'get_mobile_clinical_full_command_receipt': ['p_user_id', 'p_preview_id', 'p_operation_key'],
        'confirm_mobile_clinical_full_command': ['p_user_id', 'p_preview_id', 'p_operation_key', 'p_command', 'p_form', 'p_intent', 'p_proposal'],
    }
    sessions, bridge, session = Sessions(database), None, None
    result, failure, child_log = None, None, ''
    rpc_count, resets = 0, 0
    last_type = None
    try:
        fixture_name = 'mobile_clinical_legacy_transition_fixture.sql' if scenario != 'regular' else 'mobile_clinical_full_fixture.sql'
        seed_call = ('m3b_cycle_test.process_clinical_photos(m3b_cycle_test.legacy_photo_context(4200,' + ('false' if scenario == 'legacy_unassigned' else 'true') + ',false))') if scenario != 'regular' else 'm3b_cycle_test.clinical_photos(4200)'
        if scenario=='legacy_unassigned' and entry_phase!='recomposicao':
            seed_call='m3b_cycle_test.process_clinical_photos(m3b_cycle_test.legacy_photo_context(4200,false,false),18,0)'
        phase_for_day = 'NULL' if scenario == 'legacy_unassigned' else "'recomposicao'"
        session = sessions.spawn("BEGIN;SET LOCAL request.jwt.claim='{}';\n".format('{"role":"service_role"}') +
            "\\i '" + str(folder / fixture_name) + "'\n" + f"""
          SELECT {seed_call};
          INSERT INTO public.daily_snapshots(user_id,date,calories_target,protein_target,current_protocol)
          VALUES('{a}',(clock_timestamp() AT TIME ZONE 'America/Sao_Paulo')::date,1700,120,{phase_for_day});
          CREATE FUNCTION pg_temp.full_rpc(statement text) RETURNS jsonb LANGUAGE plpgsql AS $rpc$
          DECLARE data jsonb;BEGIN EXECUTE statement INTO data;RETURN jsonb_build_object('data',data,'error',NULL);
          EXCEPTION WHEN OTHERS THEN RETURN jsonb_build_object('data',NULL,'error',jsonb_build_object('code',SQLSTATE)); END $rpc$;
          GRANT EXECUTE ON FUNCTION pg_temp.full_rpc(text) TO service_role;
          SELECT 'READY';
        """)
        sessions.until(session, lambda line: line == 'READY')
        bridge = subprocess.Popen([node, str(runners[0]), '--script', str(folder / 'mobile_clinical_full_bff_bridge.ts')],
            cwd=root, env=dict(database.env, PERFORME_CLINICAL_FULL_QA='owned-local-rollback', PERFORME_CLINICAL_FULL_SCENARIO=scenario, PERFORME_CLINICAL_FULL_ENTRY_PHASE=entry_phase),
            stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        while True:
            require(select.select([bridge.stdout], [], [], 20)[0], 'Child response timeout')
            line = bridge.stdout.readline();require(line, 'Child closed unexpectedly')
            packet = json.loads(line);last_type = packet.get('type')
            if packet['type'] == 'result':
                result = packet;break
            require(packet['type'] != 'failure', 'Bridge assertion failed; inspect log')
            if packet['type'] == 'scope':
                sql = f"SELECT jsonb_build_object('user','{a}','cycle',(SELECT cycle_id FROM private.mobile_reevaluation_cycles WHERE user_id='{a}' AND status IN('open','collecting','review_ready')));"
            elif packet['type'] == 'rpc':
                rpc_count += 1;require(rpc_count <= 38, 'RPC budget exceeded')
                name, args = packet['name'], packet['args']
                require(name in signatures and set(args) == set(signatures[name]), 'RPC/signature refused')
                require(args['p_user_id'] == a or (name == 'get_mobile_clinical_full_command_receipt' and args['p_user_id'] == b), 'Owner refused')
                if name == 'get_mobile_current_clinical_state':
                    require(args == {'p_user_id':a,'p_mode':'profile','p_body':None,'p_expected':None}, 'Current capture must be an actual observation only')
                def argument(k):
                    if name == 'declare_mobile_health_risk' and k == 'p_items':
                        require(isinstance(args[k], list) and args[k] == ['reduced_intake'], 'Health QA array refused')
                        return 'ARRAY[' + ','.join(map(literal, args[k])) + ']::text[]'
                    return literal(args[k])
                call = 'SELECT public.' + name + '(' + ','.join(argument(k) for k in signatures[name]) + ')'
                sql = 'SET LOCAL ROLE service_role;SELECT pg_temp.full_rpc(' + literal(call) + ');RESET ROLE;'
            elif packet['type'] == 'phase_witness':
                require(scenario == 'legacy_unassigned', 'Phase witness scenario refused')
                sql = f"""SELECT jsonb_build_object('clinical',md5(jsonb_build_object(
                  'profile',(SELECT to_jsonb(p) FROM public.user_profiles p WHERE user_id='{a}'),
                  'day',(SELECT jsonb_agg(to_jsonb(d) ORDER BY date) FROM public.daily_snapshots d WHERE user_id='{a}'),
                  'measurements',(SELECT jsonb_agg(to_jsonb(w) ORDER BY id) FROM private.mobile_weight_measurements w WHERE user_id='{a}'))::text),
                  'phase',(SELECT current_protocol FROM public.user_profiles WHERE user_id='{a}'),
                  'old_marker_null',(SELECT onboarding_completed_at IS NULL FROM public.user_profiles WHERE user_id='{a}'),
                  'signup_count',(SELECT count(*) FROM private.mobile_signup_strength_completion_receipts WHERE user_id='{a}'),
                  'first_phase_count',(SELECT count(*) FROM private.mobile_clinical_first_phase_confirmations WHERE user_id='{a}'),
                  'FULL_count',(SELECT count(*) FROM private.mobile_clinical_full_receipts WHERE user_id='{a}'),
                  'episode',(SELECT jsonb_build_object('source_review',review_id IS NOT NULL,'source_first_phase',first_phase_id IS NOT NULL,
                    'origin',entry_origin,'difficulty',difficulty_count,'ledger',ledger_steps) FROM private.mobile_clinical_episode_events WHERE user_id='{a}' ORDER BY event_no DESC LIMIT 1));"""
            elif packet['type'] == 'reset':
                resets += 1;require(resets == 1, 'Reset already consumed')
                sql = f"DO $reset$ BEGIN PERFORM public.reset_user_conversation_atomic('{a}',true);END $reset$;SELECT '{{\"reset\":true}}'::jsonb;"
            elif packet['type'] == 'witness':
                sql = f"""SELECT jsonb_build_object('effects',md5(jsonb_build_object(
                  'rows',m3b_cycle_test.original_state('{a}')-'private.mobile_clinical_confirmation_keys',
                  'commands',(SELECT jsonb_agg(to_jsonb(c) ORDER BY preview_id) FROM private.mobile_clinical_full_commands c WHERE user_id='{a}'),
                  'cycles',(SELECT jsonb_agg(to_jsonb(c) ORDER BY cycle_id) FROM private.mobile_reevaluation_cycles c WHERE user_id='{a}'),
                  'start_keys',(SELECT jsonb_agg(to_jsonb(k) ORDER BY to_jsonb(k)::text) FROM private.mobile_reevaluation_start_keys k WHERE user_id='{a}'))::text),
                  'keys',(SELECT jsonb_agg(to_jsonb(k) ORDER BY operation_key) FROM private.mobile_clinical_confirmation_keys k WHERE user_id='{a}'));"""
            else:
                raise ValueError('Child operation refused')
            session.stdin.write((sql + "\nSELECT 'REPLY';\n").encode());session.stdin.flush()
            lines = sessions.until(session, lambda line: line == 'REPLY')
            values = [line for line in lines if line.startswith(('{', '"'))]
            require(len(values) == 1, 'Unexpected SQL response cardinality')
            bridge.stdin.write(values[0] + '\n');bridge.stdin.flush()
        bridge.stdin.close();bridge.wait(timeout=10);child_log = bridge.stderr.read()
        require(bridge.returncode == 0 and result['status'] == 'PASS_AUTHENTICATED_FULL_COMMAND_SERVICE_SQL'
                and len(result['cases']) == 21 and resets == 1, 'Bridge terminal status invalid')
        sessions.finish(session, 'ROLLBACK;\n')
    except Exception as error:
        failure = str(error)
        with Path(str(output) + '.failure.log').open('x') as stream:
            stream.write(json.dumps({'failure': failure, 'last_type': last_type, 'RPCs': rpc_count, 'resets': resets}))
    finally:
        if bridge and bridge.poll() is None:
            bridge.terminate()
            try:
                bridge.wait(timeout=5)
            except subprocess.TimeoutExpired:
                bridge.kill();bridge.wait(timeout=5)
        if bridge and bridge.stderr and not bridge.stderr.closed and not child_log:
            child_log = bridge.stderr.read()
        if session and session.poll() is not None and not session.stderr.closed:
            child_log += '\nSQL diagnostic:\n' + session.stderr.read().decode()[-8000:]
        sessions.close()
    clean = database.query(clean_sql) == 't'
    preserved = database.query(config_sql) == original_config
    with Path(str(output) + '.child.log').open('x') as stream:
        stream.write(child_log)
    receipt = {'at_utc': datetime.datetime.now(datetime.timezone.utc).isoformat(),
        'status': 'PASS' if not failure and clean and preserved else 'FAIL',
        'failure': failure, 'bridge': result, 'rpc_calls': rpc_count, 'actual_synthetic_reset': resets,
        'guard': database.guard, 'all_rolled_back': clean, 'config_preserved': preserved,
        'actual_calculator_kinds': ['TRANSITION_FULL' if scenario != 'regular' else 'REGULAR', 'ROUTINE_REVIEW'], 'entry_phase':entry_phase, 'other_phase_SQL_QA': entry_phase!='recomposicao', 'deployed_HTTP': False, 'PostgREST': False,
        'Storage': False, 'remote_operations': 0, 'new_paid_resources': 0}
    exclusive_json(output, receipt)
    require(receipt['status'] == 'PASS', 'Actual FULL adapter local QA failed; inspect evidence')
    return receipt


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--config', required=True);parser.add_argument('--output', required=True)
    parser.add_argument('--scenario', choices=['regular','legacy_transition','legacy_unassigned'], default='regular')
    parser.add_argument('--entry-phase',choices=['recomposicao','ganho_massa','manutencao'],default='recomposicao')
    args = parser.parse_args()
    report = run(LocalCycleDatabase(args.config), args.output, args.scenario, args.entry_phase)
    print(json.dumps({'status': report['status'], 'RPCs': report['rpc_calls']}))
