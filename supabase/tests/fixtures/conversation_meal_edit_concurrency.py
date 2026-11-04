"""Bounded real-PG direct Save/Undo races. Import is inert; guarded local only.
Synthetic auth.users rows prove C11 linkage, not a GoTrue login or public route.
"""
import importlib.util
import json
from pathlib import Path
import sys
import time

OWNER = 'c3eb0000-0000-4000-8000-000000000001'
AUTH = 'c3eb0000-0000-4000-8000-000000000002'
COMMAND = 'c3eb0000-0000-4000-8000-000000000003'
SAVE = 'c3eb0000-0000-4000-8000-000000000004'
UNDO = 'c3eb0000-0000-4000-8000-000000000005'
OTHER = 'c3eb0000-0000-4000-8000-000000000006'


def run(config):
    if config.get('ownership_verified') is not True:
        raise AssertionError('owned local target guard required')
    spec = importlib.util.spec_from_file_location('edit_actor', Path(__file__).with_name('conversation_meal_command_journal_concurrency.py'))
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    Actor, lit, require = module.Actor, module.lit, module.require
    actors = []
    admin = None
    owns_owner = False
    result = {'cases': [], 'cleanup': False, 'actors_reaped': False}
    owner_args = lit(OWNER) + '::uuid,' + lit(COMMAND) + '::uuid,'
    read = 'public.read_conversation_meal_edit_state(' + owner_args[:-1] + ')'
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
        raise AssertionError('actual direct-edit owner-lane blocking not observed')

    def setup():
        admin.command('DELETE FROM public.users WHERE id=' + lit(OWNER) + '::uuid')
        admin.command('DELETE FROM auth.users WHERE id=' + lit(AUTH) + '::uuid')
        effect = admin.query('pg_temp.edit_seed(' + lit(OWNER) + '::uuid,' + lit(AUTH) + '::uuid,' + lit(COMMAND) + '::uuid)')
        return effect, admin.query(read)

    def sql(kind, op, state, anchor=None, target=None):
        args = lit(kind) + ',' + str(state['revision']) + ',' + (lit(anchor) + '::uuid' if anchor else 'NULL') + ',' + (lit(target) + '::uuid' if target else 'NULL')
        body = admin.query('pg_temp.edit_input(' + args + ')')
        suffix = lit(op) + '::uuid,' + lit(json.dumps(body)) + '::jsonb,' + lit(json.dumps(state['current_state'])) + '::jsonb,'
        if kind == 'save':
            return 'public.commit_conversation_meal_item_edit(' + owner_args + suffix + "pg_temp.edit_quantity(),'quantity_only','{\"quantity_g\":200}'::jsonb,'synthetic-race')"
        function = 'undo_conversation_meal_item_edit' if kind == 'undo_save' else 'undo_conversation_meal_registration'
        return 'public.' + function + '(' + owner_args + suffix + "'synthetic-race')"

    def counts(ids, bodies, revision, logs=1, reset_done=False):
        actual = admin.query('json_build_array((SELECT count(*) FROM private.conversation_meal_edit_ids WHERE user_id=' + lit(OWNER) + '::uuid),(SELECT count(*) FROM private.conversation_meal_edit_operations WHERE user_id=' + lit(OWNER) + '::uuid),(SELECT coalesce(max(revision),0) FROM private.conversation_meal_edit_heads WHERE user_id=' + lit(OWNER) + '::uuid),(SELECT count(*) FROM public.meal_logs WHERE user_id=' + lit(OWNER) + '::uuid),(SELECT count(*) FROM public.workout_logs WHERE user_id=' + lit(OWNER) + '::uuid),(SELECT count(*) FROM private.workout_strength_lifecycles WHERE user_id=' + lit(OWNER) + '::uuid),(SELECT count(*) FROM public.user_progress WHERE user_id=' + lit(OWNER) + '::uuid))')
        require(actual == [ids, bodies, revision, logs, 0, 0, 1 if reset_done else 0], 'exact edit/domain/progress counts: ' + str(actual))
        if reset_done:
            require(admin.query('EXISTS(SELECT 1 FROM public.user_progress WHERE user_id=' + lit(OWNER) + '::uuid AND xp_total=0 AND level=1 AND blocks_completed=0 AND deficit_block=0)'), 'reset retains only its existing zero progress baseline')

    try:
        admin = spawn()
        a = spawn()
        b = spawn()
        require(admin.query('NOT EXISTS(SELECT 1 FROM public.users WHERE id=' + lit(OWNER) + '::uuid) AND NOT EXISTS(SELECT 1 FROM auth.users WHERE id=' + lit(AUTH) + '::uuid)'), 'preserve colliding owner/auth namespaces')
        owns_owner = True
        directory = Path(__file__).parent
        helpers = (directory / 'conversation_meal_atomic_writer_fixture.sql').read_text() + '\n' + '\n'.join(line for line in (directory / 'conversation_meal_edit_fixture.sql').read_text().splitlines() if not line.startswith('\\ir '))
        for actor in actors:
            actor.command(helpers)

        for rollback, same_op in [(False, True), (True, True), (False, False)]:
            effect, state = setup()
            first_sql = sql('save', SAVE, state, effect['log_ids'][0])
            second_sql = first_sql if same_op else sql('save', OTHER, state, effect['log_ids'][0])
            a.command('BEGIN')
            first = a.query(first_sql)
            require(first['action'] == 'committed', 'first Save really succeeded')
            marker = b.send(second_sql)
            blocked(a, b)
            a.command('ROLLBACK' if rollback else 'COMMIT')
            second = b.receive(marker)
            expected = 'committed' if rollback else 'replay' if same_op else 'version_conflict'
            require(second['action'] == expected, 'Save CAS/first winner after committed or rolled-back competitor')
            if not rollback and same_op:
                require(second == dict(first, action='replay'), 'Save replay exact original receipt')
            counts(1, 1, 1)
            result['cases'].append('save-' + ('rollback' if rollback else 'same-op' if same_op else 'different-op'))

        for kind, rollback in [('undo_registration', False), ('undo_save', False), ('undo_save', True)]:
            effect, state = setup()
            prior = 0
            if kind == 'undo_save':
                require(admin.query(sql('save', SAVE, state, effect['log_ids'][0]))['action'] == 'committed', 'setup actual Save committed')
                state = admin.query(read)
                prior = 1
            first_sql = sql(kind, UNDO, state, target=SAVE if prior else None)
            same_op = kind == 'undo_save'
            second_sql = first_sql if same_op else sql(kind, OTHER, state)
            a.command('BEGIN')
            first = a.query(first_sql)
            require(first['action'] == 'committed', 'first Undo really succeeded')
            marker = b.send(second_sql)
            blocked(a, b)
            a.command('ROLLBACK' if rollback else 'COMMIT')
            second = b.receive(marker)
            require(second['action'] == ('committed' if rollback else 'replay' if same_op else 'version_conflict'), 'one immutable compensation only')
            counts(prior + 1, prior + 1, prior + 1, logs=1 if prior else 0)
            result['cases'].append(kind + ('-rollback' if rollback else '-commit'))

        for kind in ['save', 'undo_registration', 'undo_save']:
            for reset_first in [True, False]:
                effect, state = setup()
                prior = 0
                if kind == 'undo_save':
                    admin.query(sql('save', SAVE, state, effect['log_ids'][0]))
                    state = admin.query(read)
                    prior = 1
                operation = sql(kind, UNDO, state, effect['log_ids'][0] if kind == 'save' else None, SAVE if prior else None)
                a.command('BEGIN')
                first = a.query(reset if reset_first else operation)
                require(first.get('reset') is True if reset_first else first.get('action') == 'committed', 'first reset/edit operation actually succeeded')
                marker = b.send(operation if reset_first else reset)
                blocked(a, b)
                a.command('COMMIT')
                second = b.receive(marker)
                require(second == {'action': 'stale_epoch'} if reset_first else second.get('reset') is True, 'reset fences both serialized directions')
                require(admin.query(operation) == {'action': 'stale_epoch'} and admin.query(read) == {'action': 'stale_epoch'}, 'reset before every late replay/private read')
                counts(prior + (0 if reset_first else 1), 0, 0, logs=0, reset_done=True)
                result['cases'].append(('reset-before-' if reset_first else 'reset-after-') + kind)

        effect, state = setup()
        admin.query(sql('save', SAVE, state, effect['log_ids'][0]))
        state = admin.query(read)
        undo = sql('undo_save', UNDO, state, target=SAVE)
        a.command('BEGIN')
        require(a.query(reset).get('reset') is True, 'actual reset before rollback')
        marker = b.send(undo)
        blocked(a, b)
        a.command('ROLLBACK')
        require(b.receive(marker)['action'] == 'committed', 'rolled-back reset preserves source/audit/beforeimage for compensation')
        counts(2, 2, 2)
        result['cases'].append('reset-rollback-then-undo')

        effect, state = setup()
        admin.command('SELECT pg_temp.edit_deadline_fixture(' + owner_args + lit(SAVE) + "::uuid,clock_timestamp()+interval '300 milliseconds')")
        state = admin.query(read)
        undo = sql('undo_save', UNDO, state, target=SAVE)
        before = admin.query('pg_temp.edit_fingerprint(' + lit(OWNER) + '::uuid)')
        a.command('BEGIN')
        require(a.query('private.lock_conversation_meal(' + owner_args[:-1] + ')') == 'current', 'actual owner lane held before deadline waiter')
        marker = b.send(undo)
        blocked(a, b)
        admin.command('SELECT pg_sleep(0.35)')
        a.command('COMMIT')
        require(b.receive(marker) == {'action': 'undo_expired'}, 'server clock refreshed after actual lock wait')
        require(admin.query('pg_temp.edit_fingerprint(' + lit(OWNER) + '::uuid)') == before, 'expired waiter has no compensation/receipt')
        counts(1, 1, 1)
        result['cases'].append('deadline-crosses-owner-lock-wait')

        effect, state = setup()
        admin.query(sql('save', SAVE, state, effect['log_ids'][0]))
        state = admin.query(read)
        anchor = state['current_state']['items'][0]['id']
        legacy = 'public.mutate_mobile_confirmed_meal(' + lit(OWNER) + "::uuid,'synthetic-edit-race-legacy','PATCH'," + lit('/api/mobile/v1/meal-records/' + anchor) + ',' + lit('b' * 64) + ',' + lit(anchor) + '::uuid,' + lit('v1:' + 'a' * 64) + ',ARRAY[' + lit(anchor) + '::uuid],' + lit(json.dumps(state['current_state'])) + "::jsonb,pg_temp.edit_quantity(),'recalculated',NULL,'external-same-facts')"
        undo = sql('undo_save', UNDO, state, target=SAVE)
        a.command('BEGIN')
        require(a.query(legacy)['action'] == 'completed', 'legacy C11 really replaced physical ID')
        marker = b.send(undo)
        blocked(a, b)
        a.command('COMMIT')
        require(b.receive(marker) == {'action': 'version_conflict'}, 'legacy owner share lock then stale group cannot be compensated')
        require(admin.query(read)['lineage_compatible'] is False, 'legacy equal facts still invalidate physical generation')
        counts(1, 1, 1)
        result['cases'].append('legacy-c11-before-undo-physical-cas')

        effect, state = setup()
        admin.query(sql('save', SAVE, state, effect['log_ids'][0]))
        state = admin.query(read)
        undo = sql('undo_save', UNDO, state, target=SAVE)
        b.command("CREATE FUNCTION pg_temp.catch_edit_lock(q text) RETURNS jsonb LANGUAGE plpgsql AS $$ DECLARE v jsonb;BEGIN EXECUTE 'SELECT '||q INTO v;RETURN v;EXCEPTION WHEN lock_not_available THEN RETURN '{\"lock_not_available\":true}'::jsonb;END $$")
        a.command('BEGIN')
        a.command('UPDATE public.daily_snapshots SET day_closed=true WHERE user_id=' + lit(OWNER) + '::uuid')
        require(b.query('pg_temp.catch_edit_lock(' + lit(undo) + ')') == {'lock_not_available': True}, 'snapshot day lock refuses without waiting or mutation')
        a.command('COMMIT')
        state = admin.query(read)
        require(admin.query(sql('undo_save', UNDO, state, target=SAVE)) == {'action': 'day_closed'}, 'fresh closed-day state still refuses')
        counts(1, 1, 1)
        result['cases'].append('concurrent-day-snapshot-nowait-then-closed')
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
                    admin.command('DELETE FROM auth.users WHERE id=' + lit(AUTH) + '::uuid')
                    result['cleanup'] = admin.query('NOT EXISTS(SELECT 1 FROM public.users WHERE id=' + lit(OWNER) + '::uuid) AND NOT EXISTS(SELECT 1 FROM auth.users WHERE id=' + lit(AUTH) + '::uuid) AND NOT EXISTS(SELECT 1 FROM private.conversation_meal_edit_ids WHERE user_id=' + lit(OWNER) + '::uuid)')
            except BaseException as error:
                cleanup_errors.append(error)
            finally:
                reap(admin)
        result['actors_reaped'] = all(not hasattr(actor, 'process') or actor.process.poll() is not None and (getattr(actor, 'reader', None) is None or not actor.reader.is_alive()) for actor in actors)
        if cleanup_errors:
            error = RuntimeError('direct edit race cleanup failed: ' + ','.join(type(item).__name__ for item in cleanup_errors))
            error.cleanup_errors = tuple(cleanup_errors)
            raise error from (primary_error or cleanup_errors[0])
    require(result['cleanup'] and result['actors_reaped'], 'synthetic owner removed and actors reaped')
    return result
