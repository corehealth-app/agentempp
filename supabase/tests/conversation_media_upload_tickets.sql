-- Owned local transaction; synthetic users, no Storage/provider requests.
BEGIN;
SET LOCAL request.jwt.claims='{"role":"service_role"}';
CREATE TEMP TABLE upload_assertions(label text);
CREATE FUNCTION pg_temp.upload_ok(v boolean,label text) RETURNS void LANGUAGE plpgsql AS $$
BEGIN IF v IS DISTINCT FROM true THEN RAISE EXCEPTION 'UPLOAD_LEDGER_FAIL:%',label;END IF;INSERT INTO upload_assertions VALUES(label);END $$;
DO $cases$
DECLARE u uuid:=gen_random_uuid();foreign_user uuid:=gen_random_uuid();a uuid:=gen_random_uuid();b uuid:=gen_random_uuid();c uuid:=gen_random_uuid();legacy uuid:=gen_random_uuid();t uuid:=gen_random_uuid();t2 uuid:=gen_random_uuid();t3 uuid:=gen_random_uuid();p jsonb;q jsonb;page jsonb;claim uuid;exp timestamptz:=date_trunc('second',clock_timestamp())+interval '2hours';denied boolean;
BEGIN
 INSERT INTO public.users(id,email,status,timezone,country,country_confirmed) VALUES(u,'upload-'||u||'@example.invalid','active','UTC','BR',true);
 INSERT INTO public.media_assets(id,user_id,kind,bucket_id,object_path,mime_type,declared_size_bytes,status,source_request_hash,retention_until)
 VALUES(a,u,'audio_note','audio-notes',u||'/'||a||'.m4a','audio/mp4',100,'pending_upload',repeat('a',64),clock_timestamp()+interval '1day'),
 (b,u,'conversation_photo','meal-photos',u||'/'||b||'.jpg','image/jpeg',100,'pending_upload',repeat('b',64),clock_timestamp()+interval '1day'),
 (legacy,u,'meal_photo','meal-photos',u||'/'||legacy||'.jpg','image/jpeg',100,'pending_upload',repeat('c',64),clock_timestamp()+interval '1day');
 p:=public.prepare_conversation_media_upload(u,a,t);
 PERFORM pg_temp.upload_ok(p->>'schema'='conversation.upload-prepared.v1' AND p#>>'{asset,id}'=a::text AND p#>>'{ticket,id}'=t::text,'prepared identity bound to canonical ordinary asset');
 PERFORM pg_temp.upload_ok(p=public.prepare_conversation_media_upload(u,a,t),'same prepare nonce stable before issuance');
 PERFORM pg_temp.upload_ok(p#>'{ticket,provider_expires_at}'='null'::jsonb,'unknown signing stays explicitly unresolved');
 denied:=false;BEGIN PERFORM public.prepare_conversation_media_upload(foreign_user,a,gen_random_uuid());EXCEPTION WHEN serialization_failure THEN denied:=true;END;
 PERFORM pg_temp.upload_ok(denied,'foreign owner cannot prepare');
 denied:=false;BEGIN PERFORM public.prepare_conversation_media_upload(u,b,t);EXCEPTION WHEN serialization_failure THEN denied:=true;END;
 PERFORM pg_temp.upload_ok(denied,'ticket nonce cannot migrate across assets');
 denied:=false;BEGIN PERFORM public.prepare_conversation_media_upload(u,legacy,gen_random_uuid());EXCEPTION WHEN serialization_failure THEN denied:=true;END;
 PERFORM pg_temp.upload_ok(denied,'generic legacy asset excluded');
 q:=public.register_conversation_media_upload(u,a,t,exp);
 PERFORM pg_temp.upload_ok((q#>>'{ticket,provider_expires_at}')::timestamptz=exp AND q#>'{ticket,registered_at}'<>'null'::jsonb,'actual provider expiry persisted');
 PERFORM pg_temp.upload_ok(q=public.register_conversation_media_upload(u,a,t,exp),'registration replay stable');
 PERFORM pg_temp.upload_ok(NOT EXISTS(SELECT 1 FROM private.conversation_media_expiry_debts WHERE asset_id=a),'live pending ticket does not dispose active media');
 denied:=false;BEGIN PERFORM public.register_conversation_media_upload(u,a,t,exp+interval '1second');EXCEPTION WHEN serialization_failure THEN denied:=true;END;
 PERFORM pg_temp.upload_ok(denied,'registered provider expiry immutable');
 denied:=false;BEGIN PERFORM public.prepare_conversation_media_upload(u,a,t);EXCEPTION WHEN serialization_failure THEN denied:=true;END;
 PERFORM pg_temp.upload_ok(denied,'registered nonce cannot silently sign a second capability');
 PERFORM pg_temp.upload_ok(public.get_conversation_media_upload_state(u,a)#>>'{asset,status}'='pending_upload','current scoped authority visible');
 PERFORM pg_temp.upload_ok(public.get_conversation_media_upload_state(foreign_user,a) IS NULL,'foreign current authority hidden');
 INSERT INTO public.media_assets(id,user_id,kind,bucket_id,object_path,mime_type,declared_size_bytes,actual_size_bytes,status,source_request_hash,retention_until,uploaded_at)
 VALUES(c,u,'audio_note','audio-notes',u||'/'||c||'.m4a','audio/mp4',100,100,'uploaded',repeat('d',64),clock_timestamp()+interval '1day',clock_timestamp());
 denied:=false;BEGIN PERFORM public.prepare_conversation_media_upload(u,c,gen_random_uuid());EXCEPTION WHEN serialization_failure THEN denied:=true;END;
 PERFORM pg_temp.upload_ok(denied,'completed upload cannot issue another ordinary capability');
 p:=public.prepare_conversation_media_upload(u,b,t2);
 UPDATE public.media_assets SET retention_until=clock_timestamp()-interval '1day' WHERE id=b;
 page:=public.claim_conversation_media_expiry_batch(100);
 SELECT (v->>'claim_token')::uuid INTO claim FROM jsonb_array_elements(page->'items') v WHERE v->>'asset_id'=b::text;
 PERFORM pg_temp.upload_ok(claim IS NOT NULL,'expiry claims physical cleanup before late provider response');
 PERFORM public.register_conversation_media_upload(u,b,t2,exp);
 denied:=false;BEGIN PERFORM public.acknowledge_conversation_media_expiry_sweep(b,u,claim);EXCEPTION WHEN serialization_failure THEN denied:=true;END;
 PERFORM pg_temp.upload_ok(denied,'late provider registration invalidates earlier sweep claim');
 PERFORM pg_temp.upload_ok(public.get_conversation_media_upload_state(u,b) IS NULL,'late response cannot restore disposed upload authority');
 page:=public.claim_conversation_media_expiry_batch(100);
 SELECT (v->>'claim_token')::uuid INTO claim FROM jsonb_array_elements(page->'items') v WHERE v->>'asset_id'=b::text;
 PERFORM public.register_conversation_media_upload(u,b,t2,exp);
 PERFORM pg_temp.upload_ok(public.acknowledge_conversation_media_expiry_sweep(b,u,claim)->>'state'='waiting_for_issuance_drain','registration replay does not invalidate the new physical sweep');
 PERFORM pg_temp.upload_ok((SELECT issuance_state='legacy_untracked' FROM private.conversation_media_expiry_debts WHERE asset_id=b),'tracked ticket does not invent proof about old issuers');
 denied:=false;BEGIN PERFORM public.prepare_conversation_media_upload(u,b,gen_random_uuid());EXCEPTION WHEN serialization_failure THEN denied:=true;END;
 PERFORM pg_temp.upload_ok(denied,'disposed asset cannot issue new ticket');
 PERFORM public.prepare_conversation_media_upload(u,a,t3);
 DELETE FROM public.media_assets WHERE id=a;
 PERFORM public.register_conversation_media_upload(u,a,t3,exp+interval '1day');
 PERFORM pg_temp.upload_ok((SELECT object_path=u||'/'||a||'.m4a' AND claim_token IS NULL FROM private.conversation_media_expiry_debts WHERE asset_id=a),'late signing after catalogue deletion recreates exact original cleanup debt');
 PERFORM pg_temp.upload_ok((SELECT provider_expires_at=exp+interval '1day' FROM private.conversation_media_upload_tickets WHERE ticket_id=t3),'anomalous actual expiry preserved rather than clamped');
 denied:=false;BEGIN PERFORM public.register_conversation_media_upload(foreign_user,a,t3,exp+interval '1day');EXCEPTION WHEN serialization_failure THEN denied:=true;END;
 PERFORM pg_temp.upload_ok(denied,'late registration still checks original owner');
 denied:=false;BEGIN UPDATE private.conversation_media_upload_tickets SET asset_wire=jsonb_set(asset_wire,'{mime_type}','"audio/ogg"') WHERE ticket_id=t;EXCEPTION WHEN check_violation THEN denied:=true;END;
 PERFORM pg_temp.upload_ok(denied,'frozen ticket identity cannot be rewritten');
 PERFORM pg_temp.upload_ok(NOT has_table_privilege('service_role','private.conversation_media_upload_tickets','SELECT'),'ticket table private even to direct backend table access');
 PERFORM pg_temp.upload_ok(NOT has_function_privilege('authenticated','public.prepare_conversation_media_upload(uuid,uuid,uuid)','EXECUTE') AND NOT has_function_privilege('anon','public.register_conversation_media_upload(uuid,uuid,uuid,timestamptz)','EXECUTE'),'client execution revoked');
 PERFORM pg_temp.upload_ok(has_function_privilege('service_role','public.prepare_conversation_media_upload(uuid,uuid,uuid)','EXECUTE'),'trusted backend RPC allowed');
 -- Satisfy the existing deletion precondition; no provider objects exist in
 -- this synthetic SQL fixture. This is not full account-purge QA.
 DELETE FROM public.media_assets WHERE user_id=u;
 DELETE FROM public.users WHERE id=u;
 PERFORM pg_temp.upload_ok((SELECT count(*)=3 FROM private.conversation_media_upload_tickets WHERE user_id=u),'account row deletion cannot erase outstanding ticket manifest');
 PERFORM pg_temp.upload_ok((SELECT count(*)=2 FROM private.conversation_media_expiry_debts WHERE user_id=u),'account row deletion cannot erase outstanding physical cleanup debt');
END $cases$;
SELECT jsonb_build_object('schema','conversation.upload-ledger-local-qa.v1','assertions',(SELECT count(*) FROM upload_assertions));
ROLLBACK;
