-- Owned disposable UNIX socket only; no raw answers are persisted by a preview.
BEGIN;
SET LOCAL search_path=pg_catalog;
SELECT set_config('request.jwt.claim.role','service_role',true);
\ir fixtures/mobile_reevaluation_photo_fixture.sql
SELECT m3b_cycle_test.ok(to_regprocedure('private.capture_mobile_clinical_context_at(uuid,text,uuid,timestamptz)') IS NOT NULL,
 'clinical context binds complete authority');

DO $$
DECLARE c jsonb; a uuid; cycle uuid; observed timestamptz; x jsonb; y jsonb;
 old_photo jsonb; current_photo jsonb; preview jsonb; second_preview jsonb;
 request_key uuid:=gen_random_uuid(); asset uuid; ticket uuid:=gen_random_uuid();
 cycle_revision bigint; ordinary_before jsonb; error_state text;
 form jsonb:='{"version":1,"answers":{"weightKg":80,"hunger":"moderada"}}';
 intent jsonb:='{"decision":"keep"}'; proposal jsonb:='{"version":1,"principal":"keep"}';
BEGIN
 c:=m3b_cycle_test.ready_photo(1000); a:=(c->>'user')::uuid; cycle:=(c->>'cycle')::uuid;
 UPDATE public.user_profiles SET sex='masculino',birth_date='1990-01-01',height_cm=180,
   weight_kg=80,body_fat_percent=24,activity_level='moderado',training_frequency=4,
   current_protocol='recomposicao',deficit_level=500,updated_at=clock_timestamp() WHERE user_id=a;
 observed:=clock_timestamp();
 x:=private.capture_mobile_clinical_context_at(a,'REGULAR',cycle,observed);
 y:=private.capture_mobile_clinical_context_at(a,'REGULAR',cycle,observed+interval '1 microsecond');
 PERFORM m3b_cycle_test.ok(x->>'context_hash'=y->>'context_hash' AND x->>'observed_at'<>y->>'observed_at',
  'observation time excluded from stable hash');
 PERFORM m3b_cycle_test.ok(x#>>'{facts,owner,id}'=a::text
   AND x#>>'{facts,anchor,signup_generation}' IS NOT NULL
   AND x#>>'{facts,anchor,signup_epoch}' IS NOT NULL
   AND x#>>'{facts,cycle,revision}'=(SELECT revision::text FROM private.mobile_reevaluation_cycles WHERE cycle_id=cycle),
   'owner signup epoch admission and exact cycle revision bound');
 PERFORM m3b_cycle_test.ok((x->>'valid_until')::timestamptz<=
   (SELECT last_activity_at+make_interval(secs=>idle_timeout_seconds) FROM private.mobile_reevaluation_photo_consents WHERE acceptance_id=(c->>'acceptance')::uuid),
   'preview bounded by consent inactivity deadline');
 PERFORM m3b_cycle_test.ok(x::text !~ 'object_path|context_text|bucket_id|https://|SYNTHETIC LOCAL PHOTO ALLOCATION',
   'context excludes image paths legal body and transport data');
 ordinary_before:=m3b_cycle_test.original_state(a)-'private.mobile_clinical_previews';
 preview:=private.prepare_mobile_clinical_preview_at(a,'REGULAR',cycle,request_key,x->>'context_hash',form,intent,proposal,observed);
 second_preview:=private.prepare_mobile_clinical_preview_at(a,'REGULAR',cycle,request_key,x->>'context_hash',form,intent,proposal,observed);
 PERFORM m3b_cycle_test.ok(preview=second_preview AND (SELECT count(*)=1 FROM private.mobile_clinical_previews WHERE user_id=a),
   'preview operation is durable and idempotent');
 PERFORM m3b_cycle_test.ok((SELECT to_jsonb(p)::text !~ 'weightKg|moderada|principal|answers' FROM private.mobile_clinical_previews p WHERE user_id=a),
   'preview stores hashes only, no ordinary answers or clinical proposal');
 PERFORM m3b_cycle_test.ok(ordinary_before=(m3b_cycle_test.original_state(a)-'private.mobile_clinical_previews'),
   'preview does not write profile targets answers or calendar');
 PERFORM m3b_cycle_test.throws(format('SELECT private.prepare_mobile_clinical_preview_at(%L,''REGULAR'',%L,%L,%L,''{"different":true}'',%L,%L,%L)',
   a,cycle,request_key,x->>'context_hash',intent,proposal,observed),'40001','same preview key rejects changed form');
 UPDATE public.user_profiles SET height_cm=181 WHERE user_id=a;
 y:=private.capture_mobile_clinical_context_at(a,'REGULAR',cycle,NULL);
 PERFORM m3b_cycle_test.ok(x->>'context_hash'<>y->>'context_hash','profile change invalidates context');
 PERFORM m3b_cycle_test.throws(format('SELECT private.prepare_mobile_clinical_preview_at(%L,''REGULAR'',%L,%L,%L,%L,%L,%L,NULL)',
   a,cycle,gen_random_uuid(),x->>'context_hash',form,intent,proposal),'40001','new preview refuses stale context');
 x:=y;
 PERFORM public.record_weight_atomic(a,79,'kg',clock_timestamp()-interval '1 day','snapshot-weight-old');
 y:=private.capture_mobile_clinical_context_at(a,'REGULAR',cycle,NULL);
 PERFORM m3b_cycle_test.ok(x->>'context_hash'<>y->>'context_hash'
   AND x#>'{facts,profile}'=y#>'{facts,profile}', 'older genuine history invalidates context even when profile unchanged');
 x:=y;
 PERFORM public.declare_mobile_health_risk(a,gen_random_uuid(),ARRAY['reduced_intake']);
 y:=private.capture_mobile_clinical_context_at(a,'REGULAR',cycle,NULL);
 PERFORM m3b_cycle_test.ok(x->>'context_hash'<>y->>'context_hash' AND y#>>'{facts,safety,hold_active}'='true',
  'new risk revision changes context');

 -- A second pending allocation has the same old normalized photo snapshot.
 c:=c||jsonb_build_object('revision',(SELECT revision::text FROM private.mobile_reevaluation_cycles WHERE cycle_id=cycle));
 PERFORM m3b_cycle_test.allocate(c,gen_random_uuid(),'side');
 x:=private.capture_mobile_clinical_context_at(a,'REGULAR',cycle,NULL);
 old_photo:=private.get_mobile_reevaluation_photo_snapshot_at(a,cycle,NULL)-'observed_at';
 SELECT revision INTO cycle_revision FROM private.mobile_reevaluation_cycles WHERE cycle_id=cycle;
 asset:=(m3b_cycle_test.allocate(c,gen_random_uuid(),'side')#>>'{asset,id}')::uuid;
 y:=private.capture_mobile_clinical_context_at(a,'REGULAR',cycle,NULL);
 current_photo:=private.get_mobile_reevaluation_photo_snapshot_at(a,cycle,NULL)-'observed_at';
 PERFORM m3b_cycle_test.ok(old_photo=current_photo AND cycle_revision=(SELECT revision FROM private.mobile_reevaluation_cycles WHERE cycle_id=cycle)
   AND x->>'context_hash'<>y->>'context_hash','pending allocation/source revision stale even when old photo snapshot and cycle revision are identical');
 x:=y;
 PERFORM public.prepare_mobile_reevaluation_photo_upload(a,cycle,asset,ticket);
 y:=private.capture_mobile_clinical_context_at(a,'REGULAR',cycle,NULL);
 PERFORM m3b_cycle_test.ok(x->>'context_hash'<>y->>'context_hash','ticket preparation changes authority');
 x:=y;
 PERFORM public.register_mobile_reevaluation_photo_upload_ticket(a,cycle,asset,ticket,clock_timestamp()+interval '1 hour');
 y:=private.capture_mobile_clinical_context_at(a,'REGULAR',cycle,NULL);
 PERFORM m3b_cycle_test.ok(x->>'context_hash'<>y->>'context_hash','late ticket expiry registration changes authority');
 x:=y;
 INSERT INTO public.global_config(key,value) VALUES('calc.m3b_synthetic_snapshot','1'::jsonb);
 y:=private.capture_mobile_clinical_context_at(a,'REGULAR',cycle,NULL);
 PERFORM m3b_cycle_test.ok(x->>'context_hash'<>y->>'context_hash','calc set insertion invalidates context');
 x:=y;
 INSERT INTO public.daily_snapshots(user_id,date,calories_target,protein_target,current_protocol)
   VALUES(a,(clock_timestamp() AT TIME ZONE 'America/Sao_Paulo')::date,1700,120,'recomposicao');
 y:=private.capture_mobile_clinical_context_at(a,'REGULAR',cycle,NULL);
 PERFORM m3b_cycle_test.ok(x->>'context_hash'<>y->>'context_hash','open day target creation invalidates context');
 x:=y;
 UPDATE public.daily_snapshots SET day_closed=true,closed_at=clock_timestamp() WHERE user_id=a;
 y:=private.capture_mobile_clinical_context_at(a,'REGULAR',cycle,NULL);
 PERFORM m3b_cycle_test.ok(x->>'context_hash'<>y->>'context_hash','day closing invalidates context');
 PERFORM m3b_cycle_test.throws(format('UPDATE private.mobile_clinical_previews SET context_hash=repeat(''f'',64) WHERE user_id=%L',a),
  '55000','preview receipt immutable');
 PERFORM m3b_cycle_test.throws(format('SELECT private.capture_mobile_clinical_context_at(%L,''ROUTINE_REVIEW'',NULL,NULL)',a),
  '40001','routine cannot bypass an open or due regular review');
 PERFORM m3b_cycle_test.throws(format('SELECT private.capture_mobile_clinical_context_at(%L,''REGULAR'',%L,NULL)',a,gen_random_uuid()),
  '40001','different cycle cannot be substituted');
END $$;
DO $$
DECLARE c jsonb; a uuid; cycle uuid; x jsonb; y jsonb; z jsonb;
 observed timestamptz; boundary timestamptz; k uuid:=gen_random_uuid();
 form jsonb:='{}'; request jsonb; before_rows jsonb;
BEGIN
 c:=m3b_cycle_test.ready_photo(1001); a:=(c->>'user')::uuid; cycle:=(c->>'cycle')::uuid;
 observed:=clock_timestamp();
 x:=private.capture_mobile_clinical_context_at(a,'REGULAR',cycle,observed);
 PERFORM set_config('TimeZone','Pacific/Auckland',true);
 y:=private.capture_mobile_clinical_context_at(a,'REGULAR',cycle,observed);
 PERFORM m3b_cycle_test.ok(x=y,'snapshot canonical across session timezone');
 PERFORM set_config('TimeZone','UTC',true);
 PERFORM m3b_cycle_test.ok(jsonb_typeof(x#>'{facts,cycle,revision}')='string'
  AND jsonb_typeof(x#>'{facts,photo_authority,sources,0,source_revision}')='string'
  AND x#>>'{facts,cycle,opened_at}' ~ '^\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d\.\d{6}Z$',
  'exact revisions and microsecond UTC timestamps');
 boundary:=observed+interval '20 seconds';
 INSERT INTO public.legal_documents(id,document_key,version,locale,body,required_from)
  VALUES(m3b_cycle_test.uid(1002),'body_photo_reevaluation_consent','clinical-future-1',
   'pt-BR','Synthetic future recurring photo text',boundary);
 y:=private.capture_mobile_clinical_context_at(a,'REGULAR',cycle,observed);
 PERFORM m3b_cycle_test.ok(x->>'context_hash'<>y->>'context_hash'
  AND (y->>'valid_until')::timestamptz=boundary,'future publication stales hash and bounds deadline even without enabled policy');
 z:=private.capture_mobile_clinical_context_at(a,'REGULAR',cycle,boundary);
 PERFORM m3b_cycle_test.ok(y->>'context_hash'<>z->>'context_hash'
  AND z#>>'{facts,photo_authority,consent_state,unavailable_reason}'='policy_unavailable',
  'effective legal boundary is rechecked without table mutation');
 z:=private.capture_mobile_clinical_context_at(a,'REGULAR',cycle,observed+interval '61 seconds');
 PERFORM m3b_cycle_test.ok(z#>>'{facts,photo_authority,consent_state,availability}'='unavailable',
  'elapsed consent cannot remain available');

 -- Routine journal: no calendar movement, no implicit capture of ordinary answers.
 a:=m3b_cycle_test.seed(1003,clock_timestamp()-interval '6 days');
 before_rows:=m3b_cycle_test.original_state(a)-'private.mobile_clinical_previews';
 x:=private.capture_mobile_clinical_context_at(a,'ROUTINE_REVIEW',NULL,NULL);
 PERFORM m3b_cycle_test.ok(x#>'{facts,cycle}'='null'::jsonb,'absent cycle is explicit unknown, not a phantom record');
 request:=private.prepare_mobile_clinical_preview_at(a,'ROUTINE_REVIEW',NULL,k,x->>'context_hash',form,form,form,NULL);
 PERFORM m3b_cycle_test.ok(before_rows=(m3b_cycle_test.original_state(a)-'private.mobile_clinical_previews')
  AND request->'cycle_id'='null'::jsonb,'routine preview does not open a cycle or move the base');
 UPDATE public.users SET timezone='Pacific/Auckland' WHERE id=a;
 y:=private.capture_mobile_clinical_context_at(a,'ROUTINE_REVIEW',NULL,NULL);
 PERFORM m3b_cycle_test.ok(x->>'context_hash'<>y->>'context_hash'
  AND x#>>'{facts,anchor,clock,timezone}'=y#>>'{facts,anchor,clock,timezone}',
  'owner timezone stales clinical date without reinterpreting frozen origin clock');
 PERFORM m3b_cycle_test.ok(request=private.prepare_mobile_clinical_preview_at(a,'ROUTINE_REVIEW',NULL,
   k,x->>'context_hash',form,form,form,NULL),'replay returns original acknowledgement, not new authority');
 PERFORM m3b_cycle_test.throws(format('SELECT private.prepare_mobile_clinical_preview_at(%L,''ROUTINE_REVIEW'',NULL,%L,%L,%L,%L,%L,NULL)',
  a,gen_random_uuid(),x->>'context_hash',form,form,form),'40001','new operation cannot reuse stale owner timezone');
 PERFORM m3b_cycle_test.throws(format('SELECT private.capture_mobile_clinical_context_at(%L,''SAFETY'',%L,NULL)',
  a,cycle),'22023','safety cannot substitute an existing regular cycle id');
 PERFORM m3b_cycle_test.throws(format('SELECT private.capture_mobile_clinical_context_at(%L,''unknown'',NULL,NULL)',a),
  '22023','unknown kind refused');
 UPDATE public.users SET status='blocked' WHERE id=a;
 PERFORM m3b_cycle_test.throws(format('SELECT private.capture_mobile_clinical_context_at(%L,''ROUTINE_REVIEW'',NULL,NULL)',a),
  'P0002','inactive owner refused');
END $$;
DO $$
DECLARE a uuid; cycle uuid; x jsonb; y jsonb; preview jsonb;
 key uuid:=gen_random_uuid();
BEGIN
 a:=m3b_cycle_test.seed(1004,'2026-10-01T23:00:00Z');
 cycle:=(private.start_mobile_reevaluation_cycle_at(a,gen_random_uuid(),'2026-10-15T03:00:00Z')#>>'{cycle,id}')::uuid;
 UPDATE public.users SET timezone='America/Los_Angeles' WHERE id=a;
 PERFORM m3b_cycle_test.ok(private.mobile_reevaluation_context_at(a,'2026-10-15T03:00:00Z')->>'reason' IS NULL,
  'source clock keeps original Sao Paulo due boundary');
 PERFORM m3b_cycle_test.throws(format('SELECT private.capture_mobile_clinical_context_at(%L,''REGULAR'',%L,''2026-10-15T03:00:00Z'')',a,cycle),
  '40001','clinical regular cannot count thirteen civil days after westward timezone change');
 x:=private.capture_mobile_clinical_context_at(a,'REGULAR',cycle,'2026-10-15T07:00:00Z');
 PERFORM m3b_cycle_test.ok(x#>>'{facts,calculation_date}'='2026-10-15','regular opens once both civil clocks satisfy the fortnight');
 preview:=private.prepare_mobile_clinical_preview_at(a,'REGULAR',cycle,key,x->>'context_hash','{}','{}','{}','2026-10-15T07:00:00Z');
 y:=private.capture_mobile_clinical_context_at(a,'REGULAR',cycle,'2026-10-16T07:00:00Z');
 PERFORM m3b_cycle_test.ok(x->>'context_hash'<>y->>'context_hash'
  AND (preview->>'valid_until')::timestamptz='2026-10-16T07:00:00Z',
  'local midnight invalidates preview even without profile mutation');
 PERFORM m3b_cycle_test.throws(format('SELECT private.prepare_mobile_clinical_preview_at(%L,''REGULAR'',%L,%L,%L,''{}'',''{}'',''{}'',''2026-10-16T07:00:00Z'')',
  a,cycle,gen_random_uuid(),x->>'context_hash'),'40001','new operation refuses a prior local day context');
END $$;
SELECT m3b_cycle_test.ok(NOT has_table_privilege(role,'private.mobile_clinical_previews','SELECT,INSERT,UPDATE,DELETE'),
 role||' no direct preview hash journal access') FROM unnest(ARRAY['anon','authenticated','service_role']) role;
SELECT m3b_cycle_test.ok(NOT has_function_privilege(role,
 'private.capture_mobile_clinical_context_at(uuid,text,uuid,timestamptz)','EXECUTE')
 AND NOT has_function_privilege(role,
 'private.prepare_mobile_clinical_preview_at(uuid,text,uuid,uuid,text,jsonb,jsonb,jsonb,timestamptz)','EXECUTE'),
 role||' no private capture or preview execution') FROM unnest(ARRAY['anon','authenticated','service_role']) role;
ROLLBACK;
