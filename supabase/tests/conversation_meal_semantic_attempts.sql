-- Owned real local PostgreSQL. All synthetic domain rows roll back.
BEGIN;
\ir fixtures/conversation_meal_semantic_fixture.sql
DO $exists$
BEGIN PERFORM pg_temp.writer_ok(to_regprocedure('public.start_conversation_meal_semantic_attempt(uuid,uuid,text,text)') IS NOT NULL,'semantic start CAS exists');END $exists$;
DO $attempt$
DECLARE a uuid:='c3a20000-0000-4000-8000-000000000001';cmd uuid:='c3a20000-0000-4000-8000-000000000002';other uuid:='c3a20000-0000-4000-8000-000000000003';
 version text:='conversation.meal-interpreter.v1';source jsonb;claim jsonb;x jsonb;f jsonb;before_all jsonb;prepared jsonb;effect jsonb;code text;message text;
BEGIN
 INSERT INTO public.users(id,email,status,timezone,country,country_confirmed) VALUES(a,'semantic-attempt@example.invalid','active','UTC','BR',true),(other,'semantic-other@example.invalid','active','UTC','BR',true);
 PERFORM set_config('request.jwt.claims','{"role":"service_role"}',true);
 PERFORM public.admit_conversation_meal_command(a,pg_temp.writer_input(cmd));
 before_all:=pg_temp.semantic_owner_state(a);
 x:=public.read_conversation_meal_prepared(a,cmd);
 PERFORM pg_temp.writer_ok(x->>'action'='available' AND x->'source'='null' AND x->'resolved'='null' AND x->'receipt'='null' AND pg_temp.semantic_owner_state(a)=before_all,'admitted read has no capture/preparation/effect');
 PERFORM pg_temp.writer_ok(public.start_conversation_meal_semantic_attempt(a,cmd,version,repeat('a',64))='{"action":"source_required"}'::jsonb,'first claim requires stored source without candidate');
 source:=public.capture_conversation_meal_source(a,cmd);
 PERFORM pg_temp.writer_ok(public.start_conversation_meal_semantic_attempt(a,cmd,version,repeat('a',64))='{"action":"source_conflict"}'::jsonb,'first claim binds actual source hash');
 claim:=public.start_conversation_meal_semantic_attempt(a,cmd,version,source->>'source_hash');
 PERFORM pg_temp.writer_ok(claim->>'action'='claimed' AND claim->>'status'='started' AND claim->'result'='null' AND claim->'finished_at'='null' AND claim->>'attempt_id' IS NOT NULL,'new start mints exactly one invocation permission');
 before_all:=pg_temp.semantic_owner_state(a);
 PERFORM pg_temp.writer_ok(public.read_conversation_meal_semantic_attempt(a,cmd,version)=jsonb_set(claim,'{action}','"reconciliation_required"') AND pg_temp.semantic_owner_state(a)=before_all,'started read never grants permission or writes');
 PERFORM pg_temp.writer_ok(public.start_conversation_meal_semantic_attempt(a,cmd,version,NULL)=jsonb_set(claim,'{action}','"reconciliation_required"'),'lost start response cannot reacquire claim');
 PERFORM pg_temp.writer_ok(public.read_conversation_meal_semantic_attempt(other,cmd,version)='{"action":"absent"}'::jsonb,'foreign read has no result or attempt');
 f:=pg_temp.semantic_result(claim);
 PERFORM pg_temp.writer_ok(public.commit_conversation_meal_semantic_result(a,cmd,version,gen_random_uuid(),f)='{"action":"attempt_conflict"}'::jsonb,'caller-picked attempt cannot finish or see winner');
 BEGIN PERFORM public.commit_conversation_meal_semantic_result(a,cmd,version,(claim->>'attempt_id')::uuid,f||'{"complete_source":true}');
 EXCEPTION WHEN OTHERS THEN GET STACKED DIAGNOSTICS code=RETURNED_SQLSTATE,message=MESSAGE_TEXT;END;
 PERFORM pg_temp.writer_ok(code='22023' AND message='invalid_conversation_semantic_result' AND pg_temp.semantic_owner_state(a)=before_all,'unknown result key redacted without state change');
 INSERT INTO public.daily_snapshots(user_id,date,day_closed) VALUES(a,(clock_timestamp() AT TIME ZONE 'UTC')::date,true);
 PERFORM pg_temp.writer_ok(public.start_conversation_meal_semantic_attempt(a,cmd,version,NULL)=jsonb_set(claim,'{action}','"reconciliation_required"'),'closed day never reclaims an already started attempt');
 x:=public.commit_conversation_meal_semantic_result(a,cmd,version,(claim->>'attempt_id')::uuid,f);
 PERFORM pg_temp.writer_ok(x->>'action'='committed' AND x->>'status'='completed' AND x->'result'=f AND x->>'result_hash' ~ '^[a-f0-9]{64}$','first result durable against original claim');
 PERFORM pg_temp.writer_ok(public.start_conversation_meal_semantic_attempt(a,cmd,version,NULL)=jsonb_set(x,'{action}','"replay"') AND public.commit_conversation_meal_semantic_result(a,cmd,version,(claim->>'attempt_id')::uuid,NULL)=jsonb_set(x,'{action}','"replay"'),'completed replay precedes fresh source and replacement payload');
 PERFORM pg_temp.writer_ok(public.mark_conversation_meal_semantic_unknown(a,cmd,version,(claim->>'attempt_id')::uuid,NULL)=jsonb_set(x,'{action}','"replay"'),'completed winner precedes a later empty error');
 PERFORM pg_temp.writer_ok(public.read_conversation_meal_semantic_attempt(a,cmd,version)=jsonb_set(x,'{action}','"available"'),'result read returns exact immutable result/hash');
 PERFORM pg_temp.writer_ok(public.commit_conversation_meal_semantic_result(a,cmd,version,gen_random_uuid(),NULL)='{"action":"attempt_conflict"}'::jsonb,'wrong attempt never receives completed payload');
 before_all:=pg_temp.semantic_owner_state(a);x:=public.read_conversation_meal_prepared(a,cmd);
 PERFORM pg_temp.writer_ok(x#>>'{source,source_hash}'=source->>'source_hash' AND x#>'{source,context}'=source->'context' AND x->'resolved'='null' AND x->'receipt'='null' AND pg_temp.semantic_owner_state(a)=before_all,'source read recovery is full, owned and effect-free');
 UPDATE public.daily_snapshots SET day_closed=false WHERE user_id=a;
 prepared:=public.prepare_conversation_meal(a,cmd,pg_temp.writer_resolved(source));
 x:=public.read_conversation_meal_prepared(a,cmd);
 PERFORM pg_temp.writer_ok(x#>>'{resolved,resolved_hash}'=prepared->>'resolved_hash' AND x#>'{resolved,resolved}'=pg_temp.writer_resolved(source),'lost prepare response recovers full sealed resolved payload');
 effect:=public.commit_conversation_meal(a,cmd,prepared->>'resolved_hash');
 x:=public.read_conversation_meal_prepared(a,cmd);
 PERFORM pg_temp.writer_ok(x->'receipt'=effect->'receipt' AND x->'source'<>'null' AND x->'resolved'<>'null','lost writer response recovers factual receipt with parent payloads');
 before_all:=pg_temp.semantic_owner_state(a);PERFORM public.read_conversation_meal_prepared(a,cmd);
 PERFORM pg_temp.writer_ok(pg_temp.semantic_owner_state(a)=before_all,'post-effect recovery has no domain/feedback/reward writes');
 PERFORM public.reset_user_conversation_atomic(a,true);
 PERFORM pg_temp.writer_ok(public.read_conversation_meal_prepared(a,cmd)='{"action":"stale_epoch"}'::jsonb AND public.read_conversation_meal_semantic_attempt(a,cmd,version)='{"action":"stale_epoch"}'::jsonb AND public.start_conversation_meal_semantic_attempt(a,cmd,version,NULL)='{"action":"stale_epoch"}'::jsonb AND public.commit_conversation_meal_semantic_result(a,cmd,version,(claim->>'attempt_id')::uuid,NULL)='{"action":"stale_epoch"}'::jsonb,'reset scrubs state and UUID cannot reacquire provider/domain');
END $attempt$;
DO $unknown$
DECLARE a uuid:='c3a20000-0000-4000-8000-000000000010';cmd uuid:='c3a20000-0000-4000-8000-000000000011';version text:='conversation.meal-interpreter.v1';source jsonb;claim jsonb;x jsonb;
BEGIN
 INSERT INTO public.users(id,email,status,timezone,country,country_confirmed) VALUES(a,'semantic-unknown@example.invalid','active','UTC','BR',true);
 PERFORM set_config('request.jwt.claims','{"role":"service_role"}',true);
 source:=pg_temp.writer_seed(a,cmd);claim:=public.start_conversation_meal_semantic_attempt(a,cmd,version,source->>'source_hash');
 x:=public.mark_conversation_meal_semantic_unknown(a,cmd,version,(claim->>'attempt_id')::uuid,'provider_outcome_unknown');
 PERFORM pg_temp.writer_ok(x->>'action'='committed' AND x->>'status'='unknown' AND x->>'error_code'='provider_outcome_unknown','uncertain provider outcome is durable terminal unknown');
 PERFORM pg_temp.writer_ok(public.read_conversation_meal_semantic_attempt(a,cmd,version)=jsonb_set(x,'{action}','"reconciliation_required"') AND public.start_conversation_meal_semantic_attempt(a,cmd,version,NULL)=jsonb_set(x,'{action}','"reconciliation_required"'),'unknown remains read/reconcile only');
 PERFORM pg_temp.writer_ok(public.commit_conversation_meal_semantic_result(a,cmd,version,(claim->>'attempt_id')::uuid,pg_temp.semantic_result(claim))=jsonb_set(x,'{action}','"replay"'),'late result cannot overwrite first terminal unknown');
END $unknown$;
SELECT count(*) AS semantic_assertions FROM meal_writer_assertions;
ROLLBACK;
