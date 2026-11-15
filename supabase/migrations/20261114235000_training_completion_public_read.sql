-- Additive v2 observation. Existing progress-v1 routes/readers remain literal.
BEGIN;
SET LOCAL lock_timeout='5s';
DO $preflight$ BEGIN
 IF current_user<>'postgres' OR to_regclass('private.training_execution_completions') IS NULL
 OR to_regprocedure('private.training_execution_completion_context(uuid,uuid,uuid,uuid)') IS NULL
 OR (SELECT encode(sha256(convert_to(prosrc,'UTF8')),'hex') FROM pg_proc
  WHERE oid=to_regprocedure('private.conversation_journal_events_v3(uuid,uuid)')) IS DISTINCT FROM
  '0bfc9a75ce93ed261d028c968cf438c1574ab14a769dc958e63b04c35f4fa0a1' THEN
  RAISE EXCEPTION 'training_completion_read_unknown_substrate'; END IF;
END $preflight$;
CREATE FUNCTION public.read_training_execution_state_v2_authenticated(p_user_id uuid,p_auth_user_id uuid,p_auth_session_id uuid,p_session_id uuid)
RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path=pg_catalog AS $$
DECLARE c jsonb;s jsonb;op uuid;v jsonb;
BEGIN
 PERFORM private.lock_training_execution_auth_session(p_user_id,p_auth_user_id,p_auth_session_id);
 IF p_session_id IS NULL THEN RAISE EXCEPTION 'training_execution_invalid_input' USING ERRCODE='22023';END IF;
 c:=private.training_execution_context_at(p_user_id,p_auth_user_id,p_session_id,p_session_id,NULL)->'context';s:=c->'session';
 IF s IS NULL OR s='null'::jsonb THEN RETURN '{"action":"absent"}';END IF;
 SELECT completion_id INTO op FROM private.training_execution_completions
 WHERE user_id=p_user_id AND session_id=p_session_id AND status IN('reserved','completed');
 IF FOUND THEN
  v:=private.training_execution_completion_context(p_user_id,p_auth_user_id,p_auth_session_id,op);
  IF v->>'action' IS DISTINCT FROM 'available' THEN RAISE EXCEPTION 'training_completion_read_changed' USING ERRCODE='40001';END IF;
  RETURN jsonb_build_object('action','completion','context',v);
 END IF;
 IF s->>'schema' IS DISTINCT FROM 'training.execution.v1' OR s->>'phase' NOT IN('in_progress','abandoned') THEN
  RAISE EXCEPTION 'training_completion_read_unproved_state' USING ERRCODE='40001';END IF;
 RETURN jsonb_build_object('action','progress','scope',c->'scope','session',s);
END $$;
REVOKE ALL ON FUNCTION public.read_training_execution_state_v2_authenticated(uuid,uuid,uuid,uuid) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.read_training_execution_state_v2_authenticated(uuid,uuid,uuid,uuid) TO service_role;

-- An uncompleted training reservation is owned by the Training pending UI.
-- Once the protected atomic writer completes it, the existing workout journal
-- discovers the ordinary immutable command exactly once. No old row changes.
DO $journal$
DECLARE definition text;needle text;
BEGIN
 definition:=pg_get_functiondef('private.conversation_journal_events_v3(uuid,uuid)'::regprocedure);
 needle:=' AND NOT EXISTS(SELECT 1 FROM private.conversation_intake_ids i WHERE i.user_id=c.user_id AND i.reserved_child_id=c.command_id)';
 IF (length(definition)-length(replace(definition,needle,'')))/length(needle)<>1 THEN
  RAISE EXCEPTION 'training_completion_journal_hook_changed';END IF;
 definition:=replace(definition,needle,needle||E'\n AND NOT EXISTS(SELECT 1 FROM private.training_execution_completions t WHERE t.user_id=c.user_id AND t.completion_id=c.command_id AND t.status<>''completed'')');
 EXECUTE definition;
END $journal$;

CREATE INDEX training_execution_history_page_v2 ON private.training_execution_sessions
 (user_id,epoch,(state->>'updated_at') DESC,session_id DESC);
CREATE FUNCTION public.read_training_execution_home_v2_authenticated(p_user_id uuid,p_auth_user_id uuid,p_auth_session_id uuid,p_cursor jsonb DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path=pg_catalog AS $$
DECLARE c jsonb;r record;items jsonb:='[]';entry jsonb;comp jsonb;checked jsonb;
 n integer:=0;more boolean:=false;cursor jsonb:=NULL;tail jsonb;observed text;
BEGIN
 PERFORM private.lock_training_execution_auth_session(p_user_id,p_auth_user_id,p_auth_session_id);
 c:=private.training_execution_context_at(p_user_id,p_auth_user_id,NULL,NULL,NULL)->'context';observed:=c#>>'{scope,observed_at}';
 IF p_cursor IS NOT NULL AND (jsonb_typeof(p_cursor) IS DISTINCT FROM 'object'
  OR NOT(p_cursor ?& ARRAY['owner_id','epoch','time_zone','updated_at','session_id'])
  OR p_cursor-ARRAY['owner_id','epoch','time_zone','updated_at','session_id']<>'{}'
  OR p_cursor->>'owner_id' IS DISTINCT FROM p_user_id::text OR p_cursor->>'epoch' IS DISTINCT FROM c#>>'{scope,epoch}'
  OR p_cursor->>'time_zone' IS DISTINCT FROM c#>>'{scope,time_zone}'
  OR jsonb_typeof(p_cursor->'updated_at') IS DISTINCT FROM 'string'
  OR NOT coalesce(p_cursor->>'updated_at' ~ '^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{6}Z$',false)
  OR NOT isfinite((p_cursor->>'updated_at')::timestamptz) OR (p_cursor->>'updated_at')::timestamptz>observed::timestamptz
  OR jsonb_typeof(p_cursor->'session_id') IS DISTINCT FROM 'string'
  OR NOT coalesce(p_cursor->>'session_id' ~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',false)) THEN
  RAISE EXCEPTION 'training_execution_cursor_changed' USING ERRCODE='40001';END IF;
 FOR r IN SELECT t.state,t.session_id,x.completion_id,x.input_hash,x.status,
  EXISTS(SELECT 1 FROM public.daily_snapshots d WHERE d.user_id=p_user_id AND d.date=(t.state->>'local_date')::date AND d.day_closed) closed
  FROM private.training_execution_sessions t LEFT JOIN private.training_execution_completions x
   ON x.user_id=t.user_id AND x.session_id=t.session_id AND x.status IN('reserved','completed')
  WHERE t.user_id=p_user_id AND t.epoch=(c#>>'{scope,epoch}')::uuid
   AND t.state->>'auth_user_id'=p_auth_user_id::text AND t.state->>'time_zone'=c#>>'{scope,time_zone}'
   AND (t.state->>'local_date')::date<=(c#>>'{scope,current_local_date}')::date
   AND (p_cursor IS NULL OR (t.state->>'updated_at',t.session_id)<(p_cursor->>'updated_at',(p_cursor->>'session_id')::uuid))
  ORDER BY t.state->>'updated_at' DESC,t.session_id DESC LIMIT 21 LOOP
  n:=n+1;IF n=21 THEN more:=true;EXIT;END IF;
  comp:=NULL;
  IF r.completion_id IS NOT NULL THEN
   checked:=private.training_execution_completion_context(p_user_id,p_auth_user_id,p_auth_session_id,r.completion_id);
   IF checked->>'action' IS DISTINCT FROM 'available' OR checked->'session' IS DISTINCT FROM r.state THEN
    RAISE EXCEPTION 'training_execution_history_completion_changed' USING ERRCODE='40001';END IF;
   comp:=jsonb_build_object('id',r.completion_id,'input_hash',r.input_hash,'status',r.status);
  ELSIF r.state->>'schema' IS DISTINCT FROM 'training.execution.v1' OR r.state->>'phase' NOT IN('in_progress','abandoned') THEN
   RAISE EXCEPTION 'training_execution_history_unproved_state' USING ERRCODE='40001';
  END IF;
  entry:=jsonb_build_object('id',r.session_id,'revision',r.state->'revision','local_date',r.state->'local_date',
   'started_at',r.state->'started_at','updated_at',r.state->'updated_at','plan_id',r.state#>'{definition,plan_id}',
   'day_index',r.state#>'{definition,day_index}','day_label',r.state#>'{definition,day_label}',
   'total_exercises',jsonb_array_length(r.state->'exercises'),
   'completed_exercises',(SELECT count(*) FROM jsonb_array_elements(r.state->'exercises') e WHERE e->'completed'='true'),
   'phase',r.state->'phase','day_closed',r.closed,'completion',comp);
  items:=items||jsonb_build_array(entry);tail:=entry;
 END LOOP;
 IF more THEN cursor:=jsonb_build_object('owner_id',p_user_id,'epoch',c#>'{scope,epoch}','time_zone',c#>'{scope,time_zone}',
  'updated_at',tail->'updated_at','session_id',tail->'id');END IF;
 RETURN jsonb_build_object('scope',c->'scope','plan',c->'plan','sessions',items,'next_cursor',cursor);
END $$;
REVOKE ALL ON FUNCTION public.read_training_execution_home_v2_authenticated(uuid,uuid,uuid,jsonb) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.read_training_execution_home_v2_authenticated(uuid,uuid,uuid,jsonb) TO service_role;
COMMIT;
