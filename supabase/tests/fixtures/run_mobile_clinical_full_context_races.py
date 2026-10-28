#!/usr/bin/env python3
"""Actual owner-lock races: valid locale changes and final pending callback/FULL.

Only the task-owned, guarded local UNIX-socket database; no provider or Storage.
"""
import argparse
import json
import time
from decimal import Decimal
from pathlib import Path

from run_mobile_reevaluation_cycle import LocalCycleDatabase
from run_mobile_health_hold_authority import Sessions, exclusive_json, require
from run_mobile_clinical_full import literal, confirmation, lossless_json
from run_mobile_reevaluation_photo_consent import cleanup_fixture


def run(database, output):
    output = Path(output).resolve()
    require(not output.exists(), 'Evidence already exists')
    root = Path(__file__).resolve().parents[3]
    folder = Path(__file__).resolve().parent
    require(database.query("SELECT NOT EXISTS(SELECT 1 FROM public.users) AND "
                           "to_regnamespace('m3b_cycle_test') IS NULL") == 't', 'Fixture collision')
    require(database.run_file(folder / 'mobile_clinical_full_fixture.sql',
                              str(output) + '.setup.log') == 0, 'Fixture setup failed')
    source = (root / 'supabase/tests/mobile_clinical_full_conclusion.sql').read_text()
    start = source.index('CREATE FUNCTION m3b_cycle_test.clinical_request(')
    end = source.index('\nEND $$;', start) + len('\nEND $$;')
    database.query(source[start:end])
    source = (root / 'supabase/tests/mobile_clinical_full_effect_rollback.sql').read_text()
    start = source.index('CREATE FUNCTION m3b_cycle_test.effect_state(')
    end = source.index('\n$$;', start) + len('\n$$;')
    database.query(source[start:end])
    database.query("""
      CREATE FUNCTION m3b_cycle_test.context_race_try(statement text) RETURNS jsonb
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
    sessions, owners, cases = Sessions(database), [], []
    observed = None
    try:
        for index, mode in enumerate(('locale_then_full', 'locale_then_callback',
                                      'final_pending_callback_then_full_prepare'), 6200):
            if mode == 'locale_then_callback':
                c = json.loads(database.query(f'SELECT m3b_cycle_test.ready_photo({index})'))
            else:
                c = json.loads(database.query(f'SELECT m3b_cycle_test.clinical_photos({index})'))
            owner, cycle = c['user'], c['cycle']
            owners.append(owner)
            q = None
            if mode == 'locale_then_full':
                q = json.loads(database.query('SELECT m3b_cycle_test.clinical_request('
                                              + literal(c) + '::jsonb)'), parse_float=Decimal)
                first_sql = 'UPDATE public.users SET locale=\'en-US\' WHERE id=' + literal(owner) + ';'
                second_sql = confirmation(owner, q, f'b3b01000-1000-4000-8000-{index:012d}')
            else:
                if mode == 'final_pending_callback_then_full_prepare':
                    c['revision'] = database.query('SELECT revision FROM private.mobile_reevaluation_cycles '
                                                   'WHERE cycle_id=' + literal(cycle))
                    allocation = json.loads(database.query('SELECT m3b_cycle_test.allocate('
                        + literal(c) + "::jsonb,gen_random_uuid(),'back')"))
                    asset = allocation['asset']['id']
                    ticket = database.query('SELECT gen_random_uuid()')
                    database.query('SELECT public.prepare_mobile_reevaluation_photo_upload('
                        + ','.join(literal(v) for v in (owner, cycle, asset, ticket)) + ');'
                        'SELECT public.register_mobile_reevaluation_photo_upload_ticket('
                        + ','.join(literal(v) for v in (owner, cycle, asset, ticket)) + ",clock_timestamp()+interval '2 hours');"
                        'SELECT public.complete_mobile_reevaluation_photo_upload('
                        + ','.join(literal(v) for v in (owner, cycle, asset))
                        + ',(SELECT source_revision FROM private.mobile_reevaluation_photo_sources WHERE user_id='
                        + literal(owner) + ' AND requested_asset_id=' + literal(asset) + "),1200,'image/jpeg',NULL)")
                    pose = 'back'
                else:
                    asset, pose = c['asset'], 'front'
                request = database.query('SELECT gen_random_uuid()')
                scope = ','.join(literal(v) for v in (owner, cycle, asset, request))
                database.query('SELECT public.claim_mobile_reevaluation_photo_processing(' + scope + ');'
                               'SELECT public.authorize_mobile_reevaluation_photo_provider(' + scope + ')')
                callback = 'SELECT public.complete_mobile_reevaluation_photo_processing(' + scope + ',' + literal(
                    {'type': 'body', 'view': pose, 'bf_percent_estimate': 36}) + '::jsonb);'
                if mode == 'locale_then_callback':
                    first_sql = 'UPDATE public.users SET locale=\'en-US\' WHERE id=' + literal(owner) + ';'
                    second_sql = callback
                else:
                    unavailable = json.loads(database.query('SELECT private.mobile_clinical_body_fat_candidate_at('
                        + literal(owner) + ',' + literal(cycle) + ',NULL)'))
                    require(unavailable['availability'] == 'unavailable', 'Pending replacement exposed a complete candidate')
                    pending = json.loads(database.query('SELECT json_build_object(\'status\',status,\'has_result\',result IS NOT NULL) '
                        'FROM private.mobile_reevaluation_photo_processing_attempts WHERE request_id=' + literal(request)))
                    require(pending == {'status': 'authorized', 'has_result': False}, 'Callback was not actually pending')
                    first_sql = callback
                    second_sql = 'SELECT m3b_cycle_test.clinical_request(' + literal(c) + '::jsonb);'
            first = sessions.spawn("BEGIN;SET LOCAL request.jwt.claim.role='service_role';\n"
                "SELECT json_build_object('holder',pg_backend_pid());\n" + first_sql
                + '\nSELECT jsonb_build_object(\'expected\',m3b_cycle_test.effect_state(' + literal(owner) + '));\n'
                "SELECT 'CONTEXT_READY';\n")
            lines = sessions.until(first, lambda line: line == 'CONTEXT_READY')
            holder = json.loads(next(x for x in lines if x.startswith('{"holder"')))['holder']
            expected = json.loads(next(x for x in lines if x.startswith('{"expected"')))['expected']
            second = sessions.spawn("SET request.jwt.claim.role='service_role';\n"
                "SELECT json_build_object('waiter',pg_backend_pid());\n"
                'SELECT m3b_cycle_test.context_race_try(' + literal(second_sql) + ');\n')
            waiter = json.loads(sessions.until(second, lambda line: line.startswith('{"waiter"'))[-1])['waiter']
            deadline = time.monotonic() + 5
            while time.monotonic() < deadline:
                waiting = json.loads(database.query("SELECT json_build_object('lock',wait_event_type='Lock',"
                    f"'blockers',pg_blocking_pids(pid)) FROM pg_stat_activity WHERE pid={int(waiter)}"))
                if waiting['lock'] and holder in waiting['blockers']:
                    break
                require(second.poll() is None, 'Waiter exited without the actual owner blocker')
                time.sleep(0.03)
            else:
                raise TimeoutError('Exact owner blocker not observed')
            sessions.finish(first, 'COMMIT;\n')
            out = sessions.finish(second)
            result = json.loads(next(x for x in out.splitlines() if x.startswith('{')), parse_float=Decimal)
            observed = {'case': mode, 'result': result}
            if mode.startswith('locale_'):
                require(result['code'] == '40001', 'Valid locale change did not refuse the stale operation')
                actual = json.loads(database.query('SELECT m3b_cycle_test.effect_state(' + literal(owner) + ')'))
                require(actual == expected, 'Stale operation changed owner state after locale commit')
            else:
                require(result['code'] == '00000', 'Prepare did not resume after committed final callback')
                q = result['result']
                candidate = q['context']['facts']['protocol_authority']['body_fat_candidate']
                require(candidate['availability'] == 'available' and len(candidate['sources']) == 3,
                        'Fresh FULL context lacks the three processed sources')
                require(any(s['asset_id'] == asset for s in candidate['sources']), 'Fresh candidate used obsolete back photo')
                require(q['intent']['bodyFat']['sourceHash'] == candidate['source_hash'], 'Preview did not bind new source hash')
                outcome = json.loads(database.query(confirmation(owner, q,
                    f'b3b01000-1000-4000-8000-{index:012d}')), parse_float=Decimal)
                observed['confirmation'] = outcome
                require(outcome['status'] == 'confirmed' and outcome['body_fat_percent'] == 26,
                        'FULL did not confirm the exact current mean')
                require(database.query('SELECT count(*) FROM private.mobile_clinical_full_receipts WHERE user_id='
                    + literal(owner)) == '1', 'First FULL duplicated receipt')
            cases.append({'case': mode, 'status': 'PASS', 'holder': holder, 'waiter': waiter,
                          'exact_blockers': waiting['blockers'], 'second_code': result['code']})
    except Exception as err:
        # Safe structural diagnosis, no credentials or image transports exist here.
        exclusive_json(str(output) + '.failure.json', json.loads(lossless_json(
            {'error': str(err), 'completed': cases, 'last_observation': observed})))
        raise
    finally:
        sessions.close()
        if owners:
            database.query('SELECT m3b_cycle_test.remove_photos(ARRAY['
                           + ','.join(literal(x) for x in owners) + ']::uuid[])')
        cleanup_fixture(database, owners, ('b3b01000-0000-4000-8000-000000000501',))
    require(database.query("SELECT NOT EXISTS(SELECT 1 FROM public.users) AND "
                           "to_regnamespace('m3b_cycle_test') IS NULL") == 't', 'Fixture cleanup incomplete')
    result = {'status': 'PASS_REAL_LOCAL_FULL_LOCALE_CALLBACK_RACES', 'cases': cases,
              'guard': database.guard, 'remote_operations': 0, 'provider_operations': 0,
              'private_clock_override': False, 'fixture_cleanup': 'PASS'}
    exclusive_json(output, result)
    return result


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--config', required=True)
    parser.add_argument('--output', required=True)
    args = parser.parse_args()
    db = LocalCycleDatabase(args.config)
    db.args.insert(1, '-q')
    result = run(db, args.output)
    print(json.dumps({'status': result['status'], 'cases': len(result['cases'])}))
