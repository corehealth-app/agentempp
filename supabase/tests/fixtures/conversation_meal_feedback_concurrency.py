"""Real-PG command feedback races. Inert import; no database/cloud lifecycle.
The external owned-local guard supplies credentials only in memory. Every actor
is tracked before initialization; only a proven task-created owner is removed.
"""
import importlib.util
import json
from pathlib import Path
import sys
import time

OWNER = 'c3f10000-0000-4000-8000-000000000001'
COMMAND = 'c3f10000-0000-4000-8000-000000000002'


def run(config):
    if config.get('ownership_verified') is not True:
        raise AssertionError('owned local target guard required')
    spec = importlib.util.spec_from_file_location('feedback_actor', Path(__file__).with_name('conversation_meal_command_journal_concurrency.py'))
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    Actor, lit, require = module.Actor, module.lit, module.require
    actors = []
    owns_owner = False
    result = {'cases': [], 'cleanup': False, 'actors_reaped': False}

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
        raise AssertionError('actual shared owner-lane blocker not observed')

    def setup():
        admin.command('DELETE FROM public.users WHERE id=' + lit(OWNER) + '::uuid')
        admin.command("INSERT INTO public.users(id,email,status,timezone,country,country_confirmed) VALUES(" + lit(OWNER) + "::uuid,'command-feedback-race@example.invalid','active','UTC','BR',true)")
        effect = admin.query('pg_temp.feedback_seed(' + lit(OWNER) + '::uuid,' + lit(COMMAND) + '::uuid)')['receipt']
        source = admin.query('public.read_conversation_meal_feedback_source(' + lit(OWNER) + '::uuid,' + lit(COMMAND) + '::uuid)')
        feedback = admin.query('pg_temp.command_feedback(' + lit(json.dumps(source['context'])) + '::jsonb)')
        seal = 'public.commit_conversation_meal_feedback_v2(' + lit(OWNER) + '::uuid,' + lit(COMMAND) + '::uuid,' + lit(effect['effect_version']) + ',' + lit(json.dumps(feedback)) + '::jsonb)'
        legacy = 'pg_temp.command_seal_legacy(' + lit(OWNER) + '::uuid,' + lit(effect['registration_id']) + '::uuid,' + lit(json.dumps(source['context']['confirmed']['proposal'])) + '::jsonb)'
        return source, feedback, seal, legacy

    def counts(meals, v2, v1):
        actual = admin.query('json_build_array((SELECT count(*) FROM public.meal_logs WHERE user_id=' + lit(OWNER) + '::uuid),(SELECT count(*) FROM private.mobile_registration_feedback_v2 WHERE user_id=' + lit(OWNER) + '::uuid),(SELECT count(*) FROM private.mobile_registration_feedback WHERE user_id=' + lit(OWNER) + '::uuid))')
        require(actual == [meals, v2, v1], 'exact one domain effect and first-version receipt counts')

    read = 'public.read_conversation_meal_feedback_v2(' + lit(OWNER) + '::uuid,' + lit(COMMAND) + '::uuid)'
    reset = 'public.reset_user_conversation_atomic(' + lit(OWNER) + '::uuid,true)'
    admin = None
    try:
        admin = spawn()
        a = spawn()
        b = spawn()
        require(admin.query('NOT EXISTS(SELECT 1 FROM public.users WHERE id=' + lit(OWNER) + '::uuid)'), 'synthetic owner unused; collision must preserve unknown rows')
        owns_owner = True
        directory = Path(__file__).parent
        helpers = (directory / 'conversation_meal_atomic_writer_fixture.sql').read_text()
        helpers += '\n' + '\n'.join(line for line in (directory / 'conversation_meal_feedback_fixture.sql').read_text().splitlines() if not line.startswith('\\ir '))
        for actor in actors:
            actor.command(helpers)

        source, feedback, seal, legacy = setup()
        a.command('BEGIN')
        first = a.query(seal)
        require(b.query(read) == {'action': 'absent'}, 'read cannot see or wait on uncommitted receipt')
        require(b.query('public.read_conversation_meal_feedback_source(' + lit(OWNER) + '::uuid,' + lit(COMMAND) + '::uuid)') == source, 'source read stays immutable during seal')
        marker = b.send(seal)
        blocked(a, b)
        a.command('COMMIT')
        second = b.receive(marker)
        require(first == {'action': 'committed', 'feedback': feedback} and second == {'action': 'replay', 'feedback': feedback}, 'two sessions seal exactly once')
        counts(1, 1, 0)
        result['cases'].append('same-command-seal-replay-one-receipt')

        source, feedback, seal, legacy = setup()
        a.command('BEGIN')
        first = a.query(seal)
        marker = b.send(seal)
        blocked(a, b)
        a.command('ROLLBACK')
        require(b.receive(marker) == {'action': 'committed', 'feedback': feedback}, 'rolled-back first seal does not steal receipt')
        counts(1, 1, 0)
        result['cases'].append('first-seal-rollback-waiter-commits')

        for legacy_first in [True, False]:
            source, feedback, seal, legacy = setup()
            a.command('BEGIN')
            first = a.query(legacy if legacy_first else seal)
            marker = b.send(seal if legacy_first else legacy)
            blocked(a, b)
            a.command('COMMIT')
            second = b.receive(marker)
            require(first['action'] == 'committed', 'first version commits')
            if legacy_first:
                require(second == {'action': 'legacy', 'feedback': first['feedback']}, 'v1 wins and v2 does not redraw')
                counts(1, 0, 1)
            else:
                require(second == {'action': 'event_conflict'}, 'v2 wins before v1 phrase effects')
                counts(1, 1, 0)
                require(admin.query('(public.read_flow_shared_phrase_cursor(' + lit(OWNER) + "::uuid)->>'cursor_revision')='0'") is True, 'losing v1 has no phrase draw')
            result['cases'].append('v1-first-v2-legacy' if legacy_first else 'v2-first-v1-fenced')

        for reset_first in [True, False]:
            source, feedback, seal, legacy = setup()
            a.command('BEGIN')
            first = a.query(reset if reset_first else seal)
            marker = b.send(seal if reset_first else reset)
            blocked(a, b)
            a.command('COMMIT')
            second = b.receive(marker)
            require(second == {'action': 'stale_epoch'} if reset_first else first['action'] == 'committed' and second['reset'] is True, 'reset and seal serialize')
            require(admin.query(seal) == {'action': 'stale_epoch'}, 'old UUID cannot restore health receipt')
            counts(0, 0, 0)
            result['cases'].append('reset-before-seal' if reset_first else 'seal-before-reset')
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
            if actor is admin:
                continue
            if hasattr(actor, 'process'):
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
            error = RuntimeError('feedback race cleanup failed: ' + ','.join(type(item).__name__ for item in cleanup_errors))
            error.cleanup_errors = tuple(cleanup_errors)
            raise error from (primary_error or cleanup_errors[0])
    require(result['cleanup'] and result['actors_reaped'], 'synthetic rows removed; all actors reaped')
    return result
