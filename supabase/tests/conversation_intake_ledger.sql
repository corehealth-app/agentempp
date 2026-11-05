-- Real PostgreSQL, synthetic owners, and caller-owned rollback only.
BEGIN;
SET LOCAL request.jwt.claims='{"role":"service_role"}';
SET LOCAL timezone='UTC';
SET LOCAL datestyle='ISO,YMD';
CREATE TEMP TABLE intake_actual_golden(label text PRIMARY KEY,admission jsonb,source jsonb,claim jsonb,seal jsonb,read_result jsonb) ON COMMIT DROP;
CREATE FUNCTION pg_temp.intake_ok(v boolean,label text) RETURNS void LANGUAGE plpgsql AS $$
BEGIN IF v IS DISTINCT FROM true THEN RAISE EXCEPTION 'INTAKE_FAIL:%',label; END IF;
 RAISE NOTICE 'INTAKE_PASS:%',label; END $$;
CREATE FUNCTION pg_temp.intake_input(id uuid,txt text DEFAULT 'Fiz 30 minutos de caminhada.') RETURNS jsonb LANGUAGE sql AS $$
 SELECT jsonb_build_object('intake_protocol','conversation.intake.v1','intake_id',id,'source',jsonb_build_object('channel','text','text',txt));
$$;
DO $admit$
DECLARE u uuid:='c1390000-0000-4000-8000-000000000001';e uuid:='c1390000-0000-4000-8000-000000000002';
 id uuid:='c1390000-0000-4000-8000-000000000003';v jsonb;raw jsonb:=pg_temp.intake_input(id);first_binding jsonb;
BEGIN
 PERFORM pg_temp.intake_ok(NOT EXISTS(SELECT 1 FROM public.users z WHERE z.id=u),'synthetic namespace empty');
 INSERT INTO public.users(id,email,status,timezone,country,country_confirmed) VALUES(u,'intake-real@example.invalid','active','UTC','BR',true);
 INSERT INTO private.workout_strength_authority_epochs(user_id,epoch,changed_at) VALUES(u,e,clock_timestamp());
 v:=public.admit_conversation_intake(u,e,raw);
 PERFORM pg_temp.intake_ok(v->>'action'='admitted' AND v#>>'{intake,owner_id}'=u::text AND v#>>'{intake,intake_id}'=id::text,'neutral admission owns genuine identity');
 first_binding:=v->'intake';
 PERFORM pg_temp.intake_ok(first_binding->>'input_hash'='28985944918c0453d73f7eb0f1afff838dd5322b9338ce3280a5f89d5982eab3','independently computed canonical input SHA256 literal');
 PERFORM pg_temp.intake_ok(public.admit_conversation_intake(u,e,raw)=jsonb_build_object('action','replay','intake',first_binding),'literal replay preserves admission clock and hash');
 PERFORM pg_temp.intake_ok(public.admit_conversation_intake(u,e,pg_temp.intake_input(id,' Fiz 30 minutos de caminhada.'))='{"action":"input_conflict"}','leading whitespace changes literal identity');
 PERFORM pg_temp.intake_ok(NOT EXISTS(SELECT 1 FROM private.conversation_meal_command_ids WHERE user_id=u) AND NOT EXISTS(SELECT 1 FROM private.conversation_workout_command_ids WHERE user_id=u),'neutral admission creates no typed command');
END $admit$;

CREATE FUNCTION pg_temp.intake_seed(u uuid,i uuid,txt text DEFAULT 'Fiz 30 minutos de caminhada.') RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE e uuid;a jsonb;s jsonb;c jsonb;
BEGIN
 SELECT epoch INTO e FROM private.workout_strength_authority_epochs WHERE user_id=u;
 a:=public.admit_conversation_intake(u,e,pg_temp.intake_input(i,txt));
 s:=public.capture_conversation_intake_source(u,i,a#>>'{intake,input_hash}',e);
 c:=public.claim_conversation_intake_routing(u,i,a#>>'{intake,input_hash}',e,s->>'source_hash');
 RETURN jsonb_build_object('admission',a,'intake',a->'intake','source',s,'claim',c,'claim_id',c->'claim_id');
END $$;
CREATE FUNCTION pg_temp.intake_seal(u uuid,s jsonb,kind text DEFAULT 'workout.report') RETURNS jsonb LANGUAGE sql AS $$
 SELECT public.seal_conversation_intake_routing(u,(s#>>'{intake,intake_id}')::uuid,s#>>'{intake,input_hash}',(s#>>'{intake,epoch}')::uuid,s#>>'{source,source_hash}',(s->>'claim_id')::uuid,
 jsonb_build_object('schema','conversation.intake-routing.v1','kind',kind,'reason','performed_activity'));
$$;
DO $routing$
DECLARE u uuid:='c1390000-0000-4000-8000-000000000010';e uuid:=gen_random_uuid();i uuid:=gen_random_uuid();s jsonb;x jsonb;y jsonb;r jsonb;child uuid;h text;t jsonb;
BEGIN
 INSERT INTO public.users(id,email,status,timezone,country,country_confirmed) VALUES(u,'intake-routing@example.invalid','active','UTC','BR',true);
 INSERT INTO private.workout_strength_authority_epochs(user_id,epoch,changed_at) VALUES(u,e,clock_timestamp());
 s:=pg_temp.intake_seed(u,i);h:=s#>>'{intake,input_hash}';
 PERFORM pg_temp.intake_ok(s#>>'{source,action}'='captured' AND s#>>'{source,context,schema}'='conversation.intake-source.v1' AND s#>'{source,context,media}'='null'::jsonb,'capture returns original neutral context');
 PERFORM pg_temp.intake_ok(public.capture_conversation_intake_source(u,i,h,e)=jsonb_set(s->'source','{action}','"replay"'),'capture replay preserves frozen hash and real clock');
 PERFORM pg_temp.intake_ok(public.claim_conversation_intake_routing(u,i,h,e,s#>>'{source,source_hash}')='{"action":"already_claimed"}','one permanent claim exposes no claim retry after unknown outcome');
 PERFORM pg_temp.intake_ok(public.claim_conversation_intake_routing(u,i,h,e,repeat('0',64))='{"action":"source_conflict"}','wrong source cannot claim');
 r:=public.read_conversation_intake(u,i,h,e);
 PERFORM pg_temp.intake_ok(r->>'action'='available' AND r->'source_input'=pg_temp.intake_input(i) AND r->'claimed'='true' AND r->'selection'='null','cold private read preserves actual original input and never seals');
 x:=pg_temp.intake_seal(u,s);child:=(x#>>'{selection,command,command_id}')::uuid;
 PERFORM pg_temp.intake_ok(x->>'action'='sealed' AND child<>i AND x#>>'{selection,command,kind}'='workout.report','selected text uses internally reserved distinct workout child');
 PERFORM pg_temp.intake_ok((x#>>'{selection,command,admitted_at}')::timestamptz>=(s#>>'{intake,admitted_at}')::timestamptz AND (x#>>'{selection,selected_at}')::timestamptz>=(x#>>'{selection,command,admitted_at}')::timestamptz,'three genuine clocks ordered without rewriting admission');
 PERFORM pg_temp.intake_ok(x#>>'{selection,command,input_hash}'<>h AND (SELECT source_input=x#>'{selection,command,input}' FROM private.conversation_workout_inputs WHERE user_id=u AND command_id=child),'actual typed admission input and distinct hash persisted');
 PERFORM pg_temp.intake_ok(pg_temp.intake_seal(u,s)=jsonb_set(x,'{action}','"replay"'),'lost seal success returns literal immutable selection');
 PERFORM pg_temp.intake_ok(pg_temp.intake_seal(u,s,'meal.report')='{"action":"decision_conflict"}','reclassification forbidden');
 PERFORM pg_temp.intake_ok(public.seal_conversation_intake_routing(u,i,h,e,s#>>'{source,source_hash}',gen_random_uuid(),x#>'{selection,decision}')='{"action":"claim_conflict"}','wrong claim cannot replay selection');
 y:=public.capture_conversation_workout_source(u,child,x#>>'{selection,command,input_hash}',e);
 PERFORM pg_temp.intake_ok(y#>>'{context,schema}'='conversation.workout-source.v1' AND y#>>'{context,command_id}'=child::text AND y->>'source_hash'<>s#>>'{source,source_hash}','genuine later workout capture owns independent clinical source');
 PERFORM pg_temp.intake_ok(NOT EXISTS(SELECT 1 FROM public.workout_logs WHERE user_id=u) AND NOT EXISTS(SELECT 1 FROM public.meal_logs WHERE user_id=u) AND NOT EXISTS(SELECT 1 FROM public.messages WHERE user_id=u) AND NOT EXISTS(SELECT 1 FROM public.user_progress WHERE user_id=u) AND NOT EXISTS(SELECT 1 FROM private.conversation_workout_preparations WHERE user_id=u),'routing and reads never create domain effects or reward');
 r:=public.read_conversation_intake(u,i,h,e);PERFORM pg_temp.intake_ok(r->'selection'=x->'selection','read only returns exact durable seal');
 INSERT INTO intake_actual_golden VALUES('workout_text',s->'admission',s->'source',s->'claim',x,r);
 t:=pg_temp.intake_seed(u,gen_random_uuid());y:=pg_temp.intake_seal(u,t);
 PERFORM pg_temp.intake_ok(y->>'action'='sealed' AND y#>>'{selection,command,command_id}'<>child::text AND (SELECT count(*)=2 FROM private.conversation_workout_command_ids WHERE user_id=u),'two identical legitimate activities retain separate identities');
 PERFORM pg_temp.intake_ok(public.read_conversation_intake('c1390000-0000-4000-8000-000000000001',i,h,e)='{"action":"absent"}' AND public.read_conversation_intake(u,i,repeat('0',64),e)='{"action":"input_conflict"}','read owner and hash isolation');
END $routing$;
DO $meal$
DECLARE u uuid:='c1390000-0000-4000-8000-000000000020';e uuid:=gen_random_uuid();i uuid:=gen_random_uuid();a jsonb;s jsonb;c jsonb;x jsonb;raw jsonb;child uuid;
BEGIN
 INSERT INTO public.users(id,email,status,timezone,country,country_confirmed) VALUES(u,'intake-meal@example.invalid','active','UTC','BR',true);
 INSERT INTO private.workout_strength_authority_epochs(user_id,epoch,changed_at) VALUES(u,e,clock_timestamp());
 raw:=pg_temp.intake_input(i,'  Comi arroz.  ')||'{"meal_type_hint":"almoco"}';a:=public.admit_conversation_intake(u,e,raw);s:=public.capture_conversation_intake_source(u,i,a#>>'{intake,input_hash}',e);c:=public.claim_conversation_intake_routing(u,i,a#>>'{intake,input_hash}',e,s->>'source_hash');
 x:=public.seal_conversation_intake_routing(u,i,a#>>'{intake,input_hash}',e,s->>'source_hash',(c->>'claim_id')::uuid,'{"schema":"conversation.intake-routing.v1","kind":"meal.report","reason":"performed_meal"}');child:=(x#>>'{selection,command,command_id}')::uuid;
 PERFORM pg_temp.intake_ok(x->>'action'='sealed' AND x#>>'{selection,command,input,source,text}'='  Comi arroz.  ' AND x#>>'{selection,command,input,meal_type}'='almoco','meal genuine admission preserves literal text and optional hint');
 PERFORM pg_temp.intake_ok((SELECT source_input=x#>'{selection,command,input}' FROM private.conversation_meal_command_sources WHERE user_id=u AND command_id=child),'real fenced meal source persisted');
 INSERT INTO intake_actual_golden VALUES('meal_text',a,s,c,x,public.read_conversation_intake(u,i,a#>>'{intake,input_hash}',e));
 s:=public.capture_conversation_meal_source(u,child);
 PERFORM pg_temp.intake_ok(s ? 'source_hash' AND s#>>'{context,command_id}'=child::text,'real meal capture remains independently required after seal');
END $meal$;
DO $nonselected$
DECLARE u uuid:='c1390000-0000-4000-8000-000000000030';e uuid:=gen_random_uuid();s jsonb;x jsonb;d jsonb;
BEGIN
 INSERT INTO public.users(id,email,status,timezone) VALUES(u,'intake-nonselected@example.invalid','active','UTC');
 INSERT INTO private.workout_strength_authority_epochs(user_id,epoch,changed_at) VALUES(u,e,clock_timestamp());
 s:=pg_temp.intake_seed(u,gen_random_uuid(),'Posso caminhar amanhã?');x:=pg_temp.intake_seal(u,s,'not_reported');
 PERFORM pg_temp.intake_ok(x->>'action'='sealed' AND x#>'{selection,command}'='null'::jsonb,'nonperformed routing seals factual no-child outcome');
 INSERT INTO intake_actual_golden VALUES('not_reported',s->'admission',s->'source',s->'claim',x,public.read_conversation_intake(u,(s#>>'{intake,intake_id}')::uuid,s#>>'{intake,input_hash}',e));
 s:=pg_temp.intake_seed(u,gen_random_uuid(),'Comi e caminhei.');d:='{"schema":"conversation.intake-routing.v1","kind":"clarification_required","reason":"record_kind","question":{"field":"record_kind","text":"Qual registro você quer fazer primeiro?"}}';
 x:=public.seal_conversation_intake_routing(u,(s#>>'{intake,intake_id}')::uuid,s#>>'{intake,input_hash}',e,s#>>'{source,source_hash}',(s->>'claim_id')::uuid,d);
 PERFORM pg_temp.intake_ok(x->>'action'='sealed' AND x#>'{selection,command}'='null' AND x#>'{selection,decision}'=d,'one exact preserved clarification without inventing multi-effect policy');
 INSERT INTO intake_actual_golden VALUES('clarification_required',s->'admission',s->'source',s->'claim',x,public.read_conversation_intake(u,(s#>>'{intake,intake_id}')::uuid,s#>>'{intake,input_hash}',e));
 PERFORM pg_temp.intake_ok(NOT EXISTS(SELECT 1 FROM private.conversation_meal_command_ids WHERE user_id=u) AND NOT EXISTS(SELECT 1 FROM private.conversation_workout_command_ids WHERE user_id=u),'questions and nonreports produce no typed admission');
END $nonselected$;
DO $strict$
DECLARE u uuid:='c1390000-0000-4000-8000-000000000040';e uuid:=gen_random_uuid();raw jsonb;bad jsonb;v jsonb;denied boolean;i integer;
BEGIN
 INSERT INTO public.users(id,email,status,timezone) VALUES(u,'intake-strict@example.invalid','active','UTC');
 INSERT INTO private.workout_strength_authority_epochs(user_id,epoch,changed_at) VALUES(u,e,clock_timestamp());raw:=pg_temp.intake_input(gen_random_uuid());
 FOREACH bad IN ARRAY ARRAY[raw||'{"owner_id":"ignored"}',raw||'{"clock":"2020-01-01"}',raw||'{"meal_type_hint":null}',raw||'{"intake_id":"ABCDEF00-0000-4000-8000-000000000000"}',jsonb_set(raw,'{source,text}','"  "'),jsonb_set(raw,'{source,text}',to_jsonb(chr(1))),jsonb_set(raw,'{source,text}',to_jsonb(chr(127))),jsonb_set(raw,'{source,text}',to_jsonb(repeat('🦊',1001))),jsonb_set(raw,'{source}',(raw->'source')||'{"kind":"workout.report"}')] LOOP
  denied:=false;BEGIN PERFORM public.admit_conversation_intake(u,e,bad);EXCEPTION WHEN invalid_parameter_value THEN denied:=true;END;
  PERFORM pg_temp.intake_ok(denied,'closed invalid intake rejected');
 END LOOP;
 raw:=jsonb_set(raw,'{source,text}',to_jsonb(E'  Fiz\t30 minutos\nde caminhada.\r  '::text));v:=public.admit_conversation_intake(u,e,raw);
 PERFORM pg_temp.intake_ok(v->>'action'='admitted' AND (SELECT source_input=raw FROM private.conversation_intake_inputs WHERE user_id=u AND intake_id=(raw->>'intake_id')::uuid),'typed-compatible TAB LF CR and whitespace bytes preserved');
 FOREACH bad IN ARRAY ARRAY['{"schema":"conversation.intake-routing.v1","kind":"clarification_required","reason":"missing"}'::jsonb,'{"schema":"conversation.intake-routing.v1","kind":"not_reported","reason":"UPPER"}','{"schema":"conversation.intake-routing.v1","kind":"not_reported","reason":"x","question":null}','{"schema":"conversation.intake-routing.v1","kind":"clarification_required","reason":"x","question":{"field":"weight","text":"?"}}'] LOOP
  denied:=false;BEGIN PERFORM public.seal_conversation_intake_routing(u,(raw->>'intake_id')::uuid,v#>>'{intake,input_hash}',e,repeat('0',64),gen_random_uuid(),bad);EXCEPTION WHEN invalid_parameter_value THEN denied:=true;END;
  PERFORM pg_temp.intake_ok(denied,'closed invalid routing decision rejected');
 END LOOP;
 PERFORM pg_temp.intake_ok((SELECT count(*)=1 FROM private.conversation_intake_ids WHERE user_id=u),'invalid payloads reserve no permanent identity');
END $strict$;
DO $quota$
DECLARE u uuid:='c1390000-0000-4000-8000-000000000050';e uuid:=gen_random_uuid();raw jsonb;first_raw jsonb;v jsonb;s jsonb;child uuid;i integer;
BEGIN
 INSERT INTO public.users(id,email,status,timezone) VALUES(u,'intake-quota@example.invalid','active','UTC');
 INSERT INTO private.workout_strength_authority_epochs(user_id,epoch,changed_at) VALUES(u,e,clock_timestamp());
 FOR i IN 1..10 LOOP
  raw:=pg_temp.intake_input(gen_random_uuid());IF i=1 THEN first_raw:=raw;END IF;
  PERFORM pg_temp.intake_ok(public.admit_conversation_intake(u,e,raw)->>'action'='admitted','neutral rolling quota slot');
 END LOOP;
 PERFORM pg_temp.intake_ok(public.admit_conversation_intake(u,e,pg_temp.intake_input(gen_random_uuid()))='{"action":"rate_limited"}','eleventh neutral costs no capture or domain slot');
 PERFORM pg_temp.intake_ok(public.admit_conversation_intake(u,e,first_raw)->>'action'='replay','neutral replay free at cap');
 FOR i IN 1..10 LOOP
  raw:=jsonb_build_object('command_protocol','conversation.command.v1','command_id',gen_random_uuid(),'kind',CASE WHEN i%2=0 THEN 'meal.report' ELSE 'workout.report' END,'source',jsonb_build_object('channel','text','text','Registro sintético'));
  IF i%2=0 THEN v:=public.admit_conversation_meal_command_fenced(u,raw,e);ELSE v:=public.admit_conversation_workout_command(u,e,raw);END IF;
  PERFORM pg_temp.intake_ok(v->>'action'='admitted','neutral budget never consumes legacy shared typed quota');
 END LOOP;
 v:=public.admit_conversation_intake(u,e,first_raw);s:=public.capture_conversation_intake_source(u,(first_raw->>'intake_id')::uuid,v#>>'{intake,input_hash}',e);
 raw:=public.claim_conversation_intake_routing(u,(first_raw->>'intake_id')::uuid,v#>>'{intake,input_hash}',e,s->>'source_hash');s:=jsonb_build_object('intake',v->'intake','source',s,'claim_id',raw->'claim_id');
 SELECT reserved_child_id INTO child FROM private.conversation_intake_ids WHERE user_id=u AND intake_id=(first_raw->>'intake_id')::uuid;
 PERFORM pg_temp.intake_ok(pg_temp.intake_seal(u,s)='{"action":"rate_limited"}' AND NOT EXISTS(SELECT 1 FROM private.conversation_workout_command_ids WHERE user_id=u AND command_id=child) AND NOT EXISTS(SELECT 1 FROM private.conversation_intake_selections WHERE user_id=u),'selected child independently obeys genuine mixed legacy quota');
 PERFORM pg_temp.intake_ok(pg_temp.intake_seal(u,s,'not_reported')->>'action'='sealed','known quota refusal preserves claim for factual no-child resolution');
END $quota$;
DO $epoch_collision$
DECLARE u uuid:='c1390000-0000-4000-8000-000000000060';e uuid:=gen_random_uuid();i uuid:=gen_random_uuid();s jsonb;x jsonb;raw jsonb;child uuid;denied boolean;old_hash text;ne uuid;
BEGIN
 INSERT INTO public.users(id,email,status,timezone) VALUES(u,'intake-epoch@example.invalid','active','UTC');
 INSERT INTO private.workout_strength_authority_epochs(user_id,epoch,changed_at) VALUES(u,e,clock_timestamp());s:=pg_temp.intake_seed(u,i);old_hash:=s#>>'{intake,input_hash}';
 raw:=jsonb_build_object('command_protocol','conversation.command.v1','command_id',i,'kind','workout.report','source',jsonb_build_object('channel','text','text','Fiz caminhada'));
 denied:=false;BEGIN PERFORM public.admit_conversation_workout_command(u,e,raw);EXCEPTION WHEN unique_violation THEN denied:=true;END;
 PERFORM pg_temp.intake_ok(denied AND NOT EXISTS(SELECT 1 FROM private.conversation_workout_command_ids WHERE user_id=u),'later legacy typed writer cannot adopt neutral UUID');
 SELECT reserved_child_id INTO child FROM private.conversation_intake_ids WHERE user_id=u AND intake_id=i;
 PERFORM pg_temp.intake_ok(public.admit_conversation_intake(u,e,pg_temp.intake_input(child))='{"action":"input_conflict"}','another intake cannot take reserved child');
 raw:=jsonb_set(raw,'{command_id}',to_jsonb(child));PERFORM public.admit_conversation_workout_command(u,e,raw);
 PERFORM pg_temp.intake_ok(pg_temp.intake_seal(u,s)='{"action":"input_conflict"}' AND NOT EXISTS(SELECT 1 FROM private.conversation_intake_selections WHERE user_id=u),'seal refuses preexisting reserved-child legacy admission instead of adopting replay');
 PERFORM pg_temp.intake_ok(public.admit_conversation_intake(u,e,pg_temp.intake_input(child))='{"action":"input_conflict"}','existing typed identity cannot be retyped into intake');
 PERFORM public.reset_user_conversation_atomic(u,true);SELECT epoch INTO ne FROM private.workout_strength_authority_epochs WHERE user_id=u;
 PERFORM pg_temp.intake_ok(public.admit_conversation_intake(u,ne,pg_temp.intake_input(i))='{"action":"stale_epoch"}' AND public.read_conversation_intake(u,i,old_hash,ne)='{"action":"stale_epoch"}' AND pg_temp.intake_seal(u,s)='{"action":"stale_epoch"}','reset permanently tombstones original namespace under old or new epoch');
 PERFORM pg_temp.intake_ok((SELECT count(*)=1 AND bool_and(invalidated_at IS NOT NULL) FROM private.conversation_intake_ids WHERE user_id=u) AND NOT EXISTS(SELECT 1 FROM private.conversation_intake_inputs WHERE user_id=u) AND NOT EXISTS(SELECT 1 FROM private.conversation_intake_sources WHERE user_id=u) AND NOT EXISTS(SELECT 1 FROM private.conversation_intake_claims WHERE user_id=u) AND NOT EXISTS(SELECT 1 FROM private.conversation_intake_selections WHERE user_id=u),'epoch scrub removes all raw context claim selection but retains ID and hash');
 PERFORM pg_temp.intake_ok(public.admit_conversation_intake(u,e,pg_temp.intake_input(gen_random_uuid()))='{"action":"stale_epoch"}','never-admitted offline intent cannot retag stale epoch');
END $epoch_collision$;
CREATE FUNCTION pg_temp.intake_after_child() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
 IF NEW.source_input#>>'{source,text}'='Fiz rollback day.' THEN UPDATE public.users SET timezone='Pacific/Honolulu' WHERE id=NEW.user_id;
 ELSIF NEW.source_input#>>'{source,text}'='Fiz rollback epoch.' THEN UPDATE private.workout_strength_authority_epochs SET epoch=gen_random_uuid(),changed_at=clock_timestamp() WHERE user_id=NEW.user_id;END IF;
 RETURN NEW;
END $$;
CREATE TRIGGER intake_test_after_child AFTER INSERT ON private.conversation_workout_inputs FOR EACH ROW EXECUTE FUNCTION pg_temp.intake_after_child();
DO $atomic$
DECLARE u uuid:='c1390000-0000-4000-8000-000000000070';e uuid:=gen_random_uuid();s jsonb;x jsonb;txt text;child uuid;
BEGIN
 INSERT INTO public.users(id,email,status,timezone) VALUES(u,'intake-atomic@example.invalid','active','UTC');
 INSERT INTO private.workout_strength_authority_epochs(user_id,epoch,changed_at) VALUES(u,e,clock_timestamp());
 FOREACH txt IN ARRAY ARRAY['Fiz rollback day.','Fiz rollback epoch.'] LOOP
  s:=pg_temp.intake_seed(u,gen_random_uuid(),txt);SELECT reserved_child_id INTO child FROM private.conversation_intake_ids WHERE user_id=u AND intake_id=(s#>>'{intake,intake_id}')::uuid;
  x:=pg_temp.intake_seal(u,s);
  PERFORM pg_temp.intake_ok(x=jsonb_build_object('action',CASE WHEN txt='Fiz rollback day.' THEN 'day_changed' ELSE 'stale_epoch' END),'post-genuine-admission boundary refuses seal');
  PERFORM pg_temp.intake_ok(NOT EXISTS(SELECT 1 FROM private.conversation_workout_command_ids WHERE user_id=u AND command_id=child) AND NOT EXISTS(SELECT 1 FROM private.conversation_workout_inputs WHERE user_id=u AND command_id=child) AND NOT EXISTS(SELECT 1 FROM private.conversation_intake_selections WHERE user_id=u) AND (SELECT timezone='UTC' FROM public.users WHERE id=u) AND (SELECT epoch=e FROM private.workout_strength_authority_epochs WHERE user_id=u),'subtransaction rolls back child and all post-admission side effects atomically');
  PERFORM pg_temp.intake_ok(public.read_conversation_intake(u,(s#>>'{intake,intake_id}')::uuid,s#>>'{intake,input_hash}',e)->'claimed'='true','known seal refusal retains original once-only claim');
 END LOOP;
END $atomic$;
DROP TRIGGER intake_test_after_child ON private.conversation_workout_inputs;
DO $day$
DECLARE u uuid:='c1390000-0000-4000-8000-000000000080';e uuid:=gen_random_uuid();s jsonb;i uuid:=gen_random_uuid();v jsonb;
BEGIN
 INSERT INTO public.users(id,email,status,timezone) VALUES(u,'intake-day@example.invalid','active','UTC');
 INSERT INTO private.workout_strength_authority_epochs(user_id,epoch,changed_at) VALUES(u,e,clock_timestamp());s:=pg_temp.intake_seed(u,i);
 UPDATE public.users SET timezone='Pacific/Honolulu' WHERE id=u;
 PERFORM pg_temp.intake_ok(pg_temp.intake_seal(u,s)='{"action":"day_changed"}' AND public.capture_conversation_intake_source(u,i,s#>>'{intake,input_hash}',e)='{"action":"day_changed"}','timezone change cannot relocate old intent');
 UPDATE public.users SET timezone='UTC' WHERE id=u;
 INSERT INTO public.daily_snapshots(user_id,date,day_closed) VALUES(u,(clock_timestamp() AT TIME ZONE 'UTC')::date,true);
 PERFORM pg_temp.intake_ok(pg_temp.intake_seal(u,s)='{"action":"day_closed"}' AND public.capture_conversation_intake_source(u,i,s#>>'{intake,input_hash}',e)='{"action":"day_closed"}','closed original day refuses selection and capture');
 UPDATE public.users SET status='blocked' WHERE id=u;
 PERFORM pg_temp.intake_ok(public.read_conversation_intake(u,i,s#>>'{intake,input_hash}',e)='{"action":"stale_epoch"}','inactive owner read fails closed without write');
END $day$;

DO $media$
DECLARE u uuid:='c1390000-0000-4000-8000-000000000090';foreign_u uuid:='c1390000-0000-4000-8000-000000000091';e uuid:=gen_random_uuid();asset uuid:=gen_random_uuid();i uuid:=gen_random_uuid();raw jsonb;a jsonb;s jsonb;c jsonb;x jsonb;frozen jsonb;k text;
BEGIN
 INSERT INTO public.users(id,email,status,timezone) VALUES(u,'intake-media@example.invalid','active','UTC'),(foreign_u,'intake-media-foreign@example.invalid','active','UTC');
 INSERT INTO private.workout_strength_authority_epochs(user_id,epoch,changed_at) VALUES(u,e,clock_timestamp());
 INSERT INTO public.media_assets(id,user_id,kind,bucket_id,object_path,mime_type,declared_size_bytes,actual_size_bytes,status,source_request_hash,processing_request_id,retention_until,uploaded_at,processed_at,context_text,processing_result)
 VALUES(asset,u,'audio_note','audio-notes',u::text||'/'||asset||'.mp3','audio/mpeg',1200,1200,'processed',repeat('a',64),repeat('b',64),clock_timestamp()+interval '1 day',clock_timestamp(),clock_timestamp(),'Legenda completa original','{"text":"Fiz 30 minutos de caminhada.","segments":[{"text":"Fiz","start":0.1}],"model":"synthetic"}');
 raw:=jsonb_build_object('intake_protocol','conversation.intake.v1','intake_id',i,'source',jsonb_build_object('channel','media','media_asset_id',asset,'user_action','report_actual_record','caption','Legenda literal enviada'));
 a:=public.admit_conversation_intake(u,e,raw);s:=public.capture_conversation_intake_source(u,i,a#>>'{intake,input_hash}',e);
 PERFORM pg_temp.intake_ok(s->>'action'='captured' AND s#>>'{context,media,context_text}'='Legenda completa original' AND s#>>'{context,source_input,source,caption}'='Legenda literal enviada' AND s#>'{context,media,processing_result,segments}'='[{"text":"Fiz","start":0.1}]','capture preserves exact owned processed asset, full processing object, caption and context independently');
 c:=public.claim_conversation_intake_routing(u,i,a#>>'{intake,input_hash}',e,s->>'source_hash');frozen:=jsonb_build_object('intake',a->'intake','source',s,'claim_id',c->'claim_id');
 x:=pg_temp.intake_seal(u,frozen);
 PERFORM pg_temp.intake_ok(x='{"action":"media_projection_required"}' AND NOT EXISTS(SELECT 1 FROM private.conversation_intake_selections WHERE user_id=u) AND NOT EXISTS(SELECT 1 FROM private.conversation_workout_command_ids WHERE user_id=u) AND NOT EXISTS(SELECT 1 FROM private.conversation_meal_command_ids WHERE user_id=u),'selected media explicitly refuses without fake typed source, child or seal');
 INSERT INTO intake_actual_golden VALUES('audio_projection_refused',a,s,c,x,public.read_conversation_intake(u,i,a#>>'{intake,input_hash}',e));
 UPDATE public.media_assets SET processing_result=processing_result||'{"new_version":true}' WHERE id=asset;
 PERFORM pg_temp.intake_ok(public.capture_conversation_intake_source(u,i,a#>>'{intake,input_hash}',e)='{"action":"media_unavailable"}' AND pg_temp.intake_seal(u,frozen)='{"action":"source_conflict"}','processed content or updated_at drift cannot recapture or seal');
 UPDATE public.media_assets SET user_id=foreign_u,object_path=foreign_u::text||'/'||asset||'.mp3' WHERE id=asset;
 PERFORM pg_temp.intake_ok(pg_temp.intake_seal(u,frozen)='{"action":"media_unavailable"}','media ownership revocation refuses selection');
 UPDATE public.media_assets SET user_id=u,object_path=u::text||'/'||asset||'.mp3',processing_result=jsonb_build_object('text',repeat('x',1048577)) WHERE id=asset;
 i:=gen_random_uuid();raw:=jsonb_set(raw,'{intake_id}',to_jsonb(i));a:=public.admit_conversation_intake(u,e,raw);
 PERFORM pg_temp.intake_ok(public.capture_conversation_intake_source(u,i,a#>>'{intake,input_hash}',e)='{"action":"media_unavailable"}','oversized processing object refused without truncation');
 FOREACH k IN ARRAY ARRAY['meal_photo','gym_photo'] LOOP
  UPDATE public.media_assets SET kind=k,bucket_id=CASE WHEN k='meal_photo' THEN 'meal-photos' ELSE 'gym-photos' END,object_path=u::text||'/'||asset||'.jpg',mime_type='image/jpeg',processing_result='{"description":"Fotografia sintética completa"}' WHERE id=asset;
  i:=gen_random_uuid();raw:=jsonb_set(raw,'{intake_id}',to_jsonb(i));a:=public.admit_conversation_intake(u,e,raw);x:=public.capture_conversation_intake_source(u,i,a#>>'{intake,input_hash}',e);
  PERFORM pg_temp.intake_ok(x->>'action'='captured' AND x#>>'{context,media,kind}'=k,'neutral capture supports real owned photo kind without performed projection');
 END LOOP;
END $media$;
DO $immutability$
DECLARE u uuid:='c1390000-0000-4000-8000-000000000100';e uuid:=gen_random_uuid();s jsonb;x jsonb;denied boolean;table_name text;i uuid;before_count integer;
BEGIN
 INSERT INTO public.users(id,email,status,timezone) VALUES(u,'intake-immutability@example.invalid','active','UTC');
 INSERT INTO private.workout_strength_authority_epochs(user_id,epoch,changed_at) VALUES(u,e,clock_timestamp());i:=gen_random_uuid();s:=pg_temp.intake_seed(u,i);x:=pg_temp.intake_seal(u,s,'not_reported');
 FOREACH table_name IN ARRAY ARRAY['conversation_intake_ids','conversation_intake_inputs','conversation_intake_sources','conversation_intake_claims','conversation_intake_selections'] LOOP
  denied:=false;BEGIN EXECUTE format('UPDATE private.%I SET user_id=user_id WHERE user_id=$1',table_name) USING u;EXCEPTION WHEN invalid_parameter_value THEN denied:=true;END;
  PERFORM pg_temp.intake_ok(denied,'immutable persisted identity payload source claim selection');
 END LOOP;
 PERFORM pg_temp.intake_ok((SELECT provolatile='s' FROM pg_proc WHERE oid='public.read_conversation_intake(uuid,uuid,text,uuid)'::regprocedure),'read is STABLE PostgreSQL enforces no writes');
 PERFORM pg_temp.intake_ok(NOT has_table_privilege('service_role','private.conversation_intake_ids','SELECT') AND NOT has_table_privilege('service_role','private.conversation_intake_inputs','INSERT') AND NOT has_table_privilege('authenticated','private.conversation_intake_sources','SELECT'),'private rows never exposed to caller roles');
 PERFORM pg_temp.intake_ok((SELECT count(*)=5 AND bool_and(has_function_privilege('service_role',p.oid,'EXECUTE') AND NOT has_function_privilege('anon',p.oid,'EXECUTE') AND NOT has_function_privilege('authenticated',p.oid,'EXECUTE')) FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='public' AND p.proname IN('admit_conversation_intake','capture_conversation_intake_source','claim_conversation_intake_routing','seal_conversation_intake_routing','read_conversation_intake')),'exact five public service-only RPC grants');
 PERFORM set_config('request.jwt.claims','{"role":"authenticated"}',true);denied:=false;
 BEGIN PERFORM public.read_conversation_intake(u,i,s#>>'{intake,input_hash}',e);EXCEPTION WHEN insufficient_privilege THEN denied:=true;END;
 PERFORM pg_temp.intake_ok(denied,'JWT role fence refuses even security-definer privileged invoker');PERFORM set_config('request.jwt.claims','{"role":"service_role"}',true);
END $immutability$;

DO $date_style$
DECLARE u uuid:='c1390000-0000-4000-8000-000000000110';e uuid:=gen_random_uuid();s jsonb;
BEGIN
 INSERT INTO public.users(id,email,status,timezone) VALUES(u,'intake-datestyle@example.invalid','active','UTC');
 INSERT INTO private.workout_strength_authority_epochs(user_id,epoch,changed_at) VALUES(u,e,clock_timestamp());
 PERFORM set_config('datestyle','SQL,DMY',true);s:=pg_temp.intake_seed(u,gen_random_uuid());
 PERFORM pg_temp.intake_ok(s#>>'{source,context,local_date}' ~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}$','source local date and day lock namespace independent of session datestyle');
 PERFORM set_config('datestyle','ISO,YMD',true);
 PERFORM pg_temp.intake_ok(public.capture_conversation_intake_source(u,(s#>>'{intake,intake_id}')::uuid,s#>>'{intake,input_hash}',e)->>'action'='replay','source replay stable across caller datestyle');
END $date_style$;

SELECT jsonb_build_object('schema','t39.actual-sql-intake-golden.v1','fixtures',jsonb_agg(to_jsonb(g) ORDER BY label))::text FROM intake_actual_golden g;
SELECT jsonb_agg(jsonb_build_object('signature',p.oid::regprocedure::text,'prosrc_sha256',encode(sha256(convert_to(p.prosrc,'UTF8')),'hex')) ORDER BY p.proname)::text FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='public' AND p.proname IN('admit_conversation_intake','capture_conversation_intake_source','claim_conversation_intake_routing','seal_conversation_intake_routing','read_conversation_intake');
DO $physical_roles$
DECLARE u uuid:='c1390000-0000-4000-8000-000000000120';e uuid:=gen_random_uuid();s jsonb;r jsonb;denied boolean;target_role text;
BEGIN
 INSERT INTO public.users(id,email,status,timezone) VALUES(u,'intake-physical-role@example.invalid','active','UTC');
 INSERT INTO private.workout_strength_authority_epochs(user_id,epoch,changed_at) VALUES(u,e,clock_timestamp());s:=pg_temp.intake_seed(u,gen_random_uuid());
 EXECUTE 'SET LOCAL ROLE service_role';r:=public.read_conversation_intake(u,(s#>>'{intake,intake_id}')::uuid,s#>>'{intake,input_hash}',e);EXECUTE 'SET LOCAL ROLE NONE';
 PERFORM pg_temp.intake_ok(r->>'action'='available','actual service_role invokes definer RPC without private table rights');
 FOREACH target_role IN ARRAY ARRAY['anon','authenticated'] LOOP
  denied:=false;BEGIN
   EXECUTE format('SET LOCAL ROLE %I',target_role);PERFORM public.read_conversation_intake(u,(s#>>'{intake,intake_id}')::uuid,s#>>'{intake,input_hash}',e);
  EXCEPTION WHEN insufficient_privilege THEN denied:=true;END;
  EXECUTE 'SET LOCAL ROLE NONE';PERFORM pg_temp.intake_ok(denied,'actual untrusted SQL role cannot execute intake RPC');
 END LOOP;
 UPDATE public.users SET status='blocked' WHERE id=u;denied:=false;
 BEGIN PERFORM public.capture_conversation_intake_source(u,(s#>>'{intake,intake_id}')::uuid,s#>>'{intake,input_hash}',e);EXCEPTION WHEN no_data_found THEN denied:=true;END;
 PERFORM pg_temp.intake_ok(denied,'mutations require actual active owner under shared lock');
END $physical_roles$;
-- Historical synthetic row seed only: time cannot be advanced in a live local
-- clock test. This is not claimed as an RPC admission, nor rewritten in source.
DO $previous_day$
DECLARE u uuid:='c1390000-0000-4000-8000-000000000130';e uuid:=gen_random_uuid();i uuid:=gen_random_uuid();raw jsonb;h text;at timestamptz:=clock_timestamp()-interval '1 day';
BEGIN
 INSERT INTO public.users(id,email,status,timezone) VALUES(u,'intake-previous-day@example.invalid','active','UTC');
 INSERT INTO private.workout_strength_authority_epochs(user_id,epoch,changed_at) VALUES(u,e,clock_timestamp());raw:=pg_temp.intake_input(i);h:=encode(sha256(convert_to(private.conversation_command_canonical(raw),'UTF8')),'hex');
 INSERT INTO private.conversation_intake_ids VALUES(u,i,h,e,at,gen_random_uuid(),NULL);
 INSERT INTO private.conversation_intake_inputs VALUES(u,i,raw,'UTC',(at AT TIME ZONE 'UTC')::date);
 PERFORM pg_temp.intake_ok(public.capture_conversation_intake_source(u,i,h,e)='{"action":"day_changed"}' AND NOT EXISTS(SELECT 1 FROM private.conversation_intake_sources WHERE user_id=u),'previous admitted local day cannot silently move to today');
 PERFORM pg_temp.intake_ok(public.read_conversation_intake(u,i,h,e)->>'action'='available','read historical current-epoch admission remains observational without recapture');
END $previous_day$;

ROLLBACK;
