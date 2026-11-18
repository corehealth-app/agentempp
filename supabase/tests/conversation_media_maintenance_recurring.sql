-- Same original recurring authority, including the 24h boundary and settlement.
BEGIN;
SET LOCAL request.jwt.claims='{"role":"service_role"}';
\ir fixtures/mobile_reevaluation_photo_cleanup_fixture.sql
DO $$DECLARE fresh jsonb;expired jsonb;r jsonb;h jsonb;page jsonb;ids uuid[];ack jsonb;BEGIN
 fresh:=m3b_cycle_test.cleanup_context(17701);
 PERFORM m3b_cycle_test.ok(NOT private.conversation_media_maintenance_due('recurring'),'fresh recurring consent causes no HTTP');
 expired:=m3b_cycle_test.cleanup_context(17702,86420);
 PERFORM m3b_cycle_test.ok(private.conversation_media_maintenance_due('recurring'),'24h idle scope schedules cleanup');
 r:=public.prepare_mobile_reevaluation_photo_disposition((expired->>'user')::uuid,(expired->>'cycle')::uuid,(expired->>'acceptance')::uuid);
 h:=r->'disposition';
 PERFORM m3b_cycle_test.ok(r->>'kind'='ready' AND h->>'reason'='expired','original authority adjudicates expiration');
 page:=public.get_mobile_reevaluation_photo_disposition_page((expired->>'user')::uuid,(h->>'id')::uuid,(h->>'sweep_no')::bigint,(h->>'capability_revision')::bigint,NULL);
 SELECT array_agg((x->>'asset_id')::uuid ORDER BY x->>'asset_id') INTO ids FROM jsonb_array_elements(page->'items') x;
 ack:=public.commit_mobile_reevaluation_photo_disposition_page((expired->>'user')::uuid,(h->>'id')::uuid,(h->>'sweep_no')::bigint,(h->>'capability_revision')::bigint,NULL,ids);
 PERFORM m3b_cycle_test.ok(ack->>'state'='settled','no capability scope settles normally');
 PERFORM m3b_cycle_test.ok(NOT private.conversation_media_maintenance_due('recurring'),'settled scope stops HTTP polling');
 UPDATE public.users SET status='deleted' WHERE id=(fresh->>'user')::uuid;
 PERFORM m3b_cycle_test.ok(NOT private.conversation_media_maintenance_due('recurring'),'deleted owner remains with the account coordinator');
END$$;
ROLLBACK;
