-- P0-A: privileged RPCs are backend-only. The helper also protects against
-- accidental future grants to an end-user role.
CREATE SCHEMA IF NOT EXISTS private;

REVOKE ALL ON SCHEMA private FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION private.assert_trusted_backend()
RETURNS void
LANGUAGE plpgsql
STABLE
SECURITY INVOKER
SET search_path = pg_catalog, auth, pg_temp
AS $$
DECLARE
  v_jwt_role text := NULLIF(auth.jwt() ->> 'role', '');
BEGIN
  IF v_jwt_role IS NOT NULL THEN
    IF v_jwt_role <> 'service_role' THEN
      RAISE EXCEPTION 'trusted backend role required'
        USING ERRCODE = '42501';
    END IF;
  ELSIF session_user NOT IN ('postgres', 'supabase_admin') THEN
    RAISE EXCEPTION 'trusted database session required'
      USING ERRCODE = '42501';
  END IF;
END;
$$;

REVOKE ALL ON FUNCTION private.assert_trusted_backend()
  FROM PUBLIC, anon, authenticated, service_role;

COMMENT ON FUNCTION private.assert_trusted_backend() IS
  'Defense in depth for service-role RPCs and database-owned cron execution.';

CREATE OR REPLACE FUNCTION public.is_admin()
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, public, pg_temp
AS $$
  SELECT EXISTS(
    SELECT 1
    FROM public.admin_users
    WHERE id = auth.uid()
      AND role IN (
        'admin', 'editor', 'viewer',
        'support', 'content_editor', 'nutrition_admin',
        'operations_admin', 'master_admin'
      )
  );
$$;

CREATE OR REPLACE FUNCTION public.admin_role()
RETURNS text
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, public, pg_temp
AS $$
  SELECT role
  FROM public.admin_users
  WHERE id = auth.uid();
$$;

REVOKE ALL ON FUNCTION public.is_admin() FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.admin_role() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.is_admin() TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.admin_role() TO authenticated, service_role;

CREATE OR REPLACE FUNCTION public.dispatch_inngest_event(
  p_event_name text,
  p_data jsonb DEFAULT '{}'::jsonb,
  p_delay_ms integer DEFAULT NULL
)
RETURNS bigint
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public, net, pg_temp
AS $$
DECLARE
  v_key text;
  v_body jsonb;
  v_request_id bigint;
BEGIN
  PERFORM private.assert_trusted_backend();

  SELECT value
  INTO v_key
  FROM public.service_credentials
  WHERE service = 'inngest'
    AND key_name = 'event_key'
    AND is_active = true
  LIMIT 1;

  IF v_key IS NULL THEN
    RAISE WARNING 'dispatch_inngest_event: inngest.event_key is not configured';
    RETURN NULL;
  END IF;

  v_body := jsonb_build_object('name', p_event_name, 'data', p_data);
  IF p_delay_ms IS NOT NULL AND p_delay_ms > 0 THEN
    v_body := v_body || jsonb_build_object(
      'ts', (extract(epoch FROM now()) * 1000)::bigint + p_delay_ms
    );
  END IF;

  SELECT net.http_post(
    url := 'https://inn.gs/e/' || v_key,
    body := v_body,
    headers := jsonb_build_object('Content-Type', 'application/json')
  )
  INTO v_request_id;

  RETURN v_request_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.refresh_mv_kpis_daily()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public, pg_temp
AS $$
BEGIN
  PERFORM private.assert_trusted_backend();
  REFRESH MATERIALIZED VIEW CONCURRENTLY public.mv_kpis_daily;
END;
$$;

CREATE OR REPLACE FUNCTION public.pause_user(p_user_id uuid, p_days integer)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public, pg_temp
AS $$
BEGIN
  PERFORM private.assert_trusted_backend();

  UPDATE public.users
  SET metadata = COALESCE(metadata, '{}'::jsonb)
      || jsonb_build_object(
        'paused_until', (now() + (p_days || ' days')::interval)::text,
        'paused_at', now()::text
      ),
      updated_at = now()
  WHERE id = p_user_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.resume_user(p_user_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public, pg_temp
AS $$
BEGIN
  PERFORM private.assert_trusted_backend();

  UPDATE public.users
  SET metadata = COALESCE(metadata, '{}'::jsonb) - 'paused_until' - 'paused_at',
      updated_at = now()
  WHERE id = p_user_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.set_global_config(p_key text, p_value jsonb)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public, pg_temp
AS $$
BEGIN
  PERFORM private.assert_trusted_backend();

  INSERT INTO public.global_config (key, value, updated_at)
  VALUES (p_key, p_value, now())
  ON CONFLICT (key) DO UPDATE
    SET value = EXCLUDED.value,
        updated_at = now();
END;
$$;

CREATE OR REPLACE FUNCTION public.tag_user(p_user_id uuid, p_tag text)
RETURNS text[]
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public, pg_temp
AS $$
DECLARE
  v_tags text[];
BEGIN
  PERFORM private.assert_trusted_backend();

  UPDATE public.users
  SET tags = ARRAY(
        SELECT DISTINCT unnest(COALESCE(tags, '{}') || ARRAY[p_tag])
      ),
      updated_at = now()
  WHERE id = p_user_id
  RETURNING tags INTO v_tags;

  RETURN v_tags;
END;
$$;

CREATE OR REPLACE FUNCTION public.untag_user(p_user_id uuid, p_tag text)
RETURNS text[]
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public, pg_temp
AS $$
DECLARE
  v_tags text[];
BEGIN
  PERFORM private.assert_trusted_backend();

  UPDATE public.users
  SET tags = array_remove(COALESCE(tags, '{}'), p_tag),
      updated_at = now()
  WHERE id = p_user_id
  RETURNING tags INTO v_tags;

  RETURN v_tags;
END;
$$;

CREATE OR REPLACE FUNCTION public.cron_toggle_job(
  p_jobname text,
  p_active boolean
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public, cron, pg_temp
AS $$
DECLARE
  v_jobid bigint;
BEGIN
  PERFORM private.assert_trusted_backend();

  SELECT jobid INTO v_jobid
  FROM cron.job
  WHERE jobname = p_jobname;

  IF v_jobid IS NULL THEN
    RAISE EXCEPTION 'cron job % not found', p_jobname;
  END IF;

  PERFORM cron.alter_job(job_id := v_jobid, active := p_active);

  INSERT INTO public.audit_log (
    actor_id, actor_email, action, entity, entity_id, after
  ) VALUES (
    auth.uid(),
    COALESCE(auth.jwt() ->> 'email', 'system'),
    CASE WHEN p_active THEN 'cron.enable' ELSE 'cron.disable' END,
    'cron.job',
    v_jobid::text,
    jsonb_build_object('jobname', p_jobname, 'active', p_active)
  );
END;
$$;

CREATE OR REPLACE FUNCTION public.cron_update_schedule(
  p_jobname text,
  p_schedule text
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public, cron, pg_temp
AS $$
DECLARE
  v_jobid bigint;
  v_old text;
BEGIN
  PERFORM private.assert_trusted_backend();

  SELECT jobid, schedule INTO v_jobid, v_old
  FROM cron.job
  WHERE jobname = p_jobname;

  IF v_jobid IS NULL THEN
    RAISE EXCEPTION 'cron job % not found', p_jobname;
  END IF;

  IF array_length(string_to_array(trim(p_schedule), ' '), 1) NOT IN (5, 6) THEN
    RAISE EXCEPTION 'invalid cron expression: expected 5 or 6 fields';
  END IF;

  PERFORM cron.alter_job(job_id := v_jobid, schedule := p_schedule);

  INSERT INTO public.audit_log (
    actor_id, actor_email, action, entity, entity_id, before, after
  ) VALUES (
    auth.uid(),
    COALESCE(auth.jwt() ->> 'email', 'system'),
    'cron.update_schedule',
    'cron.job',
    v_jobid::text,
    jsonb_build_object('schedule', v_old),
    jsonb_build_object('schedule', p_schedule, 'jobname', p_jobname)
  );
END;
$$;

CREATE OR REPLACE FUNCTION public.cron_run_now(p_jobname text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public, cron, pg_temp
AS $$
DECLARE
  v_command text;
  v_jobid bigint;
BEGIN
  PERFORM private.assert_trusted_backend();

  SELECT jobid, command INTO v_jobid, v_command
  FROM cron.job
  WHERE jobname = p_jobname;

  IF v_jobid IS NULL THEN
    RAISE EXCEPTION 'cron job % not found', p_jobname;
  END IF;

  EXECUTE v_command;

  INSERT INTO public.audit_log (
    actor_id, actor_email, action, entity, entity_id, after
  ) VALUES (
    auth.uid(),
    COALESCE(auth.jwt() ->> 'email', 'system'),
    'cron.run_now',
    'cron.job',
    v_jobid::text,
    jsonb_build_object('jobname', p_jobname, 'fired_at', now())
  );

  RETURN jsonb_build_object('ok', true, 'jobname', p_jobname, 'fired_at', now());
END;
$$;

CREATE OR REPLACE FUNCTION public.attention_snooze(
  p_user_id uuid,
  p_kind text,
  p_hours integer DEFAULT 24
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public, pg_temp
AS $$
BEGIN
  PERFORM private.assert_trusted_backend();

  INSERT INTO public.attention_dismissals (
    user_id, kind, dismissed_until, dismissed_by, dismissed_by_email, reason
  ) VALUES (
    p_user_id,
    p_kind,
    now() + make_interval(hours => greatest(p_hours, 1)),
    auth.uid(),
    COALESCE(auth.jwt() ->> 'email', 'system'),
    'snooze ' || p_hours || 'h'
  )
  ON CONFLICT (user_id, kind) DO UPDATE SET
    dismissed_until = EXCLUDED.dismissed_until,
    dismissed_by = EXCLUDED.dismissed_by,
    dismissed_by_email = EXCLUDED.dismissed_by_email,
    dismissed_at = now(),
    reason = EXCLUDED.reason;

  INSERT INTO public.audit_log (
    actor_id, actor_email, action, entity, entity_id, after
  ) VALUES (
    auth.uid(),
    COALESCE(auth.jwt() ->> 'email', 'system'),
    'attention.snooze',
    'attention',
    p_user_id::text || ':' || p_kind,
    jsonb_build_object('user_id', p_user_id, 'kind', p_kind, 'hours', p_hours)
  );
END;
$$;

CREATE OR REPLACE FUNCTION public.attention_dismiss(
  p_user_id uuid,
  p_kind text,
  p_reason text DEFAULT NULL
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public, pg_temp
AS $$
BEGIN
  PERFORM private.assert_trusted_backend();

  INSERT INTO public.attention_dismissals (
    user_id, kind, dismissed_until, dismissed_by, dismissed_by_email, reason
  ) VALUES (
    p_user_id,
    p_kind,
    NULL,
    auth.uid(),
    COALESCE(auth.jwt() ->> 'email', 'system'),
    COALESCE(p_reason, 'resolved')
  )
  ON CONFLICT (user_id, kind) DO UPDATE SET
    dismissed_until = NULL,
    dismissed_by = EXCLUDED.dismissed_by,
    dismissed_by_email = EXCLUDED.dismissed_by_email,
    dismissed_at = now(),
    reason = EXCLUDED.reason;

  INSERT INTO public.audit_log (
    actor_id, actor_email, action, entity, entity_id, after
  ) VALUES (
    auth.uid(),
    COALESCE(auth.jwt() ->> 'email', 'system'),
    'attention.dismiss',
    'attention',
    p_user_id::text || ':' || p_kind,
    jsonb_build_object('user_id', p_user_id, 'kind', p_kind, 'reason', p_reason)
  );
END;
$$;

CREATE OR REPLACE FUNCTION public.attention_restore(
  p_user_id uuid,
  p_kind text
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public, pg_temp
AS $$
BEGIN
  PERFORM private.assert_trusted_backend();

  DELETE FROM public.attention_dismissals
  WHERE user_id = p_user_id
    AND kind = p_kind;

  INSERT INTO public.audit_log (
    actor_id, actor_email, action, entity, entity_id, after
  ) VALUES (
    auth.uid(),
    COALESCE(auth.jwt() ->> 'email', 'system'),
    'attention.restore',
    'attention',
    p_user_id::text || ':' || p_kind,
    jsonb_build_object('user_id', p_user_id, 'kind', p_kind)
  );
END;
$$;

REVOKE ALL ON FUNCTION public.dispatch_inngest_event(text, jsonb, integer)
  FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.refresh_mv_kpis_daily()
  FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.pause_user(uuid, integer)
  FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.resume_user(uuid)
  FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.set_global_config(text, jsonb)
  FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.tag_user(uuid, text)
  FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.untag_user(uuid, text)
  FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.cron_toggle_job(text, boolean)
  FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.cron_update_schedule(text, text)
  FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.cron_run_now(text)
  FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.attention_snooze(uuid, text, integer)
  FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.attention_dismiss(uuid, text, text)
  FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.attention_restore(uuid, text)
  FROM PUBLIC, anon, authenticated;

GRANT EXECUTE ON FUNCTION public.dispatch_inngest_event(text, jsonb, integer)
  TO service_role;
GRANT EXECUTE ON FUNCTION public.refresh_mv_kpis_daily()
  TO service_role;
GRANT EXECUTE ON FUNCTION public.pause_user(uuid, integer)
  TO service_role;
GRANT EXECUTE ON FUNCTION public.resume_user(uuid)
  TO service_role;
GRANT EXECUTE ON FUNCTION public.set_global_config(text, jsonb)
  TO service_role;
GRANT EXECUTE ON FUNCTION public.tag_user(uuid, text)
  TO service_role;
GRANT EXECUTE ON FUNCTION public.untag_user(uuid, text)
  TO service_role;
GRANT EXECUTE ON FUNCTION public.cron_toggle_job(text, boolean)
  TO service_role;
GRANT EXECUTE ON FUNCTION public.cron_update_schedule(text, text)
  TO service_role;
GRANT EXECUTE ON FUNCTION public.cron_run_now(text)
  TO service_role;
GRANT EXECUTE ON FUNCTION public.attention_snooze(uuid, text, integer)
  TO service_role;
GRANT EXECUTE ON FUNCTION public.attention_dismiss(uuid, text, text)
  TO service_role;
GRANT EXECUTE ON FUNCTION public.attention_restore(uuid, text)
  TO service_role;

-- Existing backend-only SECURITY DEFINER functions already have correct ACLs;
-- make their search paths explicit and deterministic as part of the same gate.
ALTER FUNCTION public.claim_subscription_event(text, text, jsonb, timestamptz)
  SET search_path = pg_catalog, public, pg_temp;
ALTER FUNCTION public.finish_subscription_event(text, boolean, jsonb, text, timestamptz)
  SET search_path = pg_catalog, public, pg_temp;
ALTER FUNCTION public.reset_user_conversation_atomic(uuid)
  SET search_path = pg_catalog, public, pg_temp;
