-- Local rollback qualification only. No provider, Auth or Storage requests.
BEGIN;
SET LOCAL request.jwt.claims='{"role":"service_role"}';
CREATE TEMP TABLE catalog_assertions(label text PRIMARY KEY);
CREATE FUNCTION pg_temp.catalog_ok(v boolean,label text) RETURNS void LANGUAGE plpgsql AS $$
BEGIN IF v IS DISTINCT FROM true THEN RAISE EXCEPTION 'PRIVATE_CATALOG_FAIL:%',label;END IF;
INSERT INTO catalog_assertions VALUES(label);END $$;
SELECT pg_temp.catalog_ok(to_regprocedure('public.create_conversation_media_asset_v2(uuid,uuid,text,text,bigint,text,text)') IS NOT NULL,'private creation capability installed');
DO $cases$
DECLARE u uuid:=gen_random_uuid();other_user uuid:=gen_random_uuid();a uuid:=gen_random_uuid();b uuid:=gen_random_uuid();old_id uuid:=gen_random_uuid();
 p jsonb;q jsonb;denied boolean;r text;original jsonb;fmt record;fmt_id uuid;
BEGIN
 INSERT INTO public.users(id,email,status,timezone,country,country_confirmed)
 VALUES(u,'private-catalog-'||u||'@example.invalid','active','UTC','BR',true),
 (other_user,'private-catalog-'||other_user||'@example.invalid','active','UTC','BR',true);
 p:=public.create_conversation_media_asset_v2(u,a,'audio_note','audio/mp4',8,'No almoço',repeat('a',64));
 PERFORM pg_temp.catalog_ok(p->>'schema'='conversation.media-asset.v2' AND p->>'catalog_version'='2','explicit versioned source');
 PERFORM pg_temp.catalog_ok(p#>>'{asset,id}'=a::text AND p#>>'{asset,user_id}'=u::text,'owner and opaque asset bound');
 PERFORM pg_temp.catalog_ok(p#>>'{asset,object_path}'='conversation-v2/'||u||'/'||a||'.m4a' AND p#>>'{asset,bucket_id}'='audio-notes','audio key is disjoint from legacy keys');
 PERFORM pg_temp.catalog_ok(p#>>'{asset,status}'='pending_upload' AND p#>>'{asset,context_text}'='No almoço','pending source retained');
 PERFORM pg_temp.catalog_ok((p#>>'{asset,retention_until}')::timestamptz-(p#>>'{asset,created_at}')::timestamptz=interval '30days','ordinary retention preserved');
 PERFORM pg_temp.catalog_ok(NOT EXISTS(SELECT 1 FROM public.media_assets WHERE id=a),'legacy findOwned cannot acquire private key');
 PERFORM pg_temp.catalog_ok(NOT EXISTS(SELECT 1 FROM public.media_assets WHERE user_id=u AND source_request_hash=repeat('a',64)),'legacy request replay cannot acquire private key');
 PERFORM pg_temp.catalog_ok(NOT EXISTS(SELECT 1 FROM public.media_assets WHERE retention_until<=clock_timestamp() AND id=a),'legacy expiry scan cannot acquire private key');
 PERFORM pg_temp.catalog_ok(NOT EXISTS(SELECT 1 FROM public.media_assets WHERE user_id=u),'legacy account purge scan cannot acquire private key');
 PERFORM pg_temp.catalog_ok(public.get_conversation_media_asset_v2(u,a,NULL)=p,'read is stable and owner bound');
 PERFORM pg_temp.catalog_ok(public.get_conversation_media_asset_v2(u,NULL,repeat('a',64))=p,'idempotency lookup uses private source');
 q:=public.create_conversation_media_asset_v2(u,gen_random_uuid(),'audio_note','audio/mp4',8,'No almoço',repeat('a',64));
 PERFORM pg_temp.catalog_ok(q=p AND (SELECT count(*) FROM private.conversation_media_assets_v2 WHERE user_id=u)=1,'retry nonce does not duplicate a logical asset');
 PERFORM pg_temp.catalog_ok(public.get_conversation_media_asset_v2(other_user,a,NULL) IS NULL,'foreign owner cannot read private asset');
 denied:=false;BEGIN PERFORM public.create_conversation_media_asset_v2(u,a,'audio_note','audio/mp4',9,'No almoço',repeat('a',64));EXCEPTION WHEN serialization_failure THEN denied:=true;END;
 PERFORM pg_temp.catalog_ok(denied,'changed replay quantity refused');
 denied:=false;BEGIN PERFORM public.create_conversation_media_asset_v2(u,a,'audio_note','audio/mp4',8,'Outro texto',repeat('a',64));EXCEPTION WHEN serialization_failure THEN denied:=true;END;
 PERFORM pg_temp.catalog_ok(denied,'changed replay caption refused');
 denied:=false;BEGIN PERFORM public.create_conversation_media_asset_v2(other_user,a,'audio_note','audio/mp4',8,NULL,repeat('b',64));EXCEPTION WHEN serialization_failure THEN denied:=true;END;
 PERFORM pg_temp.catalog_ok(denied,'asset identity cannot migrate to another owner');
 q:=public.create_conversation_media_asset_v2(u,b,'conversation_photo','image/jpeg',100,NULL,repeat('c',64));
 PERFORM pg_temp.catalog_ok(q#>>'{asset,object_path}'='conversation-v2/'||u||'/'||b||'.jpg' AND q#>>'{asset,bucket_id}'='meal-photos','photo key is disjoint in existing private bucket');
 FOR fmt IN SELECT * FROM(VALUES
  ('audio_note','audio/mp4','m4a'),('audio_note','audio/x-m4a','m4a'),('audio_note','audio/mpeg','mp3'),
  ('audio_note','audio/aac','aac'),('audio_note','audio/wav','wav'),('audio_note','audio/x-wav','wav'),('audio_note','audio/ogg','ogg'),
  ('conversation_photo','image/jpeg','jpg'),('conversation_photo','image/png','png'),('conversation_photo','image/webp','webp'),
  ('conversation_photo','image/heic','heic'),('conversation_photo','image/heif','heif')) AS f(kind,mime,extension) LOOP
  fmt_id:=gen_random_uuid();
  q:=public.create_conversation_media_asset_v2(u,fmt_id,fmt.kind,fmt.mime,100,NULL,encode(sha256(convert_to(fmt.mime,'UTF8')),'hex'));
  PERFORM pg_temp.catalog_ok(q#>>'{asset,object_path}'='conversation-v2/'||u||'/'||fmt_id||'.'||fmt.extension,'legacy supported MIME preserved: '||fmt.mime);
 END LOOP;
 denied:=false;BEGIN PERFORM public.create_conversation_media_asset_v2(u,gen_random_uuid(),'body_checkin_photo','image/jpeg',100,NULL,repeat('d',64));EXCEPTION WHEN invalid_parameter_value THEN denied:=true;END;
 PERFORM pg_temp.catalog_ok(denied,'clinical photo cannot enter ordinary private catalog');
 denied:=false;BEGIN PERFORM public.create_conversation_media_asset_v2(u,gen_random_uuid(),'audio_note','image/jpeg',100,NULL,repeat('d',64));EXCEPTION WHEN invalid_parameter_value THEN denied:=true;END;
 PERFORM pg_temp.catalog_ok(denied,'kind mime disagreement refused');
 denied:=false;BEGIN PERFORM public.create_conversation_media_asset_v2(u,gen_random_uuid(),'conversation_photo','image/jpeg',15728641,NULL,repeat('d',64));EXCEPTION WHEN invalid_parameter_value THEN denied:=true;END;
 PERFORM pg_temp.catalog_ok(denied,'photo size bound preserved');
 denied:=false;BEGIN PERFORM public.get_conversation_media_asset_v2(u,a,repeat('a',64));EXCEPTION WHEN invalid_parameter_value THEN denied:=true;END;
 PERFORM pg_temp.catalog_ok(denied,'ambiguous lookup refused');
 original:=to_jsonb(x) FROM private.conversation_media_assets_v2 x WHERE id=a;
 denied:=false;BEGIN UPDATE private.conversation_media_assets_v2 SET object_path=u||'/'||a||'.m4a' WHERE id=a;EXCEPTION WHEN check_violation THEN denied:=true;END;
 PERFORM pg_temp.catalog_ok(denied,'source path cannot mutate into old namespace');
 denied:=false;BEGIN UPDATE private.conversation_media_assets_v2 SET source_request_hash=repeat('f',64) WHERE id=a;EXCEPTION WHEN check_violation THEN denied:=true;END;
 PERFORM pg_temp.catalog_ok(denied,'request lineage is immutable');
 denied:=false;BEGIN UPDATE private.conversation_media_assets_v2 SET retention_until=retention_until+interval '1day' WHERE id=a;EXCEPTION WHEN check_violation THEN denied:=true;END;
 PERFORM pg_temp.catalog_ok(denied,'retention origin is immutable');
 PERFORM pg_temp.catalog_ok(original=(SELECT to_jsonb(x) FROM private.conversation_media_assets_v2 x WHERE id=a),'refused mutations preserve entire source');
 denied:=false;BEGIN INSERT INTO public.media_assets(id,user_id,kind,bucket_id,object_path,mime_type,declared_size_bytes,status,source_request_hash,retention_until)
 VALUES(gen_random_uuid(),u,'audio_note','audio-notes',p#>>'{asset,object_path}','audio/mp4',8,'pending_upload',repeat('e',64),clock_timestamp()+interval '1day');EXCEPTION WHEN check_violation THEN denied:=true;END;
 PERFORM pg_temp.catalog_ok(denied,'public catalog cannot mirror a private namespace path');
 denied:=false;BEGIN INSERT INTO public.media_assets(id,user_id,kind,bucket_id,object_path,mime_type,declared_size_bytes,status,source_request_hash,retention_until)
 VALUES(a,u,'audio_note','audio-notes',u||'/'||a||'.m4a','audio/mp4',8,'pending_upload',repeat('e',64),clock_timestamp()+interval '1day');EXCEPTION WHEN serialization_failure THEN denied:=true;END;
 PERFORM pg_temp.catalog_ok(denied,'later legacy insert cannot take private identity');
 INSERT INTO public.media_assets(id,user_id,kind,bucket_id,object_path,mime_type,declared_size_bytes,status,source_request_hash,retention_until)
 VALUES(old_id,u,'audio_note','audio-notes',u||'/'||old_id||'.m4a','audio/mp4',8,'pending_upload',repeat('e',64),clock_timestamp()+interval '1day');
 denied:=false;BEGIN PERFORM public.create_conversation_media_asset_v2(u,old_id,'audio_note','audio/mp4',8,NULL,repeat('f',64));EXCEPTION WHEN serialization_failure THEN denied:=true;END;
 PERFORM pg_temp.catalog_ok(denied,'new private insert cannot take old identity');
 FOR r IN SELECT unnest(ARRAY['anon','authenticated','service_role']) LOOP
  PERFORM pg_temp.catalog_ok(NOT has_table_privilege(r,'private.conversation_media_assets_v2','SELECT,INSERT,UPDATE,DELETE'),r||' has no direct private table privilege');
  PERFORM pg_temp.catalog_ok(NOT has_table_privilege(r,'private.conversation_media_identity_v2','SELECT,INSERT,UPDATE,DELETE'),r||' has no direct identity fence privilege');
  IF r<>'service_role' THEN
   PERFORM pg_temp.catalog_ok(NOT has_function_privilege(r,'public.create_conversation_media_asset_v2(uuid,uuid,text,text,bigint,text,text)','EXECUTE'),r||' cannot invoke private creation');
   PERFORM pg_temp.catalog_ok(NOT has_function_privilege(r,'public.get_conversation_media_asset_v2(uuid,uuid,text)','EXECUTE'),r||' cannot invoke private read');
   EXECUTE 'SET LOCAL ROLE '||quote_ident(r);
   denied:=false;BEGIN PERFORM public.get_conversation_media_asset_v2(u,a,NULL);EXCEPTION WHEN insufficient_privilege THEN denied:=true;END;
   RESET ROLE;
   PERFORM pg_temp.catalog_ok(denied,r||' actual read call refused');
   EXECUTE 'SET LOCAL ROLE '||quote_ident(r);
   denied:=false;BEGIN PERFORM public.create_conversation_media_asset_v2(u,gen_random_uuid(),'audio_note','audio/mp4',8,NULL,repeat('d',64));EXCEPTION WHEN insufficient_privilege THEN denied:=true;END;
   RESET ROLE;
   PERFORM pg_temp.catalog_ok(denied,r||' actual creation call refused');
  END IF;
 END LOOP;
 SET LOCAL ROLE service_role;
 q:=public.get_conversation_media_asset_v2(u,a,NULL);
 RESET ROLE;
 PERFORM pg_temp.catalog_ok(q=p,'actual trusted backend call uses checked private reader');
 PERFORM pg_temp.catalog_ok(has_function_privilege('service_role','public.create_conversation_media_asset_v2(uuid,uuid,text,text,bigint,text,text)','EXECUTE'),'trusted backend can create through checked capability');
 PERFORM pg_temp.catalog_ok((SELECT relrowsecurity FROM pg_class WHERE oid='private.conversation_media_assets_v2'::regclass),'private table RLS enabled');
 PERFORM pg_temp.catalog_ok(NOT EXISTS(SELECT 1 FROM pg_policies WHERE schemaname='private' AND tablename='conversation_media_assets_v2'),'private table has no client policy');
 UPDATE public.users SET status='deleted' WHERE id=other_user;
 denied:=false;BEGIN PERFORM public.create_conversation_media_asset_v2(other_user,gen_random_uuid(),'audio_note','audio/mp4',8,NULL,repeat('f',64));EXCEPTION WHEN serialization_failure THEN denied:=true;END;
 PERFORM pg_temp.catalog_ok(denied,'deleted owner cannot create a new private capability');
 DELETE FROM public.media_assets WHERE id=old_id;
 PERFORM pg_temp.catalog_ok(NOT EXISTS(SELECT 1 FROM private.conversation_media_identity_v2 WHERE asset_id=old_id),'legacy removal drops transient identity fence');
 denied:=false;BEGIN DELETE FROM public.users WHERE id=u;EXCEPTION WHEN foreign_key_violation THEN denied:=true;END;
 PERFORM pg_temp.catalog_ok(denied AND EXISTS(SELECT 1 FROM private.conversation_media_assets_v2 WHERE id=a),'old account deletion cannot erase live private disposal authority');
 DELETE FROM private.conversation_media_assets_v2 WHERE id=b;
 PERFORM pg_temp.catalog_ok(EXISTS(SELECT 1 FROM private.conversation_media_identity_v2 WHERE asset_id=b AND catalog_version=2),'identity barrier survives catalog removal');
 denied:=false;BEGIN PERFORM public.create_conversation_media_asset_v2(u,b,'conversation_photo','image/jpeg',100,NULL,repeat('d',64));EXCEPTION WHEN serialization_failure THEN denied:=true;END;
 PERFORM pg_temp.catalog_ok(denied,'removed private identity cannot be recycled');
 denied:=false;BEGIN INSERT INTO public.media_assets(id,user_id,kind,bucket_id,object_path,mime_type,declared_size_bytes,status,source_request_hash,retention_until)
 VALUES(b,u,'audio_note','audio-notes',u||'/'||b||'.m4a','audio/mp4',8,'pending_upload',repeat('d',64),clock_timestamp()+interval '1day');EXCEPTION WHEN serialization_failure THEN denied:=true;END;
 PERFORM pg_temp.catalog_ok(denied,'removed private identity cannot become legacy media');
END $cases$;
SELECT jsonb_build_object('passed',count(*),'labels',jsonb_agg(label ORDER BY label)) FROM catalog_assertions;
ROLLBACK;
