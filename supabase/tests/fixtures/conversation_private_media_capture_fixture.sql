-- Synthetic rollback helpers only. Actual private intake/processing RPCs.
CREATE FUNCTION pg_temp.private_seed(k text,caption text,processed jsonb) RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE u uuid:=gen_random_uuid();e uuid:=gen_random_uuid();a uuid:=gen_random_uuid();i uuid:=gen_random_uuid();t uuid:=gen_random_uuid();c jsonb;raw jsonb;
BEGIN
 INSERT INTO public.users(id,email,status,timezone,country,country_confirmed) VALUES(u,'private-capture-'||u||'@example.invalid','active','UTC','BR',true);
 INSERT INTO private.workout_strength_authority_epochs(user_id,epoch,changed_at) VALUES(u,e,clock_timestamp());
 PERFORM public.create_conversation_media_asset_v2(u,a,k,CASE k WHEN 'audio_note' THEN 'audio/mp4' ELSE 'image/jpeg' END,8,NULL,encode(sha256(convert_to(a::text,'UTF8')),'hex'));
 PERFORM public.prepare_conversation_media_upload_v2(u,a,t);
 PERFORM public.register_conversation_media_upload_v2(u,a,t,date_trunc('second',clock_timestamp())+interval '2hours');
 PERFORM public.complete_conversation_media_upload_v2(u,a,8,CASE k WHEN 'audio_note' THEN 'audio/mp4' ELSE 'image/jpeg' END,NULL);
 c:=public.claim_conversation_media_processing_v2(u,a,repeat('a',64));
 IF NOT public.complete_conversation_media_processing_v2(u,a,repeat('a',64),(c#>>'{claim,token}')::uuid,processed) THEN RAISE EXCEPTION 'synthetic processing failed';END IF;
 raw:=jsonb_build_object('intake_protocol','conversation.intake.v1','intake_id',i,'source',jsonb_strip_nulls(jsonb_build_object('channel','media','media_asset_id',a,'user_action','report_actual_record','caption',caption)));
 RETURN jsonb_build_object('owner',u,'epoch',e,'asset',a,'intake',i,'input',raw);
END $$;
CREATE FUNCTION pg_temp.private_select(s jsonb,domain text) RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE u uuid:=(s->>'owner')::uuid;e uuid:=(s->>'epoch')::uuid;i uuid:=(s->>'intake')::uuid;a jsonb;c jsonb;claim jsonb;sealed jsonb;
BEGIN
 a:=public.admit_conversation_private_media_intake_v2(u,e,s->'input');
 c:=public.capture_conversation_intake_source(u,i,a#>>'{intake,input_hash}',e);
 claim:=public.claim_conversation_intake_routing(u,i,a#>>'{intake,input_hash}',e,c->>'source_hash');
 sealed:=public.seal_conversation_intake_routing(u,i,a#>>'{intake,input_hash}',e,c->>'source_hash',(claim->>'claim_id')::uuid,jsonb_build_object('schema','conversation.intake-routing.v1','kind',domain,'reason','processed_media_report'));
 RETURN jsonb_build_object('admission',a,'source',c,'claim',claim,'sealed',sealed);
END $$;
