-- ============================================================================
-- Migration 0015: Admin KPIs / funil / atenção
-- ============================================================================
-- Views e materialized view que alimentam o dashboard reformulado:
--   - mv_kpis_daily: agregado diário com sparklines/deltas (refresh 1x/h)
--   - v_funnel_activation: funil semanal (msg→onb→1ª refeição→1º bloco→pago)
--   - v_attention_items: top eventos que requerem ação do gestor
--   - v_mrr_summary: MRR ativo + churn 30d
-- ============================================================================

-- ----------------------------------------------------------------------------
-- mv_kpis_daily
-- ----------------------------------------------------------------------------
DROP MATERIALIZED VIEW IF EXISTS mv_kpis_daily CASCADE;

CREATE MATERIALIZED VIEW mv_kpis_daily AS
WITH days AS (
  SELECT generate_series(
    (CURRENT_DATE - INTERVAL '30 days')::date,
    CURRENT_DATE::date,
    '1 day'::interval
  )::date AS day
),
msgs AS (
  SELECT
    date_trunc('day', created_at)::date AS day,
    direction,
    user_id,
    cost_usd,
    latency_ms,
    model_used
  FROM messages
  WHERE created_at >= CURRENT_DATE - INTERVAL '31 days'
),
new_users AS (
  SELECT date_trunc('day', created_at)::date AS day, count(*) AS n
  FROM users
  WHERE created_at >= CURRENT_DATE - INTERVAL '31 days'
  GROUP BY 1
),
audit AS (
  SELECT
    date_trunc('day', created_at)::date AS day,
    count(*) AS tools_total,
    count(*) FILTER (WHERE success = true) AS tools_ok,
    count(*) FILTER (WHERE success = false) AS tools_err
  FROM tools_audit
  WHERE created_at >= CURRENT_DATE - INTERVAL '31 days'
  GROUP BY 1
)
SELECT
  d.day,
  COALESCE(count(DISTINCT m.user_id) FILTER (WHERE m.direction = 'in'), 0) AS dau,
  COALESCE(count(*) FILTER (WHERE m.direction = 'in'), 0) AS messages_in,
  COALESCE(count(*) FILTER (WHERE m.direction = 'out'), 0) AS messages_out,
  COALESCE(sum(m.cost_usd), 0)::numeric(10,4) AS cost_usd,
  COALESCE(percentile_cont(0.50) WITHIN GROUP (ORDER BY m.latency_ms), 0)::int AS p50_latency_ms,
  COALESCE(percentile_cont(0.95) WITHIN GROUP (ORDER BY m.latency_ms), 0)::int AS p95_latency_ms,
  COALESCE(nu.n, 0) AS new_users,
  COALESCE(a.tools_total, 0) AS tools_called,
  COALESCE(a.tools_ok, 0) AS tools_ok,
  COALESCE(a.tools_err, 0) AS tools_err,
  CASE WHEN COALESCE(a.tools_total, 0) = 0 THEN NULL
       ELSE (a.tools_ok::numeric / a.tools_total)::numeric(4,3)
  END AS tool_success_rate
FROM days d
LEFT JOIN msgs m ON m.day = d.day
LEFT JOIN new_users nu ON nu.day = d.day
LEFT JOIN audit a ON a.day = d.day
GROUP BY d.day, nu.n, a.tools_total, a.tools_ok, a.tools_err
ORDER BY d.day;

CREATE UNIQUE INDEX idx_mv_kpis_daily_day ON mv_kpis_daily(day);

COMMENT ON MATERIALIZED VIEW mv_kpis_daily IS
  'KPIs diários para dashboard. Refresh 1x/h via cron.';

-- ----------------------------------------------------------------------------
-- refresh_mv_kpis_daily(): chamado pelo cron
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION refresh_mv_kpis_daily()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  REFRESH MATERIALIZED VIEW CONCURRENTLY mv_kpis_daily;
END;
$$;

GRANT EXECUTE ON FUNCTION refresh_mv_kpis_daily TO authenticated, service_role;

-- Cron 1x/h
SELECT cron.unschedule('refresh-mv-kpis-daily')
  WHERE EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'refresh-mv-kpis-daily');

SELECT cron.schedule(
  'refresh-mv-kpis-daily',
  '5 * * * *',
  $$ SELECT refresh_mv_kpis_daily(); $$
);

-- ----------------------------------------------------------------------------
-- v_funnel_activation: funil semanal por cohort
-- ----------------------------------------------------------------------------
-- Steps:
--   1. cadastrou (created_at)
--   2. mandou ao menos 1 msg
--   3. completou onboarding (onboarding_completed=true)
--   4. registrou ao menos 1 refeição
--   5. fechou ao menos 1 bloco (blocks_completed >= 1)
--   6. tem subscription active|trial
CREATE OR REPLACE VIEW v_funnel_activation AS
WITH cohorts AS (
  SELECT
    date_trunc('week', u.created_at)::date AS cohort_week,
    u.id AS user_id,
    u.created_at
  FROM users u
  WHERE u.created_at >= CURRENT_DATE - INTERVAL '8 weeks'
),
steps AS (
  SELECT
    c.cohort_week,
    c.user_id,
    EXISTS (SELECT 1 FROM messages m WHERE m.user_id = c.user_id AND m.direction = 'in') AS messaged,
    COALESCE((SELECT onboarding_completed FROM user_profiles WHERE user_id = c.user_id), false) AS onboarded,
    EXISTS (SELECT 1 FROM meal_logs ml WHERE ml.user_id = c.user_id) AS logged_meal,
    COALESCE((SELECT blocks_completed FROM user_progress WHERE user_id = c.user_id), 0) >= 1 AS closed_block,
    EXISTS (
      SELECT 1 FROM subscriptions s
      WHERE s.user_id = c.user_id AND s.status IN ('active', 'trial')
    ) AS paying
  FROM cohorts c
)
SELECT
  cohort_week,
  count(*) AS cohort_size,
  count(*) FILTER (WHERE messaged) AS s1_messaged,
  count(*) FILTER (WHERE onboarded) AS s2_onboarded,
  count(*) FILTER (WHERE logged_meal) AS s3_logged_meal,
  count(*) FILTER (WHERE closed_block) AS s4_closed_block,
  count(*) FILTER (WHERE paying) AS s5_paying
FROM steps
GROUP BY cohort_week
ORDER BY cohort_week DESC;

COMMENT ON VIEW v_funnel_activation IS
  'Funil de ativação semanal. Cada coluna sN é cumulativo (passou pelo step N).';

-- ----------------------------------------------------------------------------
-- v_attention_items: top eventos que pedem ação do gestor
-- ----------------------------------------------------------------------------
-- Categorias:
--   error_recent: tool falhou nas últimas 6h
--   silent_user: ativo mas sem msg in há >3 dias
--   onboarding_stuck: começou onb, parou >24h sem completar
--   block_milestone: completou bloco nas últimas 24h (pra parabenizar manualmente)
--   payment_failed: subscription com status incompatível
CREATE OR REPLACE VIEW v_attention_items AS
WITH error_recent AS (
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
  WHERE ta.success = false AND ta.created_at > now() - interval '6 hours'
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
  JOIN LATERAL (
    SELECT max(created_at) AS last_msg
    FROM messages WHERE user_id = u.id AND direction = 'in'
  ) last_in ON true
  WHERE u.status = 'active'
    AND last_in.last_msg IS NOT NULL
    AND last_in.last_msg < now() - interval '3 days'
    AND last_in.last_msg > now() - interval '14 days'
),
onboarding_stuck AS (
  SELECT
    'onboarding_stuck'::text AS kind,
    7::int AS priority,
    u.id AS user_id,
    u.name,
    'Onboarding incompleto há >24h (step ' ||
      coalesce(p.onboarding_step::text, '?') || '/11)' AS message,
    u.updated_at AS created_at
  FROM users u
  JOIN user_profiles p ON p.user_id = u.id
  WHERE p.onboarding_completed = false
    AND p.onboarding_step > 0
    AND u.updated_at < now() - interval '24 hours'
    AND u.created_at > now() - interval '14 days'
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
  WHERE pr.blocks_completed >= 1
    AND pr.updated_at > now() - interval '24 hours'
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
  WHERE s.status IN ('past_due', 'canceled', 'expired')
    AND s.updated_at > now() - interval '7 days'
)
SELECT * FROM error_recent
UNION ALL SELECT * FROM silent_user
UNION ALL SELECT * FROM onboarding_stuck
UNION ALL SELECT * FROM block_milestone
UNION ALL SELECT * FROM payment_failed;

COMMENT ON VIEW v_attention_items IS
  'Itens que pedem ação do gestor, ordenáveis por priority desc. Limita-se nos últimos dias.';

-- ----------------------------------------------------------------------------
-- v_mrr_summary: MRR ativo, novos, churn 30d
-- ----------------------------------------------------------------------------
CREATE OR REPLACE VIEW v_mrr_summary AS
WITH active_subs AS (
  SELECT
    s.id,
    s.user_id,
    s.plan,
    s.status,
    s.created_at,
    -- Preço aproximado por plano em centavos BRL (override via subscription_events.amount_cents)
    COALESCE(
      (SELECT amount_cents FROM subscription_events
       WHERE subscription_id = s.id ORDER BY created_at DESC LIMIT 1),
      CASE s.plan
        WHEN 'mensal' THEN 19700
        WHEN 'anual' THEN 9700
        WHEN 'trial' THEN 0
        ELSE 0
      END
    ) AS amount_cents
  FROM subscriptions s
  WHERE s.status IN ('active', 'trial')
),
churned_30d AS (
  SELECT count(*) AS n
  FROM subscriptions
  WHERE status = 'canceled'
    AND updated_at > now() - interval '30 days'
)
SELECT
  count(*) AS active_subs,
  (sum(amount_cents) / 100.0)::numeric(10,2) AS mrr_brl,
  count(*) FILTER (WHERE created_at > now() - interval '30 days') AS new_30d,
  (SELECT n FROM churned_30d) AS churned_30d,
  CASE
    WHEN count(*) = 0 THEN 0
    ELSE ((SELECT n FROM churned_30d)::numeric / NULLIF(count(*) + (SELECT n FROM churned_30d), 0))::numeric(4,3)
  END AS churn_rate_30d
FROM active_subs;

COMMENT ON VIEW v_mrr_summary IS
  'Snapshot de receita: MRR, novas assinaturas 30d, churn 30d.';

-- Refresh inicial
SELECT refresh_mv_kpis_daily();
