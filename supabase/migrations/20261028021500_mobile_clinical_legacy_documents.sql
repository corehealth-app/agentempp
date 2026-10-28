-- Additive, backend-only legal reacceptance for an actual admitted legacy
-- source. Never complete signup or mutate a clinical/calendar/profile fact.
BEGIN;
SET LOCAL search_path=pg_catalog;
DO $preflight$ BEGIN
 IF current_user<>'postgres'
  OR to_regprocedure('private.read_mobile_clinical_legacy_generation_at(uuid,timestamptz)') IS NULL
  OR to_regclass('private.mobile_clinical_legacy_admissions') IS NULL
  OR to_regclass('private.mobile_clinical_legacy_document_receipts') IS NOT NULL
  OR to_regprocedure('public.accept_mobile_clinical_legacy_documents(uuid,jsonb)') IS NOT NULL THEN
  RAISE EXCEPTION 'legacy_documents_requires_known_source' USING ERRCODE='42501';END IF;
END $preflight$;
CREATE TABLE private.mobile_clinical_legacy_document_receipts(
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 user_id uuid NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
 operation_key uuid NOT NULL,
 generation uuid NOT NULL,
 epoch uuid NOT NULL,
 command jsonb NOT NULL CHECK(jsonb_typeof(command)='object'),
 command_hash text COLLATE "C" NOT NULL CHECK(command_hash=encode(extensions.digest(command::text,'sha256'),'hex')),
 requirement_set_id uuid NOT NULL REFERENCES public.onboarding_legal_requirement_sets(id) ON DELETE RESTRICT,
 policy_evidence jsonb NOT NULL CHECK(jsonb_typeof(policy_evidence)='object'),
 accepted_at timestamptz NOT NULL CHECK(isfinite(accepted_at) AND extract(year FROM accepted_at AT TIME ZONE 'UTC') BETWEEN 1 AND 9999),
 UNIQUE(user_id,operation_key),
 FOREIGN KEY(user_id,generation) REFERENCES private.mobile_clinical_legacy_admissions(user_id,generation) ON DELETE CASCADE
);
ALTER TABLE private.mobile_clinical_legacy_document_receipts ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE private.mobile_clinical_legacy_document_receipts FROM PUBLIC,anon,authenticated,service_role;
CREATE TRIGGER mobile_clinical_legacy_document_receipt_immutable BEFORE UPDATE OR DELETE
 ON private.mobile_clinical_legacy_document_receipts FOR EACH ROW
 EXECUTE FUNCTION private.mobile_clinical_evidence_immutable();

CREATE FUNCTION private.mobile_clinical_legacy_document_receipt_wire(
 p_row private.mobile_clinical_legacy_document_receipts) RETURNS jsonb
LANGUAGE sql STABLE SECURITY INVOKER SET search_path=pg_catalog AS $$
 SELECT jsonb_build_object('version',1,'user_id',(p_row).user_id,'operation_key',(p_row).operation_key,
  'receipt',jsonb_build_object('id',(p_row).id,'locale',(p_row).command->'locale',
   'accepted_at',to_char((p_row).accepted_at AT TIME ZONE 'UTC','YYYY-MM-DD"T"HH24:MI:SS.US"Z"'),
   'document_actions',(p_row).policy_evidence->'actions'))
$$;

CREATE FUNCTION private.accept_mobile_clinical_legacy_documents(p_user_id uuid,p_command jsonb)
RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY INVOKER SET search_path=pg_catalog AS $$
DECLARE k uuid;v_locale text;actions jsonb;canonical jsonb;authority jsonb;observed timestamptz;
 receipt private.mobile_clinical_legacy_document_receipts%ROWTYPE;
 requirement public.onboarding_legal_requirement_sets%ROWTYPE;documents public.onboarding_legal_documents[];
 account_locale text;completed boolean;marker timestamptz;evidence jsonb;doc_count integer;
BEGIN
 PERFORM private.assert_trusted_backend();
 IF jsonb_typeof(p_command) IS DISTINCT FROM 'object' OR octet_length(p_command::text)>16384 THEN
  RAISE EXCEPTION 'invalid_mobile_legacy_document_command' USING ERRCODE='22023';END IF;
 IF NOT(p_command ?& ARRAY['version','operation_key','locale','document_actions'])
  OR (SELECT count(*) FROM jsonb_object_keys(p_command))<>4
  OR p_command->'version' IS DISTINCT FROM '1'::jsonb
  OR jsonb_typeof(p_command->'operation_key') IS DISTINCT FROM 'string'
  OR jsonb_typeof(p_command->'locale') IS DISTINCT FROM 'string'
  OR jsonb_typeof(p_command->'document_actions') IS DISTINCT FROM 'array' THEN
  RAISE EXCEPTION 'invalid_mobile_legacy_document_command' USING ERRCODE='22023';END IF;
 IF p_command->>'operation_key' !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
  OR p_command->>'locale' NOT IN('pt-BR','en-US')
  OR jsonb_array_length(p_command->'document_actions') NOT BETWEEN 1 AND 16
  OR EXISTS(SELECT 1 FROM jsonb_array_elements(p_command->'document_actions') a WHERE jsonb_typeof(a)<>'object') THEN
  RAISE EXCEPTION 'invalid_mobile_legacy_document_command' USING ERRCODE='22023';END IF;
 k:=(p_command->>'operation_key')::uuid;v_locale:=p_command->>'locale';
 IF EXISTS(SELECT 1 FROM jsonb_array_elements(p_command->'document_actions') a
  WHERE NOT(a ?& ARRAY['document_key','version','locale','content_hash','action'])
   OR (SELECT count(*) FROM jsonb_object_keys(a))<>5
   OR EXISTS(SELECT 1 FROM jsonb_each(a) v WHERE jsonb_typeof(v.value)<>'string')
   OR a->>'document_key' !~ '^[a-z][a-z0-9_]{0,99}$' OR a->>'document_key' ~ '^dev_'
   OR a->>'version' !~ '^[A-Za-z0-9._-]{1,64}$' OR a->>'locale'<>v_locale
   OR a->>'content_hash' !~ '^[0-9a-f]{64}$'
   OR a->>'action' NOT IN('acceptance','acknowledgement','consent'))
  OR jsonb_array_length(p_command->'document_actions')<>(SELECT count(DISTINCT a->>'document_key')
   FROM jsonb_array_elements(p_command->'document_actions') a) THEN
  RAISE EXCEPTION 'invalid_mobile_legacy_document_actions' USING ERRCODE='22023';END IF;
 SELECT jsonb_agg(a ORDER BY (a->>'document_key') COLLATE "C") INTO actions
 FROM jsonb_array_elements(p_command->'document_actions') a;
 canonical:=p_command||jsonb_build_object('operation_key',k,'document_actions',actions);
 PERFORM private.mobile_reevaluation_lock_owner(p_user_id);
 SELECT * INTO receipt FROM private.mobile_clinical_legacy_document_receipts r WHERE r.user_id=p_user_id AND r.operation_key=k;
 IF FOUND THEN
  IF receipt.command IS DISTINCT FROM canonical THEN
   RAISE EXCEPTION 'mobile_legacy_document_operation_conflict' USING ERRCODE='40001';END IF;
  -- Original durable acknowledgement precedes epoch/reset/publication checks.
  RETURN private.mobile_clinical_legacy_document_receipt_wire(receipt);
 END IF;
 SELECT u.locale,p.onboarding_completed,p.onboarding_completed_at INTO account_locale,completed,marker
 FROM public.users u JOIN public.user_profiles p ON p.user_id=u.id
 WHERE u.id=p_user_id AND u.status='active' FOR UPDATE OF u,p NOWAIT;
 IF NOT FOUND OR completed IS DISTINCT FROM true OR account_locale IS DISTINCT FROM v_locale THEN
  RAISE EXCEPTION 'mobile_legacy_document_context_changed' USING ERRCODE='40001';END IF;
 -- Same order/fence as signup. SHARE permits an inverse publisher/FK wait.
 LOCK TABLE public.onboarding_legal_documents IN EXCLUSIVE MODE;
 LOCK TABLE public.onboarding_legal_requirement_sets IN EXCLUSIVE MODE;
 observed:=clock_timestamp();
 authority:=private.read_mobile_clinical_legacy_generation_at(p_user_id,observed);
 IF authority IS NULL OR authority->>'kind'<>'legacy_transition'
  OR (authority->>'profile_completed_marker')::timestamptz IS DISTINCT FROM marker THEN
  RAISE EXCEPTION 'mobile_legacy_document_context_changed' USING ERRCODE='40001';END IF;
 SELECT q.* INTO requirement FROM public.onboarding_legal_requirement_sets q
 WHERE q.locale=v_locale AND q.publication_status='published' AND q.effective_at<=observed AND q.published_at<=observed
 ORDER BY q.effective_at DESC,q.published_at DESC,q.id DESC LIMIT 1;
 IF requirement.id IS NULL THEN
  RAISE EXCEPTION 'onboarding_documents_unavailable' USING ERRCODE='23514';END IF;
 SELECT array_agg(d::public.onboarding_legal_documents ORDER BY d.document_key COLLATE "C") INTO documents FROM (
  SELECT DISTINCT ON(d.document_key) d.* FROM public.onboarding_legal_documents d
  WHERE d.locale=v_locale AND d.document_key=ANY(requirement.document_keys) AND d.publication_status='published'
   AND d.effective_at<=observed AND d.published_at<=observed
  ORDER BY d.document_key,d.effective_at DESC,d.published_at DESC,d.id DESC
 ) d;
 doc_count:=coalesce(cardinality(documents),0);
 IF doc_count<>cardinality(requirement.document_keys) OR doc_count NOT BETWEEN 1 AND 16
  OR EXISTS(SELECT 1 FROM unnest(documents) d WHERE d.required IS DISTINCT FROM true) THEN
  RAISE EXCEPTION 'onboarding_documents_unavailable' USING ERRCODE='23514';END IF;
 IF jsonb_array_length(actions)<>doc_count OR EXISTS(
  SELECT 1 FROM jsonb_array_elements(actions) a LEFT JOIN unnest(documents) d
   ON d.document_key=a->>'document_key' AND d.version=a->>'version' AND d.locale=a->>'locale'
    AND d.content_hash=a->>'content_hash' AND d.action_type=a->>'action' WHERE d.id IS NULL) THEN
  RAISE EXCEPTION 'onboarding_document_version_mismatch' USING ERRCODE='23514';END IF;
 INSERT INTO public.user_onboarding_legal_actions(user_id,legal_document_id,document_key,version,locale,content_hash,purpose,action_type,acted_at,created_at)
 SELECT p_user_id,d.id,d.document_key,d.version,d.locale,d.content_hash,d.purpose,d.action_type,observed,observed FROM unnest(documents) d
 ON CONFLICT(user_id,legal_document_id) DO NOTHING;
 SELECT jsonb_build_object('requirement',to_jsonb(requirement),'actions',jsonb_agg(jsonb_build_object(
  'document_key',d.document_key,'version',d.version,'locale',d.locale,'content_hash',d.content_hash,
  'purpose',d.purpose,'action',d.action_type,'acted_at',to_char(a.acted_at AT TIME ZONE 'UTC','YYYY-MM-DD"T"HH24:MI:SS.US"Z"'))
  ORDER BY d.document_key COLLATE "C")) INTO evidence
 FROM unnest(documents) d JOIN public.user_onboarding_legal_actions a ON a.user_id=p_user_id AND a.legal_document_id=d.id;
 INSERT INTO private.mobile_clinical_legacy_document_receipts(user_id,operation_key,generation,epoch,command,command_hash,
  requirement_set_id,policy_evidence,accepted_at)
 VALUES(p_user_id,k,(authority->>'generation')::uuid,(authority->>'epoch')::uuid,canonical,
  encode(extensions.digest(canonical::text,'sha256'),'hex'),requirement.id,evidence,observed) RETURNING * INTO receipt;
 RETURN private.mobile_clinical_legacy_document_receipt_wire(receipt);
END $$;

CREATE FUNCTION public.accept_mobile_clinical_legacy_documents(p_user_id uuid,p_command jsonb)
RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path=pg_catalog AS $$
DECLARE message text;detail text;hint text;
BEGIN
 PERFORM private.assert_trusted_backend();
 RETURN private.accept_mobile_clinical_legacy_documents(p_user_id,p_command);
EXCEPTION WHEN serialization_failure THEN
 IF current_setting('request.path',true)='/rpc/accept_mobile_clinical_legacy_documents'
  AND current_setting('request.method',true) IN('POST','GET','HEAD') THEN
  GET STACKED DIAGNOSTICS message=MESSAGE_TEXT,detail=PG_EXCEPTION_DETAIL,hint=PG_EXCEPTION_HINT;
  RAISE SQLSTATE 'PGRST' USING MESSAGE=jsonb_build_object('code','40001','message',message,
   'details',nullif(detail,''),'hint',nullif(hint,''))::text,DETAIL='{"status":409,"headers":{}}';
 END IF;
 RAISE;
END $$;
REVOKE ALL ON FUNCTION private.mobile_clinical_legacy_document_receipt_wire(private.mobile_clinical_legacy_document_receipts),
 private.accept_mobile_clinical_legacy_documents(uuid,jsonb),public.accept_mobile_clinical_legacy_documents(uuid,jsonb)
 FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.accept_mobile_clinical_legacy_documents(uuid,jsonb) TO service_role;

-- Narrow defense: an actually admitted completed legacy profile with unknown
-- old timestamp cannot enter the fresh-signup branch. Keyed original receipts
-- still replay before reaching this function; unadmitted historical semantics
-- remain unchanged. Preserve the function's existing owner/ACL/transport body.
DO $guard$
DECLARE source text;needle text;replacement text;
BEGIN
 source:=pg_get_functiondef('public.complete_mobile_onboarding_atomic(uuid,jsonb)'::regprocedure);
 needle:=E'  v_now:=clock_timestamp();\n\n  SELECT requirement_set.document_keys';
 replacement:=E'  v_now:=clock_timestamp();\n  IF v_existing_completed IS TRUE AND v_existing_completion IS NULL\n   AND private.read_mobile_clinical_legacy_generation_at(p_user_id,v_now) IS NOT NULL THEN\n   RAISE EXCEPTION ''mobile_legacy_signup_already_completed'' USING ERRCODE=''40001'';\n  END IF;\n\n  SELECT requirement_set.document_keys';
 IF (length(source)-length(replace(source,needle,'')))/length(needle)<>1 THEN
  RAISE EXCEPTION 'legacy_documents_signup_guard_source_changed' USING ERRCODE='40001';END IF;
 EXECUTE replace(source,needle,replacement);
END $guard$;
COMMIT;
