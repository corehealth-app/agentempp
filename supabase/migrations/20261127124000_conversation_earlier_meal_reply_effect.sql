-- Complete a linked answer against the original open meal date. Existing
-- same-day answers keep their original wire contract and replay semantics.
BEGIN;
SET LOCAL lock_timeout='5s';

DO $migration$
DECLARE
  writer text:=pg_get_functiondef(
    'public.commit_conversation_meal_continuation(uuid,uuid,uuid,text,uuid,text,text)'::regprocedure);
  reader text:=pg_get_functiondef('private.conversation_continuation_reply(uuid,uuid,uuid,text,jsonb)'::regprocedure);
  thread text:=pg_get_functiondef(
    'private.conversation_thread_effect_v2(private.conversation_meal_effects,private.conversation_meal_command_ids,jsonb)'::regprocedure);
  feedback text:=pg_get_functiondef('private.registration_feedback_v3_meal_command(private.conversation_meal_effects)'::regprocedure);
  change text[];
  read_old constant text:=$old$fx.receipt->>'schema' IS DISTINCT FROM 'conversation.meal-continuation-effect.v1'$old$;
  read_new constant text:=$new$coalesce(fx.receipt->>'schema','') NOT IN('conversation.meal-continuation-effect.v1','conversation.meal-continuation-effect.v2')
  OR (fx.receipt->>'schema'='conversation.meal-continuation-effect.v2' AND
    ((fx.receipt->>'committed_at')::timestamptz IS DISTINCT FROM fx.committed_at
      OR fx.receipt#>'{local_date}' IS DISTINCT FROM s.context#>'{authority,context,day,date}'
      OR fx.receipt#>'{timezone}' IS DISTINCT FROM s.context#>'{authority,context,owner,timezone}'))$new$;
  thread_old constant text:=$old$  IF parent IS NULL OR v->>'schema' IS DISTINCT FROM 'conversation.meal-continuation-effect.v1'$old$;
  thread_new constant text:=$new$  earlier:=v->>'schema' IS NOT DISTINCT FROM 'conversation.meal-continuation-effect.v2';
  IF earlier THEN keys:=keys||ARRAY['committed_at'];END IF;
  IF parent IS NULL OR (NOT earlier AND v->>'schema' IS DISTINCT FROM 'conversation.meal-continuation-effect.v1')$new$;
  feedback_old constant text:=$old$ ELSIF e.receipt->>'schema'='conversation.meal-continuation-effect.v1' THEN$old$;
  feedback_new constant text:=$new$ ELSIF e.receipt->>'schema' IN('conversation.meal-continuation-effect.v1','conversation.meal-continuation-effect.v2') THEN
  IF e.receipt->>'schema'='conversation.meal-continuation-effect.v2'
    AND private.conversation_thread_effect_v2(e,c,private.conversation_thread_parent_v2(
      e.user_id,(e.receipt->>'parent_command_id')::uuid,c.epoch)->'descriptor')
      IS DISTINCT FROM e.receipt THEN RETURN NULL;END IF;$new$;
BEGIN
  FOREACH change SLICE 1 IN ARRAY ARRAY[
    ARRAY[$old$clock timestamptz;day date;zone text;$old$,
          $new$clock timestamptz;consumed timestamptz;day date;current_day date;zone text;$new$],
    ARRAY[$old$ IF (clock AT TIME ZONE zone)::date IS DISTINCT FROM day THEN RETURN '{"action":"source_conflict"}'::jsonb;END IF;$old$,
          $new$ current_day:=coalesce(fresh#>>'{clinical,date}',fresh#>>'{day,date}')::date;
 IF (clock AT TIME ZONE zone)::date IS DISTINCT FROM current_day OR day>current_day THEN
  RETURN '{"action":"source_conflict"}'::jsonb;
 END IF;
 consumed:=clock;
 IF day<current_day THEN
  IF day>=((parent#>>'{binding,admitted_at}')::timestamptz AT TIME ZONE zone)::date
    THEN RETURN '{"action":"source_conflict"}'::jsonb;END IF;
  consumed:=(day+TIME '12:00') AT TIME ZONE zone;
  IF (consumed AT TIME ZONE zone)::date IS DISTINCT FROM day OR consumed>=clock THEN
   RETURN '{"action":"source_conflict"}'::jsonb;
  END IF;
 END IF;$new$],
    ARRAY[$old$to_char(clock AT TIME ZONE 'UTC','YYYY-MM-DD"T"HH24:MI:SS.US"Z"'),'source_timezone'$old$,
          $new$to_char(consumed AT TIME ZONE 'UTC','YYYY-MM-DD"T"HH24:MI:SS.US"Z"'),'source_timezone'$new$],
    ARRAY[$old$atomic_items,false,NULL,clock,provider,$old$,$new$atomic_items,false,NULL,consumed,provider,$new$],
    ARRAY[$old$(x->>'consumed_at')::timestamptz=clock$old$,$new$(x->>'consumed_at')::timestamptz=consumed$new$],
    ARRAY[$old$ -- Optional enrichment cannot$old$,
          $new$ IF day<current_day THEN
  receipt:=receipt||jsonb_build_object('schema','conversation.meal-continuation-effect.v2',
   'committed_at',to_char(clock AT TIME ZONE 'UTC','YYYY-MM-DD"T"HH24:MI:SS.US"Z"'));
 END IF;
 -- Optional enrichment cannot$new$]
  ] LOOP
    IF length(writer)-length(replace(writer,change[1],''))<>length(change[1]) THEN
      RAISE EXCEPTION 'unexpected_earlier_linked_meal_writer_definition';
    END IF;
    writer:=replace(writer,change[1],change[2]);
  END LOOP;
  IF length(writer)-length(replace(writer,
      '(clock_timestamp() AT TIME ZONE zone)::date IS DISTINCT FROM day',''))
      <>2*length('(clock_timestamp() AT TIME ZONE zone)::date IS DISTINCT FROM day') THEN
    RAISE EXCEPTION 'unexpected_earlier_linked_meal_commit_fences';
  END IF;
  EXECUTE replace(writer,'(clock_timestamp() AT TIME ZONE zone)::date IS DISTINCT FROM day',
    '(clock_timestamp() AT TIME ZONE zone)::date IS DISTINCT FROM current_day');
  IF length(reader)-length(replace(reader,read_old,''))<>length(read_old)
    OR length(thread)-length(replace(thread,thread_old,''))<>length(thread_old)
    OR length(feedback)-length(replace(feedback,feedback_old,''))<>length(feedback_old) THEN
    RAISE EXCEPTION 'unexpected_earlier_linked_meal_read_definition';
  END IF;
  EXECUTE replace(reader,read_old,read_new);
  EXECUTE replace(thread,thread_old,thread_new);
  EXECUTE replace(feedback,feedback_old,feedback_new);
END $migration$;

COMMIT;
