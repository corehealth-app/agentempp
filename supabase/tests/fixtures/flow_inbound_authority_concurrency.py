#!/usr/bin/env python3
"""Private S17I-A test-first source. No import-time work or server lifecycle.
Root alone runs after adopting the reviewed fixture and supplying exact bindings.
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
CASE_IDS = ['persist-reset-commit', 'persist-reset-rollback',
    'reset-persist-commit', 'reset-persist-rollback',
    'persist-persist-commit', 'persist-persist-rollback', 'probe-reset', 'reset-probe']
F = 'c59s17i_fixture.'
J = 'private.workout_strength_request_admissions'
E = 'private.workout_strength_authority_epochs'
M = 'public.messages'
PREFIX = 'c59f1700-0000-0000-0000-'
MESSAGE_FIELDS = {'id', 'user_id', 'direction', 'role', 'content_type', 'content',
    'media_url', 'media_storage_path', 'provider', 'provider_message_id', 'raw_payload',
    'intent', 'agent_stage', 'model_used', 'prompt_tokens', 'completion_tokens',
    'cost_usd', 'latency_ms', 'delivery_status', 'delivery_error', 'created_at',
    'review_flag', 'review_flagged_by', 'review_flagged_at', 'review_note'}
CLOCK = "pg_catalog.to_char(pg_catalog.clock_timestamp() AT TIME ZONE 'UTC','YYYY-MM-DD\"T\"HH24:MI:SS.US\"Z\"')"
B_REQUEST = 's17i-second-request'
B_STARTED = '2026-10-15T12:01:00.456Z'


def require(value, label):
    if value is not True:
        raise RuntimeError('C59S17I_DRIVER:' + label)


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


def success(packet):
    require(isinstance(packet, dict) and set(packet) == {'ok', 'result'}
        and packet['ok'] is True and isinstance(packet['result'], dict), 'native_RPC_success')
    return packet['result']


def unchanged_except(before, after, allowed):
    require(set(before) == set(after), 'same_full_state_groups')
    require({k: v for k, v in before.items() if k not in allowed}
        == {k: v for k, v in after.items() if k not in allowed}, 'all_other_owned_groups_exact')


def inbound(row, started):
    require(instant(row['created_at']) == instant(started), 'actual_created_at_exact_input_instant')
    return {k: row[k] for k in ('id', 'direction', 'content', 'delivery_status', 'raw_payload')} | {
        'created_at': started}


def inserted(packet, before, after, payload, request_id, started):
    body = success(packet)
    row = one(after, M)
    old_j, new_j = one(before, J), one(after, J)
    require(before[M] == [] and old_j['flow_inbound_id'] is None
        and old_j['flow_inbound_refusal'] is None
        and old_j['original_inbound_id'] is None and old_j['lifecycle_key'] is None,
        'fresh_unbound_original_admission_no_life')
    require(isinstance(row['id'], str) and re.fullmatch(
        r'[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}', row['id']) is not None,
        'actual_DB_UUID')
    expected = dict.fromkeys(MESSAGE_FIELDS)
    expected.update({'id': row['id'], 'user_id': payload['ownerID'], 'direction': 'in',
        'role': 'user', 'content_type': 'text', 'content': payload['text'],
        'provider': 'mobile_flow',
        'provider_message_id': 'mobile_flow/' + payload['ownerID'] + '/' + payload['requestKey'],
        'delivery_status': 'processing', 'created_at': row['created_at'],
        'raw_payload': {'request_id': request_id, 'conversation_id': 'flow',
            'attempt_started_at': started, 'provider_started_at': None, 'retry_started_at': []}})
    require(row == expected, 'exact_new_message_fullrow_defaults_and_operational_literals')
    require(new_j == old_j | {'flow_inbound_id': row['id']}, 'receipt_only_first_UUID_no_oldpair_update')
    require(instant(before['user']['last_active_at']) < instant(started), 'fixture_old_activity_precondition')
    require(after['user'] == before['user'] | {'last_active_at': row['created_at']},
        'real_IN_trigger_only_last_active_no_updated_at_wildcard')
    unchanged_except(before, after, {J, M, 'user'})
    require(body == {'status': 'inserted', 'inbound': inbound(row, started)}, 'exact_inserted_wire6')
    return body


def stale(packet):
    require(success(packet) == {'status': 'forbidden', 'reason': 'stale_epoch'},
        'exact_stale_before_replay_without_inbound')


def run(config):
    output = Path(config['output_dir'])
    output.mkdir(parents=True, exist_ok=False)
    result = {'executed': False, 'failure': None, 'cases': [],
        'noncooperative_legacy_INSERT': 'NOT_TESTED_40P01_MAY_PROPAGATE_WITH_ROLLBACK',
        'cleanup': {'complete': False, 'actors_reaped': False, 'readers_stopped': False, 'actors': []}}
    actors, original_failure = [], None
    deadline = time.monotonic() + 240

    def query(actor, expression, label, maximum=15):
        remaining = deadline - time.monotonic()
        require(remaining > 0 and maximum > 0, 'bounded_global_deadline')
        return actor.query(expression, label, timeout=min(maximum, remaining))

    def state(actor, owner, label):
        return query(actor, F + 'state(' + lit(owner) + '::uuid)', label)

    def outside(actor, owner, label):
        return query(actor, F + 'outside(' + lit(owner) + '::uuid)', label)

    def command(case, operation, second=False):
        tail = ' FROM ' + F + 'cases WHERE case_id=' + lit(case)
        if operation == 'reset':
            sql = '(SELECT ' + F + 'reset_sql(payload,true)' + tail + ')'
        else:
            require(operation in ('persist', 'probe'), 'known_operation')
            args = ','.join([lit(operation), lit(B_REQUEST if second else 's17i-original-request'),
                lit(B_STARTED if second else '2026-10-15T12:00:00.123Z')])
            sql = '(SELECT ' + F + 'access_sql(payload,' + args + ')' + tail + ')'
        return F + 'attempt(' + sql + ')'

    def assert_reset(actor, before, after, packet, owner):
        require(success(packet) == {'reset': True, 'user_id': owner,
            'deleted_rows': len(before[M]), 'kept_plans': True}, 'real_reset_wire_exact_fixture_rows')
        actor.statement('SELECT ' + F + 'assert_reset(' + lit(json.dumps(before))
            + '::jsonb,' + lit(json.dumps(after)) + '::jsonb);')

    def wait_block(observer, blocker, waiter, owner):
        limit = min(deadline, time.monotonic() + 8)
        key = 'pg_catalog.hashtextextended(' + lit(owner + ':workouts') + ',0)'
        high, low = '((' + key + ' >> 32) & 4294967295)', '(' + key + ' & 4294967295)'
        predicate = str(blocker) + '=ANY(pg_catalog.pg_blocking_pids(' + str(waiter) + ')) AND EXISTS('
        predicate += 'SELECT 1 FROM pg_catalog.pg_locks a JOIN pg_catalog.pg_locks b ON '
        predicate += 'a.locktype=b.locktype AND a.database=b.database AND a.classid=b.classid '
        predicate += 'AND a.objid=b.objid AND a.objsubid=b.objsubid WHERE a.pid=' + str(blocker)
        predicate += ' AND b.pid=' + str(waiter) + " AND a.locktype='advisory' AND a.mode='ExclusiveLock'"
        predicate += " AND b.mode='ExclusiveLock' AND a.granted AND NOT b.granted AND a.objsubid=1"
        predicate += ' AND a.classid::bigint=' + high + ' AND a.objid::bigint=' + low + ')'
        while time.monotonic() < limit:
            observer.statement('SELECT pg_catalog.pg_stat_clear_snapshot();')
            if query(observer, '(' + predicate + ')', 'actual_exact_workouts_advisory_blocker',
                    limit - time.monotonic()) is True:
                return 'exact_workouts_advisory_pg_blocking_pids_and_pg_locks'
        raise TimeoutError('C59S17I_DRIVER:no_actual_workouts_advisory_blocker')

    try:
        require(config.get('root_reviewed') is True, 'root_review_required')
        path = Path(config['driver_path']).resolve(strict=True)
        require(hashlib.sha256(path.read_bytes()).hexdigest() == config['driver_sha256'], 'driver_pin')
        actor_path = Path(config['actor_module']).resolve(strict=True)
        source = actor_path.read_bytes()
        require(actor_path == path.parent / 'workout_strength_commands_concurrency.py'
            and config.get('actor_sha256') == ACTOR_SHA
            and hashlib.sha256(source).hexdigest() == ACTOR_SHA, 'closed_relative_Actor_pin')
        require(config.get('user') == 'c5_local_admin' and config.get('database') == 'c5_reset_default_20261009'
            and config.get('port') == 55489 and config.get('socket') == '/private/tmp/performe-c5-osecmg7_'
            and config.get('expected_data_directory') == '/Users/eduardohenrique/.local/share/performe-ai/final-polish-20261001/e3/c5-portable-postgres17-20261009/data',
            'exact_retained_C5_no_new_environment')
        require(Path(config['psql']).is_absolute()
            and hashlib.sha256(Path(config['psql']).read_bytes()).hexdigest() == config['psql_sha256']
            and config.get('expected_case_ids') == CASE_IDS, 'psql_and_exact8_case_pins')
        base = types.ModuleType('c59s17i_closed_Actor')
        exec(compile(source, str(actor_path), 'exec'), base.__dict__)
        a = base._create_registered_actor('A', config, output, actors)
        b = base._create_registered_actor('B', config, output, actors)
        pids = []
        for actor in actors:
            identity = query(actor, "jsonb_build_object('owner',session_user,'db',current_database(),"
                "'port',current_setting('port')::int,'data',current_setting('data_directory'),"
                "'socket',current_setting('unix_socket_directories'),'listen',current_setting('listen_addresses'),"
                "'pid',pg_backend_pid(),'tag',(SELECT tag FROM " + F + 'ownership))', 'identity')
            require(identity['owner'] == config['user'] and identity['db'] == config['database']
                and identity['port'] == config['port'] and identity['data'] == config['expected_data_directory']
                and identity['socket'] == config['socket'] and identity['listen'] == ''
                and identity['tag'] == 'c59s17i_atomic_in_v1', 'actual_owned_local_identity')
            pids.append(identity['pid'])
            actor.statement("SET statement_timeout='20s';SET lock_timeout='15s';"
                "SET request.jwt.claims='{\"role\":\"service_role\"}';SET TimeZone='UTC';SET DateStyle='ISO,YMD';")
        require(pids[0] != pids[1], 'distinct_real_A_B_backends')
        sentinel = PREFIX + '000000004999'
        sentinel_before = state(a, sentinel, 'initial_sentinel')
        result['executed'] = True
        for index, case in enumerate(CASE_IDS):
            owner = PREFIX + str(index + 4301).zfill(12)
            payload = query(a, F + 'payload(' + lit(case) + ')', 'real_case_payload')
            require(payload['ownerID'] == owner and payload['requestKey'] == 's17i-request-' + str(index + 4301)
                and payload['requestHash'] == hashlib.sha256(payload['text'].encode('utf-8')).hexdigest()
                and payload['requestID'] == 's17i-original-request'
                and payload['startedAt'] == '2026-10-15T12:00:00.123Z', 'fixture_owned_literal_input_hash_not_JSON')
            before = state(a, owner, 'initial_fullstate')
            outside_before = outside(a, owner, 'initial_every_outside_product_table')
            require(before == payload['initialState'] and before[M] == []
                and one(before, J)['admission_id'] == payload['admission']['admissionID']
                and one(before, E)['epoch'] == payload['admission']['epoch'], 'actual_setup_original_S15_admission')
            a_op, b_op = case.split('-')[:2]
            commit = not case.endswith('-rollback')
            a.begin()
            a_packet = query(a, command(case, a_op), 'A_real_' + a_op)
            tentative = state(a, owner, 'A_independent_tentative_fullstate')
            if a_op == 'persist':
                inserted(a_packet, before, tentative, payload, payload['requestID'], payload['startedAt'])
            elif a_op == 'probe':
                require(success(a_packet) == {'status': 'unbound'} and tentative == before,
                    'probe_unbound_no_IN_no_receipt_no_clock_no_life')
            else:
                assert_reset(a, before, tentative, a_packet, owner)
            b.begin()
            ticket = b.send(command(case, b_op, True), 'B_real_' + b_op + '_after_observed_wait')
            blocker = wait_block(a, pids[0], pids[1], owner)
            release_lower = query(a, CLOCK, 'server_clock_before_A_release')
            a.finish(commit)
            b_packet = b.receive(ticket, timeout=min(15, max(.01, deadline - time.monotonic())))
            b.finish(True)
            after = state(a, owner, 'independent_durable_after_B_commit')
            if b_op == 'reset':
                assert_reset(a, tentative if commit else before, after, b_packet, owner)
            elif a_op == 'reset' and commit:
                stale(b_packet)
                require(after == tentative, 'stale_gate_after_real_reset_no_other_change')
            elif a_op == 'persist' and commit:
                row = one(tentative, M)
                require(success(b_packet) == {'status': 'reused', 'inbound': inbound(row, payload['startedAt'])}
                    and after == tentative, 'same_first_IN_attempt_and_clock_no_B_overwrite')
            else:
                inserted(b_packet, before, after, payload, B_REQUEST, B_STARTED)
            if b_op == 'reset' or a_op == 'reset' and commit:
                for mode in ('probe', 'persist'):
                    retry = query(a, command(case, mode, True), 'old_admission_' + mode + '_after_reset')
                    stale(retry)
                    require(state(a, owner, 'old_admission_fullstate_unchanged') == after,
                        'old_retry_never_recreates_IN_or_refusal')
            else:
                for mode, status in [('probe', 'bound'), ('persist', 'reused')]:
                    replay = query(a, command(case, mode, True), 'durable_original_UUID_' + mode)
                    expected_time = payload['startedAt'] if a_op == 'persist' and commit else B_STARTED
                    require(success(replay) == {'status': status,
                        'inbound': inbound(one(after, M), expected_time)}, 'exact_durable_replay_wire')
                    require(state(a, owner, 'durable_replay_fullstate_unchanged') == after,
                        'durable_replay_no_renewal_or_new_IN')
            require(outside(a, owner, 'durable_every_outside_product_table') == outside_before,
                'all_global_and_other_owner_groups_preserved')
            require(state(a, sentinel, 'sentinel_after_case') == sentinel_before, 'sentinel_fullstate_preserved')
            result['cases'].append({'id': case, 'passed': True, 'A_committed': commit,
                'actual_blocker': blocker, 'A_result': success(a_packet), 'B_result': success(b_packet),
                'server_clock_before_A_release': release_lower,
                'full_owned_state_checked': True, 'all_outside_and_sentinel_preserved': True})
        require([c['id'] for c in result['cases']] == CASE_IDS, 'all_exact8_cases_once')
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
        reaped = len(cleanup) == 2 and all(c['reaped'] for c in cleanup)
        readers = len(cleanup) == 2 and all(c['readers_stopped'] for c in cleanup)
        complete = reaped and readers and all(c.get('exit_code') == 0 for c in cleanup)
        result['cleanup'] = {'complete': complete, 'actors_reaped': reaped,
            'readers_stopped': readers, 'actors': cleanup}
        if original_failure is None and not complete:
            result['failure'] = 'RuntimeError'
            result['failure_label'] = 'two_owned_actors_exit0_and_readers_stopped'
        try:
            (output / 'RESULT.json').write_text(json.dumps(result, indent=2) + '\n', encoding='utf-8')
        except BaseException:
            if original_failure is None:
                raise
    require(result['cleanup']['complete'] is True, 'two_owned_actors_exit0_and_readers_stopped')
    return result


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--bindings-json', required=True)
    parser.add_argument('--output-dir', required=True)
    args = parser.parse_args()
    config = json.loads(Path(args.bindings_json).read_text(encoding='utf-8'))
    config['output_dir'] = args.output_dir
    run(config)
