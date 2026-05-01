-- ============================================================================
-- Migration 0008: Cache & reference data
-- ============================================================================

-- ----------------------------------------------------------------------------
-- tts_cache (frases recorrentes com hash → audio gerado uma vez)
-- ----------------------------------------------------------------------------
CREATE TABLE tts_cache (
  text_hash      text PRIMARY KEY,
  voice_id       text NOT NULL,
  provider       text NOT NULL,
  text_preview   text,
  audio_path     text NOT NULL,
  hits           integer NOT NULL DEFAULT 0,
  created_at     timestamptz NOT NULL DEFAULT now(),
  last_used_at   timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX idx_tts_last_used ON tts_cache(last_used_at);

COMMENT ON COLUMN tts_cache.text_hash IS 'sha256(text + voice_id + provider).';
COMMENT ON COLUMN tts_cache.provider IS 'elevenlabs | cartesia';

-- ----------------------------------------------------------------------------
-- food_db (TACO + complementos — ADR-006)
-- ----------------------------------------------------------------------------
-- unaccent não é IMMUTABLE por padrão, precisa de um wrapper para usar em
-- generated columns / index predicates.
CREATE OR REPLACE FUNCTION f_unaccent(text)
RETURNS text
LANGUAGE sql
IMMUTABLE
PARALLEL SAFE
STRICT
AS $$
  SELECT public.unaccent('public.unaccent', $1)
$$;

CREATE TABLE food_db (
  id              serial PRIMARY KEY,
  name_pt         text NOT NULL,
  name_norm       text GENERATED ALWAYS AS (lower(f_unaccent(name_pt))) STORED,
  category        text,
  kcal_per_100g   numeric(6,2),
  protein_g       numeric(5,2),
  carbs_g         numeric(5,2),
  fat_g           numeric(5,2),
  fiber_g         numeric(5,2),
  source          text NOT NULL DEFAULT 'TACO',
  embedding       vector(1024)
);

CREATE INDEX idx_food_norm_trgm ON food_db USING gin(name_norm gin_trgm_ops);
CREATE INDEX idx_food_emb_hnsw ON food_db USING hnsw (embedding vector_cosine_ops);
CREATE INDEX idx_food_category ON food_db(category) WHERE category IS NOT NULL;

COMMENT ON TABLE food_db IS 'Base nutricional. TACO (UNICAMP) + complementos. Fuzzy + semantic search.';
