-- ============================================================================
-- RPC user_metadata_merge — atomic JSONB merge em users.metadata
-- ============================================================================
-- Bug: tools (atualiza_data_user, encerra_atendimento) faziam read-then-write:
--   SELECT metadata → modify in JS → UPDATE
-- Em duas tools simultâneas (ex: pause + escalation), uma sobrescrevia outra.
--
-- Fix: faz o merge no SQL via `||` jsonb concat. Atomic.
-- Aceita partial removal passando `null` em chave (padrão jsonb_set).
-- ============================================================================

CREATE OR REPLACE FUNCTION user_metadata_merge(
  p_user_id uuid,
  p_patch jsonb
)
RETURNS jsonb
LANGUAGE plpgsql
AS $$
DECLARE
  v_result jsonb;
BEGIN
  UPDATE users
     SET metadata = COALESCE(metadata, '{}'::jsonb) || p_patch,
         updated_at = NOW()
   WHERE id = p_user_id
   RETURNING metadata INTO v_result;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'User % not found', p_user_id;
  END IF;

  RETURN v_result;
END $$;

GRANT EXECUTE ON FUNCTION user_metadata_merge TO authenticated, service_role;

COMMENT ON FUNCTION user_metadata_merge IS
  'Atomic merge de metadata. Usa jsonb || jsonb (top-level merge). Pra append em array (ex: labels), passe o array completo já mesclado em JS antes de chamar — RPC não faz array union.';

-- ----------------------------------------------------------------------------
-- RPC user_metadata_label_add — atomic add em metadata.labels (array)
-- ----------------------------------------------------------------------------
-- Caso especial pro encerra_atendimento: precisa adicionar 'humano' em
-- metadata.labels SEM substituir array existente. SQL faz com jsonb_set
-- e dedup via SELECT DISTINCT.
-- ----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION user_metadata_label_add(
  p_user_id uuid,
  p_label text,
  p_extra_patch jsonb DEFAULT '{}'::jsonb
)
RETURNS jsonb
LANGUAGE plpgsql
AS $$
DECLARE
  v_result jsonb;
  v_current_labels jsonb;
  v_new_labels jsonb;
BEGIN
  SELECT COALESCE(metadata->'labels', '[]'::jsonb) INTO v_current_labels
    FROM users WHERE id = p_user_id;

  -- Dedup: se label já está no array, não adiciona
  IF v_current_labels @> to_jsonb(p_label) THEN
    v_new_labels := v_current_labels;
  ELSE
    v_new_labels := v_current_labels || to_jsonb(p_label);
  END IF;

  UPDATE users
     SET metadata = COALESCE(metadata, '{}'::jsonb)
                    || jsonb_build_object('labels', v_new_labels)
                    || p_extra_patch,
         updated_at = NOW()
   WHERE id = p_user_id
   RETURNING metadata INTO v_result;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'User % not found', p_user_id;
  END IF;

  RETURN v_result;
END $$;

GRANT EXECUTE ON FUNCTION user_metadata_label_add TO authenticated, service_role;

COMMENT ON FUNCTION user_metadata_label_add IS
  'Atomic add de label em metadata.labels (com dedup). p_extra_patch permite gravar extras (ex: escalated_at, escalation_reason) na mesma transação.';
