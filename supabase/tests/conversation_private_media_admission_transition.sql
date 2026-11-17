-- Real local PostgreSQL only; all fixtures roll back. No Storage/model calls.
BEGIN;
SET LOCAL request.jwt.claims='{"role":"service_role"}';
CREATE TEMP TABLE private_transition_checks(label text PRIMARY KEY);
CREATE FUNCTION pg_temp.transition_ok(v boolean,label text) RETURNS void LANGUAGE plpgsql AS $$
BEGIN IF v IS DISTINCT FROM true THEN RAISE EXCEPTION 'PRIVATE_TRANSITION_FAIL:%',label;END IF;
INSERT INTO private_transition_checks VALUES(label);END $$;
DO $cases$
DECLARE u uuid:=gen_random_uuid();e uuid:=gen_random_uuid();a uuid:=gen_random_uuid();i uuid:=gen_random_uuid();old_a uuid:=gen_random_uuid();old_i uuid:=gen_random_uuid();t_i uuid:=gen_random_uuid();raw jsonb;old_raw jsonb;q jsonb;before_hash text;denied boolean;
BEGIN
 INSERT INTO public.users(id,email,status,timezone,country,country_confirmed) VALUES(u,'private-transition-'||u||'@example.invalid','active','UTC','BR',true);
 INSERT INTO private.workout_strength_authority_epochs(user_id,epoch,changed_at) VALUES(u,e,clock_timestamp());
 PERFORM public.create_conversation_media_asset_v2(u,a,'audio_note','audio/mp4',8,NULL,repeat('a',64));
 raw:=jsonb_build_object('intake_protocol','conversation.intake.v1','intake_id',i,'source',jsonb_build_object('channel','media','media_asset_id',a,'user_action','report_actual_record'));
 PERFORM pg_temp.transition_ok(public.admit_conversation_intake(u,e,raw)->>'action'='input_conflict','old unversioned caller cannot freeze new private source in legacy intake');
 PERFORM pg_temp.transition_ok(NOT EXISTS(SELECT 1 FROM private.conversation_intake_ids WHERE user_id=u AND intake_id=i),'rejected old request leaves no immutable wrong admission');
 q:=public.admit_conversation_versioned_media_intake_v2(u,e,raw);
 PERFORM pg_temp.transition_ok(q->>'action'='admitted' AND EXISTS(SELECT 1 FROM private.conversation_private_media_intakes_v2 WHERE user_id=u AND intake_id=i AND asset_id=a),'same intake ID safely resumes through atomic private dispatcher');
 PERFORM pg_temp.transition_ok(public.admit_conversation_intake(u,e,raw)->>'action'='replay','old retry of already admitted private intake cannot change its provenance');
 PERFORM pg_temp.transition_ok(public.admit_conversation_versioned_media_intake_v2(u,e,raw)->>'action'='replay','new retry keeps original private admission');
 raw:=jsonb_set(raw,'{intake_id}',to_jsonb(gen_random_uuid()::text));
 PERFORM pg_temp.transition_ok(public.admit_conversation_intake(u,gen_random_uuid(),raw)->>'action'='stale_epoch','old wrong epoch retains original refusal before new source guard');
 PERFORM pg_temp.transition_ok(public.admit_conversation_intake(u,NULL,raw)->>'action'='stale_epoch','null epoch remains stale');
 INSERT INTO public.media_assets(id,user_id,kind,bucket_id,object_path,mime_type,declared_size_bytes,status,source_request_hash,retention_until)
 VALUES(old_a,u,'audio_note','audio-notes',u||'/'||old_a||'.m4a','audio/mp4',8,'pending_upload',repeat('b',64),clock_timestamp()+interval '30days');
 old_raw:=jsonb_set(jsonb_set(raw,'{intake_id}',to_jsonb(old_i::text)),'{source,media_asset_id}',to_jsonb(old_a::text));
 q:=public.admit_conversation_intake(u,e,old_raw);PERFORM pg_temp.transition_ok(q->>'action'='admitted','old public source admission remains available');
 SELECT encode(sha256(convert_to(to_jsonb(x)::text,'UTF8')),'hex') INTO before_hash FROM private.conversation_intake_ids x WHERE user_id=u AND intake_id=old_i;
 DELETE FROM public.media_assets WHERE id=old_a;
 PERFORM public.create_conversation_media_asset_v2(u,old_a,'audio_note','audio/mp4',8,NULL,repeat('b',64));
 PERFORM pg_temp.transition_ok(public.admit_conversation_intake(u,e,old_raw)->>'action'='replay','old admission replays after source ID is reused by private media');
 PERFORM pg_temp.transition_ok(public.admit_conversation_versioned_media_intake_v2(u,e,old_raw)->>'action'='replay' AND NOT EXISTS(SELECT 1 FROM private.conversation_private_media_intakes_v2 WHERE user_id=u AND intake_id=old_i),'dispatcher never upgrades a historical public intake');
 PERFORM pg_temp.transition_ok(before_hash=(SELECT encode(sha256(convert_to(to_jsonb(x)::text,'UTF8')),'hex') FROM private.conversation_intake_ids x WHERE user_id=u AND intake_id=old_i),'original legacy admission row stays byte exact');
 raw:=jsonb_set(raw,'{intake_id}',to_jsonb(t_i::text));raw:=jsonb_set(raw,'{source}','{"channel":"text","text":"Comi arroz cozido 100 g"}');
 PERFORM pg_temp.transition_ok(public.admit_conversation_intake(u,e,raw)->>'action'='admitted','ordinary text uses original admission');
 PERFORM pg_temp.transition_ok(NOT EXISTS(SELECT 1 FROM public.meal_logs WHERE user_id=u) AND NOT EXISTS(SELECT 1 FROM public.workout_logs WHERE user_id=u),'admission alone creates no facts or rewards');
 PERFORM pg_temp.transition_ok(NOT has_function_privilege('service_role','private.admit_conversation_intake_legacy_v2(uuid,uuid,jsonb)','EXECUTE') AND NOT has_function_privilege('authenticated','public.admit_conversation_intake(uuid,uuid,jsonb)','EXECUTE'),'original raw implementation remains backend-internal and client cannot bypass guard');
 denied:=false;BEGIN EXECUTE 'SET LOCAL ROLE service_role';PERFORM private.admit_conversation_intake_legacy_v2(u,e,raw);EXCEPTION WHEN insufficient_privilege THEN denied:=true;END;RESET ROLE;
 PERFORM pg_temp.transition_ok(denied,'actual service role cannot call private raw implementation');
END $cases$;
SELECT jsonb_build_object('schema','conversation.private-admission-transition-qa.v2','checks',(SELECT count(*) FROM private_transition_checks));
ROLLBACK;
