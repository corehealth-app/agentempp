-- ============================================================================
-- engagement_phrases — 200 frases motivacionais curadas (Roberto 2026-06-13)
-- ============================================================================
-- Tabela paralela a food_education_phrases. Frases NÃO dependem de alimento
-- (são motivacionais puras). Selecionadas pelo engagement-sender (cron
-- matinal) como frase de continuidade no "Bom dia", e por outros pontos
-- determinísticos onde uma frase de reforço positivo cabe.
--
-- Slots:
--   - any            (default): qualquer momento, frase genérica
--   - morning        : "Bom dia", início do dia
--   - evening        : noite, encerramento
--   - workout        : treino feito, exercício, movimento
--   - continuity     : frase curta de continuidade ("você está no caminho")
-- ============================================================================

CREATE TABLE IF NOT EXISTS engagement_phrases (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  phrase text NOT NULL,
  slot text NOT NULL DEFAULT 'any',
  language text NOT NULL DEFAULT 'pt-BR',
  curated_by text,
  active boolean NOT NULL DEFAULT true,
  usage_count integer NOT NULL DEFAULT 0,
  last_used_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_eng_phrases_slot_lang
  ON engagement_phrases (slot, language) WHERE active = true;

CREATE INDEX IF NOT EXISTS idx_eng_phrases_lru
  ON engagement_phrases (last_used_at NULLS FIRST) WHERE active = true;

COMMENT ON TABLE engagement_phrases IS
  'Frases motivacionais curadas (Roberto 2026-06-13). Selector LRU+sorteio. Usado pelo engagement-sender no "Bom dia" como frase de continuidade.';
