#!/usr/bin/env python3
"""S11 two real A/B calendar observations. Import inert; no PG lifecycle/DDL.
Root alone calls run(config). Pinned S7 actors own/reap subprocesses and readers.
"""
import argparse
import hashlib
import json
from pathlib import Path
import re
import time
import types

ACTOR_SHA = 'c14570d9059fbd56f4aa7efeeefeb9e0030b275c9b221a0890d1d484d1db1a5f'
CASE_IDS = ['scope-commit-reuse', 'scope-rollback-new']
IDS = {'owner_commit': 'c59ab000-0000-0000-0000-000000000011',
    'life_commit': 'c59ab000-0000-0000-0000-000000000111',
    'owner_rollback': 'c59ab000-0000-0000-0000-000000000012',
    'life_rollback': 'c59ab000-0000-0000-0000-000000000112'}
SCOPE_KEYS = {'ownerID', 'lifecycleKey', 'scopeKey', 'timeZone', 'weekStartDate', 'asOfLocalDate'}


def require(value, label):
    if value is not True:
        raise RuntimeError('C59S11_DRIVER:' + label)


def lit(value):
    return "'" + str(value).replace("'", "''") + "'"


def prepare(owner, life):
    return 'public.prepare_workout_strength_calendar_scope(' + lit(owner) + '::uuid,' + lit(life) + '::uuid)'


def verify(wire, status, owner, life):
    require(isinstance(wire, dict) and set(wire) == {'status', 'scope'} and wire['status'] == status, 'wire2_exact_status')
    scope = wire['scope']
    require(isinstance(scope, dict) and set(scope) == SCOPE_KEYS and all(isinstance(value, str) for value in scope.values()), 'scope6_strings')
    require(scope['ownerID'] == owner and scope['lifecycleKey'] == life and scope['timeZone'] == 'UTC', 'scope_owned_official_zone')
    require(re.fullmatch(r'[0-9a-f]{8}(?:-[0-9a-f]{4}){3}-[0-9a-f]{12}', scope['scopeKey']) is not None, 'scope_UUID')
    require(all(re.fullmatch(r'[0-9]{4}-[0-9]{2}-[0-9]{2}', scope[key]) is not None for key in ['weekStartDate', 'asOfLocalDate']), 'scope_ISO_dates')
    return scope


def wait_block(observer, blocker_pid, waiter_pid, deadline):
    end = min(deadline, time.monotonic() + 6)
    while time.monotonic() < end:
        observer.statement('SELECT pg_stat_clear_snapshot();')
        if observer.query(str(blocker_pid) + '=ANY(pg_blocking_pids(' + str(waiter_pid) + '))', 'actual_scope_block') is True:
            return
    raise TimeoutError('C59S11_DRIVER:missing_actual_scope_block')


def run(config):
    output = Path(config['output_dir'])
    output.mkdir(parents=True, exist_ok=False)
    result = {'executed': False, 'failure': None, 'cases': [],
        'cleanup': {'complete': False, 'actors_reaped': False, 'readers_stopped': False, 'actors': []}}
    actors = []
    deadline = time.monotonic() + 180
    def query(actor, expression, label):
        require(time.monotonic() < deadline, 'bounded_driver_deadline')
        return actor.query(expression, label)
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
        require(config.get('expected_case_ids') == CASE_IDS and all(config.get(key) == value for key, value in IDS.items()), 'cases_and_synthetic_IDs_pin')
        base = types.ModuleType('c59s11_pinned_actor_module')
        exec(compile(source, str(actor_path), 'exec'), base.__dict__)
        a = base._create_registered_actor('A', config, output, actors)
        b = base._create_registered_actor('B', config, output, actors)
        pids = []
        for actor in actors:
            identity = query(actor, "jsonb_build_object('owner',session_user,'db',current_database(),'port',current_setting('port')::int,'data',current_setting('data_directory'),'socket',current_setting('unix_socket_directories'),'listen',current_setting('listen_addresses'),'isolation',current_setting('transaction_isolation'),'pid',pg_backend_pid(),'marker',(SELECT tag FROM c59s11_fixture.ownership))", 'identity')
            require(identity['owner'] == config['user'] and identity['db'] == config['database'] and identity['port'] == config['port']
                and identity['data'] == config['expected_data_directory'] and identity['socket'] == config['socket']
                and identity['listen'] == '' and identity['isolation'] == 'read committed' and identity['marker'] == 'c59s11_scopes_v1', 'actual_identity')
            pids.append(identity['pid'])
            actor.statement("SET statement_timeout='12s';SET lock_timeout='9s';SET request.jwt.claims='{\"role\":\"service_role\"}';SET DateStyle='SQL, DMY';SET TimeZone='Pacific/Auckland';")
        require(pids[0] != pids[1], 'distinct_A_B')
        # Objective setup precondition, not product failure or a clock override.
        # Margin 300s exceeds whole driver deadline180s + one outstanding bounded query12s.
        margin = query(a, "(SELECT count(*)=2 AND bool_and(timezone COLLATE \"C\"='UTC' COLLATE \"C\") FROM public.users WHERE id IN(" + lit(IDS['owner_commit']) + ',' + lit(IDS['owner_rollback']) + ")) AND extract(epoch FROM(date_trunc('day',clock_timestamp() AT TIME ZONE 'UTC')+interval '1 day'-(clock_timestamp() AT TIME ZONE 'UTC')))>300", 'setup_UTC_tuple_margin_300s')
        require(margin is True, 'SETUP_clock_margin_or_zone_no_product_claim')
        result['executed'] = True
        for index, commit in enumerate([True, False]):
            suffix = 'commit' if commit else 'rollback'
            owner, life = IDS['owner_' + suffix], IDS['life_' + suffix]
            require(query(a, '(SELECT count(*)=0 FROM private.workout_strength_calendar_scopes WHERE user_id=' + lit(owner) + '::uuid)', 'initial_scope_empty') is True, 'no_seeded_scope')
            a.begin()
            wire_a = query(a, prepare(owner, life), 'prepare_A')
            scope_a = verify(wire_a, 'prepared', owner, life)
            row_a = query(a, '(SELECT to_jsonb(s) FROM private.workout_strength_calendar_scopes s WHERE user_id=' + lit(owner) + '::uuid)', 'real_A_row')
            b.begin()
            pending = b.send(prepare(owner, life), 'prepare_B')
            wait_block(a, pids[0], pids[1], deadline)
            lower = query(a, "to_char(clock_timestamp() AT TIME ZONE 'UTC','YYYY-MM-DD\"T\"HH24:MI:SS.US\"Z\"')", 'post_block_lower_bound')
            a.finish(commit)
            wire_b = b.receive(pending)
            scope_b = verify(wire_b, 'reuse_existing' if commit else 'prepared', owner, life)
            if commit:
                require(scope_b == scope_a, 'committed_winner_exact_reuse')
            else:
                require(scope_b['scopeKey'] != scope_a['scopeKey'], 'rolledback_scope_not_reused')
            b.finish(True)
            durable = query(a, '(SELECT jsonb_agg(to_jsonb(s) ORDER BY scope_key) FROM private.workout_strength_calendar_scopes s WHERE user_id=' + lit(owner) + '::uuid)', 'durable_one_scope')
            require(isinstance(durable, list) and len(durable) == 1 and durable[0]['scope_key'] == scope_b['scopeKey'], 'durable_single_winner')
            if commit:
                require(durable[0] == row_a, 'reuse_preserves_original_created_at_and_all_columns')
            else:
                require(query(a, '(SELECT created_at>=' + lit(lower) + '::timestamptz FROM private.workout_strength_calendar_scopes WHERE user_id=' + lit(owner) + '::uuid)', 'new_clock_after_observed_wait') is True, 'new_row_clock_post_lock_lower_bound')
            require(query(a, '(SELECT time_zone=\'UTC\' AND as_of_local_date=(created_at AT TIME ZONE time_zone)::date AND week_start_date=date_trunc(\'week\',created_at AT TIME ZONE time_zone)::date AND extract(isodow FROM week_start_date)=1 AND as_of_local_date-week_start_date BETWEEN 0 AND 6 AND '
                + lit(scope_b['asOfLocalDate']) + '::date=as_of_local_date AND ' + lit(scope_b['weekStartDate']) + '::date=week_start_date FROM private.workout_strength_calendar_scopes WHERE user_id=' + lit(owner) + '::uuid)', 'single_durable_clock_calendar') is True, 'official_dates_derived_from_durable_clock')
            replay = query(b, prepare(owner, life), 'same_tuple_durable_replay')
            require(verify(replay, 'reuse_existing', owner, life) == scope_b, 'replay_exact_winner')
            require(query(a, '(SELECT jsonb_agg(to_jsonb(s) ORDER BY scope_key) FROM private.workout_strength_calendar_scopes s WHERE user_id=' + lit(owner) + '::uuid)', 'after_replay_rows') == durable, 'replay_no_refresh_or_extra_row')
            result['cases'].append({'id': CASE_IDS[index], 'passed': True, 'B_blocked_by_A_observed': True,
                'durable_one_scope': True, 'real_tuple_margin_precondition': True,
                'original_created_at_preserved_on_reuse': commit, 'new_clock_after_observed_bound': not commit})
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
