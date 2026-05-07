-- food_organization: critério oficial Notion pra Ganho de Massa.
-- Paciente que come improvisado (não estruturado) é bloqueado pra ganho.
-- Sem esse campo, resolveProtocol não conseguia avaliar o critério.

ALTER TABLE user_profiles
ADD COLUMN IF NOT EXISTS food_organization text
  CHECK (food_organization IN ('sim', 'nao'));

COMMENT ON COLUMN user_profiles.food_organization IS
  'Alimentação estruturada (sim/nao). Critério Notion: nao = blocker pra ganho_massa.';
