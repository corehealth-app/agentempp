-- ============================================================================
-- Migration 0010: search_food_trgm RPC
-- ============================================================================
-- Function pública para fuzzy search na food_db usando pg_trgm.
-- Retorna top match acima de min_similarity, ordenado por similaridade.
-- ============================================================================

CREATE OR REPLACE FUNCTION search_food_trgm(
  search_term text,
  min_similarity real DEFAULT 0.2,
  max_results integer DEFAULT 5
)
RETURNS TABLE (
  id integer,
  name_pt text,
  category text,
  similarity real,
  kcal_per_100g numeric,
  protein_g numeric,
  carbs_g numeric,
  fat_g numeric,
  fiber_g numeric
)
LANGUAGE sql
STABLE
PARALLEL SAFE
AS $$
  SELECT
    f.id,
    f.name_pt,
    f.category,
    similarity(f.name_norm, lower(public.unaccent('public.unaccent', search_term))) AS similarity,
    f.kcal_per_100g,
    f.protein_g,
    f.carbs_g,
    f.fat_g,
    f.fiber_g
  FROM food_db f
  WHERE similarity(f.name_norm, lower(public.unaccent('public.unaccent', search_term))) >= min_similarity
  ORDER BY similarity DESC
  LIMIT max_results;
$$;

COMMENT ON FUNCTION search_food_trgm IS
  'Busca alimentos por similaridade trigram. Aceita typos e variações ortográficas.';

-- Permissões
GRANT EXECUTE ON FUNCTION search_food_trgm TO authenticated, anon, service_role;
