#!/usr/bin/env python3
"""S15 bounded real A/B authority/reset tests. Import inert; no DDL/PG lifecycle.
Root supplies reviewed bindings after owned setup COMMIT. Only the closed S7
Actor module is loaded at run time, not its run/main. Cleanup precedes RESULT.
"""
import argparse
import hashlib
import json
from pathlib import Path
import re
import time
import types

ACTOR_SHA = 'c14570d9059fbd56f4aa7efeeefeb9e0030b275c9b221a0890d1d484d1db1a5f'
CASE_IDS = ['admission-reset-commit', 'admission-reset-rollback',
    'reset-admission-commit', 'reset-admission-rollback', 'init-reset-commit',
    'init-reset-rollback', 'reset-init-commit', 'reset-init-rollback',
    'two-admissions-one-life']
X = 'private.workout_strength_'
STALE = {'status': 'forbidden', 'reason': 'stale_epoch'}
UUID = r'[0-9a-f]{8}(?:-[0-9a-f]{4}){3}-[0-9a-f]{12}'
US6 = r'\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{6}Z'


def require(value, label):
    if value is not True:
        raise RuntimeError('C59S15_DRIVER:' + label)


def lit(value):
    return "'" + str(value).replace("'", "''") + "'"


def admit(p):
    return 'public.admit_workout_strength_request(' + lit(p['ownerID']) + '::uuid,' + lit(p['requestKey']) + ',' + lit(p['requestHash']) + ')'


def initialize(p):
    return 'public.initialize_workout_strength_lifecycle(' + lit(p['ownerID']) + '::uuid,' + lit(p['admission']['admissionID']) + '::uuid,' + lit(p['inboundID']) + '::uuid)'


def reset(p):
    return 'public.reset_user_conversation_atomic(' + lit(p['ownerID']) + '::uuid,true)'


def check_admission(r, p, status):
    require(isinstance(r, dict) and set(r) == {'status', 'admission'} and r['status'] == status, 'admission_envelope_' + status)
    a = r['admission']
    require(isinstance(a, dict) and set(a) == {'ownerID', 'admissionID', 'epoch', 'requestNamespace', 'requestKey', 'requestHash', 'admittedAt'}, 'admission_exact7')
    require(a['ownerID'] == p['ownerID'] and a['requestNamespace'] == 'mobile_flow_turn'
        and a['requestKey'] == p['requestKey'] and a['requestHash'] == p['requestHash']
        and re.fullmatch(UUID, a['admissionID']) is not None and re.fullmatch(UUID, a['epoch']) is not None
        and re.fullmatch(US6, a['admittedAt']) is not None, 'real_owned_admission_literals_US6')
    return a


def check_lifecycle(r, p, status):
    require(isinstance(r, dict) and set(r) == {'status', 'lifecycle'} and r['status'] == status, 'init_envelope_' + status)
    life = r['lifecycle']
    require(isinstance(life, dict) and set(life) == {'ownerID', 'lifecycleKey', 'openedAt'}
        and life['ownerID'] == p['ownerID'] and re.fullmatch(UUID, life['lifecycleKey']) is not None
        and re.fullmatch(US6, life['openedAt']) is not None, 'real_owned_lifecycle_exact3_US6')
    return life


def wait_block(observer, blocker, waiter, deadline):
    limit = min(deadline, time.monotonic() + 6)
    while time.monotonic() < limit:
        observer.statement('SELECT pg_stat_clear_snapshot();')
        if observer.query(str(blocker) + '=ANY(pg_blocking_pids(' + str(waiter) + '))', 'actual_blocker') is True:
            return
    raise TimeoutError('C59S15_DRIVER:no_actual_blocker')


def run(config):
    output = Path(config['output_dir'])
    output.mkdir(parents=True, exist_ok=False)
    result = {'executed': False, 'failure': None, 'cases': [],
        'cleanup': {'complete': False, 'actors_reaped': False, 'readers_stopped': False, 'actors': []}}
    actors = []
    deadline = time.monotonic() + 240

    def query(actor, expression, label):
        require(time.monotonic() < deadline, 'bounded_deadline')
        return actor.query(expression, label)

    def state(actor, owner, label):
        return query(actor, 'c59s15_fixture.state(' + lit(owner) + '::uuid)', label)

    def one_epoch(s):
        rows = s[X + 'authority_epochs']
        require(len(rows) == 1, 'one_epoch_row')
        return rows[0]

    def no_open(s):
        require(not any(l['closed_at'] is None for l in s[X + 'lifecycles']), 'no_open_lifecycle')
        require(s['public.workout_logs'] == [] and s['public.daily_snapshots'] == [], 'no_X_workout_or_snapshot_write')

    try:
        require(config.get('root_reviewed') is True, 'root_review_required')
        path = Path(config['driver_path']).resolve(strict=True)
        require(hashlib.sha256(path.read_bytes()).hexdigest() == config['driver_sha256'], 'driver_pin')
        actor_path = Path(config['actor_module']).resolve(strict=True)
        source = actor_path.read_bytes()
        require(actor_path == path.parent / 'workout_strength_commands_concurrency.py'
            and config.get('actor_sha256') == ACTOR_SHA and hashlib.sha256(source).hexdigest() == ACTOR_SHA, 'closed_actor_pin_relative_path')
        require(config.get('user') == 'c5_local_admin' and config.get('database') == 'c5_reset_default_20261009'
            and config.get('port') == 55489 and config.get('socket') == '/private/tmp/performe-c5-osecmg7_'
            and config.get('expected_data_directory') == '/Users/eduardohenrique/.local/share/performe-ai/final-polish-20261001/e3/c5-portable-postgres17-20261009/data', 'exact_owned_C5')
        require(Path(config['psql']).is_absolute() and hashlib.sha256(Path(config['psql']).read_bytes()).hexdigest() == config['psql_sha256'], 'psql_pin')
        require(config.get('expected_case_ids') == CASE_IDS, 'ordered_nine_case_pin')
        base = types.ModuleType('c59s15_closed_actor')
        exec(compile(source, str(actor_path), 'exec'), base.__dict__)
        a = base._create_registered_actor('A', config, output, actors)
        b = base._create_registered_actor('B', config, output, actors)
        pids = []
        for actor in actors:
            identity = query(actor, "jsonb_build_object('owner',session_user,'db',current_database(),'port',current_setting('port')::int,'data',current_setting('data_directory'),'socket',current_setting('unix_socket_directories'),'listen',current_setting('listen_addresses'),'pid',pg_backend_pid(),'tag',(SELECT tag FROM c59s15_fixture.ownership))", 'identity')
            require(identity['owner'] == config['user'] and identity['db'] == config['database']
                and identity['port'] == config['port'] and identity['data'] == config['expected_data_directory']
                and identity['socket'] == config['socket'] and identity['listen'] == ''
                and identity['tag'] == 'c59s15_authority_v1', 'actual_local_identity')
            pids.append(identity['pid'])
            actor.statement("SET statement_timeout='12s';SET lock_timeout='9s';SET request.jwt.claims='{\"role\":\"service_role\"}';SET TimeZone='UTC';SET DateStyle='ISO,YMD';")
        require(pids[0] != pids[1], 'distinct_A_B')
        sentinel = 'c59b5000-0000-0000-0000-000000000999'
        sentinel_state = state(a, sentinel, 'initial_sentinel')
        require(sentinel_state == query(a, '(SELECT sentinel FROM c59s15_fixture.ownership)', 'stored_sentinel'), 'real_setup_sentinel')
        result['executed'] = True
        for index, case in enumerate(CASE_IDS):
            p = query(a, '(SELECT payload FROM c59s15_fixture.cases WHERE case_id=' + lit(case) + ')', 'case_real_payload')
            owner = p['ownerID']
            require(owner == 'c59b5000-0000-0000-0000-' + str(index + 501).zfill(12), 'case_owner_UUID')
            before = state(a, owner, 'before_case')
            a.begin()
            first_commit = index == 8 or index % 2 == 0
            if index < 2:
                require(before[X + 'authority_epochs'] == [] and before[X + 'lifecycles'] == [], 'first_admission_setup_no_life')
                first = query(a, admit(p), 'actual_admission_A')
                receipt = check_admission(first, p, 'admitted')
                b.begin()
                pending = b.send(reset(p), 'reset_B_waits_admission')
                wait_block(a, pids[0], pids[1], deadline)
                lower = query(a, "to_char(clock_timestamp() AT TIME ZONE 'UTC','YYYY-MM-DD\"T\"HH24:MI:SS.US\"Z\"')", 'before_release_clock')
                a.finish(first_commit)
                rr = b.receive(pending)
                require(rr.get('reset') is True, 'real_reset_after_admission')
                b.finish(True)
                after = state(a, owner, 'durable_admission_reset')
                no_open(after)
                if first_commit:
                    e = one_epoch(after)
                    require(e['epoch'] != receipt['epoch'] and e['current_lifecycle_key'] is None
                        and len(after[X + 'request_admissions']) == 1
                        and after[X + 'request_admissions'][0]['admission_id'] == receipt['admissionID']
                        and after[X + 'request_admissions'][0]['epoch'] == receipt['epoch']
                        and after[X + 'request_admissions'][0]['original_inbound_id'] is None, 'reset_retains_old_admission_without_life')
                    require(query(a, admit(p), 'durable_replay_old_epoch') == STALE, 'same_key_after_committed_reset_stale')
                    changed = query(a, '(SELECT to_char(changed_at AT TIME ZONE \'UTC\',\'YYYY-MM-DD"T"HH24:MI:SS.US"Z"\') FROM private.workout_strength_authority_epochs WHERE user_id=' + lit(owner) + '::uuid)', 'reset_clock')
                    require(base.instant(changed) >= base.instant(lower), 'reset_epoch_clock_after_observed_wait')
                    # A late IN remains possible; it is not fresh authority.
                    m = query(a, 'c59s15_fixture.inbound(' + lit(owner) + '::uuid,' + lit(p['requestKey']) + ',' + lit(p['content']) + ')', 'late_real_inbound')
                    late = dict(p, admission=receipt, inboundID=m)
                    require(query(a, initialize(late), 'late_inbound_init') == STALE, 'late_IN_no_rebind_after_epoch')
                    no_open(state(a, owner, 'late_IN_no_X'))
                else:
                    require(after[X + 'authority_epochs'] == [] and after[X + 'request_admissions'] == [], 'rolledback_admission_not_durable_reset_does_not_activate')
                    fresh = query(a, admit(p), 'post_reset_first_real_admission')
                    fresh_receipt = check_admission(fresh, p, 'admitted')
                    require(fresh_receipt['admissionID'] != receipt['admissionID'], 'rolledback_tentative_receipt_not_reused')
            elif index < 4:
                first = query(a, reset(p), 'actual_reset_A_before_admit')
                require(first.get('reset') is True, 'actual_reset_A')
                b.begin()
                pending = b.send(admit(p), 'admission_B_waits_reset')
                wait_block(a, pids[0], pids[1], deadline)
                a.finish(first_commit)
                rr = b.receive(pending)
                if first_commit:
                    require(rr == STALE, 'reset_winner_denies_old_admission')
                else:
                    require(rr == {'status': 'reused', 'admission': p['admission']}, 'reset_rollback_preserves_original_admission_receipt')
                b.finish(True)
                after = state(a, owner, 'durable_reset_admission')
                no_open(after)
                if first_commit:
                    require(one_epoch(after)['epoch'] != p['admission']['epoch'] and after['public.messages'] == []
                        and after[X + 'request_admissions'] == before[X + 'request_admissions'], 'reset_winner_keeps_tombstone_removes_IN')
                else:
                    require(after == before, 'reset_rollback_and_replay_preserve_full_state')
            elif index < 6:
                first = query(a, initialize(p), 'actual_init_A')
                life = check_lifecycle(first, p, 'initialized')
                b.begin()
                pending = b.send(reset(p), 'reset_B_waits_init')
                wait_block(a, pids[0], pids[1], deadline)
                lower = query(a, "to_char(clock_timestamp() AT TIME ZONE 'UTC','YYYY-MM-DD\"T\"HH24:MI:SS.US\"Z\"')", 'before_reset_release_clock')
                a.finish(first_commit)
                rr = b.receive(pending)
                require(rr.get('reset') is True, 'reset_after_init_completes')
                b.finish(True)
                after = state(a, owner, 'durable_init_reset')
                no_open(after)
                require(one_epoch(after)['epoch'] != p['admission']['epoch'] and one_epoch(after)['current_lifecycle_key'] is None, 'reset_epoch_after_init')
                rows = after[X + 'lifecycles']
                if first_commit:
                    require(len(rows) == 1 and rows[0]['lifecycle_key'] == life['lifecycleKey'] and rows[0]['closed_at'] is not None
                        and after[X + 'request_admissions'][0]['lifecycle_key'] == life['lifecycleKey']
                        and after[X + 'request_admissions'][0]['original_inbound_id'] == p['inboundID'], 'committed_life_closed_snapshots_retained')
                else:
                    require(rows == [] and after[X + 'request_admissions'] == before[X + 'request_admissions'], 'init_rollback_no_partial_life_binding')
                require(query(a, initialize(p), 'old_init_durable_denial') == STALE, 'reset_denies_init_replay_before_missing_IN')
                changed = query(a, '(SELECT to_char(changed_at AT TIME ZONE \'UTC\',\'YYYY-MM-DD"T"HH24:MI:SS.US"Z"\') FROM private.workout_strength_authority_epochs WHERE user_id=' + lit(owner) + '::uuid)', 'epoch_after_init_wait')
                require(base.instant(changed) >= base.instant(lower), 'epoch_clock_after_init_wait')
            elif index < 8:
                require(query(a, reset(p), 'actual_reset_A_before_init').get('reset') is True, 'reset_A_real')
                b.begin()
                pending = b.send(initialize(p), 'init_B_waits_reset')
                wait_block(a, pids[0], pids[1], deadline)
                lower = query(a, "to_char(clock_timestamp() AT TIME ZONE 'UTC','YYYY-MM-DD\"T\"HH24:MI:SS.US\"Z\"')", 'before_init_release_clock')
                a.finish(first_commit)
                rr = b.receive(pending)
                life = None
                if first_commit:
                    require(rr == STALE, 'committed_reset_denies_waiting_init')
                else:
                    life = check_lifecycle(rr, p, 'initialized')
                    require(base.instant(life['openedAt']) >= base.instant(lower), 'init_open_clock_after_observed_wait')
                b.finish(True)
                after = state(a, owner, 'durable_reset_init')
                if first_commit:
                    no_open(after)
                    require(one_epoch(after)['epoch'] != p['admission']['epoch'] and after[X + 'request_admissions'] == before[X + 'request_admissions'], 'no_waiting_init_after_reset_commit')
                else:
                    require(one_epoch(after)['epoch'] == p['admission']['epoch'] and one_epoch(after)['current_lifecycle_key'] == life['lifecycleKey']
                        and len(after[X + 'lifecycles']) == 1 and after[X + 'request_admissions'][0]['original_inbound_id'] == p['inboundID'], 'reset_rollback_allows_real_owned_init')
                    replay = query(a, initialize(p), 'durable_init_retry')
                    require(replay == {'status': 'reused', 'lifecycle': life}, 'durable_initialized_reference_preserved')
            else:
                second = p['second']
                first = query(a, initialize(p), 'first_admission_init_A')
                life = check_lifecycle(first, p, 'initialized')
                b.begin()
                pending = b.send(initialize(second), 'second_admission_init_B')
                wait_block(a, pids[0], pids[1], deadline)
                a.finish(True)
                rr = b.receive(pending)
                second_life = check_lifecycle(rr, second, 'initialized')
                require(second_life == life, 'second_new_binding_uses_same_owned_current_life')
                b.finish(True)
                after = state(a, owner, 'two_bindings_durable_one_life')
                require(len(after[X + 'lifecycles']) == 1 and after[X + 'lifecycles'][0]['closed_at'] is None
                    and one_epoch(after)['current_lifecycle_key'] == life['lifecycleKey']
                    and len(after[X + 'request_admissions']) == 2
                    and all(row['lifecycle_key'] == life['lifecycleKey'] for row in after[X + 'request_admissions'])
                    and {row['original_inbound_id'] for row in after[X + 'request_admissions']} == {p['inboundID'], second['inboundID']}, 'two_current_requests_at_most_one_open_life')
                require(query(a, initialize(second), 'second_binding_real_retry') == {'status': 'reused', 'lifecycle': life}, 'second_snapshot_retry_exact_reference')
            final_state = state(a, owner, 'after_all_case_operations')
            require(final_state['public.workout_logs'] == [] and final_state['public.daily_snapshots'] == [], 'no_X_workout_or_snapshot_write')
            require(state(a, sentinel, 'sentinel_after_case') == sentinel_state, 'other_owner_unchanged')
            result['cases'].append({'id': case, 'passed': True, 'actual_B_blocked_by_A': True,
                'first_committed': first_commit, 'actual_product_calls': True, 'durable_state_checked': True, 'other_owner_unchanged': True})
        require([c['id'] for c in result['cases']] == CASE_IDS, 'all_nine_once')
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
        reaped = all(c['reaped'] for c in cleanup)
        readers = all(c['readers_stopped'] for c in cleanup)
        result['cleanup'] = {'complete': reaped and readers, 'actors_reaped': reaped, 'readers_stopped': readers, 'actors': cleanup}
        (output / 'RESULT.json').write_text(json.dumps(result, indent=2) + '\n', encoding='utf-8')
    require(result['cleanup']['complete'] is True, 'owned_actor_cleanup')
    return result


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--bindings-json', required=True)
    parser.add_argument('--output-dir', required=True)
    args = parser.parse_args()
    config = json.loads(Path(args.bindings_json).read_text(encoding='utf-8'))
    config['output_dir'] = args.output_dir
    run(config)
