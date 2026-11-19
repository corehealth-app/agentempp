-- Portuguese food names remain valid for people residing outside Brazil.
-- Country is a search tie-breaker, not the language of the reported food.
-- Exact alias of the existing official TACO IV row 53; no new nutrition estimate.
DO $migration$
DECLARE upstream public.food_db%ROWTYPE; existing public.food_db%ROWTYPE;
BEGIN
 SELECT * INTO STRICT upstream FROM public.food_db WHERE source_ref='TACO4:53' AND is_verified;
 IF upstream.name_pt <> 'Pão, trigo, francês' OR upstream.country_code <> 'BR'
 OR ROW(upstream.kcal_per_100g,upstream.protein_g,upstream.carbs_g,upstream.fat_g,upstream.fiber_g)
 IS DISTINCT FROM ROW(299.81::numeric,7.95::numeric,58.65::numeric,3.1::numeric,2.31::numeric)
 THEN RAISE EXCEPTION 'verified_french_bread_upstream_mismatch'; END IF;
 SELECT * INTO existing FROM public.food_db WHERE name_norm='pao frances' AND country_code='BR';
 IF FOUND THEN
 IF existing.source_ref IS DISTINCT FROM 'TACO4:53:alias:BR:pao-frances' OR existing.is_verified IS DISTINCT FROM true
 OR ROW(existing.kcal_per_100g,existing.protein_g,existing.carbs_g,existing.fat_g,existing.fiber_g)
 IS DISTINCT FROM ROW(upstream.kcal_per_100g,upstream.protein_g,upstream.carbs_g,upstream.fat_g,upstream.fiber_g)
 THEN RAISE EXCEPTION 'verified_french_bread_alias_conflict'; END IF;
 ELSE
 INSERT INTO public.food_db(name_pt,category,kcal_per_100g,protein_g,carbs_g,fat_g,fiber_g,country_code,source,is_verified,source_ref)
 VALUES('pão francês',upstream.category,upstream.kcal_per_100g,upstream.protein_g,upstream.carbs_g,upstream.fat_g,upstream.fiber_g,'BR','TACO_IV_OFFICIAL_2011_ALIAS',true,'TACO4:53:alias:BR:pao-frances');
 END IF;
END $migration$;
