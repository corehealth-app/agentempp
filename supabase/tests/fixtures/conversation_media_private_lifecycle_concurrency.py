"""Real local-PG lifecycle races. Import is inert, network/provider-free.

Caller must prove an owned disposable database with outbound jobs disabled.
Deletion below touches only UUIDs created and checked unused by this run.
"""
import importlib.util
from pathlib import Path
import time
import uuid


def run(config):
    if config.get('ownership_verified') is not True or config.get('disposable_local_copy') is not True:
        raise AssertionError('owned disposable local copy required')
    spec = importlib.util.spec_from_file_location('lifecycle_actor', Path(__file__).with_name('conversation_meal_command_journal_concurrency.py'))
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    Actor, lit, require = module.Actor, module.lit, module.require
    actors, assets, owners = [], [], []
    result = {'cases': [], 'cleanup': False, 'actors_reaped': False}
    admin = None

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

    def owner():
        value = str(uuid.uuid4())
        require(admin.query('NOT EXISTS(SELECT 1 FROM public.users WHERE id=' + lit(value) + '::uuid)'), 'unused synthetic owner')
        admin.command("INSERT INTO public.users(id,email,status,timezone,country,country_confirmed) VALUES(" + lit(value) + "::uuid,'lifecycle-race-" + value + "@example.invalid','active','UTC','BR',true)")
        owners.append(value)
        return value

    def fresh(who, ready=True):
        asset, ticket = str(uuid.uuid4()), str(uuid.uuid4())
        require(admin.query('NOT EXISTS(SELECT 1 FROM private.conversation_media_identity_v2 WHERE asset_id=' + lit(asset) + '::uuid)'), 'unused synthetic asset')
        admin.query('public.create_conversation_media_asset_v2(' + lit(who) + '::uuid,' + lit(asset) + "::uuid,'audio_note','audio/mp4',8,NULL,encode(sha256(convert_to(" + lit(asset) + ",'UTF8')),'hex'))")
        assets.append(asset)
        admin.query('public.prepare_conversation_media_upload_v2(' + lit(who) + '::uuid,' + lit(asset) + '::uuid,' + lit(ticket) + '::uuid)')
        if ready:
            admin.query('public.register_conversation_media_upload_v2(' + lit(who) + '::uuid,' + lit(asset) + '::uuid,' + lit(ticket) + "::uuid,date_trunc('second',clock_timestamp())+interval '2hours')")
            admin.query('public.complete_conversation_media_upload_v2(' + lit(who) + '::uuid,' + lit(asset) + "::uuid,8,'audio/mp4',NULL)")
        return asset, ticket

    def claim(actor, who, asset):
        return actor.query('public.claim_conversation_media_processing_v2(' + lit(who) + '::uuid,' + lit(asset) + "::uuid,repeat('a',64))")

    def finish(who, asset, token):
        return 'public.complete_conversation_media_processing_v2(' + lit(who) + '::uuid,' + lit(asset) + "::uuid,repeat('a',64)," + lit(token) + "::uuid,'{\"text\":\"synthetic observation\"}'::jsonb)"

    def dispose(actor, asset):
        actor.command("UPDATE private.conversation_media_assets_v2 SET status='deleted',deleted_at=clock_timestamp(),updated_at=clock_timestamp(),processing_result=NULL,processed_at=NULL,failure_stage=NULL,failure_code=NULL WHERE id=" + lit(asset) + '::uuid')
        actor.command('UPDATE private.conversation_media_obligations_v2 SET closed_at=clock_timestamp() WHERE asset_id=' + lit(asset) + '::uuid')

    def blocked(blocker, waiter):
        deadline = time.monotonic() + 3
        while time.monotonic() < deadline:
            if admin.query(str(blocker.pid) + '=ANY(pg_blocking_pids(' + str(waiter.pid) + '))'):
                return
            time.sleep(.02)
        raise AssertionError('actual lifecycle lock wait not observed')

    try:
        admin = spawn()
        a, b = spawn(), spawn()
        require(admin.query("current_database()=" + lit(config['database']) + " AND current_setting('listen_addresses')='' AND current_setting('cron.launch_active_jobs')='off' AND current_setting('pg_net.batch_size')='0'"), 'exact local runtime and network fence')
        who = owner()
        asset, ticket = fresh(who)
        a.command('BEGIN')
        first = claim(a, who, asset)
        marker = b.send('public.claim_conversation_media_processing_v2(' + lit(who) + '::uuid,' + lit(asset) + "::uuid,repeat('b',64))")
        blocked(a, b)
        a.command('COMMIT')
        require(first['action'] == 'claimed' and b.receive(marker)['action'] == 'busy', 'one simultaneous processing claim')
        require(admin.query('(SELECT count(*) FROM private.conversation_media_processing_claims_v2 WHERE asset_id=' + lit(asset) + '::uuid)') == 1, 'one claim row')
        result['cases'].append('concurrent-claims-one-token-and-busy-waiter')

        a.command('BEGIN')
        dispose(a, asset)
        marker = b.send(finish(who, asset, first['claim']['token']))
        blocked(a, b)
        a.command('COMMIT')
        require(b.receive(marker) is False, 'late result after disposal is refused')
        require(admin.query("(SELECT status='deleted' AND processing_result IS NULL FROM private.conversation_media_assets_v2 WHERE id=" + lit(asset) + '::uuid)'), 'no resurrection')
        result['cases'].append('disposal-commit-refuses-blocked-processing-result')

        asset, ticket = fresh(who)
        first = claim(admin, who, asset)
        a.command('BEGIN')
        require(a.query(finish(who, asset, first['claim']['token'])), 'current result commits')
        marker = b.send("(SELECT status FROM private.conversation_media_assets_v2 WHERE id=" + lit(asset) + '::uuid FOR UPDATE)')
        blocked(a, b)
        a.command('COMMIT')
        require(b.receive(marker) == 'processed', 'disposal sees committed source version')
        b.command('BEGIN')
        dispose(b, asset)
        b.command('COMMIT')
        require(admin.query("(SELECT status='deleted' AND processing_result IS NULL FROM private.conversation_media_assets_v2 WHERE id=" + lit(asset) + '::uuid)'), 'disposal dominates a prior committed result')
        result['cases'].append('processing-commit-followed-by-disposal-scrubs-result')

        late_owner = owner()
        asset, ticket = fresh(late_owner, ready=False)
        a.command('BEGIN')
        a.command('DELETE FROM private.conversation_media_assets_v2 WHERE id=' + lit(asset) + '::uuid')
        a.command('DELETE FROM public.users WHERE id=' + lit(late_owner) + '::uuid')
        marker = b.send('public.register_conversation_media_upload_v2(' + lit(late_owner) + '::uuid,' + lit(asset) + '::uuid,' + lit(ticket) + "::uuid,date_trunc('second',clock_timestamp())+interval '2hours')")
        blocked(a, b)
        a.command('COMMIT')
        response = b.receive(marker)
        require(response['schema'] == 'conversation.upload-registered.v2', 'late capability observation is retained')
        require(admin.query('(SELECT closed_at IS NOT NULL AND issuance_revision=1 FROM private.conversation_media_obligations_v2 WHERE asset_id=' + lit(asset) + '::uuid)'), 'independent authority survives concurrent account removal')
        result['cases'].append('account-removal-retains-blocked-late-signing-observation')
        return result
    finally:
        for actor in actors[1:]:
            actor.close()
        if admin is not None:
            if assets:
                ids = ','.join(lit(value) + '::uuid' for value in assets)
                admin.command('DELETE FROM private.conversation_media_upload_tickets_v2 WHERE asset_id IN(' + ids + ')')
                admin.command('DELETE FROM private.conversation_media_obligations_v2 WHERE asset_id IN(' + ids + ')')
                admin.command('DELETE FROM private.conversation_media_assets_v2 WHERE id IN(' + ids + ')')
                admin.command('DELETE FROM private.conversation_media_identity_v2 WHERE asset_id IN(' + ids + ')')
            if owners:
                ids = ','.join(lit(value) + '::uuid' for value in owners)
                admin.command('DELETE FROM public.users WHERE id IN(' + ids + ')')
                result['cleanup'] = admin.query('NOT EXISTS(SELECT 1 FROM public.users WHERE id IN(' + ids + '))')
                require(result['cleanup'], 'exact synthetic fixture cleanup')
            admin.close()
        result['actors_reaped'] = all(actor.process.poll() is not None for actor in actors)
