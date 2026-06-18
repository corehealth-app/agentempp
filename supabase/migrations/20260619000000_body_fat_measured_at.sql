-- ============================================================================
-- body_fat_measured_at: timestamp dedicado pra detectar BF stale
-- ============================================================================
-- Audit 06-18 (review HIGH): tool define_meta_peso usava proxy `updated_at`
-- pra warning de BF stale (>30d). Mas updated_at muda por QUALQUER UPDATE
-- (peso novo, altura corrigida, goal_type mudou) — paciente que mediu BF há
-- 6 meses mas atualizou peso anteontem passa pelo guard. Coluna dedicada
-- resolve: SÓ atualiza quando body_fat_percent foi explicitamente medido.
--
-- ADD COLUMN nullable (sem default) — existing rows ficam NULL representando
-- "desconhecido / nunca medido explicitamente". Tools tratam NULL como stale.
--
-- Backfill: NÃO popular retroativamente. Existing body_fat_percent foi
-- gravado em datas variadas — não dá pra inferir quando. Tratar como stale
-- até paciente re-medir é o caminho seguro.
-- ============================================================================

ALTER TABLE public.user_profiles
  ADD COLUMN IF NOT EXISTS body_fat_measured_at timestamptz;

COMMENT ON COLUMN public.user_profiles.body_fat_measured_at IS
  'Timestamp da última medição EXPLÍCITA de body_fat_percent. NULL = nunca medido. Tools tratam NULL ou >30d como stale (warning ao definir meta de BF).';
