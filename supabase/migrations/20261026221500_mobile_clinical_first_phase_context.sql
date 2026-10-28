-- Dedicated later-entry capture. Read-only clinical facts, no fabricated FULL,
-- signup origin, episode, target, operation receipt or automatic assignment.
BEGIN;
SET LOCAL search_path=pg_catalog;
DO $$ BEGIN
 IF current_user<>'postgres' OR to_regprocedure('private.capture_mobile_clinical_context_at(uuid,text,uuid,timestamptz)') IS NULL THEN
  RAISE EXCEPTION 'first_phase_requires_clinical_capture' USING ERRCODE='42501'; END IF;
END $$;
CREATE FUNCTION private.capture_mobile_clinical_first_phase_at(p_user_id uuid,p_observed_at timestamptz)
RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY INVOKER SET search_path=pg_catalog SET timezone='UTC' AS $$
DECLARE packet jsonb;facts jsonb;source jsonb;day date;effective date;deadline timestamptz;observed timestamptz;
BEGIN
 PERFORM private.assert_trusted_backend();
 -- Reuse factual locks/canonicalization, not an APPLICATION write or source.
 packet:=private.capture_mobile_clinical_context_at(p_user_id,'APPLICATION',NULL,p_observed_at);
 facts:=packet->'facts';source:=facts#>'{protocol_authority,phase_origin}';
 IF NOT EXISTS(SELECT 1 FROM public.users WHERE id=p_user_id AND status='active' AND wpp IS NULL)
  OR facts#>>'{profile,current_protocol}' IS NOT NULL OR facts#>>'{profile,deficit_level}' IS NOT NULL
  OR source->>'kind' IS DISTINCT FROM 'confirmed_no_plan'
  OR source->>'signupGeneration' IS DISTINCT FROM facts#>>'{anchor,signup_generation}'
  OR source->>'signupEpoch' IS DISTINCT FROM facts#>>'{anchor,signup_epoch}'
  OR source->>'completedAt' IS DISTINCT FROM facts#>>'{profile,onboarding_completed_at}'
  OR facts#>'{protocol_authority,episode}' IS DISTINCT FROM 'null'::jsonb
  OR facts#>'{protocol_authority,signup_origin}' IS DISTINCT FROM 'null'::jsonb THEN
  RAISE EXCEPTION 'mobile_clinical_first_phase_unavailable' USING ERRCODE='40001'; END IF;
 day:=(facts->>'calculation_date')::date;
 effective:=day+CASE WHEN coalesce((facts#>>'{day,day_closed}')::boolean,false) THEN 1 ELSE 0 END;
 -- An unconfirmed REGULAR photo candidate is not accepted current BF proof.
 facts:=jsonb_set(facts,'{protocol_authority,body_fat_candidate}','null');
 facts:=facts||jsonb_build_object('first_phase',jsonb_build_object('effective_date',effective));
 observed:=(packet->>'observed_at')::timestamptz;
 deadline:=least((packet->>'valid_until')::timestamptz,observed+interval '15minutes');
 RETURN jsonb_build_object('version',1,'user_id',p_user_id,'review_kind','FIRST_PHASE','cycle_id',NULL,
  'observed_at',packet->'observed_at','valid_until',to_char(deadline AT TIME ZONE 'UTC','YYYY-MM-DD"T"HH24:MI:SS.US"Z"'),
  'facts',facts,'context_hash',encode(extensions.digest(jsonb_build_object('version',1,
   'rule_version','clinical-first-phase-v1','scope','FIRST_PHASE','facts',facts)::text,'sha256'),'hex'));
END $$;
CREATE FUNCTION public.get_mobile_clinical_first_phase_context(p_user_id uuid)
RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path=pg_catalog SET lock_timeout='2s' AS $$
BEGIN
 PERFORM private.assert_trusted_backend();
 RETURN private.capture_mobile_clinical_first_phase_at(p_user_id,NULL);
END $$;
REVOKE ALL ON FUNCTION private.capture_mobile_clinical_first_phase_at(uuid,timestamptz),
 public.get_mobile_clinical_first_phase_context(uuid) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.get_mobile_clinical_first_phase_context(uuid) TO service_role;
COMMIT;
