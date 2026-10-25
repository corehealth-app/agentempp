\ir mobile_reevaluation_cycle_fixture.sql

CREATE FUNCTION m3b_cycle_test.photo_context(n integer) RETURNS jsonb
LANGUAGE plpgsql SET search_path=pg_catalog AS $$
DECLARE a uuid; c uuid; doc public.legal_documents%ROWTYPE; consent jsonb;
BEGIN
  a:=m3b_cycle_test.seed(n,'2026-10-01T23:00:00Z');
  c:=(public.start_mobile_reevaluation_cycle(a,gen_random_uuid())#>>'{cycle,id}')::uuid;
  SELECT * INTO doc FROM public.legal_documents WHERE id=m3b_cycle_test.uid(501);
  IF NOT FOUND THEN
    INSERT INTO public.legal_documents(id,document_key,version,locale,body,required_from)
      VALUES(m3b_cycle_test.uid(501),'body_photo_reevaluation_consent','asset-local-1','pt-BR',
        'SYNTHETIC LOCAL PHOTO ALLOCATION','2026-10-20T00:00:00Z') RETURNING * INTO doc;
    INSERT INTO private.mobile_reevaluation_photo_policies(document_id,document_key,version,
      locale,body_hash,idle_timeout_seconds,enabled)
      VALUES(doc.id,doc.document_key,doc.version,doc.locale,doc.body_hash,60,true);
  END IF;
  consent:=public.accept_mobile_reevaluation_photo_consent(a,c,1,doc.id,doc.document_key,
    doc.version,doc.locale,doc.body_hash,gen_random_uuid());
  RETURN jsonb_build_object('user',a,'cycle',c,'revision',consent->'cycle_revision',
    'acceptance',consent#>'{acceptance,acceptance_id}',
    'accepted_at',consent#>'{acceptance,accepted_at}');
END $$;

CREATE FUNCTION m3b_cycle_test.allocate(ctx jsonb,k uuid,pose text DEFAULT 'front',
  size_bytes bigint DEFAULT 1200,at_time timestamptz DEFAULT NULL) RETURNS jsonb
LANGUAGE plpgsql SET search_path=pg_catalog AS $$
BEGIN
  RETURN private.create_mobile_reevaluation_photo_asset_at((ctx->>'user')::uuid,
    (ctx->>'cycle')::uuid,(ctx->>'revision')::bigint,(ctx->>'acceptance')::uuid,
    pose,'image/jpeg',size_bytes,k,at_time);
END $$;

CREATE FUNCTION m3b_cycle_test.ordinary_asset(owner_id uuid,k text DEFAULT 'body_checkin_photo')
RETURNS uuid LANGUAGE plpgsql SET search_path=pg_catalog AS $$
DECLARE asset_id uuid:=gen_random_uuid(); bucket text;
BEGIN
  bucket:=CASE k WHEN 'meal_photo' THEN 'meal-photos' ELSE 'body-checkin-photos' END;
  INSERT INTO public.media_assets(id,user_id,kind,bucket_id,object_path,mime_type,
    declared_size_bytes,actual_size_bytes,status,context_text,source_request_hash,
    retention_until,uploaded_at,signup_origin)
    VALUES(asset_id,owner_id,k,bucket,owner_id::text||'/'||asset_id::text||'.jpg',
      'image/jpeg',1200,1200,'uploaded','Foto de frente.',
      encode(extensions.digest(asset_id::text,'sha256'),'hex'),clock_timestamp()+interval '1hour',
      clock_timestamp(),false);
  RETURN asset_id;
END $$;
REVOKE ALL ON ALL FUNCTIONS IN SCHEMA m3b_cycle_test FROM PUBLIC,anon,authenticated,service_role;
