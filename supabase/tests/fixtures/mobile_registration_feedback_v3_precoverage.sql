-- Execute BEFORE the concrete workout coverage migration, in the SAME rollback
-- transaction as the v3 suite. These are real old writer bodies, no invented
-- historical default marker and no mutation of an immutable effect.
\ir conversation_meal_feedback_fixture.sql
CREATE TEMP TABLE feedback_v3_precoverage(owner_id uuid,unsealed_command uuid,old_command uuid,old_receipt jsonb,old_row jsonb);
DO $precoverage$
DECLARE u uuid:='139f0000-0000-4000-8000-000000000040';c uuid:='139f0000-0000-4000-8000-000000000041';oldc uuid:='139f0000-0000-4000-8000-000000000042';s uuid:=gen_random_uuid();x jsonb;source jsonb;f jsonb;oldrow jsonb;
BEGIN
 IF EXISTS(SELECT 1 FROM pg_attribute WHERE attrelid='public.daily_snapshots'::regclass AND attname='exercise_energy_complete' AND NOT attisdropped) THEN RAISE EXCEPTION 'v3_precoverage_requires_real_pre_DDL_schema';END IF;
 PERFORM set_config('request.jwt.claims','{"role":"service_role"}',true);
 INSERT INTO public.users(id,email,status,timezone,country,country_confirmed) VALUES(u,'v3-precoverage@example.invalid','active','UTC','BR',true);
 INSERT INTO public.daily_snapshots(id,user_id,date) VALUES(s,u,(clock_timestamp() AT TIME ZONE 'UTC')::date);
 INSERT INTO public.workout_logs(user_id,snapshot_id,workout_type,duration_min,estimated_kcal,performed_at) VALUES(u,s,'caminhada',30,NULL,clock_timestamp());
 x:=pg_temp.feedback_seed(u,c);
 IF x->>'action'<>'committed' THEN RAISE EXCEPTION 'v3_real_precoverage_meal_failed';END IF;
 x:=pg_temp.feedback_seed(u,oldc);source:=public.read_conversation_meal_feedback_source(u,oldc)->'context';f:=pg_temp.command_feedback(source);
 IF public.commit_conversation_meal_feedback_v2(u,oldc,x#>>'{receipt,effect_version}',f)->>'action'<>'committed' THEN RAISE EXCEPTION 'v3_real_precoverage_old_feedback_failed';END IF;
 SELECT to_jsonb(r) INTO oldrow FROM private.mobile_registration_feedback_v2 r WHERE r.user_id=u;
 INSERT INTO feedback_v3_precoverage VALUES(u,c,oldc,f,oldrow);
END $precoverage$;

CREATE TEMP TABLE feedback_v3_precoverage_legacy(owner_id uuid,registration_id uuid,feedback jsonb,stored_row jsonb);
DO $old_v1$
DECLARE u uuid:='139f0000-0000-4000-8000-000000000043';r uuid:='139f0000-0000-4000-8000-000000000044';c jsonb:=pg_temp.feedback_empty_cursor(u);steps jsonb;f jsonb;x jsonb;
BEGIN
 INSERT INTO public.users(id,email,status,timezone) VALUES(u,'v3-old-v1@example.invalid','active','UTC');
 INSERT INTO public.pending_registrations(id,user_id,status,proposal,expires_at) VALUES(r,u,'confirmed','{"kind":"workout"}',clock_timestamp()+interval '1 day');
 steps:=jsonb_build_array(pg_temp.feedback_empty_step(u,r,'incentive',c));
 f:=jsonb_build_object('schema','registration.feedback.v1','registration_id',r,'kind','workout','locale','en','meal_totals',NULL,'day',NULL,'lines',jsonb_build_array(jsonb_build_object('key','day_unavailable','text','Synthetic day unavailable.')),'food_comment',NULL,'incentive',NULL);
 x:=public.commit_mobile_registration_feedback(u,r,'{"kind":"workout"}','0',NULL,steps,f);
 IF x->>'action'<>'committed' THEN RAISE EXCEPTION 'precoverage_v1_actual_write_failed';END IF;
 INSERT INTO feedback_v3_precoverage_legacy SELECT u,r,f,to_jsonb(row) FROM private.mobile_registration_feedback row WHERE row.registration_id=r;
END $old_v1$;
