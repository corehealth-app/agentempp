#!/usr/bin/env python3
"""Guarded explicit BFF/core/SQL bridge QA. Importing is inert; no remote I/O."""
import argparse
import datetime
import json
import os
import shutil
import subprocess
from pathlib import Path
from run_mobile_reevaluation_cycle import LocalCycleDatabase
from run_mobile_health_hold_authority import exclusive_json, require


def run(config, output, transport='private'):
    require(transport in ('private', 'public-rpc'), 'Unknown transport')
    database = LocalCycleDatabase(config)
    database.args.insert(1, '-q')
    root = Path(__file__).resolve().parents[3]
    output = Path(output).resolve()
    require(not output.exists(), 'Evidence already exists')
    require(database.query('SELECT count(*) FROM public.users') == '0', 'Local runtime is not empty')
    require(database.query("SELECT to_regnamespace('m3b_cycle_test') IS NULL") == 't', 'Fixture exists')
    node = shutil.which('node')
    runners = list((root / 'node_modules/.pnpm').glob('vite-node@*/node_modules/vite-node/vite-node.mjs'))
    require(node is not None and len(runners) == 1, 'Existing Node/vite-node runtime not uniquely found')
    saved = database.query("SELECT coalesce((SELECT to_jsonb(c) FROM public.global_config c WHERE key='calc.protein_factors'),'null'::jsonb)")
    fixture = Path(__file__).with_name('mobile_clinical_daily_fixture.sql')
    failure = None
    bridge = None
    require(database.run_file(fixture, str(output) + '.setup.log') == 0, 'Fixture setup failed')
    try:
        database.query("INSERT INTO public.global_config(key,value) VALUES('calc.protein_factors',"
                       "'{\"muita\":1.6,\"moderada\":1.8,\"pouca\":1.8,\"training_low\":1.7,\"optimal_mid_training\":1.9,\"optimal_high_training\":2}'::jsonb) "
                       "ON CONFLICT(key) DO UPDATE SET value=excluded.value,updated_at=clock_timestamp()")
        env = dict(database.env, PERFORME_CLINICAL_SQL_CONFIG=str(database.config_path),
                   PERFORME_CLINICAL_SQL_START=database.guard['pid'], PERFORME_CLINICAL_TRANSPORT=transport)
        result = subprocess.run([node, str(runners[0]), '--script', str(Path(__file__).with_name('mobile_clinical_bff_bridge.ts'))],
                                cwd=root, env=env, capture_output=True, text=True, timeout=90)
        with os.fdopen(os.open(str(output) + '.bridge.log', os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600), 'w') as log:
            log.write(result.stdout + result.stderr)
        require(result.returncode == 0, 'BFF bridge failed; inspect local bridge log')
        bridge = json.loads(next(line for line in result.stdout.splitlines() if line.startswith('{"status"')))
        expected = 'PASS_INJECTED_BFF_CORE_PUBLIC_RPC_SQL' if transport == 'public-rpc' else 'PASS_INJECTED_BFF_CORE_PRIVATE_SQL'
        require(bridge['status'] == expected and bridge['transport'] == transport, 'Bridge did not pass')
    except Exception as error:
        failure = {'type': type(error).__name__, 'message': str(error)}
    finally:
        owner = 'b3b01000-0000-4000-8000-000000001906'
        database.query("BEGIN; DO $guard$ BEGIN IF EXISTS(SELECT 1 FROM public.users WHERE id='" + owner
                       + "' AND email NOT LIKE 'm3b-cycle-%@example.invalid') THEN RAISE EXCEPTION 'Unknown fixture owner'; END IF; END $guard$;"
                       + "DELETE FROM private.mobile_reevaluation_cycles WHERE user_id='" + owner + "';"
                       + "DELETE FROM private.mobile_signup_strength_completion_receipts WHERE user_id='" + owner + "';"
                       + "DELETE FROM public.users WHERE id='" + owner + "';DROP SCHEMA m3b_cycle_test CASCADE; COMMIT;")
        literal = lambda value: "'" + value.replace("'", "''") + "'"
        if saved == 'null':
            database.query("DELETE FROM public.global_config WHERE key='calc.protein_factors'")
        else:
            database.query("UPDATE public.global_config SET value=(" + literal(saved) + "::jsonb)->'value',updated_at=(("
                           + literal(saved) + "::jsonb)->>'updated_at')::timestamptz WHERE key='calc.protein_factors'")
    clean = database.query("SELECT to_regnamespace('m3b_cycle_test') IS NULL AND NOT EXISTS(SELECT 1 FROM public.users)") == 't'
    restored = database.query("SELECT coalesce((SELECT to_jsonb(c) FROM public.global_config c WHERE key='calc.protein_factors'),'null'::jsonb)") == saved
    receipt = {'at_utc': datetime.datetime.now(datetime.timezone.utc).isoformat(), 'status': 'PASS' if not failure and clean and restored else 'FAIL',
               'bridge': bridge, 'transport': transport, 'failure': failure, 'clean': clean, 'config_restored_exact': restored, 'guard': database.guard,
               'HTTP_QA': False, 'provider_operations': 0, 'remote_operations': 0, 'Storage_operations': 0}
    exclusive_json(output, receipt)
    require(receipt['status'] == 'PASS', 'Local integrated BFF QA did not pass')
    return receipt


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--config', required=True)
    parser.add_argument('--output', required=True)
    parser.add_argument('--transport', choices=['private', 'public-rpc'], default='private')
    args = parser.parse_args()
    print(json.dumps(run(args.config, args.output, args.transport)))
