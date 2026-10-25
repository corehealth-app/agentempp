\set ON_ERROR_STOP on
BEGIN;
SET LOCAL request.jwt.claims='{"role":"service_role"}';
\ir fixtures/mobile_reevaluation_photo_fixture.sql

DO $normal$
DECLARE ctx jsonb; a uuid; c uuid; photo jsonb; aid uuid; tid uuid:=gen_random_uuid();
  prepared jsonb; receipt jsonb; again jsonb; at_time timestamptz; expiry timestamptz; activity timestamptz;
BEGIN
  ctx:=m3b_cycle_test.photo_context(301);a:=(ctx->>'user')::uuid;c:=(ctx->>'cycle')::uuid;
  photo:=m3b_cycle_test.allocate(ctx,gen_random_uuid());aid:=(photo#>>'{asset,id}')::uuid;
  SELECT last_activity_at INTO activity FROM private.mobile_reevaluation_photo_consents WHERE user_id=a;
  prepared:=public.prepare_mobile_reevaluation_photo_upload(a,c,aid,tid);
  at_time:=(prepared#>>'{ticket,prepared_at}')::timestamptz;expiry:=at_time+interval '2hours';
  PERFORM m3b_cycle_test.ok(prepared#>>'{asset,id}'=aid::text AND prepared#>>'{ticket,id}'=tid::text
    AND prepared#>>'{asset,consent_acceptance_id}'=ctx->>'acceptance','prepare_exact_cycle_asset_acceptance');
  PERFORM m3b_cycle_test.ok(prepared#>'{ticket,provider_expires_at}'='null'::jsonb,'prepare_has_no_guessed_expiry');
  receipt:=public.register_mobile_reevaluation_photo_upload_ticket(a,c,aid,tid,expiry);
  PERFORM m3b_cycle_test.ok((receipt#>>'{ticket,provider_expires_at}')::timestamptz=expiry
    AND receipt#>>'{ticket,asset_id}'=aid::text,'actual_provider_expiry_registered');
  again:=private.register_mobile_reevaluation_photo_upload_ticket_at(a,c,aid,tid,expiry,expiry+interval '1hour');
  PERFORM m3b_cycle_test.ok(again=receipt,'register_replay_does_not_change_time_even_after_expiry');
  PERFORM m3b_cycle_test.ok((public.prepare_mobile_reevaluation_photo_upload(a,c,aid,tid)#>>'{ticket,provider_expires_at}')::timestamptz=expiry,'prepare_replay_retains_observed_expiry');
  PERFORM m3b_cycle_test.ok((SELECT count(*)=1 FROM private.mobile_reevaluation_photo_upload_tickets WHERE user_id=a),'one_ticket_per_nonce');
  PERFORM m3b_cycle_test.ok((SELECT last_activity_at=activity FROM private.mobile_reevaluation_photo_consents WHERE user_id=a),'ticket_calls_do_not_renew_idle_activity');
  PERFORM m3b_cycle_test.ok((SELECT revision=2 FROM private.mobile_reevaluation_cycles WHERE cycle_id=c),'ticket_calls_preserve_clinical_revision');
  PERFORM m3b_cycle_test.throws(format('SELECT public.register_mobile_reevaluation_photo_upload_ticket(%L,%L,%L,%L,%L)',a,c,aid,tid,expiry+interval '1second'),'40001','same_nonce_different_expiry_refused');
  PERFORM m3b_cycle_test.throws(format('UPDATE private.mobile_reevaluation_photo_upload_tickets SET provider_expires_at=provider_expires_at+interval ''1second'' WHERE ticket_id=%L',tid),'55000','registered_expiry_immutable');
  PERFORM m3b_cycle_test.throws(format('UPDATE private.mobile_reevaluation_photo_upload_tickets SET asset_id=gen_random_uuid() WHERE ticket_id=%L',tid),'55000','ticket_identity_immutable');
  PERFORM m3b_cycle_test.ok(NOT (receipt::text LIKE '%signed_url%' OR receipt::text LIKE '%token%'),'no_capability_secret_persisted_in_wire');
END $normal$;

DO $invalid$
DECLARE ctx jsonb; other_ctx jsonb; a uuid; c uuid; aid uuid; tid uuid:=gen_random_uuid(); expiry timestamptz;
BEGIN
  ctx:=m3b_cycle_test.photo_context(302);other_ctx:=m3b_cycle_test.photo_context(303);
  a:=(ctx->>'user')::uuid;c:=(ctx->>'cycle')::uuid;aid:=(m3b_cycle_test.allocate(ctx,gen_random_uuid())#>>'{asset,id}')::uuid;
  PERFORM public.prepare_mobile_reevaluation_photo_upload(a,c,aid,tid);expiry:=clock_timestamp()+interval '2hours';
  PERFORM m3b_cycle_test.throws(format('SELECT public.prepare_mobile_reevaluation_photo_upload(%L,%L,%L,%L)',other_ctx->>'user',other_ctx->>'cycle',aid,gen_random_uuid()),'P0002','cross_owner_prepare_refused');
  PERFORM m3b_cycle_test.throws(format('SELECT public.register_mobile_reevaluation_photo_upload_ticket(%L,%L,%L,%L,%L)',other_ctx->>'user',other_ctx->>'cycle',aid,tid,expiry),'P0002','cross_owner_registration_refused');
  PERFORM m3b_cycle_test.throws(format('SELECT public.register_mobile_reevaluation_photo_upload_ticket(%L,%L,%L,%L,%L)',a,gen_random_uuid(),aid,tid,expiry),'P0002','cross_cycle_registration_refused');
  PERFORM m3b_cycle_test.throws(format('SELECT public.register_mobile_reevaluation_photo_upload_ticket(%L,%L,%L,%L,%L)',a,c,gen_random_uuid(),tid,expiry),'P0002','cross_asset_registration_refused');
  PERFORM m3b_cycle_test.throws(format('SELECT public.register_mobile_reevaluation_photo_upload_ticket(%L,%L,%L,%L,%L)',a,c,aid,gen_random_uuid(),expiry),'P0002','unprepared_ticket_refused');
  PERFORM m3b_cycle_test.throws(format('SELECT public.register_mobile_reevaluation_photo_upload_ticket(%L,%L,%L,%L,''infinity'')',a,c,aid,tid),'22023','infinite_expiry_refused');
  PERFORM m3b_cycle_test.throws(format('SELECT public.register_mobile_reevaluation_photo_upload_ticket(%L,%L,%L,%L,''2000-01-01Z'')',a,c,aid,tid),'22023','expiry_before_prepare_refused');
  UPDATE private.mobile_reevaluation_photo_assets SET invalidated_at=clock_timestamp(),invalidated_reason='discarded' WHERE asset_id=aid;
  PERFORM m3b_cycle_test.ok(public.register_mobile_reevaluation_photo_upload_ticket(a,c,aid,tid,expiry)#>>'{ticket,id}'=tid::text,'registration_survives_discard_for_future_resweep');
  PERFORM m3b_cycle_test.throws(format('SELECT public.prepare_mobile_reevaluation_photo_upload(%L,%L,%L,%L)',a,c,aid,gen_random_uuid()),'P0002','discarded_asset_never_signed_again');
END $invalid$;

DO $late_authority$
DECLARE ctx jsonb; a uuid; c uuid; aid uuid; tid uuid; mode text;
BEGIN
  FOREACH mode IN ARRAY ARRAY['reset','deleted','locale','expired'] LOOP
    ctx:=m3b_cycle_test.photo_context(CASE mode WHEN 'reset' THEN 304 WHEN 'deleted' THEN 305 WHEN 'locale' THEN 306 ELSE 307 END);
    a:=(ctx->>'user')::uuid;c:=(ctx->>'cycle')::uuid;aid:=(m3b_cycle_test.allocate(ctx,gen_random_uuid())#>>'{asset,id}')::uuid;tid:=gen_random_uuid();
    PERFORM public.prepare_mobile_reevaluation_photo_upload(a,c,aid,tid);
    IF mode='reset' THEN PERFORM public.reset_user_conversation_atomic(a,true);
    ELSIF mode='deleted' THEN UPDATE public.users SET status='deleted' WHERE id=a;
    ELSIF mode='locale' THEN UPDATE public.users SET locale='en-US' WHERE id=a;
    END IF;
    PERFORM m3b_cycle_test.ok(private.register_mobile_reevaluation_photo_upload_ticket_at(a,c,aid,tid,clock_timestamp()+interval '2hours',CASE WHEN mode='expired' THEN clock_timestamp()+interval '2minutes' ELSE NULL END)#>>'{ticket,id}'=tid::text,'late_registration_survives_'||mode);
    IF mode='reset' THEN
      PERFORM m3b_cycle_test.throws(format('SELECT public.get_mobile_reevaluation_photo_asset(%L,%L,%L)',a,c,aid),'40001','reset_blocks_capability_return');
    ELSIF mode='deleted' THEN
      PERFORM m3b_cycle_test.throws(format('SELECT public.get_mobile_reevaluation_photo_asset(%L,%L,%L)',a,c,aid),'P0002','softdelete_blocks_capability_return');
    ELSIF mode='locale' THEN
      PERFORM m3b_cycle_test.throws(format('SELECT public.get_mobile_reevaluation_photo_asset(%L,%L,%L)',a,c,aid),'40001','locale_change_blocks_capability_return');
    END IF;
  END LOOP;
END $late_authority$;

DO $grants$
BEGIN
  PERFORM m3b_cycle_test.ok(NOT has_table_privilege('service_role','private.mobile_reevaluation_photo_upload_tickets','SELECT'),'ticket_ledger_private_even_from_service_role');
  PERFORM m3b_cycle_test.ok(NOT has_function_privilege('authenticated','public.prepare_mobile_reevaluation_photo_upload(uuid,uuid,uuid,uuid)','EXECUTE'),'client_cannot_prepare');
  PERFORM m3b_cycle_test.ok(NOT has_function_privilege('anon','public.register_mobile_reevaluation_photo_upload_ticket(uuid,uuid,uuid,uuid,timestamptz)','EXECUTE'),'client_cannot_supply_provider_expiry');
  PERFORM m3b_cycle_test.ok(has_function_privilege('service_role','public.register_mobile_reevaluation_photo_upload_ticket(uuid,uuid,uuid,uuid,timestamptz)','EXECUTE'),'trusted_backend_can_record_expiry');
END $grants$;
ROLLBACK;
