-- New-server-only HTTP adapters. Originals retain their executable bodies,
-- signatures, grants, business guards and error contract for older clients.
BEGIN;
SET LOCAL lock_timeout='5s';
DO $install$
DECLARE sig text;pin text;fn record;target text;args text;body text;
BEGIN
 IF current_user<>'postgres' THEN RAISE EXCEPTION 'training_http_unknown_owner';END IF;
 FOR sig,pin IN SELECT * FROM (VALUES
  ('public.begin_training_execution_completion_authenticated(uuid,uuid,uuid,jsonb)','3ad19d334f39f6c3c5447ade716eb5a50ce53878fcd6676f2b6916c2a650b100'),
  ('public.cancel_training_execution_completion_authenticated(uuid,uuid,uuid,uuid,text)','37575159e77a34e6b6fd45eb349bd8d4717cee026e43820d1d76eb983a5ca1fe'),
  ('public.capture_training_execution_context_authenticated(uuid,uuid,uuid,uuid,uuid)','1783d6fedf76181e37f907079ac8b3ef4ccd7b05a4bb0a1042d8fa289a6f404f'),
  ('public.commit_training_execution_completion_authenticated(uuid,uuid,uuid,uuid,text,text,text,jsonb)','2e0513e90dbea0d9502ab07c83b561bd9172a66c8c1bb6f9e7e15b0578497591'),
  ('public.commit_training_execution_mutation_authenticated(uuid,uuid,uuid,jsonb,text,timestamp with time zone,jsonb)','6ce5127274bcaceb072c1248dae85942e5e3562d6832524d18ec0360dea0369a'),
  ('public.observe_training_execution_finish_authenticated(uuid,uuid,uuid,jsonb)','d7f68f4427d892653a9b07ddc843010138ac55d8a85c8397461e514c6dc57b87'),
  ('public.read_training_execution_completion_authenticated(uuid,uuid,uuid,uuid)','9670ca155fe549a7db7afddbc435695f8bc59d40e00d4b8b8eee2e54b4173934'),
  ('public.read_training_execution_home_authenticated(uuid,uuid,uuid,jsonb)','cdc1ce454391d2e6a29ad6505ecfee913a084ec63dbd00dfc15315829eb8a4e5'),
  ('public.read_training_execution_home_v2_authenticated(uuid,uuid,uuid,jsonb)','3c996974b249b8887cd16afa35afe80de253ba79b96366024633d89b55cb6f7b'),
  ('public.read_training_execution_state_v2_authenticated(uuid,uuid,uuid,uuid)','7bed52cf432412e1dd170b78c5cdc1afd60fb5d692d10caddaf5045e351adf3b'),
  ('public.reconcile_training_execution_progress_authenticated(uuid,uuid,uuid,jsonb)','60ce3b7980b6169ec2ab5de34c42513ed9e2ce9304014b46c6613748a2d9b492'),
  ('public.submit_training_execution_completion_authenticated(uuid,uuid,uuid,jsonb)','4faf031399928508e7541d8a9fc4e7411541066be1f67ecc2f94fd9030a78776'),
  ('public.withdraw_training_execution_finish_authenticated(uuid,uuid,uuid,jsonb)','c262ff2121776717512cae3ec3a7e8f8421e5ced555fd1d02d7e6cce2628e23e')
 ) expected(signature,hash) LOOP
  SELECT p.* INTO STRICT fn FROM pg_proc p WHERE p.oid=to_regprocedure(sig);
  target:=fn.proname||'_http';
  IF NOT fn.prosecdef OR fn.proretset OR fn.proargmodes IS NOT NULL
   OR fn.prorettype<>'jsonb'::regtype OR length(target)>63
   OR encode(sha256(convert_to(fn.prosrc,'UTF8')),'hex') IS DISTINCT FROM pin
   OR EXISTS(SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='public' AND p.proname=target)
   OR fn.proargnames IS NULL OR EXISTS(SELECT 1 FROM unnest(fn.proargnames) a WHERE a !~ '^p_[a-z_]+$') THEN
   RAISE EXCEPTION 'training_http_unknown_substrate:%',sig;END IF;
  SELECT string_agg(format('%I',a),',' ORDER BY pos) INTO args FROM unnest(fn.proargnames) WITH ORDINALITY x(a,pos);
  body:=format('BEGIN RETURN public.%I(%s); EXCEPTION WHEN serialization_failure THEN RAISE SQLSTATE ''PT409'' USING MESSAGE=''training_execution_conflict''; END',fn.proname,args);
  EXECUTE format('CREATE FUNCTION public.%I(%s) RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path=pg_catalog AS %L',target,pg_get_function_arguments(fn.oid),body);
  EXECUTE format('REVOKE ALL ON FUNCTION public.%I(%s) FROM PUBLIC,anon,authenticated,service_role',target,pg_get_function_identity_arguments(fn.oid));
  EXECUTE format('GRANT EXECUTE ON FUNCTION public.%I(%s) TO service_role',target,pg_get_function_identity_arguments(fn.oid));
  IF (SELECT encode(sha256(convert_to(prosrc,'UTF8')),'hex') FROM pg_proc WHERE oid=fn.oid) IS DISTINCT FROM pin THEN
   RAISE EXCEPTION 'training_http_original_changed:%',sig;END IF;
 END LOOP;
END $install$;
COMMIT;
