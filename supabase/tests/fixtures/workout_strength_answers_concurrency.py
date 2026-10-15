#!/usr/bin/env python3
"""S9 real A/B answer oracles. Import inert, no PG lifecycle/DDL, pinned S7 actors."""
import argparse
import hashlib
import json
from pathlib import Path
import re
import time
import types

ACTOR_SHA = 'c14570d9059fbd56f4aa7efeeefeb9e0030b275c9b221a0890d1d484d1db1a5f'
CASE_IDS = ['yes-commit-no-loser', 'no-commit-yes-loser', 'yes-rollback-no-winner', 'no-rollback-yes-winner']


def require(value, label):
    if value is not True:
        raise RuntimeError('C59S9_DRIVER:' + label)


def lit(value):
    return "'" + str(value).replace("'", "''") + "'"


def answer(owner, life, workout, question, value, key):
    return 'public.answer_confirmed_workout_strength(' + ','.join([
        lit(owner), lit(life), lit(workout), '0', lit(question), lit(value), lit(key)]) + ')'


def verify(wire, status, owner, workout, question, value, key):
    require(isinstance(wire, dict) and set(wire) == {'status', 'receipt'} and wire['status'] == status, 'result2keys')
    receipt = wire['receipt']
    require(isinstance(receipt, dict) and set(receipt) == {'ownerID', 'workoutLogID', 'questionKey', 'answer', 'operationKey', 'acceptedAt'}, 'receipt6keys')
    require(receipt['ownerID'] == owner and receipt['workoutLogID'] == workout and receipt['questionKey'] == question
        and receipt['answer'] == value and receipt['operationKey'] == key, 'receipt_owned_original_content')
    require(isinstance(receipt['acceptedAt'], str) and re.fullmatch(r'[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}\.[0-9]{6}Z', receipt['acceptedAt']) is not None, 'receipt_US6')
    return receipt


def wait_block(observer, blocker_pid, waiter_pid):
    deadline = time.monotonic() + 6
    while time.monotonic() < deadline:
        observer.statement('SELECT pg_stat_clear_snapshot();')
        if observer.query(str(blocker_pid) + '=ANY(pg_blocking_pids(' + str(waiter_pid) + '))', 'actual_answer_block') is True:
            return
    raise TimeoutError('C59S9_DRIVER:missing_actual_answer_block')


def run(config):
    output = Path(config['output_dir'])
    output.mkdir(parents=True, exist_ok=False)
    result = {'executed': False, 'failure': None, 'cases': [],
        'cleanup': {'complete': False, 'actors_reaped': False, 'readers_stopped': False, 'actors': []}}
    actors = []
    try:
        require(config.get('root_reviewed') is True, 'root_review_required')
        own_path = Path(config['driver_path']).resolve(strict=True)
        require(hashlib.sha256(own_path.read_bytes()).hexdigest() == config['driver_sha256'], 'driver_pin')
        actor_path = Path(config['actor_module']).resolve(strict=True)
        require(actor_path == own_path.parent / 'workout_strength_commands_concurrency.py', 'relative_actor_path')
        source = actor_path.read_bytes()
        require(config.get('actor_sha256') == ACTOR_SHA and hashlib.sha256(source).hexdigest() == ACTOR_SHA, 'actor_pin')
        require(config.get('user') == 'c59a2_local_admin' and config.get('database') == 'postgres'
            and config.get('port') == 55493 and str(config.get('socket', '')).startswith('/private/tmp/performe-c59a2-pg.'), 'local_binding')
        require(Path(config['psql']).is_absolute() and hashlib.sha256(Path(config['psql']).read_bytes()).hexdigest() == config['psql_sha256'], 'psql_pin')
        require(config.get('expected_case_ids') == CASE_IDS, 'cases_pin')
        base = types.ModuleType('c59s9_pinned_actor_module')
        exec(compile(source, str(actor_path), 'exec'), base.__dict__)
        a = base._create_registered_actor('A', config, output, actors)
        b = base._create_registered_actor('B', config, output, actors)
        pids = []
        for actor in actors:
            identity = actor.query("jsonb_build_object('owner',session_user,'db',current_database(),'port',current_setting('port')::int,'data',current_setting('data_directory'),'socket',current_setting('unix_socket_directories'),'listen',current_setting('listen_addresses'),'isolation',current_setting('transaction_isolation'),'pid',pg_backend_pid(),'marker',(SELECT tag FROM c59s9_fixture.ownership))", 'identity')
            require(identity['owner'] == config['user'] and identity['db'] == config['database'] and identity['port'] == config['port']
                and identity['data'] == config['expected_data_directory'] and identity['socket'] == config['socket']
                and identity['listen'] == '' and identity['isolation'] == 'read committed' and identity['marker'] == 'c59s9_answers_v1', 'actual_identity')
            pids.append(identity['pid'])
            actor.statement("SET statement_timeout='12s';SET lock_timeout='9s';SET request.jwt.claims='{\"role\":\"service_role\"}';")
        require(pids[0] != pids[1], 'distinct_A_B')
        result['executed'] = True
        for index, (value_a, commit) in enumerate([('yes', True), ('no', True), ('yes', False), ('no', False)]):
            number = 11 + index
            owner = 'c59aa000-0000-0000-0000-' + str(number).zfill(12)
            life = 'c59aa000-0000-0000-0000-' + str(number + 100).zfill(12)
            key_a = 'answer-A-' + str(number)
            key_b = 'answer-B-' + str(number)
            value_b = 'no' if value_a == 'yes' else 'yes'
            anchor = a.query("(SELECT jsonb_build_object('workout',workout_log_id::text,'question',question_key::text,'revision',revision) FROM private.workout_strength_facts WHERE user_id=" + lit(owner) + '::uuid)', 'real_S8_fact_question')
            require(isinstance(anchor, dict) and anchor['revision'] == 0, 'real_unanswered_fact')
            workout, question = anchor['workout'], anchor['question']
            before_fact = a.query('private.workout_strength_fact_snapshot(' + ','.join([lit(owner), lit(life), lit(workout)]) + ')', 'before_fact')
            before_immutable = a.query('c59s9_fixture.immutable_state(' + lit(owner) + ')', 'before_immutable')
            a.begin()
            first = a.query(answer(owner, life, workout, question, value_a, key_a), 'answer_A')
            receipt_a = verify(first, 'accepted', owner, workout, question, value_a, key_a)
            b.begin()
            pending = b.send(answer(owner, life, workout, question, value_b, key_b), 'answer_B')
            wait_block(a, pids[0], pids[1])
            lower = a.query("to_char(clock_timestamp() AT TIME ZONE 'UTC','YYYY-MM-DD\"T\"HH24:MI:SS.US\"Z\"')", 'post_block_lower_bound')
            a.finish(commit)
            response_b = b.receive(pending)
            if commit:
                require(response_b == {'status': 'conflict', 'reason': 'stale_fact'}, 'committed_A_new_B_CAS0_stale')
                winner, value, key = receipt_a, value_a, key_a
                loser_value, loser_key = value_b, key_b
            else:
                winner = verify(response_b, 'accepted', owner, workout, question, value_b, key_b)
                value, key = value_b, key_b
                loser_value, loser_key = value_a, key_a
            b.finish(True)
            replay = a.query(answer(owner, life, workout, question, value, key), 'winner_original_revision0_replay')
            require(verify(replay, 'reuse_existing', owner, workout, question, value, key) == winner, 'same_exact_winning_receipt')
            loser = b.query(answer(owner, life, workout, question, loser_value, loser_key), 'loser_retry')
            require(loser == {'status': 'conflict', 'reason': 'stale_fact'}, 'loser_no_binding_or_overwrite')
            actual = a.query('private.workout_strength_fact_snapshot(' + ','.join([lit(owner), lit(life), lit(workout)]) + ')', 'durable_fact')
            expected = dict(before_fact)
            expected.update({'revision': 1, 'clarification': {'status': 'answered', 'receipt': winner}})
            require(actual == expected, 'only_answer_revision_changed')
            rows = a.query("(SELECT jsonb_agg(jsonb_build_object('key',operation_key,'revision',answer_expected_revision,'value',answer_value,'receipt',answer_receipt,'original',original_workout_log_id::text,'live',live_workout_log_id::text)) FROM private.workout_strength_operations WHERE user_id=" + lit(owner) + "::uuid AND operation_kind='answer')", 'durable_answer_operations')
            require(rows == [{'key': key, 'revision': 0, 'value': value, 'receipt': winner, 'original': workout, 'live': workout}], 'one_original_canonical_winner_no_negative_binding')
            require(a.query('c59s9_fixture.immutable_state(' + lit(owner) + ')', 'after_immutable') == before_immutable, 'legacy_anchor_classification_calendar_capture_unchanged')
            if not commit:
                require(a.query("(SELECT created_at>=" + lit(lower) + "::timestamptz FROM private.workout_strength_operations WHERE user_id=" + lit(owner)
                    + "::uuid AND operation_kind='answer') AND " + lit(winner['acceptedAt']) + '::timestamptz>=' + lit(lower) + '::timestamptz', 'winner_clock_after_block') is True, 'clock_after_observed_block_lower_bound')
            result['cases'].append({'id': CASE_IDS[index], 'passed': True, 'B_blocked_by_A_observed': True,
                'winner_answer': value, 'winner_operation_key': key, 'durable_one_answer': True,
                'original_revision_replay': True, 'immutable_legacy_and_fact_copies': True})
    except BaseException as failure:
        result['failure'] = type(failure).__name__
        raise
    finally:
        cleanup = []
        for actor in reversed(actors):
            try:
                cleanup.append(actor.close())
            except BaseException as failure:
                cleanup.append({'actor': actor.name, 'reaped': False, 'readers_stopped': False, 'failure': type(failure).__name__})
        reaped = all(item['reaped'] for item in cleanup)
        readers = all(item['readers_stopped'] for item in cleanup)
        result['cleanup'] = {'complete': reaped and readers, 'actors_reaped': reaped, 'readers_stopped': readers, 'actors': cleanup}
        (output / 'RESULT.json').write_text(json.dumps(result, indent=2) + '\n', encoding='utf-8')
    require(result['cleanup']['complete'] is True, 'actor_cleanup')
    return result


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--bindings-json', required=True);parser.add_argument('--output-dir', required=True)
    options = parser.parse_args();config = json.loads(Path(options.bindings_json).read_text(encoding='utf-8'))
    config['output_dir'] = options.output_dir
    run(config)
