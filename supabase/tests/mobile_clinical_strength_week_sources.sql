-- A real legacy FULL must become a prospective weekly source, not a signup.
BEGIN;
SET LOCAL search_path=pg_catalog;
SELECT set_config('request.jwt.claim.role','service_role',true);
\ir fixtures/mobile_clinical_legacy_transition_fixture.sql
DO $$
DECLARE c jsonb;a uuid;q jsonb;r jsonb;scope private.strength_week_scopes%ROWTYPE;
 next_monday date;before_rows jsonb;operation uuid:=gen_random_uuid();
BEGIN
 c:=m3b_cycle_test.process_clinical_photos(m3b_cycle_test.legacy_photo_context(5460));
 a:=(c->>'user')::uuid;
 PERFORM m3b_cycle_test.ok(NOT EXISTS(SELECT 1 FROM private.strength_week_scopes WHERE user_id=a)
  AND NOT EXISTS(SELECT 1 FROM private.mobile_signup_strength_completion_receipts WHERE user_id=a),
  'legacy admission does not manufacture a signup or frequency scope');
 q:=m3b_cycle_test.legacy_clinical_request(c);
 r:=private.confirm_mobile_clinical_preview_at(a,(q#>>'{preview,preview_id}')::uuid,operation,
  q->'form',q->'intent',q->'proposal',NULL);
 PERFORM m3b_cycle_test.ok(r->>'status'='confirmed','actual legacy FULL commits before weekly assertions');
 next_monday:=date_trunc('week',(r->>'completed_at')::timestamptz AT TIME ZONE 'America/Sao_Paulo')::date+7;
 SELECT * INTO scope FROM private.strength_week_scopes WHERE user_id=a AND closed_at IS NULL;
 PERFORM m3b_cycle_test.ok(FOUND,'explicit frequency accepted by FULL opens an owned prospective scope');
 PERFORM m3b_cycle_test.ok((SELECT count(*)=1 AND bool_and(fact='value' AND planned_days=4
  AND effective_week_start=next_monday AND source_entity_id IS NULL AND source_valid_until IS NULL)
  FROM private.strength_week_source_versions WHERE user_id=a AND generation=scope.generation
  AND source_kind='informed_frequency'),
  'FULL frequency is sourced exactly once and takes effect only next local Monday');
 PERFORM m3b_cycle_test.ok((SELECT bool_and(observed_at=(r->>'completed_at')::timestamptz)
  FROM private.strength_week_source_versions WHERE user_id=a),
  'weekly sources use the same confirmed FULL clock across a civil-week boundary');
 PERFORM m3b_cycle_test.ok((SELECT count(*)=1 AND bool_and(fact='absent' AND effective_week_start=next_monday)
  FROM private.strength_week_source_versions WHERE user_id=a AND generation=scope.generation
  AND source_kind='accepted_plan'),'known absence of an active plan has its own prospective receipt');
 PERFORM m3b_cycle_test.ok(NOT EXISTS(SELECT 1 FROM private.mobile_signup_strength_completion_receipts WHERE user_id=a)
  AND NOT EXISTS(SELECT 1 FROM private.strength_week_targets WHERE user_id=a),
  'FULL never fabricates signup authority or freezes a target in the current week');
 before_rows:=m3b_cycle_test.original_state(a);
 PERFORM m3b_cycle_test.ok(private.confirm_mobile_clinical_preview_at(a,(q#>>'{preview,preview_id}')::uuid,
  operation,q->'form',q->'intent',q->'proposal',NULL)=r
  AND m3b_cycle_test.original_state(a)=before_rows,
  'FULL replay returns the original receipt without recurring effects');
 PERFORM m3b_cycle_test.ok((SELECT count(*)=2 FROM private.strength_week_source_versions WHERE user_id=a),
  'FULL replay cannot capture the frequency or plan absence twice');
 PERFORM m3b_cycle_test.ok(public.get_mobile_strength_week_context(a)->>'status'='unavailable',
  'new FULL source cannot supply a current-week target');
 PERFORM m3b_cycle_test.ok(private.get_mobile_strength_week_context_at(a,
  (next_monday+time '12:00') AT TIME ZONE 'America/Sao_Paulo')#>>'{context,frequency,receipt,planned_days}'='4',
  'the actual weekly context selects the new source next Monday');
 PERFORM m3b_cycle_test.throws(format('UPDATE private.mobile_clinical_strength_week_sources SET epoch=epoch WHERE user_id=%L',a),
  '55000','weekly FULL origin is immutable while owner exists');
 PERFORM m3b_cycle_test.throws(format('DELETE FROM private.mobile_clinical_strength_week_sources WHERE user_id=%L',a),
  '55000','weekly FULL origin cannot be deleted directly');
 PERFORM public.reset_user_conversation_atomic(a,true);
 before_rows:=m3b_cycle_test.original_state(a);
 PERFORM m3b_cycle_test.ok(private.confirm_mobile_clinical_preview_at(a,(q#>>'{preview,preview_id}')::uuid,
  operation,q->'form',q->'intent',q->'proposal',NULL)=r AND m3b_cycle_test.original_state(a)=before_rows
  AND NOT EXISTS(SELECT 1 FROM private.strength_week_scopes WHERE user_id=a AND closed_at IS NULL),
  'durable FULL replay after reset does not reopen weekly scope or recapture sources');
END $$;
DO $$
DECLARE c jsonb;a uuid;q jsonb;f jsonb;p jsonb;preview jsonb;r jsonb;before_rows jsonb;
BEGIN
 c:=m3b_cycle_test.process_clinical_photos(m3b_cycle_test.legacy_photo_context(5461));a:=(c->>'user')::uuid;
 q:=m3b_cycle_test.legacy_clinical_request(c);f:=jsonb_set(q->'form','{answers,strengthSessions}','null');
 preview:=private.prepare_mobile_clinical_preview_at(a,'TRANSITION_FULL',(c->>'cycle')::uuid,
  gen_random_uuid(),q#>>'{context,context_hash}',f,q->'intent',q->'proposal',NULL);
 r:=private.confirm_mobile_clinical_preview_at(a,(preview->>'preview_id')::uuid,gen_random_uuid(),
  f,q->'intent',q->'proposal',NULL);
 PERFORM m3b_cycle_test.ok(r->>'status'='confirmed' AND (SELECT training_frequency=4 FROM public.user_profiles WHERE user_id=a)
  AND NOT EXISTS(SELECT 1 FROM private.strength_week_scopes WHERE user_id=a),
  'explicit frequency opt-out preserves the profile without asserting a weekly source');

 c:=m3b_cycle_test.process_clinical_photos(m3b_cycle_test.legacy_photo_context(5462));a:=(c->>'user')::uuid;
 INSERT INTO public.training_plans(user_id,days_per_week,weekly_schedule) VALUES(a,2,'[]');
 q:=m3b_cycle_test.legacy_clinical_request(c);
 r:=private.confirm_mobile_clinical_preview_at(a,(q#>>'{preview,preview_id}')::uuid,gen_random_uuid(),
  q->'form',q->'intent',q->'proposal',NULL);
 PERFORM m3b_cycle_test.ok(r->>'status'='confirmed'
  AND (SELECT count(*)=1 FROM private.strength_week_source_versions WHERE user_id=a AND source_kind='informed_frequency')
  AND NOT EXISTS(SELECT 1 FROM private.strength_week_source_versions WHERE user_id=a AND source_kind='accepted_plan'),
  'an active legacy plan is neither fabricated as accepted nor recorded absent');
 PERFORM m3b_cycle_test.ok(private.get_mobile_strength_week_context_at(a,
  (date_trunc('week',clock_timestamp() AT TIME ZONE 'America/Sao_Paulo')::date+7+time '12:00')
   AT TIME ZONE 'America/Sao_Paulo')->>'reason'='history_incomplete',
  'unknown plan provenance remains unavailable even when frequency is proved');

 c:=m3b_cycle_test.process_clinical_photos(m3b_cycle_test.legacy_photo_context(5463),5,0);a:=(c->>'user')::uuid;
 q:=m3b_cycle_test.legacy_clinical_request(c);p:=q->'proposal';
 p:=jsonb_set(p,'{targets,afterKcal}',q#>'{proposal,targets,beforeKcal}');
 p:=jsonb_set(p,'{targets,afterProtein}',q#>'{proposal,targets,beforeProtein}');
 p:=jsonb_set(p,'{targets,formulaAfterKcal}','null');
 preview:=private.prepare_mobile_clinical_preview_at(a,'TRANSITION_FULL',(c->>'cycle')::uuid,
  gen_random_uuid(),q#>>'{context,context_hash}',q->'form',q->'intent',p,NULL);
 r:=private.confirm_mobile_clinical_preview_at(a,(preview->>'preview_id')::uuid,gen_random_uuid(),q->'form',q->'intent',p,NULL);
 PERFORM m3b_cycle_test.ok(r->>'status'='confirmed'
  AND NOT EXISTS(SELECT 1 FROM private.strength_week_scopes WHERE user_id=a),
  'clinical loss guard preserves the profile without producing exercise frequency authority');

 c:=m3b_cycle_test.process_clinical_photos(m3b_cycle_test.legacy_photo_context(5464));a:=(c->>'user')::uuid;
 q:=m3b_cycle_test.legacy_clinical_request(c);before_rows:=m3b_cycle_test.original_state(a);
 EXECUTE 'CREATE FUNCTION m3b_cycle_test.fail_week_origin() RETURNS trigger LANGUAGE plpgsql AS $f$ BEGIN RAISE EXCEPTION ''synthetic weekly origin failure''; END $f$';
 CREATE TRIGGER synthetic_week_origin_failure BEFORE INSERT ON private.mobile_clinical_strength_week_sources
  FOR EACH ROW EXECUTE FUNCTION m3b_cycle_test.fail_week_origin();
 PERFORM m3b_cycle_test.throws(format('SELECT private.confirm_mobile_clinical_preview_at(%L,%L,%L,%L,%L,%L,NULL)',a,
  q#>>'{preview,preview_id}',gen_random_uuid(),q->'form',q->'intent',q->'proposal'),
  'P0001','late frequency origin failure propagates out of FULL');
 DROP TRIGGER synthetic_week_origin_failure ON private.mobile_clinical_strength_week_sources;
 PERFORM m3b_cycle_test.ok(m3b_cycle_test.original_state(a)=before_rows
  AND NOT EXISTS(SELECT 1 FROM private.strength_week_scopes WHERE user_id=a),
  'frequency origin failure rolls back the entire FULL including photos and numeric effects');
END $$;
DO $$
DECLARE c jsonb;a uuid;q jsonb;f jsonb;p jsonb;preview jsonb;r jsonb;
BEGIN
 c:=m3b_cycle_test.process_clinical_photos(m3b_cycle_test.legacy_photo_context(5465));a:=(c->>'user')::uuid;
 q:=m3b_cycle_test.legacy_clinical_request(c);f:=jsonb_set(q->'form','{answers,strengthSessions}','0');
 p:=jsonb_set(q->'proposal','{profile,training_frequency}','0');
 preview:=private.prepare_mobile_clinical_preview_at(a,'TRANSITION_FULL',(c->>'cycle')::uuid,
  gen_random_uuid(),q#>>'{context,context_hash}',f,q->'intent',p,NULL);
 r:=private.confirm_mobile_clinical_preview_at(a,(preview->>'preview_id')::uuid,gen_random_uuid(),f,q->'intent',p,NULL);
 PERFORM m3b_cycle_test.ok(r->>'status'='confirmed' AND (SELECT training_frequency=0 FROM public.user_profiles WHERE user_id=a)
  AND (SELECT count(*)=1 AND bool_and(planned_days=0) FROM private.strength_week_source_versions
   WHERE user_id=a AND source_kind='informed_frequency'),
  'explicit zero sessions is a valid prospective frequency, unlike omitted input');

 c:=m3b_cycle_test.process_clinical_photos(m3b_cycle_test.legacy_photo_context(5466));a:=(c->>'user')::uuid;
 PERFORM public.declare_mobile_health_risk(a,gen_random_uuid(),ARRAY['professional_diet']);
 q:=m3b_cycle_test.legacy_clinical_request(c);p:=q->'proposal';
 p:=jsonb_set(p,'{targets,afterKcal}',q#>'{proposal,targets,beforeKcal}');
 p:=jsonb_set(p,'{targets,afterProtein}',q#>'{proposal,targets,beforeProtein}');
 p:=jsonb_set(p,'{targets,formulaAfterKcal}','null');
 preview:=private.prepare_mobile_clinical_preview_at(a,'TRANSITION_FULL',(c->>'cycle')::uuid,
  gen_random_uuid(),q#>>'{context,context_hash}',q->'form',q->'intent',p,NULL);
 r:=private.confirm_mobile_clinical_preview_at(a,(preview->>'preview_id')::uuid,gen_random_uuid(),q->'form',q->'intent',p,NULL);
 PERFORM m3b_cycle_test.ok(r->>'status'='confirmed' AND public.get_mobile_health_hold_state(a)->>'hold_active'='true'
  AND NOT EXISTS(SELECT 1 FROM private.strength_week_scopes WHERE user_id=a),
  'an active health hold cannot mint a weekly frequency from the preserved profile');
END $$;
SELECT m3b_cycle_test.ok(NOT has_function_privilege('service_role',
 'private.capture_mobile_clinical_strength_week_source(uuid,uuid)','EXECUTE')
 AND NOT has_function_privilege('anon','private.capture_mobile_clinical_strength_week_source(uuid,uuid)','EXECUTE')
 AND NOT has_function_privilege('authenticated','private.capture_mobile_clinical_strength_week_source(uuid,uuid)','EXECUTE'),
 'the new producer is private and cannot be called by app or backend roles directly');
SET CONSTRAINTS ALL IMMEDIATE;
ROLLBACK;
