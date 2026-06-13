-- ============================================================================
-- user_phrase_cooldown — evita repetir mesma frase pro mesmo paciente em <7d
-- ============================================================================
-- Review pós-Fase B 2026-06-13:
-- Selector ordena por last_used_at GLOBAL — frase pode repetir pro MESMO
-- paciente em refeições consecutivas (ovo hoje, ovo amanhã, mesmo template).
-- Fix: tabela cooldown por (user_id, phrase_id) e filtra candidatos cujo
-- last_seen pro user > 7d atrás.
-- ============================================================================

CREATE TABLE IF NOT EXISTS user_phrase_cooldown (
  user_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  phrase_table text NOT NULL,  -- 'food' | 'engagement'
  phrase_id uuid NOT NULL,
  last_seen_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (user_id, phrase_table, phrase_id)
);

CREATE INDEX IF NOT EXISTS idx_upc_user_recent
  ON user_phrase_cooldown (user_id, last_seen_at DESC);

-- Indexes auxiliares pro selector (food_canonical_name + LRU)
CREATE INDEX IF NOT EXISTS idx_food_phrases_lookup
  ON food_education_phrases (food_canonical_name, language, last_used_at NULLS FIRST)
  WHERE active = true;

CREATE INDEX IF NOT EXISTS idx_eng_phrases_lookup
  ON engagement_phrases (language, slot, last_used_at NULLS FIRST)
  WHERE active = true;

-- Normaliza nomes seed antigos (acentos + caso) pra bater com normalize()
-- do selector. Resolve falso negativo silencioso (cobertura zero).
UPDATE food_education_phrases
SET food_canonical_name = lower(translate(food_canonical_name,
  'áéíóúâêôãõçÁÉÍÓÚÂÊÔÃÕÇ', 'aeiouaeoaocAEIOUAEOAOC'))
WHERE food_canonical_name ~ '[áéíóúâêôãõçÁÉÍÓÚÂÊÔÃÕÇ]'
   OR food_canonical_name <> lower(food_canonical_name);
