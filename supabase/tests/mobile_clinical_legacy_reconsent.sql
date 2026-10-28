-- Local synthetic transaction only; actual source/legal/catalog authorities.
\set ON_ERROR_STOP on
BEGIN;
SET LOCAL request.jwt.claims='{"role":"service_role"}';
\ir fixtures/mobile_signup_health_fixture.sql
SELECT m3b_cycle_test.ok(to_regprocedure('public.accept_mobile_clinical_legacy_documents(uuid,jsonb)') IS NOT NULL,
 'legacy_documents_only_service_transport_exists');
DO $cases$
DECLARE n integer;a uuid;stamp timestamptz;c jsonb;first jsonb;r jsonb;before_rows jsonb;actions jsonb;
 legal_before jsonb;now_before timestamptz;
 allowed text[]:=ARRAY['private.mobile_clinical_legacy_document_receipts','public.user_onboarding_legal_actions'];
BEGIN
 SELECT jsonb_agg(jsonb_build_object('document_key',document_key,'version',version,'locale',locale,
  'content_hash',content_hash,'action',action_type) ORDER BY document_key COLLATE "C") INTO actions
 FROM public.onboarding_legal_documents WHERE publication_status='published' AND locale='pt-BR';
 FOR n IN 5300..5303 LOOP
  stamp:=CASE WHEN n%2=0 THEN '2026-10-01T23:00:00.123456Z'::timestamptz END;
  a:=m3b_cycle_test.seed(n,stamp,'America/Sao_Paulo',false);
  UPDATE public.user_profiles SET onboarding_completed=true,current_protocol=CASE WHEN n<5302 THEN 'recomposicao'::public.protocol_enum END WHERE user_id=a;
  PERFORM public.admit_mobile_clinical_legacy_generation(a);
  before_rows:=m3b_cycle_test.original_state(a);now_before:=clock_timestamp();
  c:=jsonb_build_object('version',1,'operation_key',gen_random_uuid(),'locale','pt-BR','document_actions',actions);
  SET LOCAL ROLE service_role;
  first:=public.accept_mobile_clinical_legacy_documents(a,c);
  RESET ROLE;
  PERFORM m3b_cycle_test.ok(first->>'user_id'=a::text AND first->>'operation_key'=c->>'operation_key'
   AND (first#>>'{receipt,accepted_at}')::timestamptz BETWEEN now_before AND clock_timestamp()
   AND jsonb_array_length(first#>'{receipt,document_actions}')=4,
   'documents_receipt_is_actual_owner_operation_actions_and_server_clock_'||n);
  PERFORM m3b_cycle_test.ok(before_rows-allowed=m3b_cycle_test.original_state(a)-allowed
   AND (SELECT count(*)=4 FROM public.user_onboarding_legal_actions WHERE user_id=a)
   AND (SELECT onboarding_completed_at IS NOT DISTINCT FROM stamp FROM public.user_profiles WHERE user_id=a)
   AND NOT EXISTS(SELECT 1 FROM private.mobile_signup_strength_completion_receipts WHERE user_id=a),
   'document_only_command_preserves_all_signup_clinical_target_and_historical_facts_'||n);
  before_rows:=m3b_cycle_test.original_state(a);
  r:=public.accept_mobile_clinical_legacy_documents(a,jsonb_set(c,'{document_actions}',
   (SELECT jsonb_agg(value ORDER BY ord DESC) FROM jsonb_array_elements(actions) WITH ORDINALITY x(value,ord))));
  PERFORM m3b_cycle_test.ok(r=first AND before_rows=m3b_cycle_test.original_state(a),
   'identical_or_reordered_command_reuses_exact_receipt_'||n);
  SELECT jsonb_agg(to_jsonb(x) ORDER BY id) INTO legal_before FROM public.user_onboarding_legal_actions x WHERE user_id=a;
  r:=public.accept_mobile_clinical_legacy_documents(a,c||jsonb_build_object('operation_key',gen_random_uuid()));
  PERFORM m3b_cycle_test.ok(legal_before=(SELECT jsonb_agg(to_jsonb(x) ORDER BY id) FROM public.user_onboarding_legal_actions x WHERE user_id=a)
   AND r#>'{receipt,document_actions}'=first#>'{receipt,document_actions}',
   'new_operation_never_rewrites_original_acted_at_'||n);
  PERFORM m3b_cycle_test.throws(format('SELECT public.accept_mobile_clinical_legacy_documents(%L,%L)',a,
   jsonb_set(c,'{document_actions,0,version}','"other"')),'40001','altered_replay_conflicts_'||n);
  PERFORM public.reset_user_conversation_atomic(a,true);
  before_rows:=m3b_cycle_test.original_state(a);
  PERFORM m3b_cycle_test.ok(public.accept_mobile_clinical_legacy_documents(a,c)=first
   AND before_rows=m3b_cycle_test.original_state(a),'replay_precedes_reset_without_readmission_'||n);
  PERFORM m3b_cycle_test.throws(format('SELECT public.accept_mobile_clinical_legacy_documents(%L,%L)',a,
   c||jsonb_build_object('operation_key',gen_random_uuid())),'40001','new_command_after_reset_is_rejected_'||n);
 END LOOP;
END $cases$;
DO $bad$
DECLARE a uuid:=m3b_cycle_test.seed(5304,NULL);c jsonb;actions jsonb;patch jsonb;before_rows jsonb;
BEGIN
 SELECT jsonb_agg(jsonb_build_object('document_key',document_key,'version',version,'locale',locale,
  'content_hash',content_hash,'action',action_type) ORDER BY document_key COLLATE "C") INTO actions
 FROM public.onboarding_legal_documents WHERE publication_status='published' AND locale='pt-BR';
 c:=jsonb_build_object('version',1,'operation_key',gen_random_uuid(),'locale','pt-BR','document_actions',actions);
 before_rows:=m3b_cycle_test.original_state(a);
 PERFORM m3b_cycle_test.throws(format('SELECT public.accept_mobile_clinical_legacy_documents(%L,%L)',a,c),
  '40001','unadmitted_incomplete_account_cannot_accept_legacy_documents');
 UPDATE public.user_profiles SET onboarding_completed=true WHERE user_id=a;
 PERFORM public.admit_mobile_clinical_legacy_generation(a);
 before_rows:=m3b_cycle_test.original_state(a);
 FOREACH patch IN ARRAY ARRAY['{"version":2}','{"locale":null}','{"locale":"en-US"}',
  '{"document_actions":[]}','{"operation_key":null}','{"epoch":"hidden"}',
  '{"weight_kg":80}','{"completed_at":"2026-10-01T00:00:00Z"}']::jsonb[] LOOP
  PERFORM m3b_cycle_test.throws(format('SELECT public.accept_mobile_clinical_legacy_documents(%L,%L)',a,c||patch),
   '22023','strict_document_command_'||patch::text);
 END LOOP;
 PERFORM m3b_cycle_test.throws(format('SELECT public.accept_mobile_clinical_legacy_documents(%L,%L)',a,
  jsonb_set(c,'{document_actions,0,content_hash}',to_jsonb(repeat('0',64)))),'23514','wrong_document_hash_cannot_create_receipt');
 PERFORM m3b_cycle_test.ok(before_rows=m3b_cycle_test.original_state(a),'all_refusals_leave_every_owner_table_unchanged');
END $bad$;
DO $publication$
DECLARE a uuid:=m3b_cycle_test.seed(5305,NULL);c jsonb;first jsonb;actions jsonb;v_body text:='SYNTHETIC changed legal notice';before_rows jsonb;
BEGIN
 UPDATE public.user_profiles SET onboarding_completed=true WHERE user_id=a;
 PERFORM public.admit_mobile_clinical_legacy_generation(a);
 SELECT jsonb_agg(jsonb_build_object('document_key',document_key,'version',version,'locale',locale,
  'content_hash',content_hash,'action',action_type) ORDER BY document_key COLLATE "C") INTO actions
 FROM public.onboarding_legal_documents WHERE publication_status='published' AND locale='pt-BR';
 c:=jsonb_build_object('version',1,'operation_key',gen_random_uuid(),'locale','pt-BR','document_actions',actions);
 first:=public.accept_mobile_clinical_legacy_documents(a,c);
 INSERT INTO public.onboarding_legal_documents(id,document_key,version,locale,body,content_hash,purpose,action_type,required,effective_at)
 SELECT m3b_cycle_test.uid(5308),document_key,'synthetic-health-2',locale,v_body,encode(extensions.digest(v_body,'sha256'),'hex'),
  purpose,action_type,required,clock_timestamp() FROM public.onboarding_legal_documents WHERE id=m3b_cycle_test.uid(201);
 PERFORM public.publish_onboarding_legal_document(m3b_cycle_test.uid(5308));
 before_rows:=m3b_cycle_test.original_state(a);
 PERFORM m3b_cycle_test.ok(public.accept_mobile_clinical_legacy_documents(a,c)=first
  AND before_rows=m3b_cycle_test.original_state(a),'original_receipt_replays_after_catalog_changes_without_new_acceptance');
 PERFORM m3b_cycle_test.throws(format('SELECT public.accept_mobile_clinical_legacy_documents(%L,%L)',a,
  c||jsonb_build_object('operation_key',gen_random_uuid())),'23514','new_operation_requires_actual_latest_document_version');
END $publication$;
DO $signup_guard$
DECLARE a uuid:=m3b_cycle_test.seed(5306,NULL);submission jsonb;actions jsonb;before_rows jsonb;
BEGIN
 UPDATE public.user_profiles SET onboarding_completed=true WHERE user_id=a;
 PERFORM public.admit_mobile_clinical_legacy_generation(a);
 SELECT jsonb_agg(jsonb_build_object('document_key',document_key,'version',version,'locale',locale,
  'content_hash',content_hash,'action',action_type) ORDER BY document_key COLLATE "C") INTO actions
 FROM public.onboarding_legal_documents WHERE publication_status='published' AND locale='pt-BR';
 submission:=jsonb_build_object('name','SYNTHETIC legacy QA','locale','pt-BR','country','BR','timezone','America/Sao_Paulo',
  'sex','masculino','birth_date','1990-01-01','height_cm',180,'weight_kg',80,'objective','recomposicao',
  'activity_level','moderado','training_frequency',4,'hunger_level','moderada','wake_time','07:00','bedtime','23:00',
  'food_organization','sim','persona','focus','document_actions',actions);
 before_rows:=m3b_cycle_test.original_state(a);
 PERFORM m3b_cycle_test.throws(format('SELECT public.complete_mobile_onboarding_atomic(%L,%L)',a,submission),
  '40001','admitted_completed_legacy_NULL_cannot_enter_fresh_signup_branch');
 PERFORM m3b_cycle_test.ok(before_rows=m3b_cycle_test.original_state(a),'signup_guard_preserves_every_original_owner_row');
END $signup_guard$;
SELECT m3b_cycle_test.ok(NOT has_function_privilege('anon','public.accept_mobile_clinical_legacy_documents(uuid,jsonb)','EXECUTE')
 AND NOT has_function_privilege('authenticated','public.accept_mobile_clinical_legacy_documents(uuid,jsonb)','EXECUTE')
 AND has_function_privilege('service_role','public.accept_mobile_clinical_legacy_documents(uuid,jsonb)','EXECUTE'),
 'new_document_command_is_backend_only');
SELECT m3b_cycle_test.throws('UPDATE private.mobile_clinical_legacy_document_receipts SET accepted_at=clock_timestamp()',
 '55000','legal_receipts_are_immutable_even_for_owner_SQL');
DO $transport$
DECLARE code text;msg text;detail text;
BEGIN
 SET LOCAL request.jwt.claims='{"role":"authenticated"}';
 BEGIN PERFORM public.accept_mobile_clinical_legacy_documents(m3b_cycle_test.uid(5300),'{}');
 EXCEPTION WHEN OTHERS THEN GET STACKED DIAGNOSTICS code=RETURNED_SQLSTATE;END;
 PERFORM m3b_cycle_test.ok(code='42501','wrapper_rejects_app_JWT_even_for_privileged_SQL_caller');
 SET LOCAL request.jwt.claims='{"role":"service_role"}';
 SET LOCAL request.path='/rpc/accept_mobile_clinical_legacy_documents';SET LOCAL request.method='POST';
 BEGIN PERFORM public.accept_mobile_clinical_legacy_documents(m3b_cycle_test.uid(5300),jsonb_build_object(
  'version',1,'operation_key',gen_random_uuid(),'locale','pt-BR','document_actions',jsonb_build_array(jsonb_build_object(
   'document_key','terms','version','1','locale','pt-BR','content_hash',repeat('a',64),'action','acceptance'))));
 EXCEPTION WHEN OTHERS THEN GET STACKED DIAGNOSTICS code=RETURNED_SQLSTATE,msg=MESSAGE_TEXT,detail=PG_EXCEPTION_DETAIL;END;
 PERFORM m3b_cycle_test.ok(code='PGRST' AND msg::jsonb->>'code'='40001' AND detail::jsonb->>'status'='409',
  'official_document_RPC_uses_closed_HTTP409_conflict_transport');
END $transport$;
SET CONSTRAINTS ALL IMMEDIATE;
ROLLBACK;
