#!/usr/bin/env python3
"""Actual current BFF -> private owned SQL, one rollback connection. Import inert."""
import argparse
import json
import select
import shutil
import subprocess
from pathlib import Path
from run_mobile_health_hold_authority import Sessions, exclusive_json, require
from run_mobile_reevaluation_cycle import LocalCycleDatabase


def run(database, output, transport='private', consumer='capture'):
    require(transport in ('private', 'public-rpc'), 'Unknown transport')
    require(consumer in ('capture', 'read-model') and (consumer != 'read-model' or transport == 'public-rpc'), 'Unknown consumer scope')
    capture_limit = 7 if consumer == 'read-model' else 3
    root = Path(__file__).resolve().parents[3]
    output = Path(output).resolve()
    require(not output.exists(), 'Evidence exists')
    clean = "SELECT NOT EXISTS(SELECT 1 FROM public.users) AND to_regnamespace('m3b_cycle_test') IS NULL"
    require(database.query(clean) == 't', 'Owned runtime not empty')
    fixture = Path(__file__).with_name('mobile_clinical_no_plan_fixture.sql')
    runners = list((root / 'node_modules/.pnpm').glob('vite-node@*/node_modules/vite-node/vite-node.mjs'))
    node = shutil.which('node')
    require(node and len(runners) == 1, 'Runtime missing or ambiguous')
    clients, bridge = Sessions(database), None
    owners = ['b3b01000-0000-4000-8000-000000002910', 'b3b01000-0000-4000-8000-000000002911']
    literal = lambda v: "'" + (json.dumps(v) if not isinstance(v, str) else v).replace("'", "''") + "'"
    result, captures, clears = None, 0, 0
    try:
        session = clients.spawn("BEGIN; SET LOCAL request.jwt.claim.role='service_role';\n\\i '" + str(fixture) + "'\n"
            "SELECT m3b_cycle_test.seed(2910,NULL);SELECT public.declare_mobile_health_risk(m3b_cycle_test.uid(2910),gen_random_uuid(),ARRAY['reduced_intake']);"
            "SELECT m3b_cycle_test.no_plan_signup(2911);CREATE TEMP TABLE clinical_original AS SELECT m3b_cycle_test.original_state(m3b_cycle_test.uid(2910)) s;\nSELECT 'READY';\n")
        clients.until(session, lambda line: line == 'READY')
        child = 'mobile_current_clinical_read_bff_bridge.ts' if consumer == 'read-model' else 'mobile_current_clinical_bff_bridge.ts'
        bridge = subprocess.Popen([node, str(runners[0]), '--script', str(Path(__file__).with_name(child))],
            cwd=root, env=dict(database.env, PERFORME_CURRENT_CLINICAL_QA='owned-local-rollback', PERFORME_CURRENT_TRANSPORT=transport),
            stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        while True:
            ready, _, _ = select.select([bridge.stdout], [], [], 20)
            require(ready, 'Child observation timeout')
            line = bridge.stdout.readline(); require(line, 'Child ended before result'); packet = json.loads(line)
            if packet['type'] == 'done': result = packet; break
            if packet['type'] in ('capture', 'rpc'):
                if packet['type'] == 'rpc':
                    require(transport == 'public-rpc' and packet['name'] == 'get_mobile_current_clinical_state', 'Unexpected RPC')
                    args = packet['args']
                    require(set(args) == {'p_user_id', 'p_mode', 'p_body', 'p_expected'} and args['p_expected'] is None, 'Unexpected RPC parameters')
                    r = {'userId': args['p_user_id'], 'mode': args['p_mode'], 'body': args['p_body']}
                    require(r['mode'] != 'profile' or r['body'] is None, 'Profile body override')
                else:
                    require(transport == 'private', 'Private bypass in public transport test')
                    r = packet['request']
                captures += 1
                require(captures <= capture_limit and r['userId'] in owners and r['mode'] in ('signup', 'profile'), 'Invalid capture scope')
                body = literal(r['body']) + '::jsonb' if r['mode'] == 'signup' else 'NULL'
                call = ('public.get_mobile_current_clinical_state(' if transport == 'public-rpc' else 'private.capture_mobile_current_clinical_state_at(')
                tail = ',NULL)' if transport == 'public-rpc' else ',NULL,NULL)'
                sql = 'SELECT ' + call + literal(r['userId']) + ',' + literal(r['mode']) + ',' + body + tail + ";\nSELECT 'REPLY';\n"
            elif packet['type'] == 'clear':
                clears += 1; require(clears == 1 and packet['owner'] == owners[1], 'Invalid clear scope')
                sql = "DO $$ DECLARE a uuid:=m3b_cycle_test.uid(2911);c uuid;q jsonb; BEGIN c:=(private.start_mobile_clinical_full_at(a,gen_random_uuid(),'EARLY_FULL','not_well_with_plan',NULL)#>>'{cycle,id}')::uuid;"
                sql += "q:=m3b_cycle_test.no_plan_request(a,'EARLY_FULL',c);PERFORM m3b_cycle_test.no_plan_confirm(a,q);END $$;\nSELECT '{\"cleared\":true}';\nSELECT 'REPLY';\n"
            else: raise ValueError('Unexpected child operation')
            session.stdin.write(sql.encode()); session.stdin.flush()
            lines = clients.until(session, lambda item: item == 'REPLY')
            reply = next(item for item in lines if item.startswith('{'))
            if packet['type'] == 'rpc': reply = json.dumps({'data': json.loads(reply), 'error': None})
            bridge.stdin.write(reply + '\n'); bridge.stdin.flush()
        bridge.stdin.close(); bridge.wait(timeout=10)
        expected_status = ('PASS_CURRENT_READERS_PUBLIC_RPC_SQL' if consumer == 'read-model' else
                           'PASS_CURRENT_BFF_PUBLIC_RPC_SQL' if transport == 'public-rpc' else 'PASS_CURRENT_BFF_PRIVATE_SQL')
        require(bridge.returncode == 0 and result['status'] == expected_status and captures == capture_limit and clears == 1, 'Bridge failed')
        session.stdin.write(("SELECT json_build_object('unchanged_A',(SELECT s FROM clinical_original)=m3b_cycle_test.original_state(m3b_cycle_test.uid(2910)),"
            "'epoch_A',(SELECT count(*) FROM private.workout_strength_authority_epochs WHERE user_id=m3b_cycle_test.uid(2910)),"
            "'full_B',(SELECT count(*) FROM private.mobile_clinical_full_receipts WHERE user_id=m3b_cycle_test.uid(2911)),"
            "'episodes_B',(SELECT count(*) FROM private.mobile_clinical_episode_events WHERE user_id=m3b_cycle_test.uid(2911)),"
            "'days_B',(SELECT count(*) FROM public.daily_snapshots WHERE user_id=m3b_cycle_test.uid(2911)));\nSELECT 'COUNTS';\n").encode()); session.stdin.flush()
        lines = clients.until(session, lambda item: item == 'COUNTS'); counts = json.loads(next(item for item in lines if item.startswith('{')))
        require(counts == {'unchanged_A': True, 'epoch_A': 0, 'full_B': 1, 'episodes_B': 0, 'days_B': 0}, 'Unexpected side effects')
        clients.finish(session, 'ROLLBACK;\n')
    finally:
        if bridge and bridge.poll() is None: bridge.terminate(); bridge.wait(timeout=5)
        clients.close()
    require(database.query(clean) == 't', 'Fixture did not roll back')
    receipt = {'status': 'PASS', 'bridge': result, 'counts': counts, 'capture_calls': captures, 'clear_SQL_calls': clears,
               'guard': database.guard, 'all_rolled_back': True, 'new_paid_resources': 0, 'remote_operations': 0}
    exclusive_json(output, receipt)
    return receipt


if __name__ == '__main__':
    parser = argparse.ArgumentParser(); parser.add_argument('--config', required=True); parser.add_argument('--output', required=True)
    parser.add_argument('--transport', choices=['private', 'public-rpc'], default='private')
    parser.add_argument('--consumer', choices=['capture', 'read-model'], default='capture')
    args = parser.parse_args(); print(json.dumps(run(LocalCycleDatabase(args.config), args.output, args.transport, args.consumer)))
