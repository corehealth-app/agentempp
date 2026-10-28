BEGIN;
DO $$ BEGIN
 IF to_regclass('private.mobile_clinical_full_presentations') IS NULL THEN RAISE EXCEPTION 'presentation_authority_missing'; END IF;
END $$;
SELECT set_config('request.jwt.claim','{"role":"service_role"}',true);
\ir fixtures/mobile_clinical_full_command_fixture.sql
DO $$
DECLARE ctx jsonb;a uuid;cycle uuid;q jsonb;packet jsonb;again jsonb;legacy jsonb;
 key uuid:=gen_random_uuid();other_key uuid:=gen_random_uuid();preview uuid;refused boolean;
 policy jsonb:='{"version":1,"hide":{"objective":false,"calories":false,"protein":true},"professionalAssessmentRecommended":true,"pauseWeightLossGuidance":true}';
BEGIN
 ctx:=m3b_cycle_test.clinical_photos(4700);a:=(ctx->>'user')::uuid;cycle:=(ctx->>'cycle')::uuid;
 INSERT INTO public.daily_snapshots(user_id,date,calories_target,protein_target,current_protocol)
 VALUES(a,(clock_timestamp() AT TIME ZONE 'America/Sao_Paulo')::date,1700,120,'recomposicao');
 q:=m3b_cycle_test.command_input(ctx);
 refused:=false;
 BEGIN
  PERFORM public.prepare_mobile_clinical_full_presented_command(a,'REGULAR',cycle,key,q#>>'{context,context_hash}',q->'command',q->'form',q->'intent',q->'proposal','{"version":1}');
 EXCEPTION WHEN invalid_parameter_value THEN refused:=true; END;
 PERFORM m3b_cycle_test.ok(refused,'malformed policy rejected');
 PERFORM m3b_cycle_test.ok(NOT EXISTS(SELECT 1 FROM private.mobile_clinical_previews WHERE user_id=a),'late policy refusal rolls preview and command back');
 EXECUTE 'SET LOCAL ROLE service_role';
 packet:=public.prepare_mobile_clinical_full_presented_command(a,'REGULAR',cycle,key,q#>>'{context,context_hash}',q->'command',q->'form',q->'intent',q->'proposal',policy);
 EXECUTE 'RESET ROLE';
 preview:=(packet#>>'{preview,preview_id}')::uuid;
 PERFORM m3b_cycle_test.ok(packet->'presentation'=policy,'original presentation returned with prepared package');
 PERFORM m3b_cycle_test.ok((SELECT count(*)=1 FROM private.mobile_clinical_full_presentations WHERE user_id=a),'one immutable sidecar created in preparation transaction');
 PERFORM m3b_cycle_test.ok(public.get_mobile_clinical_full_command(a,preview,NULL)=packet,'original lookup retains original display evidence');
 PERFORM m3b_cycle_test.ok((SELECT x.binding_hash=private.mobile_clinical_full_presentation_hash(p,c,policy)
  FROM private.mobile_clinical_full_presentations x JOIN private.mobile_clinical_previews p USING(user_id,preview_id)
  JOIN private.mobile_clinical_full_commands c USING(user_id,preview_id) WHERE x.user_id=a),'policy hash binds owner preview context command and proposal');
 PERFORM public.declare_mobile_health_risk(a,gen_random_uuid(),ARRAY['reduced_intake']);
 again:=public.prepare_mobile_clinical_full_presented_command(a,'REGULAR',cycle,key,repeat('f',64),q->'command',q->'form',q->'intent',q->'proposal','{"version":1}');
 PERFORM m3b_cycle_test.ok(again=packet,'old ACK precedes current risk/capture/policy validation and is never rewritten');
 PERFORM m3b_cycle_test.ok(NOT has_table_privilege('service_role','private.mobile_clinical_full_presentations','SELECT')
  AND NOT has_table_privilege('authenticated','private.mobile_clinical_full_presentations','SELECT'),'no direct table reader granted');
 PERFORM m3b_cycle_test.ok(has_function_privilege('service_role','public.prepare_mobile_clinical_full_presented_command(uuid,text,uuid,uuid,text,jsonb,jsonb,jsonb,jsonb,jsonb)','EXECUTE')
  AND NOT has_function_privilege('authenticated','public.prepare_mobile_clinical_full_presented_command(uuid,text,uuid,uuid,text,jsonb,jsonb,jsonb,jsonb,jsonb)','EXECUTE'),'public transport remains trusted backend only');
 refused:=false;
 BEGIN UPDATE private.mobile_clinical_full_presentations SET presentation=jsonb_set(policy,'{hide,protein}','false') WHERE user_id=a;
 EXCEPTION WHEN object_not_in_prerequisite_state THEN refused:=true; END;
 PERFORM m3b_cycle_test.ok(refused AND (SELECT presentation=policy FROM private.mobile_clinical_full_presentations WHERE user_id=a),'original display cannot be updated');
 PERFORM m3b_cycle_test.remove_photos(ARRAY[a]);
 DELETE FROM private.mobile_reevaluation_cycles WHERE user_id=a;
 DELETE FROM private.mobile_signup_strength_completion_receipts WHERE user_id=a;
 DELETE FROM public.users WHERE id=a;
 PERFORM m3b_cycle_test.ok(NOT EXISTS(SELECT 1 FROM private.mobile_clinical_full_presentations WHERE user_id=a),'real owned synthetic user purge cascades presentation without weakening immutable trigger');

 ctx:=m3b_cycle_test.clinical_photos(4701);a:=(ctx->>'user')::uuid;cycle:=(ctx->>'cycle')::uuid;
 INSERT INTO public.daily_snapshots(user_id,date,calories_target,protein_target,current_protocol)
 VALUES(a,(clock_timestamp() AT TIME ZONE 'America/Sao_Paulo')::date,1700,120,'recomposicao');
 q:=m3b_cycle_test.command_input(ctx);
 legacy:=public.prepare_mobile_clinical_full_command(a,'REGULAR',cycle,other_key,q#>>'{context,context_hash}',q->'command',q->'form',q->'intent',q->'proposal');
 PERFORM m3b_cycle_test.ok(NOT(legacy?'presentation'),'old private transport remains valid without a fabricated display policy');
 again:=public.prepare_mobile_clinical_full_presented_command(a,'REGULAR',cycle,other_key,q#>>'{context,context_hash}',q->'command',q->'form',q->'intent',q->'proposal',policy);
 PERFORM m3b_cycle_test.ok(again=legacy AND NOT EXISTS(SELECT 1 FROM private.mobile_clinical_full_presentations WHERE user_id=a),'existing old preview never backfilled by new wrapper');
END $$;
ROLLBACK;
