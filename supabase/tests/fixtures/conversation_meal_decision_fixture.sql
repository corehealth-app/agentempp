\ir conversation_meal_semantic_fixture.sql
CREATE FUNCTION pg_temp.decision_payload(reason text DEFAULT 'meal_type_required',indexes jsonb DEFAULT '[]') RETURNS jsonb LANGUAGE sql AS $$
 SELECT jsonb_build_object('schema','conversation.meal-decision.v1','status','not_recorded','reason',reason,'food_indexes',indexes);
$$;
CREATE FUNCTION pg_temp.decision_seed(u uuid,a uuid,c uuid,new_owner boolean DEFAULT true) RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE source jsonb;claim jsonb;terminal jsonb;
BEGIN
 IF new_owner THEN
  IF EXISTS(SELECT 1 FROM public.users WHERE id=u) OR EXISTS(SELECT 1 FROM auth.users WHERE id=a) THEN RAISE EXCEPTION 'decision_fixture_collision';END IF;
  INSERT INTO auth.users(id) VALUES(a);
  INSERT INTO public.users(id,auth_user_id,email,status,timezone,country,country_confirmed)
   VALUES(u,a,'decision-'||u::text||'@example.invalid','active','UTC','BR',true);
 END IF;
 -- No explicit meal type: the real registration service may refuse after a
 -- positive interpretation instead of inventing meal-window evidence.
 PERFORM public.admit_conversation_meal_command(u,pg_temp.writer_input(c)-'meal_type');
 source:=public.capture_conversation_meal_source(u,c);
 claim:=public.start_conversation_meal_semantic_attempt(u,c,'conversation.meal-interpreter.v1',source->>'source_hash');
 terminal:=public.commit_conversation_meal_semantic_result(u,c,'conversation.meal-interpreter.v1',(claim->>'attempt_id')::uuid,pg_temp.semantic_result(claim));
 IF terminal->>'status'<>'completed' THEN RAISE EXCEPTION 'decision_fixture_semantics_not_completed';END IF;
 RETURN jsonb_build_object('source',source,'terminal',terminal);
END $$;
CREATE FUNCTION pg_temp.decision_seal(u uuid,c uuid,seed jsonb,payload jsonb DEFAULT NULL) RETURNS jsonb LANGUAGE sql AS $$
 SELECT public.seal_conversation_meal_decision(u,c,(seed#>>'{terminal,epoch}')::uuid,seed#>>'{terminal,input_hash}',seed#>>'{terminal,source_hash}',
  (seed#>>'{terminal,attempt_id}')::uuid,seed#>>'{terminal,result_hash}',coalesce(payload,pg_temp.decision_payload()));
$$;
