-- Consolidated mobile state follows event occurrence time rather than worker
-- completion order. The append-only ledger remains the source for ties and
-- out-of-order save/open/complete delivery.
CREATE INDEX IF NOT EXISTS content_events_state_order_idx
  ON public.content_events (
    user_id,
    publication_id,
    occurred_at DESC,
    created_at DESC,
    id DESC
  );

CREATE INDEX IF NOT EXISTS content_events_save_order_idx
  ON public.content_events (
    user_id,
    publication_id,
    occurred_at DESC,
    created_at DESC,
    id DESC
  )
  WHERE event_type IN ('saved', 'unsaved');

CREATE OR REPLACE FUNCTION private.enforce_content_user_state_monotonic()
RETURNS trigger
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_old_version integer;
  v_new_version integer;
  v_latest_origin text;
  v_latest_save_type text;
  v_latest_save_at timestamptz;
  v_preserve_origin boolean := false;
BEGIN
  IF OLD.first_opened_at IS NOT NULL AND (
    NEW.first_opened_at IS NULL OR NEW.first_opened_at > OLD.first_opened_at
  ) THEN
    NEW.first_opened_at := OLD.first_opened_at;
  END IF;

  IF OLD.last_opened_at IS NOT NULL AND (
    NEW.last_opened_at IS DISTINCT FROM OLD.last_opened_at
    OR NEW.last_opened_version_id IS DISTINCT FROM OLD.last_opened_version_id
  ) THEN
    IF NEW.last_opened_at IS NULL OR NEW.last_opened_at < OLD.last_opened_at THEN
      NEW.last_opened_at := OLD.last_opened_at;
      NEW.last_opened_version_id := OLD.last_opened_version_id;
      v_preserve_origin := true;
    ELSIF NEW.last_opened_at = OLD.last_opened_at
      AND NEW.last_opened_version_id IS DISTINCT FROM OLD.last_opened_version_id THEN
      SELECT version.version
      INTO v_old_version
      FROM public.content_versions version
      WHERE version.id = OLD.last_opened_version_id;

      SELECT version.version
      INTO v_new_version
      FROM public.content_versions version
      WHERE version.id = NEW.last_opened_version_id;

      IF v_new_version IS NULL OR v_old_version IS NULL OR v_new_version < v_old_version THEN
        NEW.last_opened_version_id := OLD.last_opened_version_id;
        v_preserve_origin := true;
      END IF;
    END IF;
  END IF;

  IF OLD.completed_at IS NOT NULL AND (
    NEW.completed_at IS DISTINCT FROM OLD.completed_at
    OR NEW.completed_version_id IS DISTINCT FROM OLD.completed_version_id
  ) THEN
    IF NEW.completed_at IS NULL OR NEW.completed_at < OLD.completed_at THEN
      NEW.completed_at := OLD.completed_at;
      NEW.completed_version_id := OLD.completed_version_id;
      v_preserve_origin := true;
    ELSIF NEW.completed_at = OLD.completed_at
      AND NEW.completed_version_id IS DISTINCT FROM OLD.completed_version_id THEN
      SELECT version.version
      INTO v_old_version
      FROM public.content_versions version
      WHERE version.id = OLD.completed_version_id;

      SELECT version.version
      INTO v_new_version
      FROM public.content_versions version
      WHERE version.id = NEW.completed_version_id;

      IF v_new_version IS NULL OR v_old_version IS NULL OR v_new_version < v_old_version THEN
        NEW.completed_version_id := OLD.completed_version_id;
        v_preserve_origin := true;
      END IF;
    END IF;
  END IF;

  IF v_preserve_origin THEN
    NEW.last_origin := OLD.last_origin;
  END IF;

  SELECT event.origin
  INTO v_latest_origin
  FROM public.content_events event
  WHERE event.user_id = NEW.user_id
    AND event.publication_id = NEW.publication_id
    AND event.event_type IN ('opened', 'completed', 'saved', 'unsaved')
  ORDER BY event.occurred_at DESC, event.created_at DESC, event.id DESC
  LIMIT 1;

  IF FOUND THEN
    NEW.last_origin := v_latest_origin;
  END IF;

  SELECT event.event_type, event.occurred_at
  INTO v_latest_save_type, v_latest_save_at
  FROM public.content_events event
  WHERE event.user_id = NEW.user_id
    AND event.publication_id = NEW.publication_id
    AND event.event_type IN ('saved', 'unsaved')
  ORDER BY event.occurred_at DESC, event.created_at DESC, event.id DESC
  LIMIT 1;

  IF FOUND THEN
    NEW.saved_at := CASE
      WHEN v_latest_save_type = 'saved' THEN v_latest_save_at
      ELSE NULL
    END;
  END IF;

  RETURN NEW;
END;
$$;

REVOKE ALL ON FUNCTION private.enforce_content_user_state_monotonic()
  FROM PUBLIC, anon, authenticated;

DROP TRIGGER IF EXISTS content_user_state_monotonic_guard
  ON public.content_user_state;
CREATE TRIGGER content_user_state_monotonic_guard
  BEFORE UPDATE ON public.content_user_state
  FOR EACH ROW
  EXECUTE FUNCTION private.enforce_content_user_state_monotonic();

DO $migration$
DECLARE
  v_signature constant regprocedure := to_regprocedure(
    'public.set_mobile_content_saved(uuid,uuid,integer,boolean,text,text,timestamp with time zone)'
  );
  v_old_result constant text := $old$  SELECT COALESCE(
    state.completed_at IS NOT NULL
      AND state.completed_version_id = v_version_id,
    false
  )
  INTO v_completed
  FROM (SELECT 1) singleton
  LEFT JOIN public.content_user_state state
    ON state.user_id = p_user_id
    AND state.publication_id = p_publication_id;

  v_response := jsonb_build_object(
    'publicationId', p_publication_id,
    'version', p_version,
    'saved', p_saved,
    'completed', v_completed,
    'changed', true,
    'replayed', false
  );
$old$;
  v_new_result constant text := $new$  SELECT
    COALESCE(state.saved_at IS NOT NULL, false),
    COALESCE(
      state.completed_at IS NOT NULL
        AND state.completed_version_id = v_version_id,
      false
    )
  INTO v_current_saved, v_completed
  FROM (SELECT 1) singleton
  LEFT JOIN public.content_user_state state
    ON state.user_id = p_user_id
    AND state.publication_id = p_publication_id;

  v_response := jsonb_build_object(
    'publicationId', p_publication_id,
    'version', p_version,
    'saved', v_current_saved,
    'completed', v_completed,
    'changed', v_current_saved IS NOT DISTINCT FROM p_saved,
    'replayed', false
  );
$new$;
  v_definition text;
  v_rewritten text;
BEGIN
  IF v_signature IS NULL THEN
    RAISE EXCEPTION 'required content save function is missing';
  END IF;

  v_definition := pg_get_functiondef(v_signature);
  IF position(v_old_result IN v_definition) > 0 THEN
    v_rewritten := replace(v_definition, v_old_result, v_new_result);
    IF position(v_old_result IN v_rewritten) > 0
      OR position(v_new_result IN v_rewritten) = 0 THEN
      RAISE EXCEPTION 'content save response rewrite failed';
    END IF;
    EXECUTE v_rewritten;
  ELSIF position(v_new_result IN v_definition) = 0 THEN
    RAISE EXCEPTION 'content save response precondition failed';
  END IF;
END;
$migration$;

REVOKE ALL ON FUNCTION public.set_mobile_content_saved(
  uuid, uuid, integer, boolean, text, text, timestamptz
) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.set_mobile_content_saved(
  uuid, uuid, integer, boolean, text, text, timestamptz
) TO service_role;
