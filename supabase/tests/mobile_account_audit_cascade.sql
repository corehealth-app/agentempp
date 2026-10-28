-- Synthetic local account deletion with real audit constraints and roles.
-- Run only through LocalCycleDatabase; this transaction always rolls back.
BEGIN;
SET LOCAL search_path=pg_catalog;
SELECT set_config('request.jwt.claim.role','service_role',true);
\ir fixtures/mobile_reevaluation_cycle_fixture.sql

CREATE FUNCTION m3b_cycle_test.audit_state(owner_id uuid) RETURNS jsonb
LANGUAGE sql SET search_path=pg_catalog AS $$
 WITH rows(kind,data) AS (
  SELECT 'users',to_jsonb(t) FROM public.users t WHERE id=owner_id
  UNION ALL SELECT 'profiles',to_jsonb(t) FROM public.user_profiles t WHERE user_id=owner_id
  UNION ALL SELECT 'onboarding',to_jsonb(t) FROM public.user_onboarding_legal_actions t WHERE user_id=owner_id
  UNION ALL SELECT 'coach',to_jsonb(t) FROM public.coach_message_usage t WHERE user_id=owner_id
  UNION ALL SELECT 'mascot_events',to_jsonb(t) FROM public.user_mascot_state_events t WHERE user_id=owner_id
  UNION ALL SELECT 'mascot',to_jsonb(t) FROM public.user_mascot_state t WHERE user_id=owner_id
  UNION ALL SELECT 'legal',to_jsonb(t) FROM public.user_legal_acceptances t WHERE user_id=owner_id
  UNION ALL SELECT 'adherence',to_jsonb(t) FROM public.routine_adherence_logs t WHERE user_id=owner_id
  UNION ALL SELECT 'routine',to_jsonb(t) FROM public.routine_items t WHERE user_id=owner_id
  UNION ALL SELECT 'content',to_jsonb(t) FROM public.content_events t WHERE user_id=owner_id
 ) SELECT coalesce(jsonb_agg(jsonb_build_object('kind',kind,'row',data) ORDER BY kind,data::text),'[]'::jsonb) FROM rows
$$;
CREATE FUNCTION m3b_cycle_test.catalog_state() RETURNS jsonb
LANGUAGE sql SET search_path=pg_catalog AS $$
 WITH rows(kind,data) AS (
  SELECT 'onboarding_doc',to_jsonb(t) FROM public.onboarding_legal_documents t WHERE id=m3b_cycle_test.uid(3480)
  UNION ALL SELECT 'requirements',to_jsonb(t) FROM public.onboarding_legal_requirement_sets t WHERE id=m3b_cycle_test.uid(3482)
  UNION ALL SELECT 'legal',to_jsonb(t) FROM public.legal_documents t WHERE id=m3b_cycle_test.uid(3481)
  UNION ALL SELECT 'publications',to_jsonb(t) FROM public.content_publications t
  UNION ALL SELECT 'versions',to_jsonb(t) FROM public.content_versions t
 ) SELECT coalesce(jsonb_agg(jsonb_build_object('kind',kind,'row',data) ORDER BY kind,data::text),'[]'::jsonb) FROM rows
$$;
CREATE TEMP TABLE cascade_before(owner_id uuid PRIMARY KEY,state jsonb,catalog jsonb);
DO $seed$
DECLARE a uuid:=m3b_cycle_test.seed(3401,NULL);b uuid:=m3b_cycle_test.seed(3402,NULL);
 owner_id uuid;publication uuid;version_id uuid;result jsonb;item uuid;asset uuid:=gen_random_uuid();table_name text;
 body text:='SYNTHETIC LOCAL ACCOUNT CASCADE TEST';
BEGIN
 INSERT INTO public.onboarding_legal_documents(id,document_key,version,locale,body,content_hash,purpose,action_type,required,effective_at)
 VALUES(m3b_cycle_test.uid(3480),'m3b_cascade','m3b-cascade-1','pt-BR',body,
  encode(extensions.digest(body,'sha256'),'hex'),'synthetic_local_test','acceptance',true,clock_timestamp()-interval '1 second');
 PERFORM public.publish_onboarding_legal_document(m3b_cycle_test.uid(3480));
 INSERT INTO public.onboarding_legal_requirement_sets(id,version,locale,document_keys,effective_at)
 VALUES(m3b_cycle_test.uid(3482),'m3b-cascade-1','pt-BR',ARRAY['m3b_cascade'],clock_timestamp()-interval '1 second');
 PERFORM public.publish_onboarding_legal_requirement_set(m3b_cycle_test.uid(3482));
 INSERT INTO public.legal_documents(id,document_key,version,locale,body,required_from)
 VALUES(m3b_cycle_test.uid(3481),'m3b_cascade','m3b-cascade-1','pt-BR',body,clock_timestamp()-interval '1 second');
 INSERT INTO auth.users(id,aud,role,email,encrypted_password,email_confirmed_at,raw_app_meta_data,raw_user_meta_data,created_at,updated_at,is_sso_user,is_anonymous)
 VALUES(m3b_cycle_test.uid(3490),'authenticated','authenticated','m3b-cascade-editor@example.invalid','',now(),'{"provider":"email","providers":["email"]}','{}',now(),now(),false,false);
 INSERT INTO public.admin_users(id,email,role) VALUES(m3b_cycle_test.uid(3490),'m3b-cascade-editor@example.invalid','content_editor');
 result:=public.create_content_publication(m3b_cycle_test.uid(3490),'m3b-cascade-test');publication:=(result->>'publication_id')::uuid;
 result:=public.create_content_draft(m3b_cycle_test.uid(3490),publication,'pt-BR');version_id:=(result->>'version_id')::uuid;
 FOREACH owner_id IN ARRAY ARRAY[a,b] LOOP
  INSERT INTO public.user_onboarding_legal_actions(user_id,legal_document_id,document_key,version,locale,content_hash,purpose,action_type)
  SELECT owner_id,id,document_key,version,locale,content_hash,purpose,action_type FROM public.onboarding_legal_documents WHERE id=m3b_cycle_test.uid(3480);
  INSERT INTO public.user_legal_acceptances(user_id,legal_document_id,document_key,version,locale,body_hash)
  SELECT owner_id,id,document_key,version,locale,body_hash FROM public.legal_documents WHERE id=m3b_cycle_test.uid(3481);
  INSERT INTO public.coach_message_usage(user_id,context,channel,locale,requested_personality,effective_personality,outcome,reason,local_date)
  VALUES(owner_id,'onboarding','in_app','pt-BR','focus','focus','suppressed','catalog_incomplete','2026-10-28');
  PERFORM public.transition_user_mascot_state(owner_id,'reactivating','explicit_test_event','m3b-cascade-mascot');
  INSERT INTO public.routine_items(user_id,item_type,name,dose_text,origin,reminders_enabled,active)
  VALUES(owner_id,'supplement','Synthetic test item','1 dose','user',false,true) RETURNING id INTO item;
  INSERT INTO public.routine_adherence_logs(user_id,routine_item_id,item_type,status,idempotency_key,occurred_at,source)
  VALUES(owner_id,item,'supplement','taken','m3b-cascade-adherence',clock_timestamp(),'patient');
  INSERT INTO public.content_events(user_id,publication_id,content_version_id,event_type,origin,event_key_hash)
  VALUES(owner_id,publication,version_id,'opened','library',repeat('b',64));
 END LOOP;
 FOREACH table_name IN ARRAY ARRAY['user_onboarding_legal_actions','coach_message_usage','user_mascot_state_events','user_legal_acceptances','routine_adherence_logs','content_events'] LOOP
  PERFORM m3b_cycle_test.throws(format('UPDATE public.%I SET user_id=user_id WHERE user_id=%L',table_name,a),'23514',table_name||' active owner update forbidden');
  PERFORM m3b_cycle_test.throws(format('DELETE FROM public.%I WHERE user_id=%L',table_name,a),'23514',table_name||' active owner direct delete forbidden');
 END LOOP;
 UPDATE public.users SET status='deleted',updated_at=clock_timestamp()-interval '2 hours' WHERE id=a;
 FOREACH table_name IN ARRAY ARRAY['user_onboarding_legal_actions','coach_message_usage','user_mascot_state_events','user_legal_acceptances','routine_adherence_logs','content_events'] LOOP
  PERFORM m3b_cycle_test.throws(format('UPDATE public.%I SET user_id=user_id WHERE user_id=%L',table_name,a),'23514',table_name||' softdeleted owner update forbidden');
  PERFORM m3b_cycle_test.throws(format('DELETE FROM public.%I WHERE user_id=%L',table_name,a),'23514',table_name||' softdelete alone cannot prune audit');
 END LOOP;
 INSERT INTO cascade_before VALUES(a,m3b_cycle_test.audit_state(a),m3b_cycle_test.catalog_state()),(b,m3b_cycle_test.audit_state(b),m3b_cycle_test.catalog_state());
 INSERT INTO public.media_assets(id,user_id,kind,bucket_id,object_path,mime_type,declared_size_bytes,actual_size_bytes,status,context_text,source_request_hash,retention_until,uploaded_at,signup_origin)
 VALUES(asset,a,'meal_photo','meal-photos',a::text||'/'||asset::text||'.jpg','image/jpeg',1200,1200,'uploaded','Synthetic test',repeat('c',64),clock_timestamp()+interval '1 hour',clock_timestamp(),false);
 PERFORM m3b_cycle_test.throws(format('DELETE FROM public.users WHERE id=%L',a),'55000','final owner delete refuses any media catalog still present');
 DELETE FROM public.media_assets WHERE id=asset AND user_id=a;
 PERFORM m3b_cycle_test.ok((SELECT cb.state=m3b_cycle_test.audit_state(a) FROM cascade_before cb WHERE cb.owner_id=a),'media guard rolled back all owner ledger changes');
END $seed$;

CREATE FUNCTION m3b_cycle_test.reject_late_purge() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN RAISE EXCEPTION 'synthetic_late_purge_failure' USING ERRCODE='P0001';END $$;
CREATE TRIGGER qa_late_purge_failure AFTER DELETE ON public.user_profiles FOR EACH ROW EXECUTE FUNCTION m3b_cycle_test.reject_late_purge();
SELECT m3b_cycle_test.throws('DELETE FROM public.users WHERE id=''b3b01000-0000-4000-8000-000000003401''','P0001','late failure rolls back the whole final account deletion');
SELECT m3b_cycle_test.ok((SELECT state=m3b_cycle_test.audit_state(owner_id) FROM cascade_before WHERE owner_id=m3b_cycle_test.uid(3401)),'late failure restores all six ledgers and owner');
DROP TRIGGER qa_late_purge_failure ON public.user_profiles;

SET LOCAL ROLE service_role;
DELETE FROM public.users WHERE id='b3b01000-0000-4000-8000-000000003401' AND status='deleted' AND updated_at<=clock_timestamp()-interval '1 hour';
RESET ROLE;
SELECT m3b_cycle_test.ok(m3b_cycle_test.audit_state(m3b_cycle_test.uid(3401))='[]'::jsonb,'real backend role deletes owner and all six ledgers without relaxed FKs');
SELECT m3b_cycle_test.ok((SELECT state=m3b_cycle_test.audit_state(owner_id) FROM cascade_before WHERE owner_id=m3b_cycle_test.uid(3402)),'neighbor identity and every ledger byte remain unchanged');
SELECT m3b_cycle_test.ok((SELECT catalog=m3b_cycle_test.catalog_state() FROM cascade_before WHERE owner_id=m3b_cycle_test.uid(3402)),'global legal catalogs and content versions are preserved');
SELECT m3b_cycle_test.throws('DELETE FROM public.legal_documents WHERE id=''b3b01000-0000-4000-8000-000000003481''','23514','global legal document DELETE stays forbidden');
SELECT m3b_cycle_test.throws('UPDATE public.legal_documents SET body=body WHERE id=''b3b01000-0000-4000-8000-000000003481''','23514','global legal document UPDATE stays forbidden');
SELECT m3b_cycle_test.throws('DELETE FROM public.onboarding_legal_documents WHERE id=''b3b01000-0000-4000-8000-000000003480''','23514','published onboarding legal document remains immutable');
SELECT m3b_cycle_test.throws('DELETE FROM public.onboarding_legal_requirement_sets WHERE id=''b3b01000-0000-4000-8000-000000003482''','23514','published onboarding requirement set remains immutable');
SELECT m3b_cycle_test.ok(NOT has_function_privilege(role,'private.prune_mobile_deleted_user_owned_dependents()','EXECUTE'),role||' cannot call private purge trigger function') FROM unnest(ARRAY['anon','authenticated','service_role']) role;
SET CONSTRAINTS ALL IMMEDIATE;
ROLLBACK;
