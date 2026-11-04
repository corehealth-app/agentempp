"""Bounded real-PG one-attempt CAS races. Inert import, no provider/lifecycle.
Requires the external owned-local guard; only a proven synthetic owner is erased.
"""
import hashlib
import importlib.util
import json
from pathlib import Path
import sys
import time

OWNER = 'c3a50000-0000-4000-8000-000000000001'
COMMAND = 'c3a50000-0000-4000-8000-000000000002'
VERSION = 'conversation.meal-interpreter.v1'


def run(config):
    if config.get('ownership_verified') is not True:
        raise AssertionError('owned local target guard required')
    spec = importlib.util.spec_from_file_location('semantic_actor', Path(__file__).with_name('conversation_meal_command_journal_concurrency.py'))
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    Actor, lit, require = module.Actor, module.lit, module.require
    actors = []
    admin = None
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
        raise AssertionError('actual semantic owner-lane blocking not observed')

    def setup():
        admin.command('DELETE FROM public.users WHERE id=' + lit(OWNER) + '::uuid')
        admin.command("INSERT INTO public.users(id,email,status,timezone,country,country_confirmed) VALUES(" + lit(OWNER) + "::uuid,'semantic-race@example.invalid','active','UTC','BR',true)")
        src = admin.query('pg_temp.writer_seed(' + lit(OWNER) + '::uuid,' + lit(COMMAND) + '::uuid)')
        start = 'public.start_conversation_meal_semantic_attempt(' + lit(OWNER) + '::uuid,' + lit(COMMAND) + '::uuid,' + lit(VERSION) + ',' + lit(src['source_hash']) + ')'
        return src, start

    def finish(claim, error=None):
        args = lit(OWNER) + '::uuid,' + lit(COMMAND) + '::uuid,' + lit(VERSION) + ',' + lit(claim['attempt_id']) + '::uuid,'
        if error is not None:
            return 'public.mark_conversation_meal_semantic_unknown(' + args + lit(error) + ')'
        payload = admin.query('pg_temp.semantic_result(' + lit(json.dumps(claim)) + '::jsonb)')
        return 'public.commit_conversation_meal_semantic_result(' + args + lit(json.dumps(payload)) + '::jsonb)'

    def counts(attempts, terminals, after_reset=False):
        actual = admin.query('json_build_array((SELECT count(*) FROM private.conversation_meal_semantic_attempts WHERE user_id=' + lit(OWNER) + '::uuid),(SELECT count(*) FROM private.conversation_meal_semantic_results WHERE user_id=' + lit(OWNER) + '::uuid),(SELECT count(*) FROM public.meal_logs WHERE user_id=' + lit(OWNER) + '::uuid),(SELECT count(*) FROM public.pending_registrations WHERE user_id=' + lit(OWNER) + '::uuid),(SELECT count(*) FROM public.workout_logs WHERE user_id=' + lit(OWNER) + '::uuid),(SELECT count(*) FROM public.user_progress WHERE user_id=' + lit(OWNER) + '::uuid))')
        expected = [attempts, terminals, 0, 0, 0, 1 if after_reset else 0]
        require(actual == expected, 'exact interpretation/domain counts: ' + str(actual) + ' expected ' + str(expected))
        if after_reset:
            require(admin.query('EXISTS(SELECT 1 FROM public.user_progress WHERE user_id=' + lit(OWNER) + '::uuid AND xp_total=0 AND level=1 AND blocks_completed=0 AND deficit_block=0)') is True, 'existing reset creates its zero progress baseline without semantic credit')

    read = 'public.read_conversation_meal_semantic_attempt(' + lit(OWNER) + '::uuid,' + lit(COMMAND) + '::uuid,' + lit(VERSION) + ')'
    reset = 'public.reset_user_conversation_atomic(' + lit(OWNER) + '::uuid,true)'
    try:
        admin = spawn()
        a = spawn()
        b = spawn()
        require(admin.query('NOT EXISTS(SELECT 1 FROM public.users WHERE id=' + lit(OWNER) + '::uuid)'), 'preserve collision: synthetic owner must be unused')
        owns_owner = True
        directory = Path(__file__).parent
        helpers = (directory / 'conversation_meal_atomic_writer_fixture.sql').read_text()
        helpers += '\n' + '\n'.join(line for line in (directory / 'conversation_meal_semantic_fixture.sql').read_text().splitlines() if not line.startswith('\\ir '))
        for actor in actors:
            actor.command(helpers)

        src, start = setup()
        a.command('BEGIN')
        first = a.query(start)
        require(b.query(read) == {'action': 'absent'}, 'read never waits for or sees uncommitted permission')
        marker = b.send(start)
        blocked(a, b)
        a.command('COMMIT')
        second = b.receive(marker)
        require(first['action'] == 'claimed' and second == dict(first, action='reconciliation_required'), 'exact one committed claim, same original attempt')
        counts(1, 0)
        result['cases'].append('two-starts-one-committed-permission')

        src, start = setup()
        a.command('BEGIN')
        first = a.query(start)
        marker = b.send(start)
        blocked(a, b)
        a.command('ROLLBACK')
        second = b.receive(marker)
        require(second['action'] == 'claimed' and second['attempt_id'] != first['attempt_id'], 'rollback grants no legitimate committed permission')
        counts(1, 0)
        result['cases'].append('start-rollback-waiter-new-permission')

        for winner in ['completed', 'unknown', 'error']:
            src, start = setup()
            claim = admin.query(start)
            success = finish(claim)
            failure = finish(claim, 'provider_outcome_unknown' if winner != 'error' else 'provider_terminal_error')
            a.command('BEGIN')
            first = a.query(success if winner == 'completed' else failure)
            marker = b.send(failure if winner == 'completed' else success)
            blocked(a, b)
            a.command('COMMIT')
            second = b.receive(marker)
            require(first['action'] == 'committed' and first['status'] == winner and second == dict(first, action='replay'), 'first terminal wins and cannot be overwritten')
            if winner == 'completed':
                canonical = json.dumps(first['result'], sort_keys=True, separators=(',', ':'), ensure_ascii=False)
                require(hashlib.sha256(canonical.encode()).hexdigest() == first['result_hash'], 'independent compact hash of this integer/plain-decimal fixture')
            counts(1, 1)
            result['cases'].append('first-terminal-' + winner)

        src, start = setup()
        claim = admin.query(start)
        a.command('BEGIN')
        first = a.query(finish(claim))
        marker = b.send(finish(claim, 'provider_outcome_unknown'))
        blocked(a, b)
        a.command('ROLLBACK')
        second = b.receive(marker)
        require(second['action'] == 'committed' and second['status'] == 'unknown', 'rolled-back result cannot steal terminal')
        counts(1, 1)
        result['cases'].append('terminal-rollback-waiter-wins')

        for phase in ['start', 'finish']:
            for reset_first in [True, False]:
                src, start = setup()
                operation = start if phase == 'start' else finish(admin.query(start))
                a.command('BEGIN')
                first = a.query(reset if reset_first else operation)
                require(first['reset'] is True if reset_first else first['action'] == ('claimed' if phase == 'start' else 'committed'), 'first reset/semantic operation really succeeded')
                marker = b.send(operation if reset_first else reset)
                blocked(a, b)
                a.command('COMMIT')
                second = b.receive(marker)
                require(second == {'action': 'stale_epoch'} if reset_first else second['reset'] is True, 'reset fences both sides of semantic operation')
                require(admin.query(start) == {'action': 'stale_epoch'} and admin.query(read) == {'action': 'stale_epoch'}, 'old UUID never returns another permission or private body')
                counts(0, 0, after_reset=True)
                result['cases'].append(('reset-before-' if reset_first else 'reset-after-') + phase)

        src, start = setup()
        claim = admin.query(start)
        a.command('BEGIN')
        first = a.query(reset)
        marker = b.send(finish(claim))
        blocked(a, b)
        a.command('ROLLBACK')
        second = b.receive(marker)
        require(second['action'] == 'committed' and second['status'] == 'completed' and second['attempt_id'] == claim['attempt_id'], 'rolled-back reset preserves original attempt for late response')
        counts(1, 1)
        result['cases'].append('reset-rollback-late-finish')
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
            error = RuntimeError('semantic race cleanup failed: ' + ','.join(type(item).__name__ for item in cleanup_errors))
            error.cleanup_errors = tuple(cleanup_errors)
            raise error from (primary_error or cleanup_errors[0])
    require(result['cleanup'] and result['actors_reaped'], 'all synthetic data removed and actors reaped')
    return result
