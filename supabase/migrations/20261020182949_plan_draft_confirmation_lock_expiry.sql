-- Recheck both deadlines after the confirmation's existing locks.
-- Reproduced: a draft or requested plan validity can expire while waiting on
-- public.users and still be confirmed using the entry clock. Terminal replay,
-- input/status/error priorities, contracts and the legacy save remain intact.
-- Local native causal RED: two real blocked confirmations past their deadlines.
DO $migration$
DECLARE
  target constant regprocedure := 'public.confirm_plan_draft_atomic(uuid,uuid,integer,timestamptz,text)'::regprocedure;
  original text;
  changed text;
  definition text;
  catalogue jsonb;
  actual jsonb;
  digest text;
  needle constant text := '  IF v_draft.expires_at <= v_now THEN';
  addition constant text := $addition$  -- Domain, patient and draft locks may have outlived either deadline.
  -- Keep terminal replay above this refresh; a replay never renews the plan.
  v_now := clock_timestamp();
  IF p_valid_until IS NOT NULL AND p_valid_until <= v_now THEN
    RAISE EXCEPTION 'invalid plan draft confirmation' USING ERRCODE = '22023';
  END IF;
$addition$;
BEGIN
  SELECT p.prosrc,pg_catalog.to_jsonb(p)-'prosrc',pg_catalog.pg_get_functiondef(p.oid)
    INTO STRICT original,catalogue,definition
    FROM pg_catalog.pg_proc p WHERE p.oid=target;
  IF catalogue->>'prosecdef'<>'true'
    OR catalogue->>'provolatile'<>'v'
    OR (SELECT l.lanname FROM pg_catalog.pg_language l WHERE l.oid=(catalogue->>'prolang')::oid)<>'plpgsql'
    OR pg_catalog.pg_get_userbyid((catalogue->>'proowner')::oid)<>'postgres'
    OR catalogue->'proconfig' IS DISTINCT FROM '["search_path=pg_catalog, public, private, pg_temp"]'::jsonb
    OR NOT pg_catalog.has_function_privilege('service_role',target,'EXECUTE')
    OR pg_catalog.has_function_privilege('anon',target,'EXECUTE')
    OR pg_catalog.has_function_privilege('authenticated',target,'EXECUTE')
  THEN RAISE EXCEPTION 'plan draft confirmation metadata changed'; END IF;
  digest:=pg_catalog.encode(extensions.digest(pg_catalog.convert_to(original,'UTF8'),'sha256'),'hex');
  IF digest='dffea7a75edfd43d5ea3e20ce20805744f23ddbb3775988ace3fe672fb185cab' THEN RETURN; END IF;
  IF digest<>'734b55f16a42d283146002ba35d5d42805063752a7a8156329d4204501d18c4c'
    OR (pg_catalog.length(original)-pg_catalog.length(pg_catalog.replace(original,needle,'')))/pg_catalog.length(needle)<>1
  THEN RAISE EXCEPTION 'plan draft confirmation source changed'; END IF;
  changed:=pg_catalog.replace(original,needle,addition||needle);
  IF pg_catalog.encode(extensions.digest(pg_catalog.convert_to(changed,'UTF8'),'sha256'),'hex')<>'dffea7a75edfd43d5ea3e20ce20805744f23ddbb3775988ace3fe672fb185cab'
  THEN RAISE EXCEPTION 'plan draft confirmation patch mismatch'; END IF;
  EXECUTE pg_catalog.replace(definition,original,changed);
  SELECT pg_catalog.to_jsonb(p)-'prosrc' INTO STRICT actual FROM pg_catalog.pg_proc p WHERE p.oid=target;
  IF actual IS DISTINCT FROM catalogue OR
    (SELECT p.prosrc FROM pg_catalog.pg_proc p WHERE p.oid=target) IS DISTINCT FROM changed
  THEN RAISE EXCEPTION 'plan draft confirmation patch changed its contract'; END IF;
END $migration$;
