-- Owned synthetic ROLLBACK only. No Storage/provider invocation.
BEGIN;
SET LOCAL request.jwt.claims='{"role":"service_role"}';
\ir fixtures/mobile_reevaluation_photo_cleanup_fixture.sql
SELECT m3b_cycle_test.ok(to_regprocedure('public.claim_mobile_reevaluation_photo_cleanup_scopes(integer)') IS NOT NULL,'normal_cleanup_claim_exists');


DO $claim$
DECLARE fresh jsonb;old1 jsonb;old2 jsonb;discarded jsonb;reset_scope jsonb;deleted_scope jsonb;due_wait jsonb;
 r jsonb;h jsonb;page jsonb;ack jsonb;ticket uuid:=gen_random_uuid();ids uuid[];rev bigint;before_domain jsonb;
 t timestamptz;
BEGIN
 fresh:=m3b_cycle_test.cleanup_context(5400);
 PERFORM m3b_cycle_test.ok(public.claim_mobile_reevaluation_photo_cleanup_scopes(1)->'items'='[]'::jsonb,'live_24h_photo_is_not_claimed');
 old1:=m3b_cycle_test.cleanup_context(5401,86420);old2:=m3b_cycle_test.cleanup_context(5402,86410);
 SELECT jsonb_build_object('profiles',(SELECT jsonb_agg(to_jsonb(x) ORDER BY user_id) FROM public.user_profiles x),
  'users',(SELECT jsonb_agg(to_jsonb(x) ORDER BY id) FROM public.users x),
  'assets',(SELECT jsonb_agg(to_jsonb(x) ORDER BY id) FROM public.media_assets x),
  'consents',(SELECT jsonb_agg(to_jsonb(x) ORDER BY acceptance_id) FROM private.mobile_reevaluation_photo_consents x)) INTO before_domain;
 r:=public.claim_mobile_reevaluation_photo_cleanup_scopes(1);
 PERFORM m3b_cycle_test.ok(r#>>'{items,0,acceptance_id}'=old1->>'acceptance' AND r->>'has_more'='true','oldest_unvisited_expiry_claimed_first');
 PERFORM m3b_cycle_test.ok(EXISTS(SELECT 1 FROM private.mobile_reevaluation_photo_cleanup_visits WHERE acceptance_id=(old1->>'acceptance')::uuid),'visit_is_durable_before_external_work');
 r:=public.claim_mobile_reevaluation_photo_cleanup_scopes(1);
 PERFORM m3b_cycle_test.ok(r#>>'{items,0,acceptance_id}'=old2->>'acceptance','failed_first_scope_does_not_starve_next_owner');
 PERFORM m3b_cycle_test.ok(before_domain=jsonb_build_object(
  'profiles',(SELECT jsonb_agg(to_jsonb(x) ORDER BY user_id) FROM public.user_profiles x),
  'users',(SELECT jsonb_agg(to_jsonb(x) ORDER BY id) FROM public.users x),
  'assets',(SELECT jsonb_agg(to_jsonb(x) ORDER BY id) FROM public.media_assets x),
  'consents',(SELECT jsonb_agg(to_jsonb(x) ORDER BY acceptance_id) FROM private.mobile_reevaluation_photo_consents x)),'claim_changes_only_technical_visits');
 -- An idle boundary candidate is still adjudicated by the original authority.
 r:=public.prepare_mobile_reevaluation_photo_disposition((old1->>'user')::uuid,(old1->>'cycle')::uuid,(old1->>'acceptance')::uuid);h:=r->'disposition';
 PERFORM m3b_cycle_test.ok(r->>'kind'='ready' AND h->>'reason'='expired','existing_prepare_seals_the_actual_expired_scope');
 page:=public.get_mobile_reevaluation_photo_disposition_page((old1->>'user')::uuid,(h->>'id')::uuid,(h->>'sweep_no')::bigint,(h->>'capability_revision')::bigint,NULL);
 SELECT array_agg((x->>'asset_id')::uuid ORDER BY x->>'asset_id') INTO ids FROM jsonb_array_elements(page->'items') x;
 ack:=public.commit_mobile_reevaluation_photo_disposition_page((old1->>'user')::uuid,(h->>'id')::uuid,(h->>'sweep_no')::bigint,(h->>'capability_revision')::bigint,NULL,ids);
 PERFORM m3b_cycle_test.ok(ack->>'state'='settled','no_upload_capability_scope_settles_after_exact_ack');
 r:=public.claim_mobile_reevaluation_photo_cleanup_scopes(100);
 PERFORM m3b_cycle_test.ok(NOT EXISTS(SELECT 1 FROM jsonb_array_elements(r->'items') x WHERE x->>'acceptance_id'=old1->>'acceptance'),'settled_scope_is_not_polled_again');
 discarded:=m3b_cycle_test.cleanup_context(5403);
 PERFORM public.prepare_mobile_reevaluation_photo_upload((discarded->>'user')::uuid,(discarded->>'cycle')::uuid,(discarded->>'asset')::uuid,ticket);
 SELECT revision INTO rev FROM private.mobile_reevaluation_cycles WHERE cycle_id=(discarded->>'cycle')::uuid;
 PERFORM public.discard_mobile_reevaluation_photos((discarded->>'user')::uuid,(discarded->>'cycle')::uuid,(discarded->>'acceptance')::uuid,rev);
 r:=public.claim_mobile_reevaluation_photo_cleanup_scopes(100);
 PERFORM m3b_cycle_test.ok(EXISTS(SELECT 1 FROM jsonb_array_elements(r->'items') x WHERE x->>'acceptance_id'=discarded->>'acceptance'),'discard_is_discovered_before_idle_expiry');
 h:=public.prepare_mobile_reevaluation_photo_disposition((discarded->>'user')::uuid,(discarded->>'cycle')::uuid,(discarded->>'acceptance')::uuid)->'disposition';
 page:=public.get_mobile_reevaluation_photo_disposition_page((discarded->>'user')::uuid,(h->>'id')::uuid,(h->>'sweep_no')::bigint,(h->>'capability_revision')::bigint,NULL);
 SELECT array_agg((x->>'asset_id')::uuid ORDER BY x->>'asset_id') INTO ids FROM jsonb_array_elements(page->'items') x;
 ack:=public.commit_mobile_reevaluation_photo_disposition_page((discarded->>'user')::uuid,(h->>'id')::uuid,(h->>'sweep_no')::bigint,(h->>'capability_revision')::bigint,NULL,ids);
 PERFORM m3b_cycle_test.ok(ack->>'state'='waiting','unknown_signed_upload_requires_resweep');
 r:=public.claim_mobile_reevaluation_photo_cleanup_scopes(100);
 PERFORM m3b_cycle_test.ok(NOT EXISTS(SELECT 1 FROM jsonb_array_elements(r->'items') x WHERE x->>'acceptance_id'=discarded->>'acceptance'),'future_wait_is_not_reclaimed_early');
 PERFORM public.register_mobile_reevaluation_photo_upload_ticket((discarded->>'user')::uuid,(discarded->>'cycle')::uuid,(discarded->>'asset')::uuid,ticket,clock_timestamp()+interval '2hours');
 r:=public.claim_mobile_reevaluation_photo_cleanup_scopes(100);
 PERFORM m3b_cycle_test.ok(EXISTS(SELECT 1 FROM jsonb_array_elements(r->'items') x WHERE x->>'acceptance_id'=discarded->>'acceptance'),'late_provider_expiry_reopens_and_is_discovered');
 reset_scope:=m3b_cycle_test.cleanup_context(5404);
 PERFORM public.reset_user_conversation_atomic((reset_scope->>'user')::uuid,true);
 r:=public.claim_mobile_reevaluation_photo_cleanup_scopes(100);
 PERFORM m3b_cycle_test.ok(EXISTS(SELECT 1 FROM jsonb_array_elements(r->'items') x WHERE x->>'acceptance_id'=reset_scope->>'acceptance'),'historical_generation_after_reset_is_not_filtered_out');
 deleted_scope:=m3b_cycle_test.cleanup_context(5405,86420);
 UPDATE public.users SET status='deleted' WHERE id=(deleted_scope->>'user')::uuid;
 r:=public.claim_mobile_reevaluation_photo_cleanup_scopes(100);
 PERFORM m3b_cycle_test.ok(NOT EXISTS(SELECT 1 FROM jsonb_array_elements(r->'items') x WHERE x->>'user_id'=deleted_scope->>'user'),'deleted_account_remains_with_its_existing_purger');
 due_wait:=m3b_cycle_test.cleanup_context(5406,3600);
 SELECT last_activity_at INTO t FROM private.mobile_reevaluation_photo_consents WHERE acceptance_id=(due_wait->>'acceptance')::uuid;
 PERFORM private.prepare_mobile_reevaluation_photo_upload_at((due_wait->>'user')::uuid,(due_wait->>'cycle')::uuid,(due_wait->>'asset')::uuid,gen_random_uuid(),t+interval '1second');
 PERFORM private.seal_mobile_reevaluation_photo_disposition_at((due_wait->>'user')::uuid,(due_wait->>'cycle')::uuid,(due_wait->>'acceptance')::uuid,'discarded',t+interval '2seconds');
 h:=private.prepare_mobile_reevaluation_photo_disposition_at((due_wait->>'user')::uuid,(due_wait->>'cycle')::uuid,(due_wait->>'acceptance')::uuid,t+interval '3seconds')->'disposition';
 page:=public.get_mobile_reevaluation_photo_disposition_page((due_wait->>'user')::uuid,(h->>'id')::uuid,(h->>'sweep_no')::bigint,(h->>'capability_revision')::bigint,NULL);
 SELECT array_agg((x->>'asset_id')::uuid ORDER BY x->>'asset_id') INTO ids FROM jsonb_array_elements(page->'items') x;
 ack:=private.commit_mobile_reevaluation_photo_disposition_page_at((due_wait->>'user')::uuid,(h->>'id')::uuid,(h->>'sweep_no')::bigint,(h->>'capability_revision')::bigint,NULL,ids,t+interval '4seconds');
 PERFORM m3b_cycle_test.ok(ack->>'state'='waiting' AND(SELECT next_sweep_at<clock_timestamp() FROM private.mobile_reevaluation_photo_dispositions WHERE acceptance_id=(due_wait->>'acceptance')::uuid),'due_wait_fixture_uses_real_original_checkpoint');
 r:=public.claim_mobile_reevaluation_photo_cleanup_scopes(100);
 PERFORM m3b_cycle_test.ok(EXISTS(SELECT 1 FROM jsonb_array_elements(r->'items') x WHERE x->>'acceptance_id'=due_wait->>'acceptance'),'due_resweep_is_discovered');
 INSERT INTO public.legal_documents(id,document_key,version,locale,body,required_from)
  VALUES(m3b_cycle_test.uid(5498),'body_photo_reevaluation_consent','normal-cleanup-local-next','pt-BR','SYNTHETIC LOCAL CHANGED POLICY',clock_timestamp()-interval '1second');
 r:=public.claim_mobile_reevaluation_photo_cleanup_scopes(100);
 PERFORM m3b_cycle_test.ok(EXISTS(SELECT 1 FROM jsonb_array_elements(r->'items') x WHERE x->>'acceptance_id'=fresh->>'acceptance'),'changed_document_discovers_old_live_acceptance');
 PERFORM m3b_cycle_test.throws('SELECT public.claim_mobile_reevaluation_photo_cleanup_scopes(0)','22023','zero_limit_refused');
 PERFORM m3b_cycle_test.throws('SELECT public.claim_mobile_reevaluation_photo_cleanup_scopes(101)','22023','unbounded_limit_refused');
END $claim$;
SELECT m3b_cycle_test.ok(NOT has_function_privilege('anon','public.claim_mobile_reevaluation_photo_cleanup_scopes(integer)','EXECUTE')
 AND NOT has_function_privilege('authenticated','public.claim_mobile_reevaluation_photo_cleanup_scopes(integer)','EXECUTE')
 AND has_function_privilege('service_role','public.claim_mobile_reevaluation_photo_cleanup_scopes(integer)','EXECUTE'),'normal_cleanup_claim_backend_only');
SELECT m3b_cycle_test.ok(NOT has_table_privilege('service_role','private.mobile_reevaluation_photo_cleanup_visits','SELECT,INSERT,UPDATE,DELETE'),'technical_visits_no_direct_client_access');
SET LOCAL ROLE service_role;
DO $service$ BEGIN
 IF jsonb_typeof(public.claim_mobile_reevaluation_photo_cleanup_scopes(1)->'items')<>'array' THEN RAISE EXCEPTION 'M3B_ASSERT:actual_service_claim'; END IF;
 RAISE NOTICE 'M3B_PASS:actual_service_claim';
END $service$;
RESET ROLE;
ROLLBACK;
