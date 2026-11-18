-- Run against an owned migrated QA copy; every fixture is rolled back.
BEGIN;
SET LOCAL request.jwt.claim.role='service_role';
DO $$DECLARE receipt jsonb;job uuid;token text:=repeat('a',64);lease uuid;BEGIN
 IF public.claim_conversation_media_maintenance(gen_random_uuid(),repeat('0',64)) IS NOT NULL THEN
  RAISE EXCEPTION 'unknown dispatch authorized';END IF;
 IF EXISTS(SELECT 1 FROM private.conversation_media_maintenance_config WHERE enabled) THEN
  RAISE EXCEPTION 'bridge must start OFF';END IF;
 IF has_function_privilege('anon','public.claim_conversation_media_maintenance(uuid,text)','EXECUTE')
  OR has_function_privilege('authenticated','public.claim_conversation_media_maintenance(uuid,text)','EXECUTE') THEN
  RAISE EXCEPTION 'client may claim admin cleanup';END IF;
 UPDATE private.conversation_media_maintenance_config SET enabled=true;
 job:=gen_random_uuid();
 UPDATE private.conversation_media_maintenance_lanes SET dispatch_id=job,state='queued',
  token_sha256=encode(extensions.digest(token,'sha256'),'hex'),queued_at=clock_timestamp(),
  lease_until=NULL,lease_id=NULL WHERE lane='private';
 IF public.claim_conversation_media_maintenance(job,repeat('0',64)) IS NOT NULL THEN
  RAISE EXCEPTION 'forged capability authorized';END IF;
 receipt:=public.claim_conversation_media_maintenance(job,encode(extensions.digest(token,'sha256'),'hex'));
 IF receipt->>'schema'<>'conversation.media-maintenance-lease.v1' OR receipt->>'lane'<>'private'
  OR (receipt->>'dispatch_id')::uuid<>job OR (receipt->>'expires_at')::timestamptz<=clock_timestamp()
  OR (receipt->>'expires_at')::timestamptz>clock_timestamp()+interval '65 seconds' THEN
  RAISE EXCEPTION 'invalid bound receipt';END IF;
 lease:=(receipt->>'lease_id')::uuid;
 IF public.claim_conversation_media_maintenance(job,encode(extensions.digest(token,'sha256'),'hex')) IS NOT NULL THEN
  RAISE EXCEPTION 'replay authorized';END IF;
 IF public.complete_conversation_media_maintenance(job,gen_random_uuid(),'completed') THEN
  RAISE EXCEPTION 'forged completion';END IF;
 IF NOT public.complete_conversation_media_maintenance(job,lease,'completed')
  OR NOT public.complete_conversation_media_maintenance(job,lease,'completed') THEN
  RAISE EXCEPTION 'completion must be repeatable';END IF;
 IF public.complete_conversation_media_maintenance(job,lease,'retry') THEN
  RAISE EXCEPTION 'completed job downgraded';END IF;
 -- A displaced, expired, or disabled receipt cannot start Storage work.
 UPDATE private.conversation_media_maintenance_lanes SET state='queued',queued_at=clock_timestamp()-interval '3 minutes',lease_id=NULL,lease_until=NULL WHERE lane='private';
 IF public.claim_conversation_media_maintenance(job,encode(extensions.digest(token,'sha256'),'hex')) IS NOT NULL THEN
  RAISE EXCEPTION 'expired receipt authorized';END IF;
 UPDATE private.conversation_media_maintenance_lanes SET queued_at=clock_timestamp() WHERE lane='private';
 UPDATE private.conversation_media_maintenance_config SET enabled=false;
 IF public.claim_conversation_media_maintenance(job,encode(extensions.digest(token,'sha256'),'hex')) IS NOT NULL THEN
  RAISE EXCEPTION 'disabled receipt authorized';END IF;
 -- Existing protected ordinary sources do not become eligible by this dispatcher.
 IF private.conversation_media_maintenance_due('ordinary') THEN
  RAISE EXCEPTION 'old ordinary assets became due';END IF;
END$$;
-- Independent scenario: the prior case deliberately left a queued capability.
UPDATE private.conversation_media_maintenance_lanes SET state='idle',dispatch_id=NULL,
 token_sha256=NULL,queued_at=NULL,lease_id=NULL,lease_until=NULL,next_attempt_at='-infinity';
DO $$DECLARE u uuid:=gen_random_uuid();a uuid:=gen_random_uuid();sent integer;BEGIN
 IF public.dispatch_due_conversation_media_maintenance()<>0 THEN RAISE EXCEPTION 'OFF dispatch sent work';END IF;
 UPDATE private.conversation_media_maintenance_config SET enabled=true;
 IF private.conversation_media_maintenance_due('private') OR private.conversation_media_maintenance_due('accounts')
  OR private.conversation_media_maintenance_due('recurring') THEN RAISE EXCEPTION 'empty fixture unexpectedly due';END IF;
 IF public.dispatch_due_conversation_media_maintenance()<>0 THEN RAISE EXCEPTION 'idle polling sent HTTP';END IF;
 INSERT INTO public.users(id,email,status,timezone,country,country_confirmed)
 VALUES(u,'maintenance-'||u||'@example.invalid','active','UTC','BR',true);
 PERFORM public.create_conversation_media_asset_v2(u,a,'audio_note','audio/mp4',8,NULL,repeat('b',64));
 IF private.conversation_media_maintenance_due('private') THEN RAISE EXCEPTION 'fresh private source due';END IF;
 PERFORM public.close_conversation_media_v2(u,a);
 IF NOT private.conversation_media_maintenance_due('private') THEN RAISE EXCEPTION 'closed private source ignored';END IF;
 sent:=public.dispatch_due_conversation_media_maintenance();
 IF sent<>1 THEN RAISE EXCEPTION 'exactly one private dispatch expected, got %',sent;END IF;
 IF public.dispatch_due_conversation_media_maintenance()<>0 THEN RAISE EXCEPTION 'overlapping dispatch duplicated';END IF;
 IF (SELECT count(*) FROM private.conversation_media_maintenance_lanes WHERE state='queued')<>1 THEN
  RAISE EXCEPTION 'unrelated lanes scheduled';END IF;
 -- The deletion grace remains one hour; no private source is enough to waive it.
 INSERT INTO public.users(id,email,status,timezone,country,country_confirmed,updated_at)
 VALUES(gen_random_uuid(),'maintenance-deleted-'||u||'@example.invalid','deleted','UTC','BR',true,clock_timestamp()-interval '2 hours');
 IF NOT private.conversation_media_maintenance_due('accounts') THEN RAISE EXCEPTION 'deleted-account grace work ignored';END IF;
END$$;
ROLLBACK;
