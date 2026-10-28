\set ON_ERROR_STOP on
BEGIN ISOLATION LEVEL READ COMMITTED;
SET LOCAL statement_timeout='30s';
SET LOCAL lock_timeout='2s';
SET LOCAL request.jwt.claims='{"role":"service_role"}';
SET LOCAL TimeZone='UTC';
\ir fixtures/mobile_reevaluation_cycle_fixture.sql

-- Real public RPCs on the owned local database. Only the transport context is
-- simulated; no live HTTP or elapsed-calendar claim is made by this script.
CREATE FUNCTION m3b_cycle_test.http_conflict(statement text) RETURNS void
LANGUAGE plpgsql SET search_path=pg_catalog AS $$
DECLARE payload text; wire_detail text; caught boolean:=false;
BEGIN
  BEGIN
    EXECUTE statement;
  EXCEPTION WHEN SQLSTATE 'PGRST' THEN
    GET STACKED DIAGNOSTICS payload=MESSAGE_TEXT,wire_detail=PG_EXCEPTION_DETAIL;
    PERFORM m3b_cycle_test.ok((payload::jsonb)->>'code'='40001'
      AND (wire_detail::jsonb)->>'status'='409'
      AND (wire_detail::jsonb)->'headers'='{}'::jsonb
      AND length((payload::jsonb)->>'message')>0,
      'non_retrying_PostgREST_conflict_keeps_existing_wire_code_and_HTTP409');
    caught:=true;
  END;
  PERFORM m3b_cycle_test.ok(caught,'HTTP_conflict_must_not_escape_as_serialization_failure');
END $$;

DO $test$
DECLARE a uuid; c uuid; wrong_cycle uuid:=m3b_cycle_test.uid(7998); sql text; result jsonb; method text;
BEGIN
  a:=m3b_cycle_test.seed(7991,'2026-10-01T12:00:00Z');
  c:=(public.start_mobile_reevaluation_cycle(a,gen_random_uuid())#>>'{cycle,id}')::uuid;
  sql:=format('SELECT public.get_mobile_reevaluation_photo_consent(%L,%L)',a,wrong_cycle);
  PERFORM set_config('request.path','',true);
  PERFORM set_config('request.method','',true);
  PERFORM m3b_cycle_test.throws(sql,'40001','direct_SQL_original_conflict_unchanged');
  PERFORM set_config('request.path','/rpc/another_outer_function',true);
  PERFORM set_config('request.method','POST',true);
  PERFORM m3b_cycle_test.throws(sql,'40001','nested_public_call_does_not_intercept_parent_conflict');
  PERFORM set_config('request.path','/rpc/get_mobile_reevaluation_photo_consent',true);
  PERFORM set_config('request.method','',true);
  PERFORM m3b_cycle_test.throws(sql,'40001','missing_HTTP_method_does_not_change_direct_SQL');
  PERFORM set_config('request.method','PATCH',true);
  PERFORM m3b_cycle_test.throws(sql,'40001','unrecognised_RPC_method_does_not_change_SQL');
  FOREACH method IN ARRAY ARRAY['POST','GET','HEAD'] LOOP
    PERFORM set_config('request.method',method,true);
    PERFORM m3b_cycle_test.http_conflict(sql);
  END LOOP;
  PERFORM set_config('request.method','POST',true);
  result:=public.get_mobile_reevaluation_photo_consent(a,c);
  PERFORM m3b_cycle_test.ok(result->>'unavailable_reason'='policy_unavailable'
    AND result->'document'='null'::jsonb,'valid_response_and_policy_denial_preserved');
  PERFORM m3b_cycle_test.throws(format('SELECT public.get_mobile_reevaluation_photo_consent(%L,NULL)',a),
    '22023','non_conflict_SQLSTATE_is_not_translated');
  PERFORM m3b_cycle_test.ok((SELECT count(*)=0 FROM private.mobile_reevaluation_photo_consents),
    'no_new_legal_acceptance_or_photo_receipt');
END $test$;
ROLLBACK;
