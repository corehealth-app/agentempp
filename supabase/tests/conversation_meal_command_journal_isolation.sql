-- Snapshot isolation must fail before journal mutation, even with no owner/epoch.
BEGIN ISOLATION LEVEL REPEATABLE READ;
DO $$
DECLARE code text;u uuid:='c3a00000-0000-4000-8000-000000000001';c uuid:='c3a00000-0000-4000-8000-000000000002';h text:=repeat('a',64);op text;
BEGIN
 PERFORM set_config('request.jwt.claims','{"role":"service_role"}',true);
 FOREACH op IN ARRAY ARRAY['admit','attach','read'] LOOP
  code:=NULL;
  BEGIN
   IF op='admit' THEN PERFORM public.admit_conversation_meal_command(u,jsonb_build_object('command_protocol','conversation.command.v1','command_id',c,'kind','meal.report','source',jsonb_build_object('channel','text','text','Comi arroz')));
   ELSIF op='attach' THEN PERFORM public.attach_conversation_meal_candidate(u,c,h,jsonb_build_object('schema','conversation.meal-candidate.v1','input_hash',h,'status','prepared','candidate','{}'::jsonb));
   ELSE PERFORM public.read_conversation_meal_command(u,c); END IF;
  EXCEPTION WHEN OTHERS THEN GET STACKED DIAGNOSTICS code=RETURNED_SQLSTATE; END;
  IF code IS DISTINCT FROM '22023' THEN RAISE EXCEPTION 'isolation guard failed: %',op; END IF;
 END LOOP;
END $$;
ROLLBACK;
BEGIN ISOLATION LEVEL SERIALIZABLE;
DO $$
DECLARE code text;
BEGIN
 PERFORM set_config('request.jwt.claims','{"role":"service_role"}',true);
 BEGIN PERFORM public.admit_conversation_meal_command('c3a00000-0000-4000-8000-000000000001','{"command_protocol":"conversation.command.v1","command_id":"c3a00000-0000-4000-8000-000000000002","kind":"meal.report","source":{"channel":"text","text":"Comi arroz"}}');
 EXCEPTION WHEN OTHERS THEN GET STACKED DIAGNOSTICS code=RETURNED_SQLSTATE; END;
 IF code IS DISTINCT FROM '22023' THEN RAISE EXCEPTION 'serializable admission guard failed'; END IF;
END $$;
ROLLBACK;
