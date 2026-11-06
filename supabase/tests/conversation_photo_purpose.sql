-- Synthetic, transactional purpose/compatibility tests. No Storage upload or AI.
BEGIN;
INSERT INTO public.users(id,email,wpp,name,status)
VALUES('00000000-0000-4000-8000-00000000f461','t46@example.invalid',NULL,'T46 synthetic','active');
SET LOCAL ROLE service_role;
SELECT set_config('request.jwt.claims','{"role":"service_role"}',true);

DO $test$
DECLARE
 u uuid:='00000000-0000-4000-8000-00000000f461';
 a uuid:='00000000-0000-4000-8000-00000000f462';
 v record; c jsonb; refused boolean; n integer:=0;
BEGIN
 IF (SELECT count(*) FROM storage.buckets)<>6 OR
    NOT EXISTS(SELECT 1 FROM storage.buckets WHERE id='meal-photos' AND NOT public AND file_size_limit=15728640) THEN
  RAISE EXCEPTION 'T46 private existing buckets changed'; END IF;
 INSERT INTO public.media_assets(id,user_id,kind,bucket_id,object_path,mime_type,declared_size_bytes,status,source_request_hash,retention_until)
 VALUES(a,u,'conversation_photo','meal-photos',u::text||'/'||a::text||'.jpg','image/jpeg',1024,'pending_upload',repeat('4',64),now()+interval '30 days');
 n:=n+1;
 FOR v IN SELECT * FROM (VALUES
  ('body bucket','body-checkin-photos','image/jpeg',1024::bigint,NULL::bigint,false),
  ('gym bucket','gym-photos','image/jpeg',1024,NULL,false),
  ('pdf','meal-photos','application/pdf',1024,NULL,false),
  ('audio','meal-photos','audio/mpeg',1024,NULL,false),
  ('svg','meal-photos','image/svg+xml',1024,NULL,false),
  ('oversized','meal-photos','image/jpeg',15728641,NULL,false),
  ('zero','meal-photos','image/jpeg',0,NULL,false),
  ('different actual size','meal-photos','image/jpeg',1024,1023,false),
  ('retention absent','meal-photos','image/jpeg',1024,NULL,true)
 ) t(label,bucket,mime,declared,actual,without_retention) LOOP
  refused:=false;
  BEGIN
   INSERT INTO public.media_assets(id,user_id,kind,bucket_id,object_path,mime_type,declared_size_bytes,actual_size_bytes,status,source_request_hash,retention_until)
   VALUES('00000000-0000-4000-8000-00000000f463',u,'conversation_photo',v.bucket,u::text||'/00000000-0000-4000-8000-00000000f463.jpg',v.mime,v.declared,v.actual,'pending_upload',repeat('5',64),CASE WHEN v.without_retention THEN NULL ELSE now()+interval '30 days' END);
  EXCEPTION WHEN check_violation THEN refused:=true; END;
  IF NOT refused THEN RAISE EXCEPTION 'T46 accepted invalid %',v.label; END IF;
  n:=n+1;
 END LOOP;
 -- Same purpose admits the supported image formats, at the existing limit.
 FOR v IN SELECT unnest(ARRAY['image/png','image/webp','image/heic','image/heif']) mime LOOP
  INSERT INTO public.media_assets(id,user_id,kind,bucket_id,object_path,mime_type,declared_size_bytes,status,source_request_hash,retention_until)
  VALUES('00000000-0000-4000-8000-00000000f464',u,'conversation_photo','meal-photos',u::text||'/00000000-0000-4000-8000-00000000f464.jpg',v.mime,15728640,'pending_upload',repeat('6',64),now()+interval '30 days');
  DELETE FROM public.media_assets WHERE id='00000000-0000-4000-8000-00000000f464';
  n:=n+1;
 END LOOP;
 -- The identity, source, and purpose cannot change after upload-ticket creation.
 FOR v IN SELECT * FROM (VALUES
  ('kind','meal_photo'),('mime_type','image/png'),('context_text','changed'),
  ('bucket_id','gym-photos'),('source_request_hash',repeat('b',64)),
  ('object_path',u::text||'/00000000-0000-4000-8000-00000000f465.jpg')
 ) t(column_name,value) LOOP
  refused:=false;
  BEGIN
   EXECUTE format('UPDATE public.media_assets SET %I=$1 WHERE id=$2',v.column_name) USING v.value,a;
  EXCEPTION WHEN check_violation THEN refused:=true; END;
  IF NOT refused THEN RAISE EXCEPTION 'T46 source metadata mutable: %',v.column_name; END IF;
  n:=n+1;
 END LOOP;
 INSERT INTO public.media_assets(id,user_id,kind,bucket_id,object_path,mime_type,declared_size_bytes,status,source_request_hash,retention_until)
 VALUES('00000000-0000-4000-8000-00000000f466',u,'meal_photo','meal-photos',u::text||'/00000000-0000-4000-8000-00000000f466.jpg','image/jpeg',1024,'pending_upload',repeat('7',64),now()+interval '30 days');
 refused:=false;
 BEGIN
  UPDATE public.media_assets SET kind='conversation_photo' WHERE id='00000000-0000-4000-8000-00000000f466';
 EXCEPTION WHEN check_violation THEN refused:=true; END;
 IF NOT refused THEN RAISE EXCEPTION 'T46 old asset adopted a new purpose'; END IF;
 n:=n+1;
 -- The genuine existing claim/completion path supports the additive kind.
 UPDATE public.media_assets SET status='uploaded',actual_size_bytes=1024,uploaded_at=clock_timestamp() WHERE id=a;
 c:=public.claim_media_asset_processing(a,u,repeat('8',64));
 IF c->>'kind' IS DISTINCT FROM 'conversation_photo' OR c->>'user_id' IS DISTINCT FROM u::text THEN
  RAISE EXCEPTION 'T46 genuine claim lost purpose/owner'; END IF;
 n:=n+1;
 IF NOT public.complete_media_asset_processing(a,u,repeat('8',64),'{"schema":"conversation.image-result.v1","status":"unsupported","classification":"body","reason":"image_not_supported_for_conversation"}'::jsonb) THEN
  RAISE EXCEPTION 'T46 genuine completion lost claim'; END IF;
 IF (SELECT status FROM public.media_assets WHERE id=a)<>'processed' THEN RAISE EXCEPTION 'T46 completion not persisted'; END IF;
 n:=n+1;
 IF public.complete_media_asset_processing(a,u,repeat('9',64),'{}'::jsonb) THEN
  RAISE EXCEPTION 'T46 another request completed the asset'; END IF;
 n:=n+1;
 IF has_table_privilege('authenticated','public.media_assets','INSERT') OR
    has_table_privilege('authenticated','public.media_assets','UPDATE') OR
    has_column_privilege('authenticated','public.media_assets','object_path','SELECT') OR
    has_column_privilege('authenticated','public.media_assets','processing_result','SELECT') THEN
  RAISE EXCEPTION 'T46 widened private media grants'; END IF;
 n:=n+1;
 RAISE NOTICE 'T46 purpose assertions PASS: %',n;
END $test$;
ROLLBACK;
