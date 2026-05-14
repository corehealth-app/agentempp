-- ============================================================================
-- user_food_corrections — mapa de correções de alimentos POR PACIENTE
-- ============================================================================
-- Roberto pediu (2026-05-14): quando o paciente corrige um alimento que a visão
-- identificou errado (ex: "batata" que na verdade é "mandioca"), o sistema deve
-- aprender essa correção e aplicar nas próximas vezes — sem re-perguntar.
--
-- Design fechado em conversa:
--  - ENTRA no mapa na 1ª correção (status='learning').
--  - APLICA com confirmação enquanto status='learning' (confirmed_count=1).
--  - Vira status='active' (aplica silencioso) só na 2ª confirmação.
--  - Suporta macro customizado (geleia caseira da pessoa ≠ geleia padrão).
--  - Contradição (paciente corrige CONTRA o mapa) rebaixa/aposenta a entrada.
--  - Janela de validade: 30 dias sem uso → ignorado na aplicação (filtro no
--    código, não hard-delete — preserva histórico pra auditoria).
-- ============================================================================

CREATE TABLE user_food_corrections (
  id                   uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id              uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  -- nome que a visão/paciente disse originalmente (normalizado: lower, sem acento)
  said_name            text NOT NULL,
  -- o que o alimento realmente é (nome corrigido pelo paciente)
  corrected_to         text NOT NULL,
  -- macro customizado opcional (preenchido só quando o paciente informa valores
  -- específicos — ex: "minha geleia caseira tem 130 kcal/100g"). NULL = usa TACO.
  custom_kcal_per_100g numeric(6,2),
  custom_protein_g     numeric(5,2),
  custom_carbs_g       numeric(5,2),
  custom_fat_g         numeric(5,2),
  -- quantas vezes a correção foi confirmada (1 = learning, >=2 = active)
  confirmed_count      smallint NOT NULL DEFAULT 1,
  -- quantas vezes o paciente corrigiu CONTRA esta entrada
  contradicted_count   smallint NOT NULL DEFAULT 0,
  -- learning = aplica c/ confirmação | active = aplica silencioso | retired = ignorado
  status               text NOT NULL DEFAULT 'learning'
                         CHECK (status IN ('learning', 'active', 'retired')),
  first_seen           timestamptz NOT NULL DEFAULT now(),
  last_seen            timestamptz NOT NULL DEFAULT now(),
  -- uma entrada por (paciente + nome dito) — a correção mais recente vence
  UNIQUE (user_id, said_name)
);

CREATE INDEX idx_food_corrections_lookup
  ON user_food_corrections (user_id, said_name)
  WHERE status <> 'retired';

COMMENT ON TABLE user_food_corrections IS
  'Mapa de correções de alimentos por paciente. O agente aprende quando o paciente corrige um alimento mal identificado e aplica nas próximas. learning=aplica c/ confirmação, active=silencioso (>=2 confirmações), retired=ignorado.';

-- RLS: mesmo padrão das tabelas de domínio — service_role muta (bypass),
-- admin lê. Paciente final não acessa direto (sem API pública pra isso ainda).
ALTER TABLE user_food_corrections ENABLE ROW LEVEL SECURITY;

CREATE POLICY "user_food_corrections_admin_read" ON user_food_corrections
  FOR SELECT
  USING (auth.jwt() ->> 'role' IN ('admin', 'editor', 'viewer'));
