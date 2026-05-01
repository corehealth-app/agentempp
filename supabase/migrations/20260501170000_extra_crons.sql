-- ============================================================================
-- Migration 0013: Crons restantes (engagement + buffer-flush + wa-monitor)
-- ============================================================================
-- Adiciona os crons que faltavam para completar a operação:
--   * 5 engagement-* (manhã, almoço, tarde, jantar, noite)
--   * buffer-flush (a cada minuto, processa mensagens debounced)
--   * wa-quality-monitor (a cada 30min, verifica quality rating WhatsApp)
--
-- Os jobs apenas registram que rodaram; o trabalho real é feito por workers
-- (Inngest functions) ou Edge Functions agendados via NOTIFY/eventos.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- Engagement: 5 disparos durante o dia (segmenta usuários por timezone)
-- ----------------------------------------------------------------------------
SELECT cron.schedule(
  'engagement-morning',
  '7 7 * * *',
  $$
    INSERT INTO public.product_events (event, properties)
    VALUES ('cron.engagement.tick', jsonb_build_object('slot', 'morning', 'fired_at', now()))
  $$
);

SELECT cron.schedule(
  'engagement-late-morning',
  '16 11 * * *',
  $$
    INSERT INTO public.product_events (event, properties)
    VALUES ('cron.engagement.tick', jsonb_build_object('slot', 'late_morning', 'fired_at', now()))
  $$
);

SELECT cron.schedule(
  'engagement-afternoon',
  '9 14 * * *',
  $$
    INSERT INTO public.product_events (event, properties)
    VALUES ('cron.engagement.tick', jsonb_build_object('slot', 'afternoon', 'fired_at', now()))
  $$
);

SELECT cron.schedule(
  'engagement-evening',
  '30 18 * * *',
  $$
    INSERT INTO public.product_events (event, properties)
    VALUES ('cron.engagement.tick', jsonb_build_object('slot', 'evening', 'fired_at', now()))
  $$
);

SELECT cron.schedule(
  'engagement-night',
  '27 21 * * *',
  $$
    INSERT INTO public.product_events (event, properties)
    VALUES ('cron.engagement.tick', jsonb_build_object('slot', 'night', 'fired_at', now()))
  $$
);

-- ----------------------------------------------------------------------------
-- Buffer flush: a cada minuto checa se há mensagens debounced para processar
-- ----------------------------------------------------------------------------
SELECT cron.schedule(
  'buffer-flush',
  '* * * * *',
  $$
    -- Marca mensagens vencidas como prontas para processar.
    -- A Edge Function/worker consome via polling ou pg_notify.
    SELECT pg_notify(
      'mpp_buffer_flush',
      jsonb_build_object('count', count(*), 'fired_at', now())::text
    )
    FROM public.message_buffer
    WHERE flush_after < now()
  $$
);

-- ----------------------------------------------------------------------------
-- WhatsApp quality monitor: a cada 30min checa quality_rating
-- ----------------------------------------------------------------------------
SELECT cron.schedule(
  'wa-quality-check',
  '*/30 * * * *',
  $$
    INSERT INTO public.product_events (event, properties)
    VALUES ('cron.wa.quality.tick', jsonb_build_object('fired_at', now()))
  $$
);

COMMENT ON EXTENSION pg_cron IS
  'Crons da plataforma Agente MPP. Cada job emite evento que workers consomem.';
