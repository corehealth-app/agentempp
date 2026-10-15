#!/usr/bin/env python3
"""Private S17D test-first A/B source; importing this file is inert.
Root alone supplies reviewed local bindings and runs the closed S7 Actor.
No server lifecycle, product DDL, prepare or teardown is implemented here.
"""
import argparse
import datetime
import hashlib
import json
from pathlib import Path
import re
import time
import types

ACTOR_SHA = 'c14570d9059fbd56f4aa7efeeefeb9e0030b275c9b221a0890d1d484d1db1a5f'
CASE_IDS = [
    'confirm-confirm-commit', 'confirm-confirm-rollback',
    'confirm-edit-commit', 'confirm-edit-rollback',
    'edit-confirm-commit', 'edit-confirm-rollback',
    'confirm-cancel-commit', 'confirm-cancel-rollback',
    'cancel-confirm-commit', 'cancel-confirm-rollback',
    'legacy-terminal-confirm-commit', 'legacy-terminal-confirm-rollback',
    'expiry-confirm-after-rowlock',
    'reset-confirm-commit', 'reset-confirm-rollback',
    'delete-pending-confirm-commit', 'delete-pending-confirm-rollback',
    'catalogue-mutation-confirm-commit', 'catalogue-mutation-confirm-rollback',
]
PREFIX = 'c59d7000-0000-0000-0000-'
F = 'c59s17d_fixture.'
J = 'private.mobile_workout_proposal_admissions'
P = 'public.pending_registrations'
R = 'private.mobile_workout_registration_edit_receipts'
E = 'private.workout_strength_authority_epochs'
L = 'private.workout_strength_lifecycles'
C = 'private.workout_strength_commands'
O = 'private.workout_strength_operations'
T = 'private.workout_strength_facts'
W = 'public.workout_logs'
S = 'public.daily_snapshots'
CAT = 'public.workout_types'
CAPTURE_GROUPS = {L, C, O, T, W, S}
CLOCK = "pg_catalog.to_char(pg_catalog.clock_timestamp() AT TIME ZONE 'UTC','YYYY-MM-DD\"T\"HH24:MI:SS.US\"Z\"')"


def require(value, label):
    if value is not True:
        raise RuntimeError('C59S17D_DRIVER:' + label)


def lit(value):
    return "'" + str(value).replace("'", "''") + "'"


def instant(value):
    require(isinstance(value, str), 'server_timestamp_string')
    normalized = re.sub(r'\.(\d{1,6})(?=[+-]\d{2}:\d{2}$)',
        lambda match: '.' + match.group(1).ljust(6, '0'), value.replace('Z', '+00:00'))
    parsed = datetime.datetime.fromisoformat(normalized)
    require(parsed.tzinfo is not None, 'server_timestamp_with_timezone')
    return parsed.astimezone(datetime.timezone.utc)


def one(state, relation):
    rows = state.get(relation)
    require(isinstance(rows, list) and len(rows) == 1, 'exact_one:' + relation)
    return rows[0]


def projection(state):
    pending, admission = one(state, P), one(state, J)
    require(pending['id'] == admission['pending_id']
        and pending['workout_ui_admission_id'] == admission['admission_id']
        and pending['user_id'] == admission['user_id'], 'projection_all_owned_links')
    return {key: pending[key] for key in
        ('id', 'status', 'created_at', 'expires_at', 'resolved_at', 'proposal')} | {
            'workout_protocol': 'ui-v1', 'content_revision': admission['content_revision']}


def unchanged_except(before, after, allowed, label):
    require(set(before) == set(after), label + ':same_full_state_groups')
    require({k: v for k, v in before.items() if k not in allowed}
        == {k: v for k, v in after.items() if k not in allowed}, label)


def success(packet, label):
    require(isinstance(packet, dict) and set(packet) == {'ok', 'result'}
        and packet['ok'] is True and isinstance(packet['result'], dict), label)
    return packet['result']


def edited(packet, before, after, payload, low, high):
    body = success(packet, 'native_edited_success')
    old_j, new_j = one(before, J), one(after, J)
    old_p, new_p = one(before, P), one(after, P)
    require(old_j['content_revision'] == 0, 'real_original_revision0')
    key, proposal = payload['editKeyA'], payload['editProposalA']
    require(body == {'status': 'edited', 'registration': projection(after),
        'receipt': {'requestKey': key, 'expectedRevision': 0, 'resultRevision': 1}},
        'exact_edit_wire_receipt_current_projection')
    require(new_j == old_j | {'content_revision': 1}, 'admission_only_revision_changes')
    require(new_p == old_p | {'proposal': proposal, 'expires_at': new_p['expires_at']},
        'edit_same_pending_only_proposal_and_expiry_changes')
    renewed = instant(new_p['expires_at']) - datetime.timedelta(hours=24)
    require(instant(low) <= renewed <= instant(high), 'edit_real_server_24_hours_after_locks')
    require(before[R] == [] and after[R] == [{
        'user_id': old_j['user_id'], 'admission_id': old_j['admission_id'],
        'request_key': key, 'input_hash': payload['inputHashA'],
        'expected_revision': 0, 'result_revision': 1}], 'one_exact_real_edit_receipt')
    unchanged_except(before, after, {J, P, R}, 'edit_preserves_all_other_owned_groups')


def cancelled(packet, before, after, low, high):
    body = success(packet, 'native_cancelled_success')
    old_p, new_p = one(before, P), one(after, P)
    require(body == {'status': 'cancelled', 'registration': projection(after)},
        'exact_cancel_wire_current_projection')
    require(old_p['status'] == 'pending'
        and new_p == old_p | {'status': 'cancelled', 'resolved_at': new_p['resolved_at']},
        'cancel_only_status_and_resolved_at_changes')
    require(instant(low) <= instant(new_p['resolved_at']) <= instant(high),
        'cancel_resolved_at_real_clock_after_locks')
    unchanged_except(before, after, {P}, 'cancel_preserves_all_other_owned_groups')


def conflict(packet, state, reason):
    body = success(packet, 'native_conflict_success')
    require(body == {'status': 'conflict', 'reason': reason, 'registration': projection(state)},
        'exact_owned_conflict:' + reason)


def forbidden(packet, reason):
    body = success(packet, 'native_authority_negative_success')
    require(body == {'status': 'forbidden', 'reason': reason},
        'exact_authority_negative_without_data:' + reason)


def confirmed(packet, before, after, payload, arguments, low, high, resolved):
    """Fresh AB owners have no prior capture; replay is checked separately.
    All cardinalities below follow that real baseline, not a general dedup rule.
    """
    body = success(packet, 'native_confirmed_success')
    require(set(body) == {'status', 'registration', 'capture'}
        and body['status'] == 'confirmed' and body['registration'] == projection(after),
        'exact_confirmation_wire_projection')
    require(all(before[k] == [] for k in CAPTURE_GROUPS), 'fresh_actual_empty_capture_baseline')
    require(all(len(after[k]) == 1 for k in CAPTURE_GROUPS),
        'fresh_exact_one_life_command_binding_fact_workout_snapshot')
    old_j, new_j = one(before, J), one(after, J)
    old_p, new_p = one(before, P), one(after, P)
    old_e, new_e = one(before, E), one(after, E)
    life, command, operation = one(after, L), one(after, C), one(after, O)
    workout, snapshot, fact = one(after, W), one(after, S), one(after, T)
    owner, lifecycle = old_j['user_id'], life['lifecycle_key']
    key = 'ui:' + old_j['admission_id'] + ':r:' + str(old_j['content_revision'])
    require(payload['operationKey0'] == key and old_j['content_revision'] == 0,
        'server_key_exact_admission_revision')
    require(new_j == old_j | {'confirmed_lifecycle_key': lifecycle},
        'journal_only_confirmation_lifecycle_pointer')
    require(old_p['status'] == 'pending' and new_p == old_p | {
        'status': 'confirmed', 'resolved_at': new_p['resolved_at']},
        'confirmation_only_status_resolved_preserves_content_expiry')
    require(old_e['current_lifecycle_key'] is None
        and new_e == old_e | {'current_lifecycle_key': lifecycle},
        'epoch_only_current_lifecycle_pointer_changed')
    require(life == {'user_id': owner, 'lifecycle_key': lifecycle,
        'opened_at': life['opened_at'], 'closed_at': None, 'close_operation_key': None},
        'one_real_UI_lifecycle_open_without_Flow_IN')
    require(command == {'user_id': owner, 'lifecycle_key': lifecycle,
        'operation_key': key, 'original_operation_type': old_p['proposal']['workoutType'],
        'legacy_arguments': arguments, 'admitted_at': command['admitted_at'],
        'recent_cutoff': command['recent_cutoff']}, 'one_exact_S7_winner_original_13')
    require(instant(command['admitted_at']) - instant(command['recent_cutoff'])
        == datetime.timedelta(hours=6), 'S7_exact_six_elapsed_hours')
    for value in (life['opened_at'], command['admitted_at'], operation['created_at'], new_p['resolved_at']):
        require(instant(low) <= instant(value) <= instant(high),
            'accepted_DB_clocks_within_real_postlock_bounds')
    require(instant(new_p['resolved_at']) >= instant(operation['created_at']),
        'resolved_clock_after_accepted_capture')
    require(operation == {'user_id': owner, 'lifecycle_key': lifecycle,
        'operation_kind': 'capture', 'operation_key': key,
        'original_operation_type': old_p['proposal']['workoutType'],
        'original_workout_log_id': workout['id'], 'live_workout_log_id': workout['id'],
        'created_at': operation['created_at'], 'resolution': 'sql_insert',
        'capture_outcome': 'fact', 'legacy_result': operation['legacy_result'],
        'answer_expected_revision': None, 'answer_question_key': None,
        'answer_value': None, 'answer_receipt': None}, 'one_exact_durable_capture_binding')
    require(workout['user_id'] == owner and workout['snapshot_id'] == snapshot['id']
        and workout['workout_type'] == arguments['p_workout_type']
        and workout['duration_min'] == arguments['p_duration_min']
        and workout['estimated_kcal'] == arguments['p_estimated_kcal']
        and workout['intensity'] == arguments['p_intensity']
        and workout['notes'] == arguments['p_notes']
        and workout['raw_provider_message_id'] == arguments['p_provider_message_id']
        and instant(workout['performed_at']) == instant(arguments['p_performed_at']),
        'actual_writer_row_matches_original_S7_winner')
    require(snapshot['user_id'] == owner and snapshot['date'] == arguments['p_date']
        and snapshot['exercise_calories'] == arguments['p_estimated_kcal']
        and snapshot['training_done'] is True
        and snapshot['calories_target'] == arguments['p_calories_target']
        # Exact S7 candidate150.125 remains in the journal; the existing snapshot
        # numeric(6,2) cast stores150.13. Do not round through a Python formula.
        and arguments['p_protein_target'] == 150.125 and snapshot['protein_target'] == 150.13
        and all(snapshot[k] == 0 for k in ('calories_consumed', 'protein_g', 'carbs_g', 'fat_g')),
        'actual_fresh_snapshot_totals_no_invented_formula')
    require(fact['user_id'] == owner and fact['lifecycle_key'] == lifecycle
        and fact['workout_log_id'] == workout['id'] and fact['snapshot_id'] == snapshot['id']
        and fact['stored_workout_type'] == workout['workout_type']
        and instant(fact['performed_at']) == instant(workout['performed_at'])
        and fact['snapshot_date'] == snapshot['date']
        and fact['classification_status'] == 'matched'
        and fact['catalogue_id'] == payload['catalogueDecision']['selectedRowID']
        and fact['observation_key'] == payload['catalogueObservation']['observationKey']
        and fact['revision'] == 0 and fact['answer'] is None
        and fact['calendar_status'] == 'proven' and fact['local_date'] == snapshot['date']
        and fact['time_zone'] == 'UTC', 'real_fact_owned_original_anchor_and_catalogue')
    require(resolved['status'] == 'reuse_existing'
        and body['capture'] == {'legacy_result': operation['legacy_result'],
            'strength': resolved | {'status': 'committed'}},
        'capture_equals_stored_legacy_result_and_independent_resolver')
    require(operation['legacy_result'] == {
        'snapshot_id': snapshot['id'], 'workout_log_id': workout['id'], 'inserted': True,
        'replaced_count': 0, 'exercise_calories': snapshot['exercise_calories'],
        'training_done': True, 'calories_target': snapshot['calories_target'],
        'protein_target': snapshot['protein_target']}, 'literal_official_13_result_not_reconstructed_by_product')
    unchanged_except(before, after, {J, P, E} | CAPTURE_GROUPS,
        'confirmation_preserves_every_other_owned_group_including_Flow_admissions_messages')


def reused(packet, before, after, resolved):
    body = success(packet, 'native_reused_success')
    operation = one(after, O)
    require(after == before and body == {'status': 'reused',
        'registration': projection(after), 'capture': {
            'legacy_result': operation['legacy_result'], 'strength': resolved}},
        'confirmed_replay_current_projection_original_result_no_clock_or_write')


def run(config):
    output = Path(config['output_dir'])
    output.mkdir(parents=True, exist_ok=False)
    result = {'executed': False, 'failure': None, 'cases': [],
        'cleanup': {'complete': False, 'actors_reaped': False, 'readers_stopped': False, 'actors': []}}
    actors = []
    deadline = time.monotonic() + 480
    original_failure = None

    def query(actor, expression, label, maximum=15):
        remaining = deadline - time.monotonic()
        require(remaining > 0 and maximum > 0, 'bounded_global_deadline')
        return actor.query(expression, label, timeout=min(maximum, remaining))

    def clock(actor, label):
        return query(actor, CLOCK, label)

    def state(actor, owner, label):
        return query(actor, F + 'state(' + lit(owner) + '::uuid)', label)

    def outside(actor, owner, label):
        return query(actor, F + 'outside(' + lit(owner) + '::uuid)', label)

    def select_case(case):
        return ' FROM ' + F + 'cases WHERE case_id=' + lit(case)

    def mutation(case, kind, side='A'):
        tail = select_case(case)
        if kind == 'confirm':
            replay = side == 'B' and case == 'confirm-confirm-commit'
            args = "'null'::jsonb" if replay else "payload->'legacyArguments'"
            observation = 'NULL::jsonb' if replay else "payload->'catalogueObservation'"
            decision = "'null'::jsonb" if replay else "payload->'catalogueDecision'"
            sql = '(SELECT ' + F + "confirm_sql(owner_id,(payload->>'registrationID')::uuid,0," \
                + args + ',' + observation + ',' + decision + ')' + tail + ')'
        elif kind == 'edit':
            sql = '(SELECT ' + F + "edit_sql(owner_id,(payload->>'registrationID')::uuid,0," \
                + "payload->>'editKeyA',payload->'editInputA',payload->'editProposalA')" + tail + ')'
        else:
            require(kind == 'cancel', 'known_mutator')
            sql = '(SELECT ' + F + "cancel_sql(owner_id,(payload->>'registrationID')::uuid,0)" + tail + ')'
        return F + 'attempt(' + sql + ')'

    def attempt_sql(sql, role='service_role'):
        return F + 'attempt(' + lit(sql) + ',' + lit(role) + ')'

    def resolver(actor, current, label):
        admission, pending, operation = one(current, J), one(current, P), one(current, O)
        sql = 'SELECT public.resolve_confirmed_workout_strength_capture(' + ','.join([
            lit(admission['user_id']) + '::uuid', lit(operation['lifecycle_key']) + '::uuid',
            lit(operation['operation_key']), lit(pending['proposal']['workoutType'])]) + ')'
        return success(query(actor, attempt_sql(sql), label), 'independent_existing_resolver_native_success')

    def wait_block(observer, blocker, waiter, owner, kind):
        limit = min(deadline, time.monotonic() + 8)
        native_edge = str(blocker) + '=ANY(pg_catalog.pg_blocking_pids(' + str(waiter) + '))'
        no_advisory_wait = 'NOT EXISTS(SELECT 1 FROM pg_catalog.pg_locks x WHERE x.pid=' + str(waiter) + " AND x.locktype='advisory' AND NOT x.granted)"
        if kind == 'row':
            predicate = native_edge + ' AND EXISTS(SELECT 1 FROM pg_catalog.pg_locks a JOIN pg_catalog.pg_locks b ON a.transactionid=b.transactionid WHERE a.pid=' + str(blocker) + ' AND b.pid=' + str(waiter) + " AND a.locktype='transactionid' AND b.locktype='transactionid' AND a.granted AND NOT b.granted AND a.mode='ExclusiveLock' AND b.mode='ShareLock') AND " + no_advisory_wait
            label = 'actual_pending_row_transaction_blocker'
        elif kind == 'catalogue':
            predicate = native_edge + ' AND EXISTS(SELECT 1 FROM pg_catalog.pg_locks a JOIN pg_catalog.pg_locks b ON a.database=b.database AND a.relation=b.relation WHERE a.pid=' + str(blocker) + ' AND b.pid=' + str(waiter) + " AND a.locktype='relation' AND b.locktype='relation' AND a.relation='public.workout_types'::regclass AND a.mode='RowExclusiveLock' AND a.granted AND b.mode='ShareLock' AND NOT b.granted) AND NOT EXISTS(SELECT 1 FROM pg_catalog.pg_locks x WHERE x.pid=" + str(waiter) + " AND x.locktype='advisory')"
            label = 'actual_catalogue_SHARE_wait_before_any_workouts_lock'
        else:
            require(kind == 'advisory', 'known_lock_kind')
            lock_key = 'pg_catalog.hashtextextended(' + lit(owner + ':workouts') + ',0)'
            high, low = '((' + lock_key + ' >> 32) & 4294967295)', '(' + lock_key + ' & 4294967295)'
            predicate = native_edge + ' AND EXISTS(SELECT 1 FROM pg_catalog.pg_locks a JOIN pg_catalog.pg_locks b ON a.locktype=b.locktype AND a.database=b.database AND a.classid=b.classid AND a.objid=b.objid AND a.objsubid=b.objsubid WHERE a.pid=' + str(blocker) + ' AND b.pid=' + str(waiter) + " AND a.locktype='advisory' AND a.granted AND NOT b.granted AND a.objsubid=1 AND a.classid::bigint=" + high + ' AND a.objid::bigint=' + low + ')'
            label = 'actual_exact_workouts_advisory_blocker'
        while time.monotonic() < limit:
            observer.statement('SELECT pg_catalog.pg_stat_clear_snapshot();')
            if query(observer, '(' + predicate + ')', label, limit - time.monotonic()) is True:
                return label
        raise TimeoutError('C59S17D_DRIVER:no_' + label)

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
            == config['psql_sha256'] and config.get('expected_case_ids') == CASE_IDS,
            'psql_and_exact_19_case_pins')
        base = types.ModuleType('c59s17d_closed_Actor')
        exec(compile(source, str(actor_path), 'exec'), base.__dict__)
        a = base._create_registered_actor('A', config, output, actors)
        b = base._create_registered_actor('B', config, output, actors)
        pids = []
        for actor in actors:
            identity = query(actor, "jsonb_build_object('owner',session_user,'db',current_database(),'port',current_setting('port')::int,'data',current_setting('data_directory'),'socket',current_setting('unix_socket_directories'),'listen',current_setting('listen_addresses'),'pid',pg_backend_pid(),'tag',(SELECT tag FROM " + F + 'ownership))', 'identity')
            require(identity['owner'] == config['user'] and identity['db'] == config['database']
                and identity['port'] == config['port'] and identity['data'] == config['expected_data_directory']
                and identity['socket'] == config['socket'] and identity['listen'] == ''
                and identity['tag'] == 'c59s17d_confirm_v1', 'actual_local_identity')
            pids.append(identity['pid'])
            actor.statement("SET statement_timeout='20s';SET lock_timeout='15s';SET request.jwt.claims='{\"role\":\"service_role\"}';SET TimeZone='UTC';SET DateStyle='ISO,YMD';")
        require(pids[0] != pids[1], 'distinct_real_A_B')
        sentinel = PREFIX + '000000003999'
        sentinel_before = state(a, sentinel, 'initial_sentinel')
        require(sentinel_before == query(a, "(SELECT payload->'initialState' FROM " + F + "cases WHERE case_id='sentinel')", 'stored_setup_sentinel'), 'real_setup_sentinel')
        result['executed'] = True
        for index, case in enumerate(CASE_IDS):
            # Refresh only fixture payload with the real catalogue observation before A.
            # No observation/candidate is refreshed after B has started its wait.
            payload = query(a, F + 'payload_refresh_catalogue(' + lit(case) + ')', 'fresh_real_catalogue_payload_before_A')
            owner = PREFIX + str(index + 2801).zfill(12)
            require(payload['ownerID'] == owner and payload['requestKey'] == 'wui1:' + owner
                and payload['input'] == {'kind': 'workout', 'workout_type': 'c59s17d-treino',
                    'duration_min': 40, 'intensity': 'moderada'}
                and payload['editInputA'] == payload['input'] | {'duration_min': 45},
                'exact_owned_keys_and_actual40_45_input')
            before = state(a, owner, 'before_case')
            outside_before = outside(a, owner, 'before_case_all_outside_rows')
            catalogue_before = query(a, F + 'catalogue_state()', 'before_case_all_catalogue_rows')
            require(before == payload['initialState'] and one(before, J)['content_revision'] == 0
                and one(before, P)['id'] == payload['registrationID'] and one(before, P)['status'] == 'pending'
                and one(before, P)['proposal'] == payload['proposal'] and before[R] == []
                and all(before[k] == [] for k in CAPTURE_GROUPS), 'real_S17B_original_fullstate_no_prior_life_or_capture')
            input_hash = query(a, "(SELECT private.mobile_workout_proposal_input_hash(payload->'editInputA')" + select_case(case) + ')', 'closed_S16_edit_input_hash')
            require(input_hash == payload['inputHashA'], 'edit_hash_is_actual_S16_input_not_proposal')
            expiry = case.startswith('expiry-')
            reset = case.startswith('reset-')
            deleted = case.startswith('delete-pending-')
            legacy = case.startswith('legacy-terminal-')
            catalogue = case.startswith('catalogue-mutation-')
            lock_kind = 'catalogue' if catalogue else 'row' if (expiry or deleted or legacy) else 'advisory'
            commit = not case.endswith('-rollback')
            a_kind = 'edit' if case.startswith('edit-confirm-') else 'cancel' if case.startswith('cancel-confirm-') else 'confirm'
            b_kind = 'edit' if case.startswith('confirm-edit-') else 'cancel' if case.startswith('confirm-cancel-') else 'confirm'
            a.begin()
            a_lower = clock(a, 'before_A_real_operation')
            a_packet = None
            if expiry:
                armed = query(a, F + 'arm_expiry_case(' + lit(case) + ')', 'A_single_arm_real_expiry_before_B')
                require(instant(armed) > instant(a_lower), 'expiry_armed_in_real_future')
            elif reset:
                a_packet = query(a, attempt_sql('SELECT public.reset_user_conversation_atomic(' + lit(owner) + '::uuid,true)'), 'A_real_reset')
                require(success(a_packet, 'real_reset_success') == {
                    'reset': True, 'user_id': owner, 'deleted_rows': 1, 'kept_plans': True}, 'real_reset_one_original_pending')
            elif deleted:
                a_packet = query(a, attempt_sql('DELETE FROM ONLY ' + P + ' p WHERE p.user_id=' + lit(owner) + '::uuid AND p.id=' + lit(payload['registrationID']) + '::uuid RETURNING to_jsonb(p)'), 'A_real_service_DELETE_pending')
                require(success(a_packet, 'native_delete_success') == one(before, P), 'delete_exact_original_pending')
            elif legacy:
                sql = 'UPDATE ONLY ' + P + " p SET status='cancelled',resolved_at=pg_catalog.clock_timestamp() WHERE p.user_id=" + lit(owner) + '::uuid AND p.id=' + lit(payload['registrationID']) + '::uuid RETURNING to_jsonb(p)'
                a_packet = query(a, attempt_sql(sql), 'A_real_service_legacy_terminal_rowlock')
                terminal_row = success(a_packet, 'native_terminal_update_success')
            elif catalogue:
                a_packet = query(a, F + 'attempt((SELECT ' + F + 'catalogue_mutation_sql(' + lit(case) + ")),'c5_local_admin')", 'A_real_owned_catalogue_mutation')
                catalogue_row = success(a_packet, 'native_owned_catalogue_mutation_success')
            else:
                a_packet = query(a, mutation(case, a_kind), 'A_real_' + a_kind)
            a_upper = clock(a, 'after_A_real_operation')
            tentative = state(a, owner, 'A_independent_tentative_before_B')
            catalogue_tentative = query(a, F + 'catalogue_state()', 'A_tentative_catalogue_rows')
            if expiry:
                require(one(tentative, P) == one(before, P) | {'expires_at': armed}, 'single_expiry_arm_only_timestamp_delta')
                unchanged_except(before, tentative, {P}, 'expiry_arm_no_other_owned_effect')
            elif reset:
                require(tentative[P] == [] and tentative[J] == before[J] and tentative[R] == []
                    and one(tentative, E)['epoch'] != one(before, E)['epoch']
                    and all(tentative[k] == [] for k in CAPTURE_GROUPS),
                    'real_reset_invalidates_epoch_retains_journal_no_capture')
            elif deleted:
                require(tentative[P] == [], 'real_pending_deleted_not_rematerialized')
                unchanged_except(before, tentative, {P}, 'delete_no_other_owned_effect')
            elif legacy:
                require(one(tentative, P) == one(before, P) | {
                    'status': 'cancelled', 'resolved_at': terminal_row['resolved_at']}
                    and instant(a_lower) <= instant(terminal_row['resolved_at']) <= instant(a_upper),
                    'legacy_only_status_and_resolved_clock')
                unchanged_except(before, tentative, {P}, 'legacy_terminal_no_other_owned_effect')
            elif catalogue:
                require(tentative == before, 'catalogue_A_changes_no_owner_state')
                owned_id = PREFIX + '000000009901'
                original_rows = [r for r in catalogue_before if r['id'] == owned_id]
                require(len(original_rows) == 1 and catalogue_row == original_rows[0] | {
                    'display_name': 'S17D changed ' + case, 'updated_at': catalogue_row['updated_at']},
                    'catalogue_only_exact_owned_row_display_and_real_updated_timestamp')
                require(catalogue_tentative == [catalogue_row if r['id'] == owned_id else r
                    for r in catalogue_before], 'all_other_catalogue_rows_exact_no_insert_or_delete')
            elif a_kind == 'edit':
                edited(a_packet, before, tentative, payload, a_lower, a_upper)
            elif a_kind == 'cancel':
                cancelled(a_packet, before, tentative, a_lower, a_upper)
            else:
                confirmed(a_packet, before, tentative, payload, payload['legacyArguments'],
                    a_lower, a_upper, resolver(a, tentative, 'A_independent_existing_capture_resolver'))
            if not catalogue:
                require(catalogue_tentative == catalogue_before, 'A_preserves_entire_catalogue')
            b.begin()
            ticket = b.send(mutation(case, b_kind, 'B'), 'B_real_' + b_kind + '_after_observed_wait')
            blocker = wait_block(a, pids[0], pids[1], owner, lock_kind)
            expiry_clock = None
            if expiry:
                # A never UPDATEs after B locks admission: that would create an FK
                # parent KEY SHARE inversion instead of the product's real wait.
                expiry_clock = clock(a, 'real_clock_before_expiry_crossing')
                require(instant(expiry_clock) < instant(armed), 'SETUP_EXPIRY_WINDOW_EXHAUSTED_before_crossing')
                limit = min(deadline, time.monotonic() + 6)
                while time.monotonic() < limit:
                    expiry_clock = clock(a, 'real_clock_while_B_rowblocked_until_expiry')
                    if instant(expiry_clock) >= instant(armed):
                        break
                require(instant(expiry_clock) >= instant(armed), 'actual_server_clock_crossed_pending_expiry')
                require(wait_block(a, pids[0], pids[1], owner, 'row') == blocker,
                    'B_remains_real_rowblocked_after_expiry')
                tentative = state(a, owner, 'A_timestamp_expired_but_status_still_pending')
                require(one(tentative, P) == one(before, P) | {'expires_at': armed},
                    'single_arm_expired_timestamp_no_status_mutation')
                unchanged_except(before, tentative, {P}, 'single_arm_no_other_effect')
            release_lower = clock(a, 'real_clock_immediately_before_A_release')
            a.finish(commit)
            b_packet = b.receive(ticket, timeout=min(15, max(0.01, deadline - time.monotonic())))
            b_upper = clock(b, 'real_clock_after_B_result')
            b.finish(True)
            after = state(a, owner, 'independent_durable_after_B_commit')
            outside_after = outside(a, owner, 'durable_all_outside_rows')
            catalogue_after = query(a, F + 'catalogue_state()', 'durable_entire_catalogue')
            if commit and reset:
                forbidden(b_packet, 'stale_epoch')
                require(after == tentative, 'stale_epoch_precedes_pending_missing_without_capture')
            elif commit and deleted:
                forbidden(b_packet, 'pending_missing')
                require(after == tentative, 'pending_missing_without_life_or_capture_recreation')
            elif expiry:
                conflict(b_packet, tentative, 'expired')
                require(after == tentative, 'expired_after_rowwait_no_new_life_or_S7_effect')
            elif commit and legacy:
                conflict(b_packet, tentative, 'not_pending')
                require(after == tentative, 'terminal_status_seen_after_rowwait_no_capture')
            elif catalogue and commit:
                require(success(b_packet, 'native_catalogue_conflict_success') == {
                    'status': 'conflict', 'reason': 'capture_not_accepted',
                    'registration': projection(before), 'capture': {'legacy_result': None,
                        'strength': {'status': 'conflict', 'reason': 'source_observation_changed'}}},
                    'exact_native_catalogue_CAS_negative_wire')
                require(after == before, 'catalogue_negative_rolls_back_new_life_pointer_command_capture')
            elif commit and not catalogue:
                if a_kind == 'confirm' and b_kind == 'confirm':
                    reused(b_packet, tentative, after, resolver(a, after, 'B_replay_independent_resolver'))
                else:
                    reason = 'revision_conflict' if a_kind == 'edit' else 'already_confirmed' if a_kind == 'confirm' else 'not_pending'
                    conflict(b_packet, tentative, reason)
                    require(after == tentative, 'committed_winner_fullstate_no_loser_side_effect')
            elif b_kind == 'confirm':
                confirmed(b_packet, before, after, payload, payload['legacyArguments'],
                    release_lower, b_upper, resolver(a, after, 'B_independent_existing_capture_resolver'))
            elif b_kind == 'edit':
                edited(b_packet, before, after, payload, release_lower, b_upper)
            else:
                cancelled(b_packet, before, after, release_lower, b_upper)
            require(catalogue_after == (catalogue_tentative if catalogue and commit else catalogue_before),
                'catalogue_commit_or_rollback_exact_full_rows')
            unchanged_except(outside_before, outside_after, {CAT} if catalogue and commit else set(),
                'every_global_product_group_outside_owner_preserved_except_explicit_owned_catalogue_change')
            require(state(a, sentinel, 'sentinel_after_case') == sentinel_before,
                'other_owner_sentinel_fullstate_preserved')
            result['cases'].append({'id': case, 'passed': True, 'A_committed': commit,
                'actual_blocker': blocker, 'postwait_clock_lower_bound': release_lower,
                'B_result_clock_upper_bound': b_upper, 'expiry_server_crossing': expiry_clock,
                'B_actual_service_role_mutator': True, 'current_fullstate_and_exact_envelope': True,
                'fresh_capture_cardinality_or_exact_negative_or_replay': True,
                'every_outside_group_checked': True})
        require([c['id'] for c in result['cases']] == CASE_IDS, 'all_exact_19_cases_once')
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
