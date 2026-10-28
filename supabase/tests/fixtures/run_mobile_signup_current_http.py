#!/usr/bin/env python3
"""Real signup public HTTP/adapters/owned SQL. No providers, all ROLLBACK."""
import argparse
import datetime
import json
import os
import select
import shutil
import subprocess
from pathlib import Path

from run_mobile_clinical_http import literal
from run_mobile_health_hold_authority import Sessions, exclusive_json, require, uid
from run_mobile_reevaluation_cycle import LocalCycleDatabase


def run(database, output):
    root = Path(__file__).resolve().parents[3]
    folder = Path(__file__).resolve().parent
    output = Path(output).resolve()
    require(not output.exists(), 'Evidence exists')
    clean_sql = "SELECT NOT EXISTS(SELECT 1 FROM public.users) AND to_regnamespace('m3b_cycle_test') IS NULL AND NOT EXISTS(SELECT 1 FROM net.http_request_queue)"
    require(database.query(clean_sql) == 't', 'Owned runtime not empty')
    catalogue_sql = "SELECT jsonb_build_object(" + ','.join(
        literal(table) + ",coalesce((SELECT md5(jsonb_agg(to_jsonb(x) ORDER BY " + order + ")::text) FROM public."
        + table + " x),'empty')" for table, order in (
            ('global_config', 'key'), ('onboarding_legal_documents', 'id'),
            ('onboarding_legal_requirement_sets', 'id'), ('audit_log', 'id'))) + ')'
    catalogue = database.query(catalogue_sql)
    names = ['admit_mobile_signup_health', 'get_mobile_current_clinical_state']
    signatures = json.loads(database.query("SELECT jsonb_object_agg(proname,to_jsonb(proargnames)) FROM pg_proc WHERE pronamespace='public'::regnamespace AND proname=ANY(ARRAY[" + ','.join(map(literal, names)) + '])'))
    require(set(signatures) == set(names), 'Public transport missing')
    runners = list((root / 'node_modules/.pnpm').glob('vite-node@*/node_modules/vite-node/vite-node.mjs'))
    node = shutil.which('node'); require(node and len(runners) == 1, 'Runtime missing/ambiguous')
    owner, other = uid(5801), uid(5800)
    sessions, session, child = Sessions(database), None, None
    result, witness, failure, diagnostic = None, None, None, ''
    rpc_count, resets = 0, 0
    try:
        setup = "BEGIN;SET LOCAL request.jwt.claims='" + '{"role":"service_role"}' + "';\n"
        setup += "\\i '" + str(folder / 'mobile_signup_health_fixture.sql') + "'\n"
        setup += f"""
          SELECT m3b_cycle_test.seed(5800,NULL);SELECT m3b_cycle_test.seed(5801,NULL);
          CREATE FUNCTION pg_temp.signup_http_rpc(statement text) RETURNS jsonb LANGUAGE plpgsql AS $rpc$
          DECLARE data jsonb;BEGIN EXECUTE statement INTO data;RETURN jsonb_build_object('data',data,'error',NULL);
          EXCEPTION WHEN OTHERS THEN RETURN jsonb_build_object('data',NULL,'error',jsonb_build_object('code',SQLSTATE)); END $rpc$;
          GRANT EXECUTE ON FUNCTION pg_temp.signup_http_rpc(text) TO service_role;
          SELECT 'READY';
        """
        session = sessions.spawn(setup); sessions.until(session, lambda line: line == 'READY')

        def query(sql):
            session.stdin.write((sql + "\nSELECT 'REPLY';\n").encode()); session.stdin.flush()
            lines = sessions.until(session, lambda line: line == 'REPLY')
            values = [line for line in lines if line.startswith('{')]
            require(len(values) == 1, 'Unexpected SQL cardinality')
            return json.loads(values[0])

        initial = query(f"""SELECT jsonb_build_object('owner','{owner}','other','{other}',
          'command',m3b_cycle_test.signup_health_command('{owner}',m3b_cycle_test.uid(5802),m3b_cycle_test.uid(5803)),
          'minorBirth',to_char(((clock_timestamp() AT TIME ZONE 'America/Sao_Paulo')::date-interval '17 years')::date,'YYYY-MM-DD'),
          'other_profile',(SELECT md5(to_jsonb(p)::text) FROM public.user_profiles p WHERE user_id='{other}'));""")
        child = subprocess.Popen([node, str(runners[0]), '--script', str(folder / 'mobile_signup_current_http_bridge.ts')],
            cwd=root, env=dict(database.env, PERFORME_SIGNUP_CURRENT_HTTP_QA='owned-local-rollback'),
            stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        while True:
            require(select.select([child.stdout], [], [], 20)[0], 'Child timeout')
            line = child.stdout.readline(); require(line, 'Child closed unexpectedly')
            packet = json.loads(line); kind = packet['type']
            if kind == 'result': result = packet; break
            if kind == 'init': reply = {key: initial[key] for key in ['owner', 'other', 'command', 'minorBirth']}
            elif kind == 'rpc':
                rpc_count += 1; require(rpc_count <= 12, 'RPC budget exceeded')
                name, args = packet['name'], packet['args']
                require(name in signatures and set(args) == set(signatures[name]), 'RPC signature refused')
                require(args['p_user_id'] in (owner, other), 'Owner refused')
                if name == 'admit_mobile_signup_health':
                    require(args['p_user_id'] == owner, 'Other owner write refused')
                    command = args['p_command']
                    expected = dict(initial['command'], operation_key=command['operation_key'])
                    require(command == expected and command['operation_key'] in (uid(5802), uid(5899)), 'Declaration changed')
                def arg(key):
                    value = args[key]
                    return literal(value) + ('::jsonb' if isinstance(value, dict) else '')
                call = 'SELECT public.' + name + '(' + ','.join(key + ':=' + arg(key) for key in signatures[name]) + ')'
                reply = query('SET LOCAL ROLE service_role;SELECT pg_temp.signup_http_rpc(' + literal(call) + ');RESET ROLE;')
            elif kind == 'reset':
                require(packet['owner'] == owner and resets == 0, 'Reset scope refused')
                query(f"SELECT jsonb_build_object('result',public.reset_user_conversation_atomic('{owner}',true));")
                resets += 1; reply = {'reset': True}
            else: raise ValueError('Child operation refused')
            child.stdin.write(json.dumps(reply) + '\n'); child.stdin.flush()
        child.stdin.close(); child.wait(timeout=10); diagnostic = child.stderr.read()
        require(child.returncode == 0 and result['status'] == 'PASS_PUBLIC_HTTP_LOCAL_SQL', 'Bridge terminal failed')
        require(rpc_count == 9 and resets == 1, 'Unexpected operation counts')
        witness = query(f"""SELECT jsonb_build_object(
          'signup_receipts',(SELECT count(*) FROM private.mobile_signup_health_receipts WHERE user_id='{owner}'),
          'health_receipts',(SELECT count(*) FROM private.mobile_health_risk_receipts WHERE user_id='{owner}'),
          'legal_acts',(SELECT count(*) FROM public.user_onboarding_legal_actions WHERE user_id='{owner}'),
          'other_profile',(SELECT md5(to_jsonb(p)::text) FROM public.user_profiles p WHERE user_id='{other}'),
          'no_snapshots',NOT EXISTS(SELECT 1 FROM public.daily_snapshots),
          'no_phases',(SELECT bool_and(current_protocol IS NULL AND NOT onboarding_completed) FROM public.user_profiles));""")
        require(witness['signup_receipts'] == 1 and witness['health_receipts'] == 1 and witness['legal_acts'] == 4
                and witness['other_profile'] == initial['other_profile'] and witness['no_snapshots'] and witness['no_phases'], 'Preservation/idempotency failed')
        sessions.finish(session, 'ROLLBACK;\n')
    except Exception as error: failure = str(error)
    finally:
        if child and child.poll() is None:
            child.terminate()
            try: child.wait(timeout=5)
            except subprocess.TimeoutExpired: child.kill(); child.wait(timeout=5)
        if child and child.stderr and not child.stderr.closed and not diagnostic: diagnostic = child.stderr.read()
        if session and session.poll() is not None and not session.stderr.closed:
            diagnostic += '\nSQL diagnostic:\n' + session.stderr.read().decode()[-6000:]
        sessions.close()
    clean, preserved = database.query(clean_sql) == 't', database.query(catalogue_sql) == catalogue
    with Path(str(output) + '.child.log').open('x') as stream: stream.write(diagnostic)
    receipt = {'at_utc': datetime.datetime.now(datetime.timezone.utc).isoformat(),
               'status': 'PASS' if not failure and clean and preserved else 'FAIL', 'failure': failure,
               'bridge': result, 'witness': witness, 'rpc_calls': rpc_count, 'resets': resets,
               'guard': database.guard, 'all_rolled_back': clean, 'catalogue_preserved': preserved,
               'PostgREST': False, 'remote_operations': 0, 'new_paid_resources': 0}
    exclusive_json(output, receipt)
    require(receipt['status'] == 'PASS', 'Signup current HTTP local SQL QA failed; inspect evidence')
    return receipt


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--config', required=True); parser.add_argument('--output', required=True)
    args = parser.parse_args()
    report = run(LocalCycleDatabase(args.config), args.output)
    print(json.dumps({'status': report['status'], 'RPCs': report['rpc_calls']}))
