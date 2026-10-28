-- Run only through LocalCycleDatabase in the owned, disposable UNIX socket.
BEGIN;
SET LOCAL search_path=pg_catalog;
SELECT set_config('request.jwt.claim.role','service_role',true);
\ir fixtures/mobile_reevaluation_cycle_fixture.sql
SELECT m3b_cycle_test.ok(to_regclass('private.mobile_weight_measurements') IS NOT NULL,
 'true individual weight history exists');
SELECT m3b_cycle_test.seed(n,NULL) FROM generate_series(900,906) n;
SELECT m3b_cycle_test.seed(907,clock_timestamp()-interval '30 days');

DO $$
DECLARE owner_id uuid:=m3b_cycle_test.uid(900); other_id uuid:=m3b_cycle_test.uid(901);
 t timestamptz:=date_trunc('second',clock_timestamp()-interval '1 hour');
 observed timestamptz:=clock_timestamp(); original jsonb; result jsonb; evidence uuid;
 measurements_before bigint; requests_before bigint; observed_epoch uuid; targets_before jsonb;
BEGIN
 SELECT jsonb_build_object('snapshots',(SELECT jsonb_agg(to_jsonb(s) ORDER BY s.id) FROM public.daily_snapshots s WHERE user_id IN(owner_id,other_id)),
   'progress',(SELECT jsonb_agg(to_jsonb(p) ORDER BY p.user_id) FROM public.user_progress p WHERE user_id IN(owner_id,other_id))) INTO targets_before;
 original:=public.record_weight_atomic(owner_id,78.456,'kg',t,'history-key-0001');
 PERFORM m3b_cycle_test.ok(original->>'reason'='applied' AND (original->>'weight_kg')::numeric=78.46,
   'canonical rounded official result preserved');
 PERFORM m3b_cycle_test.ok((SELECT count(*)=1 AND min(weight_kg)=78.46
   AND min(measured_at)=t AND min(instant_source)='measured'
   AND min(observed_timezone)='America/Sao_Paulo' FROM private.mobile_weight_measurements WHERE user_id=owner_id),
   'one genuine individual measurement with server timezone');
 PERFORM m3b_cycle_test.ok((SELECT authority_epoch IS NULL FROM private.mobile_weight_measurements WHERE user_id=owner_id),
   'absent epoch remains unknown, no signup authority fabricated');
 result:=public.record_weight_atomic(owner_id,78.456,'kg',t,'history-key-0001');
 PERFORM m3b_cycle_test.ok(result=original AND (SELECT count(*)=1 FROM private.mobile_weight_request_receipts WHERE user_id=owner_id),
   'same request returns original receipt without another sample');
 result:=public.record_weight_atomic(owner_id,78.46,'kg',t,'history-key-0002');
 PERFORM m3b_cycle_test.ok(result->>'reason'='same_measurement'
   AND (SELECT count(*)=1 FROM private.mobile_weight_measurements WHERE user_id=owner_id)
   AND (SELECT count(*)=2 FROM private.mobile_weight_request_receipts WHERE user_id=owner_id),
   'new request for same physical measurement has its own result, one sample');
 PERFORM m3b_cycle_test.throws(format('SELECT public.record_weight_atomic(%L,78.459,''kg'',%L,''history-key-0001'')',owner_id,t),
   '40001','raw request change conflicts even when rounded kg is identical');
 PERFORM m3b_cycle_test.throws(format('SELECT public.record_weight_atomic(%L,78.456,''lb'',%L,''history-key-0001'')',owner_id,t),
   '40001','same key cannot change unit');
 PERFORM m3b_cycle_test.throws(format('SELECT public.record_weight_atomic(%L,78.456,''kg'',%L,''history-key-0001'')',owner_id,t+interval '1 second'),
   '40001','same key cannot change instant');
 PERFORM m3b_cycle_test.throws(format('SELECT public.record_weight_atomic(%L,79,''kg'',%L,''history-key-0003'')',owner_id,t),
   '23505','different value at physical measurement instant conflicts');
 result:=public.record_weight_atomic(owner_id,79,'kg',t-interval '1 day','history-key-0004');
 PERFORM m3b_cycle_test.ok(result->>'reason'='older_than_current' AND (result->>'weight_kg')::numeric=78.46
   AND (SELECT count(*)=2 FROM private.mobile_weight_measurements WHERE user_id=owner_id),
   'valid older value retained in history, latest official result stays ordered');
 PERFORM public.record_weight_atomic(owner_id,80,'kg',t+interval '1 minute','history-key-0005');
 PERFORM m3b_cycle_test.throws(format('SELECT public.record_weight_atomic(%L,79.01,''kg'',%L,''history-key-0006'')',owner_id,t-interval '1 day'),
   '23505','historical instant remains conflict-protected after official profile advances');
 result:=public.record_weight_atomic(other_id,78.456,'kg',t,'history-key-0001');
 PERFORM m3b_cycle_test.ok(result=original AND (SELECT count(*)=1 FROM private.mobile_weight_measurements WHERE user_id=other_id),
   'keys and physical instants isolated between people');
 PERFORM m3b_cycle_test.ok(targets_before=jsonb_build_object(
   'snapshots',(SELECT jsonb_agg(to_jsonb(s) ORDER BY s.id) FROM public.daily_snapshots s WHERE user_id IN(owner_id,other_id)),
   'progress',(SELECT jsonb_agg(to_jsonb(p) ORDER BY p.user_id) FROM public.user_progress p WHERE user_id IN(owner_id,other_id))),
   'weight recording preserves exact snapshot and progress rows');

 -- A replay is an acknowledgement, never a reapplication over a later legacy write.
 UPDATE public.user_profiles SET weight_kg=85 WHERE user_id=owner_id;
 result:=public.record_weight_atomic(owner_id,78.456,'kg',t,'history-key-0001');
 PERFORM m3b_cycle_test.ok(result=original AND (SELECT weight_kg=85 FROM public.user_profiles WHERE user_id=owner_id),
   'original applied result replays without overwriting newer legacy profile');
 result:=private.record_mobile_weight_at(owner_id,78.456,'kg',t,'history-key-0001',observed+interval '8 days');
 PERFORM m3b_cycle_test.ok(result=original,'durable replay precedes aged offline window check');
 PERFORM m3b_cycle_test.throws(format('SELECT private.record_mobile_weight_at(%L,78.456,''kg'',%L,''history-key-expired'',%L)',
   owner_id,t,observed+interval '8 days'),'22023','new request outside offline window still refused');
 PERFORM public.reset_user_conversation_atomic(owner_id,true);
 result:=public.record_weight_atomic(owner_id,78.456,'kg',t,'history-key-0001');
 PERFORM m3b_cycle_test.ok(result=original AND (SELECT weight_kg IS NULL FROM public.user_profiles WHERE user_id=owner_id),
   'replay after reset preserves original result without restoring cleared profile');
 PERFORM m3b_cycle_test.ok((SELECT count(*)=3 FROM private.mobile_weight_measurements WHERE user_id=owner_id),
   'reset preserves genuine history without fabricating a sample');
 -- A person without an epoch retains NULL through reset. Observe the actual
 -- authority before expecting a non-NULL epoch; reset does not invent one.
 PERFORM public.observe_mobile_signup_strength_epoch(owner_id);
 SELECT e.epoch INTO observed_epoch FROM private.workout_strength_authority_epochs e WHERE e.user_id=owner_id;
 PERFORM public.record_weight_atomic(owner_id,81,'kg',t+interval '2 minutes','history-key-new-epoch');
 PERFORM m3b_cycle_test.ok((SELECT authority_epoch=observed_epoch FROM private.mobile_weight_measurements
   WHERE user_id=owner_id AND measured_at=t+interval '2 minutes'), 'new observation captures actual post-reset epoch');
 PERFORM m3b_cycle_test.ok((SELECT authority_epoch IS NULL FROM private.mobile_weight_measurements
   WHERE user_id=owner_id AND measured_at=t),'reset cannot relabel old evidence into new epoch');

 SELECT count(*) INTO measurements_before FROM private.mobile_weight_measurements;
 SELECT count(*) INTO requests_before FROM private.mobile_weight_request_receipts;
 PERFORM m3b_cycle_test.throws(format('SELECT public.record_weight_atomic(%L,''NaN'',''kg'',%L,''history-invalid-nan'')',other_id,t),'22023','numeric NaN refused');
 PERFORM m3b_cycle_test.throws(format('SELECT public.record_weight_atomic(%L,''Infinity'',''kg'',%L,''history-invalid-inf'')',other_id,t),'22023','numeric infinity refused');
 PERFORM m3b_cycle_test.throws(format('SELECT public.record_weight_atomic(%L,78,''kg'',%L,''history-invalid-future'')',other_id,observed+interval '10 minutes'),
   '22023','future input refused');
 UPDATE public.users SET status='blocked' WHERE id=other_id;
 PERFORM m3b_cycle_test.throws(format('SELECT public.record_weight_atomic(%L,78.456,''kg'',%L,''history-key-0001'')',other_id,t),
   '22023','inactive person cannot obtain historical replay');
 UPDATE public.users SET status='active',timezone='not/a-zone' WHERE id=other_id;
 PERFORM m3b_cycle_test.throws(format('SELECT public.record_weight_atomic(%L,79,''kg'',%L,''history-invalid-zone'')',other_id,t+interval '2 minutes'),
   '22023','invalid timezone cannot silently become a local day');
 PERFORM m3b_cycle_test.ok((SELECT count(*)=measurements_before FROM private.mobile_weight_measurements)
   AND (SELECT count(*)=requests_before FROM private.mobile_weight_request_receipts),'refused operations write neither history nor receipts');

 SELECT id INTO evidence FROM private.mobile_weight_measurements WHERE user_id=owner_id AND measured_at=t;
 PERFORM m3b_cycle_test.throws(format('UPDATE private.mobile_weight_measurements SET weight_kg=90 WHERE id=%L',evidence),
   '55000','measurement evidence immutable');
 PERFORM m3b_cycle_test.throws(format('DELETE FROM private.mobile_weight_measurements WHERE id=%L',evidence),
   '55000','measurement cannot be removed while person exists');
 PERFORM m3b_cycle_test.throws(format('UPDATE private.mobile_weight_request_receipts SET result=''{}'' WHERE user_id=%L',owner_id),
   '55000','request result immutable');
 PERFORM m3b_cycle_test.throws(format('DELETE FROM private.mobile_weight_request_receipts WHERE user_id=%L',owner_id),
   '55000','receipt cannot be removed while person exists');
 DELETE FROM public.users WHERE id=other_id;
 PERFORM m3b_cycle_test.ok(NOT EXISTS(SELECT 1 FROM private.mobile_weight_measurements WHERE user_id=other_id)
   AND NOT EXISTS(SELECT 1 FROM private.mobile_weight_request_receipts WHERE user_id=other_id),
   'actual hard deletion cascades both private ledgers');

 owner_id:=m3b_cycle_test.uid(907);
 PERFORM public.record_weight_atomic(owner_id,170,'lb',t,'history-pounds-0001');
 PERFORM m3b_cycle_test.ok((SELECT weight_kg=77.11 AND authority_epoch IS NOT NULL
   FROM private.mobile_weight_measurements WHERE user_id=owner_id),'pounds conversion and observed epoch captured');
 PERFORM m3b_cycle_test.ok((SELECT request_value=170 AND request_unit='lb' FROM private.mobile_weight_request_receipts WHERE user_id=owner_id),
   'receipt preserves original quantity and unit');
END $$;

SELECT m3b_cycle_test.ok(NOT has_table_privilege(role,table_name,'SELECT,INSERT,UPDATE,DELETE'),role||' no direct private weight access '||table_name)
 FROM unnest(ARRAY['anon','authenticated','service_role']) role
 CROSS JOIN unnest(ARRAY['private.mobile_weight_measurements','private.mobile_weight_request_receipts']) table_name;
SELECT m3b_cycle_test.ok(relrowsecurity,'private weight table RLS enabled '||relname)
 FROM pg_class WHERE oid IN('private.mobile_weight_measurements'::regclass,'private.mobile_weight_request_receipts'::regclass);
SELECT m3b_cycle_test.ok(NOT has_function_privilege(role,'private.record_mobile_weight_at(uuid,numeric,text,timestamptz,text,timestamptz)','EXECUTE'),
 role||' cannot choose weight server clock') FROM unnest(ARRAY['anon','authenticated','service_role']) role;
SELECT m3b_cycle_test.ok(has_function_privilege('service_role','public.record_weight_atomic(uuid,numeric,text,timestamptz,text)','EXECUTE')
 AND NOT has_function_privilege('authenticated','public.record_weight_atomic(uuid,numeric,text,timestamptz,text)','EXECUTE'),
 'only backend public weight writer');
ROLLBACK;
