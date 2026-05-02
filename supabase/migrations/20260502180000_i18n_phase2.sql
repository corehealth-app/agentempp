-- ============================================================================
-- Migration 0022: i18n Fase 2 — food_db por país, rules por idioma, persona
-- ============================================================================
-- Infraestrutura pra suportar múltiplos países sem refator. Conteúdo (food_db
-- USDA, rules em EN/ES) pode ser populado depois quando aparecer demanda real.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1. food_db ganha country_code (default BR pra preservar TACO existente)
-- ----------------------------------------------------------------------------
ALTER TABLE food_db
  ADD COLUMN IF NOT EXISTS country_code text NOT NULL DEFAULT 'BR'
    CHECK (country_code ~ '^[A-Z]{2}$');

CREATE INDEX IF NOT EXISTS idx_food_db_country
  ON food_db(country_code, name_norm);

COMMENT ON COLUMN food_db.country_code IS
  'ISO alpha-2 do país onde o alimento existe/é tipico. BR = TACO, US = USDA, etc.';

-- ----------------------------------------------------------------------------
-- 2. search_food_trgm aceita filtro de país (opcional, default BR)
-- ----------------------------------------------------------------------------
DROP FUNCTION IF EXISTS search_food_trgm(text, real, integer);

CREATE OR REPLACE FUNCTION search_food_trgm(
  search_term       text,
  min_similarity    real    DEFAULT 0.2,
  max_results       integer DEFAULT 5,
  p_country         text    DEFAULT 'BR'
)
RETURNS TABLE (
  id              integer,
  name_pt         text,
  category        text,
  similarity      real,
  kcal_per_100g   numeric,
  protein_g       numeric,
  carbs_g         numeric,
  fat_g           numeric,
  fiber_g         numeric,
  country_code    text
)
LANGUAGE sql
STABLE
PARALLEL SAFE
AS $$
  -- Tenta primeiro no país do user
  SELECT
    f.id, f.name_pt, f.category,
    similarity(f.name_norm, lower(public.unaccent('public.unaccent', search_term))) AS similarity,
    f.kcal_per_100g, f.protein_g, f.carbs_g, f.fat_g, f.fiber_g,
    f.country_code
  FROM food_db f
  WHERE similarity(f.name_norm, lower(public.unaccent('public.unaccent', search_term))) >= min_similarity
    AND f.country_code = p_country
  ORDER BY similarity DESC
  LIMIT max_results;
$$;

GRANT EXECUTE ON FUNCTION search_food_trgm TO authenticated, anon, service_role;

COMMENT ON FUNCTION search_food_trgm IS
  'Fuzzy search na food_db filtrando por país. Default BR (TACO). Quando outros países forem adicionados, passar p_country.';

-- ----------------------------------------------------------------------------
-- 3. agent_rules.language pra suporte a EN/ES futuro
-- ----------------------------------------------------------------------------
ALTER TABLE agent_rules
  ADD COLUMN IF NOT EXISTS language text NOT NULL DEFAULT 'pt-BR'
    CHECK (language ~ '^[a-z]{2}(-[A-Z]{2})?$');

CREATE INDEX IF NOT EXISTS idx_rules_language
  ON agent_rules(language, status, display_order)
  WHERE status = 'active';

COMMENT ON COLUMN agent_rules.language IS
  'BCP-47 reduzido. pt-BR (default), en, es, pt-PT, etc. v_active_prompts faz fallback pra pt-BR.';

-- ----------------------------------------------------------------------------
-- 4. v_active_prompts agora aceita parâmetro de idioma (via overload)
-- ----------------------------------------------------------------------------
-- Mantém v_active_prompts existente pra compat. Adiciona function que aceita language.
CREATE OR REPLACE FUNCTION resolve_system_prompt(
  p_stage text,
  p_language text DEFAULT 'pt-BR'
)
RETURNS text
LANGUAGE sql
STABLE
AS $$
  SELECT string_agg(
    '## ' || topic || E'\n\n' || content,
    E'\n\n---\n\n' ORDER BY display_order
  )
  FROM (
    -- Pega rules do idioma alvo + as gerais default
    SELECT
      r.topic,
      r.content,
      r.display_order,
      CASE WHEN r.language = p_language THEN 0 ELSE 1 END AS lang_priority
    FROM agent_rules r
    WHERE r.status = 'active'
      AND (r.tipo = 'regras_gerais' OR r.tipo::text = p_stage)
      AND (r.language = p_language OR r.language = 'pt-BR')
  ) ranked;
$$;

COMMENT ON FUNCTION resolve_system_prompt IS
  'Monta system prompt do stage no idioma alvo, fallback para pt-BR se rule específica não existe.';

GRANT EXECUTE ON FUNCTION resolve_system_prompt TO authenticated, service_role;

-- ----------------------------------------------------------------------------
-- 5. Persona variável por país via global_config
-- ----------------------------------------------------------------------------
INSERT INTO global_config (key, value, description) VALUES
  ('persona.BR.name',       '"Dr. Roberto Menescal"'::jsonb,
   'Nome do agente em conversas com pacientes brasileiros'),
  ('persona.BR.title',      '"Nutricionista"'::jsonb,
   'Título profissional a usar em apresentações'),
  ('persona.BR.method',     '"Método MPP (Muscular Power Plant)"'::jsonb,
   'Nome do método/programa'),
  ('persona.PT.name',       '"Dr. Roberto Menescal"'::jsonb,
   'Persona pra Portugal — mesmo nome, ajustes na cadência'),
  ('persona.PT.title',      '"Nutricionista"'::jsonb, ''),
  ('persona.PT.method',     '"Método MPP"'::jsonb, ''),
  ('persona.US.name',       '"Dr. Robert Menescal"'::jsonb,
   'Persona pra Estados Unidos — anglicização do nome'),
  ('persona.US.title',      '"Nutritionist"'::jsonb, ''),
  ('persona.US.method',     '"MPP Method (Muscular Power Plant)"'::jsonb, ''),
  ('persona.ES.name',       '"Dr. Roberto Menescal"'::jsonb,
   'Persona pra Espanha/LatAm hispano'),
  ('persona.ES.title',      '"Nutricionista"'::jsonb, ''),
  ('persona.ES.method',     '"Método MPP (Muscular Power Plant)"'::jsonb, ''),
  ('country_to_language',
   '{"BR":"pt-BR","PT":"pt-PT","US":"en","GB":"en","CA":"en","AU":"en","ES":"es","MX":"es","AR":"es","CL":"es","CO":"es","PE":"es","UY":"es","PY":"es","BO":"es","EC":"es","VE":"es","FR":"fr","DE":"de","IT":"it"}'::jsonb,
   'Map ISO country → BCP-47 language. Adicione conforme expandir.')
ON CONFLICT (key) DO NOTHING;

-- ----------------------------------------------------------------------------
-- 6. Rule master de tradução (opera junto com persona)
-- ----------------------------------------------------------------------------
INSERT INTO agent_rules (slug, topic, tipo, content, display_order, language, status)
VALUES (
  'idioma-do-paciente',
  'Idioma da resposta',
  'regras_gerais',
  $rule$
**Sempre responda no idioma do país do paciente** (vem no contexto como "País de residência").

Mapeamento:
- BR → pt-BR (português brasileiro, padrão)
- PT → pt-PT (português europeu — formal, "tu" em vez de "você", "comboio" não "trem")
- US/GB/CA/AU → English (informal, friendly coach tone)
- ES/MX/AR/CL/CO/PE/UY/PY/BO/EC/VE → Español (latino-americano, "tú" informal)
- FR → Français (informal "tu")
- DE → Deutsch (Du, informal)
- IT → Italiano (informal "tu")
- País não listado ou desconhecido → pt-BR

**O sistema é otimizado pra Brasil.** Se responder em outro idioma:
- Não invente alimentos típicos do país do paciente sem confirmar
- Avise se as referências (TACO, BMR Mifflin) podem não bater 100%
- Mantenha o tom "amigo coach" mesmo na tradução

**Persona pelo país** (use o nome correspondente do `global_config.persona.{COUNTRY}.name`):
- BR/PT → Dr. Roberto Menescal
- US/GB → Dr. Robert Menescal
- ES/LATAM → Dr. Roberto Menescal

Não traduza o nome do método arbitrariamente — siga `persona.{COUNTRY}.method` quando precisar mencionar.
$rule$,
  -75,
  'pt-BR',
  'active'
)
ON CONFLICT (slug) DO NOTHING;
