"""Actual private/legacy admission races in a caller-proven owned local copy.
Import is inert. No Storage, provider, cloud or process-lifecycle operation.
"""
import importlib.util
import json
from pathlib import Path
import time
import uuid


def run(config):
    if config.get('ownership_verified') is not True or config.get('disposable_local_copy') is not True:
        raise AssertionError('owned disposable local copy required')
    spec = importlib.util.spec_from_file_location('private_admission_actor', Path(__file__).with_name('conversation_meal_command_journal_concurrency.py'))
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    Actor, lit, require = module.Actor, module.lit, module.require
    actors = []
    admin = None
    owner, epoch, asset = str(uuid.uuid4()), str(uuid.uuid4()), str(uuid.uuid4())
    owns = False
    result = {'cases': [], 'cleanup': False, 'actors_reaped': False}

    def spawn():
        actor = Actor.__new__(Actor)
        try:
            Actor.__init__(actor, config)
        except BaseException:
            if hasattr(actor, 'process'):
                actor.close()
            raise
        actors.append(actor)
        return actor

    def admission(private, intake):
        raw = {'intake_protocol': 'conversation.intake.v1', 'intake_id': intake,
            'source': {'channel': 'media', 'media_asset_id': asset, 'user_action': 'report_actual_record'}}
        name = 'admit_conversation_versioned_media_intake_v2' if private else 'admit_conversation_intake'
        return 'public.' + name + '(' + lit(owner) + '::uuid,' + lit(epoch) + '::uuid,' + lit(json.dumps(raw)) + '::jsonb)'

    def blocked(blocker, waiter):
        deadline = time.monotonic() + 3
        while time.monotonic() < deadline:
            if admin.query(str(blocker.pid) + '=ANY(pg_blocking_pids(' + str(waiter.pid) + '))'):
                return
            time.sleep(.02)
        raise AssertionError('actual admission lock wait not observed')

    try:
        admin = spawn()
        a, b = spawn(), spawn()
        require(admin.query("current_database()=" + lit(config['database']) + " AND current_setting('listen_addresses')='' AND current_setting('cron.launch_active_jobs')='off' AND current_setting('pg_net.batch_size')='0'"), 'exact local target and outbound fence')
        require(admin.query('NOT EXISTS(SELECT 1 FROM public.users WHERE id=' + lit(owner) + '::uuid)'), 'unused synthetic owner')
        admin.command("INSERT INTO public.users(id,email,status,timezone,country,country_confirmed) VALUES(" + lit(owner) + "::uuid,'private-admission-" + owner + "@example.invalid','active','UTC','BR',true)")
        owns = True
        admin.command('INSERT INTO private.workout_strength_authority_epochs(user_id,epoch,changed_at) VALUES(' + lit(owner) + '::uuid,' + lit(epoch) + '::uuid,clock_timestamp())')
        admin.query('public.create_conversation_media_asset_v2(' + lit(owner) + '::uuid,' + lit(asset) + "::uuid,'audio_note','audio/mp4',8,NULL,repeat('e',64))")
        for private_first, private_second, rollback in [(True, True, False), (True, False, False), (False, True, False), (False, True, True), (True, False, True)]:
            intake = str(uuid.uuid4())
            a.command('BEGIN')
            first = a.query(admission(private_first, intake))
            require(first['action'] == ('admitted' if private_first else 'input_conflict'), 'old new-private-source caller cannot reserve a legacy intake')
            marker = b.send(admission(private_second, intake))
            blocked(a, b)
            a.command('ROLLBACK' if rollback else 'COMMIT')
            second = b.receive(marker)
            expected = ('replay' if private_first and not rollback else 'admitted') if private_second else ('replay' if private_first and not rollback else 'input_conflict')
            require(second['action'] == expected, 'waiter respects the original admission version')
            # A refused old caller leaves no immutable stub. A current retry
            # can still admit this same ID, including after a private rollback.
            expected_rows = 0 if expected == 'input_conflict' else 1
            require(admin.query('(SELECT count(*) FROM private.conversation_intake_ids WHERE user_id=' + lit(owner) + '::uuid AND intake_id=' + lit(intake) + '::uuid)') == expected_rows, 'refused old request leaves no intake row')
            if expected_rows == 0:
                require(admin.query(admission(True, intake))['action'] == 'admitted', 'current dispatcher resumes the exact refused intake ID')
            version2 = True
            count = admin.query('(SELECT count(*) FROM private.conversation_private_media_intakes_v2 WHERE user_id=' + lit(owner) + '::uuid AND intake_id=' + lit(intake) + '::uuid AND asset_id=' + lit(asset) + '::uuid)')
            require(count == (1 if version2 else 0), 'exact one immutable binding or permanent legacy admission')
            require(admin.query('(SELECT count(*) FROM private.conversation_intake_ids WHERE user_id=' + lit(owner) + '::uuid AND intake_id=' + lit(intake) + '::uuid)') == 1, 'one logical intake')
            result['cases'].append({'private_holder': private_first, 'private_waiter': private_second,
                'holder_rollback': rollback, 'waiter_action': expected, 'catalog_version': 2 if version2 else 1})
        require(admin.query('NOT EXISTS(SELECT 1 FROM public.media_assets WHERE id=' + lit(asset) + '::uuid) AND NOT EXISTS(SELECT 1 FROM public.meal_logs WHERE user_id=' + lit(owner) + '::uuid) AND NOT EXISTS(SELECT 1 FROM public.workout_logs WHERE user_id=' + lit(owner) + '::uuid)'), 'no public mirror or domain registration')
        return result
    finally:
        for actor in actors[1:]:
            actor.close()
        if admin is not None:
            if owns:
                admin.command('DELETE FROM private.conversation_intake_ids WHERE user_id=' + lit(owner) + '::uuid')
                admin.command('DELETE FROM private.conversation_media_assets_v2 WHERE id=' + lit(asset) + '::uuid AND user_id=' + lit(owner) + '::uuid')
                admin.command('DELETE FROM private.conversation_media_identity_v2 WHERE asset_id=' + lit(asset) + '::uuid')
                admin.command('DELETE FROM public.users WHERE id=' + lit(owner) + '::uuid')
                result['cleanup'] = admin.query('NOT EXISTS(SELECT 1 FROM public.users WHERE id=' + lit(owner) + '::uuid) AND NOT EXISTS(SELECT 1 FROM private.conversation_private_media_intakes_v2 WHERE user_id=' + lit(owner) + '::uuid)')
                require(result['cleanup'], 'exact synthetic admission cleanup')
            admin.close()
        result['actors_reaped'] = all(actor.process.poll() is not None for actor in actors)
