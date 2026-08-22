ALTER TABLE public.users
  ADD COLUMN auth_user_id uuid;

ALTER TABLE public.users
  ALTER COLUMN wpp DROP NOT NULL;

ALTER TABLE public.users
  ADD CONSTRAINT users_auth_user_id_key UNIQUE (auth_user_id);

ALTER TABLE public.users
  ADD CONSTRAINT users_auth_user_id_fkey
  FOREIGN KEY (auth_user_id)
  REFERENCES auth.users(id)
  ON DELETE SET NULL;

COMMENT ON COLUMN public.users.auth_user_id IS
  'Nullable link to a confirmed email-first Supabase Auth identity. Legacy users remain unlinked.';
COMMENT ON COLUMN public.users.wpp IS
  'Legacy WhatsApp identity. Null for app-first BodyFlow accounts.';

ALTER TABLE public.admin_users
  DROP CONSTRAINT admin_users_role_check;

UPDATE public.admin_users
SET role = CASE role
  WHEN 'admin' THEN 'master_admin'
  WHEN 'editor' THEN 'content_editor'
  WHEN 'viewer' THEN 'support'
  ELSE role
END;

ALTER TABLE public.admin_users
  ALTER COLUMN role SET DEFAULT 'support';

ALTER TABLE public.admin_users
  ADD CONSTRAINT admin_users_role_check
  CHECK (role IN (
    'support',
    'content_editor',
    'nutrition_admin',
    'operations_admin',
    'master_admin'
  ));

CREATE OR REPLACE FUNCTION public.is_admin()
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, public, pg_temp
AS $$
  SELECT EXISTS(
    SELECT 1
    FROM public.admin_users
    WHERE id = auth.uid()
      AND role IN (
        'support',
        'content_editor',
        'nutrition_admin',
        'operations_admin',
        'master_admin'
      )
  );
$$;

CREATE OR REPLACE FUNCTION public.admin_role()
RETURNS text
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, public, pg_temp
AS $$
  SELECT role
  FROM public.admin_users
  WHERE id = auth.uid();
$$;

REVOKE ALL ON FUNCTION public.is_admin() FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.admin_role() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.is_admin() TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.admin_role() TO authenticated, service_role;

CREATE OR REPLACE FUNCTION private.enforce_patient_account_separation()
RETURNS trigger
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = pg_catalog, public, pg_temp
AS $$
BEGIN
  IF NEW.auth_user_id IS NOT NULL
    AND EXISTS (
      SELECT 1
      FROM public.admin_users
      WHERE id = NEW.auth_user_id
    ) THEN
    RAISE EXCEPTION 'an admin identity cannot also be a patient identity'
      USING ERRCODE = '23514',
            CONSTRAINT = 'users_auth_user_id_not_admin';
  END IF;

  RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION private.enforce_admin_account_separation()
RETURNS trigger
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = pg_catalog, public, pg_temp
AS $$
BEGIN
  IF EXISTS (
    SELECT 1
    FROM public.users
    WHERE auth_user_id = NEW.id
  ) THEN
    RAISE EXCEPTION 'a patient identity cannot also be an admin identity'
      USING ERRCODE = '23514',
            CONSTRAINT = 'admin_users_id_not_patient';
  END IF;

  RETURN NEW;
END;
$$;

REVOKE ALL ON FUNCTION private.enforce_patient_account_separation()
  FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION private.enforce_admin_account_separation()
  FROM PUBLIC, anon, authenticated, service_role;

CREATE TRIGGER users_enforce_account_separation
  BEFORE INSERT OR UPDATE OF auth_user_id ON public.users
  FOR EACH ROW
  EXECUTE FUNCTION private.enforce_patient_account_separation();

CREATE TRIGGER admin_users_enforce_account_separation
  BEFORE INSERT OR UPDATE OF id ON public.admin_users
  FOR EACH ROW
  EXECUTE FUNCTION private.enforce_admin_account_separation();

CREATE OR REPLACE FUNCTION public.bootstrap_patient_profile()
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public, auth, pg_temp
AS $$
DECLARE
  v_auth_user_id uuid := auth.uid();
  v_email text;
  v_email_confirmed_at timestamptz;
  v_domain_user_id uuid;
BEGIN
  IF v_auth_user_id IS NULL THEN
    RAISE EXCEPTION 'authenticated user required'
      USING ERRCODE = '42501';
  END IF;

  PERFORM pg_advisory_xact_lock(hashtextextended(v_auth_user_id::text, 0));

  SELECT email, email_confirmed_at
  INTO v_email, v_email_confirmed_at
  FROM auth.users
  WHERE id = v_auth_user_id
    AND deleted_at IS NULL;

  IF NOT FOUND OR v_email IS NULL OR v_email_confirmed_at IS NULL THEN
    RAISE EXCEPTION 'confirmed email required'
      USING ERRCODE = '42501';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM public.admin_users
    WHERE id = v_auth_user_id
  ) THEN
    RAISE EXCEPTION 'admin and patient accounts must be separate'
      USING ERRCODE = '42501';
  END IF;

  SELECT id
  INTO v_domain_user_id
  FROM public.users
  WHERE auth_user_id = v_auth_user_id;

  IF v_domain_user_id IS NULL THEN
    IF EXISTS (
      SELECT 1
      FROM public.users
      WHERE email = v_email
    ) THEN
      RAISE EXCEPTION 'existing domain user requires explicit identity migration'
        USING ERRCODE = '23505',
              CONSTRAINT = 'users_email_key';
    END IF;

    INSERT INTO public.users (auth_user_id, email, wpp)
    VALUES (v_auth_user_id, v_email, NULL)
    RETURNING id INTO v_domain_user_id;
  END IF;

  INSERT INTO public.user_profiles (user_id)
  VALUES (v_domain_user_id)
  ON CONFLICT (user_id) DO NOTHING;

  INSERT INTO public.user_progress (user_id)
  VALUES (v_domain_user_id)
  ON CONFLICT (user_id) DO NOTHING;

  RETURN v_domain_user_id;
END;
$$;

REVOKE ALL ON FUNCTION public.bootstrap_patient_profile()
  FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.bootstrap_patient_profile()
  TO authenticated, service_role;

COMMENT ON FUNCTION public.bootstrap_patient_profile() IS
  'Idempotently creates an empty app-first domain profile after email confirmation; never links legacy users.';

DROP POLICY IF EXISTS rules_admin_read ON public.agent_rules;
DROP POLICY IF EXISTS rules_admin_write ON public.agent_rules;
DROP POLICY IF EXISTS rules_admin_update ON public.agent_rules;
CREATE POLICY rules_admin_read
  ON public.agent_rules
  FOR SELECT
  TO authenticated
  USING (public.is_admin());
CREATE POLICY rules_admin_write
  ON public.agent_rules
  FOR INSERT
  TO authenticated
  WITH CHECK (
    public.admin_role() = 'master_admin'
    OR (
      public.admin_role() = 'content_editor'
      AND status <> 'active'
    )
  );
CREATE POLICY rules_admin_update
  ON public.agent_rules
  FOR UPDATE
  TO authenticated
  USING (public.admin_role() IN ('content_editor', 'master_admin'))
  WITH CHECK (
    public.admin_role() = 'master_admin'
    OR (
      public.admin_role() = 'content_editor'
      AND status <> 'active'
    )
  );

DROP POLICY IF EXISTS configs_admin_read ON public.agent_configs;
DROP POLICY IF EXISTS configs_admin_write ON public.agent_configs;
CREATE POLICY configs_admin_read
  ON public.agent_configs
  FOR SELECT
  TO authenticated
  USING (public.is_admin());
CREATE POLICY configs_admin_write
  ON public.agent_configs
  FOR ALL
  TO authenticated
  USING (public.admin_role() = 'master_admin')
  WITH CHECK (public.admin_role() = 'master_admin');

DROP POLICY IF EXISTS flags_admin_all ON public.feature_flags;
DROP POLICY IF EXISTS flags_admin_read ON public.feature_flags;
CREATE POLICY flags_admin_read
  ON public.feature_flags
  FOR SELECT
  TO authenticated
  USING (public.is_admin());
CREATE POLICY flags_admin_all
  ON public.feature_flags
  FOR ALL
  TO authenticated
  USING (public.admin_role() IN ('operations_admin', 'master_admin'))
  WITH CHECK (public.admin_role() IN ('operations_admin', 'master_admin'));

DROP POLICY IF EXISTS credentials_admin_all ON public.service_credentials;
CREATE POLICY credentials_admin_all
  ON public.service_credentials
  FOR ALL
  TO authenticated
  USING (public.admin_role() = 'master_admin')
  WITH CHECK (public.admin_role() = 'master_admin');

DROP POLICY IF EXISTS admin_users_self_read ON public.admin_users;
DROP POLICY IF EXISTS admin_users_admin_write ON public.admin_users;
CREATE POLICY admin_users_self_read
  ON public.admin_users
  FOR SELECT
  TO authenticated
  USING (id = auth.uid() OR public.is_admin());
CREATE POLICY admin_users_admin_write
  ON public.admin_users
  FOR ALL
  TO authenticated
  USING (public.admin_role() = 'master_admin')
  WITH CHECK (public.admin_role() = 'master_admin');
