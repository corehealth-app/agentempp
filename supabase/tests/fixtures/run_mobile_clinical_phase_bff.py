#!/usr/bin/env python3
"""Current all-phase BFF/SQL, synthetic history, one owned ROLLBACK session."""
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
    require(not output.exists(), 'Evidence exists')
    clean_sql = "SELECT NOT EXISTS(SELECT 1 FROM public.users) AND to_regnamespace('m3b_cycle_test') IS NULL AND NOT EXISTS(SELECT 1 FROM net.http_request_queue)"
    require(database.query(clean_sql) == 't', 'Owned runtime not clean')
    config_sql = 'SELECT jsonb_build_object(' + ','.join(
        literal(table) + ",coalesce((SELECT md5(jsonb_agg(to_jsonb(x) ORDER BY " + order + ")::text) FROM public." + table + " x),'empty')"
        for table, order in [('global_config', 'key'), ('onboarding_legal_documents', 'id'),
                             ('onboarding_legal_requirement_sets', 'id'), ('audit_log', 'id')]) + ')'
    before = database.query(config_sql)
    cases = {
        'recomp_transition': ('recomposicao', 18, 1700),
        'maintenance_recomp': ('manutencao', 24, 2400),
        'maintenance_step': ('manutencao', 18, 2400),
        'gain_step': ('ganho_massa', 15, 3000),
        'gain_exit': ('ganho_massa', 15, 3100),
        'gain_exit_complete': ('ganho_massa', 15, 2400),
        'guarded_keep': ('recomposicao', 24, 1700),
        'closed_transition': ('recomposicao', 18, 1700),
        'gain_without_history': ('manutencao', 18, 2400),
        'direct_recomp_gain': ('recomposicao', 18, 1700),
        'direct_gain_recomp': ('ganho_massa', 15, 3000),
        'maintenance_gain': ('manutencao', 18, 2400),
        'maintenance_recomp_choice': ('manutencao', 18, 2400),
        'gain_sparse_history': ('manutencao', 18, 2400),
        'missing_day': ('recomposicao',24,1700),
        'null_target': ('recomposicao',24,1700),
        'legacy_null_guard': ('recomposicao',24,1700),
    }
    signatures = {
        'get_mobile_clinical_full_context': ['p_user_id', 'p_kind', 'p_cycle_id'],
        'get_mobile_clinical_full_command': ['p_user_id', 'p_preview_id', 'p_prepare_operation_key'],
        'prepare_mobile_clinical_full_command': ['p_user_id', 'p_kind', 'p_cycle_id', 'p_operation_key', 'p_context_hash', 'p_command', 'p_form', 'p_intent', 'p_proposal'],
        'get_mobile_clinical_full_command_receipt': ['p_user_id', 'p_preview_id', 'p_operation_key'],
        'confirm_mobile_clinical_full_command': ['p_user_id', 'p_preview_id', 'p_operation_key', 'p_command', 'p_form', 'p_intent', 'p_proposal'],
        'get_mobile_clinical_daily_receipt': ['p_user_id','p_operation_key'],
        'get_mobile_clinical_daily_context': ['p_user_id'],
        'apply_mobile_clinical_daily': ['p_user_id','p_operation_key','p_context_hash','p_calculation'],
    }
    runners = list((root / 'node_modules/.pnpm').glob('vite-node@*/node_modules/vite-node/vite-node.mjs'))
    node = shutil.which('node')
    require(node and len(runners) == 1, 'Runtime missing/ambiguous')
    sessions, session, bridge = Sessions(database), None, None
    failure, result, child_log, owner, last_type = None, None, '', None, None
    seeded, calls, reads = [], 0, 0
    prospective_actions, previous_snapshots = set(), {}
    try:
        session = sessions.spawn("BEGIN;SET LOCAL request.jwt.claim='{" + '"role":"service_role"' + "}';\n\\i '"
            + str(folder / 'mobile_clinical_phase_fixture.sql') + "'\n"
            + "CREATE FUNCTION pg_temp.full_rpc(statement text) RETURNS jsonb LANGUAGE plpgsql AS $rpc$ DECLARE data jsonb;BEGIN "
            "EXECUTE statement INTO data;RETURN jsonb_build_object('data',data,'error',NULL);EXCEPTION WHEN OTHERS THEN "
            "RETURN jsonb_build_object('data',NULL,'error',jsonb_build_object('code',SQLSTATE));END $rpc$;"
            "GRANT EXECUTE ON FUNCTION pg_temp.full_rpc(text) TO service_role;SELECT 'READY';\n")
        sessions.until(session, lambda line: line == 'READY')
        bridge = subprocess.Popen([node, str(runners[0]), '--script', str(folder / 'mobile_clinical_phase_bff_bridge.ts')],
            cwd=root, env=dict(database.env, PERFORME_CLINICAL_PHASE_QA='owned-local-rollback'),
            stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        while True:
            require(select.select([bridge.stdout], [], [], 20)[0], 'Child observation timeout')
            line = bridge.stdout.readline(); require(line, 'Child closed unexpectedly')
            packet = json.loads(line); last_type = packet.get('type')
            if packet['type'] == 'result':
                result = packet; break
            require(packet['type'] != 'failure', 'Child assertion failed')
            if packet['type'] == 'seed':
                name = packet['case']; require(name in cases and name not in seeded, 'Seed refused')
                require(name == list(cases)[len(seeded)], 'Case order differs')
                n = 4500 + len(seeded); seeded.append(name); owner = f'b3b01000-0000-4000-8000-{n:012d}'
                phase, mean, target = cases[name]
                arguments = [n, phase, mean, target, 56,
                             name in ['maintenance_gain', 'maintenance_recomp_choice', 'gain_sparse_history'],
                             name == 'gain_sparse_history']
                sql = ('SELECT m3b_cycle_test.clinical_photos('+str(n)+');' if name=='legacy_null_guard'
                       else 'SELECT m3b_cycle_test.phase_context(' + ','.join(map(literal, arguments)) + ');')
            elif packet['type'] == 'rpc':
                calls += 1; require(calls <= 210, 'RPC bound exceeded')
                name, args = packet['name'], packet['args']
                require(name in signatures and set(args) == set(signatures[name]) and args['p_user_id'] == owner, 'RPC scope refused')
                statement = 'SELECT public.' + name + '(' + ','.join(literal(args[k]) for k in signatures[name]) + ')'
                sql = 'SET LOCAL ROLE service_role;SELECT pg_temp.full_rpc(' + literal(statement) + ');RESET ROLE;'
            elif packet['type'] == 'state':
                reads += 1; require(owner and reads <= 85, 'State bound exceeded')
                today = "(clock_timestamp() AT TIME ZONE (SELECT timezone FROM public.users WHERE id=" + literal(owner) + "))::date"
                sql = "SELECT jsonb_build_object('phase',(SELECT current_protocol FROM public.user_profiles WHERE user_id=" + literal(owner) + "),"
                sql += "'deficit_level',(SELECT deficit_level FROM public.user_profiles WHERE user_id="+literal(owner)+"),"
                sql += "'day',(SELECT to_jsonb(s) FROM public.daily_snapshots s WHERE user_id=" + literal(owner) + " AND date="+today+"),"
                sql += "'episode',(SELECT jsonb_build_object('phase',v.phase,'deficit_level',v.deficit_level,'ledger_steps',v.ledger_steps,'maintenance_since',v.maintenance_since,'difficulty_count',v.difficulty_count::text,'schedule',v.schedule) FROM private.mobile_signup_strength_completion_receipts o CROSS JOIN LATERAL private.mobile_clinical_effective_episode(o.user_id,o.admission_id,o.epoch) v WHERE o.user_id=" + literal(owner) + "),"
                sql += "'fulls',(SELECT count(*) FROM private.mobile_clinical_full_receipts WHERE user_id=" + literal(owner) + "),'keys',(SELECT count(*) FROM private.mobile_clinical_confirmation_keys WHERE user_id=" + literal(owner) + "),'weights',(SELECT count(*) FROM private.mobile_weight_measurements WHERE user_id=" + literal(owner) + "),"
                sql += "'effects_hash',md5(m3b_cycle_test.original_state(" + literal(owner) + ")::text),"
                sql += "'confirmed_effects_hash',md5((m3b_cycle_test.original_state("+literal(owner)+")-'private.mobile_clinical_previews'-'private.mobile_clinical_full_commands')::text),"
                sql += "'origin',(SELECT private.mobile_clinical_target_origin(o.user_id,o.admission_id,o.epoch,"+today+",clock_timestamp()) FROM private.mobile_signup_strength_completion_receipts o WHERE o.user_id=" + literal(owner) + "),"
                sql += "'prior_hash',(SELECT md5(to_jsonb(s)::text) FROM public.daily_snapshots s WHERE user_id="+literal(owner)+" AND id="+literal(previous_snapshots.get(owner))+"::uuid),"
                sql += "'decisions_hash',md5((SELECT coalesce(jsonb_agg(to_jsonb(d) ORDER BY review_id),'[]'::jsonb)::text FROM private.mobile_clinical_calorie_decisions d WHERE user_id="+literal(owner)+")),"
                sql += "'origin_hash',md5(jsonb_build_object('journal',(SELECT jsonb_agg(to_jsonb(o) ORDER BY origin_id) FROM private.mobile_clinical_target_origins o WHERE user_id=" + literal(owner) + "),'heads',(SELECT jsonb_agg(to_jsonb(h) ORDER BY snapshot_id) FROM private.mobile_clinical_target_origin_heads h WHERE user_id=" + literal(owner) + "))::text),"
                sql += "'cycle_hash',md5(jsonb_build_object('cycles',(SELECT jsonb_agg(to_jsonb(c) ORDER BY cycle_id) FROM private.mobile_reevaluation_cycles c WHERE user_id=" + literal(owner) + "),'keys',(SELECT jsonb_agg(to_jsonb(k) ORDER BY to_jsonb(k)::text) FROM private.mobile_reevaluation_start_keys k WHERE user_id=" + literal(owner) + "))::text),"
                sql += "'clock',public.get_mobile_reevaluation_cycle(" + literal(owner) + ")->'clock');"
            elif packet['type'] == 'prospective':
                action = packet['action']; name = seeded[-1]
                require(name in ['missing_day','closed_transition'] and action in ['advance','unknown_existing','early_cycle'], 'Prospective scope refused')
                require((owner,action) not in prospective_actions, 'Prospective action repeated')
                require(action=='advance' or (owner,'advance') in prospective_actions, 'Advance required')
                require(name=='missing_day' or action=='advance', 'Closed fixture mutation refused')
                prospective_actions.add((owner,action))
                if action=='advance':
                    # Two real time zones >24h apart guarantee a later civil
                    # date, while the public daily RPC still uses the SQL clock.
                    # Preserve the exact original snapshot for later comparison.
                    sql="SELECT id::text FROM public.daily_snapshots WHERE user_id="+literal(owner)+" AND date=(clock_timestamp() AT TIME ZONE 'Etc/GMT+12')::date;"
                    session.stdin.write((sql+"\nSELECT 'PRIOR';\n").encode());session.stdin.flush()
                    prior=sessions.until(session,lambda line:line=='PRIOR')
                    candidates=[v for v in prior if len(v)==36 and v.count('-')==4]
                    require(len(candidates)==1,'Previous snapshot ambiguous')
                    previous_snapshots[owner]=candidates[0]
                    sql="UPDATE public.users SET timezone='Pacific/Kiritimati' WHERE id="+literal(owner)+";"
                    if name=='missing_day':
                        sql+="UPDATE public.user_profiles SET body_fat_percent=45 WHERE user_id="+literal(owner)+";"
                    sql+="SELECT jsonb_build_object('prior_hash',(SELECT md5(to_jsonb(s)::text) FROM public.daily_snapshots s WHERE id="+literal(candidates[0])+"::uuid));"
                elif action=='unknown_existing':
                    sql="UPDATE public.daily_snapshots SET calories_target=1099 WHERE user_id="+literal(owner)+" AND date=(clock_timestamp() AT TIME ZONE 'Pacific/Kiritimati')::date;SELECT '{}'::jsonb;"
                else:
                    sql="SELECT private.start_mobile_clinical_full_at("+literal(owner)+",gen_random_uuid(),'EARLY_FULL','not_well_with_plan',NULL);"
            else:
                raise ValueError('Child request refused')
            if packet['type'] == 'seed' and packet['case'] in ['guarded_keep', 'closed_transition','missing_day','null_target','legacy_null_guard']:
                # Capture seed output exactly once, then mutate only this known
                # synthetic owner's safety/closed-day fixture before reply.
                zone = "UPDATE public.users SET timezone='Etc/GMT+12' WHERE id=a;UPDATE public.daily_snapshots SET date=(clock_timestamp() AT TIME ZONE 'Etc/GMT+12')::date WHERE user_id=a;" if packet['case'] in ['closed_transition','missing_day'] else ''
                extra = zone + {
                    'guarded_keep':"PERFORM public.declare_mobile_health_risk(a,gen_random_uuid(),ARRAY['reduced_intake']);",
                    'closed_transition':"UPDATE public.daily_snapshots SET day_closed=true,closed_at=clock_timestamp() WHERE user_id=a;",
                    'missing_day':"DELETE FROM public.daily_snapshots WHERE user_id=a;",
                    'null_target':"UPDATE public.daily_snapshots SET calories_target=NULL WHERE user_id=a;",
                    'legacy_null_guard':"UPDATE public.user_profiles SET deficit_level=NULL WHERE user_id=a;INSERT INTO public.daily_snapshots(user_id,date,calories_target,protein_target,current_protocol,calories_consumed,exercise_calories) VALUES(a,(clock_timestamp() AT TIME ZONE 'America/Sao_Paulo')::date,1700,144,'recomposicao',200,50);PERFORM public.declare_mobile_health_risk(a,gen_random_uuid(),ARRAY['reduced_intake']);",
                }[packet['case']]
                seed_call = sql.removeprefix('SELECT ').removesuffix(';')
                sql = "DO $seed$ DECLARE c jsonb;a uuid;BEGIN c:=" + seed_call + ";a:=(c->>'user')::uuid;" + extra + "PERFORM set_config('m3b.phase_seed',c::text,true);END $seed$;SELECT current_setting('m3b.phase_seed')::jsonb;"
            session.stdin.write((sql + "\nSELECT 'REPLY';\n").encode()); session.stdin.flush()
            lines = sessions.until(session, lambda line: line == 'REPLY')
            values = [row for row in lines if row.startswith('{')]
            require(len(values) == 1, 'Unexpected reply cardinality')
            bridge.stdin.write(values[0] + '\n'); bridge.stdin.flush()
        bridge.stdin.close(); bridge.wait(timeout=10); child_log = bridge.stderr.read()
        require(bridge.returncode == 0 and result['status'] == 'PASS_CURRENT_ALL_PHASE_SERVICE_SQL' and len(result['cases']) == 17, 'Terminal qualification differs')
        sessions.finish(session, 'SET CONSTRAINTS ALL IMMEDIATE;ROLLBACK;\n')
    except Exception as error:
        failure = str(error)
    finally:
        if bridge and bridge.poll() is None:
            bridge.terminate()
            try: bridge.wait(timeout=5)
            except subprocess.TimeoutExpired: bridge.kill(); bridge.wait(timeout=5)
        if bridge and bridge.stderr and not child_log: child_log = bridge.stderr.read()
        if session and session.poll() is not None and not session.stderr.closed: child_log += '\nSQL:\n' + session.stderr.read().decode()[-8000:]
        sessions.close()
    clean = database.query(clean_sql) == 't'; preserved = database.query(config_sql) == before
    with Path(str(output) + '.child.log').open('x') as stream: stream.write(child_log)
    report = {'at_utc': datetime.datetime.now(datetime.timezone.utc).isoformat(), 'status': 'PASS' if not failure and clean and preserved else 'FAIL',
              'failure': failure, 'last_type': last_type, 'seeded_cases': seeded, 'bridge': result, 'RPCs': calls, 'state_reads': reads,
              'all_rolled_back': clean, 'config_legal_audit_preserved': preserved, 'historical_signup_evidence': 'explicit synthetic fixture; actual insertion capture trigger; not historical onboarding emission proof',
              'prospective_actions': len(prospective_actions),
              'provider': False, 'Storage': False, 'PostgREST': False, 'deployed_HTTP': False, 'remote_operations': 0, 'new_paid_resources': 0}
    exclusive_json(output, report); require(report['status'] == 'PASS', 'Phase BFF/SQL failed; inspect evidence')
    return report


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--config', required=True); parser.add_argument('--output', required=True)
    args = parser.parse_args(); report = run(LocalCycleDatabase(args.config), args.output)
    print(json.dumps({'status': report['status'], 'RPCs': report['RPCs']}))
