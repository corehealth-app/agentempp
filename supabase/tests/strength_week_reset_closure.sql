-- Local retained C5 regression: Y installed and reset candidate applied; all scenarios roll back.
-- No permanent fixture install, implicit COMMIT, product replacement, or sequence nextval.
\set ON_ERROR_STOP on
\set VERBOSITY verbose
BEGIN ISOLATION LEVEL READ COMMITTED;
SET LOCAL statement_timeout='30s';
SET LOCAL lock_timeout='10s';
SET LOCAL ROLE NONE;
SET LOCAL request.jwt.claims='{"role":"service_role"}';
SET LOCAL TimeZone='UTC';
\ir fixtures/strength_week_reset_closure_fixture.sql
SELECT c59ry_fixture.sequences() AS before_sequences \gset c59ry_

DO $variants$
DECLARE
  variant text;i integer;keep boolean;p jsonb;u uuid;r jsonb;again jsonb;
  before_state jsonb;after_state jsonb;control_before jsonb;closed jsonb;prior jsonb;
  lower_bound timestamptz;expected_deleted bigint;
BEGIN
  PERFORM c59ry_fixture.seed(201);
  control_before:=c59ry_fixture.state(c59ry_fixture.uid(201));
  FOREACH variant IN ARRAY ARRAY['keep','remove','wrapper'] LOOP
    i:=CASE variant WHEN 'keep' THEN 101 WHEN 'remove' THEN 102 ELSE 103 END;
    keep:=variant<>'remove';p:=c59ry_fixture.seed(i);u:=(p->>'owner')::uuid;
    before_state:=c59ry_fixture.state(u);expected_deleted:=c59ry_fixture.deleted_count(u,keep);
    SELECT to_jsonb(s) INTO prior FROM private.strength_week_scopes s
      WHERE user_id=u AND generation=(p->>'prior')::uuid;
    lower_bound:=clock_timestamp();
    r:=CASE WHEN variant='wrapper' THEN public.reset_user_conversation_atomic(u)
      ELSE public.reset_user_conversation_atomic(u,keep) END;
    SELECT to_jsonb(s) INTO closed FROM private.strength_week_scopes s
      WHERE user_id=u AND generation=(p->>'generation')::uuid;
    after_state:=c59ry_fixture.state(u);
    PERFORM c59ry_fixture.ok(r=jsonb_build_object('reset',true,'user_id',u,
      'deleted_rows',expected_deleted,'kept_plans',keep),variant||'_exact_legacy_result_count');
    PERFORM c59ry_fixture.ok((closed->>'closed_at')::timestamptz>=lower_bound
      AND (closed->>'closed_at')::timestamptz<=clock_timestamp()
      AND (SELECT count(*)=2 AND count(*) FILTER(WHERE closed_at IS NULL)=0
        FROM private.strength_week_scopes WHERE user_id=u)
      AND (closed-'closed_at')=(SELECT to_jsonb(s)-'closed_at'
        FROM jsonb_to_recordset(before_state->'private.strength_week_scopes')
        AS s(user_id uuid,generation uuid,predecessor_generation uuid,
          open_operation_namespace text,open_operation_key text,opened_at timestamptz,closed_at timestamptz)
        WHERE generation=(p->>'generation')::uuid),variant||'_only_existing_Y_closed_postlock');
    PERFORM c59ry_fixture.ok((SELECT to_jsonb(s)=prior FROM private.strength_week_scopes s
      WHERE user_id=u AND generation=(p->>'prior')::uuid)
      AND after_state->'private.strength_week_source_versions'=before_state->'private.strength_week_source_versions'
      AND after_state->'private.strength_week_targets'=before_state->'private.strength_week_targets',
      variant||'_prior_scope_receipts_and_targets_preserved');
    PERFORM c59ry_fixture.ok((SELECT EXISTS(SELECT 1 FROM public.training_plans
      WHERE id=(p->>'plan')::uuid))=keep
      AND (SELECT metadata=CASE WHEN keep THEN
        '{"training_reminders":true,"training_delivery_hour":7}'::jsonb ELSE '{}'::jsonb END
        AND status='active' AND flow_phrase_cursor_revision=0 FROM public.users WHERE id=u)
      AND (SELECT NOT onboarding_completed AND onboarding_step=0
        AND weight_kg IS NULL AND training_frequency IS NULL FROM public.user_profiles WHERE user_id=u),
      variant||'_plans_profile_metadata_legacy_semantics');
    PERFORM c59ry_fixture.ok((SELECT epoch<>(p->>'epoch')::uuid AND current_lifecycle_key IS NULL
        FROM private.workout_strength_authority_epochs WHERE user_id=u)
      AND (SELECT closed_at IS NOT NULL FROM private.workout_strength_lifecycles
        WHERE user_id=u AND lifecycle_key=(p->>'life')::uuid)
      AND after_state->'private.workout_strength_request_admissions'=before_state->'private.workout_strength_request_admissions',
      variant||'_S15_epoch_lifecycle_and_old_admissions_preserved');
    PERFORM c59ry_fixture.ok(c59ry_fixture.state(c59ry_fixture.uid(201))=control_before,
      variant||'_other_owner_unchanged');
    again:=CASE WHEN variant='wrapper' THEN public.reset_user_conversation_atomic(u)
      ELSE public.reset_user_conversation_atomic(u,keep) END;
    PERFORM c59ry_fixture.ok(again=jsonb_build_object('reset',true,'user_id',u,
      'deleted_rows',0,'kept_plans',keep)
      AND (SELECT to_jsonb(s)=closed FROM private.strength_week_scopes s
        WHERE user_id=u AND generation=(p->>'generation')::uuid)
      AND (SELECT count(*)=2 FROM private.strength_week_scopes WHERE user_id=u),
      variant||'_repeat_no_reopen_or_retimestamp');
  END LOOP;
END $variants$;

DO $old_generation$
DECLARE p jsonb:=c59ry_fixture.seed(104);u uuid:=(p->>'owner')::uuid;
  g uuid:=(p->>'generation')::uuid;r jsonb;s jsonb;
BEGIN
  PERFORM public.reset_user_conversation_atomic(u,true);s:=c59ry_fixture.state(u);
  r:=private.get_mobile_strength_week_context_at(u,'2026-10-12T12:00:00Z');
  PERFORM c59ry_fixture.ok(r='{"status":"unavailable","reason":"missing_scope"}'::jsonb,
    'old_Y_read_missing_scope_no_auto_bootstrap');
  r:=c59ry_fixture.attempt(format('SELECT private.capture_strength_week_source_at(%L::uuid,%L::uuid,''informed_frequency'',''value'',4::smallint,NULL::uuid,NULL::timestamptz,''c59ry.fixture'',%L,''2026-10-08T12:00:00.654321Z''::timestamptz)',
    u,g,'reset-y-frequency-104'));
  PERFORM c59ry_fixture.ok(r->>'ok'='false' AND r->>'sqlstate'='40001'
    AND r->>'message'='strength_week_generation_changed','old_Y_source_receipt_replay_rejected_before_reuse');
  r:=private.freeze_mobile_strength_week_target_at(u,g,'UTC','2026-10-12',p->'proof',p->'proposal',
    '2026-10-12T12:00:00Z');
  PERFORM c59ry_fixture.ok(r='{"status":"conflict","reason":"generation_changed"}'::jsonb,
    'old_Y_frozen_target_replay_rejected_before_reuse');
  r:=c59ry_fixture.attempt(format('SELECT private.open_strength_week_scope(%L::uuid,''c59ry.fixture'',''reset-y-current-104'')',u));
  PERFORM c59ry_fixture.ok(r->>'ok'='false' AND r->>'sqlstate'='40001'
    AND r->>'message'='strength_week_operation_conflict','old_Y_roll_origin_not_readmitted_as_initial_open');
  r:=c59ry_fixture.attempt(format('SELECT private.roll_strength_week_scope(%L::uuid,%L::uuid,''c59ry.fixture'',''reset-y-no-new-generation-104'')',u,g));
  PERFORM c59ry_fixture.ok(r->>'ok'='false' AND r->>'sqlstate'='40001'
    AND r->>'message'='strength_week_generation_changed','old_Y_new_roll_key_not_adopted');
  PERFORM c59ry_fixture.ok(c59ry_fixture.state(u)=s,'old_Y_rejections_preserve_all_owner_state');
END $old_generation$;

DO $inactive_and_absent$
DECLARE p jsonb;u uuid;r jsonb;n bigint;closed jsonb;
BEGIN
  p:=c59ry_fixture.seed(105);u:=(p->>'owner')::uuid;
  UPDATE public.users SET status='blocked' WHERE id=u;
  n:=c59ry_fixture.deleted_count(u,true);
  r:=public.reset_user_conversation_atomic(u,true);
  PERFORM c59ry_fixture.ok(r=jsonb_build_object('reset',true,'user_id',u,'deleted_rows',n,'kept_plans',true)
    AND (SELECT status='blocked' FROM public.users WHERE id=u)
    AND (SELECT closed_at IS NOT NULL FROM private.strength_week_scopes
      WHERE user_id=u AND generation=(p->>'generation')::uuid),
    'inactive_existing_owner_reset_keeps_legacy_acceptance');
  p:=c59ry_fixture.seed(106,false);u:=(p->>'owner')::uuid;
  n:=c59ry_fixture.deleted_count(u,false);r:=public.reset_user_conversation_atomic(u,false);
  PERFORM c59ry_fixture.ok(r=jsonb_build_object('reset',true,'user_id',u,'deleted_rows',n,'kept_plans',false)
    AND NOT EXISTS(SELECT 1 FROM private.strength_week_scopes WHERE user_id=u)
    AND NOT EXISTS(SELECT 1 FROM private.strength_week_source_versions WHERE user_id=u)
    AND NOT EXISTS(SELECT 1 FROM private.strength_week_targets WHERE user_id=u),
    'no_Y_update_zero_rows_never_opens_or_seeds_Y');
END $inactive_and_absent$;

DO $future$
DECLARE p jsonb:=c59ry_fixture.seed(301);u uuid:=(p->>'owner')::uuid;s jsonb;r jsonb;
BEGIN
  UPDATE private.strength_week_scopes SET opened_at='9999-01-01T00:00:00Z'
    WHERE user_id=u AND generation=(p->>'generation')::uuid;
  s:=c59ry_fixture.state(u);
  r:=c59ry_fixture.attempt(format('SELECT public.reset_user_conversation_atomic(%L::uuid,false)',u));
  PERFORM c59ry_fixture.ok(r->>'ok'='false' AND r->>'sqlstate'='23514'
    AND c59ry_fixture.state(u)=s,'future_Y_close_CHECK_failure_rolls_back_entire_reset');
END $future$;

DO $late_seed$ BEGIN PERFORM c59ry_fixture.seed(302); END $late_seed$;
CREATE TRIGGER c59ry_after_y_fault BEFORE DELETE ON public.workout_logs
  FOR EACH ROW EXECUTE FUNCTION c59ry_fixture.fail_after_y_close();
DO $late_fault$
DECLARE u uuid:=c59ry_fixture.uid(302);s jsonb:=c59ry_fixture.state(u);r jsonb;
BEGIN
  r:=c59ry_fixture.attempt(format('SELECT public.reset_user_conversation_atomic(%L::uuid,false)',u));
  PERFORM c59ry_fixture.ok(r->>'ok'='false' AND r->>'sqlstate'='P0001'
    AND r->>'message'='C59RY_INJECTED_AFTER_Y_EPOCH_LIFE_AND_EARLY_DELETE'
    AND c59ry_fixture.state(u)=s,'late_failure_after_Y_epoch_life_and_deletes_rolls_back_all');
END $late_fault$;

SELECT c59ry_fixture.ok(c59ry_fixture.sequences()=:'c59ry_before_sequences'::jsonb,
  'all_public_private_sequence_state_unchanged');
ROLLBACK;
\echo C59RY_GREEN_ROLLBACK_CONFIRMED
