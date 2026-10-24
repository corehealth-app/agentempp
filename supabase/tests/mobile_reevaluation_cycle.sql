\set ON_ERROR_STOP on
BEGIN ISOLATION LEVEL READ COMMITTED;
SET LOCAL statement_timeout = '30s';
SET LOCAL lock_timeout = '5s';
SET LOCAL request.jwt.claims = '{"role":"service_role"}';
SET LOCAL TimeZone = 'UTC';
\ir fixtures/mobile_reevaluation_cycle_fixture.sql

DO $golden$
DECLARE a uuid; d jsonb; before_state jsonb;
BEGIN
  a := m3b_cycle_test.seed(1,'2026-10-01T23:00:00Z');
  before_state := m3b_cycle_test.original_state(a);
  d := private.mobile_reevaluation_clock_at(a,'2026-10-15T02:59:59Z');
  PERFORM m3b_cycle_test.ok(d->>'unavailable_reason'='not_due'
    AND d->'clock'='{"base_date":"2026-10-01","due_date":"2026-10-15","timezone":"America/Sao_Paulo"}'::jsonb,
    'signup_20h_due_at_civil_day14_not_336_hours');
  d := private.mobile_reevaluation_clock_at(a,'2026-10-15T03:00:00Z');
  PERFORM m3b_cycle_test.ok(d->>'availability'='available' AND d->'unavailable_reason'='null'
    AND d->'cycle'='null','available_exactly_at_local_midnight_no_implicit_cycle');
  d := private.mobile_reevaluation_clock_at(a,'2026-11-22T03:00:00Z');
  PERFORM m3b_cycle_test.ok(d#>>'{clock,due_date}'='2026-10-15'
    AND d->'cycle'='null','late_does_not_catch_up_or_create_cycles');
  PERFORM public.get_mobile_reevaluation_cycle(a);
  PERFORM m3b_cycle_test.ok((SELECT count(*)=0 FROM private.mobile_reevaluation_cycles WHERE user_id=a)
    AND m3b_cycle_test.original_state(a)=before_state,'GET_and_clock_preserve_all_original_rows');
  -- Pure civil-calendar contract for the future completion writer; no conclusion is simulated.
  a := m3b_cycle_test.seed(2,'2026-10-18T23:00:00Z');
  PERFORM m3b_cycle_test.ok(private.mobile_reevaluation_clock_at(a,'2026-11-01T03:00:00Z')
    #>>'{clock,due_date}'='2026-11-01','base_18Oct_gives_01Nov_without_claiming_completion');
  a := m3b_cycle_test.seed(3,'2026-03-02T01:00:00Z','America/New_York');
  PERFORM m3b_cycle_test.ok(private.mobile_reevaluation_clock_at(a,'2026-03-15T03:59:59Z')
    ->>'unavailable_reason'='not_due','DST_day14_before_midnight');
  PERFORM m3b_cycle_test.ok(private.mobile_reevaluation_clock_at(a,'2026-03-15T04:00:00Z')
    ->>'availability'='available','DST_uses_new_offset_at_midnight');
END $golden$;

DO $origins$
DECLARE a uuid; d jsonb;
BEGIN
  a := m3b_cycle_test.seed(4,NULL);
  PERFORM m3b_cycle_test.ok(public.get_mobile_reevaluation_cycle(a)->>'unavailable_reason'
    ='onboarding_incomplete','incomplete_signup_not_initialized');
  a := m3b_cycle_test.seed(5,'2026-10-01T23:00:00Z','America/Sao_Paulo',false);
  PERFORM m3b_cycle_test.ok(public.get_mobile_reevaluation_cycle(a)->>'unavailable_reason'
    ='anchor_unproven','legacy_timestamp_without_receipt_not_imported');
  INSERT INTO public.reevaluations(user_id,evaluation_date) VALUES(a,'2026-10-22');
  PERFORM m3b_cycle_test.ok(public.get_mobile_reevaluation_cycle(a)->>'unavailable_reason'
    ='anchor_unproven','untyped_legacy_reevaluation_not_FULL_proof');
  a := m3b_cycle_test.seed(6,'2026-10-01T23:00:00Z');
  UPDATE public.users SET timezone='Asia/Tokyo' WHERE id=a;
  d := private.mobile_reevaluation_clock_at(a,'2026-10-15T02:59:59Z');
  PERFORM m3b_cycle_test.ok(d#>>'{clock,timezone}'='America/Sao_Paulo'
    AND d->>'unavailable_reason'='not_due','historical_origin_not_reinterpreted_in_mutable_profile_zone');
  a := m3b_cycle_test.seed(7,'2026-10-01T23:00:00Z');
  UPDATE public.users SET status='blocked' WHERE id=a;
  PERFORM m3b_cycle_test.throws(format('SELECT public.get_mobile_reevaluation_cycle(%L)',a),
    'P0002','inactive_owner_rejected');
  PERFORM m3b_cycle_test.throws('SELECT public.get_mobile_reevaluation_cycle(NULL)',
    '22023','null_owner_rejected');
  PERFORM m3b_cycle_test.throws(format('SELECT private.mobile_reevaluation_clock_at(%L,''infinity'')',
    m3b_cycle_test.uid(1)),'22023','invalid_observed_clock_rejected');
END $origins$;

DO $start_replay$
DECLARE a uuid; b uuid; d jsonb; again jsonb; state_a jsonb; state_b jsonb;
  key_id uuid := 'b3b01000-1000-4000-8000-000000000001';
BEGIN
  a := m3b_cycle_test.seed(8,'2026-10-01T23:00:00Z');
  b := m3b_cycle_test.seed(9,'2026-10-01T23:00:00Z');
  state_a:=m3b_cycle_test.original_state(a);state_b:=m3b_cycle_test.original_state(b);
  d:=public.start_mobile_reevaluation_cycle(a,key_id);
  again:=public.start_mobile_reevaluation_cycle(a,key_id);
  PERFORM m3b_cycle_test.ok(d=again AND d#>>'{cycle,kind}'='REGULAR'
    AND d#>>'{cycle,status}'='open' AND d#>>'{cycle,revision}'='1','same_key_replays_one_cycle');
  again:=public.start_mobile_reevaluation_cycle(a,gen_random_uuid());
  PERFORM m3b_cycle_test.ok(d=again AND (SELECT count(*)=1 FROM private.mobile_reevaluation_cycles
    WHERE user_id=a),'different_start_key_resumes_same_open_cycle');
  again:=public.start_mobile_reevaluation_cycle(b,key_id);
  PERFORM m3b_cycle_test.ok(d#>>'{cycle,id}'<>again#>>'{cycle,id}'
    AND m3b_cycle_test.original_state(a)=state_a AND m3b_cycle_test.original_state(b)=state_b,
    'same_key_other_owner_isolated_and_all_original_rows_preserved');
  UPDATE private.mobile_reevaluation_cycles SET revision=9007199254740993 WHERE user_id=a;
  PERFORM m3b_cycle_test.ok(public.get_mobile_reevaluation_cycle(a)#>'{cycle,revision}'
    ='"9007199254740993"'::jsonb,'bigint_revision_is_exact_decimal_string');
  UPDATE public.users SET timezone='Europe/London' WHERE id=a;
  PERFORM m3b_cycle_test.ok(public.get_mobile_reevaluation_cycle(a)#>>'{cycle,timezone_at_open}'
    ='America/Sao_Paulo','opened_cycle_keeps_origin_zone');
  PERFORM m3b_cycle_test.throws(format('SELECT public.start_mobile_reevaluation_cycle(%L,NULL)',a),
    '22023','null_idempotency_key_rejected');
  -- Exercise real reset: its historical receipt remains, but cannot authorize the old cycle.
  PERFORM public.reset_user_conversation_atomic(a,true);
  PERFORM m3b_cycle_test.ok(public.get_mobile_reevaluation_cycle(a)->>'unavailable_reason'
    ='onboarding_incomplete','real_reset_does_not_restore_old_cycle');
  PERFORM m3b_cycle_test.throws(format('SELECT public.start_mobile_reevaluation_cycle(%L,%L)',a,key_id),
    '40001','consumed_key_after_reset_rejected');
END $start_replay$;

DO $catalog$
DECLARE valid boolean;
BEGIN
  SELECT bool_and(c.relrowsecurity AND c.relowner='postgres'::regrole
    AND NOT EXISTS(SELECT 1 FROM aclexplode(coalesce(c.relacl,acldefault('r',c.relowner))) x
      WHERE x.grantee<>c.relowner)) INTO valid FROM pg_class c
    WHERE c.oid IN('private.mobile_reevaluation_cycles'::regclass,
      'private.mobile_reevaluation_start_keys'::regclass);
  PERFORM m3b_cycle_test.ok(valid,'new_tables_owner_only_RLS');
  SELECT bool_and(p.prosecdef AND p.proconfig=ARRAY['search_path=pg_catalog']
    AND has_function_privilege('service_role',p.oid,'EXECUTE')
    AND NOT has_function_privilege('authenticated',p.oid,'EXECUTE')
    AND NOT has_function_privilege('anon',p.oid,'EXECUTE')) INTO valid FROM pg_proc p
    WHERE p.oid IN('public.get_mobile_reevaluation_cycle(uuid)'::regprocedure,
      'public.start_mobile_reevaluation_cycle(uuid,uuid)'::regprocedure);
  PERFORM m3b_cycle_test.ok(valid,'RPC_service_only_fixed_path');
  PERFORM m3b_cycle_test.ok(NOT has_function_privilege('service_role',
    'private.mobile_reevaluation_clock_at(uuid,timestamp with time zone)','EXECUTE'),
    'explicit_clock_not_exposed_to_service');
  PERFORM m3b_cycle_test.ok(NOT has_function_privilege('service_role',
    'private.start_mobile_reevaluation_cycle_at(uuid,uuid,timestamp with time zone)','EXECUTE'),
    'explicit_start_clock_not_exposed_to_service');
  PERFORM set_config('request.jwt.claims','{"role":"authenticated"}',true);
  PERFORM m3b_cycle_test.throws(format('SELECT public.get_mobile_reevaluation_cycle(%L)',
    m3b_cycle_test.uid(9)),'42501','foreign_owner_untrusted_claim_rejected');
END $catalog$;

SET LOCAL request.jwt.claims = '{"role":"service_role"}';
DO $not_due_and_corruption$
DECLARE a uuid; d jsonb; b uuid;
BEGIN
  a:=m3b_cycle_test.seed(10,clock_timestamp());
  d:=public.start_mobile_reevaluation_cycle(a,gen_random_uuid());
  PERFORM m3b_cycle_test.ok(d->>'unavailable_reason'='not_due'
    AND NOT EXISTS(SELECT 1 FROM private.mobile_reevaluation_cycles WHERE user_id=a)
    AND NOT EXISTS(SELECT 1 FROM private.mobile_reevaluation_start_keys WHERE user_id=a),
    'early_start_has_no_operational_effect');
  a:=m3b_cycle_test.seed(11,'2026-10-01T23:00:00Z');
  b:=m3b_cycle_test.seed(12,'2026-10-01T23:00:00Z');
  d:=public.start_mobile_reevaluation_cycle(a,gen_random_uuid());
  PERFORM m3b_cycle_test.throws(format('UPDATE private.mobile_reevaluation_cycles SET user_id=%L WHERE cycle_id=%L',
    b,d#>>'{cycle,id}'),'23503','cycle_cannot_reassign_to_foreign_receipt_owner');
  UPDATE private.mobile_reevaluation_cycles SET signup_epoch=gen_random_uuid() WHERE user_id=a;
  PERFORM m3b_cycle_test.throws(format('SELECT public.get_mobile_reevaluation_cycle(%L)',a),
    'XX001','corrupt_cycle_origin_is_an_error_not_unavailable_fallback');
  UPDATE private.mobile_reevaluation_cycles SET signup_epoch=(SELECT epoch FROM private.workout_strength_authority_epochs
    WHERE user_id=a),status='completed',completed_at=opened_at WHERE user_id=a;
  PERFORM m3b_cycle_test.throws(format('SELECT public.get_mobile_reevaluation_cycle(%L)',a),
    'XX001','bare_completed_status_is_not_typed_FULL_receipt');
END $not_due_and_corruption$;

-- Neighbor regression through the real signup writer, not the seeded historic receipt.
DO $real_signup_neighbor$
DECLARE a uuid; observation jsonb; admission jsonb; submission jsonb; completed jsonb; before_state jsonb;
  body text := 'M3B local synthetic document, no external legal acceptance.'; digest text;
BEGIN
  a:=m3b_cycle_test.seed(13,NULL);digest:=encode(extensions.digest(body,'sha256'),'hex');
  INSERT INTO public.onboarding_legal_documents(id,document_key,version,locale,body,content_hash,
    purpose,action_type,required,effective_at)
    VALUES(m3b_cycle_test.uid(201),'m3b_local_test','m3b-local-1','pt-BR',body,digest,
      'synthetic_local_test','acceptance',true,clock_timestamp()-interval '1 second');
  PERFORM public.publish_onboarding_legal_document(m3b_cycle_test.uid(201));
  INSERT INTO public.onboarding_legal_requirement_sets(id,version,locale,document_keys,effective_at)
    VALUES(m3b_cycle_test.uid(202),'m3b-local-1','pt-BR',ARRAY['m3b_local_test'],clock_timestamp()-interval '1 second');
  PERFORM public.publish_onboarding_legal_requirement_set(m3b_cycle_test.uid(202));
  submission:=jsonb_build_object('name','M3B synthetic QA','locale','pt-BR','country','BR',
    'timezone','America/Sao_Paulo','sex','masculino','birth_date','1990-01-01','height_cm',180,
    'weight_kg',80,'body_fat_percent',24,'objective','recomposicao','activity_level','moderado',
    'training_frequency',4,'hunger_level','moderada','wake_time','07:00','bedtime','23:00',
    'food_organization','sim','persona','focus','document_actions',jsonb_build_array(jsonb_build_object(
      'document_key','m3b_local_test','version','m3b-local-1','locale','pt-BR','content_hash',digest,'action','acceptance')));
  observation:=public.observe_mobile_signup_strength_epoch(a);
  admission:=public.admit_mobile_signup_strength_request(a,'m3b-real-signup',repeat('b',64),
    (observation#>>'{observation,epoch}')::uuid)->'admission';
  completed:=public.complete_mobile_onboarding_keyed(a,submission,'atomic','m3b-real-signup',repeat('b',64),
    (admission->>'epoch')::uuid,(admission->>'admissionID')::uuid,NULL,NULL,NULL,NULL);
  PERFORM m3b_cycle_test.ok(completed->'onboarding_completed'='true'
    AND (SELECT water_intake IS NULL FROM public.user_profiles WHERE user_id=a),
    'real_signup_still_completes_without_water_question');
  before_state:=m3b_cycle_test.original_state(a);
  PERFORM m3b_cycle_test.ok(public.get_mobile_reevaluation_cycle(a)->>'unavailable_reason'='not_due'
    AND public.complete_mobile_onboarding_keyed(a,submission,'atomic','m3b-real-signup',repeat('b',64),
      (admission->>'epoch')::uuid,(admission->>'admissionID')::uuid,NULL,NULL,NULL,NULL)=completed
    AND m3b_cycle_test.original_state(a)=before_state,'real_signup_provenance_accepted_and_replay_preserved');
END $real_signup_neighbor$;
DO $new_signup_generation$
DECLARE a uuid:=m3b_cycle_test.uid(8); previous_cycle uuid; previous_generation uuid;
  completed jsonb; state jsonb; future_at timestamptz;
  old_key uuid:='b3b01000-1000-4000-8000-000000000001'; new_key uuid:=gen_random_uuid();
BEGIN
  SELECT cycle_id,signup_generation INTO STRICT previous_cycle,previous_generation
    FROM private.mobile_reevaluation_cycles WHERE user_id=a;
  completed:=m3b_cycle_test.complete_again(a,'m3b-recompleted-8');
  state:=public.get_mobile_reevaluation_cycle(a);
  PERFORM m3b_cycle_test.ok(state->>'unavailable_reason'='not_due' AND state->'cycle'='null'
    AND state#>>'{clock,base_date}'=to_char((completed->>'completed_at')::timestamptz AT TIME ZONE
      'America/Sao_Paulo','YYYY-MM-DD'),'real_recompletion_uses_new_anchor_without_old_cycle');
  PERFORM m3b_cycle_test.throws(format('SELECT public.start_mobile_reevaluation_cycle(%L,%L)',a,old_key),
    '40001','old_key_refused_after_new_first_fresh_conclusion');
  PERFORM m3b_cycle_test.ok(public.start_mobile_reevaluation_cycle(a,new_key)=state,
    'fresh_generation_not_due_does_not_resume_historical_cycle');
  -- Local model time only, inside this rollback transaction. No live weekly claim.
  future_at:=(completed->>'completed_at')::timestamptz+interval '15 days';
  state:=private.start_mobile_reevaluation_cycle_at(a,new_key,future_at);
  PERFORM m3b_cycle_test.ok(state#>>'{cycle,id}'<>previous_cycle::text
    AND state#>>'{cycle,signup_generation}'<>previous_generation::text
    AND (SELECT status='invalidated' FROM private.mobile_reevaluation_cycles WHERE cycle_id=previous_cycle)
    AND (SELECT count(*)=1 FROM private.mobile_reevaluation_cycles WHERE user_id=a
      AND status IN('open','collecting','review_ready')),'new_eligible_generation_invalidates_only_stale_open_cycle');
  PERFORM m3b_cycle_test.throws(format('SELECT private.start_mobile_reevaluation_cycle_at(%L,%L,%L)',
    a,old_key,future_at),'40001','old_key_never_rebinds_to_new_eligible_cycle');
END $new_signup_generation$;
DO $weekly_scope_neighbor$
DECLARE a uuid; old_generation uuid; rolled jsonb; before_cycle jsonb;
BEGIN
  a:=m3b_cycle_test.seed(14,'2026-10-01T23:00:00Z');
  SELECT generation INTO old_generation FROM private.mobile_signup_strength_completion_receipts WHERE user_id=a;
  before_cycle:=public.get_mobile_reevaluation_cycle(a);
  rolled:=private.roll_strength_week_scope(a,old_generation,'m3b_neighbor','m3b-weekly-roll-14');
  PERFORM m3b_cycle_test.ok((rolled->>'generation')::uuid<>old_generation
    AND public.get_mobile_strength_week_context(a)->>'status'='unavailable'
    AND public.get_mobile_reevaluation_cycle(a)=before_cycle,
    'real_weekly_scope_roll_does_not_replace_signup_generation_or_anchor');
END $weekly_scope_neighbor$;
SET LOCAL ROLE authenticated;
DO $direct_access$
BEGIN
  BEGIN
    PERFORM public.get_mobile_reevaluation_cycle('b3b01000-0000-4000-8000-000000000009');
    RAISE EXCEPTION 'M3B_ASSERT:authenticated_direct_RPC_was_allowed';
  EXCEPTION WHEN insufficient_privilege THEN RAISE NOTICE 'M3B_PASS:authenticated_actual_RPC_denied'; END;
END $direct_access$;
RESET ROLE;
SET LOCAL ROLE anon;
DO $direct_access$
BEGIN
  BEGIN
    PERFORM public.start_mobile_reevaluation_cycle('b3b01000-0000-4000-8000-000000000009',
      'b3b01000-1000-4000-8000-000000000020');
    RAISE EXCEPTION 'M3B_ASSERT:anon_direct_RPC_was_allowed';
  EXCEPTION WHEN insufficient_privilege THEN RAISE NOTICE 'M3B_PASS:anon_actual_RPC_denied'; END;
END $direct_access$;
RESET ROLE;
ROLLBACK;

BEGIN ISOLATION LEVEL REPEATABLE READ;
DO $isolation$
BEGIN
  BEGIN
    PERFORM public.get_mobile_reevaluation_cycle('b3b01000-0000-4000-8000-000000000009');
    RAISE EXCEPTION 'M3B_ASSERT:repeatable_read_was_allowed';
  EXCEPTION WHEN invalid_parameter_value THEN
    IF SQLERRM<>'mobile_reevaluation_requires_read_committed' THEN RAISE; END IF;
    RAISE NOTICE 'M3B_PASS:repeatable_read_rejected_before_owner_lookup';
  END;
END $isolation$;
ROLLBACK;
BEGIN ISOLATION LEVEL SERIALIZABLE;
DO $isolation$
BEGIN
  BEGIN
    PERFORM public.start_mobile_reevaluation_cycle('b3b01000-0000-4000-8000-000000000009',
      'b3b01000-1000-4000-8000-000000000020');
    RAISE EXCEPTION 'M3B_ASSERT:serializable_was_allowed';
  EXCEPTION WHEN invalid_parameter_value THEN
    IF SQLERRM<>'mobile_reevaluation_requires_read_committed' THEN RAISE; END IF;
    RAISE NOTICE 'M3B_PASS:serializable_rejected_before_owner_lookup';
  END;
END $isolation$;
ROLLBACK;
