\set ON_ERROR_STOP on
BEGIN;
SET LOCAL request.jwt.claims='{"role":"service_role"}';
\ir fixtures/mobile_reevaluation_photo_fixture.sql

DO $uncoordinated$
DECLARE ctx jsonb; a uuid; cutoff timestamptz:=clock_timestamp();
BEGIN
 ctx:=m3b_cycle_test.ready_photo(920);a:=(ctx->>'user')::uuid;
 -- The existing circular FK must remain effective; never weaken it for cleanup.
 PERFORM m3b_cycle_test.throws(format('DELETE FROM public.media_assets WHERE user_id=%L; SET CONSTRAINTS ALL IMMEDIATE',a),'23503','uncoordinated_catalog_delete_violates_real_fk');
 PERFORM m3b_cycle_test.ok(NOT public.purge_mobile_reevaluation_photo_catalog_for_deleted_user(a,cutoff),'active_owner_not_purgeable');
END $uncoordinated$;

CREATE FUNCTION m3b_cycle_test.settle_scope(ctx jsonb,at_time timestamptz DEFAULT NULL) RETURNS jsonb
LANGUAGE plpgsql SET search_path=pg_catalog AS $$
DECLARE prep jsonb;h jsonb;page jsonb;ids uuid[];
BEGIN
 prep:=private.prepare_mobile_reevaluation_photo_disposition_at((ctx->>'user')::uuid,(ctx->>'cycle')::uuid,(ctx->>'acceptance')::uuid,at_time);
 IF prep->>'kind'<>'ready' THEN RETURN prep;END IF;
 h:=prep->'disposition';
 page:=public.get_mobile_reevaluation_photo_disposition_page((ctx->>'user')::uuid,(h->>'id')::uuid,(h->>'sweep_no')::bigint,(h->>'capability_revision')::bigint,(h->>'cursor')::uuid);
 SELECT array_agg((x->>'asset_id')::uuid ORDER BY x->>'asset_id') INTO ids FROM jsonb_array_elements(page->'items') x;
 RETURN private.commit_mobile_reevaluation_photo_disposition_page_at((ctx->>'user')::uuid,(h->>'id')::uuid,(h->>'sweep_no')::bigint,(h->>'capability_revision')::bigint,(h->>'cursor')::uuid,ids,
  CASE WHEN at_time IS NULL THEN NULL ELSE at_time+interval '1microsecond' END);
END $$;

DO $waiting$
DECLARE ctx jsonb;a uuid;aid uuid;t uuid:=gen_random_uuid();r jsonb;before_state jsonb;expiry timestamptz;cutoff timestamptz;
BEGIN
 ctx:=m3b_cycle_test.photo_context(921);a:=(ctx->>'user')::uuid;
 aid:=(m3b_cycle_test.allocate(ctx,gen_random_uuid())#>>'{asset,id}')::uuid;
 PERFORM public.prepare_mobile_reevaluation_photo_upload(a,(ctx->>'cycle')::uuid,aid,t);
 UPDATE public.users SET status='deleted' WHERE id=a;
 cutoff:=clock_timestamp();before_state:=m3b_cycle_test.original_state(a);
 PERFORM m3b_cycle_test.ok(NOT public.purge_mobile_reevaluation_photo_catalog_for_deleted_user(a,cutoff),'missing_manifest_blocks_purge');
 PERFORM m3b_cycle_test.ok(m3b_cycle_test.original_state(a)=before_state,'false_missing_manifest_writes_no_rows');
 r:=m3b_cycle_test.settle_scope(ctx);
 PERFORM m3b_cycle_test.ok(r->>'state'='waiting','unknown_capability_waits');
 before_state:=m3b_cycle_test.original_state(a);
 PERFORM m3b_cycle_test.ok(NOT public.purge_mobile_reevaluation_photo_catalog_for_deleted_user(a,cutoff)
  AND m3b_cycle_test.original_state(a)=before_state,'unknown_ticket_retains_every_authority_row');
 r:=public.list_mobile_reevaluation_photo_purge_scopes(a,cutoff,NULL,20);
 PERFORM m3b_cycle_test.ok(r->>'eligible'='true' AND jsonb_array_length(r->'items')=0,'waiting_not_due_is_not_repeated_in_same_pass');
 expiry:=clock_timestamp()+interval '2hours';
 PERFORM public.register_mobile_reevaluation_photo_upload_ticket(a,(ctx->>'cycle')::uuid,aid,t,expiry);
 r:=public.list_mobile_reevaluation_photo_purge_scopes(a,cutoff,NULL,20);
 PERFORM m3b_cycle_test.ok(jsonb_array_length(r->'items')=1 AND r#>>'{items,0,acceptance_id}'=ctx->>'acceptance','late_registration_reopens_due_scope');
 r:=m3b_cycle_test.settle_scope(ctx);
 PERFORM m3b_cycle_test.ok(r->>'state'='waiting','still_live_url_blocks_purge');
 before_state:=m3b_cycle_test.original_state(a);
 PERFORM m3b_cycle_test.ok(NOT private.purge_mobile_reevaluation_photo_catalog_at(a,cutoff,expiry+interval '1second')
  AND m3b_cycle_test.original_state(a)=before_state,'elapsed_expiry_without_new_remove_is_not_proof');
 r:=m3b_cycle_test.settle_scope(ctx,expiry+interval '2seconds');
 PERFORM m3b_cycle_test.ok(r->>'state'='settled','synthetic_post_expiry_resweep_settles');
 PERFORM m3b_cycle_test.ok(private.purge_mobile_reevaluation_photo_catalog_at(a,cutoff,expiry+interval '3seconds'),'post_expiry_current_proof_allows_purge');
 PERFORM m3b_cycle_test.ok(NOT EXISTS(SELECT 1 FROM private.mobile_reevaluation_photo_assets WHERE user_id=a)
  AND NOT EXISTS(SELECT 1 FROM private.mobile_reevaluation_photo_upload_tickets WHERE user_id=a),'ticket_and_ledger_removed_together');
END $waiting$;

CREATE FUNCTION m3b_cycle_test.fail_purge_ticket() RETURNS trigger LANGUAGE plpgsql SET search_path=pg_catalog AS $$
BEGIN RAISE EXCEPTION 'synthetic_mid_purge_failure' USING ERRCODE='P0001';END $$;

DO $atomic_and_isolated$
DECLARE ctx jsonb;otherctx jsonb;a uuid;c uuid;acc uuid;aid uuid;t uuid:=gen_random_uuid();r jsonb;before_state jsonb;other_state jsonb;signup_state jsonb;generic uuid;signup uuid:=gen_random_uuid();signup_owner uuid;cutoff timestamptz;
BEGIN
 ctx:=m3b_cycle_test.photo_context(922);a:=(ctx->>'user')::uuid;c:=(ctx->>'cycle')::uuid;acc:=(ctx->>'acceptance')::uuid;
 aid:=(m3b_cycle_test.allocate(ctx,gen_random_uuid())#>>'{asset,id}')::uuid;
 -- A ticket is needed for the injected failure. Complete it with a synthetic clock,
 -- then make the entire purge proof at that clock; no real Storage claim is made.
 PERFORM public.prepare_mobile_reevaluation_photo_upload(a,c,aid,t);
 PERFORM public.register_mobile_reevaluation_photo_upload_ticket(a,c,aid,t,clock_timestamp()+interval '1second');
 generic:=m3b_cycle_test.ordinary_asset(a,'meal_photo');
 signup_owner:=m3b_cycle_test.seed(925,NULL);
 INSERT INTO public.media_assets(id,user_id,kind,bucket_id,object_path,mime_type,declared_size_bytes,status,context_text,source_request_hash,retention_until,signup_origin)
 VALUES(signup,signup_owner,'body_checkin_photo','body-checkin-photos',signup_owner::text||'/'||signup::text||'.jpg','image/jpeg',1200,'pending_upload','Foto de frente.',repeat('a',64),clock_timestamp()+interval '1hour',true);
 signup_state:=m3b_cycle_test.original_state(signup_owner);
 otherctx:=m3b_cycle_test.ready_photo(923);other_state:=m3b_cycle_test.original_state((otherctx->>'user')::uuid);
 UPDATE public.users SET status='deleted' WHERE id=a;cutoff:=clock_timestamp();
 r:=m3b_cycle_test.settle_scope(ctx,cutoff+interval '2seconds');
 PERFORM m3b_cycle_test.ok(r->>'state'='settled','atomic_fixture_settled');
 before_state:=m3b_cycle_test.original_state(a);
 PERFORM m3b_cycle_test.ok(NOT private.purge_mobile_reevaluation_photo_catalog_at(a,cutoff-interval '1hour',cutoff+interval '3seconds')
  AND m3b_cycle_test.original_state(a)=before_state,'changed_cutoff_blocks_without_writes');
 CREATE TRIGGER synthetic_mid_purge_failure BEFORE DELETE ON private.mobile_reevaluation_photo_upload_tickets
  FOR EACH ROW EXECUTE FUNCTION m3b_cycle_test.fail_purge_ticket();
 PERFORM m3b_cycle_test.throws(format('SELECT private.purge_mobile_reevaluation_photo_catalog_at(%L,%L,%L)',a,cutoff,cutoff+interval '3seconds'),'P0001','mid_purge_failure_surfaces');
 PERFORM m3b_cycle_test.ok(m3b_cycle_test.original_state(a)=before_state,'mid_purge_failure_rolls_back_manifest_and_all_children');
 DROP TRIGGER synthetic_mid_purge_failure ON private.mobile_reevaluation_photo_upload_tickets;
 SET CONSTRAINTS ALL IMMEDIATE;
 PERFORM m3b_cycle_test.ok(private.purge_mobile_reevaluation_photo_catalog_at(a,cutoff,cutoff+interval '3seconds'),'purge_handles_existing_immediate_constraints');
 SET CONSTRAINTS ALL IMMEDIATE;
 PERFORM m3b_cycle_test.ok(NOT EXISTS(SELECT 1 FROM public.media_assets WHERE id=aid)
  AND NOT EXISTS(SELECT 1 FROM private.mobile_reevaluation_photo_dispositions WHERE user_id=a)
  AND NOT EXISTS(SELECT 1 FROM private.mobile_reevaluation_photo_sources WHERE user_id=a),'all_recurring_catalog_children_removed_fk_safe');
 PERFORM m3b_cycle_test.ok(EXISTS(SELECT 1 FROM public.users WHERE id=a)
  AND EXISTS(SELECT 1 FROM public.user_profiles WHERE user_id=a)
  AND EXISTS(SELECT 1 FROM private.mobile_reevaluation_cycles WHERE cycle_id=c),'purge_leaves_account_clinical_profile_and_cycle_for_existing_flow');
 PERFORM m3b_cycle_test.ok((SELECT count(*)=2 FROM public.media_assets WHERE id IN(generic,signup))
  AND m3b_cycle_test.original_state(signup_owner)=signup_state
  AND m3b_cycle_test.original_state((otherctx->>'user')::uuid)=other_state,'generic_signup_and_other_owner_untouched');
 PERFORM m3b_cycle_test.ok(private.purge_mobile_reevaluation_photo_catalog_at(a,cutoff,cutoff+interval '3seconds'),'completed_catalog_purge_replays_without_side_effects');
 SET CONSTRAINTS ALL DEFERRED;
END $atomic_and_isolated$;

DO $scope_progress$
DECLARE ctx jsonb;a uuid;c uuid;acc uuid;r jsonb;doc public.legal_documents%ROWTYPE;i integer;rev bigint;cutoff timestamptz;pending uuid;
BEGIN
 ctx:=m3b_cycle_test.photo_context(924);a:=(ctx->>'user')::uuid;c:=(ctx->>'cycle')::uuid;
 SELECT * INTO STRICT doc FROM public.legal_documents WHERE id=m3b_cycle_test.uid(501);
 FOR i IN 1..25 LOOP
  acc:=(ctx->>'acceptance')::uuid;SELECT revision INTO rev FROM private.mobile_reevaluation_cycles WHERE cycle_id=c;
  PERFORM public.discard_mobile_reevaluation_photos(a,c,acc,rev);
  PERFORM public.prepare_mobile_reevaluation_photo_disposition(a,c,acc);
  SELECT revision INTO rev FROM private.mobile_reevaluation_cycles WHERE cycle_id=c;
  r:=public.accept_mobile_reevaluation_photo_consent(a,c,rev,doc.id,doc.document_key,doc.version,doc.locale,doc.body_hash,gen_random_uuid());
  ctx:=ctx||jsonb_build_object('acceptance',r#>'{acceptance,acceptance_id}','revision',r->'cycle_revision');
 END LOOP;
 pending:=(ctx->>'acceptance')::uuid;
 PERFORM m3b_cycle_test.allocate(ctx,gen_random_uuid());UPDATE public.users SET status='deleted' WHERE id=a;cutoff:=clock_timestamp();
 r:=public.list_mobile_reevaluation_photo_purge_scopes(a,cutoff,NULL,1);
 PERFORM m3b_cycle_test.ok(jsonb_array_length(r->'items')=1 AND r#>>'{items,0,acceptance_id}'=pending::text
  AND r->>'has_more'='false','settled_history_does_not_starve_later_due_scope');
 PERFORM m3b_cycle_test.settle_scope(ctx);
 r:=public.list_mobile_reevaluation_photo_purge_scopes(a,cutoff,NULL,1);
 PERFORM m3b_cycle_test.ok(jsonb_array_length(r->'items')=0 AND r->'cursor'='null'::jsonb,'durable_progress_leaves_due_set');
 PERFORM m3b_cycle_test.ok(public.purge_mobile_reevaluation_photo_catalog_for_deleted_user(a,cutoff),'all_settled_history_purges');
 PERFORM m3b_cycle_test.throws(format('SELECT public.list_mobile_reevaluation_photo_purge_scopes(%L,%L,NULL,0)',a,cutoff),'22023','invalid_scope_limit_refused');
 PERFORM m3b_cycle_test.ok(NOT has_function_privilege('authenticated','public.purge_mobile_reevaluation_photo_catalog_for_deleted_user(uuid,timestamptz)','EXECUTE')
  AND NOT has_function_privilege('service_role','private.purge_mobile_reevaluation_photo_catalog_at(uuid,timestamptz,timestamptz)','EXECUTE')
  AND has_function_privilege('service_role','public.list_mobile_reevaluation_photo_purge_scopes(uuid,timestamptz,uuid,integer)','EXECUTE'),'purge_apis_backend_only_private_clock_hidden');
END $scope_progress$;
ROLLBACK;
