-- Product used in the reported Orlando incident. The patient's package photo
-- matches Mission Carb Balance Soft Taco Flour Tortillas: 1 tortilla (43 g),
-- 70 kcal, 6 g protein, 19 g carbohydrate, 3.5 g fat and 17 g fiber.
-- Manufacturer label:
-- https://www.missionfoods.com/wp-content/uploads/2022/07/cb-soft-taco-flour-nf-23.png

INSERT INTO public.food_db (
  name_pt,
  category,
  kcal_per_100g,
  protein_g,
  carbs_g,
  fat_g,
  fiber_g,
  country_code,
  source,
  is_verified,
  source_ref
) VALUES
  (
    'Mission Carb Balance Soft Taco Flour Tortilla',
    'Baked Products',
    162.79,
    13.95,
    44.19,
    8.14,
    39.53,
    'US',
    'product_label_mission_carb_balance_2026_07_18',
    true,
    'PRODUCT_LABEL:mission-carb-balance-soft-taco:US:2026-07-18'
  ),
  (
    'rap10',
    'Baked Products',
    162.79,
    13.95,
    44.19,
    8.14,
    39.53,
    'US',
    'product_label_mission_carb_balance_2026_07_18',
    true,
    'PRODUCT_LABEL:mission-carb-balance-soft-taco:US:2026-07-18:rap10-alias'
  )
ON CONFLICT (name_norm, country_code) DO UPDATE SET
  category = EXCLUDED.category,
  kcal_per_100g = EXCLUDED.kcal_per_100g,
  protein_g = EXCLUDED.protein_g,
  carbs_g = EXCLUDED.carbs_g,
  fat_g = EXCLUDED.fat_g,
  fiber_g = EXCLUDED.fiber_g,
  source = EXCLUDED.source,
  is_verified = EXCLUDED.is_verified,
  source_ref = EXCLUDED.source_ref;
