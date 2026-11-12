-- Actual SQL writers and canonical receipts; caller owns the rollback.
BEGIN;
SET LOCAL request.jwt.claims='{"role":"service_role"}';
SET LOCAL timezone='UTC';SET LOCAL datestyle='ISO,YMD';
\ir fixtures/conversation_meal_thread_page_v2_fixture.sql
CREATE TEMP TABLE journal_feedback_assertions(label text PRIMARY KEY) ON COMMIT DROP;
CREATE FUNCTION pg_temp.journal_feedback_ok(v boolean,label text) RETURNS void LANGUAGE plpgsql AS $$
BEGIN
 IF v IS DISTINCT FROM true THEN RAISE EXCEPTION 'JOURNAL_FEEDBACK_V3_FAIL:%',label;END IF;
 INSERT INTO journal_feedback_assertions VALUES(label);
END $$;
CREATE FUNCTION pg_temp.journal_feedback_seal(u uuid,r uuid,version integer DEFAULT 3) RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE c jsonb;f jsonb;x jsonb;command_id uuid;effect_version text;
BEGIN
 c:=public.capture_mobile_registration_feedback_v3(u,r,'pending_registration')->'context';
 f:=jsonb_build_object('schema','registration.feedback.v'||version,'registration_id',r,'local_date',c->'local_date',
  'locale','pt-BR','assistant','Flow AI','registration',c->'record','day',NULL,
  'block',jsonb_build_object('status',CASE WHEN version=3 THEN 'protected' ELSE 'unavailable' END),
  'guidance','unavailable','education',jsonb_build_object('status','unavailable'));
 IF version=3 THEN x:=public.commit_mobile_registration_feedback_v3(u,r,'pending_registration',c,f);
 ELSE
  SELECT e.command_id,e.receipt->>'effect_version' INTO STRICT command_id,effect_version
   FROM private.conversation_meal_effects e WHERE e.user_id=u AND e.receipt->>'registration_id'=r::text;
  x:=public.commit_conversation_meal_feedback_v2(u,command_id,effect_version,f);
 END IF;
 IF x->>'action'<>'committed' THEN RAISE EXCEPTION 'journal_feedback_fixture_seal:%',x->>'action';END IF;
 RETURN f;
END $$;
DO $direct$
DECLARE u uuid:='c1770000-0000-4000-8000-000000000001';a uuid:='c1770000-0000-4000-8000-000000000002';
 cmd uuid:='c1770000-0000-4000-8000-000000000003';old2 uuid:='c1770000-0000-4000-8000-000000000004';
 old1 uuid:='c1770000-0000-4000-8000-000000000005';op uuid:='c1770000-0000-4000-8000-000000000006';
 x jsonb;f jsonb;f2 jsonb;page jsonb;prior jsonb;epoch uuid;r uuid;r2 uuid;cursor jsonb;
 actual text[]:='{}';expected text[];count integer:=0;
BEGIN
 INSERT INTO auth.users(id) VALUES(a);
 INSERT INTO public.users(id,auth_user_id,email,status,timezone,country,country_confirmed)
  VALUES(u,a,'journal-feedback-v3@example.invalid','active','UTC','BR',true);
 x:=pg_temp.thread_v2_register(u,cmd);r:=(x->>'registration_id')::uuid;
 f:=pg_temp.journal_feedback_seal(u,r);
 SELECT e.epoch INTO STRICT epoch FROM private.workout_strength_authority_epochs e WHERE e.user_id=u;
 PERFORM pg_temp.journal_feedback_ok(public.read_conversation_meal_feedback_v2(u,cmd)='{"action":"event_conflict"}',
  'old receipt reader keeps canonical3 fence');
 prior:=pg_temp.semantic_owner_state(u);
 page:=public.read_conversation_journal_page_v3(u,epoch,25);
 PERFORM pg_temp.journal_feedback_ok(page->>'action'='available','genuine canonical3 meal reloads in journal3');
 PERFORM pg_temp.journal_feedback_ok(page#>>'{meal_page,items,0,feedback_ref,schema}'='registration.feedback.v3'
  AND page#>>'{meal_page,items,0,feedback_ref,registration_id}'=r::text,'canonical3 reference names actual saved receipt');
 PERFORM pg_temp.journal_feedback_ok(pg_temp.semantic_owner_state(u)=prior,'history performs no write or reward');
 PERFORM pg_temp.journal_feedback_ok(public.read_conversation_meal_journal_page_v2(u,epoch,25)->>'action'='event_conflict',
  'old journal2 remains unchanged and refuses unsupported canonical3');
 x:=pg_temp.thread_v2_register(u,old2);r2:=(x->>'registration_id')::uuid;f2:=pg_temp.journal_feedback_seal(u,r2,2);
 x:=pg_temp.thread_v2_register(u,old1);PERFORM pg_temp.thread_v2_legacy_feedback(u,old1);
 page:=public.read_conversation_journal_page_v3(u,epoch,25);
 PERFORM pg_temp.journal_feedback_ok(page->>'action'='available' AND jsonb_array_length(page->'items')=3,
  'canonical1 canonical2 canonical3 coexist in same history');
 PERFORM pg_temp.journal_feedback_ok((SELECT array_agg(DISTINCT value#>>'{feedback_ref,schema}' ORDER BY value#>>'{feedback_ref,schema}')
   FROM jsonb_array_elements(page#>'{meal_page,items}'))=ARRAY['registration.feedback.v1','registration.feedback.v2','registration.feedback.v3'],
  'mixed page preserves three original version identities');
 prior:=pg_temp.semantic_owner_state(u);
 LOOP
  x:=public.read_conversation_journal_page_v3(u,epoch,1,cursor);count:=count+1;
  IF count>4 THEN RAISE EXCEPTION 'journal_feedback_paging_loop';END IF;
  PERFORM pg_temp.journal_feedback_ok(x->>'action'='available' AND jsonb_array_length(x->'items')=1,'bounded mixed page '||count);
  actual:=array_append(actual,x#>>'{items,0,event_id}');EXIT WHEN x->'has_more'='false';cursor:=x->'next_cursor';
 END LOOP;
 SELECT array_agg(v->>'event_id' ORDER BY n) INTO expected FROM jsonb_array_elements(page->'items') WITH ORDINALITY q(v,n);
 PERFORM pg_temp.journal_feedback_ok(actual=expected AND cardinality(actual)=3,'mixed keyset pages have no gaps or duplicates');
 PERFORM pg_temp.journal_feedback_ok(pg_temp.semantic_owner_state(u)=prior,'mixed repeated reads preserve all owner rows');
 PERFORM pg_temp.thread_v2_save(u,cmd,op);
 prior:=pg_temp.semantic_owner_state(u);page:=public.read_conversation_journal_page_v3(u,epoch,25);
 PERFORM pg_temp.journal_feedback_ok(page->>'action'='available' AND jsonb_array_length(page->'items')=4,
  'canonical3 saved edit appears without losing original report');
 PERFORM pg_temp.journal_feedback_ok(public.read_mobile_registration_feedback_v3(u,r,'pending_registration')=jsonb_build_object('action','available','feedback',f)
  AND public.read_mobile_registration_feedback_v3(u,r2,'pending_registration')=jsonb_build_object('action','available','feedback',f2),
  'edits never regenerate original canonical3 or canonical2 receipt');
 PERFORM pg_temp.journal_feedback_ok(pg_temp.semantic_owner_state(u)=prior,'post-edit history remains observational');
 PERFORM pg_temp.journal_feedback_ok(public.read_conversation_journal_page_v3(u,gen_random_uuid())='{"action":"stale_epoch"}'
  AND public.read_conversation_journal_page_v3(gen_random_uuid(),epoch)='{"action":"absent"}','owner and epoch isolation retained');
END $direct$;
DO $linked$
DECLARE u uuid:='c1770000-0000-4000-8000-000000000101';a uuid:='c1770000-0000-4000-8000-000000000102';
 parent uuid:='c1770000-0000-4000-8000-000000000103';child uuid:='c1770000-0000-4000-8000-000000000104';
 seed jsonb;s jsonb;body jsonb;ad jsonb;prepared jsonb;fx jsonb;page jsonb;before_state jsonb;f jsonb;r uuid;epoch uuid;
BEGIN
 seed:=pg_temp.continuation_seed(u,a,parent,false);epoch:=(seed#>>'{terminal,epoch}')::uuid;
 s:=pg_temp.continuation_read(u,parent,seed);body:=pg_temp.continuation_body(s,'{"kind":"meal_type","meal_type":"almoco"}');
 ad:=pg_temp.continuation_admit(u,parent,seed,child,body);s:=pg_temp.continuation_read(u,parent,seed,child,ad#>>'{child_binding,input_hash}');
 prepared:=pg_temp.continuation_prepare(u,parent,seed,child,ad#>>'{child_binding,input_hash}',pg_temp.continuation_preparation(s));
 fx:=pg_temp.continuation_commit(u,parent,seed,child,ad#>>'{child_binding,input_hash}',prepared#>>'{stored,prepared_hash}');
 r:=(fx#>>'{fulfillment,receipt,registration_id}')::uuid;f:=pg_temp.journal_feedback_seal(u,r);
 before_state:=pg_temp.semantic_owner_state(u);page:=public.read_conversation_journal_page_v3(u,epoch,25);
 PERFORM pg_temp.journal_feedback_ok(page->>'action'='available','linked canonical3 fulfillment reloads in journal3');
 PERFORM pg_temp.journal_feedback_ok(EXISTS(SELECT 1 FROM jsonb_array_elements(page#>'{meal_page,items}') i
   WHERE i->>'kind'='fulfillment' AND i#>>'{feedback_ref,schema}'='registration.feedback.v3' AND i#>>'{feedback_ref,registration_id}'=r::text),
  'linked fulfillment reference keeps actual canonical3 registration');
 PERFORM pg_temp.journal_feedback_ok(public.read_conversation_meal_feedback_v2(u,child)='{"action":"event_conflict"}'
  AND pg_temp.semantic_owner_state(u)=before_state,'linked old fence and observational history preserved');
END $linked$;
DO $neutral$
DECLARE u uuid:='c1770000-0000-4000-8000-000000000201';a uuid:='c1770000-0000-4000-8000-000000000202';
 intake uuid:='c1770000-0000-4000-8000-000000000203';epoch uuid;child uuid;
 raw jsonb;ad jsonb;source jsonb;claim jsonb;selection jsonb;captured jsonb;prepared jsonb;fx jsonb;page jsonb;prior jsonb;r uuid;
BEGIN
 INSERT INTO auth.users(id) VALUES(a);
 INSERT INTO public.users(id,auth_user_id,email,status,timezone,country,country_confirmed)
  VALUES(u,a,'journal-neutral-feedback-v3@example.invalid','active','UTC','BR',true);
 -- Existing admission initializes the real authority epoch. This pending
 -- original is retained; the neutral child below must never duplicate it.
 PERFORM pg_temp.writer_seed(u,gen_random_uuid());
 SELECT e.epoch INTO STRICT epoch FROM private.workout_strength_authority_epochs e WHERE e.user_id=u;
 raw:=jsonb_build_object('intake_protocol','conversation.intake.v1','intake_id',intake,
  'source',jsonb_build_object('channel','text','text','Comi 100g de arroz sintetico'));
 ad:=public.admit_conversation_intake(u,epoch,raw);
 source:=public.capture_conversation_intake_source(u,intake,ad#>>'{intake,input_hash}',epoch);
 claim:=public.claim_conversation_intake_routing(u,intake,ad#>>'{intake,input_hash}',epoch,source->>'source_hash');
 selection:=public.seal_conversation_intake_routing(u,intake,ad#>>'{intake,input_hash}',epoch,source->>'source_hash',
  (claim->>'claim_id')::uuid,'{"schema":"conversation.intake-routing.v1","kind":"meal.report","reason":"performed_meal"}');
 child:=(selection#>>'{selection,command,command_id}')::uuid;
 captured:=public.capture_conversation_meal_source(u,child);
 prepared:=public.prepare_conversation_meal(u,child,pg_temp.writer_resolved(captured));
 fx:=public.commit_conversation_meal(u,child,prepared->>'resolved_hash');
 PERFORM pg_temp.journal_feedback_ok(fx->>'action'='committed','actual neutral child writer commits before history');
 r:=(fx#>>'{receipt,registration_id}')::uuid;PERFORM pg_temp.journal_feedback_seal(u,r);
 prior:=pg_temp.semantic_owner_state(u);page:=public.read_conversation_journal_page_v3(u,epoch,25);
 PERFORM pg_temp.journal_feedback_ok(page->>'action'='available','neutral canonical3 intake reloads through full lineage');
 PERFORM pg_temp.journal_feedback_ok((SELECT count(*)=1 FROM jsonb_array_elements(page->'items') i
   WHERE i->>'kind'='intake' AND i->>'intake_id'=intake::text)
  AND NOT EXISTS(SELECT 1 FROM jsonb_array_elements(page->'items') i WHERE i->>'event_id'='command/'||child::text),
  'neutral original appears once and typed child stays a dependency');
 PERFORM pg_temp.journal_feedback_ok(EXISTS(SELECT 1 FROM jsonb_array_elements(page#>'{meal_page,items}') i
   WHERE i#>>'{feedback_ref,schema}'='registration.feedback.v3' AND i#>>'{feedback_ref,registration_id}'=r::text)
  AND pg_temp.semantic_owner_state(u)=prior,'neutral canonical3 ref reads without registration or reward duplication');
END $neutral$;
DO $read_boundaries$
DECLARE e private.conversation_meal_effects%ROWTYPE;original private.conversation_meal_effects%ROWTYPE;
 sig text;expected text;actual text;clone text;
BEGIN
 SELECT * INTO STRICT original FROM private.conversation_meal_effects
  WHERE user_id='c1770000-0000-4000-8000-000000000001' AND command_id='c1770000-0000-4000-8000-000000000003';
 PERFORM pg_temp.journal_feedback_ok(private.conversation_journal_feedback_ref_v3(original)->>'schema'='registration.feedback.v3',
  'new private reference follows verified canonical3');
 e:=original;e.command_id:=gen_random_uuid();
 PERFORM pg_temp.journal_feedback_ok(private.conversation_journal_feedback_ref_v3(e)='{"action":"event_conflict"}',
  'canonical3 reference refuses another command identity');
 e:=original;e.receipt:=jsonb_set(e.receipt,'{registration_id}','"invalid-registration"');
 PERFORM pg_temp.journal_feedback_ok(private.conversation_journal_feedback_ref_v3(e)='{"action":"event_conflict"}',
  'malformed registration reference fails closed');
 FOR sig,expected IN SELECT * FROM (VALUES
  ('private.conversation_thread_feedback_ref_v2(private.conversation_meal_effects)',
   'd101186298f711a6ff914bf98d772e7afcde3fb0290772c95b9a9c183cf286b4'),
  ('private.conversation_thread_child_v2(uuid,uuid,jsonb)',
   '9933d32584de6752a17d698b15e9fef1589577a9f09677bbb1910566bccc5e4b'),
  ('private.conversation_thread_entry_v2(uuid,jsonb,jsonb,jsonb)',
   'a9af0f241cd397130db8234beb8926f070407be19014698d93cc8e6104810459'),
  ('private.conversation_meal_feedback_receipt(private.conversation_meal_effects)',
   '47158c4ebfaf3cafd600c094bc53412e615088421e25cc7808784af969f6731d'),
  ('public.read_mobile_registration_feedback_v3(uuid,uuid,text)',
   '381dbb9fb7464bf3cc1e5ebc63ee16d1c68cdf9ec7f1b2aba693151829e517c5')
 ) AS qualified(signature,source_hash) LOOP
  SELECT encode(sha256(convert_to(prosrc,'UTF8')),'hex') INTO actual FROM pg_proc WHERE oid=to_regprocedure(sig);
  PERFORM pg_temp.journal_feedback_ok(actual=expected,'qualified old reader source unchanged '||sig);
 END LOOP;
 FOR sig,clone IN SELECT * FROM (VALUES
  ('private.conversation_thread_child_v2(uuid,uuid,jsonb)','private.conversation_journal_child_v3(uuid,uuid,jsonb)'),
  ('private.conversation_thread_entry_v2(uuid,jsonb,jsonb,jsonb)','private.conversation_journal_entry_v3(uuid,jsonb,jsonb,jsonb)')
 ) AS pairs(original_signature,clone_signature) LOOP
  PERFORM pg_temp.journal_feedback_ok((SELECT prosrc FROM pg_proc WHERE oid=to_regprocedure(sig))=
   replace((SELECT prosrc FROM pg_proc WHERE oid=to_regprocedure(clone)),
    'private.conversation_journal_feedback_ref_v3(','private.conversation_thread_feedback_ref_v2('),
   'factual and lineage validators remain byte-identical '||clone);
 END LOOP;
 PERFORM pg_temp.journal_feedback_ok((SELECT bool_and(NOT has_function_privilege(role_name,signature,'EXECUTE'))
  FROM unnest(ARRAY['anon','authenticated','service_role']) role_name
  CROSS JOIN unnest(ARRAY['private.conversation_journal_feedback_ref_v3(private.conversation_meal_effects)',
   'private.conversation_journal_child_v3(uuid,uuid,jsonb)','private.conversation_journal_entry_v3(uuid,jsonb,jsonb,jsonb)']) signature),
  'new private helpers grant no external execution');
 PERFORM pg_temp.journal_feedback_ok(has_function_privilege('service_role','public.read_conversation_journal_page_v3(uuid,uuid,integer,jsonb)','EXECUTE')
  AND NOT has_function_privilege('anon','public.read_conversation_journal_page_v3(uuid,uuid,integer,jsonb)','EXECUTE')
  AND NOT has_function_privilege('authenticated','public.read_conversation_journal_page_v3(uuid,uuid,integer,jsonb)','EXECUTE'),
  'existing trusted page reader permissions preserved');
END $read_boundaries$;
SELECT count(*) AS journal_feedback_assertions FROM journal_feedback_assertions;
ROLLBACK;
