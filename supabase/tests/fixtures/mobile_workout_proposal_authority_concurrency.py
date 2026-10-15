#!/usr/bin/env python3
"""S16 real bounded A/B materialize/reset tests. Import inert; no DDL/server.
Root supplies reviewed bindings after owned setup COMMIT. Closed S7 Actor only.
RESULT is written after owned actor cleanup, including original exceptions.
"""
import argparse
import hashlib
import json
from pathlib import Path
import re
import time
import types

ACTOR_SHA = 'c14570d9059fbd56f4aa7efeeefeb9e0030b275c9b221a0890d1d484d1db1a5f'
CASE_IDS = ['materialize-reset-commit', 'materialize-reset-rollback',
    'reset-materialize-commit', 'reset-materialize-rollback',
    'materialize-materialize-commit', 'materialize-materialize-rollback']
X = 'private.workout_strength_'
J = 'private.mobile_workout_proposal_admissions'
P = 'public.pending_registrations'
STALE = {'status': 'forbidden', 'reason': 'stale_epoch'}
UUID = r'[0-9a-f]{8}(?:-[0-9a-f]{4}){3}-[0-9a-f]{12}'
US6 = r'\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{6}Z'


def require(value, label):
    if value is not True:
        raise RuntimeError('C59S16_DRIVER:' + label)


def lit(value):
    return "'" + str(value).replace("'", "''") + "'"


def js(value):
    return lit(json.dumps(value, ensure_ascii=False)) + '::jsonb'


def materialize(p, proposal=None, expires=None, replay_null=False):
    proposal_sql = 'NULL' if replay_null else js(p['proposal'] if proposal is None else proposal)
    expiry_sql = 'NULL' if replay_null else lit(p['expiresAt'] if expires is None else expires) + '::timestamptz'
    return 'public.materialize_mobile_workout_proposal(' + ','.join([
        lit(p['ownerID']) + '::uuid', lit(p['admission']['admissionID']) + '::uuid',
        js(p['input']), proposal_sql, expiry_sql]) + ')'


def reset(p):
    return 'public.reset_user_conversation_atomic(' + lit(p['ownerID']) + '::uuid,true)'


def check_materialized(r, status, pending_id=None):
    require(isinstance(r, dict) and set(r) == {'status', 'pendingID', 'pendingStatus', 'cancelledCount'}
        and r['status'] == status and isinstance(r['pendingID'], str)
        and re.fullmatch(UUID, r['pendingID']) is not None
        and r['pendingStatus'] == 'pending' and type(r['cancelledCount']) is int
        and r['cancelledCount'] == 0, 'exact_materialize_wire_' + status)
    if pending_id is not None:
        require(r['pendingID'] == pending_id, 'winner_pending_UUID')
    return r['pendingID']

def wait_block(observer, blocker, waiter, deadline):
    limit = min(deadline, time.monotonic() + 6)
    while time.monotonic() < limit:
        observer.statement('SELECT pg_stat_clear_snapshot();')
        if observer.query(str(blocker) + '=ANY(pg_blocking_pids(' + str(waiter) + '))', 'actual_blocker') is True:
            return
    raise TimeoutError('C59S16_DRIVER:no_actual_blocker')


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
        return query(actor, 'c59s16_fixture.state(' + lit(owner) + '::uuid)', label)

    def epoch(s):
        rows = s[X + 'authority_epochs']
        require(len(rows) == 1, 'one_real_epoch')
        return rows[0]

    def journal(s):
        rows = s[J]
        require(len(rows) == 1, 'one_real_UI_admission')
        return rows[0]

    def no_other_writes(s):
        for key in ['public.messages', 'public.workout_logs', 'public.daily_snapshots', X + 'lifecycles',
            X + 'operations', X + 'facts', X + 'commands', X + 'calendar_scopes',
            X + 'request_admissions']:
            require(s[key] == [], 'no_unrequested_write_' + key)

    def outside_pending_binding(s):
        return {k: v for k, v in s.items() if k not in [J, P]}

    def official_reset_projection(s, owner):
        profiles = s['public.user_profiles']
        progress = s['public.user_progress']
        require(len(profiles) == 1 and profiles[0]['user_id'] == owner
            and profiles[0]['onboarding_completed'] is False
            and profiles[0]['onboarding_step'] == 0, 'official_reset_owned_profile')
        require(len(progress) == 1 and progress[0]['user_id'] == owner
            and all(progress[0][k] == v for k, v in {
                'xp_total': 0, 'level': 1, 'current_streak': 0,
                'longest_streak': 0, 'blocks_completed': 0, 'deficit_block': 0,
                'badges_earned': []}.items()), 'official_reset_owned_progress')

    def clock(actor, expression, label):
        return query(actor, "to_char((" + expression + ") AT TIME ZONE 'UTC','YYYY-MM-DD\"T\"HH24:MI:SS.US\"Z\"')", label)

    def check_bound(s, p, pending_id, proposal, expires, label):
        j = journal(s)
        require(len(s[P]) == 1, label + '_one_pending')
        pending_row = s[P][0]
        require(pending_row['id'] == pending_id and pending_row['user_id'] == p['ownerID']
            and pending_row['status'] == 'pending' and pending_row['proposal'] == proposal,
            label + '_exact_owned_raw_proposal')
        digest = query(a, "encode(sha256(convert_to((" + js(proposal) + ")::text,'UTF8')),'hex')", label + '_proposal_digest')
        no_other_writes(s)
        require(outside_pending_binding(s) == outside_pending_binding(before), label + '_no_other_state_mutation')
        require({k: v for k, v in j.items() if k not in ['pending_id', 'first_proposal_hash', 'bound_at']}
            == {k: v for k, v in j_before.items() if k not in ['pending_id', 'first_proposal_hash', 'bound_at']},
            label + '_immutable_original_admission')
        require(j['user_id'] == p['ownerID'] and j['admission_id'] == p['admission']['admissionID']
            and j['epoch'] == p['admission']['epoch'] and j['request_key'] == p['requestKey']
            and j['request_hash'] == p['admission']['requestHash'] and j['pending_id'] == pending_id
            and j['first_proposal_hash'] == digest and j['bound_at'] is not None
            and j['rejection_reason'] is None, label + '_journal_triplet_and_original_admission')
        require(query(a, '(SELECT expires_at=' + lit(expires) + '::timestamptz FROM ONLY public.pending_registrations WHERE id=' + lit(pending_id) + '::uuid)', label + '_expires_equal') is True,
            label + '_exact_expiry')
        return j

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
        require(config.get('expected_case_ids') == CASE_IDS, 'ordered_six_case_pin')
        base = types.ModuleType('c59s16_closed_actor')
        exec(compile(source, str(actor_path), 'exec'), base.__dict__)
        a = base._create_registered_actor('A', config, output, actors)
        b = base._create_registered_actor('B', config, output, actors)
        pids = []
        for actor in actors:
            identity = query(actor, "jsonb_build_object('owner',session_user,'db',current_database(),'port',current_setting('port')::int,'data',current_setting('data_directory'),'socket',current_setting('unix_socket_directories'),'listen',current_setting('listen_addresses'),'pid',pg_backend_pid(),'tag',(SELECT tag FROM c59s16_fixture.ownership))", 'identity')
            require(identity['owner'] == config['user'] and identity['db'] == config['database']
                and identity['port'] == config['port'] and identity['data'] == config['expected_data_directory']
                and identity['socket'] == config['socket'] and identity['listen'] == ''
                and identity['tag'] == 'c59s16_ui_proposal_v1', 'actual_local_identity')
            pids.append(identity['pid'])
            actor.statement("SET statement_timeout='12s';SET lock_timeout='9s';SET request.jwt.claims='{\"role\":\"service_role\"}';SET TimeZone='UTC';SET DateStyle='ISO,YMD';")
        require(pids[0] != pids[1], 'distinct_A_B')
        sentinel = 'c59b6000-0000-0000-0000-000000000999'
        sentinel_state = state(a, sentinel, 'initial_sentinel')
        require(sentinel_state == query(a, '(SELECT sentinel FROM c59s16_fixture.ownership)', 'stored_sentinel'), 'real_setup_sentinel')
        result['executed'] = True
        for index, case in enumerate(CASE_IDS):
            p = query(a, '(SELECT payload FROM c59s16_fixture.cases WHERE case_id=' + lit(case) + ')', 'case_real_payload')
            owner = p['ownerID']
            require(owner == 'c59b6000-0000-0000-0000-' + str(index + 501).zfill(12)
                and p['requestKey'] == 's16-request-' + str(index + 501), 'case_owner_and_literal_key')
            before = state(a, owner, 'before_case')
            no_other_writes(before)
            require(before['public.user_profiles'] == [] and before['public.user_progress'] == [],
                'new_owner_setup_profiles_and_progress_empty')
            j_before = journal(before)
            require(before[P] == [] and j_before['pending_id'] is None and j_before['first_proposal_hash'] is None
                and j_before['bound_at'] is None and j_before['rejection_reason'] is None
                and epoch(before)['epoch'] == p['admission']['epoch'], 'real_unbound_setup')
            require(query(a, 'c59s16_fixture.admission_wire(' + js({'status': 'admitted', 'admission': p['admission']}) + ',' + lit(owner) + '::uuid,' + lit(p['requestKey']) + ',' + lit(p['admission']['requestHash']) + ",'admitted')", 'real_admission_receipt') is True, 'owned_original_receipt_exact7')
            first_commit = index % 2 == 0
            a.begin()
            if index < 2:
                first = query(a, materialize(p), 'materialize_A')
                tentative_id = check_materialized(first, 'materialized')
                tentative = state(a, owner, 'tentative_bound_A')
                bound_a = check_bound(tentative, p, tentative_id, p['proposal'], p['expiresAt'], 'tentative_A')
                b.begin()
                ticket = b.send(reset(p), 'reset_B_waits_materialize')
                wait_block(a, pids[0], pids[1], deadline)
                lower = clock(a, 'clock_timestamp()', 'before_reset_release_clock')
                a.finish(first_commit)
                require(b.receive(ticket).get('reset') is True, 'real_reset_after_wait')
                b.finish(True)
                after = state(a, owner, 'durable_materialize_reset')
                official_reset_projection(after, owner)
                require(after[P] == [] and epoch(after)['epoch'] != p['admission']['epoch']
                    and epoch(after)['current_lifecycle_key'] is None, 'reset_clears_pending_and_advances_epoch')
                require(journal(after) == (bound_a if first_commit else j_before), 'reset_retains_only_committed_binding_tombstone')
                require(query(a, materialize(p, replay_null=True), 'old_materialize_retry') == STALE,
                    'reset_denies_replay_before_original_pending_lookup')
                require(state(a, owner, 'after_stale_materialize_retry') == after,
                    'stale_retry_preserves_full_official_reset_state')
                changed = clock(a, '(SELECT changed_at FROM private.workout_strength_authority_epochs WHERE user_id=' + lit(owner) + '::uuid)', 'epoch_changed_at_after_wait')
                require(base.instant(changed) >= base.instant(lower), 'reset_clock_after_observed_block')
            elif index < 4:
                require(query(a, reset(p), 'reset_A').get('reset') is True, 'real_reset_A')
                b.begin()
                ticket = b.send(materialize(p), 'materialize_B_waits_reset')
                wait_block(a, pids[0], pids[1], deadline)
                lower = clock(a, 'clock_timestamp()', 'before_materialize_release_clock')
                a.finish(first_commit)
                second = b.receive(ticket)
                if first_commit:
                    require(second == STALE, 'committed_reset_denies_waiting_materialize')
                else:
                    check_materialized(second, 'materialized')
                b.finish(True)
                after = state(a, owner, 'durable_reset_materialize')
                if first_commit:
                    official_reset_projection(after, owner)
                    require(after[P] == [] and journal(after) == j_before
                        and epoch(after)['epoch'] != p['admission']['epoch']
                        and epoch(after)['current_lifecycle_key'] is None, 'reset_winner_no_partial_pending_or_binding')
                    require(query(a, materialize(p, replay_null=True), 'old_waiting_retry') == STALE, 'stale_retry_is_durable')
                    require(state(a, owner, 'after_stale_waiting_retry') == after,
                        'waiting_stale_retry_preserves_full_official_reset_state')
                else:
                    check_bound(after, p, second['pendingID'], p['proposal'], p['expiresAt'], 'after_reset_rollback')
                    require(outside_pending_binding(after) == outside_pending_binding(before), 'reset_rollback_no_other_mutation')
                    bound_time = clock(a, '(SELECT bound_at FROM private.mobile_workout_proposal_admissions WHERE user_id=' + lit(owner) + '::uuid)', 'binding_clock_after_reset_wait')
                    require(base.instant(bound_time) >= base.instant(lower), 'binding_clock_after_observed_reset_wait')
                    retry = query(a, materialize(p, replay_null=True), 'materialize_retry_after_reset_rollback')
                    check_materialized(retry, 'reused', second['pendingID'])
                    require(state(a, owner, 'retry_state_reset_rollback') == after, 'durable_retry_no_write')
            else:
                proposal_b = dict(p['proposal'], kcalEst=456)
                expiry_b = query(a, 'to_jsonb(' + lit(p['expiresAt']) + "::timestamptz+interval '1 day')", 'distinct_expiry_B')
                require(proposal_b != p['proposal'] and expiry_b != p['expiresAt'], 'distinct_candidate_B')
                first = query(a, materialize(p), 'materialize_first_A')
                tentative_id = check_materialized(first, 'materialized')
                tentative = state(a, owner, 'tentative_winner_A')
                bound_a = check_bound(tentative, p, tentative_id, p['proposal'], p['expiresAt'], 'tentative_first_A')
                b.begin()
                ticket = b.send(materialize(p, proposal_b, expiry_b), 'materialize_B_waits_first')
                wait_block(a, pids[0], pids[1], deadline)
                lower = clock(a, 'clock_timestamp()', 'before_first_materialize_release_clock')
                a.finish(first_commit)
                second = b.receive(ticket)
                winner_id = check_materialized(second, 'reused' if first_commit else 'materialized',
                    tentative_id if first_commit else None)
                require(first_commit or winner_id != tentative_id, 'rollback_does_not_reuse_tentative_UUID')
                b.finish(True)
                after = state(a, owner, 'durable_first_winner')
                winning_proposal = p['proposal'] if first_commit else proposal_b
                winning_expiry = p['expiresAt'] if first_commit else expiry_b
                check_bound(after, p, winner_id, winning_proposal, winning_expiry, 'durable_winner')
                require(outside_pending_binding(after) == outside_pending_binding(before), 'materialize_only_changes_pending_and_binding')
                if first_commit:
                    require(after == tentative and journal(after) == bound_a, 'committed_first_proposal_and_triplet_immutable')
                else:
                    bound_time = clock(a, '(SELECT bound_at FROM private.mobile_workout_proposal_admissions WHERE user_id=' + lit(owner) + '::uuid)', 'rollback_winner_bound_clock')
                    require(base.instant(bound_time) >= base.instant(lower), 'new_winner_clock_after_observed_wait')
                retry = query(a, materialize(p, replay_null=True), 'durable_first_winner_retry_NULLs')
                check_materialized(retry, 'reused', winner_id)
                require(state(a, owner, 'winner_after_retry') == after, 'retry_never_rewrites_first_raw_proposal_or_expiry')
            final_state = state(a, owner, 'after_all_case_operations')
            no_other_writes(final_state)
            require(state(a, sentinel, 'sentinel_after_case') == sentinel_state, 'other_owner_unchanged')
            result['cases'].append({'id': case, 'passed': True, 'actual_B_blocked_by_A': True,
                'first_committed': first_commit, 'actual_product_calls': True, 'durable_state_checked': True,
                'no_IN_lifecycle_workout_snapshot_write': True, 'other_owner_unchanged': True})
        require([c['id'] for c in result['cases']] == CASE_IDS, 'all_six_once')
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
