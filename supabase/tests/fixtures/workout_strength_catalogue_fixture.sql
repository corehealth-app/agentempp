-- TEST-ONLY independent fixture, included inside the caller's BEGIN/ROLLBACK.
-- No product observer/body, users, auth shim, cross-task helper or COMMIT here.
-- Caller already proved these table/schema objects absent and pins original DDL.
CREATE SCHEMA c59a3s3_fixture;
REVOKE ALL ON SCHEMA c59a3s3_fixture FROM PUBLIC,anon,authenticated,service_role;
CREATE FUNCTION c59a3s3_fixture.ok(p_ok boolean,p_label text) RETURNS void
LANGUAGE plpgsql SECURITY INVOKER SET search_path=pg_catalog AS $$
BEGIN
  IF p_ok IS DISTINCT FROM true THEN
    RAISE EXCEPTION 'C59A3_S3_ASSERT:%',p_label USING ERRCODE='P0001';
  END IF;
  RAISE NOTICE 'C59A3_S3_PASS:%',p_label;
END $$;
CREATE FUNCTION c59a3s3_fixture.throws(p_sql text,p_state text,p_message text,p_label text)
RETURNS void LANGUAGE plpgsql SECURITY INVOKER SET search_path=pg_catalog AS $$
DECLARE s text;m text;
BEGIN
  BEGIN
    EXECUTE p_sql;
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS s=RETURNED_SQLSTATE,m=MESSAGE_TEXT;
    PERFORM c59a3s3_fixture.ok(s=p_state AND (p_message IS NULL OR m=p_message),p_label);
    RETURN;
  END;
  RAISE EXCEPTION 'C59A3_S3_EXPECTED_ERROR:%',p_label USING ERRCODE='P0001';
END $$;
REVOKE ALL ON FUNCTION c59a3s3_fixture.ok(boolean,text)
  FROM PUBLIC,anon,authenticated,service_role;
REVOKE ALL ON FUNCTION c59a3s3_fixture.throws(text,text,text,text)
  FROM PUBLIC,anon,authenticated,service_role;

-- Exact original DDL lines14–27, including the complete comment statement.
CREATE TABLE IF NOT EXISTS workout_types (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  slug            text NOT NULL UNIQUE,
  display_name    text NOT NULL,
  category        text NOT NULL CHECK (category IN ('musculacao', 'cardio', 'esporte', 'mobilidade')),
  kcal_per_min    numeric(5,2) NOT NULL,  -- pra paciente médio (70kg, intensidade moderada)
  description     text,
  is_active       boolean NOT NULL DEFAULT true,
  created_at      timestamptz NOT NULL DEFAULT now(),
  updated_at      timestamptz NOT NULL DEFAULT now()
);

COMMENT ON TABLE workout_types IS
  'Tipos de treino com kcal/min de referência. Replicação do ADR-007: cálculo determinístico em vez de LLM estimar.';

-- Exact original line63: real legacy SELECT authority present before migration.
GRANT SELECT ON workout_types TO authenticated, service_role;
