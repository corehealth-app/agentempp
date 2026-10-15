#!/usr/bin/env python3
"""Private S17B test-first driver. Inert import; Root alone supplies live bindings.
Four real membership/writer races. No server lifecycle, DDL, setup or teardown.
"""
import argparse
import hashlib
import json
from pathlib import Path
import re
import time
import types

ACTOR_SHA = 'c14570d9059fbd56f4aa7efeeefeb9e0030b275c9b221a0890d1d484d1db1a5f'
CASE_IDS = ['membership-13-commit', 'membership-13-rollback',
    'membership-s8-commit', 'membership-s8-rollback']
PREFIX = 'c59b7000-0000-0000-0000-'
F = 'c59s17b_fixture.'
J = 'private.mobile_workout_proposal_admissions'
P = 'public.pending_registrations'
W = 'public.workout_logs'
S = 'public.daily_snapshots'
X = 'private.workout_strength_'
DENIED = {'ok': False, 'sqlstate': '42501',
    'message': 'mobile_workout_registration_requires_revision'}


def require(value, label):
    if value is not True:
        raise RuntimeError('C59S17B_DRIVER:' + label)


def lit(value):
    return "'" + str(value).replace("'", "''") + "'"


def js(value):
    return lit(json.dumps(value, ensure_ascii=False)) + '::jsonb'


def case_select(case):
    return ' FROM ' + F + 'cases WHERE case_id=' + lit(case)


def admit(case):
    return F + "attempt((SELECT format('SELECT public.admit_mobile_workout_registration(%L::uuid,%L,%L::jsonb)',owner_id,payload->>'requestKey',payload->'input')" + case_select(case) + '))'


def materialize(case):
    return F + "attempt((SELECT format('SELECT public.materialize_mobile_workout_registration(%L::uuid,%L::uuid,%L::jsonb,%L::jsonb,%L::timestamptz)',owner_id,(SELECT admission_id FROM ONLY " + J + " j WHERE j.user_id=c.owner_id),payload->'input',payload->'proposal',payload->>'expiresAt') FROM " + F + 'cases c WHERE case_id=' + lit(case) + '))'


def writer(case, strength):
    if not strength:
        sql = 'SELECT ' + F + "legacy_sql(" + F + "arguments(owner_id,'musculacao',payload->>'requestKey'))" + case_select(case)
    else:
        sql = "SELECT format('SELECT public.register_workout_strength_atomic(%L::uuid,%L::uuid,%L,''musculacao'',NULL,''{\"status\":\"unavailable\",\"reason\":\"catalogue_read_error\"}''::jsonb)',owner_id,payload->>'lifecycleKey',payload->>'operationKey')" + case_select(case)
    return F + 'attempt((' + sql + '))'


def run(config):
    output = Path(config['output_dir'])
    output.mkdir(parents=True, exist_ok=False)
    result = {'executed': False, 'failure': None, 'cases': [],
        'cleanup': {'complete': False, 'actors_reaped': False, 'readers_stopped': False, 'actors': []}}
    actors = []
    deadline = time.monotonic() + 240
    original_failure = None

    def query(actor, expression, label, maximum=10):
        remaining = deadline - time.monotonic()
        require(remaining > 0, 'bounded_deadline')
        return actor.query(expression, label, timeout=min(maximum, remaining))

    def state(actor, owner, label):
        return query(actor, F + 'state(' + lit(owner) + '::uuid)', label)

    def wait_block(observer, blocker, waiter, owner):
        limit = min(deadline, time.monotonic() + 6)
        # Both the real blocker edge and its exact 64-bit :workouts lock key.
        lock_key = "pg_catalog.hashtextextended(" + lit(owner + ':workouts') + ',0)'
        high = '((' + lock_key + ' >> 32) & 4294967295)'
        low = '(' + lock_key + ' & 4294967295)'
        predicate = str(blocker) + '=ANY(pg_catalog.pg_blocking_pids(' + str(waiter) + ')) AND EXISTS(SELECT 1 FROM pg_catalog.pg_locks a JOIN pg_catalog.pg_locks b ON a.locktype=b.locktype AND a.database=b.database AND a.classid=b.classid AND a.objid=b.objid AND a.objsubid=b.objsubid WHERE a.pid=' + str(blocker) + ' AND b.pid=' + str(waiter) + " AND a.locktype='advisory' AND a.granted AND NOT b.granted AND a.objsubid=1 AND a.classid::bigint=" + high + ' AND a.objid::bigint=' + low + ')'
        while time.monotonic() < limit:
            observer.statement('SELECT pg_catalog.pg_stat_clear_snapshot();')
            if query(observer, '(' + predicate + ')', 'actual_workouts_blocker', limit - time.monotonic()) is True:
                return
        raise TimeoutError('C59S17B_DRIVER:no_actual_workouts_blocker')

    def success(packet, label):
        require(isinstance(packet, dict) and set(packet) == {'ok', 'result'}
            and packet['ok'] is True and isinstance(packet['result'], dict), label)
        return packet['result']

    def check_member(tentative, before, payload, receipt, materialized):
        require(set(receipt) == {'ownerID', 'admissionID', 'epoch', 'requestNamespace',
            'requestKey', 'requestHash', 'admittedAt'}
            and receipt['ownerID'] == payload['ownerID']
            and receipt['requestNamespace'] == 'mobile_workout_proposal_v1'
            and receipt['requestKey'] == payload['requestKey']
            and all(isinstance(receipt[k], str) for k in receipt), 'exact_real_original_admission_receipt7')
        for key in ('admissionID', 'epoch'):
            require(re.fullmatch(r'[0-9a-f]{8}(?:-[0-9a-f]{4}){3}-[0-9a-f]{12}', receipt[key]) is not None,
                'real_UUID_' + key)
        require(set(materialized) == {'status', 'pendingID', 'pendingStatus', 'cancelledCount'}
            and materialized['status'] == 'materialized' and materialized['pendingStatus'] == 'pending'
            and type(materialized['cancelledCount']) is int and materialized['cancelledCount'] == 0,
            'exact_real_first_materialized_wire')
        require(len(tentative[J]) == len(tentative[P]) == 1, 'one_real_journal_and_pending')
        journal, pending = tentative[J][0], tentative[P][0]
        require(journal['user_id'] == payload['ownerID'] and journal['admission_id'] == receipt['admissionID']
            and journal['epoch'] == receipt['epoch'] and journal['request_key'] == payload['requestKey']
            and journal['request_hash'] == receipt['requestHash'] and journal['content_revision'] == 0
            and journal['pending_id'] == materialized['pendingID'] and journal['bound_at'] is not None
            and journal['first_proposal_hash'] is not None and journal['rejection_reason'] is None
            and journal['confirmed_lifecycle_key'] is None, 'new_membership_and_real_first_binding')
        require(pending['id'] == materialized['pendingID'] and pending['user_id'] == payload['ownerID']
            and pending['workout_ui_admission_id'] == receipt['admissionID']
            and pending['proposal'] == payload['proposal'] and pending['status'] == 'pending',
            'owned_marker_exact_raw_server_proposal')
        allowed = {J, P, X + 'authority_epochs'}
        require({k: v for k, v in tentative.items() if k not in allowed}
            == {k: v for k, v in before.items() if k not in allowed}, 'membership_only_metadata_no_workout_snapshot_F1')

    def check_legacy_success(packet, after, before, payload, strength):
        body = success(packet, 'real_service_writer_success')
        legacy = body['legacy_result'] if strength else body
        require(set(legacy) == {'snapshot_id', 'workout_log_id', 'inserted', 'replaced_count',
            'exercise_calories', 'training_done', 'calories_target', 'protein_target'}
            and legacy['inserted'] is True and legacy['replaced_count'] == 0
            and legacy['exercise_calories'] == 300 and legacy['training_done'] is True
            and legacy['calories_target'] == 2000 and legacy['protein_target'] == 150.25,
            'real_legacy13_result_values_preserved')
        require(len(after[W]) == len(after[S]) == 1 and after[J] == after[P] == [],
            'rollback_has_one_real_workout_snapshot_and_no_UI_journal_pending')
        workout, snapshot = after[W][0], after[S][0]
        require(workout['id'] == legacy['workout_log_id'] and workout['snapshot_id'] == legacy['snapshot_id']
            and snapshot['id'] == workout['snapshot_id'], 'actual_workout_snapshot_response_identity')
        # Exact SQL numeric/instant/text comparisons, never rewrite the frozen 13 args through JS/Python.
        exact = "(SELECT w.user_id=c.owner_id AND w.workout_type='musculacao' AND w.duration_min=60 AND w.estimated_kcal=300 AND w.intensity='moderada' AND w.notes='S17B preserved café 🏋️' AND w.performed_at='2026-10-15T12:00:00.123456Z'::timestamptz AND w.raw_provider_message_id=c.payload->>'requestKey' AND s.user_id=c.owner_id AND s.date='2026-10-15'::date AND s.calories_target=2000 AND s.protein_target=150.25::numeric AND s.exercise_calories=300 AND s.training_done FROM ONLY " + W + ' w JOIN ONLY ' + S + ' s ON s.id=w.snapshot_id JOIN ' + F + 'cases c ON c.owner_id=w.user_id WHERE c.case_id=' + lit(case) + ')'
        require(query(a, exact, 'all_13_SQL_arguments_and_totals') is True, 'all_13_args_SQL_literals_preserved')
        allowed = {W, S}
        if strength:
            allowed |= {X + 'facts', X + 'operations'}
            require(set(body) == {'legacy_result', 'strength'}, 'exact_S8_outer_envelope')
            capture = body['strength']
            require(set(capture) == {'status', 'binding', 'fact'} and capture['status'] == 'committed'
                and capture['binding'] == {'ownerID': payload['ownerID'], 'lifecycleKey': payload['lifecycleKey'],
                    'operationKey': payload['operationKey'], 'originalOperationType': 'musculacao',
                    'workoutLogID': workout['id'], 'resolution': 'sql_insert'}, 'real_S8_committed_binding')
            fact = capture['fact']
            require(fact['classification'] == {'status': 'unavailable', 'reason': 'catalogue_read_error'}
                and fact['clarification'] == {'status': 'not_applicable'} and fact['revision'] == 0
                and fact['anchor']['ownerID'] == payload['ownerID']
                and fact['anchor']['workoutLogID'] == workout['id']
                and fact['anchor']['lifecycleKey'] == payload['lifecycleKey']
                and fact['anchor']['snapshotID'] == snapshot['id']
                and fact['anchor']['performedAt'] == '2026-10-15T12:00:00.123456Z'
                and fact['anchor']['snapshotDate'] == '2026-10-15'
                and fact['calendar']['status'] == 'proven' and fact['calendar']['timeZone'] == 'UTC',
                'real_fact_unavailable_classification_and_proven_anchor')
            require(len(after[X + 'facts']) == len(after[X + 'operations']) == 1,
                'one_real_F1_and_fact_only_after_rollback')
            operation = after[X + 'operations'][0]
            require(operation['operation_kind'] == 'capture' and operation['operation_key'] == payload['operationKey']
                and operation['original_operation_type'] == 'musculacao'
                and operation['original_workout_log_id'] == operation['live_workout_log_id'] == workout['id'],
                'stored_F1_real_UUID_and_original_key')
        require({k: v for k, v in after.items() if k not in allowed}
            == {k: v for k, v in before.items() if k not in allowed}, 'writer_no_other_state_mutation')

    try:
        require(config.get('root_reviewed') is True, 'root_review_required')
        path = Path(config['driver_path']).resolve(strict=True)
        require(hashlib.sha256(path.read_bytes()).hexdigest() == config['driver_sha256'], 'driver_pin')
        actor_path = Path(config['actor_module']).resolve(strict=True)
        source = actor_path.read_bytes()
        require(actor_path == path.parent / 'workout_strength_commands_concurrency.py'
            and config.get('actor_sha256') == ACTOR_SHA and hashlib.sha256(source).hexdigest() == ACTOR_SHA,
            'closed_relative_Actor_pin')
        require(config.get('user') == 'c5_local_admin' and config.get('database') == 'c5_reset_default_20261009'
            and config.get('port') == 55489 and config.get('socket') == '/private/tmp/performe-c5-osecmg7_'
            and config.get('expected_data_directory') == '/Users/eduardohenrique/.local/share/performe-ai/final-polish-20261001/e3/c5-portable-postgres17-20261009/data', 'exact_owned_C5')
        require(Path(config['psql']).is_absolute() and hashlib.sha256(Path(config['psql']).read_bytes()).hexdigest()
            == config['psql_sha256'] and config.get('expected_case_ids') == CASE_IDS, 'psql_and_exact_four_case_pins')
        base = types.ModuleType('c59s17b_closed_Actor')
        exec(compile(source, str(actor_path), 'exec'), base.__dict__)
        a = base._create_registered_actor('A', config, output, actors)
        b = base._create_registered_actor('B', config, output, actors)
        pids = []
        for actor in actors:
            identity = query(actor, "jsonb_build_object('owner',session_user,'db',current_database(),'port',current_setting('port')::int,'data',current_setting('data_directory'),'socket',current_setting('unix_socket_directories'),'listen',current_setting('listen_addresses'),'pid',pg_backend_pid(),'tag',(SELECT tag FROM " + F + 'ownership))', 'identity')
            require(identity['owner'] == config['user'] and identity['db'] == config['database']
                and identity['port'] == config['port'] and identity['data'] == config['expected_data_directory']
                and identity['socket'] == config['socket'] and identity['listen'] == ''
                and identity['tag'] == 'c59s17b_ui_boundary_v1', 'actual_local_identity')
            pids.append(identity['pid'])
            actor.statement("SET statement_timeout='12s';SET lock_timeout='9s';SET request.jwt.claims='{\"role\":\"service_role\"}';SET TimeZone='UTC';SET DateStyle='ISO,YMD';")
        require(pids[0] != pids[1], 'distinct_A_B')
        sentinel = PREFIX + '000000000999'
        sentinel_before = state(a, sentinel, 'initial_sentinel')
        require(sentinel_before == query(a, "(SELECT payload->'sentinelState' FROM " + F + "cases WHERE case_id='sentinel')", 'stored_setup_sentinel'), 'real_setup_sentinel')
        result['executed'] = True
        for index, case in enumerate(CASE_IDS):
            payload = query(a, '(SELECT payload' + case_select(case) + ')', 'case_real_payload')
            owner = PREFIX + str(index + 501).zfill(12)
            require(payload['ownerID'] == owner and payload['requestKey'] == 'wui1:' + owner
                and payload['input'] == {'kind': 'workout', 'workout_type': 'musculacao', 'duration_min': 60, 'intensity': 'moderada'},
                'case_owned_original_key_and_input')
            before = state(a, owner, 'before_case')
            require(before[W] == before[S] == before[J] == before[P] == before[X + 'operations'] == before[X + 'facts'] == [], 'initial_no_UI_or_write')
            strength = index >= 2
            require(len(before[X + 'lifecycles']) == len(before[X + 'commands']) == (1 if strength else 0),
                'real_S7_setup_only_for_S8')
            a.begin()
            first = success(query(a, admit(case), 'A_real_new_admit'), 'new_admit_success')
            require(set(first) == {'status', 'admission'} and first['status'] == 'admitted', 'new_admitted_not_promoted')
            receipt = first['admission']
            bound = success(query(a, materialize(case), 'A_real_new_materialize'), 'new_materialize_success')
            # Only receipt strings/IDs/zero are copied; input/proposal/13 args stay in DB.
            a.statement('UPDATE ' + F + 'cases SET payload=payload||' + js({'admission': receipt, 'materialized': bound}) + ' WHERE case_id=' + lit(case) + ';')
            tentative = state(a, owner, 'A_tentative_before_commit_or_rollback')
            check_member(tentative, before, payload, receipt, bound)
            b.begin()
            ticket = b.send(writer(case, strength), 'B_actual_public_writer_waits_membership')
            wait_block(a, pids[0], pids[1], owner)
            commit = index % 2 == 0
            a.finish(commit)
            second = b.receive(ticket, timeout=min(10, max(0.01, deadline - time.monotonic())))
            b.finish(True)
            after = state(a, owner, 'durable_after_B_commit')
            if commit:
                require(second == DENIED, 'committed_membership_fresh42501_before_writer')
                require(after == tentative, 'B_denied_preserves_precommit_A_fullstate_no_workout_snapshot_F1')
                require(after[W] == after[S] == after[X + 'operations'] == after[X + 'facts'] == [],
                    'no_false_receipt_or_first_writer_effect')
            else:
                check_legacy_success(second, after, before, payload, strength)
                require(query(a, "(SELECT NOT(payload?'admission') AND NOT(payload?'materialized')" + case_select(case) + ')', 'A_receipt_fixture_rollback') is True,
                    'rolled_back_membership_receipts_not_persisted')
            require(state(a, sentinel, 'sentinel_after_case') == sentinel_before, 'other_owner_unchanged')
            result['cases'].append({'id': case, 'passed': True, 'A_membership_committed': commit,
                'actual_workouts_blocker': True, 'actual_service_role_RPC': True,
                'precommit_A_snapshot_is_negative_oracle': commit,
                'legacy_13_SQL_literals_checked': not commit, 'other_owner_unchanged': True})
        require([c['id'] for c in result['cases']] == CASE_IDS, 'all_four_once')
    except BaseException as failure:
        original_failure = failure
        result['failure'] = type(failure).__name__
        raise
    finally:
        cleanup = []
        for actor in reversed(actors):
            try:
                cleanup.append(actor.close())
            except BaseException as failure:
                cleanup.append({'actor': actor.name, 'reaped': False, 'readers_stopped': False,
                    'failure': type(failure).__name__})
        reaped = all(c['reaped'] for c in cleanup)
        readers = all(c['readers_stopped'] for c in cleanup)
        result['cleanup'] = {'complete': reaped and readers, 'actors_reaped': reaped,
            'readers_stopped': readers, 'actors': cleanup}
        if original_failure is None and not (reaped and readers and len(cleanup) == 2
                and all(c.get('exit_code') == 0 for c in cleanup)):
            result['failure'] = 'RuntimeError'
            result['failure_label'] = 'two_owned_actors_exit0_and_readers_stopped'
        try:
            (output / 'RESULT.json').write_text(json.dumps(result, indent=2) + '\n', encoding='utf-8')
        except BaseException:
            if original_failure is None:
                raise
    require(result['cleanup']['complete'] is True and len(cleanup) == 2
        and all(c['exit_code'] == 0 for c in cleanup), 'two_owned_actors_exit0_and_readers_stopped')
    return result


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--bindings-json', required=True)
    parser.add_argument('--output-dir', required=True)
    args = parser.parse_args()
    config = json.loads(Path(args.bindings_json).read_text(encoding='utf-8'))
    config['output_dir'] = args.output_dir
    run(config)
