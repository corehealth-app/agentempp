-- Real owned PostgreSQL; all fixture data and changes roll back.
BEGIN;
SET LOCAL search_path=pg_catalog;
SELECT set_config('request.jwt.claims','{"role":"service_role"}',true);
\ir fixtures/mobile_clinical_signup_targets_fixture.sql

CREATE FUNCTION m3b_cycle_test.flow_plan_seed(n integer) RETURNS jsonb
LANGUAGE plpgsql SET search_path=pg_catalog AS $$
DECLARE c jsonb;a uuid;msg uuid;key text;day_context jsonb;
BEGIN
 c:=m3b_cycle_test.signup_target_context(n,'recomposicao');a:=(c->>'user')::uuid;
 day_context:=public.get_mobile_clinical_daily_context(a);
 PERFORM public.apply_mobile_clinical_daily(a,gen_random_uuid(),day_context->>'context_hash',
  '{"version":1,"formulaKcal":2000,"maintenanceKcal":2400,"sedentaryKcal":1900,"proteinTarget":144,"maintenanceProteinTarget":126}');
 key:='qa-mobile-plan-'||n;
 INSERT INTO public.messages(user_id,direction,role,content_type,content,provider,provider_message_id)
 VALUES(a,'in','user','text','Synthetic plan request','mobile_flow',key) RETURNING id INTO msg;
 RETURN jsonb_build_object('user',a,'message',msg,'key',key||':propoe_plano_dieta');
END $$;

CREATE FUNCTION m3b_cycle_test.flow_plan_create(q jsonb,c jsonb,payload jsonb DEFAULT
 '{"meta_kcal":2000,"meta_protein_g":144,"mode":"referencia","horizon":"daily","daily_meals":[],"shopping_list":[]}',
 domain text DEFAULT 'nutrition') RETURNS jsonb LANGUAGE sql SET search_path=pg_catalog AS $$
 SELECT public.create_mobile_flow_plan_draft((q->>'user')::uuid,domain,
  replace(q->>'key',':propoe_plano_dieta',CASE WHEN domain='training' THEN ':propoe_plano_treino' ELSE ':propoe_plano_dieta' END),
  (q->>'message')::uuid,c,'needs_completion',payload,'[]',jsonb_build_object('identity','flow'))
$$;

DO $$ DECLARE q jsonb:=m3b_cycle_test.flow_plan_seed(6330);a uuid:=(q->>'user')::uuid;c jsonb;r jsonb;
BEGIN
 c:=public.get_mobile_flow_plan_context(a);
 PERFORM m3b_cycle_test.ok(c#>>'{day,calories_target}'='2000' AND (c#>>'{day,protein_target}')::numeric=144
  AND c#>>'{day,target_revision}'='0' AND c#>>'{day,calorie_origin,source}'='clinical_signup_v1',
  'private draft context binds actual current day and genuine signup origin');
 r:=m3b_cycle_test.flow_plan_create(q,c);
 PERFORM m3b_cycle_test.ok(r->'inserted'='true' AND r->>'status'='needs_completion'
  AND (SELECT count(*)=1 FROM public.plan_drafts WHERE user_id=a)
  AND (SELECT count(*)=1 FROM private.mobile_flow_plan_draft_origins WHERE user_id=a),
  'guarded creation stores draft and immutable private origin atomically');
 PERFORM m3b_cycle_test.ok(NOT EXISTS(SELECT 1 FROM public.training_plans WHERE user_id=a)
  AND NOT EXISTS(SELECT 1 FROM public.prescriptions WHERE user_id=a), 'creation never activates a plan');
 PERFORM public.update_plan_draft_atomic(a,(r->>'id')::uuid,1,r->'payload'||'{"notes":"patient edited"}', '[]',false);
 r:=m3b_cycle_test.flow_plan_create(q,public.get_mobile_flow_plan_context(a),'{"meta_kcal":1,"meta_protein_g":1}');
 PERFORM m3b_cycle_test.ok(r->'inserted'='false' AND r#>>'{payload,notes}'='patient edited'
  AND r->>'payload_version'='2' AND (SELECT count(*)=1 FROM public.plan_drafts WHERE user_id=a),
  'same-key replay returns actual edited payload and current version without overwriting it');
 PERFORM public.discard_plan_draft_atomic(a,(r->>'id')::uuid);
 r:=m3b_cycle_test.flow_plan_create(q,public.get_mobile_flow_plan_context(a));
 PERFORM m3b_cycle_test.ok(r->'inserted'='false' AND r->>'status'='discarded',
  'closed replay preserves current draft status rather than fabricating original creation ACK');
END $$;

DO $$ DECLARE q jsonb;a uuid;c jsonb;before_state jsonb;field text;n integer:=6331;
BEGIN
 FOREACH field IN ARRAY ARRAY['profile','health','config','calories','protein','protein_restore','calories_restore','reset'] LOOP
  q:=m3b_cycle_test.flow_plan_seed(n);n:=n+1;a:=(q->>'user')::uuid;c:=public.get_mobile_flow_plan_context(a);
  CASE field
   WHEN 'profile' THEN UPDATE public.user_profiles SET weight_kg=81 WHERE user_id=a;
   WHEN 'health' THEN PERFORM public.declare_mobile_health_risk(a,gen_random_uuid(),ARRAY['reduced_intake']);
   WHEN 'config' THEN UPDATE public.global_config SET updated_at=updated_at+interval '1 microsecond' WHERE key='calc.bf_limits';
   WHEN 'calories' THEN UPDATE public.daily_snapshots SET calories_target=2100 WHERE user_id=a;
   WHEN 'protein' THEN UPDATE public.daily_snapshots SET protein_target=145 WHERE user_id=a;
   WHEN 'protein_restore' THEN
    UPDATE public.daily_snapshots SET protein_target=145 WHERE user_id=a;
    UPDATE public.daily_snapshots SET protein_target=144 WHERE user_id=a;
   WHEN 'calories_restore' THEN
    UPDATE public.daily_snapshots SET calories_target=2100 WHERE user_id=a;
    UPDATE public.daily_snapshots SET calories_target=2000 WHERE user_id=a;
   WHEN 'reset' THEN PERFORM public.reset_user_conversation_atomic(a,true);
  END CASE;
  before_state:=m3b_cycle_test.original_state(a);
  PERFORM m3b_cycle_test.throws(format('SELECT m3b_cycle_test.flow_plan_create(%L,%L)',q,c),'40001',field||' drift refuses stale generation');
  PERFORM m3b_cycle_test.ok(before_state=m3b_cycle_test.original_state(a)
   AND NOT EXISTS(SELECT 1 FROM public.plan_drafts WHERE user_id=a),field||' refusal has zero partial draft/origin/plan effects');
 END LOOP;
END $$;

DO $$ DECLARE q jsonb:=m3b_cycle_test.flow_plan_seed(6340);a uuid:=(q->>'user')::uuid;c jsonb;r jsonb;before_state jsonb;
BEGIN
 c:=public.get_mobile_flow_plan_context(a);
 UPDATE public.daily_snapshots SET calories_consumed=777,protein_g=33,exercise_calories=123,xp_earned=15 WHERE user_id=a;
 PERFORM m3b_cycle_test.ok(private.mobile_flow_plan_context_binding(c)=
  private.mobile_flow_plan_context_binding(public.get_mobile_flow_plan_context(a)),
  'consumption/exercise/XP aggregation does not invalidate a target-only latch');
 r:=m3b_cycle_test.flow_plan_create(q,c);
 PERFORM m3b_cycle_test.ok(r->'inserted'='true' AND (SELECT calories_consumed=777 AND protein_g=33 AND exercise_calories=123 AND xp_earned=15
  FROM public.daily_snapshots WHERE user_id=a),'valid generation preserves concurrent observed facts');
 UPDATE public.daily_snapshots SET protein_target=145 WHERE user_id=a;
 c:=public.get_mobile_flow_plan_context(a);before_state:=m3b_cycle_test.original_state(a);
 PERFORM m3b_cycle_test.throws(format('SELECT public.lookup_mobile_flow_plan_draft(%L,%L,%L,%L,%L)',a,'nutrition',q->>'key',q->>'message',c),
  '40001','fresh context cannot relabel an existing draft written under an earlier target');
 PERFORM m3b_cycle_test.ok(before_state=m3b_cycle_test.original_state(a),'stale lookup does not mutate or recreate draft');
END $$;

DO $$ DECLARE q jsonb:=m3b_cycle_test.flow_plan_seed(6341);a uuid:=(q->>'user')::uuid;c jsonb;r jsonb;before_state jsonb;
BEGIN
 c:=public.get_mobile_flow_plan_context(a);before_state:=m3b_cycle_test.original_state(a);
 PERFORM m3b_cycle_test.throws(format('SELECT m3b_cycle_test.flow_plan_create(%L,%L,%L)',q,c,
  '{"meta_kcal":1999,"meta_protein_g":144}'),'23514','generated target fields cannot substitute the official day targets');
 PERFORM m3b_cycle_test.ok(before_state=m3b_cycle_test.original_state(a),'wrong generated targets create no draft');
 PERFORM public.declare_mobile_health_risk(a,gen_random_uuid(),ARRAY['reduced_intake']);c:=public.get_mobile_flow_plan_context(a);
 PERFORM m3b_cycle_test.ok(c#>'{allowed,training}'='true' AND c#>'{allowed,nutrition}'='false',
  'existing approved HOLD permits training guidance and refuses nutrition guidance');
 PERFORM m3b_cycle_test.throws(format('SELECT m3b_cycle_test.flow_plan_create(%L,%L)',q,c),'23514','fresh HOLD cannot create a diet');
 r:=m3b_cycle_test.flow_plan_create(q,c,'{"notes":"synthetic training"}','training');
 PERFORM m3b_cycle_test.ok(r->'inserted'='true','allowed training writes only a draft under HOLD');
END $$;

DO $$ DECLARE q jsonb:=m3b_cycle_test.flow_plan_seed(6342);other jsonb:=m3b_cycle_test.flow_plan_seed(6343);
 a uuid:=(q->>'user')::uuid;c jsonb;r jsonb;caller text;refused boolean;
BEGIN
 c:=public.get_mobile_flow_plan_context(a);
 PERFORM m3b_cycle_test.throws(format('SELECT public.lookup_mobile_flow_plan_draft(%L,%L,%L,%L,%L)',
  a,'nutrition',q->>'key',other->>'message',c),'P0002','other owner inbound cannot authorize a draft');
 PERFORM m3b_cycle_test.throws(format('SELECT m3b_cycle_test.flow_plan_create(%L,%L)',other,c),'40001','other owner cannot use captured authority');
 r:=m3b_cycle_test.flow_plan_create(q,c);
 PERFORM public.reset_user_conversation_atomic(a,true);
 c:=public.get_mobile_flow_plan_context(a);
 PERFORM m3b_cycle_test.throws(format('SELECT public.lookup_mobile_flow_plan_draft(%L,%L,%L,%L,%L)',
  a,'nutrition',q->>'key',q->>'message',c),'23514','reset state cannot recover old draft content');
 PERFORM m3b_cycle_test.ok((SELECT count(*)=1 FROM public.plan_drafts WHERE user_id=a), 'keep-plans reset preserves stored draft');
 PERFORM public.reset_user_conversation_atomic(a,false);
 PERFORM m3b_cycle_test.ok(NOT EXISTS(SELECT 1 FROM public.plan_drafts WHERE user_id=a)
  AND NOT EXISTS(SELECT 1 FROM private.mobile_flow_plan_draft_origins WHERE user_id=a),
  'normal discard-plans reset cascades private origin without blocking deletion');
 FOREACH caller IN ARRAY ARRAY['anon','authenticated','service_role'] LOOP
  PERFORM m3b_cycle_test.ok(NOT has_table_privilege(caller,'private.mobile_flow_plan_draft_origins','SELECT,INSERT,UPDATE,DELETE')
   AND NOT has_table_privilege(caller,'private.mobile_flow_plan_day_revisions','SELECT,INSERT,UPDATE,DELETE'),caller||' has no direct private authority access');
  PERFORM m3b_cycle_test.ok(NOT has_function_privilege(caller,'private.capture_mobile_flow_plan_context_at(uuid,timestamptz)','EXECUTE'),
   caller||' cannot choose authority clock');
 END LOOP;
 FOREACH caller IN ARRAY ARRAY['anon','authenticated'] LOOP
  refused:=false;EXECUTE format('SET LOCAL ROLE %I',caller);
  BEGIN PERFORM public.get_mobile_flow_plan_context(a);EXCEPTION WHEN insufficient_privilege THEN refused:=true;END;
  EXECUTE 'RESET ROLE';PERFORM m3b_cycle_test.ok(refused,caller||' cannot invoke service RPC');
 END LOOP;
 PERFORM m3b_cycle_test.ok((SELECT bool_and(relrowsecurity) FROM pg_class WHERE oid IN
  ('private.mobile_flow_plan_draft_origins'::regclass,'private.mobile_flow_plan_day_revisions'::regclass)), 'private authority tables have RLS');
END $$;

DO $$ DECLARE q jsonb:=m3b_cycle_test.flow_plan_seed(6344);a uuid:=(q->>'user')::uuid;c jsonb;r jsonb;
BEGIN
 c:=public.get_mobile_flow_plan_context(a);
 EXECUTE 'SET LOCAL ROLE service_role';
 r:=public.get_mobile_flow_plan_context(a);
 EXECUTE 'RESET ROLE';
 PERFORM m3b_cycle_test.ok(private.mobile_flow_plan_context_binding(c)=private.mobile_flow_plan_context_binding(r),
  'actual service role can capture current backend-only authority');
 r:=m3b_cycle_test.flow_plan_create(q,c);
 PERFORM m3b_cycle_test.throws(format('UPDATE private.mobile_flow_plan_draft_origins SET binding=%L WHERE user_id=%L','{}',a),
  '55000','surviving draft origin cannot be relabeled');
 PERFORM m3b_cycle_test.throws(format('DELETE FROM private.mobile_flow_plan_draft_origins WHERE user_id=%L',a),
  '55000','surviving draft origin cannot be erased');
 DELETE FROM public.messages WHERE id=(q->>'message')::uuid;
 PERFORM m3b_cycle_test.throws(format('SELECT public.lookup_mobile_flow_plan_draft(%L,%L,%L,%L,%L)',
  a,'nutrition',q->>'key',q->>'message',public.get_mobile_flow_plan_context(a)),
  'P0002','a deleted inbound cannot recover or recreate its draft');
END $$;

DO $$ DECLARE q jsonb:=m3b_cycle_test.flow_plan_seed(6345);a uuid:=(q->>'user')::uuid;c jsonb;r jsonb;
BEGIN
 c:=public.get_mobile_flow_plan_context(a);
 PERFORM public.create_plan_draft_atomic(a,'nutrition','flow_generated','needs_completion','{"notes":"legacy"}',NULL,
  '[]','[]',NULL,(q->>'message')::uuid,'{}',q->>'key');
 PERFORM m3b_cycle_test.throws(format('SELECT m3b_cycle_test.flow_plan_create(%L,%L)',q,c),
  '40001','legacy draft has no invented clinical origin or backfill');
 UPDATE public.user_profiles SET height_cm=NULL WHERE user_id=a;c:=public.get_mobile_flow_plan_context(a);
 PERFORM m3b_cycle_test.ok(c#>>'{state,assessment}'='incomplete' AND c#>'{allowed,training}'='true'
  AND c#>'{allowed,nutrition}'='true','incomplete unrelated body field preserves available official targets and guidance');
 UPDATE public.user_profiles SET birth_date='2012-01-01' WHERE user_id=a;c:=public.get_mobile_flow_plan_context(a);
 PERFORM m3b_cycle_test.ok(c#>'{allowed,training}'='false' AND c#>'{allowed,nutrition}'='false',
  'known underage guard remains effective even with an incomplete assessment');
END $$;
SET CONSTRAINTS ALL IMMEDIATE;
ROLLBACK;
