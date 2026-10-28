#!/usr/bin/env python3
"""Actual cleanup worker/adapter/SQL; explicit synthetic Storage port, ROLLBACK."""
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


def run(database, output):
    root = Path(__file__).resolve().parents[3]
    folder = Path(__file__).resolve().parent
    output = Path(output).resolve()
    require(not output.exists(), 'Evidence already exists')
    clean_sql = "SELECT NOT EXISTS(SELECT 1 FROM public.users) AND to_regnamespace('m3b_cycle_test') IS NULL AND NOT EXISTS(SELECT 1 FROM net.http_request_queue)"
    require(database.query(clean_sql) == 't', 'Owned runtime is not empty')
    config_sql = "SELECT jsonb_build_object(" + ','.join(
        literal(table) + ",coalesce((SELECT md5(jsonb_agg(to_jsonb(x) ORDER BY " + order + ")::text) FROM public."
        + table + " x),'empty')" for table, order in (
            ('global_config', 'key'), ('onboarding_legal_documents', 'id'),
            ('onboarding_legal_requirement_sets', 'id'), ('legal_documents', 'id'), ('audit_log', 'id'))) + ')'
    original_config = database.query(config_sql)
    runners = list((root / 'node_modules/.pnpm').glob('vite-node@*/node_modules/vite-node/vite-node.mjs'))
    node = shutil.which('node')
    require(node and len(runners) == 1, 'Runtime missing/ambiguous')
    owners = [f'b3b01000-0000-4000-8000-{n:012d}' for n in (5410, 5411, 5412)]
    signatures = {
        'claim_mobile_reevaluation_photo_cleanup_scopes': ['p_limit'],
        'prepare_mobile_reevaluation_photo_disposition': ['p_user_id', 'p_cycle_id', 'p_acceptance_id'],
        'get_mobile_reevaluation_photo_disposition_page': ['p_user_id', 'p_disposition_id', 'p_expected_sweep', 'p_expected_capability_revision', 'p_expected_after'],
        'commit_mobile_reevaluation_photo_disposition_page': ['p_user_id', 'p_disposition_id', 'p_expected_sweep', 'p_expected_capability_revision', 'p_expected_after', 'p_asset_ids'],
    }
    sessions, session, bridge = Sessions(database), None, None
    result, witness, failure, child_log = None, None, None, ''
    rpc_count, remove_count, commits = 0, 0, 0
    removed = set()
    try:
        setup = "BEGIN;SET LOCAL request.jwt.claims='" + '{"role":"service_role"}' + "';\n"
        setup += "\\i '" + str(folder / 'mobile_reevaluation_photo_cleanup_fixture.sql') + "'\n"
        setup += """
          SELECT m3b_cycle_test.cleanup_context(5410,86420);
          SELECT m3b_cycle_test.cleanup_context(5411,86410);
          SELECT m3b_cycle_test.cleanup_context(5412,0);
          SELECT m3b_cycle_test.ordinary_asset(m3b_cycle_test.uid(5410),'meal_photo');
          CREATE FUNCTION pg_temp.cleanup_rpc(statement text) RETURNS jsonb LANGUAGE plpgsql AS $rpc$
          DECLARE data jsonb;BEGIN EXECUTE statement INTO data;RETURN jsonb_build_object('data',data,'error',NULL);
          EXCEPTION WHEN OTHERS THEN RETURN jsonb_build_object('data',NULL,'error',jsonb_build_object('code',SQLSTATE)); END $rpc$;
          GRANT EXECUTE ON FUNCTION pg_temp.cleanup_rpc(text) TO service_role;
          SELECT 'READY';
        """
        session = sessions.spawn(setup)
        sessions.until(session, lambda line: line == 'READY')
        def sql_query(sql):
            session.stdin.write((sql + "\nSELECT 'REPLY';\n").encode()); session.stdin.flush()
            lines = sessions.until(session, lambda line: line == 'REPLY')
            values = [line for line in lines if line.startswith('{')]
            require(len(values) == 1, 'Unexpected SQL cardinality')
            return json.loads(values[0])
        initial = sql_query("SELECT jsonb_build_object('profiles',md5((SELECT jsonb_agg(to_jsonb(p) ORDER BY user_id)::text FROM public.user_profiles p)), 'paths',(SELECT jsonb_agg(object_path ORDER BY object_path) FROM public.media_assets WHERE reevaluation_origin_version=1));")
        valid_paths = set(initial['paths'])
        bridge = subprocess.Popen([node, str(runners[0]), '--script', str(folder / 'mobile_reevaluation_photo_cleanup_bridge.ts')],
            cwd=root, env=dict(database.env, PERFORME_PHOTO_CLEANUP_QA='owned-local-rollback'),
            stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        while True:
            require(select.select([bridge.stdout], [], [], 20)[0], 'Child response timeout')
            line = bridge.stdout.readline(); require(line, 'Child closed unexpectedly')
            packet = json.loads(line)
            if packet['type'] == 'result':
                result = packet; break
            require(packet['type'] != 'failure', 'Bridge assertion failed')
            if packet['type'] == 'rpc':
                rpc_count += 1; require(rpc_count <= 12, 'RPC budget exceeded')
                name, args = packet['name'], packet['args']
                require(name in signatures and set(args) == set(signatures[name]), 'RPC/signature refused')
                if name.startswith('claim_'):
                    require(args['p_limit'] == 1, 'Claim limit refused')
                else:
                    require(args['p_user_id'] in owners[:2], 'Owner refused')
                if name.startswith('commit_'):
                    commits += 1
                    require(args['p_user_id'] == owners[1] and len(args['p_asset_ids']) == 1, 'ACK before successful removal')
                    require(owners[1] + '/' + args['p_asset_ids'][0] + '.jpg' in removed, 'ACK path was not removed')
                def argument(key):
                    if key == 'p_asset_ids':
                        return 'ARRAY[' + ','.join(map(literal, args[key])) + ']::uuid[]'
                    return literal(args[key])
                call = 'SELECT public.' + name + '(' + ','.join(argument(k) for k in signatures[name]) + ')'
                reply = sql_query('SET LOCAL ROLE service_role;SELECT pg_temp.cleanup_rpc(' + literal(call) + ');RESET ROLE;')
            elif packet['type'] == 'remove':
                remove_count += 1; require(remove_count <= 2, 'Removal budget exceeded')
                require(packet['bucket'] == 'body-checkin-photos' and len(packet['paths']) == 1, 'Storage scope refused')
                path = packet['paths'][0]
                require(path in valid_paths and path.split('/')[0] in owners[:2], 'Unknown synthetic path')
                if path.startswith(owners[0] + '/'):
                    reply = {'data': None, 'error': {'message': 'synthetic removal failure'}}
                else:
                    removed.add(path); reply = {'data': [], 'error': None}
            else:
                raise ValueError('Child operation refused')
            bridge.stdin.write(json.dumps(reply) + '\n'); bridge.stdin.flush()
        bridge.stdin.close(); bridge.wait(timeout=10); child_log = bridge.stderr.read()
        require(bridge.returncode == 0 and result['status'] == 'PASS_LOCAL_WORKER_SQL_SYNTHETIC_STORAGE'
                and rpc_count == 8 and remove_count == 2 and commits == 1, 'Terminal counts invalid')
        witness = sql_query(f"""SELECT jsonb_build_object(
          'profiles',md5((SELECT jsonb_agg(to_jsonb(p) ORDER BY user_id)::text FROM public.user_profiles p)),
          'failed_owner_unchanged',(SELECT status='pending_upload' FROM public.media_assets WHERE user_id='{owners[0]}' AND reevaluation_origin_version=1),
          'second_owner_deleted',(SELECT status='deleted' FROM public.media_assets WHERE user_id='{owners[1]}' AND reevaluation_origin_version=1),
          'fresh_owner_unchanged',(SELECT status='pending_upload' FROM public.media_assets WHERE user_id='{owners[2]}' AND reevaluation_origin_version=1),
          'ordinary_media_unchanged',(SELECT status='uploaded' FROM public.media_assets WHERE kind='meal_photo'),
          'technical_scopes',(SELECT count(*) FROM private.mobile_reevaluation_photo_cleanup_visits));""")
        require(witness['profiles'] == initial['profiles'] and all(witness[k] is True for k in (
            'failed_owner_unchanged', 'second_owner_deleted', 'fresh_owner_unchanged', 'ordinary_media_unchanged'))
            and witness['technical_scopes'] == 2, 'Domain preservation failed')
        sessions.finish(session, 'ROLLBACK;\n')
    except Exception as error:
        failure = str(error)
    finally:
        if bridge and bridge.poll() is None:
            bridge.terminate()
            try: bridge.wait(timeout=5)
            except subprocess.TimeoutExpired: bridge.kill(); bridge.wait(timeout=5)
        if bridge and bridge.stderr and not bridge.stderr.closed and not child_log: child_log = bridge.stderr.read()
        if session and session.poll() is not None and not session.stderr.closed:
            child_log += '\nSQL diagnostic:\n' + session.stderr.read().decode()[-6000:]
        sessions.close()
    clean, preserved = database.query(clean_sql) == 't', database.query(config_sql) == original_config
    with Path(str(output) + '.child.log').open('x') as f: f.write(child_log)
    receipt = {'at_utc': datetime.datetime.now(datetime.timezone.utc).isoformat(), 'status': 'PASS' if not failure and clean and preserved else 'FAIL',
        'failure': failure, 'bridge': result, 'witness': witness, 'rpc_calls': rpc_count, 'synthetic_remove_calls': remove_count,
        'SQL_ACKs': commits, 'guard': database.guard, 'all_rolled_back': clean, 'catalogue_preserved': preserved,
        'PostgREST': False, 'Storage_provider': False, 'worker_deployed': False, 'remote_operations': 0, 'new_paid_resources': 0}
    exclusive_json(output, receipt)
    require(receipt['status'] == 'PASS', 'Cleanup worker local SQL QA failed; inspect evidence')
    return receipt


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--config', required=True); parser.add_argument('--output', required=True)
    args = parser.parse_args()
    report = run(LocalCycleDatabase(args.config), args.output)
    print(json.dumps({'status': report['status'], 'RPCs': report['rpc_calls'], 'synthetic_removes': report['synthetic_remove_calls']}))
