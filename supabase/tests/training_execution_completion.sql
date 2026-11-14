-- Synthetic fixtures; actual protected workout/clinical/strength writers. Entire run rolls back.
BEGIN;
INSERT INTO auth.users(id,email) VALUES('13700000-0000-4000-8000-000000000001','r139-training-completion@example.invalid');
INSERT INTO public.users(id,auth_user_id,name,timezone) VALUES('13700000-0000-4000-8000-000000000002','13700000-0000-4000-8000-000000000001','Synthetic R139 training completion','America/Sao_Paulo');
INSERT INTO public.user_profiles(user_id,weight_kg) VALUES('13700000-0000-4000-8000-000000000002',80) ON CONFLICT(user_id) DO UPDATE SET weight_kg=excluded.weight_kg;
INSERT INTO auth.sessions(id,user_id,created_at,not_after) VALUES('139d0000-0000-4000-8000-000000000005','13700000-0000-4000-8000-000000000001',clock_timestamp(),NULL);
INSERT INTO private.workout_strength_authority_epochs(user_id,epoch,changed_at) VALUES('13700000-0000-4000-8000-000000000002','13700000-0000-4000-8000-000000000010',clock_timestamp());
INSERT INTO private.training_execution_sessions(user_id,session_id,epoch,revision,state) VALUES('13700000-0000-4000-8000-000000000002','13700000-0000-4000-8000-000000000020','13700000-0000-4000-8000-000000000010',0,$state${"schema": "training.execution.v1", "id": "13700000-0000-4000-8000-000000000020", "owner_id": "13700000-0000-4000-8000-000000000002", "auth_user_id": "13700000-0000-4000-8000-000000000001", "epoch": "13700000-0000-4000-8000-000000000010", "time_zone": "America/Sao_Paulo", "local_date": "2026-11-14", "started_at": "2026-11-14T20:00:00.000000Z", "updated_at": "2026-11-14T20:00:00.000000Z", "phase": "in_progress", "revision": 0, "definition": {"plan_id": "13700000-0000-4000-8000-000000000004", "plan_version": 1, "plan_hash": "3791b20c526113d3a8f1068e4d8447d027785d657883900d628dea1005647b55", "day_index": 0, "day_label": "Sábado", "focus": "Força", "recommended_duration_min": 30, "exercises": [{"index": 0, "fingerprint": "4bb3cd1105ce82fa0267625daf4129be93ef2a105a846b47b2c2ed078557946d", "name": "Supino", "muscle_group": null, "recommended_sets": 3, "reps_reference": "8–12", "rest_seconds": 60, "rpe_target": null, "notes": null, "execution_steps": [], "common_mistakes": []}, {"index": 1, "fingerprint": "e28005d4c5f88783dfd909dc3b38292f089519d40ae008adcc37e7c549b81757", "name": "Supino", "muscle_group": null, "recommended_sets": 2, "reps_reference": "6–8", "rest_seconds": null, "rpe_target": null, "notes": null, "execution_steps": [], "common_mistakes": []}]}, "exercises": [{"index": 0, "completed": false, "sets": []}, {"index": 1, "completed": false, "sets": []}]}$state$::jsonb||jsonb_build_object('local_date',(transaction_timestamp() AT TIME ZONE 'America/Sao_Paulo')::date::text,
 'started_at',private.conversation_workout_clock(transaction_timestamp()-interval '1 minute'),
 'updated_at',private.conversation_workout_clock(transaction_timestamp()-interval '1 minute')));
CREATE TEMP TABLE finish_fixture AS SELECT '13700000-0000-4000-8000-000000000002'::uuid owner_id,'13700000-0000-4000-8000-000000000001'::uuid auth_id,'139d0000-0000-4000-8000-000000000005'::uuid login_id,'13700000-0000-4000-8000-000000000020'::uuid session_id,'139d0000-0000-4000-8000-000000000003'::uuid completion_id,'13700000-0000-4000-8000-000000000010'::uuid epoch,$finish${"schema": "training.execution.finish.v1", "session_id": "13700000-0000-4000-8000-000000000020", "operation_id": "139d0000-0000-4000-8000-000000000003", "expected_epoch": "13700000-0000-4000-8000-000000000010", "expected_revision": 0, "source": {"channel": "text", "text": "Fiz full body por 30 min com intensidade moderada."}}$finish$::jsonb command;

CREATE FUNCTION pg_temp.prepare_training_finish() RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE f record;b jsonb;s jsonb;p jsonb;
BEGIN
 SELECT * INTO STRICT f FROM finish_fixture;
 b:=public.begin_training_execution_completion_authenticated(f.owner_id,f.auth_id,f.login_id,f.command);
 s:=public.capture_conversation_workout_source(f.owner_id,f.completion_id,b#>>'{completion,workout_hash}',f.epoch);
 p:=public.prepare_conversation_workout(f.owner_id,f.completion_id,b#>>'{completion,workout_hash}',s->>'source_hash',f.epoch,
  private.conversation_workout_report_v2(s->'context',s->>'source_hash'));
 ASSERT p#>>'{prepared,status}'='ready',p::text;
 RETURN jsonb_build_object('begin',b,'source',s,'prepared',p);
END $$;
CREATE FUNCTION pg_temp.commit_training_finish(x jsonb) RETURNS jsonb LANGUAGE sql AS $$
 SELECT public.commit_training_execution_completion_authenticated(f.owner_id,f.auth_id,f.login_id,f.completion_id,
 x#>>'{begin,completion,input_hash}',x#>>'{source,source_hash}',x#>>'{prepared,prepared_hash}',x#>'{prepared,prepared}') FROM finish_fixture f;
$$;
SAVEPOINT main;
DO $test$
DECLARE f record;beginning jsonb;again jsonb;source jsonb;report jsonb;prepared jsonb;effect jsonb;replayed jsonb;state jsonb;blocked boolean:=false;changed jsonb;fhash text;whash text;
BEGIN
 SELECT * INTO STRICT f FROM finish_fixture;
 beginning:=public.begin_training_execution_completion_authenticated(f.owner_id,f.auth_id,f.login_id,f.command);
 ASSERT beginning->>'action'='reserved','finish reserves the original actual state';
 ASSERT beginning#>>'{completion,status}'='reserved';
 ASSERT beginning#>'{completion,frozen_state,exercises,0,sets}'='[]'::jsonb,'prescribed sets are never performed by finish';
 fhash:=beginning#>>'{completion,input_hash}';whash:=beginning#>>'{completion,workout_hash}';
 ASSERT fhash ~ '^[0-9a-f]{64}$' AND whash ~ '^[0-9a-f]{64}$';
 ASSERT NOT EXISTS(SELECT 1 FROM public.workout_logs WHERE user_id=f.owner_id),'reserve is not a workout';
 again:=public.begin_training_execution_completion_authenticated(f.owner_id,f.auth_id,f.login_id,f.command);
 ASSERT again#>'{completion}'=beginning#>'{completion}','same finish is immutable and idempotent';
 changed:=jsonb_set(f.command,'{source,text}','"Fiz full body por 40 min com intensidade moderada."');
 BEGIN PERFORM public.begin_training_execution_completion_authenticated(f.owner_id,f.auth_id,f.login_id,changed);
 EXCEPTION WHEN serialization_failure THEN blocked:=true; END;ASSERT blocked,'same operation cannot change accepted report';blocked:=false;
 changed:=jsonb_set(f.command,'{operation_id}','"139d0000-0000-4000-8000-000000000008"');
 BEGIN PERFORM public.begin_training_execution_completion_authenticated(f.owner_id,f.auth_id,f.login_id,changed);
 EXCEPTION WHEN serialization_failure THEN blocked:=true; END;ASSERT blocked,'one active completion per execution';blocked:=false;
 effect:=public.commit_conversation_workout(f.owner_id,f.completion_id,whash,repeat('a',64),f.epoch,repeat('b',64),'{}');
 ASSERT effect->>'action'='training_completion_required','ordinary writer cannot bypass the reserved training completion';
 BEGIN PERFORM public.commit_training_execution_mutation(f.owner_id,f.auth_id,jsonb_build_object('session_id',f.session_id,'operation_id','139d0000-0000-4000-8000-000000000009'),repeat('a',64),clock_timestamp(),'{}');
 EXCEPTION WHEN serialization_failure THEN blocked:=true; END;ASSERT blocked,'frozen actual sets cannot change';
 source:=public.capture_conversation_workout_source(f.owner_id,f.completion_id,whash,f.epoch);
 report:=private.conversation_workout_report_v2(source->'context',source->>'source_hash');
 ASSERT report->>'status'='ready',report::text;
 prepared:=public.prepare_conversation_workout(f.owner_id,f.completion_id,whash,source->>'source_hash',f.epoch,report);
 ASSERT prepared#>>'{prepared,status}'='ready',prepared::text;
 effect:=public.commit_training_execution_completion_authenticated(f.owner_id,f.auth_id,f.login_id,f.completion_id,fhash,source->>'source_hash',prepared->>'prepared_hash',prepared->'prepared');
 ASSERT effect->>'action'='committed',effect::text;
 ASSERT (SELECT count(*) FROM public.workout_logs WHERE user_id=f.owner_id)=1,'one workout per execution';
 SELECT s.state INTO STRICT state FROM private.training_execution_sessions s WHERE s.user_id=f.owner_id AND s.session_id=f.session_id;
 ASSERT state->>'phase'='completed' AND state->>'schema'='training.execution.v2' AND state->>'revision'='1','official receipt atomically completes the actual execution';
 ASSERT state->'exercises'=beginning#>'{completion,frozen_state,exercises}','finish does not invent actual sets or checked exercises';
 ASSERT (SELECT c.receipt#>>'{workout,workout_id}' FROM private.training_execution_completions c WHERE c.user_id=f.owner_id AND c.completion_id=f.completion_id)=effect#>>'{receipt,workout_id}','linked receipt proves the same workout';
 replayed:=public.commit_training_execution_completion_authenticated(f.owner_id,f.auth_id,f.login_id,f.completion_id,fhash,source->>'source_hash',prepared->>'prepared_hash',prepared->'prepared');
 ASSERT replayed->>'action'='replay' AND replayed->'receipt'=effect->'receipt','lost reply recovers original receipt';
 ASSERT (SELECT count(*) FROM public.workout_logs WHERE user_id=f.owner_id)=1;
 ASSERT (SELECT count(*) FROM private.training_execution_completion_events WHERE user_id=f.owner_id)=2,'reserve and complete are audited once';
 ASSERT NOT has_table_privilege('service_role','private.training_execution_completions','SELECT');
 ASSERT NOT has_function_privilege('authenticated','public.begin_training_execution_completion_authenticated(uuid,uuid,uuid,jsonb)','EXECUTE');
 ASSERT NOT has_function_privilege('service_role','private.commit_conversation_workout_unreserved(uuid,uuid,text,text,uuid,text,jsonb)','EXECUTE');
 RAISE NOTICE 'R139_REAL_WORKOUT_AND_COMPLETION_ATOMIC_REPLAY_PASS';
END $test$;
ROLLBACK TO main;

SAVEPOINT cancellation;
DO $test$
DECLARE f record;x jsonb;a jsonb;b jsonb;denied boolean:=false;
BEGIN
 SELECT * INTO STRICT f FROM finish_fixture;x:=pg_temp.prepare_training_finish();
 a:=public.cancel_training_execution_completion_authenticated(f.owner_id,f.auth_id,f.login_id,f.completion_id,x#>>'{begin,completion,input_hash}');
 ASSERT a->>'action'='cancelled';
 b:=public.cancel_training_execution_completion_authenticated(f.owner_id,f.auth_id,f.login_id,f.completion_id,x#>>'{begin,completion,input_hash}');
 ASSERT b->>'action'='replay' AND b->'receipt'=a->'receipt';
 BEGIN PERFORM pg_temp.commit_training_finish(x);EXCEPTION WHEN serialization_failure THEN denied:=true;END;
 ASSERT denied,'cancelled delayed completion must never record';
 a:=public.commit_conversation_workout(f.owner_id,f.completion_id,x#>>'{begin,completion,workout_hash}',x#>>'{source,source_hash}',f.epoch,x#>>'{prepared,prepared_hash}',x#>'{prepared,prepared}');
 ASSERT a->>'action'='training_completion_required','cancelled late job cannot use ordinary writer';
 ASSERT NOT EXISTS(SELECT 1 FROM public.workout_logs WHERE user_id=f.owner_id);
 ASSERT (SELECT state->>'phase' FROM private.training_execution_sessions WHERE user_id=f.owner_id)='in_progress';
 b:=public.begin_training_execution_completion_authenticated(f.owner_id,f.auth_id,f.login_id,
 jsonb_set(f.command,'{operation_id}','"139d0000-0000-4000-8000-000000000088"'));
 ASSERT b->>'action'='reserved','a new accepted report can follow a safe cancellation';
 RAISE NOTICE 'R139_CANCEL_LATE_WRITER_NEW_COMMAND_PASS';
END $test$;
ROLLBACK TO cancellation;

SAVEPOINT auth_and_day;
DO $test$
DECLARE f record;x jsonb;denied boolean:=false;bad uuid;
BEGIN
 SELECT * INTO STRICT f FROM finish_fixture;x:=pg_temp.prepare_training_finish();
 FOREACH bad IN ARRAY ARRAY[f.completion_id,'139d0000-0000-4000-8000-000000000099'::uuid] LOOP
  BEGIN PERFORM public.read_training_execution_completion_authenticated(f.owner_id,f.auth_id,bad,f.completion_id);
  EXCEPTION WHEN insufficient_privilege THEN denied:=true;END;
  ASSERT denied,'unproved login must not read or regain finish';denied:=false;
 END LOOP;
 UPDATE auth.sessions SET not_after=clock_timestamp()-interval '1 second' WHERE id=f.login_id;
 BEGIN PERFORM pg_temp.commit_training_finish(x);EXCEPTION WHEN insufficient_privilege THEN denied:=true;END;
 ASSERT denied,'expired original login cannot finish';denied:=false;
 UPDATE auth.sessions SET not_after=NULL WHERE id=f.login_id;
 UPDATE public.users SET timezone='UTC' WHERE id=f.owner_id;
 BEGIN PERFORM pg_temp.commit_training_finish(x);EXCEPTION WHEN serialization_failure THEN denied:=true;END;
 ASSERT denied,'changed timezone cannot finish an old claim';denied:=false;
 UPDATE public.users SET timezone='America/Sao_Paulo' WHERE id=f.owner_id;
 INSERT INTO public.daily_snapshots(user_id,date,day_closed) VALUES(f.owner_id,(x#>>'{begin,session,local_date}')::date,true);
 BEGIN PERFORM pg_temp.commit_training_finish(x);EXCEPTION WHEN serialization_failure THEN denied:=true;END;
 ASSERT denied,'closed original day cannot acquire a new effect';
 ASSERT NOT EXISTS(SELECT 1 FROM public.workout_logs WHERE user_id=f.owner_id);
 ASSERT (SELECT status FROM private.training_execution_completions WHERE user_id=f.owner_id)='reserved';
 RAISE NOTICE 'R139_ORIGINAL_AUTH_TIMEZONE_CLOSED_DAY_PASS';
END $test$;
ROLLBACK TO auth_and_day;

SAVEPOINT atomic_audit;
CREATE FUNCTION pg_temp.reject_completion_audit() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN IF NEW.kind='completed' THEN RAISE EXCEPTION 'synthetic_completion_audit_failure' USING ERRCODE='P0001';END IF;RETURN NEW;END $$;
CREATE TRIGGER r139_reject_completion_audit BEFORE INSERT ON private.training_execution_completion_events FOR EACH ROW EXECUTE FUNCTION pg_temp.reject_completion_audit();
DO $test$
DECLARE f record;x jsonb;denied boolean:=false;a jsonb;
BEGIN
 SELECT * INTO STRICT f FROM finish_fixture;x:=pg_temp.prepare_training_finish();
 BEGIN PERFORM pg_temp.commit_training_finish(x);EXCEPTION WHEN raise_exception THEN
  IF SQLERRM<>'synthetic_completion_audit_failure' THEN RAISE;END IF;denied:=true;END;
 ASSERT denied,'injected final audit failure must be reached';
 ASSERT NOT EXISTS(SELECT 1 FROM public.workout_logs WHERE user_id=f.owner_id),'audit failure rolls back the actual workout';
 ASSERT NOT EXISTS(SELECT 1 FROM private.conversation_workout_effects WHERE user_id=f.owner_id),'no orphan receipt';
 ASSERT NOT EXISTS(SELECT 1 FROM public.daily_snapshots WHERE user_id=f.owner_id),'no orphan clinical snapshot';
 ASSERT (SELECT status FROM private.training_execution_completions WHERE user_id=f.owner_id)='reserved';
 ASSERT (SELECT state FROM private.training_execution_sessions WHERE user_id=f.owner_id)=x#>'{begin,completion,frozen_state}','no terminal fiction';
 RAISE NOTICE 'R139_DOMAIN_COMPLETION_AUDIT_ATOMIC_ROLLBACK_PASS';
END $test$;
ROLLBACK TO atomic_audit;

SAVEPOINT replay_after_delete;
DO $test$
DECLARE f record;x jsonb;a jsonb;b jsonb;c jsonb;denied boolean:=false;
BEGIN
 SELECT * INTO STRICT f FROM finish_fixture;x:=pg_temp.prepare_training_finish();a:=pg_temp.commit_training_finish(x);
 ASSERT a->>'action'='committed';
 UPDATE public.daily_snapshots SET day_closed=true WHERE user_id=f.owner_id;
 b:=pg_temp.commit_training_finish(x);ASSERT b->>'action'='replay' AND b->'receipt'=a->'receipt';
 -- Effect FK intentionally retains the original receipt when a domain log is
 -- removed. This tests late replay after removal, not the separate Undo policy.
 DELETE FROM public.workout_logs WHERE user_id=f.owner_id AND id=(a#>>'{receipt,workout_id}')::uuid;
 c:=public.read_training_execution_completion_authenticated(f.owner_id,f.auth_id,f.login_id,f.completion_id);
 ASSERT c->'workout_is_live'='false'::jsonb AND c#>>'{session,phase}'='completed';
 b:=pg_temp.commit_training_finish(x);ASSERT b->>'action'='replay' AND b->'receipt'=a->'receipt';
 ASSERT NOT EXISTS(SELECT 1 FROM public.workout_logs WHERE user_id=f.owner_id),'replay never restores a removed effect';
 c:=public.cancel_training_execution_completion_authenticated(f.owner_id,f.auth_id,f.login_id,f.completion_id,x#>>'{begin,completion,input_hash}');
 ASSERT c->>'action'='completed','cancelling a completed finish is observational';
 BEGIN PERFORM public.begin_training_execution_completion_authenticated(f.owner_id,f.auth_id,f.login_id,
 jsonb_set(f.command,'{operation_id}','"139d0000-0000-4000-8000-000000000088"'));EXCEPTION WHEN serialization_failure THEN denied:=true;END;
 ASSERT denied,'removed workout cannot be earned again with a new nonce';
 RAISE NOTICE 'R139_CLOSED_DAY_REMOVED_EFFECT_REPLAY_NO_RESURRECTION_PASS';
END $test$;
ROLLBACK TO replay_after_delete;

SAVEPOINT epoch_delete;
DO $test$
DECLARE f record;x jsonb;b jsonb;
BEGIN
 SELECT * INTO STRICT f FROM finish_fixture;x:=pg_temp.prepare_training_finish();
 UPDATE private.workout_strength_authority_epochs SET epoch='139d0000-0000-4000-8000-000000000077' WHERE user_id=f.owner_id;
 ASSERT NOT EXISTS(SELECT 1 FROM private.training_execution_completions WHERE user_id=f.owner_id),'epoch scrubs obsolete reservation';
 b:=public.commit_conversation_workout(f.owner_id,f.completion_id,x#>>'{begin,completion,workout_hash}',x#>>'{source,source_hash}',f.epoch,x#>>'{prepared,prepared_hash}',x#>'{prepared,prepared}');
 ASSERT b->>'action'<>'committed' AND NOT EXISTS(SELECT 1 FROM public.workout_logs WHERE user_id=f.owner_id),'late old epoch cannot bypass a scrubbed reservation';
 DELETE FROM public.users WHERE id=f.owner_id;
 ASSERT NOT EXISTS(SELECT 1 FROM private.training_execution_sessions WHERE user_id=f.owner_id);
 ASSERT NOT EXISTS(SELECT 1 FROM private.training_execution_completion_events WHERE user_id=f.owner_id);
 RAISE NOTICE 'R139_EPOCH_AND_ACCOUNT_DELETE_NO_LATE_EFFECT_PASS';
END $test$;
ROLLBACK TO epoch_delete;


SAVEPOINT ordinary_workout;
DO $test$
DECLARE f record;x jsonb;b jsonb;s jsonb;p jsonb;c jsonb;ordinary uuid:='139d0000-0000-4000-8000-000000000066';
BEGIN
 SELECT * INTO STRICT f FROM finish_fixture;x:=pg_temp.prepare_training_finish();
 INSERT INTO public.daily_snapshots(user_id,date,calories_target,protein_target) VALUES(f.owner_id,(x#>>'{begin,session,local_date}')::date,2000,140);
 b:=public.admit_conversation_workout_command(f.owner_id,f.epoch,jsonb_set(x#>'{begin,completion,workout_input}','{command_id}',to_jsonb(ordinary::text)));
 ASSERT b->>'action'='admitted';
 s:=public.capture_conversation_workout_source(f.owner_id,ordinary,b#>>'{command,input_hash}',f.epoch);
 p:=public.prepare_conversation_workout(f.owner_id,ordinary,b#>>'{command,input_hash}',s->>'source_hash',f.epoch,private.conversation_workout_report_v2(s->'context',s->>'source_hash'));
 c:=public.commit_conversation_workout(f.owner_id,ordinary,b#>>'{command,input_hash}',s->>'source_hash',f.epoch,p->>'prepared_hash',p->'prepared');
 ASSERT c->>'action'='committed','ordinary workout still uses the exact protected primitive';
 ASSERT (SELECT calories_target=2000 AND protein_target=140 FROM public.daily_snapshots WHERE user_id=f.owner_id),'exercise never increases food allowance';
 ASSERT NOT EXISTS(SELECT 1 FROM public.user_progress WHERE user_id=f.owner_id),'registration never gives block credits or XP';
 ASSERT (SELECT status FROM private.training_execution_completions WHERE user_id=f.owner_id)='reserved','ordinary workout never completes a training execution';
 ASSERT (SELECT state->>'phase' FROM private.training_execution_sessions WHERE user_id=f.owner_id)='in_progress';
 RAISE NOTICE 'R139_ORDINARY_WORKOUT_COMPATIBILITY_FOOD_TARGET_NO_XP_PASS';
END $test$;
ROLLBACK TO ordinary_workout;


SAVEPOINT auth_expires_inside_writer;
CREATE FUNCTION pg_temp.expire_completion_during_writer() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN IF NEW.kind='completed' THEN PERFORM pg_sleep(0.5);END IF;RETURN NEW;END $$;
CREATE TRIGGER r139_auth_expiry_during_completion BEFORE INSERT ON private.training_execution_completion_events FOR EACH ROW EXECUTE FUNCTION pg_temp.expire_completion_during_writer();
DO $test$
DECLARE f record;x jsonb;denied boolean:=false;
BEGIN
 SELECT * INTO STRICT f FROM finish_fixture;x:=pg_temp.prepare_training_finish();
 UPDATE auth.sessions SET not_after=clock_timestamp()+interval '350 milliseconds' WHERE id=f.login_id;
 BEGIN PERFORM pg_temp.commit_training_finish(x);EXCEPTION WHEN insufficient_privilege THEN denied:=true;END;
 ASSERT denied,'natural original-login expiry during the actual writer must be observed';
 ASSERT NOT EXISTS(SELECT 1 FROM public.workout_logs WHERE user_id=f.owner_id),'post-writer Auth refusal rolls back all effects';
 ASSERT NOT EXISTS(SELECT 1 FROM private.conversation_workout_effects WHERE user_id=f.owner_id);
 ASSERT NOT EXISTS(SELECT 1 FROM public.daily_snapshots WHERE user_id=f.owner_id);
 ASSERT (SELECT status FROM private.training_execution_completions WHERE user_id=f.owner_id)='reserved';
 ASSERT (SELECT count(*) FROM private.training_execution_completion_events WHERE user_id=f.owner_id)=1;
 RAISE NOTICE 'R139_AUTH_EXPIRES_DURING_ACTUAL_WRITER_ATOMIC_ROLLBACK_PASS';
END $test$;
ROLLBACK TO auth_expires_inside_writer;

SAVEPOINT other_owner;
INSERT INTO auth.users(id,email) VALUES('139d0000-0000-4000-8000-000000000071','r139-other-completion@example.invalid');
INSERT INTO public.users(id,auth_user_id,name,timezone) VALUES('139d0000-0000-4000-8000-000000000072','139d0000-0000-4000-8000-000000000071','Synthetic R139 other owner','America/Sao_Paulo');
INSERT INTO auth.sessions(id,user_id,created_at) VALUES('139d0000-0000-4000-8000-000000000073','139d0000-0000-4000-8000-000000000071',clock_timestamp());
DO $test$
DECLARE f record;x jsonb;a jsonb;denied boolean:=false;
BEGIN
 SELECT * INTO STRICT f FROM finish_fixture;x:=pg_temp.prepare_training_finish();
 a:=public.read_training_execution_completion_authenticated('139d0000-0000-4000-8000-000000000072','139d0000-0000-4000-8000-000000000071','139d0000-0000-4000-8000-000000000073',f.completion_id);
 ASSERT a='{"action":"absent"}'::jsonb,'a valid different patient does not receive another execution';
 BEGIN PERFORM public.read_training_execution_completion_authenticated(f.owner_id,'139d0000-0000-4000-8000-000000000071','139d0000-0000-4000-8000-000000000073',f.completion_id);
 EXCEPTION WHEN insufficient_privilege THEN denied:=true;END;ASSERT denied,'owner header cannot transfer original Auth';
 ASSERT NOT EXISTS(SELECT 1 FROM private.workout_strength_authority_epochs WHERE user_id='139d0000-0000-4000-8000-000000000072'),'foreign reads mint no lifecycle';
 RAISE NOTICE 'R139_REAL_TWO_OWNER_ISOLATION_NO_READ_SIDE_EFFECT_PASS';
END $test$;
ROLLBACK TO other_owner;


SAVEPOINT no_performed_report;
DO $test$
DECLARE f record;b jsonb;s jsonb;p jsonb;c jsonb;
BEGIN
 SELECT * INTO STRICT f FROM finish_fixture;
 b:=public.begin_training_execution_completion_authenticated(f.owner_id,f.auth_id,f.login_id,jsonb_set(f.command,'{source,text}','"Vou fazer full body por 30 min amanhã."'));
 s:=public.capture_conversation_workout_source(f.owner_id,f.completion_id,b#>>'{completion,workout_hash}',f.epoch);
 p:=public.prepare_conversation_workout(f.owner_id,f.completion_id,b#>>'{completion,workout_hash}',s->>'source_hash',f.epoch,private.conversation_workout_report_v2(s->'context',s->>'source_hash'));
 ASSERT p#>>'{prepared,status}'='not_reported','accepted text never fabricates a performed activity';
 c:=public.commit_training_execution_completion_authenticated(f.owner_id,f.auth_id,f.login_id,f.completion_id,b#>>'{completion,input_hash}',s->>'source_hash',p->>'prepared_hash',p->'prepared');
 ASSERT c->>'action'='not_ready';
 ASSERT NOT EXISTS(SELECT 1 FROM public.workout_logs WHERE user_id=f.owner_id);
 ASSERT (SELECT state->>'phase' FROM private.training_execution_sessions WHERE user_id=f.owner_id)='in_progress';
 ASSERT (SELECT status FROM private.training_execution_completions WHERE user_id=f.owner_id)='reserved';
 RAISE NOTICE 'R139_ACCEPTED_FUTURE_TEXT_NO_PERFORMED_OR_REWARD_PASS';
END $test$;
ROLLBACK TO no_performed_report;

ROLLBACK;
