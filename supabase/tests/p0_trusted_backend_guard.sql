BEGIN;

-- Exercise the internal guard independently from the permanent function ACL.
GRANT EXECUTE ON FUNCTION public.set_global_config(text, jsonb) TO authenticated;

SET LOCAL ROLE authenticated;
SELECT set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-0000-0000-000000000201","role":"authenticated"}',
  true
);

DO $test$
DECLARE
  v_denied boolean := false;
BEGIN
  BEGIN
    PERFORM public.set_global_config('p0_guard_probe', 'true'::jsonb);
  EXCEPTION
    WHEN insufficient_privilege THEN
      v_denied := true;
  END;

  IF NOT v_denied THEN
    RAISE EXCEPTION 'administrative RPC accepted an authenticated patient session';
  END IF;
END;
$test$;

RESET ROLE;
SET LOCAL ROLE service_role;
SELECT set_config(
  'request.jwt.claims',
  '{"role":"service_role"}',
  true
);
SELECT public.set_global_config('p0_guard_probe', 'true'::jsonb);

RESET ROLE;
ROLLBACK;
