-- Before-DDL fixture: the historical real writer seals NULL and known-zero days.
-- Only concatenate with the concrete migration (outer transaction stripped) and
-- conversation_workout_legacy_energy.sql in the guarded owned rollback runner.
BEGIN;
\ir fixtures/mobile_clinical_day_close_fixture.sql
CREATE TEMP TABLE workout_legacy_energy_original(kind text,q jsonb,c jsonb,k uuid,e jsonb,r jsonb);
DO $$
DECLARE kind text;q jsonb;u uuid;c jsonb;e jsonb;r jsonb;k uuid;
BEGIN
 FOREACH kind IN ARRAY ARRAY['unknown','known_zero'] LOOP
  q:=m3b_cycle_test.close_seed(CASE WHEN kind='unknown' THEN 1396 ELSE 1397 END);u:=(q->>'user')::uuid;k:=gen_random_uuid();
  INSERT INTO public.workout_logs(user_id,snapshot_id,workout_type,duration_min,estimated_kcal,performed_at)
  VALUES(u,(q->>'snapshot')::uuid,'caminhada',30,CASE WHEN kind='unknown' THEN NULL ELSE 0 END,((q->>'date')::date+time '12:00') AT TIME ZONE (q->>'zone'));
  c:=m3b_cycle_test.close_capture(q);e:=m3b_cycle_test.close_effect(q);
  e:=jsonb_set(jsonb_set(jsonb_set(e,'{fields,training_done}','true'),'{fields,xp_earned}','20'),'{progress,xpTotal}','20');
  e:=jsonb_set(jsonb_set(e,'{telemetry,0,properties,training_done}','true'),'{telemetry,0,properties,xp_earned}','20');
  r:=m3b_cycle_test.close_apply(q,c,k,e);INSERT INTO workout_legacy_energy_original VALUES(kind,q,c,k,e,r);
 END LOOP;
END $$;
