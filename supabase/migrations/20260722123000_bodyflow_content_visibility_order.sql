-- A later editorial version supersedes every older version once it is eligible,
-- even when an older version originally carried a later schedule.
DO $migration$
DECLARE
  v_signature regprocedure;
  v_definition text;
  v_rewritten text;
  v_old_order constant text :=
    'ORDER BY content_version.publish_at DESC, content_version.version DESC';
  v_new_order constant text :=
    'ORDER BY content_version.version DESC, content_version.publish_at DESC';
BEGIN
  FOREACH v_signature IN ARRAY ARRAY[
    to_regprocedure(
      'public.list_mobile_content(uuid,text,text,integer,timestamp with time zone,uuid,timestamp with time zone)'
    ),
    to_regprocedure('public.get_mobile_content(uuid,uuid,timestamp with time zone)'),
    to_regprocedure(
      'public.record_mobile_content_event(uuid,uuid,integer,text,text,text,timestamp with time zone)'
    ),
    to_regprocedure(
      'public.set_mobile_content_saved(uuid,uuid,integer,boolean,text,text,timestamp with time zone)'
    )
  ]
  LOOP
    IF v_signature IS NULL THEN
      RAISE EXCEPTION 'required content delivery function is missing';
    END IF;

    v_definition := pg_get_functiondef(v_signature);
    IF position(v_old_order IN v_definition) > 0 THEN
      v_rewritten := replace(v_definition, v_old_order, v_new_order);
      IF position(v_old_order IN v_rewritten) > 0
        OR position(v_new_order IN v_rewritten) = 0 THEN
        RAISE EXCEPTION 'content delivery visibility rewrite failed for %', v_signature;
      END IF;
      EXECUTE v_rewritten;
    ELSIF position(v_new_order IN v_definition) = 0 THEN
      RAISE EXCEPTION 'content delivery visibility order precondition failed for %', v_signature;
    END IF;
  END LOOP;
END;
$migration$;

REVOKE ALL ON FUNCTION public.list_mobile_content(
  uuid, text, text, integer, timestamptz, uuid, timestamptz
) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.get_mobile_content(uuid, uuid, timestamptz)
  FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.record_mobile_content_event(
  uuid, uuid, integer, text, text, text, timestamptz
) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.set_mobile_content_saved(
  uuid, uuid, integer, boolean, text, text, timestamptz
) FROM PUBLIC, anon, authenticated;

GRANT EXECUTE ON FUNCTION public.list_mobile_content(
  uuid, text, text, integer, timestamptz, uuid, timestamptz
) TO service_role;
GRANT EXECUTE ON FUNCTION public.get_mobile_content(uuid, uuid, timestamptz)
  TO service_role;
GRANT EXECUTE ON FUNCTION public.record_mobile_content_event(
  uuid, uuid, integer, text, text, text, timestamptz
) TO service_role;
GRANT EXECUTE ON FUNCTION public.set_mobile_content_saved(
  uuid, uuid, integer, boolean, text, text, timestamptz
) TO service_role;
