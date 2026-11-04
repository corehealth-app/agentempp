"""Real-PG admission quota/reset races; inert without an owned-local guard.

No provider, domain writer or stack lifecycle. Only the exact synthetic owner
is deleted, after proving its namespace unused. Every tracked actor is reaped.
"""
import importlib.util
import json
from pathlib import Path
import sys
import time

OWNER = 'c3fb0000-0000-4000-8000-000000000001'
COMMAND = 'c3fb0000-0000-4000-8000-000000000002'
EPOCH = 'c3fb0000-0000-4000-8000-000000000003'


def run(config):
    if config.get('ownership_verified') is not True:
        raise AssertionError('owned local target guard required')
    spec = importlib.util.spec_from_file_location('quota_actor', Path(__file__).with_name('conversation_meal_command_journal_concurrency.py'))
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    Actor, lit, require = module.Actor, module.lit, module.require
    actors = []
    admin = None
    owns_owner = False
    result = {'cases': [], 'cleanup': False, 'actors_reaped': False}
    raw = {'command_protocol': 'conversation.command.v1', 'command_id': COMMAND,
        'kind': 'meal.report', 'source': {'channel': 'text', 'text': 'Comi arroz 100g sintetico'}}
    admit = 'public.admit_conversation_meal_command_fenced(' + lit(OWNER) + '::uuid,' + lit(json.dumps(raw)) + '::jsonb,' + lit(EPOCH) + '::uuid)'
    reset = 'public.reset_user_conversation_atomic(' + lit(OWNER) + '::uuid,true)'

    def spawn():
        actor = Actor.__new__(Actor)
        actors.append(actor)
        Actor.__init__(actor, config)
        return actor

    def setup():
        admin.command('DELETE FROM public.users WHERE id=' + lit(OWNER) + '::uuid')
        admin.command("INSERT INTO public.users(id,email,status,timezone,country,country_confirmed) VALUES(" + lit(OWNER) + "::uuid,'admission-quota-race@example.invalid','active','UTC','BR',true)")
        admin.command('INSERT INTO private.workout_strength_authority_epochs(user_id,epoch,changed_at) VALUES(' + lit(OWNER) + '::uuid,' + lit(EPOCH) + '::uuid,clock_timestamp())')
        for index in range(101, 110):
            seeded = dict(raw, command_id='c3fb0000-0000-4000-8000-' + str(index).zfill(12))
            require(admin.query('public.admit_conversation_meal_command(' + lit(OWNER) + '::uuid,' + lit(json.dumps(seeded)) + '::jsonb)')['action'] == 'admitted', 'nine real baseline admissions')

    def blocked(blocker, waiter):
        deadline = time.monotonic() + 3
        while time.monotonic() < deadline:
            if admin.query(str(blocker.pid) + '=ANY(pg_blocking_pids(' + str(waiter.pid) + '))'):
                return
            time.sleep(.02)
        raise AssertionError('actual fenced admission/reset blocking not observed')

    def counts(ids, sources, reset_done=False):
        actual = admin.query('json_build_array((SELECT count(*) FROM private.conversation_meal_command_ids WHERE user_id=' + lit(OWNER) + '::uuid),(SELECT count(*) FROM private.conversation_meal_command_sources WHERE user_id=' + lit(OWNER) + '::uuid),(SELECT count(*) FROM public.meal_logs WHERE user_id=' + lit(OWNER) + '::uuid),(SELECT count(*) FROM public.pending_registrations WHERE user_id=' + lit(OWNER) + '::uuid),(SELECT count(*) FROM public.workout_logs WHERE user_id=' + lit(OWNER) + '::uuid),(SELECT count(*) FROM private.workout_strength_lifecycles WHERE user_id=' + lit(OWNER) + '::uuid),(SELECT count(*) FROM public.user_progress WHERE user_id=' + lit(OWNER) + '::uuid))')
        require(actual == [ids, sources, 0, 0, 0, 0, 1 if reset_done else 0], 'exact fenced admission/domain counts: ' + str(actual))
        if reset_done:
            require(admin.query('EXISTS(SELECT 1 FROM public.user_progress WHERE user_id=' + lit(OWNER) + '::uuid AND xp_total=0 AND level=1 AND blocks_completed=0 AND deficit_block=0)'), 'reset retains only its existing zero progress baseline')

    try:
        admin = spawn()
        a = spawn()
        b = spawn()
        require(admin.query('NOT EXISTS(SELECT 1 FROM public.users WHERE id=' + lit(OWNER) + '::uuid)'), 'preserve collision: synthetic owner must be unused')
        owns_owner = True
        second_admit = admit.replace(COMMAND, 'c3fb0000-0000-4000-8000-000000000004')
        for rollback in [False, True]:
            setup()
            a.command('BEGIN')
            first = a.query(admit)
            require(first['action'] == 'admitted', 'tenth slot really admitted')
            marker = b.send(second_admit)
            blocked(a, b)
            a.command('ROLLBACK' if rollback else 'COMMIT')
            second = b.receive(marker)
            if rollback:
                require(second['action'] == 'admitted', 'rolled-back slot remains available to distinct waiter')
                require(admin.query(admit) == {'action': 'rate_limited'}, 'rolled-back first identity never persisted')
                require(admin.query(second_admit) == dict(second, action='replay'), 'waiter winner replays at full quota')
            else:
                require(second == {'action': 'rate_limited'}, 'only one of two fresh identities gets final slot')
                require(admin.query(admit) == dict(first, action='replay'), 'winner replays at full quota')
                require(admin.query(second_admit) == {'action': 'rate_limited'}, 'loser never acquired identity')
            counts(10, 10)
            result['cases'].append('tenth-slot-first-rollback' if rollback else 'two-fresh-commands-one-tenth-slot')

        setup()
        a.command('BEGIN')
        require(a.query(reset).get('reset') is True, 'reset really succeeded before waiter')
        marker = b.send(admit)
        blocked(a, b)
        a.command('COMMIT')
        require(b.receive(marker) == {'action': 'stale_epoch'}, 'reset fence takes priority over quota slot')
        counts(9, 0, reset_done=True)
        epoch = admin.query('(SELECT epoch FROM private.workout_strength_authority_epochs WHERE user_id=' + lit(OWNER) + '::uuid)')
        new_intent = second_admit.rsplit(lit(EPOCH), 1)[0] + lit(epoch) + '::uuid)'
        require(admin.query(new_intent)['action'] == 'admitted', 'separate fresh intent uses current epoch quota')
        counts(10, 1, reset_done=True)
        result['cases'].append('reset-before-quota-waiter-new-epoch-isolated')
    finally:
        primary_error = sys.exc_info()[1]
        cleanup_errors = []

        def reap(actor):
            try:
                actor.close()
            except BaseException as error:
                cleanup_errors.append(error)
            finally:
                try:
                    if actor.process.poll() is None:
                        actor.process.kill()
                        actor.process.wait(timeout=3)
                    reader = getattr(actor, 'reader', None)
                    if reader is not None:
                        reader.join(timeout=1)
                except BaseException as error:
                    cleanup_errors.append(error)

        for actor in reversed(actors):
            if actor is not admin and hasattr(actor, 'process'):
                reap(actor)
        if admin is not None and hasattr(admin, 'process'):
            try:
                if owns_owner:
                    admin.command('DELETE FROM public.users WHERE id=' + lit(OWNER) + '::uuid')
                    result['cleanup'] = admin.query('NOT EXISTS(SELECT 1 FROM public.users WHERE id=' + lit(OWNER) + '::uuid) AND NOT EXISTS(SELECT 1 FROM private.conversation_meal_command_ids WHERE user_id=' + lit(OWNER) + '::uuid)')
            except BaseException as error:
                cleanup_errors.append(error)
            finally:
                reap(admin)
        result['actors_reaped'] = all(not hasattr(actor, 'process') or actor.process.poll() is not None and (getattr(actor, 'reader', None) is None or not actor.reader.is_alive()) for actor in actors)
        if cleanup_errors:
            error = RuntimeError('admission quota race cleanup failed: ' + ','.join(type(item).__name__ for item in cleanup_errors))
            error.cleanup_errors = tuple(cleanup_errors)
            raise error from (primary_error or cleanup_errors[0])
    require(result['cleanup'] and result['actors_reaped'], 'synthetic owner removed and actors reaped')
    return result
