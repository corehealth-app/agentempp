\ir mobile_reevaluation_photo_fixture.sql

-- Real local allocation/upload/processing authorities; no provider or Storage.
CREATE FUNCTION m3b_cycle_test.process_clinical_photos(c jsonb, initial_reading numeric DEFAULT 18, reading_step numeric DEFAULT 6) RETURNS jsonb
LANGUAGE plpgsql SET search_path=pg_catalog AS $$
DECLARE a uuid:=(c->>'user')::uuid; cycle uuid:=(c->>'cycle')::uuid;
 pose text; asset uuid; ticket uuid; request uuid; reading numeric:=initial_reading;
BEGIN
 FOREACH pose IN ARRAY ARRAY['front','side','back'] LOOP
  c:=c||jsonb_build_object('revision',(SELECT revision::text FROM private.mobile_reevaluation_cycles WHERE cycle_id=cycle));
  asset:=(m3b_cycle_test.allocate(c,gen_random_uuid(),pose)#>>'{asset,id}')::uuid;
  ticket:=gen_random_uuid();request:=gen_random_uuid();
  PERFORM public.prepare_mobile_reevaluation_photo_upload(a,cycle,asset,ticket);
  PERFORM public.register_mobile_reevaluation_photo_upload_ticket(a,cycle,asset,ticket,clock_timestamp()+interval '2 hours');
  PERFORM public.complete_mobile_reevaluation_photo_upload(a,cycle,asset,
   (SELECT source_revision FROM private.mobile_reevaluation_photo_sources WHERE user_id=a AND cycle_id=cycle AND requested_asset_id=asset),
   1200,'image/jpeg',NULL);
  PERFORM public.claim_mobile_reevaluation_photo_processing(a,cycle,asset,request);
  PERFORM public.authorize_mobile_reevaluation_photo_provider(a,cycle,asset,request);
  PERFORM public.complete_mobile_reevaluation_photo_processing(a,cycle,asset,request,
   jsonb_build_object('type','body','view',pose,'bf_percent_estimate',reading));
  reading:=reading+reading_step;
 END LOOP;
 RETURN c||jsonb_build_object('revision',(SELECT revision::text FROM private.mobile_reevaluation_cycles WHERE cycle_id=cycle));
END $$;
CREATE FUNCTION m3b_cycle_test.clinical_photos(n integer) RETURNS jsonb
LANGUAGE plpgsql SET search_path=pg_catalog AS $$
DECLARE c jsonb; a uuid;
BEGIN
 c:=m3b_cycle_test.photo_context(n);a:=(c->>'user')::uuid;
 UPDATE public.user_profiles SET sex='masculino',birth_date='1990-01-01',height_cm=180,
  weight_kg=80,body_fat_percent=24,activity_level='moderado',training_frequency=4,
  hunger_level='moderada',current_protocol='recomposicao',deficit_level=500,updated_at=clock_timestamp()
 WHERE user_id=a;
 RETURN m3b_cycle_test.process_clinical_photos(c);
END $$;
REVOKE ALL ON FUNCTION m3b_cycle_test.process_clinical_photos(jsonb,numeric,numeric),m3b_cycle_test.clinical_photos(integer)
 FROM PUBLIC,anon,authenticated,service_role;
