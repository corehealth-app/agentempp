-- ============================================================================
-- match_food_phrases RPC — similarity search via pgvector
-- ============================================================================
-- Workflow audit detectou que essa função foi criada em prod via execute_sql
-- mas não estava na migration. Source-of-truth fix: re-cria idempotente
-- via CREATE OR REPLACE.
--
-- A função roda 100% dentro do Postgres (LANGUAGE sql STABLE) — não faz
-- network calls. Recebe query_embedding já pronto (gerado pelo worker
-- Inngest via OpenRouter) e calcula cosine distance via pgvector.
--
-- Threshold + match_count são passados pelo selector (calibrados
-- empiricamente em 0.80 / 50 — ver curated-phrase-selector.ts).
-- ============================================================================

CREATE OR REPLACE FUNCTION match_food_phrases(
  query_embedding vector(1024),
  match_threshold float,
  match_count int,
  match_language text DEFAULT 'pt-BR'
)
RETURNS TABLE (
  id uuid,
  phrase text,
  tags jsonb,
  usage_count int,
  last_used_at timestamptz,
  similarity float
)
LANGUAGE sql
STABLE
AS $$
  SELECT id, phrase, tags, usage_count, last_used_at,
         1 - (food_name_embedding <=> query_embedding) AS similarity
  FROM food_education_phrases
  WHERE active = true
    AND language = match_language
    AND food_name_embedding IS NOT NULL
    AND polaridade IS NOT NULL  -- exclui seeds sem polaridade
    AND 1 - (food_name_embedding <=> query_embedding) > match_threshold
  ORDER BY last_used_at ASC NULLS FIRST,
           food_name_embedding <=> query_embedding ASC,
           id ASC
  LIMIT match_count;
$$;

GRANT EXECUTE ON FUNCTION match_food_phrases TO service_role, anon, authenticated;
