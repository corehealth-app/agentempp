-- T5 backend persistence only. No HTTP route, workout, energy, XP or activation.
-- The original-Auth backend runs the closed TS kernel; this store independently
-- recaptures authority/CAS and restricts the state delta to that single action.
DO $$ BEGIN
 IF current_user<>'postgres' OR to_regprocedure('private.lock_conversation_command_owner(uuid)') IS NULL
  OR to_regclass('private.workout_strength_authority_epochs') IS NULL THEN
  RAISE EXCEPTION 'training_execution_dependencies_missing'; END IF;
END $$;

CREATE TABLE private.training_execution_sessions (
 user_id uuid NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
 session_id uuid NOT NULL, epoch uuid NOT NULL, revision integer NOT NULL CHECK(revision>=0),
 state jsonb NOT NULL CHECK(jsonb_typeof(state)='object' AND octet_length(state::text)<=524288),
 PRIMARY KEY(user_id,session_id),
 CHECK((state->>'owner_id')::uuid=user_id AND (state->>'id')::uuid=session_id
  AND (state->>'epoch')::uuid=epoch AND (state->>'revision')::integer=revision)
);
CREATE TABLE private.training_execution_operations (
 user_id uuid NOT NULL, session_id uuid NOT NULL, operation_id uuid NOT NULL,
 input jsonb NOT NULL CHECK(jsonb_typeof(input)='object' AND octet_length(input::text)<=16384),
 receipt jsonb NOT NULL CHECK(jsonb_typeof(receipt)='object'),
 PRIMARY KEY(user_id,operation_id),
 FOREIGN KEY(user_id,session_id) REFERENCES private.training_execution_sessions(user_id,session_id) ON DELETE CASCADE
);
CREATE TABLE private.training_execution_audit (
 user_id uuid NOT NULL, operation_id uuid NOT NULL, delta jsonb NOT NULL,
 PRIMARY KEY(user_id,operation_id),
 FOREIGN KEY(user_id,operation_id) REFERENCES private.training_execution_operations(user_id,operation_id) ON DELETE CASCADE,
 CHECK(jsonb_typeof(delta)='object' AND octet_length(delta::text)<=16384)
);
ALTER TABLE private.training_execution_sessions ENABLE ROW LEVEL SECURITY;
ALTER TABLE private.training_execution_operations ENABLE ROW LEVEL SECURITY;
ALTER TABLE private.training_execution_audit ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON private.training_execution_sessions,private.training_execution_operations,private.training_execution_audit FROM PUBLIC,anon,authenticated,service_role;

-- Same owner/workouts lane as reset. Original session day, not current clock's
-- day, gates an update across midnight. No clinical target is recalculated here.
CREATE FUNCTION private.training_execution_context_at(p_user uuid,p_auth uuid,p_session uuid,p_operation uuid,p_at timestamptz)
RETURNS jsonb LANGUAGE plpgsql VOLATILE SET search_path=pg_catalog SET timezone='UTC' SET datestyle='ISO,YMD' AS $$
DECLARE u public.users%ROWTYPE; e uuid; s jsonb; r jsonb; p jsonb; d date; opened date; observed timestamptz; c jsonb;
BEGIN
 PERFORM private.assert_trusted_backend();
 IF p_user IS NULL OR p_auth IS NULL OR p_session IS NULL OR p_operation IS NULL THEN
  RAISE EXCEPTION 'training_execution_invalid_input' USING ERRCODE='22023'; END IF;
 PERFORM private.lock_conversation_command_owner(p_user);
 SELECT * INTO STRICT u FROM public.users WHERE id=p_user;
 IF u.auth_user_id IS DISTINCT FROM p_auth THEN RAISE EXCEPTION 'training_execution_owner_changed' USING ERRCODE='42501'; END IF;
 IF NOT EXISTS(SELECT 1 FROM pg_timezone_names WHERE name=u.timezone) THEN RAISE EXCEPTION 'training_execution_scope_unavailable' USING ERRCODE='55000'; END IF;
 SELECT epoch INTO e FROM private.workout_strength_authority_epochs WHERE user_id=p_user FOR UPDATE;
 IF NOT FOUND THEN INSERT INTO private.workout_strength_authority_epochs(user_id,epoch,changed_at)
  VALUES(p_user,gen_random_uuid(),clock_timestamp()) RETURNING epoch INTO e; END IF;
 observed:=coalesce(p_at,clock_timestamp());
 IF NOT isfinite(observed) OR observed>clock_timestamp() OR observed<clock_timestamp()-interval '5 minutes' THEN
  RAISE EXCEPTION 'training_execution_capture_expired' USING ERRCODE='40001'; END IF;
 d:=(observed AT TIME ZONE u.timezone)::date;
 IF d<>(clock_timestamp() AT TIME ZONE u.timezone)::date THEN RAISE EXCEPTION 'training_execution_scope_changed' USING ERRCODE='40001'; END IF;
 SELECT state INTO s FROM private.training_execution_sessions WHERE user_id=p_user AND session_id=p_session FOR UPDATE;
 SELECT receipt INTO r FROM private.training_execution_operations WHERE user_id=p_user AND operation_id=p_operation;
 opened:=coalesce((s->>'local_date')::date,d);
 PERFORM pg_advisory_xact_lock(hashtextextended(p_user::text||':'||opened::text,0));
 PERFORM 1 FROM public.daily_snapshots WHERE user_id=p_user AND date=opened AND day_closed FOR SHARE;
 IF FOUND THEN opened:=NULL; END IF;
 IF s IS NULL THEN
  SELECT to_jsonb(t) INTO p FROM public.training_plans t WHERE user_id=p_user AND active
   AND generated_at<=observed AND (valid_until IS NULL OR valid_until>observed)
   ORDER BY generated_at DESC,version DESC,id LIMIT 1 FOR SHARE;
 END IF;
 c:=jsonb_build_object('scope',jsonb_build_object('owner_id',p_user,'auth_user_id',p_auth,'epoch',e,
  'time_zone',u.timezone,'current_local_date',d::text,'open_local_date',opened::text,
  'observed_at',to_char(observed AT TIME ZONE 'UTC','YYYY-MM-DD"T"HH24:MI:SS.US"Z"'),'recording_allowed',true),
  'plan',p,'session',s,'prior_receipt',r);
 RETURN jsonb_build_object('context',c,'context_hash',encode(sha256(convert_to(c::text,'UTF8')),'hex'));
END $$;
CREATE FUNCTION public.capture_training_execution_context(p_user_id uuid,p_auth_user_id uuid,p_session_id uuid,p_operation_id uuid)
RETURNS jsonb LANGUAGE sql VOLATILE SECURITY DEFINER SET search_path=pg_catalog AS $$
 SELECT private.training_execution_context_at(p_user_id,p_auth_user_id,p_session_id,p_operation_id,NULL);
$$;

CREATE FUNCTION public.commit_training_execution_mutation(p_user_id uuid,p_auth_user_id uuid,p_command jsonb,
 p_context_hash text,p_observed_at timestamptz,p_prepared jsonb)
RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path=pg_catalog AS $$
DECLARE captured jsonb; c jsonb; s jsonb; n jsonb:=p_prepared->'session'; r jsonb:=p_prepared->'receipt';
 audit jsonb:=p_prepared->'audit'; old private.training_execution_operations%ROWTYPE;
 sid uuid; op uuid; kind text; rev integer; expected jsonb; a jsonb:=p_command->'action';
 x integer; item jsonb; old_item jsonb; sets jsonb; before_value jsonb; after_value jsonb; expected_audit jsonb;
BEGIN
 PERFORM private.assert_trusted_backend();
 IF jsonb_typeof(p_command) IS DISTINCT FROM 'object' OR octet_length(p_command::text)>16384
  OR jsonb_typeof(p_prepared) IS DISTINCT FROM 'object' OR p_prepared-ARRAY['status','session','receipt','audit']<>'{}'::jsonb
  OR jsonb_typeof(n) IS DISTINCT FROM 'object' OR octet_length(n::text)>524288 THEN
  RAISE EXCEPTION 'training_execution_invalid_input' USING ERRCODE='22023'; END IF;
 sid:=(p_command->>'session_id')::uuid;op:=(p_command->>'operation_id')::uuid;
 captured:=private.training_execution_context_at(p_user_id,p_auth_user_id,sid,op,NULL);c:=captured->'context';s:=c->'session';
 IF (p_command->>'expected_epoch')::uuid IS DISTINCT FROM (c#>>'{scope,epoch}')::uuid THEN
  RAISE EXCEPTION 'training_execution_epoch_changed' USING ERRCODE='40001'; END IF;
 SELECT * INTO old FROM private.training_execution_operations WHERE user_id=p_user_id AND operation_id=op;
 IF FOUND THEN
  IF old.session_id<>sid OR old.input IS DISTINCT FROM p_command THEN RAISE EXCEPTION 'training_execution_operation_conflict' USING ERRCODE='40001'; END IF;
  IF s='null'::jsonb OR s->>'auth_user_id' IS DISTINCT FROM p_auth_user_id::text
   OR s->>'epoch' IS DISTINCT FROM c#>>'{scope,epoch}'
   OR s->>'time_zone' IS DISTINCT FROM c#>>'{scope,time_zone}' THEN
   RAISE EXCEPTION 'training_execution_scope_changed' USING ERRCODE='40001'; END IF;
  -- Return CURRENT state, never the state at this operation's old revision.
  RETURN jsonb_build_object('status','replayed','session',s,'receipt',old.receipt,'audit',NULL);
 END IF;
 captured:=private.training_execution_context_at(p_user_id,p_auth_user_id,sid,op,p_observed_at);c:=captured->'context';s:=c->'session';
 IF captured->>'context_hash' IS DISTINCT FROM p_context_hash THEN RAISE EXCEPTION 'training_execution_context_changed' USING ERRCODE='40001'; END IF;
 kind:=CASE WHEN p_command->>'schema'='training.execution.start.v1' THEN 'start' ELSE a->>'kind' END;
 IF kind IS NULL OR kind NOT IN('start','save_set','remove_set','mark_exercise','abandon') THEN
  RAISE EXCEPTION 'training_execution_invalid_input' USING ERRCODE='22023'; END IF;
 IF c#>>'{scope,open_local_date}' IS NULL OR c#>>'{scope,open_local_date}' IS DISTINCT FROM
  (CASE WHEN s='null'::jsonb THEN c#>>'{scope,current_local_date}' ELSE s->>'local_date' END) THEN
  RAISE EXCEPTION 'training_execution_day_closed' USING ERRCODE='40001'; END IF;
 IF n->>'schema' IS DISTINCT FROM 'training.execution.v1' OR (n->>'id')::uuid IS DISTINCT FROM sid
  OR (n->>'owner_id')::uuid IS DISTINCT FROM p_user_id OR (n->>'auth_user_id')::uuid IS DISTINCT FROM p_auth_user_id
  OR (n->>'epoch')::uuid IS DISTINCT FROM (c#>>'{scope,epoch}')::uuid
  OR n->>'time_zone' IS DISTINCT FROM c#>>'{scope,time_zone}'
  OR n->>'updated_at' IS DISTINCT FROM c#>>'{scope,observed_at}' THEN
  RAISE EXCEPTION 'training_execution_invalid_state' USING ERRCODE='22023'; END IF;
 IF kind='start' THEN
  IF s<>'null'::jsonb OR c->'plan'='null'::jsonb OR op<>sid
   OR p_command->>'expected_local_date' IS DISTINCT FROM c#>>'{scope,current_local_date}'
   OR n->>'local_date' IS DISTINCT FROM c#>>'{scope,current_local_date}'
   OR n->>'started_at' IS DISTINCT FROM n->>'updated_at'
   OR n->>'phase' IS DISTINCT FROM 'in_progress' OR n->>'revision' IS DISTINCT FROM '0'
   OR n#>>'{definition,plan_id}' IS DISTINCT FROM c#>>'{plan,id}'
   OR n#>'{definition,plan_version}' IS DISTINCT FROM c#>'{plan,version}'
   OR n#>>'{definition,plan_hash}' IS DISTINCT FROM p_command->>'plan_hash'
   OR n#>'{definition,day_index}' IS DISTINCT FROM p_command->'day_index'
   OR p_command->>'plan_id' IS DISTINCT FROM c#>>'{plan,id}' THEN
   RAISE EXCEPTION 'training_execution_plan_or_start_changed' USING ERRCODE='40001'; END IF;
  -- Recommendations are a backend projection of the captured original plan;
  -- initial actuals must be empty regardless of prescribed repetitions/sets.
  IF jsonb_array_length(n->'exercises') NOT BETWEEN 1 AND 20 OR EXISTS(
   SELECT 1 FROM jsonb_array_elements(n->'exercises') WITH ORDINALITY q(v,i)
   WHERE v IS DISTINCT FROM jsonb_build_object('index',i-1,'completed',false,'sets','[]'::jsonb)) THEN
   RAISE EXCEPTION 'training_execution_invalid_actuals' USING ERRCODE='22023'; END IF;
  rev:=0;
  expected_audit:=jsonb_build_object('kind','start','before',NULL,'after',jsonb_build_object(
   'plan_id',p_command->'plan_id','plan_hash',p_command->'plan_hash','day_index',p_command->'day_index'));
 ELSE
  IF p_command->>'schema' IS DISTINCT FROM 'training.execution.update.v1' OR s='null'::jsonb OR s->>'phase'<>'in_progress'
   OR s->>'time_zone' IS DISTINCT FROM c#>>'{scope,time_zone}'
   OR (p_command->>'expected_revision')::integer IS DISTINCT FROM (s->>'revision')::integer THEN
   RAISE EXCEPTION 'training_execution_revision_or_scope_changed' USING ERRCODE='40001'; END IF;
  rev:=(s->>'revision')::integer+1;
  expected:=s||jsonb_build_object('revision',rev,'updated_at',n->'updated_at');
  IF kind='abandon' THEN
   expected:=expected||'{"phase":"abandoned"}';
   expected_audit:='{"kind":"abandon","before":"in_progress","after":"abandoned"}';
  ELSE
   x:=(a->>'exercise_index')::integer;item:=s#>ARRAY['exercises',x::text];
   IF x IS NULL OR x<0 OR item IS NULL THEN RAISE EXCEPTION 'training_execution_invalid_exercise' USING ERRCODE='22023'; END IF;
   IF kind='mark_exercise' THEN
    IF jsonb_typeof(a->'completed') IS DISTINCT FROM 'boolean' THEN RAISE EXCEPTION 'training_execution_invalid_input' USING ERRCODE='22023'; END IF;
    before_value:=item->'completed';after_value:=a->'completed';item:=item||jsonb_build_object('completed',after_value);
   ELSE
    SELECT v INTO old_item FROM jsonb_array_elements(item->'sets') v WHERE v->>'id'=coalesce(a#>>'{set,id}',a->>'set_id');
    before_value:=coalesce(old_item,'null'::jsonb);
    IF kind='save_set' THEN
     after_value:=a->'set';
     IF jsonb_typeof(after_value) IS DISTINCT FROM 'object' OR EXISTS(
      SELECT 1 FROM jsonb_array_elements(s->'exercises') q, jsonb_array_elements(q->'sets') v
      WHERE (q->>'index')::integer<>x AND v->>'id'=after_value->>'id') OR EXISTS(
      SELECT 1 FROM jsonb_array_elements(item->'sets') v WHERE v->>'id'<>after_value->>'id' AND v->'index'=after_value->'index') THEN
      RAISE EXCEPTION 'training_execution_set_conflict' USING ERRCODE='40001'; END IF;
     SELECT jsonb_agg(v ORDER BY (v->>'index')::integer) INTO sets FROM (
      SELECT v FROM jsonb_array_elements(item->'sets') v WHERE v->>'id'<>after_value->>'id' UNION ALL SELECT after_value) q;
     IF jsonb_array_length(sets)>100 THEN RAISE EXCEPTION 'training_execution_set_limit' USING ERRCODE='22023'; END IF;
    ELSE
     IF old_item IS NULL THEN RAISE EXCEPTION 'training_execution_set_conflict' USING ERRCODE='40001'; END IF;
     after_value:='null';SELECT coalesce(jsonb_agg(v ORDER BY (v->>'index')::integer),'[]') INTO sets FROM jsonb_array_elements(item->'sets') v WHERE v->>'id'<>a->>'set_id';
    END IF;
    item:=item||jsonb_build_object('sets',sets);
   END IF;
   expected:=jsonb_set(expected,ARRAY['exercises',x::text],item);
   expected_audit:=jsonb_build_object('kind',kind,'exercise_index',x,'before',before_value,'after',after_value);
  END IF;
  IF n IS DISTINCT FROM expected THEN RAISE EXCEPTION 'training_execution_unexpected_delta' USING ERRCODE='22023'; END IF;
 END IF;
 IF audit IS DISTINCT FROM expected_audit OR jsonb_typeof(r) IS DISTINCT FROM 'object'
  OR r-ARRAY['schema','owner_id','epoch','session_id','operation_id','input_hash','before_revision','after_revision','kind','at']<>'{}'
  OR r->>'schema' IS DISTINCT FROM 'training.execution.receipt.v1'
  OR r->>'owner_id' IS DISTINCT FROM n->>'owner_id' OR r->>'epoch' IS DISTINCT FROM n->>'epoch'
  OR (r->>'session_id')::uuid IS DISTINCT FROM sid OR (r->>'operation_id')::uuid IS DISTINCT FROM op
  OR r->>'kind' IS DISTINCT FROM kind OR r->>'at' IS DISTINCT FROM n->>'updated_at'
  OR r->'before_revision' IS DISTINCT FROM (CASE WHEN kind='start' THEN 'null'::jsonb ELSE s->'revision' END)
  OR (r->>'after_revision')::integer IS DISTINCT FROM rev
  OR NOT coalesce(r->>'input_hash' ~ '^[0-9a-f]{64}$',false) THEN
  RAISE EXCEPTION 'training_execution_invalid_receipt_or_audit' USING ERRCODE='22023'; END IF;
 INSERT INTO private.training_execution_sessions(user_id,session_id,epoch,revision,state)
  VALUES(p_user_id,sid,(n->>'epoch')::uuid,rev,n)
  ON CONFLICT(user_id,session_id) DO UPDATE SET revision=excluded.revision,state=excluded.state;
 INSERT INTO private.training_execution_operations VALUES(p_user_id,sid,op,p_command,r);
 INSERT INTO private.training_execution_audit VALUES(p_user_id,op,audit);
 RETURN jsonb_build_object('status',CASE WHEN kind='start' THEN 'created' ELSE 'updated' END,'session',n,'receipt',r,'audit',audit);
END $$;

CREATE FUNCTION private.scrub_training_execution_on_epoch() RETURNS trigger LANGUAGE plpgsql SET search_path=pg_catalog AS $$
BEGIN DELETE FROM private.training_execution_sessions WHERE user_id=NEW.user_id;RETURN NEW; END $$;
CREATE TRIGGER training_execution_epoch_scrub AFTER UPDATE OF epoch ON private.workout_strength_authority_epochs
 FOR EACH ROW WHEN(OLD.epoch IS DISTINCT FROM NEW.epoch) EXECUTE FUNCTION private.scrub_training_execution_on_epoch();
REVOKE ALL ON FUNCTION private.training_execution_context_at(uuid,uuid,uuid,uuid,timestamptz),private.scrub_training_execution_on_epoch() FROM PUBLIC,anon,authenticated,service_role;
REVOKE ALL ON FUNCTION public.capture_training_execution_context(uuid,uuid,uuid,uuid),public.commit_training_execution_mutation(uuid,uuid,jsonb,text,timestamptz,jsonb) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.capture_training_execution_context(uuid,uuid,uuid,uuid),public.commit_training_execution_mutation(uuid,uuid,jsonb,text,timestamptz,jsonb) TO service_role;
