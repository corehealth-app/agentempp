-- ============================================================================
-- food_education_phrases: separar metadata (bloco/polaridade) de state-tags
-- ============================================================================
-- Review #4 high finding 2026-06-13: o selector filtra rows por tags do
-- estado (inferTags → recomp/protein_low/etc). Mas o ingest do Roberto
-- colocava {bloco_id, polaridade} em tags jsonb, fazendo o filter
-- eliminar TODAS as 1023 rows silenciosamente. Mover metadata pra
-- colunas dedicadas e deixar tags reservado pra state-filtering.
-- ============================================================================

ALTER TABLE food_education_phrases ADD COLUMN IF NOT EXISTS bloco_id text;
ALTER TABLE food_education_phrases ADD COLUMN IF NOT EXISTS polaridade text;

CREATE INDEX IF NOT EXISTS idx_food_phrases_bloco
  ON food_education_phrases (bloco_id) WHERE active = true;

-- Migration de dados das 1023 linhas do Roberto (Fase A) já em prod:
-- mover tags JSON → colunas, esvazia tags.
UPDATE food_education_phrases SET
  bloco_id = tags->>'bloco_id',
  polaridade = tags->>'polaridade',
  tags = '{}'::jsonb
WHERE curated_by = 'roberto-2026-06-13' AND tags ? 'bloco_id';
