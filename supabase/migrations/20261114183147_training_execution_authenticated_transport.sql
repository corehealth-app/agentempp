-- T5 original live-session transport; reads never initialize domain state.
CREATE OR REPLACE FUNCTION private.training_execution_context_at(p_user uuid,p_auth uuid,p_session uuid,p_operation uuid,p_at timestamptz)
RETURNS jsonb LANGUAGE plpgsql VOLATILE SET search_path=pg_catalog SET timezone='UTC' SET datestyle='ISO,YMD' AS $$
DECLARE u public.users%ROWTYPE; e uuid; s jsonb; r jsonb; p jsonb; d date; opened date; observed timestamptz; c jsonb;
BEGIN
 PERFORM private.assert_trusted_backend();
 IF p_user IS NULL OR p_auth IS NULL OR (p_session IS NULL) IS DISTINCT FROM (p_operation IS NULL) THEN
  RAISE EXCEPTION 'training_execution_invalid_input' USING ERRCODE='22023'; END IF;
 PERFORM private.lock_conversation_command_owner(p_user);
 SELECT * INTO STRICT u FROM public.users WHERE id=p_user;
 IF u.auth_user_id IS DISTINCT FROM p_auth THEN RAISE EXCEPTION 'training_execution_owner_changed' USING ERRCODE='42501'; END IF;
 IF NOT EXISTS(SELECT 1 FROM pg_timezone_names WHERE name=u.timezone) THEN RAISE EXCEPTION 'training_execution_scope_unavailable' USING ERRCODE='55000'; END IF;
 SELECT epoch INTO e FROM private.workout_strength_authority_epochs WHERE user_id=p_user FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'training_execution_epoch_unavailable' USING ERRCODE='55000'; END IF;
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

-- Owner first, then short shared Auth session lock: logout/delete cannot pass
-- between this check and the atomic command. No refresh token or JWT is stored.
CREATE FUNCTION private.lock_training_execution_auth_session(p_user uuid,p_auth uuid,p_login uuid)
RETURNS void LANGUAGE plpgsql VOLATILE SET search_path=pg_catalog AS $$
BEGIN
 PERFORM private.assert_trusted_backend();PERFORM private.lock_conversation_command_owner(p_user);
 IF p_login IS NULL OR NOT EXISTS(SELECT 1 FROM public.users WHERE id=p_user AND auth_user_id=p_auth)
  OR EXISTS(SELECT 1 FROM public.admin_users WHERE id=p_auth) THEN
  RAISE EXCEPTION 'training_execution_auth_unavailable' USING ERRCODE='42501'; END IF;
 BEGIN
  PERFORM 1 FROM auth.sessions WHERE id=p_login AND user_id=p_auth
   AND (not_after IS NULL OR not_after>clock_timestamp()) FOR SHARE NOWAIT;
 EXCEPTION WHEN lock_not_available THEN RAISE EXCEPTION 'training_execution_auth_changed' USING ERRCODE='40001'; END;
 IF NOT FOUND THEN RAISE EXCEPTION 'training_execution_auth_unavailable' USING ERRCODE='42501'; END IF;
END $$;
CREATE FUNCTION public.capture_training_execution_context_authenticated(p_user_id uuid,p_auth_user_id uuid,p_auth_session_id uuid,p_session_id uuid,p_operation_id uuid)
RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path=pg_catalog AS $$
BEGIN
 PERFORM private.lock_training_execution_auth_session(p_user_id,p_auth_user_id,p_auth_session_id);
 IF p_session_id IS NULL OR p_operation_id IS NULL THEN RAISE EXCEPTION 'training_execution_invalid_input' USING ERRCODE='22023'; END IF;
 RETURN private.training_execution_context_at(p_user_id,p_auth_user_id,p_session_id,p_operation_id,NULL);
END $$;
CREATE FUNCTION public.commit_training_execution_mutation_authenticated(p_user_id uuid,p_auth_user_id uuid,p_auth_session_id uuid,
 p_command jsonb,p_context_hash text,p_observed_at timestamptz,p_prepared jsonb)
RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path=pg_catalog AS $$
DECLARE value jsonb;
BEGIN
 PERFORM private.lock_training_execution_auth_session(p_user_id,p_auth_user_id,p_auth_session_id);
 value:=public.commit_training_execution_mutation(p_user_id,p_auth_user_id,p_command,p_context_hash,p_observed_at,p_prepared);
 -- Natural expiry during the writer also aborts its entire transaction.
 PERFORM private.lock_training_execution_auth_session(p_user_id,p_auth_user_id,p_auth_session_id);
 RETURN value;
END $$;

CREATE INDEX training_execution_resume_page ON private.training_execution_sessions
 (user_id,epoch,(state->>'updated_at') DESC,session_id DESC) WHERE state->>'phase'='in_progress';
CREATE FUNCTION public.read_training_execution_home_authenticated(p_user_id uuid,p_auth_user_id uuid,p_auth_session_id uuid,p_cursor jsonb DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path=pg_catalog AS $$
DECLARE c jsonb; summaries jsonb; has_more boolean; tail jsonb; cursor jsonb:=NULL; observed text;
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
  OR NOT isfinite((p_cursor->>'updated_at')::timestamptz)
  OR (p_cursor->>'updated_at')::timestamptz>observed::timestamptz
  OR jsonb_typeof(p_cursor->'session_id') IS DISTINCT FROM 'string'
  OR NOT coalesce(p_cursor->>'session_id' ~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',false)) THEN
  RAISE EXCEPTION 'training_execution_cursor_changed' USING ERRCODE='40001'; END IF;
 WITH owned AS (
  SELECT state,session_id FROM private.training_execution_sessions t
  WHERE t.user_id=p_user_id AND t.epoch=(c#>>'{scope,epoch}')::uuid AND state->>'phase'='in_progress'
   AND state->>'auth_user_id'=p_auth_user_id::text AND state->>'time_zone'=c#>>'{scope,time_zone}'
   AND (state->>'local_date')::date<=(c#>>'{scope,current_local_date}')::date
   AND NOT EXISTS(SELECT 1 FROM public.daily_snapshots d WHERE d.user_id=p_user_id AND d.date=(state->>'local_date')::date AND d.day_closed)
   AND (p_cursor IS NULL OR (state->>'updated_at',session_id)<(p_cursor->>'updated_at',(p_cursor->>'session_id')::uuid))
  ORDER BY state->>'updated_at' DESC,session_id DESC LIMIT 21
 ), numbered AS (SELECT *,row_number() OVER(ORDER BY state->>'updated_at' DESC,session_id DESC) n FROM owned)
 SELECT coalesce(jsonb_agg(jsonb_build_object('id',session_id,'revision',state->'revision','local_date',state->'local_date',
   'started_at',state->'started_at','updated_at',state->'updated_at','plan_id',state#>'{definition,plan_id}',
   'day_index',state#>'{definition,day_index}','day_label',state#>'{definition,day_label}',
   'total_exercises',jsonb_array_length(state->'exercises'),
   'completed_exercises',(SELECT count(*) FROM jsonb_array_elements(state->'exercises') v WHERE v->'completed'='true'))
   ORDER BY n) FILTER(WHERE n<=20),'[]'),coalesce(bool_or(n>20),false),
   (jsonb_agg(jsonb_build_object('updated_at',state->'updated_at','session_id',session_id) ORDER BY n DESC) FILTER(WHERE n<=20))->0
 INTO summaries,has_more,tail FROM numbered;
 IF has_more THEN cursor:=jsonb_build_object('owner_id',p_user_id,'epoch',c#>'{scope,epoch}',
  'time_zone',c#>'{scope,time_zone}')||tail; END IF;
 RETURN jsonb_build_object('scope',c->'scope','plan',c->'plan','sessions',summaries,'next_cursor',cursor);
END $$;
REVOKE ALL ON FUNCTION private.lock_training_execution_auth_session(uuid,uuid,uuid) FROM PUBLIC,anon,authenticated,service_role;
REVOKE ALL ON FUNCTION public.capture_training_execution_context_authenticated(uuid,uuid,uuid,uuid,uuid),
 public.commit_training_execution_mutation_authenticated(uuid,uuid,uuid,jsonb,text,timestamptz,jsonb),
 public.read_training_execution_home_authenticated(uuid,uuid,uuid,jsonb) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.capture_training_execution_context_authenticated(uuid,uuid,uuid,uuid,uuid),
 public.commit_training_execution_mutation_authenticated(uuid,uuid,uuid,jsonb,text,timestamptz,jsonb),
 public.read_training_execution_home_authenticated(uuid,uuid,uuid,jsonb) TO service_role;
