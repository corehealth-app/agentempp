-- Synthetic, actual RPCs, caller-owned rollback. No model/provider/network.
BEGIN;
SET LOCAL request.jwt.claims='{"role":"service_role"}';SET LOCAL timezone='UTC';SET LOCAL datestyle='ISO,YMD';
DO $$ BEGIN IF to_regprocedure('public.read_conversation_journal_page_v3(uuid,uuid,integer,jsonb)') IS NULL THEN RAISE EXCEPTION 'JOURNAL_V3_RED:missing_reader';END IF;END $$;
\ir fixtures/conversation_meal_thread_page_v2_fixture.sql
CREATE TEMP TABLE journal_v3_golden(label text PRIMARY KEY,page jsonb,reconciles jsonb DEFAULT '[]') ON COMMIT DROP;
CREATE FUNCTION pg_temp.journal_ok(v boolean,label text) RETURNS void LANGUAGE plpgsql AS $$ BEGIN IF v IS DISTINCT FROM true THEN RAISE EXCEPTION 'JOURNAL_V3_FAIL:%',label;END IF;RAISE NOTICE 'JOURNAL_V3_PASS:%',label;END $$;
CREATE FUNCTION pg_temp.journal_without_clock(v jsonb) RETURNS jsonb LANGUAGE sql AS $$ SELECT jsonb_set(v-'observed_at','{meal_page}',(v->'meal_page')-'observed_at'); $$;
CREATE FUNCTION pg_temp.journal_intake(u uuid,i uuid,kind text DEFAULT NULL) RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE v_epoch uuid;a jsonb;s jsonb;c jsonb;raw jsonb;d jsonb;
BEGIN
 SELECT e.epoch INTO STRICT v_epoch FROM private.workout_strength_authority_epochs e WHERE user_id=u;
 raw:=jsonb_build_object('intake_protocol','conversation.intake.v1','intake_id',i,'source',jsonb_build_object('channel','text','text',CASE WHEN kind='meal.report' THEN 'Comi arroz.' ELSE 'Fiz 30 minutos de caminhada.' END));
 a:=public.admit_conversation_intake(u,v_epoch,raw);
 IF a->>'action'<>'admitted' THEN RAISE EXCEPTION 'journal_intake_admit';END IF;
 IF kind IS NOT NULL THEN
  s:=public.capture_conversation_intake_source(u,i,a#>>'{intake,input_hash}',v_epoch);c:=public.claim_conversation_intake_routing(u,i,a#>>'{intake,input_hash}',v_epoch,s->>'source_hash');
  d:=jsonb_build_object('schema','conversation.intake-routing.v1','kind',kind,'reason',CASE WHEN kind='meal.report' THEN 'performed_meal' ELSE 'performed_activity' END);
  c:=public.seal_conversation_intake_routing(u,i,a#>>'{intake,input_hash}',v_epoch,s->>'source_hash',(c->>'claim_id')::uuid,d);
  IF c->>'action'<>'sealed' THEN RAISE EXCEPTION 'journal_intake_seal:%',c->>'action';END IF;
 END IF;RETURN c;
END $$;
DO $mixed$
DECLARE u uuid:='c1450000-0000-4000-8000-000000000001';a uuid:='c1450000-0000-4000-8000-000000000002';p uuid:='c1450000-0000-4000-8000-000000000003';
 i1 uuid:='c1450000-0000-4000-8000-000000000004';i2 uuid:='c1450000-0000-4000-8000-000000000005';i3 uuid:='c1450000-0000-4000-8000-000000000006';i4 uuid:='c1450000-0000-4000-8000-000000000007';
 w uuid:='c1450000-0000-4000-8000-000000000008';r uuid:='c1450000-0000-4000-8000-000000000009';op uuid:='c1450000-0000-4000-8000-000000000010';
 seed jsonb;v_epoch uuid;x jsonb;y jsonb;page jsonb;all_page jsonb;cursor jsonb;body jsonb;ad jsonb;ready jsonb;state jsonb;old1 jsonb;old2 jsonb;before_state jsonb;ids text[]:='{}';expected text[];calls integer:=0;child uuid;
BEGIN
 seed:=pg_temp.continuation_seed(u,a,p,false);v_epoch:=(seed#>>'{terminal,epoch}')::uuid;
 state:=pg_temp.continuation_read(u,p,seed);body:=pg_temp.continuation_body(state,'{"kind":"meal_type","meal_type":"almoco"}');
 ad:=pg_temp.continuation_admit(u,p,seed,r,body);state:=pg_temp.continuation_read(u,p,seed,r,ad#>>'{child_binding,input_hash}');
 ready:=pg_temp.continuation_prepare(u,p,seed,r,ad#>>'{child_binding,input_hash}',pg_temp.continuation_preparation(state));
 PERFORM pg_temp.continuation_commit(u,p,seed,r,ad#>>'{child_binding,input_hash}',ready#>>'{stored,prepared_hash}');
 PERFORM pg_temp.thread_v2_save(u,r,op);
 PERFORM pg_temp.journal_intake(u,i1);x:=pg_temp.journal_intake(u,i2,'workout.report');y:=pg_temp.journal_intake(u,i3,'meal.report');
 child:=(y#>>'{selection,command,command_id}')::uuid;
 -- Capturing is a separate actual POST operation; GET never performs this.
 PERFORM public.capture_conversation_meal_source(u,child);
 PERFORM pg_temp.journal_intake(u,i4,'workout.report');
 x:=public.admit_conversation_workout_command(u,v_epoch,jsonb_build_object('command_protocol','conversation.command.v1','command_id',w,'kind','workout.report','source',jsonb_build_object('channel','text','text','Fiz 30 minutos de caminhada.')));
 PERFORM pg_temp.journal_ok(x->>'action'='admitted','standalone workout genuinely admitted');
 old1:=public.read_conversation_meal_journal_page(u,v_epoch,25)-'observed_at';old2:=public.read_conversation_meal_journal_page_v2(u,v_epoch,25)-'observed_at';before_state:=pg_temp.semantic_owner_state(u);
 page:=public.read_conversation_journal_page_v3(u,v_epoch,25);all_page:=page;
 PERFORM pg_temp.journal_ok(page->>'action'='available' AND jsonb_array_length(page->'items')=10,'mixed originals plus real five meal variants');
 PERFORM pg_temp.journal_ok((SELECT count(*)=4 FROM jsonb_array_elements(page->'items') e WHERE e->>'kind'='intake') AND (SELECT count(*)=1 FROM jsonb_array_elements(page->'items') e WHERE e->>'kind'='workout'),'reserved typed children never duplicate neutral originals');
 PERFORM pg_temp.journal_ok((SELECT count(*)=1 FROM jsonb_array_elements(page#>'{meal_page,items}') e WHERE e->>'event_id'='command/'||child::text) AND NOT EXISTS(SELECT 1 FROM jsonb_array_elements(page->'items') e WHERE e->>'event_id'='command/'||child::text),'real neutral meal report remains private projection dependency only');
 PERFORM pg_temp.journal_ok((SELECT count(*)=3 FROM jsonb_array_elements(page->'workouts')),'equal legitimate activities preserve distinct actual identities');
 INSERT INTO journal_v3_golden(label,page,reconciles) SELECT 'mixed',page,(SELECT coalesce(jsonb_agg(jsonb_build_object('binding',jw.value->'binding','response',public.reconcile_conversation_workout((jw.value#>>'{binding,owner_id}')::uuid,(jw.value#>>'{binding,command_id}')::uuid,jw.value#>>'{binding,input_hash}',(jw.value#>>'{binding,epoch}')::uuid)) ORDER BY jw.value#>>'{binding,command_id}'),'[]') FROM jsonb_array_elements(page->'workouts') AS jw(value));
 LOOP
  page:=public.read_conversation_journal_page_v3(u,v_epoch,1,cursor);calls:=calls+1;IF calls>11 THEN RAISE EXCEPTION 'journal_paging_loop';END IF;
  PERFORM pg_temp.journal_ok(page->>'action'='available' AND jsonb_array_length(page->'items')=1,'bounded page with its own immutable dependencies '||calls);
  ids:=array_append(ids,page#>>'{items,0,event_id}');EXIT WHEN page->'has_more'='false';cursor:=page->'next_cursor';
 END LOOP;
 SELECT array_agg(e->>'event_id' ORDER BY ord) INTO expected FROM jsonb_array_elements(all_page->'items') WITH ORDINALITY e(e,ord);
 PERFORM pg_temp.journal_ok(ids=expected AND cardinality(ids)=10,'keyset stream has no gaps duplicates or lost descendants');
 PERFORM pg_temp.journal_ok(public.read_conversation_meal_journal_page(u,v_epoch,25)-'observed_at'=old1 AND public.read_conversation_meal_journal_page_v2(u,v_epoch,25)-'observed_at'=old2,'legacy v1 v2 bytes unchanged except actual observation clock');
 PERFORM pg_temp.journal_ok(pg_temp.semantic_owner_state(u)=before_state,'all journal reads preserve actual domain source receipt reward and feedback rows');
 PERFORM pg_temp.journal_ok(public.read_conversation_journal_page_v3(u,gen_random_uuid())='{"action":"stale_epoch"}' AND public.read_conversation_journal_page_v3(gen_random_uuid(),v_epoch)='{"action":"absent"}','owner epoch isolation');
 PERFORM pg_temp.journal_ok(public.read_conversation_journal_page_v3(u,v_epoch,10,'{"at":"2026-01-01T00:00:00.000000Z","id":"intake/c1450000-0000-4000-8000-000000000004"}')='{"action":"cursor_conflict"}','cursor must name actual original event and clock');
 UPDATE public.users SET timezone='America/Sao_Paulo' WHERE id=u;
 UPDATE public.user_profiles SET weight_kg=81,updated_at=clock_timestamp() WHERE user_id=u;
 INSERT INTO public.reevaluations(user_id,evaluation_date) VALUES(u,current_date);
 PERFORM pg_temp.journal_ok((SELECT e.epoch=v_epoch FROM private.workout_strength_authority_epochs e WHERE user_id=u) AND pg_temp.journal_without_clock(public.read_conversation_journal_page_v3(u,v_epoch,25))=pg_temp.journal_without_clock(all_page),'actual profile and reevaluation row updates preserve epoch and history');
 PERFORM public.reset_user_conversation_atomic(u,true);
 PERFORM pg_temp.journal_ok(public.read_conversation_journal_page_v3(u,v_epoch,1,cursor)='{"action":"stale_epoch"}' AND (SELECT count(*)=4 AND bool_and(invalidated_at IS NOT NULL) FROM private.conversation_intake_ids WHERE user_id=u),'explicit reset closes old cursor and preserves provenance tombstones');
 PERFORM pg_temp.journal_ok(NOT EXISTS(SELECT 1 FROM private.conversation_intake_inputs WHERE user_id=u) AND NOT EXISTS(SELECT 1 FROM private.conversation_workout_inputs WHERE user_id=u),'deleted original bodies are never reconstructed');
END $mixed$;
CREATE FUNCTION pg_temp.journal_media_seed(k text,caption text,context text,processed jsonb) RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE u uuid:=gen_random_uuid();e uuid:=gen_random_uuid();i uuid:=gen_random_uuid();m uuid:=gen_random_uuid();a jsonb;s jsonb;c jsonb;raw jsonb;
BEGIN
 INSERT INTO public.users(id,email,status,timezone,country,country_confirmed) VALUES(u,'t44-'||u||'@example.invalid','active','UTC','BR',true);
 INSERT INTO private.workout_strength_authority_epochs(user_id,epoch,changed_at) VALUES(u,e,clock_timestamp());
 INSERT INTO public.media_assets(id,user_id,kind,bucket_id,object_path,mime_type,declared_size_bytes,actual_size_bytes,status,source_request_hash,processing_request_id,retention_until,uploaded_at,processed_at,context_text,processing_result)
 VALUES(m,u,k,CASE WHEN k='audio_note' THEN 'audio-notes' WHEN k='gym_photo' THEN 'gym-photos' ELSE 'meal-photos' END,u||'/'||m||'.bin',CASE WHEN k='audio_note' THEN 'audio/mpeg' ELSE 'image/jpeg' END,1200,1200,'processed',repeat('a',64),repeat('b',64),clock_timestamp()+interval '1 day',clock_timestamp(),clock_timestamp(),context,processed);
 raw:=jsonb_build_object('intake_protocol','conversation.intake.v1','intake_id',i,'source',jsonb_strip_nulls(jsonb_build_object('channel','media','media_asset_id',m,'user_action','report_actual_record','caption',caption)));
 a:=public.admit_conversation_intake(u,e,raw);s:=public.capture_conversation_intake_source(u,i,a#>>'{intake,input_hash}',e);c:=public.claim_conversation_intake_routing(u,i,a#>>'{intake,input_hash}',e,s->>'source_hash');
 RETURN jsonb_build_object('intake',a->'intake','source',s,'claim',c,'raw',raw);
END $$;
CREATE FUNCTION pg_temp.journal_media_seal(s jsonb,k text) RETURNS jsonb LANGUAGE sql AS $$
 SELECT public.seal_conversation_intake_routing((s#>>'{intake,owner_id}')::uuid,(s#>>'{intake,intake_id}')::uuid,s#>>'{intake,input_hash}',(s#>>'{intake,epoch}')::uuid,s#>>'{source,source_hash}',(s#>>'{claim,claim_id}')::uuid,jsonb_build_object('schema','conversation.intake-routing.v1','kind',k,'reason','processed_media_report'));
$$;
DO $media$
DECLARE seed jsonb;x jsonb;r jsonb;prepared jsonb;fx jsonb;page jsonb;old_page jsonb;u uuid;v_epoch uuid;child uuid;kind text;
BEGIN
 FOREACH kind IN ARRAY ARRAY['meal_photo','audio_note'] LOOP
  seed:=pg_temp.journal_media_seed(kind,CASE WHEN kind='meal_photo' THEN 'Comi arroz' ELSE NULL END,CASE WHEN kind='meal_photo' THEN 'Contexto separado' ELSE 'Fiz 30 minutos de caminhada leve' END,CASE WHEN kind='meal_photo' THEN '{"items":[{"name":"arroz","quantity_g":100}]}'::jsonb ELSE '{"text":"Fiz 30 minutos de caminhada leve"}'::jsonb END);
  x:=pg_temp.journal_media_seal(seed,CASE WHEN kind='meal_photo' THEN 'meal.report' ELSE 'workout.report' END);
  u:=(seed#>>'{intake,owner_id}')::uuid;v_epoch:=(seed#>>'{intake,epoch}')::uuid;child:=(x#>>'{selection,command,command_id}')::uuid;
  IF kind='meal_photo' THEN
   r:=public.capture_conversation_meal_source(u,child);prepared:=public.prepare_conversation_meal(u,child,pg_temp.writer_resolved(r));fx:=public.commit_conversation_meal(u,child,prepared->>'resolved_hash');
  ELSE
   r:=public.capture_conversation_workout_source(u,child,x#>>'{selection,command,input_hash}',v_epoch);
   prepared:=public.prepare_conversation_workout(u,child,x#>>'{selection,command,input_hash}',r->>'source_hash',v_epoch,private.conversation_workout_report(r->'context',r->>'source_hash'));
   fx:=public.commit_conversation_workout(u,child,x#>>'{selection,command,input_hash}',r->>'source_hash',v_epoch,prepared->>'prepared_hash',prepared->'prepared');
  END IF;
  PERFORM pg_temp.journal_ok(fx->>'action'='committed','actual media effect exists before GET '||kind);
  page:=public.read_conversation_journal_page_v3(u,v_epoch);
  PERFORM pg_temp.journal_ok(page->>'action'='available' AND jsonb_array_length(page->'items')=1 AND page#>>'{intakes,0,selection,schema}'='conversation.intake-selection.v2','genuine internal media selection projects historical original '||kind);
  INSERT INTO journal_v3_golden(label,page) VALUES(kind,page);
  UPDATE public.media_assets SET context_text='Later changed context',processing_result=processing_result||'{"later":true}' WHERE id=(seed#>>'{raw,source,media_asset_id}')::uuid;
  PERFORM pg_temp.journal_ok(pg_temp.journal_without_clock(public.read_conversation_journal_page_v3(u,v_epoch))=pg_temp.journal_without_clock(page),'historical immutable source never adopts current asset or requires fresh media authority '||kind);
 END LOOP;
END $media$;
-- Same existing qualified FULL clinical fixture and actual conclusion writer.
\ir fixtures/mobile_clinical_full_fixture.sql
CREATE FUNCTION m3b_cycle_test.clinical_request(c jsonb,weight numeric DEFAULT 84,clear_hold boolean DEFAULT false)
RETURNS jsonb LANGUAGE plpgsql SET search_path=pg_catalog AS $$
DECLARE context jsonb;candidate jsonb;form jsonb;intent jsonb;proposal jsonb;preview jsonb;
BEGIN
 context:=private.capture_mobile_clinical_context_at((c->>'user')::uuid,'REGULAR',(c->>'cycle')::uuid,NULL);
 candidate:=context#>'{facts,protocol_authority,body_fat_candidate}';
 form:=jsonb_build_object('version',1,'phase','recomposicao','kind','REGULAR','activityPurpose','normal','preference',NULL,
  'answers',jsonb_build_object('weightKg',weight,'strengthSessions',4,'hunger','moderada','energy','boa',
   'adherence','bem_consistente','strengthProgression',NULL,'fatPerception',NULL,'difficultToMaintain',NULL,
   'activity',NULL,'healthCheck',jsonb_build_object('kind','none'),'professionalConversationConfirmed',CASE WHEN clear_hold THEN true ELSE NULL END));
 intent:=jsonb_build_object('principalConfirmed',false,'bodyFat',jsonb_build_object('confirmed',true,
  'sourceHash',candidate->'source_hash','meanHundredths',candidate->'mean_hundredths'));
 proposal:=jsonb_build_object('version',1,'principal','keep','clearHold',clear_hold,
  'profile',jsonb_build_object('current_protocol','recomposicao','deficit_level',500,'activity_level','moderado','training_frequency',4,'hunger_level','moderada'),
  'targets',jsonb_build_object('beforeKcal',context#>'{facts,day,calories_target}',
   'beforeProtein',context#>'{facts,day,protein_target}','afterKcal',1599,'afterProtein',126,'formulaAfterKcal',1599),
  'episode',jsonb_build_object('difficultyCount',0,'ledgerSteps',NULL,'schedule',NULL,'maintenanceSince',NULL));
 preview:=private.prepare_mobile_clinical_preview_at((c->>'user')::uuid,'REGULAR',(c->>'cycle')::uuid,
  gen_random_uuid(),context->>'context_hash',form,intent,proposal,NULL);
 RETURN jsonb_build_object('preview',preview,'form',form,'intent',intent,'proposal',proposal,'context',context);
END $$;
DO $reevaluation$
DECLARE c jsonb;u uuid;v_epoch uuid;raw jsonb;request jsonb;result jsonb;page jsonb;after_page jsonb;day date;
BEGIN
 c:=m3b_cycle_test.clinical_photos(45145);u:=(c->>'user')::uuid;day:=(clock_timestamp() AT TIME ZONE 'America/Sao_Paulo')::date;
 INSERT INTO public.daily_snapshots(user_id,date,calories_target,protein_target,current_protocol,calories_consumed,exercise_calories,day_closed)
 VALUES(u,day,1700,120,'recomposicao',200,50,false);
 -- Real legacy admission initializes an absent authority epoch. Journal never does.
 PERFORM public.admit_conversation_meal_command(u,jsonb_build_object('command_protocol','conversation.command.v1','command_id',gen_random_uuid(),'kind','meal.report','source',jsonb_build_object('channel','text','text','Comi arroz')));
 SELECT e.epoch INTO STRICT v_epoch FROM private.workout_strength_authority_epochs e WHERE user_id=u;
 PERFORM pg_temp.journal_intake(u,gen_random_uuid());page:=public.read_conversation_journal_page_v3(u,v_epoch,25);
 request:=m3b_cycle_test.clinical_request(c);
 result:=private.confirm_mobile_clinical_preview_at(u,(request#>>'{preview,preview_id}')::uuid,gen_random_uuid(),request->'form',request->'intent',request->'proposal',NULL);
 after_page:=public.read_conversation_journal_page_v3(u,v_epoch,25);
 PERFORM pg_temp.journal_ok(result->>'status'='confirmed' AND (SELECT e.epoch=v_epoch FROM private.workout_strength_authority_epochs e WHERE user_id=u),'actual fortnightly FULL conclusion preserves original conversation epoch');
 PERFORM pg_temp.journal_ok(page->>'action'='available' AND pg_temp.journal_without_clock(page)=pg_temp.journal_without_clock(after_page),'actual FULL profile target and cycle changes preserve retained history visibility');
END $reevaluation$;
DO $closed$
DECLARE u uuid:='c1450000-0000-4000-8000-000000000021';v_epoch uuid:='c1450000-0000-4000-8000-000000000022';i uuid:='c1450000-0000-4000-8000-000000000023';child uuid;page jsonb;denied boolean;v integer;
BEGIN
 INSERT INTO public.users(id,email,status,timezone,country,country_confirmed) VALUES(u,'journal-closed@example.invalid','active','UTC','BR',true);
 PERFORM pg_temp.journal_ok(public.read_conversation_journal_page_v3(u,v_epoch)='{"action":"stale_epoch"}' AND NOT EXISTS(SELECT 1 FROM private.workout_strength_authority_epochs e WHERE e.user_id=u),'GET never creates an absent epoch');
 INSERT INTO private.workout_strength_authority_epochs(user_id,epoch,changed_at) VALUES(u,v_epoch,clock_timestamp());
 FOREACH v IN ARRAY ARRAY[0,26,NULL::integer] LOOP
  denied:=false;BEGIN PERFORM public.read_conversation_journal_page_v3(u,v_epoch,v);EXCEPTION WHEN invalid_parameter_value THEN denied:=true;END;
  PERFORM pg_temp.journal_ok(denied,'strict SQL limit '||coalesce(v::text,'NULL'));
 END LOOP;
 PERFORM pg_temp.journal_ok(public.read_conversation_journal_page_v3(u,v_epoch,10,'null')='{"action":"cursor_conflict"}' AND public.read_conversation_journal_page_v3(u,v_epoch,10,'{"at":"infinity","id":"bad"}')='{"action":"cursor_conflict"}','JSON null and nonfinite cursors are closed refusals');
 -- Qualified historical direct fixture forces a genuine equal-clock tie; no
 -- admission clock is rewritten and no domain effect/proof is fabricated.
 PERFORM pg_temp.thread_v2_pending_at(u,'c1450000-0000-4000-8000-000000000025','2026-11-01T12:00:00Z');
 PERFORM pg_temp.thread_v2_pending_at(u,'c1450000-0000-4000-8000-000000000026','2026-11-01T12:00:00Z');
 page:=public.read_conversation_journal_page_v3(u,v_epoch,1);
 PERFORM pg_temp.journal_ok(page#>>'{items,0,event_id}'='command/c1450000-0000-4000-8000-000000000026' AND public.read_conversation_journal_page_v3(u,v_epoch,1,page->'next_cursor')#>>'{items,0,event_id}'='command/c1450000-0000-4000-8000-000000000025','C-order UUID tie breaker has no missing or duplicated event');
 PERFORM pg_temp.journal_intake(u,i);
 SELECT reserved_child_id INTO STRICT child FROM private.conversation_intake_ids WHERE user_id=u AND intake_id=i;
 PERFORM public.admit_conversation_workout_command(u,v_epoch,jsonb_build_object('command_protocol','conversation.command.v1','command_id',child,'kind','workout.report','source',jsonb_build_object('channel','text','text','Fiz 30 minutos de caminhada.')));
 PERFORM pg_temp.journal_ok(public.read_conversation_journal_page_v3(u,v_epoch)='{"action":"event_conflict"}','a reserved orphan cannot masquerade as an independent original or vanish silently');
 UPDATE public.users SET status='blocked' WHERE id=u;
 PERFORM pg_temp.journal_ok(public.read_conversation_journal_page_v3(u,v_epoch)='{"action":"absent"}','inactive owner cannot disclose history');
 PERFORM set_config('request.jwt.claims','{"role":"authenticated"}',true);denied:=false;
 BEGIN PERFORM public.read_conversation_journal_page_v3(u,v_epoch);EXCEPTION WHEN insufficient_privilege THEN denied:=true;END;
 PERFORM set_config('request.jwt.claims','{"role":"service_role"}',true);
 PERFORM pg_temp.journal_ok(denied,'actual backend role guard precedes even absent owner reads');
END $closed$;
DO $roles$ BEGIN
 PERFORM pg_temp.journal_ok((SELECT provolatile='s' AND prosecdef FROM pg_proc WHERE oid='public.read_conversation_journal_page_v3(uuid,uuid,integer,jsonb)'::regprocedure),'reader is STABLE security definer');
 PERFORM pg_temp.journal_ok(has_function_privilege('service_role','public.read_conversation_journal_page_v3(uuid,uuid,integer,jsonb)','EXECUTE') AND NOT has_function_privilege('anon','public.read_conversation_journal_page_v3(uuid,uuid,integer,jsonb)','EXECUTE') AND NOT has_function_privilege('authenticated','public.read_conversation_journal_page_v3(uuid,uuid,integer,jsonb)','EXECUTE'),'service-only ACL');
END $roles$;
UPDATE journal_v3_golden g SET reconciles=(SELECT coalesce(jsonb_agg(jsonb_build_object('binding',jw.value->'binding','response',public.reconcile_conversation_workout((jw.value#>>'{binding,owner_id}')::uuid,(jw.value#>>'{binding,command_id}')::uuid,jw.value#>>'{binding,input_hash}',(jw.value#>>'{binding,epoch}')::uuid)) ORDER BY jw.value#>>'{binding,command_id}'),'[]') FROM jsonb_array_elements(g.page->'workouts') AS jw(value)) WHERE g.label<>'mixed';
SET CONSTRAINTS ALL IMMEDIATE;
SELECT jsonb_build_object('journal_v3_actual_golden',jsonb_agg(jsonb_build_object('label',label,'page',page,'reconciles',reconciles) ORDER BY label)) FROM journal_v3_golden;
ROLLBACK;
