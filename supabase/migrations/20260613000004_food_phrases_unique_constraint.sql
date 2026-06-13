-- ============================================================================
-- food_education_phrases: UNIQUE constraint anti-duplicação
-- ============================================================================
-- Review pós-Fase D/E 2026-06-13:
-- Workflow audit detectou 78+ entries duplicadas em prod — Fase D copiou
-- 15 frases idênticas da Fase B, Fase E copiou 3. Sem proteção no DB,
-- futuras Fases podem re-introduzir. Script de ingest já dedupa em memória
-- (Set de fingerprints) — mas constraint é a defesa final.
-- ============================================================================

CREATE UNIQUE INDEX IF NOT EXISTS uq_food_phrases_dedup
  ON food_education_phrases (bloco_id, food_canonical_name, md5(phrase), language)
  WHERE active = true;
