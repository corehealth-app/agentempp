-- Local synthetic provenance, using the installed production schema. No fake RPCs.
CREATE SCHEMA m3b_cycle_test;
REVOKE ALL ON SCHEMA m3b_cycle_test FROM PUBLIC, anon, authenticated, service_role;

CREATE FUNCTION m3b_cycle_test.ok(value boolean, label text) RETURNS void
LANGUAGE plpgsql SET search_path = pg_catalog AS $$
BEGIN
  IF value IS DISTINCT FROM true THEN RAISE EXCEPTION 'M3B_ASSERT:%', label; END IF;
  RAISE NOTICE 'M3B_PASS:%', label;
END $$;

CREATE FUNCTION m3b_cycle_test.complete_again(owner_id uuid, request_key text) RETURNS jsonb
LANGUAGE plpgsql SET search_path=pg_catalog AS $$
DECLARE observation jsonb; admission jsonb; submission jsonb; doc public.onboarding_legal_documents%ROWTYPE;
BEGIN
  SELECT d.* INTO STRICT doc FROM public.onboarding_legal_documents d WHERE id=m3b_cycle_test.uid(201);
  submission:=jsonb_build_object('name','M3B synthetic QA','locale','pt-BR','country','BR',
    'timezone','America/Sao_Paulo','sex','masculino','birth_date','1990-01-01','height_cm',180,
    'weight_kg',80,'body_fat_percent',24,'objective','recomposicao','activity_level','moderado',
    'training_frequency',4,'hunger_level','moderada','wake_time','07:00','bedtime','23:00',
    'food_organization','sim','persona','focus','document_actions',jsonb_build_array(jsonb_build_object(
      'document_key',doc.document_key,'version',doc.version,'locale',doc.locale,
      'content_hash',doc.content_hash,'action',doc.action_type)));
  observation:=public.observe_mobile_signup_strength_epoch(owner_id);
  admission:=public.admit_mobile_signup_strength_request(owner_id,request_key,repeat('c',64),
    (observation#>>'{observation,epoch}')::uuid)->'admission';
  RETURN public.complete_mobile_onboarding_keyed(owner_id,submission,'atomic',request_key,repeat('c',64),
    (admission->>'epoch')::uuid,(admission->>'admissionID')::uuid,NULL,NULL,NULL,NULL);
END $$;

CREATE FUNCTION m3b_cycle_test.throws(query text, expected_state text, label text) RETURNS void
LANGUAGE plpgsql SET search_path = pg_catalog AS $$
DECLARE actual text;
BEGIN
  BEGIN EXECUTE query;
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS actual = RETURNED_SQLSTATE;
    PERFORM m3b_cycle_test.ok(actual = expected_state, label); RETURN;
  END;
  RAISE EXCEPTION 'M3B_EXPECTED_ERROR:%', label;
END $$;

CREATE FUNCTION m3b_cycle_test.uid(n integer) RETURNS uuid LANGUAGE sql IMMUTABLE
SET search_path = pg_catalog AS $$
  SELECT ('b3b01000-0000-4000-8000-' || lpad(n::text, 12, '0'))::uuid
$$;

CREATE FUNCTION m3b_cycle_test.seed(n integer, completed_at timestamptz,
  zone text DEFAULT 'America/Sao_Paulo', with_proof boolean DEFAULT true) RETURNS uuid
LANGUAGE plpgsql SET search_path = pg_catalog AS $$
DECLARE owner_id uuid := m3b_cycle_test.uid(n); epoch_id uuid := gen_random_uuid();
  admission_id uuid := gen_random_uuid(); generation_id uuid := gen_random_uuid(); source_id uuid;
BEGIN
  INSERT INTO public.users(id,email,name,locale,timezone,country,status)
    VALUES(owner_id,'m3b-cycle-'||n::text||'@example.invalid','M3B synthetic QA',
      'pt-BR',zone,'BR','active');
  INSERT INTO public.user_profiles(user_id,onboarding_completed,onboarding_completed_at)
    VALUES(owner_id,completed_at IS NOT NULL,completed_at);
  IF completed_at IS NULL OR NOT with_proof THEN RETURN owner_id; END IF;
  INSERT INTO private.workout_strength_authority_epochs(user_id,epoch,changed_at)
    VALUES(owner_id,epoch_id,completed_at - interval '2 minutes');
  INSERT INTO private.mobile_signup_strength_request_admissions(
    user_id,request_key,request_hash,epoch,admission_id,admitted_at)
    VALUES(owner_id,'m3b-seed-'||n::text,repeat('a',64),epoch_id,admission_id,
      completed_at - interval '1 minute');
  INSERT INTO private.strength_week_scopes(user_id,generation,open_operation_namespace,
    open_operation_key,opened_at)
    VALUES(owner_id,generation_id,'mobile_signup_completion_v1',admission_id::text,completed_at);
  INSERT INTO private.strength_week_source_versions(user_id,generation,source_kind,fact,
    planned_days,operation_namespace,operation_key,observed_at,observed_timezone,effective_week_start)
    VALUES(owner_id,generation_id,'informed_frequency','value',4,
      'mobile_signup_completion_v1',admission_id::text,completed_at,zone,
      date_trunc('week',completed_at AT TIME ZONE zone)::date + 7)
    RETURNING source_version_id INTO source_id;
  INSERT INTO private.mobile_signup_strength_completion_receipts(user_id,admission_id,
    epoch,outcome,completion_path,completed_at,generation,frequency_source_version_id,
    completion_result,recorded_at)
    VALUES(owner_id,admission_id,epoch_id,'first_fresh','atomic',completed_at,generation_id,
      source_id,jsonb_build_object('user_id',owner_id,'onboarding_completed',true,
        'completed_at',completed_at),completed_at);
  RETURN owner_id;
END $$;

-- Preserve all original per-owner rows, excluding only the new operational tables.
CREATE FUNCTION m3b_cycle_test.original_state(owner_id uuid) RETURNS jsonb
LANGUAGE plpgsql SET search_path = pg_catalog AS $$
DECLARE relation record; rows jsonb; result jsonb := jsonb_build_object('public.users',
  (SELECT to_jsonb(u) FROM public.users u WHERE id = owner_id));
BEGIN
  FOR relation IN SELECT n.nspname,c.relname FROM pg_class c
    JOIN pg_namespace n ON n.oid=c.relnamespace
    WHERE n.nspname IN('public','private') AND c.relkind IN('r','p')
      AND c.relname NOT IN('mobile_reevaluation_cycles','mobile_reevaluation_start_keys')
      AND EXISTS(SELECT 1 FROM pg_attribute a WHERE a.attrelid=c.oid
        AND a.attname='user_id' AND a.attnum>0 AND NOT a.attisdropped)
    ORDER BY n.nspname,c.relname
  LOOP
    EXECUTE format('SELECT coalesce(jsonb_agg(to_jsonb(r) ORDER BY to_jsonb(r)::text),''[]'')
      FROM ONLY %I.%I r WHERE user_id=$1',relation.nspname,relation.relname) INTO rows USING owner_id;
    result := result || jsonb_build_object(relation.nspname||'.'||relation.relname,rows);
  END LOOP;
  RETURN result;
END $$;
REVOKE ALL ON ALL FUNCTIONS IN SCHEMA m3b_cycle_test FROM PUBLIC,anon,authenticated,service_role;
