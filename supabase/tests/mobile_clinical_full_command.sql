BEGIN;
DO $$ BEGIN
 IF to_regprocedure('public.get_mobile_clinical_full_command(uuid,uuid,uuid)') IS NULL
  OR to_regprocedure('public.prepare_mobile_clinical_full_command(uuid,text,uuid,uuid,text,jsonb,jsonb,jsonb,jsonb)') IS NULL
  OR to_regprocedure('public.get_mobile_clinical_full_command_receipt(uuid,uuid,uuid)') IS NULL
  OR to_regprocedure('public.confirm_mobile_clinical_full_command(uuid,uuid,uuid,jsonb,jsonb,jsonb,jsonb)') IS NULL THEN
  RAISE EXCEPTION 'clinical_full_command_authority_missing'; END IF;
END $$;
SELECT set_config('request.jwt.claim','{"role":"service_role"}',true);
\ir fixtures/mobile_clinical_full_command_fixture.sql
DO $$
DECLARE c jsonb;a uuid;cycle uuid;q jsonb;packet jsonb;prepared jsonb;confirmed jsonb;receipt jsonb;
 prepare_key uuid:=gen_random_uuid();key uuid:=gen_random_uuid();alias_key uuid:=gen_random_uuid();preview uuid;
 before_rows jsonb;caller text;statement text;refused boolean;other_key uuid;raw_cmd jsonb;raw_form jsonb;
BEGIN
 c:=m3b_cycle_test.clinical_photos(4300);a:=(c->>'user')::uuid;cycle:=(c->>'cycle')::uuid;
 INSERT INTO public.daily_snapshots(user_id,date,calories_target,protein_target,current_protocol)
 VALUES(a,(clock_timestamp() AT TIME ZONE 'America/Sao_Paulo')::date,1700,120,'recomposicao');
 q:=m3b_cycle_test.command_input(c,'{"action":"change","value":{"kind":"body_fat","percent":11}}');
 EXECUTE 'SET LOCAL ROLE service_role';
 packet:=public.prepare_mobile_clinical_full_command(a,'REGULAR',cycle,prepare_key,q#>>'{context,context_hash}',q->'command',q->'form',q->'intent',q->'proposal');
 EXECUTE 'RESET ROLE';
 prepared:=packet;preview:=(packet#>>'{preview,preview_id}')::uuid;
 PERFORM m3b_cycle_test.ok(packet->>'user_id'=a::text AND packet->>'operation_key'=prepare_key::text AND preview IS NOT NULL,'command prepare binds owner/key/preview');
 PERFORM m3b_cycle_test.ok(packet->'command'=q->'command' AND packet->'command_version'='1'::jsonb AND length(packet->>'command_hash')=64,'only normalized exact choice/form/measure/photo command retained');
 PERFORM m3b_cycle_test.ok(packet->'normalization_context'='{"sex":"masculino","heightCm":180}'::jsonb,'n21 normalization context bound to original locked profile');
 PERFORM m3b_cycle_test.ok((SELECT count(*)=1 FROM private.mobile_clinical_full_commands WHERE user_id=a),'preview and command committed together in statement');
 PERFORM m3b_cycle_test.ok(public.get_mobile_clinical_full_command(a,preview,NULL)=prepared AND public.get_mobile_clinical_full_command(a,NULL,prepare_key)=prepared,'pending and original prepare-key lookups return identical original ACK');
 PERFORM m3b_cycle_test.ok(public.get_mobile_clinical_full_command(gen_random_uuid(),preview,NULL) IS NULL,'command lookup cannot cross owner');
 PERFORM m3b_cycle_test.throws(format('SELECT public.get_mobile_clinical_full_command(%L,NULL,NULL)',a),'22023','unbounded command lookup refused');
 PERFORM m3b_cycle_test.throws(format('SELECT public.get_mobile_clinical_full_command(%L,%L,%L)',a,preview,prepare_key),'22023','ambiguous command lookup refused');
 PERFORM m3b_cycle_test.throws(format('UPDATE private.mobile_clinical_full_commands SET command=command WHERE user_id=%L',a),'55000','command immutable even for table owner');
 PERFORM m3b_cycle_test.throws(format('DELETE FROM private.mobile_clinical_full_commands WHERE user_id=%L',a),'55000','command cannot be deleted separately');
 packet:=public.prepare_mobile_clinical_full_command(a,'REGULAR',cycle,prepare_key,repeat('b',64),q->'command',q->'form',q->'intent',jsonb_set(q->'proposal','{targets,afterKcal}','1999'));
 PERFORM m3b_cycle_test.ok(packet=prepared,'same command preparation replays original ACK without recapture/recalculation');
 PERFORM m3b_cycle_test.throws(format('SELECT public.prepare_mobile_clinical_full_command(%L,%L,%L,%L,%L,%L,%L,%L,%L)',a,'REGULAR',cycle,prepare_key,q#>>'{context,context_hash}',jsonb_set(q->'command','{measureConfirmed}','true'),q->'form',q->'intent',q->'proposal'),'40001','changed measure confirmation conflicts despite identical effects');
 PERFORM m3b_cycle_test.throws(format('SELECT public.prepare_mobile_clinical_full_command(%L,%L,%L,%L,%L,%L,%L,%L,%L)',a,'EARLY_FULL',cycle,prepare_key,q#>>'{context,context_hash}',q->'command',q->'form',q->'intent',q->'proposal'),'40001','same prepare key cannot change review scope');
 other_key:=gen_random_uuid();raw_form:=jsonb_set(q->'form','{preference}','{"action":"change","value":{"kind":"body_fat","percent":8}}');raw_cmd:=jsonb_set(q->'command','{form}',raw_form);
 PERFORM m3b_cycle_test.throws(format('SELECT public.prepare_mobile_clinical_full_command(%L,%L,%L,%L,%L,%L,%L,%L,%L)',a,'REGULAR',cycle,other_key,q#>>'{context,context_hash}',raw_cmd,raw_form,q->'intent',q->'proposal'),'22023','refused n21 value never persisted in command');
 PERFORM m3b_cycle_test.ok(NOT EXISTS(SELECT 1 FROM private.mobile_clinical_previews WHERE user_id=a AND operation_key=other_key),'failure rolls back inserted preview too');
 PERFORM m3b_cycle_test.throws(format('SELECT public.prepare_mobile_clinical_full_command(%L,%L,%L,%L,%L,%L,%L,%L,%L)',a,'REGULAR',cycle,gen_random_uuid(),q#>>'{context,context_hash}',q->'command'||'{"effect":{}}',q->'form',q->'intent',q->'proposal'),'22023','unknown command effect keys refused');
 PERFORM m3b_cycle_test.throws(format('SELECT public.prepare_mobile_clinical_full_command(%L,%L,%L,%L,%L,%L,%L,%L,%L)',a,'REGULAR',cycle,gen_random_uuid(),q#>>'{context,context_hash}',jsonb_set(q->'command','{bodyFat,meanHundredths}','2401'),q->'form',q->'intent',q->'proposal'),'22023','command and prepared photo intent must agree');
 PERFORM m3b_cycle_test.ok(public.get_mobile_clinical_full_command_receipt(a,preview,key) IS NULL,'missing completed command receipt stays SQL NULL');
 EXECUTE 'SET LOCAL ROLE service_role';
 confirmed:=public.confirm_mobile_clinical_full_command(a,preview,key,q->'command',q->'form',q->'intent',q->'proposal');
 receipt:=public.get_mobile_clinical_full_command_receipt(a,preview,key);
 EXECUTE 'RESET ROLE';
 PERFORM m3b_cycle_test.ok(confirmed->'result'=receipt->'result' AND receipt->'prepared'=prepared,'completed original receipt carries exact prepared command authority');
 PERFORM m3b_cycle_test.ok(receipt->'operation_matched'='true'::jsonb AND receipt->'review_no'='"1"'::jsonb,'original receipt flag and counter text preserved');
 PERFORM public.reset_user_conversation_atomic(a,true);
 UPDATE public.user_profiles SET sex='feminino',height_cm=100 WHERE user_id=a;
 before_rows:=m3b_cycle_test.original_state(a);
 PERFORM m3b_cycle_test.ok(public.get_mobile_clinical_full_command(a,NULL,prepare_key)=prepared,'original normalization context and prepare ACK survive reset/profile change');
 packet:=public.prepare_mobile_clinical_full_command(a,'REGULAR',cycle,prepare_key,repeat('c',64),q->'command',q->'form',q->'intent',q->'proposal');
 PERFORM m3b_cycle_test.ok(packet=prepared AND before_rows=m3b_cycle_test.original_state(a),'same prepare request never rereads current n21 profile or recreates effects');
 EXECUTE 'SET LOCAL ROLE service_role';
 packet:=public.confirm_mobile_clinical_full_command(a,preview,key,q->'command',q->'form',q->'intent',q->'proposal');
 EXECUTE 'RESET ROLE';
 PERFORM m3b_cycle_test.ok(packet=confirmed AND before_rows=m3b_cycle_test.original_state(a),'original confirmation after reset returns original before current context');
 PERFORM m3b_cycle_test.throws(format('SELECT public.confirm_mobile_clinical_full_command(%L,%L,%L,%L,%L,%L,%L)',a,preview,key,jsonb_set(q->'command','{measureConfirmed}','true'),q->'form',q->'intent',q->'proposal'),'40001','changed command conflicts before original result even when package unchanged');
 receipt:=public.get_mobile_clinical_full_command_receipt(a,preview,alias_key);
 PERFORM m3b_cycle_test.ok(receipt->'operation_matched'='false'::jsonb AND NOT EXISTS(SELECT 1 FROM private.mobile_clinical_confirmation_keys WHERE user_id=a AND operation_key=alias_key),'unmatched alias lookup remains read-only');
 packet:=public.confirm_mobile_clinical_full_command(a,preview,alias_key,q->'command',q->'form',q->'intent',q->'proposal');
 PERFORM m3b_cycle_test.ok(packet->'result'=confirmed->'result' AND EXISTS(SELECT 1 FROM private.mobile_clinical_confirmation_keys WHERE user_id=a AND operation_key=alias_key),'alias registers exact original package before recapture');
 PERFORM m3b_cycle_test.throws(format('SELECT public.get_mobile_clinical_full_command_receipt(%L,%L,%L)',a,gen_random_uuid(),key),'40001','same confirmation key refuses a different preview');
 PERFORM m3b_cycle_test.ok(public.get_mobile_clinical_full_command_receipt(gen_random_uuid(),preview,key) IS NULL,'original command receipt cannot cross owner');
 FOREACH statement IN ARRAY ARRAY[
  format('SELECT public.get_mobile_clinical_full_command(%L,%L,NULL)',a,preview),
  format('SELECT public.prepare_mobile_clinical_full_command(%L,%L,%L,%L,%L,%L,%L,%L,%L)',a,'REGULAR',cycle,prepare_key,q#>>'{context,context_hash}',q->'command',q->'form',q->'intent',q->'proposal'),
  format('SELECT public.get_mobile_clinical_full_command_receipt(%L,%L,%L)',a,preview,key),
  format('SELECT public.confirm_mobile_clinical_full_command(%L,%L,%L,%L,%L,%L,%L)',a,preview,key,q->'command',q->'form',q->'intent',q->'proposal')
 ] LOOP
  FOREACH caller IN ARRAY ARRAY['anon','authenticated'] LOOP
   refused:=false;EXECUTE format('SET LOCAL ROLE %I',caller);
   BEGIN EXECUTE statement;EXCEPTION WHEN insufficient_privilege THEN refused:=true;END;
   EXECUTE 'RESET ROLE';PERFORM m3b_cycle_test.ok(refused,'actual client role denied command backend RPC');
  END LOOP;
  PERFORM set_config('request.jwt.claim','{"role":"authenticated"}',true);
  PERFORM m3b_cycle_test.throws(statement,'42501','every command definer requires trusted backend JWT');
  PERFORM set_config('request.jwt.claim','{"role":"service_role"}',true);
 END LOOP;
 PERFORM m3b_cycle_test.ok(NOT has_table_privilege('service_role','private.mobile_clinical_full_commands','SELECT'),'no direct command-table privilege');
 PERFORM m3b_cycle_test.ok((SELECT count(*)=4 AND bool_and(prosecdef AND 'search_path=pg_catalog'=ANY(proconfig) AND 'lock_timeout=2s'=ANY(proconfig)) FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='public' AND p.proname IN('get_mobile_clinical_full_command','prepare_mobile_clinical_full_command','get_mobile_clinical_full_command_receipt','confirm_mobile_clinical_full_command')),'four narrow backend RPCs without public clock overloads');
 -- Remove only this fixture's synthetic photo catalogue before its consent
 -- and cycle, then purge signup and user in dependency order.
 PERFORM m3b_cycle_test.remove_photos(ARRAY[a]);
 DELETE FROM private.mobile_reevaluation_cycles WHERE user_id=a;
 DELETE FROM private.mobile_signup_strength_completion_receipts WHERE user_id=a;
 DELETE FROM public.users WHERE id=a;
 PERFORM m3b_cycle_test.ok(NOT EXISTS(SELECT 1 FROM private.mobile_clinical_full_commands WHERE user_id=a),'real user purge cascades command evidence without weakening immutable trigger');
END $$;
ROLLBACK;
