-- Owned migrated copy only; synthetic fixtures, Vault secret, cron and HTTP
-- queue entries are rolled back. Never runs on shared staging/production.
BEGIN;
SET LOCAL request.jwt.claim.role='service_role';
CREATE TEMP TABLE processing_transport_checks(label text);
CREATE FUNCTION pg_temp.processing_transport_ok(ok boolean,label text) RETURNS void LANGUAGE plpgsql AS $$BEGIN
 IF ok IS DISTINCT FROM true THEN RAISE EXCEPTION 'processing transport: %',label;END IF;
 INSERT INTO processing_transport_checks VALUES(label);
END$$;
DO $cases$
DECLARE u uuid:=gen_random_uuid();v uuid:=gen_random_uuid();a uuid:=gen_random_uuid();b uuid:=gen_random_uuid();
 receipt jsonb;claim jsonb;again jsonb;processing_claim jsonb;ticket uuid;asset uuid;job uuid;dispatch uuid;lease uuid;denied boolean;
 token text:=repeat('b',64);target text:='https://agentempp-media-worker-staging-qa180-gestao-9664s-projects.vercel.app';
BEGIN
 PERFORM pg_temp.processing_transport_ok(public.dispatch_due_conversation_media_processing_v2()=0,'defaultOFF no dispatch');
 PERFORM pg_temp.processing_transport_ok(NOT has_function_privilege('anon','public.claim_conversation_media_processing_job_v2(uuid,text,text)','EXECUTE') AND NOT has_function_privilege('authenticated','public.enqueue_conversation_media_processing_job_v2(uuid,uuid,text)','EXECUTE'),'client ACL denied');
 PERFORM pg_temp.processing_transport_ok(NOT has_table_privilege('service_role','private.conversation_media_processing_jobs_v2','SELECT'),'no direct job table access');
 denied:=false;BEGIN PERFORM public.prepare_conversation_media_processing_transport_v2('xitugspwfxkcluxvrdeg','https://example.com',repeat('c',40),repeat('a',64));EXCEPTION WHEN invalid_parameter_value THEN denied:=true;END;
 PERFORM pg_temp.processing_transport_ok(denied,'arbitrary callback rejected');
 PERFORM public.prepare_conversation_media_processing_transport_v2('xitugspwfxkcluxvrdeg',target,repeat('c',40),repeat('a',64));
 PERFORM pg_temp.processing_transport_ok(NOT public.register_conversation_media_processing_transport_v2(target,repeat('c',40),repeat('d',64),'synthetic-bypass'),'wrong setup capability');
 PERFORM pg_temp.processing_transport_ok(NOT public.register_conversation_media_processing_transport_v2(target,repeat('d',40),repeat('a',64),'synthetic-bypass'),'wrong source setup');
 UPDATE private.conversation_media_processing_transport_v2 SET setup_expires_at=clock_timestamp()-interval '1second';
 PERFORM pg_temp.processing_transport_ok(NOT public.register_conversation_media_processing_transport_v2(target,repeat('c',40),repeat('a',64),'synthetic-bypass'),'expired setup');
 UPDATE private.conversation_media_processing_transport_v2 SET setup_expires_at=clock_timestamp()+interval '5minutes';
 PERFORM pg_temp.processing_transport_ok(public.register_conversation_media_processing_transport_v2(target,repeat('c',40),repeat('a',64),'synthetic-bypass'),'exact setup consumes capability');
 PERFORM pg_temp.processing_transport_ok(NOT public.register_conversation_media_processing_transport_v2(target,repeat('c',40),repeat('a',64),'synthetic-bypass'),'setup cannot replay');
 PERFORM public.configure_conversation_media_processing_transport_v2(true,'xitugspwfxkcluxvrdeg');
 PERFORM pg_temp.processing_transport_ok((SELECT count(*)=1 FROM cron.job WHERE jobname='performe-conversation-media-processing-v2' AND active),'one owned cron registered');
 INSERT INTO public.users(id,email,status,timezone,country,country_confirmed) VALUES(u,'transport-'||u||'@example.invalid','active','UTC','BR',true),(v,'transport-'||v||'@example.invalid','active','UTC','BR',true);
 PERFORM public.create_conversation_media_asset_v2(u,a,'audio_note','audio/mp4',8,NULL,repeat('e',64));
 PERFORM public.create_conversation_media_asset_v2(u,b,'audio_note','audio/mp4',8,NULL,repeat('f',64));
 PERFORM pg_temp.processing_transport_ok(public.enqueue_conversation_media_processing_job_v2(v,a,repeat('1',64)) IS NULL,'foreign source denied');
 PERFORM pg_temp.processing_transport_ok(public.enqueue_conversation_media_processing_job_v2(u,a,repeat('1',64)) IS NULL,'unuploaded source denied');
 FOREACH asset IN ARRAY ARRAY[a,b] LOOP
  ticket:=gen_random_uuid();PERFORM public.prepare_conversation_media_upload_v2(u,asset,ticket);
  PERFORM public.register_conversation_media_upload_v2(u,asset,ticket,clock_timestamp()+interval '2hours');
  PERFORM public.complete_conversation_media_upload_v2(u,asset,8,'audio/mp4','synthetic-etag');
 END LOOP;
 receipt:=public.enqueue_conversation_media_processing_job_v2(u,a,repeat('1',64));job:=(receipt->>'job_id')::uuid;
 PERFORM pg_temp.processing_transport_ok(job IS NOT NULL AND receipt->>'state'='waiting','durable acceptance before wakeup');
 again:=public.enqueue_conversation_media_processing_job_v2(u,a,repeat('1',64));
 PERFORM pg_temp.processing_transport_ok(again=receipt,'technical repeat stable receipt');
 PERFORM pg_temp.processing_transport_ok(public.dispatch_due_conversation_media_processing_v2()=1,'separate transaction wakeup dispatches accepted job');
 PERFORM pg_temp.processing_transport_ok((public.enqueue_conversation_media_processing_job_v2(u,a,repeat('2',64))->>'job_id')::uuid=job,'new key during same active source reuses job');
 SELECT dispatch_id INTO dispatch FROM private.conversation_media_processing_jobs_v2 WHERE id=job;
 -- Replace only the synthetic dispatch hash so the test never extracts a raw
 -- server token from the outbound queue or touches any provider credential.
 UPDATE private.conversation_media_processing_jobs_v2 SET token_sha256=encode(extensions.digest(token,'sha256'),'hex') WHERE id=job;
 PERFORM pg_temp.processing_transport_ok(public.claim_conversation_media_processing_job_v2(dispatch,repeat('0',64),repeat('c',40)) IS NULL,'forged job capability');
 PERFORM pg_temp.processing_transport_ok(public.claim_conversation_media_processing_job_v2(dispatch,encode(extensions.digest(token,'sha256'),'hex'),repeat('d',40)) IS NULL,'wrong runtime source');
 claim:=public.claim_conversation_media_processing_job_v2(dispatch,encode(extensions.digest(token,'sha256'),'hex'),repeat('c',40));lease:=(claim->>'lease_id')::uuid;
 PERFORM pg_temp.processing_transport_ok(claim->>'user_id'=u::text AND claim->>'asset_id'=a::text AND claim->>'request_id'=repeat('1',64) AND lease IS NOT NULL,'job resolves trusted scope');
 PERFORM pg_temp.processing_transport_ok(public.claim_conversation_media_processing_job_v2(dispatch,encode(extensions.digest(token,'sha256'),'hex'),repeat('c',40)) IS NULL,'claim oneuse');
 PERFORM pg_temp.processing_transport_ok(public.validate_conversation_media_processing_job_v2(dispatch,lease,repeat('c',40)),'live lease validated');
 PERFORM pg_temp.processing_transport_ok(NOT public.complete_conversation_media_processing_job_v2(dispatch,gen_random_uuid(),'completed',NULL),'forged completion denied');
 PERFORM pg_temp.processing_transport_ok(public.complete_conversation_media_processing_job_v2(dispatch,lease,'defer',clock_timestamp()+interval '60seconds'),'featureOFF safely deferred');
 PERFORM pg_temp.processing_transport_ok(NOT public.validate_conversation_media_processing_job_v2(dispatch,lease,repeat('c',40)),'deferred lease cannot write');
 PERFORM pg_temp.processing_transport_ok(public.dispatch_due_conversation_media_processing_v2()=0,'future work no HTTP polling');
 UPDATE private.conversation_media_processing_jobs_v2 SET next_attempt_at=clock_timestamp()-interval '1second' WHERE id=job;
 PERFORM pg_temp.processing_transport_ok(public.dispatch_due_conversation_media_processing_v2()=1,'due work resumed');
 SELECT dispatch_id INTO dispatch FROM private.conversation_media_processing_jobs_v2 WHERE id=job;
 UPDATE private.conversation_media_processing_jobs_v2 SET token_sha256=encode(extensions.digest(token,'sha256'),'hex') WHERE id=job;
 claim:=public.claim_conversation_media_processing_job_v2(dispatch,encode(extensions.digest(token,'sha256'),'hex'),repeat('c',40));lease:=(claim->>'lease_id')::uuid;
 PERFORM pg_temp.processing_transport_ok(NOT public.complete_conversation_media_processing_job_v2(dispatch,lease,'completed',NULL),'unprocessed source cannot be reported done');
 processing_claim:=public.claim_conversation_media_processing_v2(u,a,repeat('1',64));
 PERFORM pg_temp.processing_transport_ok(public.fail_conversation_media_processing_v2(u,a,repeat('1',64),(processing_claim#>>'{claim,token}')::uuid,'provider_error'),'actual terminal source observation persisted');
 PERFORM pg_temp.processing_transport_ok(public.complete_conversation_media_processing_job_v2(dispatch,lease,'completed',NULL) AND public.complete_conversation_media_processing_job_v2(dispatch,lease,'completed',NULL),'lost completion ACK replay stable');
 PERFORM pg_temp.processing_transport_ok(NOT public.complete_conversation_media_processing_job_v2(dispatch,lease,'retry',NULL),'cannot downgrade completed');
 -- A lost transport ACK must not reopen a persisted core provider failure.
 UPDATE private.conversation_media_processing_jobs_v2 SET state='queued',dispatch_id=gen_random_uuid(),queued_at=clock_timestamp(),token_sha256=repeat('b',64),lease_id=NULL,lease_until=NULL WHERE id=(SELECT id FROM private.conversation_media_processing_jobs_v2 WHERE asset_id=a AND request_id=repeat('1',64));
 SELECT dispatch_id INTO dispatch FROM private.conversation_media_processing_jobs_v2 WHERE asset_id=a AND request_id=repeat('1',64);
 PERFORM pg_temp.processing_transport_ok(public.claim_conversation_media_processing_job_v2(dispatch,repeat('b',64),repeat('c',40)) IS NULL,'lost ACK cannot reprocess a terminal source failure');
 PERFORM pg_temp.processing_transport_ok((SELECT state='completed' FROM private.conversation_media_processing_jobs_v2 WHERE asset_id=a AND request_id=repeat('1',64)),'terminal failure transport reconciled');
 PERFORM pg_temp.processing_transport_ok((SELECT failure_code='provider_error' FROM private.conversation_media_assets_v2 WHERE id=a),'original provider failure preserved');

 receipt:=public.enqueue_conversation_media_processing_job_v2(u,b,repeat('3',64));job:=(receipt->>'job_id')::uuid;
 PERFORM public.dispatch_due_conversation_media_processing_v2();
 UPDATE private.conversation_media_processing_jobs_v2 SET queued_at=clock_timestamp()-interval '3minutes' WHERE id=job;
 PERFORM public.dispatch_due_conversation_media_processing_v2();
 PERFORM pg_temp.processing_transport_ok((SELECT failure_count=1 AND state='waiting' FROM private.conversation_media_processing_jobs_v2 WHERE id=job),'lost dispatch bounded retry');
 PERFORM public.close_conversation_media_v2(u,b);
 UPDATE private.conversation_media_processing_jobs_v2 SET next_attempt_at=clock_timestamp()-interval '1second' WHERE id=job;
 PERFORM public.dispatch_due_conversation_media_processing_v2();
 PERFORM pg_temp.processing_transport_ok((SELECT state='cancelled' FROM private.conversation_media_processing_jobs_v2 WHERE id=job),'closed source never revived');
 PERFORM public.configure_conversation_media_processing_transport_v2(false,'xitugspwfxkcluxvrdeg');
 PERFORM pg_temp.processing_transport_ok(NOT EXISTS(SELECT 1 FROM cron.job WHERE jobname='performe-conversation-media-processing-v2' AND active),'rollback only own cron');
 PERFORM pg_temp.processing_transport_ok(public.dispatch_due_conversation_media_processing_v2()=0,'disabled no dispatch');
END $cases$;

DO $retry_cases$
DECLARE u uuid:=gen_random_uuid();assets uuid[]:=ARRAY[gen_random_uuid(),gen_random_uuid(),gen_random_uuid(),gen_random_uuid()];
 a uuid;t uuid;j uuid;d uuid;l uuid;q jsonb;denied boolean;before_count integer;
 target text:='https://agentempp-media-worker-staging-qa180-gestao-9664s-projects.vercel.app';
BEGIN
 PERFORM public.prepare_conversation_media_processing_transport_v2('xitugspwfxkcluxvrdeg',target,repeat('c',40),repeat('a',64));
 PERFORM public.register_conversation_media_processing_transport_v2(target,repeat('c',40),repeat('a',64),'synthetic-bypass');
 PERFORM public.configure_conversation_media_processing_transport_v2(true,'xitugspwfxkcluxvrdeg');
 INSERT INTO public.users(id,email,status,timezone,country,country_confirmed) VALUES(u,'retry-'||u||'@example.invalid','active','UTC','BR',true);
 FOREACH a IN ARRAY assets LOOP
  PERFORM public.create_conversation_media_asset_v2(u,a,'audio_note','audio/mp4',8,NULL,encode(extensions.digest(a::text,'sha256'),'hex'));
  t:=gen_random_uuid();PERFORM public.prepare_conversation_media_upload_v2(u,a,t);
  PERFORM public.register_conversation_media_upload_v2(u,a,t,clock_timestamp()+interval '2hours');
  PERFORM public.complete_conversation_media_upload_v2(u,a,8,'audio/mp4','synthetic');
  PERFORM public.enqueue_conversation_media_processing_job_v2(u,a,repeat('1',64));
 END LOOP;
 PERFORM pg_temp.processing_transport_ok(public.dispatch_due_conversation_media_processing_v2()=2,'global two in-flight cap');
 PERFORM pg_temp.processing_transport_ok(public.dispatch_due_conversation_media_processing_v2()=0,'parallel wakeup cannot exceed cap');
 SELECT id,dispatch_id INTO j,d FROM private.conversation_media_processing_jobs_v2 WHERE user_id=u AND state='queued' ORDER BY id LIMIT 1;
 UPDATE private.conversation_media_processing_jobs_v2 SET queued_at=clock_timestamp()-interval '3minutes',token_sha256=repeat('b',64) WHERE id=j;
 PERFORM pg_temp.processing_transport_ok(public.claim_conversation_media_processing_job_v2(d,repeat('b',64),repeat('c',40)) IS NULL,'expired dispatch refused');
 PERFORM public.dispatch_due_conversation_media_processing_v2();
 PERFORM pg_temp.processing_transport_ok((SELECT failure_count=1 FROM private.conversation_media_processing_jobs_v2 WHERE id=j),'expired dispatch counts one bounded failure');
 PERFORM pg_temp.processing_transport_ok((SELECT count(*)<=2 FROM private.conversation_media_processing_jobs_v2 WHERE user_id=u AND state IN('queued','running')),'retry preserves global cap');
 UPDATE private.conversation_media_processing_jobs_v2 SET state='waiting',failure_count=4,next_attempt_at=clock_timestamp()-interval '1second' WHERE id=j;
 PERFORM public.dispatch_due_conversation_media_processing_v2();
 PERFORM pg_temp.processing_transport_ok((SELECT state='failed' FROM private.conversation_media_processing_jobs_v2 WHERE id=j),'four failures stop dispatch');
 PERFORM pg_temp.processing_transport_ok((SELECT a.status='failed' AND a.failure_stage='processing' AND a.failure_code='worker_transport_unavailable' FROM private.conversation_media_assets_v2 a JOIN private.conversation_media_processing_jobs_v2 x ON x.asset_id=a.id WHERE x.id=j),'bounded failure visible through original media API');
 PERFORM pg_temp.processing_transport_ok(public.claim_conversation_media_processing_job_v2(d,repeat('b',64),repeat('c',40)) IS NULL,'exhausted capability never revived');
 SELECT id,dispatch_id INTO j,d FROM private.conversation_media_processing_jobs_v2 WHERE user_id=u AND state='queued' ORDER BY id LIMIT 1;
 UPDATE private.conversation_media_processing_jobs_v2 SET token_sha256=repeat('b',64) WHERE id=j;
 q:=public.claim_conversation_media_processing_job_v2(d,repeat('b',64),repeat('c',40));l:=(q->>'lease_id')::uuid;
 PERFORM pg_temp.processing_transport_ok(l IS NOT NULL,'second source independently claimed');
 PERFORM public.configure_conversation_media_processing_transport_v2(false,'xitugspwfxkcluxvrdeg');
 PERFORM pg_temp.processing_transport_ok(NOT public.validate_conversation_media_processing_job_v2(d,l,repeat('c',40)),'OFF revokes live IO fence');
 PERFORM pg_temp.processing_transport_ok(NOT public.complete_conversation_media_processing_job_v2(d,l,'retry',NULL),'OFF refuses stale completion');
 denied:=false;BEGIN PERFORM public.prepare_conversation_media_processing_transport_v2('xitugspwfxkcluxvrdeg',target,repeat('d',40),repeat('a',64));EXCEPTION WHEN serialization_failure THEN denied:=true;END;
 PERFORM pg_temp.processing_transport_ok(denied,'handover waits for live lease instead of duplicating IO');
 UPDATE private.conversation_media_processing_jobs_v2 SET lease_until=clock_timestamp()-interval '1second' WHERE id=j;
 PERFORM public.prepare_conversation_media_processing_transport_v2('xitugspwfxkcluxvrdeg',target,repeat('d',40),repeat('a',64));
 PERFORM public.register_conversation_media_processing_transport_v2(target,repeat('d',40),repeat('a',64),'synthetic-bypass');
 PERFORM public.configure_conversation_media_processing_transport_v2(true,'xitugspwfxkcluxvrdeg');
 PERFORM pg_temp.processing_transport_ok(NOT public.validate_conversation_media_processing_job_v2(d,l,repeat('c',40)),'old deployment lease invalid after handover');
 PERFORM pg_temp.processing_transport_ok(public.claim_conversation_media_processing_job_v2(d,repeat('b',64),repeat('c',40)) IS NULL,'old deployment token cannot claim new job');
 PERFORM set_config('request.jwt.claims','{"role":"authenticated"}',true);
 denied:=false;BEGIN PERFORM public.dispatch_due_conversation_media_processing_v2();EXCEPTION WHEN insufficient_privilege THEN denied:=true;END;
 PERFORM set_config('request.jwt.claims','{"role":"service_role"}',true);
 PERFORM pg_temp.processing_transport_ok(denied,'untrusted request context cannot dispatch');
 PERFORM public.configure_conversation_media_processing_transport_v2(false,'xitugspwfxkcluxvrdeg');
END $retry_cases$;
SELECT jsonb_build_object('status','PASS','checks',(SELECT count(*) FROM processing_transport_checks));
ROLLBACK;
