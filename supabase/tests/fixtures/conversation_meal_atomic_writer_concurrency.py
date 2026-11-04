"""Real PostgreSQL two-session atomic meal cases; inert import, no PG lifecycle.
External owned-local guard supplies psql_args/env. Synthetic owner is removed and
all actors reaped before success. Uses the journal fixture's bounded psql Actor.
"""
import importlib.util
import json
from pathlib import Path
import time

OWNER = 'c3d00000-0000-4000-8000-000000000001'
COMMAND = 'c3d00000-0000-4000-8000-000000000002'
SECOND = 'c3d00000-0000-4000-8000-000000000003'


def run(config):
    if config.get('ownership_verified') is not True:
        raise AssertionError('owned local target guard required')
    spec = importlib.util.spec_from_file_location('journal_actor', Path(__file__).with_name('conversation_meal_command_journal_concurrency.py'))
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    Actor, lit, require = module.Actor, module.lit, module.require
    admin, a, b = Actor(config), Actor(config), Actor(config)
    result = {'cases': [], 'cleanup': False, 'actors_reaped': False}

    def setup():
        admin.command('DELETE FROM public.users WHERE id=' + lit(OWNER) + '::uuid')
        admin.command("INSERT INTO public.users(id,email,status,timezone,country,country_confirmed) VALUES(" + lit(OWNER) + "::uuid,'atomic-race@example.invalid','active','UTC','BR',true)")

    def prepare(command):
        value = {'command_protocol': 'conversation.command.v1', 'command_id': command, 'kind': 'meal.report', 'meal_type': 'almoco', 'source': {'channel': 'text', 'text': 'Comi 100g de arroz sintetico'}}
        require(admin.query('public.admit_conversation_meal_command(' + lit(OWNER) + '::uuid,' + lit(json.dumps(value)) + "::jsonb)")['action'] == 'admitted', 'new UUID admission')
        src = admin.query('public.capture_conversation_meal_source(' + lit(OWNER) + '::uuid,' + lit(command) + '::uuid)')
        proof = {'schema': 'conversation.meal-semantic.v1', 'decision': 'consumed_meal', 'input_hash': src['context']['input_hash'], 'source_hash': src['source_hash'], 'complete_source': True, 'source_units': src['context']['source_units'], 'input_count': 1}
        value = {'schema': 'conversation.meal-resolved.v1', 'input_hash': src['context']['input_hash'], 'source_hash': src['source_hash'], 'meal_type': 'almoco', 'semantic_proof': proof,
            'items': [{'name': 'arroz sintetico', 'food_db_id': None, 'nutrition_source': 'user_kcal', 'quantity_g': 100, 'kcal': 130.04, 'protein_g': 2.31, 'carbs_g': 28.21, 'fat_g': .21, 'confidence': None, 'input_indexes': [0], 'quantity_basis': 'stated', 'display_qty': None, 'display_unit': None}],
            'totals': {'kcal': 130, 'protein_g': 2.3, 'carbs_g': 28.2, 'fat_g': .2}, 'preparation_annotations': [], 'source_receipts': []}
        prepared = admin.query('public.prepare_conversation_meal(' + lit(OWNER) + '::uuid,' + lit(command) + '::uuid,' + lit(json.dumps(value)) + '::jsonb)')
        require(prepared['action'] == 'prepared', 'authoritative resolved preparation')
        return 'public.commit_conversation_meal(' + lit(OWNER) + '::uuid,' + lit(command) + '::uuid,' + lit(prepared['resolved_hash']) + ')'

    def blocked(blocker, waiter):
        end = time.monotonic() + 3
        while time.monotonic() < end:
            if admin.query(str(blocker.pid) + '=ANY(pg_blocking_pids(' + str(waiter.pid) + '))'):
                return
            time.sleep(.02)
        raise AssertionError('actual owner-lane blocker not observed')

    def counts(meals, receipts):
        value = admin.query('json_build_array((SELECT count(*) FROM public.meal_logs WHERE user_id=' + lit(OWNER) + '::uuid),(SELECT count(*) FROM private.conversation_meal_effects WHERE user_id=' + lit(OWNER) + '::uuid))')
        require(value == [meals, receipts], 'exact domain + receipt counts')

    reset = 'public.reset_user_conversation_atomic(' + lit(OWNER) + '::uuid,true)'
    try:
        require(admin.query('NOT EXISTS(SELECT 1 FROM public.users WHERE id=' + lit(OWNER) + '::uuid)'), 'synthetic owner unused')
        setup()
        commit = prepare(COMMAND)
        a.command('BEGIN')
        first = a.query(commit)
        marker = b.send(commit)
        blocked(a, b)
        a.command('COMMIT')
        second = b.receive(marker)
        require(first['action'] == 'committed' and second == dict(first, action='replay'), 'same UUID exact one effect + exact original receipt')
        counts(1, 1)
        result['cases'].append('same-UUID-two-sessions-one-effect')
        setup()
        first_commit, second_commit = prepare(COMMAND), prepare(SECOND)
        a.command('BEGIN')
        first = a.query(first_commit)
        marker = b.send(second_commit)
        blocked(a, b)
        a.command('COMMIT')
        second = b.receive(marker)
        require(first['action'] == second['action'] == 'committed' and first['receipt']['provider_key'] != second['receipt']['provider_key'], 'two UUIDs append from same absent-day source')
        counts(2, 2)
        result['cases'].append('distinct-UUIDs-first-day-concurrent-append')
        for reset_first in [True, False]:
            setup()
            commit = prepare(COMMAND)
            a.command('BEGIN')
            first = a.query(reset if reset_first else commit)
            marker = b.send(commit if reset_first else reset)
            blocked(a, b)
            a.command('COMMIT')
            second = b.receive(marker)
            if reset_first:
                require(second == {'action': 'stale_epoch'}, 'reset fences waiter')
            else:
                require(first['action'] == 'committed' and second['reset'] is True, 'commit then reset completed')
            require(admin.query(commit) == {'action': 'stale_epoch'}, 'completed or prepared UUID never reacquires epoch')
            counts(0, 0)
            result['cases'].append('reset-before-commit' if reset_first else 'commit-before-reset')
    finally:
        a.close()
        b.close()
        admin.command('DELETE FROM public.users WHERE id=' + lit(OWNER) + '::uuid')
        result['cleanup'] = admin.query('NOT EXISTS(SELECT 1 FROM public.users WHERE id=' + lit(OWNER) + '::uuid) AND NOT EXISTS(SELECT 1 FROM private.conversation_meal_command_ids WHERE user_id=' + lit(OWNER) + '::uuid)')
        admin.close()
        result['actors_reaped'] = all(x.process.poll() is not None and not x.reader.is_alive() for x in [admin, a, b])
    require(result['cleanup'] and result['actors_reaped'], 'fixtures removed and all actors reaped')
    return result
