-- ============================================================================
-- vw_meal_state — view canônica do MealState (audit 06-26 Layer 2.2)
-- ============================================================================
-- Derivada de pending_registrations + meal_logs. Read-only, sem migration
-- destrutiva. Helper TypeScript em packages/agent/src/meal-state/derive.ts
-- continua sendo fonte canônica pra runtime; esta view existe pra dashboards/
-- audit cron / análise SQL ad-hoc.
--
-- Mapeamento (Opção 3 do plan: wrapper lógico, ZERO DDL destrutiva):
--   PROPOSED:    pending.status='pending'
--   CONFIRMED:   pending.status='confirmed' + meal_log existe
--   REGISTERED:  meal_log sem pending (express path)
--   CANCELLED:   pending.status='cancelled'
--   EDITED:      pending.status='edited'
--   EXPIRED:     pending.status='expired'
--   SKIPPED:     meal_log com kcal=0 + food_name LIKE 'pulou_%'
--   UNKNOWN:     fallback se algum estado fugir (sinal de drift)
-- ============================================================================

-- Index pra JOIN performar (filter via WHERE em status pra reduzir candidatos).
CREATE INDEX IF NOT EXISTS idx_pending_source_pmid
  ON pending_registrations ((proposal->>'source_provider_message_id'))
  WHERE status IN ('confirmed', 'pending');

-- Review HIGH 2 (audit 06-26): distingue CANCELLED limpo de
-- CANCELLED_WITH_ORPHANS (caso pizza-race: pending cancelled MAS meal_logs
-- gravados pelo express path ficaram órfãos). Dashboards podem somar
-- kcal_orphaned pra rastrear perda silenciosa que motivou Layer 3 recovery.
CREATE OR REPLACE VIEW vw_meal_state AS
SELECT
  COALESCE(p.user_id, m.user_id) AS user_id,
  p.id                            AS pending_id,
  m.id                            AS meal_log_id,
  m.consumed_at,
  m.meal_type,
  CASE
    WHEN m.id IS NOT NULL AND m.kcal = 0 AND m.food_name LIKE 'pulou_%' THEN 'SKIPPED'
    WHEN p.status = 'pending'                                            THEN 'PROPOSED'
    WHEN p.status = 'expired'                                            THEN 'EXPIRED'
    WHEN p.status = 'cancelled' AND m.id IS NOT NULL                     THEN 'CANCELLED_WITH_ORPHANS'
    WHEN p.status = 'cancelled'                                          THEN 'CANCELLED'
    WHEN p.status = 'edited'                                             THEN 'EDITED'
    WHEN p.status = 'confirmed' AND m.id IS NOT NULL                     THEN 'CONFIRMED'
    WHEN p.status = 'confirmed' AND m.id IS NULL                         THEN 'PROPOSED'  -- drift
    WHEN p.id IS NULL AND m.id IS NOT NULL                               THEN 'REGISTERED'
    ELSE 'UNKNOWN'
  END                              AS state,
  COALESCE(p.resolved_at, m.created_at, p.created_at) AS last_transition_at,
  p.created_at                     AS pending_created_at,
  m.created_at                     AS meal_log_created_at,
  p.proposal->>'source_provider_message_id' AS source_pmid,
  m.raw_provider_message_id         AS meal_log_pmid,
  -- review HIGH 2: kcal de meal_logs órfãos quando pending=cancelled.
  -- Adicionado no fim pra permitir CREATE OR REPLACE sem DROP (Postgres
  -- não permite mudar ordem/nome de colunas existentes em REPLACE VIEW).
  CASE
    WHEN p.status = 'cancelled' AND m.id IS NOT NULL THEN m.kcal
    ELSE 0
  END                              AS kcal_orphaned
FROM meal_logs m
FULL OUTER JOIN pending_registrations p
  ON  p.user_id = m.user_id
  AND p.proposal->>'source_provider_message_id' = m.raw_provider_message_id
WHERE COALESCE(p.user_id, m.user_id) IS NOT NULL;

COMMENT ON VIEW vw_meal_state IS
  $$Estado canônico derivado de meal_logs + pending_registrations (audit 06-26 Layer 2.2). Read-only.
ATENÇÃO fan-out: FULL OUTER JOIN por (user_id, source_provider_message_id). Para um
mesmo pending com N meal_logs (refeição multi-item registrada pelo execute do
registra_refeicao), a view retorna N linhas — uma por meal_log — todas com mesmo
pending_id. Para contagens DISTINCT de eventos de pending use COUNT(DISTINCT pending_id).
Para somar kcal, NÃO agregue por pending_id (vai duplicar). Coluna kcal_orphaned só é
> 0 em CANCELLED_WITH_ORPHANS (caso pizza-race).$$;
