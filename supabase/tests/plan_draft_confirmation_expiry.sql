-- Confirmation priorities and original-result replay. Synthetic, rollback only.
BEGIN;
INSERT INTO public.users(id,email,wpp,name,status,metadata) VALUES
 ('c59d2a00-0000-4000-8000-000000000001',NULL,NULL,'Synthetic deadline priorities','active',
  '{"qa_owner":"plan-deadline-priorities"}'::jsonb);
SELECT set_config('request.jwt.claims','{"role":"service_role"}',true);
DO $test$
DECLARE
 u constant uuid:='c59d2a00-0000-4000-8000-000000000001';
 d uuid; answer jsonb; original_answer jsonb; before jsonb; after jsonb; code text; plan uuid;
 payload constant jsonb:='{"plan_type":"full_body","weekly_schedule":[{"day":"seg","focus":"full body","exercises":[]}]}';
BEGIN
 d:=(public.create_plan_draft_atomic(u,'training','flow_generated','ready_for_review',payload,
  NULL,NULL,NULL,NULL,NULL,NULL,'plan-deadline-priorities-0001')->>'id')::uuid;
 UPDATE public.plan_drafts SET expires_at=clock_timestamp()-interval '1 minute' WHERE id=d;
 code:=NULL;
 BEGIN
  PERFORM public.confirm_plan_draft_atomic(u,d,2,clock_timestamp()-interval '1 minute','priority-confirm-0001');
 EXCEPTION WHEN OTHERS THEN code:=SQLSTATE; END;
 IF code IS DISTINCT FROM '22023' THEN RAISE EXCEPTION 'expired input must precede draft/version: %',code; END IF;
 RAISE NOTICE 'PLAN_EXPIRY_PRIORITY:input22023';

 code:=NULL;
 BEGIN PERFORM public.confirm_plan_draft_atomic(u,d,2,NULL,'priority-confirm-0002');
 EXCEPTION WHEN OTHERS THEN code:=SQLSTATE; END;
 IF code IS DISTINCT FROM 'PD410' THEN RAISE EXCEPTION 'expired draft must precede version: %',code; END IF;
 RAISE NOTICE 'PLAN_EXPIRY_PRIORITY:draftPD410';

 UPDATE public.plan_drafts SET status='needs_completion' WHERE id=d;
 code:=NULL;
 BEGIN PERFORM public.confirm_plan_draft_atomic(u,d,1,NULL,'priority-confirm-0003');
 EXCEPTION WHEN OTHERS THEN code:=SQLSTATE; END;
 IF code IS DISTINCT FROM 'PD422' THEN RAISE EXCEPTION 'unreviewable must precede expiry: %',code; END IF;
 RAISE NOTICE 'PLAN_EXPIRY_PRIORITY:statusPD422';

 UPDATE public.plan_drafts SET status='ready_for_review',expires_at=clock_timestamp()+interval '1 day' WHERE id=d;
 code:=NULL;
 BEGIN PERFORM public.confirm_plan_draft_atomic(u,d,2,NULL,'priority-confirm-0004');
 EXCEPTION WHEN OTHERS THEN code:=SQLSTATE; END;
 IF code IS DISTINCT FROM 'PD409' THEN RAISE EXCEPTION 'valid review must enforce version: %',code; END IF;
 code:=NULL;
 BEGIN PERFORM public.confirm_plan_draft_atomic(NULL,NULL,0,NULL,NULL);
 EXCEPTION WHEN OTHERS THEN code:=SQLSTATE; END;
 IF code IS DISTINCT FROM '22023' THEN RAISE EXCEPTION 'invalid arguments must precede lookup: %',code; END IF;
 IF EXISTS(SELECT 1 FROM public.training_plans WHERE user_id=u)
  OR (SELECT status FROM public.plan_drafts WHERE id=d)<>'ready_for_review'
 THEN RAISE EXCEPTION 'refusals wrote a plan or terminalized the draft'; END IF;
 RAISE NOTICE 'PLAN_EXPIRY_PRIORITY:versionAndInvalidArguments';

 answer:=public.confirm_plan_draft_atomic(u,d,1,NULL,'priority-confirm-0005');
 plan:=(answer->>'confirmed_plan_id')::uuid;
 IF answer->>'status' IS DISTINCT FROM 'confirmed' OR (answer->>'already_confirmed')::boolean IS NOT FALSE
  OR NOT EXISTS(SELECT 1 FROM public.training_plans WHERE id=plan AND user_id=u AND active AND valid_until IS NULL)
  OR (SELECT metadata ? 'training_reminders' FROM public.users WHERE id=u)
 THEN RAISE EXCEPTION 'NULL validity must confirm without enabling reminders'; END IF;
 original_answer:=answer;
 SELECT jsonb_build_object('user',(SELECT to_jsonb(t) FROM public.users t WHERE id=u),
  'draft',(SELECT to_jsonb(t) FROM public.plan_drafts t WHERE id=d),
  'plans',(SELECT jsonb_agg(to_jsonb(t) ORDER BY id) FROM public.training_plans t WHERE user_id=u)) INTO before;
 answer:=public.confirm_plan_draft_atomic(u,d,9,clock_timestamp()+interval '42 days','priority-different-key-0006');
 SELECT jsonb_build_object('user',(SELECT to_jsonb(t) FROM public.users t WHERE id=u),
  'draft',(SELECT to_jsonb(t) FROM public.plan_drafts t WHERE id=d),
  'plans',(SELECT jsonb_agg(to_jsonb(t) ORDER BY id) FROM public.training_plans t WHERE user_id=u)) INTO after;
 IF answer IS DISTINCT FROM (original_answer || jsonb_build_object('already_confirmed',true))
  OR (answer->>'confirmed_plan_id')::uuid IS DISTINCT FROM plan
  OR before IS DISTINCT FROM after THEN RAISE EXCEPTION 'replay renewed or changed original result'; END IF;
 RAISE NOTICE 'PLAN_EXPIRY_PRIORITY:NULLAndOriginalReplay';

 code:=NULL;
 BEGIN PERFORM public.confirm_plan_draft_atomic(u,d,0,NULL,'priority-confirm-0007');
 EXCEPTION WHEN OTHERS THEN code:=SQLSTATE; END;
 IF code IS DISTINCT FROM '22023' THEN RAISE EXCEPTION 'replay bypassed preliminary invalid argument guard: %',code; END IF;
 SELECT jsonb_build_object('user',(SELECT to_jsonb(t) FROM public.users t WHERE id=u),
  'draft',(SELECT to_jsonb(t) FROM public.plan_drafts t WHERE id=d),
  'plans',(SELECT jsonb_agg(to_jsonb(t) ORDER BY id) FROM public.training_plans t WHERE user_id=u)) INTO after;
 IF before IS DISTINCT FROM after THEN RAISE EXCEPTION 'invalid replay changed original result'; END IF;
 RAISE NOTICE 'PLAN_EXPIRY_PRIORITY:replayStillValidatesArguments';
END $test$;
ROLLBACK;
