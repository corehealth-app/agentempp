-- ============================================================================
-- daily_snapshots: add day_status + gap_reminder_sent_at
-- ============================================================================
-- Roberto levantou caso (sessão 2026-05-16): paciente registra café+almoço
-- mas esquece de registrar jantar. Bloco 7700 atual credita falsamente o
-- déficit ("comeu pouco hoje"), quando na verdade ele só esqueceu de logar.
-- Vira gamificação enganosa: quem não registra "ganha" bloco fake.
--
-- Fluxo novo:
--   1. cron `daily-gap-checker` roda 21h-23h local; detecta refeição esperada
--      faltando (baseado em padrão dos últimos 14d, threshold ≥50% dos dias).
--   2. Se gap detectado E reminder_sent_at IS NULL: envia 1 lembrete
--      ("comeu jantar? se sim, manda. se não, responde 'pulei'") e seta
--      day_status='pending_close' + gap_reminder_sent_at=now().
--   3. cron `daily-gap-recheck` (a cada 30min) processa pending_close mais
--      antigos que 2h sem resposta → seta day_status='incomplete_no_response'.
--   4. daily-closer respeita day_status: incomplete_no_response NÃO credita
--      bloco 7700.
--   5. Quando paciente diz "pulei" → tool marca_refeicao_pulada → day_status
--      vai pra 'user_skipped' (credita bloco normal, confia no paciente).
--
-- Honra o já-existente:
--   - day_closed boolean continua sendo a flag de "fechei a contabilidade"
--   - day_status é ortogonal: descreve a QUALIDADE/ESTADO da informação
--   - Fix #6 daily-closer (hasActivity) cobre dia totalmente vazio; este
--     novo mecanismo cobre dia PARCIALMENTE registrado.
-- ============================================================================

ALTER TABLE daily_snapshots
  ADD COLUMN day_status text NOT NULL DEFAULT 'complete'
    CHECK (day_status IN ('complete', 'user_skipped', 'incomplete_no_response', 'pending_close'));

ALTER TABLE daily_snapshots
  ADD COLUMN gap_reminder_sent_at timestamp with time zone;

-- Índice pra cron de re-check: encontra rapidamente os pending_close vencidos.
CREATE INDEX idx_daily_snapshots_pending_close
  ON daily_snapshots (gap_reminder_sent_at)
  WHERE day_status = 'pending_close';
