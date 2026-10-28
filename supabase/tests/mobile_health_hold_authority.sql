-- n10 person authority; synthetic local schema only. No photo/provider/clinical completion.
BEGIN;
SET LOCAL request.jwt.claims='{"role":"service_role"}';
\ir fixtures/mobile_reevaluation_cycle_fixture.sql
SELECT m3b_cycle_test.ok(to_regprocedure('public.declare_mobile_health_risk(uuid,uuid,text[])') IS NOT NULL,
  'health declaration RPC exists');
SELECT m3b_cycle_test.seed(700,NULL);
SELECT m3b_cycle_test.seed(701,NULL);
INSERT INTO public.users(id,email,status) VALUES(m3b_cycle_test.uid(702),'hold-no-profile@example.invalid','active');

DO $$
DECLARE owner_id uuid:=m3b_cycle_test.uid(700); a jsonb; b jsonb; c jsonb; original jsonb;
  first_receipt jsonb; current_state jsonb; rejected text;
BEGIN
  original:=m3b_cycle_test.original_state(owner_id)-ARRAY['private.mobile_health_hold_states','private.mobile_health_risk_receipts'];
  a:=public.get_mobile_health_hold_state(owner_id);
  PERFORM m3b_cycle_test.ok(a=jsonb_build_object('version',1,'user_id',owner_id,'safety_revision','0',
    'hold_active',false,'declared_no_plan',false,'hide_protein',false,'last_declared_at',NULL,'items','[]'::jsonb),
    'proven absence is explicit revision zero');
  a:=private.declare_mobile_health_risk_at(owner_id,m3b_cycle_test.uid(710),
    ARRAY['professional_diet','unintended_weight_loss'],'2026-10-01T10:00:00Z');
  first_receipt:=a->'receipt';
  PERFORM m3b_cycle_test.ok(a#>>'{state,safety_revision}'='1' AND (a#>>'{state,hold_active}')::boolean
    AND (a#>>'{state,hide_protein}')::boolean AND NOT (a#>>'{state,declared_no_plan}')::boolean,
    'risk before signup cycle day14 and photos enables hold without changing targets');
  PERFORM m3b_cycle_test.ok(first_receipt->'items'='["unintended_weight_loss","professional_diet"]'::jsonb,
    'risk set canonical source order');
  PERFORM m3b_cycle_test.throws(format('UPDATE private.mobile_health_hold_states SET items=''{}'',hold_active=false WHERE user_id=%L; SELECT public.get_mobile_health_hold_state(%L)',
    owner_id,owner_id),'XX001','same revision cannot clear a durable risk declaration on read');
  PERFORM m3b_cycle_test.throws(format('UPDATE private.mobile_health_hold_states SET items=ARRAY[''unintended_weight_loss'']::private.mobile_health_risk_code_v1[] WHERE user_id=%L; SELECT public.get_mobile_health_hold_state(%L)',
    owner_id,owner_id),'XX001','same revision cannot silently drop one of the current declared risks');
  PERFORM m3b_cycle_test.throws(format('UPDATE private.mobile_health_hold_states SET items=''{}'',hold_active=false WHERE user_id=%L; SELECT public.declare_mobile_health_risk(%L,%L,ARRAY[''professional_diet'',''unintended_weight_loss''])',
    owner_id,owner_id,m3b_cycle_test.uid(710)),'XX001','replay also refuses malformed same revision clearance');
  PERFORM m3b_cycle_test.throws(format('UPDATE private.mobile_health_hold_states SET items=ARRAY[''unintended_weight_loss'']::private.mobile_health_risk_code_v1[] WHERE user_id=%L; SELECT public.declare_mobile_health_risk(%L,%L,ARRAY[''professional_diet'',''unintended_weight_loss''])',
    owner_id,owner_id,m3b_cycle_test.uid(710)),'XX001','replay also refuses partial current receipt loss');
  PERFORM m3b_cycle_test.throws(format('UPDATE private.mobile_health_hold_states SET last_declared_at=last_declared_at+interval ''1 day'' WHERE user_id=%L; SELECT public.get_mobile_health_hold_state(%L)',
    owner_id,owner_id),'XX001','current receipt and state declaration timestamp must agree');
  PERFORM m3b_cycle_test.throws(format('UPDATE private.mobile_health_hold_states SET safety_revision=2 WHERE user_id=%L; SELECT public.get_mobile_health_hold_state(%L)',
    owner_id,owner_id),'XX001','active hold requires a declaration receipt at its current revision');
  PERFORM m3b_cycle_test.ok(m3b_cycle_test.original_state(owner_id)-ARRAY['private.mobile_health_hold_states','private.mobile_health_risk_receipts']=original,
    'only private health rows changed');
  PERFORM m3b_cycle_test.ok(NOT EXISTS(SELECT 1 FROM private.mobile_reevaluation_cycles WHERE user_id=owner_id)
    AND NOT EXISTS(SELECT 1 FROM private.strength_week_scopes WHERE user_id=owner_id),
    'no signup generation or cycle created');
  b:=private.declare_mobile_health_risk_at(owner_id,m3b_cycle_test.uid(710),
    ARRAY['unintended_weight_loss','professional_diet'],'2026-10-04T10:00:00Z');
  PERFORM m3b_cycle_test.ok(b=a,'same key after HTTP TTL replays original result without a new date');
  PERFORM m3b_cycle_test.throws(format('SELECT public.declare_mobile_health_risk(%L,%L,ARRAY[%L])',
    owner_id,m3b_cycle_test.uid(710),'reduced_intake'),'40001','different items on same key conflict');
  c:=private.declare_mobile_health_risk_at(owner_id,m3b_cycle_test.uid(711),
    ARRAY['pregnant_or_breastfeeding'],'2026-10-05T10:00:00Z');
  PERFORM m3b_cycle_test.ok(c#>>'{state,safety_revision}'='2' AND (c#>>'{state,declared_no_plan}')::boolean
    AND jsonb_array_length(c#>'{state,items}')=3,'new declaration unions flags without lost prior risks');
  b:=public.declare_mobile_health_risk(owner_id,m3b_cycle_test.uid(710),ARRAY['professional_diet','unintended_weight_loss']);
  PERFORM m3b_cycle_test.ok(b->'receipt'=first_receipt AND b->'state'=c->'state',
    'old key returns stable receipt and current newer safety revision');
  PERFORM m3b_cycle_test.ok(c#>>'{state,items,0,declared_at}'='2026-10-01T10:00:00.000000Z'
    AND c#>>'{state,items,2,declared_at}'='2026-10-05T10:00:00.000000Z','each active flag has its declaration date');
  current_state:=public.get_mobile_health_hold_state(owner_id);
  PERFORM public.reset_user_conversation_atomic(owner_id,true);
  PERFORM m3b_cycle_test.ok(public.get_mobile_health_hold_state(owner_id)=current_state
    AND (SELECT count(*)=2 FROM private.mobile_health_risk_receipts WHERE user_id=owner_id),
    'real conversation reset preserves hold and durable receipts');
  b:=public.declare_mobile_health_risk(owner_id,m3b_cycle_test.uid(710),ARRAY['unintended_weight_loss','professional_diet']);
  PERFORM m3b_cycle_test.ok(b->'receipt'=first_receipt AND b->'state'=current_state,'replay after reset does not rearm or rewrite');

  -- The formerly accepted synthetic clear is no longer authority. The actual
  -- cleared-state replay/presentation cases now run through the real FULL
  -- writer in mobile_clinical_full_conclusion.sql, with an immutable receipt.
  PERFORM m3b_cycle_test.throws(format('UPDATE private.mobile_health_hold_states SET hold_active=false,items=''{}'',safety_revision=3 WHERE user_id=%L; SELECT public.get_mobile_health_hold_state(%L)',
    owner_id,owner_id),'XX001','inactive higher revision without concluded FULL clear proof is refused');
  current_state:=public.get_mobile_health_hold_state(owner_id);
  b:=public.declare_mobile_health_risk(owner_id,m3b_cycle_test.uid(710),ARRAY['professional_diet','unintended_weight_loss']);
  PERFORM m3b_cycle_test.ok(b->'receipt'=first_receipt AND b->'state'=current_state
    AND b#>>'{state,safety_revision}'='2' AND (b#>>'{state,hold_active}')::boolean,
    'old durable key preserves real current authority after refused synthetic clear');
  PERFORM m3b_cycle_test.throws(format('SELECT private.declare_mobile_health_risk_at(%L,%L,ARRAY[%L],%L)',
    owner_id,m3b_cycle_test.uid(720),'reduced_intake','2026-10-04T10:00:00Z'),
    '40001','regressed new declaration clock refuses without losing current authority');
  PERFORM m3b_cycle_test.throws(format('DELETE FROM private.mobile_health_hold_states WHERE user_id=%L; SELECT public.get_mobile_health_hold_state(%L)',
    owner_id,owner_id),'XX001','missing state with retained receipts is unavailable not no hold');

  b:=public.declare_mobile_health_risk(m3b_cycle_test.uid(702),m3b_cycle_test.uid(712),ARRAY['loss_of_control_eating']);
  PERFORM m3b_cycle_test.ok((b#>>'{state,hold_active}')::boolean AND NOT EXISTS(
    SELECT 1 FROM public.user_profiles WHERE user_id=m3b_cycle_test.uid(702)), 'person declaration works without profile and never creates one');
  PERFORM m3b_cycle_test.ok(public.get_mobile_health_hold_state(m3b_cycle_test.uid(701))->>'safety_revision'='0',
    'another owner remains absent');

  FOREACH rejected IN ARRAY ARRAY['none','prefiro_nao_responder','unknown','professional_diet secret'] LOOP
    PERFORM m3b_cycle_test.throws(format('SELECT public.declare_mobile_health_risk(%L,%L,ARRAY[%L])',owner_id,m3b_cycle_test.uid(720),rejected),
      '22023','nonrisk or unknown code rejected');
  END LOOP;
  PERFORM m3b_cycle_test.throws(format('SELECT public.declare_mobile_health_risk(%L,%L,ARRAY[]::text[])',owner_id,m3b_cycle_test.uid(720)),'22023','empty list cannot mean none');
  PERFORM m3b_cycle_test.throws(format('SELECT public.declare_mobile_health_risk(%L,%L,ARRAY[%L,%L])',owner_id,m3b_cycle_test.uid(720),'reduced_intake','reduced_intake'),'22023','duplicate items rejected');
  PERFORM m3b_cycle_test.throws(format('SELECT public.declare_mobile_health_risk(%L,%L,ARRAY[NULL]::text[])',owner_id,m3b_cycle_test.uid(720)),'22023','null item rejected');
  PERFORM m3b_cycle_test.throws(format('SELECT public.declare_mobile_health_risk(%L,NULL,ARRAY[%L])',owner_id,'reduced_intake'),'22023','missing operation rejected');
  PERFORM m3b_cycle_test.throws(format('SELECT public.get_mobile_health_hold_state(%L)',m3b_cycle_test.uid(799)),'P0002','missing owner is unavailable not absent');
  PERFORM m3b_cycle_test.throws(format('SELECT public.declare_mobile_health_risk(%L,%L,ARRAY[%L])',m3b_cycle_test.uid(799),m3b_cycle_test.uid(720),'reduced_intake'),'P0002','missing owner cannot declare');
  UPDATE public.users SET status='deleted' WHERE id=m3b_cycle_test.uid(701);
  PERFORM m3b_cycle_test.throws(format('SELECT public.get_mobile_health_hold_state(%L)',m3b_cycle_test.uid(701)),'P0002','deleted owner unavailable');
  PERFORM m3b_cycle_test.throws(format('UPDATE private.mobile_health_risk_receipts SET declared_at=clock_timestamp() WHERE user_id=%L',owner_id),'55000','receipt updates forbidden');
  PERFORM m3b_cycle_test.throws(format('DELETE FROM private.mobile_health_risk_receipts WHERE user_id=%L',owner_id),'55000','receipt deletion forbidden while person exists');
END $$;

SELECT m3b_cycle_test.ok((SELECT enum_range(NULL::private.mobile_health_risk_code_v1)::text[])=ARRAY[
 'unintended_weight_loss','reduced_intake','persistent_fatigue_weakness_dizziness','menstrual_change',
 'loss_of_control_eating','appetite_weight_treatment','professional_diet','pregnant_or_breastfeeding'],
 'SQL enum pins the shared eight-code wire catalog');
SELECT m3b_cycle_test.ok((SELECT bool_and(relrowsecurity) FROM pg_class WHERE oid IN(
 'private.mobile_health_hold_states'::regclass,'private.mobile_health_risk_receipts'::regclass)), 'private tables have RLS');
SELECT m3b_cycle_test.ok(NOT has_table_privilege('service_role','private.mobile_health_hold_states','SELECT,INSERT,UPDATE,DELETE')
 AND NOT has_table_privilege('authenticated','private.mobile_health_risk_receipts','SELECT,INSERT,UPDATE,DELETE'), 'no direct table grants');
SELECT m3b_cycle_test.ok(has_function_privilege('service_role','public.get_mobile_health_hold_state(uuid)','EXECUTE')
 AND has_function_privilege('service_role','public.declare_mobile_health_risk(uuid,uuid,text[])','EXECUTE')
 AND NOT has_function_privilege('authenticated','public.declare_mobile_health_risk(uuid,uuid,text[])','EXECUTE')
 AND NOT has_function_privilege('anon','public.get_mobile_health_hold_state(uuid)','EXECUTE')
 AND NOT has_function_privilege('service_role','private.declare_mobile_health_risk_at(uuid,uuid,text[],timestamp with time zone)','EXECUTE'),
 'only trusted public entrypoints granted');
SET LOCAL request.jwt.claims='{"role":"authenticated"}';
SELECT m3b_cycle_test.throws('SELECT public.get_mobile_health_hold_state(m3b_cycle_test.uid(700))','42501','authenticated claim rejected inside definer');
SELECT m3b_cycle_test.throws('SELECT public.declare_mobile_health_risk(m3b_cycle_test.uid(700),m3b_cycle_test.uid(720),ARRAY[''reduced_intake''])','42501','authenticated declaration rejected inside definer');
SET LOCAL request.jwt.claims='{"role":"service_role"}';
DELETE FROM public.users WHERE id=m3b_cycle_test.uid(702);
SELECT m3b_cycle_test.ok(NOT EXISTS(SELECT 1 FROM private.mobile_health_hold_states WHERE user_id=m3b_cycle_test.uid(702))
 AND NOT EXISTS(SELECT 1 FROM private.mobile_health_risk_receipts WHERE user_id=m3b_cycle_test.uid(702)), 'hard account deletion cascades only owned private health data');
ROLLBACK;
