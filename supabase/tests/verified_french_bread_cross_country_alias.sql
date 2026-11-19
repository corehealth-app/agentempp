BEGIN;
DO $test$
DECLARE bread public.food_db%ROWTYPE; upstream public.food_db%ROWTYPE; country text;
BEGIN
 SELECT * INTO STRICT upstream FROM public.food_db WHERE source_ref='TACO4:53' AND is_verified;
 SELECT * INTO STRICT bread FROM public.food_db WHERE source_ref='TACO4:53:alias:BR:pao-frances' AND is_verified;
 IF ROW(bread.kcal_per_100g,bread.protein_g,bread.carbs_g,bread.fat_g,bread.fiber_g)
 IS DISTINCT FROM ROW(upstream.kcal_per_100g,upstream.protein_g,upstream.carbs_g,upstream.fat_g,upstream.fiber_g)
 THEN RAISE EXCEPTION 'bread_alias_nutrition_changed'; END IF;
 FOREACH country IN ARRAY ARRAY['BR','US'] LOOP
 IF NOT EXISTS(SELECT 1 FROM public.search_food_trgm('pao frances',0.9,5,country) WHERE id=bread.id AND similarity=1)
 THEN RAISE EXCEPTION 'bread_not_strict_searchable_%',country; END IF;
 IF EXISTS(SELECT 1 FROM public.search_food_trgm('pao frances integral',0.9,5,country) WHERE id=bread.id)
 OR EXISTS(SELECT 1 FROM public.search_food_trgm('alimento desconhecido',0.9,5,country) WHERE id=bread.id)
 THEN RAISE EXCEPTION 'bread_alias_removed_qualifier'; END IF;
 END LOOP;
END $test$;
ROLLBACK;
