-- This two-phase real-PG rollback suite places the exact additive migration at
-- the unique marker below. The owned qualification wrapper strips only the
-- migration's outer BEGIN/COMMIT; no product body/guard is rewritten.
BEGIN;
SET LOCAL request.jwt.claims='{"role":"service_role"}';
SET LOCAL timezone='UTC'; SET LOCAL datestyle='ISO,YMD';
CREATE FUNCTION pg_temp.t41_ok(v boolean,label text) RETURNS void LANGUAGE plpgsql AS $$
BEGIN IF v IS DISTINCT FROM true THEN RAISE EXCEPTION 'T41_FAIL:%',label;END IF;RAISE NOTICE 'T41_PASS:%',label;END $$;
CREATE FUNCTION pg_temp.t41_input(i uuid) RETURNS jsonb LANGUAGE sql AS $$
 SELECT jsonb_build_object('intake_protocol','conversation.intake.v1','intake_id',i,'source',jsonb_build_object('channel','text','text','Fiz 30 minutos de caminhada.'));
$$;
CREATE FUNCTION pg_temp.t41_decision(k text DEFAULT 'workout.report') RETURNS jsonb LANGUAGE sql AS $$
 SELECT jsonb_build_object('schema','conversation.intake-routing.v1','kind',k,'reason','performed_activity');
$$;
CREATE FUNCTION pg_temp.t41_seed(u uuid,e uuid,i uuid) RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE a jsonb;s jsonb;c jsonb;
BEGIN
 INSERT INTO public.users(id,email,status,timezone,country,country_confirmed) VALUES(u,'t41-'||u::text||'@example.invalid','active','UTC','BR',true);
 INSERT INTO private.workout_strength_authority_epochs(user_id,epoch,changed_at) VALUES(u,e,clock_timestamp());
 a:=public.admit_conversation_intake(u,e,pg_temp.t41_input(i));s:=public.capture_conversation_intake_source(u,i,a#>>'{intake,input_hash}',e);
 c:=public.claim_conversation_intake_routing(u,i,a#>>'{intake,input_hash}',e,s->>'source_hash');
 RETURN jsonb_build_object('intake',a->'intake','source',s,'claim',c);
END $$;
CREATE FUNCTION pg_temp.t41_seal(s jsonb,d jsonb DEFAULT pg_temp.t41_decision()) RETURNS jsonb LANGUAGE sql AS $$
 SELECT public.seal_conversation_intake_routing((s#>>'{intake,owner_id}')::uuid,(s#>>'{intake,intake_id}')::uuid,s#>>'{intake,input_hash}',(s#>>'{intake,epoch}')::uuid,s#>>'{source,source_hash}',(s#>>'{claim,claim_id}')::uuid,d);
$$;
CREATE TEMP TABLE t41_cases(label text PRIMARY KEY,seed jsonb NOT NULL,old_selection jsonb,old_read jsonb,old_claim jsonb,proof jsonb,started_at timestamptz DEFAULT clock_timestamp()) ON COMMIT DROP;
DO $before$
DECLARE u uuid;s jsonb;x jsonb;label text;
BEGIN
 PERFORM pg_temp.t41_ok(to_regclass('private.conversation_intake_routing_leases') IS NULL,'pre-DDL fixture runs against exact old five-RPC schema');
 FOREACH label IN ARRAY ARRAY['old_sealed','old_pending'] LOOP
  u:=CASE WHEN label='old_sealed' THEN 'c1410000-0000-4000-8000-000000000001'::uuid ELSE 'c1410000-0000-4000-8000-000000000002'::uuid END;
  s:=pg_temp.t41_seed(u,gen_random_uuid(),gen_random_uuid());x:=NULL;
  IF label='old_sealed' THEN x:=pg_temp.t41_seal(s);PERFORM pg_temp.t41_ok(x->>'action'='sealed','actual old selection admitted by genuine typed RPC');END IF;
  INSERT INTO t41_cases(label,seed,old_selection,old_read,old_claim) VALUES(label,s,x,
   public.read_conversation_intake(u,(s#>>'{intake,intake_id}')::uuid,s#>>'{intake,input_hash}',(s#>>'{intake,epoch}')::uuid),
   (SELECT to_jsonb(c) FROM private.conversation_intake_claims c WHERE user_id=u AND intake_id=(s#>>'{intake,intake_id}')::uuid));
 END LOOP;
END $before$;
-- T41_APPLY_ACTUAL_MIGRATION_HERE
DO $backfill$
DECLARE r record;p jsonb;
BEGIN
 FOR r IN SELECT * FROM t41_cases LOOP
  p:=public.read_conversation_intake_routing_result((r.seed#>>'{intake,owner_id}')::uuid,(r.seed#>>'{intake,intake_id}')::uuid,r.seed#>>'{intake,input_hash}',(r.seed#>>'{intake,epoch}')::uuid,r.seed#>>'{source,source_hash}');
  PERFORM pg_temp.t41_ok(p->>'action'='available' AND p->>'lease_clock_origin'='migration_backfill' AND (p->>'lease_anchor_at')::timestamptz>=r.started_at,'old claim receives conservative explicit migration lease anchor');
  PERFORM pg_temp.t41_ok(public.read_conversation_intake((r.seed#>>'{intake,owner_id}')::uuid,(r.seed#>>'{intake,intake_id}')::uuid,r.seed#>>'{intake,input_hash}',(r.seed#>>'{intake,epoch}')::uuid)=r.old_read,'legacy read5 DTO literal remains exact after migration');
  PERFORM pg_temp.t41_ok((SELECT to_jsonb(c)=r.old_claim FROM private.conversation_intake_claims c WHERE user_id=(r.seed#>>'{intake,owner_id}')::uuid AND intake_id=(r.seed#>>'{intake,intake_id}')::uuid),'old immutable claim row remains byte-exact');
  IF r.label='old_sealed' THEN
   PERFORM pg_temp.t41_ok(p#>>'{result,origin}'='sealed_selection_backfill' AND p#>'{result,decision}'=r.old_selection#>'{selection,decision}' AND p#>>'{result,recorded_at}'=r.old_selection#>>'{selection,selected_at}' AND (p#>>'{result,recorded_at}')::timestamptz<(p->>'lease_anchor_at')::timestamptz,'backfill uses actual selected_at even before conservative migration anchor');
   PERFORM pg_temp.t41_ok(pg_temp.t41_seal(r.seed)=jsonb_set(r.old_selection,'{action}','"replay"'),'old sealed replay remains exact');
  ELSE PERFORM pg_temp.t41_ok(p->'result'='null'::jsonb,'unknown old claim gets no invented routing result');END IF;
  UPDATE t41_cases SET proof=p WHERE label=r.label;
 END LOOP;
END $backfill$;
CREATE FUNCTION pg_temp.t41_read(s jsonb) RETURNS jsonb LANGUAGE sql AS $$
 SELECT public.read_conversation_intake_routing_result((s#>>'{intake,owner_id}')::uuid,(s#>>'{intake,intake_id}')::uuid,s#>>'{intake,input_hash}',(s#>>'{intake,epoch}')::uuid,s#>>'{source,source_hash}');
$$;
CREATE FUNCTION pg_temp.t41_reconcile(s jsonb) RETURNS jsonb LANGUAGE sql AS $$
 SELECT public.reconcile_conversation_intake_routing((s#>>'{intake,owner_id}')::uuid,(s#>>'{intake,intake_id}')::uuid,s#>>'{intake,input_hash}',(s#>>'{intake,epoch}')::uuid,s#>>'{source,source_hash}',(s#>>'{claim,claim_id}')::uuid);
$$;
DO $durable$
DECLARE u uuid:='c1410000-0000-4000-8000-000000000003';e uuid:=gen_random_uuid();s jsonb;p jsonb;raw jsonb;x jsonb;cmd uuid;z integer;
BEGIN
 s:=pg_temp.t41_seed(u,e,gen_random_uuid());p:=pg_temp.t41_read(s);
 PERFORM pg_temp.t41_ok(p->>'lease_clock_origin'='claim' AND (p->>'lease_anchor_at')::timestamptz>=(s#>>'{source,context,captured_at}')::timestamptz AND p->'result'='null','new lease is finite actual claim clock after captured source');
 FOR z IN 1..10 LOOP
  raw:=jsonb_build_object('command_protocol','conversation.command.v1','command_id',gen_random_uuid(),'kind',CASE WHEN z%2=0 THEN 'meal.report' ELSE 'workout.report' END,'source',jsonb_build_object('channel','text','text','Registro sintético'));
  IF z%2=0 THEN x:=public.admit_conversation_meal_command_fenced(u,raw,e);ELSE x:=public.admit_conversation_workout_command(u,e,raw);END IF;
  PERFORM pg_temp.t41_ok(x->>'action'='admitted','original shared typed quota slot');
 END LOOP;
 x:=pg_temp.t41_seal(s);p:=pg_temp.t41_read(s);
 PERFORM pg_temp.t41_ok(x='{"action":"rate_limited"}' AND p#>>'{result,origin}'='router' AND p#>'{result,decision}'=pg_temp.t41_decision() AND (p#>>'{result,recorded_at}')::timestamptz>=(p->>'lease_anchor_at')::timestamptz,'quota refusal durably retains exact classifier result outside child savepoint');
 PERFORM pg_temp.t41_ok((SELECT count(*)=5 FROM private.conversation_workout_command_ids WHERE user_id=u) AND (SELECT count(*)=5 FROM private.conversation_meal_command_ids WHERE user_id=u),'actual mixed quota contains five meals and five workouts');
 SELECT reserved_child_id INTO cmd FROM private.conversation_intake_ids WHERE user_id=u AND intake_id=(s#>>'{intake,intake_id}')::uuid;
 PERFORM pg_temp.t41_ok(NOT EXISTS(SELECT 1 FROM private.conversation_workout_command_ids WHERE user_id=u AND command_id=cmd) AND NOT EXISTS(SELECT 1 FROM private.conversation_intake_selections WHERE user_id=u),'quota failure creates no child or selected effect');
 PERFORM pg_temp.t41_ok(pg_temp.t41_seal(s)='{"action":"rate_limited"}' AND pg_temp.t41_read(s)=p,'same original pair retries typed admission without replacing result or claim');
 PERFORM pg_temp.t41_ok(pg_temp.t41_seal(s,pg_temp.t41_decision('meal.report'))='{"action":"decision_conflict"}' AND pg_temp.t41_read(s)=p,'a new classifier decision cannot replace durable original after refusal');
 INSERT INTO t41_cases(label,seed,proof) VALUES('quota',s,p);
END $durable$;
DO $day$
DECLARE u uuid:='c1410000-0000-4000-8000-000000000004';s jsonb;p jsonb;x jsonb;
BEGIN
 s:=pg_temp.t41_seed(u,gen_random_uuid(),gen_random_uuid());
 INSERT INTO public.daily_snapshots(user_id,date,day_closed) VALUES(u,(clock_timestamp() AT TIME ZONE 'UTC')::date,true);
 PERFORM pg_temp.t41_ok(pg_temp.t41_seal(s)='{"action":"day_closed"}','existing day guard still refuses actual typed admission');p:=pg_temp.t41_read(s);
 PERFORM pg_temp.t41_ok(p#>>'{result,origin}'='router' AND p#>'{result,decision}'=pg_temp.t41_decision() AND NOT EXISTS(SELECT 1 FROM private.conversation_workout_command_ids WHERE user_id=u),'day refusal also preserves routing without child');
 INSERT INTO t41_cases(label,seed,proof) VALUES('day_closed',s,p);
 u:='c1410000-0000-4000-8000-000000000005';s:=pg_temp.t41_seed(u,gen_random_uuid(),gen_random_uuid());UPDATE public.users SET timezone='Pacific/Honolulu' WHERE id=u;
 x:=pg_temp.t41_seal(s);p:=pg_temp.t41_read(s);
 PERFORM pg_temp.t41_ok(x='{"action":"day_changed"}' AND p#>>'{result,origin}'='router','changed local day cannot discard or silently rebind original result');
 u:='c1410000-0000-4000-8000-000000000006';s:=pg_temp.t41_seed(u,gen_random_uuid(),gen_random_uuid());p:=pg_temp.t41_read(s);
 PERFORM pg_temp.t41_ok(pg_temp.t41_reconcile(s)='{"action":"in_flight"}' AND pg_temp.t41_read(s)=p,'fresh claim is not interrupted or renewed by POST/read');
 INSERT INTO t41_cases(label,seed,proof) VALUES('interrupt',s,p);
 u:='c1410000-0000-4000-8000-000000000007';s:=pg_temp.t41_seed(u,gen_random_uuid(),gen_random_uuid());
 INSERT INTO public.daily_snapshots(user_id,date,day_closed) VALUES(u,(clock_timestamp() AT TIME ZONE 'UTC')::date,true);UPDATE public.users SET timezone='Pacific/Honolulu' WHERE id=u;
 INSERT INTO t41_cases(label,seed,proof) VALUES('interrupt_closed_changed',s,pg_temp.t41_read(s));
END $day$;
DO $fences$
DECLARE s jsonb;u uuid;i uuid;e uuid;h text;source text;claim uuid;denied boolean;before jsonb;r jsonb;table_name text;role_name text;
BEGIN
 SELECT seed INTO s FROM t41_cases WHERE label='interrupt';u:=(s#>>'{intake,owner_id}')::uuid;i:=(s#>>'{intake,intake_id}')::uuid;e:=(s#>>'{intake,epoch}')::uuid;h:=s#>>'{intake,input_hash}';source:=s#>>'{source,source_hash}';claim:=(s#>>'{claim,claim_id}')::uuid;before:=pg_temp.t41_read(s);
 PERFORM pg_temp.t41_ok(public.read_conversation_intake_routing_result('c1410000-0000-4000-8000-000000000001',i,h,e,source)='{"action":"absent"}','read ownership isolation');
 PERFORM pg_temp.t41_ok(public.read_conversation_intake_routing_result(u,i,NULL,e,source)='{"action":"input_conflict"}' AND public.read_conversation_intake_routing_result(u,i,h,NULL,source)='{"action":"stale_epoch"}' AND public.read_conversation_intake_routing_result(u,i,h,e,NULL)='{"action":"source_conflict"}','read SQL NULL identity guards');
 PERFORM pg_temp.t41_ok(public.reconcile_conversation_intake_routing(u,i,h,e,source,NULL)='{"action":"claim_conflict"}' AND public.reconcile_conversation_intake_routing(u,i,h,e,repeat('0',64),claim)='{"action":"source_conflict"}','reconcile exact original claim/source guards');
 PERFORM pg_temp.t41_ok(pg_temp.t41_read(s)=before,'all refused calls leave lease and result literal');
 denied:=false;BEGIN PERFORM pg_temp.t41_seal(s,'null');EXCEPTION WHEN invalid_parameter_value THEN denied:=true;END;
 PERFORM pg_temp.t41_ok(denied AND pg_temp.t41_read(s)=before,'SQL NULL routing decision cannot become durable output');
 PERFORM pg_temp.t41_ok((SELECT provolatile='s' FROM pg_proc WHERE oid='public.read_conversation_intake_routing_result(uuid,uuid,text,uuid,text)'::regprocedure),'new read result is STABLE');
 FOREACH table_name IN ARRAY ARRAY['conversation_intake_routing_leases','conversation_intake_routing_results'] LOOP
  PERFORM pg_temp.t41_ok(NOT has_table_privilege('service_role','private.'||table_name,'SELECT') AND NOT has_table_privilege('authenticated','private.'||table_name,'INSERT'),'new sidecars remain private');
 END LOOP;
 FOREACH role_name IN ARRAY ARRAY['anon','authenticated'] LOOP
  denied:=false;BEGIN EXECUTE format('SET LOCAL ROLE %I',role_name);PERFORM public.read_conversation_intake_routing_result(u,i,h,e,source);EXCEPTION WHEN insufficient_privilege THEN denied:=true;END;EXECUTE 'SET LOCAL ROLE NONE';
  PERFORM pg_temp.t41_ok(denied,'untrusted role cannot read routing proof');
 END LOOP;
 EXECUTE 'SET LOCAL ROLE service_role';r:=public.read_conversation_intake_routing_result(u,i,h,e,source);EXECUTE 'SET LOCAL ROLE NONE';PERFORM pg_temp.t41_ok(r=before,'actual service role can read without private table rights');
 UPDATE public.users SET status='blocked' WHERE id=u;
 PERFORM pg_temp.t41_ok(public.read_conversation_intake_routing_result(u,i,h,e,source)='{"action":"stale_epoch"}','inactive owner cannot read original private proof');
 denied:=false;BEGIN PERFORM pg_temp.t41_reconcile(s);EXCEPTION WHEN no_data_found THEN denied:=true;END;PERFORM pg_temp.t41_ok(denied,'inactive owner cannot reconcile');UPDATE public.users SET status='active' WHERE id=u;
END $fences$;

-- One real elapsed lease window also ages the original rolling typed quota.
-- No clock/lease is forged, updated, shortened or advanced by the test.
SELECT pg_sleep(greatest(0,61-extract(epoch FROM(clock_timestamp()-(SELECT max((proof->>'lease_anchor_at')::timestamptz) FROM t41_cases WHERE proof IS NOT NULL)))));
DO $expired$
DECLARE r record;s jsonb;x jsonb;p jsonb;prior jsonb;u uuid;child uuid;
BEGIN
 FOR r IN SELECT * FROM t41_cases WHERE label IN('old_pending','interrupt','interrupt_closed_changed') LOOP
  s:=r.seed;u:=(s#>>'{intake,owner_id}')::uuid;x:=pg_temp.t41_reconcile(s);p:=pg_temp.t41_read(s);
  PERFORM pg_temp.t41_ok(x->>'action'='reconciled' AND x->'result'=p AND p#>>'{result,origin}'='interrupted' AND p#>>'{result,decision,kind}'='clarification_required' AND p#>>'{result,decision,reason}'='routing_interrupted','expired unknown claim atomically stores explicit nonperformed interruption result');
  PERFORM pg_temp.t41_ok((p#>>'{result,recorded_at}')::timestamptz>=(p->>'lease_anchor_at')::timestamptz+interval '60 seconds','interruption clock proves real >=60s lease elapsed');
  prior:=public.read_conversation_intake(u,(s#>>'{intake,intake_id}')::uuid,s#>>'{intake,input_hash}',(s#>>'{intake,epoch}')::uuid);
  PERFORM pg_temp.t41_ok(prior#>>'{selection,decision,reason}'='routing_interrupted' AND prior#>'{selection,command}'='null','legacy read sees durable terminal clarification without child');
  PERFORM pg_temp.t41_ok(pg_temp.t41_reconcile(s)=jsonb_set(x,'{action}','"replay"') AND pg_temp.t41_read(s)=p,'reconciliation replay never renews lease or changes fixed result');
  PERFORM pg_temp.t41_ok(pg_temp.t41_seal(s)='{"action":"decision_conflict"}' AND pg_temp.t41_read(s)=p,'late original classifier cannot overwrite interruption or admit typed child');
  PERFORM pg_temp.t41_ok(NOT EXISTS(SELECT 1 FROM private.conversation_workout_command_ids WHERE user_id=u) AND NOT EXISTS(SELECT 1 FROM private.conversation_meal_command_ids WHERE user_id=u),'interruption creates no typed identity even on closed/changed day');
  UPDATE t41_cases SET proof=p WHERE label=r.label;
 END LOOP;
 SELECT seed,proof INTO s,prior FROM t41_cases WHERE label='day_closed';x:=pg_temp.t41_reconcile(s);
 PERFORM pg_temp.t41_ok(x->>'action'='replay' AND x->'result'=prior AND pg_temp.t41_seal(s)='{"action":"day_closed"}','known router result after day refusal is never replaced by interruption');
 SELECT seed,proof INTO s,prior FROM t41_cases WHERE label='quota';x:=pg_temp.t41_seal(s);p:=pg_temp.t41_read(s);u:=(s#>>'{intake,owner_id}')::uuid;child:=(x#>>'{selection,command,command_id}')::uuid;
 PERFORM pg_temp.t41_ok(x->>'action'='sealed' AND p=prior AND x#>'{selection,decision}'=prior#>'{result,decision}','same original classifier result can retry genuine admission after real quota expiry');
 PERFORM pg_temp.t41_ok((SELECT count(*)=1 FROM private.conversation_workout_command_ids WHERE user_id=u AND command_id=child) AND (SELECT count(*)=1 FROM private.conversation_intake_routing_results WHERE user_id=u) AND (SELECT count(*)=1 FROM private.conversation_intake_claims WHERE user_id=u),'retry has one genuine child one result one original claim');
 PERFORM pg_temp.t41_ok(pg_temp.t41_seal(s)=jsonb_set(x,'{action}','"replay"'),'successful retry then replays exact old selection');
END $expired$;
DO $immutable_reset$
DECLARE s jsonb;u uuid;e uuid;i uuid;h text;source text;denied boolean;table_name text;before jsonb;
BEGIN
 SELECT seed INTO s FROM t41_cases WHERE label='interrupt';u:=(s#>>'{intake,owner_id}')::uuid;e:=(s#>>'{intake,epoch}')::uuid;i:=(s#>>'{intake,intake_id}')::uuid;h:=s#>>'{intake,input_hash}';source:=s#>>'{source,source_hash}';
 FOREACH table_name IN ARRAY ARRAY['conversation_intake_routing_leases','conversation_intake_routing_results'] LOOP
  denied:=false;BEGIN EXECUTE format('UPDATE private.%I SET user_id=user_id WHERE user_id=$1',table_name) USING u;EXCEPTION WHEN invalid_parameter_value THEN denied:=true;END;
  PERFORM pg_temp.t41_ok(denied,'lease/result updates cannot extend deadline or replace decision');
 END LOOP;
 before:=pg_temp.t41_read(s);
 PERFORM pg_temp.t41_ok(NOT EXISTS(SELECT 1 FROM public.workout_logs WHERE user_id::text LIKE 'c141%') AND NOT EXISTS(SELECT 1 FROM public.meal_logs WHERE user_id::text LIKE 'c141%') AND NOT EXISTS(SELECT 1 FROM public.messages WHERE user_id::text LIKE 'c141%') AND NOT EXISTS(SELECT 1 FROM public.user_progress WHERE user_id::text LIKE 'c141%'),'all routing/lease/read/retry work leaves effects messages XP and credit absent before explicit legacy reset');
 PERFORM public.reset_user_conversation_atomic(u,true);
 PERFORM pg_temp.t41_ok(public.read_conversation_intake_routing_result(u,i,h,e,source)='{"action":"stale_epoch"}' AND pg_temp.t41_reconcile(s)='{"action":"stale_epoch"}','reset invalidates both new APIs under original epoch');
 SELECT epoch INTO e FROM private.workout_strength_authority_epochs WHERE user_id=u;
 PERFORM pg_temp.t41_ok(public.read_conversation_intake_routing_result(u,i,h,e,source)='{"action":"stale_epoch"}' AND public.admit_conversation_intake(u,e,pg_temp.t41_input(i))='{"action":"stale_epoch"}','new epoch cannot revive old routing/claim identity');
 PERFORM pg_temp.t41_ok(NOT EXISTS(SELECT 1 FROM private.conversation_intake_routing_results WHERE user_id=u) AND NOT EXISTS(SELECT 1 FROM private.conversation_intake_routing_leases WHERE user_id=u) AND NOT EXISTS(SELECT 1 FROM private.conversation_intake_claims WHERE user_id=u) AND NOT EXISTS(SELECT 1 FROM private.conversation_intake_sources WHERE user_id=u) AND (SELECT count(*)=1 AND bool_and(invalidated_at IS NOT NULL AND input_hash=h) FROM private.conversation_intake_ids WHERE user_id=u),'epoch cascade scrubs raw source and both sidecars while retaining original tombstone hash');
 PERFORM pg_temp.t41_ok(NOT EXISTS(SELECT 1 FROM public.workout_logs WHERE user_id::text LIKE 'c141%') AND NOT EXISTS(SELECT 1 FROM public.meal_logs WHERE user_id::text LIKE 'c141%') AND NOT EXISTS(SELECT 1 FROM public.messages WHERE user_id::text LIKE 'c141%') AND (SELECT count(*)=1 AND bool_and(xp_total=0 AND level=1 AND current_streak=0 AND longest_streak=0 AND blocks_completed=0 AND deficit_block=0) FROM public.user_progress WHERE user_id=u),'explicit existing reset preserves its own official zero-progress behavior without routing reward');
END $immutable_reset$;
SELECT jsonb_build_object('schema','t41.actual-routing-result-golden.v1','cases',jsonb_agg(jsonb_build_object('label',label,'result',proof) ORDER BY label))::text FROM t41_cases;
SELECT jsonb_agg(jsonb_build_object('signature',p.oid::regprocedure::text,'prosrc_sha256',encode(sha256(convert_to(p.prosrc,'UTF8')),'hex'),'volatility',p.provolatile) ORDER BY p.proname)::text FROM pg_proc p WHERE p.oid IN('public.read_conversation_intake_routing_result(uuid,uuid,text,uuid,text)'::regprocedure,'public.reconcile_conversation_intake_routing(uuid,uuid,text,uuid,text,uuid)'::regprocedure,'public.seal_conversation_intake_routing(uuid,uuid,text,uuid,text,uuid,jsonb)'::regprocedure);

ROLLBACK;
