-- Canonical Nutella references from the manufacturer's nutrition tables.
-- Brazil: 100g = 542 kcal, 6.3g protein, 58g carbs, 31g fat, 3g fiber.
-- https://www.nutella.com/br/pt/produtos/nutella
-- United States: 37g = 200 kcal, 2g protein, 22g carbs, 11g fat, 1g fiber.
-- https://www.nutella.com/us/en/products/nutella

INSERT INTO public.food_db (
  name_pt,
  category,
  kcal_per_100g,
  protein_g,
  carbs_g,
  fat_g,
  fiber_g,
  country_code,
  source
) VALUES
  (
    'Nutella',
    'doces',
    542,
    6.3,
    58,
    31,
    3,
    'BR',
    'nutella_br_official_2026_07_18'
  ),
  (
    'Nutella',
    'doces',
    540.54,
    5.41,
    59.46,
    29.73,
    2.70,
    'US',
    'nutella_us_official_2026_07_18'
  )
ON CONFLICT (name_norm, country_code) DO UPDATE SET
  category = EXCLUDED.category,
  kcal_per_100g = EXCLUDED.kcal_per_100g,
  protein_g = EXCLUDED.protein_g,
  carbs_g = EXCLUDED.carbs_g,
  fat_g = EXCLUDED.fat_g,
  fiber_g = EXCLUDED.fiber_g,
  source = EXCLUDED.source;
