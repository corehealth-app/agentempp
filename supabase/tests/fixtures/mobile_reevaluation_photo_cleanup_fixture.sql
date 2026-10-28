\ir mobile_reevaluation_photo_fixture.sql

CREATE FUNCTION m3b_cycle_test.cleanup_context(n integer,age_seconds integer DEFAULT 0) RETURNS jsonb
LANGUAGE plpgsql SET search_path=pg_catalog AS $$
DECLARE a uuid;c uuid;t timestamptz:=clock_timestamp()-make_interval(secs=>age_seconds);doc public.legal_documents%ROWTYPE;r jsonb;ctx jsonb;aid uuid;
BEGIN
 a:=m3b_cycle_test.seed(n,'2026-10-01T23:00:00Z');
 SELECT * INTO doc FROM public.legal_documents WHERE id=m3b_cycle_test.uid(5499);
 IF NOT FOUND THEN
  INSERT INTO public.legal_documents(id,document_key,version,locale,body,required_from)
   VALUES(m3b_cycle_test.uid(5499),'body_photo_reevaluation_consent','normal-cleanup-local','pt-BR','SYNTHETIC LOCAL 24H RETENTION','2026-10-01T00:00:00Z') RETURNING * INTO doc;
  INSERT INTO private.mobile_reevaluation_photo_policies(document_id,document_key,version,locale,body_hash,idle_timeout_seconds,enabled)
   VALUES(doc.id,doc.document_key,doc.version,doc.locale,doc.body_hash,86400,true);
 END IF;
 c:=(private.start_mobile_reevaluation_cycle_at(a,gen_random_uuid(),t)#>>'{cycle,id}')::uuid;
 r:=private.accept_mobile_reevaluation_photo_consent_at(a,c,1,doc.id,doc.document_key,doc.version,doc.locale,doc.body_hash,gen_random_uuid(),t);
 ctx:=jsonb_build_object('user',a,'cycle',c,'acceptance',r#>'{acceptance,acceptance_id}','revision',r->'cycle_revision');
 aid:=(m3b_cycle_test.allocate(ctx,gen_random_uuid(),'front',1200,t)#>>'{asset,id}')::uuid;
 RETURN ctx||jsonb_build_object('asset',aid);
END $$;
