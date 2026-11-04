-- Transaction-owned synthetic fixtures. Real existing SQL writers only.
\ir conversation_meal_continuation_fixture.sql
CREATE FUNCTION pg_temp.thread_v2_register(u uuid,c uuid) RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE s jsonb;r jsonb;fx jsonb;
BEGIN
 s:=pg_temp.writer_seed(u,c);r:=public.prepare_conversation_meal(u,c,pg_temp.writer_resolved(s));
 fx:=public.commit_conversation_meal(u,c,r->>'resolved_hash');
 IF fx->>'action'<>'committed' THEN RAISE EXCEPTION 'thread_fixture_register_failed';END IF;
 RETURN fx->'receipt';
END $$;
CREATE FUNCTION pg_temp.thread_v2_save(u uuid,c uuid,op uuid) RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE s jsonb:=public.read_conversation_meal_edit_state(u,c);body jsonb;result jsonb;
BEGIN
 body:=jsonb_build_object('schema','conversation.meal-edit.v1','kind','save','expected_revision',0,'expected_version','v1:'||repeat('a',64),
  'record_id',s#>'{current_state,items,0,id}','items','[{"food_name":"arroz sintetico","quantity_g":200}]'::jsonb);
 result:=public.commit_conversation_meal_item_edit(u,c,op,body,s->'current_state',
  '[{"food_name":"arroz sintetico","quantity_g":200,"kcal":260.1,"protein_g":4.62,"carbs_g":56.42,"fat_g":0.42,"source":"user_kcal","food_db_id":null,"confidence":null}]',
  'quantity_only','{"quantity_g":200}','synthetic-thread-v2-edit');
 IF result->>'action'<>'committed' THEN RAISE EXCEPTION 'thread_fixture_edit_failed';END IF;
 RETURN result->'receipt';
END $$;
CREATE FUNCTION pg_temp.thread_v2_pending_at(u uuid,c uuid,stamp timestamptz) RETURNS void LANGUAGE plpgsql AS $$
DECLARE raw jsonb:=pg_temp.writer_input(c);epoch uuid;
BEGIN
 SELECT e.epoch INTO STRICT epoch FROM private.workout_strength_authority_epochs e WHERE user_id=u;
 IF EXISTS(SELECT 1 FROM private.conversation_meal_command_ids WHERE user_id=u AND command_id=c) THEN RAISE EXCEPTION 'thread_fixture_command_collision';END IF;
 INSERT INTO private.conversation_meal_command_ids(user_id,command_id,input_hash,command_protocol,kind,epoch,admitted_at)
 VALUES(u,c,encode(sha256(convert_to(private.conversation_command_canonical(raw),'UTF8')),'hex'),'conversation.command.v1','meal.report',epoch,stamp);
 INSERT INTO private.conversation_meal_command_sources VALUES(u,c,raw);
END $$;
CREATE FUNCTION pg_temp.thread_v2_legacy_feedback(u uuid,c uuid) RETURNS void LANGUAGE plpgsql AS $$
DECLARE fx private.conversation_meal_effects%ROWTYPE;rd jsonb;cursor jsonb;steps jsonb;stage text;reg uuid;f jsonb;result jsonb;
BEGIN
 SELECT * INTO STRICT fx FROM private.conversation_meal_effects WHERE user_id=u AND command_id=c;reg:=(fx.receipt->>'registration_id')::uuid;
 rd:=public.read_flow_shared_phrase_cursor(u);
 cursor:=coalesce(nullif(rd->'cursor','null'),jsonb_build_object('schema','flow.phrase-state.v1','userId',u::text,
  'catalogVersion','flow-curated.v1:a26c9848f04e1c7c8e0e93ffb6a50903b10110ed627b9dedd49362135fba5feb','ordinal',0,'lastTextKey',NULL,'usedTextKeys','[]'::jsonb));
 steps:='[]';FOREACH stage IN ARRAY ARRAY['food','incentive'] LOOP
  steps:=steps||jsonb_build_array(jsonb_build_object('receipt',jsonb_build_object('eventKey','mobile_registration/'||u::text||'/'||reg::text||'/'||stage,
   'requestFingerprint',repeat('a',64),'selection',jsonb_build_object('phrase',NULL,'phraseId',NULL,'sourceText',NULL,'foodCanonicalName',NULL,'reason','unsupported_language')),'nextCursor',cursor));
 END LOOP;
 f:=jsonb_build_object('schema','registration.feedback.v1','registration_id',reg,'kind','meal','locale','en',
  'meal_totals',jsonb_build_object('kcal',130,'protein_g',2.3,'carbs_g',28.2,'fat_g',0.2),'day',NULL,
  'lines',jsonb_build_array(jsonb_build_object('key','meal_totals','text','130 kcal | synthetic original totals'),jsonb_build_object('key','day_unavailable','text','Synthetic day unavailable.')),
  'food_comment',NULL,'incentive',NULL);
 result:=public.commit_mobile_registration_feedback(u,reg,fx.original_facts#>'{confirmed,proposal}',rd->>'cursor_revision',rd->'cursor',steps,f);
 IF NOT EXISTS(SELECT 1 FROM private.mobile_registration_feedback WHERE user_id=u AND registration_id=reg) THEN RAISE EXCEPTION 'thread_fixture_feedback_failed';END IF;
END $$;
CREATE FUNCTION pg_temp.thread_v2_without_clock(page jsonb) RETURNS jsonb LANGUAGE sql AS $$ SELECT page-'observed_at';$$;
