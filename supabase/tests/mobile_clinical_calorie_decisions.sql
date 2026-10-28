-- Local synthetic transaction only. Numeric fixture formula is not BFF math
-- proof; the actual phase bridge separately executes the real evaluator.
BEGIN;
SELECT set_config('request.jwt.claim','{"role":"service_role"}',true);
\ir fixtures/mobile_clinical_full_command_fixture.sql
DO $$
DECLARE c jsonb;q jsonb;packet jsonb;ack jsonb;decision jsonb;origin jsonb;
 a uuid;cycle uuid;review uuid;generation uuid;epoch uuid;today date;seen timestamptz;
 prior jsonb;prior_state jsonb;closed boolean;n integer;caller text;refused boolean;
BEGIN
 FOR n IN 6100..6101 LOOP
  closed:=n=6101;c:=m3b_cycle_test.clinical_photos(n);a:=(c->>'user')::uuid;cycle:=(c->>'cycle')::uuid;
  today:=(clock_timestamp() AT TIME ZONE 'America/Sao_Paulo')::date;
  INSERT INTO public.daily_snapshots(user_id,date,calories_target,protein_target,current_protocol,day_closed,closed_at)
  VALUES(a,today,1700,120,'recomposicao',closed,CASE WHEN closed THEN clock_timestamp() END);
  SELECT to_jsonb(s) INTO prior FROM public.daily_snapshots s WHERE user_id=a AND date=today;
  q:=m3b_cycle_test.command_input(c);
  generation:=(q#>>'{context,facts,anchor,signup_generation}')::uuid;
  epoch:=(q#>>'{context,facts,anchor,signup_epoch}')::uuid;
  packet:=public.prepare_mobile_clinical_full_command(a,'REGULAR',cycle,gen_random_uuid(),q#>>'{context,context_hash}',q->'command',q->'form',q->'intent',q->'proposal');
  review:=(packet#>>'{preview,preview_id}')::uuid;
  ack:=public.confirm_mobile_clinical_full_command(a,review,m3b_cycle_test.uid(n+100),q->'command',q->'form',q->'intent',q->'proposal');
  seen:=clock_timestamp();
  decision:=private.mobile_clinical_confirmed_calorie_decision(a,generation,epoch,today,seen);
  PERFORM m3b_cycle_test.ok(decision->>'source'='confirmed_full_calculation_v1' AND decision->>'decision_kind'='calculated','normalized confirmed FULL has a calculation decision');
  PERFORM m3b_cycle_test.ok(decision->>'review_id'=review::text AND decision->>'user_id'=a::text
   AND decision->>'signup_generation'=generation::text AND decision->>'signup_epoch'=epoch::text,'decision bound to exact owner/review/admission/epoch');
  PERFORM m3b_cycle_test.ok(EXISTS(SELECT 1 FROM private.mobile_clinical_episode_events e WHERE e.user_id=a AND e.review_id=review
   AND e.event_id=(decision->>'source_episode_event_id')::uuid),'decision references actual source episode');
  PERFORM m3b_cycle_test.ok(decision->>'command_hash'=packet->>'command_hash'
   AND decision->>'context_hash'=q#>>'{context,context_hash}','decision retains exact normalized command/context hashes');
  PERFORM m3b_cycle_test.ok(decision->'calories_target'='1599'::jsonb AND decision->'formula_target'='1599'::jsonb,'confirmed numeric proposal retained separately from application');
  origin:=private.mobile_clinical_target_origin(a,generation,epoch,today,seen);
  IF closed THEN
   PERFORM m3b_cycle_test.ok((SELECT to_jsonb(s)=prior FROM public.daily_snapshots s WHERE user_id=a AND date=today),'closed snapshot remains byte exact despite new decision');
   PERFORM m3b_cycle_test.ok(origin IS NULL,'confirmed decision on closed day is not an applied origin');
  ELSE
   PERFORM m3b_cycle_test.ok(origin->>'source'='clinical_full_v1' AND origin->>'review_id'=review::text,'open actual write has independent applied FULL origin');
  END IF;
  PERFORM m3b_cycle_test.ok(private.mobile_clinical_confirmed_calorie_decision(gen_random_uuid(),generation,epoch,today,seen) IS NULL,'decision cannot cross owner');
  PERFORM m3b_cycle_test.ok(private.mobile_clinical_confirmed_calorie_decision(a,gen_random_uuid(),epoch,today,seen) IS NULL,'decision cannot cross admission');
  PERFORM m3b_cycle_test.ok(private.mobile_clinical_confirmed_calorie_decision(a,generation,gen_random_uuid(),today,seen) IS NULL,'decision cannot cross epoch');
  PERFORM m3b_cycle_test.ok(private.mobile_clinical_confirmed_calorie_decision(a,generation,epoch,today-1,seen) IS NULL,'decision cannot flow into an earlier civil date');
  PERFORM m3b_cycle_test.ok(private.mobile_clinical_confirmed_calorie_decision(a,generation,epoch,today,'2026-01-01T00:00:00Z') IS NULL,'decision cannot flow into an earlier observation');
  PERFORM m3b_cycle_test.ok(private.mobile_clinical_confirmed_calorie_decision(a,generation,epoch,today+1,seen+interval '1day')=decision,'later date retains exact immutable decision');
  PERFORM m3b_cycle_test.throws(format('UPDATE private.mobile_clinical_calorie_decisions SET calories_target=calories_target WHERE user_id=%L',a),'55000','decision UPDATE refused even if equal');
  PERFORM m3b_cycle_test.throws(format('DELETE FROM private.mobile_clinical_calorie_decisions WHERE user_id=%L',a),'55000','decision DELETE refused independently');
  prior_state:=m3b_cycle_test.original_state(a);
  PERFORM m3b_cycle_test.ok(public.confirm_mobile_clinical_full_command(a,review,m3b_cycle_test.uid(n+100),q->'command',q->'form',q->'intent',q->'proposal')=ack
   AND m3b_cycle_test.original_state(a)=prior_state,'original acknowledgement replays without target/origin/decision effects');
 END LOOP;
 -- Numeric preservation never proves a formula. A known source can be
 -- carried through a guarded FULL without labelling the preservation a new
 -- calculation; an unknown source still remains unknown.
 FOR n IN 6110..6111 LOOP
  c:=m3b_cycle_test.clinical_photos(n);a:=(c->>'user')::uuid;cycle:=(c->>'cycle')::uuid;
  INSERT INTO public.daily_snapshots(user_id,date,calories_target,protein_target,current_protocol)
   VALUES(a,today,1700,120,'recomposicao');
  q:=m3b_cycle_test.command_input(c);
  IF n=6110 THEN
   packet:=public.prepare_mobile_clinical_full_command(a,'REGULAR',cycle,gen_random_uuid(),q#>>'{context,context_hash}',q->'command',q->'form',q->'intent',q->'proposal');
   PERFORM public.confirm_mobile_clinical_full_command(a,(packet#>>'{preview,preview_id}')::uuid,gen_random_uuid(),q->'command',q->'form',q->'intent',q->'proposal');
   origin:=private.mobile_clinical_target_origin(a,(q#>>'{context,facts,anchor,signup_generation}')::uuid,(q#>>'{context,facts,anchor,signup_epoch}')::uuid,today,clock_timestamp());
   cycle:=(private.start_mobile_clinical_full_at(a,gen_random_uuid(),'EARLY_FULL','not_well_with_plan',NULL)#>>'{cycle,id}')::uuid;
   PERFORM public.declare_mobile_health_risk(a,gen_random_uuid(),ARRAY['reduced_intake']);
   q:=jsonb_set(q,'{context}',public.get_mobile_clinical_full_context(a,'EARLY_FULL',cycle));
   q:=jsonb_set(q,'{form,kind}','"EARLY_FULL"');
   q:=jsonb_set(q,'{command,form}',q->'form');
   q:=jsonb_set(q,'{command,bodyFat}','null');q:=jsonb_set(q,'{intent,bodyFat}','null');
  END IF;
  SELECT to_jsonb(s) INTO prior FROM public.daily_snapshots s WHERE user_id=a AND date=today;
  q:=jsonb_set(q,'{proposal,targets}',jsonb_build_object('beforeKcal',prior->'calories_target','beforeProtein',prior->'protein_target',
   'afterKcal',prior->'calories_target','afterProtein',prior->'protein_target','formulaAfterKcal',NULL));
  packet:=public.prepare_mobile_clinical_full_command(a,CASE WHEN n=6110 THEN 'EARLY_FULL' ELSE 'REGULAR' END,cycle,gen_random_uuid(),q#>>'{context,context_hash}',q->'command',q->'form',q->'intent',q->'proposal');
  review:=(packet#>>'{preview,preview_id}')::uuid;
  PERFORM public.confirm_mobile_clinical_full_command(a,review,gen_random_uuid(),q->'command',q->'form',q->'intent',q->'proposal');
  IF n=6110 THEN
   PERFORM m3b_cycle_test.ok(EXISTS(SELECT 1 FROM private.mobile_clinical_calorie_decisions d WHERE d.user_id=a AND d.review_id=review
    AND d.decision_kind='preserved_known' AND d.parent_origin_id=(origin->>'origin_id')::uuid AND d.formula_target=(origin->>'formula_target')::integer),'guarded known preservation inherits the actual parent formula without manufacturing a new one');
   PERFORM m3b_cycle_test.ok(NOT EXISTS(SELECT 1 FROM private.mobile_clinical_target_origins WHERE user_id=a AND review_id=review),'guarded preservation does not create a newly calculated FULL origin');
  ELSE
   PERFORM m3b_cycle_test.ok(NOT EXISTS(SELECT 1 FROM private.mobile_clinical_calorie_decisions WHERE user_id=a),'unknown target with absent formula never gains a confirmed decision');
  END IF;
 END LOOP;
 -- A private historical receipt with no normalized command must not be
 -- reconstructed into a prospective authority.
 c:=m3b_cycle_test.clinical_photos(6102);a:=(c->>'user')::uuid;cycle:=(c->>'cycle')::uuid;
 INSERT INTO public.daily_snapshots(user_id,date,calories_target,protein_target,current_protocol)
 VALUES(a,today,1700,120,'recomposicao');
 q:=m3b_cycle_test.command_input(c);
 packet:=private.prepare_mobile_clinical_preview_at(a,'REGULAR',cycle,gen_random_uuid(),q#>>'{context,context_hash}',q->'form',q->'intent',q->'proposal',NULL);
 PERFORM private.confirm_mobile_clinical_preview_at(a,(packet->>'preview_id')::uuid,gen_random_uuid(),q->'form',q->'intent',q->'proposal',NULL);
 PERFORM m3b_cycle_test.ok(NOT EXISTS(SELECT 1 FROM private.mobile_clinical_calorie_decisions WHERE user_id=a),'missing historical command never manufactures prospective decision');
 PERFORM m3b_cycle_test.ok(EXISTS(SELECT 1 FROM private.mobile_clinical_target_origins WHERE user_id=a),'actual historical application remains independent evidence');
 FOREACH caller IN ARRAY ARRAY['anon','authenticated','service_role'] LOOP
  PERFORM m3b_cycle_test.ok(NOT has_table_privilege(caller,'private.mobile_clinical_calorie_decisions','SELECT,INSERT,UPDATE,DELETE'),'no client/backend direct decision table grant');
  refused:=false;EXECUTE format('SET LOCAL ROLE %I',caller);
  BEGIN PERFORM private.mobile_clinical_confirmed_calorie_decision(a,generation,epoch,today,clock_timestamp());
   EXCEPTION WHEN insufficient_privilege THEN refused:=true;END;
  EXECUTE 'RESET ROLE';PERFORM m3b_cycle_test.ok(refused,'actual restricted role cannot call private decision helper');
 END LOOP;
 PERFORM m3b_cycle_test.ok((SELECT relrowsecurity FROM pg_class WHERE oid='private.mobile_clinical_calorie_decisions'::regclass),'decision table RLS enabled');
END $$;
CREATE FUNCTION m3b_cycle_test.fail_after_calorie_decision() RETURNS trigger
LANGUAGE plpgsql SET search_path=pg_catalog AS $$ BEGIN
 IF NEW.user_id=m3b_cycle_test.uid(6120) AND EXISTS(SELECT 1 FROM private.mobile_clinical_calorie_decisions WHERE user_id=NEW.user_id AND review_id=NEW.review_id)
 THEN RAISE EXCEPTION 'synthetic_after_calorie_decision';END IF;
 RETURN NEW;
END $$;
CREATE TRIGGER zzz_test_fail_after_calorie_decision AFTER INSERT ON private.mobile_clinical_full_receipts
 FOR EACH ROW EXECUTE FUNCTION m3b_cycle_test.fail_after_calorie_decision();
DO $$
DECLARE c jsonb;q jsonb;packet jsonb;prior jsonb;a uuid;review uuid;key uuid:=gen_random_uuid();
BEGIN
 c:=m3b_cycle_test.clinical_photos(6120);a:=(c->>'user')::uuid;
 INSERT INTO public.daily_snapshots(user_id,date,calories_target,protein_target,current_protocol)
 VALUES(a,(clock_timestamp() AT TIME ZONE 'America/Sao_Paulo')::date,1700,120,'recomposicao');
 q:=m3b_cycle_test.command_input(c);
 packet:=public.prepare_mobile_clinical_full_command(a,'REGULAR',(c->>'cycle')::uuid,gen_random_uuid(),q#>>'{context,context_hash}',q->'command',q->'form',q->'intent',q->'proposal');
 review:=(packet#>>'{preview,preview_id}')::uuid;prior:=m3b_cycle_test.original_state(a);
 PERFORM m3b_cycle_test.throws(format('SELECT public.confirm_mobile_clinical_full_command(%L,%L,%L,%L,%L,%L,%L)',a,review,key,q->'command',q->'form',q->'intent',q->'proposal'),'P0001','later failure reached only after decision and applied origin insertion');
 PERFORM m3b_cycle_test.ok(m3b_cycle_test.original_state(a)=prior,'later error rolls back every target/decision/origin/receipt effect atomically');
 EXECUTE 'DROP TRIGGER zzz_test_fail_after_calorie_decision ON private.mobile_clinical_full_receipts';
 PERFORM public.confirm_mobile_clinical_full_command(a,review,key,q->'command',q->'form',q->'intent',q->'proposal');
 PERFORM m3b_cycle_test.ok(EXISTS(SELECT 1 FROM private.mobile_clinical_calorie_decisions WHERE user_id=a AND review_id=review),'same previously failed key can complete once after rollback');
 PERFORM m3b_cycle_test.remove_photos(ARRAY[a]);
 DELETE FROM private.mobile_reevaluation_cycles WHERE user_id=a;
 DELETE FROM private.mobile_signup_strength_completion_receipts WHERE user_id=a;
 DELETE FROM public.users WHERE id=a;
 PERFORM m3b_cycle_test.ok(NOT EXISTS(SELECT 1 FROM private.mobile_clinical_calorie_decisions WHERE user_id=a),'real owner purge cascades immutable decisions without disabling guards');
END $$;
SET CONSTRAINTS ALL IMMEDIATE;
ROLLBACK;
