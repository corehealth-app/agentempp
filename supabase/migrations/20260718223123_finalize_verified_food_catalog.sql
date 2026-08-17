-- Activate the nutrition trust boundary only after every official catalog and
-- audited product alias is present. This ordering keeps database-first deploys
-- compatible with the currently running application throughout the rollout.

ALTER TABLE public.food_db
  ADD CONSTRAINT food_db_verified_source_ref_check
    CHECK (is_verified IS FALSE OR source_ref IS NOT NULL) NOT VALID;

ALTER TABLE public.food_db
  VALIDATE CONSTRAINT food_db_verified_source_ref_check;

CREATE OR REPLACE FUNCTION public.search_food_trgm(
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
SET search_path = public, pg_temp
AS $$
  WITH normalized AS (
    SELECT lower(public.unaccent('public.unaccent', COALESCE(search_term, ''))) AS term
  ), nearest AS MATERIALIZED (
    SELECT
      food.id,
      food.name_pt,
      food.category,
      similarity(food.name_norm, normalized.term) AS similarity,
      food.kcal_per_100g,
      food.protein_g,
      food.carbs_g,
      food.fat_g,
      food.fiber_g,
      food.country_code
    FROM public.food_db AS food
    CROSS JOIN normalized
    WHERE food.is_verified IS TRUE
    ORDER BY food.name_norm <-> normalized.term
    LIMIT LEAST(GREATEST(COALESCE(max_results, 5) * 4, 20), 200)
  )
  SELECT
    nearest.id,
    nearest.name_pt,
    nearest.category,
    nearest.similarity,
    nearest.kcal_per_100g,
    nearest.protein_g,
    nearest.carbs_g,
    nearest.fat_g,
    nearest.fiber_g,
    nearest.country_code
  FROM nearest
  WHERE nearest.similarity >= COALESCE(min_similarity, 0.2)
  ORDER BY
    nearest.similarity DESC,
    CASE WHEN nearest.country_code = p_country THEN 0 ELSE 1 END,
    nearest.id
  LIMIT LEAST(GREATEST(COALESCE(max_results, 5), 1), 50);
$$;

COMMENT ON FUNCTION public.search_food_trgm(text, real, integer, text) IS
  'Cross-country food search restricted to nutrition rows with verified provenance.';

CREATE OR REPLACE FUNCTION public.enforce_verified_food_db_reference()
RETURNS trigger
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = public, pg_temp
AS $$
BEGIN
  IF NEW.food_db_id IS NOT NULL AND NOT EXISTS (
    SELECT 1
    FROM public.food_db AS food
    WHERE food.id = NEW.food_db_id
      AND food.is_verified IS TRUE
  ) THEN
    RAISE EXCEPTION 'invalid meal item provenance: unverified or unknown food_db_id';
  END IF;

  RETURN NEW;
END;
$$;

REVOKE ALL ON FUNCTION public.enforce_verified_food_db_reference() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.enforce_verified_food_db_reference() TO service_role;

CREATE TRIGGER meal_logs_verified_food_db_reference
  BEFORE INSERT OR UPDATE OF food_db_id
  ON public.meal_logs
  FOR EACH ROW
  EXECUTE FUNCTION public.enforce_verified_food_db_reference();

COMMENT ON FUNCTION public.enforce_verified_food_db_reference() IS
  'Database-level last line of defense: new meal logs cannot reference unverified food_db rows.';
