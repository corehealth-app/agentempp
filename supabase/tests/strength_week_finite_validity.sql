\set ON_ERROR_STOP on
-- Historical semantic fixtures only, distinct from the real producer42day test.
-- Install the literal strength_week_fixture_support.sql helpers in this transaction's QA wrapper.
BEGIN ISOLATION LEVEL READ COMMITTED;
SET LOCAL search_path=pg_catalog;SET LOCAL TimeZone='UTC';SET LOCAL DateStyle='ISO,YMD';
SET LOCAL statement_timeout='45s';SET LOCAL lock_timeout='3s';
SET LOCAL ROLE postgres;
SET LOCAL request.jwt.claims='{"role":"service_role"}';
CREATE FUNCTION c59a2_fixture.state(u uuid) RETURNS jsonb LANGUAGE plpgsql STABLE SET search_path=pg_catalog SET DateStyle='ISO,YMD' SET TimeZone='UTC' AS $f$
DECLARE t record;a jsonb;r jsonb:=jsonb_build_object('user',(SELECT to_jsonb(x)FROM ONLY public.users x WHERE id=u));BEGIN
 FOR t IN SELECT n.nspname,c.relname FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
 WHERE n.nspname IN('public','private')AND c.relkind IN('r','p')AND EXISTS(SELECT 1 FROM pg_attribute a WHERE a.attrelid=c.oid AND a.attname='user_id'AND a.atttypid='uuid'::regtype AND a.attnum>0 AND NOT a.attisdropped)ORDER BY n.nspname,c.relname LOOP
 EXECUTE format('SELECT coalesce(jsonb_agg(to_jsonb(x)ORDER BY to_jsonb(x)::text),''[]''::jsonb)FROM ONLY %I.%I x WHERE user_id=$1',t.nspname,t.relname)INTO a USING u;
 r:=r||jsonb_build_object(t.nspname||'.'||t.relname,a);END LOOP;RETURN r;END $f$;
REVOKE ALL ON FUNCTION c59a2_fixture.state(uuid) FROM PUBLIC,anon,authenticated,service_role;
CREATE FUNCTION c59a2_fixture.finite_case(o jsonb,p jsonb,f jsonb,at timestamptz,source text,days smallint)
RETURNS jsonb LANGUAGE plpgsql SECURITY INVOKER SET search_path=pg_catalog AS $case$
DECLARE r jsonb;result jsonb;again jsonb;before_read jsonb;after_freeze jsonb;proposal jsonb;key text;start_at timestamptz;
BEGIN
 before_read:=c59a2_fixture.state((o->>'user_id')::uuid);
 r:=c59a2_fixture.read_at(o,at);
 IF r->>'status' IS DISTINCT FROM 'ready' OR r#>>'{context,kind}' IS DISTINCT FROM 'source_facts'
  OR r#>'{context,plan,receipt}' IS DISTINCT FROM p
  OR r#>'{context,frequency,receipt}' IS DISTINCT FROM f
  OR c59a2_fixture.state((o->>'user_id')::uuid) IS DISTINCT FROM before_read
 THEN RAISE EXCEPTION 'C59P2_GOLDEN_CONTEXT_OR_READ_CHANGED';END IF;
 start_at:=(r#>>'{context,week_start}')::date::timestamp AT TIME ZONE (r#>>'{context,timezone}');
 IF r#>>'{context,week_start_at}' IS DISTINCT FROM to_char(start_at AT TIME ZONE 'UTC','YYYY-MM-DD"T"HH24:MI:SS.US"Z"')
 THEN RAISE EXCEPTION 'C59P2_GOLDEN_OFFICIAL_MONDAY_WRONG';END IF;
 key:=CASE source WHEN 'accepted_plan' THEN p->>'source_version_id' WHEN 'informed_frequency' THEN f->>'source_version_id' ELSE NULL END;
 proposal:=c59a2_fixture.proposal(source,days,key);
 result:=c59a2_fixture.freeze_at(o,r,proposal,at);
 IF result->>'status' IS DISTINCT FROM 'frozen' OR result#>>'{target,source}' IS DISTINCT FROM source
  OR result#>>'{target,planned_days}' IS DISTINCT FROM days::text
  OR result#>>'{target,source_key}' IS DISTINCT FROM key
  OR result#>'{target,source_proof}' IS DISTINCT FROM r#>'{context,source_proof}'
  OR (SELECT count(*) FROM private.strength_week_targets WHERE user_id=(o->>'user_id')::uuid)<>1
  OR c59a2_fixture.state((o->>'user_id')::uuid)-'private.strength_week_targets'
   IS DISTINCT FROM before_read-'private.strength_week_targets'
 THEN RAISE EXCEPTION 'C59P2_GOLDEN_FREEZE_WRONG_OR_SIDE_EFFECT';END IF;
 after_freeze:=c59a2_fixture.state((o->>'user_id')::uuid);
 again:=c59a2_fixture.freeze_at(o,r,proposal,at);
 IF again->>'status' IS DISTINCT FROM 'reused' OR again->'target' IS DISTINCT FROM result->'target'
  OR c59a2_fixture.state((o->>'user_id')::uuid) IS DISTINCT FROM after_freeze
 THEN RAISE EXCEPTION 'C59P2_GOLDEN_REPLAY_CHANGED_WINNER';END IF;
 RETURN result->'target';
END $case$;
REVOKE ALL ON FUNCTION c59a2_fixture.finite_case(jsonb,jsonb,jsonb,timestamptz,text,smallint) FROM PUBLIC,anon,authenticated,service_role;

DO $matrix$
DECLARE o jsonb;p jsonb;f jsonb;a jsonb;b jsonb;target jsonb;r jsonb;before_read jsonb;delta integer;until_at timestamptz;
 monday constant timestamptz:='2026-10-12T03:00:00.000000Z';label text;days smallint;source text;
BEGIN
 FOR delta IN -1..1 LOOP
  label:='P2-boundary-'||delta;
  o:=c59a2_fixture.new_owner(label);
  until_at:=monday+delta*interval '1 microsecond';
  p:=c59a2_fixture.plan(o,3::smallint,label||'-plan','2026-10-08T12:00:00.000000Z',until_at);
  f:=c59a2_fixture.frequency(o,4::smallint,label||'-frequency');
  source:=CASE WHEN delta<0 THEN 'informed_frequency' ELSE 'accepted_plan' END;
  days:=CASE WHEN delta<0 THEN 4 ELSE 3 END;
  PERFORM c59a2_fixture.finite_case(o,p,f,'2026-10-12T12:00Z',source,days);
  PERFORM c59a2_fixture.ok(true,label||':inclusive_read_freeze_replay');
 END LOOP;
 o:=c59a2_fixture.new_owner('P2-no-resurrection');
 a:=c59a2_fixture.plan(o,2::smallint,'P2-old-A','2026-10-07T12:00Z',NULL);
 b:=c59a2_fixture.plan(o,3::smallint,'P2-new-B','2026-10-08T12:00Z',monday-interval '1 microsecond');
 f:=c59a2_fixture.frequency(o,4::smallint,'P2-new-B-frequency');
 target:=c59a2_fixture.finite_case(o,b,f,'2026-10-12T12:00Z','informed_frequency',4::smallint);
 PERFORM c59a2_fixture.ok(target#>>'{source_proof,plan,source_version_id}'=b->>'source_version_id'
  AND target#>>'{source_proof,plan,source_version_id}'<>a->>'source_version_id','P2:expired_B_does_not_revive_A');
 o:=c59a2_fixture.new_owner('P2-late-Friday');
 p:=c59a2_fixture.plan(o,3::smallint,'P2-expire-Wednesday','2026-10-08T12:00Z','2026-10-14T03:00Z');
 f:=c59a2_fixture.frequency(o,4::smallint,'P2-late-Friday-frequency');
 target:=c59a2_fixture.finite_case(o,p,f,'2026-10-16T18:00Z','accepted_plan',3::smallint);
 r:=c59a2_fixture.read_at(o,'2026-10-19T12:00Z');
 PERFORM c59a2_fixture.ok(r->>'status'='ready' AND r#>'{context,plan,receipt}'=p
  AND r#>>'{context,week_start_at}'='2026-10-19T03:00:00.000000Z','P2:next_Monday_retains_expired_proof');
 -- This second week has no winner; freeze must fall back to frequency4.
 target:=c59a2_fixture.freeze_at(o,r,c59a2_fixture.proposal('informed_frequency',4::smallint,f->>'source_version_id'),'2026-10-19T12:00Z')->'target';
 PERFORM c59a2_fixture.ok(target->>'source'='informed_frequency' AND target->>'planned_days'='4'
  AND target#>>'{source_proof,plan,source_version_id}'=p->>'source_version_id','P2:next_Monday_frequency_fallback');
 o:=c59a2_fixture.new_owner('P2-winner');
 p:=c59a2_fixture.plan(o,3::smallint,'P2-winner-A','2026-10-08T12:00Z','2026-10-14T03:00Z');
 f:=c59a2_fixture.frequency(o,4::smallint,'P2-winner-frequency');
 target:=c59a2_fixture.finite_case(o,p,f,'2026-10-12T12:00Z','accepted_plan',3::smallint);
 b:=c59a2_fixture.plan(o,2::smallint,'P2-winner-B','2026-10-15T12:00Z','2026-10-16T03:00Z');
 UPDATE public.users SET timezone='Asia/Tokyo' WHERE id=(o->>'user_id')::uuid;
 before_read:=c59a2_fixture.state((o->>'user_id')::uuid);
 r:=c59a2_fixture.read_at(o,'2026-10-16T18:00Z');
 PERFORM c59a2_fixture.ok(r->>'status'='ready' AND r#>>'{context,kind}'='existing_target'
  AND r#>'{context,target}'=target AND c59a2_fixture.state((o->>'user_id')::uuid)=before_read,
  'P2:stored_winner_survives_expiry_replacement_timezone');
 FOREACH label IN ARRAY ARRAY['zero','absent'] LOOP
  o:=c59a2_fixture.new_owner('P2-frequency-'||label);
  p:=c59a2_fixture.plan(o,3::smallint,'P2-frequency-plan-'||label,'2026-10-08T12:00Z',monday-interval '1 microsecond');
  f:=c59a2_fixture.frequency(o,CASE label WHEN 'zero' THEN 0::smallint ELSE NULL END,'P2-frequency-'||label);
  PERFORM c59a2_fixture.finite_case(o,p,f,'2026-10-12T12:00Z',
   CASE label WHEN 'zero' THEN 'informed_frequency' ELSE 'absent' END,CASE label WHEN 'zero' THEN 0::smallint ELSE NULL END);
  PERFORM c59a2_fixture.ok(true,'P2:expired_plan_frequency_'||label);
 END LOOP;
 o:=c59a2_fixture.new_owner('P2-unknown-frequency');
 p:=c59a2_fixture.plan(o,3::smallint,'P2-unknown-frequency-plan','2026-10-08T12:00Z',monday-interval '1 microsecond');
 before_read:=c59a2_fixture.state((o->>'user_id')::uuid);
 r:=c59a2_fixture.read_at(o);
 PERFORM c59a2_fixture.ok(r='{"status":"unavailable","reason":"history_incomplete"}'::jsonb
  AND c59a2_fixture.state((o->>'user_id')::uuid)=before_read,'P2:expired_plan_unknown_frequency_unavailable');
 o:=c59a2_fixture.new_owner('P2-valid-unknown-frequency');
 p:=c59a2_fixture.plan(o,3::smallint,'P2-valid-no-frequency','2026-10-08T12:00Z',monday);
 target:=c59a2_fixture.finite_case(o,p,NULL,'2026-10-12T12:00Z','accepted_plan',3::smallint);
 PERFORM c59a2_fixture.ok(target->>'planned_days'='3','P2:valid_plan_unknown_frequency_accepted');
END $matrix$;
ROLLBACK;
