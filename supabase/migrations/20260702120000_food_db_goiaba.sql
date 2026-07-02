-- ============================================================================
-- food_db: goiaba fruta canonica
-- ============================================================================
-- Incidente Paulo/Roberto 2026-07-02: "goiaba" casava via trigram com
-- "goiabada" (255 kcal/100g), registrando ~383 kcal para 150g.
--
-- Referencia operacional definida no incidente: 150g = 95 kcal, 0.9g proteina,
-- 16.1g carboidrato, 0.35g gordura.
-- ============================================================================

DO $$
BEGIN
  UPDATE food_db
     SET category = 'frutas',
         kcal_per_100g = 63.33,
         protein_g = 0.60,
         carbs_g = 10.73,
         fat_g = 0.23,
         fiber_g = 5.40,
         source = 'manual_incident_2026_07_02'
   WHERE name_norm = lower(f_unaccent('goiaba'))
     AND country_code = 'BR';

  IF NOT FOUND THEN
    INSERT INTO food_db (
      name_pt,
      category,
      kcal_per_100g,
      protein_g,
      carbs_g,
      fat_g,
      fiber_g,
      country_code,
      source
    )
    VALUES (
      'goiaba',
      'frutas',
      63.33,
      0.60,
      10.73,
      0.23,
      5.40,
      'BR',
      'manual_incident_2026_07_02'
    );
  END IF;
END $$;
