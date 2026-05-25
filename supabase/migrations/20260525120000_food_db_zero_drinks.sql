-- ============================================================================
-- Aliases de bebidas ZERO/diet/light no food_db — Bug Luciana 2026-05-25
-- ============================================================================
-- A food_db tinha "coca-cola" (~42 kcal/100g) mas NÃO tinha "coca-cola zero"/
-- "coca zero", então o trigram (search_food_trgm) casava a versão NORMAL e
-- gravava caloria cheia (136,5 kcal num refri que o paciente disse ser zero).
--
-- O fix principal é determinístico no pipeline (isZeroCalDrink em
-- meal-pipeline.ts força ~0 kcal). Estes aliases são a camada de food_db: dão
-- match direto (~1 kcal/100g) pros nomes zero mais comuns, reduzindo a
-- dependência do guard de runtime.
--
-- Mesmo formato do seed 20260504220000_food_db_aliases_expanded.sql.
-- Macros ~0 (1 kcal/100g, refrigerante adoçado com adoçante não-calórico).
-- ============================================================================

DO $$
DECLARE
  v_aliases jsonb := $aliases$[
    {"name_pt":"coca-cola zero","category":"bebidas","kcal":1,"prot":0,"carb":0,"fat":0,"fib":0},
    {"name_pt":"coca zero","category":"bebidas","kcal":1,"prot":0,"carb":0,"fat":0,"fib":0},
    {"name_pt":"coca-cola diet","category":"bebidas","kcal":1,"prot":0,"carb":0,"fat":0,"fib":0},
    {"name_pt":"coca diet","category":"bebidas","kcal":1,"prot":0,"carb":0,"fat":0,"fib":0},
    {"name_pt":"coca-cola light","category":"bebidas","kcal":1,"prot":0,"carb":0,"fat":0,"fib":0},
    {"name_pt":"guaraná zero","category":"bebidas","kcal":1,"prot":0,"carb":0,"fat":0,"fib":0},
    {"name_pt":"guaraná diet","category":"bebidas","kcal":1,"prot":0,"carb":0,"fat":0,"fib":0},
    {"name_pt":"guaraná antarctica zero","category":"bebidas","kcal":1,"prot":0,"carb":0,"fat":0,"fib":0},
    {"name_pt":"refrigerante diet","category":"bebidas","kcal":1,"prot":0,"carb":0,"fat":0,"fib":0},
    {"name_pt":"refrigerante light","category":"bebidas","kcal":1,"prot":0,"carb":0,"fat":0,"fib":0},
    {"name_pt":"refri zero","category":"bebidas","kcal":1,"prot":0,"carb":0,"fat":0,"fib":0},
    {"name_pt":"pepsi zero","category":"bebidas","kcal":1,"prot":0,"carb":0,"fat":0,"fib":0},
    {"name_pt":"sprite zero","category":"bebidas","kcal":1,"prot":0,"carb":0,"fat":0,"fib":0},
    {"name_pt":"fanta zero","category":"bebidas","kcal":1,"prot":0,"carb":0,"fat":0,"fib":0},
    {"name_pt":"soda diet","category":"bebidas","kcal":1,"prot":0,"carb":0,"fat":0,"fib":0},
    {"name_pt":"água tônica zero","category":"bebidas","kcal":1,"prot":0,"carb":0,"fat":0,"fib":0}
  ]$aliases$::jsonb;
  v_alias jsonb;
BEGIN
  FOR v_alias IN SELECT * FROM jsonb_array_elements(v_aliases) LOOP
    INSERT INTO food_db (name_pt, category, kcal_per_100g, protein_g, carbs_g, fat_g, fiber_g, country_code, source)
    SELECT
      v_alias->>'name_pt',
      v_alias->>'category',
      (v_alias->>'kcal')::numeric,
      (v_alias->>'prot')::numeric,
      (v_alias->>'carb')::numeric,
      (v_alias->>'fat')::numeric,
      (v_alias->>'fib')::numeric,
      'BR',
      'alias'
    WHERE NOT EXISTS (
      SELECT 1 FROM food_db
       WHERE name_pt = v_alias->>'name_pt' AND country_code = 'BR'
    );
  END LOOP;
END $$;
