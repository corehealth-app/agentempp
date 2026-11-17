"""Real local-PG cross-catalog technical-request races. Import is inert.

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
    spec = importlib.util.spec_from_file_location('request_actor', Path(__file__).with_name('conversation_meal_command_journal_concurrency.py'))
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
        actor.command("CREATE FUNCTION pg_temp.legacy_catalog(a uuid,h text) RETURNS text LANGUAGE plpgsql AS $$ BEGIN INSERT INTO public.media_assets(id,user_id,kind,bucket_id,object_path,mime_type,declared_size_bytes,status,source_request_hash,retention_until) VALUES(a," + lit(owner) + "::uuid,'audio_note','audio-notes'," + lit(owner) + "||'/'||a::text||'.m4a','audio/mp4',8,'pending_upload',h,clock_timestamp()+interval '1day'); RETURN 'saved'; EXCEPTION WHEN serialization_failure THEN RETURN 'namespace_refused'; END $$")
        actor.command("CREATE FUNCTION pg_temp.private_catalog(a uuid,h text) RETURNS jsonb LANGUAGE plpgsql AS $$ BEGIN RETURN public.create_conversation_media_asset_v2(" + lit(owner) + "::uuid,a,'audio_note','audio/mp4',8,NULL,h); EXCEPTION WHEN serialization_failure THEN RETURN '{\"schema\":\"namespace_refused\"}'::jsonb; END $$")

    def private(asset, key):
        return 'pg_temp.private_catalog(' + lit(asset) + '::uuid,' + lit(key * 64) + ')'

    def legacy(asset, key):
        return 'pg_temp.legacy_catalog(' + lit(asset) + '::uuid,' + lit(key * 64) + ')'

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

        for private_first in [True, False]:
            asset, alternate = fresh(), fresh()
            key = 'a' if private_first else 'b'
            b.command('BEGIN ISOLATION LEVEL REPEATABLE READ')
            b.query('(SELECT count(*) FROM public.media_assets)')
            a.query(private(asset, key) if private_first else legacy(asset, key))
            second = b.query(legacy(alternate, key) if private_first else private(alternate, key))
            require(second == 'namespace_refused' if private_first else second['schema'] == 'namespace_refused', 'old snapshot cannot create a second catalog source for one technical request')
            b.command('COMMIT')
            counts(asset, [1, 0] if private_first else [0, 1])
            counts(alternate, [0, 0])
            result['cases'].append('private-first-stale-public-snapshot' if private_first else 'public-first-stale-private-snapshot')

        for n, (private_first, rollback) in enumerate([(True, False), (False, False), (True, True), (False, True)]):
            asset, alternate = fresh(), fresh()
            key = ['c', 'd', 'e', 'f'][n]
            a.command('BEGIN')
            a.query(private(asset, key) if private_first else legacy(asset, key))
            marker = b.send(legacy(alternate, key) if private_first else private(alternate, key))
            blocked(a, b)
            a.command('ROLLBACK' if rollback else 'COMMIT')
            second = b.receive(marker)
            if private_first:
                require(second == ('saved' if rollback else 'namespace_refused'), 'public waiter respects actual private commit/rollback')
            else:
                require(second['schema'] == ('conversation.media-asset.v2' if rollback else 'namespace_refused'), 'private waiter respects actual public commit/rollback')
            counts(asset, [0, 0] if rollback else [1, 0] if private_first else [0, 1])
            counts(alternate, ([0, 1] if private_first else [1, 0]) if rollback else [0, 0])
            require(admin.query('(SELECT count(*) FROM private.conversation_media_requests_v2 WHERE user_id=' + lit(owner) + '::uuid AND source_request_hash=' + lit(key * 64) + ')') == 1, 'one live technical reservation across both catalogs')
            result['cases'].append({'private_holder': private_first, 'holder_rollback': rollback, 'actual_wait_observed': True, 'logical_sources': 1})
        return result
    finally:
        for actor in actors[1:]:
            actor.close()
        try:
            if admin is not None and owns_owner:
                admin.command('DELETE FROM private.conversation_media_assets_v2 WHERE user_id=' + lit(owner) + '::uuid')
                admin.command('DELETE FROM public.media_assets WHERE user_id=' + lit(owner) + '::uuid')
                if identities:
                    admin.command('DELETE FROM private.conversation_media_identity_v2 WHERE asset_id IN(' + ','.join(lit(value) + '::uuid' for value in identities) + ')')
                admin.command('DELETE FROM public.users WHERE id=' + lit(owner) + '::uuid')
                result['cleanup'] = admin.query('NOT EXISTS(SELECT 1 FROM public.users WHERE id=' + lit(owner) + '::uuid) AND NOT EXISTS(SELECT 1 FROM private.conversation_media_assets_v2 WHERE user_id=' + lit(owner) + '::uuid)')
                require(result['cleanup'], 'exact owned request fixture cleanup')
        finally:
            if admin is not None:
                admin.close()
        result['actors_reaped'] = all(actor.process.poll() is not None for actor in actors)
