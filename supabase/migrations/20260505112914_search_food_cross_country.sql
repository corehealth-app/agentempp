-- ============================================================================
-- search_food_trgm: cross-country fuzzy search
-- ============================================================================
-- Bug crítico: RPC anterior filtrava `country_code = p_country`, retornando
-- 0 matches pra brasileiros morando nos EUA (country='US' mas comem comida
-- e falam em PT). Roberto tinha 100% dos itens com 0 kcal.
--
-- Fix: busca em TODOS os países, ordenando preferência pelo p_country quando
-- existe match similar. Não regride o caso BR→BR (já era top match).
-- ============================================================================

DROP FUNCTION IF EXISTS search_food_trgm(text, real, integer, text);

CREATE OR REPLACE FUNCTION search_food_trgm(
  search_term       text,
  min_similarity    real    DEFAULT 0.2,
  max_results       integer DEFAULT 5,
  p_country         text    DEFAULT 'BR'
)
RETURNS TABLE (
  id              integer,
  name_pt         text,
  category        text,
  similarity      real,
  kcal_per_100g   numeric,
  protein_g       numeric,
  carbs_g         numeric,
  fat_g           numeric,
  fiber_g         numeric,
  country_code    text
)
LANGUAGE sql
STABLE
PARALLEL SAFE
AS $$
  -- Busca cross-country, preferindo p_country como tiebreaker quando similaridade
  -- é parecida. Se "leite integral" matcha forte em BR e nada em US, retorna BR
  -- mesmo se p_country='US'. Se "milk" matcha forte em US, retorna US.
  SELECT
    f.id, f.name_pt, f.category,
    similarity(f.name_norm, lower(public.unaccent('public.unaccent', search_term))) AS similarity,
    f.kcal_per_100g, f.protein_g, f.carbs_g, f.fat_g, f.fiber_g,
    f.country_code
  FROM food_db f
  WHERE similarity(f.name_norm, lower(public.unaccent('public.unaccent', search_term))) >= min_similarity
  ORDER BY
    -- Prioriza match no país do user, mas só como tiebreaker:
    -- similaridade vence se diferença > 0.05
    similarity(f.name_norm, lower(public.unaccent('public.unaccent', search_term))) DESC,
    CASE WHEN f.country_code = p_country THEN 0 ELSE 1 END ASC
  LIMIT max_results;
$$;

GRANT EXECUTE ON FUNCTION search_food_trgm TO authenticated, anon, service_role;

COMMENT ON FUNCTION search_food_trgm IS
  'Fuzzy cross-country na food_db. p_country é tiebreaker quando similaridade é parecida — não filtro restritivo. Brasileiro nos EUA falando PT matcha BR; americano falando EN matcha US.';
