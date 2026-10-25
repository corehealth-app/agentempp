\set ON_ERROR_STOP on
BEGIN;
SET LOCAL request.jwt.claims='{"role":"service_role"}';
\ir fixtures/mobile_reevaluation_photo_fixture.sql

CREATE FUNCTION m3b_cycle_test.cleanup_once(a uuid,c uuid,acc uuid,at_time timestamptz DEFAULT NULL) RETURNS jsonb
LANGUAGE plpgsql SET search_path=pg_catalog AS $$
DECLARE prep jsonb;h jsonb;page jsonb;ids uuid[];ack jsonb;
BEGIN
 prep:=private.prepare_mobile_reevaluation_photo_disposition_at(a,c,acc,at_time);
 IF prep->>'kind'<>'ready' THEN RETURN jsonb_build_object('prepare',prep); END IF;
 h:=prep->'disposition';
 page:=public.get_mobile_reevaluation_photo_disposition_page(a,(h->>'id')::uuid,(h->>'sweep_no')::bigint,(h->>'capability_revision')::bigint,(h->>'cursor')::uuid);
 SELECT array_agg((x->>'asset_id')::uuid ORDER BY x->>'asset_id') INTO ids FROM jsonb_array_elements(page->'items') x;
 ack:=private.commit_mobile_reevaluation_photo_disposition_page_at(a,(h->>'id')::uuid,(h->>'sweep_no')::bigint,(h->>'capability_revision')::bigint,(h->>'cursor')::uuid,ids,CASE WHEN at_time IS NULL THEN NULL ELSE at_time+interval '1microsecond' END);
 RETURN jsonb_build_object('prepare',prep,'page',page,'ack',ack);
END $$;

DO $discard$
DECLARE ctx jsonb; a uuid;c uuid;acc uuid;front uuid;extra uuid;allocated jsonb;h jsonb;prep jsonb;page jsonb;ack jsonb;ids uuid[];profile jsonb;activity timestamptz;rev bigint;
BEGIN
 ctx:=m3b_cycle_test.ready_photo(880);a:=(ctx->>'user')::uuid;c:=(ctx->>'cycle')::uuid;acc:=(ctx->>'acceptance')::uuid;front:=(ctx->>'asset')::uuid;
 SELECT to_jsonb(p) INTO profile FROM public.user_profiles p WHERE user_id=a;
 allocated:=m3b_cycle_test.allocate(ctx,gen_random_uuid());extra:=(allocated#>>'{asset,id}')::uuid;
 SELECT revision INTO rev FROM private.mobile_reevaluation_cycles WHERE cycle_id=c;
 SELECT last_activity_at INTO activity FROM private.mobile_reevaluation_photo_consents WHERE acceptance_id=acc;
 PERFORM m3b_cycle_test.throws(format('SELECT public.discard_mobile_reevaluation_photos(%L,%L,%L,%s)',a,c,acc,rev+1),'40001','discard_wrong_revision_refused');
 h:=public.discard_mobile_reevaluation_photos(a,c,acc,rev);
 PERFORM m3b_cycle_test.ok(h->>'reason'='discarded' AND h->>'manifest_count'='2','discard_seals_selected_and_unselected_pending');
 PERFORM m3b_cycle_test.ok(public.discard_mobile_reevaluation_photos(a,c,acc,rev)=h,'discard_exact_replay_stable');
 PERFORM m3b_cycle_test.ok((SELECT revoked_reason='discarded' AND last_activity_at=activity FROM private.mobile_reevaluation_photo_consents WHERE acceptance_id=acc),'discard_revokes_without_renewal');
 PERFORM m3b_cycle_test.ok((SELECT count(*)=2 AND bool_and(invalidated_reason='discarded') FROM private.mobile_reevaluation_photo_assets WHERE user_id=a),'all_members_invalidated');
 PERFORM m3b_cycle_test.ok((SELECT revision=rev+1 AND status='collecting' FROM private.mobile_reevaluation_cycles WHERE cycle_id=c),'discard_only_one_operational_revision_not_completion');
 PERFORM m3b_cycle_test.ok((SELECT to_jsonb(p)=profile FROM public.user_profiles p WHERE user_id=a),'discard_preserves_profile_targets_anchor');
 PERFORM m3b_cycle_test.throws(format('SELECT public.prepare_mobile_reevaluation_photo_upload(%L,%L,%L,%L)',a,c,extra,gen_random_uuid()),'40001','discard_blocks_further_signing');
 prep:=public.prepare_mobile_reevaluation_photo_disposition(a,c,acc);
 PERFORM m3b_cycle_test.ok(prep->>'kind'='ready','first_remove_is_immediate');
 h:=prep->'disposition';
 page:=public.get_mobile_reevaluation_photo_disposition_page(a,(h->>'id')::uuid,(h->>'sweep_no')::bigint,(h->>'capability_revision')::bigint,NULL);
 SELECT array_agg((x->>'asset_id')::uuid ORDER BY x->>'asset_id') INTO ids FROM jsonb_array_elements(page->'items') x;
 PERFORM m3b_cycle_test.ok(cardinality(ids)=2 AND front=ANY(ids) AND extra=ANY(ids) AND page->>'has_more'='false','page_contains_complete_original_membership');
 PERFORM m3b_cycle_test.throws(format('SELECT public.commit_mobile_reevaluation_photo_disposition_page(%L,%L,%s,%s,NULL,%L::uuid[])',a,h->>'id',h->>'sweep_no',h->>'capability_revision',ARRAY[ids[1]]),'40001','partial_ack_refused');
 PERFORM m3b_cycle_test.throws(format('SELECT public.commit_mobile_reevaluation_photo_disposition_page(%L,%L,%s,%s,NULL,%L::uuid[])',a,h->>'id',h->>'sweep_no',h->>'capability_revision',ARRAY[ids[1],ids[1]]),'40001','duplicate_ids_refused');
 PERFORM m3b_cycle_test.throws(format('SELECT public.commit_mobile_reevaluation_photo_disposition_page(%L,%L,%s,%s,NULL,%L::uuid[])',a,h->>'id',h->>'sweep_no',h->>'capability_revision',ARRAY[ids[2],ids[1]]),'40001','reordered_ids_refused');
 ack:=public.commit_mobile_reevaluation_photo_disposition_page(a,(h->>'id')::uuid,(h->>'sweep_no')::bigint,(h->>'capability_revision')::bigint,NULL,ids);
 PERFORM m3b_cycle_test.ok(ack->>'sweep_complete'='true' AND ack->>'state'='waiting','live_upload_capability_requires_resweep');
 PERFORM m3b_cycle_test.ok((SELECT count(*)=2 AND bool_and(status='deleted' AND processing_result IS NULL) FROM public.media_assets WHERE user_id=a),'catalog_ack_only_after_remove_attestation');
 PERFORM m3b_cycle_test.throws(format('SELECT public.commit_mobile_reevaluation_photo_disposition_page(%L,%L,%s,%s,NULL,%L::uuid[])',a,h->>'id',h->>'sweep_no',h->>'capability_revision',ids),'40001','old_ack_cannot_advance_twice');
 PERFORM m3b_cycle_test.ok(public.prepare_mobile_reevaluation_photo_disposition(a,c,acc)->>'kind'='waiting','waiting_does_not_immediately_repeat_remove');
END $discard$;

DO $tickets$
DECLARE ctx jsonb;a uuid;c uuid;acc uuid;aid uuid;ticket uuid:=gen_random_uuid();h jsonb;r jsonb;oldh jsonb;at_time timestamptz;expiry timestamptz;rev bigint;
BEGIN
 ctx:=m3b_cycle_test.photo_context(881);a:=(ctx->>'user')::uuid;c:=(ctx->>'cycle')::uuid;acc:=(ctx->>'acceptance')::uuid;
 h:=m3b_cycle_test.allocate(ctx,gen_random_uuid());aid:=(h#>>'{asset,id}')::uuid;
 PERFORM public.prepare_mobile_reevaluation_photo_upload(a,c,aid,ticket);
 SELECT revision INTO rev FROM private.mobile_reevaluation_cycles WHERE cycle_id=c;
 PERFORM public.discard_mobile_reevaluation_photos(a,c,acc,rev);at_time:=clock_timestamp();
 r:=m3b_cycle_test.cleanup_once(a,c,acc,at_time);oldh:=r#>'{prepare,disposition}';
 PERFORM m3b_cycle_test.ok(r#>>'{ack,state}'='waiting','unknown_ticket_never_settles');
 PERFORM m3b_cycle_test.ok((SELECT next_sweep_at>=at_time+interval '900seconds' FROM private.mobile_reevaluation_photo_dispositions WHERE acceptance_id=acc),'unknown_ticket_has_bounded_retry_cadence_not_invented_expiry');
 expiry:=at_time+interval '30days';
 PERFORM private.register_mobile_reevaluation_photo_upload_ticket_at(a,c,aid,ticket,expiry,at_time+interval '1second');
 h:=private.mobile_reevaluation_photo_disposition_wire((SELECT x FROM private.mobile_reevaluation_photo_dispositions x WHERE acceptance_id=acc));
 PERFORM m3b_cycle_test.ok(h->>'capability_revision'='2' AND h->>'sweep_state'='idle','late_actual_expiry_reopens_durable_scope');
 PERFORM m3b_cycle_test.ok((SELECT provider_expires_at=expiry FROM private.mobile_reevaluation_photo_upload_tickets WHERE ticket_id=ticket),'anomalously_far_expiry_preserved_untruncated');
 PERFORM m3b_cycle_test.throws(format('SELECT public.commit_mobile_reevaluation_photo_disposition_page(%L,%L,%s,%s,NULL,%L::uuid[])',a,oldh->>'id',oldh->>'sweep_no',oldh->>'capability_revision',ARRAY[aid]),'40001','old_capability_ack_cannot_finish');
 PERFORM private.register_mobile_reevaluation_photo_upload_ticket_at(a,c,aid,ticket,expiry,at_time+interval '2seconds');
 PERFORM m3b_cycle_test.ok((SELECT capability_revision=2 FROM private.mobile_reevaluation_photo_dispositions WHERE acceptance_id=acc),'registration_replay_does_not_bump_capability_revision');
 r:=private.prepare_mobile_reevaluation_photo_disposition_at(a,c,acc,at_time+interval '3seconds');h:=r->'disposition';
 r:=private.commit_mobile_reevaluation_photo_disposition_page_at(a,(h->>'id')::uuid,(h->>'sweep_no')::bigint,(h->>'capability_revision')::bigint,NULL,ARRAY[aid],expiry+interval '1second');
 PERFORM m3b_cycle_test.ok(r->>'state'='waiting','ack_after_expiry_is_not_enough_when_remove_began_before');
 r:=m3b_cycle_test.cleanup_once(a,c,acc,expiry+interval '2seconds');
 PERFORM m3b_cycle_test.ok(r#>>'{ack,state}'='settled' AND r#>>'{prepare,disposition,sweep_no}'='3','post_capability_full_resweep_settles');
 PERFORM m3b_cycle_test.ok((SELECT last_activity_at=(SELECT created_at FROM public.media_assets WHERE id=aid) FROM private.mobile_reevaluation_photo_consents WHERE acceptance_id=acc),'resweep_never_renews_idle_activity');
 PERFORM m3b_cycle_test.ok(private.prepare_mobile_reevaluation_photo_disposition_at(a,c,acc,expiry+interval '3seconds')->>'kind'='settled','settled_replay_never_restarts_provider_or_storage');
END $tickets$;

DO $expiry_and_new_acceptance$
DECLARE ctx jsonb;a uuid;c uuid;acc uuid;oldasset uuid;fresh uuid;base_time timestamptz;expiry timestamptz;r jsonb;newacc jsonb;doc public.legal_documents%ROWTYPE;rev bigint;newctx jsonb;
BEGIN
 ctx:=m3b_cycle_test.ready_photo(882);a:=(ctx->>'user')::uuid;c:=(ctx->>'cycle')::uuid;acc:=(ctx->>'acceptance')::uuid;oldasset:=(ctx->>'asset')::uuid;
 SELECT last_activity_at,last_activity_at+make_interval(secs=>idle_timeout_seconds) INTO base_time,expiry FROM private.mobile_reevaluation_photo_consents WHERE acceptance_id=acc;
 r:=private.prepare_mobile_reevaluation_photo_disposition_at(a,c,acc,expiry-interval '1microsecond');
 PERFORM m3b_cycle_test.ok(r->>'kind'='live' AND r->'disposition'='null'::jsonb,'before_idle_boundary_live_scope_untouched');
 r:=private.prepare_mobile_reevaluation_photo_disposition_at(a,c,acc,expiry);
 PERFORM m3b_cycle_test.ok(r#>>'{disposition,reason}'='expired' AND r->>'kind'='ready','at_idle_boundary_seals_expired_scope');
 SELECT revision INTO rev FROM private.mobile_reevaluation_cycles WHERE cycle_id=c;
 SELECT * INTO doc FROM public.legal_documents WHERE id=m3b_cycle_test.uid(501);
 newacc:=private.accept_mobile_reevaluation_photo_consent_at(a,c,rev,doc.id,doc.document_key,doc.version,doc.locale,doc.body_hash,gen_random_uuid(),expiry+interval '1second');
 newctx:=ctx||jsonb_build_object('acceptance',newacc#>'{acceptance,acceptance_id}','revision',newacc->'cycle_revision');
 fresh:=(m3b_cycle_test.allocate(newctx,gen_random_uuid(),'front',1200,expiry+interval '2seconds')#>>'{asset,id}')::uuid;
 r:=m3b_cycle_test.cleanup_once(a,c,acc,expiry+interval '3seconds');
 PERFORM m3b_cycle_test.ok(jsonb_array_length(r#>'{page,items}')=1 AND r#>>'{page,items,0,asset_id}'=oldasset::text,'old_scope_remove_does_not_capture_new_acceptance');
 PERFORM m3b_cycle_test.ok((SELECT status='pending_upload' FROM public.media_assets WHERE id=fresh)
  AND(SELECT invalidated_at IS NULL FROM private.mobile_reevaluation_photo_assets WHERE asset_id=fresh),'fresh_photo_survives_old_scope_cleanup');
 PERFORM m3b_cycle_test.ok((SELECT revoked_at IS NULL AND last_activity_at=expiry+interval '2seconds' FROM private.mobile_reevaluation_photo_consents WHERE acceptance_id=(newctx->>'acceptance')::uuid),'fresh_consent_and_activity_preserved');
 r:=public.list_mobile_reevaluation_photo_disposition_scopes(a,NULL,1);
 PERFORM m3b_cycle_test.ok(jsonb_array_length(r->'items')=1 AND r->>'has_more'='true','scope_list_keyset_first_page_bounded');
 r:=public.list_mobile_reevaluation_photo_disposition_scopes(a,(r->>'cursor')::uuid,1);
 PERFORM m3b_cycle_test.ok(jsonb_array_length(r->'items')=1 AND r->>'has_more'='false','scope_list_keyset_second_page_no_loss');

END $expiry_and_new_acceptance$;

DO $context_closure$
DECLARE ctx jsonb;a uuid;c uuid;acc uuid;aid uuid;r jsonb;mode text;n integer:=883;rid uuid;
BEGIN
 FOREACH mode IN ARRAY ARRAY['reset','locale','deleted'] LOOP
  ctx:=m3b_cycle_test.ready_photo(n);n:=n+1;a:=(ctx->>'user')::uuid;c:=(ctx->>'cycle')::uuid;acc:=(ctx->>'acceptance')::uuid;aid:=(ctx->>'asset')::uuid;rid:=gen_random_uuid();
  PERFORM public.claim_mobile_reevaluation_photo_processing(a,c,aid,rid);PERFORM public.authorize_mobile_reevaluation_photo_provider(a,c,aid,rid);
  IF mode='reset' THEN PERFORM public.reset_user_conversation_atomic(a,true);
  ELSIF mode='locale' THEN UPDATE public.users SET locale='en-US' WHERE id=a;
  ELSE UPDATE public.users SET status='deleted' WHERE id=a;END IF;
  r:=public.prepare_mobile_reevaluation_photo_disposition(a,c,acc);
  PERFORM m3b_cycle_test.ok(r->>'kind'='ready','cleanup_can_capture_old_scope_after_'||mode);
  PERFORM m3b_cycle_test.throws(format('SELECT public.complete_mobile_reevaluation_photo_processing(%L,%L,%L,%L,''{"type":"body","view":"front","bf_percent_estimate":20}'')',a,c,aid,rid),CASE WHEN mode='deleted' THEN 'P0002' ELSE '40001' END,'sealed_scope_blocks_provider_callback_'||mode);
 END LOOP;
END $context_closure$;

DO $pages_and_isolation$
DECLARE ctx jsonb;otherctx jsonb;a uuid;c uuid;acc uuid;r jsonb;h jsonb;page jsonb;first uuid;generic_id uuid;ordinary_before jsonb;other_before jsonb;i integer;
BEGIN
 ctx:=m3b_cycle_test.photo_context(886);a:=(ctx->>'user')::uuid;c:=(ctx->>'cycle')::uuid;acc:=(ctx->>'acceptance')::uuid;
 generic_id:=m3b_cycle_test.ordinary_asset(a,'meal_photo');SELECT to_jsonb(x) INTO ordinary_before FROM public.media_assets x WHERE id=generic_id;
 otherctx:=m3b_cycle_test.ready_photo(887);SELECT to_jsonb(x) INTO other_before FROM public.media_assets x WHERE id=(otherctx->>'asset')::uuid;
 FOR i IN 1..201 LOOP
  r:=m3b_cycle_test.allocate(ctx,gen_random_uuid());ctx:=ctx||jsonb_build_object('revision',r->'cycle_revision');
 END LOOP;
 h:=public.discard_mobile_reevaluation_photos(a,c,acc,(ctx->>'revision')::bigint);
 PERFORM m3b_cycle_test.ok(h->>'manifest_count'='201','manifest_uses_all_ledger_members_not_only_latest_source');
 r:=m3b_cycle_test.cleanup_once(a,c,acc);
 PERFORM m3b_cycle_test.ok(jsonb_array_length(r#>'{page,items}')=200 AND r#>>'{page,has_more}'='true' AND r#>>'{ack,sweep_complete}'='false','first_page_is_exactly_200_not_partial_settlement');
 r:=m3b_cycle_test.cleanup_once(a,c,acc);
 PERFORM m3b_cycle_test.ok(jsonb_array_length(r#>'{page,items}')=1 AND r#>>'{ack,state}'='settled','second_page_finishes_all_201_no_capabilities');
 PERFORM m3b_cycle_test.ok((SELECT to_jsonb(x)=ordinary_before FROM public.media_assets x WHERE id=generic_id)
  AND(SELECT to_jsonb(x)=other_before FROM public.media_assets x WHERE id=(otherctx->>'asset')::uuid),'generic_and_other_owner_media_byte_exact');
 PERFORM m3b_cycle_test.throws(format('UPDATE private.mobile_reevaluation_photo_dispositions SET reason=''completed'' WHERE acceptance_id=%L',acc),'55000','sealed_reason_immutable');
 PERFORM m3b_cycle_test.throws(format('UPDATE private.mobile_reevaluation_photo_disposition_assets SET object_path=''bad'' WHERE disposition_id=%L',h->>'id'),'55000','sealed_paths_immutable');
 PERFORM m3b_cycle_test.throws(format('SELECT public.get_mobile_reevaluation_photo_disposition_page(%L,%L,1,1,NULL)',otherctx->>'user',h->>'id'),'P0002','other_owner_cannot_read_paths');
 PERFORM m3b_cycle_test.ok(NOT has_table_privilege('service_role','private.mobile_reevaluation_photo_dispositions','SELECT') AND NOT has_table_privilege('authenticated','private.mobile_reevaluation_photo_disposition_assets','SELECT'),'private_manifest_acl_closed');
 PERFORM m3b_cycle_test.ok(has_function_privilege('service_role','public.prepare_mobile_reevaluation_photo_disposition(uuid,uuid,uuid)','EXECUTE') AND NOT has_function_privilege('authenticated','public.discard_mobile_reevaluation_photos(uuid,uuid,uuid,bigint)','EXECUTE'),'only_backend_can_invoke_disposition');
 ctx:=m3b_cycle_test.photo_context(888);a:=(ctx->>'user')::uuid;c:=(ctx->>'cycle')::uuid;acc:=(ctx->>'acceptance')::uuid;
 PERFORM public.discard_mobile_reevaluation_photos(a,c,acc,(ctx->>'revision')::bigint);
 PERFORM m3b_cycle_test.ok(public.prepare_mobile_reevaluation_photo_disposition(a,c,acc)->>'kind'='settled','zero_photo_scope_settles_without_storage');
END $pages_and_isolation$;

DO $failed_upload_and_publication$
DECLARE ctx jsonb;a uuid;c uuid;acc uuid;aid uuid;r jsonb;
BEGIN
 ctx:=m3b_cycle_test.photo_context(890);a:=(ctx->>'user')::uuid;c:=(ctx->>'cycle')::uuid;acc:=(ctx->>'acceptance')::uuid;
 r:=m3b_cycle_test.allocate(ctx,gen_random_uuid());aid:=(r#>>'{asset,id}')::uuid;
 UPDATE public.media_assets SET status='failed',failure_stage='upload',failure_code='synthetic_failure' WHERE id=aid;
 PERFORM public.discard_mobile_reevaluation_photos(a,c,acc,(r->>'cycle_revision')::bigint);
 r:=m3b_cycle_test.cleanup_once(a,c,acc);
 PERFORM m3b_cycle_test.ok(r#>>'{ack,assets,0,catalogue_state}'='failed_upload_preserved' AND r#>>'{ack,state}'='settled','failed_upload_still_has_storage_remove_attestation');
 PERFORM m3b_cycle_test.ok((SELECT status='failed' AND failure_stage='upload' AND failure_code='synthetic_failure' FROM public.media_assets WHERE id=aid),'upload_failure_catalog_evidence_preserved');
 ctx:=m3b_cycle_test.ready_photo(891);a:=(ctx->>'user')::uuid;c:=(ctx->>'cycle')::uuid;acc:=(ctx->>'acceptance')::uuid;
 INSERT INTO public.legal_documents(id,document_key,version,locale,body,required_from) VALUES(m3b_cycle_test.uid(507),'body_photo_reevaluation_consent','synthetic-unenabled-new-doc','pt-BR','SYNTHETIC LOCAL NEW DOCUMENT WITHOUT POLICY',clock_timestamp()-interval '1second');
 r:=public.prepare_mobile_reevaluation_photo_disposition(a,c,acc);
 PERFORM m3b_cycle_test.ok(r->>'kind'='ready' AND r#>>'{disposition,reason}'='consent_changed','effective_unenabled_new_document_seals_old_scope');
 PERFORM m3b_cycle_test.ok(NOT has_function_privilege('service_role','private.seal_mobile_reevaluation_photo_disposition_at(uuid,uuid,uuid,text,timestamptz)','EXECUTE'),'completed_hook_never_exposed_to_backend_role');
END $failed_upload_and_publication$;

DO $approved_timeout_duration$
DECLARE a uuid;c uuid;acc jsonb;doc public.legal_documents%ROWTYPE;ctx jsonb;allocated jsonb;created timestamptz;r jsonb;
BEGIN
 INSERT INTO public.legal_documents(id,document_key,version,locale,body,required_from) VALUES(m3b_cycle_test.uid(506),'body_photo_reevaluation_consent','synthetic-duration-86400','pt-BR','SYNTHETIC LOCAL TIMEOUT DURATION; NOT APPROVED TEXT',clock_timestamp()-interval '1second') RETURNING * INTO doc;
 INSERT INTO private.mobile_reevaluation_photo_policies(document_id,document_key,version,locale,body_hash,idle_timeout_seconds,enabled) VALUES(doc.id,doc.document_key,doc.version,doc.locale,doc.body_hash,86400,true);
 a:=m3b_cycle_test.seed(889,'2026-10-01T23:00:00Z');c:=(public.start_mobile_reevaluation_cycle(a,gen_random_uuid())#>>'{cycle,id}')::uuid;
 acc:=public.accept_mobile_reevaluation_photo_consent(a,c,1,doc.id,doc.document_key,doc.version,doc.locale,doc.body_hash,gen_random_uuid());
 ctx:=jsonb_build_object('user',a,'cycle',c,'acceptance',acc#>'{acceptance,acceptance_id}','revision',acc->'cycle_revision');allocated:=m3b_cycle_test.allocate(ctx,gen_random_uuid());
 created:=(allocated#>>'{asset,created_at}')::timestamptz;
 r:=private.prepare_mobile_reevaluation_photo_disposition_at(a,c,(ctx->>'acceptance')::uuid,created+interval '86399seconds');
 PERFORM m3b_cycle_test.ok(r->>'kind'='live','configured_24h_has_not_expired_at_86399_seconds');
 r:=private.prepare_mobile_reevaluation_photo_disposition_at(a,c,(ctx->>'acceptance')::uuid,created+interval '86400seconds');
 PERFORM m3b_cycle_test.ok(r->>'kind'='ready' AND r#>>'{disposition,reason}'='expired','configured_24h_expires_at_exact_86400_seconds');
END $approved_timeout_duration$;

ROLLBACK;
