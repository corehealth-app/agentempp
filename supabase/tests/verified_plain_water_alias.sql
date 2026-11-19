BEGIN;
DO $test$
DECLARE water public.food_db%ROWTYPE;
BEGIN
  SELECT * INTO STRICT water FROM public.food_db
  WHERE country_code = 'BR' AND name_norm = 'agua' AND is_verified;
  IF water.source_ref <> 'FDC:174158:alias:BR:agua'
    OR water.kcal_per_100g <> 0 OR water.protein_g <> 0
    OR water.carbs_g <> 0 OR water.fat_g <> 0 OR water.fiber_g <> 0 THEN
    RAISE EXCEPTION 'water_provenance_or_nutrition_mismatch';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.search_food_trgm('agua', 0.9, 5, 'BR')
    WHERE id = water.id AND similarity = 1) THEN
    RAISE EXCEPTION 'water_not_strict_searchable';
  END IF;
  IF EXISTS (SELECT 1 FROM public.search_food_trgm('agua de coco', 0.9, 5, 'BR')
    WHERE id = water.id) OR EXISTS (
    SELECT 1 FROM public.search_food_trgm('bebida desconhecida', 0.9, 5, 'BR')
    WHERE id = water.id) THEN
    RAISE EXCEPTION 'plain_water_qualified_a_different_drink';
  END IF;
END $test$;
ROLLBACK;
