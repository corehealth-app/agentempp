-- ============================================================================
-- Calc Config: expõe TODAS as constantes do packages/core no global_config
-- ============================================================================
-- Permite editar via UI:
--   - BMR (Mifflin-St Jeor + Katch-McArdle)
--   - Activity factors (sedentário → atleta)
--   - Protein factors (pouca/moderada/muita fome)
--   - KCAL_BLOCK (7700 = 1kg gordura)
--   - Limites IMC/BF pra protocolo
--   - Levels XP
--   - Badges
--   - XP rules diárias
--
-- Funções que computam métricas continuam puras — recebem config como arg.
-- O agente/Inngest carregam config uma vez por execução e passam pra função.
-- ============================================================================

INSERT INTO global_config (key, value, description) VALUES

  -- ----- BMR (cálculo metabólico basal) -----
  ('calc.bmr_mifflin', $${
    "weight_coef": 10,
    "height_coef": 6.25,
    "age_coef": 5,
    "male_offset": 5,
    "female_offset": -161
  }$$::jsonb,
   'Mifflin-St Jeor: BMR = weight*W + height*H - age*A + offset(sex). ⚠️ Constantes científicas — só altere se souber o que está fazendo.'),

  ('calc.bmr_katch', $${
    "base": 370,
    "lbm_coef": 21.6
  }$$::jsonb,
   'Katch-McArdle (usado quando há %BF): BMR = base + lbm_coef * LBM. ⚠️ Constantes científicas.'),

  -- ----- Fatores de atividade (TDEE = BMR * factor) -----
  ('calc.activity_factors', $${
    "sedentario": 1.2,
    "leve": 1.375,
    "moderado": 1.55,
    "alto": 1.725,
    "atleta": 1.9
  }$$::jsonb,
   'Multiplicador BMR → TDEE por nível de atividade.'),

  -- ----- Proteína por nível de fome -----
  ('calc.protein_factors', $${
    "pouca": 1.6,
    "moderada": 1.8,
    "muita": 2.0
  }$$::jsonb,
   'Gramas de proteína por kg de peso corporal, ajustado por fome reportada.'),

  -- ----- Bloco 7700 -----
  ('calc.kcal_block', '7700'::jsonb,
   'kcal pra "queimar 1 kg de gordura" (gamificação). Padrão fisiológico = 7700.'),

  -- ----- Limites de protocolo -----
  ('calc.imc_limit_recomp', '25'::jsonb,
   'IMC ≥ esse valor força recomposição (não permite ganho de massa).'),

  ('calc.training_min', '3'::jsonb,
   'Frequência mínima de treino/semana pra liberar ganho_massa.'),

  ('calc.bf_limits', $${
    "masculino": { "recomp": 20, "gain": 19 },
    "feminino":  { "recomp": 28, "gain": 27 }
  }$$::jsonb,
   'Limites de %BF. Acima de recomp → força recomposição. Abaixo de gain → libera ganho_massa.'),

  -- ----- Metas de redução -----
  ('calc.imc_goal_steps', '[25, 23, 22, 21]'::jsonb,
   'Próximas metas de IMC (busca o primeiro que está ≥1 ponto abaixo do atual).'),

  ('calc.bf_goal_rules', $$[
    { "above": 30, "subtract": 10 },
    { "above": 20, "target":   20 },
    { "above": 18, "target":   18 },
    { "above": 15, "target":   15 },
    { "above":  0, "target":   10 }
  ]$$::jsonb,
   'Meta de %BF: avalia em ordem. Se "subtract" → meta = bf-N; se "target" → meta = N.'),

  -- ----- Níveis XP -----
  ('calc.levels', $$[
    { "level": 1, "name": "Início",       "min":    0, "max":   99 },
    { "level": 2, "name": "Constância",   "min":  100, "max":  249 },
    { "level": 3, "name": "Foco",         "min":  250, "max":  499 },
    { "level": 4, "name": "Disciplina",   "min":  500, "max":  999 },
    { "level": 5, "name": "Performance",  "min": 1000, "max": 1999 },
    { "level": 6, "name": "Domínio",      "min": 2000, "max": 3499 },
    { "level": 7, "name": "Elite MPP",    "min": 3500, "max": null }
  ]$$::jsonb,
   'Faixas de XP por nível. max=null no último nível significa infinito.'),

  -- ----- Badges -----
  ('calc.badges', $$[
    { "key": "Primeira Semana", "type": "streak", "threshold":  7 },
    { "key": "Mês de Ferro",    "type": "streak", "threshold": 30 },
    { "key": "Atleta Real",     "type": "streak", "threshold": 90 },
    { "key": "Primeiro Bloco",  "type": "blocks", "threshold":  1 },
    { "key": "XP Master",       "type": "xp",     "threshold": 1000 },
    { "key": "Elite",           "type": "xp",     "threshold": 3500 }
  ]$$::jsonb,
   'Conquistas. type ∈ {streak, blocks, xp}. Granted quando o campo correspondente >= threshold.'),

  -- ----- Regras de XP diário -----
  ('calc.xp_rules', $${
    "base": 10,
    "training_bonus": 5,
    "protein_bonus": 5,
    "protein_threshold_g": 100
  }$$::jsonb,
   'XP diário: base + (training_bonus se treinou) + (protein_bonus se proteína ≥ threshold).')

ON CONFLICT (key) DO NOTHING;
