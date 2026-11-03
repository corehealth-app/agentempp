-- Synthetic local SQL qualification only; fixture effects always roll back.
BEGIN;
CREATE TEMP TABLE v2_workout_assertions(label text PRIMARY KEY) ON COMMIT DROP;
CREATE FUNCTION pg_temp.v2wok(v boolean,label text) RETURNS void LANGUAGE plpgsql AS $$
BEGIN IF v IS DISTINCT FROM true THEN RAISE EXCEPTION 'V2_WORKOUT_ASSERT: %',label; END IF; INSERT INTO v2_workout_assertions VALUES(label); END $$;
DO $test$
DECLARE u uuid:='b2b10000-0000-4000-8000-000000000001';k text:='wui1:b2b10000-0000-4000-8000-000000000002';
 input jsonb:='{"kind":"workout","workout_type":"qa-feedback-v2-activity","duration_min":30,"intensity":"moderada"}';
 ts text:=to_char(date_trunc('second',clock_timestamp()) AT TIME ZONE 'UTC','YYYY-MM-DD"T"HH24:MI:SS"Z"');
 proposal jsonb;admission jsonb;materialized jsonb;confirmed jsonb;context jsonb;before_state jsonb;after_state jsonb;
 observation jsonb;decision jsonb;args jsonb;pid uuid;marker uuid;epoch uuid;workout_id uuid;
BEGIN
 PERFORM set_config('request.jwt.claims','{"role":"service_role"}',true);
 INSERT INTO public.users(id,email,status,timezone,country,country_confirmed) VALUES(u,'v2-workout@example.invalid','active','UTC','BR',true);
 INSERT INTO public.user_profiles(user_id,weight_kg) VALUES(u,70);
 proposal:=jsonb_build_object('kind','workout','workoutType',input->'workout_type','durationMin',30,'kcalEst',999,'intensity','moderada',
  'sourceContentType','mobile','source_provider_message_id',k,'source_timestamp',ts,'source_timezone','UTC','source_local_date',left(ts,10),
  'raw_args',input-'kind','express_eligible',false);
 admission:=public.admit_mobile_workout_registration(u,k,input);
 PERFORM pg_temp.v2wok(admission->>'status'='admitted','real workout admission');
 materialized:=public.materialize_mobile_workout_registration(u,(admission#>>'{admission,admissionID}')::uuid,input,proposal,clock_timestamp()+interval '6 hours');
 PERFORM pg_temp.v2wok(materialized->>'status'='materialized','real workout materialization');pid:=(materialized->>'pendingID')::uuid;
 observation:=public.get_workout_strength_catalogue_context();
 decision:=jsonb_build_object('status','unrecognized','observationKey',observation->'observationKey','matcherVersion',observation->'matcherVersion',
  'originalOperationType',input->'workout_type','reason','no_active_match');
 args:=jsonb_build_object('p_user_id',u,'p_date',left(ts,10),'p_workout_type',input->'workout_type','p_duration_min',30,'p_estimated_kcal',123,
  'p_intensity','moderada','p_notes','synthetic feedback v2 QA','p_performed_at',ts,'p_provider_message_id',k,
  'p_calories_target',2200,'p_protein_target',150,'p_replace_recent',false,'p_replace_since',NULL);
 confirmed:=public.confirm_mobile_workout_registration(u,pid,0,args,observation,decision);
 PERFORM pg_temp.v2wok(confirmed->>'status'='confirmed','real protected confirmation once');
 SELECT jsonb_build_object('logs',(SELECT jsonb_agg(to_jsonb(w) ORDER BY id) FROM public.workout_logs w WHERE user_id=u),
  'snapshot',(SELECT jsonb_agg(to_jsonb(s) ORDER BY id) FROM public.daily_snapshots s WHERE user_id=u),
  'operations',(SELECT jsonb_agg(to_jsonb(o) ORDER BY operation_key) FROM private.workout_strength_operations o WHERE user_id=u),
  'phrase',(SELECT jsonb_build_array(flow_shared_phrase_revision,flow_shared_phrase_cursor) FROM public.users WHERE id=u)) INTO before_state;
 context:=public.capture_mobile_registration_feedback_v2(u,pid);
 PERFORM pg_temp.v2wok(context->>'action'='available','protected ui-v1 capture available');
 PERFORM pg_temp.v2wok(context#>>'{context,workout_proof,kind}'='ui-v1','protected proof carried privately');
 PERFORM pg_temp.v2wok(context#>>'{context,confirmed,workout_protocol}'='ui-v1','protected marker carried to private adapter');
 PERFORM pg_temp.v2wok(context#>'{context,logs,0,estimated_kcal}'='123'::jsonb AND context#>'{context,confirmed,proposal,kcalEst}'='999'::jsonb,'persisted energy differs from preview');
 workout_id:=(context#>>'{context,logs,0,id}')::uuid;
 PERFORM pg_temp.v2wok(context#>>'{context,workout_proof,workout_id}'=workout_id::text,'resolver linked exact live row');
 SELECT jsonb_build_object('logs',(SELECT jsonb_agg(to_jsonb(w) ORDER BY id) FROM public.workout_logs w WHERE user_id=u),
  'snapshot',(SELECT jsonb_agg(to_jsonb(s) ORDER BY id) FROM public.daily_snapshots s WHERE user_id=u),
  'operations',(SELECT jsonb_agg(to_jsonb(o) ORDER BY operation_key) FROM private.workout_strength_operations o WHERE user_id=u),
  'phrase',(SELECT jsonb_build_array(flow_shared_phrase_revision,flow_shared_phrase_cursor) FROM public.users WHERE id=u)) INTO after_state;
 PERFORM pg_temp.v2wok(before_state=after_state,'capture does not write records rewards classifications or v1 cursor');
 -- A corrupt marker must never downgrade a protected pending to direct-key lookup.
 SELECT workout_ui_admission_id INTO marker FROM public.pending_registrations WHERE id=pid;
 UPDATE public.pending_registrations SET workout_ui_admission_id=NULL WHERE id=pid;
 PERFORM pg_temp.v2wok(public.capture_mobile_registration_feedback_v2(u,pid)='{"action":"event_conflict"}'::jsonb,'historical membership blocks corrupt marker fallback');
 UPDATE public.pending_registrations SET workout_ui_admission_id=marker WHERE id=pid;
 SELECT e.epoch INTO epoch FROM private.workout_strength_authority_epochs e WHERE e.user_id=u;
 -- Source context reflects the epoch proof and keeps it backend-only.
 PERFORM pg_temp.v2wok(context#>>'{context,workout_proof,epoch}'=epoch::text,'current epoch explicitly bound');
END $test$;
SELECT count(*) AS assertions FROM v2_workout_assertions;
ROLLBACK;
