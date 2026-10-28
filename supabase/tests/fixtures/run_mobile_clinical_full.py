#!/usr/bin/env python3
"""Real FULL writer races on the existing task-owned socket database only."""
import argparse
import hashlib
import json
import time
from decimal import Decimal
from pathlib import Path

from run_mobile_health_hold_authority import Sessions, exclusive_json, require
from run_mobile_reevaluation_cycle import LocalCycleDatabase
from run_mobile_reevaluation_photo_consent import cleanup_fixture


def lossless_json(value):
    # A SQL-built preview hashes numeric scale (e.g.120.00). Preserve that
    # representation across the Python test transport, including nested rows.
    # Production BFF requests create/hash their own original JSON package.
    if isinstance(value, Decimal):
        require(value.is_finite(), 'Non-finite SQL JSON number')
        return str(value)
    if isinstance(value, dict):
        return '{' + ','.join(json.dumps(k) + ':' + lossless_json(v) for k,v in value.items()) + '}'
    if isinstance(value, list):
        return '[' + ','.join(lossless_json(v) for v in value) + ']'
    return json.dumps(value, separators=(',', ':'), allow_nan=False)


def literal(value):
    if isinstance(value, (dict, list)):
        value = lossless_json(value)
    return "'" + str(value).replace("'", "''") + "'"


def confirmation(owner, request, operation):
    return ('SELECT private.confirm_mobile_clinical_preview_at('
            + ','.join(literal(x) for x in (owner, request['preview']['preview_id'], operation,
                                            request['form'], request['intent'], request['proposal']))
            + ',NULL);')


def run(database, output, scenario="regular"):
    require(scenario in ("regular","legacy_transition","legacy_unassigned"), "Unsupported explicit scenario")
    output = Path(output).resolve()
    require(not output.exists(), 'Evidence path already exists')
    root = Path(__file__).resolve().parents[3]
    fixture = root / ('supabase/tests/fixtures/mobile_clinical_legacy_transition_fixture.sql' if scenario != 'regular' else 'supabase/tests/fixtures/mobile_clinical_full_fixture.sql')
    tests = root / 'supabase/tests/mobile_clinical_full_conclusion.sql'
    require(database.query("SELECT to_regnamespace('m3b_cycle_test') IS NULL AND "
                           "NOT EXISTS(SELECT 1 FROM public.users)") == 't', 'Owned runtime is not clean')
    require(database.run_file(fixture, str(output) + '.setup.log') == 0, 'FULL fixture setup failed')
    request_helper = ('legacy_initial_phase_request' if scenario == 'legacy_unassigned'
                      else 'legacy_clinical_request' if scenario == 'legacy_transition' else 'clinical_request')
    if scenario == 'regular':
        helper_source = tests.read_text()
        start = helper_source.index('CREATE FUNCTION m3b_cycle_test.clinical_request(')
        end = helper_source.index('\nEND $$;', start) + len('\nEND $$;')
        database.query(helper_source[start:end])
    database.query("""
      CREATE FUNCTION m3b_cycle_test.try_command(statement text) RETURNS jsonb
      LANGUAGE plpgsql SET search_path=pg_catalog AS $$
      DECLARE result jsonb;code text;message text;
      BEGIN
        BEGIN EXECUTE statement INTO result;
        EXCEPTION WHEN OTHERS THEN GET STACKED DIAGNOSTICS code=RETURNED_SQLSTATE,message=MESSAGE_TEXT;
          RETURN jsonb_build_object('code',code,'message',message); END;
        RETURN jsonb_build_object('code','00000','result',result);
      END $$;
      REVOKE ALL ON ALL FUNCTIONS IN SCHEMA m3b_cycle_test FROM PUBLIC,anon,authenticated,service_role;
    """)
    sessions = Sessions(database)
    owners = []
    cases = []
    try:
        modes = ('same_preview', 'competing_previews', 'rollback', 'risk_then_full',
                 'clear_then_risk', 'reset_then_full', 'weight_then_full', 'replacement_then_full')
        for n, mode in enumerate(modes, 1800):
            owner = f'b3b01000-0000-4000-8000-{n:012d}'
            owners.append(owner)
            seed = (f'm3b_cycle_test.process_clinical_photos(m3b_cycle_test.legacy_photo_context({n},'
                    + ('false' if scenario == 'legacy_unassigned' else 'true') + ',false))'
                    if scenario != 'regular' else f'm3b_cycle_test.clinical_photos({n})')
            context = json.loads(database.query('SELECT ' + seed))
            database.query("INSERT INTO public.daily_snapshots(user_id,date,calories_target,protein_target,current_protocol) "
                           f"VALUES({literal(owner)},(clock_timestamp() AT TIME ZONE 'America/Sao_Paulo')::date,1700,120,"
                           + ('NULL' if scenario == 'legacy_unassigned' else "'recomposicao'") + ')')
            if mode == 'clear_then_risk':
                database.query(f"SELECT public.declare_mobile_health_risk({literal(owner)},gen_random_uuid(),ARRAY['reduced_intake'])")
            request = json.loads(database.query('SELECT m3b_cycle_test.' + request_helper + '('
                                                + literal(context) + ',84,'
                                                + ('true' if mode == 'clear_then_risk' else 'false') + ')'), parse_float=Decimal)
            operation = f'b3b01000-1000-4000-8000-{n:012d}'
            full = confirmation(owner, request, operation)
            first_sql = full
            second_sql = full
            if mode == 'competing_previews':
                competing = json.loads(database.query('SELECT m3b_cycle_test.' + request_helper + '(' + literal(context) + ')'), parse_float=Decimal)
                second_sql = confirmation(owner, competing, f'b3b01000-2000-4000-8000-{n:012d}')
            if mode == 'risk_then_full':
                first_sql = f"SELECT public.declare_mobile_health_risk({literal(owner)},gen_random_uuid(),ARRAY['professional_diet']);"
            if mode == 'clear_then_risk':
                second_sql = f"SELECT public.declare_mobile_health_risk({literal(owner)},gen_random_uuid(),ARRAY['professional_diet']);"
            if mode == 'reset_then_full':
                first_sql = f'SELECT public.reset_user_conversation_atomic({literal(owner)},true);'
            if mode == 'weight_then_full':
                first_sql = (f'SELECT public.record_weight_atomic({literal(owner)},82,\'kg\',clock_timestamp(),'
                             + literal(f'full-race-weight-{n}') + ');')
            if mode == 'replacement_then_full':
                first_sql = 'SELECT m3b_cycle_test.allocate(' + literal(context) + ",gen_random_uuid(),'front');"
            first = sessions.spawn("BEGIN;SELECT jsonb_build_object('holder',pg_backend_pid());\n"
                                   + first_sql + "\nSELECT 'M3B_FULL_READY';\n")
            lines = sessions.until(first, lambda line: line == 'M3B_FULL_READY')
            holder = json.loads(next(x for x in lines if x.startswith('{"holder"')))['holder']
            first_result = json.loads(next(x for x in lines if x.startswith('{') and not x.startswith('{"holder"')))
            second = sessions.spawn("SELECT jsonb_build_object('waiter',pg_backend_pid());\n"
                                    'SELECT m3b_cycle_test.try_command(' + literal(second_sql) + ');\n')
            lines = sessions.until(second, lambda line: line.startswith('{"waiter"'))
            waiter = json.loads(lines[-1])['waiter']
            deadline = time.monotonic() + 5
            while time.monotonic() < deadline:
                blocking = json.loads(database.query(
                    "SELECT json_build_object('lock',wait_event_type='Lock','blockers',pg_blocking_pids(pid)) "
                    f'FROM pg_stat_activity WHERE pid={int(waiter)}'))
                if blocking['lock'] and holder in blocking['blockers']:
                    break
                require(second.poll() is None, 'FULL waiter exited without the actual owner lock')
                time.sleep(0.03)
            else:
                raise TimeoutError('Exact FULL blocker was not observed')
            boundary = database.query("SELECT to_char(clock_timestamp() AT TIME ZONE 'UTC','YYYY-MM-DD\"T\"HH24:MI:SS.US\"Z\"')")
            sessions.finish(first, 'ROLLBACK;\n' if mode == 'rollback' else 'COMMIT;\n')
            result = json.loads(next(x for x in sessions.finish(second).splitlines() if x.startswith('{')))
            state = json.loads(database.query("SELECT json_build_object('fulls',(SELECT count(*) FROM private.mobile_clinical_full_receipts "
                f"WHERE user_id={literal(owner)}),'weights',(SELECT count(*) FROM private.mobile_weight_measurements WHERE user_id={literal(owner)}),"
                f"'weight',(SELECT weight_kg FROM public.user_profiles WHERE user_id={literal(owner)}),"
                f"'hold',public.get_mobile_health_hold_state({literal(owner)}))"))
            if mode in ('same_preview', 'rollback', 'clear_then_risk'):
                require(result['code'] == '00000' and state['fulls'] == 1 and state['weights'] == 1, 'FULL effect count differs')
            else:
                require(result['code'] == '40001', f'{mode}: stale confirmation did not refuse')
                require(state['fulls'] == (1 if mode == 'competing_previews' else 0), 'Stale FULL wrote clinical effects')
            if mode == 'same_preview':
                require(result['result'] == first_result, 'Same preview did not replay exact original receipt')
            if mode == 'rollback':
                require(result['result']['completed_at'] >= boundary, 'FULL clock was sampled before owner wait')
            if mode == 'risk_then_full':
                require(state['hold']['hold_active'] and state['hold']['safety_revision'] == '1', 'Concurrent risk was lost')
            if mode == 'clear_then_risk':
                require(state['hold']['hold_active'] and state['hold']['safety_revision'] == '3', 'Post-clear risk did not win')
            if mode == 'reset_then_full':
                require(state['weight'] is None, 'Stale FULL resurrected a reset profile')
            if mode == 'weight_then_full':
                require(state['weight'] == 82 and state['weights'] == 1, 'Stale FULL overwrote genuine weight')
            if mode == 'replacement_then_full':
                require(database.query('SELECT count(*) FROM private.mobile_reevaluation_photo_sources WHERE user_id='
                                       + literal(owner) + ' AND requested_asset_id<>selected_asset_id') == '1', 'Pending source was lost')
            if scenario == 'legacy_unassigned':
                phase_state = json.loads(database.query("SELECT json_build_object("
                    f"'phase',(SELECT current_protocol FROM public.user_profiles WHERE user_id={literal(owner)}),"
                    f"'marker',(SELECT onboarding_completed_at FROM public.user_profiles WHERE user_id={literal(owner)}),"
                    f"'episodes',(SELECT count(*) FROM private.mobile_clinical_episode_events WHERE user_id={literal(owner)}),"
                    f"'signup',(SELECT count(*) FROM private.mobile_signup_strength_completion_receipts WHERE user_id={literal(owner)}),"
                    f"'first_phase',(SELECT count(*) FROM private.mobile_clinical_first_phase_confirmations WHERE user_id={literal(owner)}))"))
                require(phase_state == {'phase': 'recomposicao' if state['fulls'] else None,
                    'marker': None, 'episodes': state['fulls'], 'signup': 0, 'first_phase': 0},
                    'Concurrent initial phase fabricated or duplicated clinical authority')
            cases.append({'case': mode, 'status': 'PASS', 'holder': holder, 'waiter': waiter,
                          'exact_blockers': blocking['blockers'], 'second_code': result['code']})
    except Exception as error:
        diagnostics = []
        for child in sessions.children:
            if child.poll() is not None and child.stderr and not child.stderr.closed:
                diagnostics.append(child.stderr.read().decode()[-5000:])
        exclusive_json(str(output) + '.failure.json', {
            'error': str(error), 'scenario': scenario, 'completed_cases': cases,
            'local_synthetic_diagnostics': diagnostics,
        })
        raise
    finally:
        sessions.close()
        if owners:
            database.query('SELECT m3b_cycle_test.remove_photos(ARRAY[' + ','.join(literal(x) for x in owners) + ']::uuid[])')
        cleanup_fixture(database, owners, ('b3b01000-0000-4000-8000-000000000501',))
    require(database.query("SELECT to_regnamespace('m3b_cycle_test') IS NULL AND NOT EXISTS(SELECT 1 FROM public.users)") == 't',
            'FULL fixture cleanup incomplete')
    result = {'status': 'PASS_PRIVATE_FULL_SQL_CONCURRENCY_ONLY', 'cases': cases, 'guard': database.guard,
              'fixture_sha256': hashlib.sha256(fixture.read_bytes()).hexdigest(),
              'request_source_sha256': hashlib.sha256((tests if scenario == 'regular' else fixture).read_bytes()).hexdigest(),
              'synthetic_fixture_purge': 'PASS; not customer account purge proof',
              'remote_operations': 0, 'provider_operations': 0, 'actual_BFF_QA': False, 'scenario': scenario}
    exclusive_json(output, result)
    return result


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--config', required=True)
    parser.add_argument('--output', required=True)
    parser.add_argument('--scenario', choices=['regular','legacy_transition','legacy_unassigned'], default='regular')
    args = parser.parse_args()
    db = LocalCycleDatabase(args.config)
    db.args.insert(1, '-q')
    result = run(db, args.output, args.scenario)
    print(json.dumps({'status': result['status'], 'cases': len(result['cases'])}))
