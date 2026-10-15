#!/usr/bin/env python3
"""S12 four real A/B read-snapshot scenarios. Import inert; no PG lifecycle/DDL.
Answers use the real closed S9 RPC; legacy cases use explicit fixture INSERT,
not S8 or register_workout_atomic. Root alone may call run(config).
"""
import argparse
import hashlib
import json
from pathlib import Path
import re
import time
import types

ACTOR_SHA = 'c14570d9059fbd56f4aa7efeeefeb9e0030b275c9b221a0890d1d484d1db1a5f'
CASE_IDS = ['project-answer-commit', 'project-answer-rollback', 'project-cooperative-legacy-commit', 'project-uncooperative-legacy']
SUFFIXES = ['answer_commit', 'answer_rollback', 'cooperative_legacy', 'uncooperative_legacy']
IDS = {key + '_' + suffix: 'c59ac000-0000-0000-0000-' + str(11 + index + (100 if key == 'life' else 0)).zfill(12)
    for index, suffix in enumerate(SUFFIXES) for key in ['owner', 'life']}
SCOPE_KEYS = {'ownerID', 'lifecycleKey', 'scopeKey', 'timeZone', 'weekStartDate', 'asOfLocalDate'}
NEGATIVE = {'status': 'unavailable', 'reason': 'calendar_unproved', 'workouts': None}
EMPTY = {'status': 'available', 'workouts': []}


def require(value, label):
    if value is not True:
        raise RuntimeError('C59S12_DRIVER:' + label)


def lit(value):
    return "'" + str(value).replace("'", "''") + "'"


def project(scope):
    return 'public.get_confirmed_workouts_for_strength_week(' + ','.join([
        lit(scope['ownerID']) + '::uuid', lit(scope['lifecycleKey']) + '::uuid', lit(scope['scopeKey']) + '::uuid',
        lit(scope['timeZone']), lit(scope['weekStartDate']) + '::date', lit(scope['asOfLocalDate']) + '::date']) + ')'


def scope_expression(owner, life):
    return "(SELECT jsonb_build_object('ownerID',user_id::text,'lifecycleKey',lifecycle_key::text,'scopeKey',scope_key::text,'timeZone',time_zone,'weekStartDate',to_char(week_start_date,'YYYY-MM-DD'),'asOfLocalDate',to_char(as_of_local_date,'YYYY-MM-DD')) FROM private.workout_strength_calendar_scopes WHERE user_id=" + lit(owner) + '::uuid AND lifecycle_key=' + lit(life) + '::uuid)'


def event(owner, workout, date, answer):
    return {'ownerKey': owner, 'workoutKey': workout, 'localDate': date, 'state': 'confirmed', 'catalogueCategory': None,
        'storedStrengthAnswer': None if answer is None else {'ownerKey': owner, 'workoutKey': workout, 'answer': answer}}


def wait_block(observer, blocker_pid, waiter_pid, deadline):
    end = min(deadline, time.monotonic() + 6)
    while time.monotonic() < end:
        observer.statement('SELECT pg_stat_clear_snapshot();')
        if observer.query(str(blocker_pid) + '=ANY(pg_blocking_pids(' + str(waiter_pid) + '))', 'actual_projector_block') is True:
            return
    raise TimeoutError('C59S12_DRIVER:missing_actual_projector_block')


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
        require(config.get('expected_case_ids') == CASE_IDS and all(config.get(key) == value for key, value in IDS.items()), 'cases_synthetic_owners_pin')
        base = types.ModuleType('c59s12_pinned_actor_module')
        exec(compile(source, str(actor_path), 'exec'), base.__dict__)
        a = base._create_registered_actor('A', config, output, actors)
        b = base._create_registered_actor('B', config, output, actors)
        pids = []
        for actor in actors:
            identity = query(actor, "jsonb_build_object('owner',session_user,'db',current_database(),'port',current_setting('port')::int,'data',current_setting('data_directory'),'socket',current_setting('unix_socket_directories'),'listen',current_setting('listen_addresses'),'isolation',current_setting('transaction_isolation'),'pid',pg_backend_pid(),'marker',(SELECT tag FROM c59s12_fixture.ownership))", 'identity')
            require(identity['owner'] == config['user'] and identity['db'] == config['database'] and identity['port'] == config['port']
                and identity['data'] == config['expected_data_directory'] and identity['socket'] == config['socket']
                and identity['listen'] == '' and identity['isolation'] == 'read committed' and identity['marker'] == 'c59s12_week_projection_v1', 'actual_identity')
            pids.append(identity['pid'])
            actor.statement("SET statement_timeout='12s';SET lock_timeout='9s';SET request.jwt.claims='{\"role\":\"service_role\"}';SET DateStyle='SQL, DMY';SET TimeZone='Pacific/Auckland';")
        require(pids[0] != pids[1], 'distinct_A_B')
        result['executed'] = True
        for index, suffix in enumerate(SUFFIXES):
            owner, life = IDS['owner_' + suffix], IDS['life_' + suffix]
            scope = query(a, scope_expression(owner, life), 'real_persisted_scope')
            require(isinstance(scope, dict) and set(scope) == SCOPE_KEYS and all(isinstance(v, str) for v in scope.values())
                and scope['ownerID'] == owner and scope['lifecycleKey'] == life and scope['timeZone'] == 'UTC', 'actual_owned_scope6')
            if index < 2:
                anchor = query(a, "(SELECT jsonb_build_object('workout',f.workout_log_id::text,'question',f.question_key::text,'revision',f.revision,'classification',f.classification_status,'calendar',f.calendar_status,'zone',f.time_zone,'date',to_char(f.local_date,'YYYY-MM-DD'),'ownedAnchor',f.snapshot_id=w.snapshot_id AND f.performed_at=w.performed_at AND f.stored_workout_type=(w.workout_type COLLATE \"C\") AND s.user_id=w.user_id AND s.date=f.snapshot_date) FROM private.workout_strength_facts f JOIN public.workout_logs w ON w.user_id=f.user_id AND w.id=f.workout_log_id JOIN public.daily_snapshots s ON s.id=w.snapshot_id WHERE f.user_id=" + lit(owner) + '::uuid AND f.lifecycle_key=' + lit(life) + '::uuid)', 'real_unanswered_fact_anchor')
                require(isinstance(anchor, dict) and anchor['revision'] == 0 and anchor['classification'] == 'unrecognized'
                    and anchor['calendar'] == 'proven' and anchor['zone'] == scope['timeZone'] and anchor['date'] == scope['asOfLocalDate']
                    and anchor['ownedAnchor'] is True, 'real_fact_before_answer')
                workout, question = anchor['workout'], anchor['question']
                a.begin()
                key = 'project-answer-' + str(11 + index)
                answered = query(a, 'public.answer_confirmed_workout_strength(' + ','.join([lit(owner), lit(life), lit(workout), '0', lit(question), "'yes'", lit(key)]) + ')', 'REAL_S9_answer_A')
                require(isinstance(answered, dict) and set(answered) == {'status', 'receipt'} and answered['status'] == 'accepted', 'real_S9_accepted')
                receipt = answered['receipt']
                require(isinstance(receipt, dict) and set(receipt) == {'ownerID', 'workoutLogID', 'questionKey', 'answer', 'operationKey', 'acceptedAt'}
                    and receipt['ownerID'] == owner and receipt['workoutLogID'] == workout and receipt['questionKey'] == question
                    and receipt['answer'] == 'yes' and receipt['operationKey'] == key
                    and re.fullmatch(r'[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}\.[0-9]{6}Z', receipt['acceptedAt']) is not None, 'actual_S9_owned_receipt')
                b.begin()
                pending = b.send(project(scope), 'project_B_after_real_answer_started')
                wait_block(a, pids[0], pids[1], deadline)
                commit = index == 0
                a.finish(commit)
                projected = b.receive(pending)
                require(projected == {'status': 'available', 'workouts': [event(owner, workout, scope['asOfLocalDate'], 'yes' if commit else None)]}, 'post_wait_current_answer_snapshot_exact_DTO6')
                b.finish(True)
                require(query(a, '(SELECT revision=' + ('1' if commit else '0') + ' AND ' + ("answer='yes'" if commit else 'answer IS NULL') + ' FROM private.workout_strength_facts WHERE user_id=' + lit(owner) + '::uuid) AND (SELECT count(*)=' + ('1' if commit else '0') + ' FROM private.workout_strength_operations WHERE user_id=' + lit(owner) + "::uuid AND operation_kind='answer')", 'actual_durable_answer_or_rollback') is True, 'answer_commit_rollback_reality')
                result['cases'].append({'id': CASE_IDS[index], 'passed': True, 'real_S9_accepted_before_block': True,
                    'B_blocked_by_A_observed': True, 'committed_answer_visible': commit, 'rollback_left_unanswered': not commit})
            else:
                require(query(a, '(SELECT count(*)=0 FROM public.workout_logs WHERE user_id=' + lit(owner) + '::uuid)', 'initial_complete_empty_U') is True, 'legacy_case_initial_U_empty')
                a.begin()
                if index == 2:
                    a.statement('SELECT pg_advisory_xact_lock(hashtextextended(' + lit(owner + ':workouts') + ',0));')
                a.statement('INSERT INTO public.workout_logs(user_id,workout_type,performed_at,created_at) VALUES(' + lit(owner)
                    + ",'C59S12 real legacy new UUID',(" + lit(scope['asOfLocalDate']) + "::date+TIME '12:00') AT TIME ZONE 'UTC',clock_timestamp());")
                fresh = query(a, "(SELECT jsonb_build_object('uuid',id::text,'snapshotNull',snapshot_id IS NULL,'factMissing',NOT EXISTS(SELECT 1 FROM private.workout_strength_facts f WHERE f.user_id=w.user_id AND f.workout_log_id=w.id)) FROM public.workout_logs w WHERE user_id=" + lit(owner) + '::uuid)', 'actual_new_DB_UUID_legacy_row')
                require(isinstance(fresh, dict) and re.fullmatch(r'[0-9a-f]{8}(?:-[0-9a-f]{4}){3}-[0-9a-f]{12}', fresh['uuid']) is not None
                    and fresh['snapshotNull'] is True and fresh['factMissing'] is True, 'genuine_new_legacy_workout')
                if index == 2:
                    b.begin()
                    pending = b.send(project(scope), 'project_B_waits_cooperative_new_UUID')
                    wait_block(a, pids[0], pids[1], deadline)
                    a.finish(True)
                    require(b.receive(pending) == NEGATIVE, 'post_wait_U_includes_new_committed_UUID_calendar_gap')
                    b.finish(True)
                else:
                    require(query(b, project(scope), 'first_snapshot_before_uncooperative_COMMIT') == EMPTY, 'uncommitted_row_invisible_first_empty_snapshot')
                    a.finish(True)
                    require(query(b, project(scope), 'next_snapshot_after_uncooperative_COMMIT') == NEGATIVE, 'next_snapshot_new_legacy_denies_same_scope')
                require(query(a, '(SELECT count(*)=1 AND bool_and(id=' + lit(fresh['uuid']) + '::uuid) FROM public.workout_logs WHERE user_id=' + lit(owner) + '::uuid) AND NOT EXISTS(SELECT 1 FROM private.workout_strength_facts WHERE user_id=' + lit(owner) + '::uuid)', 'durable_exact_new_legacy_UUID') is True, 'committed_new_UUID_no_fact')
                result['cases'].append({'id': CASE_IDS[index], 'passed': True, 'actual_DB_new_UUID_committed': True,
                    'B_blocked_by_A_observed': index == 2, 'uncommitted_first_empty_then_committed_gap': index == 3})
            state = query(a, 'c59s12_fixture.state(' + lit(owner) + ')', 'before_readonly_repeat')
            require(query(a, project(scope), 'same_scope_repeat_after_case') == (projected if index < 2 else NEGATIVE), 'same_snapshot_state_repeat_exact')
            require(query(a, 'c59s12_fixture.state(' + lit(owner) + ')', 'after_readonly_repeat') == state
                and query(a, scope_expression(owner, life), 'scope_never_modified') == scope, 'projection_readonly_scope_and_full_owner_state')
        require([case['id'] for case in result['cases']] == CASE_IDS, 'all_four_cases_completed_once')
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
