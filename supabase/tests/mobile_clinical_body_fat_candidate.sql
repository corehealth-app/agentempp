BEGIN;
SET LOCAL search_path=pg_catalog;
SELECT set_config('request.jwt.claim.role','service_role',true);
\ir fixtures/mobile_clinical_full_fixture.sql
SELECT m3b_cycle_test.ok(to_regprocedure('private.mobile_clinical_body_fat_candidate_at(uuid,uuid,timestamptz)') IS NOT NULL,
 'trusted recurring body fat candidate authority exists');
DO $$
DECLARE c jsonb;a uuid;cycle uuid;x jsonb;y jsonb; before_rows jsonb; observed timestamptz;
BEGIN
 c:=m3b_cycle_test.clinical_photos(1400);a:=(c->>'user')::uuid;cycle:=(c->>'cycle')::uuid;
 before_rows:=m3b_cycle_test.original_state(a);observed:=clock_timestamp();
 x:=private.mobile_clinical_body_fat_candidate_at(a,cycle,observed);
 y:=private.mobile_clinical_body_fat_candidate_at(a,cycle,observed+interval '1 microsecond');
 PERFORM m3b_cycle_test.ok(x=y AND x->>'availability'='available' AND (x->>'mean_percent')::numeric=24
  AND (x->>'mean_hundredths')::integer=2400,'three actual private readings produce stable canonical arithmetic mean');
 PERFORM m3b_cycle_test.ok(jsonb_array_length(x->'sources')=3
  AND x#>>'{sources,0,pose}'='front' AND x#>>'{sources,1,pose}'='side' AND x#>>'{sources,2,pose}'='back'
  AND x#>>'{sources,0,source_revision}' IS NOT NULL AND x->>'source_hash' ~ '^[0-9a-f]{64}$',
  'candidate binds three exact current source and processing identities');
 PERFORM m3b_cycle_test.ok(x::text !~ 'object_path|bucket_id|context_text|https://|SYNTHETIC LOCAL',
  'candidate has no image transport or legal text');
 PERFORM m3b_cycle_test.ok(before_rows=m3b_cycle_test.original_state(a),
  'candidate never records an acceptance profile BF progress or calorie target');
 PERFORM m3b_cycle_test.allocate(c,gen_random_uuid(),'side');
 y:=private.mobile_clinical_body_fat_candidate_at(a,cycle,NULL);
 PERFORM m3b_cycle_test.ok(y->>'availability'='unavailable' AND y->'mean_percent'='null'::jsonb,
  'pending replacement blocks old mean before upload changes cycle revision');
 c:=m3b_cycle_test.ready_photo(1401);a:=(c->>'user')::uuid;cycle:=(c->>'cycle')::uuid;
 x:=private.mobile_clinical_body_fat_candidate_at(a,cycle,NULL);
 PERFORM m3b_cycle_test.ok(x->>'availability'='unavailable' AND x->>'unavailable_reason'='three_processed_photos_required',
  'uploaded single photo is not three processed readings');
 x:=private.mobile_clinical_body_fat_candidate_at(a,cycle,clock_timestamp()+interval '61 seconds');
 PERFORM m3b_cycle_test.ok(x->>'availability'='unavailable' AND x->>'unavailable_reason'='consent_expired',
  'expired consent cannot supply a confirmation candidate');
 PERFORM m3b_cycle_test.throws(format('SELECT private.mobile_clinical_body_fat_candidate_at(%L,%L,NULL)',
  m3b_cycle_test.uid(1400),cycle),'40001','other owner cycle cannot supply a candidate');
END $$;
SELECT m3b_cycle_test.ok(NOT has_function_privilege(role,
 'private.mobile_clinical_body_fat_candidate_at(uuid,uuid,timestamptz)','EXECUTE'),role||' no private candidate execution')
 FROM unnest(ARRAY['anon','authenticated','service_role']) role;
ROLLBACK;
