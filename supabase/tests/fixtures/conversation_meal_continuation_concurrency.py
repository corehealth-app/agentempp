"""Owned real-PG linked-continuation races; inert import, no runtime lifecycle.

Run only after the exact stack/owner/source pins are verified externally. Each
waiter is proven blocked using pg_blocking_pids. No provider is ever contacted.
"""
import importlib.util
import json
from pathlib import Path
import sys
import time

OWNER = 'c3c40000-0000-4000-8000-000000000001'
AUTH = 'c3c40000-0000-4000-8000-000000000002'
PARENT = 'c3c40000-0000-4000-8000-000000000003'
REPLY_A = 'c3c40000-0000-4000-8000-000000000004'
REPLY_B = 'c3c40000-0000-4000-8000-000000000005'


def run(config):
    if config.get('ownership_verified') is not True:
        raise AssertionError('exact owned local target guard required')
    spec = importlib.util.spec_from_file_location('continuation_actor', Path(__file__).with_name('conversation_meal_command_journal_concurrency.py'))
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    Actor, lit, require = module.Actor, module.lit, module.require
    actors = []
    admin = None
    owns_owner = False
    result = {'cases': [], 'cleanup': False, 'actors_reaped': False}
    owner = lit(OWNER) + '::uuid'
    parent = lit(PARENT) + '::uuid'
    reset = 'public.reset_user_conversation_atomic(' + owner + ',true)'

    def spawn():
        actor = Actor.__new__(Actor)
        actors.append(actor)
        Actor.__init__(actor, config)
        return actor

    def blocked(blocker, waiter):
        deadline = time.monotonic() + 3
        while time.monotonic() < deadline:
            if admin.query(str(blocker.pid) + '=ANY(pg_blocking_pids(' + str(waiter.pid) + '))'):
                return
            time.sleep(.02)
        raise AssertionError('actual linked parent owner-lane blocking not observed')

    def js(value):
        return lit(json.dumps(value)) + '::jsonb'

    def setup(missing=False):
        admin.command('DELETE FROM public.users WHERE id=' + owner)
        admin.command('DELETE FROM auth.users WHERE id=' + lit(AUTH) + '::uuid')
        seed = admin.query('pg_temp.continuation_seed(' + owner + ',' + lit(AUTH) + '::uuid,' + parent + ',' + ('true' if missing else 'false') + ')')
        state = admin.query('pg_temp.continuation_read(' + owner + ',' + parent + ',' + js(seed) + ')')
        answer = {'kind': 'quantity', 'food_index': 0, 'amount': 100, 'unit': 'g'} if missing else {'kind': 'meal_type', 'meal_type': 'almoco'}
        body = {'schema': 'conversation.meal-clarification.v1', 'expected_revision': state['head']['revision'], 'question_key': state['head']['question']['question_key'], 'answer': answer}
        base = owner + ',' + parent + ',' + js(seed) + ','
        calls = {}
        for rid in [REPLY_A, REPLY_B]:
            calls[rid] = 'pg_temp.continuation_admit(' + base + lit(rid) + '::uuid,' + js(body) + ')'
        return seed, state, body, calls

    def prepare_call(seed, rid, admission, ready=True):
        base = owner + ',' + parent + ',' + js(seed) + ',' + lit(rid) + '::uuid,' + lit(admission['child_binding']['input_hash'])
        state = admin.query('pg_temp.continuation_read(' + base + ')')
        payload = admin.query('pg_temp.continuation_preparation(' + js(state) + ',' + ('true' if ready else 'false') + ')')
        return 'pg_temp.continuation_prepare(' + base + ',' + js(payload) + ')'

    def commit_call(seed, rid, admission, preparation):
        return 'pg_temp.continuation_commit(' + owner + ',' + parent + ',' + js(seed) + ',' + lit(rid) + '::uuid,' + lit(admission['child_binding']['input_hash']) + ',' + lit(preparation['stored']['prepared_hash']) + ')'

    def counts(foods, effects, heads, reset_done=False):
        actual = admin.query('json_build_array((SELECT count(*) FROM public.meal_logs WHERE user_id=' + owner + '),(SELECT count(*) FROM private.conversation_meal_effects WHERE user_id=' + owner + '),(SELECT count(*) FROM private.conversation_meal_fulfillments WHERE user_id=' + owner + '),(SELECT count(*) FROM private.conversation_meal_continuation_heads WHERE user_id=' + owner + '),(SELECT count(*) FROM public.pending_registrations WHERE user_id=' + owner + '),(SELECT count(*) FROM public.workout_logs WHERE user_id=' + owner + '),(SELECT count(*) FROM private.workout_strength_lifecycles WHERE user_id=' + owner + '),(SELECT count(*) FROM public.user_progress WHERE user_id=' + owner + '))')
        require(actual == [foods, effects, effects, heads, effects, 0, 0, 1 if reset_done else 0], 'exact continuation/domain/progress counts ' + str(actual))
        if reset_done:
            require(admin.query('EXISTS(SELECT 1 FROM public.user_progress WHERE user_id=' + owner + ' AND xp_total=0 AND level=1 AND blocks_completed=0 AND deficit_block=0)'), 'only unchanged reset zero baseline exists')

    try:
        admin = Actor.__new__(Actor)
        actors.append(admin)
        Actor.__init__(admin, config)
        a = spawn()
        b = spawn()
        require(admin.query('NOT EXISTS(SELECT 1 FROM public.users WHERE id=' + owner + ') AND NOT EXISTS(SELECT 1 FROM auth.users WHERE id=' + lit(AUTH) + '::uuid)'), 'preserve colliding owner/auth namespace')
        owns_owner = True
        directory = Path(__file__).parent
        helpers = (directory / 'conversation_meal_atomic_writer_fixture.sql').read_text()
        for name in ['conversation_meal_semantic_fixture.sql', 'conversation_meal_decision_fixture.sql', 'conversation_meal_continuation_fixture.sql']:
            helpers += '\n' + '\n'.join(line for line in (directory / name).read_text().splitlines() if not line.startswith('\\ir '))
        for actor in actors:
            actor.command(helpers)

        for rollback in [False, True]:
            seed, state, body, calls = setup()
            a.command('BEGIN')
            first = a.query(calls[REPLY_A])
            require(first['action'] == 'admitted', 'first reply actually admitted')
            marker = b.send(calls[REPLY_A])
            blocked(a, b)
            a.command('ROLLBACK' if rollback else 'COMMIT')
            second = b.receive(marker)
            require(second['action'] == ('admitted' if rollback else 'replay'), 'one committed child identity/source')
            if not rollback:
                require(second == dict(first, action='replay'), 'exact immutable admission replay')
            counts(0, 0, 1)
            result['cases'].append('admit-' + ('rollback' if rollback else 'commit'))

        for rollback in [False, True]:
            seed, state, body, calls = setup(True)
            admissions = {rid: admin.query(calls[rid]) for rid in [REPLY_A, REPLY_B]}
            first_sql = prepare_call(seed, REPLY_A, admissions[REPLY_A], False)
            second_sql = prepare_call(seed, REPLY_B, admissions[REPLY_B], False)
            a.command('BEGIN')
            first = a.query(first_sql)
            require(first['action'] == 'prepared' and first['head']['revision'] == 1, 'partial preparation advances exactly once')
            marker = b.send(second_sql)
            blocked(a, b)
            a.command('ROLLBACK' if rollback else 'COMMIT')
            second = b.receive(marker)
            require(second['action'] == ('prepared' if rollback else 'question_conflict'), 'only one accepted answer advances current question')
            counts(0, 0, 1)
            result['cases'].append('partial-prepare-' + ('rollback' if rollback else 'commit'))

        for same_reply in [True, False]:
            for rollback in [False, True]:
                seed, state, body, calls = setup()
                admissions = {rid: admin.query(calls[rid]) for rid in [REPLY_A, REPLY_B]}
                prepared = {rid: admin.query(prepare_call(seed, rid, admissions[rid])) for rid in [REPLY_A, REPLY_B]}
                first_sql = commit_call(seed, REPLY_A, admissions[REPLY_A], prepared[REPLY_A])
                rid = REPLY_A if same_reply else REPLY_B
                second_sql = commit_call(seed, rid, admissions[rid], prepared[rid])
                a.command('BEGIN')
                first = a.query(first_sql)
                require(first['action'] == 'committed', 'first domain/FX/fulfillment really committed inside actor TX')
                read = admin.query('pg_temp.continuation_read(' + owner + ',' + parent + ',' + js(seed) + ')')
                require(read['fulfillment'] is None, 'read neither blocks nor exposes uncommitted food receipt')
                marker = b.send(second_sql)
                blocked(a, b)
                a.command('ROLLBACK' if rollback else 'COMMIT')
                second = b.receive(marker)
                expected = 'committed' if rollback else 'replay' if same_reply else 'question_conflict'
                require(second['action'] == expected, 'unique parent fulfillment across both child IDs')
                if not rollback and same_reply:
                    require(second == dict(first, action='replay'), 'same reply exact frozen effect replay')
                counts(1, 1, 1)
                result['cases'].append('commit-' + ('same' if same_reply else 'different') + '-' + ('rollback' if rollback else 'commit'))

        for operation in ['admit', 'commit']:
            for reset_first in [True, False]:
                for rollback in [False, True]:
                    seed, state, body, calls = setup()
                    operation_sql = calls[REPLY_A]
                    if operation == 'commit':
                        admission = admin.query(operation_sql)
                        preparation = admin.query(prepare_call(seed, REPLY_A, admission))
                        operation_sql = commit_call(seed, REPLY_A, admission, preparation)
                    a.command('BEGIN')
                    first = a.query(reset if reset_first else operation_sql)
                    if reset_first:
                        require(a.query('EXISTS(SELECT 1 FROM private.conversation_meal_command_ids WHERE user_id=' + owner + ' AND invalidated_at IS NOT NULL)'), 'actual reset invalidates before contention')
                    else:
                        require(first['action'] == ('admitted' if operation == 'admit' else 'committed'), 'actual first operation succeeded before reset')
                    marker = b.send(operation_sql if reset_first else reset)
                    blocked(a, b)
                    a.command('ROLLBACK' if rollback else 'COMMIT')
                    second = b.receive(marker)
                    if reset_first:
                        require(second['action'] == (('admitted' if operation == 'admit' else 'committed') if rollback else 'stale_epoch'), 'old identity cannot cross a committed reset')
                        counts(1 if operation == 'commit' and rollback else 0, 1 if operation == 'commit' and rollback else 0, 1 if rollback else 0, not rollback)
                    else:
                        require(second is not None and admin.query('pg_temp.continuation_read(' + owner + ',' + parent + ',' + js(seed) + ')') == {'action': 'stale_epoch'}, 'reset erases committed/rolled-back health state and blocks old epoch replay')
                        counts(0, 0, 0, True)
                    result['cases'].append(operation + '-' + ('reset-first' if reset_first else 'operation-first') + '-' + ('rollback' if rollback else 'commit'))
    finally:
        primary_error = sys.exc_info()[1]
        errors = []
        for actor in actors[1:]:
            try:
                actor.close()
            except BaseException as error:
                errors.append(error)
                process = getattr(actor, 'process', None)
                if process is not None and process.poll() is None:
                    try:
                        process.kill()
                        process.wait(timeout=5)
                    except BaseException as kill_error:
                        errors.append(kill_error)
        if admin is not None:
            try:
                if owns_owner:
                    admin.command('ROLLBACK')
                    admin.command('DELETE FROM public.users WHERE id=' + lit(OWNER) + '::uuid')
                    admin.command('DELETE FROM auth.users WHERE id=' + lit(AUTH) + '::uuid')
                    require(admin.query('NOT EXISTS(SELECT 1 FROM public.users WHERE id=' + lit(OWNER) + '::uuid) AND NOT EXISTS(SELECT 1 FROM auth.users WHERE id=' + lit(AUTH) + '::uuid) AND NOT EXISTS(SELECT 1 FROM private.conversation_meal_command_ids WHERE user_id=' + lit(OWNER) + '::uuid)'), 'owned race rows fully cleaned')
                    result['cleanup'] = True
            except BaseException as error:
                errors.append(error)
            finally:
                try:
                    admin.close()
                except BaseException as error:
                    errors.append(error)
                    process = getattr(admin, 'process', None)
                    if process is not None and process.poll() is None:
                        try:
                            process.kill()
                            process.wait(timeout=5)
                        except BaseException as kill_error:
                            errors.append(kill_error)
        result['actors_reaped'] = all(getattr(actor, 'process', None) is None or actor.process.poll() is not None for actor in actors)
        if errors:
            error = AssertionError('continuation race cleanup failed: ' + '; '.join(str(item) for item in errors))
            error.cleanup_errors = tuple(errors)
            if primary_error is not None:
                raise error from primary_error
            raise error
    return result
