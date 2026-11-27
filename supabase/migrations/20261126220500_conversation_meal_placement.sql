-- Move an existing Flow meal as a group. The receipt of the original
-- registration and its nutrition are immutable; the edit ledger follows
-- the current placement and records the bounded compensation.
BEGIN;
SET LOCAL lock_timeout = '5s';

ALTER TABLE private.conversation_meal_edit_ids
  DROP CONSTRAINT conversation_meal_edit_ids_kind_check,
  ADD CONSTRAINT conversation_meal_edit_ids_kind_check CHECK (
    kind IN ('save','undo_save','undo_registration','placement','undo_placement')
  );

CREATE OR REPLACE FUNCTION private.conversation_meal_edit_state(p_user uuid,p_command uuid) RETURNS jsonb
LANGUAGE sql STABLE SET search_path=pg_catalog SET timezone='UTC' SET datestyle='ISO,YMD' AS $$
 SELECT CASE WHEN jsonb_array_length(g.items) BETWEEN 1 AND 30 AND NOT EXISTS(
  SELECT 1 FROM jsonb_array_elements(g.items) x WHERE x->>'snapshot_id' IS DISTINCT FROM s.id::text)
 THEN jsonb_build_object('context',jsonb_build_object('id',u.id,'auth_user_id',u.auth_user_id,'country',u.country,
  'country_confirmed',u.country_confirmed,'timezone',u.timezone,'status',u.status,'wpp',u.wpp,'updated_at',u.updated_at),
  'snapshot',to_jsonb(s),'items',g.items) ELSE NULL END
 FROM private.conversation_meal_effects e JOIN public.users u ON u.id=e.user_id
 LEFT JOIN private.conversation_meal_edit_heads h USING (user_id,command_id)
 JOIN public.daily_snapshots s ON s.user_id=u.id AND s.id=coalesce(
  (h.after_group#>>'{0,snapshot_id}')::uuid,(e.original_facts#>>'{snapshot,id}')::uuid)
 CROSS JOIN LATERAL(SELECT private.conversation_meal_edit_group(p_user,p_command) items) g
 WHERE e.user_id=p_user AND e.command_id=p_command;
$$;

CREATE FUNCTION public.apply_conversation_meal_placement(
  p_user_id uuid,p_command_id uuid,p_operation_id uuid,p_input jsonb,p_expected_state jsonb
) RETURNS jsonb
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path=pg_catalog
 SET timezone='UTC' SET datestyle='ISO,YMD' AS $$
DECLARE
  kind text := p_input->>'kind';
  gate text;
  request_hash text;
  prior private.conversation_meal_edit_ids%ROWTYPE;
  command_row private.conversation_meal_command_ids%ROWTYPE;
  effect private.conversation_meal_effects%ROWTYPE;
  head private.conversation_meal_edit_heads%ROWTYPE;
  previous private.conversation_meal_edit_operations%ROWTYPE;
  owner public.users%ROWTYPE;
  origin public.daily_snapshots%ROWTYPE;
  destination public.daily_snapshots%ROWTYPE;
  state jsonb;
  before_group jsonb;
  after_group jsonb;
  receipt jsonb;
  edited_at timestamptz;
  undo_until timestamptz;
  local_today date;
  from_day date;
  to_day date;
  locked_day date;
  target_meal public.meal_type_enum;
  revision integer;
  changed integer;
BEGIN
  PERFORM private.assert_trusted_backend();
  IF p_operation_id IS NULL OR jsonb_typeof(p_input) IS DISTINCT FROM 'object'
     OR octet_length(p_input::text)>4096 OR kind IS NULL
     OR kind NOT IN ('placement','undo_placement')
     OR p_input->>'schema' IS DISTINCT FROM 'conversation.meal-edit.v1'
     OR coalesce(p_input->>'expected_version' !~ '^v1:[a-f0-9]{64}$',true) THEN
    RAISE EXCEPTION 'invalid meal placement input' USING ERRCODE='22023';
  END IF;
  PERFORM private.conversation_semantic_uint(p_input->'expected_revision',2147483647);
  IF kind='placement' THEN
    PERFORM private.conversation_meal_keys(p_input,
      ARRAY['schema','kind','expected_revision','expected_version','local_date','meal_type']);
    IF coalesce(p_input->>'local_date' !~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}$',true)
       OR (p_input->>'local_date')::date::text IS DISTINCT FROM p_input->>'local_date'
       OR coalesce(p_input->>'meal_type' NOT IN ('cafe','almoco','lanche','jantar','ceia','outro'),true) THEN
      RAISE EXCEPTION 'invalid meal placement destination' USING ERRCODE='22023';
    END IF;
  ELSE
    PERFORM private.conversation_meal_keys(p_input,
      ARRAY['schema','kind','expected_revision','expected_version','target_operation_id']);
    IF coalesce(p_input->>'target_operation_id' !~ '^[a-f0-9]{8}(-[a-f0-9]{4}){3}-[a-f0-9]{12}$',true) THEN
      RAISE EXCEPTION 'invalid meal placement undo' USING ERRCODE='22023';
    END IF;
  END IF;

  gate:=private.lock_conversation_meal(p_user_id,p_command_id);
  IF gate<>'current' THEN RETURN jsonb_build_object('action',gate); END IF;
  SELECT * INTO STRICT command_row FROM private.conversation_meal_command_ids
    WHERE user_id=p_user_id AND command_id=p_command_id;
  request_hash:=encode(sha256(convert_to(private.conversation_command_canonical(p_input),'UTF8')),'hex');
  SELECT * INTO prior FROM private.conversation_meal_edit_ids
    WHERE user_id=p_user_id AND command_id=p_command_id AND operation_id=p_operation_id;
  IF FOUND THEN
    IF prior.input_hash IS DISTINCT FROM request_hash OR prior.kind IS DISTINCT FROM kind THEN
      RETURN '{"action":"input_conflict"}';
    END IF;
    SELECT o.receipt INTO receipt FROM private.conversation_meal_edit_operations o
      WHERE o.user_id=p_user_id AND o.command_id=p_command_id AND o.operation_id=p_operation_id;
    IF receipt IS NULL THEN RETURN '{"action":"event_conflict"}'; END IF;
    RETURN jsonb_build_object('action','replay','command',
      private.conversation_meal_command_binding(command_row),'receipt',receipt);
  END IF;

  SELECT * INTO effect FROM private.conversation_meal_effects
    WHERE user_id=p_user_id AND command_id=p_command_id;
  IF NOT FOUND THEN RETURN '{"action":"absent"}'; END IF;
  SELECT * INTO head FROM private.conversation_meal_edit_heads
    WHERE user_id=p_user_id AND command_id=p_command_id FOR UPDATE;
  revision:=coalesce(head.revision,0);
  IF revision IS DISTINCT FROM (p_input->>'expected_revision')::numeric::integer OR revision=2147483647 THEN
    RETURN '{"action":"version_conflict"}';
  END IF;
  SELECT * INTO STRICT owner FROM public.users WHERE id=p_user_id;
  IF owner.auth_user_id IS NULL OR owner.auth_user_id::text IS DISTINCT FROM p_expected_state#>>'{context,auth_user_id}'
     OR owner.timezone IS NULL OR NOT EXISTS(SELECT 1 FROM pg_timezone_names WHERE name=owner.timezone) THEN
    RAISE EXCEPTION 'meal placement context changed' USING ERRCODE='40001';
  END IF;

  from_day:=(p_expected_state#>>'{snapshot,date}')::date;
  IF kind='placement' THEN
    to_day:=(p_input->>'local_date')::date;
    target_meal:=(p_input->>'meal_type')::public.meal_type_enum;
  ELSE
    IF head.last_operation_id IS DISTINCT FROM (p_input->>'target_operation_id')::uuid THEN
      RETURN '{"action":"version_conflict"}';
    END IF;
    SELECT * INTO previous FROM private.conversation_meal_edit_operations
      WHERE user_id=p_user_id AND command_id=p_command_id AND operation_id=head.last_operation_id;
    IF previous.receipt->>'kind' IS DISTINCT FROM 'placement_saved' THEN
      RETURN '{"action":"version_conflict"}';
    END IF;
    undo_until:=(previous.receipt->>'undo_expires_at')::timestamptz;
    SELECT date INTO to_day FROM public.daily_snapshots
      WHERE user_id=p_user_id AND id=(previous.before_group#>>'{0,snapshot_id}')::uuid;
  END IF;

  IF from_day IS NULL OR to_day IS NULL THEN RETURN '{"action":"version_conflict"}'; END IF;
  FOR locked_day IN SELECT DISTINCT d FROM unnest(ARRAY[from_day,to_day]) AS days(d) ORDER BY d LOOP
    IF NOT pg_try_advisory_xact_lock(hashtextextended(p_user_id::text||':'||locked_day::text,0)) THEN
      RAISE EXCEPTION 'meal placement day is busy' USING ERRCODE='55P03';
    END IF;
  END LOOP;
  PERFORM 1 FROM public.user_progress WHERE user_id=p_user_id FOR UPDATE NOWAIT;
  PERFORM 1 FROM public.daily_snapshots WHERE user_id=p_user_id AND date IN (from_day,to_day)
    ORDER BY id FOR UPDATE NOWAIT;
  SELECT * INTO origin FROM public.daily_snapshots WHERE user_id=p_user_id AND date=from_day;
  SELECT * INTO destination FROM public.daily_snapshots WHERE user_id=p_user_id AND date=to_day;
  IF origin.id IS NULL THEN RETURN '{"action":"version_conflict"}'; END IF;
  PERFORM 1 FROM public.meal_logs
    WHERE snapshot_id IN (origin.id,destination.id) ORDER BY id FOR UPDATE NOWAIT;
  IF EXISTS (SELECT 1 FROM public.meal_logs WHERE snapshot_id IN (origin.id,destination.id) AND user_id<>p_user_id) THEN
    RAISE EXCEPTION 'meal placement cross-owner snapshot' USING ERRCODE='40001';
  END IF;
  state:=private.conversation_meal_edit_state(p_user_id,p_command_id);
  before_group:=state->'items';
  IF state IS NULL OR before_group IS DISTINCT FROM coalesce(head.after_group,effect.original_facts->'logs')
     OR NOT private.conversation_meal_edit_expected(state,p_expected_state)
     OR (state#>>'{snapshot,id}')::uuid IS DISTINCT FROM origin.id THEN
    RETURN '{"action":"version_conflict"}';
  END IF;
  edited_at:=clock_timestamp();
  local_today:=(edited_at AT TIME ZONE owner.timezone)::date;
  IF to_day>local_today THEN RETURN '{"action":"invalid_date"}'; END IF;
  IF from_day>local_today OR origin.day_closed OR coalesce(destination.day_closed,false)
     OR EXISTS (SELECT 1 FROM public.daily_snapshots WHERE user_id=p_user_id
       AND day_closed AND date>=least(from_day,to_day))
     OR EXISTS (SELECT 1 FROM public.user_progress WHERE user_id=p_user_id
       AND last_active_date>=least(from_day,to_day)) THEN
    RETURN '{"action":"day_closed"}';
  END IF;
  IF undo_until IS NOT NULL AND undo_until<=edited_at THEN RETURN '{"action":"undo_expired"}'; END IF;
  IF EXISTS (SELECT 1 FROM jsonb_array_elements(before_group) x
    WHERE ((x->>'consumed_at')::timestamptz AT TIME ZONE owner.timezone)::date<>from_day) THEN
    RETURN '{"action":"version_conflict"}';
  END IF;

  IF kind='placement' AND from_day=to_day AND NOT EXISTS (
    SELECT 1 FROM jsonb_array_elements(before_group) x
    WHERE x->>'meal_type' IS DISTINCT FROM target_meal::text
  ) THEN RETURN '{"action":"unchanged"}'; END IF;

  IF destination.id IS NULL THEN
    -- An open day without a snapshot has no proven historical goals.
    -- A concurrent producer can create it first, in which case we retry.
    INSERT INTO public.daily_snapshots(user_id,date) VALUES (p_user_id,to_day)
      ON CONFLICT (user_id,date) DO NOTHING RETURNING * INTO destination;
    IF destination.id IS NULL THEN RAISE EXCEPTION 'meal placement destination changed' USING ERRCODE='40001'; END IF;
  END IF;
  IF kind='placement' THEN
    UPDATE public.meal_logs m
    SET snapshot_id=destination.id, meal_type=target_meal,
        consumed_at=CASE WHEN from_day=to_day THEN m.consumed_at ELSE least(edited_at,
          (to_day+(m.consumed_at AT TIME ZONE owner.timezone)::time) AT TIME ZONE owner.timezone) END
    FROM jsonb_array_elements(before_group) x
    WHERE m.id=(x->>'id')::uuid AND m.user_id=p_user_id AND m.snapshot_id=origin.id;
  ELSE
    UPDATE public.meal_logs m
    SET snapshot_id=destination.id, meal_type=(x->>'meal_type')::public.meal_type_enum,
        consumed_at=(x->>'consumed_at')::timestamptz
    FROM jsonb_array_elements(previous.before_group) x
    WHERE m.id=(x->>'id')::uuid AND m.user_id=p_user_id AND m.snapshot_id=origin.id;
  END IF;
  GET DIAGNOSTICS changed=ROW_COUNT;
  IF changed<>jsonb_array_length(before_group) THEN
    RAISE EXCEPTION 'meal placement group changed' USING ERRCODE='40001';
  END IF;
  after_group:=private.conversation_meal_edit_group(p_user_id,p_command_id);
  IF (SELECT jsonb_agg(x-ARRAY['snapshot_id','meal_type','consumed_at'] ORDER BY x->>'id') FROM jsonb_array_elements(after_group) x)
     IS DISTINCT FROM (SELECT jsonb_agg(x-ARRAY['snapshot_id','meal_type','consumed_at'] ORDER BY x->>'id') FROM jsonb_array_elements(before_group) x)
     OR EXISTS (SELECT 1 FROM jsonb_array_elements(after_group) x WHERE
       x->>'snapshot_id' IS DISTINCT FROM destination.id::text OR
       ((x->>'consumed_at')::timestamptz AT TIME ZONE owner.timezone)::date<>to_day) THEN
    RAISE EXCEPTION 'meal placement facts changed' USING ERRCODE='40001';
  END IF;

  IF origin.id IS DISTINCT FROM destination.id THEN
    UPDATE public.daily_snapshots s
    SET (calories_consumed,protein_g,carbs_g,fat_g)=(
      SELECT round(coalesce(sum(m.kcal),0))::integer,round(coalesce(sum(m.protein_g),0),2),
        round(coalesce(sum(m.carbs_g),0),2),round(coalesce(sum(m.fat_g),0),2)
      FROM public.meal_logs m WHERE m.snapshot_id=s.id
    ), updated_at=clock_timestamp()
    WHERE s.id IN (origin.id,destination.id);
    SELECT * INTO STRICT destination FROM public.daily_snapshots WHERE id=destination.id;
  END IF;

  edited_at:=clock_timestamp();
  IF (edited_at AT TIME ZONE owner.timezone)::date<>local_today OR
     (undo_until IS NOT NULL AND undo_until<=edited_at) THEN
    RAISE EXCEPTION 'meal placement timing changed' USING ERRCODE='40001';
  END IF;
  receipt:=jsonb_build_object('schema','conversation.meal-edit-effect.v1','owner_id',p_user_id,
    'command_id',p_command_id,'operation_id',p_operation_id,'input_hash',request_hash,
    'kind',CASE kind WHEN 'placement' THEN 'placement_saved' ELSE 'placement_undone' END,
    'revision',revision+1,'applied_at',edited_at,
    'undo_expires_at',CASE kind WHEN 'placement' THEN edited_at+interval '5 minutes' ELSE NULL END,
    'target_operation_id',CASE kind WHEN 'undo_placement' THEN previous.operation_id ELSE NULL END,
    'removed_item_ids',jsonb_build_array(),'new_item_ids',jsonb_build_array(),'next_record_id',NULL,
    'snapshot',jsonb_build_object('id',destination.id,'date',destination.date,
      'calories_consumed',destination.calories_consumed,'protein_g',destination.protein_g,
      'carbs_g',destination.carbs_g,'fat_g',destination.fat_g,'daily_balance',destination.daily_balance));
  INSERT INTO private.conversation_meal_edit_ids
    VALUES (p_user_id,p_command_id,p_operation_id,command_row.epoch,request_hash,kind,edited_at);
  INSERT INTO private.conversation_meal_edit_operations
    VALUES (p_user_id,p_command_id,p_operation_id,receipt,before_group,after_group,before_group,after_group,edited_at);
  INSERT INTO private.conversation_meal_edit_heads VALUES (p_user_id,p_command_id,revision+1,p_operation_id,after_group)
    ON CONFLICT(user_id,command_id) DO UPDATE SET revision=EXCLUDED.revision,
      last_operation_id=EXCLUDED.last_operation_id,after_group=EXCLUDED.after_group;
  RETURN jsonb_build_object('action','committed','command',
    private.conversation_meal_command_binding(command_row),'receipt',receipt);
END $$;

REVOKE ALL ON FUNCTION public.apply_conversation_meal_placement(uuid,uuid,uuid,jsonb,jsonb)
  FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.apply_conversation_meal_placement(uuid,uuid,uuid,jsonb,jsonb) TO service_role;

-- The original receipt stays a historical fact. Subsequent item edits of
-- today's meal use the latest owned location, including after moving it back.
-- Legacy paginated journals keep their old receipt codec. Placement is read
-- through the current group and the same immutable operation/reconcile lane.
DO $migration$
DECLARE
  routine regprocedure;
  definition text;
  before_text text;
  after_text text;
BEGIN
  FOREACH routine IN ARRAY ARRAY[
    'private.apply_conversation_meal_edit(uuid,uuid,uuid,jsonb,jsonb,jsonb,text,jsonb,text,text)'::regprocedure,
    'private.conversation_meal_journal_events(uuid,uuid)'::regprocedure,
    'private.conversation_thread_events_v2(uuid,uuid)'::regprocedure
  ] LOOP
    definition:=pg_get_functiondef(routine);
    IF routine='private.apply_conversation_meal_edit(uuid,uuid,uuid,jsonb,jsonb,jsonb,text,jsonb,text,text)'::regprocedure THEN
      before_text:='day:=(fx.receipt->>''local_date'')::date;';
      after_text:='day:=coalesce((head.after_group#>>''{0,consumed_at}'')::timestamptz AT TIME ZONE u.timezone,
        (fx.receipt->>''local_date'')::date::timestamp)::date;';
      IF length(definition)-length(replace(definition,before_text,''))<>length(before_text) THEN
        RAISE EXCEPTION 'meal placement item edit date dependency changed';
      END IF;
      definition:=replace(definition,before_text,after_text);
      before_text:='id=(fx.original_facts#>>''{snapshot,id}'')::uuid AND user_id=p_user AND date=day';
      after_text:='id=coalesce((head.after_group#>>''{0,snapshot_id}'')::uuid,
        (fx.original_facts#>>''{snapshot,id}'')::uuid) AND user_id=p_user AND date=day';
    ELSE
      before_text:='FROM private.conversation_meal_edit_operations op JOIN';
      after_text:='FROM (SELECT * FROM private.conversation_meal_edit_operations
        WHERE receipt->>''kind'' IN (''saved'',''save_undone'',''registration_undone'')) op JOIN';
    END IF;
    IF length(definition)-length(replace(definition,before_text,''))<>length(before_text) THEN
      RAISE EXCEPTION 'meal placement dependency changed';
    END IF;
    EXECUTE replace(definition,before_text,after_text);
  END LOOP;
END $migration$;

-- A location edit keeps the original weighed/reference portion. The existing
-- unit reader first proves the entire current group against the edit head.
-- Only then can it disregard the audited location fields when walking the
-- older quantity edits, which remain the only edits that can replace item ids.
DO $units$
DECLARE
  definition text:=pg_get_functiondef('public.read_nutrition_window_units(uuid,uuid[])'::regprocedure);
  change text[];
BEGIN
  FOREACH change SLICE 1 IN ARRAY ARRAY[
    ARRAY['revision integer;matches integer;', 'revision integer;placement_fields text[];matches integer;'],
    ARRAY['AND m.snapshot_id::text=fx.original_facts#>>''{snapshot,id}'' THEN',
          'AND m.snapshot_id::text=coalesce(head.after_group#>>''{0,snapshot_id}'',fx.original_facts#>>''{snapshot,id}'') THEN
      placement_fields:=CASE WHEN EXISTS(SELECT 1 FROM private.conversation_meal_edit_operations p
        WHERE p.user_id=p_user_id AND p.command_id=fx.command_id
        AND p.receipt->>''kind'' IN (''placement_saved'',''placement_undone'')) THEN
        ARRAY[''snapshot_id'',''meal_type'',''consumed_at''] ELSE ARRAY[]::text[] END;'],
    ARRAY['IF origin IS DISTINCT FROM cursor_row THEN EXIT;END IF;',
          'IF origin-placement_fields IS DISTINCT FROM cursor_row-placement_fields THEN EXIT;END IF;'],
    ARRAY['WHERE o.user_id=p_user_id AND o.command_id=fx.command_id
       AND (o.receipt->>''revision'')::integer BETWEEN greatest(1,revision-64) AND revision',
          'WHERE o.user_id=p_user_id AND o.command_id=fx.command_id
       AND o.receipt->>''kind'' IN (''saved'',''save_undone'')
       AND (o.receipt->>''revision'')::integer BETWEEN greatest(1,revision-64) AND revision'],
    ARRAY['SELECT * INTO op FROM private.conversation_meal_edit_operations o WHERE o.user_id=p_user_id AND o.command_id=fx.command_id',
          'SELECT * INTO op FROM private.conversation_meal_edit_operations o WHERE o.user_id=p_user_id AND o.command_id=fx.command_id
      AND o.receipt->>''kind'' IN (''saved'',''save_undone'')'],
    ARRAY['op.after_items->0 IS DISTINCT FROM cursor_row',
          '(op.after_items->0)-placement_fields IS DISTINCT FROM cursor_row-placement_fields'],
    ARRAY['private.nutrition_window_same_scaled_food(op.before_items->0,cursor_row)',
          'private.nutrition_window_same_scaled_food((op.before_items->0)-placement_fields,cursor_row-placement_fields)'],
    ARRAY['cursor_row-ARRAY[''id'',''created_at''] IS DISTINCT FROM (target.before_items->0)-ARRAY[''id'',''created_at'']',
          'cursor_row-(ARRAY[''id'',''created_at'']||placement_fields) IS DISTINCT FROM
       (target.before_items->0)-(ARRAY[''id'',''created_at'']||placement_fields)']
  ] LOOP
    IF length(definition)-length(replace(definition,change[1],''))<>length(change[1]) THEN
      RAISE EXCEPTION 'meal placement nutrition display dependency changed';
    END IF;
    definition:=replace(definition,change[1],change[2]);
  END LOOP;
  EXECUTE definition;
END $units$;
COMMIT;
