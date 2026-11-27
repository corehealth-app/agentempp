-- Store an explicitly dated Flow report against the correct open civil day.
-- Only a verified, sealed neutral selection can activate an earlier date.
BEGIN;
SET LOCAL lock_timeout='5s';

CREATE FUNCTION private.conversation_verified_meal_day(
  u uuid, c uuid, command_hash text, command_epoch uuid, zone text, admitted timestamptz
) RETURNS date
LANGUAGE plpgsql STABLE SET search_path=pg_catalog SET timezone='UTC' SET datestyle='ISO,YMD' AS $$
DECLARE
  selection jsonb;
  captured jsonb;
  captured_hash text;
  original_day date;
  original_zone text;
  offset_days integer;
BEGIN
  SELECT x.selection,s.context,s.source_hash,n.admitted_local_date,n.admitted_time_zone
    INTO selection,captured,captured_hash,original_day,original_zone
    FROM private.conversation_intake_ids i
    JOIN private.conversation_intake_inputs n USING(user_id,intake_id)
    JOIN private.conversation_intake_sources s USING(user_id,intake_id)
    JOIN private.conversation_intake_selections x USING(user_id,intake_id)
    WHERE i.user_id=u AND i.reserved_child_id=c AND i.epoch=command_epoch
      AND i.invalidated_at IS NULL;
  offset_days:=CASE selection#>>'{decision,reason}'
    WHEN 'verified_meal_yesterday' THEN 1 WHEN 'verified_meal_two_days_ago' THEN 2 END;
  IF offset_days IS NULL THEN RETURN NULL; END IF;
  IF original_day IS NULL OR original_zone IS DISTINCT FROM zone
    OR captured->>'time_zone' IS DISTINCT FROM zone
    OR captured->>'local_date' IS DISTINCT FROM original_day::text
    OR selection->>'source_hash' IS DISTINCT FROM captured_hash
    OR selection#>>'{decision,kind}' IS DISTINCT FROM 'meal.report'
    OR selection#>>'{command,kind}' IS DISTINCT FROM 'meal.report'
    OR selection#>>'{command,owner_id}' IS DISTINCT FROM u::text
    OR selection#>>'{command,command_id}' IS DISTINCT FROM c::text
    OR selection#>>'{command,input_hash}' IS DISTINCT FROM command_hash
    OR selection#>>'{command,epoch}' IS DISTINCT FROM command_epoch::text
    OR (selection#>>'{command,admitted_at}')::timestamptz IS DISTINCT FROM admitted
    OR (admitted AT TIME ZONE zone)::date IS DISTINCT FROM original_day THEN
    RAISE EXCEPTION 'verified_meal_day_binding_changed' USING ERRCODE='40001';
  END IF;
  RETURN original_day-offset_days;
END $$;

REVOKE ALL ON FUNCTION private.conversation_verified_meal_day(uuid,uuid,text,uuid,text,timestamptz)
  FROM PUBLIC,anon,authenticated,service_role;

DO $migration$
DECLARE
  source_def text:=pg_get_functiondef('private.conversation_meal_source_at(uuid,uuid,timestamptz)'::regprocedure);
  commit_def text:=pg_get_functiondef('private.commit_conversation_meal_at(uuid,uuid,text,timestamptz)'::regprocedure);
  change text[];
BEGIN
  FOREACH change SLICE 1 IN ARRAY ARRAY[
    ARRAY[$old$revision bigint;day date;observed timestamptz;$old$,
          $new$revision bigint;day date;current_day date;verified_day date;closed boolean;observed timestamptz;$new$],
    ARRAY[$old$ day:=(clinical->>'date')::date;$old$,
          $new$ current_day:=(clinical->>'date')::date;
 verified_day:=private.conversation_verified_meal_day(p_user,p_command,c.input_hash,c.epoch,u.timezone,c.admitted_at);
 IF verified_day IS NOT NULL AND (c.admitted_at AT TIME ZONE u.timezone)::date IS DISTINCT FROM current_day THEN
  RAISE EXCEPTION 'conversation_verified_meal_day_changed' USING ERRCODE='40001';
 END IF;
 day:=coalesce(verified_day,current_day);$new$],
    ARRAY[$old$ SELECT * INTO s FROM public.daily_snapshots WHERE user_id=p_user AND date=day FOR UPDATE NOWAIT;
 IF FOUND THEN SELECT r.revision INTO revision FROM private.mobile_flow_plan_day_revisions r WHERE r.snapshot_id=s.id AND r.user_id=p_user; END IF;$old$,
          $new$ IF verified_day IS NOT NULL AND NOT pg_try_advisory_xact_lock(
   hashtextextended(p_user::text||':daily-close',0)) THEN
  RAISE EXCEPTION 'conversation_meal_daily_close_busy' USING ERRCODE='55P03';
 END IF;
 SELECT * INTO s FROM public.daily_snapshots WHERE user_id=p_user AND date=day FOR UPDATE NOWAIT;
 IF FOUND THEN SELECT r.revision INTO revision FROM private.mobile_flow_plan_day_revisions r WHERE r.snapshot_id=s.id AND r.user_id=p_user; END IF;
 closed:=coalesce(s.day_closed,false);
 IF verified_day IS NOT NULL THEN
  PERFORM 1 FROM public.user_progress WHERE user_id=p_user FOR UPDATE NOWAIT;
  closed:=closed OR EXISTS(SELECT 1 FROM public.daily_snapshots
    WHERE user_id=p_user AND date>=day AND day_closed)
    OR EXISTS(SELECT 1 FROM public.user_progress WHERE user_id=p_user AND last_active_date>=day);
 END IF;$new$],
    ARRAY[$old$ IF (observed AT TIME ZONE u.timezone)::date IS DISTINCT FROM day THEN$old$,
          $new$ IF (observed AT TIME ZONE u.timezone)::date IS DISTINCT FROM current_day THEN$new$],
    ARRAY[$old$'day_closed',coalesce(s.day_closed,false)$old$,$new$'day_closed',closed$new$]
  ] LOOP
    IF length(source_def)-length(replace(source_def,change[1],''))<>length(change[1]) THEN
      RAISE EXCEPTION 'unexpected_verified_meal_source_definition';
    END IF;
    source_def:=replace(source_def,change[1],change[2]);
  END LOOP;
  FOREACH change SLICE 1 IN ARRAY ARRAY[
    ARRAY[$old$fresh jsonb;clock timestamptz;day date;zone text;$old$,
          $new$fresh jsonb;clock timestamptz;consumed timestamptz;day date;current_day date;zone text;$new$],
    ARRAY[$old$ IF fresh IS DISTINCT FROM s.context THEN RETURN '{"action":"source_conflict"}'::jsonb; END IF;
 IF (fresh#>>'{day,day_closed}')::boolean THEN RETURN '{"action":"day_closed"}'::jsonb; END IF;$old$,
          $new$ IF (fresh#>>'{day,day_closed}')::boolean AND fresh#>'{day,date}'=s.context#>'{day,date}'
  AND fresh#>'{day,date}'<>fresh#>'{clinical,date}' THEN
  RETURN '{"action":"day_closed"}'::jsonb;
 END IF;
 IF fresh IS DISTINCT FROM s.context THEN RETURN '{"action":"source_conflict"}'::jsonb; END IF;
 IF (fresh#>>'{day,day_closed}')::boolean THEN RETURN '{"action":"day_closed"}'::jsonb; END IF;$new$],
    ARRAY[$old$ IF (clock AT TIME ZONE zone)::date IS DISTINCT FROM day THEN RETURN '{"action":"source_conflict"}'::jsonb; END IF;$old$,
          $new$ current_day:=(fresh#>>'{clinical,date}')::date;
 IF (clock AT TIME ZONE zone)::date IS DISTINCT FROM current_day OR day>current_day THEN
  RETURN '{"action":"source_conflict"}'::jsonb;
 END IF;
 consumed:=clock;
 IF day<current_day THEN
  -- Preserve the day reported by the person. The exact time was not supplied.
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
  receipt:=receipt||jsonb_build_object('schema','conversation.meal-effect.v2',
   'committed_at',to_char(clock AT TIME ZONE 'UTC','YYYY-MM-DD"T"HH24:MI:SS.US"Z"'));
 END IF;
 -- Optional enrichment cannot$new$],
    ARRAY[$old$IF (coalesce(p_observed,clock_timestamp()) AT TIME ZONE zone)::date IS DISTINCT FROM day THEN$old$,
          $new$IF (coalesce(p_observed,clock_timestamp()) AT TIME ZONE zone)::date IS DISTINCT FROM current_day THEN$new$]
  ] LOOP
    IF length(commit_def)-length(replace(commit_def,change[1],''))<>length(change[1]) THEN
      RAISE EXCEPTION 'unexpected_verified_meal_commit_definition';
    END IF;
    commit_def:=replace(commit_def,change[1],change[2]);
  END LOOP;
  EXECUTE source_def;
  EXECUTE commit_def;
END $migration$;

COMMIT;
