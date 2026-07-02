-- ============================================================================
-- match_food_phrases: usa HNSW antes da rotação por last_used_at
-- ============================================================================
-- A versão anterior ordenava por last_used_at antes da distância vetorial.
-- Isso atrapalhava o planner a usar o índice HNSW de food_name_embedding.
-- Agora buscamos um conjunto candidato por distância vetorial e só então
-- aplicamos threshold + rotação para evitar repetir frases.

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
  WITH params AS (
    SELECT greatest(coalesce(match_count, 1), 1) AS requested_count
  ),
  candidates AS MATERIALIZED (
    SELECT
      f.id,
      f.phrase,
      f.tags,
      f.usage_count,
      f.last_used_at,
      1 - (f.food_name_embedding <=> query_embedding) AS similarity
    FROM food_education_phrases f
    WHERE f.active = true
      AND f.language = match_language
      AND f.food_name_embedding IS NOT NULL
      AND f.polaridade IS NOT NULL
    ORDER BY f.food_name_embedding <=> query_embedding ASC
    LIMIT (SELECT greatest(requested_count * 5, 50) FROM params)
  )
  SELECT
    c.id,
    c.phrase,
    c.tags,
    c.usage_count,
    c.last_used_at,
    c.similarity
  FROM candidates c
  WHERE c.similarity > match_threshold
  ORDER BY c.last_used_at ASC NULLS FIRST,
           c.similarity DESC,
           c.id ASC
  LIMIT (SELECT requested_count FROM params);
$$;

GRANT EXECUTE ON FUNCTION match_food_phrases TO service_role, anon, authenticated;
