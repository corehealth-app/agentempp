\set ON_ERROR_STOP on
BEGIN ISOLATION LEVEL READ COMMITTED;
SET LOCAL statement_timeout='30s';
SET LOCAL lock_timeout='5s';
SET LOCAL request.jwt.claims='{"role":"service_role"}';
SET LOCAL TimeZone='UTC';
\ir fixtures/mobile_reevaluation_cycle_fixture.sql

-- This catches authorization by a bare legal row or a default retention period.
DO $unconfigured$
DECLARE a uuid; c uuid; d jsonb;
BEGIN
  a:=m3b_cycle_test.seed(101,'2026-10-01T23:00:00Z');
  c:=(public.start_mobile_reevaluation_cycle(a,gen_random_uuid())#>>'{cycle,id}')::uuid;
  d:=public.get_mobile_reevaluation_photo_consent(a,c);
  PERFORM m3b_cycle_test.ok(d->>'unavailable_reason'='policy_unavailable'
    AND d->'document'='null' AND d->'acceptance'='null','no_implicit_consent_or_retention_policy');
END $unconfigured$;

-- Fixtures are local, rolled back, and intentionally not the real consent texts.
CREATE FUNCTION m3b_cycle_test.photo_doc(n integer, lang text, ver text,
  effective_at timestamptz, enabled boolean DEFAULT true) RETURNS uuid
LANGUAGE plpgsql SET search_path=pg_catalog AS $$
DECLARE doc public.legal_documents%ROWTYPE;
BEGIN
  INSERT INTO public.legal_documents(id,document_key,version,locale,body,required_from)
    VALUES(m3b_cycle_test.uid(n),'body_photo_reevaluation_consent',ver,lang,
      'SYNTHETIC LOCAL ONLY '||n,effective_at) RETURNING * INTO doc;
  INSERT INTO private.mobile_reevaluation_photo_policies(document_id,document_key,version,
    locale,body_hash,idle_timeout_seconds,enabled)
    VALUES(doc.id,doc.document_key,doc.version,doc.locale,doc.body_hash,60,enabled);
  RETURN doc.id;
END $$;

CREATE FUNCTION m3b_cycle_test.photo_accept(a uuid,c uuid,rev bigint,doc_id uuid,k uuid,
  at_time timestamptz DEFAULT NULL) RETURNS jsonb
LANGUAGE plpgsql SET search_path=pg_catalog AS $$
DECLARE doc public.legal_documents%ROWTYPE;
BEGIN
  SELECT * INTO STRICT doc FROM public.legal_documents WHERE id=doc_id;
  RETURN private.accept_mobile_reevaluation_photo_consent_at(a,c,rev,doc.id,
    doc.document_key,doc.version,doc.locale,doc.body_hash,k,at_time);
END $$;

DO $main$
DECLARE a uuid:=m3b_cycle_test.uid(101); c uuid; doc_id uuid; d jsonb; r jsonb;
  receipt_id uuid; key_id uuid:=gen_random_uuid(); before_profile jsonb; before_rev bigint;
BEGIN
  c:=(public.get_mobile_reevaluation_cycle(a)#>>'{cycle,id}')::uuid;
  SELECT to_jsonb(p) INTO before_profile FROM public.user_profiles p WHERE user_id=a;
  doc_id:=m3b_cycle_test.photo_doc(301,'pt-BR','local-1','2026-10-20T00:00:00Z',false);
  d:=public.get_mobile_reevaluation_photo_consent(a,c);
  PERFORM m3b_cycle_test.ok(d->>'unavailable_reason'='policy_unavailable','disabled_policy_denies_document');
  PERFORM m3b_cycle_test.throws(format('SELECT m3b_cycle_test.photo_accept(%L,%L,1,%L,%L)',
    a,c,doc_id,key_id),'P0002','disabled_policy_cannot_be_accepted');
  UPDATE private.mobile_reevaluation_photo_policies SET enabled=true WHERE document_id=doc_id;
  d:=public.get_mobile_reevaluation_photo_consent(a,c);
  PERFORM m3b_cycle_test.ok(d->>'unavailable_reason'='consent_required'
    AND d#>>'{document,locale}'='pt-BR' AND d#>>'{document,idle_timeout_seconds}'='60'
    AND d->>'cycle_revision'='1','configured_document_shows_explicit_policy');
  PERFORM m3b_cycle_test.throws(format('SELECT m3b_cycle_test.photo_accept(%L,%L,2,%L,%L)',
    a,c,doc_id,key_id),'40001','stale_revision_has_no_acceptance');
  PERFORM m3b_cycle_test.ok((SELECT count(*)=0 FROM private.mobile_reevaluation_photo_consents),
    'failed_CAS_does_not_leave_partial_receipt');
  d:=m3b_cycle_test.photo_accept(a,c,1,doc_id,key_id);
  receipt_id:=(d#>>'{acceptance,acceptance_id}')::uuid;
  PERFORM m3b_cycle_test.ok(d->>'availability'='available' AND d->'unavailable_reason'='null'
    AND d->>'cycle_revision'='2' AND d#>>'{acceptance,document_id}'=doc_id::text,
    'acceptance_binds_exact_document_and_increments_revision_once');
  PERFORM m3b_cycle_test.ok((SELECT status='collecting' FROM private.mobile_reevaluation_cycles WHERE cycle_id=c)
    AND (SELECT count(*)=1 FROM private.mobile_reevaluation_photo_consents WHERE cycle_id=c),
    'one_active_cycle_receipt');
  r:=m3b_cycle_test.photo_accept(a,c,1,doc_id,key_id);
  PERFORM m3b_cycle_test.ok(r=d,'same_key_replay_preserves_receipt_and_deadline');
  r:=m3b_cycle_test.photo_accept(a,c,2,doc_id,gen_random_uuid());
  PERFORM m3b_cycle_test.ok(r=d AND (SELECT count(*)=1 FROM private.mobile_reevaluation_photo_consents
    WHERE cycle_id=c),'new_key_reuses_valid_receipt_without_renewal');
  PERFORM m3b_cycle_test.throws(format('SELECT m3b_cycle_test.photo_accept(%L,%L,2,%L,%L)',
    a,c,doc_id,key_id),'40001','reused_key_different_original_revision_conflicts');
  PERFORM m3b_cycle_test.throws(format('UPDATE private.mobile_reevaluation_photo_policies SET idle_timeout_seconds=120 WHERE document_id=%L',doc_id),
    '55000','policy_duration_immutable_under_same_consent_text');
  PERFORM m3b_cycle_test.throws(format('UPDATE private.mobile_reevaluation_photo_consents SET accepted_at=accepted_at-interval ''1second'' WHERE acceptance_id=%L',receipt_id),
    '55000','accepted_timestamp_immutable');
  PERFORM m3b_cycle_test.throws(format('UPDATE private.mobile_reevaluation_photo_consents SET user_id=%L WHERE acceptance_id=%L',m3b_cycle_test.uid(999),receipt_id),
    '55000','receipt_cannot_be_reassigned');
  PERFORM m3b_cycle_test.ok((SELECT to_jsonb(p)=before_profile FROM public.user_profiles p WHERE user_id=a)
    AND (SELECT count(*)=0 FROM public.user_legal_acceptances WHERE user_id=a),
    'profile_and_generic_legal_acceptances_preserved');
  UPDATE private.mobile_reevaluation_photo_policies SET enabled=false WHERE document_id=doc_id;
  PERFORM m3b_cycle_test.throws(format('SELECT m3b_cycle_test.photo_accept(%L,%L,1,%L,%L)',
    a,c,doc_id,key_id),'P0002','disabled_policy_revalidated_before_replay');
  UPDATE private.mobile_reevaluation_photo_policies SET enabled=true WHERE document_id=doc_id;
  PERFORM public.reset_user_conversation_atomic(a,true);
  PERFORM m3b_cycle_test.throws(format('SELECT m3b_cycle_test.photo_accept(%L,%L,1,%L,%L)',
    a,c,doc_id,key_id),'40001','reset_rejects_old_cycle_and_receipt');
END $main$;

DO $locale_and_current_document$
DECLARE a uuid; b uuid; c uuid; other_cycle uuid; doc_pt uuid:=m3b_cycle_test.uid(301);
  doc_en uuid; future_doc uuid; replacement uuid; d jsonb; key_id uuid:=gen_random_uuid(); pt_hash text;
BEGIN
  a:=m3b_cycle_test.seed(102,'2026-10-01T23:00:00Z');
  b:=m3b_cycle_test.seed(103,'2026-10-01T23:00:00Z');
  c:=(public.start_mobile_reevaluation_cycle(a,gen_random_uuid())#>>'{cycle,id}')::uuid;
  other_cycle:=(public.start_mobile_reevaluation_cycle(b,gen_random_uuid())#>>'{cycle,id}')::uuid;
  doc_en:=m3b_cycle_test.photo_doc(302,'en-US','local-1','2026-10-20T00:00:00Z');
  d:=m3b_cycle_test.photo_accept(a,c,1,doc_pt,key_id);
  UPDATE public.users SET locale='en-US' WHERE id=a;
  d:=public.get_mobile_reevaluation_photo_consent(a,c);
  PERFORM m3b_cycle_test.ok(d->>'unavailable_reason'='consent_changed'
    AND d#>>'{document,id}'=doc_en::text AND d->'acceptance'='null',
    'same_version_different_locale_is_not_the_same_consent');
  PERFORM m3b_cycle_test.throws(format('SELECT m3b_cycle_test.photo_accept(%L,%L,1,%L,%L)',
    a,c,doc_pt,key_id),'40001','current_locale_checked_before_old_replay');
  d:=m3b_cycle_test.photo_accept(a,c,2,doc_en,gen_random_uuid());
  PERFORM m3b_cycle_test.ok(d->>'cycle_revision'='3' AND d#>>'{acceptance,locale}'='en-US'
    AND (SELECT count(*)=1 FROM private.mobile_reevaluation_photo_consents WHERE cycle_id=c AND revoked_at IS NULL),
    'new_locale_revokes_old_receipt_and_creates_current_one');
  PERFORM m3b_cycle_test.throws(format('SELECT public.get_mobile_reevaluation_photo_consent(%L,%L)',a,other_cycle),
    '40001','foreign_cycle_cannot_be_read');
  PERFORM m3b_cycle_test.throws(format('SELECT m3b_cycle_test.photo_accept(%L,%L,1,%L,%L)',
    b,c,doc_en,gen_random_uuid()),'40001','foreign_cycle_cannot_be_accepted');
  future_doc:=m3b_cycle_test.photo_doc(303,'en-US','local-future',clock_timestamp()+interval '1day');
  PERFORM m3b_cycle_test.ok(public.get_mobile_reevaluation_photo_consent(a,c)#>>'{document,id}'=doc_en::text,
    'future_document_does_not_replace_current');
  replacement:=m3b_cycle_test.photo_doc(304,'en-US','local-2','2026-10-21T00:00:00Z',false);
  PERFORM m3b_cycle_test.ok(public.get_mobile_reevaluation_photo_consent(a,c)->>'unavailable_reason'='policy_unavailable',
    'new_document_without_enabled_policy_cannot_fallback_to_old_policy');
  PERFORM m3b_cycle_test.throws(format('SELECT m3b_cycle_test.photo_accept(%L,%L,3,%L,%L)',
    a,c,doc_en,gen_random_uuid()),'P0002','new_unconfigured_document_blocks_old_acceptance');
  UPDATE private.mobile_reevaluation_photo_policies SET enabled=true WHERE document_id=replacement;
  SELECT body_hash INTO pt_hash FROM public.legal_documents WHERE id=doc_pt;
  PERFORM m3b_cycle_test.throws(format('SELECT public.accept_mobile_reevaluation_photo_consent(%L,%L,3,%L,''body_photo_reevaluation_consent'',''local-2'',''en-US'',%L,%L)',
    a,c,replacement,pt_hash,gen_random_uuid()),'40001','hash_mismatch_is_not_accepted');
  PERFORM m3b_cycle_test.throws(format('SELECT public.accept_mobile_reevaluation_photo_consent(%L,%L,NULL,%L,''body_photo_reevaluation_consent'',''local-2'',''en-US'',%L,%L)',
    a,c,replacement,pt_hash,gen_random_uuid()),'22023','null_revision_rejected_explicitly');
END $locale_and_current_document$;

DO $expiry$
DECLARE a uuid; c uuid; doc_id uuid:=m3b_cycle_test.uid(301); d jsonb; r jsonb;
  accepted timestamptz; key_id uuid:=gen_random_uuid(); before_id uuid;
BEGIN
  a:=m3b_cycle_test.seed(104,'2026-10-01T23:00:00Z');
  c:=(public.start_mobile_reevaluation_cycle(a,gen_random_uuid())#>>'{cycle,id}')::uuid;
  d:=m3b_cycle_test.photo_accept(a,c,1,doc_id,key_id);
  accepted:=(d#>>'{acceptance,accepted_at}')::timestamptz;
  before_id:=(d#>>'{acceptance,acceptance_id}')::uuid;
  r:=private.mobile_reevaluation_photo_consent_state_at(a,c,accepted+interval '59.999999 seconds');
  PERFORM m3b_cycle_test.ok(r->>'availability'='available','consent_valid_just_before_configured_idle_expiry');
  r:=private.mobile_reevaluation_photo_consent_state_at(a,c,accepted+interval '60 seconds');
  PERFORM m3b_cycle_test.ok(r->>'unavailable_reason'='consent_expired' AND r->'acceptance'='null',
    'consent_expires_at_exact_boundary');
  PERFORM m3b_cycle_test.throws(format('SELECT m3b_cycle_test.photo_accept(%L,%L,1,%L,%L,%L)',
    a,c,doc_id,key_id,accepted+interval '60 seconds'),'40001','expired_replay_cannot_renew_consent');
  r:=m3b_cycle_test.photo_accept(a,c,2,doc_id,gen_random_uuid(),accepted+interval '60 seconds');
  PERFORM m3b_cycle_test.ok((r#>>'{acceptance,acceptance_id}')::uuid<>before_id
    AND r->>'cycle_revision'='3'
    AND (SELECT revoked_reason='expired' FROM private.mobile_reevaluation_photo_consents WHERE acceptance_id=before_id),
    'fresh_key_after_expiry_creates_new_bound_receipt');
  PERFORM m3b_cycle_test.ok((SELECT count(*)=2 FROM private.mobile_reevaluation_photo_consents WHERE cycle_id=c)
    AND (SELECT count(*)=1 FROM private.mobile_reevaluation_photo_consents WHERE cycle_id=c AND revoked_at IS NULL),
    'expired_evidence_retained_with_one_live_receipt');
END $expiry$;

DO $security$
DECLARE valid boolean; doc_id uuid; d public.legal_documents%ROWTYPE;
  cycle_row private.mobile_reevaluation_cycles%ROWTYPE; receipt_id uuid;
BEGIN
  INSERT INTO public.legal_documents(id,document_key,version,locale,body,required_from)
    VALUES(m3b_cycle_test.uid(305),'body_photo_reevaluation_consent','local-policy-constraints','pt-BR',
      'SYNTHETIC LOCAL CONSTRAINTS','2026-10-19T00:00:00Z') RETURNING * INTO d;
  PERFORM m3b_cycle_test.throws(format('INSERT INTO private.mobile_reevaluation_photo_policies(document_id,document_key,version,locale,body_hash) VALUES(%L,%L,%L,%L,%L)',
    d.id,d.document_key,d.version,d.locale,d.body_hash),'23502','policy_has_no_default_retention_duration');
  PERFORM m3b_cycle_test.throws(format('INSERT INTO private.mobile_reevaluation_photo_policies(document_id,document_key,version,locale,body_hash,idle_timeout_seconds) VALUES(%L,%L,%L,%L,%L,0)',
    d.id,d.document_key,d.version,d.locale,d.body_hash),'23514','policy_cannot_have_zero_duration');
  PERFORM m3b_cycle_test.throws(format('INSERT INTO private.mobile_reevaluation_photo_policies(document_id,document_key,version,locale,body_hash,idle_timeout_seconds) VALUES(%L,%L,%L,%L,%L,60)',
    d.id,d.document_key,d.version,d.locale,repeat('a',64)),'23503','policy_FK_requires_exact_legal_identity');
  SELECT * INTO STRICT cycle_row FROM private.mobile_reevaluation_cycles WHERE user_id=m3b_cycle_test.uid(104);
  SELECT acceptance_id INTO STRICT receipt_id FROM private.mobile_reevaluation_photo_consents
    WHERE cycle_id=cycle_row.cycle_id AND revoked_at IS NULL;
  PERFORM m3b_cycle_test.throws(format('INSERT INTO private.mobile_reevaluation_photo_consent_keys(user_id,idempotency_key,signup_generation,cycle_id,acceptance_id,expected_revision) VALUES(%L,%L,%L,%L,%L,1)',
    m3b_cycle_test.uid(103),gen_random_uuid(),cycle_row.signup_generation,cycle_row.cycle_id,receipt_id),
    '23503','key_receipt_FK_preserves_owner_and_cycle');
  PERFORM m3b_cycle_test.throws(format('UPDATE private.mobile_reevaluation_photo_consent_keys SET expected_revision=expected_revision+1 WHERE acceptance_id=%L',receipt_id),
    '55000','idempotency_payload_cannot_be_rewritten');
  SELECT * INTO STRICT d FROM public.legal_documents WHERE id=m3b_cycle_test.uid(301);
  PERFORM m3b_cycle_test.throws(format('INSERT INTO private.mobile_reevaluation_photo_consents(user_id,signup_generation,cycle_id,document_id,document_key,version,locale,body_hash,idle_timeout_seconds,accepted_at,last_activity_at) VALUES(%L,%L,%L,%L,%L,%L,%L,%L,60,clock_timestamp(),clock_timestamp())',
    m3b_cycle_test.uid(103),cycle_row.signup_generation,cycle_row.cycle_id,d.id,d.document_key,d.version,d.locale,d.body_hash),
    '23503','receipt_cycle_FK_prevents_foreign_owner');
  SELECT bool_and(c.relrowsecurity AND c.relowner='postgres'::regrole
    AND NOT EXISTS(SELECT 1 FROM aclexplode(coalesce(c.relacl,acldefault('r',c.relowner))) x WHERE x.grantee<>c.relowner))
  INTO valid FROM pg_class c WHERE c.oid IN('private.mobile_reevaluation_photo_policies'::regclass,
    'private.mobile_reevaluation_photo_consents'::regclass,'private.mobile_reevaluation_photo_consent_keys'::regclass);
  PERFORM m3b_cycle_test.ok(valid,'private_tables_RLS_owner_only');
  SELECT bool_and(p.prosecdef AND p.proconfig=ARRAY['search_path=pg_catalog']
    AND has_function_privilege('service_role',p.oid,'EXECUTE')
    AND NOT has_function_privilege('authenticated',p.oid,'EXECUTE')
    AND NOT has_function_privilege('anon',p.oid,'EXECUTE')) INTO valid FROM pg_proc p
    WHERE p.oid IN('public.get_mobile_reevaluation_photo_consent(uuid,uuid)'::regprocedure,
      'public.accept_mobile_reevaluation_photo_consent(uuid,uuid,bigint,uuid,text,text,text,text,uuid)'::regprocedure);
  PERFORM m3b_cycle_test.ok(valid,'RPCs_fixed_path_backend_role_only');
  SELECT bool_and(NOT has_function_privilege('service_role',p.oid,'EXECUTE')) INTO valid FROM pg_proc p
    JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='private'
      AND (p.proname LIKE '%reevaluation_photo_consent%' OR p.proname='mobile_reevaluation_photo_context');
  PERFORM m3b_cycle_test.ok(valid,'private_helpers_and_clock_not_exposed');
  PERFORM set_config('request.jwt.claims','{"role":"authenticated"}',true);
  PERFORM m3b_cycle_test.throws(format('SELECT public.get_mobile_reevaluation_photo_consent(%L,(SELECT cycle_id FROM private.mobile_reevaluation_cycles WHERE user_id=%L))',
    m3b_cycle_test.uid(104),m3b_cycle_test.uid(104)),'42501','untrusted_backend_claim_rejected');
END $security$;
ROLLBACK;
