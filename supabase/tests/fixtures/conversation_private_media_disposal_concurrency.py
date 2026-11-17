"""Real signing/disposal schedules in a caller-verified disposable local copy.
Import is inert. No cloud, Storage API, provider or process lifecycle operations.
"""
import importlib.util
from pathlib import Path
import time
import uuid


def run(config):
    if config.get('ownership_verified') is not True or config.get('disposable_local_copy') is not True:
        raise AssertionError('owned disposable local copy required')
    spec = importlib.util.spec_from_file_location('disposal_actor', Path(__file__).with_name('conversation_meal_command_journal_concurrency.py'))
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    Actor, lit, require = module.Actor, module.lit, module.require
    actors, assets = [], []
    result = {'cases': [], 'cleanup': False, 'actors_reaped': False}
    owner = str(uuid.uuid4())
    admin = None
    owns = False

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

    def blocked(holder, waiter):
        deadline = time.monotonic() + 3
        while time.monotonic() < deadline:
            if admin.query(str(holder.pid) + '=ANY(pg_blocking_pids(' + str(waiter.pid) + '))'):
                return
            time.sleep(.02)
        raise AssertionError('actual signing/disposal lock wait not observed')

    def args(asset):
        return lit(owner) + '::uuid,' + lit(asset) + '::uuid'

    def seed():
        asset, ticket = str(uuid.uuid4()), str(uuid.uuid4())
        assets.append(asset)
        admin.query('public.create_conversation_media_asset_v2(' + args(asset) + ",'audio_note','audio/mp4',8,NULL," + lit(asset.replace('-', '').ljust(64, '0')) + ')')
        admin.query('public.prepare_conversation_media_upload_v2(' + args(asset) + ',' + lit(ticket) + '::uuid)')
        return asset, ticket

    def register(asset, ticket):
        return 'public.register_conversation_media_upload_v2(' + args(asset) + ',' + lit(ticket) + "::uuid,'2026-12-17T00:00:00Z'::timestamptz)"

    def claim(asset):
        page = admin.query('public.claim_conversation_media_disposal_batch_v2(100)')
        matches = [x for x in page['items'] if x['asset_id'] == asset]
        require(len(matches) == 1, 'one owner-bound disposal claim')
        return matches[0]

    try:
        admin, a, b = spawn(), spawn(), spawn()
        require(admin.query("current_database()=" + lit(config['database']) + " AND current_setting('listen_addresses')='' AND current_setting('cron.launch_active_jobs')='off' AND current_setting('pg_net.batch_size')='0'"), 'exact local target/outbound fence')
        require(admin.query('NOT EXISTS(SELECT 1 FROM public.users WHERE id=' + lit(owner) + '::uuid)'), 'unused synthetic owner')
        admin.command('INSERT INTO public.users(id,email,status) VALUES(' + lit(owner) + "::uuid,'disposal-race-" + owner + "@example.invalid','active')")
        owns = True
        for signer_first in [True, False]:
            asset, ticket = seed()
            close = 'public.close_conversation_media_v2(' + args(asset) + ')'
            a.command('BEGIN')
            first = a.query(register(asset, ticket) if signer_first else close)
            require(first is True if not signer_first else first['schema'] == 'conversation.upload-registered.v2', 'first operation admitted')
            marker = b.send(close if signer_first else register(asset, ticket))
            blocked(a, b)
            a.command('COMMIT')
            second = b.receive(marker)
            require(second is True if signer_first else second['schema'] == 'conversation.upload-registered.v2', 'waiter preserves closure and actual signer bookkeeping')
            require(admin.query('(SELECT status=\'deleted\' AND processing_result IS NULL FROM private.conversation_media_assets_v2 WHERE id=' + lit(asset) + '::uuid)'), 'late signer cannot resurrect catalog')
            require(admin.query('(SELECT closed_at IS NOT NULL AND issuance_revision=1 FROM private.conversation_media_obligations_v2 WHERE asset_id=' + lit(asset) + '::uuid)'), 'one observation and durable closure')
            c = claim(asset)
            require(admin.query('public.inspect_conversation_media_disposal_v2(' + lit(asset) + '::uuid,' + lit(owner) + '::uuid,' + lit(c['claim_token']) + "::uuid)->>'state'") == 'absent', 'claim survives both real lock orders')
            result['cases'].append({'schedule': 'signer_before_disposal' if signer_first else 'disposal_before_signer', 'actual_wait_observed': True})

        # An ack commits before an already-started signing response. Its revision
        # is not a final certificate; account purge must wait for a fresh sweep.
        asset, ticket = seed()
        admin.query('public.close_conversation_media_v2(' + args(asset) + ')')
        c = claim(asset)
        admin.command('INSERT INTO storage.objects(bucket_id,name,version,metadata) VALUES(\'audio-notes\',' + lit(c['object_path']) + ',' + lit(str(uuid.uuid4())) + ",' {\"size\":0}'::jsonb)")
        ack = 'public.acknowledge_conversation_media_disposal_v2(' + lit(asset) + '::uuid,' + lit(owner) + '::uuid,' + lit(c['claim_token']) + '::uuid)'
        a.command('BEGIN')
        require(a.query(ack)['state'] == 'barrier_retained', 'empty barrier acknowledged')
        marker = b.send(register(asset, ticket))
        blocked(a, b)
        a.command('COMMIT')
        require(b.receive(marker)['schema'] == 'conversation.upload-registered.v2', 'late actual expiry retained')
        require(admin.query('(SELECT d.last_completed_revision<o.issuance_revision FROM private.conversation_media_disposals_v2 d JOIN private.conversation_media_obligations_v2 o USING(asset_id) WHERE d.asset_id=' + lit(asset) + '::uuid)'), 'late signer invalidates prior sweep readiness')
        result['cases'].append({'schedule': 'ack_before_late_signer', 'actual_wait_observed': True, 'prior_sweep_invalidated': True})

        # A worker already holding an independent obligation must not block a
        # second batch or yield a second token for the same source.
        asset, _ticket = seed()
        admin.query('public.close_conversation_media_v2(' + args(asset) + ')')
        a.command('BEGIN')
        one = a.query('public.claim_conversation_media_disposal_batch_v2(100)')
        require(any(x['asset_id'] == asset for x in one['items']), 'first worker holds exact claim')
        two = b.query('public.claim_conversation_media_disposal_batch_v2(100)')
        require(not any(x['asset_id'] == asset for x in two['items']), 'second worker skips held authority')
        a.command('COMMIT')
        result['cases'].append({'schedule': 'two_workers_skip_held_source', 'duplicate_claims': 0})
        require(admin.query('NOT EXISTS(SELECT 1 FROM public.media_assets WHERE user_id=' + lit(owner) + '::uuid) AND NOT EXISTS(SELECT 1 FROM private.conversation_media_expiry_debts WHERE user_id=' + lit(owner) + '::uuid)'), 'old queries never acquire private source')
        return result
    finally:
        for actor in actors[1:]:
            actor.close()
        try:
            if admin is not None and owns:
                # Only metadata created by this fixture, in the externally
                # verified network-sandboxed disposable copy. Never real Storage.
                admin.command('BEGIN; SET LOCAL storage.allow_delete_query=\'true\'; DELETE FROM storage.objects WHERE bucket_id=\'audio-notes\' AND name LIKE ' + lit('conversation-v2/' + owner + '/%') + '; COMMIT')
                for table in ['conversation_media_assets_v2', 'conversation_media_disposals_v2', 'conversation_media_upload_tickets_v2', 'conversation_media_obligations_v2']:
                    admin.command('DELETE FROM private.' + table + ' WHERE user_id=' + lit(owner) + '::uuid')
                for asset in assets:
                    admin.command('DELETE FROM private.conversation_media_identity_v2 WHERE asset_id=' + lit(asset) + '::uuid')
                admin.command('DELETE FROM public.users WHERE id=' + lit(owner) + '::uuid')
                result['cleanup'] = admin.query('NOT EXISTS(SELECT 1 FROM public.users WHERE id=' + lit(owner) + '::uuid) AND NOT EXISTS(SELECT 1 FROM private.conversation_media_obligations_v2 WHERE user_id=' + lit(owner) + '::uuid)')
                require(result['cleanup'], 'owned synthetic cleanup')
        finally:
            if admin is not None:
                admin.close()
            result['actors_reaped'] = all(actor.process.poll() is not None for actor in actors)
