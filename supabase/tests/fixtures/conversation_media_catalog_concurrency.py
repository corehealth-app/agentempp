"""Real local-PG catalog namespace races. Import is inert.

The caller must prove an owned, disposable, network-disabled local database.
No Storage, API, Auth, provider or process lifecycle operations are performed.
"""
import importlib.util
import json
from pathlib import Path
import time
import uuid


def run(config):
    if config.get('ownership_verified') is not True or config.get('disposable_local_copy') is not True:
        raise AssertionError('owned disposable local copy required')
    spec = importlib.util.spec_from_file_location('catalog_actor', Path(__file__).with_name('conversation_meal_command_journal_concurrency.py'))
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    Actor, lit, require = module.Actor, module.lit, module.require
    actors, identities = [], []
    owner = str(uuid.uuid4())
    result = {'cases': [], 'cleanup': False, 'actors_reaped': False}
    admin = None
    owns_owner = False

    def spawn():
        actor = Actor.__new__(Actor)
        actors.append(actor)
        Actor.__init__(actor, config)
        return actor

    def fresh():
        value = str(uuid.uuid4())
        require(admin.query('NOT EXISTS(SELECT 1 FROM public.media_assets WHERE id=' + lit(value) + '::uuid) AND NOT EXISTS(SELECT 1 FROM private.conversation_media_identity_v2 WHERE asset_id=' + lit(value) + '::uuid)'), 'unused synthetic opaque ID')
        identities.append(value)
        return value

    def install(actor):
        actor.command("CREATE FUNCTION pg_temp.legacy_catalog(a uuid) RETURNS text LANGUAGE plpgsql AS $$ BEGIN INSERT INTO public.media_assets(id,user_id,kind,bucket_id,object_path,mime_type,declared_size_bytes,status,source_request_hash,retention_until) VALUES(a," + lit(owner) + "::uuid,'audio_note','audio-notes'," + lit(owner) + "||'/'||a::text||'.m4a','audio/mp4',8,'pending_upload',encode(sha256(convert_to(a::text,'UTF8')),'hex'),clock_timestamp()+interval '1day'); RETURN 'saved'; EXCEPTION WHEN serialization_failure THEN RETURN 'namespace_refused'; END $$")
        actor.command("CREATE FUNCTION pg_temp.private_catalog(a uuid,h text) RETURNS jsonb LANGUAGE plpgsql AS $$ BEGIN RETURN public.create_conversation_media_asset_v2(" + lit(owner) + "::uuid,a,'audio_note','audio/mp4',8,NULL,h); EXCEPTION WHEN serialization_failure THEN RETURN '{\"schema\":\"namespace_refused\"}'::jsonb; END $$")

    def private(asset, key):
        return 'pg_temp.private_catalog(' + lit(asset) + '::uuid,' + lit(key * 64) + ')'

    def legacy(asset):
        return 'pg_temp.legacy_catalog(' + lit(asset) + '::uuid)'

    def counts(asset, expected):
        actual = admin.query("json_build_array((SELECT count(*) FROM private.conversation_media_assets_v2 WHERE id=" + lit(asset) + "::uuid),(SELECT count(*) FROM public.media_assets WHERE id=" + lit(asset) + '::uuid))')
        require(actual == expected, 'exact private/public ownership counts ' + str(actual))

    def blocked(blocker, waiter):
        deadline = time.monotonic() + 4
        while time.monotonic() < deadline:
            if admin.query(str(blocker.pid) + '=ANY(pg_blocking_pids(' + str(waiter.pid) + '))'):
                return
            time.sleep(.02)
        raise AssertionError('actual catalog lock wait was not observed')

    try:
        admin, a, b = spawn(), spawn(), spawn()
        require(admin.query("current_database()=" + lit(config['database']) + " AND current_setting('listen_addresses')='' AND current_setting('cron.launch_active_jobs')='off' AND current_setting('pg_net.batch_size')='0'"), 'local runtime and job/network fence')
        require(admin.query('NOT EXISTS(SELECT 1 FROM public.users WHERE id=' + lit(owner) + '::uuid)'), 'unused synthetic owner')
        admin.command("INSERT INTO public.users(id,email,status,timezone,country,country_confirmed) VALUES(" + lit(owner) + "::uuid,'catalog-race-" + owner + "@example.invalid','active','UTC','BR',true)")
        owns_owner = True
        install(a)
        install(b)

        asset = fresh()
        b.command('BEGIN ISOLATION LEVEL REPEATABLE READ')
        b.query('(SELECT count(*) FROM public.media_assets)')
        first = a.query(private(asset, 'a'))
        require(first['asset']['id'] == asset, 'private first commit succeeded')
        require(b.query(legacy(asset)) == 'namespace_refused', 'old repeatable snapshot cannot bypass identity fence')
        b.command('COMMIT')
        counts(asset, [1, 0])
        result['cases'].append('legacy-repeatable-snapshot-before-private-commit')

        asset = fresh()
        b.command('BEGIN ISOLATION LEVEL REPEATABLE READ')
        b.query('(SELECT count(*) FROM public.media_assets)')
        require(a.query(legacy(asset)) == 'saved', 'legacy first commit succeeded')
        require(b.query(private(asset, 'b'))['schema'] == 'namespace_refused', 'private old snapshot cannot claim legacy ID')
        b.command('COMMIT')
        counts(asset, [0, 1])
        result['cases'].append('private-repeatable-snapshot-before-legacy-commit')

        asset = fresh()
        a.command('BEGIN')
        a.query(private(asset, 'c'))
        marker = b.send(legacy(asset))
        blocked(a, b)
        a.command('COMMIT')
        require(b.receive(marker) == 'namespace_refused', 'waiting old insertion refused after private commit')
        counts(asset, [1, 0])
        result['cases'].append('private-commit-refuses-blocked-legacy-insertion')

        for rollback in [False, True]:
            asset = fresh()
            a.command('BEGIN')
            require(a.query(legacy(asset)) == 'saved', 'legacy transaction inserted before private waiter')
            marker = b.send(private(asset, 'd' if rollback else 'e'))
            blocked(a, b)
            a.command('ROLLBACK' if rollback else 'COMMIT')
            second = b.receive(marker)
            require(second['schema'] == ('conversation.media-asset.v2' if rollback else 'namespace_refused'), 'legacy transaction outcome respected')
            counts(asset, [1, 0] if rollback else [0, 1])
            result['cases'].append('legacy-rollback-private-admits' if rollback else 'legacy-commit-private-refuses')

        asset, alternate = fresh(), fresh()
        a.command('BEGIN')
        first = a.query(private(asset, 'f'))
        marker = b.send(private(alternate, 'f'))
        blocked(a, b)
        a.command('COMMIT')
        require(b.receive(marker) == first, 'concurrent technical replay returns exact first source')
        counts(asset, [1, 0])
        counts(alternate, [0, 0])
        require(admin.query('NOT EXISTS(SELECT 1 FROM private.conversation_media_identity_v2 WHERE asset_id=' + lit(alternate) + '::uuid)'), 'no phantom identity on replay nonce')
        result['cases'].append('concurrent-replay-one-source-no-phantom-ID')
        return result
    finally:
        for actor in actors[1:]:
            actor.close()
        if admin is not None and owns_owner:
            admin.command('DELETE FROM private.conversation_media_assets_v2 WHERE user_id=' + lit(owner) + '::uuid')
            admin.command('DELETE FROM public.media_assets WHERE user_id=' + lit(owner) + '::uuid')
            if identities:
                admin.command('DELETE FROM private.conversation_media_identity_v2 WHERE asset_id IN(' + ','.join(lit(value) + '::uuid' for value in identities) + ')')
            admin.command('DELETE FROM public.users WHERE id=' + lit(owner) + '::uuid')
            result['cleanup'] = admin.query('NOT EXISTS(SELECT 1 FROM public.users WHERE id=' + lit(owner) + '::uuid) AND NOT EXISTS(SELECT 1 FROM private.conversation_media_assets_v2 WHERE user_id=' + lit(owner) + '::uuid)')
            require(result['cleanup'], 'exact owned fixture cleanup')
        if admin is not None:
            admin.close()
        result['actors_reaped'] = all(actor.process.poll() is not None for actor in actors)
