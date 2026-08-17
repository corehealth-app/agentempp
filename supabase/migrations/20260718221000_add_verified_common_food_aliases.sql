-- Audited Portuguese aliases for high-frequency names that do not trigram-match
-- the English USDA descriptions safely, or that otherwise select a different
-- cut/preparation from TACO. Values are copied verbatim from the source_ref
-- documented on each row; the alias suffix preserves source uniqueness.

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
  ('sorvete', 'Sweets', 207, 3.5, 23.6, 11, 0.7, 'BR', 'USDA_FDC_SR_LEGACY_2018_ALIAS', true, 'FDC:167575:alias:BR:sorvete'),
  ('sorvete', 'Sweets', 207, 3.5, 23.6, 11, 0.7, 'US', 'USDA_FDC_SR_LEGACY_2018_ALIAS', true, 'FDC:167575:alias:US:sorvete'),
  ('geleia', 'Sweets', 278, 0.37, 68.86, 0.07, 1.1, 'BR', 'USDA_FDC_SR_LEGACY_2018_ALIAS', true, 'FDC:169641:alias:BR:geleia'),
  ('geleia', 'Sweets', 278, 0.37, 68.86, 0.07, 1.1, 'US', 'USDA_FDC_SR_LEGACY_2018_ALIAS', true, 'FDC:169641:alias:US:geleia'),
  ('geleia de morango', 'Sweets', 278, 0.37, 68.86, 0.07, 1.1, 'BR', 'USDA_FDC_SR_LEGACY_2018_ALIAS', true, 'FDC:169641:alias:BR:geleia-morango'),
  ('geleia de morango', 'Sweets', 278, 0.37, 68.86, 0.07, 1.1, 'US', 'USDA_FDC_SR_LEGACY_2018_ALIAS', true, 'FDC:169641:alias:US:geleia-morango'),
  ('queijo mussarela', 'Leite e derivados', 329.87, 22.65, 3.05, 25.18, NULL, 'BR', 'TACO_IV_OFFICIAL_2011_ALIAS', true, 'TACO4:463:alias:queijo-mussarela'),
  ('queijo mussarela', 'Dairy and Egg Products', 318, 21.6, 2.47, 24.64, 0, 'US', 'USDA_FDC_SR_LEGACY_2018_ALIAS', true, 'FDC:170846:alias:US:queijo-mussarela'),
  ('frango grelhado', 'Carnes e derivados', 159.19, 32.03, 0, 2.48, NULL, 'BR', 'TACO_IV_OFFICIAL_2011_ALIAS', true, 'TACO4:410:alias:frango-grelhado'),
  ('frango grelhado', 'Poultry Products', 151, 30.54, 0, 3.17, 0, 'US', 'USDA_FDC_SR_LEGACY_2018_ALIAS', true, 'FDC:171534:alias:US:frango-grelhado'),
  ('frango frito', 'Poultry Products', 219, 30.57, 1.69, 9.12, 0.1, 'BR', 'USDA_FDC_SR_LEGACY_2018_ALIAS', true, 'FDC:171053:alias:BR:frango-frito'),
  ('frango frito', 'Poultry Products', 219, 30.57, 1.69, 9.12, 0.1, 'US', 'USDA_FDC_SR_LEGACY_2018_ALIAS', true, 'FDC:171053:alias:US:frango-frito')
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
