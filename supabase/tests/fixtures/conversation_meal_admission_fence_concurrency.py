"""Real-PG admission/reset fencing races; inert without an owned-local guard.

No provider, domain writer or stack lifecycle. Only the exact synthetic owner
is deleted, after proving its namespace unused. Every tracked actor is reaped.
"""
import importlib.util
import json
from pathlib import Path
import sys
import time

OWNER = 'c3ff0000-0000-4000-8000-000000000001'
COMMAND = 'c3ff0000-0000-4000-8000-000000000002'
EPOCH = 'c3ff0000-0000-4000-8000-000000000003'


def run(config):
    if config.get('ownership_verified') is not True:
        raise AssertionError('owned local target guard required')
    spec = importlib.util.spec_from_file_location('fence_actor', Path(__file__).with_name('conversation_meal_command_journal_concurrency.py'))
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
        admin.command("INSERT INTO public.users(id,email,status,timezone,country,country_confirmed) VALUES(" + lit(OWNER) + "::uuid,'fenced-admission-race@example.invalid','active','UTC','BR',true)")
        admin.command('INSERT INTO private.workout_strength_authority_epochs(user_id,epoch,changed_at) VALUES(' + lit(OWNER) + '::uuid,' + lit(EPOCH) + '::uuid,clock_timestamp())')

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
        for rollback in [False, True]:
            setup()
            a.command('BEGIN')
            first = a.query(admit)
            require(first['action'] == 'admitted', 'first admission actually succeeded')
            marker = b.send(admit)
            blocked(a, b)
            a.command('ROLLBACK' if rollback else 'COMMIT')
            second = b.receive(marker)
            require(second['action'] == ('admitted' if rollback else 'replay'), 'first committed winner or rollback admission')
            require(second['command']['epoch'] == EPOCH, 'original epoch retained')
            if not rollback:
                require(second['command'] == first['command'], 'immutable first winner')
            counts(1, 1)
            result['cases'].append('admit-rollback-waiter-admits' if rollback else 'two-admits-one-identity')

        for reset_first in [True, False]:
            for rollback in [False, True]:
                setup()
                a.command('BEGIN')
                first = a.query(reset if reset_first else admit)
                require(first.get('reset') is True if reset_first else first.get('action') == 'admitted', 'first reset/admission really succeeded')
                marker = b.send(admit if reset_first else reset)
                blocked(a, b)
                a.command('ROLLBACK' if rollback else 'COMMIT')
                second = b.receive(marker)
                if reset_first and rollback:
                    require(second['action'] == 'admitted' and second['command']['epoch'] == EPOCH, 'rolled-back reset keeps original queue epoch valid')
                    counts(1, 1)
                else:
                    require(second == {'action': 'stale_epoch'} if reset_first else second.get('reset') is True, 'committed reset fences waiting or previous admission')
                    require(admin.query(admit) == {'action': 'stale_epoch'}, 'never retag original offline intent after reset')
                    expected_ids = 1 if not reset_first and not rollback else 0
                    counts(expected_ids, 0, reset_done=True)
                    if expected_ids:
                        epoch = admin.query('(SELECT epoch FROM private.workout_strength_authority_epochs WHERE user_id=' + lit(OWNER) + '::uuid)')
                        changed = admit.rsplit(lit(EPOCH), 1)[0] + lit(epoch) + '::uuid)'
                        require(admin.query(changed) == {'action': 'stale_epoch'}, 'tombstone cannot reacquire new epoch')
                result['cases'].append(('reset-first-' if reset_first else 'admit-first-') + ('rollback' if rollback else 'commit'))
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
            error = RuntimeError('fenced admission race cleanup failed: ' + ','.join(type(item).__name__ for item in cleanup_errors))
            error.cleanup_errors = tuple(cleanup_errors)
            raise error from (primary_error or cleanup_errors[0])
    require(result['cleanup'] and result['actors_reaped'], 'synthetic owner removed and actors reaped')
    return result
