-- The photo flow can identify ordinary water alongside food. Keep this known
-- zero-energy drink distinct from unknown drinks, coconut water and tonic water.
-- Copy only the existing verified upstream row, not model-generated nutrition.
-- USDA FDC SR Legacy 174158: Water, bottled, generic, per 100 g.
-- https://api.nal.usda.gov/fdc/v1/food/174158
DO $migration$
DECLARE upstream public.food_db%ROWTYPE; existing public.food_db%ROWTYPE;
BEGIN
  SELECT * INTO STRICT upstream FROM public.food_db
  WHERE source_ref = 'FDC:174158' AND is_verified IS TRUE;
  IF upstream.name_pt <> 'Water, bottled, generic'
    OR upstream.kcal_per_100g IS DISTINCT FROM 0
    OR upstream.protein_g IS DISTINCT FROM 0
    OR upstream.carbs_g IS DISTINCT FROM 0
    OR upstream.fat_g IS DISTINCT FROM 0
    OR upstream.fiber_g IS DISTINCT FROM 0 THEN
    RAISE EXCEPTION 'verified_plain_water_upstream_mismatch';
  END IF;
  SELECT * INTO existing FROM public.food_db
  WHERE name_norm = 'agua' AND country_code = 'BR';
  IF FOUND THEN
    IF existing.source_ref IS DISTINCT FROM 'FDC:174158:alias:BR:agua'
      OR existing.is_verified IS DISTINCT FROM true
      OR existing.kcal_per_100g IS DISTINCT FROM upstream.kcal_per_100g
      OR existing.protein_g IS DISTINCT FROM upstream.protein_g
      OR existing.carbs_g IS DISTINCT FROM upstream.carbs_g
      OR existing.fat_g IS DISTINCT FROM upstream.fat_g
      OR existing.fiber_g IS DISTINCT FROM upstream.fiber_g THEN
      RAISE EXCEPTION 'verified_plain_water_alias_conflict';
    END IF;
  ELSE
    INSERT INTO public.food_db
      (name_pt, category, kcal_per_100g, protein_g, carbs_g, fat_g, fiber_g,
       country_code, source, is_verified, source_ref)
    VALUES ('água', upstream.category, upstream.kcal_per_100g, upstream.protein_g,
      upstream.carbs_g, upstream.fat_g, upstream.fiber_g, 'BR',
      'USDA_FDC_SR_LEGACY_2018_ALIAS', true, 'FDC:174158:alias:BR:agua');
  END IF;
END $migration$;
