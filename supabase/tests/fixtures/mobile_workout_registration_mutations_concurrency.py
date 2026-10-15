#!/usr/bin/env python3
"""Private S17C test-first A/B source. Import is inert; Root supplies bindings.
No server lifecycle, product DDL, prepare or teardown. Actor S7 remains literal.
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
    'edit-edit-commit', 'edit-edit-rollback',
    'edit-cancel-commit', 'edit-cancel-rollback',
    'cancel-edit-commit', 'cancel-edit-rollback',
    'legacy-terminal-edit-commit', 'legacy-terminal-edit-rollback',
    'legacy-terminal-cancel-commit', 'legacy-terminal-cancel-rollback',
    'expiry-edit-after-rowlock', 'expiry-cancel-after-rowlock',
    'reset-edit-commit', 'reset-edit-rollback',
    'delete-pending-edit-commit', 'delete-pending-edit-rollback',
]
PREFIX = 'c59c7000-0000-0000-0000-'
F = 'c59s17c_fixture.'
J = 'private.mobile_workout_proposal_admissions'
P = 'public.pending_registrations'
R = 'private.mobile_workout_registration_edit_receipts'
E = 'private.workout_strength_authority_epochs'
CLOCK = "pg_catalog.to_char(pg_catalog.clock_timestamp() AT TIME ZONE 'UTC','YYYY-MM-DD\"T\"HH24:MI:SS.US\"Z\"')"


def require(value, label):
    if value is not True:
        raise RuntimeError('C59S17C_DRIVER:' + label)


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


def edited(packet, before, after, payload, side, low, high, input_hash):
    body = success(packet, 'native_edited_success')
    old_j, new_j = one(before, J), one(after, J)
    old_p, new_p = one(before, P), one(after, P)
    revision = old_j['content_revision']
    require(type(revision) is int and revision == 0, 'case_real_original_revision0')
    key, proposal = payload['editKey' + side], payload['editProposal' + side]
    require(set(body) == {'status', 'registration', 'receipt'} and body['status'] == 'edited'
        and body['registration'] == projection(after)
        and body['receipt'] == {'requestKey': key, 'expectedRevision': revision,
            'resultRevision': revision + 1}, 'exact_edit_wire_receipt_current_projection')
    require(new_j == old_j | {'content_revision': revision + 1}, 'admission_only_revision_changes')
    require(new_p == old_p | {'proposal': proposal, 'expires_at': new_p['expires_at']},
        'same_pending_only_proposal_and_expiry_changes')
    renewed = instant(new_p['expires_at']) - datetime.timedelta(hours=24)
    require(instant(low) <= renewed <= instant(high), 'real_server_24_elapsed_hours_after_locks')
    require(before[R] == [] and after[R] == [{
        'user_id': old_j['user_id'], 'admission_id': old_j['admission_id'],
        'request_key': key, 'input_hash': input_hash,
        'expected_revision': revision, 'result_revision': revision + 1}],
        'one_exact_new_receipt_input_hash_not_candidate_hash')
    unchanged_except(before, after, {J, P, R}, 'edit_no_other_effects')


def cancelled(packet, before, after, low, high):
    body = success(packet, 'native_cancelled_success')
    old_p, new_p = one(before, P), one(after, P)
    require(set(body) == {'status', 'registration'} and body['status'] == 'cancelled'
        and body['registration'] == projection(after), 'exact_cancel_wire_current_projection')
    require(old_p['status'] == 'pending'
        and new_p == old_p | {'status': 'cancelled', 'resolved_at': new_p['resolved_at']},
        'cancel_only_status_and_resolved_at_changes')
    require(instant(low) <= instant(new_p['resolved_at']) <= instant(high),
        'cancel_resolved_at_real_server_clock_after_locks')
    unchanged_except(before, after, {P}, 'cancel_preserves_revision_receipts_expiry_all_other_state')


def conflict(packet, state, reason):
    body = success(packet, 'native_conflict_success')
    require(body == {'status': 'conflict', 'reason': reason, 'registration': projection(state)},
        'exact_owned_conflict_no_receipt:' + reason)


def forbidden(packet, reason):
    body = success(packet, 'native_authority_negative_success')
    require(body == {'status': 'forbidden', 'reason': reason},
        'exact_authority_negative_without_projection:' + reason)


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
        require(remaining > 0, 'bounded_global_deadline')
        return actor.query(expression, label, timeout=min(maximum, remaining))

    def clock(actor, label):
        return query(actor, CLOCK, label)

    def state(actor, owner, label):
        return query(actor, F + 'state(' + lit(owner) + '::uuid)', label)

    def select_case(case):
        return ' FROM ' + F + 'cases WHERE case_id=' + lit(case)

    def mutation(case, kind, side='B'):
        tail = select_case(case)
        if kind == 'edit':
            sql = '(SELECT ' + F + "edit_sql(owner_id,(payload->>'registrationID')::uuid,0," \
                + "payload->>'editKey" + side + "',payload->'editInput" + side + "',payload->'editProposal" + side + "')" + tail + ')'
        else:
            require(kind == 'cancel', 'known_mutator')
            sql = '(SELECT ' + F + "cancel_sql(owner_id,(payload->>'registrationID')::uuid,0)" + tail + ')'
        return F + 'attempt(' + sql + ')'

    def attempt_sql(sql, role='service_role'):
        return F + 'attempt(' + lit(sql) + ',' + lit(role) + ')'

    def wait_block(observer, blocker, waiter, owner, row):
        limit = min(deadline, time.monotonic() + 8)
        native_edge = str(blocker) + '=ANY(pg_catalog.pg_blocking_pids(' + str(waiter) + '))'
        if row:
            predicate = native_edge + ' AND EXISTS(SELECT 1 FROM pg_catalog.pg_locks a JOIN pg_catalog.pg_locks b ON a.transactionid=b.transactionid WHERE a.pid=' + str(blocker) + ' AND b.pid=' + str(waiter) + " AND a.locktype='transactionid' AND b.locktype='transactionid' AND a.granted AND NOT b.granted AND a.mode='ExclusiveLock' AND b.mode='ShareLock') AND NOT EXISTS(SELECT 1 FROM pg_catalog.pg_locks x WHERE x.pid=" + str(waiter) + " AND x.locktype='advisory' AND NOT x.granted)"
            label = 'actual_pending_row_transaction_blocker'
        else:
            lock_key = 'pg_catalog.hashtextextended(' + lit(owner + ':workouts') + ',0)'
            high, low = '((' + lock_key + ' >> 32) & 4294967295)', '(' + lock_key + ' & 4294967295)'
            predicate = native_edge + ' AND EXISTS(SELECT 1 FROM pg_catalog.pg_locks a JOIN pg_catalog.pg_locks b ON a.locktype=b.locktype AND a.database=b.database AND a.classid=b.classid AND a.objid=b.objid AND a.objsubid=b.objsubid WHERE a.pid=' + str(blocker) + ' AND b.pid=' + str(waiter) + " AND a.locktype='advisory' AND a.granted AND NOT b.granted AND a.objsubid=1 AND a.classid::bigint=" + high + ' AND a.objid::bigint=' + low + ')'
            label = 'actual_exact_workouts_advisory_blocker'
        while time.monotonic() < limit:
            observer.statement('SELECT pg_catalog.pg_stat_clear_snapshot();')
            if query(observer, '(' + predicate + ')', label, limit - time.monotonic()) is True:
                return label
        raise TimeoutError('C59S17C_DRIVER:no_' + label)

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
            == config['psql_sha256'] and config.get('expected_case_ids') == CASE_IDS, 'psql_and_exact_16_case_pins')
        base = types.ModuleType('c59s17c_closed_Actor')
        exec(compile(source, str(actor_path), 'exec'), base.__dict__)
        a = base._create_registered_actor('A', config, output, actors)
        b = base._create_registered_actor('B', config, output, actors)
        pids = []
        for actor in actors:
            identity = query(actor, "jsonb_build_object('owner',session_user,'db',current_database(),'port',current_setting('port')::int,'data',current_setting('data_directory'),'socket',current_setting('unix_socket_directories'),'listen',current_setting('listen_addresses'),'pid',pg_backend_pid(),'tag',(SELECT tag FROM " + F + 'ownership))', 'identity')
            require(identity['owner'] == config['user'] and identity['db'] == config['database']
                and identity['port'] == config['port'] and identity['data'] == config['expected_data_directory']
                and identity['socket'] == config['socket'] and identity['listen'] == ''
                and identity['tag'] == 'c59s17c_edit_cancel_v1', 'actual_local_identity')
            pids.append(identity['pid'])
            actor.statement("SET statement_timeout='20s';SET lock_timeout='15s';SET request.jwt.claims='{\"role\":\"service_role\"}';SET TimeZone='UTC';SET DateStyle='ISO,YMD';")
        require(pids[0] != pids[1], 'distinct_real_A_B')
        sentinel = PREFIX + '000000001999'
        sentinel_before = state(a, sentinel, 'initial_sentinel')
        require(sentinel_before == query(a, "(SELECT payload->'initialState' FROM " + F + "cases WHERE case_id='sentinel')", 'stored_setup_sentinel'), 'real_setup_sentinel')
        result['executed'] = True
        for index, case in enumerate(CASE_IDS):
            payload = query(a, '(SELECT payload' + select_case(case) + ')', 'case_real_payload')
            owner = PREFIX + str(index + 1801).zfill(12)
            require(payload['ownerID'] == owner and payload['requestKey'] == 'wui1:' + owner
                and payload['editKeyA'] == 'wue1:' + PREFIX + str(index + 2801).zfill(12)
                and payload['editKeyB'] == 'wue1:' + PREFIX + str(index + 3801).zfill(12)
                and payload['input'] == {'kind': 'workout', 'workout_type': 'Natação', 'duration_min': 40, 'intensity': 'moderada'}
                and payload['editInputA'] == payload['input'] | {'duration_min': 45}
                and payload['editInputB'] == payload['input'] | {'duration_min': 50}, 'case_exact_owned_keys_and_Natacao40_45_50')
            before = state(a, owner, 'before_case')
            require(before == payload['initialState'] and one(before, J)['content_revision'] == 0
                and one(before, P)['id'] == payload['registrationID'] and one(before, P)['status'] == 'pending'
                and one(before, P)['proposal'] == payload['proposal'] and before[R] == [], 'real_S17B_prepared_original_fullstate')
            input_hashes = query(a, "(SELECT jsonb_build_object('A',private.mobile_workout_proposal_input_hash(payload->'editInputA'),'B',private.mobile_workout_proposal_input_hash(payload->'editInputB'))" + select_case(case) + ')', 'closed_S16_input_hashes_before_mutation')
            require(input_hashes == {'A': payload['inputHashA'], 'B': payload['inputHashB']},
                'prepared_hashes_match_closed_S16_input_not_candidate_or_revision')
            row = case.startswith(('legacy-terminal-', 'expiry-', 'delete-pending-'))
            expiry = case.startswith('expiry-')
            reset = case.startswith('reset-')
            deleted = case.startswith('delete-pending-')
            legacy = case.startswith('legacy-terminal-')
            b_kind = 'cancel' if case.startswith(('edit-cancel-', 'legacy-terminal-cancel-', 'expiry-cancel-')) else 'edit'
            a_kind = 'cancel' if case.startswith('cancel-edit-') else 'edit'
            commit = not case.endswith('-rollback')
            a.begin()
            a_lower = clock(a, 'before_A_real_operation')
            a_packet = None
            if expiry:
                armed = query(a, F + 'arm_expiry_case(' + lit(case) + ')', 'A_arm_real_fixture_owned_expiry')
                require(instant(armed) > instant(a_lower), 'expiry_armed_in_real_future')
            elif reset:
                a_packet = query(a, attempt_sql('SELECT public.reset_user_conversation_atomic(' + lit(owner) + '::uuid,true)'), 'A_real_reset')
                reset_body = success(a_packet, 'real_reset_success')
                require(reset_body == {'reset': True, 'user_id': owner, 'deleted_rows': 1, 'kept_plans': True}, 'exact_real_reset_one_prepared_pending')
            elif deleted:
                a_packet = query(a, attempt_sql('DELETE FROM ONLY ' + P + ' p WHERE p.user_id=' + lit(owner) + '::uuid AND p.id=' + lit(payload['registrationID']) + '::uuid RETURNING to_jsonb(p)'), 'A_real_service_DELETE_pending')
                require(success(a_packet, 'real_delete_success') == one(before, P), 'delete_exact_original_pending_only')
            elif legacy:
                terminal = 'expired' if b_kind == 'cancel' else 'cancelled'
                sql = 'UPDATE ONLY ' + P + ' p SET status=' + lit(terminal) + ',resolved_at=pg_catalog.clock_timestamp() WHERE p.user_id=' + lit(owner) + '::uuid AND p.id=' + lit(payload['registrationID']) + '::uuid RETURNING to_jsonb(p)'
                a_packet = query(a, attempt_sql(sql), 'A_real_service_legacy_terminal_rowlock')
                terminal_row = success(a_packet, 'native_terminal_update_success')
                require(terminal_row['status'] == terminal, 'exact_legacy_terminal_kind')
            else:
                a_packet = query(a, mutation(case, a_kind, 'A'), 'A_real_' + a_kind)
            a_upper = clock(a, 'after_A_real_operation')
            tentative = state(a, owner, 'A_tentative_before_B_wait')
            if expiry:
                require(one(tentative, P) == one(before, P) | {'expires_at': armed}, 'expiry_fixture_only_timestamp_delta')
                unchanged_except(before, tentative, {P}, 'expiry_arm_no_other_effect')
            elif reset:
                require(tentative[P] == [] and tentative[J] == before[J] and tentative[R] == []
                    and one(tentative, E)['epoch'] != one(before, E)['epoch'], 'reset_preserves_historical_admission_and_invalidates_epoch')
            elif deleted:
                require(tentative[P] == [], 'native_pending_deleted_not_rematerialized')
                unchanged_except(before, tentative, {P}, 'delete_no_other_owned_state_effect')
            elif legacy:
                require(one(tentative, P) == one(before, P) | {'status': terminal, 'resolved_at': terminal_row['resolved_at']}
                    and instant(a_lower) <= instant(terminal_row['resolved_at']) <= instant(a_upper), 'legacy_only_status_and_finite_real_resolved_at')
                unchanged_except(before, tentative, {P}, 'legacy_terminal_no_other_effect')
            elif a_kind == 'edit':
                edited(a_packet, before, tentative, payload, 'A', a_lower, a_upper, input_hashes['A'])
            else:
                cancelled(a_packet, before, tentative, a_lower, a_upper)
            b.begin()
            ticket = b.send(mutation(case, b_kind), 'B_real_' + b_kind + '_after_observed_wait')
            blocker = wait_block(a, pids[0], pids[1], owner, row)
            expiry_clock = None
            if expiry:
                # Never UPDATE A after B locks admission: a repeated UPDATE can
                # require FK parent KEY SHARE and invert B's admission -> pending locks.
                # Root's fixture arms one real five-second window before B starts.
                expiry_clock = clock(a, 'real_clock_before_expiry_crossing')
                require(instant(expiry_clock) < instant(armed),
                    'SETUP_EXPIRY_WINDOW_EXHAUSTED_before_observed_crossing')
                limit = min(deadline, time.monotonic() + 6)
                while time.monotonic() < limit:
                    expiry_clock = clock(a, 'real_clock_while_B_blocked_until_expiry')
                    if instant(expiry_clock) >= instant(armed):
                        break
                require(instant(expiry_clock) >= instant(armed), 'actual_server_clock_crossed_pending_expiry')
                require(wait_block(a, pids[0], pids[1], owner, True) == blocker, 'B_remains_row_blocked_after_expiry')
                tentative = state(a, owner, 'A_tentative_expired_timestamp_still_pending')
                require(one(tentative, P)['status'] == 'pending' and one(tentative, P)['expires_at'] == armed,
                    'timestamp_expired_not_terminal_status')
                require(one(tentative, P) == one(before, P) | {'expires_at': armed}, 'single_arm_only_exact_expiry_delta')
                unchanged_except(before, tentative, {P}, 'single_arm_no_other_state_effect')
            release_lower = clock(a, 'real_clock_immediately_before_release')
            a.finish(commit)
            b_packet = b.receive(ticket, timeout=min(15, max(0.01, deadline - time.monotonic())))
            b_upper = clock(b, 'real_clock_after_B_result')
            b.finish(True)
            after = state(a, owner, 'durable_after_B_commit')
            if commit and reset:
                forbidden(b_packet, 'stale_epoch')
                require(after == tentative, 'stale_epoch_precedes_pending_missing_no_mutation')
            elif commit and deleted:
                forbidden(b_packet, 'pending_missing')
                require(after == tentative, 'pending_missing_no_recreation_or_receipt')
            elif commit and expiry:
                if b_kind == 'edit':
                    conflict(b_packet, tentative, 'expired')
                    require(after == tentative, 'expired_edit_preserves_fullstate')
                else:
                    cancelled(b_packet, tentative, after, release_lower, b_upper)
                    require(instant(one(after, P)['expires_at']) <= instant(release_lower),
                        'cancel_succeeds_after_real_timestamp_expiry')
            elif commit and legacy:
                conflict(b_packet, tentative, 'not_pending')
                require(after == tentative, 'legacy_terminal_seen_after_rowwait_no_mutation')
            elif commit:
                reason = 'not_pending' if a_kind == 'cancel' else 'revision_conflict'
                conflict(b_packet, tentative, reason)
                require(after == tentative, 'committed_winner_fullstate_preserved_no_loser_receipt')
            elif b_kind == 'edit':
                edited(b_packet, before, after, payload, 'B', release_lower, b_upper, input_hashes['B'])
            else:
                cancelled(b_packet, before, after, release_lower, b_upper)
            require(state(a, sentinel, 'sentinel_after_case') == sentinel_before, 'other_owner_sentinel_fullstate_preserved')
            result['cases'].append({'id': case, 'passed': True, 'A_committed': commit,
                'actual_blocker': blocker, 'B_actual_service_role_mutator': True,
                'postwait_clock_lower_bound': release_lower, 'B_result_clock_upper_bound': b_upper,
                'expiry_server_crossing': expiry_clock, 'current_fullstate_and_exact_envelope': True,
                'all_other_owned_groups_and_sentinel_preserved': True})
        require([c['id'] for c in result['cases']] == CASE_IDS, 'all_exact_16_cases_once')
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
