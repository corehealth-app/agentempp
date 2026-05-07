-- Atualiza calc.protein_factors pra cascata oficial Notion MPP.
-- Bug histórico: mapping invertido pouca↔muita causava overdose/underdose
-- de proteína em pacientes que não fossem 'moderada'.
--
-- Antes: { pouca: 1.6, moderada: 1.8, muita: 2.0 }
-- Depois: cascata em resolveProteinFactor (packages/core/src/nutrition.ts)
--   - muita → 1.6 (perfil comportamental difícil)
--   - training < 3 → 1.7
--   - pouca + treino ≥ 5 → 2.0
--   - pouca + treino ≥ 4 → 1.9
--   - default → 1.8

UPDATE global_config
SET value = $${
  "muita": 1.6,
  "moderada": 1.8,
  "pouca": 1.8,
  "training_low": 1.7,
  "optimal_mid_training": 1.9,
  "optimal_high_training": 2.0
}$$::jsonb,
    description = 'Gramas de proteína por kg. Cascata oficial MPP (resolveProteinFactor): muita→1.6, training<3→1.7, pouca+treino≥5→2.0, pouca+treino≥4→1.9, default→1.8.'
WHERE key = 'calc.protein_factors';
