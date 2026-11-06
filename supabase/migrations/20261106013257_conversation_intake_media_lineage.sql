-- Internal processed-media projection. Public v1 DTOs and historical receipts
-- stay literal; only T39/T41's original parent may mint its reserved typed child.
-- No new fact table, public media cutover, provider call or worker purpose.
BEGIN;
DO $preflight$
DECLARE sig text;expected text;
BEGIN
 IF current_user<>'postgres' THEN RAISE EXCEPTION 'intake_media_requires_postgres' USING ERRCODE='42501';END IF;
 IF to_regprocedure('private.conversation_intake_media_projection(uuid,jsonb,boolean,boolean)') IS NOT NULL THEN RAISE EXCEPTION 'intake_media_unknown_existing_object';END IF;
 FOR sig,expected IN SELECT * FROM (VALUES
 ('public.seal_conversation_intake_routing(uuid,uuid,text,uuid,text,uuid,jsonb)','4cc47588c0aaca58d5ca49847e27ec7ade861863efb92b98011e42c89d56e0fb'),
 ('public.admit_conversation_workout_command(uuid,uuid,jsonb)','5cf3dc1049b45d83e3fa92138063874343767f3b862d0ecb45dd77beba70cbb8'),
 ('public.admit_conversation_meal_command_fenced(uuid,jsonb,uuid)','01419c67be21ca3fee9e7cb24fd027b0fb9ae70ca1b5e1b48e449e33b756c41c'),
 ('public.admit_conversation_meal_command(uuid,jsonb)','5b3a9f658b240009ee7e5b0b435c68abbfb033ae85cce2a28cb542897bb225ef'),
 ('private.conversation_meal_source_at(uuid,uuid,timestamptz)','e252df2e79e94b457404feafde28b60cefe4a5f61ba894be67699134cf534c4c'),
 ('private.conversation_workout_source_at(uuid,uuid,timestamptz)','72091ebcded6b41cd4edfa9ef7c8b2a987d0aad2055bff47a6844bb31d6d8ee1'),
 ('private.conversation_workout_report(jsonb,text)','b87f0bbb69cf27e801b71f5916c146cdd5ccdd571d2711805cda886d3601b606'),
 ('private.conversation_semantic_text(jsonb,text)','adb1919672ee2f2c195817343bcf9687da92fa5f45cb4df331d546f888b24aa5'),
 ('private.conversation_continuation_original_current_at(uuid,jsonb,timestamptz)','c5331819daa206b983d6ca0fd7de3e0e764162c21385b4bbab4cbe24ef4e883b'),
 ('private.assert_conversation_semantic_result(jsonb,private.conversation_meal_semantic_attempts,jsonb)','372b83ed8b295780209058078e273e1417b1583f3e10c97aad90fc8a40b4a9d6')
 ) AS pins(signature,hash) LOOP
  IF to_regprocedure(sig) IS NULL OR (SELECT encode(sha256(convert_to(prosrc,'UTF8')),'hex') FROM pg_proc WHERE oid=to_regprocedure(sig)) IS DISTINCT FROM expected THEN RAISE EXCEPTION 'intake_media_unknown_substrate:%',sig;END IF;
 END LOOP;
END $preflight$;

-- Reconstruct from immutable originals, never from a caller-authored binding.
-- require_selection=false is private to the seal's atomic initial admission.
-- current_media=false is historical typed admission replay, not new writing.
CREATE FUNCTION private.conversation_intake_media_projection(u uuid,input jsonb,require_selection boolean,current_media boolean) RETURNS jsonb
LANGUAGE plpgsql VOLATILE SET search_path=pg_catalog SET timezone='UTC' SET datestyle='ISO,YMD' AS $$
DECLARE c private.conversation_intake_ids%ROWTYPE;s private.conversation_intake_sources%ROWTYPE;
 r private.conversation_intake_routing_results%ROWTYPE;claim uuid;origin jsonb;expected jsonb;projection jsonb;media jsonb;selection jsonb;fresh jsonb;gate text;h text;
BEGIN
 IF input#>>'{intake_origin,schema}' IS DISTINCT FROM 'conversation.intake-media-origin.v1' THEN RAISE EXCEPTION 'invalid_conversation_intake_media_origin' USING ERRCODE='22023';END IF;
 SELECT * INTO c FROM private.conversation_intake_ids WHERE user_id=u AND intake_id=(input#>>'{intake_origin,intake_id}')::uuid;
 IF NOT FOUND OR c.reserved_child_id::text IS DISTINCT FROM input->>'command_id' THEN RAISE EXCEPTION 'invalid_conversation_intake_media_child' USING ERRCODE='22023';END IF;
 gate:=private.lock_conversation_intake(u,c.intake_id,c.input_hash,c.epoch);IF gate<>'current' THEN RAISE EXCEPTION 'invalid_conversation_intake_media_epoch' USING ERRCODE='22023';END IF;
 SELECT * INTO STRICT s FROM private.conversation_intake_sources WHERE user_id=u AND intake_id=c.intake_id;
 SELECT claim_id INTO STRICT claim FROM private.conversation_intake_claims WHERE user_id=u AND intake_id=c.intake_id;
 SELECT * INTO STRICT r FROM private.conversation_intake_routing_results WHERE user_id=u AND intake_id=c.intake_id;
 media:=s.context->'media';
 IF s.context#>>'{source_input,source,channel}' IS DISTINCT FROM 'media' OR s.context#>>'{source_input,source,user_action}' IS DISTINCT FROM 'report_actual_record'
 OR r.decision->>'kind' NOT IN('meal.report','workout.report') OR r.decision->>'kind' IS DISTINCT FROM input->>'kind'
 OR media->>'owner_id' IS DISTINCT FROM u::text OR media->>'asset_id' IS DISTINCT FROM s.context#>>'{source_input,source,media_asset_id}'
 OR (r.decision->>'kind'='meal.report' AND media->>'kind' NOT IN('meal_photo','audio_note'))
 OR (r.decision->>'kind'='workout.report' AND media->>'kind' NOT IN('gym_photo','audio_note')) THEN RAISE EXCEPTION 'invalid_conversation_intake_media_domain' USING ERRCODE='22023';END IF;
 origin:=jsonb_build_object('schema','conversation.intake-media-origin.v1','intake_id',c.intake_id,'input_hash',c.input_hash,'source_hash',s.source_hash,'epoch',c.epoch,'claim_id',claim,'decision_hash',r.decision_hash);
 expected:=jsonb_build_object('command_protocol','conversation.command.v1','command_id',c.reserved_child_id,'kind',r.decision->>'kind','source',s.context#>'{source_input,source}','intake_origin',origin);
 IF r.decision->>'kind'='meal.report' AND s.context#>'{source_input,meal_type_hint}' IS NOT NULL THEN expected:=expected||jsonb_build_object('meal_type',s.context#>'{source_input,meal_type_hint}');END IF;
 IF input IS DISTINCT FROM expected THEN RAISE EXCEPTION 'invalid_conversation_intake_media_input' USING ERRCODE='22023';END IF;
 h:=encode(sha256(convert_to(private.conversation_command_canonical(input),'UTF8')),'hex');
 projection:=jsonb_build_object('schema','conversation.intake-media-projection.v1','origin',origin,'child_input_hash',h,'media',jsonb_build_object(
 'asset_id',media->'asset_id','owner_id',media->'owner_id','kind',media->'kind','processed_at',media->'processed_at','updated_at',media->'updated_at',
 'processing_hash',encode(sha256(convert_to(private.conversation_command_canonical(jsonb_build_object('context_text',media->'context_text','processing_result',media->'processing_result')),'UTF8')),'hex')));
 IF require_selection THEN
  SELECT x.selection INTO selection FROM private.conversation_intake_selections x WHERE user_id=u AND intake_id=c.intake_id;
  IF selection->>'schema' IS DISTINCT FROM 'conversation.intake-selection.v2' OR selection->'media_projection' IS DISTINCT FROM projection
   OR selection#>'{command,input}' IS DISTINCT FROM input OR selection#>>'{command,input_hash}' IS DISTINCT FROM h
   OR selection->'decision' IS DISTINCT FROM r.decision OR selection->>'decision_hash' IS DISTINCT FROM r.decision_hash THEN RAISE EXCEPTION 'invalid_conversation_intake_media_selection' USING ERRCODE='22023';END IF;
 END IF;
 IF current_media THEN
  fresh:=private.conversation_intake_context(u,c.intake_id);
  IF fresh ? 'action' OR fresh-'captured_at' IS DISTINCT FROM s.context-'captured_at' THEN RAISE EXCEPTION 'conversation_intake_media_changed' USING ERRCODE='40001';END IF;
 END IF;
 RETURN projection;
END $$;

CREATE FUNCTION private.admit_conversation_intake_media_child(u uuid,e uuid,input jsonb) RETURNS jsonb
LANGUAGE plpgsql VOLATILE SET search_path=pg_catalog SET timezone='UTC' SET datestyle='ISO,YMD' AS $$
DECLARE projection jsonb;h text;id uuid;at timestamptz;binding jsonb;
BEGIN
 projection:=private.conversation_intake_media_projection(u,input,false,true);id:=(input->>'command_id')::uuid;h:=projection->>'child_input_hash';
 IF e IS DISTINCT FROM (projection#>>'{origin,epoch}')::uuid THEN RETURN '{"action":"stale_epoch"}';END IF;
 IF EXISTS(SELECT 1 FROM private.conversation_meal_command_ids WHERE user_id=u AND command_id=id) OR EXISTS(SELECT 1 FROM private.conversation_workout_command_ids WHERE user_id=u AND command_id=id) THEN RETURN '{"action":"input_conflict"}';END IF;
 at:=clock_timestamp();IF private.conversation_workout_admission_count(u,e,at)>=10 THEN RETURN '{"action":"rate_limited"}';END IF;
 IF input->>'kind'='meal.report' THEN
  INSERT INTO private.conversation_meal_command_ids VALUES(u,id,h,'conversation.command.v1','meal.report',e,at,NULL);
  INSERT INTO private.conversation_meal_command_sources VALUES(u,id,input);
 ELSE
  INSERT INTO private.conversation_workout_command_ids VALUES(u,id,h,'conversation.command.v1','workout.report',e,at,NULL);
  INSERT INTO private.conversation_workout_inputs VALUES(u,id,input);
 END IF;
 binding:=jsonb_build_object('owner_id',u,'command_id',id,'input_hash',h,'epoch',e,'admitted_at',private.conversation_intake_clock(at));
 RETURN jsonb_build_object('action','admitted','command',binding,'media_projection',projection);
END $$;

-- Neutral alternatives can resume only an existing actually selected child;
-- this helper cannot create an identity, alter a selection or consume quota.
CREATE FUNCTION private.replay_conversation_intake_media_child(u uuid,e uuid,input jsonb,kind text) RETURNS jsonb
LANGUAGE plpgsql VOLATILE SET search_path=pg_catalog SET timezone='UTC' SET datestyle='ISO,YMD' AS $$
DECLARE projection jsonb;row jsonb;stored jsonb;id uuid;h text;actual_epoch uuid;
BEGIN
 PERFORM private.assert_trusted_backend();PERFORM private.lock_conversation_command_owner(u);
 SELECT epoch INTO actual_epoch FROM private.workout_strength_authority_epochs WHERE user_id=u FOR UPDATE;
 IF actual_epoch IS NULL OR actual_epoch IS DISTINCT FROM e THEN RETURN '{"action":"stale_epoch"}';END IF;
 IF input->>'kind' IS DISTINCT FROM kind THEN RAISE EXCEPTION 'invalid_conversation_intake_media_kind' USING ERRCODE='22023';END IF;
 id:=(input->>'command_id')::uuid;
 IF kind='meal.report' THEN
  SELECT to_jsonb(c) INTO row FROM private.conversation_meal_command_ids c WHERE user_id=u AND command_id=id FOR UPDATE;
  SELECT source_input INTO stored FROM private.conversation_meal_command_sources WHERE user_id=u AND command_id=id;
 ELSE
  SELECT to_jsonb(c) INTO row FROM private.conversation_workout_command_ids c WHERE user_id=u AND command_id=id FOR UPDATE;
  SELECT source_input INTO stored FROM private.conversation_workout_inputs WHERE user_id=u AND command_id=id;
 END IF;
 IF row IS NOT NULL AND (row->'invalidated_at'<>'null'::jsonb OR row->>'epoch' IS DISTINCT FROM e::text) THEN RETURN '{"action":"stale_epoch"}';END IF;
 projection:=private.conversation_intake_media_projection(u,input,true,false);h:=projection->>'child_input_hash';
 IF e IS DISTINCT FROM (projection#>>'{origin,epoch}')::uuid THEN RETURN '{"action":"stale_epoch"}';END IF;
 IF row IS NULL OR row->>'input_hash' IS DISTINCT FROM h OR stored IS DISTINCT FROM input THEN RAISE EXCEPTION 'invalid_conversation_intake_media_child' USING ERRCODE='22023';END IF;
 IF row->'invalidated_at'<>'null'::jsonb OR row->>'epoch' IS DISTINCT FROM e::text THEN RETURN '{"action":"stale_epoch"}';END IF;
 RETURN jsonb_build_object('action','replay','command',jsonb_build_object('owner_id',u,'command_id',id,'input_hash',h,'epoch',e,'admitted_at',private.conversation_intake_clock((row->>'admitted_at')::timestamptz)));
END $$;

-- Narrow, pinned transforms preserve every existing fence and receipt path.
DO $patch$
DECLARE sig text;body text;old text;new text;
BEGIN
 FOREACH sig IN ARRAY ARRAY['public.admit_conversation_meal_command(uuid,jsonb)','public.admit_conversation_meal_command_fenced(uuid,jsonb,uuid)','public.admit_conversation_workout_command(uuid,uuid,jsonb)'] LOOP
  body:=pg_get_functiondef(to_regprocedure(sig));old:='BEGIN';
  new:='BEGIN'||E'\n IF p_input ? ''intake_origin'' THEN RETURN private.replay_conversation_intake_media_child(p_user_id,'||CASE WHEN sig='public.admit_conversation_meal_command(uuid,jsonb)' THEN '(p_input#>>''{intake_origin,epoch}'')::uuid' ELSE 'p_expected_epoch' END||',p_input,'''||CASE WHEN sig LIKE '%workout%' THEN 'workout.report' ELSE 'meal.report' END||''');END IF;';
  IF (length(body)-length(replace(body,old,'')))/length(old)<>1 THEN RAISE EXCEPTION 'intake_media_admit_hook';END IF;
  EXECUTE replace(body,old,new);
 END LOOP;
 body:=pg_get_functiondef('public.seal_conversation_intake_routing(uuid,uuid,text,uuid,text,uuid,jsonb)'::regprocedure);
 old:=$n$ IF p_decision->>'kind' IN('meal.report','workout.report') AND s.context#>>'{source_input,source,channel}'='media' THEN RETURN '{"action":"media_projection_required"}';END IF;$n$;
 new:=$n$ IF s.context#>>'{source_input,source,channel}'='media' AND
  ((p_decision->>'kind'='meal.report' AND s.context#>>'{media,kind}' NOT IN('meal_photo','audio_note')) OR
   (p_decision->>'kind'='workout.report' AND s.context#>>'{media,kind}' NOT IN('gym_photo','audio_note'))) THEN RETURN '{"action":"media_projection_required"}';END IF;$n$;
 IF strpos(body,old)=0 THEN RAISE EXCEPTION 'intake_media_seal_refusal_hook';END IF;body:=replace(body,old,new);
 old:=$n$   IF p_decision->>'kind'='meal.report' THEN typed:=public.admit_conversation_meal_command_fenced(p_user_id,raw,p_expected_epoch);
   ELSE typed:=public.admit_conversation_workout_command(p_user_id,p_expected_epoch,raw);END IF;$n$;
 new:=$n$   IF s.context#>>'{source_input,source,channel}'='media' THEN
    raw:=raw||jsonb_build_object('intake_origin',jsonb_build_object('schema','conversation.intake-media-origin.v1','intake_id',c.intake_id,'input_hash',c.input_hash,'source_hash',s.source_hash,'epoch',c.epoch,'claim_id',actual_claim,'decision_hash',h));
    typed:=private.admit_conversation_intake_media_child(p_user_id,p_expected_epoch,raw);
   ELSIF p_decision->>'kind'='meal.report' THEN typed:=public.admit_conversation_meal_command_fenced(p_user_id,raw,p_expected_epoch);
   ELSE typed:=public.admit_conversation_workout_command(p_user_id,p_expected_epoch,raw);END IF;$n$;
 IF strpos(body,old)=0 THEN RAISE EXCEPTION 'intake_media_seal_admit_hook';END IF;body:=replace(body,old,new);
 old:=$n$  INSERT INTO private.conversation_intake_selections VALUES(p_user_id,p_intake_id,h,selection);$n$;
 new:=$n$  IF child IS NOT NULL AND raw ? 'intake_origin' THEN selection:=selection||jsonb_build_object('schema','conversation.intake-selection.v2','media_projection',typed->'media_projection');END IF;
$n$||old;
 IF strpos(body,old)=0 THEN RAISE EXCEPTION 'intake_media_seal_selection_hook';END IF;EXECUTE replace(body,old,new);
END $patch$;
-- SOURCE_PATCHES_BEGIN

DO $source_patch$
DECLARE body text:=pg_get_functiondef('private.conversation_meal_source_at(uuid,uuid,timestamptz)'::regprocedure);old text;new text;
BEGIN
 old:=$old$catalog jsonb;revision bigint;day date;observed timestamptz;caption text;transcript text;$old$;new:=$new$catalog jsonb;revision bigint;day date;observed timestamptz;caption text;transcript text;projection jsonb;$new$;
 IF (length(body)-length(replace(body,old,'')))/length(old)<>1 THEN RAISE EXCEPTION 'intake_media_source_hook:%',old;END IF;body:=replace(body,old,new);
 old:=$old$ SELECT source_input INTO STRICT input FROM private.conversation_meal_command_sources WHERE user_id=p_user AND command_id=p_command;$old$;new:=$new$ SELECT source_input INTO STRICT input FROM private.conversation_meal_command_sources WHERE user_id=p_user AND command_id=p_command;
 IF input ? 'intake_origin' THEN projection:=private.conversation_intake_media_projection(p_user,input,true,true);END IF;$new$;
 IF (length(body)-length(replace(body,old,'')))/length(old)<>1 THEN RAISE EXCEPTION 'intake_media_source_hook:%',old;END IF;body:=replace(body,old,new);
 old:=$old$caption:=coalesce(input#>>'{source,caption}',m.context_text);$old$;new:=$new$caption:=CASE WHEN projection IS NULL THEN coalesce(input#>>'{source,caption}',m.context_text) ELSE input#>>'{source,caption}' END;$new$;
 IF (length(body)-length(replace(body,old,'')))/length(old)<>1 THEN RAISE EXCEPTION 'intake_media_source_hook:%',old;END IF;body:=replace(body,old,new);
 old:=$old$  IF m.kind='audio_note' THEN$old$;new:=$new$  IF projection IS NOT NULL AND nullif(btrim(m.context_text),'') IS NOT NULL THEN units:=units||jsonb_build_array('media_context');END IF;
  IF m.kind='audio_note' THEN$new$;
 IF (length(body)-length(replace(body,old,'')))/length(old)<>1 THEN RAISE EXCEPTION 'intake_media_source_hook:%',old;END IF;body:=replace(body,old,new);
 old:=$old$  evidence:=jsonb_build_object('caption',caption,'transcript',transcript);$old$;new:=$new$  evidence:=jsonb_build_object('caption',caption,'transcript',transcript);
  IF projection IS NOT NULL THEN media:=media||jsonb_build_object('owner_id',m.user_id);evidence:=evidence||jsonb_build_object('context_text',m.context_text);END IF;$new$;
 IF (length(body)-length(replace(body,old,'')))/length(old)<>1 THEN RAISE EXCEPTION 'intake_media_source_hook:%',old;END IF;body:=replace(body,old,new);
 old:=$old$'schema','conversation.meal-source.v1'$old$;new:=$new$'schema',CASE WHEN projection IS NULL THEN 'conversation.meal-source.v1' ELSE 'conversation.meal-source.v2' END$new$;
 IF (length(body)-length(replace(body,old,'')))/length(old)<>1 THEN RAISE EXCEPTION 'intake_media_source_hook:%',old;END IF;body:=replace(body,old,new);
 old:=$old$c.epoch,day,observed)));$old$;new:=$new$c.epoch,day,observed)))||CASE WHEN projection IS NULL THEN '{}'::jsonb ELSE jsonb_build_object('intake_projection',projection) END;$new$;
 IF (length(body)-length(replace(body,old,'')))/length(old)<>1 THEN RAISE EXCEPTION 'intake_media_source_hook:%',old;END IF;body:=replace(body,old,new);
 EXECUTE body;
END $source_patch$;

DO $source_patch$
DECLARE body text:=pg_get_functiondef('private.conversation_workout_source_at(uuid,uuid,timestamptz)'::regprocedure);old text;new text;
BEGIN
 old:=$old$input jsonb;clinical jsonb;catalogue jsonb;media jsonb:=NULL;observed timestamptz;day date;$old$;new:=$new$input jsonb;clinical jsonb;catalogue jsonb;media jsonb:=NULL;observed timestamptz;day date;projection jsonb;$new$;
 IF (length(body)-length(replace(body,old,'')))/length(old)<>1 THEN RAISE EXCEPTION 'intake_media_source_hook:%',old;END IF;body:=replace(body,old,new);
 old:=$old$ SELECT source_input INTO STRICT input FROM private.conversation_workout_inputs WHERE user_id=p_user AND command_id=p_command;$old$;new:=$new$ SELECT source_input INTO STRICT input FROM private.conversation_workout_inputs WHERE user_id=p_user AND command_id=p_command;
 IF input ? 'intake_origin' THEN projection:=private.conversation_intake_media_projection(p_user,input,true,true);END IF;$new$;
 IF (length(body)-length(replace(body,old,'')))/length(old)<>1 THEN RAISE EXCEPTION 'intake_media_source_hook:%',old;END IF;body:=replace(body,old,new);
 old:=$old$  IF input#>>'{source,caption}' IS NOT NULL AND nullif(btrim(m.context_text),'') IS NOT NULL$old$;new:=$new$  IF projection IS NULL AND input#>>'{source,caption}' IS NOT NULL AND nullif(btrim(m.context_text),'') IS NOT NULL$new$;
 IF (length(body)-length(replace(body,old,'')))/length(old)<>1 THEN RAISE EXCEPTION 'intake_media_source_hook:%',old;END IF;body:=replace(body,old,new);
 old:=$old$'schema','conversation.workout-source.v1'$old$;new:=$new$'schema',CASE WHEN projection IS NULL THEN 'conversation.workout-source.v1' ELSE 'conversation.workout-source.v2' END$new$;
 IF (length(body)-length(replace(body,old,'')))/length(old)<>1 THEN RAISE EXCEPTION 'intake_media_source_hook:%',old;END IF;body:=replace(body,old,new);
 old:=$old$'media',media,'catalogue',catalogue);$old$;new:=$new$'media',media,'catalogue',catalogue)||CASE WHEN projection IS NULL THEN '{}'::jsonb ELSE jsonb_build_object('intake_projection',projection) END;$new$;
 IF (length(body)-length(replace(body,old,'')))/length(old)<>1 THEN RAISE EXCEPTION 'intake_media_source_hook:%',old;END IF;body:=replace(body,old,new);
 EXECUTE body;
END $source_patch$;

DO $source_patch$
DECLARE body text:=pg_get_functiondef('private.conversation_workout_report(jsonb,text)'::regprocedure);old text;new text;
BEGIN
 old:=$old$  v:=coalesce(src#>>'{source,caption}',c#>>'{media,context_text}');IF nullif(btrim(v),'') IS NOT NULL THEN units:=units||jsonb_build_array(jsonb_build_object('unit','media_caption','text',v));END IF;$old$;new:=$new$  v:=CASE WHEN c->>'schema'='conversation.workout-source.v2' THEN src#>>'{source,caption}' ELSE coalesce(src#>>'{source,caption}',c#>>'{media,context_text}') END;IF nullif(btrim(v),'') IS NOT NULL THEN units:=units||jsonb_build_array(jsonb_build_object('unit','media_caption','text',v));END IF;
  IF c->>'schema'='conversation.workout-source.v2' AND nullif(btrim(c#>>'{media,context_text}'),'') IS NOT NULL THEN units:=units||jsonb_build_array(jsonb_build_object('unit','media_context','text',c#>>'{media,context_text}'));END IF;$new$;
 IF (length(body)-length(replace(body,old,'')))/length(old)<>1 THEN RAISE EXCEPTION 'intake_media_source_hook:%',old;END IF;body:=replace(body,old,new);
 EXECUTE body;
END $source_patch$;

DO $source_patch$
DECLARE body text:=pg_get_functiondef('private.conversation_semantic_text(jsonb,text)'::regprocedure);old text;new text;
BEGIN
 old:=$old$WHEN 'media_transcript' THEN c#>>'{source_evidence,transcript}'$old$;new:=$new$WHEN 'media_context' THEN c#>>'{source_evidence,context_text}' WHEN 'media_transcript' THEN c#>>'{source_evidence,transcript}'$new$;
 IF (length(body)-length(replace(body,old,'')))/length(old)<>1 THEN RAISE EXCEPTION 'intake_media_source_hook:%',old;END IF;body:=replace(body,old,new);
 EXECUTE body;
END $source_patch$;

DO $source_patch$
DECLARE body text:=pg_get_functiondef('private.assert_conversation_semantic_result(jsonb,private.conversation_meal_semantic_attempts,jsonb)'::regprocedure);old text;new text;
BEGIN
 old:=$old$source_unit NOT IN('command_text','media_caption','media_transcript')$old$;new:=$new$source_unit NOT IN('command_text','media_caption','media_context','media_transcript')$new$;
 IF (length(body)-length(replace(body,old,'')))/length(old)<>1 THEN RAISE EXCEPTION 'intake_media_source_hook:%',old;END IF;body:=replace(body,old,new);
 EXECUTE body;
END $source_patch$;

DO $source_patch$
DECLARE body text:=pg_get_functiondef('private.conversation_continuation_original_current_at(uuid,jsonb,timestamptz)'::regprocedure);old text;new text;
BEGIN
 old:=$old$ IF raw#>>'{source,channel}' IS DISTINCT FROM 'media' THEN RETURN false;END IF;$old$;new:=$new$ IF raw#>>'{source,channel}' IS DISTINCT FROM 'media' THEN RETURN false;END IF;
 IF raw ? 'intake_origin' THEN PERFORM private.conversation_intake_media_projection(p_user,raw,true,true);END IF;$new$;
 IF (length(body)-length(replace(body,old,'')))/length(old)<>1 THEN RAISE EXCEPTION 'intake_media_source_hook:%',old;END IF;body:=replace(body,old,new);
 old:=$old$caption:=coalesce(raw#>>'{source,caption}',m.context_text);$old$;new:=$new$caption:=CASE WHEN raw ? 'intake_origin' THEN raw#>>'{source,caption}' ELSE coalesce(raw#>>'{source,caption}',m.context_text) END;$new$;
 IF (length(body)-length(replace(body,old,'')))/length(old)<>1 THEN RAISE EXCEPTION 'intake_media_source_hook:%',old;END IF;body:=replace(body,old,new);
 old:=$old$ IF m.kind='audio_note' THEN$old$;new:=$new$ IF raw ? 'intake_origin' AND nullif(btrim(m.context_text),'') IS NOT NULL THEN units:=units||jsonb_build_array('media_context');END IF;
 IF m.kind='audio_note' THEN$new$;
 IF (length(body)-length(replace(body,old,'')))/length(old)<>1 THEN RAISE EXCEPTION 'intake_media_source_hook:%',old;END IF;body:=replace(body,old,new);
 old:=$old$ evidence:=jsonb_build_object('caption',caption,'transcript',transcript);$old$;new:=$new$ evidence:=jsonb_build_object('caption',caption,'transcript',transcript);
 IF raw ? 'intake_origin' THEN media:=media||jsonb_build_object('owner_id',m.user_id);evidence:=evidence||jsonb_build_object('context_text',m.context_text);END IF;$new$;
 IF (length(body)-length(replace(body,old,'')))/length(old)<>1 THEN RAISE EXCEPTION 'intake_media_source_hook:%',old;END IF;body:=replace(body,old,new);
 EXECUTE body;
END $source_patch$;

REVOKE ALL ON FUNCTION private.conversation_intake_media_projection(uuid,jsonb,boolean,boolean),private.admit_conversation_intake_media_child(uuid,uuid,jsonb),private.replay_conversation_intake_media_child(uuid,uuid,jsonb,text) FROM PUBLIC,anon,authenticated,service_role;
COMMIT;
