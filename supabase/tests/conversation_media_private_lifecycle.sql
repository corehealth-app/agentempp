-- Local rollback only; synthetic source/metadata. No Storage or model requests.
BEGIN;
SET LOCAL request.jwt.claims='{"role":"service_role"}';
SET LOCAL timezone='UTC';
CREATE TEMP TABLE lifecycle_checks(label text PRIMARY KEY);
CREATE FUNCTION pg_temp.life_ok(v boolean,label text) RETURNS void LANGUAGE plpgsql AS $$
BEGIN IF v IS DISTINCT FROM true THEN RAISE EXCEPTION 'PRIVATE_MEDIA_LIFECYCLE_FAIL:%',label;END IF;
INSERT INTO lifecycle_checks VALUES(label);END $$;
SELECT pg_temp.life_ok(to_regprocedure('public.prepare_conversation_media_upload_v2(uuid,uuid,uuid)') IS NOT NULL,'private upload preparation installed');
DO $cases$
DECLARE u uuid:=gen_random_uuid();other_user uuid:=gen_random_uuid();a uuid:=gen_random_uuid();b uuid:=gen_random_uuid();
 t uuid:=gen_random_uuid();t2 uuid:=gen_random_uuid();t3 uuid:=gen_random_uuid();p jsonb;q jsonb;c jsonb;replay jsonb;
 exp timestamptz:=date_trunc('second',clock_timestamp())+interval '2hours';denied boolean;token uuid;at_done timestamptz;r text;
BEGIN
 INSERT INTO public.users(id,email,status,timezone,country,country_confirmed) VALUES
 (u,'private-lifecycle-'||u||'@example.invalid','active','UTC','BR',true),
 (other_user,'private-lifecycle-'||other_user||'@example.invalid','active','UTC','BR',true);
 PERFORM public.create_conversation_media_asset_v2(u,a,'audio_note','audio/mp4',8,'Acabei de consumir leite com whey',repeat('a',64));
 PERFORM public.create_conversation_media_asset_v2(u,b,'conversation_photo','image/jpeg',100,NULL,repeat('b',64));
 p:=public.prepare_conversation_media_upload_v2(u,a,t);
 PERFORM pg_temp.life_ok(p->>'schema'='conversation.upload-prepared.v2' AND p#>>'{asset,identity,catalog_version}'='2','explicit prepared identity version');
 PERFORM pg_temp.life_ok(p#>>'{asset,identity,object_path}'='conversation-v2/'||u||'/'||a||'.m4a','prepared private path stays disjoint');
 PERFORM pg_temp.life_ok(p#>>'{ticket,id}'=t::text AND p#>>'{ticket,asset_id}'=a::text AND p#>>'{ticket,user_id}'=u::text,'preparation binds actual ticket owner and source');
 PERFORM pg_temp.life_ok(p#>'{ticket,provider_expires_at}'='null'::jsonb AND p#>'{ticket,registered_at}'='null'::jsonb,'unknown signer outcome remains unresolved');
 PERFORM pg_temp.life_ok(public.prepare_conversation_media_upload_v2(u,a,t)=p,'same unsigned preparation is stable');
 PERFORM pg_temp.life_ok(EXISTS(SELECT 1 FROM private.conversation_media_obligations_v2 WHERE asset_id=a AND user_id=u AND issuance_revision=0 AND closed_at IS NULL),'independent obligation precedes signing');
 denied:=false;BEGIN PERFORM public.prepare_conversation_media_upload_v2(other_user,a,gen_random_uuid());EXCEPTION WHEN serialization_failure THEN denied:=true;END;
 PERFORM pg_temp.life_ok(denied,'foreign owner cannot prepare');
 denied:=false;BEGIN PERFORM public.prepare_conversation_media_upload_v2(u,b,t);EXCEPTION WHEN serialization_failure THEN denied:=true;END;
 PERFORM pg_temp.life_ok(denied,'ticket nonce cannot migrate across private sources');
 q:=public.register_conversation_media_upload_v2(u,a,t,exp);
 PERFORM pg_temp.life_ok(q->>'schema'='conversation.upload-registered.v2' AND(q#>>'{ticket,provider_expires_at}')::timestamptz=exp,'actual provider expiry is durably registered');
 PERFORM pg_temp.life_ok(q#>'{ticket,registered_at}'<>'null'::jsonb,'provider response instant recorded');
 PERFORM pg_temp.life_ok((SELECT issuance_revision=1 FROM private.conversation_media_obligations_v2 WHERE asset_id=a),'first observation advances issuance revision');
 PERFORM pg_temp.life_ok(public.register_conversation_media_upload_v2(u,a,t,exp)=q AND(SELECT issuance_revision=1 FROM private.conversation_media_obligations_v2 WHERE asset_id=a),'bookkeeping replay never creates another observation');
 denied:=false;BEGIN PERFORM public.register_conversation_media_upload_v2(u,a,t,exp+interval '1second');EXCEPTION WHEN serialization_failure THEN denied:=true;END;
 PERFORM pg_temp.life_ok(denied,'registered provider expiry cannot change');
 denied:=false;BEGIN PERFORM public.prepare_conversation_media_upload_v2(u,a,t);EXCEPTION WHEN serialization_failure THEN denied:=true;END;
 PERFORM pg_temp.life_ok(denied,'already signed ticket cannot be prepared as unsigned');
 PERFORM pg_temp.life_ok(public.get_conversation_media_upload_state_v2(u,a)#>>'{asset,identity,asset_id}'=a::text,'current upload scope uses exact private source');
 denied:=false;BEGIN UPDATE private.conversation_media_upload_tickets_v2 SET provider_expires_at=exp+interval '1day' WHERE ticket_id=t;EXCEPTION WHEN check_violation THEN denied:=true;END;
 PERFORM pg_temp.life_ok(denied,'ticket source and observed expiry are immutable');
 p:=public.complete_conversation_media_upload_v2(u,a,8,'audio/mp4','synthetic-etag');
 PERFORM pg_temp.life_ok(p#>>'{asset,status}'='uploaded' AND p#>>'{asset,actual_size_bytes}'='8','private completion persists actual metadata');
 PERFORM pg_temp.life_ok(public.complete_conversation_media_upload_v2(u,a,8,'audio/mp4','synthetic-etag')=p,'upload completion replay preserves original instant');
 denied:=false;BEGIN PERFORM public.complete_conversation_media_upload_v2(u,a,9,'audio/mp4','synthetic-etag');EXCEPTION WHEN serialization_failure THEN denied:=true;END;
 PERFORM pg_temp.life_ok(denied,'changed completion metadata is refused');
 PERFORM pg_temp.life_ok(public.get_conversation_media_upload_state_v2(u,a) IS NULL,'uploaded source cannot receive another upload capability');
 c:=public.claim_conversation_media_processing_v2(u,a,repeat('c',64));
 PERFORM pg_temp.life_ok(c->>'schema'='conversation.media-processing-claim.v2' AND c->>'action'='claimed','one private processing claim admitted');
 token:=(c#>>'{claim,token}')::uuid;
 PERFORM pg_temp.life_ok(c#>>'{asset,identity,asset_id}'=a::text AND c#>>'{asset,state,status}'='processing','claim binds canonical private snapshot');
 PERFORM pg_temp.life_ok(public.claim_conversation_media_processing_v2(u,a,repeat('c',64))->>'action'='busy','same technical retry cannot duplicate a live provider call');
 PERFORM pg_temp.life_ok(public.claim_conversation_media_processing_v2(u,a,repeat('d',64))->>'action'='busy','different request cannot steal a live provider lease');
 PERFORM pg_temp.life_ok(NOT public.complete_conversation_media_processing_v2(u,a,repeat('c',64),gen_random_uuid(),'{"text":"Leite com whey"}'),'foreign token cannot commit provider result');
 PERFORM pg_temp.life_ok(public.complete_conversation_media_processing_v2(u,a,repeat('c',64),token,'{"text":"Leite com whey"}'),'current processing claim commits once');
 SELECT processed_at INTO at_done FROM private.conversation_media_assets_v2 WHERE id=a;
 PERFORM pg_temp.life_ok(public.complete_conversation_media_processing_v2(u,a,repeat('c',64),token,'{"text":"Leite com whey"}') AND(SELECT processed_at=at_done FROM private.conversation_media_assets_v2 WHERE id=a),'lost response replay preserves exact original processing instant');
 PERFORM pg_temp.life_ok(NOT public.complete_conversation_media_processing_v2(u,a,repeat('c',64),token,'{"text":"outro conteúdo"}'),'completed provider result cannot be replaced');
 PERFORM pg_temp.life_ok(public.claim_conversation_media_processing_v2(u,a,repeat('c',64))->>'action'='unavailable','processed source does not run the model again');
 PERFORM pg_temp.life_ok(NOT EXISTS(SELECT 1 FROM public.meal_logs WHERE user_id=u) AND NOT EXISTS(SELECT 1 FROM public.workout_logs WHERE user_id=u),'processing creates no consumption or workout facts');

 p:=public.prepare_conversation_media_upload_v2(u,b,t2);PERFORM public.register_conversation_media_upload_v2(u,b,t2,exp);
 PERFORM public.complete_conversation_media_upload_v2(u,b,100,'image/jpeg',NULL);
 c:=public.claim_conversation_media_processing_v2(u,b,repeat('d',64));token:=(c#>>'{claim,token}')::uuid;
 UPDATE private.conversation_media_assets_v2 SET status='deleted',deleted_at=clock_timestamp(),failure_stage=NULL,failure_code=NULL,processing_result=NULL WHERE id=b;
 UPDATE private.conversation_media_obligations_v2 SET closed_at=clock_timestamp() WHERE asset_id=b;
 PERFORM pg_temp.life_ok(NOT public.complete_conversation_media_processing_v2(u,b,repeat('d',64),token,'{"schema":"conversation.image-result.v1"}'),'late provider response cannot resurrect a disposed source');
 PERFORM pg_temp.life_ok(NOT public.fail_conversation_media_processing_v2(u,b,repeat('d',64),token,'provider_error'),'late failure cannot replace disposed state');
 PERFORM pg_temp.life_ok((SELECT status='deleted' AND processing_result IS NULL FROM private.conversation_media_assets_v2 WHERE id=b),'disposed catalog remains closed and scrubbed');
 PERFORM pg_temp.life_ok(public.get_conversation_media_upload_state_v2(u,b) IS NULL,'closed source cannot issue another capability');

 -- Controlled expiry of only this synthetic lease; no wall-clock sleeps or
 -- weakening of the production lease checks.
 DECLARE retry_asset uuid:=gen_random_uuid();retry_ticket uuid:=gen_random_uuid();old_token uuid;new_token uuid;
  old_start timestamptz:=clock_timestamp()-interval '6minutes';failed_at timestamptz;BEGIN
  PERFORM public.create_conversation_media_asset_v2(u,retry_asset,'audio_note','audio/mp4',8,NULL,repeat('f',64));
  PERFORM public.prepare_conversation_media_upload_v2(u,retry_asset,retry_ticket);
  PERFORM public.register_conversation_media_upload_v2(u,retry_asset,retry_ticket,exp);
  PERFORM public.complete_conversation_media_upload_v2(u,retry_asset,8,'audio/mp4',NULL);
  c:=public.claim_conversation_media_processing_v2(u,retry_asset,repeat('1',64));old_token:=(c#>>'{claim,token}')::uuid;
  UPDATE private.conversation_media_processing_claims_v2 SET started_at=old_start,lease_until=old_start+interval '5minutes' WHERE asset_id=retry_asset;
  PERFORM pg_temp.life_ok(NOT public.complete_conversation_media_processing_v2(u,retry_asset,repeat('1',64),old_token,'{"text":"stale"}'),'expired processing token cannot commit');
  PERFORM pg_temp.life_ok(NOT public.fail_conversation_media_processing_v2(u,retry_asset,repeat('1',64),old_token,'provider_error'),'expired processing token cannot mark failure');
  c:=public.claim_conversation_media_processing_v2(u,retry_asset,repeat('2',64));new_token:=(c#>>'{claim,token}')::uuid;
  PERFORM pg_temp.life_ok(c->>'action'='claimed' AND new_token<>old_token,'expired lease is reclaimed with a new token');
  PERFORM pg_temp.life_ok(NOT public.complete_conversation_media_processing_v2(u,retry_asset,repeat('1',64),old_token,'{"text":"stale"}'),'reclaimed source refuses the superseded request');
  PERFORM pg_temp.life_ok(public.fail_conversation_media_processing_v2(u,retry_asset,repeat('2',64),new_token,'provider_error'),'current processing token may record bounded failure');
  SELECT updated_at INTO failed_at FROM private.conversation_media_assets_v2 WHERE id=retry_asset;
  PERFORM pg_temp.life_ok(public.fail_conversation_media_processing_v2(u,retry_asset,repeat('2',64),new_token,'provider_error') AND(SELECT updated_at=failed_at FROM private.conversation_media_assets_v2 WHERE id=retry_asset),'failure replay preserves the first failure instant');
  PERFORM pg_temp.life_ok(NOT public.fail_conversation_media_processing_v2(u,retry_asset,repeat('2',64),new_token,'different_error'),'completed failure cannot be replaced on replay');
  c:=public.claim_conversation_media_processing_v2(u,retry_asset,repeat('3',64));token:=(c#>>'{claim,token}')::uuid;
  PERFORM pg_temp.life_ok(c->>'action'='claimed' AND token<>new_token,'explicit retry of failed processing obtains a fresh token');
  PERFORM pg_temp.life_ok(public.complete_conversation_media_processing_v2(u,retry_asset,repeat('3',64),token,'{"text":"resolved"}'),'retry may complete only its current token');
  PERFORM pg_temp.life_ok(NOT public.fail_conversation_media_processing_v2(u,retry_asset,repeat('2',64),new_token,'provider_error'),'old failure cannot downgrade a successful retry');
 END;

 -- An actual capability response must be bookkept even after catalog/account removal.
 DECLARE late_owner uuid:=gen_random_uuid();late_asset uuid:=gen_random_uuid();late_ticket uuid:=gen_random_uuid();BEGIN
  INSERT INTO public.users(id,email,status,timezone,country,country_confirmed) VALUES(late_owner,'late-'||late_owner||'@example.invalid','active','UTC','BR',true);
  PERFORM public.create_conversation_media_asset_v2(late_owner,late_asset,'audio_note','audio/mp4',8,NULL,repeat('e',64));
  PERFORM public.prepare_conversation_media_upload_v2(late_owner,late_asset,late_ticket);
  DELETE FROM private.conversation_media_assets_v2 WHERE id=late_asset;
  DELETE FROM public.users WHERE id=late_owner;
  q:=public.register_conversation_media_upload_v2(late_owner,late_asset,late_ticket,exp);
  PERFORM pg_temp.life_ok((q#>>'{ticket,provider_expires_at}')::timestamptz=exp,'late signing response survives catalog and owner deletion');
  PERFORM pg_temp.life_ok(EXISTS(SELECT 1 FROM private.conversation_media_obligations_v2 WHERE asset_id=late_asset AND closed_at IS NOT NULL AND issuance_revision=1),'missing catalog retains closed independent disposal authority');
  PERFORM pg_temp.life_ok(public.register_conversation_media_upload_v2(late_owner,late_asset,late_ticket,exp)=q,'late response bookkeeping replay is exact');
 END;

 FOR r IN SELECT unnest(ARRAY['anon','authenticated','service_role']) LOOP
  PERFORM pg_temp.life_ok(NOT has_table_privilege(r,'private.conversation_media_upload_tickets_v2','SELECT,INSERT,UPDATE,DELETE'),r||' has no direct private ticket privileges');
  PERFORM pg_temp.life_ok(NOT has_table_privilege(r,'private.conversation_media_obligations_v2','SELECT,INSERT,UPDATE,DELETE'),r||' has no direct private obligation privileges');
  PERFORM pg_temp.life_ok(NOT has_table_privilege(r,'private.conversation_media_processing_claims_v2','SELECT,INSERT,UPDATE,DELETE'),r||' has no direct processing claim privileges');
 END LOOP;
 PERFORM set_config('request.jwt.claims','{"role":"authenticated"}',true);
 denied:=false;BEGIN PERFORM public.prepare_conversation_media_upload_v2(u,a,gen_random_uuid());EXCEPTION WHEN insufficient_privilege THEN denied:=true;END;
 PERFORM set_config('request.jwt.claims','{"role":"service_role"}',true);
 PERFORM pg_temp.life_ok(denied,'untrusted caller cannot invoke the privileged signer preparation');
END $cases$;
SELECT jsonb_build_object('passed',count(*),'labels',jsonb_agg(label ORDER BY label)) FROM lifecycle_checks;
ROLLBACK;
