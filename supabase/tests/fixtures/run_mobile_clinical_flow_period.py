#!/usr/bin/env python3
"""Actual BFF period adapter and SQL, one guarded rollback; no cloud/provider."""
import argparse
import datetime
import json
import select
import shutil
import subprocess
from pathlib import Path
from run_mobile_reevaluation_cycle import LocalCycleDatabase
from run_mobile_health_hold_authority import Sessions, exclusive_json, require
from run_mobile_clinical_http import literal


def run(db, output, dry_migration=False):
    root = Path(__file__).resolve().parents[3]
    output = Path(output).resolve()
    require(not output.exists(), 'Evidence exists')
    clean_sql = "SELECT count(*)=0 AND to_regnamespace('m3b_cycle_test') IS NULL AND NOT EXISTS(SELECT 1 FROM net.http_request_queue) FROM public.users"
    require(db.query(clean_sql) == 't', 'Owned PG not clean')
    existed = db.query("SELECT to_regclass('private.mobile_clinical_closed_day_evidence') IS NOT NULL")
    require(existed == ('f' if dry_migration else 't'), 'Migration state differs')
    runners = list((root / 'node_modules/.pnpm').glob('vite-node@*/node_modules/vite-node/vite-node.mjs'))
    node = shutil.which('node')
    require(node and len(runners) == 1, 'Runtime unavailable/ambiguous')
    sessions = Sessions(db)
    session = child = result = failure = None
    log = ''
    calls = tampered = 0
    owner = 'b3b01000-0000-4000-8000-000000006406'
    try:
        sql = 'BEGIN;\n'
        if dry_migration:
            migration = (root / 'supabase/migrations/20261027111532_mobile_clinical_flow_period_evidence.sql').read_text()
            require(migration.rstrip().endswith('COMMIT;'), 'Migration terminator differs')
            sql = migration.rstrip()[:-7] + '\n'
        sql += '\\i ' + str(Path(__file__).with_name('mobile_clinical_day_close_fixture.sql')) + '\n'
        sql += "CREATE FUNCTION pg_temp.period_rpc(statement text) RETURNS jsonb LANGUAGE plpgsql AS $$DECLARE data jsonb;BEGIN EXECUTE statement INTO data;RETURN jsonb_build_object('data',data,'error',NULL);EXCEPTION WHEN OTHERS THEN RETURN jsonb_build_object('data',NULL,'error',jsonb_build_object('code',SQLSTATE));END$$;GRANT EXECUTE ON FUNCTION pg_temp.period_rpc(text) TO service_role;SELECT set_config('request.jwt.claim','{\"role\":\"service_role\"}',true);SELECT 'READY';\n"
        session = sessions.spawn(sql)
        sessions.until(session, lambda line: line == 'READY')
        child = subprocess.Popen([node, str(runners[0]), '--script', str(Path(__file__).with_name('mobile_clinical_flow_period_bridge.ts'))], cwd=root, env=dict(db.env, PERFORME_FLOW_PERIOD_QA='owned-local-rollback'), stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        seeded = False
        while True:
            require(select.select([child.stdout], [], [], 30)[0], 'Specific bridge timed out')
            line = child.stdout.readline()
            require(line, 'Bridge stream closed')
            packet = json.loads(line)
            if packet['type'] == 'done':
                result = packet
                break
            if packet['type'] == 'seed':
                require(not seeded, 'Seed replay refused')
                seeded = True
                sql = "DO $seed$ DECLARE q jsonb;a uuid;BEGIN q:=m3b_cycle_test.close_seed(6406);a:=(q->>'user')::uuid;PERFORM m3b_cycle_test.close_apply(q,m3b_cycle_test.close_capture(q));INSERT INTO public.daily_snapshots(user_id,date,calories_consumed,protein_g,calories_target,current_protocol,day_closed,day_status,closed_at) VALUES(a,(q->>'date')::date-1,1300,90,2000,'recomposicao',true,'complete',clock_timestamp());END$seed$;SELECT jsonb_build_object('owner'," + literal(owner) + ",'from',(clock_timestamp() AT TIME ZONE 'America/Sao_Paulo')::date-6,'to',(clock_timestamp() AT TIME ZONE 'America/Sao_Paulo')::date)"
            elif packet['type'] == 'rpc':
                calls += 1
                args = packet['args']
                require(calls <= 3 and packet['name'] == 'get_mobile_clinical_flow_period' and set(args) == {'p_user_id', 'p_period', 'p_expected_from', 'p_expected_to'} and args['p_user_id'] == owner and args['p_period'] == 'semana', 'RPC scope differs')
                statement = 'SELECT public.get_mobile_clinical_flow_period(' + ','.join(literal(args[k]) for k in ['p_user_id', 'p_period', 'p_expected_from', 'p_expected_to']) + ')'
                sql = 'SET LOCAL ROLE service_role;SELECT pg_temp.period_rpc(' + literal(statement) + ');RESET ROLE'
            elif packet['type'] == 'tamper':
                tampered += 1
                require(tampered == 1, 'Tamper bound exceeded')
                sql = "UPDATE public.daily_snapshots SET calories_consumed=1601 WHERE user_id=" + literal(owner) + " AND date=(clock_timestamp() AT TIME ZONE 'America/Sao_Paulo')::date-1;SELECT '{\"changed\":true}'::jsonb"
            else:
                raise AssertionError('Bridge failed or unknown operation')
            session.stdin.write((sql.rstrip(';') + ";\nSELECT 'REPLY';\n").encode())
            session.stdin.flush()
            rows = sessions.until(session, lambda line: line == 'REPLY')
            values = [v for v in rows if v.startswith('{')]
            require(len(values) == 1, 'SQL response cardinality differs')
            child.stdin.write(values[0] + '\n')
            child.stdin.flush()
        child.stdin.close()
        child.wait(timeout=10)
        log = child.stderr.read()
        require(child.returncode == 0 and result['status'] == 'PASS_REAL_PERIOD_BFF_SQL' and result['cases'] == 3 and calls == 3, 'Qualification incomplete')
        sessions.finish(session, 'SET CONSTRAINTS ALL IMMEDIATE;ROLLBACK;\n')
    except Exception as error:
        failure = {'type': type(error).__name__, 'message': str(error)}
    finally:
        if child and child.poll() is None:
            child.terminate()
            child.wait(timeout=5)
        if child and child.stderr and not log:
            log = child.stderr.read()
        if session and session.poll() is not None and not session.stderr.closed:
            log += '\nSQL:' + session.stderr.read().decode()[-6000:]
        sessions.close()
    clean = db.query(clean_sql) == 't' and db.query("SELECT to_regclass('private.mobile_clinical_closed_day_evidence') IS NOT NULL") == existed
    with Path(str(output) + '.child.log').open('x') as f:
        f.write(log)
    report = {'at_utc': datetime.datetime.now(datetime.timezone.utc).isoformat(), 'status': 'PASS' if failure is None and clean else 'FAIL', 'failure': failure, 'bridge': result, 'RPCs': calls, 'owned_PG_clean': clean, 'dry_migration_rolled_back': dry_migration, 'actual_BFF_SQL': True, 'PostgREST': False, 'app_or_Storage': False, 'provider_calls': 0, 'remote_operations': 0, 'new_paid_resources': 0}
    exclusive_json(output, report)
    require(report['status'] == 'PASS', 'Period bridge failed; inspect evidence')
    return report


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--config', required=True)
    parser.add_argument('--output', required=True)
    parser.add_argument('--dry-migration', action='store_true')
    args = parser.parse_args()
    result = run(LocalCycleDatabase(args.config), args.output, args.dry_migration)
    print(json.dumps({'status': result['status'], 'RPCs': result['RPCs']}))
