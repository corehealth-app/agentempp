-- Nominal AFTER-effect failures in the real FULL writer. Local synthetic owners.
-- No provider/Storage, no disabled product trigger, all setup/effects roll back.
BEGIN;
SET LOCAL search_path=pg_catalog;
SET LOCAL statement_timeout='60s';
SELECT set_config('request.jwt.claim.role','service_role',true);
\ir fixtures/mobile_clinical_legacy_transition_fixture.sql

CREATE FUNCTION m3b_cycle_test.effect_state(a uuid) RETURNS jsonb
LANGUAGE sql SET search_path=pg_catalog AS $$
 SELECT m3b_cycle_test.original_state(a)||jsonb_build_object(
 'all_cycles',(SELECT coalesce(jsonb_agg(to_jsonb(x) ORDER BY to_jsonb(x)::text),'[]')
  FROM private.mobile_reevaluation_cycles x WHERE user_id=a),
 'all_start_keys',(SELECT coalesce(jsonb_agg(to_jsonb(x) ORDER BY to_jsonb(x)::text),'[]')
  FROM private.mobile_reevaluation_start_keys x WHERE user_id=a))
$$;

-- TG arguments bind each fault to exactly its synthetic owner and preview.
-- Reaching the named P0001 proves the actual write already happened. A wrong
-- shape raises a different message and cannot satisfy the test oracle.
CREATE FUNCTION m3b_cycle_test.fail_after_full_effect() RETURNS trigger
LANGUAGE plpgsql SET search_path=pg_catalog AS $$
DECLARE n jsonb:=to_jsonb(NEW);o jsonb;stage text:=TG_ARGV[0];good boolean;
BEGIN
 IF n->>'user_id' IS DISTINCT FROM TG_ARGV[1] THEN RETURN NEW; END IF;
 IF TG_OP='UPDATE' THEN o:=to_jsonb(OLD); END IF;
 IF stage='cycle_calendar' AND n->>'status'<>'completed' THEN RETURN NEW; END IF;
 IF stage='seal_consent' AND (n->>'revoked_at' IS NULL OR o->>'revoked_at' IS NOT NULL) THEN RETURN NEW; END IF;
 IF stage='seal_asset' AND (n->>'invalidated_at' IS NULL OR o->>'invalidated_at' IS NOT NULL) THEN RETURN NEW; END IF;
 IF stage='clear_cas' AND (n->>'hold_active'<>'false' OR o->>'hold_active'<>'true') THEN RETURN NEW; END IF;
 IF stage='bf_head_update' AND n->>'review_id' IS NULL THEN RETURN NEW; END IF;
 good:=CASE stage
  WHEN 'profile_input' THEN (n->>'weight_kg')::numeric=84 AND (o->>'weight_kg')::numeric=80
  WHEN 'weight' THEN (n->>'weight_kg')::numeric=84 AND n->>'instant_source'='recorded' AND n->>'authority_epoch' IS NOT NULL
  WHEN 'bf_profile' THEN (n->>'body_fat_percent')::numeric=24 AND n->>'body_fat_measured_at' IS NOT NULL
   AND n->>'body_fat_measured_at' IS DISTINCT FROM o->>'body_fat_measured_at'
  WHEN 'seal_header' THEN n->>'reason'='completed' AND (n->>'manifest_count')::integer=3
  WHEN 'seal_manifest' THEN n->>'disposition_id' IS NOT NULL AND n->>'asset_id' IS NOT NULL
  WHEN 'seal_consent' THEN n->>'revoked_reason'='completed'
  WHEN 'seal_asset' THEN n->>'invalidated_reason'='completed'
  WHEN 'cycle_calendar' THEN n->>'completed_at' IS NOT NULL AND (n->>'revision')::bigint>(o->>'revision')::bigint
  WHEN 'clear_receipt' THEN n->>'review_id'=TG_ARGV[2] AND n->>'professional_conversation_confirmed'='true'
   AND (n->>'safety_revision')::bigint=(n->>'previous_safety_revision')::bigint+1
  WHEN 'clear_cas' THEN (n->>'safety_revision')::bigint=(o->>'safety_revision')::bigint+1 AND n->'items'='[]'::jsonb
  WHEN 'day_insert' THEN (n->>'calories_target')::integer=1599 AND (n->>'protein_target')::numeric=126
  WHEN 'day_update' THEN (n->>'calories_target')::integer=1599 AND (n->>'protein_target')::numeric=126
   AND (n->>'calories_consumed')::numeric=222 AND (n->>'exercise_calories')::numeric=55
  WHEN 'day_event' THEN n->>'review_id'=TG_ARGV[2] AND (n->>'calories_target')::integer=1599
  WHEN 'progress_calendar' THEN (n->>'current_weight')::numeric=84 AND (n->>'current_bf_percent')::numeric=24
   AND (n->>'next_reevaluation')::date=(clock_timestamp() AT TIME ZONE 'America/Sao_Paulo')::date+14
  WHEN 'episode' THEN n->>'review_id'=TG_ARGV[2] AND n->>'entry_origin'='legacy_unknown'
  WHEN 'responses' THEN n->>'review_id'=TG_ARGV[2] AND (n#>>'{form,answers,weightKg}')::numeric=84
   AND n#>>'{intent,bodyFat,confirmed}'='true' AND n#>>'{proposal,principal}'='keep'
  WHEN 'full_receipt' THEN n->>'review_id'=TG_ARGV[2] AND n#>>'{result,status}'='confirmed'
   AND n->>'completed_at' IS NOT NULL AND n->>'final_cycle_revision' IS NOT NULL
  WHEN 'bf_receipt' THEN n->>'review_id'=TG_ARGV[2] AND (n->>'mean_percent')::numeric=24
   AND jsonb_array_length(n->'sources')=3 AND length(n->>'source_hash')=64
  WHEN 'bf_head_insert' THEN n->>'review_id'=TG_ARGV[2]
  WHEN 'bf_head_update' THEN n->>'review_id'=TG_ARGV[2]
  WHEN 'confirmation_key' THEN n->>'review_id'=TG_ARGV[2] AND n->>'operation_key'=TG_ARGV[3]
  ELSE false END;
 IF good IS DISTINCT FROM true THEN
  RAISE EXCEPTION 'M3B_EFFECT_SHAPE_MISMATCH:%:%',stage,TG_OP USING ERRCODE='P0001';
 END IF;
 RAISE EXCEPTION 'M3B_EFFECT_REACHED:%:%',stage,TG_OP USING ERRCODE='P0001';
END $$;

DO $effects$
DECLARE stage record;c jsonb;a uuid;q jsonb;k uuid;before_rows jsonb;result jsonb;
 err_state text;err_message text;idx integer:=6100;day date:=(clock_timestamp() AT TIME ZONE 'America/Sao_Paulo')::date;
 neighbor uuid;neighbor_before jsonb;
BEGIN
 neighbor:=m3b_cycle_test.seed(6099,NULL);neighbor_before:=m3b_cycle_test.effect_state(neighbor);
 FOR stage IN SELECT * FROM (VALUES
  ('profile_input','public.user_profiles','UPDATE OF weight_kg','UPDATE'),
  ('weight','private.mobile_weight_measurements','INSERT','INSERT'),
  ('bf_profile','public.user_profiles','UPDATE OF body_fat_percent','UPDATE'),
  ('seal_header','private.mobile_reevaluation_photo_dispositions','INSERT','INSERT'),
  ('seal_manifest','private.mobile_reevaluation_photo_disposition_assets','INSERT','INSERT'),
  ('seal_consent','private.mobile_reevaluation_photo_consents','UPDATE','UPDATE'),
  ('seal_asset','private.mobile_reevaluation_photo_assets','UPDATE','UPDATE'),
  ('cycle_calendar','private.mobile_reevaluation_cycles','UPDATE','UPDATE'),
  ('clear_receipt','private.mobile_clinical_health_clear_receipts','INSERT','INSERT'),
  ('clear_cas','private.mobile_health_hold_states','UPDATE','UPDATE'),
  ('day_insert','public.daily_snapshots','INSERT','INSERT'),
  ('day_update','public.daily_snapshots','UPDATE','UPDATE'),
  ('day_event','private.mobile_clinical_day_events','INSERT','INSERT'),
  ('progress_calendar','public.user_progress','UPDATE','UPDATE'),
  ('episode','private.mobile_clinical_episode_events','INSERT','INSERT'),
  ('responses','private.mobile_clinical_full_receipts','INSERT','INSERT'),
  ('full_receipt','private.mobile_clinical_full_receipts','INSERT','INSERT'),
  ('bf_receipt','private.mobile_clinical_body_fat_receipts','INSERT','INSERT'),
  ('bf_head_insert','private.mobile_clinical_body_fat_heads','INSERT','INSERT'),
  ('confirmation_key','private.mobile_clinical_confirmation_keys','INSERT','INSERT')
 ) v(label,relation,event,operation) LOOP
  idx:=idx+1;k:=gen_random_uuid();
  c:=m3b_cycle_test.process_clinical_photos(m3b_cycle_test.legacy_photo_context(idx));a:=(c->>'user')::uuid;
  INSERT INTO public.user_progress(user_id,xp_total,current_weight,current_bf_percent,next_reevaluation)
   VALUES(a,17,80,24,day-1);
  IF stage.label IN('clear_receipt','clear_cas') THEN
   UPDATE public.user_profiles SET sex='feminino' WHERE user_id=a;
   PERFORM public.declare_mobile_health_risk(a,gen_random_uuid(),ARRAY['reduced_intake','professional_diet','pregnant_or_breastfeeding']);
  END IF;
  IF stage.label='day_update' THEN
   INSERT INTO public.daily_snapshots(user_id,date,calories_target,protein_target,current_protocol,calories_consumed,exercise_calories)
    VALUES(a,day,1700,120,'recomposicao',222,55);
  END IF;
  q:=m3b_cycle_test.legacy_clinical_request(c,84,stage.label IN('clear_receipt','clear_cas'));
  before_rows:=m3b_cycle_test.effect_state(a);
  EXECUTE format('CREATE TRIGGER synthetic_after_full_effect AFTER %s ON %s FOR EACH ROW EXECUTE FUNCTION m3b_cycle_test.fail_after_full_effect(%L,%L,%L,%L)',
   stage.event,stage.relation,stage.label,a,q#>>'{preview,preview_id}',k);
  err_state:=NULL;err_message:=NULL;
  BEGIN
   PERFORM private.confirm_mobile_clinical_preview_at(a,(q#>>'{preview,preview_id}')::uuid,k,q->'form',q->'intent',q->'proposal',NULL);
  EXCEPTION WHEN OTHERS THEN
   GET STACKED DIAGNOSTICS err_state=RETURNED_SQLSTATE,err_message=MESSAGE_TEXT;
  END;
  EXECUTE format('DROP TRIGGER synthetic_after_full_effect ON %s',stage.relation);
  PERFORM m3b_cycle_test.ok(err_state='P0001' AND err_message='M3B_EFFECT_REACHED:'||stage.label||':'||stage.operation,
   'actual AFTER effect reached: '||stage.label||' ['||coalesce(err_message,'no exception')||']');
  PERFORM m3b_cycle_test.ok(before_rows=m3b_cycle_test.effect_state(a),
   'every owner row plus cycles/start keys rolls back: '||stage.label);
  result:=private.confirm_mobile_clinical_preview_at(a,(q#>>'{preview,preview_id}')::uuid,k,q->'form',q->'intent',q->'proposal',NULL);
  PERFORM m3b_cycle_test.ok(result->>'status'='confirmed' AND result->>'review_id'=q#>>'{preview,preview_id}',
   'same preview/key remains recoverable after known rollback: '||stage.label);
  PERFORM m3b_cycle_test.ok(neighbor_before=m3b_cycle_test.effect_state(neighbor),'neighbor preserved: '||stage.label);
 END LOOP;
END $effects$;

DO $locale$
DECLARE c jsonb;a uuid;q jsonb;k uuid:=gen_random_uuid();before_rows jsonb;result jsonb;err_state text;
BEGIN
 c:=m3b_cycle_test.process_clinical_photos(m3b_cycle_test.legacy_photo_context(6150));a:=(c->>'user')::uuid;
 q:=m3b_cycle_test.legacy_clinical_request(c);
 PERFORM m3b_cycle_test.ok(q#>>'{context,facts,owner,locale}'='pt-BR','FULL prepared against valid pt-BR locale');
 UPDATE public.users SET locale='en-US' WHERE id=a;
 before_rows:=m3b_cycle_test.effect_state(a);
 BEGIN
  PERFORM private.confirm_mobile_clinical_preview_at(a,(q#>>'{preview,preview_id}')::uuid,k,q->'form',q->'intent',q->'proposal',NULL);
 EXCEPTION WHEN OTHERS THEN GET STACKED DIAGNOSTICS err_state=RETURNED_SQLSTATE; END;
 PERFORM m3b_cycle_test.ok(err_state='40001' AND before_rows=m3b_cycle_test.effect_state(a),
  'valid locale switch after prepare rejects the entire fresh FULL without any write');
 c:=m3b_cycle_test.process_clinical_photos(m3b_cycle_test.legacy_photo_context(6151));a:=(c->>'user')::uuid;
 q:=m3b_cycle_test.legacy_clinical_request(c);k:=gen_random_uuid();
 result:=private.confirm_mobile_clinical_preview_at(a,(q#>>'{preview,preview_id}')::uuid,k,q->'form',q->'intent',q->'proposal',NULL);
 UPDATE public.users SET locale='en-US' WHERE id=a;before_rows:=m3b_cycle_test.effect_state(a);
 PERFORM m3b_cycle_test.ok(result=private.confirm_mobile_clinical_preview_at(a,(q#>>'{preview,preview_id}')::uuid,k,q->'form',q->'intent',q->'proposal',NULL)
  AND before_rows=m3b_cycle_test.effect_state(a),'already confirmed ACK wins before locale recapture and creates no effects');
END $locale$;

-- The second actual FULL uses explicit PRIVATE local clocks. This proves the
-- UPDATE arm of the numeric-origin head, not an elapsed fortnight in staging.
CREATE FUNCTION m3b_cycle_test.effect_future_photos(a uuid,cycle uuid,at_time timestamptz) RETURNS void
LANGUAGE plpgsql SET search_path=pg_catalog AS $$
DECLARE doc public.legal_documents%ROWTYPE;consent jsonb;asset uuid;ticket uuid;request uuid;pose text;reading numeric:=18;
BEGIN
 SELECT * INTO STRICT doc FROM public.legal_documents WHERE id=m3b_cycle_test.uid(501);
 consent:=private.accept_mobile_reevaluation_photo_consent_at(a,cycle,
  (SELECT revision FROM private.mobile_reevaluation_cycles WHERE cycle_id=cycle),doc.id,doc.document_key,
  doc.version,doc.locale,doc.body_hash,gen_random_uuid(),at_time);
 FOREACH pose IN ARRAY ARRAY['front','side','back'] LOOP
  asset:=(private.create_mobile_reevaluation_photo_asset_at(a,cycle,
   (SELECT revision FROM private.mobile_reevaluation_cycles WHERE cycle_id=cycle),
   (consent#>>'{acceptance,acceptance_id}')::uuid,pose,'image/jpeg',1200,gen_random_uuid(),at_time)#>>'{asset,id}')::uuid;
  ticket:=gen_random_uuid();request:=gen_random_uuid();
  PERFORM private.prepare_mobile_reevaluation_photo_upload_at(a,cycle,asset,ticket,at_time);
  PERFORM private.register_mobile_reevaluation_photo_upload_ticket_at(a,cycle,asset,ticket,at_time+interval '2 hours',at_time);
  PERFORM private.complete_mobile_reevaluation_photo_upload_at(a,cycle,asset,
   (SELECT source_revision FROM private.mobile_reevaluation_photo_sources WHERE user_id=a
    AND cycle_id=effect_future_photos.cycle AND requested_asset_id=asset),1200,'image/jpeg',NULL,at_time);
  PERFORM private.claim_mobile_reevaluation_photo_processing_at(a,cycle,asset,request,at_time);
  PERFORM private.authorize_mobile_reevaluation_photo_provider_at(a,cycle,asset,request,at_time);
  PERFORM private.complete_mobile_reevaluation_photo_processing_at(a,cycle,asset,request,
   jsonb_build_object('type','body','view',pose,'bf_percent_estimate',reading),at_time);
  reading:=reading+6;
 END LOOP;
END $$;

DO $head_update$
DECLARE c jsonb;a uuid;q jsonb;r jsonb;ctx jsonb;f jsonb;i jsonb;p jsonb;cycle uuid;
 k uuid:=gen_random_uuid();future_at timestamptz;before_rows jsonb;code text;message text;old_review uuid;
BEGIN
 c:=m3b_cycle_test.process_clinical_photos(m3b_cycle_test.legacy_photo_context(6152));a:=(c->>'user')::uuid;
 q:=m3b_cycle_test.legacy_clinical_request(c);
 r:=private.confirm_mobile_clinical_preview_at(a,(q#>>'{preview,preview_id}')::uuid,gen_random_uuid(),q->'form',q->'intent',q->'proposal',NULL);
 old_review:=(r->>'review_id')::uuid;future_at:=(r->>'completed_at')::timestamptz+interval '15 days';
 cycle:=(private.start_mobile_clinical_full_at(a,gen_random_uuid(),'REGULAR',NULL,future_at)#>>'{cycle,id}')::uuid;
 PERFORM m3b_cycle_test.effect_future_photos(a,cycle,future_at);
 ctx:=private.capture_mobile_clinical_context_at(a,'REGULAR',cycle,future_at);
 f:=jsonb_set(q->'form','{kind}','"REGULAR"');
 i:=jsonb_build_object('principalConfirmed',false,'bodyFat',jsonb_build_object('confirmed',true,
  'sourceHash',ctx#>'{facts,protocol_authority,body_fat_candidate,source_hash}',
  'meanHundredths',ctx#>'{facts,protocol_authority,body_fat_candidate,mean_hundredths}'));
 p:=jsonb_set(jsonb_set(q->'proposal','{targets,beforeKcal}',coalesce(ctx#>'{facts,day,calories_target}','null'::jsonb)),
  '{targets,beforeProtein}',coalesce(ctx#>'{facts,day,protein_target}','null'::jsonb));
 p:=jsonb_set(p,'{episode,difficultyCount}','0');
 q:=jsonb_build_object('form',f,'intent',i,'proposal',p,'preview',
  private.prepare_mobile_clinical_preview_at(a,'REGULAR',cycle,gen_random_uuid(),ctx->>'context_hash',f,i,p,future_at));
 before_rows:=m3b_cycle_test.effect_state(a);
 EXECUTE format('CREATE TRIGGER synthetic_after_full_effect AFTER UPDATE ON private.mobile_clinical_body_fat_heads
  FOR EACH ROW EXECUTE FUNCTION m3b_cycle_test.fail_after_full_effect(%L,%L,%L,%L)',
  'bf_head_update',a,q#>>'{preview,preview_id}',k);
 BEGIN
  PERFORM private.confirm_mobile_clinical_preview_at(a,(q#>>'{preview,preview_id}')::uuid,k,f,i,p,future_at);
 EXCEPTION WHEN OTHERS THEN GET STACKED DIAGNOSTICS code=RETURNED_SQLSTATE,message=MESSAGE_TEXT; END;
 DROP TRIGGER synthetic_after_full_effect ON private.mobile_clinical_body_fat_heads;
 PERFORM m3b_cycle_test.ok(code='P0001' AND message='M3B_EFFECT_REACHED:bf_head_update:UPDATE',
  'actual second FULL reaches BF head UPDATE ['||coalesce(message,'none')||']');
 PERFORM m3b_cycle_test.ok(before_rows=m3b_cycle_test.effect_state(a)
  AND (SELECT review_id=old_review FROM private.mobile_clinical_body_fat_heads WHERE user_id=a),
  'late UPDATE fault restores original head and all prior/new clinical rows');
 r:=private.confirm_mobile_clinical_preview_at(a,(q#>>'{preview,preview_id}')::uuid,k,f,i,p,future_at);
 PERFORM m3b_cycle_test.ok(r->>'status'='confirmed' AND r->>'kind'='REGULAR'
  AND (SELECT count(*)=2 FROM private.mobile_clinical_body_fat_receipts WHERE user_id=a)
  AND (SELECT review_id=(r->>'review_id')::uuid FROM private.mobile_clinical_body_fat_heads WHERE user_id=a),
  'same second FULL preview/key succeeds and preserves immutable first numeric receipt');
END $head_update$;

DO $closed_day$
DECLARE c jsonb;a uuid;q jsonb;r jsonb;before_day jsonb;
 day date:=(clock_timestamp() AT TIME ZONE 'America/Sao_Paulo')::date;
BEGIN
 c:=m3b_cycle_test.process_clinical_photos(m3b_cycle_test.legacy_photo_context(6153));a:=(c->>'user')::uuid;
 INSERT INTO public.daily_snapshots(user_id,date,calories_target,protein_target,current_protocol,
  calories_consumed,exercise_calories,day_closed,closed_at)
 VALUES(a,day,1700,120,'recomposicao',222,55,true,clock_timestamp());
 SELECT to_jsonb(x) INTO before_day FROM public.daily_snapshots x WHERE user_id=a AND date=day;
 q:=m3b_cycle_test.legacy_clinical_request(c);
 r:=private.confirm_mobile_clinical_preview_at(a,(q#>>'{preview,preview_id}')::uuid,gen_random_uuid(),q->'form',q->'intent',q->'proposal',NULL);
 PERFORM m3b_cycle_test.ok(r->>'status'='confirmed'
  AND before_day=(SELECT to_jsonb(x) FROM public.daily_snapshots x WHERE user_id=a AND date=day)
  AND NOT EXISTS(SELECT 1 FROM private.mobile_clinical_day_events WHERE user_id=a),
  'closed current day is byte exact: FULL creates neither target overwrite nor target ledger');
END $closed_day$;

REVOKE ALL ON ALL FUNCTIONS IN SCHEMA m3b_cycle_test FROM PUBLIC,anon,authenticated,service_role;
ROLLBACK;
