-- ============================================================================
-- pending_approvals: aprovação manual via Telegram
-- ============================================================================
-- Modo A da auditoria automática: TODA mudança que a routine quer fazer fica
-- como pending até aprovação humana via botão no Telegram (Margot).
--
-- Fluxo:
--   1. Routine cria row com status='pending'
--   2. Edge function notify-telegram envia msg com botões [Aprovar][Rejeitar]
--   3. User clica → Telegram dispara webhook em telegram-webhook
--   4. UPDATE status pra 'approved' / 'rejected'
--   5. Se approved: aplica o fix (chamando audit-auto-fix internamente)
--   6. editMessageText no Telegram pra mostrar "✅ Aplicado" / "❌ Rejeitado"
-- ============================================================================

CREATE TABLE IF NOT EXISTS pending_approvals (
  id uuid primary key default gen_random_uuid(),
  type text not null check (type in (
    'food_alias',
    'global_config_update',
    'rule_update',
    'structural_bug_report'
  )),
  -- Payload depende do type. food_alias: {food_name, category, kcal_per_100g, ...}
  payload jsonb not null,
  -- Razão pelo qual a routine sugeriu. Ex: "5 users tentaram registrar X em 7d"
  reason text,
  -- Confidence da sugestão pelo LLM auditor.
  confidence text check (confidence in ('high', 'medium', 'low')),
  status text not null default 'pending' check (status in (
    'pending',
    'approved',
    'rejected',
    'applied',
    'failed_to_apply',
    'expired'
  )),
  -- Mensagem do Telegram pra editar quando decidido (mostrar status)
  telegram_message_id bigint,
  telegram_chat_id text,
  -- ID do run da routine (UUID v4)
  run_id text,
  -- Como foi decidido
  decided_via text check (decided_via in ('telegram', 'admin_ui', 'auto_expire')),
  decided_at timestamptz,
  -- Resultado da aplicação (se approved e aplicou)
  application_result jsonb,
  application_error text,
  created_at timestamptz default now()
);

CREATE INDEX IF NOT EXISTS idx_pending_approvals_status_created
  ON pending_approvals (status, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_pending_approvals_type
  ON pending_approvals (type, status);

COMMENT ON TABLE pending_approvals IS
  'Mudanças sugeridas pela auditoria automática aguardando aprovação manual via Telegram. Modo A = aprovação total.';

-- ----------------------------------------------------------------------------
-- Auto-expire: pending > 72h vira 'expired' (cron diário cuida)
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION pending_approvals_expire_old()
RETURNS integer
LANGUAGE sql
AS $$
  UPDATE pending_approvals
     SET status = 'expired',
         decided_via = 'auto_expire',
         decided_at = NOW()
   WHERE status = 'pending'
     AND created_at < NOW() - INTERVAL '72 hours'
   RETURNING 1;
  SELECT count(*)::integer FROM pending_approvals
   WHERE status = 'expired' AND decided_at > NOW() - INTERVAL '5 minutes';
$$;

GRANT EXECUTE ON FUNCTION pending_approvals_expire_old TO service_role;

-- RLS: admin only
ALTER TABLE pending_approvals ENABLE ROW LEVEL SECURITY;

CREATE POLICY "pending_approvals_admin_all"
  ON pending_approvals
  FOR ALL
  TO authenticated
  USING (is_admin())
  WITH CHECK (is_admin());
