-- Display-only proof accepts the exact official quantity-edit calorie precision.
-- Never recalculate stored nutrition, infer a liquid density, or rewrite receipts.
BEGIN;
SET LOCAL lock_timeout='5s';
DO $qualified$
BEGIN
 IF current_user<>'postgres' THEN RAISE EXCEPTION 'nutrition_rounding_requires_postgres' USING ERRCODE='42501';END IF;
 IF (SELECT encode(sha256(convert_to(prosrc,'UTF8')),'hex') FROM pg_proc
  WHERE oid=to_regprocedure('private.nutrition_window_same_scaled_food(jsonb,jsonb)'))
  IS DISTINCT FROM 'fe464f67909758dce800657cc48875e36691029ad78e0b05ff01d457c5fe1773' THEN RAISE EXCEPTION 'nutrition_rounding_unknown_proof';END IF;
END $qualified$;
-- Match the complete binary64+EPSILON vector already enforced by C11, or the
-- complete previously qualified numeric2 vector. Never mix rounding modes by
-- nutrient, infer a density, or allow a fuzzy numerical tolerance.
CREATE OR REPLACE FUNCTION private.nutrition_window_same_scaled_food(a jsonb,b jsonb) RETURNS boolean
LANGUAGE plpgsql IMMUTABLE SET search_path=pg_catalog AS $$
DECLARE k text;q numeric;ratio double precision;scaled double precision;rounded double precision;
 factor integer;legacy boolean:=true;official boolean:=true;
BEGIN
 IF jsonb_typeof(a->'quantity_g') IS DISTINCT FROM 'number' OR jsonb_typeof(b->'quantity_g') IS DISTINCT FROM 'number'
  OR (a->>'quantity_g')::numeric<=0 OR (b->>'quantity_g')::numeric<=0 THEN RETURN false;END IF;
 FOREACH k IN ARRAY ARRAY['user_id','snapshot_id','food_name','food_db_id','source','meal_type','consumed_at','raw_provider_message_id'] LOOP
  IF a->k IS DISTINCT FROM b->k THEN RETURN false;END IF;
 END LOOP;
 q:=(b->>'quantity_g')::numeric/(a->>'quantity_g')::numeric;
 ratio:=(b->>'quantity_g')::double precision/(a->>'quantity_g')::double precision;
 FOREACH k IN ARRAY ARRAY['kcal','protein_g','carbs_g','fat_g'] LOOP
  IF jsonb_typeof(a->k) IS DISTINCT FROM 'number' OR jsonb_typeof(b->k) IS DISTINCT FROM 'number' THEN RETURN false;END IF;
  legacy:=legacy AND round((a->>k)::numeric*q,2) IS NOT DISTINCT FROM (b->>k)::numeric;
  factor:=CASE WHEN k='kcal' THEN 10 ELSE 100 END;
  scaled:=((a->>k)::double precision*ratio+2.220446049250313e-16::double precision)*factor;
  -- Same positive Math.round implementation as mutate_mobile_confirmed_meal:
  -- floor(x+0.5) would add another rounding at a half-way boundary.
  rounded:=(floor(scaled)+CASE WHEN scaled-floor(scaled)>=0.5 THEN 1 ELSE 0 END)/factor;
  official:=official AND rounded IS NOT DISTINCT FROM (b->>k)::double precision;
 END LOOP;
 RETURN legacy OR official;
EXCEPTION WHEN numeric_value_out_of_range THEN RETURN false;
END $$;
COMMIT;
