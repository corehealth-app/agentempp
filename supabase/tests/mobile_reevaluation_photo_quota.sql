\set ON_ERROR_STOP on
BEGIN ISOLATION LEVEL READ COMMITTED;
SET LOCAL request.jwt.claims='{"role":"service_role"}';
SET LOCAL statement_timeout='30s';
SET LOCAL lock_timeout='5s';
\ir fixtures/mobile_reevaluation_photo_fixture.sql

CREATE FUNCTION m3b_cycle_test.renew_quota_consent(ctx jsonb,at_time timestamptz) RETURNS jsonb
LANGUAGE plpgsql SET search_path=pg_catalog AS $$
DECLARE doc public.legal_documents%ROWTYPE;r jsonb;rev bigint;
BEGIN
 SELECT * INTO STRICT doc FROM public.legal_documents WHERE id=m3b_cycle_test.uid(501);
 SELECT revision INTO STRICT rev FROM private.mobile_reevaluation_cycles WHERE cycle_id=(ctx->>'cycle')::uuid;
 r:=private.accept_mobile_reevaluation_photo_consent_at((ctx->>'user')::uuid,(ctx->>'cycle')::uuid,
  rev,doc.id,doc.document_key,doc.version,doc.locale,doc.body_hash,gen_random_uuid(),at_time);
 RETURN ctx||jsonb_build_object('revision',r->'cycle_revision','acceptance',r#>'{acceptance,acceptance_id}');
END $$;

DO $six_and_replay$
DECLARE ctx jsonb;other_ctx jsonb;a uuid;k uuid;keys uuid[]:=ARRAY[]::uuid[];first_wire jsonb;r jsonb;
 before_rows jsonb;before_activity timestamptz;i integer;generic uuid;
BEGIN
 ctx:=m3b_cycle_test.photo_context(1200);a:=(ctx->>'user')::uuid;
 FOR i IN 1..6 LOOP
  k:=gen_random_uuid();keys:=array_append(keys,k);r:=m3b_cycle_test.allocate(ctx,k);
  IF i=6 THEN first_wire:=r;END IF;
 END LOOP;
 PERFORM m3b_cycle_test.ok((SELECT count(*)=6 FROM private.mobile_reevaluation_photo_assets WHERE user_id=a),'six_new_photos_allowed');
 SELECT jsonb_agg(to_jsonb(m) ORDER BY id) INTO before_rows FROM public.media_assets m WHERE user_id=a;
 SELECT last_activity_at INTO before_activity FROM private.mobile_reevaluation_photo_consents WHERE acceptance_id=(ctx->>'acceptance')::uuid;
 PERFORM m3b_cycle_test.throws(format('SELECT m3b_cycle_test.allocate(%L::jsonb,%L)',ctx,gen_random_uuid()),'P0001','seventh_new_photo_refused');
 BEGIN
  PERFORM m3b_cycle_test.allocate(ctx,gen_random_uuid());
  RAISE EXCEPTION 'expected_quota_rejection';
 EXCEPTION WHEN SQLSTATE 'P0001' THEN
  PERFORM m3b_cycle_test.ok(SQLERRM='mobile_reevaluation_photo_limit_reached','fixed_quota_message_contains_no_usage_or_paths');
 END;
 r:=m3b_cycle_test.allocate(ctx,keys[6]);
 PERFORM m3b_cycle_test.ok(r#>'{asset,id}'=first_wire#>'{asset,id}' AND r#>'{asset,created_at}'=first_wire#>'{asset,created_at}',
  'same_request_replay_is_free_at_limit');
 PERFORM m3b_cycle_test.ok(m3b_cycle_test.allocate(ctx,keys[1]) IS NULL,'superseded_request_never_retakes_source_or_spends_slot');
 PERFORM m3b_cycle_test.throws(format('SELECT m3b_cycle_test.allocate(%L::jsonb,%L,''side'')',ctx,keys[6]),'40001','reused_key_different_payload_is_not_free_new_photo');
 PERFORM m3b_cycle_test.ok((SELECT jsonb_agg(to_jsonb(m) ORDER BY id)=before_rows FROM public.media_assets m WHERE user_id=a)
  AND (SELECT last_activity_at=before_activity FROM private.mobile_reevaluation_photo_consents WHERE acceptance_id=(ctx->>'acceptance')::uuid),
  'rejection_and_replay_preserve_assets_and_activity');
 PERFORM m3b_cycle_test.ok((SELECT count(*)=6 FROM private.mobile_reevaluation_photo_assets WHERE user_id=a)
  AND(SELECT max(source_revision)=6 FROM private.mobile_reevaluation_photo_sources WHERE user_id=a),'rejection_creates_no_orphan_or_source_revision');
 other_ctx:=m3b_cycle_test.photo_context(1201);r:=m3b_cycle_test.allocate(other_ctx,gen_random_uuid());
 PERFORM m3b_cycle_test.ok(r#>>'{asset,user_id}'=other_ctx->>'user','quota_isolates_persons');
 generic:=m3b_cycle_test.ordinary_asset(a,'meal_photo');
 PERFORM m3b_cycle_test.ok(generic IS NOT NULL AND (SELECT count(*)=6 FROM private.mobile_reevaluation_photo_assets WHERE user_id=a),'generic_media_unaffected_and_does_not_spend_recurring_slot');
END $six_and_replay$;

DO $retained_usage$
DECLARE ctx jsonb;a uuid;r jsonb;ids uuid[]:=ARRAY[]::uuid[];i integer;before_profile jsonb;rev bigint;
BEGIN
 ctx:=m3b_cycle_test.photo_context(1202);a:=(ctx->>'user')::uuid;
 SELECT to_jsonb(p) INTO before_profile FROM public.user_profiles p WHERE user_id=a;
 FOR i IN 1..6 LOOP r:=m3b_cycle_test.allocate(ctx,gen_random_uuid());ids:=array_append(ids,(r#>>'{asset,id}')::uuid);END LOOP;
 UPDATE public.media_assets SET status='failed',failure_stage='upload',failure_code='synthetic' WHERE id=ids[1];
 UPDATE public.media_assets SET status='deleted',deleted_at=clock_timestamp() WHERE id=ids[2];
 UPDATE private.mobile_reevaluation_photo_assets SET invalidated_at=clock_timestamp(),invalidated_reason='replaced' WHERE asset_id=ids[3];
 PERFORM m3b_cycle_test.throws(format('SELECT m3b_cycle_test.allocate(%L::jsonb,%L)',ctx,gen_random_uuid()),'P0001','failed_deleted_replaced_and_pending_photos_all_count');
 PERFORM public.discard_mobile_reevaluation_photos(a,(ctx->>'cycle')::uuid,(ctx->>'acceptance')::uuid,(ctx->>'revision')::bigint);
 ctx:=m3b_cycle_test.renew_quota_consent(ctx,clock_timestamp());
 PERFORM m3b_cycle_test.throws(format('SELECT m3b_cycle_test.allocate(%L::jsonb,%L)',ctx,gen_random_uuid()),'P0001','new_consent_after_discard_cannot_reset_quota');
 PERFORM m3b_cycle_test.ok((SELECT count(*)=6 AND bool_and(invalidated_at IS NOT NULL) FROM private.mobile_reevaluation_photo_assets WHERE user_id=a),
  'discard_keeps_usage_history');
 PERFORM m3b_cycle_test.ok((SELECT to_jsonb(p)=before_profile FROM public.user_profiles p WHERE user_id=a),'quota_and_discard_preserve_clinical_profile');
 PERFORM public.reset_user_conversation_atomic(a,true);
 PERFORM m3b_cycle_test.ok((SELECT count(*)=6 FROM private.mobile_reevaluation_photo_assets WHERE user_id=a),'real_reset_preserves_person_usage_history');
 PERFORM m3b_cycle_test.throws(format('SELECT m3b_cycle_test.allocate(%L::jsonb,%L)',ctx,gen_random_uuid()),'40001','reset_rejects_old_cycle_instead_of_opening_capacity');
END $retained_usage$;

DO $rolling_boundary$
DECLARE ctx jsonb;a uuid;r jsonb;base_time timestamptz;i integer;count_before bigint;
BEGIN
 ctx:=m3b_cycle_test.photo_context(1203);a:=(ctx->>'user')::uuid;base_time:=clock_timestamp();
 FOR i IN 1..6 LOOP PERFORM m3b_cycle_test.allocate(ctx,gen_random_uuid(),'front',1200,base_time);END LOOP;
 ctx:=m3b_cycle_test.renew_quota_consent(ctx,base_time+interval '24 hours'-interval '1microsecond');
 PERFORM m3b_cycle_test.throws(format('SELECT m3b_cycle_test.allocate(%L::jsonb,%L,''front'',1200,%L)',
  ctx,gen_random_uuid(),base_time+interval '24 hours'-interval '1microsecond'),'P0001','one_microsecond_inside_window_still_counts');
 r:=m3b_cycle_test.allocate(ctx,gen_random_uuid(),'side',1200,base_time+interval '24 hours');
 PERFORM m3b_cycle_test.ok((SELECT count(*)=7 FROM private.mobile_reevaluation_photo_assets WHERE user_id=a),
  'exact_elapsed_24hours_releases_capacity_without_deleting_history');
 PERFORM m3b_cycle_test.ok((r#>>'{asset,created_at}')::timestamptz=base_time+interval '24 hours','allocation_uses_server_context_time_not_calendar_day');
END $rolling_boundary$;

DO $transaction_and_acl$
DECLARE ctx jsonb;a uuid;r jsonb;i integer;k uuid:=gen_random_uuid();rolled_id uuid;
BEGIN
 ctx:=m3b_cycle_test.photo_context(1204);a:=(ctx->>'user')::uuid;
 FOR i IN 1..5 LOOP PERFORM m3b_cycle_test.allocate(ctx,gen_random_uuid());END LOOP;
 BEGIN
  r:=m3b_cycle_test.allocate(ctx,k);rolled_id:=(r#>>'{asset,id}')::uuid;
  RAISE EXCEPTION 'synthetic_rollback' USING ERRCODE='PT001';
 EXCEPTION WHEN SQLSTATE 'PT001' THEN NULL;END;
 r:=m3b_cycle_test.allocate(ctx,k);
 PERFORM m3b_cycle_test.ok((SELECT count(*)=6 FROM private.mobile_reevaluation_photo_assets WHERE user_id=a)
  AND r#>>'{asset,id}'<>rolled_id::text,'rolled_back_allocation_does_not_spend_slot');
 PERFORM m3b_cycle_test.ok(NOT has_table_privilege('service_role','private.mobile_reevaluation_photo_assets','INSERT')
  AND NOT has_table_privilege('authenticated','private.mobile_reevaluation_photo_assets','SELECT'),'ledger_stays_backend_private');
 PERFORM m3b_cycle_test.ok((SELECT tgenabled='O' FROM pg_trigger WHERE tgrelid='private.mobile_reevaluation_photo_assets'::regclass
  AND tgname='enforce_mobile_reevaluation_photo_quota'),'quota_trigger_enabled_after_all_tests');
END $transaction_and_acl$;
ROLLBACK;
