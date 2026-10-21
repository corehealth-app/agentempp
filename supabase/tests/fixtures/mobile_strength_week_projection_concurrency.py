"""Definitions only. Root supplies pinned actors, fixture and owned commit checks.

Never starts a server, installs DDL or seeds producers. Public clock evidence is
separate from the private future-week projection, which must stay empty here.
"""


def parse_native_utc_timestamp(value):
    import datetime
    import re

    match = re.fullmatch(
        r'(\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d)(?:\.(\d{1,6}))?(?:Z|\+00:00)', value
    ) if isinstance(value, str) else None
    if match is None:
        raise ValueError('P7_native_UTC_timestamp')
    # Python 3.9 fromisoformat rejects PostgreSQL JSON's trimmed fractions.
    normalized = match.group(1) + '.' + (match.group(2) or '').ljust(6, '0')
    return datetime.datetime.strptime(normalized, '%Y-%m-%dT%H:%M:%S.%f').replace(tzinfo=datetime.timezone.utc)


def finalize_race_result(result, reports):
    final = dict(result)
    final['cleanup'] = {'actors': reports,
                        'actors_reaped': bool(reports) and all(v['reaped'] for v in reports),
                        'readers_stopped': bool(reports) and all(v['readers_stopped'] for v in reports),
                        'exit_codes_zero': bool(reports) and all(v.get('exit_code') == 0 for v in reports)}
    if not all(final['cleanup'][k] for k in ('actors_reaped', 'readers_stopped', 'exit_codes_zero')):
        final['status'] = 'P7_RACES_FAILED_PRESERVED'
        if 'failure' not in final:
            final['failure'] = {'type': 'ActorCleanupFailed', 'label': 'P7_actor_cleanup_incomplete'}
    return final


def advisory_lock_matches(row, pid, granted, expected):
    import re

    def oid(value):
        # PostgreSQL JSON renders oid as text, while the computed bitmap is
        # bigint. Both carry an exact uint32; reject coercible or lossy forms.
        if type(value) is int:
            number = value
        elif isinstance(value, str) and re.fullmatch(r'0|[1-9][0-9]{0,9}', value):
            number = int(value)
        else:
            return None
        return str(number) if 0 <= number <= 4294967295 else None

    if (not isinstance(row, dict) or not isinstance(expected, dict)
            or set(expected) != {'database', 'classid', 'objid', 'objsubid'}
            or type(pid) is not int or type(row.get('pid')) is not int
            or type(granted) is not bool or row.get('pid') != pid
            or row.get('type') != 'advisory' or row.get('mode') != 'ExclusiveLock'
            or row.get('granted') is not granted
            or type(row.get('objsubid')) is not int or row['objsubid'] != 1
            or type(expected.get('objsubid')) is not int or expected['objsubid'] != 1):
        return False
    for field in ('database', 'classid', 'objid'):
        actual, wanted = oid(row.get(field)), oid(expected.get(field))
        if actual is None or wanted is None or actual != wanted:
            return False
    return True


def run_projection_races(config, actor_api, prepare_commit, after_commit):
    import json
    import re
    import time
    from pathlib import Path

    need = actor_api['require']
    lit = actor_api['literal']
    create = actor_api['_create_registered_actor']
    owner = 'c59d4200-0000-4000-8000-000000000901'
    need(config.get('root_reviewed') is True, 'P7_reviewed_caller')
    need(config['user'] == 'c5_local_admin'
         and config['database'] == 'c5_reset_default_20261009'
         and config['socket'] == '/private/tmp/performe-c5-osecmg7_'
         and config['port'] == 55489, 'P7_exact_local_target')
    output = Path(config['output_dir'])
    output.mkdir(mode=0o700, exist_ok=False)
    actors, closed, cleanup = [], set(), []
    result = {'status': 'RUNNING', 'cases': [], 'remote_operation': False}
    deadline = time.monotonic() + 180

    def query(actor, expression, label):
        need(time.monotonic() < deadline, 'P7_bounded_deadline')
        return actor.query(expression, label, timeout=min(18, max(.1, deadline - time.monotonic())))

    def state(actor, label):
        return query(actor, 'c59_p7_fixture.state()', label)

    def instant(value):
        return parse_native_utc_timestamp(value)

    def close(actor):
        if id(actor) in closed:
            return
        report = actor.close()
        need(report['reaped'] and report['readers_stopped'] and report['exit_code'] == 0,
             'P7_actor_close_zero_' + actor.name)
        cleanup.append(report)
        closed.add(id(actor))

    def make(name):
        actor = create(name, config, output, actors)
        identity = query(actor, "jsonb_build_object('session',session_user,'db',current_database(),"
                         "'data',current_setting('data_directory'),'socket',current_setting('unix_socket_directories'),"
                         "'port',current_setting('port')::integer,'listen',current_setting('listen_addresses'),"
                         "'pid',pg_backend_pid(),'setup_pid',(SELECT value FROM c59_p7_fixture.registry WHERE key='setup_pid'))",
                         'identity')
        need(identity['session'] == config['user'] and identity['db'] == config['database']
             and identity['data'] == config['expected_data_directory']
             and identity['socket'] == config['socket'] and identity['port'] == config['port']
             and identity['listen'] == '' and identity['pid'] != identity['setup_pid'],
             'P7_actor_identity_and_fresh_connection')
        actor.statement("SET statement_timeout='20s';SET lock_timeout='16s';"
                        "SET idle_in_transaction_session_timeout='30s';SET TimeZone='UTC';SET DateStyle='ISO,YMD';")
        return actor, identity['pid']

    def begin(actor, role='postgres'):
        actor.begin()
        actor.statement("SET LOCAL ROLE " + role + ";SET LOCAL search_path=pg_catalog;"
                        "SET LOCAL request.jwt.claims='{\"role\":\"service_role\"}';")

    def wait_for_block(observer, aid, bid, name, kind):
        observer.statement('RESET ROLE;')
        end = min(deadline, time.monotonic() + 6)
        key = "hashtextextended(" + lit(owner + ':workouts') + ",0)"
        while time.monotonic() < end:
            observer.statement('SELECT pg_stat_clear_snapshot();')
            diagnostic = query(observer,
                "jsonb_build_object('blockers',pg_blocking_pids(" + str(bid) + "),"
                "'activity',(SELECT jsonb_build_object('pid',pid,'state',state,'wait_type',wait_event_type,"
                "'application',application_name) FROM pg_stat_activity WHERE pid=" + str(bid) + "),"
                "'blocker_xid',(SELECT backend_xid::text FROM pg_stat_activity WHERE pid=" + str(aid) + "),"
                "'locks',(SELECT coalesce(jsonb_agg(jsonb_build_object('pid',pid,'type',locktype,'mode',mode,"
                "'granted',granted,'xid',transactionid::text,'database',database,'classid',classid,"
                "'objid',objid,'objsubid',objsubid)),'[]'::jsonb) FROM pg_locks WHERE pid IN("
                + str(aid) + ',' + str(bid) + ")),"
                "'expected_key',jsonb_build_object('database',(SELECT oid FROM pg_database WHERE datname=current_database()),"
                "'classid',((" + key + ">>32)&4294967295),'objid',(" + key + "&4294967295),'objsubid',1))",
                'observed_block_' + kind)
            if aid in diagnostic['blockers']:
                need(diagnostic['activity']['pid'] == bid and diagnostic['activity']['state'] == 'active'
                     and diagnostic['activity']['wait_type'] == 'Lock'
                     and diagnostic['activity']['application'] == 'c59s7-' + name,
                     'P7_actual_waiter_identity')
                locks, expected = diagnostic['locks'], diagnostic['expected_key']

                def key_lock(row, pid, granted):
                    return advisory_lock_matches(row, pid, granted, expected)

                if kind == 'advisory':
                    need(any(key_lock(row, aid, True) for row in locks)
                         and any(key_lock(row, bid, False) for row in locks),
                         'P7_exact_shared_workouts_advisory_wait')
                else:
                    need(diagnostic['blocker_xid'] is not None
                         and any(row['pid'] == bid and row['type'] == 'transactionid'
                                 and not row['granted'] and row['xid'] == diagnostic['blocker_xid']
                                 for row in locks)
                         and any(key_lock(row, bid, True) for row in locks)
                         and not any(key_lock(row, aid, True) for row in locks),
                         'P7_owner_row_wait_after_B_acquired_advisory')
                return diagnostic
            time.sleep(.02)
        raise TimeoutError('P7_missing_real_' + kind + '_wait')

    try:
        a, aid = make('P7-A')
        b, bid = make('P7-CLOCK-B')
        need(aid != bid, 'P7_distinct_A_B')
        seed = query(a, "(SELECT value FROM c59_p7_fixture.registry WHERE key='initial_state')", 'seed')
        need(state(a, 'initial_durable_state') == seed, 'P7_real_setup_commit_visible')
        target = query(a, "(SELECT value FROM c59_p7_fixture.registry WHERE key='target')", 'target')
        binding = query(a, "(SELECT value FROM c59_p7_fixture.registry WHERE key='binding')", 'binding')
        future = query(a, "(SELECT value FROM c59_p7_fixture.registry WHERE key='future_UTC6')", 'future')
        generation, target_id = target['generation'], target['target_id']
        args = ','.join([lit(owner) + '::uuid', lit(generation) + '::uuid', lit(target_id) + '::uuid'])
        public = 'public.get_mobile_strength_week_projection(' + args + ')'
        private = 'private.get_mobile_strength_week_projection_at(' + args + ',' + lit(future) + '::timestamptz)'

        # The public real-clock call must wait specifically on users, after it
        # acquired workouts. It cannot succeed for next week's private target.
        begin(a)
        query(a, '(SELECT id FROM public.users WHERE id=' + lit(owner) + '::uuid FOR UPDATE)', 'hold_owner_only')
        begin(b, 'service_role')
        pending = b.send(public, 'public_after_owner_wait')
        block = wait_for_block(a, aid, bid, b.name, 'transactionid')
        lower = query(a, "to_char(clock_timestamp() AT TIME ZONE 'UTC','YYYY-MM-DD\"T\"HH24:MI:SS.US\"Z\"')", 'clock_lower')
        a.finish(True)
        wire = b.receive(pending, timeout=18)
        upper = query(b, "to_char(clock_timestamp() AT TIME ZONE 'UTC','YYYY-MM-DD\"T\"HH24:MI:SS.US\"Z\"')", 'clock_upper')
        need(wire == {'status': 'conflict', 'reason': 'week_changed'}, 'P7_public_future_target_exact_conflict')
        b.finish(False)
        close(b)
        lines = (output / (b.name + '.stderr.log')).read_text().splitlines()
        match = re.fullmatch(r'NOTICE:\s+P7_CLOCK:(\{.*\})', lines[0]) if len(lines) == 1 else None
        need(match is not None, 'P7_one_public_clock_observation_only')
        clock = json.loads(match.group(1))
        need(set(clock) == {'owner', 'generation', 'target', 'pid', 'input_at', 'at', 'statement_at', 'transaction_at'}
             and clock['owner'] == owner and clock['generation'] == generation
             and clock['target'] == target_id and clock['pid'] == bid and clock['input_at'] is None,
             'P7_clock_observation_exact_identity')
        need(instant(clock['transaction_at']) <= instant(clock['statement_at']) < instant(lower)
             <= instant(clock['at']) <= instant(upper), 'P7_real_clock_sampled_after_observed_wait')
        need(state(a, 'after_public_wait') == seed, 'P7_public_negative_changes_no_owned_rows')
        result['cases'].append({'id': 'public_clock_after_owner_wait', 'block': block,
                                'clock': clock, 'lower': lower, 'upper': upper, 'passed': True})

        # A real reset is held open. This waiter blocks on the shared advisory,
        # not on a users XID. Rollback restores the original generation.
        begin(a)
        reset = query(a, 'public.reset_user_conversation_atomic(' + lit(owner) + '::uuid,true)', 'reset_rollback_A')
        need(reset.get('reset') is True and reset.get('user_id') == owner and reset.get('kept_plans') is True,
             'P7_real_reset_rollback_result')
        prepare_commit(a, 'reset_rehearsal')
        b, bid = make('P7-PROJECT-B')
        begin(b)
        pending = b.send(private, 'project_after_reset_rollback')
        block = wait_for_block(a, aid, bid, b.name, 'advisory')
        a.finish(False)
        wire = b.receive(pending, timeout=18)
        need(isinstance(wire, dict) and set(wire) == {'status', 'target', 'binding', 'calendar', 'projection', 'observed_at'}
             and wire['status'] == 'available' and wire['target'] == target and wire['binding'] == binding
             and wire['observed_at'] == future and wire['projection'] == {'status': 'available', 'workouts': []},
             'P7_available_future_private_tuple_exact')
        current = state(b, 'projected_owned_state')
        relation = 'private.workout_strength_calendar_scopes'
        need(set(current) == set(seed) and seed[relation] == [] and len(current[relation]) == 1
             and all(current[k] == seed[k] for k in seed if k != relation),
             'P7_only_one_new_calendar_receipt')
        row = current[relation][0]
        need(wire['calendar'] == {'ownerID': owner, 'lifecycleKey': binding['lifecycleKey'],
                                  'scopeKey': row['scope_key'], 'timeZone': target['timezone_at_freeze'],
                                  'weekStartDate': target['week_start'], 'asOfLocalDate': target['week_start']}
             and instant(row['created_at']) == instant(future), 'P7_calendar_from_exact_private_instant')
        witness = prepare_commit(b, 'projected')
        b.finish(True)
        close(b)
        after_commit('projected', witness)
        result['cases'].append({'id': 'reset_rollback_available_calendar_commit', 'block': block,
                                'projection': wire, 'committed_pid': bid, 'passed': True})

        c, cid = make('P7-REPLAY-C')
        need(cid != aid and cid != bid, 'P7_replay_new_backend_after_B_reaped')
        before = state(c, 'replay_before')
        need(before == current, 'P7_calendar_commit_visible_to_new_connection')
        begin(c)
        replay = query(c, private, 'durable_projection_replay')
        need(replay == wire and state(c, 'replay_after') == before, 'P7_exact_replay_no_refresh_or_rows')
        c.finish(False)
        result['cases'].append({'id': 'new_backend_exact_durable_replay', 'old_pid': bid,
                                'new_pid': cid, 'passed': True})

        # The second reset commits. Its historical target and binding remain,
        # but the old generation can no longer supply a projection.
        begin(a)
        reset = query(a, 'public.reset_user_conversation_atomic(' + lit(owner) + '::uuid,true)', 'reset_commit_A')
        need(reset.get('reset') is True and reset.get('user_id') == owner and reset.get('kept_plans') is True,
             'P7_real_reset_commit_result')
        witness = prepare_commit(a, 'reset')
        reset_state = state(a, 'reset_approved_state')
        begin(c)
        pending = c.send(private, 'project_after_reset_commit')
        block = wait_for_block(a, aid, cid, c.name, 'advisory')
        a.finish(True)
        stale = c.receive(pending, timeout=18)
        need(stale == {'status': 'conflict', 'reason': 'generation_changed'}
             and state(c, 'stale_later_statement') == reset_state, 'P7_committed_reset_old_generation_no_side_effect')
        c.finish(False)
        after_commit('reset', witness)
        result['cases'].append({'id': 'reset_commit_rejects_old_generation', 'block': block, 'passed': True})
        result['status'] = 'P7_DURABILITY_RESET_RACES_AND_CLOCK_VERIFIED'
    except BaseException as exc:
        result['status'] = 'P7_RACES_FAILED_PRESERVED'
        result['failure'] = {'type': type(exc).__name__,
                             'label': str(exc) if isinstance(exc, (RuntimeError, TimeoutError)) else None}
        raise
    finally:
        for actor in reversed(actors):
            if id(actor) in closed:
                continue
            try:
                report = actor.close()
            except BaseException as exc:
                report = {'actor': actor.name, 'reaped': False, 'readers_stopped': False,
                          'exit_code': None, 'error': type(exc).__name__}
            cleanup.append(report)
        result = finalize_race_result(result, cleanup)
        (output / 'RESULT.json').write_text(json.dumps(result, ensure_ascii=False, indent=2) + '\n')
    need(all(result['cleanup'][k] for k in ('actors_reaped', 'readers_stopped', 'exit_codes_zero')),
         'P7_all_actors_reaped_before_owned_cleanup')
    return result
