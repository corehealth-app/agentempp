-- Local rollback-only behavior tests; never writes a real Storage payload.
BEGIN;
SET LOCAL request.jwt.claims='{"role":"service_role"}';
CREATE TEMP TABLE retention_cutover_assertions(label text);
CREATE FUNCTION pg_temp.cutover_ok(v boolean,label text) RETURNS void LANGUAGE plpgsql AS $$
BEGIN IF v IS DISTINCT FROM true THEN RAISE EXCEPTION 'RETENTION_CUTOVER_FAIL:%',label;END IF;
INSERT INTO retention_cutover_assertions VALUES(label);END $$;
DO $cases$
DECLARE u uuid:=gen_random_uuid();v uuid:=gen_random_uuid();w uuid:=gen_random_uuid();old_a uuid:=gen_random_uuid();
 fresh uuid:=gen_random_uuid();mixed uuid:=gen_random_uuid();solo uuid:=gen_random_uuid();
 old_b uuid:=gen_random_uuid();unqualified uuid:=gen_random_uuid();photo uuid:=gen_random_uuid();
 orphan uuid:=gen_random_uuid();
 t uuid:=gen_random_uuid();old_t uuid:=gen_random_uuid();p jsonb;q jsonb;before_old jsonb;
 before_debt jsonb;cutoff timestamptz;denied boolean;
BEGIN
 INSERT INTO public.users(id,email,status) VALUES(u,'cutover-'||u||'@example.invalid','active'),(v,'cutover-'||v||'@example.invalid','active'),(w,'cutover-'||w||'@example.invalid','active');
 INSERT INTO public.media_assets(id,user_id,kind,bucket_id,object_path,mime_type,declared_size_bytes,status,source_request_hash,retention_until,created_at)
 VALUES(old_a,u,'audio_note','audio-notes',u||'/'||old_a||'.m4a','audio/mp4',8,'pending_upload',repeat('1',64),clock_timestamp()+interval '1day',clock_timestamp()-interval '1day'),
 (fresh,u,'audio_note','audio-notes',u||'/'||fresh||'.m4a','audio/mp4',8,'pending_upload',repeat('2',64),clock_timestamp()+interval '1day',clock_timestamp()),
 (old_b,u,'conversation_photo','meal-photos',u||'/'||old_b||'.jpg','image/jpeg',8,'pending_upload',repeat('3',64),clock_timestamp()-interval '1day',clock_timestamp()-interval '2days'),
 (unqualified,u,'audio_note','audio-notes',u||'/'||unqualified||'.m4a','audio/mp4',8,'pending_upload',repeat('4',64),clock_timestamp()-interval '1second',clock_timestamp()),
 (photo,u,'conversation_photo','meal-photos',u||'/'||photo||'.jpg','image/jpeg',8,'pending_upload',repeat('5',64),clock_timestamp()+interval '1day',clock_timestamp());
 -- Retrying issuance today must not turn an old asset into a new one.
 PERFORM public.prepare_conversation_media_upload(u,old_a,old_t);
 PERFORM public.prepare_conversation_media_upload(u,fresh,t);
 PERFORM public.prepare_conversation_media_upload(u,fresh,gen_random_uuid());
 PERFORM public.prepare_conversation_media_upload(u,photo,gen_random_uuid());
 UPDATE public.media_assets SET retention_until=clock_timestamp()-interval '1second' WHERE id IN(old_a,fresh,photo);
 INSERT INTO private.conversation_media_expiry_debts(asset_id,user_id,kind,bucket_id,object_path)
 VALUES(old_a,u,'audio_note','audio-notes',u||'/'||old_a||'.m4a');
 SELECT to_jsonb(a) INTO before_old FROM public.media_assets a WHERE id=old_a;
 SELECT to_jsonb(d) INTO before_debt FROM private.conversation_media_expiry_debts d WHERE asset_id=old_a;
 PERFORM public.register_conversation_media_upload(u,old_a,old_t,clock_timestamp()+interval '2hours');
 PERFORM pg_temp.cutover_ok((SELECT to_jsonb(a)=before_old FROM public.media_assets a WHERE id=old_a),'late registration of an old upload preserves its catalog');
 PERFORM pg_temp.cutover_ok((SELECT to_jsonb(d)=before_debt FROM private.conversation_media_expiry_debts d WHERE asset_id=old_a),'late old registration preserves existing debt');
 p:=public.claim_conversation_media_expiry_batch(100);
 PERFORM pg_temp.cutover_ok((SELECT to_jsonb(a)=before_old FROM public.media_assets a WHERE id=old_a),'old expired asset remains byte-for-byte unchanged despite new ticket');
 PERFORM pg_temp.cutover_ok((SELECT to_jsonb(d)=before_debt FROM private.conversation_media_expiry_debts d WHERE asset_id=old_a),'old debt is not leased or rewritten');
 PERFORM pg_temp.cutover_ok(EXISTS(SELECT 1 FROM jsonb_array_elements(p->'items') x WHERE x->>'asset_id'=fresh::text),'new qualified asset enters automatic cleanup');
 PERFORM pg_temp.cutover_ok(NOT EXISTS(SELECT 1 FROM jsonb_array_elements(p->'items') x WHERE x->>'asset_id'=old_a::text),'old asset is never exposed as a Storage task');
 PERFORM pg_temp.cutover_ok((SELECT status='deleted' AND processing_result IS NULL FROM public.media_assets WHERE id=fresh),'new catalog is closed before cleanup');
 PERFORM pg_temp.cutover_ok(NOT EXISTS(SELECT 1 FROM private.conversation_media_retention_cohort WHERE asset_id=old_a),'old retry creates no qualifying cohort');
 PERFORM pg_temp.cutover_ok((SELECT count(*)=1 FROM private.conversation_media_retention_cohort WHERE asset_id=fresh AND user_id=u AND ticket_id=t),'new prepared ticket binds durable owner and source');
 PERFORM pg_temp.cutover_ok((SELECT status='pending_upload' FROM public.media_assets WHERE id=old_b),'old expired photo without a debt is not enrolled');
 PERFORM pg_temp.cutover_ok(NOT EXISTS(SELECT 1 FROM private.conversation_media_expiry_debts WHERE asset_id=old_b),'no new debt for preserved old photo');
 PERFORM pg_temp.cutover_ok((SELECT status='pending_upload' FROM public.media_assets WHERE id=unqualified),'new but unqualified audio is not swept');
 PERFORM pg_temp.cutover_ok(EXISTS(SELECT 1 FROM jsonb_array_elements(p->'items') x WHERE x->>'asset_id'=photo::text),'new qualified photo is swept');
 PERFORM pg_temp.cutover_ok(jsonb_array_length(p->'items')=2 AND p->'has_more'='false'::jsonb,'preserved backlog cannot cause an automatic retry loop');
 PERFORM public.register_conversation_media_upload(u,fresh,t,clock_timestamp()+interval '2hours');
 PERFORM pg_temp.cutover_ok((SELECT claim_token IS NULL AND last_successful_sweep_at IS NULL FROM private.conversation_media_expiry_debts WHERE asset_id=fresh),'late new registration retains and resets its cleanup obligation');
 q:=public.claim_conversation_media_expiry_batch(100);
 PERFORM pg_temp.cutover_ok(EXISTS(SELECT 1 FROM jsonb_array_elements(q->'items') x WHERE x->>'asset_id'=fresh::text),'new late capability is swept again');
 PERFORM pg_temp.cutover_ok((SELECT to_jsonb(d)=before_debt FROM private.conversation_media_expiry_debts d WHERE asset_id=old_a),'new late capability does not lease old debt');
 PERFORM pg_temp.cutover_ok(NOT private.conversation_media_retention_eligible(fresh,v,'audio_note','audio-notes',u||'/'||fresh||'.m4a'),'foreign owner cannot borrow eligibility');
 PERFORM pg_temp.cutover_ok(NOT private.conversation_media_retention_eligible(fresh,u,'conversation_photo','meal-photos',u||'/'||fresh||'.jpg'),'kind and Storage path are bound');
 INSERT INTO public.media_assets(id,user_id,kind,bucket_id,object_path,mime_type,declared_size_bytes,status,source_request_hash,retention_until,created_at)
 VALUES(mixed,u,'audio_note','audio-notes',u||'/'||mixed||'.m4a','audio/mp4',8,'pending_upload',repeat('6',64),clock_timestamp()+interval '1day',clock_timestamp()),
 (solo,v,'audio_note','audio-notes',v||'/'||solo||'.m4a','audio/mp4',8,'pending_upload',repeat('7',64),clock_timestamp()+interval '1day',clock_timestamp());
 PERFORM public.prepare_conversation_media_upload(u,mixed,gen_random_uuid());
 PERFORM public.prepare_conversation_media_upload(v,solo,gen_random_uuid());
 UPDATE public.users SET status='deleted' WHERE id IN(u,v,w);cutoff:=clock_timestamp();
 PERFORM pg_temp.cutover_ok(NOT public.prepare_conversation_media_account_purge(u,cutoff),'mixed old/new account cannot purge preserved media');
 PERFORM pg_temp.cutover_ok((SELECT status='pending_upload' FROM public.media_assets WHERE id=mixed),'mixed preflight changes no new media before refusing');
 PERFORM pg_temp.cutover_ok((SELECT to_jsonb(a)=before_old FROM public.media_assets a WHERE id=old_a),'mixed preflight preserves old catalog exactly');
 PERFORM pg_temp.cutover_ok(NOT public.prepare_conversation_media_account_purge(v,cutoff),'new-only account waits for payload disposal');
 PERFORM pg_temp.cutover_ok((SELECT status='deleted' FROM public.media_assets WHERE id=solo),'new-only account enrolls its pending media');
 q:=public.claim_conversation_media_expiry_batch(100);
 PERFORM pg_temp.cutover_ok(EXISTS(SELECT 1 FROM jsonb_array_elements(q->'items') x WHERE x->>'asset_id'=solo::text),'new account cleanup debt is selected');
 DELETE FROM public.media_assets WHERE id=solo;
 UPDATE private.conversation_media_expiry_debts SET lease_until=last_attempt_at+interval '1microsecond' WHERE asset_id=solo;
 q:=public.claim_conversation_media_expiry_batch(100);
 PERFORM pg_temp.cutover_ok(EXISTS(SELECT 1 FROM jsonb_array_elements(q->'items') x WHERE x->>'asset_id'=solo::text),'new cleanup lineage survives catalog removal');
 PERFORM public.acknowledge_conversation_media_expiry_sweep(solo,v,(SELECT claim_token FROM private.conversation_media_expiry_debts WHERE asset_id=solo));
 INSERT INTO storage.objects(bucket_id,name,version,metadata) VALUES('audio-notes',v||'/'||solo||'.m4a','11110000-0000-4000-8000-000000000110','{"size":0,"mimetype":"audio/mp4"}');
 PERFORM pg_temp.cutover_ok(public.prepare_conversation_media_account_purge(v,cutoff),'new-only account can finish once actual empty-barrier metadata is ready');
 DELETE FROM public.users WHERE id=v;
 PERFORM pg_temp.cutover_ok(private.conversation_media_retention_eligible(solo,v,'audio_note','audio-notes',v||'/'||solo||'.m4a'),'independent new lineage survives account deletion');
 INSERT INTO private.conversation_media_expiry_debts(asset_id,user_id,kind,bucket_id,object_path)
 VALUES(orphan,w,'audio_note','audio-notes',w||'/'||orphan||'.m4a');
 PERFORM pg_temp.cutover_ok(NOT public.prepare_conversation_media_account_purge(w,cutoff),'missing old catalog cannot waive independent old-debt preservation');
 denied:=false;BEGIN UPDATE private.conversation_media_retention_cutover SET starts_at=starts_at-interval '2days';EXCEPTION WHEN check_violation THEN denied:=true;END;
 PERFORM pg_temp.cutover_ok(denied,'cutover cannot be moved to reclassify old media');
 denied:=false;BEGIN DELETE FROM private.conversation_media_retention_cohort WHERE asset_id=fresh;EXCEPTION WHEN check_violation THEN denied:=true;END;
 PERFORM pg_temp.cutover_ok(denied,'qualified lineage cannot be silently erased');
 PERFORM pg_temp.cutover_ok(NOT has_table_privilege('service_role','private.conversation_media_retention_cohort','INSERT,UPDATE,DELETE,SELECT'),'service role has no direct cohort access');
 PERFORM pg_temp.cutover_ok(NOT has_table_privilege('authenticated','private.conversation_media_retention_cutover','INSERT,UPDATE,DELETE,SELECT'),'client cannot change the cutover');
 PERFORM pg_temp.cutover_ok(NOT has_function_privilege('anon','public.claim_conversation_media_expiry_batch(integer)','EXECUTE'),'anonymous caller cannot claim cleanup');
 PERFORM pg_temp.cutover_ok(has_function_privilege('service_role','public.register_conversation_media_upload(uuid,uuid,uuid,timestamptz)','EXECUTE') AND has_function_privilege('service_role','public.claim_conversation_media_expiry_batch(integer)','EXECUTE') AND has_function_privilege('service_role','public.prepare_conversation_media_account_purge(uuid,timestamptz)','EXECUTE'),'all three existing service contracts remain callable');
END $cases$;
SELECT jsonb_build_object('assertions',(SELECT count(*) FROM retention_cutover_assertions));
ROLLBACK;
