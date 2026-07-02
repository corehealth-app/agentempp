-- ============================================================================
-- Remove SQL daily closer legado
-- ============================================================================
-- O fechamento diário real roda no worker Inngest `daily-closer`.
-- A RPC SQL `daily_close_user` deveria ter sido removida em 20260504165600,
-- mas ainda apareceu no banco live, quebrada por chamar `mpp_level_for_xp`.
-- Esta migration é idempotente: revoga execução pública se a função existir e
-- remove o código morto para evitar falhas operacionais e manutenção ambígua.

DO $$
BEGIN
  IF EXISTS (
    SELECT 1
    FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public'
      AND p.proname = 'daily_close_user'
      AND pg_get_function_identity_arguments(p.oid) = 'p_user_id uuid, p_date date'
  ) THEN
    REVOKE EXECUTE ON FUNCTION public.daily_close_user(uuid, date)
      FROM PUBLIC, anon, authenticated;
  END IF;
END;
$$;

DROP FUNCTION IF EXISTS public.daily_close_all(date);
DROP FUNCTION IF EXISTS public.daily_close_user(uuid, date);
DROP FUNCTION IF EXISTS public.mpp_level_for_xp(integer);
