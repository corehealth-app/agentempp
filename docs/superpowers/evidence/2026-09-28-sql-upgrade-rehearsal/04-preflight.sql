-- Preflight before M1-M4. Read-only: it raises and changes nothing.
-- Run on the target immediately before applying, in the same session that
-- will apply the migrations. Any failure means: stop, do not apply.
\set ON_ERROR_STOP on
DO $preflight$
DECLARE
  r record;
  v_expected constant jsonb := jsonb_build_object(
    'media_assets_id_user_unique', 'CREATE UNIQUE INDEX media_assets_id_user_unique ON public.media_assets USING btree (id, user_id)',
    'messages_id_user_unique', 'CREATE UNIQUE INDEX messages_id_user_unique ON public.messages USING btree (id, user_id)',
    'uniq_prescriptions_request', 'CREATE UNIQUE INDEX uniq_prescriptions_request ON public.prescriptions USING btree (user_id, source_request_key) WHERE (source_request_key IS NOT NULL)'
  );
  v_name text;
BEGIN
  -- 1. The target is at the expected baseline: none of the M1-M4 objects exist.
  IF to_regclass('public.plan_drafts') IS NOT NULL THEN
    RAISE EXCEPTION 'PREFLIGHT: public.plan_drafts already exists (M2 applied or partial)';
  END IF;
  IF EXISTS (SELECT 1 FROM information_schema.columns
             WHERE table_schema = 'public' AND table_name = 'user_profiles'
               AND column_name IN ('weight_measured_at', 'weight_instant_source')) THEN
    RAISE EXCEPTION 'PREFLIGHT: user_profiles weight instant columns already exist (M1 applied or partial)';
  END IF;
  IF to_regprocedure('public.reset_user_conversation_atomic(uuid,boolean)') IS NOT NULL THEN
    RAISE EXCEPTION 'PREFLIGHT: reset_user_conversation_atomic(uuid, boolean) already exists (M4 applied or partial)';
  END IF;
  IF to_regprocedure('public.reset_user_conversation_atomic(uuid)') IS NULL THEN
    RAISE EXCEPTION 'PREFLIGHT: legacy reset_user_conversation_atomic(uuid) missing: baseline is not the expected one';
  END IF;

  -- 2. An index that M2 creates "IF NOT EXISTS" and that someone may have
  --    pre-built CONCURRENTLY must be valid, ready and exactly the expected
  --    definition. IF NOT EXISTS only checks the name: an invalid index left
  --    by a cancelled CONCURRENTLY build, or a different definition under the
  --    same name, would be silently kept.
  FOR v_name IN SELECT jsonb_object_keys(v_expected) LOOP
    SELECT i.indisvalid, i.indisready, pg_get_indexdef(i.indexrelid) AS def
    INTO r
    FROM pg_index i
    JOIN pg_class c ON c.oid = i.indexrelid
    WHERE c.relnamespace = 'public'::regnamespace AND c.relname = v_name;
    IF FOUND THEN
      IF NOT r.indisvalid OR NOT r.indisready THEN
        RAISE EXCEPTION 'PREFLIGHT: index % exists but is not valid/ready (valid=%, ready=%): drop it and rebuild CONCURRENTLY before applying',
          v_name, r.indisvalid, r.indisready;
      END IF;
      IF r.def <> v_expected->>v_name THEN
        RAISE EXCEPTION 'PREFLIGHT: index % exists with a different definition: %', v_name, r.def;
      END IF;
      RAISE NOTICE 'PREFLIGHT: index % pre-built, valid and equivalent', v_name;
    ELSE
      RAISE NOTICE 'PREFLIGHT: index % absent; M2 will build it (non-concurrently, table lock)', v_name;
    END IF;
  END LOOP;

  -- 3. No other session holds locks on the tables M1-M4 alter.
  FOR r IN
    SELECT l.relation::regclass AS rel, l.mode, a.pid, a.state
    FROM pg_locks l JOIN pg_stat_activity a ON a.pid = l.pid
    WHERE l.relation IN ('public.user_profiles'::regclass, 'public.media_assets'::regclass,
                         'public.messages'::regclass, 'public.prescriptions'::regclass,
                         'public.training_plans'::regclass)
      AND l.pid <> pg_backend_pid()
  LOOP
    RAISE EXCEPTION 'PREFLIGHT: % held in % by pid % (%)', r.rel, r.mode, r.pid, r.state;
  END LOOP;

  RAISE NOTICE 'PREFLIGHT OK';
END;
$preflight$;

-- Sizes that decide whether to pre-build the indexes CONCURRENTLY.
SELECT relname, n_live_tup
FROM pg_stat_user_tables
WHERE schemaname = 'public' AND relname IN ('media_assets', 'messages', 'prescriptions', 'user_profiles')
ORDER BY relname;
