-- ============================================================================
-- BF% estimado das fotos (sub-projeto B, 2026-05-21)
-- ============================================================================
-- A visão estima o % de gordura das fotos corporais, mas hoje o número é
-- descartado. Persistimos a ESTIMATIVA num campo SEPARADO do confirmado
-- (body_fat_percent) — nunca sobrescreve o confirmado. Serve pra tendência e
-- pra decisão de protocolo quando não há BF% confirmado (marcado como estimativa).
-- Aditivo, nullable, idempotente. Aplicado e validado em prod antes do commit.
-- ============================================================================
ALTER TABLE public.user_profiles
  ADD COLUMN IF NOT EXISTS bf_percent_estimated numeric,
  ADD COLUMN IF NOT EXISTS bf_source text,
  ADD COLUMN IF NOT EXISTS bf_estimated_at timestamptz;
