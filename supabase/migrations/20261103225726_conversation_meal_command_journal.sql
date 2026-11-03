-- Dormant meal-command journal foundation. No HTTP caller, domain writer,
-- receipt sealing, semantic authorization, timeline, reward or cutover.
BEGIN;
DO $preflight$
BEGIN
 IF current_user<>'postgres' THEN RAISE EXCEPTION 'journal_requires_postgres' USING ERRCODE='42501'; END IF;
 IF to_regclass('private.workout_strength_authority_epochs') IS NULL OR to_regprocedure('private.assert_trusted_backend()') IS NULL THEN
  RAISE EXCEPTION 'journal_requires_existing_authority' USING ERRCODE='42P01'; END IF;
 IF to_regclass('private.conversation_meal_command_ids') IS NOT NULL THEN
  RAISE EXCEPTION 'journal_unknown_existing_object' USING ERRCODE='42P07'; END IF;
END $preflight$;

-- Permanent dedup tombstone is deliberately independent of messages, pending
-- registrations and erasable content. Account deletion remains cascading.
CREATE TABLE private.conversation_meal_command_ids (
 user_id uuid NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
 command_id uuid NOT NULL,
 input_hash text COLLATE "C" NOT NULL CHECK(input_hash ~ '^[0-9a-f]{64}$'),
 command_protocol text NOT NULL CHECK(command_protocol='conversation.command.v1'),
 kind text NOT NULL CHECK(kind='meal.report'),
 epoch uuid NOT NULL,
 admitted_at timestamptz NOT NULL CHECK(isfinite(admitted_at)),
 invalidated_at timestamptz CHECK(isfinite(invalidated_at)),
 PRIMARY KEY(user_id,command_id)
);
CREATE TABLE private.conversation_meal_command_sources (
 user_id uuid NOT NULL,command_id uuid NOT NULL,
 source_input jsonb NOT NULL CHECK(jsonb_typeof(source_input)='object'),
 PRIMARY KEY(user_id,command_id),
 FOREIGN KEY(user_id,command_id) REFERENCES private.conversation_meal_command_ids(user_id,command_id) ON DELETE CASCADE
);
CREATE TABLE private.conversation_meal_command_candidates (
 user_id uuid NOT NULL,command_id uuid NOT NULL,
 candidate_hash text COLLATE "C" NOT NULL CHECK(candidate_hash ~ '^[0-9a-f]{64}$'),
 candidate jsonb NOT NULL CHECK(jsonb_typeof(candidate)='object'),
 attached_at timestamptz NOT NULL CHECK(isfinite(attached_at)),
 PRIMARY KEY(user_id,command_id),
 FOREIGN KEY(user_id,command_id) REFERENCES private.conversation_meal_command_sources(user_id,command_id) ON DELETE CASCADE
);
ALTER TABLE private.conversation_meal_command_ids ENABLE ROW LEVEL SECURITY;
ALTER TABLE private.conversation_meal_command_sources ENABLE ROW LEVEL SECURITY;
ALTER TABLE private.conversation_meal_command_candidates ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE private.conversation_meal_command_ids,private.conversation_meal_command_sources,
 private.conversation_meal_command_candidates FROM PUBLIC,anon,authenticated,service_role;

CREATE FUNCTION private.conversation_command_immutable() RETURNS trigger LANGUAGE plpgsql SET search_path=pg_catalog AS $$
BEGIN
 IF TG_TABLE_NAME='conversation_meal_command_ids' THEN
  IF (to_jsonb(NEW)-'invalidated_at')=(to_jsonb(OLD)-'invalidated_at') AND
   OLD.invalidated_at IS NULL AND NEW.invalidated_at IS NOT NULL THEN RETURN NEW; END IF;
 END IF;
 RAISE EXCEPTION 'conversation_command_immutable' USING ERRCODE='22023';
END $$;
CREATE TRIGGER conversation_meal_command_id_immutable BEFORE UPDATE ON private.conversation_meal_command_ids
 FOR EACH ROW EXECUTE FUNCTION private.conversation_command_immutable();
CREATE TRIGGER conversation_meal_command_source_immutable BEFORE UPDATE ON private.conversation_meal_command_sources
 FOR EACH ROW EXECUTE FUNCTION private.conversation_command_immutable();
CREATE TRIGGER conversation_meal_command_candidate_immutable BEFORE UPDATE ON private.conversation_meal_command_candidates
 FOR EACH ROW EXECUTE FUNCTION private.conversation_command_immutable();

-- Same byte-level canonical JSON as the closed TypeScript DTO: sorted keys,
-- no structural spaces, original Unicode/text preserved. Arrays/numbers are
-- unsupported for admission; the canonical helper also hashes opaque candidates.
CREATE FUNCTION private.conversation_command_canonical(v jsonb) RETURNS text
LANGUAGE sql IMMUTABLE STRICT SET search_path=pg_catalog AS $$
 SELECT CASE jsonb_typeof(v)
 WHEN 'object' THEN '{'||coalesce((SELECT string_agg(to_jsonb(k)::text||':'||private.conversation_command_canonical(x),',' ORDER BY k COLLATE "C") FROM jsonb_each(v) e(k,x)),'')||'}'
 WHEN 'array' THEN '['||coalesce((SELECT string_agg(private.conversation_command_canonical(x),',' ORDER BY n) FROM jsonb_array_elements(v) WITH ORDINALITY e(x,n)),'')||']'
 ELSE v::text END;
$$;
CREATE FUNCTION private.conversation_command_text_valid(v jsonb,max_units integer) RETURNS boolean
LANGUAGE sql IMMUTABLE SET search_path=pg_catalog AS $$
 SELECT coalesce(jsonb_typeof(v)='string' AND length(btrim(v#>>'{}',E' \t\n\r'||chr(11)||chr(12)||chr(160)||chr(5760)||chr(8192)||chr(8193)||chr(8194)||chr(8195)||chr(8196)||chr(8197)||chr(8198)||chr(8199)||chr(8200)||chr(8201)||chr(8202)||chr(8232)||chr(8233)||chr(8239)||chr(8287)||chr(12288)||chr(65279)))>0
 AND (SELECT coalesce(sum(CASE WHEN ascii(c)>65535 THEN 2 ELSE 1 END),0)<=max_units
  AND coalesce(bool_and(ascii(c)>=32 OR ascii(c) IN(9,10,13)),true) AND coalesce(bool_and(ascii(c)<>127),true)
  FROM regexp_split_to_table(v#>>'{}','') c),false);
$$;
CREATE FUNCTION private.assert_conversation_meal_input(v jsonb) RETURNS void
LANGUAGE plpgsql IMMUTABLE SET search_path=pg_catalog AS $$
DECLARE s jsonb:=v->'source';k text;
BEGIN
 IF v IS NULL OR jsonb_typeof(v)<>'object' OR
  NOT (v ?& ARRAY['command_protocol','command_id','kind','source']) OR
  v->>'command_protocol' IS DISTINCT FROM 'conversation.command.v1' OR v->>'kind' IS DISTINCT FROM 'meal.report' OR
  jsonb_typeof(v->'command_id')<>'string' OR NOT ((v->>'command_id' COLLATE "C") ~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$') OR
  (v ? 'meal_type' AND (jsonb_typeof(v->'meal_type')<>'string' OR v->>'meal_type' NOT IN('cafe','almoco','lanche','jantar','ceia','outro'))) OR
  jsonb_typeof(s)<>'object' THEN RAISE EXCEPTION 'invalid_conversation_command' USING ERRCODE='22023'; END IF;
 FOR k IN SELECT jsonb_object_keys(v) LOOP
  IF k NOT IN('command_protocol','command_id','kind','meal_type','source') THEN RAISE EXCEPTION 'invalid_conversation_command' USING ERRCODE='22023'; END IF;
 END LOOP;
 IF s->>'channel'='text' THEN
  IF (SELECT count(*) FROM jsonb_object_keys(s))<>2 OR NOT private.conversation_command_text_valid(s->'text',2000) THEN RAISE EXCEPTION 'invalid_conversation_command' USING ERRCODE='22023'; END IF;
 ELSIF s->>'channel'='media' THEN
  IF NOT (s ?& ARRAY['channel','media_asset_id','user_action']) OR
   jsonb_typeof(s->'media_asset_id')<>'string' OR NOT ((s->>'media_asset_id' COLLATE "C") ~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$') OR
   s->>'user_action' IS DISTINCT FROM 'register_consumed_meal' OR
   (s ? 'caption' AND NOT private.conversation_command_text_valid(s->'caption',1000)) THEN RAISE EXCEPTION 'invalid_conversation_command' USING ERRCODE='22023'; END IF;
  FOR k IN SELECT jsonb_object_keys(s) LOOP
   IF k NOT IN('channel','media_asset_id','user_action','caption') THEN RAISE EXCEPTION 'invalid_conversation_command' USING ERRCODE='22023'; END IF;
  END LOOP;
 ELSE RAISE EXCEPTION 'invalid_conversation_command' USING ERRCODE='22023'; END IF;
END $$;

-- Common lock order matches reset and workout authority, without enrolling this
-- command in the namespace-constrained workout admissions/lifecycle.
CREATE FUNCTION private.lock_conversation_command_owner(p_user_id uuid) RETURNS void
LANGUAGE plpgsql VOLATILE SET search_path=pg_catalog AS $$
BEGIN
 IF p_user_id IS NULL THEN RAISE EXCEPTION 'invalid_conversation_command' USING ERRCODE='22023'; END IF;
 IF current_setting('transaction_isolation')<>'read committed' THEN RAISE EXCEPTION 'conversation_command_requires_read_committed' USING ERRCODE='22023'; END IF;
 PERFORM pg_advisory_xact_lock(hashtextextended(p_user_id::text||':workouts',0));
 PERFORM u.id FROM public.users u WHERE u.id=p_user_id AND u.status='active' FOR NO KEY UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'conversation_command_owner_not_found' USING ERRCODE='P0002'; END IF;
END $$;
CREATE FUNCTION private.conversation_meal_command_binding(c private.conversation_meal_command_ids) RETURNS jsonb
LANGUAGE sql IMMUTABLE STRICT SET search_path=pg_catalog AS $$
 SELECT jsonb_build_object('owner_id',c.user_id,'command_id',c.command_id,'input_hash',c.input_hash,
 'command_protocol',c.command_protocol,'kind',c.kind,'epoch',c.epoch,'admitted_at',
 to_char(c.admitted_at AT TIME ZONE 'UTC','YYYY-MM-DD"T"HH24:MI:SS.US"Z"'));
$$;
CREATE FUNCTION public.admit_conversation_meal_command(p_user_id uuid,p_input jsonb) RETURNS jsonb
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path=pg_catalog AS $$
DECLARE e private.workout_strength_authority_epochs%ROWTYPE;c private.conversation_meal_command_ids%ROWTYPE;
 h text;id uuid;action text:='replay';
BEGIN
 PERFORM private.assert_trusted_backend();PERFORM private.assert_conversation_meal_input(p_input);
 PERFORM private.lock_conversation_command_owner(p_user_id);
 id:=(p_input->>'command_id')::uuid;
 h:=encode(sha256(convert_to(private.conversation_command_canonical(p_input),'UTF8')),'hex');
 SELECT * INTO e FROM private.workout_strength_authority_epochs WHERE user_id=p_user_id FOR UPDATE;
 IF NOT FOUND THEN
  INSERT INTO private.workout_strength_authority_epochs(user_id,epoch,changed_at)
   VALUES(p_user_id,gen_random_uuid(),clock_timestamp()) RETURNING * INTO e;
 END IF;
 SELECT * INTO c FROM private.conversation_meal_command_ids WHERE user_id=p_user_id AND command_id=id FOR UPDATE;
 IF FOUND THEN
  -- Fence the old identity before examining changed input: reset cannot become
  -- an oracle or turn a previously admitted UUID into a fresh command.
  IF c.invalidated_at IS NOT NULL OR c.epoch IS DISTINCT FROM e.epoch THEN RETURN '{"action":"stale_epoch"}'::jsonb; END IF;
  IF c.input_hash IS DISTINCT FROM h THEN RETURN '{"action":"input_conflict"}'::jsonb; END IF;
 ELSE
  INSERT INTO private.conversation_meal_command_ids(user_id,command_id,input_hash,command_protocol,kind,epoch,admitted_at)
   VALUES(p_user_id,id,h,'conversation.command.v1','meal.report',e.epoch,clock_timestamp()) RETURNING * INTO c;
  INSERT INTO private.conversation_meal_command_sources(user_id,command_id,source_input) VALUES(p_user_id,id,p_input);
  action:='admitted';
 END IF;
 RETURN jsonb_build_object('action',action,'command',private.conversation_meal_command_binding(c));
END $$;

-- This stores candidate preparation only. It is never semantic authorization,
-- nutrition authority or permission to invoke any current/future domain writer.
CREATE FUNCTION public.attach_conversation_meal_candidate(p_user_id uuid,p_command_id uuid,p_input_hash text,p_candidate jsonb) RETURNS jsonb
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path=pg_catalog AS $$
DECLARE e uuid;c private.conversation_meal_command_ids%ROWTYPE;old private.conversation_meal_command_candidates%ROWTYPE;h text;
BEGIN
 PERFORM private.assert_trusted_backend();
 IF p_command_id IS NULL OR p_input_hash IS NULL OR NOT ((p_input_hash COLLATE "C") ~ '^[0-9a-f]{64}$') OR
  p_candidate IS NULL OR jsonb_typeof(p_candidate)<>'object' OR
  NOT (p_candidate ?& ARRAY['schema','input_hash','status','candidate']) OR (SELECT count(*) FROM jsonb_object_keys(p_candidate))<>4 OR
  p_candidate->>'schema' IS DISTINCT FROM 'conversation.meal-candidate.v1' OR p_candidate->>'input_hash' IS DISTINCT FROM p_input_hash OR
  coalesce(p_candidate->>'status' NOT IN('prepared','conversational','clarification_required'),true) OR jsonb_typeof(p_candidate->'candidate')<>'object' OR
  octet_length(p_candidate::text)>131072 THEN RAISE EXCEPTION 'invalid_conversation_candidate' USING ERRCODE='22023'; END IF;
 PERFORM private.lock_conversation_command_owner(p_user_id);
 SELECT epoch INTO e FROM private.workout_strength_authority_epochs WHERE user_id=p_user_id FOR UPDATE;
 SELECT * INTO c FROM private.conversation_meal_command_ids WHERE user_id=p_user_id AND command_id=p_command_id FOR UPDATE;
 IF NOT FOUND THEN RETURN '{"action":"absent"}'::jsonb; END IF;
 IF c.invalidated_at IS NOT NULL OR c.epoch IS DISTINCT FROM e THEN RETURN '{"action":"stale_epoch"}'::jsonb; END IF;
 IF c.input_hash IS DISTINCT FROM p_input_hash THEN RETURN '{"action":"input_conflict"}'::jsonb; END IF;
 IF NOT EXISTS(SELECT 1 FROM private.conversation_meal_command_sources WHERE user_id=p_user_id AND command_id=p_command_id) THEN RETURN '{"action":"stale_epoch"}'::jsonb; END IF;
 h:=encode(sha256(convert_to(private.conversation_command_canonical(p_candidate),'UTF8')),'hex');
 SELECT * INTO old FROM private.conversation_meal_command_candidates WHERE user_id=p_user_id AND command_id=p_command_id;
 IF FOUND THEN
  IF old.candidate IS DISTINCT FROM p_candidate THEN RETURN '{"action":"candidate_conflict"}'::jsonb; END IF;
  RETURN jsonb_build_object('action','replay','candidate_hash',old.candidate_hash);
 END IF;
 INSERT INTO private.conversation_meal_command_candidates VALUES(p_user_id,p_command_id,h,p_candidate,clock_timestamp());
 RETURN jsonb_build_object('action','attached','candidate_hash',h);
END $$;
CREATE FUNCTION public.read_conversation_meal_command(p_user_id uuid,p_command_id uuid) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=pg_catalog AS $$
DECLARE result jsonb;
BEGIN
 PERFORM private.assert_trusted_backend();
 IF p_user_id IS NULL OR p_command_id IS NULL THEN RAISE EXCEPTION 'invalid_conversation_command' USING ERRCODE='22023'; END IF;
 IF current_setting('transaction_isolation')<>'read committed' THEN RAISE EXCEPTION 'conversation_command_requires_read_committed' USING ERRCODE='22023'; END IF;
 -- One snapshot, no ensure/lock/write/seal: reset has either committed or not.
 SELECT CASE WHEN c.invalidated_at IS NOT NULL OR c.epoch IS DISTINCT FROM e.epoch OR s.command_id IS NULL
  THEN '{"action":"stale_epoch"}'::jsonb ELSE
  jsonb_build_object('action','available','command',private.conversation_meal_command_binding(c),
   'state',CASE WHEN p.command_id IS NULL THEN 'admitted' ELSE 'candidate_attached' END,
   'source_input',s.source_input,'candidate',p.candidate,'candidate_hash',p.candidate_hash) END
 INTO result FROM private.conversation_meal_command_ids c
 JOIN public.users u ON u.id=c.user_id AND u.status='active'
 LEFT JOIN private.workout_strength_authority_epochs e ON e.user_id=c.user_id
 LEFT JOIN private.conversation_meal_command_sources s ON s.user_id=c.user_id AND s.command_id=c.command_id
 LEFT JOIN private.conversation_meal_command_candidates p ON p.user_id=c.user_id AND p.command_id=c.command_id
 WHERE c.user_id=p_user_id AND c.command_id=p_command_id;
 RETURN coalesce(result,'{"action":"absent"}'::jsonb);
END $$;
CREATE FUNCTION private.scrub_conversation_meal_commands_on_epoch() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog AS $$
BEGIN
 IF OLD.epoch IS DISTINCT FROM NEW.epoch THEN
  UPDATE private.conversation_meal_command_ids SET invalidated_at=clock_timestamp()
   WHERE user_id=NEW.user_id AND invalidated_at IS NULL;
  DELETE FROM private.conversation_meal_command_sources WHERE user_id=NEW.user_id;
 END IF;
 RETURN NEW;
END $$;
CREATE TRIGGER conversation_meal_command_epoch_scrub AFTER UPDATE OF epoch ON private.workout_strength_authority_epochs
 FOR EACH ROW WHEN(OLD.epoch IS DISTINCT FROM NEW.epoch) EXECUTE FUNCTION private.scrub_conversation_meal_commands_on_epoch();

REVOKE ALL ON FUNCTION private.conversation_command_immutable(),private.conversation_command_canonical(jsonb),
 private.conversation_command_text_valid(jsonb,integer),private.assert_conversation_meal_input(jsonb),
 private.lock_conversation_command_owner(uuid),private.conversation_meal_command_binding(private.conversation_meal_command_ids),
 private.scrub_conversation_meal_commands_on_epoch(),public.admit_conversation_meal_command(uuid,jsonb),
 public.attach_conversation_meal_candidate(uuid,uuid,text,jsonb),public.read_conversation_meal_command(uuid,uuid)
 FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.admit_conversation_meal_command(uuid,jsonb),
 public.attach_conversation_meal_candidate(uuid,uuid,text,jsonb),public.read_conversation_meal_command(uuid,uuid) TO service_role;
COMMIT;
