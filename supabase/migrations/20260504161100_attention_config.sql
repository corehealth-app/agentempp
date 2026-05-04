-- ============================================================================
-- Attention Config + Dismissals
-- ============================================================================
-- 1) Expõe thresholds da v_attention_items em global_config (attention.*)
-- 2) Adiciona tabela attention_dismissals pra snooze/resolve manual
-- 3) Rebuild da view v_attention_items lendo config + filtrando dismissals
-- 4) RPCs pra snooze/dismiss (security definer + audit_log)
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1) Seeds em global_config
-- ----------------------------------------------------------------------------
INSERT INTO global_config (key, value, description) VALUES
  ('attention.error_recent_hours', '6'::jsonb,
   'Quantas horas atrás conta como "tool error recent" (prioridade 9 — mais alta).'),
  ('attention.silent_user_min_days', '3'::jsonb,
   'Quantos dias sem msg IN pra paciente virar "silent_user" (prioridade 5).'),
  ('attention.silent_user_max_days', '14'::jsonb,
   'Cap superior — quem está silencioso há mais que isso é considerado churned (não aparece).'),
  ('attention.onboarding_stuck_hours', '24'::jsonb,
   'Horas de inatividade pra paciente em onboarding virar "stuck" (prioridade 7).'),
  ('attention.onboarding_stuck_max_days', '14'::jsonb,
   'Só mostra onboarding stuck pra pacientes cadastrados nos últimos N dias.'),
  ('attention.block_milestone_hours', '24'::jsonb,
   'Janela em horas pra mostrar quem fechou bloco 7700 — pra parabenizar (prioridade 3).'),
  ('attention.payment_failed_days', '7'::jsonb,
   'Dias pra mostrar subscriptions canceladas/past_due/expired (prioridade 8).')
ON CONFLICT (key) DO NOTHING;

-- ----------------------------------------------------------------------------
-- 2) Tabela de dismissals (snooze + resolve)
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS attention_dismissals (
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id       uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  kind          text NOT NULL,
  dismissed_until timestamptz, -- NULL = resolvido permanentemente; timestamp = snooze até essa hora
  dismissed_by  uuid,
  dismissed_by_email text,
  dismissed_at  timestamptz NOT NULL DEFAULT now(),
  reason        text,
  UNIQUE (user_id, kind)
);
CREATE INDEX IF NOT EXISTS idx_attention_dismissals_user_kind ON attention_dismissals(user_id, kind);
CREATE INDEX IF NOT EXISTS idx_attention_dismissals_until ON attention_dismissals(dismissed_until)
  WHERE dismissed_until IS NOT NULL;

COMMENT ON TABLE attention_dismissals IS
  'Itens de v_attention_items que admin marcou como resolvido (dismissed_until=NULL) ou snoozed (until > now).';

-- ----------------------------------------------------------------------------
-- 3) Helper: lê valor numérico de global_config com fallback
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION attention_int(p_key text, p_default int)
RETURNS int
LANGUAGE sql
STABLE
AS $$
  SELECT COALESCE(
    (SELECT (value)::text::int FROM global_config WHERE key = p_key),
    p_default
  );
$$;

-- ----------------------------------------------------------------------------
-- 4) Rebuild v_attention_items
-- ----------------------------------------------------------------------------
DROP VIEW IF EXISTS v_attention_items;

CREATE VIEW v_attention_items AS
WITH config AS (
  SELECT
    attention_int('attention.error_recent_hours', 6) AS error_hours,
    attention_int('attention.silent_user_min_days', 3) AS silent_min,
    attention_int('attention.silent_user_max_days', 14) AS silent_max,
    attention_int('attention.onboarding_stuck_hours', 24) AS onb_hours,
    attention_int('attention.onboarding_stuck_max_days', 14) AS onb_max,
    attention_int('attention.block_milestone_hours', 24) AS block_hours,
    attention_int('attention.payment_failed_days', 7) AS pay_days
),
error_recent AS (
  SELECT DISTINCT ON (ta.user_id)
    'error_recent'::text AS kind,
    9::int AS priority,
    ta.user_id,
    u.name,
    'Tool ' || ta.tool_name || ' falhou: ' ||
      coalesce(left(ta.error, 80), 'erro desconhecido') AS message,
    ta.created_at
  FROM tools_audit ta
  JOIN users u ON u.id = ta.user_id
  CROSS JOIN config c
  WHERE ta.success = false
    AND ta.created_at > now() - make_interval(hours => c.error_hours)
  ORDER BY ta.user_id, ta.created_at DESC
),
silent_user AS (
  SELECT
    'silent_user'::text AS kind,
    5::int AS priority,
    u.id AS user_id,
    u.name,
    'Sem msg há ' ||
      extract(day from (now() - last_in.last_msg))::int || ' dias' AS message,
    last_in.last_msg AS created_at
  FROM users u
  CROSS JOIN config c
  JOIN LATERAL (
    SELECT max(created_at) AS last_msg
    FROM messages WHERE user_id = u.id AND direction = 'in'
  ) last_in ON true
  WHERE u.status = 'active'
    AND last_in.last_msg IS NOT NULL
    AND last_in.last_msg < now() - make_interval(days => c.silent_min)
    AND last_in.last_msg > now() - make_interval(days => c.silent_max)
),
onboarding_stuck AS (
  SELECT
    'onboarding_stuck'::text AS kind,
    7::int AS priority,
    u.id AS user_id,
    u.name,
    'Onboarding incompleto há >' || c.onb_hours || 'h (step ' ||
      coalesce(p.onboarding_step::text, '?') || '/11)' AS message,
    u.updated_at AS created_at
  FROM users u
  JOIN user_profiles p ON p.user_id = u.id
  CROSS JOIN config c
  WHERE p.onboarding_completed = false
    AND p.onboarding_step > 0
    AND u.updated_at < now() - make_interval(hours => c.onb_hours)
    AND u.created_at > now() - make_interval(days => c.onb_max)
),
block_milestone AS (
  SELECT
    'block_milestone'::text AS kind,
    3::int AS priority,
    pr.user_id,
    u.name,
    pr.blocks_completed || ' bloco(s) fechado(s) — momento de parabenizar' AS message,
    pr.updated_at AS created_at
  FROM user_progress pr
  JOIN users u ON u.id = pr.user_id
  CROSS JOIN config c
  WHERE pr.blocks_completed >= 1
    AND pr.updated_at > now() - make_interval(hours => c.block_hours)
),
payment_failed AS (
  SELECT
    'payment_failed'::text AS kind,
    8::int AS priority,
    s.user_id,
    u.name,
    'Assinatura ' || s.status || ' (' || s.plan || ')' AS message,
    s.updated_at AS created_at
  FROM subscriptions s
  JOIN users u ON u.id = s.user_id
  CROSS JOIN config c
  WHERE s.status IN ('past_due', 'canceled', 'expired')
    AND s.updated_at > now() - make_interval(days => c.pay_days)
),
all_items AS (
  SELECT * FROM error_recent
  UNION ALL SELECT * FROM silent_user
  UNION ALL SELECT * FROM onboarding_stuck
  UNION ALL SELECT * FROM block_milestone
  UNION ALL SELECT * FROM payment_failed
)
SELECT a.*
FROM all_items a
LEFT JOIN attention_dismissals d
  ON d.user_id = a.user_id
 AND d.kind = a.kind
 AND (d.dismissed_until IS NULL OR d.dismissed_until > now())
WHERE d.id IS NULL;

GRANT SELECT ON v_attention_items TO authenticated, service_role;

-- ----------------------------------------------------------------------------
-- 5) RPCs: snooze + dismiss + restore
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION attention_snooze(
  p_user_id uuid,
  p_kind    text,
  p_hours   int DEFAULT 24
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  INSERT INTO attention_dismissals (
    user_id, kind, dismissed_until, dismissed_by, dismissed_by_email, reason
  ) VALUES (
    p_user_id, p_kind,
    now() + make_interval(hours => greatest(p_hours, 1)),
    auth.uid(),
    coalesce((auth.jwt() ->> 'email'), 'system'),
    'snooze ' || p_hours || 'h'
  )
  ON CONFLICT (user_id, kind) DO UPDATE SET
    dismissed_until = excluded.dismissed_until,
    dismissed_by = excluded.dismissed_by,
    dismissed_by_email = excluded.dismissed_by_email,
    dismissed_at = now(),
    reason = excluded.reason;

  INSERT INTO public.audit_log (actor_id, actor_email, action, entity, entity_id, after)
  VALUES (
    auth.uid(),
    coalesce((auth.jwt() ->> 'email'), 'system'),
    'attention.snooze',
    'attention',
    p_user_id::text || ':' || p_kind,
    jsonb_build_object('user_id', p_user_id, 'kind', p_kind, 'hours', p_hours)
  );
END;
$$;

CREATE OR REPLACE FUNCTION attention_dismiss(
  p_user_id uuid,
  p_kind    text,
  p_reason  text DEFAULT NULL
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  INSERT INTO attention_dismissals (
    user_id, kind, dismissed_until, dismissed_by, dismissed_by_email, reason
  ) VALUES (
    p_user_id, p_kind, NULL, auth.uid(),
    coalesce((auth.jwt() ->> 'email'), 'system'),
    coalesce(p_reason, 'resolved')
  )
  ON CONFLICT (user_id, kind) DO UPDATE SET
    dismissed_until = NULL,
    dismissed_by = excluded.dismissed_by,
    dismissed_by_email = excluded.dismissed_by_email,
    dismissed_at = now(),
    reason = excluded.reason;

  INSERT INTO public.audit_log (actor_id, actor_email, action, entity, entity_id, after)
  VALUES (
    auth.uid(),
    coalesce((auth.jwt() ->> 'email'), 'system'),
    'attention.dismiss',
    'attention',
    p_user_id::text || ':' || p_kind,
    jsonb_build_object('user_id', p_user_id, 'kind', p_kind, 'reason', p_reason)
  );
END;
$$;

CREATE OR REPLACE FUNCTION attention_restore(
  p_user_id uuid,
  p_kind    text
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  DELETE FROM attention_dismissals
  WHERE user_id = p_user_id AND kind = p_kind;

  INSERT INTO public.audit_log (actor_id, actor_email, action, entity, entity_id, after)
  VALUES (
    auth.uid(),
    coalesce((auth.jwt() ->> 'email'), 'system'),
    'attention.restore',
    'attention',
    p_user_id::text || ':' || p_kind,
    jsonb_build_object('user_id', p_user_id, 'kind', p_kind)
  );
END;
$$;

GRANT EXECUTE ON FUNCTION attention_snooze(uuid, text, int) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION attention_dismiss(uuid, text, text) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION attention_restore(uuid, text) TO authenticated, service_role;

COMMENT ON FUNCTION attention_snooze IS 'Esconde item de atenção por N horas (default 24).';
COMMENT ON FUNCTION attention_dismiss IS 'Marca item como resolvido permanentemente (até nova ocorrência).';
COMMENT ON FUNCTION attention_restore IS 'Reverte snooze/dismiss — item volta a aparecer se ainda atender critérios.';
