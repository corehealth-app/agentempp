-- ============================================================================
-- Migration 0014: Bridge pg_cron ↔ Inngest via pg_net
-- ============================================================================
-- Os crons anteriores apenas inseriam linhas em product_events e ninguém
-- consumia. Agora cada cron dispara um evento Inngest direto via HTTP.
-- ============================================================================

CREATE EXTENSION IF NOT EXISTS pg_net;

-- ----------------------------------------------------------------------------
-- dispatch_inngest_event: envia evento ao Inngest Cloud via HTTP
-- ----------------------------------------------------------------------------
-- Lê INNGEST_EVENT_KEY de service_credentials (service='inngest', key='event_key')
-- e POSTa para https://inn.gs/e/{KEY} com {name, data, [ts]}.
--
-- Não bloqueia: pg_net.http_post é assíncrono (queue interna).
CREATE OR REPLACE FUNCTION dispatch_inngest_event(
  p_event_name text,
  p_data jsonb DEFAULT '{}'::jsonb,
  p_delay_ms integer DEFAULT NULL
)
RETURNS bigint
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_key text;
  v_body jsonb;
  v_request_id bigint;
BEGIN
  SELECT value INTO v_key
  FROM service_credentials
  WHERE service = 'inngest'
    AND key_name = 'event_key'
    AND is_active = true
  LIMIT 1;

  IF v_key IS NULL THEN
    RAISE WARNING 'dispatch_inngest_event: inngest.event_key não configurado';
    RETURN NULL;
  END IF;

  v_body := jsonb_build_object('name', p_event_name, 'data', p_data);
  IF p_delay_ms IS NOT NULL AND p_delay_ms > 0 THEN
    v_body := v_body || jsonb_build_object(
      'ts', (extract(epoch from now()) * 1000)::bigint + p_delay_ms
    );
  END IF;

  SELECT net.http_post(
    url := 'https://inn.gs/e/' || v_key,
    body := v_body,
    headers := jsonb_build_object('Content-Type', 'application/json')
  ) INTO v_request_id;

  RETURN v_request_id;
END;
$$;

COMMENT ON FUNCTION dispatch_inngest_event IS
  'Dispara evento ao Inngest Cloud via pg_net. Usado pelos pg_cron jobs.';

-- ----------------------------------------------------------------------------
-- Substitui crons antigos
-- ----------------------------------------------------------------------------

-- Remove crons que apenas inseriam em product_events (sem consumidor)
SELECT cron.unschedule('engagement-morning')        WHERE EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'engagement-morning');
SELECT cron.unschedule('engagement-late-morning')   WHERE EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'engagement-late-morning');
SELECT cron.unschedule('engagement-afternoon')      WHERE EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'engagement-afternoon');
SELECT cron.unschedule('engagement-evening')        WHERE EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'engagement-evening');
SELECT cron.unschedule('engagement-night')          WHERE EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'engagement-night');
SELECT cron.unschedule('wa-quality-check')          WHERE EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'wa-quality-check');
SELECT cron.unschedule('buffer-flush')              WHERE EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'buffer-flush');

-- Daily closer SQL → substituído pelo dailyCloserFn (Inngest, faz LLM batch)
SELECT cron.unschedule('daily-closer-0030')         WHERE EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'daily-closer-0030');
SELECT cron.unschedule('daily-closer-0130')         WHERE EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'daily-closer-0130');
SELECT cron.unschedule('daily-closer-0230')         WHERE EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'daily-closer-0230');
SELECT cron.unschedule('daily-closer-0330')         WHERE EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'daily-closer-0330');

-- ----------------------------------------------------------------------------
-- Novos crons: disparam Inngest events
-- ----------------------------------------------------------------------------

-- Engagement: 5 disparos durante o dia
SELECT cron.schedule(
  'engagement-morning',
  '7 7 * * *',
  $$ SELECT dispatch_inngest_event(
       'engagement.tick',
       jsonb_build_object('slot', 'morning', 'fired_at', now()::text)
     ) $$
);

SELECT cron.schedule(
  'engagement-late-morning',
  '16 11 * * *',
  $$ SELECT dispatch_inngest_event(
       'engagement.tick',
       jsonb_build_object('slot', 'late_morning', 'fired_at', now()::text)
     ) $$
);

SELECT cron.schedule(
  'engagement-afternoon',
  '9 14 * * *',
  $$ SELECT dispatch_inngest_event(
       'engagement.tick',
       jsonb_build_object('slot', 'afternoon', 'fired_at', now()::text)
     ) $$
);

SELECT cron.schedule(
  'engagement-evening',
  '30 18 * * *',
  $$ SELECT dispatch_inngest_event(
       'engagement.tick',
       jsonb_build_object('slot', 'evening', 'fired_at', now()::text)
     ) $$
);

SELECT cron.schedule(
  'engagement-night',
  '27 21 * * *',
  $$ SELECT dispatch_inngest_event(
       'engagement.tick',
       jsonb_build_object('slot', 'night', 'fired_at', now()::text)
     ) $$
);

-- Daily closer: 4 ticks (cobre fusos BR -2h, -3h, -4h, -5h ≈ ~00h local)
SELECT cron.schedule(
  'daily-closer-0030',
  '30 0 * * *',
  $$ SELECT dispatch_inngest_event(
       'day.close.tick',
       jsonb_build_object('hour', 0, 'fired_at', now()::text)
     ) $$
);

SELECT cron.schedule(
  'daily-closer-0130',
  '30 1 * * *',
  $$ SELECT dispatch_inngest_event(
       'day.close.tick',
       jsonb_build_object('hour', 1, 'fired_at', now()::text)
     ) $$
);

SELECT cron.schedule(
  'daily-closer-0230',
  '30 2 * * *',
  $$ SELECT dispatch_inngest_event(
       'day.close.tick',
       jsonb_build_object('hour', 2, 'fired_at', now()::text)
     ) $$
);

SELECT cron.schedule(
  'daily-closer-0330',
  '30 3 * * *',
  $$ SELECT dispatch_inngest_event(
       'day.close.tick',
       jsonb_build_object('hour', 3, 'fired_at', now()::text)
     ) $$
);

-- WhatsApp quality monitor: a cada 30min
SELECT cron.schedule(
  'wa-quality-check',
  '*/30 * * * *',
  $$ SELECT dispatch_inngest_event(
       'wa.quality.check',
       jsonb_build_object('fired_at', now()::text)
     ) $$
);

COMMENT ON EXTENSION pg_net IS
  'Permite chamadas HTTP assíncronas a partir do Postgres (usado pelos crons → Inngest).';
