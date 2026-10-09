-- Local synthetic transaction only. No cloud/patient data; all records roll back.
BEGIN;
SET LOCAL request.jwt.claims = '{"role":"service_role"}';

CREATE FUNCTION pg_temp.c11_state(owner_id uuid, snapshot_id uuid, anchor_id uuid)
RETURNS jsonb LANGUAGE sql AS $$
  SELECT jsonb_build_object('context', jsonb_build_object('id', u.id, 'auth_user_id', u.auth_user_id,
    'country', u.country, 'country_confirmed', u.country_confirmed, 'timezone', u.timezone,
    'status', u.status, 'wpp', u.wpp, 'updated_at', u.updated_at), 'snapshot', to_jsonb(s),
    'items', (SELECT jsonb_agg(to_jsonb(m) ORDER BY m.id) FROM public.meal_logs m
      WHERE m.user_id = u.id AND m.snapshot_id = s.id AND
        ((a.raw_provider_message_id IS NULL AND m.id = a.id) OR
          (a.raw_provider_message_id IS NOT NULL AND m.raw_provider_message_id = a.raw_provider_message_id))))
  FROM public.users u JOIN public.daily_snapshots s ON s.user_id = u.id
    JOIN public.meal_logs a ON a.user_id = u.id AND a.snapshot_id = s.id
  WHERE u.id = $1 AND s.id = $2 AND a.id = $3
$$;

DO $access$
DECLARE
  signature text := 'public.mutate_mobile_confirmed_meal(uuid,text,text,text,text,uuid,text,uuid[],jsonb,jsonb,text,jsonb,text)';
  did_fail boolean := false;
BEGIN
  IF has_function_privilege('anon',signature,'EXECUTE')
    OR has_function_privilege('authenticated',signature,'EXECUTE')
    OR NOT has_function_privilege('service_role',signature,'EXECUTE') THEN
    RAISE EXCEPTION 'confirmed mutation backend-only ACL failed';
  END IF;
  -- Even an executing backend connection cannot smuggle an authenticated JWT role.
  PERFORM set_config('request.jwt.claims','{"role":"authenticated"}',true);
  BEGIN
    PERFORM public.mutate_mobile_confirmed_meal(NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL);
  EXCEPTION WHEN insufficient_privilege THEN did_fail := true;
  END;
  IF NOT did_fail THEN RAISE EXCEPTION 'untrusted JWT role accepted'; END IF;
  PERFORM set_config('request.jwt.claims','{"role":"service_role"}',true);
END;
$access$;

-- Same mixed-group review scenario as the HTTP test; calendar follows the live official clock.
-- On09October: Honolulu00:30 anchor=10:30Z; previous-day14:30 sibling=00:30Z.
DO $mixed_group$
DECLARE
  owner_id uuid := 'c1410000-0000-4000-8000-000000000001';
  auth_id uuid := 'c1410000-0000-4000-8000-000000000002';
  snapshot_id uuid := 'c1410000-0000-4000-8000-000000000003';
  anchor_id uuid := 'c1410000-0000-4000-8000-000000000004';
  sibling_id uuid := 'c1410000-0000-4000-8000-000000000005';
  local_day date := (clock_timestamp() AT TIME ZONE 'Pacific/Honolulu')::date;
  state jsonb;
  before_failure jsonb;
  after_failure jsonb;
  method text;
  did_fail boolean;
BEGIN
  INSERT INTO auth.users(id) VALUES(auth_id);
  INSERT INTO public.users(id,auth_user_id,timezone,country,country_confirmed,status)
    VALUES(owner_id,auth_id,'Pacific/Honolulu','BR',true,'active');
  INSERT INTO public.daily_snapshots(id,user_id,date,calories_target,protein_target,calories_consumed,protein_g,carbs_g,fat_g)
    VALUES(snapshot_id,owner_id,local_day,1900,120,155,23,4.5,4.75);
  INSERT INTO public.meal_logs(id,user_id,snapshot_id,food_name,quantity_g,kcal,protein_g,carbs_g,fat_g,source,confidence,consumed_at,meal_type,raw_provider_message_id)
    VALUES(anchor_id,owner_id,snapshot_id,'iogurte natural',85,55,3,4.5,2.75,'product_label',0.93,
      (local_day::timestamp + interval '30 minutes') AT TIME ZONE 'Pacific/Honolulu','almoco','c11-mixed-group'),
      (sibling_id,owner_id,snapshot_id,'frango grelhado',120,100,20,0,2,'legacy_estimate',NULL,
      ((local_day - 1)::timestamp + interval '14 hours 30 minutes') AT TIME ZONE 'Pacific/Honolulu','jantar','c11-mixed-group');
  state := pg_temp.c11_state(owner_id,snapshot_id,anchor_id);
  SELECT jsonb_build_object('snapshot',(SELECT to_jsonb(s) FROM public.daily_snapshots s WHERE id=snapshot_id),
    'logs',(SELECT jsonb_agg(to_jsonb(m) ORDER BY id) FROM public.meal_logs m WHERE user_id=owner_id),
    'ledger',(SELECT jsonb_agg(to_jsonb(l) ORDER BY id) FROM public.mobile_api_idempotency l WHERE user_id=owner_id)) INTO before_failure;
  FOREACH method IN ARRAY ARRAY['PATCH','DELETE'] LOOP
    did_fail := false;
    BEGIN
      PERFORM public.mutate_mobile_confirmed_meal(owner_id,'c11-mixed-' || method,method,
        '/api/mobile/v1/meal-records/' || anchor_id,repeat('b',64),anchor_id,'v1:' || repeat('a',64),
        ARRAY[anchor_id],state,
        CASE WHEN method='PATCH' THEN '[{"food_name":"iogurte natural","quantity_g":170,"kcal":110,"protein_g":6,"carbs_g":9,"fat_g":5.5,"source":"product_label","food_db_id":null,"confidence":0.93}]'::jsonb ELSE NULL END,
        CASE WHEN method='PATCH' THEN 'quantity_only' ELSE NULL END,
        CASE WHEN method='PATCH' THEN '{"quantity_g":170}'::jsonb ELSE NULL END,'synthetic-mixed-request');
    EXCEPTION WHEN serialization_failure THEN did_fail := true;
    END;
    SELECT jsonb_build_object('snapshot',(SELECT to_jsonb(s) FROM public.daily_snapshots s WHERE id=snapshot_id),
      'logs',(SELECT jsonb_agg(to_jsonb(m) ORDER BY id) FROM public.meal_logs m WHERE user_id=owner_id),
      'ledger',(SELECT jsonb_agg(to_jsonb(l) ORDER BY id) FROM public.mobile_api_idempotency l WHERE user_id=owner_id)) INTO after_failure;
    IF NOT did_fail OR before_failure IS DISTINCT FROM after_failure THEN
      RAISE EXCEPTION 'mixed previous-day sibling allowed % or changed rows/ledger',method;
    END IF;
  END LOOP;
END;
$mixed_group$;

-- Literal JS/PG product goldens: half, nonintegral ratio, rescale from persisted rounded values.
DO $rounding$
DECLARE
  owner_id uuid := 'c1420000-0000-4000-8000-000000000001';
  auth_id uuid := 'c1420000-0000-4000-8000-000000000002';
  snapshot_id uuid := 'c1420000-0000-4000-8000-000000000003';
  anchor_id uuid := 'c1420000-0000-4000-8000-000000000004';
  local_day date := (clock_timestamp() AT TIME ZONE 'UTC')::date;
  old_values jsonb;
  expected_values jsonb;
  golden jsonb;
  state jsonb;
  result jsonb;
  persisted public.meal_logs%ROWTYPE;
  index integer := 0;
BEGIN
  INSERT INTO auth.users(id) VALUES(auth_id);
  INSERT INTO public.users(id,auth_user_id,timezone,country,country_confirmed,status)
    VALUES(owner_id,auth_id,'UTC','BR',true,'active');
  INSERT INTO public.daily_snapshots(id,user_id,date,calories_target,protein_target)
    VALUES(snapshot_id,owner_id,local_day,1900,120);
  INSERT INTO public.meal_logs(id,user_id,snapshot_id,food_name,quantity_g,kcal,protein_g,carbs_g,fat_g,source,confidence,consumed_at,meal_type,raw_provider_message_id)
    VALUES(anchor_id,owner_id,snapshot_id,'iogurte natural',100,11.1,2.01,2.03,2.05,'product_label',0.92,clock_timestamp(),'almoco','c11-rounding');
  FOR golden IN SELECT value FROM jsonb_array_elements('[
    {"old":[100,11.1,2.01,2.03,2.05],"new":[50,5.6,1.01,1.02,1.03]},
    {"old":[100,11.1,2.01,2.03,2.05],"new":[33,3.7,0.66,0.67,0.68]},
    {"old":[50,5.6,1.01,1.02,1.03],"new":[100,11.2,2.02,2.04,2.06]}
  ]'::jsonb) LOOP
    index := index + 1;
    old_values := golden->'old'; expected_values := golden->'new';
    UPDATE public.meal_logs SET quantity_g=(old_values->>0)::numeric,kcal=(old_values->>1)::numeric,
      protein_g=(old_values->>2)::numeric,carbs_g=(old_values->>3)::numeric,fat_g=(old_values->>4)::numeric WHERE id=anchor_id;
    UPDATE public.daily_snapshots SET calories_consumed=round((old_values->>1)::numeric),
      protein_g=(old_values->>2)::numeric,carbs_g=(old_values->>3)::numeric,fat_g=(old_values->>4)::numeric WHERE id=snapshot_id;
    state := pg_temp.c11_state(owner_id,snapshot_id,anchor_id);
    result := public.mutate_mobile_confirmed_meal(owner_id,'c11-rounding-' || index,'PATCH',
      '/api/mobile/v1/meal-records/' || anchor_id,repeat('b',64),anchor_id,'v1:' || repeat('a',64),ARRAY[anchor_id],state,
      jsonb_build_array(jsonb_build_object('food_name','iogurte natural','quantity_g',expected_values->0,'kcal',expected_values->1,
        'protein_g',expected_values->2,'carbs_g',expected_values->3,'fat_g',expected_values->4,'source','product_label','food_db_id',NULL,'confidence',0.92)),
      'quantity_only',jsonb_build_object('quantity_g',expected_values->0),'synthetic-rounding');
    anchor_id := (result#>>'{response_body,data,next_record_id}')::uuid;
    SELECT * INTO persisted FROM public.meal_logs WHERE id=anchor_id;
    IF result->>'action' IS DISTINCT FROM 'completed'
      OR jsonb_build_array(persisted.quantity_g,persisted.kcal,persisted.protein_g,persisted.carbs_g,persisted.fat_g) IS DISTINCT FROM expected_values
      OR persisted.source IS DISTINCT FROM 'product_label' OR persisted.confidence IS DISTINCT FROM 0.92::numeric THEN
      RAISE EXCEPTION 'literal JS/PG product rounding golden % failed',index;
    END IF;
  END LOOP;
END;
$rounding$;

DO $gate$
DECLARE
  owner_id uuid := 'c1400000-0000-4000-8000-000000000001';
  auth_id uuid := 'c1400000-0000-4000-8000-000000000002';
  snapshot_id uuid := 'c1400000-0000-4000-8000-000000000003';
  anchor_id uuid := 'c1400000-0000-4000-8000-000000000004';
  sibling_id uuid := 'c1400000-0000-4000-8000-000000000005';
  current_anchor uuid;
  route text;
  version text := 'v1:' || repeat('a', 64);
  command_hash text := repeat('b', 64);
  local_day date := (clock_timestamp() AT TIME ZONE 'UTC')::date;
  state jsonb;
  result jsonb;
  first_result jsonb;
  calculated jsonb;
  sibling_before jsonb;
  snapshot_before jsonb;
  before_failure jsonb;
  after_failure jsonb;
  row_value public.meal_logs%ROWTYPE;
  source_value text;
  did_fail boolean;
  completion_literal text;
BEGIN
  INSERT INTO auth.users(id) VALUES(auth_id);
  INSERT INTO public.users(id, auth_user_id, timezone, country, country_confirmed, status)
  VALUES(owner_id, auth_id, 'UTC', 'BR', true, 'active');
  INSERT INTO public.daily_snapshots(id, user_id, date, calories_target, protein_target,
    calories_consumed, protein_g, carbs_g, fat_g, exercise_calories, training_done,
    water_consumed_ml, xp_earned, deficit_accumulated)
  VALUES(snapshot_id, owner_id, local_day, 1900, 120, 155, 23, 4.5, 4.75, 100, true, 1100, 40, 321);
  INSERT INTO public.meal_logs(id, user_id, snapshot_id, food_name, quantity_g, kcal,
    protein_g, carbs_g, fat_g, source, confidence, consumed_at, meal_type,
    raw_provider_message_id, raw_message_id, image_url)
  VALUES(anchor_id, owner_id, snapshot_id, 'iogurte natural', 85, 55, 3, 4.5, 2.75,
    'product_label', 0.93, clock_timestamp(), 'almoco', 'c11-synthetic-group', auth_id, 'synthetic-private-origin'),
    (sibling_id, owner_id, snapshot_id, 'frango grelhado', 120, 100, 20, 0, 2,
    'legacy_estimate', NULL, clock_timestamp(), 'jantar', 'c11-synthetic-group', NULL, NULL);
  SELECT to_jsonb(m) INTO sibling_before FROM public.meal_logs m WHERE id = sibling_id;
  SELECT to_jsonb(s) INTO snapshot_before FROM public.daily_snapshots s WHERE id = snapshot_id;
  state := pg_temp.c11_state(owner_id, snapshot_id, anchor_id);
  route := '/api/mobile/v1/meal-records/' || anchor_id;
  calculated := '[{"food_name":"iogurte natural","quantity_g":170,"kcal":110,"protein_g":6,"carbs_g":9,"fat_g":5.5,"source":"product_label","food_db_id":null,"confidence":0.93}]';
  result := public.mutate_mobile_confirmed_meal(owner_id, 'c11-quantity-label', 'PATCH', route,
    command_hash, anchor_id, version, ARRAY[anchor_id], state, calculated,
    'quantity_only', '{"quantity_g":170}', 'synthetic-request-1');
  IF result->>'action' IS DISTINCT FROM 'completed' OR (result->>'response_status')::int <> 200
    OR result#>>'{response_body,data,operation}' IS DISTINCT FROM 'updated'
    OR (result#>>'{response_body,data,snapshot,calories_consumed}')::int <> 210
    OR (result#>>'{response_body,data,snapshot,protein_g}')::numeric <> 26
    OR (result#>>'{response_body,data,snapshot,carbs_g}')::numeric <> 9
    OR (result#>>'{response_body,data,snapshot,fat_g}')::numeric <> 7.5
    OR (result#>>'{response_body,data,snapshot,daily_balance}')::int <> -1790 THEN
    RAISE EXCEPTION 'exact label proportional receipt/totals failed';
  END IF;
  current_anchor := (result#>>'{response_body,data,next_record_id}')::uuid;
  SELECT * INTO row_value FROM public.meal_logs WHERE id = current_anchor;
  IF row_value.id = anchor_id OR row_value.source IS DISTINCT FROM 'product_label'
    OR row_value.confidence IS DISTINCT FROM 0.93::numeric OR row_value.food_db_id IS NOT NULL
    OR row_value.quantity_g <> 170 OR row_value.raw_message_id IS DISTINCT FROM auth_id
    OR row_value.image_url IS DISTINCT FROM 'synthetic-private-origin'
    OR row_value.raw_provider_message_id IS DISTINCT FROM 'c11-synthetic-group'
    OR row_value.meal_type IS DISTINCT FROM 'almoco'::public.meal_type_enum THEN
    RAISE EXCEPTION 'replacement changed official provenance/header';
  END IF;
  IF (SELECT to_jsonb(m) FROM public.meal_logs m WHERE id = sibling_id) IS DISTINCT FROM sibling_before THEN
    RAISE EXCEPTION 'untouched sibling changed';
  END IF;
  IF (SELECT to_jsonb(s) - ARRAY['calories_consumed','protein_g','carbs_g','fat_g','daily_balance','updated_at']
      FROM public.daily_snapshots s WHERE id = snapshot_id)
    IS DISTINCT FROM (snapshot_before - ARRAY['calories_consumed','protein_g','carbs_g','fat_g','daily_balance','updated_at']) THEN
    RAISE EXCEPTION 'unrelated snapshot values changed';
  END IF;
  first_result := result;

  -- Replay survives expired retention and missing old target; immutable original receipt.
  UPDATE public.mobile_api_idempotency SET expires_at = clock_timestamp() - interval '1 day'
  WHERE user_id = owner_id AND idempotency_key = 'c11-quantity-label';
  result := public.mutate_mobile_confirmed_meal(owner_id, 'c11-quantity-label', 'PATCH', route,
    command_hash, anchor_id, NULL, NULL, NULL, NULL, NULL, NULL, 'synthetic-request-2');
  IF result->>'action' IS DISTINCT FROM 'replay' OR result->'response_body' IS DISTINCT FROM first_result->'response_body' THEN
    RAISE EXCEPTION 'expired replay lost original receipt';
  END IF;
  result := public.claim_mobile_api_request(owner_id, 'c11-quantity-label', 'PATCH', route, command_hash);
  IF result->>'action' IS DISTINCT FROM 'replay' THEN RAISE EXCEPTION 'generic claim overwrote completed meal receipt'; END IF;
  result := public.claim_mobile_api_request(owner_id, 'c11-quantity-label', 'POST', '/api/mobile/v1/weight', command_hash);
  IF result->>'action' IS DISTINCT FROM 'conflict' THEN RAISE EXCEPTION 'generic foreign route overwrote completed meal receipt'; END IF;

  -- Official NULL/legacy source must survive proportional publication, not become approved/catalog.
  FOREACH source_value IN ARRAY ARRAY[NULL::text, 'user_kcal', 'pending_approved', 'legacy_estimate'] LOOP
    UPDATE public.meal_logs SET source = source_value, confidence = NULL WHERE id = current_anchor;
    state := pg_temp.c11_state(owner_id, snapshot_id, current_anchor);
    calculated := jsonb_build_array(jsonb_build_object('food_name','iogurte natural',
      'quantity_g',170,'kcal',110,'protein_g',6,'carbs_g',9,'fat_g',5.5,
      'source',source_value,'food_db_id',NULL,'confidence',NULL));
    route := '/api/mobile/v1/meal-records/' || current_anchor;
    result := public.mutate_mobile_confirmed_meal(owner_id, 'c11-source-' || coalesce(source_value,'null'),
      'PATCH', route, command_hash, current_anchor, version, ARRAY[current_anchor], state,
      calculated, 'quantity_only', '{"quantity_g":170}', 'synthetic-source-request');
    current_anchor := (result#>>'{response_body,data,next_record_id}')::uuid;
    SELECT * INTO row_value FROM public.meal_logs WHERE id = current_anchor;
    IF row_value.source IS DISTINCT FROM source_value OR row_value.confidence IS NOT NULL
      OR row_value.kcal <> 110 OR row_value.protein_g <> 6 THEN
      RAISE EXCEPTION 'official NULL/legacy provenance changed';
    END IF;
  END LOOP;

  -- Changed whole snapshot must roll back every row and the new request ledger.
  state := pg_temp.c11_state(owner_id, snapshot_id, current_anchor);
  UPDATE public.daily_snapshots SET water_consumed_ml = 1200 WHERE id = snapshot_id;
  SELECT jsonb_build_object('snapshot',(SELECT to_jsonb(s) FROM public.daily_snapshots s WHERE id=snapshot_id),
    'logs',(SELECT jsonb_agg(to_jsonb(m) ORDER BY id) FROM public.meal_logs m WHERE user_id=owner_id),
    'ledger',(SELECT jsonb_agg(to_jsonb(l) ORDER BY id) FROM public.mobile_api_idempotency l WHERE user_id=owner_id)) INTO before_failure;
  did_fail := false;
  BEGIN
    PERFORM public.mutate_mobile_confirmed_meal(owner_id, 'c11-stale-snapshot', 'DELETE',
      '/api/mobile/v1/meal-records/' || current_anchor, command_hash, current_anchor, version,
      ARRAY[current_anchor], state, NULL, NULL, NULL, 'synthetic-stale-request');
  EXCEPTION WHEN serialization_failure THEN did_fail := true;
  END;
  SELECT jsonb_build_object('snapshot',(SELECT to_jsonb(s) FROM public.daily_snapshots s WHERE id=snapshot_id),
    'logs',(SELECT jsonb_agg(to_jsonb(m) ORDER BY id) FROM public.meal_logs m WHERE user_id=owner_id),
    'ledger',(SELECT jsonb_agg(to_jsonb(l) ORDER BY id) FROM public.mobile_api_idempotency l WHERE user_id=owner_id)) INTO after_failure;
  IF NOT did_fail OR before_failure IS DISTINCT FROM after_failure THEN RAISE EXCEPTION 'stale state wrote partial data'; END IF;

  -- Group2 ->30 replacements must not silently create group31 or erase the sibling.
  state := pg_temp.c11_state(owner_id, snapshot_id, current_anchor);
  SELECT jsonb_agg(jsonb_build_object('food_name','synthetic-compound-' || n,
    'quantity_g',1,'kcal',0,'protein_g',0,'carbs_g',0,'fat_g',0,
    'source','legacy_estimate','food_db_id',NULL,'confidence',NULL))
  INTO calculated FROM generate_series(1,30) AS ingredients(n);
  did_fail := false;
  BEGIN
    PERFORM public.mutate_mobile_confirmed_meal(owner_id, 'c11-group31', 'PATCH',
      '/api/mobile/v1/meal-records/' || current_anchor, command_hash, current_anchor, version,
      ARRAY[current_anchor], state, calculated, 'recalculated', NULL, 'synthetic-group-limit');
  EXCEPTION WHEN invalid_parameter_value THEN did_fail := true;
  END;
  SELECT jsonb_build_object('snapshot',(SELECT to_jsonb(s) FROM public.daily_snapshots s WHERE id=snapshot_id),
    'logs',(SELECT jsonb_agg(to_jsonb(m) ORDER BY id) FROM public.meal_logs m WHERE user_id=owner_id),
    'ledger',(SELECT jsonb_agg(to_jsonb(l) ORDER BY id) FROM public.mobile_api_idempotency l WHERE user_id=owner_id)) INTO after_failure;
  IF NOT did_fail OR before_failure IS DISTINCT FROM after_failure THEN RAISE EXCEPTION 'group31 refusal wrote partial data'; END IF;

  -- A false OR NULL ledger completion is a rollback, even after the meal mutation ran.
  -- Replacement helper is local to this test transaction and restored on outer ROLLBACK.
  FOREACH completion_literal IN ARRAY ARRAY['false', 'NULL'] LOOP
    EXECUTE 'CREATE OR REPLACE FUNCTION public.complete_mobile_api_request(p_claim_id uuid, p_user_id uuid, p_response_status integer, p_response_body jsonb)
      RETURNS boolean LANGUAGE sql SECURITY DEFINER SET search_path=pg_catalog,public,private,pg_temp
      AS ''SELECT ' || completion_literal || '::boolean''';
    did_fail := false;
    BEGIN
      PERFORM public.mutate_mobile_confirmed_meal(owner_id, 'c11-complete-' || lower(completion_literal),
        'DELETE', '/api/mobile/v1/meal-records/' || current_anchor, command_hash, current_anchor, version,
        ARRAY[current_anchor], state, NULL, NULL, NULL, 'synthetic-complete-failure');
    EXCEPTION WHEN serialization_failure THEN did_fail := true;
    END;
    SELECT jsonb_build_object('snapshot',(SELECT to_jsonb(s) FROM public.daily_snapshots s WHERE id=snapshot_id),
      'logs',(SELECT jsonb_agg(to_jsonb(m) ORDER BY id) FROM public.meal_logs m WHERE user_id=owner_id),
      'ledger',(SELECT jsonb_agg(to_jsonb(l) ORDER BY id) FROM public.mobile_api_idempotency l WHERE user_id=owner_id)) INTO after_failure;
    IF NOT did_fail OR before_failure IS DISTINCT FROM after_failure THEN RAISE EXCEPTION 'incomplete ledger wrote partial data'; END IF;
  END LOOP;
  -- Restore the exact existing completion semantics for the positive DELETE controls.
  EXECUTE 'CREATE OR REPLACE FUNCTION public.complete_mobile_api_request(p_claim_id uuid,p_user_id uuid,p_response_status integer,p_response_body jsonb)
    RETURNS boolean LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public,private,pg_temp AS $fn$
    BEGIN
      PERFORM private.assert_trusted_backend();
      UPDATE public.mobile_api_idempotency SET state=''completed'',response_status=p_response_status,
        response_body=p_response_body,updated_at=clock_timestamp()
      WHERE id=p_claim_id AND user_id=p_user_id AND state=''processing'';
      RETURN FOUND;
    END;$fn$';

  -- Finite selection deletes one food; remaining sibling stays byte-equivalent and official totals update.
  state := pg_temp.c11_state(owner_id, snapshot_id, current_anchor);
  result := public.mutate_mobile_confirmed_meal(owner_id, 'c11-delete-one', 'DELETE',
    '/api/mobile/v1/meal-records/' || current_anchor, command_hash, current_anchor, version,
    ARRAY[current_anchor], state, NULL, NULL, NULL, 'synthetic-delete-request');
  IF (result#>>'{response_body,data,snapshot,calories_consumed}')::int <> 100
    OR result#>>'{response_body,data,next_record_id}' IS DISTINCT FROM sibling_id::text
    OR (SELECT to_jsonb(m) FROM public.meal_logs m WHERE id = sibling_id) IS DISTINCT FROM sibling_before THEN
    RAISE EXCEPTION 'finite deletion harmed survivor/totals';
  END IF;
  state := pg_temp.c11_state(owner_id, snapshot_id, sibling_id);
  result := public.mutate_mobile_confirmed_meal(owner_id, 'c11-delete-last', 'DELETE',
    '/api/mobile/v1/meal-records/' || sibling_id, command_hash, sibling_id, version,
    ARRAY[sibling_id], state, NULL, NULL, NULL, 'synthetic-delete-last');
  IF result#>'{response_body,data,next_record_id}' IS DISTINCT FROM 'null'::jsonb
    OR (result#>>'{response_body,data,snapshot,calories_consumed}')::int <> 0
    OR (result#>>'{response_body,data,snapshot,protein_g}')::numeric <> 0
    OR (result#>>'{response_body,data,snapshot,daily_balance}')::int <> -2000
    OR EXISTS(SELECT 1 FROM public.meal_logs WHERE user_id=owner_id) THEN
    RAISE EXCEPTION 'delete last did not publish legitimate zero consumption';
  END IF;
END;
$gate$;
ROLLBACK;
