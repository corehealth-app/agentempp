-- Test-first invariants for local, rollback-only native execution.
-- Missing candidate RPC is SETUP, never a causal product RED.
-- Caller owns BEGIN READ COMMITTED / ROLLBACK and installs the reviewed fixture/candidate.
\set ON_ERROR_STOP on
SET LOCAL ROLE postgres;
DO $setup$
DECLARE u uuid;p jsonb;i integer;
BEGIN
 IF current_setting('transaction_isolation')<>'read committed'
  OR to_regprocedure('public.get_mobile_workout_strength_clarification(uuid,uuid)') IS NULL
  OR to_regprocedure('public.answer_mobile_workout_strength_clarification(uuid,uuid,uuid,integer,uuid,text,text)') IS NULL
 THEN RAISE EXCEPTION 'P10B_SETUP_CANDIDATE_OR_ISOLATION';END IF;
 INSERT INTO c59p10b_fixture.context VALUES('catalogue_baseline',c59p10b_fixture.catalogue());
 FOR i IN 3101..3102 LOOP
  u:=c59s17d_fixture.uid(i);
  INSERT INTO public.users(id,wpp,email,name,timezone,country,country_confirmed,metadata,flow_phrase_cursor_revision)
  VALUES(u,'155521'||lpad(i::text,7,'0'),'p10b-'||i||'@example.invalid','P10B synthetic','UTC','US',true,'{"p10b_fixture":"owned_clarification_r1"}',17);
  INSERT INTO public.user_profiles(user_id,weight_kg) VALUES(u,70);
  IF i=3101 THEN
   PERFORM c59p10b_fixture.expect(c59p10b_fixture.get_sql(u,c59s17d_fixture.uid(3199)),u,c59s17d_fixture.uid(3102),
    '{"status":"forbidden","reason":"stale_lifecycle"}','absent_authority_read_does_not_initialize');
   PERFORM c59p10b_fixture.expect(c59p10b_fixture.answer_sql(u,c59s17d_fixture.uid(3199),c59s17d_fixture.uid(3198),0,
    c59s17d_fixture.uid(3197),'yes','p10b-missing-authority'),u,c59s17d_fixture.uid(3102),
    '{"status":"forbidden","reason":"stale_lifecycle"}','absent_authority_answer_does_not_initialize');
  END IF;
  p:=c59p10b_fixture.produce(u,i,'P10B unknown '||i);
  SET LOCAL ROLE postgres;
  IF p#>>'{confirmation,capture,strength,fact,classification,status}' IS DISTINCT FROM 'unrecognized'
   OR p#>>'{confirmation,capture,strength,fact,clarification,status}' IS DISTINCT FROM 'unanswered'
  THEN RAISE EXCEPTION 'P10B_SETUP_REAL_UNKNOWN:%',p;END IF;
  INSERT INTO c59p10b_fixture.context VALUES(i::text,p);
 END LOOP;
 PERFORM c59p10b_fixture.ok((SELECT count(*)=2 FROM private.workout_strength_facts
  WHERE user_id IN(c59s17d_fixture.uid(3101),c59s17d_fixture.uid(3102))),'two_real_unknown_producers');
END $setup$;

DO $reads$
DECLARE p jsonb;u uuid:=c59s17d_fixture.uid(3101);v uuid:=c59s17d_fixture.uid(3102);
 w uuid;l uuid;q uuid;expected jsonb;other_workout uuid;target uuid;
BEGIN
 SELECT value INTO STRICT p FROM c59p10b_fixture.context WHERE label='3101';
 w:=(p#>>'{confirmation,capture,strength,fact,anchor,workoutLogID}')::uuid;
 l:=(p#>>'{confirmation,capture,strength,fact,anchor,lifecycleKey}')::uuid;
 q:=(p#>>'{confirmation,capture,strength,fact,clarification,questionKey}')::uuid;
 expected:=jsonb_build_object('status','available','workoutLogID',w,'lifecycleKey',l,
  'factRevision',0,'clarification',jsonb_build_object('status','unanswered','questionKey',q));
 INSERT INTO c59p10b_fixture.context VALUES('unanswered',expected);
 PERFORM c59p10b_fixture.expect(c59p10b_fixture.get_sql(u,w),u,v,expected,'owned_unanswered_read_no_side_effect');
 PERFORM c59p10b_fixture.expect(c59p10b_fixture.get_sql(u,w),u,v,expected,'repeated_read_same_tuple');
 SELECT (value#>>'{confirmation,capture,strength,fact,anchor,workoutLogID}')::uuid INTO STRICT other_workout
  FROM c59p10b_fixture.context WHERE label='3102';
 FOREACH target IN ARRAY ARRAY[other_workout,(p->>'registrationID')::uuid,c59s17d_fixture.uid(3199)] LOOP
  PERFORM c59p10b_fixture.expect(c59p10b_fixture.get_sql(u,target),u,v,
   '{"status":"forbidden","reason":"stale_workout"}',CASE WHEN target=other_workout THEN 'foreign_workout_private'
    WHEN target=(p->>'registrationID')::uuid THEN 'pending_uuid_not_workout' ELSE 'missing_workout_private' END);
  PERFORM c59p10b_fixture.expect(c59p10b_fixture.answer_sql(u,l,target,0,q,'yes','p10b-wrong-target-'||target::text),u,v,
   '{"status":"forbidden","reason":"stale_workout"}',CASE WHEN target=other_workout THEN 'foreign_answer_target_private'
    WHEN target=(p->>'registrationID')::uuid THEN 'pending_uuid_not_answer_target' ELSE 'missing_answer_target_private' END);
 END LOOP;
END $reads$;

SAVEPOINT pending_removed;
DELETE FROM public.pending_registrations WHERE user_id=c59s17d_fixture.uid(3101);
DO $pending_independent$
DECLARE e jsonb;BEGIN
 SELECT value INTO STRICT e FROM c59p10b_fixture.context WHERE label='unanswered';
 PERFORM c59p10b_fixture.expect(c59p10b_fixture.get_sql(c59s17d_fixture.uid(3101),(e->>'workoutLogID')::uuid),
  c59s17d_fixture.uid(3101),c59s17d_fixture.uid(3102),e,'question_survives_pending_removal');
END $pending_independent$;
ROLLBACK TO pending_removed;
RELEASE pending_removed;

SAVEPOINT catalogue_known;
INSERT INTO public.workout_types(id,slug,display_name,category,kcal_per_min,is_active,created_at,updated_at)
VALUES(c59s17d_fixture.uid(9901),'c59s17d-treino','P10B known synthetic','musculacao',5,true,'2026-10-15T00:00:00.000001Z','2026-10-15T00:00:00.000001Z');
DO $known$
DECLARE u uuid:=c59s17d_fixture.uid(3101);p jsonb;w uuid;l uuid;BEGIN
 p:=c59p10b_fixture.produce(u,3111,'c59s17d-treino');
 SET LOCAL ROLE postgres;
 w:=(p#>>'{confirmation,capture,strength,fact,anchor,workoutLogID}')::uuid;
 l:=(p#>>'{confirmation,capture,strength,fact,anchor,lifecycleKey}')::uuid;
 PERFORM c59p10b_fixture.ok(p#>>'{confirmation,capture,strength,fact,classification,status}'='matched','known_real_match_setup');
 PERFORM c59p10b_fixture.expect(c59p10b_fixture.get_sql(u,w),u,c59s17d_fixture.uid(3102),
  jsonb_build_object('status','available','workoutLogID',w,'lifecycleKey',l,'factRevision',0,
   'clarification',jsonb_build_object('status','not_applicable')),'known_has_no_question');
 PERFORM c59p10b_fixture.expect(c59p10b_fixture.answer_sql(u,l,w,0,c59s17d_fixture.uid(3199),'yes','p10b-known'),u,
  c59s17d_fixture.uid(3102),'{"status":"forbidden","reason":"not_unrecognized"}','known_rejects_nonnull_question');
END $known$;
ROLLBACK TO catalogue_known;
RELEASE catalogue_known;

SAVEPOINT catalogue_invalid;
INSERT INTO public.workout_types(id,slug,display_name,category,kcal_per_min,is_active,created_at,updated_at)
VALUES(c59s17d_fixture.uid(9901),'p10b-invalid-catalogue','P10B invalid synthetic','cardio',5,true,'2026-10-15T00:00:00.000001Z','infinity');
DO $unavailable$
DECLARE u uuid:=c59s17d_fixture.uid(3101);p jsonb;w uuid;l uuid;BEGIN
 p:=c59p10b_fixture.produce(u,3112,'P10B unavailable catalogue',true);
 SET LOCAL ROLE postgres;
 w:=(p#>>'{confirmation,capture,strength,fact,anchor,workoutLogID}')::uuid;
 l:=(p#>>'{confirmation,capture,strength,fact,anchor,lifecycleKey}')::uuid;
 PERFORM c59p10b_fixture.ok(p#>>'{confirmation,capture,strength,fact,classification,status}'='unavailable','unavailable_real_catalogue_setup');
 PERFORM c59p10b_fixture.expect(c59p10b_fixture.get_sql(u,w),u,c59s17d_fixture.uid(3102),
  jsonb_build_object('status','available','workoutLogID',w,'lifecycleKey',l,'factRevision',0,
   'clarification',jsonb_build_object('status','not_applicable')),'unavailable_classification_no_question');
 PERFORM c59p10b_fixture.expect(c59p10b_fixture.answer_sql(u,l,w,0,c59s17d_fixture.uid(3199),'yes','p10b-unavailable'),u,
  c59s17d_fixture.uid(3102),'{"status":"forbidden","reason":"not_unrecognized"}','unavailable_rejects_nonnull_question');
END $unavailable$;
ROLLBACK TO catalogue_invalid;
RELEASE catalogue_invalid;
DO $catalogue_restored$
BEGIN
 PERFORM c59p10b_fixture.ok(c59p10b_fixture.catalogue()=(SELECT value FROM c59p10b_fixture.context WHERE label='catalogue_baseline'),
  'catalogue_savepoints_restored');
END $catalogue_restored$;

SAVEPOINT legacy_workout;
DO $legacy_write$
DECLARE u uuid:=c59s17d_fixture.uid(3101);r jsonb;before_immutable jsonb;BEGIN
 before_immutable:=c59s17d_fixture.state(u)-ARRAY['public.workout_logs','public.daily_snapshots'];
 SET LOCAL ROLE service_role;
 r:=public.register_workout_atomic(u,'2026-10-16','P10B legacy only',10,100,'moderada',
  'synthetic legacy provenance control','2026-10-16T12:00:00.123456Z','p10b-legacy',2200,150.125,false,NULL);
 SET LOCAL ROLE postgres;
 -- The legacy13 contract returns inserted/workout_log_id/snapshot_id, not success.
 PERFORM c59p10b_fixture.ok(r->'inserted'='true'::jsonb AND r->'replaced_count'='0'::jsonb
  AND EXISTS(SELECT 1 FROM public.workout_logs w WHERE w.user_id=u AND w.id::text=r->>'workout_log_id'
   AND w.snapshot_id::text=r->>'snapshot_id' AND w.workout_type='P10B legacy only' AND w.estimated_kcal=100)
  AND EXISTS(SELECT 1 FROM public.daily_snapshots s WHERE s.user_id=u AND s.id::text=r->>'snapshot_id'
   AND s.date='2026-10-16' AND s.exercise_calories=100 AND s.training_done)
  AND c59s17d_fixture.state(u)-ARRAY['public.workout_logs','public.daily_snapshots']=before_immutable,
  'real_legacy_writer_control');
 INSERT INTO c59p10b_fixture.context VALUES('legacy',r);
END $legacy_write$;
DO $legacy_read$
DECLARE u uuid:=c59s17d_fixture.uid(3101);w uuid;BEGIN
 SELECT id INTO STRICT w FROM public.workout_logs WHERE user_id=u AND workout_type='P10B legacy only';
 PERFORM c59p10b_fixture.expect(c59p10b_fixture.get_sql(u,w),u,c59s17d_fixture.uid(3102),
  '{"status":"unavailable","reason":"provenance_gap"}','legacy_no_fact_no_backfill');
END $legacy_read$;
ROLLBACK TO legacy_workout;
RELEASE legacy_workout;

DO $missing_owner$
DECLARE u uuid:=c59s17d_fixture.uid(3199);v uuid:=c59s17d_fixture.uid(3102);BEGIN
 PERFORM c59p10b_fixture.expect_error(c59p10b_fixture.get_sql(u,c59s17d_fixture.uid(3198)),u,v,
  'P0002','workout_strength_patient_not_found','reader_missing_owner_p0002');
 PERFORM c59p10b_fixture.expect_error(c59p10b_fixture.answer_sql(u,c59s17d_fixture.uid(3198),c59s17d_fixture.uid(3197),0,
  c59s17d_fixture.uid(3196),'yes','p10b-missing-owner'),u,v,'P0002','workout_strength_patient_not_found','answer_missing_owner_p0002');
END $missing_owner$;
SAVEPOINT blocked_owner;
UPDATE public.users SET status='blocked' WHERE id=c59s17d_fixture.uid(3101);
DO $blocked$
DECLARE u uuid:=c59s17d_fixture.uid(3101);v uuid:=c59s17d_fixture.uid(3102);e jsonb;BEGIN
 SELECT value INTO STRICT e FROM c59p10b_fixture.context WHERE label='unanswered';
 PERFORM c59p10b_fixture.expect_error(c59p10b_fixture.get_sql(u,(e->>'workoutLogID')::uuid),u,v,
  'P0002','workout_strength_patient_not_found','reader_blocked_owner_p0002');
 PERFORM c59p10b_fixture.expect_error(c59p10b_fixture.answer_sql(u,(e->>'lifecycleKey')::uuid,(e->>'workoutLogID')::uuid,0,
  (e#>>'{clarification,questionKey}')::uuid,'yes','p10b-blocked-owner'),u,v,
  'P0002','workout_strength_patient_not_found','answer_blocked_owner_p0002');
END $blocked$;
ROLLBACK TO blocked_owner;
RELEASE blocked_owner;

DO $answers$
DECLARE p jsonb;u uuid;v uuid;w uuid;l uuid;q uuid;r jsonb;replay jsonb;expected jsonb;
 before_workout jsonb;before_snapshot jsonb;before_control jsonb;before_immutable jsonb;before_fact jsonb;before_captures jsonb;
 answer_value text;i integer;
BEGIN
 FOR i IN 3101..3102 LOOP
  u:=c59s17d_fixture.uid(i);v:=c59s17d_fixture.uid(CASE i WHEN 3101 THEN 3102 ELSE 3101 END);
  answer_value:=CASE i WHEN 3101 THEN 'yes' ELSE 'no' END;
  SELECT value INTO STRICT p FROM c59p10b_fixture.context WHERE label=i::text;
  w:=(p#>>'{confirmation,capture,strength,fact,anchor,workoutLogID}')::uuid;
  l:=(p#>>'{confirmation,capture,strength,fact,anchor,lifecycleKey}')::uuid;
  q:=(p#>>'{confirmation,capture,strength,fact,clarification,questionKey}')::uuid;
  SELECT to_jsonb(x) INTO STRICT before_workout FROM public.workout_logs x WHERE id=w AND user_id=u;
  SELECT to_jsonb(x) INTO STRICT before_snapshot FROM public.daily_snapshots x WHERE id=(before_workout->>'snapshot_id')::uuid AND user_id=u;
  before_control:=c59s17d_fixture.state(v);
  before_immutable:=c59s17d_fixture.state(u)-ARRAY['private.workout_strength_facts','private.workout_strength_operations'];
  SELECT to_jsonb(f)-ARRAY['answer','answer_operation_key','answer_accepted_at','revision'] INTO STRICT before_fact
   FROM private.workout_strength_facts f WHERE user_id=u AND workout_log_id=w;
  SELECT jsonb_agg(to_jsonb(o) ORDER BY o.operation_key) INTO before_captures FROM private.workout_strength_operations o
   WHERE user_id=u AND operation_kind='capture';
  r:=c59s17d_fixture.attempt(c59p10b_fixture.answer_sql(u,l,w,0,q,answer_value,'p10b-answer-'||i));
  SET LOCAL ROLE postgres;
  PERFORM c59p10b_fixture.ok(r->'ok'='true'::jsonb AND r#>>'{result,status}'='accepted'
   AND r#>>'{result,receipt,answer}'=answer_value
   AND (SELECT to_jsonb(x) FROM public.workout_logs x WHERE id=w)=before_workout
   AND (SELECT to_jsonb(x) FROM public.daily_snapshots x WHERE id=(before_workout->>'snapshot_id')::uuid)=before_snapshot
   AND c59s17d_fixture.state(u)-ARRAY['private.workout_strength_facts','private.workout_strength_operations']=before_immutable
   AND (SELECT to_jsonb(f)-ARRAY['answer','answer_operation_key','answer_accepted_at','revision'] FROM private.workout_strength_facts f
    WHERE user_id=u AND workout_log_id=w)=before_fact
   AND (SELECT jsonb_agg(to_jsonb(o) ORDER BY o.operation_key) FROM private.workout_strength_operations o
    WHERE user_id=u AND operation_kind='capture')=before_captures
   AND (SELECT count(*) FROM private.workout_strength_operations WHERE user_id=u AND operation_kind='answer')=1
   AND c59s17d_fixture.state(v)=before_control,'answer_'||answer_value||'_preserves_calories_control');
  expected:=jsonb_build_object('status','available','workoutLogID',w,'lifecycleKey',l,'factRevision',1,
   'clarification',jsonb_build_object('status','answered','receipt',r#>'{result,receipt}'));
  PERFORM c59p10b_fixture.expect(c59p10b_fixture.get_sql(u,w),u,v,expected,'lost_response_get_'||answer_value);
  replay:=(r->'result')||'{"status":"reuse_existing"}'::jsonb;
  PERFORM c59p10b_fixture.expect(c59p10b_fixture.answer_sql(u,l,w,0,q,answer_value,'p10b-answer-'||i),u,v,replay,'original_revision_zero_replay_'||answer_value);
  r:=c59s17d_fixture.attempt(c59p10b_fixture.answer_sql(u,l,w,1,q,answer_value,'p10b-second-'||i));
  SET LOCAL ROLE postgres;
  PERFORM c59p10b_fixture.ok(r=jsonb_build_object('ok',true,'result',replay),'second_operation_gets_original_winner_'||answer_value);
  PERFORM c59p10b_fixture.expect(c59p10b_fixture.answer_sql(u,l,w,0,q,CASE answer_value WHEN 'yes' THEN 'no' ELSE 'yes' END,'p10b-answer-'||i),u,v,
   '{"status":"conflict","reason":"operation_content_conflict"}','same_key_different_answer_'||answer_value);
  PERFORM c59p10b_fixture.expect(c59p10b_fixture.answer_sql(u,l,w,1,c59s17d_fixture.uid(3199),answer_value,'p10b-wrong-question-'||i),u,v,
   '{"status":"forbidden","reason":"stale_fact"}','wrong_question_'||answer_value);
  INSERT INTO c59p10b_fixture.context VALUES('answered-'||i,expected);
 END LOOP;
END $answers$;

-- Every authority mutation below is a QA fault injection inside a savepoint.
-- Facts, bindings and receipts remain genuine; none are fabricated or reclassified.
SAVEPOINT authority_null;
UPDATE private.workout_strength_authority_epochs SET current_lifecycle_key=NULL WHERE user_id=c59s17d_fixture.uid(3101);
DO $null_authority$
DECLARE e jsonb;u uuid:=c59s17d_fixture.uid(3101);v uuid:=c59s17d_fixture.uid(3102);BEGIN
 SELECT value INTO STRICT e FROM c59p10b_fixture.context WHERE label='answered-3101';
 PERFORM c59p10b_fixture.expect(c59p10b_fixture.get_sql(u,(e->>'workoutLogID')::uuid),u,v,
  '{"status":"forbidden","reason":"stale_lifecycle"}','null_authority_does_not_adopt_open_lifecycle');
 PERFORM c59p10b_fixture.expect(c59p10b_fixture.answer_sql(u,(e->>'lifecycleKey')::uuid,(e->>'workoutLogID')::uuid,0,
  (e#>>'{clarification,receipt,questionKey}')::uuid,'yes','p10b-answer-3101'),u,v,
  '{"status":"forbidden","reason":"stale_lifecycle"}','null_authority_rejects_original_replay');
END $null_authority$;
ROLLBACK TO authority_null;
RELEASE authority_null;

SAVEPOINT orphan_authority;
UPDATE private.workout_strength_authority_epochs SET current_lifecycle_key=c59s17d_fixture.uid(3199) WHERE user_id=c59s17d_fixture.uid(3101);
DO $orphan$
DECLARE e jsonb;BEGIN
 SELECT value INTO STRICT e FROM c59p10b_fixture.context WHERE label='answered-3101';
 PERFORM c59p10b_fixture.expect(c59p10b_fixture.get_sql(c59s17d_fixture.uid(3101),(e->>'workoutLogID')::uuid),
  c59s17d_fixture.uid(3101),c59s17d_fixture.uid(3102),'{"status":"forbidden","reason":"stale_lifecycle"}','missing_lifecycle_pointer_not_adopted');
END $orphan$;
ROLLBACK TO orphan_authority;
RELEASE orphan_authority;

SAVEPOINT foreign_authority;
UPDATE private.workout_strength_authority_epochs SET current_lifecycle_key=
 (SELECT current_lifecycle_key FROM private.workout_strength_authority_epochs WHERE user_id=c59s17d_fixture.uid(3102))
WHERE user_id=c59s17d_fixture.uid(3101);
DO $foreign_lifecycle$
DECLARE e jsonb;u uuid:=c59s17d_fixture.uid(3101);v uuid:=c59s17d_fixture.uid(3102);BEGIN
 SELECT value INTO STRICT e FROM c59p10b_fixture.context WHERE label='answered-3101';
 PERFORM c59p10b_fixture.expect(c59p10b_fixture.get_sql(u,(e->>'workoutLogID')::uuid),u,v,
  '{"status":"forbidden","reason":"stale_lifecycle"}','foreign_lifecycle_pointer_rejected');
 PERFORM c59p10b_fixture.expect(c59p10b_fixture.answer_sql(u,(e->>'lifecycleKey')::uuid,(e->>'workoutLogID')::uuid,0,
  (e#>>'{clarification,receipt,questionKey}')::uuid,'yes','p10b-answer-3101'),u,v,
  '{"status":"forbidden","reason":"stale_lifecycle"}','foreign_pointer_rejects_replay');
END $foreign_lifecycle$;
ROLLBACK TO foreign_authority;
RELEASE foreign_authority;

SAVEPOINT closed_lifecycle;
UPDATE private.workout_strength_lifecycles SET closed_at=clock_timestamp(),close_operation_key='p10b-controlled-close'
WHERE user_id=c59s17d_fixture.uid(3101) AND closed_at IS NULL;
DO $closed$
DECLARE e jsonb;u uuid:=c59s17d_fixture.uid(3101);v uuid:=c59s17d_fixture.uid(3102);BEGIN
 SELECT value INTO STRICT e FROM c59p10b_fixture.context WHERE label='answered-3101';
 PERFORM c59p10b_fixture.expect(c59p10b_fixture.get_sql(c59s17d_fixture.uid(3101),(e->>'workoutLogID')::uuid),
  c59s17d_fixture.uid(3101),c59s17d_fixture.uid(3102),'{"status":"forbidden","reason":"stale_lifecycle"}','closed_lifecycle_rejected');
 PERFORM c59p10b_fixture.expect(c59p10b_fixture.answer_sql(u,(e->>'lifecycleKey')::uuid,(e->>'workoutLogID')::uuid,0,
  (e#>>'{clarification,receipt,questionKey}')::uuid,'yes','p10b-answer-3101'),u,v,
  '{"status":"forbidden","reason":"stale_lifecycle"}','closed_lifecycle_rejects_replay');
END $closed$;
-- Controlled old-L retention, followed by a real new S17D confirmation. No fact edit.
UPDATE private.workout_strength_authority_epochs SET current_lifecycle_key=NULL WHERE user_id=c59s17d_fixture.uid(3101);
DO $new_current$
DECLARE p jsonb;BEGIN
 p:=c59p10b_fixture.produce(c59s17d_fixture.uid(3101),3120,'P10B new current lifecycle');
 SET LOCAL ROLE postgres;
 INSERT INTO c59p10b_fixture.context VALUES('new_current',p);
END $new_current$;
DO $old_fact$
DECLARE e jsonb;BEGIN
 SELECT value INTO STRICT e FROM c59p10b_fixture.context WHERE label='answered-3101';
 PERFORM c59p10b_fixture.expect(c59p10b_fixture.get_sql(c59s17d_fixture.uid(3101),(e->>'workoutLogID')::uuid),
  c59s17d_fixture.uid(3101),c59s17d_fixture.uid(3102),'{"status":"forbidden","reason":"stale_workout"}','old_fact_is_stale_not_legacy_gap');
END $old_fact$;
ROLLBACK TO closed_lifecycle;
RELEASE closed_lifecycle;

SAVEPOINT current_catalogue_zone_changed;
UPDATE public.users SET timezone='Asia/Tokyo' WHERE id=c59s17d_fixture.uid(3101);
INSERT INTO public.workout_types(id,slug,display_name,category,kcal_per_min,is_active,created_at,updated_at)
VALUES(c59s17d_fixture.uid(9901),'p10b-now-known','P10B unknown 3101','musculacao',5,true,clock_timestamp(),clock_timestamp());
DO $frozen_question$
DECLARE e jsonb;BEGIN
 SELECT value INTO STRICT e FROM c59p10b_fixture.context WHERE label='answered-3101';
 PERFORM c59p10b_fixture.expect(c59p10b_fixture.get_sql(c59s17d_fixture.uid(3101),(e->>'workoutLogID')::uuid),
  c59s17d_fixture.uid(3101),c59s17d_fixture.uid(3102),e,'catalogue_zone_changes_do_not_reclassify_question');
END $frozen_question$;
ROLLBACK TO current_catalogue_zone_changed;
RELEASE current_catalogue_zone_changed;

SAVEPOINT stored_anchor_changed;
UPDATE public.workout_logs SET workout_type='P10B edited anchor' WHERE user_id=c59s17d_fixture.uid(3101);
DO $anchor_changed$
DECLARE e jsonb;u uuid:=c59s17d_fixture.uid(3101);v uuid:=c59s17d_fixture.uid(3102);BEGIN
 SELECT value INTO STRICT e FROM c59p10b_fixture.context WHERE label='answered-3101';
 PERFORM c59p10b_fixture.expect(c59p10b_fixture.get_sql(u,(e->>'workoutLogID')::uuid),u,v,
  '{"status":"forbidden","reason":"stale_workout"}','changed_anchor_not_reclassified');
 PERFORM c59p10b_fixture.expect(c59p10b_fixture.answer_sql(u,(e->>'lifecycleKey')::uuid,(e->>'workoutLogID')::uuid,0,
  (e#>>'{clarification,receipt,questionKey}')::uuid,'yes','p10b-answer-3101'),u,v,
  '{"status":"forbidden","reason":"stale_workout"}','changed_anchor_rejects_original_replay');
END $anchor_changed$;
ROLLBACK TO stored_anchor_changed;
RELEASE stored_anchor_changed;

DO $reset$
DECLARE e jsonb;r jsonb;u uuid:=c59s17d_fixture.uid(3101);v uuid:=c59s17d_fixture.uid(3102);control jsonb;BEGIN
 SELECT value INTO STRICT e FROM c59p10b_fixture.context WHERE label='answered-3101';
 control:=c59s17d_fixture.state(v);
 r:=c59s17d_fixture.attempt(format('SELECT public.reset_user_conversation_atomic(%L::uuid,true)',u));
 SET LOCAL ROLE postgres;
 PERFORM c59p10b_fixture.ok(r->'ok'='true'::jsonb AND c59s17d_fixture.state(v)=control
  AND EXISTS(SELECT 1 FROM private.workout_strength_authority_epochs WHERE user_id=u AND current_lifecycle_key IS NULL),'real_reset_control_preserved');
 PERFORM c59p10b_fixture.expect(c59p10b_fixture.get_sql(u,(e->>'workoutLogID')::uuid),u,v,
  '{"status":"forbidden","reason":"stale_lifecycle"}','reset_get_rejected_without_new_authority');
 PERFORM c59p10b_fixture.expect(c59p10b_fixture.answer_sql(u,(e->>'lifecycleKey')::uuid,(e->>'workoutLogID')::uuid,0,
  (e#>>'{clarification,receipt,questionKey}')::uuid,'yes','p10b-answer-3101'),u,v,
  '{"status":"forbidden","reason":"stale_lifecycle"}','reset_rejects_replay_before_s9');
END $reset$;

DO $acl_and_arguments$
DECLARE signature text;r jsonb;BEGIN
 FOREACH signature IN ARRAY ARRAY['public.get_mobile_workout_strength_clarification(uuid,uuid)',
  'public.answer_mobile_workout_strength_clarification(uuid,uuid,uuid,integer,uuid,text,text)'] LOOP
  PERFORM c59p10b_fixture.ok(has_function_privilege('service_role',signature,'EXECUTE')
   AND NOT has_function_privilege('anon',signature,'EXECUTE') AND NOT has_function_privilege('authenticated',signature,'EXECUTE'),
   CASE WHEN signature LIKE '%get_mobile%' THEN 'reader_backend_acl' ELSE 'answer_backend_acl' END);
 END LOOP;
 r:=c59s17d_fixture.attempt('SELECT public.get_mobile_workout_strength_clarification(NULL,NULL)');
 SET LOCAL ROLE postgres;
 PERFORM c59p10b_fixture.ok(r->>'sqlstate'='22023' AND r->>'message'='invalid_workout_strength_input','reader_invalid_arguments_first');
 r:=c59s17d_fixture.attempt('SELECT public.answer_mobile_workout_strength_clarification(NULL,NULL,NULL,NULL,NULL,NULL,NULL)');
 SET LOCAL ROLE postgres;
 PERFORM c59p10b_fixture.ok(r->>'sqlstate'='22023' AND r->>'message'='invalid_workout_strength_input','answer_invalid_arguments_first');
 r:=c59s17d_fixture.attempt('SELECT public.get_mobile_workout_strength_clarification(NULL,NULL)','anon');
 SET LOCAL ROLE postgres;
 PERFORM c59p10b_fixture.ok(r->>'sqlstate'='42501','anon_actual_execute_denied');
END $acl_and_arguments$;

SAVEPOINT untrusted_claims;
SET LOCAL request.jwt.claims='{"role":"authenticated"}';
DO $guard_priority$
DECLARE r jsonb;BEGIN
 r:=c59s17d_fixture.attempt('SELECT public.get_mobile_workout_strength_clarification(NULL,NULL)');
 SET LOCAL ROLE postgres;
 PERFORM c59p10b_fixture.ok(r->>'sqlstate'='42501' AND r->>'message'='trusted backend role required','reader_trusted_guard_before_invalid_args');
 r:=c59s17d_fixture.attempt('SELECT public.answer_mobile_workout_strength_clarification(NULL,NULL,NULL,NULL,NULL,NULL,NULL)');
 SET LOCAL ROLE postgres;
 PERFORM c59p10b_fixture.ok(r->>'sqlstate'='42501' AND r->>'message'='trusted backend role required','answer_trusted_guard_before_invalid_args');
END $guard_priority$;
ROLLBACK TO untrusted_claims;
RELEASE untrusted_claims;
