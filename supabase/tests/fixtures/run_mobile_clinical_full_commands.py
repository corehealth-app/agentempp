#!/usr/bin/env python3
"""Public command RPC races on the existing guarded local socket only."""
import argparse
import json
import time
from pathlib import Path

from run_mobile_clinical_full import literal
from run_mobile_health_hold_authority import Sessions, exclusive_json, require
from run_mobile_reevaluation_cycle import LocalCycleDatabase
from run_mobile_reevaluation_photo_consent import cleanup_fixture


def uid(n):
    return f'b3b01000-0000-4000-8000-{n:012d}'


def prepare(owner, q, key, command=None):
    values = [owner, 'REGULAR', q['context']['cycle_id'], key,
              q['context']['context_hash'], command or q['command'],
              q['form'], q['intent'], q['proposal']]
    return 'SELECT public.prepare_mobile_clinical_full_command(' + ','.join(map(literal, values)) + ');'


def confirm(owner, q, preview, key):
    values = [owner, preview, key, q['command'], q['form'], q['intent'], q['proposal']]
    return 'SELECT public.confirm_mobile_clinical_full_command(' + ','.join(map(literal, values)) + ');'


def json_rows(output):
    return [json.loads(row) for row in output.splitlines() if row.startswith('{')]


TRUST = "SET LOCAL ROLE service_role;SET LOCAL request.jwt.claim='{" + '"role":"service_role"' + "}';"


def run(database, output):
    output = Path(output).resolve()
    require(not output.exists(), 'Evidence already exists')
    require(database.query("SELECT NOT EXISTS(SELECT 1 FROM public.users) AND to_regnamespace('m3b_cycle_test') IS NULL") == 't', 'Owned runtime not clean')
    config_expr = 'md5(jsonb_build_object(' + ','.join(
        literal(table) + ",coalesce((SELECT jsonb_agg(to_jsonb(x) ORDER BY " + order + ") FROM public." + table + " x),'[]'::jsonb)"
        for table, order in [('global_config', 'key'), ('onboarding_legal_documents', 'id'),
                             ('onboarding_legal_requirement_sets', 'id'), ('audit_log', 'id')]) + ')::text)'
    baseline = database.query('SELECT ' + config_expr)
    fixture = Path(__file__).with_name('mobile_clinical_full_command_fixture.sql')
    require(database.run_file(fixture, str(output) + '.setup.log') == 0, 'Fixture setup failed')
    sessions, owners, cases = Sessions(database), [], []
    try:
        modes = ['prepare_same', 'prepare_changed', 'prepare_rollback', 'confirm_same',
                 'confirm_alias', 'confirm_rollback', 'reset_then_confirm']
        for n, mode in enumerate(modes, 4400):
            owner, key = uid(n), uid(n + 100)
            owners.append(owner)
            seeded = database.query('BEGIN;SELECT m3b_cycle_test.clinical_photos(' + str(n) + ');'
                + "INSERT INTO public.daily_snapshots(user_id,date,calories_target,protein_target,current_protocol) VALUES("
                + literal(owner) + ",(clock_timestamp() AT TIME ZONE 'America/Sao_Paulo')::date,1700,120,'recomposicao');"
                + "DO $guard$ BEGIN IF (SELECT " + config_expr + ') IS DISTINCT FROM ' + literal(baseline)
                + " THEN RAISE EXCEPTION 'fixture changed shared catalogue';END IF;END $guard$;COMMIT;")
            context = json_rows(seeded)[0]
            q = json.loads(database.query('SELECT m3b_cycle_test.command_input(' + literal(context) + ')'))
            first_sql = prepare(owner, q, key)
            second_sql = first_sql
            if mode == 'prepare_changed':
                changed = dict(q['command'], measureConfirmed=True)
                second_sql = prepare(owner, q, key, changed)
            if mode.startswith('confirm') or mode == 'reset_then_confirm':
                prepared = json_rows(database.query('BEGIN;' + TRUST + first_sql + 'COMMIT;'))[0]
                preview = prepared['preview']['preview_id']
                first_sql = confirm(owner, q, preview, uid(n + 200))
                second_sql = confirm(owner, q, preview, uid(n + (300 if mode == 'confirm_alias' else 200)))
                if mode == 'reset_then_confirm':
                    first_sql = 'SELECT jsonb_build_object(\'reset\',public.reset_user_conversation_atomic(' + literal(owner) + ',true));'
            first = sessions.spawn('BEGIN;' + TRUST + "SELECT jsonb_build_object('holder',pg_backend_pid());\n"
                + first_sql + "\nSELECT 'COMMAND_READY';\n")
            rows = json_rows('\n'.join(sessions.until(first, lambda line: line == 'COMMAND_READY')))
            holder, first_result = rows[0]['holder'], rows[1]
            second = sessions.spawn("BEGIN;CREATE FUNCTION pg_temp.try_command(statement text) RETURNS jsonb "
                "LANGUAGE plpgsql SECURITY INVOKER SET search_path=pg_catalog AS $try$ DECLARE result jsonb;BEGIN "
                "BEGIN EXECUTE statement INTO result;EXCEPTION WHEN OTHERS THEN RETURN jsonb_build_object('code',SQLSTATE);END;"
                "RETURN jsonb_build_object('code','00000','result',result);END $try$;"
                'GRANT EXECUTE ON FUNCTION pg_temp.try_command(text) TO service_role;' + TRUST
                + "SELECT jsonb_build_object('waiter',pg_backend_pid());\nSELECT pg_temp.try_command("
                + literal(second_sql) + ');COMMIT;\n')
            waiter = json_rows('\n'.join(sessions.until(second, lambda line: line.startswith('{"waiter"'))))[0]['waiter']
            deadline = time.monotonic() + 5
            while time.monotonic() < deadline:
                blocking = json.loads(database.query("SELECT json_build_object('lock',wait_event_type='Lock','blockers',pg_blocking_pids(pid)) FROM pg_stat_activity WHERE pid=" + str(waiter)))
                if blocking['lock'] and holder in blocking['blockers']:
                    break
                require(second.poll() is None, 'Waiter exited without exact owner lock')
                time.sleep(0.03)
            else:
                raise TimeoutError('Exact command blocker not observed')
            sessions.finish(first, 'ROLLBACK;\n' if mode.endswith('rollback') else 'COMMIT;\n')
            second_result = json_rows(sessions.finish(second))[0]
            expected = '40001' if mode in ['prepare_changed', 'reset_then_confirm'] else '00000'
            require(second_result['code'] == expected, mode + ': result differs')
            counts = json.loads(database.query("SELECT json_build_object('previews',(SELECT count(*) FROM private.mobile_clinical_previews WHERE user_id=" + literal(owner)
                + "),'commands',(SELECT count(*) FROM private.mobile_clinical_full_commands WHERE user_id=" + literal(owner)
                + "),'fulls',(SELECT count(*) FROM private.mobile_clinical_full_receipts WHERE user_id=" + literal(owner)
                + "),'keys',(SELECT count(*) FROM private.mobile_clinical_confirmation_keys WHERE user_id=" + literal(owner) + '))'))
            require(counts['previews'] == counts['commands'] == 1, 'Orphan/duplicate preview or command')
            require(counts['fulls'] == (1 if mode.startswith('confirm') else 0), 'Wrong clinical effect count')
            require(counts['keys'] == (2 if mode == 'confirm_alias' else 1 if mode.startswith('confirm') else 0), 'Wrong confirmation key count')
            if mode in ['prepare_same', 'confirm_same']:
                require(second_result['result'] == first_result, 'Original ACK changed after lock')
            if mode == 'confirm_alias':
                require(second_result['result']['result'] == first_result['result'], 'Alias recalculated result')
            cases.append({'case': mode, 'status': 'PASS', 'holder': holder, 'waiter': waiter,
                          'exact_blockers': blocking['blockers'], 'second_code': second_result['code'], 'counts': counts})
    finally:
        sessions.close()
        if owners:
            database.query('SELECT m3b_cycle_test.remove_photos(ARRAY[' + ','.join(map(literal, owners)) + ']::uuid[])')
        cleanup_fixture(database, owners, ('b3b01000-0000-4000-8000-000000000501',))
    clean = database.query("SELECT NOT EXISTS(SELECT 1 FROM public.users) AND to_regnamespace('m3b_cycle_test') IS NULL AND NOT EXISTS(SELECT 1 FROM net.http_request_queue)") == 't'
    preserved = database.query('SELECT ' + config_expr) == baseline
    require(clean and preserved, 'Runtime/catalogue not preserved')
    result = {'status': 'PASS_PUBLIC_COMMAND_SQL_RACES', 'cases': cases,
              'local_only': True, 'all_synthetic_removed': clean, 'config_legal_audit_preserved': preserved,
              'remote_operations': 0, 'new_paid_resources': 0}
    exclusive_json(output, result)
    return result


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--config', required=True)
    parser.add_argument('--output', required=True)
    args = parser.parse_args()
    result = run(LocalCycleDatabase(args.config), args.output)
    print(json.dumps({'status': result['status'], 'cases': len(result['cases'])}))
