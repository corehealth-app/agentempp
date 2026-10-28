-- Dormant atomic n10 signup entry. No public RPC, grant, route or activation.
-- Only explicit current legal actions and marked risks are saved before signup.
BEGIN;
SET LOCAL search_path=pg_catalog;
DO $$ BEGIN
 IF current_user<>'postgres' OR to_regprocedure('private.declare_mobile_health_risk_at(uuid,uuid,text[],timestamptz)') IS NULL
  OR to_regclass('private.mobile_signup_completion_intents') IS NULL THEN
  RAISE EXCEPTION 'mobile_signup_health_requires_private_authorities' USING ERRCODE='42501';
 END IF;
END $$;
CREATE TABLE private.mobile_signup_health_receipts (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 user_id uuid NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
 operation_key uuid NOT NULL,
 intent_id uuid NOT NULL,
 request_key text COLLATE "C" NOT NULL,
 epoch uuid NOT NULL,
 command jsonb NOT NULL CHECK(jsonb_typeof(command)='object'),
 command_hash text COLLATE "C" NOT NULL CHECK(command_hash=encode(extensions.digest(command::text,'sha256'),'hex')),
 requirement_set_id uuid NOT NULL REFERENCES public.onboarding_legal_requirement_sets(id) ON DELETE RESTRICT,
 policy_evidence jsonb NOT NULL CHECK(jsonb_typeof(policy_evidence)='object'),
 health_operation_key uuid NOT NULL,
 health_receipt_id uuid NOT NULL UNIQUE REFERENCES private.mobile_health_risk_receipts(id) ON DELETE CASCADE,
 admitted_at timestamptz NOT NULL CHECK(isfinite(admitted_at) AND extract(year FROM admitted_at AT TIME ZONE 'UTC') BETWEEN 1 AND 9999),
 UNIQUE(user_id,operation_key), UNIQUE(user_id,health_operation_key)
);
ALTER TABLE private.mobile_signup_health_receipts ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE private.mobile_signup_health_receipts FROM PUBLIC,anon,authenticated,service_role;
CREATE TRIGGER mobile_signup_health_receipt_immutable BEFORE UPDATE OR DELETE
 ON private.mobile_signup_health_receipts FOR EACH ROW EXECUTE FUNCTION private.mobile_health_receipt_immutable();

CREATE FUNCTION private.mobile_signup_health_receipt_wire(p_row private.mobile_signup_health_receipts)
RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY INVOKER SET search_path=pg_catalog AS $$
DECLARE h private.mobile_health_risk_receipts%ROWTYPE;
BEGIN
 SELECT * INTO h FROM private.mobile_health_risk_receipts
 WHERE id=p_row.health_receipt_id AND user_id=p_row.user_id AND operation_key=p_row.health_operation_key;
 IF NOT FOUND OR h.declared_at IS DISTINCT FROM p_row.admitted_at
  OR to_jsonb(h.items) IS DISTINCT FROM p_row.command->'risks' THEN
  RAISE EXCEPTION 'mobile_signup_health_receipt_inconsistent' USING ERRCODE='XX001';
 END IF;
 RETURN jsonb_build_object('version',1,'user_id',p_row.user_id,'operation_key',p_row.operation_key,
  'receipt',jsonb_build_object('id',p_row.id,'intent_id',p_row.intent_id,'request_key',p_row.request_key,
   'epoch',p_row.epoch,'locale',p_row.command->'locale','requirement_set_id',p_row.requirement_set_id,
   'document_actions',p_row.command->'document_actions','risks',p_row.command->'risks',
   'health_operation_key',p_row.health_operation_key,
   'admitted_at',to_char(p_row.admitted_at AT TIME ZONE 'UTC','YYYY-MM-DD"T"HH24:MI:SS.US"Z"')),
  'declaration',jsonb_build_object('version',1,'user_id',p_row.user_id,'receipt',private.mobile_health_receipt_wire(h),
   'state',private.mobile_health_state_wire(p_row.user_id)));
END $$;

CREATE FUNCTION private.admit_mobile_signup_health(p_user_id uuid,p_command jsonb)
RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY INVOKER SET search_path=pg_catalog AS $$
DECLARE k uuid;v_intent_id uuid;v_request_key text;v_locale text;items text[];canonical_items private.mobile_health_risk_code_v1[];
 canonical jsonb;actions jsonb;receipt private.mobile_signup_health_receipts%ROWTYPE;
 intent private.mobile_signup_completion_intents%ROWTYPE;current_epoch uuid;
 requirement public.onboarding_legal_requirement_sets%ROWTYPE;documents public.onboarding_legal_documents[];
 now_at timestamptz;health_key uuid;health jsonb;evidence jsonb;doc_count integer;
 completed boolean;completed_at timestamptz;
BEGIN
 PERFORM private.assert_trusted_backend();
 IF jsonb_typeof(p_command) IS DISTINCT FROM 'object' OR octet_length(p_command::text)>16384 THEN
  RAISE EXCEPTION 'invalid_mobile_signup_health_command' USING ERRCODE='22023';
 END IF;
 IF NOT (p_command ?& ARRAY['version','operation_key','intent_id','request_key','locale','document_actions','risks'])
  OR (SELECT count(*) FROM jsonb_object_keys(p_command))<>7 OR p_command->'version' IS DISTINCT FROM '1'::jsonb
  OR jsonb_typeof(p_command->'operation_key') IS DISTINCT FROM 'string'
  OR jsonb_typeof(p_command->'intent_id') IS DISTINCT FROM 'string'
  OR jsonb_typeof(p_command->'request_key') IS DISTINCT FROM 'string'
  OR jsonb_typeof(p_command->'locale') IS DISTINCT FROM 'string'
  OR jsonb_typeof(p_command->'document_actions') IS DISTINCT FROM 'array'
  OR jsonb_typeof(p_command->'risks') IS DISTINCT FROM 'array' THEN
  RAISE EXCEPTION 'invalid_mobile_signup_health_command' USING ERRCODE='22023';
 END IF;
 IF p_command->>'operation_key' !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
  OR p_command->>'intent_id' !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
  OR p_command->>'request_key' !~ '^osc1:[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
  OR p_command->>'locale' NOT IN('pt-BR','en-US')
  OR jsonb_array_length(p_command->'document_actions') NOT BETWEEN 1 AND 16
  OR jsonb_array_length(p_command->'risks') NOT BETWEEN 1 AND 8
  OR EXISTS(SELECT 1 FROM jsonb_array_elements(p_command->'risks') x WHERE jsonb_typeof(x)<>'string') THEN
  RAISE EXCEPTION 'invalid_mobile_signup_health_command' USING ERRCODE='22023';
 END IF;
 k:=(p_command->>'operation_key')::uuid;v_intent_id:=(p_command->>'intent_id')::uuid;
 v_request_key:=p_command->>'request_key';v_locale:=p_command->>'locale';
 SELECT array_agg(x) INTO items FROM jsonb_array_elements_text(p_command->'risks') x;
 canonical_items:=private.mobile_health_risk_set(items);
 IF EXISTS(SELECT 1 FROM jsonb_array_elements(p_command->'document_actions') a
  WHERE jsonb_typeof(a)<>'object') THEN
  RAISE EXCEPTION 'invalid_mobile_signup_health_actions' USING ERRCODE='22023';
 END IF;
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
  RAISE EXCEPTION 'invalid_mobile_signup_health_actions' USING ERRCODE='22023';
 END IF;
 SELECT jsonb_agg(a ORDER BY (a->>'document_key') COLLATE "C") INTO actions
 FROM jsonb_array_elements(p_command->'document_actions') a;
 canonical:=p_command||jsonb_build_object('operation_key',k,'intent_id',v_intent_id,'document_actions',actions,'risks',canonical_items);
 PERFORM private.mobile_reevaluation_lock_owner(p_user_id);
 SELECT * INTO receipt FROM private.mobile_signup_health_receipts r WHERE r.user_id=p_user_id AND r.operation_key=k;
 IF FOUND THEN
  IF receipt.command IS DISTINCT FROM canonical THEN
   RAISE EXCEPTION 'mobile_signup_health_operation_conflict' USING ERRCODE='40001';
  END IF;
  -- Original acknowledgement precedes epoch, signup completion and current
  -- publication checks. Read current health without ever declaring risks again.
  RETURN private.mobile_signup_health_receipt_wire(receipt);
 END IF;
 SELECT i.* INTO intent FROM private.mobile_signup_completion_intents i
 WHERE i.user_id=p_user_id AND i.intent_id=v_intent_id AND i.request_key=v_request_key;
 SELECT e.epoch INTO current_epoch FROM private.workout_strength_authority_epochs e WHERE e.user_id=p_user_id;
 -- Owner lock fences structured writers; NOWAIT also protects against a
 -- legacy profile writer without waiting in its inverse lock order.
 SELECT p.onboarding_completed,p.onboarding_completed_at INTO completed,completed_at
 FROM public.user_profiles p WHERE p.user_id=p_user_id FOR UPDATE NOWAIT;
 IF intent.intent_id IS NULL OR intent.epoch IS DISTINCT FROM current_epoch OR current_epoch IS NULL
  OR completed IS DISTINCT FROM false OR completed_at IS NOT NULL THEN
  RAISE EXCEPTION 'mobile_signup_health_context_changed' USING ERRCODE='40001';
 END IF;
 -- SHARE alone is unsafe: a publisher can hold FOR UPDATE (RowShare),
 -- then wait for RowExclusive while a ledger FK waits on its row. EXCLUSIVE
 -- also fences RowShare. Catalog order is documents then requirements; no
 -- workout lock/epoch initialization may be acquired after the owner lock.
 LOCK TABLE public.onboarding_legal_documents IN EXCLUSIVE MODE;
 LOCK TABLE public.onboarding_legal_requirement_sets IN EXCLUSIVE MODE;
 now_at:=clock_timestamp();
 SELECT q.* INTO requirement FROM public.onboarding_legal_requirement_sets q
 WHERE q.locale=v_locale AND q.publication_status='published' AND q.effective_at<=now_at AND q.published_at<=now_at
 ORDER BY q.effective_at DESC,q.published_at DESC,q.id DESC LIMIT 1;
 IF requirement.id IS NULL THEN
  RAISE EXCEPTION 'onboarding_documents_unavailable' USING ERRCODE='23514';
 END IF;
 SELECT array_agg(d::public.onboarding_legal_documents ORDER BY d.document_key COLLATE "C") INTO documents FROM (
  SELECT DISTINCT ON(d.document_key) d.* FROM public.onboarding_legal_documents d
  WHERE d.locale=v_locale AND d.document_key=ANY(requirement.document_keys) AND d.publication_status='published'
   AND d.effective_at<=now_at AND d.published_at<=now_at
  ORDER BY d.document_key,d.effective_at DESC,d.published_at DESC,d.id DESC
 ) d;
 doc_count:=coalesce(cardinality(documents),0);
 IF doc_count<>cardinality(requirement.document_keys) OR doc_count NOT BETWEEN 1 AND 16
  OR EXISTS(SELECT 1 FROM unnest(documents) d WHERE d.required IS DISTINCT FROM true)
  OR (SELECT count(*) FROM unnest(documents) d
   WHERE d.purpose='closed_evaluation_sensitive_health_data_processing' AND d.action_type='consent')<>1 THEN
  RAISE EXCEPTION 'mobile_signup_health_sensitive_consent_unavailable' USING ERRCODE='23514';
 END IF;
 IF jsonb_array_length(actions)<>doc_count OR EXISTS(
  SELECT 1 FROM jsonb_array_elements(actions) a LEFT JOIN unnest(documents) d
   ON d.document_key=a->>'document_key' AND d.version=a->>'version' AND d.locale=a->>'locale'
    AND d.content_hash=a->>'content_hash' AND d.action_type=a->>'action' WHERE d.id IS NULL) THEN
  RAISE EXCEPTION 'onboarding_document_version_mismatch' USING ERRCODE='23514';
 END IF;
 INSERT INTO public.user_onboarding_legal_actions(user_id,legal_document_id,document_key,version,locale,content_hash,purpose,action_type,acted_at,created_at)
 SELECT p_user_id,d.id,d.document_key,d.version,d.locale,d.content_hash,d.purpose,d.action_type,now_at,now_at FROM unnest(documents) d
 ON CONFLICT(user_id,legal_document_id) DO NOTHING;
 SELECT jsonb_build_object('requirement',to_jsonb(requirement),'actions',jsonb_agg(jsonb_build_object(
  'document_id',d.id,'document_key',d.document_key,'version',d.version,'locale',d.locale,'content_hash',d.content_hash,
  'purpose',d.purpose,'action',d.action_type,'legal_action_id',a.id,'acted_at',a.acted_at) ORDER BY d.document_key COLLATE "C")) INTO evidence
 FROM unnest(documents) d JOIN public.user_onboarding_legal_actions a ON a.user_id=p_user_id AND a.legal_document_id=d.id;
 health_key:=gen_random_uuid();
 health:=private.declare_mobile_health_risk_at(p_user_id,health_key,canonical_items::text[],now_at);
 INSERT INTO private.mobile_signup_health_receipts(user_id,operation_key,intent_id,request_key,epoch,command,command_hash,
  requirement_set_id,policy_evidence,health_operation_key,health_receipt_id,admitted_at)
 VALUES(p_user_id,k,intent.intent_id,intent.request_key,intent.epoch,canonical,encode(extensions.digest(canonical::text,'sha256'),'hex'),
  requirement.id,evidence,health_key,(health#>>'{receipt,id}')::uuid,now_at) RETURNING * INTO receipt;
 RETURN private.mobile_signup_health_receipt_wire(receipt);
END $$;
REVOKE ALL ON FUNCTION private.mobile_signup_health_receipt_wire(private.mobile_signup_health_receipts),
 private.admit_mobile_signup_health(uuid,jsonb) FROM PUBLIC,anon,authenticated,service_role;
COMMENT ON TABLE private.mobile_signup_health_receipts IS
 'Private immutable signup consent/risk acknowledgement; ordinary answers are saved only on conclusion. No public transport is enabled.';
COMMIT;
