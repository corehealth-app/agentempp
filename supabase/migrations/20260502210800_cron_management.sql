-- ============================================================================
-- Cron Management RPCs
-- ============================================================================
-- Expõe pg_cron pro painel admin via RPCs seguras (security definer).
-- Permite enable/disable, mudar schedule e disparar execução imediata.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- cron_toggle_job: ativa/desativa um cron job pelo nome
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION cron_toggle_job(
  p_jobname text,
  p_active  boolean
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, cron
AS $$
DECLARE
  v_jobid bigint;
BEGIN
  SELECT jobid INTO v_jobid FROM cron.job WHERE jobname = p_jobname;
  IF v_jobid IS NULL THEN
    RAISE EXCEPTION 'cron job % não encontrado', p_jobname;
  END IF;

  PERFORM cron.alter_job(job_id := v_jobid, active := p_active);

  INSERT INTO public.audit_log (actor_id, actor_email, action, entity, entity_id, after)
  VALUES (
    auth.uid(),
    coalesce((auth.jwt() ->> 'email'), 'system'),
    CASE WHEN p_active THEN 'cron.enable' ELSE 'cron.disable' END,
    'cron.job',
    v_jobid::text,
    jsonb_build_object('jobname', p_jobname, 'active', p_active)
  );
END;
$$;

-- ----------------------------------------------------------------------------
-- cron_update_schedule: muda o cron expression (5-field) de um job
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION cron_update_schedule(
  p_jobname  text,
  p_schedule text
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, cron
AS $$
DECLARE
  v_jobid bigint;
  v_old   text;
BEGIN
  SELECT jobid, schedule INTO v_jobid, v_old FROM cron.job WHERE jobname = p_jobname;
  IF v_jobid IS NULL THEN
    RAISE EXCEPTION 'cron job % não encontrado', p_jobname;
  END IF;

  -- Validação básica: cron tem que ter 5 ou 6 campos separados por espaço
  IF array_length(string_to_array(trim(p_schedule), ' '), 1) NOT IN (5, 6) THEN
    RAISE EXCEPTION 'cron expression inválido: esperado 5 ou 6 campos, recebido %', p_schedule;
  END IF;

  PERFORM cron.alter_job(job_id := v_jobid, schedule := p_schedule);

  INSERT INTO public.audit_log (actor_id, actor_email, action, entity, entity_id, before, after)
  VALUES (
    auth.uid(),
    coalesce((auth.jwt() ->> 'email'), 'system'),
    'cron.update_schedule',
    'cron.job',
    v_jobid::text,
    jsonb_build_object('schedule', v_old),
    jsonb_build_object('schedule', p_schedule, 'jobname', p_jobname)
  );
END;
$$;

-- ----------------------------------------------------------------------------
-- cron_run_now: executa o command de um cron job imediatamente
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION cron_run_now(p_jobname text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, cron
AS $$
DECLARE
  v_command text;
  v_jobid   bigint;
BEGIN
  SELECT jobid, command INTO v_jobid, v_command FROM cron.job WHERE jobname = p_jobname;
  IF v_jobid IS NULL THEN
    RAISE EXCEPTION 'cron job % não encontrado', p_jobname;
  END IF;

  -- Executa o comando exatamente como o pg_cron faria
  EXECUTE v_command;

  INSERT INTO public.audit_log (actor_id, actor_email, action, entity, entity_id, after)
  VALUES (
    auth.uid(),
    coalesce((auth.jwt() ->> 'email'), 'system'),
    'cron.run_now',
    'cron.job',
    v_jobid::text,
    jsonb_build_object('jobname', p_jobname, 'fired_at', now())
  );

  RETURN jsonb_build_object('ok', true, 'jobname', p_jobname, 'fired_at', now());
END;
$$;

GRANT EXECUTE ON FUNCTION cron_toggle_job(text, boolean) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION cron_update_schedule(text, text) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION cron_run_now(text) TO authenticated, service_role;

COMMENT ON FUNCTION cron_toggle_job IS
  'Liga/desliga um cron job pelo nome. Audit log automático. SECURITY DEFINER.';
COMMENT ON FUNCTION cron_update_schedule IS
  'Muda o cron expression de um job. Valida formato 5 ou 6 campos. Audit log automático.';
COMMENT ON FUNCTION cron_run_now IS
  'Executa imediatamente o command de um cron job. Útil pra testes manuais. Audit log automático.';
