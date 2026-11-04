-- Source-only test preparation. Real PG execution is not authorized yet.
BEGIN;
SET LOCAL request.jwt.claims='{"role":"service_role"}';SET LOCAL timezone='UTC';SET LOCAL datestyle='ISO,YMD';
\ir fixtures/conversation_meal_continuation_fixture.sql
DO $day$
DECLARE u uuid:='c3c50000-0000-4000-8000-000000000001';a uuid:='c3c50000-0000-4000-8000-000000000002';c uuid:='c3c50000-0000-4000-8000-000000000003';r uuid:='c3c50000-0000-4000-8000-000000000004';
 seed jsonb;state jsonb;body jsonb;before_state jsonb;parent_before jsonb;v jsonb;
BEGIN
 seed:=pg_temp.continuation_historical_seed(u,a,c,clock_timestamp()-interval '1 day');state:=pg_temp.continuation_read(u,c,seed);
 IF state->>'action'<>'available' THEN RAISE EXCEPTION 'historical fixture must be structurally eligible before freshness check';END IF;
 body:=pg_temp.continuation_body(state,'{"kind":"meal_type","meal_type":"almoco"}');before_state:=pg_temp.semantic_owner_state(u);parent_before:=state->'parent';
 v:=pg_temp.continuation_admit(u,c,seed,r,body);
 PERFORM pg_temp.writer_ok(v='{"action":"question_conflict"}'::jsonb AND pg_temp.semantic_owner_state(u)=before_state
  AND pg_temp.continuation_read(u,c,seed)->'parent'=parent_before,'yesterday original cannot be reassigned to today; no child head source domain or daily writes');
 PERFORM pg_temp.writer_ok(NOT EXISTS(SELECT 1 FROM private.conversation_meal_command_ids WHERE user_id=u AND command_id=r)
  AND NOT EXISTS(SELECT 1 FROM public.daily_snapshots WHERE user_id=u),'cross-day refusal never initializes current daily authority');
END $day$;
DO $zone$
DECLARE u uuid:='c3c50000-0000-4000-8000-000000000011';a uuid:='c3c50000-0000-4000-8000-000000000012';c uuid:='c3c50000-0000-4000-8000-000000000013';r uuid:='c3c50000-0000-4000-8000-000000000014';
 seed jsonb;state jsonb;body jsonb;before_state jsonb;
BEGIN
 seed:=pg_temp.continuation_seed(u,a,c,false);state:=pg_temp.continuation_read(u,c,seed);body:=pg_temp.continuation_body(state,'{"kind":"meal_type","meal_type":"almoco"}');
 -- Africa/Abidjan has the same current UTC civil day but a different timezone.
 UPDATE public.users SET timezone='Africa/Abidjan' WHERE id=u;before_state:=pg_temp.semantic_owner_state(u);
 PERFORM pg_temp.writer_ok(pg_temp.continuation_admit(u,c,seed,r,body)='{"action":"question_conflict"}'::jsonb
  AND pg_temp.semantic_owner_state(u)=before_state,'same civil date with changed original timezone still refuses before capture');
END $zone$;
DO $media$
DECLARE u uuid;auth_id uuid;c uuid;r uuid;asset uuid;seed jsonb;state jsonb;body jsonb;before_state jsonb;parent_before jsonb;admission jsonb;
 media_kind text;variant text;counter integer:=20;foreign_owner uuid:='c3c50000-0000-4000-8000-000000000099';p jsonb;prepared jsonb;
BEGIN
 INSERT INTO public.users(id,email,status,timezone,country,country_confirmed) VALUES(foreign_owner,'continuation-media-foreign@example.invalid','active','UTC','BR',true);
 FOREACH media_kind IN ARRAY ARRAY['audio_note','meal_photo'] LOOP
  u:=('c3c50000-0000-4000-8000-'||lpad(counter::text,12,'0'))::uuid;auth_id:=('c3c50000-0000-4000-8000-'||lpad((counter+1)::text,12,'0'))::uuid;
  c:=('c3c50000-0000-4000-8000-'||lpad((counter+2)::text,12,'0'))::uuid;r:=('c3c50000-0000-4000-8000-'||lpad((counter+3)::text,12,'0'))::uuid;asset:=('c3c50000-0000-4000-8000-'||lpad((counter+4)::text,12,'0'))::uuid;counter:=counter+10;
  seed:=pg_temp.continuation_media_seed(u,auth_id,c,asset,media_kind);state:=pg_temp.continuation_read(u,c,seed);parent_before:=state->'parent';
  IF state->>'action'<>'available' THEN RAISE EXCEPTION 'actual media fixture must have an eligible frozen question';END IF;
  body:=pg_temp.continuation_body(state,CASE media_kind WHEN 'audio_note' THEN '{"kind":"quantity","food_index":0,"amount":100,"unit":"g"}'::jsonb ELSE '{"kind":"meal_type","meal_type":"almoco"}'::jsonb END);
  FOREACH variant IN ARRAY ARRAY['processing_result','processed_at','context_text','updated_at','deleted_at','foreign_owner'] LOOP
   BEGIN
    IF variant='processing_result' THEN UPDATE public.media_assets SET processing_result=CASE media_kind WHEN 'audio_note' THEN '{"text":"Comi feijao"}'::jsonb ELSE '{"items":[{"name":"feijao","quantity_g_estimate":100,"confidence":1}]}'::jsonb END WHERE id=asset;
    ELSIF variant='processed_at' THEN UPDATE public.media_assets SET processed_at=processed_at+interval '1 microsecond' WHERE id=asset;
    ELSIF variant='context_text' THEN UPDATE public.media_assets SET context_text='Comi outra refeicao' WHERE id=asset;
    ELSIF variant='updated_at' THEN UPDATE public.media_assets SET updated_at=updated_at+interval '1 microsecond' WHERE id=asset;
    ELSIF variant='deleted_at' THEN UPDATE public.media_assets SET deleted_at=clock_timestamp() WHERE id=asset;
    ELSE UPDATE public.media_assets SET user_id=foreign_owner,object_path=foreign_owner::text||'/'||asset::text||CASE media_kind WHEN 'audio_note' THEN '.m4a' ELSE '.jpg' END WHERE id=asset;END IF;
    before_state:=pg_temp.semantic_owner_state(u);
    IF pg_temp.continuation_admit(u,c,seed,r,body)<>'{"action":"question_conflict"}'::jsonb OR pg_temp.semantic_owner_state(u) IS DISTINCT FROM before_state
     OR pg_temp.continuation_read(u,c,seed)->'parent' IS DISTINCT FROM parent_before THEN RAISE EXCEPTION 'original media drift accepted or changed state: % %',media_kind,variant;END IF;
    RAISE SQLSTATE 'ZC001' USING MESSAGE='rollback only this synthetic media drift';
   EXCEPTION WHEN SQLSTATE 'ZC001' THEN NULL;END;
   PERFORM pg_temp.writer_ok(true,'original pinned media refuses '||media_kind||' '||variant);
  END LOOP;
  admission:=pg_temp.continuation_admit(u,c,seed,r,body);
  PERFORM pg_temp.writer_ok(admission->>'action'='admitted','unchanged actual original media admits '||media_kind);
  BEGIN
   UPDATE public.media_assets SET context_text='changed after reply admission' WHERE id=asset;before_state:=pg_temp.semantic_owner_state(u);
   IF pg_temp.continuation_prepare(u,c,seed,r,admission#>>'{child_binding,input_hash}',NULL)<>'{"action":"source_conflict"}'::jsonb
    OR pg_temp.semantic_owner_state(u) IS DISTINCT FROM before_state THEN RAISE EXCEPTION 'original media CAS lost after admission %',media_kind;END IF;
   RAISE SQLSTATE 'ZC001';
  EXCEPTION WHEN SQLSTATE 'ZC001' THEN NULL;END;
  PERFORM pg_temp.writer_ok(true,'original media CAS retained after reply admission at prepare '||media_kind);
  IF media_kind='meal_photo' THEN
   state:=pg_temp.continuation_read(u,c,seed,r,admission#>>'{child_binding,input_hash}');p:=pg_temp.continuation_preparation(state);
   prepared:=pg_temp.continuation_prepare(u,c,seed,r,admission#>>'{child_binding,input_hash}',p);
   IF prepared->>'action'<>'prepared' THEN RAISE EXCEPTION 'unchanged photo source must actually prepare before testing commit drift';END IF;
   UPDATE public.media_assets SET processing_result=jsonb_set(processing_result,'{items,0,name}','"feijao"') WHERE id=asset;before_state:=pg_temp.semantic_owner_state(u);
   PERFORM pg_temp.writer_ok(pg_temp.continuation_commit(u,c,seed,r,admission#>>'{child_binding,input_hash}',prepared#>>'{stored,prepared_hash}')='{"action":"source_conflict"}'::jsonb
    AND pg_temp.semantic_owner_state(u)=before_state AND pg_temp.continuation_read(u,c,seed)->'parent'=parent_before,'original media CAS retained through actual prepared commit without changing parent proof');
  END IF;
 END LOOP;
END $media$;
-- A private server-clock seam is substituted only in this rollback-owned test.
-- Real public RPCs receive no caller clock; original definitions are restored.
CREATE TEMP TABLE continuation_original_clock_definition(definition text) ON COMMIT DROP;
INSERT INTO continuation_original_clock_definition SELECT pg_get_functiondef('private.conversation_continuation_original_current(uuid,jsonb)'::regprocedure);
CREATE OR REPLACE FUNCTION private.conversation_continuation_original_current(p_user uuid,parent jsonb) RETURNS boolean
LANGUAGE plpgsql VOLATILE SET search_path=pg_catalog SET timezone='UTC' SET datestyle='ISO,YMD' AS $$
DECLARE n integer;observed timestamptz;
BEGIN
 observed:=coalesce(nullif(current_setting('performe.synthetic_continuation_clock',true),'')::timestamptz,clock_timestamp());
 IF current_setting('performe.synthetic_continuation_late_clock',true)='on' THEN
  n:=coalesce(nullif(current_setting('performe.synthetic_continuation_clock_calls',true),'')::integer,0)+1;
  PERFORM set_config('performe.synthetic_continuation_clock_calls',n::text,true);
  IF n>1 THEN observed:=observed+interval '1 day';END IF;
 END IF;
 RETURN private.conversation_continuation_original_current_at(p_user,parent,observed);
END $$;
DO $midnight$
DECLARE u uuid:='c3c50000-0000-4000-8000-000000000061';a uuid:='c3c50000-0000-4000-8000-000000000062';c uuid:='c3c50000-0000-4000-8000-000000000063';r uuid:='c3c50000-0000-4000-8000-000000000064';
 seed jsonb;state jsonb;admission jsonb;body jsonb;p jsonb;prepared jsonb;fx jsonb;before_state jsonb;rejected boolean;
BEGIN
 seed:=pg_temp.continuation_seed(u,a,c,false);state:=pg_temp.continuation_read(u,c,seed);body:=pg_temp.continuation_body(state,'{"kind":"meal_type","meal_type":"almoco"}');
 admission:=pg_temp.continuation_admit(u,c,seed,r,body);state:=pg_temp.continuation_read(u,c,seed,r,admission#>>'{child_binding,input_hash}');p:=pg_temp.continuation_preparation(state);
 PERFORM set_config('performe.synthetic_continuation_clock',(clock_timestamp()+interval '1 day')::text,true);before_state:=pg_temp.semantic_owner_state(u);
 PERFORM pg_temp.writer_ok(pg_temp.continuation_prepare(u,c,seed,r,admission#>>'{child_binding,input_hash}',p)='{"action":"source_conflict"}'::jsonb
  AND pg_temp.semantic_owner_state(u)=before_state,'actual prepare refuses original-day rollover without preparing');
 PERFORM set_config('performe.synthetic_continuation_clock','',true);
 PERFORM set_config('performe.synthetic_continuation_late_clock','on',true);PERFORM set_config('performe.synthetic_continuation_clock_calls','0',true);before_state:=pg_temp.semantic_owner_state(u);rejected:=false;
 BEGIN PERFORM pg_temp.continuation_prepare(u,c,seed,r,admission#>>'{child_binding,input_hash}',p);
 EXCEPTION WHEN serialization_failure THEN rejected:=SQLERRM='conversation_original_source_changed_before_preparation';END;
 PERFORM pg_temp.writer_ok(rejected AND pg_temp.semantic_owner_state(u)=before_state,'rollover during preparation publication rolls back resolved metadata and head atomically');
 PERFORM set_config('performe.synthetic_continuation_late_clock','off',true);prepared:=pg_temp.continuation_prepare(u,c,seed,r,admission#>>'{child_binding,input_hash}',p);
 PERFORM set_config('performe.synthetic_continuation_clock',(clock_timestamp()+interval '1 day')::text,true);before_state:=pg_temp.semantic_owner_state(u);
 PERFORM pg_temp.writer_ok(pg_temp.continuation_commit(u,c,seed,r,admission#>>'{child_binding,input_hash}',prepared#>>'{stored,prepared_hash}')='{"action":"source_conflict"}'::jsonb
  AND pg_temp.semantic_owner_state(u)=before_state,'actual commit refuses original-day rollover before domain effect');
 PERFORM set_config('performe.synthetic_continuation_clock','',true);fx:=pg_temp.continuation_commit(u,c,seed,r,admission#>>'{child_binding,input_hash}',prepared#>>'{stored,prepared_hash}');
 IF fx->>'action'<>'committed' THEN RAISE EXCEPTION 'clock replay fixture must actually commit first';END IF;
 PERFORM set_config('performe.synthetic_continuation_clock',(clock_timestamp()+interval '1 day')::text,true);UPDATE public.daily_snapshots SET day_closed=true WHERE user_id=u;before_state:=pg_temp.semantic_owner_state(u);
 PERFORM pg_temp.writer_ok(pg_temp.continuation_commit(u,c,seed,r,admission#>>'{child_binding,input_hash}','obsolete')=jsonb_set(fx,'{action}','"replay"')
  AND pg_temp.semantic_owner_state(u)=before_state,'completed same-epoch lost response replays before original day and day-close freshness');
 PERFORM public.reset_user_conversation_atomic(u,true);
 PERFORM pg_temp.writer_ok(pg_temp.continuation_commit(u,c,seed,r,admission#>>'{child_binding,input_hash}','obsolete')='{"action":"stale_epoch"}'::jsonb,'reset precedes post-midnight first-winner replay');
END $midnight$;
DO $$ DECLARE definition text;BEGIN SELECT d.definition INTO definition FROM continuation_original_clock_definition d;EXECUTE definition;END $$;
SET CONSTRAINTS ALL IMMEDIATE;
SELECT count(*) AS continuation_original_source_assertions FROM meal_writer_assertions;
ROLLBACK;
