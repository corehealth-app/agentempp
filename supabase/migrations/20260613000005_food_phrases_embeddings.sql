-- ============================================================================
-- food_education_phrases: semantic matching via vector embeddings
-- ============================================================================
-- Audit empírico pós-fechamento (commit b4bae97): selector tinha 0 hits
-- em prod. Causa: meal_logs registra food_names compostos ("aveia em
-- flocos", "iogurte zero açúcar", "mamão picado") mas Roberto entregou
-- nomes-base ("aveia", "iogurte natural", "mamão"). .eq() exato +
-- plurais não cobre composição.
--
-- Solução estrutural: cascade selector
--   1) .eq() exato (fast path — 0 custo)
--   2) similarity search via pgvector com embeddings text-embedding-3-large
--      truncated a 1024 dims (cosine threshold 0.65)
--
-- Vantagens long-term:
-- - Zero acoplamento ao formato dos food_names em prod
-- - Polaridade preservada via semântica (embedding distingue "desnatado"
--   de "condensado")
-- - Self-healing: foods novos viram match automático
-- - Custo desprezível ($0.001/mês runtime, $0.0003 backfill)
-- ============================================================================

ALTER TABLE food_education_phrases
  ADD COLUMN IF NOT EXISTS food_name_embedding vector(1024);

-- IVFFlat com 50 lists pra ~2k canonical names únicos
-- (heurística: lists = sqrt(N), arredondado pra cima)
CREATE INDEX IF NOT EXISTS idx_food_phrases_embedding
  ON food_education_phrases
  USING ivfflat (food_name_embedding vector_cosine_ops)
  WITH (lists = 50);

COMMENT ON COLUMN food_education_phrases.food_name_embedding IS
  'Embedding de food_canonical_name (text-embedding-3-large 1024d). Usado pelo selector cascade: se .eq() não bate, similarity search com threshold cosine 0.65. Backfill via scripts/backfill-food-phrase-embeddings.ts.';
