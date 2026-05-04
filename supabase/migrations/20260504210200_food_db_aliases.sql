-- ============================================================================
-- Aliases / nomes populares no food_db (aplicados via REST)
-- ============================================================================
-- Migration original tentava ON CONFLICT (name_pt, country_code) mas não
-- existe constraint UNIQUE nessa combinação. Aliases foram inseridos via
-- REST API com Prefer: resolution=ignore-duplicates pra evitar reprocessar
-- em ambientes futuros (dev fresh).
--
-- Esta migration agora apenas DOCUMENTA o estado esperado: 41 aliases
-- foram seedados pra cobrir gaps comuns que TACO não tinha (ovos fritos,
-- bacon em PT, frangos comuns, pães, lácteos, vegetais cotidianos).
--
-- Pra reaplicar em ambiente novo: rode o seed via apps/admin SeedScripts
-- ou copie o block de INSERT abaixo (usa DO $$ pra ignorar duplicates).
-- ============================================================================

DO $$
DECLARE
  v_aliases jsonb := $aliases$[
    {"name_pt":"ovo frito","category":"ovos","kcal":187,"prot":13.6,"carb":0.7,"fat":14.5,"fib":0},
    {"name_pt":"ovo cozido","category":"ovos","kcal":146,"prot":13.3,"carb":0.6,"fat":9.5,"fib":0},
    {"name_pt":"omelete","category":"ovos","kcal":195,"prot":13.5,"carb":1,"fat":15,"fib":0},
    {"name_pt":"bacon frito","category":"carnes","kcal":541,"prot":37,"carb":1.4,"fat":42,"fib":0},
    {"name_pt":"bacon","category":"carnes","kcal":541,"prot":37,"carb":1.4,"fat":42,"fib":0},
    {"name_pt":"peito de frango","category":"carnes","kcal":159,"prot":32,"carb":0,"fat":2.5,"fib":0},
    {"name_pt":"frango grelhado","category":"carnes","kcal":159,"prot":32,"carb":0,"fat":2.5,"fib":0},
    {"name_pt":"pão de forma","category":"pães","kcal":265,"prot":9,"carb":49,"fat":3.5,"fib":2.5},
    {"name_pt":"pão de forma tostado","category":"pães","kcal":310,"prot":10.5,"carb":57,"fat":4,"fib":2.8},
    {"name_pt":"queijo branco","category":"lacteos","kcal":240,"prot":17,"carb":3,"fat":18,"fib":0},
    {"name_pt":"alface americana","category":"vegetais","kcal":14,"prot":1,"carb":2.5,"fat":0.2,"fib":1.5},
    {"name_pt":"tomate","category":"vegetais","kcal":18,"prot":0.9,"carb":3.9,"fat":0.2,"fib":1.2},
    {"name_pt":"batata frita","category":"tuberculos","kcal":312,"prot":3,"carb":41,"fat":15,"fib":3},
    {"name_pt":"batata cozida","category":"tuberculos","kcal":87,"prot":1.7,"carb":20.1,"fat":0.1,"fib":1.8},
    {"name_pt":"café preto","category":"bebidas","kcal":2,"prot":0.1,"carb":0,"fat":0,"fib":0}
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
