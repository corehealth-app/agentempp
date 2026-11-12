-- Additive ordinary-photo lineage. Raw worker envelope stays immutable and
-- hash-bound; classification never establishes consumed/performed authority.
-- No flags, jobs, records, uploads, rewards, or legacy raw media changes.
BEGIN;
DO $preflight$
DECLARE sig text;expected text;
BEGIN
 IF current_user<>'postgres' THEN RAISE EXCEPTION 'ordinary_photo_requires_postgres' USING ERRCODE='42501';END IF;
 IF to_regprocedure('private.conversation_photo_domain_allowed(text,jsonb,text)') IS NOT NULL
 OR to_regprocedure('private.conversation_meal_media_analysis(text,jsonb)') IS NOT NULL THEN RAISE EXCEPTION 'ordinary_photo_unknown_existing_object';END IF;
 FOR sig,expected IN SELECT * FROM (VALUES
 ('private.conversation_intake_context(uuid,uuid)','f1c060fdee8b7212f393998d4d287b9ab7276daca9af9522fb0b6b7292d52d8c'),
 ('private.conversation_intake_media_projection(uuid,jsonb,boolean,boolean)','f00ef3b921c1781756854762d2be13048a5dbab5af9bf855f730ca718c5822be'),
 ('public.seal_conversation_intake_routing(uuid,uuid,text,uuid,text,uuid,jsonb)','d18f71aeea2d7fc6a95e283f87c144e178051dfae0a93ac31f0fd06725cf5315'),
 ('private.conversation_meal_source_at(uuid,uuid,timestamp with time zone)','0cd7e0c3ecb7e9ce8346e8b93e9e80038bf8f179556c07dc0b92b1e1d1dce2b2'),
 ('private.conversation_continuation_original_current_at(uuid,jsonb,timestamp with time zone)','2997f98dc0287e7d8c26c6e597037bf4946031ec436e650f8d22a99e51caeb95'),
 ('private.conversation_workout_source_at(uuid,uuid,timestamp with time zone)','6233eda6ae683a9cc74776cf548c2867afc44c267189b43abb97bb25a7905f6b'),
 ('private.assert_conversation_semantic_result(jsonb,private.conversation_meal_semantic_attempts,jsonb)','1107de11a4a3a51b864aa449c831db4b83034220d812c134904d9b488de32032')
 ) AS pins(signature,hash) LOOP
  IF to_regprocedure(sig) IS NULL OR (SELECT encode(sha256(convert_to(prosrc,'UTF8')),'hex') FROM pg_proc WHERE oid=to_regprocedure(sig)) IS DISTINCT FROM expected THEN RAISE EXCEPTION 'ordinary_photo_unknown_substrate:%',sig;END IF;
 END LOOP;
END $preflight$;
CREATE FUNCTION private.conversation_photo_domain_allowed(kind text,processed jsonb,domain text) RETURNS boolean
LANGUAGE sql IMMUTABLE SET search_path=pg_catalog AS $$
 SELECT coalesce(CASE WHEN kind='conversation_photo' THEN
  processed->>'schema'='conversation.image-result.v1' AND processed->>'status'='ready'
  AND processed#>>'{analysis,type}'=processed->>'classification'
  AND ((domain='meal.report' AND (processed->>'classification'='meal' OR (processed->>'classification'='nutrition_label' AND jsonb_typeof(processed#>'{analysis,product_name}')='string' AND nullif(btrim(processed#>>'{analysis,product_name}'),'') IS NOT NULL AND char_length(processed#>>'{analysis,product_name}')<=240)))
    OR (domain='workout.report' AND processed->>'classification'='equipment'))
 ELSE (domain='meal.report' AND kind IN('meal_photo','audio_note'))
   OR (domain='workout.report' AND kind IN('gym_photo','audio_note')) END,false);
$$;
CREATE FUNCTION private.conversation_meal_media_analysis(kind text,processed jsonb) RETURNS jsonb
LANGUAGE plpgsql IMMUTABLE SET search_path=pg_catalog AS $$
DECLARE analysis jsonb;name text;
BEGIN
 IF kind IS DISTINCT FROM 'conversation_photo' THEN RETURN processed;END IF;
 IF NOT private.conversation_photo_domain_allowed(kind,processed,'meal.report') THEN RAISE EXCEPTION 'ordinary_photo_not_meal' USING ERRCODE='22023';END IF;
 analysis:=processed->'analysis';
 IF processed->>'classification'='meal' THEN RETURN analysis;END IF;
 -- A printed serving is never evidence of the amount consumed. Zero here is
 -- the existing missing-portion observation sentinel, never a saved quantity.
 name:=analysis->>'product_name';
 IF jsonb_typeof(analysis->'product_name') IS DISTINCT FROM 'string' OR nullif(btrim(name),'') IS NULL OR char_length(name)>240 THEN RAISE EXCEPTION 'ordinary_label_product_required' USING ERRCODE='22023';END IF;
 RETURN jsonb_build_object('type','meal','items',jsonb_build_array(jsonb_build_object('name',name,'quantity_g_estimate',0,'confidence',analysis->'confidence')),'nutrition_label_visible',true,'nutrition_label',analysis);
END $$;
DO $patch$
DECLARE body text:=pg_get_functiondef('private.conversation_intake_context(uuid,uuid)'::regprocedure);old text:=$old$m.kind NOT IN('meal_photo','audio_note','gym_photo')$old$;new text:=$new$m.kind NOT IN('meal_photo','audio_note','gym_photo','conversation_photo')$new$;
BEGIN
 IF (length(body)-length(replace(body,old,'')))/length(old)<>1 THEN RAISE EXCEPTION 'ordinary_photo_hook_mismatch:%', 'private.conversation_intake_context(uuid,uuid)';END IF;
 EXECUTE replace(body,old,new);
END $patch$;
DO $patch$
DECLARE body text:=pg_get_functiondef('private.conversation_intake_media_projection(uuid,jsonb,boolean,boolean)'::regprocedure);old text:=$old$OR (r.decision->>'kind'='meal.report' AND media->>'kind' NOT IN('meal_photo','audio_note'))
 OR (r.decision->>'kind'='workout.report' AND media->>'kind' NOT IN('gym_photo','audio_note'))$old$;new text:=$new$OR NOT private.conversation_photo_domain_allowed(media->>'kind',media->'processing_result',r.decision->>'kind')$new$;
BEGIN
 IF (length(body)-length(replace(body,old,'')))/length(old)<>1 THEN RAISE EXCEPTION 'ordinary_photo_hook_mismatch:%', 'private.conversation_intake_media_projection(uuid,jsonb,boolean,boolean)';END IF;
 EXECUTE replace(body,old,new);
END $patch$;
DO $patch$
DECLARE body text:=pg_get_functiondef('public.seal_conversation_intake_routing(uuid,uuid,text,uuid,text,uuid,jsonb)'::regprocedure);old text:=$old$ IF s.context#>>'{source_input,source,channel}'='media' AND
  ((p_decision->>'kind'='meal.report' AND s.context#>>'{media,kind}' NOT IN('meal_photo','audio_note')) OR
   (p_decision->>'kind'='workout.report' AND s.context#>>'{media,kind}' NOT IN('gym_photo','audio_note'))) THEN RETURN '{"action":"media_projection_required"}';END IF;$old$;new text:=$new$ IF s.context#>>'{source_input,source,channel}'='media' AND p_decision->>'kind' IN('meal.report','workout.report')
 AND NOT private.conversation_photo_domain_allowed(s.context#>>'{media,kind}',s.context#>'{media,processing_result}',p_decision->>'kind') THEN RETURN '{"action":"media_projection_required"}';END IF;$new$;
BEGIN
 IF (length(body)-length(replace(body,old,'')))/length(old)<>1 THEN RAISE EXCEPTION 'ordinary_photo_hook_mismatch:%', 'public.seal_conversation_intake_routing(uuid,uuid,text,uuid,text,uuid,jsonb)';END IF;
 EXECUTE replace(body,old,new);
END $patch$;
DO $patch$
DECLARE body text:=pg_get_functiondef('private.conversation_meal_source_at(uuid,uuid,timestamp with time zone)'::regprocedure);old text:=$old$m.kind NOT IN('meal_photo','audio_note')$old$;new text:=$new$(m.kind NOT IN('meal_photo','audio_note') AND NOT (m.kind='conversation_photo' AND projection IS NOT NULL AND private.conversation_photo_domain_allowed(m.kind,m.processing_result,'meal.report')))$new$;
BEGIN
 IF (length(body)-length(replace(body,old,'')))/length(old)<>1 THEN RAISE EXCEPTION 'ordinary_photo_hook_mismatch:%', 'private.conversation_meal_source_at(uuid,uuid,timestamp with time zone)';END IF;
 EXECUTE replace(body,old,new);
END $patch$;
DO $patch$
DECLARE body text:=pg_get_functiondef('private.conversation_meal_source_at(uuid,uuid,timestamp with time zone)'::regprocedure);old text:=$old$jsonb_typeof(m.processing_result->'items') IS DISTINCT FROM 'array' OR jsonb_array_length(m.processing_result->'items') NOT BETWEEN 1 AND 30$old$;new text:=$new$jsonb_typeof(private.conversation_meal_media_analysis(m.kind,m.processing_result)->'items') IS DISTINCT FROM 'array' OR jsonb_array_length(private.conversation_meal_media_analysis(m.kind,m.processing_result)->'items') NOT BETWEEN 0 AND 30 OR (jsonb_array_length(private.conversation_meal_media_analysis(m.kind,m.processing_result)->'items')=0 AND (m.kind<>'conversation_photo' OR jsonb_array_length(units)=0))$new$;
BEGIN
 IF (length(body)-length(replace(body,old,'')))/length(old)<>1 THEN RAISE EXCEPTION 'ordinary_photo_hook_mismatch:%', 'private.conversation_meal_source_at(uuid,uuid,timestamp with time zone)';END IF;
 EXECUTE replace(body,old,new);
END $patch$;
DO $patch$
DECLARE body text:=pg_get_functiondef('private.conversation_meal_source_at(uuid,uuid,timestamp with time zone)'::regprocedure);old text:=$old$units:=units||jsonb_build_array('vision_items');$old$;new text:=$new$IF jsonb_array_length(private.conversation_meal_media_analysis(m.kind,m.processing_result)->'items')>0 THEN units:=units||jsonb_build_array('vision_items');END IF;$new$;
BEGIN
 IF (length(body)-length(replace(body,old,'')))/length(old)<>1 THEN RAISE EXCEPTION 'ordinary_photo_hook_mismatch:%', 'private.conversation_meal_source_at(uuid,uuid,timestamp with time zone)';END IF;
 EXECUTE replace(body,old,new);
END $patch$;
DO $patch$
DECLARE body text:=pg_get_functiondef('private.conversation_continuation_original_current_at(uuid,jsonb,timestamp with time zone)'::regprocedure);old text:=$old$m.kind NOT IN('meal_photo','audio_note')$old$;new text:=$new$(m.kind NOT IN('meal_photo','audio_note') AND NOT (m.kind='conversation_photo' AND raw ? 'intake_origin' AND private.conversation_photo_domain_allowed(m.kind,m.processing_result,'meal.report')))$new$;
BEGIN
 IF (length(body)-length(replace(body,old,'')))/length(old)<>1 THEN RAISE EXCEPTION 'ordinary_photo_hook_mismatch:%', 'private.conversation_continuation_original_current_at(uuid,jsonb,timestamp with time zone)';END IF;
 EXECUTE replace(body,old,new);
END $patch$;
DO $patch$
DECLARE body text:=pg_get_functiondef('private.conversation_continuation_original_current_at(uuid,jsonb,timestamp with time zone)'::regprocedure);old text:=$old$jsonb_typeof(m.processing_result->'items') IS DISTINCT FROM 'array' OR jsonb_array_length(m.processing_result->'items') NOT BETWEEN 1 AND 30$old$;new text:=$new$jsonb_typeof(private.conversation_meal_media_analysis(m.kind,m.processing_result)->'items') IS DISTINCT FROM 'array' OR jsonb_array_length(private.conversation_meal_media_analysis(m.kind,m.processing_result)->'items') NOT BETWEEN 0 AND 30 OR (jsonb_array_length(private.conversation_meal_media_analysis(m.kind,m.processing_result)->'items')=0 AND (m.kind<>'conversation_photo' OR jsonb_array_length(units)=0))$new$;
BEGIN
 IF (length(body)-length(replace(body,old,'')))/length(old)<>1 THEN RAISE EXCEPTION 'ordinary_photo_hook_mismatch:%', 'private.conversation_continuation_original_current_at(uuid,jsonb,timestamp with time zone)';END IF;
 EXECUTE replace(body,old,new);
END $patch$;
DO $patch$
DECLARE body text:=pg_get_functiondef('private.conversation_continuation_original_current_at(uuid,jsonb,timestamp with time zone)'::regprocedure);old text:=$old$units:=units||jsonb_build_array('vision_items');$old$;new text:=$new$IF jsonb_array_length(private.conversation_meal_media_analysis(m.kind,m.processing_result)->'items')>0 THEN units:=units||jsonb_build_array('vision_items');END IF;$new$;
BEGIN
 IF (length(body)-length(replace(body,old,'')))/length(old)<>1 THEN RAISE EXCEPTION 'ordinary_photo_hook_mismatch:%', 'private.conversation_continuation_original_current_at(uuid,jsonb,timestamp with time zone)';END IF;
 EXECUTE replace(body,old,new);
END $patch$;
DO $patch$
DECLARE body text:=pg_get_functiondef('private.conversation_workout_source_at(uuid,uuid,timestamp with time zone)'::regprocedure);old text:=$old$m.kind NOT IN('gym_photo','audio_note')$old$;new text:=$new$(m.kind NOT IN('gym_photo','audio_note') AND NOT (m.kind='conversation_photo' AND projection IS NOT NULL AND private.conversation_photo_domain_allowed(m.kind,m.processing_result,'workout.report')))$new$;
BEGIN
 IF (length(body)-length(replace(body,old,'')))/length(old)<>1 THEN RAISE EXCEPTION 'ordinary_photo_hook_mismatch:%', 'private.conversation_workout_source_at(uuid,uuid,timestamp with time zone)';END IF;
 EXECUTE replace(body,old,new);
END $patch$;
DO $patch$
DECLARE body text:=pg_get_functiondef('private.assert_conversation_semantic_result(jsonb,private.conversation_meal_semantic_attempts,jsonb)'::regprocedure);old text:=$old$c#>'{media,processing_result,items}'$old$;new text:=$new$private.conversation_meal_media_analysis(c#>>'{media,kind}',c#>'{media,processing_result}')->'items'$new$;
BEGIN
 IF (length(body)-length(replace(body,old,'')))/length(old)<>1 THEN RAISE EXCEPTION 'ordinary_photo_hook_mismatch:%', 'private.assert_conversation_semantic_result(jsonb,private.conversation_meal_semantic_attempts,jsonb)';END IF;
 EXECUTE replace(body,old,new);
END $patch$;
REVOKE ALL ON FUNCTION private.conversation_photo_domain_allowed(text,jsonb,text),private.conversation_meal_media_analysis(text,jsonb) FROM PUBLIC,anon,authenticated,service_role;
COMMIT;
