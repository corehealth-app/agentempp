-- Command-owned C11 Save and finite compensation. Original FX/feedback never change.
BEGIN;
DO $$ BEGIN
 IF current_user<>'postgres' OR to_regprocedure('private.lock_conversation_meal(uuid,uuid)') IS NULL THEN
  RAISE EXCEPTION 'meal_edit_requires_existing_journal' USING ERRCODE='55000';END IF;
END $$;
CREATE TABLE private.conversation_meal_edit_ids(
 user_id uuid NOT NULL,command_id uuid NOT NULL,operation_id uuid NOT NULL,
 epoch uuid NOT NULL,input_hash text NOT NULL CHECK(input_hash ~ '^[0-9a-f]{64}$'),
 kind text NOT NULL CHECK(kind IN('save','undo_save','undo_registration')),
 created_at timestamptz NOT NULL CHECK(isfinite(created_at)),
 PRIMARY KEY(user_id,command_id,operation_id),
 FOREIGN KEY(user_id,command_id) REFERENCES private.conversation_meal_command_ids ON DELETE CASCADE
);
CREATE TABLE private.conversation_meal_edit_operations(
 user_id uuid NOT NULL,command_id uuid NOT NULL,operation_id uuid NOT NULL,
 receipt jsonb NOT NULL CHECK(jsonb_typeof(receipt)='object'),
 before_items jsonb NOT NULL CHECK(jsonb_typeof(before_items)='array'),
 after_items jsonb NOT NULL CHECK(jsonb_typeof(after_items)='array'),
 before_group jsonb NOT NULL CHECK(jsonb_typeof(before_group)='array'),
 after_group jsonb NOT NULL CHECK(jsonb_typeof(after_group)='array'),
 applied_at timestamptz NOT NULL CHECK(isfinite(applied_at)),
 PRIMARY KEY(user_id,command_id,operation_id),
 FOREIGN KEY(user_id,command_id,operation_id) REFERENCES private.conversation_meal_edit_ids ON DELETE CASCADE,
 FOREIGN KEY(user_id,command_id) REFERENCES private.conversation_meal_effects ON DELETE CASCADE
);
CREATE TABLE private.conversation_meal_edit_heads(
 user_id uuid NOT NULL,command_id uuid NOT NULL,revision integer NOT NULL CHECK(revision>0),
 last_operation_id uuid NOT NULL,after_group jsonb NOT NULL CHECK(jsonb_typeof(after_group)='array' AND jsonb_array_length(after_group)<=30),
 PRIMARY KEY(user_id,command_id),
 FOREIGN KEY(user_id,command_id,last_operation_id) REFERENCES private.conversation_meal_edit_ids(user_id,command_id,operation_id) DEFERRABLE INITIALLY DEFERRED,
 FOREIGN KEY(user_id,command_id) REFERENCES private.conversation_meal_effects ON DELETE CASCADE
);
ALTER TABLE private.conversation_meal_edit_ids ENABLE ROW LEVEL SECURITY;
ALTER TABLE private.conversation_meal_edit_operations ENABLE ROW LEVEL SECURITY;
ALTER TABLE private.conversation_meal_edit_heads ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON private.conversation_meal_edit_ids,private.conversation_meal_edit_operations,private.conversation_meal_edit_heads FROM PUBLIC,anon,authenticated,service_role;
CREATE FUNCTION private.guard_conversation_meal_edit() RETURNS trigger LANGUAGE plpgsql SET search_path=pg_catalog AS $$
BEGIN
 IF TG_OP='DELETE' AND (NOT EXISTS(SELECT 1 FROM public.users WHERE id=OLD.user_id) OR
  CASE WHEN TG_TABLE_NAME='conversation_meal_edit_ids' THEN
   NOT EXISTS(SELECT 1 FROM private.conversation_meal_command_ids WHERE user_id=OLD.user_id AND command_id=OLD.command_id)
  ELSE NOT EXISTS(SELECT 1 FROM private.conversation_meal_effects WHERE user_id=OLD.user_id AND command_id=OLD.command_id) END) THEN RETURN OLD;END IF;
 RAISE EXCEPTION 'conversation_meal_edit_immutable' USING ERRCODE='22023';
END $$;
CREATE TRIGGER immutable_conversation_meal_edit_id BEFORE UPDATE OR DELETE ON private.conversation_meal_edit_ids FOR EACH ROW EXECUTE FUNCTION private.guard_conversation_meal_edit();
CREATE TRIGGER immutable_conversation_meal_edit_operation BEFORE UPDATE OR DELETE ON private.conversation_meal_edit_operations FOR EACH ROW EXECUTE FUNCTION private.guard_conversation_meal_edit();
CREATE TRIGGER cascade_conversation_meal_edit_head BEFORE DELETE ON private.conversation_meal_edit_heads FOR EACH ROW EXECUTE FUNCTION private.guard_conversation_meal_edit();

CREATE FUNCTION private.conversation_meal_edit_group(p_user uuid,p_command uuid) RETURNS jsonb
LANGUAGE sql STABLE SET search_path=pg_catalog SET timezone='UTC' SET datestyle='ISO,YMD' AS $$
 SELECT coalesce(jsonb_agg(to_jsonb(m) ORDER BY m.id),'[]'::jsonb)
 FROM private.conversation_meal_effects e JOIN public.meal_logs m ON m.user_id=e.user_id AND m.raw_provider_message_id=e.receipt->>'provider_key'
 WHERE e.user_id=p_user AND e.command_id=p_command;
$$;
CREATE FUNCTION private.conversation_meal_edit_state(p_user uuid,p_command uuid) RETURNS jsonb
LANGUAGE sql STABLE SET search_path=pg_catalog SET timezone='UTC' SET datestyle='ISO,YMD' AS $$
 SELECT CASE WHEN jsonb_array_length(g.items) BETWEEN 1 AND 30 AND NOT EXISTS(
  SELECT 1 FROM jsonb_array_elements(g.items) x WHERE x->>'snapshot_id' IS DISTINCT FROM s.id::text)
 THEN jsonb_build_object('context',jsonb_build_object('id',u.id,'auth_user_id',u.auth_user_id,'country',u.country,
  'country_confirmed',u.country_confirmed,'timezone',u.timezone,'status',u.status,'wpp',u.wpp,'updated_at',u.updated_at),
  'snapshot',to_jsonb(s),'items',g.items) ELSE NULL END
 FROM private.conversation_meal_effects e JOIN public.users u ON u.id=e.user_id
 JOIN public.daily_snapshots s ON s.user_id=u.id AND s.id=(e.original_facts#>>'{snapshot,id}')::uuid
 CROSS JOIN LATERAL(SELECT private.conversation_meal_edit_group(p_user,p_command) items) g
 WHERE e.user_id=p_user AND e.command_id=p_command;
$$;
CREATE FUNCTION private.assert_conversation_meal_edit_input(v jsonb,kind text) RETURNS void
LANGUAGE plpgsql IMMUTABLE SET search_path=pg_catalog AS $$
DECLARE item jsonb;k text;
BEGIN
 IF v IS NULL OR jsonb_typeof(v)<>'object' OR octet_length(v::text)>65536 OR
  v->>'schema' IS DISTINCT FROM 'conversation.meal-edit.v1' OR v->>'kind' IS DISTINCT FROM kind OR
  jsonb_typeof(v->'expected_revision') IS DISTINCT FROM 'number' OR
  (v->>'expected_revision')::numeric NOT BETWEEN 0 AND 2147483647 OR
  (v->>'expected_revision')::numeric<>trunc((v->>'expected_revision')::numeric) OR
  coalesce(NOT(v->>'expected_version' ~ '^v1:[0-9a-f]{64}$'),true) THEN
  RAISE EXCEPTION 'invalid_conversation_meal_edit' USING ERRCODE='22023';END IF;
 IF kind='save' THEN
  PERFORM private.conversation_meal_keys(v,ARRAY['schema','kind','expected_revision','expected_version','record_id','items']);
  IF
   coalesce(NOT(v->>'record_id' ~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'),true) OR
   jsonb_typeof(v->'items') IS DISTINCT FROM 'array' OR jsonb_array_length(v->'items') NOT BETWEEN 1 AND 30 THEN
   RAISE EXCEPTION 'invalid_conversation_meal_edit' USING ERRCODE='22023';END IF;
  FOR item IN SELECT value FROM jsonb_array_elements(v->'items') LOOP
   IF jsonb_typeof(item)<>'object' OR NOT(item ?& ARRAY['food_name','quantity_g']) OR
    NOT private.conversation_command_text_valid(item->'food_name',160) OR item->>'food_name'<>btrim(item->>'food_name') OR
    jsonb_typeof(item->'quantity_g') IS DISTINCT FROM 'number' OR (item->>'quantity_g')::numeric<=0 OR (item->>'quantity_g')::numeric>9999 THEN
    RAISE EXCEPTION 'invalid_conversation_meal_edit_item' USING ERRCODE='22023';END IF;
   FOR k IN SELECT jsonb_object_keys(item) LOOP
    IF k NOT IN('food_name','quantity_g','user_kcal','quantity_basis','candidate_id') THEN RAISE EXCEPTION 'invalid_conversation_meal_edit_item' USING ERRCODE='22023';END IF;
   END LOOP;
   IF (item ? 'user_kcal' AND (jsonb_typeof(item->'user_kcal')<>'number' OR (item->>'user_kcal')::numeric NOT BETWEEN 0 AND 20000)) OR
    (item ? 'quantity_basis' AND coalesce(item->>'quantity_basis' NOT IN('stated','visual_estimate','portion_reference'),true)) OR
    (item ? 'candidate_id' AND coalesce(NOT(item->>'candidate_id' ~ '^c[0-9]{1,2}-[0-9a-f]{8}$'),true)) THEN
    RAISE EXCEPTION 'invalid_conversation_meal_edit_item' USING ERRCODE='22023';END IF;
  END LOOP;
 ELSIF kind='undo_save' THEN
  PERFORM private.conversation_meal_keys(v,ARRAY['schema','kind','expected_revision','expected_version','target_operation_id']);
  IF
   coalesce(NOT(v->>'target_operation_id' ~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'),true) THEN
   RAISE EXCEPTION 'invalid_conversation_meal_edit' USING ERRCODE='22023';END IF;
 ELSIF kind='undo_registration' THEN
  PERFORM private.conversation_meal_keys(v,ARRAY['schema','kind','expected_revision','expected_version']);
 ELSE
  RAISE EXCEPTION 'invalid_conversation_meal_edit' USING ERRCODE='22023';END IF;
END $$;

-- C11's full typed state is the CAS; its v1 string alone is not SQL authority.
CREATE FUNCTION private.conversation_meal_edit_expected(actual jsonb,expected jsonb) RETURNS boolean
LANGUAGE plpgsql STABLE SET search_path=pg_catalog SET timezone='UTC' SET datestyle='ISO,YMD' AS $$
DECLARE u public.users%ROWTYPE;s public.daily_snapshots%ROWTYPE;items jsonb;expected_item jsonb;
BEGIN
 PERFORM private.conversation_meal_keys(expected,ARRAY['context','snapshot','items']);
 IF expected IS NULL OR jsonb_typeof(expected)<>'object' OR
  jsonb_typeof(expected->'context') IS DISTINCT FROM 'object' OR jsonb_typeof(expected->'snapshot') IS DISTINCT FROM 'object' OR
  jsonb_typeof(expected->'items') IS DISTINCT FROM 'array' OR jsonb_array_length(expected->'items') NOT BETWEEN 1 AND 30 OR
  (SELECT array_agg(key ORDER BY key) FROM jsonb_object_keys(expected->'context') key) IS DISTINCT FROM
   (SELECT array_agg(key ORDER BY key) FROM jsonb_object_keys(actual->'context') key) OR
  (SELECT array_agg(key ORDER BY key) FROM jsonb_object_keys(expected->'snapshot') key) IS DISTINCT FROM
   (SELECT array_agg(key ORDER BY key) FROM jsonb_object_keys(actual->'snapshot') key) THEN
  RAISE EXCEPTION 'invalid_conversation_meal_edit_state' USING ERRCODE='22023';END IF;
 FOR expected_item IN SELECT value FROM jsonb_array_elements(expected->'items') LOOP
  IF jsonb_typeof(expected_item)<>'object' OR (SELECT array_agg(key ORDER BY key) FROM jsonb_object_keys(expected_item) key) IS DISTINCT FROM
   (SELECT array_agg(key ORDER BY key) FROM jsonb_object_keys(actual->'items'->0) key) THEN
   RAISE EXCEPTION 'invalid_conversation_meal_edit_state' USING ERRCODE='22023';END IF;
 END LOOP;
 u:=jsonb_populate_record(NULL::public.users,expected->'context');s:=jsonb_populate_record(NULL::public.daily_snapshots,expected->'snapshot');
 SELECT jsonb_agg(to_jsonb(jsonb_populate_record(NULL::public.meal_logs,x)) ORDER BY (x->>'id')::uuid) INTO items FROM jsonb_array_elements(expected->'items') x;
 RETURN actual=jsonb_build_object('context',jsonb_build_object('id',u.id,'auth_user_id',u.auth_user_id,'country',u.country,
  'country_confirmed',u.country_confirmed,'timezone',u.timezone,'status',u.status,'wpp',u.wpp,'updated_at',u.updated_at),'snapshot',to_jsonb(s),'items',items);
END $$;

CREATE FUNCTION public.read_conversation_meal_edit_operation(p_user_id uuid,p_command_id uuid,p_operation_id uuid,p_input jsonb) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=pg_catalog SET timezone='UTC' SET datestyle='ISO,YMD' AS $$
DECLARE c private.conversation_meal_command_ids%ROWTYPE;e uuid;i private.conversation_meal_edit_ids%ROWTYPE;receipt jsonb;h text;
BEGIN
 PERFORM private.assert_trusted_backend();
 IF p_user_id IS NULL OR p_command_id IS NULL OR p_operation_id IS NULL OR current_setting('transaction_isolation')<>'read committed' THEN RAISE EXCEPTION 'invalid_conversation_meal_edit_read' USING ERRCODE='22023';END IF;
 SELECT ids.* INTO c FROM private.conversation_meal_command_ids ids JOIN public.users u ON u.id=ids.user_id AND u.status='active'
 WHERE ids.user_id=p_user_id AND ids.command_id=p_command_id;
 SELECT epoch INTO e FROM private.workout_strength_authority_epochs WHERE user_id=p_user_id;
 IF c.command_id IS NULL THEN RETURN '{"action":"absent"}';END IF;
 IF c.invalidated_at IS NOT NULL OR c.epoch IS DISTINCT FROM e THEN RETURN '{"action":"stale_epoch"}';END IF;
 SELECT * INTO i FROM private.conversation_meal_edit_ids WHERE user_id=p_user_id AND command_id=p_command_id AND operation_id=p_operation_id;
 IF NOT FOUND THEN RETURN '{"action":"absent"}';END IF;
 h:=encode(sha256(convert_to(private.conversation_command_canonical(p_input),'UTF8')),'hex');
 IF i.input_hash IS DISTINCT FROM h THEN RETURN '{"action":"input_conflict"}';END IF;
 SELECT o.receipt INTO receipt FROM private.conversation_meal_edit_operations o WHERE user_id=p_user_id AND command_id=p_command_id AND operation_id=p_operation_id;
 IF receipt IS NULL THEN RETURN '{"action":"event_conflict"}';END IF;
 RETURN jsonb_build_object('action','available','command',private.conversation_meal_command_binding(c),'receipt',receipt);
END $$;
CREATE FUNCTION public.read_conversation_meal_edit_state(p_user_id uuid,p_command_id uuid) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=pg_catalog SET timezone='UTC' SET datestyle='ISO,YMD' AS $$
DECLARE c private.conversation_meal_command_ids%ROWTYPE;e uuid;fx private.conversation_meal_effects%ROWTYPE;
 head private.conversation_meal_edit_heads%ROWTYPE;last_receipt jsonb;g jsonb;
BEGIN
 PERFORM private.assert_trusted_backend();
 IF p_user_id IS NULL OR p_command_id IS NULL OR current_setting('transaction_isolation')<>'read committed' THEN RAISE EXCEPTION 'invalid_conversation_meal_edit_read' USING ERRCODE='22023';END IF;
 SELECT ids.* INTO c FROM private.conversation_meal_command_ids ids JOIN public.users u ON u.id=ids.user_id AND u.status='active'
 WHERE ids.user_id=p_user_id AND ids.command_id=p_command_id;
 SELECT epoch INTO e FROM private.workout_strength_authority_epochs WHERE user_id=p_user_id;
 IF c.command_id IS NULL THEN RETURN '{"action":"absent"}';END IF;
 IF c.invalidated_at IS NOT NULL OR c.epoch IS DISTINCT FROM e THEN RETURN '{"action":"stale_epoch"}';END IF;
 SELECT * INTO fx FROM private.conversation_meal_effects WHERE user_id=p_user_id AND command_id=p_command_id;
 IF NOT FOUND THEN RETURN '{"action":"absent"}';END IF;
 SELECT * INTO head FROM private.conversation_meal_edit_heads WHERE user_id=p_user_id AND command_id=p_command_id;
 IF FOUND THEN SELECT receipt INTO last_receipt FROM private.conversation_meal_edit_operations WHERE user_id=p_user_id AND command_id=p_command_id AND operation_id=head.last_operation_id;
  IF last_receipt IS NULL THEN RETURN '{"action":"event_conflict"}';END IF;END IF;
 g:=private.conversation_meal_edit_group(p_user_id,p_command_id);
 RETURN jsonb_build_object('action','available','command',private.conversation_meal_command_binding(c),'original_receipt',fx.receipt,
  'revision',coalesce(head.revision,0),'current_state',private.conversation_meal_edit_state(p_user_id,p_command_id),
  'lineage_compatible',g=coalesce(head.after_group,fx.original_facts->'logs'),'last_operation',last_receipt,
  'registration_undo_expires_at',fx.committed_at+interval '5 minutes','observed_at',clock_timestamp());
END $$;

CREATE FUNCTION private.apply_conversation_meal_edit(p_user uuid,p_command uuid,p_operation uuid,p_input jsonb,p_expected_state jsonb,
 p_calculated jsonb,p_mode text,p_quantity jsonb,p_request_id text,p_kind text) RETURNS jsonb
LANGUAGE plpgsql VOLATILE SET search_path=pg_catalog SET timezone='UTC' SET datestyle='ISO,YMD' AS $$
DECLARE gate text;h text;command_row private.conversation_meal_command_ids%ROWTYPE;fx private.conversation_meal_effects%ROWTYPE;head private.conversation_meal_edit_heads%ROWTYPE;
 ident private.conversation_meal_edit_ids%ROWTYPE;target private.conversation_meal_edit_operations%ROWTYPE;u public.users%ROWTYPE;
 snap public.daily_snapshots%ROWTYPE;anchor public.meal_logs%ROWTYPE;state jsonb;g jsonb;before_snap jsonb;before_all jsonb;
 before_items jsonb;after_items jsonb;after_group jsonb;retained jsonb;expected_retained jsonb;restored jsonb;result jsonb;receipt jsonb;
 removed uuid[];new_ids uuid[]:='{}';all_ids uuid[];revision integer;day date;clock timestamptz;deadline timestamptz;n integer;
BEGIN
 PERFORM private.assert_trusted_backend();
 IF p_operation IS NULL THEN RAISE EXCEPTION 'invalid_conversation_meal_edit' USING ERRCODE='22023';END IF;
 gate:=private.lock_conversation_meal(p_user,p_command);IF gate<>'current' THEN RETURN jsonb_build_object('action',gate);END IF;
 SELECT * INTO fx FROM private.conversation_meal_effects WHERE user_id=p_user AND command_id=p_command;
 IF NOT FOUND THEN RETURN '{"action":"absent"}';END IF;
 SELECT * INTO STRICT command_row FROM private.conversation_meal_command_ids WHERE user_id=p_user AND command_id=p_command;
 h:=encode(sha256(convert_to(private.conversation_command_canonical(p_input),'UTF8')),'hex');
 SELECT * INTO ident FROM private.conversation_meal_edit_ids WHERE user_id=p_user AND command_id=p_command AND operation_id=p_operation FOR UPDATE;
 IF FOUND THEN
  IF ident.input_hash IS DISTINCT FROM h OR ident.kind IS DISTINCT FROM p_kind THEN RETURN '{"action":"input_conflict"}';END IF;
  SELECT o.receipt INTO receipt FROM private.conversation_meal_edit_operations o WHERE user_id=p_user AND command_id=p_command AND operation_id=p_operation;
  IF receipt IS NULL THEN RETURN '{"action":"event_conflict"}';END IF;
  RETURN jsonb_build_object('action','replay','command',private.conversation_meal_command_binding(command_row),'receipt',receipt);
 END IF;
 PERFORM private.assert_conversation_meal_edit_input(p_input,p_kind);
 IF p_request_id IS NULL OR length(p_request_id) NOT BETWEEN 1 AND 128 THEN RAISE EXCEPTION 'invalid_conversation_meal_edit_request' USING ERRCODE='22023';END IF;
 SELECT * INTO head FROM private.conversation_meal_edit_heads WHERE user_id=p_user AND command_id=p_command FOR UPDATE;
 revision:=coalesce(head.revision,0);
 IF revision<>(p_input->>'expected_revision')::numeric::integer OR revision=2147483647 OR (p_kind='undo_registration' AND revision<>0) THEN RETURN '{"action":"version_conflict"}';END IF;
 IF p_kind='undo_save' THEN
  IF head.last_operation_id IS DISTINCT FROM (p_input->>'target_operation_id')::uuid THEN RETURN '{"action":"version_conflict"}';END IF;
  SELECT * INTO target FROM private.conversation_meal_edit_operations WHERE user_id=p_user AND command_id=p_command AND operation_id=head.last_operation_id;
  IF target.receipt->>'kind' IS DISTINCT FROM 'saved' THEN RETURN '{"action":"version_conflict"}';END IF;
  deadline:=(target.receipt->>'undo_expires_at')::timestamptz;
 ELSIF p_kind='undo_registration' THEN deadline:=fx.committed_at+interval '5 minutes';END IF;
 SELECT * INTO u FROM public.users WHERE id=p_user;
 IF u.auth_user_id IS NULL OR u.auth_user_id::text IS DISTINCT FROM p_expected_state#>>'{context,auth_user_id}' THEN RAISE EXCEPTION 'conversation_meal_edit_authenticated_context_changed' USING ERRCODE='40001';END IF;
 IF u.timezone IS NULL OR NOT EXISTS(SELECT 1 FROM pg_timezone_names WHERE name=u.timezone) THEN RAISE EXCEPTION 'conversation_meal_edit_timezone_required' USING ERRCODE='22023';END IF;
 day:=(fx.receipt->>'local_date')::date;
 IF NOT pg_try_advisory_xact_lock(hashtextextended(p_user::text||':'||day::text,0)) THEN RAISE EXCEPTION 'conversation_meal_edit_day_busy' USING ERRCODE='55P03';END IF;
 SELECT * INTO snap FROM public.daily_snapshots WHERE id=(fx.original_facts#>>'{snapshot,id}')::uuid AND user_id=p_user AND date=day FOR UPDATE NOWAIT;
 IF NOT FOUND THEN RETURN '{"action":"version_conflict"}';END IF;
 PERFORM 1 FROM public.meal_logs WHERE snapshot_id=snap.id ORDER BY id FOR UPDATE NOWAIT;
 IF EXISTS(SELECT 1 FROM public.meal_logs WHERE snapshot_id=snap.id AND user_id<>p_user) THEN RAISE EXCEPTION 'conversation_meal_edit_foreign_snapshot' USING ERRCODE='40001';END IF;
 state:=private.conversation_meal_edit_state(p_user,p_command);g:=private.conversation_meal_edit_group(p_user,p_command);
 IF state IS NULL THEN RETURN '{"action":"version_conflict"}';END IF;
 IF p_kind='undo_registration' AND g IS DISTINCT FROM fx.original_facts->'logs' THEN RETURN '{"action":"version_conflict"}';END IF;
 IF p_kind='undo_save' AND g IS DISTINCT FROM head.after_group THEN RETURN '{"action":"version_conflict"}';END IF;
 IF NOT private.conversation_meal_edit_expected(state,p_expected_state) THEN RETURN '{"action":"version_conflict"}';END IF;
 clock:=clock_timestamp();
 IF snap.day_closed OR (clock AT TIME ZONE u.timezone)::date IS DISTINCT FROM day OR EXISTS(
  SELECT 1 FROM jsonb_array_elements(g) x WHERE ((x->>'consumed_at')::timestamptz AT TIME ZONE u.timezone)::date IS DISTINCT FROM day) THEN
  RETURN '{"action":"day_closed"}';END IF;
 IF deadline IS NOT NULL AND deadline<=clock THEN RETURN '{"action":"undo_expired"}';END IF;
 before_snap:=to_jsonb(snap);
 SELECT coalesce(jsonb_agg(to_jsonb(m) ORDER BY id),'[]'),coalesce(array_agg(id ORDER BY id),'{}') INTO before_all,all_ids FROM public.meal_logs m WHERE snapshot_id=snap.id;
 IF p_kind='save' THEN
  SELECT * INTO anchor FROM public.meal_logs WHERE id=(p_input->>'record_id')::uuid AND user_id=p_user AND raw_provider_message_id=fx.receipt->>'provider_key' AND snapshot_id=snap.id;
  IF NOT FOUND THEN RETURN '{"action":"version_conflict"}';END IF;
  removed:=ARRAY[anchor.id];before_items:=jsonb_build_array(to_jsonb(anchor));
  result:=public.mutate_mobile_confirmed_meal(p_user,'cmeal-edit1:'||p_command::text||':'||p_operation::text||':save','PATCH',
   '/api/mobile/v1/meal-records/'||anchor.id::text,h,anchor.id,p_input->>'expected_version',removed,p_expected_state,p_calculated,p_mode,p_quantity,p_request_id);
  IF result->>'action'='in_progress' THEN RETURN result;END IF;
  IF result->>'action' IS DISTINCT FROM 'completed' THEN RAISE EXCEPTION 'conversation_meal_edit_unlinked_c11_receipt' USING ERRCODE='40001';END IF;
  SELECT coalesce(array_agg(x::uuid ORDER BY x::uuid),'{}') INTO new_ids FROM jsonb_array_elements_text(result#>'{response_body,data,new_item_ids}') x;
 ELSIF p_kind='undo_registration' THEN
  before_items:=g;SELECT array_agg((x->>'id')::uuid ORDER BY (x->>'id')::uuid) INTO removed FROM jsonb_array_elements(g) x;
  DELETE FROM public.meal_logs WHERE id=ANY(removed) AND user_id=p_user AND snapshot_id=snap.id;
  GET DIAGNOSTICS n=ROW_COUNT;IF n<>cardinality(removed) THEN RAISE EXCEPTION 'conversation_meal_edit_partial_delete' USING ERRCODE='40001';END IF;
 ELSE
  before_items:=target.after_items;
  SELECT array_agg((x->>'id')::uuid ORDER BY (x->>'id')::uuid) INTO removed FROM jsonb_array_elements(target.after_items) x;
  IF jsonb_array_length(target.before_items)<>1 OR cardinality(removed) NOT BETWEEN 1 AND 30 THEN RAISE EXCEPTION 'conversation_meal_edit_invalid_audit' USING ERRCODE='40001';END IF;
  anchor:=jsonb_populate_record(NULL::public.meal_logs,target.before_items->0);
  restored:=jsonb_build_array(jsonb_build_object('food_name',anchor.food_name,'food_db_id',anchor.food_db_id,'source',anchor.source,
   'quantity_g',anchor.quantity_g,'kcal',anchor.kcal,'protein_g',anchor.protein_g,'carbs_g',anchor.carbs_g,'fat_g',anchor.fat_g,'confidence',anchor.confidence));
  result:=public.register_meal_atomic_scoped(p_user,day,anchor.meal_type,restored,true,NULL,anchor.consumed_at,anchor.raw_provider_message_id,snap.calories_target,snap.protein_target,removed);
  IF (result->>'replaced_count')::integer IS DISTINCT FROM cardinality(removed) OR (result->>'inserted_count')::integer IS DISTINCT FROM 1 OR (result->>'snapshot_id')::uuid IS DISTINCT FROM snap.id THEN
   RAISE EXCEPTION 'conversation_meal_edit_partial_restore' USING ERRCODE='40001';END IF;
  SELECT array_agg(id ORDER BY id) INTO new_ids FROM public.meal_logs WHERE snapshot_id=snap.id AND NOT(id=ANY(all_ids));
  IF cardinality(new_ids) IS DISTINCT FROM 1 THEN RAISE EXCEPTION 'conversation_meal_edit_restore_ids_changed' USING ERRCODE='40001';END IF;
  UPDATE public.meal_logs SET image_url=anchor.image_url,raw_message_id=anchor.raw_message_id,created_at=clock_timestamp() WHERE id=ANY(new_ids);
  IF (SELECT to_jsonb(m)-ARRAY['id','created_at'] FROM public.meal_logs m WHERE id=new_ids[1]) IS DISTINCT FROM (to_jsonb(anchor)-ARRAY['id','created_at']) THEN
   RAISE EXCEPTION 'conversation_meal_edit_restore_facts_changed' USING ERRCODE='40001';END IF;
 END IF;
 -- Same current sum and rounding as C11; never restore an old whole snapshot.
 UPDATE public.daily_snapshots s SET calories_consumed=t.kcal,protein_g=t.p,carbs_g=t.c,fat_g=t.f,updated_at=clock_timestamp()
 FROM(SELECT round(coalesce(sum(kcal),0))::integer kcal,round(coalesce(sum(protein_g),0),2) p,
  round(coalesce(sum(carbs_g),0),2) c,round(coalesce(sum(fat_g),0),2) f FROM public.meal_logs WHERE snapshot_id=snap.id) t WHERE s.id=snap.id;
 SELECT * INTO snap FROM public.daily_snapshots WHERE id=snap.id;
 IF (to_jsonb(snap)-ARRAY['calories_consumed','protein_g','carbs_g','fat_g','daily_balance','updated_at']) IS DISTINCT FROM
  (before_snap-ARRAY['calories_consumed','protein_g','carbs_g','fat_g','daily_balance','updated_at']) THEN RAISE EXCEPTION 'conversation_meal_edit_unrelated_snapshot_changed' USING ERRCODE='40001';END IF;
 SELECT coalesce(jsonb_agg(x ORDER BY x->>'id'),'[]') INTO expected_retained FROM jsonb_array_elements(before_all) x WHERE NOT((x->>'id')::uuid=ANY(removed));
 SELECT coalesce(jsonb_agg(to_jsonb(m) ORDER BY id),'[]') INTO retained FROM public.meal_logs m WHERE snapshot_id=snap.id AND id=ANY(all_ids) AND NOT(id=ANY(removed));
 IF retained IS DISTINCT FROM expected_retained OR EXISTS(SELECT 1 FROM public.meal_logs WHERE id=ANY(removed)) THEN RAISE EXCEPTION 'conversation_meal_edit_unrelated_rows_changed' USING ERRCODE='40001';END IF;
 after_group:=private.conversation_meal_edit_group(p_user,p_command);
 SELECT coalesce(jsonb_agg(to_jsonb(m) ORDER BY id),'[]') INTO after_items FROM public.meal_logs m WHERE id=ANY(new_ids);
 clock:=clock_timestamp();
 IF (clock AT TIME ZONE u.timezone)::date IS DISTINCT FROM day THEN RAISE EXCEPTION 'conversation_meal_edit_midnight' USING ERRCODE='40001';END IF;
 IF deadline IS NOT NULL AND deadline<=clock THEN RAISE EXCEPTION 'conversation_meal_edit_deadline_passed' USING ERRCODE='40001';END IF;
 receipt:=jsonb_build_object('schema','conversation.meal-edit-effect.v1','owner_id',p_user,'command_id',p_command,'operation_id',p_operation,
  'input_hash',h,'kind',CASE p_kind WHEN 'save' THEN 'saved' WHEN 'undo_save' THEN 'save_undone' ELSE 'registration_undone' END,
  'revision',revision+1,'applied_at',clock,'undo_expires_at',CASE WHEN p_kind='save' THEN clock+interval '5 minutes' ELSE NULL END,
  'target_operation_id',CASE WHEN p_kind='undo_save' THEN (p_input->>'target_operation_id')::uuid ELSE NULL END,
  'removed_item_ids',to_jsonb(removed),'new_item_ids',to_jsonb(new_ids),'next_record_id',new_ids[1],
  'snapshot',jsonb_build_object('id',snap.id,'date',snap.date,'calories_consumed',snap.calories_consumed,'protein_g',snap.protein_g,'carbs_g',snap.carbs_g,'fat_g',snap.fat_g,'daily_balance',snap.daily_balance));
 INSERT INTO private.conversation_meal_edit_ids VALUES(p_user,p_command,p_operation,command_row.epoch,h,p_kind,clock);
 INSERT INTO private.conversation_meal_edit_operations VALUES(p_user,p_command,p_operation,receipt,before_items,after_items,g,after_group,clock);
 INSERT INTO private.conversation_meal_edit_heads VALUES(p_user,p_command,revision+1,p_operation,after_group)
 ON CONFLICT(user_id,command_id) DO UPDATE SET revision=EXCLUDED.revision,last_operation_id=EXCLUDED.last_operation_id,after_group=EXCLUDED.after_group;
 -- A mandatory publication/constraint wait cannot move compensation past TTL
 -- or midnight after its factual writes. Any late completion rolls all back.
 clock:=clock_timestamp();
 IF (clock AT TIME ZONE u.timezone)::date IS DISTINCT FROM day THEN RAISE EXCEPTION 'conversation_meal_edit_midnight' USING ERRCODE='40001';END IF;
 IF deadline IS NOT NULL AND deadline<=clock THEN RAISE EXCEPTION 'conversation_meal_edit_deadline_passed' USING ERRCODE='40001';END IF;
 RETURN jsonb_build_object('action','committed','command',private.conversation_meal_command_binding(command_row),'receipt',receipt);
END $$;
CREATE FUNCTION public.commit_conversation_meal_item_edit(p_user_id uuid,p_command_id uuid,p_operation_id uuid,p_input jsonb,p_expected_state jsonb,p_calculated_items jsonb,p_nutrition_mode text,p_quantity_change jsonb,p_request_id text) RETURNS jsonb
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path=pg_catalog SET timezone='UTC' SET datestyle='ISO,YMD' AS $$
BEGIN RETURN private.apply_conversation_meal_edit(p_user_id,p_command_id,p_operation_id,p_input,p_expected_state,p_calculated_items,p_nutrition_mode,p_quantity_change,p_request_id,'save');END $$;
CREATE FUNCTION public.undo_conversation_meal_item_edit(p_user_id uuid,p_command_id uuid,p_operation_id uuid,p_input jsonb,p_expected_state jsonb,p_request_id text) RETURNS jsonb
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path=pg_catalog SET timezone='UTC' SET datestyle='ISO,YMD' AS $$
BEGIN RETURN private.apply_conversation_meal_edit(p_user_id,p_command_id,p_operation_id,p_input,p_expected_state,NULL,NULL,NULL,p_request_id,'undo_save');END $$;
CREATE FUNCTION public.undo_conversation_meal_registration(p_user_id uuid,p_command_id uuid,p_operation_id uuid,p_input jsonb,p_expected_state jsonb,p_request_id text) RETURNS jsonb
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path=pg_catalog SET timezone='UTC' SET datestyle='ISO,YMD' AS $$
BEGIN RETURN private.apply_conversation_meal_edit(p_user_id,p_command_id,p_operation_id,p_input,p_expected_state,NULL,NULL,NULL,p_request_id,'undo_registration');END $$;
REVOKE ALL ON FUNCTION private.guard_conversation_meal_edit(),private.conversation_meal_edit_group(uuid,uuid),private.conversation_meal_edit_state(uuid,uuid),
 private.assert_conversation_meal_edit_input(jsonb,text),private.conversation_meal_edit_expected(jsonb,jsonb),
 private.apply_conversation_meal_edit(uuid,uuid,uuid,jsonb,jsonb,jsonb,text,jsonb,text,text),
 public.read_conversation_meal_edit_operation(uuid,uuid,uuid,jsonb),public.read_conversation_meal_edit_state(uuid,uuid),
 public.commit_conversation_meal_item_edit(uuid,uuid,uuid,jsonb,jsonb,jsonb,text,jsonb,text),
 public.undo_conversation_meal_item_edit(uuid,uuid,uuid,jsonb,jsonb,text),public.undo_conversation_meal_registration(uuid,uuid,uuid,jsonb,jsonb,text)
 FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.read_conversation_meal_edit_operation(uuid,uuid,uuid,jsonb),public.read_conversation_meal_edit_state(uuid,uuid),
 public.commit_conversation_meal_item_edit(uuid,uuid,uuid,jsonb,jsonb,jsonb,text,jsonb,text),
 public.undo_conversation_meal_item_edit(uuid,uuid,uuid,jsonb,jsonb,text),public.undo_conversation_meal_registration(uuid,uuid,uuid,jsonb,jsonb,text) TO service_role;
COMMIT;
