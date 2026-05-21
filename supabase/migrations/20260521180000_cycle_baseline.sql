-- ============================================================================
-- Baseline do ciclo de ganho/manutenção (sub-projeto C — wiring, 2026-05-21)
-- ============================================================================
-- Pra computar velocidade de ganho e tetos de segurança na reavaliação (dia 14),
-- precisamos do estado de INÍCIO do ciclo. Capturado em define_protocolo quando
-- o paciente entra em ganho_massa/manutencao. Aditivo, nullable, idempotente.
-- Aplicado e validado em prod antes do commit.
-- ============================================================================
ALTER TABLE public.user_profiles
  ADD COLUMN IF NOT EXISTS cycle_start_weight_kg numeric,
  ADD COLUMN IF NOT EXISTS cycle_start_bf_percent numeric,
  ADD COLUMN IF NOT EXISTS cycle_start_training_freq integer,
  ADD COLUMN IF NOT EXISTS cycle_start_at timestamptz;
