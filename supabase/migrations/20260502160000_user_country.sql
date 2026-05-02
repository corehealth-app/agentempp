-- ============================================================================
-- Migration 0020: País de residência do usuário (i18n Fase 1)
-- ============================================================================
-- Hoje o produto é 100% Brasil (TACO, pt-BR, BRL, persona Dr. Roberto).
-- Mas vale capturar país desde já, pra:
--   1. detectar atendimentos fora do BR e flagar pro admin
--   2. preparar i18n futuro sem refator
--   3. lembrar que número de telefone NÃO indica residência
--      (alguém pode ter chip BR morando em Portugal e vice-versa)
--
-- O agente SEMPRE pergunta o país de residência, mesmo se o DDI bater.
-- ============================================================================

ALTER TABLE users
  ADD COLUMN IF NOT EXISTS country
    text CHECK (country ~ '^[A-Z]{2}$') DEFAULT 'BR',
  ADD COLUMN IF NOT EXISTS country_confirmed
    boolean NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS country_detected_from_wpp
    text CHECK (country_detected_from_wpp IS NULL OR country_detected_from_wpp ~ '^[A-Z]{2}$');

CREATE INDEX IF NOT EXISTS idx_users_country
  ON users(country) WHERE country_confirmed = true;
CREATE INDEX IF NOT EXISTS idx_users_country_unconfirmed
  ON users(created_at DESC) WHERE country_confirmed = false;

COMMENT ON COLUMN users.country IS
  'ISO 3166-1 alpha-2 do país de RESIDÊNCIA. Default BR. Definitivo só quando country_confirmed=true.';
COMMENT ON COLUMN users.country_confirmed IS
  'true após o usuário confirmar explicitamente. Antes disso, country é só palpite.';
COMMENT ON COLUMN users.country_detected_from_wpp IS
  'País inferido pelo prefixo do WhatsApp na criação. Não é confiável (chip de viagem, expat, etc).';

-- ----------------------------------------------------------------------------
-- detect_country_from_wpp: heurística inicial pelo DDI
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION detect_country_from_wpp(p_wpp text)
RETURNS text
LANGUAGE plpgsql
IMMUTABLE
AS $$
BEGIN
  IF p_wpp IS NULL OR length(p_wpp) < 8 THEN
    RETURN NULL;
  END IF;

  -- DDIs principais (foco em mercados que falam pt/es e maiores parceiros)
  RETURN CASE
    WHEN p_wpp LIKE '55%'  THEN 'BR'
    WHEN p_wpp LIKE '351%' THEN 'PT'
    WHEN p_wpp LIKE '34%'  THEN 'ES'
    WHEN p_wpp LIKE '52%'  THEN 'MX'
    WHEN p_wpp LIKE '54%'  THEN 'AR'
    WHEN p_wpp LIKE '56%'  THEN 'CL'
    WHEN p_wpp LIKE '57%'  THEN 'CO'
    WHEN p_wpp LIKE '58%'  THEN 'VE'
    WHEN p_wpp LIKE '51%'  THEN 'PE'
    WHEN p_wpp LIKE '593%' THEN 'EC'
    WHEN p_wpp LIKE '595%' THEN 'PY'
    WHEN p_wpp LIKE '598%' THEN 'UY'
    WHEN p_wpp LIKE '591%' THEN 'BO'
    WHEN p_wpp LIKE '44%'  THEN 'GB'
    WHEN p_wpp LIKE '49%'  THEN 'DE'
    WHEN p_wpp LIKE '33%'  THEN 'FR'
    WHEN p_wpp LIKE '39%'  THEN 'IT'
    WHEN p_wpp LIKE '31%'  THEN 'NL'
    WHEN p_wpp LIKE '41%'  THEN 'CH'
    WHEN p_wpp LIKE '43%'  THEN 'AT'
    WHEN p_wpp LIKE '45%'  THEN 'DK'
    WHEN p_wpp LIKE '46%'  THEN 'SE'
    WHEN p_wpp LIKE '47%'  THEN 'NO'
    WHEN p_wpp LIKE '48%'  THEN 'PL'
    WHEN p_wpp LIKE '353%' THEN 'IE'
    WHEN p_wpp LIKE '353%' THEN 'IE'
    WHEN p_wpp LIKE '81%'  THEN 'JP'
    WHEN p_wpp LIKE '82%'  THEN 'KR'
    WHEN p_wpp LIKE '86%'  THEN 'CN'
    WHEN p_wpp LIKE '91%'  THEN 'IN'
    WHEN p_wpp LIKE '61%'  THEN 'AU'
    WHEN p_wpp LIKE '64%'  THEN 'NZ'
    WHEN p_wpp LIKE '27%'  THEN 'ZA'
    WHEN p_wpp LIKE '20%'  THEN 'EG'
    WHEN p_wpp LIKE '212%' THEN 'MA'
    WHEN p_wpp LIKE '7%'   THEN 'RU'
    -- USA/Canadá compartilham DDI 1, mas length pode diferenciar pouco; assume US
    WHEN p_wpp LIKE '1%' AND length(p_wpp) BETWEEN 11 AND 12 THEN 'US'
    ELSE NULL
  END;
END;
$$;

COMMENT ON FUNCTION detect_country_from_wpp IS
  'Inferência inicial de país pelo prefixo DDI. NÃO usar como fonte de verdade — só sugestão pro agente perguntar.';

GRANT EXECUTE ON FUNCTION detect_country_from_wpp TO authenticated, service_role;

-- ----------------------------------------------------------------------------
-- Trigger: ao inserir user, popula country_detected_from_wpp e country
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION users_populate_country()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
  v_detected text;
BEGIN
  v_detected := detect_country_from_wpp(NEW.wpp);
  IF NEW.country_detected_from_wpp IS NULL THEN
    NEW.country_detected_from_wpp := v_detected;
  END IF;
  -- Só sobrescreve country se ainda não foi confirmado E está com default 'BR'
  IF NEW.country_confirmed = false AND v_detected IS NOT NULL THEN
    NEW.country := v_detected;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_users_populate_country ON users;
CREATE TRIGGER trg_users_populate_country
  BEFORE INSERT ON users
  FOR EACH ROW
  EXECUTE FUNCTION users_populate_country();

-- ----------------------------------------------------------------------------
-- Backfill: rodar pros users existentes (NÃO marca como confirmed)
-- ----------------------------------------------------------------------------
UPDATE users
SET
  country_detected_from_wpp = detect_country_from_wpp(wpp),
  country = COALESCE(detect_country_from_wpp(wpp), country)
WHERE country_confirmed = false;
