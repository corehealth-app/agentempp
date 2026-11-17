-- Local rollback only. Actual writers/replay, synthetic resolution and Storage
-- metadata; no external payload operation or automatic nutrition QA claim.
BEGIN;
SET LOCAL request.jwt.claims='{"role":"service_role"}';
SET LOCAL timezone='UTC';SET LOCAL datestyle='ISO,YMD';
\ir fixtures/conversation_private_media_capture_fixture.sql
\ir fixtures/conversation_meal_atomic_writer_fixture.sql
CREATE TEMP TABLE disposal_history_checks(label text PRIMARY KEY);
CREATE FUNCTION pg_temp.history_ok(v boolean,label text) RETURNS void LANGUAGE plpgsql AS $$
BEGIN IF v IS DISTINCT FROM true THEN RAISE EXCEPTION 'PRIVATE_DISPOSAL_HISTORY_FAIL:%',label;END IF;
INSERT INTO disposal_history_checks VALUES(label);END $$;
DO $cases$
DECLARE s jsonb;q jsonb;r jsonb;prepared jsonb;receipt jsonb;u uuid;e uuid;child uuid;a uuid;
 claim jsonb;token uuid;p text;kind text;input_hash text;
BEGIN
 FOREACH kind IN ARRAY ARRAY['meal.report','workout.report'] LOOP
  s:=pg_temp.private_seed('audio_note',NULL,CASE kind WHEN 'meal.report' THEN '{"text":"Comi arroz 100 g"}'::jsonb ELSE '{"text":"Fiz 30 minutos de caminhada leve"}'::jsonb END);
  u:=(s->>'owner')::uuid;e:=(s->>'epoch')::uuid;a:=(s->>'asset')::uuid;
  q:=pg_temp.private_select(s,kind);child:=(q#>>'{sealed,selection,command,command_id}')::uuid;
  input_hash:=q#>>'{sealed,selection,command,input_hash}';
  IF kind='meal.report' THEN
   r:=public.capture_conversation_meal_source(u,child);
   prepared:=public.prepare_conversation_meal(u,child,pg_temp.writer_resolved(r));
   receipt:=public.commit_conversation_meal(u,child,prepared->>'resolved_hash');
  ELSE
   r:=public.capture_conversation_workout_source(u,child,q#>>'{sealed,selection,command,input_hash}',e);
   prepared:=public.prepare_conversation_workout(u,child,q#>>'{sealed,selection,command,input_hash}',r->>'source_hash',e,private.conversation_workout_report(r->'context',r->>'source_hash'));
   receipt:=public.commit_conversation_workout(u,child,q#>>'{sealed,selection,command,input_hash}',r->>'source_hash',e,prepared->>'prepared_hash',prepared->'prepared');
  END IF;
  PERFORM pg_temp.history_ok(receipt->>'action'='committed','original writer commits before disposal '||kind);
  PERFORM pg_temp.history_ok(public.close_conversation_media_v2(u,a),'explicit disposal closes factual source '||kind);
  q:=public.claim_conversation_media_disposal_batch_v2(100);
  SELECT x INTO claim FROM jsonb_array_elements(q->'items')x WHERE x->>'asset_id'=a::text;
  token:=(claim->>'claim_token')::uuid;p:=claim->>'object_path';
  INSERT INTO storage.objects(bucket_id,name,version,metadata) VALUES('audio-notes',p,gen_random_uuid()::text,'{"size":0}');
  PERFORM public.acknowledge_conversation_media_disposal_v2(a,u,token);
  PERFORM pg_temp.history_ok((SELECT status='deleted' AND processing_result IS NULL FROM private.conversation_media_assets_v2 WHERE id=a),'catalog has no interpretation after disposition '||kind);
  IF kind='meal.report' THEN
   q:=public.capture_conversation_meal_source(u,child);
   PERFORM pg_temp.history_ok(q-'action'=r-'action','historical source and hash preserved '||kind);
   PERFORM pg_temp.history_ok(public.commit_conversation_meal(u,child,NULL)=jsonb_set(receipt,'{action}','"replay"'),'original receipt survives disposition '||kind);
   PERFORM pg_temp.history_ok((SELECT count(*)=1 FROM public.meal_logs WHERE user_id=u),'disposal/reopen creates no second meal');
  ELSE
   q:=public.capture_conversation_workout_source(u,child,input_hash,e);
   PERFORM pg_temp.history_ok(q-'action'=r-'action','historical source and hash preserved '||kind);
   PERFORM pg_temp.history_ok(public.commit_conversation_workout(u,child,input_hash,r->>'source_hash',e,prepared->>'prepared_hash',prepared->'prepared')=jsonb_set(receipt,'{action}','"replay"'),'original receipt survives disposition '||kind);
   PERFORM pg_temp.history_ok((SELECT count(*)=1 FROM public.workout_logs WHERE user_id=u),'disposal/reopen creates no second workout');
  END IF;
  PERFORM pg_temp.history_ok(NOT EXISTS(SELECT 1 FROM public.media_assets WHERE id=a),'no public mirror introduced by disposition '||kind);
 END LOOP;
END $cases$;
SELECT jsonb_build_object('schema','conversation.private-disposal-history-qa.v2','checks',(SELECT count(*) FROM disposal_history_checks));
ROLLBACK;
