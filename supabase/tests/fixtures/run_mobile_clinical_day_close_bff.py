#!/usr/bin/env python3
"""Owned local actual BFF/core/public RPC proof. Import is inert; no remote I/O."""
import argparse
import datetime
import json
import os
import shutil
import subprocess
from pathlib import Path

from run_mobile_health_hold_authority import exclusive_json, require
from run_mobile_reevaluation_cycle import LocalCycleDatabase


def run(config, output):
    database = LocalCycleDatabase(config)
    database.args.insert(1, '-q')
    root = Path(__file__).resolve().parents[3]
    output = Path(output).resolve()
    require(not output.exists(), 'Evidence already exists')
    require(database.query("SELECT NOT EXISTS(SELECT 1 FROM public.users) AND to_regnamespace('m3b_cycle_test') IS NULL "
                           'AND NOT EXISTS(SELECT 1 FROM net.http_request_queue)') == 't', 'Owned runtime is not empty')
    node = shutil.which('node')
    runners = list((root / 'node_modules/.pnpm').glob('vite-node@*/node_modules/vite-node/vite-node.mjs'))
    require(node is not None and len(runners) == 1, 'Existing Node/vite-node runtime is not unique')
    saved = database.query("SELECT jsonb_agg(to_jsonb(c) ORDER BY key) FROM public.global_config c "
                           "WHERE key IN('calc.xp_rules','calc.kcal_block')")
    require(len(json.loads(saved)) == 2, 'Expected local config rows missing')
    fixture = Path(__file__).with_name('mobile_clinical_day_close_fixture.sql')
    require(database.run_file(fixture, str(output) + '.setup.log') == 0, 'Fixture setup failed')
    failure, bridge = None, None
    try:
        env = dict(database.env, PERFORME_CLINICAL_SQL_CONFIG=str(database.config_path),
                   PERFORME_CLINICAL_SQL_START=database.guard['pid'], PERFORME_CLINICAL_TRANSPORT='public-rpc')
        result = subprocess.run([node, str(runners[0]), '--script',
                                 str(Path(__file__).with_name('mobile_clinical_day_close_bff_bridge.ts'))],
                                cwd=root, env=env, capture_output=True, text=True, timeout=90)
        with os.fdopen(os.open(str(output) + '.bridge.log', os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600), 'w') as log:
            log.write(result.stdout + result.stderr)
        require(result.returncode == 0, 'Whole-close BFF bridge failed; inspect local bridge log')
        bridge = json.loads(next(line for line in result.stdout.splitlines() if line.startswith('{"status"')))
        require(bridge['status'] == 'PASS_ACTUAL_CLOSER_BFF_CORE_PUBLIC_RPC_SQL' and len(bridge['cases']) == 18,
                'Whole-close BFF bridge did not prove every case')
    except Exception as error:
        failure = {'type': type(error).__name__, 'message': str(error)}
    finally:
        ids = ','.join("'b3b01000-0000-4000-8000-" + str(n).zfill(12) + "'" for n in [*range(3450, 3459), 3460, *range(3470, 3476)])
        database.query("BEGIN;DO $guard$ BEGIN IF EXISTS(SELECT 1 FROM public.users WHERE id IN(" + ids + ") "
                       "AND email NOT LIKE 'm3b-cycle-%@example.invalid') THEN RAISE EXCEPTION 'Unknown fixture owner';END IF;END $guard$;"
                       'DELETE FROM private.mobile_reevaluation_cycles WHERE user_id IN(' + ids + ');'
                       'DELETE FROM private.mobile_signup_strength_completion_receipts WHERE user_id IN(' + ids + ');'
                       'DELETE FROM public.users WHERE id IN(' + ids + ');DROP SCHEMA m3b_cycle_test CASCADE;COMMIT;')
        literal = lambda value: "'" + value.replace("'", "''") + "'"
        database.query('UPDATE public.global_config c SET value=s.value,updated_at=s.updated_at '
                       'FROM jsonb_to_recordset(' + literal(saved) + '::jsonb) AS s(key text,value jsonb,updated_at timestamptz) '
                       'WHERE c.key=s.key')
    clean = database.query("SELECT NOT EXISTS(SELECT 1 FROM public.users) AND to_regnamespace('m3b_cycle_test') IS NULL "
                           'AND NOT EXISTS(SELECT 1 FROM private.mobile_clinical_day_close_keys) '
                           'AND NOT EXISTS(SELECT 1 FROM net.http_request_queue)') == 't'
    restored = database.query("SELECT jsonb_agg(to_jsonb(c) ORDER BY key) FROM public.global_config c "
                              "WHERE key IN('calc.xp_rules','calc.kcal_block')") == saved
    report = {'at_utc': datetime.datetime.now(datetime.timezone.utc).isoformat(),
              'status': 'PASS' if not failure and clean and restored else 'FAIL',
              'bridge': bridge, 'failure': failure, 'clean': clean, 'config_restored_exact': restored,
              'guard': database.guard, 'HTTP_QA': False, 'Storage_QA': False, 'remote_operations': 0}
    exclusive_json(output, report)
    require(report['status'] == 'PASS', 'Actual whole-close BFF QA did not pass')
    return report


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--config', required=True)
    parser.add_argument('--output', required=True)
    args = parser.parse_args()
    report = run(args.config, args.output)
    print(json.dumps({'status': report['status'], 'cases': len(report['bridge']['cases']), 'clean': report['clean']}))
