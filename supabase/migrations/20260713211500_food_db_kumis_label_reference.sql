-- Canonical US reference for the Yokey Kumis incident.
-- Visible label: 1 cup (240g) = 200 kcal, 8g protein, 23g carbs, 8g fat.
-- Normalized per 100g so any consumed quantity scales deterministically.

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
) VALUES (
  'iogurte kumis',
  'lacteos',
  83.33,
  3.33,
  9.58,
  3.33,
  0,
  'US',
  'product_label_yokey_kumis_2026_07_13'
)
ON CONFLICT (name_norm, country_code) DO UPDATE SET
  category = EXCLUDED.category,
  kcal_per_100g = EXCLUDED.kcal_per_100g,
  protein_g = EXCLUDED.protein_g,
  carbs_g = EXCLUDED.carbs_g,
  fat_g = EXCLUDED.fat_g,
  fiber_g = EXCLUDED.fiber_g,
  source = EXCLUDED.source;
