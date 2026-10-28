#!/usr/bin/env python3
"""Real HTTP/default clinical BFF/public SQL, one guarded ROLLBACK connection.

No providers or remote HTTP. Publication/config/QA effects are rolled back too.
"""
import argparse
import datetime
import hashlib
import json
import select
import shutil
import subprocess
from pathlib import Path

from run_mobile_health_hold_authority import Sessions, exclusive_json, require
from run_mobile_reevaluation_cycle import LocalCycleDatabase


def literal(value):
    if value is None:
        return 'NULL'
    if isinstance(value, bool):
        return 'true' if value else 'false'
    return "'" + (value if isinstance(value, str) else json.dumps(value)).replace("'", "''") + "'"


def run(database, output):
    root = Path(__file__).resolve().parents[3]
    folder = Path(__file__).resolve().parent
    output = Path(output).resolve()
    require(not output.exists(), 'Evidence exists')
    clean_sql = ("SELECT NOT EXISTS(SELECT 1 FROM public.users) AND to_regnamespace('m3b_cycle_test') IS NULL "
                 "AND NOT EXISTS(SELECT 1 FROM private.mobile_clinical_daily_keys) "
                 "AND NOT EXISTS(SELECT 1 FROM private.mobile_clinical_day_close_keys) "
                 "AND NOT EXISTS(SELECT 1 FROM net.http_request_queue)")
    require(database.query(clean_sql) == 't', 'Owned runtime not empty')
    global_sql = "SELECT jsonb_build_object(" + ','.join(
        literal(table) + ",coalesce((SELECT md5(jsonb_agg(to_jsonb(x) ORDER BY " + order + ")::text) FROM public."
        + table + " x),'empty')" for table, order in (
            ('global_config', 'key'), ('onboarding_legal_documents', 'id'),
            ('onboarding_legal_requirement_sets', 'id'), ('audit_log', 'id'))) + ')'
    original_globals = database.query(global_sql)
    runners = list((root / 'node_modules/.pnpm').glob('vite-node@*/node_modules/vite-node/vite-node.mjs'))
    node = shutil.which('node')
    require(node and len(runners) == 1, 'Runtime missing or ambiguous')
    owners = ['b3b01000-0000-4000-8000-000000003800', 'b3b01000-0000-4000-8000-000000003801']
    a, b = map(literal, owners)
    # Reuse the existing helper definitions, removing only its declared include;
    # the common cycle fixture is already loaded by the no-plan fixture.
    daily = (folder / 'mobile_clinical_daily_fixture.sql').read_text()
    include, helpers = daily.split('\n', 1)
    require(include == r'\ir mobile_clinical_full_fixture.sql' and r'\ir' not in helpers,
            'Daily helper include layout changed; refuse partial setup')
    fixture = folder / 'mobile_clinical_no_plan_fixture.sql'
    signatures = {
        'get_mobile_current_clinical_state': ['p_user_id', 'p_mode', 'p_body', 'p_expected'],
        'get_mobile_clinical_daily_receipt': ['p_user_id', 'p_operation_key'],
        'get_mobile_clinical_daily_context': ['p_user_id'],
        'apply_mobile_clinical_daily': ['p_user_id', 'p_operation_key', 'p_context_hash', 'p_calculation'],
        'get_mobile_clinical_day_close_receipt': ['p_user_id', 'p_operation_key'],
        'capture_mobile_clinical_day_close': ['p_user_id', 'p_from', 'p_close_date', 'p_expected_timezone'],
        'apply_mobile_clinical_day_close': ['p_user_id', 'p_operation_key', 'p_from', 'p_close_date', 'p_expected_timezone', 'p_context_hash', 'p_effect'],
        'get_mobile_signup_body_photo_snapshot': ['p_user_id', 'p_include_open_photos'],
        'get_mobile_clinical_first_phase_context': ['p_user_id'],
        'get_mobile_clinical_first_phase_prepared': ['p_user_id', 'p_preview_id', 'p_prepare_operation_key'],
        'get_mobile_clinical_first_phase_receipt': ['p_user_id', 'p_preview_id', 'p_operation_key'],
        'prepare_mobile_clinical_first_phase': ['p_user_id', 'p_operation_key', 'p_context_hash', 'p_selection', 'p_proposal'],
        'confirm_mobile_clinical_first_phase': ['p_user_id', 'p_preview_id', 'p_operation_key', 'p_selection', 'p_proposal'],
        'get_mobile_clinical_full_context': ['p_user_id', 'p_kind', 'p_cycle_id'],
        'get_mobile_clinical_full_command': ['p_user_id', 'p_preview_id', 'p_prepare_operation_key'],
        'prepare_mobile_clinical_full_command': ['p_user_id', 'p_kind', 'p_cycle_id', 'p_operation_key', 'p_context_hash', 'p_command', 'p_form', 'p_intent', 'p_proposal'],
        'prepare_mobile_clinical_full_presented_command': ['p_user_id', 'p_kind', 'p_cycle_id', 'p_operation_key', 'p_context_hash', 'p_command', 'p_form', 'p_intent', 'p_proposal', 'p_presentation'],
        'get_mobile_clinical_full_command_receipt': ['p_user_id', 'p_preview_id', 'p_operation_key'],
        'confirm_mobile_clinical_full_command': ['p_user_id', 'p_preview_id', 'p_operation_key', 'p_command', 'p_form', 'p_intent', 'p_proposal'],
    }
    allowed_columns = {
        'users': {'id', 'wpp', 'timezone'},
        'user_profiles': {'user_id', 'current_protocol', 'body_fat_percent', 'onboarding_completed', 'onboarding_completed_at'},
        'user_progress': {'user_id', 'xp_total', 'level', 'current_streak', 'longest_streak', 'blocks_completed',
                          'deficit_block', 'current_weight', 'current_bf_percent', 'badges_earned', 'last_active_date',
                          'next_reevaluation', 'updated_at'},
        'daily_snapshots': {'user_id', 'date', 'day_closed'},
        'meal_logs': {'user_id', 'consumed_at'},
        'workout_logs': {'user_id', 'performed_at'},
        'messages': {'user_id', 'created_at', 'direction'},
    }
    witness_sql = f"""SELECT jsonb_build_object(
      'applications_A',(SELECT count(*) FROM private.mobile_clinical_daily_applications WHERE user_id={a}),
      'closed_A',(SELECT count(*) FROM public.daily_snapshots WHERE user_id={a} AND day_closed),
      'day_target_A',(SELECT calories_target FROM public.daily_snapshots WHERE user_id={a} AND date=(clock_timestamp() AT TIME ZONE 'America/Sao_Paulo')::date-2),
      'source_day_target_A',(SELECT calories_target FROM public.daily_snapshots WHERE user_id={a} AND date=(clock_timestamp() AT TIME ZONE 'America/Sao_Paulo')::date-6),
      'source_day_closed_A',(SELECT day_closed FROM public.daily_snapshots WHERE user_id={a} AND date=(clock_timestamp() AT TIME ZONE 'America/Sao_Paulo')::date-6),
      'today_snapshots_A',(SELECT count(*) FROM public.daily_snapshots WHERE user_id={a} AND date=(clock_timestamp() AT TIME ZONE 'America/Sao_Paulo')::date),
      'today_target_A',(SELECT calories_target FROM public.daily_snapshots WHERE user_id={a} AND date=(clock_timestamp() AT TIME ZONE 'America/Sao_Paulo')::date),
      'application_state_A',(SELECT state FROM private.mobile_clinical_daily_applications WHERE user_id={a} ORDER BY application_no DESC LIMIT 1),
      'suspended_target_A',(SELECT calories_target FROM private.mobile_clinical_daily_applications WHERE user_id={a} ORDER BY application_no DESC LIMIT 1),
      'guarded_calculation_null',(SELECT calculation='{{"version":1,"formulaKcal":null,"maintenanceKcal":null,"sedentaryKcal":null,"proteinTarget":null,"maintenanceProteinTarget":null}}'::jsonb FROM private.mobile_clinical_daily_applications WHERE user_id={a} ORDER BY application_no DESC LIMIT 1),
      'xp_A',(SELECT xp_total FROM public.user_progress WHERE user_id={a}),
      'xp_B',(SELECT xp_total FROM public.user_progress WHERE user_id={b}),
      'phase_B',(SELECT current_protocol FROM public.user_profiles WHERE user_id={b}),
      'weight_B',(SELECT weight_kg FROM public.user_profiles WHERE user_id={b}),
      'episodes_B',(SELECT count(*) FROM private.mobile_clinical_episode_events WHERE user_id={b}),
      'full_B',(SELECT count(*) FROM private.mobile_clinical_full_receipts WHERE user_id={b}),
      'weights_B',(SELECT count(*) FROM private.mobile_weight_measurements WHERE user_id={b}),
      'clears_B',(SELECT count(*) FROM private.mobile_clinical_health_clear_receipts WHERE user_id={b}),
      'health_B',public.get_mobile_health_hold_state({b}),
      'due_B',public.get_mobile_reevaluation_cycle({b})#>'{{clock,due_date}}',
      'day_events_B',(SELECT count(*) FROM private.mobile_clinical_day_events WHERE user_id={b}),
      'snapshots_B',(SELECT count(*) FROM public.daily_snapshots WHERE user_id={b}),
      'confirmation_keys_B',(SELECT count(*) FROM private.mobile_clinical_confirmation_keys WHERE user_id={b}),
      'first_previews_B',(SELECT count(*) FROM private.mobile_clinical_first_phase_previews WHERE user_id={b}),
      'first_confirmations_B',(SELECT count(*) FROM private.mobile_clinical_first_phase_confirmations WHERE user_id={b}),
      'first_keys_B',(SELECT count(*) FROM private.mobile_clinical_first_phase_keys WHERE user_id={b}),
      'current_target_B',(SELECT calories_target FROM public.daily_snapshots WHERE user_id={b} AND date=(clock_timestamp() AT TIME ZONE (SELECT timezone FROM public.users WHERE id={b}))::date),
      'latest_episode_B',(SELECT to_jsonb(e) FROM private.mobile_clinical_episode_events e WHERE user_id={b} ORDER BY event_no DESC LIMIT 1),
      'effective_episode_B',to_jsonb(private.mobile_clinical_effective_episode({b},
       (SELECT admission_id FROM private.mobile_signup_strength_completion_receipts WHERE user_id={b}),
       (SELECT epoch FROM private.mobile_signup_strength_completion_receipts WHERE user_id={b}))),
      'effects_B',md5(jsonb_build_object('rows',m3b_cycle_test.original_state({b})-ARRAY['private.mobile_clinical_confirmation_keys','private.mobile_clinical_first_phase_keys'],
        'cycles',(SELECT jsonb_agg(to_jsonb(c) ORDER BY cycle_id) FROM private.mobile_reevaluation_cycles c WHERE user_id={b}),
        'start_keys',(SELECT jsonb_agg(to_jsonb(k) ORDER BY to_jsonb(k)::text) FROM private.mobile_reevaluation_start_keys k WHERE user_id={b}))::text),
      'applications_B',(SELECT count(*) FROM private.mobile_clinical_daily_applications WHERE user_id={b}),
      'daily_keys_B',(SELECT count(*) FROM private.mobile_clinical_daily_keys WHERE user_id={b}));"""
    sessions, bridge = Sessions(database), None
    result, failure, risk_armed = None, None, False
    rpc_count, select_count, start_count, injected_count, risk_count, reset_count, advance_count, assigned_start_count = 0, 0, 0, 0, 0, 0, 0, 0
    child_stderr, sql_stderr, session = '', '', None
    try:
        session = sessions.spawn("BEGIN;SET LOCAL request.jwt.claim.role='service_role';\n\\i '" + str(fixture) + "'\n"
            + helpers + f"""
          SELECT m3b_cycle_test.scheduled(3800,'recomp_to_maintenance',clock_timestamp()-interval '6 days');
          UPDATE public.user_profiles SET body_fat_percent=NULL WHERE user_id={a};
          SELECT m3b_cycle_test.no_plan_signup(3801);
          UPDATE public.users SET timezone='Etc/GMT+12' WHERE id={b};
          INSERT INTO public.user_progress(user_id,xp_total,current_streak,longest_streak,last_active_date)
          VALUES({a},40,2,3,(clock_timestamp() AT TIME ZONE 'America/Sao_Paulo')::date-3),
                ({b},42,2,3,(clock_timestamp() AT TIME ZONE 'America/Sao_Paulo')::date);
          WITH day AS (INSERT INTO public.daily_snapshots(user_id,date,calories_target,protein_target)
            VALUES({a},(clock_timestamp() AT TIME ZONE 'America/Sao_Paulo')::date-2,2000,130) RETURNING id,date)
          INSERT INTO public.meal_logs(user_id,snapshot_id,meal_type,food_name,quantity_g,kcal,protein_g,carbs_g,fat_g,consumed_at)
            SELECT {a},id,'almoco','synthetic HTTP meal',600,1600,100,90,20,(date+time '12:00') AT TIME ZONE 'America/Sao_Paulo' FROM day;
          INSERT INTO public.global_config(key,value) VALUES('calc.protein_factors','{{"muita":1.6,"moderada":1.8,"pouca":1.8,"training_low":1.7,"optimal_mid_training":1.9,"optimal_high_training":2}}')
            ON CONFLICT(key) DO UPDATE SET value=excluded.value,updated_at=clock_timestamp();
          CREATE FUNCTION pg_temp.owned_rpc(statement text) RETURNS jsonb LANGUAGE plpgsql AS $rpc$
          DECLARE data jsonb;BEGIN EXECUTE statement INTO data;RETURN jsonb_build_object('data',data,'error',NULL);
            EXCEPTION WHEN OTHERS THEN RETURN jsonb_build_object('data',NULL,'error',jsonb_build_object('code',SQLSTATE)); END $rpc$;
          GRANT EXECUTE ON FUNCTION pg_temp.owned_rpc(text) TO service_role;
          SELECT 'READY';
          """)
        sessions.until(session, lambda line: line == 'READY')
        bridge = subprocess.Popen([node, str(runners[0]), '--script', str(folder / 'mobile_clinical_http_bridge.ts')],
            cwd=root, env=dict(database.env, PERFORME_CLINICAL_HTTP_QA='owned-local-rollback'),
            stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        while True:
            ready, _, _ = select.select([bridge.stdout], [], [], 20)
            require(ready, 'Child observation timeout')
            line = bridge.stdout.readline();require(line, 'Child ended before result')
            packet = json.loads(line)
            if packet['type'] == 'done':
                result = packet;break
            require(packet['type'] != 'failure', 'HTTP bridge assertions failed; inspect child log')
            inject_after = False
            if packet['type'] == 'rpc':
                rpc_count += 1;require(rpc_count <= 110, 'RPC budget exceeded')
                name, args = packet['name'], packet['args']
                require(name in signatures and set(args) == set(signatures[name]), 'Unapproved RPC/signature')
                require(packet['owner'] in owners and args['p_user_id'] == packet['owner'], 'Cross-owner RPC refused')
                if name == 'get_mobile_current_clinical_state':
                    require(args['p_mode'] == 'profile' and args['p_body'] is None and args['p_expected'] is None, 'Non-profile override refused')
                if name == 'get_mobile_signup_body_photo_snapshot':
                    require(args['p_include_open_photos'] is False, 'Open photo read refused')
                call = 'SELECT public.' + name + '(' + ','.join(literal(args[k]) for k in signatures[name]) + ')'
                sql = "SET LOCAL ROLE service_role;SELECT pg_temp.owned_rpc(" + literal(call) + ");RESET ROLE;"
                inject_after = risk_armed and name == 'get_mobile_clinical_daily_context'
            elif packet['type'] == 'select':
                select_count += 1;require(select_count <= 80, 'SELECT budget exceeded')
                table, columns = packet['table'], [v.strip() for v in packet['columns'].split(',')]
                require(table in allowed_columns and columns and set(columns) <= allowed_columns[table], 'Table/columns refused')
                filters = packet['filters'];owner_key = 'id' if table == 'users' else 'user_id'
                require(packet['owner'] in owners and any(f == {'column': owner_key, 'op': '=', 'value': packet['owner']} for f in filters), 'Owner SELECT filter missing')
                require(all(f['column'] in allowed_columns[table] and f['op'] in ('=', '>=', '<=', '<') for f in filters), 'Filter refused')
                selection = 'SELECT ' + ','.join('"' + col + '"' for col in columns) + ' FROM public."' + table + '" WHERE '
                selection += ' AND '.join('"' + f['column'] + '"' + f['op'] + literal(f['value']) for f in filters)
                if packet['order'] is not None:
                    order = packet['order'];require(order['column'] in allowed_columns[table] and isinstance(order['ascending'], bool), 'Order refused')
                    selection += ' ORDER BY "' + order['column'] + '" ' + ('ASC' if order['ascending'] else 'DESC')
                if packet['limit'] is not None:
                    limit = packet['limit'];require(type(limit) is int and 0 < limit <= 1000, 'Limit refused');selection += ' LIMIT ' + str(limit)
                aggregate = "SELECT coalesce(jsonb_agg(to_jsonb(x)),'[]'::jsonb) FROM (" + selection + ') x'
                sql = 'SET LOCAL ROLE service_role;SELECT pg_temp.owned_rpc(' + literal(aggregate) + ');RESET ROLE;'
            elif packet['type'] == 'arm_risk':
                require(packet['owner'] == owners[0] and not risk_armed and injected_count == 0, 'Risk control refused')
                risk_armed = True;sql = "SELECT '{\"armed\":true}'::jsonb;"
            elif packet['type'] == 'start_no_plan':
                start_count += 1;require(start_count == 1 and packet['owner'] == owners[1], 'Start control refused')
                # Only occurrence setup is private; the real service must
                # calculate, normalize, prepare and confirm through public RPCs.
                sql = f"SELECT jsonb_build_object('cycle',private.start_mobile_clinical_full_at({b},gen_random_uuid(),'EARLY_FULL','not_well_with_plan',NULL)#>'{{cycle,id}}');"
            elif packet['type'] == 'advance_first_civil_day':
                advance_count += 1;require(advance_count == 1 and packet['owner'] == owners[1], 'Civil date control refused')
                sql = f"""DO $advance$ BEGIN IF (SELECT timezone FROM public.users WHERE id={b})<>'Etc/GMT+12'
                  THEN RAISE EXCEPTION 'Synthetic civil date source changed';END IF;END $advance$;
                  UPDATE public.users SET timezone='Pacific/Kiritimati' WHERE id={b};
                  SELECT jsonb_build_object('date',(clock_timestamp() AT TIME ZONE 'Pacific/Kiritimati')::date);"""
            elif packet['type'] == 'start_assigned':
                assigned_start_count += 1;require(assigned_start_count == 1 and packet['owner'] == owners[1], 'Assigned start control refused')
                sql = f"SELECT jsonb_build_object('cycle',private.start_mobile_clinical_full_at({b},gen_random_uuid(),'EARLY_FULL','not_well_with_plan',NULL)#>'{{cycle,id}}');"
            elif packet['type'] == 'risk_no_plan':
                risk_count += 1;require(risk_count == 1 and packet['owner'] == owners[1], 'New risk control refused')
                sql = f"SELECT jsonb_build_object('health',public.declare_mobile_health_risk({b},gen_random_uuid(),ARRAY['reduced_intake']));"
            elif packet['type'] == 'reset_no_plan':
                reset_count += 1;require(reset_count == 1 and packet['owner'] == owners[1], 'Reset control refused')
                sql = f"DO $reset$ BEGIN PERFORM public.reset_user_conversation_atomic({b},true);END $reset$;SELECT '{{\"reset\":true}}'::jsonb;"
            elif packet['type'] == 'witness':
                sql = witness_sql
            else:
                raise ValueError('Unexpected child operation')
            session.stdin.write((sql + "\nSELECT 'REPLY';\n").encode());session.stdin.flush()
            lines = sessions.until(session, lambda item: item == 'REPLY')
            reply = json.loads(next(item for item in lines if item.startswith('{')))
            if packet['type'] == 'select' and reply['error'] is None:
                data = reply['data'];require(isinstance(data, list), 'SELECT rows malformed')
                if packet['single']:
                    require(len(data) <= 1, 'Multiple single rows');reply['data'] = data[0] if data else None
            if inject_after:
                session.stdin.write((f"SELECT public.declare_mobile_health_risk({a},gen_random_uuid(),ARRAY['reduced_intake']);\nSELECT 'INJECTED';\n").encode());session.stdin.flush()
                sessions.until(session, lambda item: item == 'INJECTED');risk_armed = False;injected_count += 1
            bridge.stdin.write(json.dumps(reply) + '\n');bridge.stdin.flush()
        bridge.stdin.close();bridge.wait(timeout=10);child_stderr = bridge.stderr.read()
        require(bridge.returncode == 0 and result['status'] == 'PASS_ACTUAL_HTTP_DEFAULT_CLINICAL_SERVICES_SQL'
                and len(result['cases']) == 27 and injected_count == 1 and start_count == 1
                and risk_count == 1 and reset_count == 1 and advance_count == 1 and assigned_start_count == 1, 'Bridge result incomplete')
        sessions.finish(session, 'ROLLBACK;\n')
    except Exception as error:
        failure = {'type': type(error).__name__, 'message': str(error)}
    finally:
        if bridge and bridge.poll() is None:
            bridge.terminate();bridge.wait(timeout=5)
        if bridge and not child_stderr:
            child_stderr = bridge.stderr.read()
        if session and session.poll() is not None and not session.stderr.closed:
            sql_stderr = session.stderr.read().decode()[-12000:]
        sessions.close()
    clean = database.query(clean_sql) == 't'
    globals_preserved = database.query(global_sql) == original_globals
    with (Path(str(output) + '.child.log')).open('x') as f:
        f.write(child_stderr + '\nSQL diagnostic:\n' + sql_stderr)
    receipt = {'at_utc': datetime.datetime.now(datetime.timezone.utc).isoformat(),
        'status': 'PASS' if not failure and clean and globals_preserved else 'FAIL',
        'bridge': result, 'failure': failure, 'rpc_calls': rpc_count, 'table_selects': select_count,
        'guard': database.guard, 'all_rolled_back': clean, 'legal_config_audit_rows_preserved': globals_preserved,
        'controlled_context_change': injected_count, 'real_concurrent_commit_race': False,
        'actual_health_only_FULL_service': bool(result and not failure), 'health_only_start_private_setup': True,
        'health_only_original_replay_after_new_risk_and_reset': bool(result and not failure),
        'fixture_sources_sha256': {p.name: hashlib.sha256(p.read_bytes()).hexdigest() for p in (fixture, folder / 'mobile_clinical_daily_fixture.sql')},
        'deployed_HTTP_QA': False, 'PostgREST_QA': False, 'Native_QA': False, 'Storage_QA': False,
        'provider_operations': 0, 'remote_operations': 0, 'new_paid_resources': 0}
    exclusive_json(output, receipt)
    require(receipt['status'] == 'PASS', 'Actual HTTP/default-service local QA failed; inspect receipt/child log')
    return receipt


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--config', required=True);parser.add_argument('--output', required=True)
    args = parser.parse_args()
    report = run(LocalCycleDatabase(args.config), args.output)
    print(json.dumps({'status': report['status'], 'RPCs': report['rpc_calls'], 'SELECTs': report['table_selects']}))
