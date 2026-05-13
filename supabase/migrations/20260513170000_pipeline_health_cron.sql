-- ============================================================================
-- Pipeline health cron: detecta sistema "mudo" e faz auto-sync do Inngest.
-- ============================================================================
-- Context (2026-05-13): após deploy manual via `vercel --prod`, Inngest perdeu
-- o registro das functions. Webhook escreveu msgs em `messages` mas pipeline
-- não respondeu. Levou 3h pra eu perceber olhando timestamps no banco.
--
-- Solução: cron a cada 5min dispara evento Inngest `pipeline.health.tick`
-- que verifica se há incoming sem resposta em >10min. Se sim, faz PUT no
-- /api/inngest pra re-registrar functions automaticamente.
-- ============================================================================

SELECT cron.schedule(
  'pipeline-health-tick',
  '*/5 * * * *',
  $$ SELECT dispatch_inngest_event(
    p_event_name := 'pipeline.health.tick',
    p_data := jsonb_build_object('fired_at', now()::text)
  ) $$
);

COMMENT ON FUNCTION dispatch_inngest_event IS
  'Dispara evento Inngest via HTTP. Usado pelos pg_crons. NÃO chamar direto do código TS — use o SDK Inngest.';
