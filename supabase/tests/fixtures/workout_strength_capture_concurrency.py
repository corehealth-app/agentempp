#!/usr/bin/env python3
"""S8 A/B oracles only. Reuses pinned S7 actors, never runs S7 or starts/stops PG."""
import argparse
import hashlib
import json
from pathlib import Path
import time
import types

ACTOR_SHA = 'c14570d9059fbd56f4aa7efeeefeb9e0030b275c9b221a0890d1d484d1db1a5f'
CASE_IDS = ['capture-commit-replay', 'capture-rollback-new', 'catalogue-commit-sourcechanged',
    'capture-share-blocks-catalogue', 'catalogue-rollback-capture']


def require(value, label):
    if value is not True:
        raise RuntimeError('C59S8_DRIVER:' + label)


def lit(value):
    return "'" + str(value).replace("'", "''") + "'"


def capture(owner, life, key, observation=None):
    obs = 'NULL' if observation is None else lit(json.dumps(observation, ensure_ascii=False)) + '::jsonb'
    decision = 'NULL' if observation is None else lit(json.dumps({'status': 'matched',
        'observationKey': observation['observationKey'], 'matcherVersion': observation['matcherVersion'],
        'originalOperationType': 'musculacao', 'method': 'active_slug',
        'selectedRowID': 'c59a9000-0000-0000-0000-000000009001'})) + '::jsonb'
    return 'public.register_workout_strength_atomic(' + ','.join([lit(owner), lit(life), lit(key),
        "'musculacao'", obs, decision]) + ')'


def verify_new(wire):
    require(isinstance(wire, dict) and set(wire) == {'legacy_result', 'strength'}, 'outer2keys')
    require(wire['strength']['status'] == 'committed' and wire['legacy_result']['inserted'] is True, 'new_committed')
    require(wire['strength']['binding']['resolution'] == 'sql_insert', 'new_resolution')
    require(wire['strength']['fact']['anchor']['workoutLogID'] == wire['legacy_result']['workout_log_id'], 'actual_UUID')


def verify_replay(wire, first):
    require(wire['strength']['status'] == 'reuse_existing' and wire['legacy_result'] == first['legacy_result']
        and wire['strength']['binding'] == first['strength']['binding']
        and wire['strength']['fact'] == first['strength']['fact'], 'exact_durable_replay')


def wait_block(observer, blocker_pid, waiter_pid, label):
    deadline = time.monotonic() + 6
    while time.monotonic() < deadline:
        observer.statement('SELECT pg_stat_clear_snapshot();')
        if observer.query(str(blocker_pid) + '=ANY(pg_blocking_pids(' + str(waiter_pid) + '))', label) is True:
            return True
    raise TimeoutError('C59S8_DRIVER:missing_actual_block:' + label)


def counts(actor, owner):
    return actor.query("jsonb_build_object('workouts',(SELECT count(*) FROM public.workout_logs WHERE user_id=" + lit(owner)
        + "::uuid),'facts',(SELECT count(*) FROM private.workout_strength_facts WHERE user_id=" + lit(owner)
        + "::uuid),'bindings',(SELECT count(*) FROM private.workout_strength_operations WHERE user_id=" + lit(owner)
        + "::uuid))", 'owned_counts')


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
        actor_source = actor_path.read_bytes()
        require(config.get('actor_sha256') == ACTOR_SHA and hashlib.sha256(actor_source).hexdigest() == ACTOR_SHA, 'actor_pin')
        require(config.get('user') == 'c59a2_local_admin' and config.get('database') == 'postgres'
            and config.get('port') == 55493 and str(config.get('socket', '')).startswith('/private/tmp/performe-c59a2-pg.'), 'local_binding')
        require(Path(config['psql']).is_absolute() and hashlib.sha256(Path(config['psql']).read_bytes()).hexdigest() == config['psql_sha256'], 'psql_pin')
        require(config.get('expected_case_ids') == CASE_IDS, 'cases_pin')
        base = types.ModuleType('c59s8_pinned_actor_module')
        exec(compile(actor_source, str(actor_path), 'exec'), base.__dict__)
        a = base._create_registered_actor('A', config, output, actors)
        b = base._create_registered_actor('B', config, output, actors)
        pids = []
        for actor in actors:
            identity = actor.query("jsonb_build_object('owner',session_user,'db',current_database(),'port',current_setting('port')::int,'data',current_setting('data_directory'),'socket',current_setting('unix_socket_directories'),'listen',current_setting('listen_addresses'),'pid',pg_backend_pid(),'marker',(SELECT tag FROM c59s8_fixture.ownership))", 'identity')
            require(identity['owner'] == config['user'] and identity['db'] == config['database'] and identity['port'] == config['port']
                and identity['data'] == config['expected_data_directory'] and identity['socket'] == config['socket'] and identity['listen'] == ''
                and identity['marker'] == 'c59s8_capture_v1', 'actual_identity')
            pids.append(identity['pid'])
            actor.statement("SET statement_timeout='12s';SET lock_timeout='9s';SET request.jwt.claims='{\"role\":\"service_role\"}';")
        require(pids[0] != pids[1], 'distinct_A_B')
        result['executed'] = True
        # Same-row capture races: SHARE compatible, common owner advisory blocks B.
        for number, commit in [(11, True), (12, False)]:
            owner = 'c59a9000-0000-0000-0000-' + str(number).zfill(12)
            life = 'c59a9000-0000-0000-0000-' + str(number + 100).zfill(12)
            key = 'case-' + str(number)
            observation = a.query('public.get_workout_strength_catalogue_context()', 'observation')
            a.begin(); first = a.query(capture(owner, life, key, observation), 'capture_A'); verify_new(first)
            b.begin(); pending = b.send(capture(owner, life, key, None if commit else observation), 'capture_B')
            wait_block(a, pids[0], pids[1], 'B_waits_capture_A')
            lower = a.query("to_char(clock_timestamp() AT TIME ZONE 'UTC','YYYY-MM-DD\"T\"HH24:MI:SS.US\"Z\"')", 'post_block_lower_bound')
            a.finish(commit)
            winner = b.receive(pending)
            if commit:
                verify_replay(winner, first)
            else:
                verify_new(winner)
                require(winner['legacy_result']['workout_log_id'] != first['legacy_result']['workout_log_id'], 'rollback_UUID_not_reused')
            b.finish(True)
            if not commit:
                require(b.query("(SELECT created_at>=" + lit(lower) + "::timestamptz FROM private.workout_strength_operations WHERE user_id="
                    + lit(owner) + "::uuid AND operation_kind='capture') AND "
                    + lit(winner['strength']['fact']['calendar']['zoneObservedAt']) + '::timestamptz>=' + lit(lower) + '::timestamptz',
                    'new_receipt_and_zone_clock_after_observed_block') is True, 'post_lock_clock_lower_bound')
            verify_replay(a.query(capture(owner, life, key), 'durable_replay'), winner)
            require(counts(a, owner) == {'workouts': 1, 'facts': 1, 'bindings': 1}, 'one_durable_set')
            result['cases'].append({'id': CASE_IDS[0 if commit else 1], 'passed': True,
                'B_blocked_by_A_observed': True, 'durable_one_set': True, 'replay_before_new_envelope': True})
        # A catalogue mutation commits before the waiting capture obtains SHARE.
        owner = 'c59a9000-0000-0000-0000-000000000013'; life = 'c59a9000-0000-0000-0000-000000000113'
        observation = a.query('public.get_workout_strength_catalogue_context()', 'before_catalogue_mutation')
        a.begin();a.statement("INSERT INTO public.workout_types(id,slug,display_name,category,kcal_per_min) VALUES('c59a9000-0000-0000-0000-000000009101','concurrent_competitor','Musculação','musculacao',4);")
        b.begin();pending = b.send(capture(owner, life, 'case-13', observation), 'capture_after_catalogue')
        wait_block(a, pids[0], pids[1], 'B_SHARE_waits_catalogue_A')
        a.finish(True);wire = b.receive(pending);b.finish(True)
        require(wire == {'legacy_result': None, 'strength': {'status': 'conflict', 'reason': 'source_observation_changed'}}, 'source_changed_after_wait')
        require(counts(a, owner) == {'workouts': 0, 'facts': 0, 'bindings': 0}, 'CAS_zero_writes')
        result['cases'].append({'id': CASE_IDS[2], 'passed': True, 'B_blocked_by_A_observed': True, 'zero_writes': True})
        # Capturing B holds SHARE through COMMIT; real catalogue DML A must wait.
        owner = 'c59a9000-0000-0000-0000-000000000014'; life = 'c59a9000-0000-0000-0000-000000000114'
        observation = a.query('public.get_workout_strength_catalogue_context()', 'before_SHARE')
        b.begin();first = b.query(capture(owner, life, 'case-14', observation), 'B_holds_SHARE');verify_new(first)
        a.begin()
        a.proc.stdin.write("UPDATE public.workout_types SET display_name='edited after SHARE' WHERE id='c59a9000-0000-0000-0000-000000009101';\n");a.proc.stdin.flush()
        pending = a.send("(SELECT count(*) FROM public.workout_types WHERE id='c59a9000-0000-0000-0000-000000009101' AND display_name='edited after SHARE')", 'A_catalogue_DML')
        wait_block(b, pids[1], pids[0], 'A_DML_waits_B_SHARE')
        b.finish(True);require(a.receive(pending) == 1, 'actual_DML_after_capture_commit');a.finish(True)
        verify_replay(b.query(capture(owner, life, 'case-14'), 'replay_after_catalogue_edit'), first)
        require(counts(b, owner) == {'workouts': 1, 'facts': 1, 'bindings': 1}, 'history_durable_one_set')
        result['cases'].append({'id': CASE_IDS[3], 'passed': True, 'A_blocked_by_B_observed': True, 'history_preserved': True})
        # Same catalogue-first race, but rollback restores the observation set.
        owner = 'c59a9000-0000-0000-0000-000000000015'; life = 'c59a9000-0000-0000-0000-000000000115'
        observation = a.query('public.get_workout_strength_catalogue_context()', 'before_catalogue_rollback')
        a.begin();a.statement("INSERT INTO public.workout_types(id,slug,display_name,category,kcal_per_min) VALUES('c59a9000-0000-0000-0000-000000009102','rolled_back_competitor','Musculação','musculacao',4);")
        b.begin();pending = b.send(capture(owner, life, 'case-15', observation), 'B_after_catalogue_rollback')
        wait_block(a, pids[0], pids[1], 'B_SHARE_waits_catalogue_rollback_A');a.finish(False)
        wire = b.receive(pending);verify_new(wire);b.finish(True)
        require(counts(a, owner) == {'workouts': 1, 'facts': 1, 'bindings': 1}, 'catalogue_rollback_capture_one_set')
        result['cases'].append({'id': CASE_IDS[4], 'passed': True, 'B_blocked_by_A_observed': True, 'capture_after_rollback': True})
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
