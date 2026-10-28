#!/usr/bin/env python3
"""Real injected BFF/private SQL, one owned rollback-only connection. Import inert."""
import argparse
import json
import os
import select
import shutil
import subprocess
from pathlib import Path
from run_mobile_health_hold_authority import Sessions, exclusive_json, require
from run_mobile_reevaluation_cycle import LocalCycleDatabase


def run(database, output):
    root = Path(__file__).resolve().parents[3]
    output = Path(output).resolve()
    require(not output.exists(), 'Evidence already exists')
    clean = "SELECT to_regnamespace('m3b_cycle_test') IS NULL AND NOT EXISTS(SELECT 1 FROM public.users)"
    require(database.query(clean) == 't', 'Local runtime not empty')
    runners = list((root / 'node_modules/.pnpm').glob('vite-node@*/node_modules/vite-node/vite-node.mjs'))
    node = shutil.which('node')
    require(node is not None and len(runners) == 1, 'Existing Node/vite-node runtime not unique')
    fixture = Path(__file__).with_name('mobile_signup_health_fixture.sql')
    clients = Sessions(database)
    bridge = None
    owner = 'b3b01000-0000-4000-8000-000000002500'
    literal = lambda value: "'" + value.replace("'", "''") + "'"
    result = None
    try:
        session = clients.spawn("BEGIN; SET LOCAL request.jwt.claim.role='service_role';\n\\i '" + str(fixture) + "'\n"
            "SELECT m3b_cycle_test.seed(2500,NULL);\nSELECT m3b_cycle_test.signup_health_command("
            "m3b_cycle_test.uid(2500),m3b_cycle_test.uid(2502),m3b_cycle_test.uid(2503));\nSELECT 'BFF_READY';\n")
        lines = clients.until(session, lambda line: line == 'BFF_READY')
        command = json.loads(next(line for line in lines if '"document_actions"' in line))
        birth = database.query("SELECT to_char(((clock_timestamp() AT TIME ZONE 'America/Sao_Paulo')::date-interval '17 years')::date,'YYYY-MM-DD')")
        submission = {'name': 'M3B synthetic QA', 'locale': 'pt-BR', 'country': 'BR', 'timezone': 'America/Sao_Paulo',
                      'sex': 'masculino', 'birth_date': birth, 'height_cm': 180, 'weight_kg': 80, 'body_fat_percent': 15,
                      'objective': None, 'activity_level': 'moderado', 'training_frequency': 4, 'water_intake': None,
                      'hunger_level': 'moderada', 'wake_time': '07:00', 'bedtime': '23:00', 'food_organization': 'sim',
                      'persona': 'focus', 'document_actions': command['document_actions']}
        env = dict(database.env, PERFORME_SIGNUP_HEALTH_BRIDGE_QA='owned-local-rollback')
        bridge = subprocess.Popen([node, str(runners[0]), '--script', str(Path(__file__).with_name('mobile_signup_health_bff_bridge.ts'))],
            cwd=root, env=env, stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        bridge.stdin.write(json.dumps({'owner': owner, 'command': command, 'submission': submission}) + '\n'); bridge.stdin.flush()
        calls = 0
        completions = 0
        while True:
            ready, _, _ = select.select([bridge.stdout], [], [], 20)
            require(ready, 'BFF bridge observation timeout')
            line = bridge.stdout.readline()
            require(line, 'BFF bridge ended before completion')
            packet = json.loads(line)
            if packet['type'] == 'done':
                result = packet
                break
            require(packet.get('owner') == owner, 'Bridge changed owned fixture identity')
            if packet['type'] == 'admit':
                require(packet['command'] == command and calls < 3, 'Unexpected admission content/count')
                calls += 1
                sql = "SELECT private.admit_mobile_signup_health(" + literal(owner) + ',' + literal(json.dumps(command)) + ");\nSELECT 'BFF_REPLY';\n"
                session.stdin.write(sql.encode()); session.stdin.flush()
                lines = clients.until(session, lambda item: item == 'BFF_REPLY')
                response = json.loads(next(item for item in lines if '"health_operation_key"' in item))
            elif packet['type'] == 'reset':
                session.stdin.write(("SELECT public.reset_user_conversation_atomic(" + literal(owner) + ",true);\nSELECT 'BFF_RESET';\n").encode())
                session.stdin.flush()
                clients.until(session, lambda item: item == 'BFF_RESET')
                response = {'reset': True}
            elif packet['type'] == 'complete':
                require(packet['submission'] == submission and completions == 0, 'Unexpected completion content/count')
                completions += 1
                sql = "SELECT public.complete_mobile_onboarding_atomic(" + literal(owner) + ',' + literal(json.dumps(submission)) + ");\nSELECT 'BFF_COMPLETED';\n"
                session.stdin.write(sql.encode()); session.stdin.flush()
                lines = clients.until(session, lambda item: item == 'BFF_COMPLETED')
                response = {'data': json.loads(next(item for item in lines if '"clinical_safety"' in item)), 'error': None}
            else:
                raise ValueError('Unexpected bridge operation')
            bridge.stdin.write(json.dumps(response) + '\n'); bridge.stdin.flush()
        bridge.stdin.close()
        bridge.wait(timeout=10)
        require(bridge.returncode == 0 and not bridge.stderr.read().strip(), 'BFF process failed')
        require(result['status'] == 'PASS_INJECTED_BFF_PRIVATE_SQL' and calls == 3 and completions == 1, 'BFF did not complete the expected path')
        session.stdin.write(("SELECT json_build_object('signup',(SELECT count(*) FROM private.mobile_signup_health_receipts WHERE user_id="
            + literal(owner) + "),'risk',(SELECT count(*) FROM private.mobile_health_risk_receipts WHERE user_id=" + literal(owner)
            + "),'acts',(SELECT count(*) FROM public.user_onboarding_legal_actions WHERE user_id=" + literal(owner) + "));\nSELECT 'BFF_COUNTS';\n").encode())
        session.stdin.flush()
        lines = clients.until(session, lambda item: item == 'BFF_COUNTS')
        counts = json.loads(next(item for item in lines if item.startswith('{"signup"')))
        require(counts == {'signup': 1, 'risk': 1, 'acts': 4}, 'Replay duplicated durable rows')
        session.stdin.write(("SELECT json_build_object('no_phase',(SELECT current_protocol IS NULL AND deficit_level IS NULL AND onboarding_completed "
                             "FROM public.user_profiles WHERE user_id=" + literal(owner) + "),'no_snapshot',NOT EXISTS(SELECT 1 FROM public.daily_snapshots WHERE user_id="
                             + literal(owner) + "));\nSELECT 'BFF_NO_PLAN';\n").encode()); session.stdin.flush()
        lines = clients.until(session, lambda item: item == 'BFF_NO_PLAN')
        no_plan = json.loads(next(item for item in lines if item.startswith('{"no_phase"')))
        require(no_plan == {'no_phase': True, 'no_snapshot': True}, 'No-plan completion manufactured clinical targets')
        clients.finish(session, 'ROLLBACK;\n')
    finally:
        if bridge is not None and bridge.poll() is None:
            bridge.terminate(); bridge.wait(timeout=5)
        clients.close()
    require(database.query(clean) == 't', 'Owned fixture did not roll back')
    evidence = {'status': 'PASS', 'bridge': result, 'counts_before_rollback': counts, 'no_plan_before_rollback': no_plan, 'fixtures_rolled_back': True,
                'guard': database.guard, 'remote_operations': 0, 'new_paid_resources': 0, 'HTTP_QA': False}
    exclusive_json(output, evidence)
    return evidence


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--config', required=True)
    parser.add_argument('--output', required=True)
    args = parser.parse_args()
    print(json.dumps(run(LocalCycleDatabase(args.config), args.output)))
