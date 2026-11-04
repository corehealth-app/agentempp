"""Real-PG decision/preparation/reset races. Inert import; owned local only.

The caller must establish the exact retained stack and zero-data guard first.
Every waiter is proven blocked by pg_blocking_pids, not by elapsed time.
"""
import importlib.util
import json
from pathlib import Path
import sys
import time

OWNER = 'c3da0000-0000-4000-8000-000000000001'
AUTH = 'c3da0000-0000-4000-8000-000000000002'
COMMAND = 'c3da0000-0000-4000-8000-000000000003'


def run(config):
    if config.get('ownership_verified') is not True:
        raise AssertionError('owned local target guard required')
    spec = importlib.util.spec_from_file_location('decision_actor', Path(__file__).with_name('conversation_meal_command_journal_concurrency.py'))
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    Actor, lit, require = module.Actor, module.lit, module.require
    actors = []
    admin = None
    owns_owner = False
    result = {'cases': [], 'cleanup': False, 'actors_reaped': False}
    args = lit(OWNER) + '::uuid,' + lit(COMMAND) + '::uuid,'
    reset = 'public.reset_user_conversation_atomic(' + lit(OWNER) + '::uuid,true)'

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
        raise AssertionError('actual decision owner-lane blocking not observed')

    def setup():
        admin.command('DELETE FROM public.users WHERE id=' + lit(OWNER) + '::uuid')
        admin.command('DELETE FROM auth.users WHERE id=' + lit(AUTH) + '::uuid')
        seed = admin.query('pg_temp.decision_seed(' + lit(OWNER) + '::uuid,' + lit(AUTH) + '::uuid,' + lit(COMMAND) + '::uuid)')
        terminal = seed['terminal']
        read = 'public.read_conversation_meal_decision(' + args + lit(terminal['epoch']) + '::uuid,' + lit(terminal['input_hash']) + ')'
        seal = 'pg_temp.decision_seal(' + args + lit(json.dumps(seed)) + '::jsonb)'
        prepare = 'public.prepare_conversation_meal(' + args + 'pg_temp.writer_resolved(' + lit(json.dumps(seed['source'])) + '::jsonb))'
        return seed, read, seal, prepare

    def counts(decisions, resolved, after_reset=False):
        actual = admin.query('json_build_array((SELECT count(*) FROM private.conversation_meal_decisions WHERE user_id=' + lit(OWNER) + '::uuid),(SELECT count(*) FROM private.conversation_meal_resolved WHERE user_id=' + lit(OWNER) + '::uuid),(SELECT count(*) FROM public.meal_logs WHERE user_id=' + lit(OWNER) + '::uuid),(SELECT count(*) FROM public.pending_registrations WHERE user_id=' + lit(OWNER) + '::uuid),(SELECT count(*) FROM public.workout_logs WHERE user_id=' + lit(OWNER) + '::uuid),(SELECT count(*) FROM private.workout_strength_lifecycles WHERE user_id=' + lit(OWNER) + '::uuid),(SELECT count(*) FROM public.user_progress WHERE user_id=' + lit(OWNER) + '::uuid))')
        require(actual == [decisions, resolved, 0, 0, 0, 0, 1 if after_reset else 0], 'exact decision/preparation/domain counts: ' + str(actual))
        if after_reset:
            require(admin.query('EXISTS(SELECT 1 FROM public.user_progress WHERE user_id=' + lit(OWNER) + '::uuid AND xp_total=0 AND level=1 AND blocks_completed=0 AND deficit_block=0)'), 'only the existing reset zero baseline remains')

    try:
        admin = spawn()
        a = spawn()
        b = spawn()
        require(admin.query('NOT EXISTS(SELECT 1 FROM public.users WHERE id=' + lit(OWNER) + '::uuid) AND NOT EXISTS(SELECT 1 FROM auth.users WHERE id=' + lit(AUTH) + '::uuid)'), 'preserve a colliding synthetic owner/auth namespace')
        owns_owner = True
        directory = Path(__file__).parent
        helpers = (directory / 'conversation_meal_atomic_writer_fixture.sql').read_text()
        for name in ['conversation_meal_semantic_fixture.sql', 'conversation_meal_decision_fixture.sql']:
            helpers += '\n' + '\n'.join(line for line in (directory / name).read_text().splitlines() if not line.startswith('\\ir '))
        # Catch expected preparation refusal inside a subtransaction so the actor
        # transaction can still COMMIT, and inspect the actual SQLSTATE/message.
        helpers += """
CREATE FUNCTION pg_temp.decision_try_prepare(u uuid,c uuid,s jsonb) RETURNS jsonb LANGUAGE plpgsql AS $$
BEGIN RETURN public.prepare_conversation_meal(u,c,pg_temp.writer_resolved(s));
EXCEPTION WHEN serialization_failure THEN
 IF SQLERRM<>'conversation_meal_terminal_decision' THEN RAISE;END IF;
 RETURN jsonb_build_object('action','decision_fenced','sqlstate',SQLSTATE);END $$;
"""
        for actor in actors:
            actor.command(helpers)

        for rollback, changed in [(False, False), (True, False), (False, True)]:
            seed, read, seal, prepare = setup()
            second_sql = seal if not changed else 'pg_temp.decision_seal(' + args + lit(json.dumps(seed)) + "::jsonb,pg_temp.decision_payload('nutrition_unresolved'))"
            a.command('BEGIN')
            first = a.query(seal)
            require(first['action'] == 'sealed', 'first decision really sealed')
            require(b.query(read) == {'action': 'absent'}, 'STABLE read neither waits nor exposes uncommitted decision')
            marker = b.send(second_sql)
            blocked(a, b)
            a.command('ROLLBACK' if rollback else 'COMMIT')
            second = b.receive(marker)
            require(second['action'] == ('sealed' if rollback else 'decision_conflict' if changed else 'replay'), 'one immutable decision winner')
            if not rollback and not changed:
                require(second == dict(first, action='replay'), 'replay recovers exact first decision and command binding')
            counts(1, 0)
            result['cases'].append('two-seals-' + ('rollback' if rollback else 'different-body' if changed else 'exact-replay'))

        for decision_first in [True, False]:
            for rollback in [False, True]:
                seed, read, seal, prepare = setup()
                try_prepare = 'pg_temp.decision_try_prepare(' + args + lit(json.dumps(seed['source'])) + '::jsonb)'
                a.command('BEGIN')
                first = a.query(seal if decision_first else prepare)
                require(first['action'] == ('sealed' if decision_first else 'prepared'), 'first opposing operation really succeeded')
                marker = b.send(try_prepare if decision_first else seal)
                blocked(a, b)
                a.command('ROLLBACK' if rollback else 'COMMIT')
                second = b.receive(marker)
                expected = ('prepared' if decision_first else 'sealed') if rollback else ('decision_fenced' if decision_first else 'resolved_conflict')
                require(second['action'] == expected, 'decision and preparation cannot both commit')
                decision_won = decision_first != rollback
                counts(1 if decision_won else 0, 0 if decision_won else 1)
                result['cases'].append(('decision' if decision_first else 'prepare') + '-first-' + ('rollback' if rollback else 'commit'))

        for reset_first in [True, False]:
            for rollback in [False, True]:
                seed, read, seal, prepare = setup()
                a.command('BEGIN')
                first = a.query(reset if reset_first else seal)
                require(first.get('action') == 'sealed' if not reset_first else first is not None, 'first reset/decision operation actually returned success')
                if reset_first:
                    require(a.query('EXISTS(SELECT 1 FROM private.conversation_meal_command_ids WHERE user_id=' + lit(OWNER) + '::uuid AND invalidated_at IS NOT NULL)'), 'reset first really invalidated the command')
                marker = b.send(seal if reset_first else reset)
                blocked(a, b)
                a.command('ROLLBACK' if rollback else 'COMMIT')
                second = b.receive(marker)
                if reset_first:
                    require(second['action'] == ('sealed' if rollback else 'stale_epoch'), 'old command decision never crosses a committed reset')
                    counts(1 if rollback else 0, 0, after_reset=not rollback)
                else:
                    require(second is not None and admin.query(read) == {'action': 'stale_epoch'}, 'reset scrubs committed or rolled-back decision and fences replay')
                    counts(0, 0, after_reset=True)
                result['cases'].append(('reset' if reset_first else 'decision') + '-before-' + ('rollback' if rollback else 'commit'))

        seed, read, seal, prepare = setup()
        page = 'public.read_conversation_meal_journal_page(' + lit(OWNER) + '::uuid,' + lit(seed['terminal']['epoch']) + '::uuid)'
        barrier = '731104072910'
        a.command('BEGIN')
        a.query('pg_advisory_xact_lock(' + barrier + ') IS NULL')
        # Each STABLE page uses the outer statement snapshot even though the
        # real owner decision commits while this statement is at its barrier.
        expression = '(WITH first AS MATERIALIZED(SELECT ' + page + ' p),wait AS MATERIALIZED(SELECT pg_advisory_xact_lock(' + barrier + ') FROM first),last AS MATERIALIZED(SELECT ' + page + ' p FROM wait) SELECT json_build_object(\'before\',first.p,\'after\',last.p) FROM first,last)'
        marker = b.send(expression)
        blocked(a, b)
        require(admin.query(seal)['action'] == 'sealed', 'actual decision commits between page reads in one outer snapshot')
        a.command('COMMIT')
        snapshot = b.receive(marker)
        require(snapshot['before'] == snapshot['after'] and snapshot['before']['items'][0]['status'] == 'pending', 'one snapshot never mixes pending and newly sealed bodies')
        require(admin.query(page)['items'][0]['status'] == 'not_recorded', 'next statement sees the committed terminal decision')
        counts(1, 0)
        result['cases'].append('page-single-snapshot-across-concurrent-seal')
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
            error = AssertionError('decision race cleanup failed: ' + '; '.join(str(item) for item in errors))
            error.cleanup_errors = tuple(errors)
            if primary_error is not None:
                raise error from primary_error
            raise error
    return result
