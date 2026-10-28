#!/usr/bin/env python3
"""Actual photo HTTP factories/adapters/SQL. Synthetic media ports, ROLLBACK only."""
import argparse
import datetime
import json
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
            ('onboarding_legal_requirement_sets', 'id'), ('legal_documents', 'id'), ('audit_log', 'id'))) + ')'
    catalogue = database.query(catalogue_sql)
    names = ['get_mobile_reevaluation_photo_consent', 'accept_mobile_reevaluation_photo_consent',
             'create_mobile_reevaluation_photo_asset', 'prepare_mobile_reevaluation_photo_upload',
             'register_mobile_reevaluation_photo_upload_ticket', 'get_mobile_reevaluation_photo_asset',
             'get_mobile_reevaluation_photo_upload_completion', 'complete_mobile_reevaluation_photo_upload',
             'claim_mobile_reevaluation_photo_processing', 'authorize_mobile_reevaluation_photo_provider',
             'complete_mobile_reevaluation_photo_processing', 'fail_mobile_reevaluation_photo_processing',
             'get_mobile_reevaluation_photo_snapshot', 'discard_mobile_reevaluation_photos',
             'prepare_mobile_reevaluation_photo_disposition', 'get_mobile_reevaluation_photo_disposition_page',
             'commit_mobile_reevaluation_photo_disposition_page']
    signatures = json.loads(database.query("SELECT jsonb_object_agg(proname,to_jsonb(proargnames)) FROM pg_proc WHERE pronamespace='public'::regnamespace AND proname=ANY(ARRAY[" + ','.join(map(literal, names)) + '])'))
    require(set(signatures) == set(names), 'RPC inventory missing')
    runners = list((root / 'node_modules/.pnpm').glob('vite-node@*/node_modules/vite-node/vite-node.mjs'))
    node = shutil.which('node'); require(node and len(runners) == 1, 'Runtime missing/ambiguous')
    owner, other = uid(5701), uid(5700)
    sessions, session, child = Sessions(database), None, None
    result, witness, failure, diagnostic = None, None, None, ''
    rpc_count, puts, analyses, removals, acks, document_changes = 0, 0, 0, 0, 0, 0
    document_change_active = False
    uploaded, removed = set(), set()
    try:
        setup = "BEGIN;SET LOCAL request.jwt.claims='" + '{"role":"service_role"}' + "';\n"
        setup += "\\i '" + str(folder / 'mobile_reevaluation_photo_cleanup_fixture.sql') + "'\n"
        setup += f"""
          SELECT m3b_cycle_test.cleanup_context(5700,0);
          SELECT m3b_cycle_test.seed(5701,'2026-10-01T23:00:00Z');
          SELECT public.start_mobile_reevaluation_cycle('{owner}',m3b_cycle_test.uid(5702));
          CREATE FUNCTION pg_temp.photo_http_rpc(statement text) RETURNS jsonb LANGUAGE plpgsql AS $rpc$
          DECLARE data jsonb;BEGIN EXECUTE statement INTO data;RETURN jsonb_build_object('data',data,'error',NULL);
          EXCEPTION WHEN OTHERS THEN RETURN jsonb_build_object('data',NULL,'error',jsonb_build_object('code',SQLSTATE)); END $rpc$;
          GRANT EXECUTE ON FUNCTION pg_temp.photo_http_rpc(text) TO service_role;
          SELECT 'READY';
        """
        session = sessions.spawn(setup); sessions.until(session, lambda line: line == 'READY')

        def query(sql):
            session.stdin.write((sql + "\nSELECT 'REPLY';\n").encode()); session.stdin.flush()
            lines = sessions.until(session, lambda line: line == 'REPLY')
            values = [line for line in lines if line.startswith('{')]
            require(len(values) == 1, 'Unexpected SQL cardinality')
            return json.loads(values[0])

        initial = query(f"SELECT jsonb_build_object('owner','{owner}','cycle',(SELECT cycle_id FROM private.mobile_reevaluation_cycles WHERE user_id='{owner}'),'profiles',(SELECT md5(jsonb_agg(to_jsonb(p) ORDER BY user_id)::text) FROM public.user_profiles p),'other_asset',(SELECT id FROM public.media_assets WHERE user_id='{other}'));" )
        child = subprocess.Popen([node, str(runners[0]), '--script', str(folder / 'mobile_reevaluation_photo_http_bridge.ts')],
            cwd=root, env=dict(database.env, PERFORME_PHOTO_HTTP_QA='owned-local-rollback'),
            stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        while True:
            require(select.select([child.stdout], [], [], 20)[0], 'Child timeout')
            line = child.stdout.readline(); require(line, 'Child closed unexpectedly')
            packet = json.loads(line); kind = packet['type']
            if kind == 'result': result = packet; break
            require(kind != 'failure', 'Bridge assertion failed')
            if kind == 'init':
                reply = {'owner': owner, 'cycle': initial['cycle']}
            elif kind == 'rpc':
                rpc_count += 1; require(rpc_count <= 50, 'RPC budget exceeded')
                name, args = packet['name'], packet['args']
                require(name in signatures and set(args) == set(signatures[name]), 'RPC signature refused')
                require(args['p_user_id'] == owner, 'Owner refused')
                if 'p_cycle_id' in args: require(args['p_cycle_id'] == initial['cycle'], 'Cycle refused')
                if name == 'commit_mobile_reevaluation_photo_disposition_page':
                    paths = {owner + '/' + asset + '.jpg' for asset in args['p_asset_ids']}
                    require(paths and paths.issubset(removed), 'ACK before exact successful removal'); acks += 1
                def arg(key):
                    value = args[key]
                    if key == 'p_asset_ids': return 'ARRAY[' + ','.join(map(literal, value)) + ']::uuid[]'
                    return literal(value) + ('::jsonb' if isinstance(value, dict) else '')
                call = 'SELECT public.' + name + '(' + ','.join(key + ':=' + arg(key) for key in signatures[name]) + ')'
                reply = query('SET LOCAL ROLE service_role;SELECT pg_temp.photo_http_rpc(' + literal(call) + ');RESET ROLE;')
            elif kind == 'put':
                path = packet['path']; require(path.startswith(owner + '/') and path not in uploaded, 'PUT scope refused')
                fence = query("SELECT jsonb_build_object('registered',EXISTS(SELECT 1 FROM private.mobile_reevaluation_photo_upload_tickets t JOIN public.media_assets m ON m.id=t.asset_id WHERE m.object_path=" + literal(path) + " AND t.provider_expires_at>clock_timestamp() AND t.registered_at IS NOT NULL));")
                require(fence['registered'] is True, 'PUT capability released before persisted expiry')
                uploaded.add(path); puts += 1; reply = {'ok': True}
            elif kind == 'analyze':
                require(packet['pose'] in ('front', 'side', 'back'), 'AI pose refused')
                fence = query(f"SELECT jsonb_build_object('authorized',(SELECT count(*)=1 FROM private.mobile_reevaluation_photo_processing_attempts WHERE user_id='{owner}' AND pose=" + literal(packet['pose']) + " AND status='authorized' AND provider_authorized_until>clock_timestamp()));")
                require(fence['authorized'] is True, 'AI before current authority fence')
                analyses += 1; require(analyses <= 3, 'Duplicate AI invocation'); reply = {'ok': True}
            elif kind == 'remove':
                paths = set(packet['paths'])
                require(packet['bucket'] == 'body-checkin-photos' and paths == uploaded and not removed, 'Removal scope refused')
                removed.update(paths); removals += 1; reply = {'data': [], 'error': None}
            elif kind == 'change_document':
                require(document_changes == 0 and not document_change_active, 'Duplicate document experiment')
                reply = query("""SAVEPOINT current_document_experiment;WITH d AS (
                  INSERT INTO public.legal_documents(id,document_key,version,locale,body,required_from)
                  VALUES(m3b_cycle_test.uid(5790),'body_photo_reevaluation_consent','http-new-1','pt-BR','SYNTHETIC CHANGED POLICY',clock_timestamp()) RETURNING *),
                  p AS (INSERT INTO private.mobile_reevaluation_photo_policies(document_id,document_key,version,locale,body_hash,idle_timeout_seconds,enabled)
                  SELECT id,document_key,version,locale,body_hash,86400,true FROM d RETURNING document_id)
                  SELECT jsonb_build_object('changed',(SELECT count(*)=1 FROM p));""")
                require(reply['changed'] is True, 'Document change failed')
                document_changes += 1; document_change_active = True
            elif kind == 'restore_document':
                require(document_changes == 1 and document_change_active, 'No owned document experiment')
                reply = query("ROLLBACK TO SAVEPOINT current_document_experiment;RELEASE SAVEPOINT current_document_experiment;SELECT jsonb_build_object('restored',NOT EXISTS(SELECT 1 FROM public.legal_documents WHERE id=m3b_cycle_test.uid(5790)));" )
                require(reply['restored'] is True, 'Document experiment not restored')
                document_change_active = False
            else: raise ValueError('Child operation refused')
            child.stdin.write(json.dumps(reply) + '\n'); child.stdin.flush()
        child.stdin.close(); child.wait(timeout=10); diagnostic = child.stderr.read()
        require(child.returncode == 0 and result['status'] == 'PASS_LOCAL_HTTP_SQL_SYNTHETIC_MEDIA', 'Bridge terminal failed')
        require(puts == 3 and analyses == 3 and removals == 1 and acks == 1
                and document_changes == 1 and not document_change_active, 'Media/experiment counts failed')
        witness = query(f"""SELECT jsonb_build_object(
          'profiles',(SELECT md5(jsonb_agg(to_jsonb(p) ORDER BY user_id)::text) FROM public.user_profiles p),
          'revision',(SELECT revision::text FROM private.mobile_reevaluation_cycles WHERE user_id='{owner}'),
          'assets_deleted',(SELECT count(*)=3 AND bool_and(status='deleted') FROM public.media_assets WHERE user_id='{owner}'),
          'other_unchanged',(SELECT status='pending_upload' FROM public.media_assets WHERE id='{initial['other_asset']}'),
          'waiting',(SELECT sweep_state='waiting' FROM private.mobile_reevaluation_photo_dispositions WHERE user_id='{owner}'),
          'successful_attempts',(SELECT count(*) FROM private.mobile_reevaluation_photo_processing_attempts WHERE user_id='{owner}' AND status='succeeded'));
        """)
        require(witness['profiles'] == initial['profiles'] and witness['revision'] == '6'
                and witness['assets_deleted'] and witness['other_unchanged'] and witness['waiting']
                and witness['successful_attempts'] == 3, 'Domain preservation failed')
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
    receipt = {'at_utc': datetime.datetime.now(datetime.timezone.utc).isoformat(), 'status': 'PASS' if not failure and clean and preserved else 'FAIL',
               'failure': failure, 'bridge': result, 'witness': witness, 'rpc_calls': rpc_count,
               'synthetic_puts': puts, 'synthetic_analyses': analyses, 'synthetic_removals': removals, 'SQL_ACKs': acks,
               'current_document_precedes_replay_on_live_cycle': document_changes == 1 and not document_change_active,
               'guard': database.guard, 'all_rolled_back': clean, 'catalogue_preserved': preserved,
               'PostgREST': False, 'Storage_provider': False, 'provider_AI': False,
               'remote_operations': 0, 'new_paid_resources': 0}
    exclusive_json(output, receipt)
    require(receipt['status'] == 'PASS', 'Photo HTTP local SQL QA failed; inspect evidence')
    return receipt


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--config', required=True); parser.add_argument('--output', required=True)
    args = parser.parse_args()
    report = run(LocalCycleDatabase(args.config), args.output)
    print(json.dumps({'status': report['status'], 'RPCs': report['rpc_calls'], 'poses': report['synthetic_puts']}))
