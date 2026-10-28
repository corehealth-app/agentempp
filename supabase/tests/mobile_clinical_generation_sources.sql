\set ON_ERROR_STOP on
BEGIN ISOLATION LEVEL READ COMMITTED;
SET LOCAL statement_timeout='30s';
SET LOCAL lock_timeout='5s';
SET LOCAL request.jwt.claims='{"role":"service_role"}';
SET LOCAL TimeZone='UTC';
\ir fixtures/mobile_reevaluation_cycle_fixture.sql

DO $references$
DECLARE a uuid; b uuid; g uuid; e uuid; d jsonb; before_neighbor jsonb;
 base date:=(clock_timestamp() AT TIME ZONE 'America/Sao_Paulo')::date;
BEGIN
 a:=m3b_cycle_test.seed(2961,'2026-10-01T23:00:00Z','America/Sao_Paulo',false);
 b:=m3b_cycle_test.seed(2962,'2026-10-01T23:00:00Z');
 before_neighbor:=m3b_cycle_test.original_state(b);
 d:=private.admit_mobile_clinical_legacy_generation_at(a,NULL)->'authority';
 g:=(d->>'generation')::uuid;e:=(d->>'epoch')::uuid;
 -- Structural FK proof only, not proof of legacy calendar availability or FULL.
 INSERT INTO private.mobile_reevaluation_cycles(user_id,signup_generation,signup_epoch,
  base_date,due_date,timezone_at_open,status,opened_at,kind)
 VALUES(a,g,e,base,base+14,'America/Sao_Paulo','open',clock_timestamp(),'REGULAR');
 PERFORM m3b_cycle_test.ok(EXISTS(SELECT 1 FROM private.mobile_clinical_generation_sources
  WHERE user_id=a AND generation=g AND epoch=e AND kind='legacy_transition'
   AND signup_admission_id IS NULL AND legacy_generation=g),
  'legacy_clinical_reference_points_to_actual_admission_not_fake_signup');
 PERFORM m3b_cycle_test.ok(NOT EXISTS(SELECT 1 FROM private.mobile_signup_strength_completion_receipts WHERE user_id=a)
  AND NOT EXISTS(SELECT 1 FROM private.strength_week_scopes WHERE user_id=a),
  'generic_reference_does_not_fabricate_original_signup_or_frequency');
 PERFORM m3b_cycle_test.ok(EXISTS(SELECT 1 FROM private.mobile_clinical_generation_sources s
  JOIN private.mobile_signup_strength_completion_receipts r ON r.user_id=s.user_id AND r.admission_id=s.generation
  WHERE s.user_id=b AND s.kind='signup_receipt' AND s.epoch=r.epoch
   AND s.signup_admission_id=r.admission_id AND s.legacy_generation IS NULL),
  'genuine_signup_automatically_keeps_its_own_source');
 PERFORM m3b_cycle_test.throws(format('INSERT INTO private.mobile_reevaluation_cycles(user_id,signup_generation,signup_epoch,base_date,due_date,timezone_at_open,status,opened_at,kind) VALUES(%L,%L,%L,%L,%L,''America/Sao_Paulo'',''open'',clock_timestamp(),''REGULAR'')',
  b,g,e,base,base+14),'23503','foreign_generation_cannot_be_rebound_to_another_owner');
 PERFORM m3b_cycle_test.throws(format('UPDATE private.mobile_clinical_generation_sources SET kind=''signup_receipt'' WHERE user_id=%L',a),
  '55000','generation_source_cannot_be_relabelled');
 PERFORM m3b_cycle_test.throws(format('DELETE FROM private.mobile_clinical_generation_sources WHERE user_id=%L',a),
  '55000','generation_source_cannot_disappear_while_its_backing_evidence_exists');
 PERFORM m3b_cycle_test.ok(m3b_cycle_test.original_state(b)=before_neighbor,
  'reference_and_rejected_writes_leave_neighbor_unchanged');
 PERFORM public.reset_user_conversation_atomic(a,true);
 PERFORM m3b_cycle_test.ok(private.read_mobile_clinical_legacy_generation_at(a,NULL) IS NULL
  AND (SELECT count(*)=1 FROM private.mobile_clinical_generation_sources WHERE user_id=a),
  'reset_revokes_current_validity_without_erasing_original_source_registry');
 DELETE FROM public.users WHERE id=a;
 PERFORM m3b_cycle_test.ok(NOT EXISTS(SELECT 1 FROM private.mobile_clinical_generation_sources WHERE user_id=a)
  AND NOT EXISTS(SELECT 1 FROM private.mobile_clinical_legacy_admissions WHERE user_id=a)
  AND NOT EXISTS(SELECT 1 FROM private.mobile_reevaluation_cycles WHERE user_id=a)
  AND m3b_cycle_test.original_state(b)=before_neighbor,
  'final_owner_cascade_removes_only_its_registry_and_children');
END $references$;

DO $integrity$
DECLARE a uuid; b uuid; g uuid; e uuid; source_id uuid;
BEGIN
 a:=m3b_cycle_test.seed(2963,'2026-10-01T23:00:00Z');
 SELECT admission_id,epoch INTO g,e FROM private.mobile_signup_strength_completion_receipts WHERE user_id=a;
 PERFORM m3b_cycle_test.throws(format('INSERT INTO private.mobile_clinical_generation_sources(user_id,generation,epoch,kind,legacy_generation) VALUES(%L,%L,%L,''legacy_transition'',%L)',
  a,gen_random_uuid(),e,g),'23514','one_source_shape_rejects_legacy_alias_of_genuine_signup');
 b:=m3b_cycle_test.seed(2964,'2026-10-01T23:00:00Z','America/Sao_Paulo',false);
 PERFORM m3b_cycle_test.throws(format('INSERT INTO private.mobile_clinical_generation_sources(user_id,generation,epoch,kind,signup_admission_id) VALUES(%L,%L,%L,''signup_receipt'',%L)',
  b,g,e,g),'23503','registry_cannot_invent_or_steal_a_source');
 PERFORM m3b_cycle_test.throws(format('INSERT INTO private.mobile_clinical_generation_sources(user_id,generation,epoch,kind,signup_admission_id) VALUES(%L,%L,%L,''signup_receipt'',%L)',
  a,g,gen_random_uuid(),g),'23514','registry_epoch_must_match_its_actual_source');
 -- The registry follows the lifetime of its actual source; it is not a new FULL ACK.
 DELETE FROM private.mobile_signup_strength_completion_receipts WHERE user_id=a;
 PERFORM m3b_cycle_test.ok(NOT EXISTS(SELECT 1 FROM private.mobile_clinical_generation_sources WHERE user_id=a)
  AND EXISTS(SELECT 1 FROM public.users WHERE id=a),
  'source_teardown_cascades_derived_registry_without_a_new_purge_blocker');
END $integrity$;

DO $constraints$
DECLARE relation_name text; relation_oid regclass; found_count integer; c record; role_name text;
BEGIN
 FOREACH relation_name IN ARRAY ARRAY['mobile_reevaluation_cycles','mobile_clinical_previews',
  'mobile_clinical_full_receipts','mobile_clinical_episode_events','mobile_clinical_daily_applications'] LOOP
  relation_oid:=to_regclass('private.'||relation_name);
  SELECT count(*) INTO found_count FROM pg_constraint k WHERE k.conrelid=relation_oid
   AND k.contype='f' AND k.confrelid='private.mobile_clinical_generation_sources'::regclass;
  PERFORM m3b_cycle_test.ok(found_count=1,'generic_clinical_parent_'||relation_name);
  SELECT * INTO STRICT c FROM pg_constraint k WHERE k.conrelid=relation_oid
   AND k.contype='f' AND k.confrelid='private.mobile_clinical_generation_sources'::regclass;
  PERFORM m3b_cycle_test.ok(c.confupdtype='a' AND c.confdeltype='a' AND c.convalidated
   AND c.condeferrable=(relation_name<>'mobile_reevaluation_cycles')
   AND c.condeferred=(relation_name<>'mobile_reevaluation_cycles'),
   'original_fk_actions_and_deferral_preserved_'||relation_name);
 END LOOP;
 FOREACH relation_name IN ARRAY ARRAY['mobile_clinical_signup_origins','strength_week_lifecycle_bindings',
  'mobile_clinical_first_phase_previews','mobile_clinical_first_phase_confirmations'] LOOP
  PERFORM m3b_cycle_test.ok((SELECT count(*)=1 FROM pg_constraint k
   WHERE k.conrelid=to_regclass('private.'||relation_name) AND k.contype='f'
    AND k.confrelid='private.mobile_signup_strength_completion_receipts'::regclass),
   'specific_signup_proof_stays_strict_'||relation_name);
 END LOOP;
 FOREACH role_name IN ARRAY ARRAY['anon','authenticated','service_role'] LOOP
  PERFORM m3b_cycle_test.ok(NOT has_table_privilege(role_name,'private.mobile_clinical_generation_sources','SELECT,INSERT,UPDATE,DELETE'),
   'generation_registry_private_acl_'||role_name);
 END LOOP;
 PERFORM m3b_cycle_test.ok((SELECT relrowsecurity FROM pg_class
  WHERE oid='private.mobile_clinical_generation_sources'::regclass),'generation_registry_rls_enabled');
END $constraints$;
ROLLBACK;
