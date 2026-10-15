\set ON_ERROR_STOP on
-- Missing real dependencies are SETUP failures, never a product RED.
DO $target$BEGIN IF session_user<>'c5_local_admin' OR current_database()<>'c5_reset_default_20261009'
 OR current_setting('port')<>'55489' OR current_setting('listen_addresses')<>''
 OR current_setting('data_directory')<>'/Users/eduardohenrique/.local/share/performe-ai/final-polish-20261001/e3/c5-portable-postgres17-20261009/data'
 THEN RAISE EXCEPTION 'C59S14_SETUP_WRONG_LOCAL_TARGET';END IF;END $target$;
\if :{?baseline_only}
\else
\set baseline_only false
\endif
\if :{?setup_concurrency}
\else
\set setup_concurrency false
\endif
\if :{?teardown_concurrency}
\else
\set teardown_concurrency false
\endif
\if :baseline_only
\if :setup_concurrency
DO $$BEGIN RAISE EXCEPTION 'C59S14_SETUP_CONFLICTING_MODES';END$$;
\endif
\if :teardown_concurrency
DO $$BEGIN RAISE EXCEPTION 'C59S14_SETUP_CONFLICTING_MODES';END$$;
\endif
\endif
\if :setup_concurrency
\if :teardown_concurrency
DO $$BEGIN RAISE EXCEPTION 'C59S14_SETUP_CONFLICTING_MODES';END$$;
\endif
\endif
\if :teardown_concurrency
BEGIN ISOLATION LEVEL READ COMMITTED;
SET LOCAL statement_timeout='40s';SET LOCAL lock_timeout='10s';SET LOCAL request.jwt.claims='{"role":"service_role"}';
DO $owned$DECLARE o record;r record;BEGIN
 SELECT * INTO STRICT o FROM c59s14_fixture.ownership WHERE tag='c59s14_reset_v1';
 IF o.owner_name<>session_user OR o.object_oids IS DISTINCT FROM c59s14_fixture.object_oids()
 OR o.object_fingerprint IS DISTINCT FROM c59s14_fixture.object_fingerprint() OR(SELECT count(*) FROM c59s14_fixture.ownership)<>1
 OR(SELECT count(*) FROM c59s14_fixture.cases)<>13
 OR(SELECT array_agg(owner_id ORDER BY owner_id) FROM c59s14_fixture.cases) IS DISTINCT FROM ARRAY(SELECT c59s14_fixture.uid(i) FROM generate_series(11,23)i ORDER BY i) THEN RAISE EXCEPTION 'C59S14_TEARDOWN_OBJECT_DRIFT';END IF;
 IF c59s14_fixture.state(c59s14_fixture.uid(201)) IS DISTINCT FROM o.sentinel THEN RAISE EXCEPTION 'C59S14_TEARDOWN_SENTINEL_CHANGED';END IF;
 FOR r IN SELECT owner_id FROM c59s14_fixture.cases UNION ALL SELECT c59s14_fixture.uid(201) LOOP
 IF r.owner_id NOT IN(SELECT c59s14_fixture.uid(i) FROM generate_series(11,23)i UNION ALL SELECT c59s14_fixture.uid(201)) THEN RAISE EXCEPTION 'C59S14_TEARDOWN_UUID_DRIFT';END IF;
 IF EXISTS(SELECT 1 FROM public.users WHERE id=r.owner_id AND (wpp IS DISTINCT FROM '155514'||lpad(right(r.owner_id::text,12)::integer::text,7,'0')
 OR email IS DISTINCT FROM 'c59s14-'||right(r.owner_id::text,12)::integer||'@example.invalid')) THEN RAISE EXCEPTION 'C59S14_TEARDOWN_OWNER_DRIFT';END IF;
 DELETE FROM public.users WHERE id=r.owner_id;
 END LOOP;
END $owned$;
-- Only new task-owned helpers/tables. Product functions/tables are NOT dropped.
DROP FUNCTION c59s14_fixture.seed(integer,boolean);DROP FUNCTION c59s14_fixture.enrich(uuid);
DROP FUNCTION c59s14_fixture.capture(uuid,uuid,text,text);DROP FUNCTION c59s14_fixture.answer(jsonb,text);
DROP FUNCTION c59s14_fixture.owner(integer,boolean);DROP FUNCTION c59s14_fixture.arguments(uuid,text,text);
DROP FUNCTION c59s14_fixture.deleted_count(jsonb,boolean);DROP FUNCTION c59s14_fixture.delete_owner(uuid);
DROP FUNCTION c59s14_fixture.fail_after_close();DROP FUNCTION c59s14_fixture.state(uuid);
DROP FUNCTION c59s14_fixture.object_fingerprint();DROP FUNCTION c59s14_fixture.object_oids();
DROP FUNCTION c59s14_fixture.uid(integer);DROP FUNCTION c59s14_fixture.attempt(text);DROP FUNCTION c59s14_fixture.ok(boolean,text);
DROP TABLE c59s14_fixture.cases;DROP TABLE c59s14_fixture.ownership;DROP SCHEMA c59s14_fixture;
COMMIT;
\echo C59S14_CONCURRENCY_TEARDOWN_CONFIRMED
\else
BEGIN ISOLATION LEVEL READ COMMITTED;
SET LOCAL statement_timeout='45s';SET LOCAL lock_timeout='10s';SET LOCAL search_path=public,pg_catalog;
SET LOCAL request.jwt.claims='{"role":"service_role"}';SET LOCAL TimeZone='UTC';SET LOCAL DateStyle='ISO, YMD';
DO $preflight$BEGIN
 IF to_regnamespace('c59s14_fixture') IS NOT NULL THEN RAISE EXCEPTION 'C59S14_SETUP_UNKNOWN_FIXTURE';END IF;
 IF to_regprocedure('public.register_workout_strength_atomic(uuid,uuid,text,text,jsonb,jsonb)') IS NULL
 OR to_regprocedure('public.answer_confirmed_workout_strength(uuid,uuid,uuid,integer,uuid,text,text)') IS NULL
 OR to_regprocedure('public.get_confirmed_workouts_for_strength_week(uuid,uuid,uuid,text,date,date)') IS NULL
 OR to_regprocedure('public.create_plan_draft_atomic(uuid,text,text,text,jsonb,jsonb,jsonb,jsonb,uuid,uuid,jsonb,text)') IS NULL
 OR to_regprocedure('public.confirm_plan_draft_atomic(uuid,uuid,integer,timestamptz,text)') IS NULL THEN RAISE EXCEPTION 'C59S14_SETUP_REAL_DEPENDENCIES_REQUIRED';END IF;
 IF EXISTS(SELECT 1 FROM public.users WHERE id IN(SELECT ('c59ae000-0000-0000-0000-'||lpad(i::text,12,'0'))::uuid FROM generate_series(11,23)i
 UNION ALL SELECT ('c59ae000-0000-0000-0000-'||lpad(i::text,12,'0'))::uuid FROM generate_series(100,110)i UNION ALL SELECT 'c59ae000-0000-0000-0000-000000000201'::uuid))
 THEN RAISE EXCEPTION 'C59S14_SETUP_SYNTHETIC_UUID_COLLISION';END IF;
END $preflight$;
\ir fixtures/reset_workout_strength_lifecycle_fixture.sql
\if :setup_concurrency
DO $seed$DECLARE i integer;p jsonb;ids text[]:=ARRAY['reset-capture-commit','reset-capture-rollback','capture-reset-commit','capture-reset-rollback','reset-answer-commit','reset-answer-rollback','answer-reset-commit','answer-reset-rollback','delete-capture-commit','delete-capture-rollback','capture-delete-commit','capture-delete-rollback','no-life-reset-advisory'];BEGIN
 FOR i IN 11..23 LOOP IF i=23 THEN PERFORM c59s14_fixture.owner(i,false);p:=jsonb_build_object('ownerID',c59s14_fixture.uid(i)::text,'lifecycleKey',c59s14_fixture.uid(i+1000)::text);ELSE p:=c59s14_fixture.seed(i,i NOT BETWEEN 15 AND 18);END IF;
 INSERT INTO c59s14_fixture.cases VALUES(ids[i-10],c59s14_fixture.uid(i),c59s14_fixture.uid(i+1000),p);END LOOP;
 PERFORM c59s14_fixture.seed(201);
END $seed$;
INSERT INTO c59s14_fixture.ownership VALUES('c59s14_reset_v1',session_user,c59s14_fixture.object_oids(),c59s14_fixture.object_fingerprint(),c59s14_fixture.state(c59s14_fixture.uid(201)));
COMMIT;
\echo C59S14_CONCURRENCY_SETUP_CONFIRMED
\else
-- EXACT causal oracle is identical in baseline-only and post-fix full mode.
DO $baseline$DECLARE u uuid:=c59s14_fixture.owner(100);r jsonb;BEGIN
 r:=public.reset_user_conversation_atomic(u,true);
 PERFORM c59s14_fixture.ok(r->>'reset'='true' AND EXISTS(SELECT 1 FROM private.workout_strength_lifecycles WHERE user_id=u AND closed_at IS NOT NULL),'exact_old_reset_closes_open_lifecycle');
END $baseline$;
\if :baseline_only
ROLLBACK;
\echo C59S14_BASELINE_ROLLBACK_CONFIRMED
\else
SELECT c59s14_fixture.object_fingerprint() AS fingerprint
\gset s14_
DO $variant$DECLARE u uuid:=c59s14_fixture.uid(101);p jsonb;draft uuid;before_state jsonb;other_state jsonb;r jsonb;closed jsonb;lower_bound timestamptz;plans boolean;BEGIN
 p:=c59s14_fixture.seed(101);draft:=c59s14_fixture.enrich(u);
 IF NOT EXISTS(SELECT 1 FROM public.users WHERE id=c59s14_fixture.uid(201)) THEN PERFORM c59s14_fixture.seed(201);END IF;
 other_state:=c59s14_fixture.state(c59s14_fixture.uid(201));before_state:=c59s14_fixture.state(u);lower_bound:=clock_timestamp();
 r:=public.reset_user_conversation_atomic(u,true);
 PERFORM c59s14_fixture.ok(r=jsonb_build_object('reset',true,'user_id',u,'deleted_rows',c59s14_fixture.deleted_count(before_state,true),'kept_plans',true),'true_exact_legacy_result_count');
 SELECT to_jsonb(l) INTO closed FROM private.workout_strength_lifecycles l WHERE user_id=u;
 PERFORM c59s14_fixture.ok((closed->>'closed_at')::timestamptz>=lower_bound AND (closed->>'closed_at')::timestamptz<=clock_timestamp()
 AND closed->>'close_operation_key' LIKE 'reset_user_conversation:%' AND (closed->>'close_operation_key')~'^reset_user_conversation:[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
 AND closed->>'lifecycle_key'=p->>'lifecycleKey' AND closed->>'opened_at'=(before_state#>>'{private.workout_strength_lifecycles,0,opened_at}'),'true_closed_postlock_once');
 PERFORM c59s14_fixture.ok(NOT EXISTS(SELECT 1 FROM public.workout_logs WHERE user_id=u) AND NOT EXISTS(SELECT 1 FROM private.workout_strength_facts WHERE user_id=u)
 AND NOT EXISTS(SELECT 1 FROM public.daily_snapshots WHERE user_id=u)
 AND (SELECT jsonb_agg(to_jsonb(c) ORDER BY to_jsonb(c)::text) FROM private.workout_strength_commands c WHERE user_id=u)=before_state->'private.workout_strength_commands'
 AND (SELECT jsonb_agg(to_jsonb(s) ORDER BY to_jsonb(s)::text) FROM private.workout_strength_calendar_scopes s WHERE user_id=u)=before_state->'private.workout_strength_calendar_scopes'
 AND (SELECT count(*)=2 AND bool_and(live_workout_log_id IS NULL) AND bool_and(original_workout_log_id=(p->>'workoutLogID')::uuid) FROM private.workout_strength_operations WHERE user_id=u)
 AND (SELECT answer_receipt=p->'receipt' FROM private.workout_strength_operations WHERE user_id=u AND operation_kind='answer'),'true_private_tombstones_no_live_facts');
 plans:=(SELECT metadata='{"training_reminders":true,"training_delivery_hour":7}'::jsonb FROM public.users WHERE id=u) AND EXISTS(SELECT 1 FROM public.plan_drafts WHERE id=draft AND source_message_id IS NULL) AND EXISTS(SELECT 1 FROM public.prescriptions WHERE user_id=u) AND EXISTS(SELECT 1 FROM public.training_plans WHERE user_id=u AND active);r:=public.confirm_plan_draft_atomic(u,draft,1,NULL,'s14-confirm-after-reset');plans:=plans AND r->>'status'='confirmed';
 PERFORM c59s14_fixture.ok(plans,'true_plans_metadata_real_confirmation');
 PERFORM c59s14_fixture.ok((SELECT wpp=before_state#>>'{user,wpp}' AND email=before_state#>>'{user,email}' AND timezone='UTC' AND country='US' AND status='active'
 AND name IS NULL AND NOT country_confirmed AND flow_phrase_cursor_revision=0 FROM public.users WHERE id=u)
 AND (SELECT NOT onboarding_completed AND onboarding_step=0 AND weight_kg IS NULL AND body_fat_percent IS NULL FROM public.user_profiles WHERE user_id=u)
 AND (SELECT xp_total=0 AND level=1 AND current_streak=0 AND deficit_block=0 AND current_weight IS NULL AND cardinality(badges_earned)=0 FROM public.user_progress WHERE user_id=u)
 AND (SELECT count(*)=1 FROM public.subscriptions WHERE user_id=u) AND (SELECT count(*)=1 FROM public.subscription_events WHERE user_id=u)
 AND c59s14_fixture.state(c59s14_fixture.uid(201))=other_state,'true_identity_profile_progress_billing_otherowner');
 r:=public.reset_user_conversation_atomic(u,true);
 PERFORM c59s14_fixture.ok((SELECT to_jsonb(l)=closed FROM private.workout_strength_lifecycles l WHERE user_id=u) AND r->>'deleted_rows'='0','true_repeat_preserves_closure');
END $variant$;
DO $variant$DECLARE u uuid:=c59s14_fixture.uid(102);p jsonb;draft uuid;before_state jsonb;other_state jsonb;r jsonb;closed jsonb;lower_bound timestamptz;plans boolean;BEGIN
 p:=c59s14_fixture.seed(102);draft:=c59s14_fixture.enrich(u);
 IF NOT EXISTS(SELECT 1 FROM public.users WHERE id=c59s14_fixture.uid(201)) THEN PERFORM c59s14_fixture.seed(201);END IF;
 other_state:=c59s14_fixture.state(c59s14_fixture.uid(201));before_state:=c59s14_fixture.state(u);lower_bound:=clock_timestamp();
 r:=public.reset_user_conversation_atomic(u,false);
 PERFORM c59s14_fixture.ok(r=jsonb_build_object('reset',true,'user_id',u,'deleted_rows',c59s14_fixture.deleted_count(before_state,false),'kept_plans',false),'false_exact_legacy_result_count');
 SELECT to_jsonb(l) INTO closed FROM private.workout_strength_lifecycles l WHERE user_id=u;
 PERFORM c59s14_fixture.ok((closed->>'closed_at')::timestamptz>=lower_bound AND (closed->>'closed_at')::timestamptz<=clock_timestamp()
 AND closed->>'close_operation_key' LIKE 'reset_user_conversation:%' AND (closed->>'close_operation_key')~'^reset_user_conversation:[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
 AND closed->>'lifecycle_key'=p->>'lifecycleKey' AND closed->>'opened_at'=(before_state#>>'{private.workout_strength_lifecycles,0,opened_at}'),'false_closed_postlock_once');
 PERFORM c59s14_fixture.ok(NOT EXISTS(SELECT 1 FROM public.workout_logs WHERE user_id=u) AND NOT EXISTS(SELECT 1 FROM private.workout_strength_facts WHERE user_id=u)
 AND NOT EXISTS(SELECT 1 FROM public.daily_snapshots WHERE user_id=u)
 AND (SELECT jsonb_agg(to_jsonb(c) ORDER BY to_jsonb(c)::text) FROM private.workout_strength_commands c WHERE user_id=u)=before_state->'private.workout_strength_commands'
 AND (SELECT jsonb_agg(to_jsonb(s) ORDER BY to_jsonb(s)::text) FROM private.workout_strength_calendar_scopes s WHERE user_id=u)=before_state->'private.workout_strength_calendar_scopes'
 AND (SELECT count(*)=2 AND bool_and(live_workout_log_id IS NULL) AND bool_and(original_workout_log_id=(p->>'workoutLogID')::uuid) FROM private.workout_strength_operations WHERE user_id=u)
 AND (SELECT answer_receipt=p->'receipt' FROM private.workout_strength_operations WHERE user_id=u AND operation_kind='answer'),'false_private_tombstones_no_live_facts');
 plans:=(SELECT metadata='{}'::jsonb FROM public.users WHERE id=u) AND NOT EXISTS(SELECT 1 FROM public.plan_drafts WHERE user_id=u) AND NOT EXISTS(SELECT 1 FROM public.training_plans WHERE user_id=u) AND NOT EXISTS(SELECT 1 FROM public.prescriptions WHERE user_id=u);
 PERFORM c59s14_fixture.ok(plans,'false_plans_metadata_real_confirmation');
 PERFORM c59s14_fixture.ok((SELECT wpp=before_state#>>'{user,wpp}' AND email=before_state#>>'{user,email}' AND timezone='UTC' AND country='US' AND status='active'
 AND name IS NULL AND NOT country_confirmed AND flow_phrase_cursor_revision=0 FROM public.users WHERE id=u)
 AND (SELECT NOT onboarding_completed AND onboarding_step=0 AND weight_kg IS NULL AND body_fat_percent IS NULL FROM public.user_profiles WHERE user_id=u)
 AND (SELECT xp_total=0 AND level=1 AND current_streak=0 AND deficit_block=0 AND current_weight IS NULL AND cardinality(badges_earned)=0 FROM public.user_progress WHERE user_id=u)
 AND (SELECT count(*)=1 FROM public.subscriptions WHERE user_id=u) AND (SELECT count(*)=1 FROM public.subscription_events WHERE user_id=u)
 AND c59s14_fixture.state(c59s14_fixture.uid(201))=other_state,'false_identity_profile_progress_billing_otherowner');
 r:=public.reset_user_conversation_atomic(u,false);
 PERFORM c59s14_fixture.ok((SELECT to_jsonb(l)=closed FROM private.workout_strength_lifecycles l WHERE user_id=u) AND r->>'deleted_rows'='0','false_repeat_preserves_closure');
END $variant$;
DO $variant$DECLARE u uuid:=c59s14_fixture.uid(103);p jsonb;draft uuid;before_state jsonb;other_state jsonb;r jsonb;closed jsonb;lower_bound timestamptz;plans boolean;BEGIN
 p:=c59s14_fixture.seed(103);draft:=c59s14_fixture.enrich(u);
 IF NOT EXISTS(SELECT 1 FROM public.users WHERE id=c59s14_fixture.uid(201)) THEN PERFORM c59s14_fixture.seed(201);END IF;
 other_state:=c59s14_fixture.state(c59s14_fixture.uid(201));before_state:=c59s14_fixture.state(u);lower_bound:=clock_timestamp();
 r:=public.reset_user_conversation_atomic(u);
 PERFORM c59s14_fixture.ok(r=jsonb_build_object('reset',true,'user_id',u,'deleted_rows',c59s14_fixture.deleted_count(before_state,true),'kept_plans',true),'wrapper_exact_legacy_result_count');
 SELECT to_jsonb(l) INTO closed FROM private.workout_strength_lifecycles l WHERE user_id=u;
 PERFORM c59s14_fixture.ok((closed->>'closed_at')::timestamptz>=lower_bound AND (closed->>'closed_at')::timestamptz<=clock_timestamp()
 AND closed->>'close_operation_key' LIKE 'reset_user_conversation:%' AND (closed->>'close_operation_key')~'^reset_user_conversation:[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
 AND closed->>'lifecycle_key'=p->>'lifecycleKey' AND closed->>'opened_at'=(before_state#>>'{private.workout_strength_lifecycles,0,opened_at}'),'wrapper_closed_postlock_once');
 PERFORM c59s14_fixture.ok(NOT EXISTS(SELECT 1 FROM public.workout_logs WHERE user_id=u) AND NOT EXISTS(SELECT 1 FROM private.workout_strength_facts WHERE user_id=u)
 AND NOT EXISTS(SELECT 1 FROM public.daily_snapshots WHERE user_id=u)
 AND (SELECT jsonb_agg(to_jsonb(c) ORDER BY to_jsonb(c)::text) FROM private.workout_strength_commands c WHERE user_id=u)=before_state->'private.workout_strength_commands'
 AND (SELECT jsonb_agg(to_jsonb(s) ORDER BY to_jsonb(s)::text) FROM private.workout_strength_calendar_scopes s WHERE user_id=u)=before_state->'private.workout_strength_calendar_scopes'
 AND (SELECT count(*)=2 AND bool_and(live_workout_log_id IS NULL) AND bool_and(original_workout_log_id=(p->>'workoutLogID')::uuid) FROM private.workout_strength_operations WHERE user_id=u)
 AND (SELECT answer_receipt=p->'receipt' FROM private.workout_strength_operations WHERE user_id=u AND operation_kind='answer'),'wrapper_private_tombstones_no_live_facts');
 plans:=(SELECT metadata='{"training_reminders":true,"training_delivery_hour":7}'::jsonb FROM public.users WHERE id=u) AND EXISTS(SELECT 1 FROM public.plan_drafts WHERE id=draft AND source_message_id IS NULL) AND EXISTS(SELECT 1 FROM public.prescriptions WHERE user_id=u) AND EXISTS(SELECT 1 FROM public.training_plans WHERE user_id=u AND active);r:=public.confirm_plan_draft_atomic(u,draft,1,NULL,'s14-confirm-after-reset');plans:=plans AND r->>'status'='confirmed';
 PERFORM c59s14_fixture.ok(plans,'wrapper_plans_metadata_real_confirmation');
 PERFORM c59s14_fixture.ok((SELECT wpp=before_state#>>'{user,wpp}' AND email=before_state#>>'{user,email}' AND timezone='UTC' AND country='US' AND status='active'
 AND name IS NULL AND NOT country_confirmed AND flow_phrase_cursor_revision=0 FROM public.users WHERE id=u)
 AND (SELECT NOT onboarding_completed AND onboarding_step=0 AND weight_kg IS NULL AND body_fat_percent IS NULL FROM public.user_profiles WHERE user_id=u)
 AND (SELECT xp_total=0 AND level=1 AND current_streak=0 AND deficit_block=0 AND current_weight IS NULL AND cardinality(badges_earned)=0 FROM public.user_progress WHERE user_id=u)
 AND (SELECT count(*)=1 FROM public.subscriptions WHERE user_id=u) AND (SELECT count(*)=1 FROM public.subscription_events WHERE user_id=u)
 AND c59s14_fixture.state(c59s14_fixture.uid(201))=other_state,'wrapper_identity_profile_progress_billing_otherowner');
 r:=public.reset_user_conversation_atomic(u);
 PERFORM c59s14_fixture.ok((SELECT to_jsonb(l)=closed FROM private.workout_strength_lifecycles l WHERE user_id=u) AND r->>'deleted_rows'='0','wrapper_repeat_preserves_closure');
END $variant$;
DO $no_life$DECLARE u uuid:=c59s14_fixture.owner(104,false);r jsonb;BEGIN
 r:=public.reset_user_conversation_atomic(u,false);
 PERFORM c59s14_fixture.ok(r=jsonb_build_object('reset',true,'user_id',u,'deleted_rows',0,'kept_plans',false) AND NOT EXISTS(SELECT 1 FROM private.workout_strength_lifecycles WHERE user_id=u),'no_life_no_automatic_open');
 u:=c59s14_fixture.owner(105);UPDATE public.users SET status='blocked' WHERE id=u;
 INSERT INTO private.workout_strength_lifecycles VALUES(u,c59s14_fixture.uid(2105),TIMESTAMPTZ '2026-09-01T00:00:00Z',TIMESTAMPTZ '2026-09-02T00:00:00Z','s14-prior-closed');
 r:=public.reset_user_conversation_atomic(u,true);
 PERFORM c59s14_fixture.ok(r->>'reset'='true' AND (SELECT status='blocked' FROM public.users WHERE id=u)
 AND (SELECT closed_at IS NOT NULL FROM private.workout_strength_lifecycles WHERE user_id=u AND lifecycle_key=c59s14_fixture.uid(1105))
 AND (SELECT closed_at=TIMESTAMPTZ '2026-09-02T00:00:00Z' AND close_operation_key='s14-prior-closed' FROM private.workout_strength_lifecycles WHERE user_id=u AND lifecycle_key=c59s14_fixture.uid(2105)),'inactive_existing_owner_reset_no_new_active_guard');
END $no_life$;
DO $future$DECLARE u uuid:=c59s14_fixture.owner(106);s jsonb;r jsonb;BEGIN
 UPDATE private.workout_strength_lifecycles SET opened_at='infinity'::timestamptz WHERE user_id=u;
 s:=c59s14_fixture.state(u);r:=c59s14_fixture.attempt(format('SELECT public.reset_user_conversation_atomic(%L::uuid,true)',u));
 PERFORM c59s14_fixture.ok(r='{"ok":false,"sqlstate":"23514"}'::jsonb AND c59s14_fixture.state(u)=s,'closure_constraint_failure_rolls_back_whole_reset');
END $future$;
DO $fault_seed$DECLARE p jsonb;BEGIN p:=c59s14_fixture.seed(107);PERFORM c59s14_fixture.enrich((p->>'ownerID')::uuid);END $fault_seed$;
DO $$BEGIN IF EXISTS(SELECT 1 FROM pg_trigger WHERE tgrelid='public.workout_logs'::regclass AND tgname='c59s14_after_close_fault') THEN RAISE EXCEPTION 'C59S14_SETUP_TRIGGER_COLLISION';END IF;END$$;
CREATE TRIGGER c59s14_after_close_fault BEFORE DELETE ON public.workout_logs FOR EACH ROW EXECUTE FUNCTION c59s14_fixture.fail_after_close();
DO $late_fault$DECLARE u uuid:=c59s14_fixture.uid(107);s jsonb:=c59s14_fixture.state(u);error_state text;error_message text;BEGIN
 BEGIN
  PERFORM public.reset_user_conversation_atomic(u,false);
 EXCEPTION WHEN OTHERS THEN
  GET STACKED DIAGNOSTICS error_state=RETURNED_SQLSTATE,error_message=MESSAGE_TEXT;
 END;
 PERFORM c59s14_fixture.ok(error_state='P0001' AND error_message='C59S14_INJECTED_AFTER_CLOSE_AND_EARLY_DELETE'
 AND c59s14_fixture.state(u)=s,'failure_after_close_and_early_deletes_reverts_everything');
END $late_fault$;
DROP TRIGGER c59s14_after_close_fault ON public.workout_logs;
DO $correction$DECLARE p jsonb:=c59s14_fixture.seed(108);u uuid:=(p->>'ownerID')::uuid;l uuid:=(p->>'lifecycleKey')::uuid;r jsonb;new_id uuid;s jsonb;BEGIN
 r:=public.register_workout_atomic(u,DATE '2026-10-13','C59S14 adjacent',30,222,NULL,NULL,TIMESTAMPTZ '2026-10-13T13:00:00Z','s14-adjacent',2000,150,false,NULL);
 r:=public.register_workout_atomic(u,DATE '2026-10-13',p->>'originalType',80,400,NULL,NULL,TIMESTAMPTZ '2026-10-13T14:00:00Z','s14-correction',2000,150,true,TIMESTAMPTZ '2026-10-01T00:00:00Z');new_id:=(r->>'workout_log_id')::uuid;
 PERFORM c59s14_fixture.ok(r->>'inserted'='true' AND r->>'replaced_count'='1' AND new_id<>(p->>'workoutLogID')::uuid
 AND NOT EXISTS(SELECT 1 FROM private.workout_strength_facts WHERE user_id=u AND workout_log_id IN(new_id,(p->>'workoutLogID')::uuid))
 AND (SELECT count(*)=2 AND bool_and(live_workout_log_id IS NULL) AND bool_and(original_workout_log_id=(p->>'workoutLogID')::uuid) FROM private.workout_strength_operations WHERE user_id=u),'real_legacy_correction_fresh_UUID_no_answer_transfer');
 s:=c59s14_fixture.state(u);
 r:=public.resolve_confirmed_workout_strength_capture(u,l,p->>'captureKey',p->>'originalType');
 PERFORM c59s14_fixture.ok(r='{"status":"forbidden","reason":"stale_workout"}'::jsonb,'correction_old_resolve_stale_before_replay');
 r:=c59s14_fixture.answer(p);PERFORM c59s14_fixture.ok(r='{"status":"forbidden","reason":"stale_workout"}'::jsonb,'correction_old_answer_stale_before_replay');
 r:=c59s14_fixture.capture(u,l,p->>'captureKey',p->>'originalType');
 PERFORM c59s14_fixture.ok(r='{"legacy_result":null,"strength":{"status":"forbidden","reason":"stale_workout"}}'::jsonb AND c59s14_fixture.state(u)=s,'correction_capture_replay_no_6h_rebind_or_resurrection');
 PERFORM c59s14_fixture.ok((SELECT exercise_calories=0 AND NOT training_done FROM public.daily_snapshots WHERE user_id=u AND date=DATE '2026-10-12')
 AND (SELECT exercise_calories=622 AND training_done FROM public.daily_snapshots WHERE user_id=u AND date=DATE '2026-10-13'),'correction_official_both_snapshot_totals_preserved');
END $correction$;
DO $stale$DECLARE p jsonb:=c59s14_fixture.seed(109);u uuid:=(p->>'ownerID')::uuid;l uuid:=(p->>'lifecycleKey')::uuid;s jsonb;r jsonb;BEGIN
 PERFORM public.reset_user_conversation_atomic(u,true);s:=c59s14_fixture.state(u);
 r:=c59s14_fixture.capture(u,l,p->>'captureKey',p->>'originalType');
 PERFORM c59s14_fixture.ok(r='{"legacy_result":null,"strength":{"status":"forbidden","reason":"stale_lifecycle"}}'::jsonb,'reset_old_capture_life_before_replay_no_legacy_fallback');
 r:=c59s14_fixture.answer(p);PERFORM c59s14_fixture.ok(r='{"status":"forbidden","reason":"stale_lifecycle"}'::jsonb,'reset_old_answer_life_before_receipt_replay');
 r:=public.resolve_confirmed_workout_strength_capture(u,l,p->>'captureKey',p->>'originalType');
 PERFORM c59s14_fixture.ok(r='{"status":"forbidden","reason":"stale_lifecycle"}'::jsonb,'reset_old_resolve_life_before_tombstone');
 r:=public.get_confirmed_workouts_for_strength_week(u,l,(p#>>'{scope,scopeKey}')::uuid,p#>>'{scope,timeZone}',(p#>>'{scope,weekStartDate}')::date,(p#>>'{scope,asOfLocalDate}')::date);
 PERFORM c59s14_fixture.ok(r='{"status":"unavailable","reason":"calendar_unproved","workouts":null}'::jsonb AND c59s14_fixture.state(u)=s,'reset_old_scope_denied_all_stale_reads_no_mutation');
END $stale$;
DO $soft$DECLARE p jsonb:=c59s14_fixture.seed(110);u uuid:=(p->>'ownerID')::uuid;l uuid:=(p->>'lifecycleKey')::uuid;s jsonb;r jsonb;BEGIN
 UPDATE public.users SET status='deleted' WHERE id=u;s:=c59s14_fixture.state(u);
 r:=c59s14_fixture.attempt(format('SELECT c59s14_fixture.capture(%L::uuid,%L::uuid,%L,%L)',u,l,p->>'captureKey',p->>'originalType'));
 PERFORM c59s14_fixture.ok(r='{"ok":false,"sqlstate":"P0002"}'::jsonb,'soft_deleted_capture_denied_actual_owner_guard');
 r:=c59s14_fixture.attempt(format('SELECT c59s14_fixture.answer(%L::jsonb)',p));
 PERFORM c59s14_fixture.ok(r='{"ok":false,"sqlstate":"P0002"}'::jsonb AND c59s14_fixture.state(u)=s AND EXISTS(SELECT 1 FROM public.workout_logs WHERE user_id=u),'soft_deleted_answer_denied_data_retained_no_global_legacy_claim');
END $soft$;
DO $acl$DECLARE allowed boolean;BEGIN
 SELECT bool_and(has_function_privilege('service_role',p.oid,'EXECUTE')
 AND NOT EXISTS(SELECT 1 FROM aclexplode(coalesce(p.proacl,acldefault('f',p.proowner))) a WHERE a.privilege_type='EXECUTE' AND a.grantee NOT IN(p.proowner,'service_role'::regrole::oid))) INTO allowed
 FROM pg_proc p WHERE p.oid IN('public.reset_user_conversation_atomic(uuid)'::regprocedure,'public.reset_user_conversation_atomic(uuid,boolean)'::regprocedure);
 PERFORM c59s14_fixture.ok(allowed AND NOT has_function_privilege('anon','public.reset_user_conversation_atomic(uuid)','EXECUTE') AND NOT has_function_privilege('authenticated','public.reset_user_conversation_atomic(uuid,boolean)','EXECUTE'),'both_reset_signatures_only_owner_service_EXECUTE');
END $acl$;
DO $args$DECLARE a jsonb;b jsonb;BEGIN
 a:=c59s14_fixture.attempt('SELECT public.reset_user_conversation_atomic(NULL::uuid,true)');
 b:=c59s14_fixture.attempt('SELECT public.reset_user_conversation_atomic(''c59ae000-0000-0000-0000-000000000201''::uuid,NULL::boolean)');
 PERFORM c59s14_fixture.ok(a='{"ok":false,"sqlstate":"22023"}'::jsonb AND b=a,'null_reset_args_rejected_before_state');
END $args$;
SET LOCAL request.jwt.claims='{"role":"authenticated"}';
DO $guard$DECLARE r jsonb;BEGIN r:=c59s14_fixture.attempt('SELECT public.reset_user_conversation_atomic(''c59ae000-0000-0000-0000-000000000201''::uuid,true)');
 PERFORM c59s14_fixture.ok(r='{"ok":false,"sqlstate":"42501"}'::jsonb,'actual_trusted_backend_guard_rejects_authenticated_claim');END $guard$;
SET LOCAL request.jwt.claims='{"role":"service_role"}';
SELECT c59s14_fixture.object_fingerprint() AS after_fingerprint
\gset s14_
SELECT c59s14_fixture.ok(:'s14_after_fingerprint'::jsonb=:'s14_fingerprint'::jsonb,'fullseq_no_product_schema_ACL_or_trigger_drift');
ROLLBACK;
\echo C59S14_ROLLBACK_CONFIRMED
\endif
\endif
\endif
