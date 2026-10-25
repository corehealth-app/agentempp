\set ON_ERROR_STOP on
BEGIN;
SET LOCAL request.jwt.claims='{"role":"service_role"}';
\ir fixtures/mobile_reevaluation_photo_fixture.sql



DO $owners$
DECLARE n integer;cutoff timestamptz;first_batch jsonb;second_batch jsonb;before_users jsonb;after_users jsonb;last_owner uuid:=m3b_cycle_test.uid(1100);
BEGIN
 FOR n IN 1000..1100 LOOP
  PERFORM m3b_cycle_test.seed(n,NULL);
 END LOOP;
 UPDATE public.users SET status='deleted' WHERE id BETWEEN m3b_cycle_test.uid(1000) AND m3b_cycle_test.uid(1100);cutoff:=clock_timestamp();
 SELECT jsonb_agg(to_jsonb(u) ORDER BY id) INTO before_users FROM public.users u;
 first_batch:=public.list_mobile_deleted_users_for_photo_purge(cutoff,100);
 FOR n IN 1000..1099 LOOP PERFORM public.begin_mobile_deleted_user_photo_purge(m3b_cycle_test.uid(n),cutoff);END LOOP;
 second_batch:=public.list_mobile_deleted_users_for_photo_purge(cutoff,100);
 PERFORM m3b_cycle_test.ok(jsonb_array_length(first_batch->'users')=100,'owner_claim_bounded_to_100');
 PERFORM m3b_cycle_test.ok(NOT EXISTS(SELECT 1 FROM jsonb_array_elements(first_batch->'users') x WHERE x->>'id'=last_owner::text)
  AND EXISTS(SELECT 1 FROM jsonb_array_elements(second_batch->'users') x WHERE x->>'id'=last_owner::text),'101st_owner_reached_even_when_first100_defer');
 SELECT jsonb_agg(to_jsonb(u) ORDER BY id) INTO after_users FROM public.users u;
 PERFORM m3b_cycle_test.ok(before_users=after_users,'rotation_never_changes_owner_eligibility_or_updated_at');
 PERFORM m3b_cycle_test.ok((SELECT count(*)=100 FROM private.mobile_reevaluation_photo_purge_owner_visits),'owner_visits_durable_across_calls');
END $owners$;
DO $scopes$
DECLARE ctx jsonb;a uuid;c uuid;acc uuid;aid uuid;tid uuid;r jsonb;h jsonb;doc public.legal_documents%ROWTYPE;rev bigint;i integer;cutoff timestamptz;first_batch jsonb;second_batch jsonb;remaining uuid;before_rows jsonb;
BEGIN
 ctx:=m3b_cycle_test.photo_context(1110);a:=(ctx->>'user')::uuid;c:=(ctx->>'cycle')::uuid;
 SELECT * INTO STRICT doc FROM public.legal_documents WHERE id=m3b_cycle_test.uid(501);
 -- Pre-quota historical scopes; retain the full 21-scope starvation regression.
 SET CONSTRAINTS private.mobile_reevaluation_photo_ass_asset_id_user_id_origin_vers_fkey IMMEDIATE;
 ALTER TABLE private.mobile_reevaluation_photo_assets DISABLE TRIGGER enforce_mobile_reevaluation_photo_quota;
 SET CONSTRAINTS private.mobile_reevaluation_photo_ass_asset_id_user_id_origin_vers_fkey DEFERRED;
 FOR i IN 1..21 LOOP
  acc:=(ctx->>'acceptance')::uuid;
  r:=m3b_cycle_test.allocate(ctx,gen_random_uuid());aid:=(r#>>'{asset,id}')::uuid;
  tid:=gen_random_uuid();PERFORM public.prepare_mobile_reevaluation_photo_upload(a,c,aid,tid);
  PERFORM public.discard_mobile_reevaluation_photos(a,c,acc,(r->>'cycle_revision')::bigint);
  h:=public.prepare_mobile_reevaluation_photo_disposition(a,c,acc)->'disposition';
  PERFORM public.commit_mobile_reevaluation_photo_disposition_page(a,(h->>'id')::uuid,(h->>'sweep_no')::bigint,(h->>'capability_revision')::bigint,NULL,ARRAY[aid]);
  IF i<21 THEN
   SELECT revision INTO rev FROM private.mobile_reevaluation_cycles WHERE cycle_id=c;
   r:=public.accept_mobile_reevaluation_photo_consent(a,c,rev,doc.id,doc.document_key,doc.version,doc.locale,doc.body_hash,gen_random_uuid());
   ctx:=ctx||jsonb_build_object('acceptance',r#>'{acceptance,acceptance_id}','revision',r->'cycle_revision');
  END IF;
 END LOOP;
 SET CONSTRAINTS private.mobile_reevaluation_photo_ass_asset_id_user_id_origin_vers_fkey IMMEDIATE;
 ALTER TABLE private.mobile_reevaluation_photo_assets ENABLE TRIGGER enforce_mobile_reevaluation_photo_quota;
 SET CONSTRAINTS private.mobile_reevaluation_photo_ass_asset_id_user_id_origin_vers_fkey DEFERRED;
 PERFORM m3b_cycle_test.ok((SELECT tgenabled='O' FROM pg_trigger WHERE tgrelid='private.mobile_reevaluation_photo_assets'::regclass
  AND tgname='enforce_mobile_reevaluation_photo_quota'),'quota_enabled_after_legacy_21_scopes_seed');
 UPDATE public.users SET status='deleted' WHERE id=a;cutoff:=clock_timestamp();
 -- Make every unknown scope due again before EACH invocation, reproducing a late cron.
 UPDATE private.mobile_reevaluation_photo_dispositions SET next_sweep_at=clock_timestamp()-interval '1second' WHERE user_id=a;
 first_batch:=jsonb_build_object('items','[]'::jsonb,'has_more',true);
 FOR i IN 1..20 LOOP
  r:=public.claim_mobile_reevaluation_photo_purge_scopes(a,cutoff,1);
  first_batch:=jsonb_set(first_batch,'{items}',(first_batch->'items')||(r->'items'));
 END LOOP;
 SELECT acceptance_id INTO STRICT remaining FROM private.mobile_reevaluation_photo_consents t WHERE user_id=a
  AND NOT EXISTS(SELECT 1 FROM jsonb_array_elements(first_batch->'items') x WHERE x->>'acceptance_id'=t.acceptance_id::text);
 UPDATE private.mobile_reevaluation_photo_dispositions SET next_sweep_at=clock_timestamp()-interval '1second' WHERE user_id=a;
 second_batch:=public.claim_mobile_reevaluation_photo_purge_scopes(a,cutoff,1);
 PERFORM m3b_cycle_test.ok(jsonb_array_length(first_batch->'items')=20 AND first_batch->>'has_more'='true','scope_claim_preserves_20_budget');
 PERFORM m3b_cycle_test.ok(EXISTS(SELECT 1 FROM jsonb_array_elements(second_batch->'items') x WHERE x->>'acceptance_id'=remaining::text),'21st_scope_reached_when_first20_are_due_again');
 PERFORM m3b_cycle_test.ok((SELECT count(*)=21 FROM private.mobile_reevaluation_photo_purge_scope_visits WHERE user_id=a),'scope_visits_durable_across_calls');
 before_rows:=m3b_cycle_test.original_state(a);
 PERFORM m3b_cycle_test.ok(NOT public.purge_mobile_reevaluation_photo_catalog_for_deleted_user(a,cutoff)
  AND m3b_cycle_test.original_state(a)=before_rows,'fair_rotation_does_not_bypass_unknown_ticket_proof');
 PERFORM m3b_cycle_test.ok((SELECT count(*)=21 FROM private.mobile_reevaluation_photo_upload_tickets WHERE user_id=a AND provider_expires_at IS NULL)
  AND(SELECT count(*)=21 FROM private.mobile_reevaluation_photo_disposition_assets WHERE user_id=a),'all_unknown_paths_and_tickets_preserved');
 PERFORM m3b_cycle_test.ok(NOT has_table_privilege('service_role','private.mobile_reevaluation_photo_purge_owner_visits','SELECT')
  AND NOT has_table_privilege('authenticated','private.mobile_reevaluation_photo_purge_scope_visits','INSERT'),'visit_metadata_private');
END $scopes$;

ROLLBACK;
