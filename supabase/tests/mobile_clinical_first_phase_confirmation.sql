-- Actual SQL authority with explicit synthetic server numbers. Not core/BFF QA.
BEGIN;
SET LOCAL search_path=pg_catalog;
SELECT set_config('request.jwt.claim.role','service_role',true);
DO $$ BEGIN
 IF to_regprocedure('public.prepare_mobile_clinical_first_phase(uuid,uuid,text,jsonb,jsonb)') IS NULL THEN
  RAISE EXCEPTION 'M3B_ASSERT:first_phase_persistent_authority_missing';END IF;
END $$;
\ir fixtures/mobile_clinical_first_phase_fixture.sql
DO $$
DECLARE q jsonb:=m3b_cycle_test.first_phase_request(2860);a uuid:=(q->>'user')::uuid;k uuid:=gen_random_uuid();alias uuid:=gen_random_uuid();
 r jsonb;before_rows jsonb;clock_before jsonb;origin jsonb;preview uuid:=(q#>>'{prepared,preview_id}')::uuid;gen uuid;epoch uuid;
BEGIN
 SELECT signup_generation,signup_epoch INTO gen,epoch FROM private.mobile_clinical_first_phase_previews WHERE user_id=a;
 clock_before:=public.get_mobile_reevaluation_cycle(a)->'clock';
 PERFORM m3b_cycle_test.ok((SELECT current_protocol IS NULL FROM public.user_profiles WHERE user_id=a)
  AND NOT EXISTS(SELECT 1 FROM public.daily_snapshots WHERE user_id=a)
  AND NOT EXISTS(SELECT 1 FROM private.mobile_clinical_episode_events WHERE user_id=a),
  'persistent prepare records no phase target or episode before acceptance');
 r:=m3b_cycle_test.first_phase_confirm(q,k);
 PERFORM m3b_cycle_test.ok((SELECT current_protocol='recomposicao' AND deficit_level=500 AND weight_kg=81
  FROM public.user_profiles WHERE user_id=a) AND (SELECT calories_target=1413 AND protein_target=121.5 FROM public.daily_snapshots WHERE user_id=a),
  'one confirmation atomically applies phase deficit and the shown server targets');
 PERFORM m3b_cycle_test.ok((SELECT count(*)=1 AND bool_and(review_id IS NULL AND first_phase_id=preview
  AND difficulty_count=0 AND entry_origin='confirmed_phase_change') FROM private.mobile_clinical_episode_events WHERE user_id=a),
  'genuine initial event references first-phase source without a fabricated FULL');
 PERFORM m3b_cycle_test.ok((SELECT count(*)=1 FROM private.mobile_clinical_full_receipts WHERE user_id=a)
  AND clock_before=public.get_mobile_reevaluation_cycle(a)->'clock'
  AND NOT EXISTS(SELECT 1 FROM private.mobile_clinical_day_events WHERE user_id=a)
  AND NOT EXISTS(SELECT 1 FROM private.mobile_clinical_signup_origins WHERE user_id=a),
  'phase acceptance leaves actual FULL calendar and signup origin untouched');
 origin:=private.mobile_clinical_target_origin(a,gen,epoch,(r#>>'{result,decision_date}')::date,clock_timestamp());
 PERFORM m3b_cycle_test.ok(origin->>'source'='clinical_first_phase_v1' AND origin->>'first_phase_id'=preview::text,
  'applied calories have their own immutable first-phase source');
 origin:=private.mobile_clinical_confirmed_calorie_decision(a,gen,epoch,(r#>>'{result,decision_date}')::date,clock_timestamp());
 PERFORM m3b_cycle_test.ok(origin->>'source'='confirmed_first_phase_calculation_v1'
  AND origin->>'first_phase_id'=preview::text AND origin->>'source_episode_event_id'=r#>>'{result,event_id}',
  'future calculation authority is the genuine first-phase decision, not a FULL receipt');
 before_rows:=m3b_cycle_test.original_state(a);
 PERFORM m3b_cycle_test.ok(m3b_cycle_test.first_phase_confirm(q,k)=r AND before_rows=m3b_cycle_test.original_state(a),
  'original confirmation replay is effect free');
 PERFORM m3b_cycle_test.ok(public.prepare_mobile_clinical_first_phase(a,(q#>>'{prepared,prepare_operation_key}')::uuid,
  q#>>'{prepared,context_hash}',q->'selection',q->'proposal')=q->'prepared' AND before_rows=m3b_cycle_test.original_state(a),
  'original prepare ACK precedes recapture after first phase is already assigned');
 PERFORM public.declare_mobile_health_risk(a,gen_random_uuid(),ARRAY['reduced_intake']);before_rows:=m3b_cycle_test.original_state(a);
 PERFORM m3b_cycle_test.ok(m3b_cycle_test.first_phase_confirm(q,k)=r AND before_rows=m3b_cycle_test.original_state(a)
  AND public.get_mobile_health_hold_state(a)->>'hold_active'='true','original ACK cannot erase a later risk');
 PERFORM m3b_cycle_test.first_phase_confirm(q,alias);
 PERFORM m3b_cycle_test.ok((before_rows-'private.mobile_clinical_first_phase_keys')=(m3b_cycle_test.original_state(a)-'private.mobile_clinical_first_phase_keys')
  AND (SELECT count(*)=2 FROM private.mobile_clinical_first_phase_keys WHERE user_id=a),'alias adds only the original confirmation key');
 PERFORM public.reset_user_conversation_atomic(a,true);before_rows:=m3b_cycle_test.original_state(a);
 PERFORM m3b_cycle_test.ok(m3b_cycle_test.first_phase_confirm(q,k)=r AND before_rows=m3b_cycle_test.original_state(a),
  'original first-phase ACK after actual reset never restores a phase or target');
 PERFORM m3b_cycle_test.throws(format('SELECT public.confirm_mobile_clinical_first_phase(%L,%L,%L,%L,%L)',a,preview,k,
  '{"phase":"manutencao"}',q->'proposal'),'40001','same key cannot substitute another phase selection');
END $$;
DO $$
DECLARE q jsonb:=m3b_cycle_test.first_phase_request(2861);a uuid:=(q->>'user')::uuid;b jsonb;
BEGIN
 PERFORM public.declare_mobile_health_risk(a,gen_random_uuid(),ARRAY['reduced_intake']);b:=m3b_cycle_test.original_state(a);
 PERFORM m3b_cycle_test.throws(format('SELECT m3b_cycle_test.first_phase_confirm(%L)',q),'40001','risk after preview refuses before phase target and episode writes');
 PERFORM m3b_cycle_test.ok(b=m3b_cycle_test.original_state(a),'risk refusal leaves the full owner state intact');
END $$;
DO $$
DECLARE q jsonb:=m3b_cycle_test.first_phase_request(2862,'manutencao',true);a uuid:=(q->>'user')::uuid;day jsonb;r jsonb;
BEGIN
 SELECT to_jsonb(s) INTO day FROM public.daily_snapshots s WHERE user_id=a;
 r:=m3b_cycle_test.first_phase_confirm(q);
 PERFORM m3b_cycle_test.ok(day=(SELECT to_jsonb(s) FROM public.daily_snapshots s WHERE user_id=a)
  AND r#>'{result,applied_snapshot_id}'='null'::jsonb AND r#>'{result,maintenance_since}'='null'::jsonb
  AND (r#>>'{result,effective_date}')::date=(r#>>'{result,decision_date}')::date+1,
  'closed snapshot remains exact and maintenance R waits for actual future application');
END $$;
CREATE FUNCTION m3b_cycle_test.fail_first_phase() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN IF NEW.user_id=m3b_cycle_test.uid(2863) THEN RAISE EXCEPTION 'synthetic late first-phase failure' USING ERRCODE='40001';END IF;RETURN NEW;END $$;
CREATE TRIGGER synthetic_first_phase_failure BEFORE INSERT ON private.mobile_clinical_first_phase_confirmations
 FOR EACH ROW EXECUTE FUNCTION m3b_cycle_test.fail_first_phase();
DO $$
DECLARE q jsonb:=m3b_cycle_test.first_phase_request(2863);a uuid:=(q->>'user')::uuid;b jsonb;
BEGIN
 b:=m3b_cycle_test.original_state(a);
 PERFORM m3b_cycle_test.throws(format('SELECT m3b_cycle_test.first_phase_confirm(%L)',q),'40001','late first-phase failure propagates');
 PERFORM m3b_cycle_test.ok(b=m3b_cycle_test.original_state(a),'failure after preliminary profile and target writes rolls back the entire confirmation');
END $$;
DROP TRIGGER synthetic_first_phase_failure ON private.mobile_clinical_first_phase_confirmations;
DO $$
DECLARE role_name text;fn text;
BEGIN
 FOREACH role_name IN ARRAY ARRAY['anon','authenticated'] LOOP
  FOREACH fn IN ARRAY ARRAY['public.get_mobile_clinical_first_phase_prepared(uuid,uuid,uuid)',
   'public.get_mobile_clinical_first_phase_receipt(uuid,uuid,uuid)','public.prepare_mobile_clinical_first_phase(uuid,uuid,text,jsonb,jsonb)',
   'public.confirm_mobile_clinical_first_phase(uuid,uuid,uuid,jsonb,jsonb)'] LOOP
   PERFORM m3b_cycle_test.ok(NOT has_function_privilege(role_name,fn,'EXECUTE'),'mobile client cannot invoke first-phase backend authority');
  END LOOP;
 END LOOP;
 PERFORM m3b_cycle_test.ok(NOT has_function_privilege('service_role','private.confirm_mobile_clinical_first_phase_at(uuid,uuid,uuid,jsonb,jsonb,timestamptz)','EXECUTE')
  AND NOT has_table_privilege('service_role','private.mobile_clinical_first_phase_confirmations','SELECT'),
  'backend cannot bypass first-phase public wrappers or read private receipts directly');
END $$;
SET CONSTRAINTS ALL IMMEDIATE;
ROLLBACK;
