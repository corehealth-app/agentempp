-- Readers for the versioned historical meal effect. The writer remains
-- unchanged until the entry path can bind an explicit owned civil date.
BEGIN;
SET LOCAL lock_timeout='5s';

DO $migration$
DECLARE
  thread_text text:=pg_get_functiondef(
    'private.conversation_thread_effect_v2(private.conversation_meal_effects,private.conversation_meal_command_ids,jsonb)'::regprocedure);
  change text[];
  journal_text text:=pg_get_functiondef('private.conversation_meal_journal_receipt(jsonb,boolean)'::regprocedure);
  journal_keys constant text:=$old$'consumed_at','log_ids','effect_version'] END$old$;
BEGIN
  FOREACH change SLICE 1 IN ARRAY ARRAY[
    ARRAY[$old$stamp timestamptz;registration uuid;$old$,
          $new$stamp timestamptz;committed timestamptz;registration uuid;earlier boolean:=false;$new$],
    ARRAY[$old$  IF v->>'schema' IS DISTINCT FROM 'conversation.meal-effect.v1' OR v->>'provider_key' IS DISTINCT FROM 'conversation.meal/'||c.user_id::text||'/'||c.command_id::text THEN RETURN NULL;END IF;$old$,
          $new$  earlier:=v->>'schema' IS NOT DISTINCT FROM 'conversation.meal-effect.v2';
  IF (NOT earlier AND v->>'schema' IS DISTINCT FROM 'conversation.meal-effect.v1')
   OR v->>'provider_key' IS DISTINCT FROM 'conversation.meal/'||c.user_id::text||'/'||c.command_id::text THEN RETURN NULL;END IF;
  IF earlier THEN keys:=keys||ARRAY['committed_at'];END IF;$new$],
    ARRAY[$old$ IF registration IS NULL OR NOT isfinite(stamp) OR NOT isfinite(e.committed_at) OR stamp IS DISTINCT FROM e.committed_at OR stamp<c.admitted_at$old$,
          $new$ committed:=stamp;
 IF earlier THEN
  IF jsonb_typeof(v->'committed_at') IS DISTINCT FROM 'string' THEN RETURN NULL;END IF;
  committed:=(v->>'committed_at')::timestamptz;
  IF NOT isfinite(committed) OR stamp>=committed
   OR (v->>'local_date')::date >= (c.admitted_at AT TIME ZONE (v->>'timezone'))::date
   OR e.original_facts#>>'{snapshot,date}' IS DISTINCT FROM v->>'local_date'
   OR e.original_facts#>>'{confirmed,proposal,source_local_date}' IS DISTINCT FROM v->>'local_date'
   OR (e.original_facts#>>'{confirmed,proposal,source_timestamp}')::timestamptz IS DISTINCT FROM stamp
   THEN RETURN NULL;END IF;
 END IF;
 IF registration IS NULL OR NOT isfinite(stamp) OR NOT isfinite(e.committed_at) OR committed IS DISTINCT FROM e.committed_at OR committed<c.admitted_at$new$]
  ] LOOP
    IF length(thread_text)-length(replace(thread_text,change[1],''))<>length(change[1]) THEN
      RAISE EXCEPTION 'unexpected_conversation_thread_effect_definition';
    END IF;
    thread_text:=replace(thread_text,change[1],change[2]);
  END LOOP;
  IF length(journal_text)-length(replace(journal_text,journal_keys,''))<>length(journal_keys) THEN
    RAISE EXCEPTION 'unexpected_conversation_earlier_receipt_projection';
  END IF;
  EXECUTE thread_text;
  EXECUTE replace(journal_text,journal_keys,$new$'consumed_at','log_ids','effect_version']
    || CASE WHEN v->>'schema'='conversation.meal-effect.v2' THEN ARRAY['committed_at'] ELSE ARRAY[]::text[] END
  END$new$);
END $migration$;

COMMIT;
