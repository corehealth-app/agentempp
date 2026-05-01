-- ============================================================================
-- Migration 0001: Extensions and Enums
-- ============================================================================
-- Habilita extensões necessárias e cria todos os tipos enumerados do domínio.
-- ============================================================================

-- Extensions
CREATE EXTENSION IF NOT EXISTS pgcrypto;
CREATE EXTENSION IF NOT EXISTS pg_trgm;
CREATE EXTENSION IF NOT EXISTS unaccent;
CREATE EXTENSION IF NOT EXISTS vector;
CREATE EXTENSION IF NOT EXISTS pg_cron;

-- ============================================================================
-- ENUMS
-- ============================================================================

CREATE TYPE user_status AS ENUM ('active', 'blocked', 'deleted');

CREATE TYPE sex_enum AS ENUM ('masculino', 'feminino');

CREATE TYPE activity_enum AS ENUM (
  'sedentario',
  'leve',
  'moderado',
  'alto',
  'atleta'
);

CREATE TYPE water_enum AS ENUM ('pouco', 'moderado', 'bastante');

CREATE TYPE hunger_enum AS ENUM ('pouca', 'moderada', 'muita');

CREATE TYPE protocol_enum AS ENUM (
  'recomposicao',
  'ganho_massa',
  'manutencao'
);

CREATE TYPE goal_type_enum AS ENUM ('BF', 'IMC');

CREATE TYPE direction_enum AS ENUM ('in', 'out');

CREATE TYPE msg_role_enum AS ENUM ('user', 'assistant', 'system', 'tool');

CREATE TYPE content_type_enum AS ENUM (
  'text',
  'audio',
  'image',
  'template',
  'interactive'
);

CREATE TYPE meal_type_enum AS ENUM (
  'cafe',
  'almoco',
  'lanche',
  'jantar',
  'ceia',
  'outro'
);

CREATE TYPE agent_stage AS ENUM (
  'coleta_dados',
  'recomposicao',
  'ganho_massa',
  'manutencao',
  'analista_diario',
  'engajamento'
);

CREATE TYPE rule_tipo AS ENUM (
  'recomposicao',
  'ganho_massa',
  'manutencao',
  'coleta_dados',
  'regras_gerais'
);

CREATE TYPE config_status AS ENUM (
  'draft',
  'testing',
  'active',
  'archived'
);

CREATE TYPE plan_enum AS ENUM ('trial', 'mensal', 'anual');

CREATE TYPE sub_status AS ENUM (
  'trial',
  'active',
  'past_due',
  'canceled',
  'expired'
);
