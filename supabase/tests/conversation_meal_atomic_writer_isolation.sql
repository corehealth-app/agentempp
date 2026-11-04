-- No owner data required: isolation guard must precede fresh authority lookup.
BEGIN ISOLATION LEVEL REPEATABLE READ;
DO $$
DECLARE op text;code text;u uuid:='c3f00000-0000-4000-8000-000000000001';c uuid:='c3f00000-0000-4000-8000-000000000002';
BEGIN
 PERFORM set_config('request.jwt.claims','{"role":"service_role"}',true);
 FOREACH op IN ARRAY ARRAY['capture','nutrition','prepare','commit','read'] LOOP
  code:=NULL;BEGIN
   IF op='capture' THEN PERFORM public.capture_conversation_meal_source(u,c);
   ELSIF op='nutrition' THEN PERFORM public.read_conversation_meal_nutrition_source(u,c,'trusted_recent',NULL);
   ELSIF op='prepare' THEN PERFORM public.prepare_conversation_meal(u,c,NULL);
   ELSIF op='commit' THEN PERFORM public.commit_conversation_meal(u,c,NULL);
   ELSE PERFORM public.read_conversation_meal_effect(u,c); END IF;
  EXCEPTION WHEN OTHERS THEN GET STACKED DIAGNOSTICS code=RETURNED_SQLSTATE;END;
  IF code IS DISTINCT FROM '22023' THEN RAISE EXCEPTION 'atomic meal RR isolation guard failed: % %',op,code;END IF;
 END LOOP;
END $$;
ROLLBACK;
BEGIN ISOLATION LEVEL SERIALIZABLE;
DO $$
DECLARE code text;
BEGIN
 PERFORM set_config('request.jwt.claims','{"role":"service_role"}',true);
 BEGIN PERFORM public.commit_conversation_meal('c3f00000-0000-4000-8000-000000000001','c3f00000-0000-4000-8000-000000000002',NULL);EXCEPTION WHEN OTHERS THEN GET STACKED DIAGNOSTICS code=RETURNED_SQLSTATE;END;
 IF code IS DISTINCT FROM '22023' THEN RAISE EXCEPTION 'atomic meal serializable isolation guard failed';END IF;
END $$;
ROLLBACK;
