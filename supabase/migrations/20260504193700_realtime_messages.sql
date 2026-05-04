-- ============================================================================
-- Habilita Supabase Realtime pra tabelas que a UI admin escuta
-- ============================================================================
-- Sem isso, .channel('...').on('postgres_changes', { table: 'messages' }, ...)
-- nunca recebe eventos. Listener no /messages page rodava no client mas
-- ficava quieto — UI só atualizava no F5 manual.
--
-- Tabelas habilitadas:
--   - messages (principal: thread + lista lateral atualizam em tempo real)
--   - daily_snapshots (KPIs do dashboard atualizam quando paciente loga)
--   - user_progress (XP/streak/blocks atualizam ao fechar dia)
--   - product_events (engagement.sent/skipped aparecem em audit live)
--   - tools_audit (badge "N tools" no thread reflete tool nova)
-- ============================================================================

-- REPLICA IDENTITY FULL: garante que UPDATE/DELETE incluem old row no payload
-- (necessário pra realtime detectar mudanças de campo)
ALTER TABLE messages REPLICA IDENTITY FULL;
ALTER TABLE daily_snapshots REPLICA IDENTITY FULL;
ALTER TABLE user_progress REPLICA IDENTITY FULL;

-- Adiciona à publication usada pelo Realtime
ALTER PUBLICATION supabase_realtime ADD TABLE messages;
ALTER PUBLICATION supabase_realtime ADD TABLE daily_snapshots;
ALTER PUBLICATION supabase_realtime ADD TABLE user_progress;
ALTER PUBLICATION supabase_realtime ADD TABLE product_events;
ALTER PUBLICATION supabase_realtime ADD TABLE tools_audit;

-- Confirma com NOTICE
DO $$
DECLARE
  v_count int;
BEGIN
  SELECT count(*) INTO v_count
  FROM pg_publication_tables
  WHERE pubname = 'supabase_realtime'
    AND tablename IN ('messages', 'daily_snapshots', 'user_progress', 'product_events', 'tools_audit');
  RAISE NOTICE 'Tabelas em supabase_realtime: % (esperado: 5)', v_count;
END $$;
