-- Owned synthetic completion fixtures only; caller supplies BEGIN/ROLLBACK.

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
