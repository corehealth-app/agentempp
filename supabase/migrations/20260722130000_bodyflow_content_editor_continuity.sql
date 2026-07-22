-- Editorial ownership is role-based. The immutable authored_by field retains
-- original authorship while audit_log records every subsequent editor action.
DO $migration$
DECLARE
  v_signatures constant regprocedure[] := ARRAY[
    to_regprocedure(
      'public.save_content_draft(uuid,uuid,timestamp with time zone,jsonb)'
    ),
    to_regprocedure(
      'public.submit_content_version(uuid,uuid,timestamp with time zone)'
    )
  ];
  v_guards constant text[] := ARRAY[
    $save_guard$  IF v_version.authored_by <> p_actor_id THEN
    RAISE EXCEPTION 'only the content author may save this draft' USING ERRCODE = '42501';
  END IF;
$save_guard$,
    $submit_guard$  IF v_version.authored_by <> p_actor_id THEN
    RAISE EXCEPTION 'only the content author may submit this version' USING ERRCODE = '42501';
  END IF;
$submit_guard$
  ];
  v_role_guard constant text := 'content_editor actor is required';
  v_index integer;
  v_definition text;
  v_rewritten text;
BEGIN
  FOR v_index IN 1..cardinality(v_signatures)
  LOOP
    IF v_signatures[v_index] IS NULL THEN
      RAISE EXCEPTION 'required content authoring function is missing';
    END IF;

    v_definition := pg_get_functiondef(v_signatures[v_index]);
    IF position(v_role_guard IN v_definition) = 0 THEN
      RAISE EXCEPTION 'content editor continuity precondition failed for %',
        v_signatures[v_index];
    END IF;

    IF position(v_guards[v_index] IN v_definition) > 0 THEN
      v_rewritten := replace(v_definition, v_guards[v_index], '');
      IF position(v_guards[v_index] IN v_rewritten) > 0
        OR position(v_role_guard IN v_rewritten) = 0 THEN
        RAISE EXCEPTION 'content editor continuity rewrite failed for %',
          v_signatures[v_index];
      END IF;
      EXECUTE v_rewritten;
    END IF;
  END LOOP;
END;
$migration$;

REVOKE ALL ON FUNCTION public.save_content_draft(
  uuid, uuid, timestamptz, jsonb
) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.submit_content_version(
  uuid, uuid, timestamptz
) FROM PUBLIC, anon, authenticated;

GRANT EXECUTE ON FUNCTION public.save_content_draft(
  uuid, uuid, timestamptz, jsonb
) TO service_role;
GRANT EXECUTE ON FUNCTION public.submit_content_version(
  uuid, uuid, timestamptz
) TO service_role;
