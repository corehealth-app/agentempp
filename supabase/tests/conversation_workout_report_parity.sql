-- Real owned local PostgreSQL only. Fixtures and DDL are rollback-only.
BEGIN;
SET LOCAL request.jwt.claims='{"role":"service_role"}';
CREATE TEMP TABLE workout_parity_assertions(label text);
CREATE TEMP TABLE workout_parity_actual(kind text,source jsonb,report jsonb,preparation jsonb,effect jsonb);
CREATE FUNCTION pg_temp.parity_ok(value boolean,label text) RETURNS void LANGUAGE plpgsql AS $$
BEGIN IF value IS DISTINCT FROM true THEN RAISE EXCEPTION 'WORKOUT_PARITY_ASSERT:%',label;END IF;
 INSERT INTO workout_parity_assertions VALUES(label);END $$;
DO $natural$
DECLARE u uuid:=gen_random_uuid();e uuid:=gen_random_uuid();id uuid:=gen_random_uuid();input jsonb;a jsonb;s jsonb;report jsonb;p jsonb;
BEGIN
 INSERT INTO public.users(id,email,status,timezone,country,country_confirmed) VALUES(u,'t49-'||u||'@example.invalid','active','UTC','BR',true);
 INSERT INTO private.workout_strength_authority_epochs(user_id,epoch,changed_at) VALUES(u,e,clock_timestamp());
 input:=jsonb_build_object('command_protocol','conversation.command.v1','command_id',id,'kind','workout.report','source',jsonb_build_object('channel','text','text','Caminhei30min'));
 a:=public.admit_conversation_workout_command(u,e,input);
 s:=public.capture_conversation_workout_source(u,id,a#>>'{command,input_hash}',e);
 report:=jsonb_build_object('owner_id',u,'command_id',id,'input_hash',a#>>'{command,input_hash}','source_hash',s->>'source_hash','epoch',e,
  'status','ready','activity',jsonb_build_object('workout_type','caminhada','duration_min',30,'intensity',NULL),
  'evidence',jsonb_build_array(jsonb_build_object('unit','command_text','text','Caminhei30min')));
 p:=public.prepare_conversation_workout(u,id,a#>>'{command,input_hash}',s->>'source_hash',e,report);
 PERFORM pg_temp.parity_ok(p->>'action'='prepared' AND p#>>'{prepared,status}'='ready','natural complete TS report accepted by independent SQL');
END $natural$;
DO $legacy$
DECLARE row record;s jsonb;p jsonb;q jsonb;u uuid;id uuid;e uuid;denied boolean;
BEGIN
 PERFORM pg_temp.parity_ok((SELECT count(*)=4 FROM workout_parity_legacy),'real pre-upgrade fixture present');
 FOR row IN SELECT * FROM workout_parity_legacy LOOP
  s:=row.source;u:=(s#>>'{context,owner_id}')::uuid;id:=(s#>>'{context,command_id}')::uuid;e:=(s#>>'{context,epoch}')::uuid;
  PERFORM pg_temp.parity_ok((SELECT x.report_version=1 AND to_jsonb(x)-'report_version'=row.row_before FROM private.conversation_workout_preparations x WHERE user_id=u AND command_id=id),'legacy row defaults version1 with all original bytes preserved '||row.kind);
  PERFORM pg_temp.parity_ok(private.conversation_workout_report(s->'context',s->>'source_hash')=row.report,'legacy guard literal '||row.kind);
  PERFORM pg_temp.parity_ok(public.read_conversation_workout_preparation(u,id,s#>>'{context,input_hash}',e)=row.read_before,'legacy read payload identical '||row.kind);
  p:=public.prepare_conversation_workout(u,id,s#>>'{context,input_hash}',s->>'source_hash',e,row.report);
  PERFORM pg_temp.parity_ok(p=jsonb_set(row.preparation,'{action}','"replay"'),'legacy prepare replay identical '||row.kind);
  IF row.kind='natural' THEN
   q:=private.conversation_workout_report_v2(s->'context',s->>'source_hash');
   PERFORM pg_temp.parity_ok(q->>'status'='ready' AND public.prepare_conversation_workout(u,id,s#>>'{context,input_hash}',s->>'source_hash',e,q)='{"action":"semantic_conflict"}'::jsonb,'new grammar cannot reinterpret stored pending natural report');
  ELSIF row.kind='ready' THEN
   q:=public.commit_conversation_workout(u,id,s#>>'{context,input_hash}',s->>'source_hash',e,p->>'prepared_hash',p->'prepared');
   PERFORM pg_temp.parity_ok(q->>'action'='committed' AND public.commit_conversation_workout(u,id,s#>>'{context,input_hash}',s->>'source_hash',e,p->>'prepared_hash',p->'prepared')=jsonb_set(q,'{action}','"replay"'),'legacy uncommitted preparation still commits/replays with its guard');
  ELSIF row.kind='saved' THEN
   UPDATE public.user_profiles SET weight_kg=90 WHERE user_id=u;
   UPDATE public.daily_snapshots SET day_closed=true WHERE user_id=u;
   q:=public.commit_conversation_workout(u,id,s#>>'{context,input_hash}',s->>'source_hash',e,p->>'prepared_hash',p->'prepared');
   PERFORM pg_temp.parity_ok(q=jsonb_set(row.receipt,'{action}','"replay"'),'legacy saved receipt survives day/body changes byte-identically');
   PERFORM pg_temp.parity_ok(public.read_conversation_workout_effect(u,id,s#>>'{context,input_hash}',s->>'source_hash',e,p->>'prepared_hash')->'receipt'=row.receipt->'receipt','legacy effect read remains literal');
  END IF;
  denied:=false;BEGIN UPDATE private.conversation_workout_preparations SET report_version=2 WHERE user_id=u AND command_id=id;EXCEPTION WHEN invalid_parameter_value THEN denied:=true;END;
  PERFORM pg_temp.parity_ok(denied,'grammar version cannot change after preparation '||row.kind);
 END LOOP;
 PERFORM pg_temp.parity_ok((SELECT p.prosrc=b.prosrc AND p.proacl=b.proacl FROM pg_proc p JOIN workout_parity_before_bodies b ON b.signature='private.conversation_workout_report(jsonb,text)' WHERE p.oid='private.conversation_workout_report(jsonb,text)'::regprocedure),'legacy guard body and ACL unchanged');
 PERFORM pg_temp.parity_ok((SELECT bool_and(p.proacl=b.proacl) FROM pg_proc p JOIN workout_parity_before_bodies b ON p.oid=to_regprocedure(b.signature)),'existing RPC ACL unchanged');
END $legacy$;

DO $positive$
DECLARE row record;s jsonb;r jsonb;p jsonb;q jsonb;u uuid;id uuid;e uuid;facts jsonb;
BEGIN
 FOR row IN SELECT * FROM (VALUES
 ('Caminhei30min','caminhada',30,NULL),('Caminhei por 30 minutos leve.','caminhada',30,'leve'),
 ('Eu caminhei durante 30 min em ritmo moderado hoje.','caminhada',30,'moderada'),
 ('Hoje corri 1 hora e 15 minutos em ritmo alto!','corrida',75,'alta'),('Pedalei meia hora.','bicicleta',30,NULL),
 ('Nadei 1h30min moderada','natacao',90,'moderada'),('Corri 0,5h','corrida',30,NULL),
 ('Eu treinei musculação por 45 min','musculacao',45,NULL),('Fiz caminhada por 35 minutos','caminhada',35,NULL),
 ('Realizei 1h de bicicleta','bicicleta',60,NULL),('Fiz uma caminhada de 30 minutos','caminhada',30,NULL),
 ('Fiz 30 minutos de caminhada.','caminhada',30,NULL),
 ('Caminhei^30min','caminhada',30,NULL),(U&'Caminhei\00A030min','caminhada',30,NULL)
 ) x(t,slug,minutes,intensity) LOOP
  s:=pg_temp.parity_seed(row.t);u:=(s#>>'{context,owner_id}')::uuid;id:=(s#>>'{context,command_id}')::uuid;e:=(s#>>'{context,epoch}')::uuid;
  r:=private.conversation_workout_report_v2(s->'context',s->>'source_hash');
  PERFORM pg_temp.parity_ok(r->>'status'='ready' AND r->'activity'=jsonb_build_object('workout_type',row.slug,'duration_min',row.minutes,'intensity',row.intensity),'exact accepted activity '||row.t);
  p:=public.prepare_conversation_workout(u,id,s#>>'{context,input_hash}',s->>'source_hash',e,r);
  PERFORM pg_temp.parity_ok(p->>'action'='prepared' AND (SELECT report_version=2 FROM private.conversation_workout_preparations WHERE user_id=u AND command_id=id),'new SQL preparation chooses private version2 '||row.t);
  PERFORM pg_temp.parity_ok(p#>'{prepared,activity,estimated_kcal}'='null'::jsonb AND p#>>'{prepared,energy,status}'='unavailable','no missing-weight/intensity energy fallback '||row.t);
  q:=public.commit_conversation_workout(u,id,s#>>'{context,input_hash}',s->>'source_hash',e,p->>'prepared_hash',p->'prepared');
  PERFORM pg_temp.parity_ok(q->>'action'='committed' AND (SELECT count(*)=1 AND bool_and(estimated_kcal IS NULL) FROM public.workout_logs WHERE user_id=u),'v2 independent commit actually stores one owned workout '||row.t);
  PERFORM pg_temp.parity_ok(public.commit_conversation_workout(u,id,s#>>'{context,input_hash}',s->>'source_hash',e,p->>'prepared_hash',p->'prepared')=jsonb_set(q,'{action}','"replay"'),'v2 lost ACK replay does not duplicate '||row.t);
  facts:=public.read_conversation_workout_effect(u,id,s#>>'{context,input_hash}',s->>'source_hash',e,p->>'prepared_hash');
  PERFORM pg_temp.parity_ok(facts->>'action'='available' AND facts->'receipt'=q->'receipt' AND NOT(facts->'receipt' ? 'report_version'),'read receipt has unchanged closed public shape '||row.t);
  PERFORM pg_temp.parity_ok(NOT EXISTS(SELECT 1 FROM public.user_progress WHERE user_id=u) AND (SELECT calories_target IS NULL AND protein_target IS NULL FROM public.daily_snapshots WHERE user_id=u),'no XP block or food target minted '||row.t);
  INSERT INTO workout_parity_actual VALUES('text:'||row.t,s,r,p,facts);
 END LOOP;
END $positive$;

DO $negative$
DECLARE row record;s jsonb;r jsonb;p jsonb;q jsonb;u uuid;id uuid;e uuid;
BEGIN
 FOR row IN SELECT * FROM (VALUES
 ('Caminhei','duration_min'),('Hoje caminhei.','duration_min'),('Caminhei 0min','duration_min'),
 ('Caminhei 24h1min','duration_min'),('Caminhei 1h90min','duration_min'),('Caminhei 1441min','duration_min'),
 ('Comi arroz e fiz 30 minutos de caminhada.','activity'),('Caminhei30min e corri20min','activity'),
 ('Caminhei por aí','activity'),('Fiz caminhada leve alta','activity'),('Fiz 30 minutos de outro','activity'),
 ('Vou fazer caminhada',NULL),('Eu não fiz caminhada',NULL),('Sempre faço caminhada',NULL),
 ('sonhei2',NULL),('sonho_2',NULL),
 ('Ele fez 30 minutos de caminhada.',NULL),('Fiz 30 minutos de caminhada?',NULL),('Ontem caminhei30min',NULL),
 (U&'Fiz 30 minutos de mu\017Fcula\00E7\00E3o','activity'),
 ('Corri30min leve','activity'),('Fiz 30 minutos de corrida leve','activity')
 ) x(t,field) LOOP
  s:=pg_temp.parity_seed(row.t);u:=(s#>>'{context,owner_id}')::uuid;id:=(s#>>'{context,command_id}')::uuid;e:=(s#>>'{context,epoch}')::uuid;
  r:=private.conversation_workout_report_v2(s->'context',s->>'source_hash');
  PERFORM pg_temp.parity_ok(CASE WHEN row.field IS NULL THEN r->>'status'='not_reported' ELSE r->>'status'='needs_reply' AND r#>>'{question,field}'=row.field END,'negative/insufficient clause remains exact refusal '||row.t);
  p:=public.prepare_conversation_workout(u,id,s#>>'{context,input_hash}',s->>'source_hash',e,r);
  q:=public.commit_conversation_workout(u,id,s#>>'{context,input_hash}',s->>'source_hash',e,p->>'prepared_hash',p->'prepared');
  PERFORM pg_temp.parity_ok(p->>'action'='prepared' AND q->>'action'='not_ready' AND NOT EXISTS(SELECT 1 FROM public.workout_logs WHERE user_id=u),'no registration from non-ready report '||row.t);
  INSERT INTO workout_parity_actual VALUES('negative:'||row.t,s,r,p,NULL);
 END LOOP;
END $negative$;

DO $media$
DECLARE row record;s jsonb;r jsonb;p jsonb;q jsonb;u uuid;id uuid;e uuid;units jsonb;
BEGIN
 FOR row IN SELECT * FROM (VALUES
 ('agreement','Caminhei30min','Eu caminhei durante 30 min','Fiz caminhada por 30 minutos','audio_note','ready'),
 ('negated-context','Caminhei30min','Não fiz caminhada','Caminhei30min','audio_note','not_reported'),
 ('different-duration','Caminhei30min','Caminhei20min','Caminhei30min','audio_note','needs_reply'),
 ('missing-duration','Caminhei','Caminhei30min','Caminhei30min','audio_note','needs_reply'),
 ('pixels-only',NULL,NULL,NULL,'gym_photo','needs_reply'),
 ('unicode-blank-context','Caminhei30min',U&'\00A0','Caminhei30min','audio_note','ready')
 ) x(k,caption,context,transcript,kind,status) LOOP
  s:=pg_temp.parity_media(row.caption,row.context,row.transcript,row.kind);u:=(s#>>'{context,owner_id}')::uuid;id:=(s#>>'{context,command_id}')::uuid;e:=(s#>>'{context,epoch}')::uuid;
  r:=private.conversation_workout_report_v2(s->'context',s->>'source_hash');units:=private.conversation_workout_units_v2(s->'context');
  PERFORM pg_temp.parity_ok(s#>>'{context,schema}'='conversation.workout-source.v2' AND r->>'status'=row.status,'actual T44 selected child and separate sources '||row.k);
  IF row.kind='audio_note' THEN
   PERFORM pg_temp.parity_ok(CASE WHEN row.k='unicode-blank-context' THEN jsonb_array_length(units)=2 AND units->0->>'unit'='media_caption' AND units->1->>'unit'='media_transcript'
    ELSE jsonb_array_length(units)=3 AND units->0->>'unit'='media_caption' AND units->1->>'unit'='media_context' AND units->2->>'unit'='media_transcript' END,'all actual original media assertions retained '||row.k);END IF;
  p:=public.prepare_conversation_workout(u,id,s#>>'{context,input_hash}',s->>'source_hash',e,r);
  q:=public.commit_conversation_workout(u,id,s#>>'{context,input_hash}',s->>'source_hash',e,p->>'prepared_hash',p->'prepared');
  PERFORM pg_temp.parity_ok(q->>'action'=CASE WHEN row.status='ready' THEN 'committed' ELSE 'not_ready' END,'media commit respects every source '||row.k);
  INSERT INTO workout_parity_actual VALUES('media:'||row.k,s,r,p,q);
 END LOOP;
END $media$;

DO $caller_guards$
DECLARE s jsonb;r jsonb;p jsonb;x jsonb;u uuid;id uuid;e uuid;
BEGIN
 s:=pg_temp.parity_seed('Caminhei30min');u:=(s#>>'{context,owner_id}')::uuid;id:=(s#>>'{context,command_id}')::uuid;e:=(s#>>'{context,epoch}')::uuid;
 r:=private.conversation_workout_report_v2(s->'context',s->>'source_hash');
 PERFORM pg_temp.parity_ok(public.prepare_conversation_workout(u,id,s#>>'{context,input_hash}',s->>'source_hash',e,r||'{"report_version":1}')='{"action":"semantic_conflict"}'::jsonb
  AND NOT EXISTS(SELECT 1 FROM private.conversation_workout_preparations WHERE user_id=u),'caller metadata field never selects grammar or writes');
 p:=public.prepare_conversation_workout(u,id,s#>>'{context,input_hash}',s->>'source_hash',e,r);
 PERFORM pg_temp.parity_ok(public.commit_conversation_workout(u,id,s#>>'{context,input_hash}',s->>'source_hash',e,p->>'prepared_hash',p->'prepared'||'{"report_version":1}')='{"action":"prepared_conflict"}'::jsonb,'caller cannot override persisted version through prepared JSON');
 PERFORM pg_temp.parity_ok(public.read_conversation_workout_preparation(gen_random_uuid(),id,s#>>'{context,input_hash}',e)='{"action":"absent"}'::jsonb,'foreign owner has no versioned preparation');
 UPDATE public.users usr SET timezone='Pacific/Honolulu' WHERE usr.id=u;
 PERFORM pg_temp.parity_ok(public.commit_conversation_workout(u,id,s#>>'{context,input_hash}',s->>'source_hash',e,p->>'prepared_hash',p->'prepared')->>'action'='source_conflict','v2 source timezone drift still refused');
 UPDATE public.users usr SET timezone='UTC' WHERE usr.id=u;
 INSERT INTO public.daily_snapshots(user_id,date,day_closed) VALUES(u,(clock_timestamp() AT TIME ZONE 'UTC')::date,true);
 PERFORM pg_temp.parity_ok(public.commit_conversation_workout(u,id,s#>>'{context,input_hash}',s->>'source_hash',e,p->>'prepared_hash',p->'prepared')->>'action'='day_closed','v2 closed day still refused');
 PERFORM pg_temp.parity_ok(NOT EXISTS(SELECT 1 FROM public.workout_logs WHERE user_id=u) AND NOT EXISTS(SELECT 1 FROM public.user_progress WHERE user_id=u),'all caller refusals leave domain/rewards untouched');
 PERFORM public.reset_user_conversation_atomic(u,true);
 PERFORM pg_temp.parity_ok(public.read_conversation_workout_preparation(u,id,s#>>'{context,input_hash}',e)='{"action":"stale_epoch"}'::jsonb
  AND public.prepare_conversation_workout(u,id,s#>>'{context,input_hash}',s->>'source_hash',e,r)='{"action":"stale_epoch"}'::jsonb,'v2 reset preserves old epoch refusal');
 PERFORM pg_temp.parity_ok(NOT EXISTS(SELECT 1 FROM public.workout_logs WHERE user_id=u)
  AND (SELECT xp_total=0 AND blocks_completed=0 AND deficit_block=0 FROM public.user_progress WHERE user_id=u),'existing reset initialization grants no XP or block credit');
END $caller_guards$;

DO $acl$
DECLARE sig text;role text;
BEGIN
 FOREACH sig IN ARRAY ARRAY['private.conversation_workout_normalize_v2(text)','private.conversation_workout_units_v2(jsonb)','private.conversation_workout_duration_v2(text)','private.conversation_workout_clause_v2(text)','private.conversation_workout_question_v2(jsonb,text,text)','private.conversation_workout_report_v2(jsonb,text)','private.conversation_workout_report_version(jsonb,text,smallint)'] LOOP
  FOREACH role IN ARRAY ARRAY['anon','authenticated','service_role'] LOOP PERFORM pg_temp.parity_ok(NOT has_function_privilege(role,sig,'EXECUTE'),'no exposed private grammar privilege '||sig||role);END LOOP;
 END LOOP;
 PERFORM pg_temp.parity_ok(NOT has_table_privilege('service_role','private.conversation_workout_preparations','INSERT,UPDATE'),'caller cannot select/change private grammar metadata');
END $acl$;
SELECT jsonb_agg(to_jsonb(x) ORDER BY kind)::text FROM workout_parity_actual x;
DO $$ BEGIN RAISE NOTICE 'WORKOUT_PARITY_PASS:%',(SELECT count(*) FROM workout_parity_assertions);END $$;
SET CONSTRAINTS ALL IMMEDIATE;
ROLLBACK;
