-- Final owner deletion must honor existing audit FKs without making audit rows mutable.
-- Only a nested trusted cascade after the actual owner disappears can delete an
-- owner ledger. Global legal catalogs, direct writes and existing ACLs stay guarded.
BEGIN;
SET LOCAL search_path=pg_catalog;
DO $audit_cascade$
DECLARE row record; original text; definition text; before_metadata jsonb; after_metadata jsonb; next_body text;
BEGIN
 IF current_user<>'postgres' OR to_regclass('private.mobile_clinical_legacy_admissions') IS NULL
  OR to_regprocedure('public.purge_mobile_reevaluation_photo_catalog_for_deleted_user(uuid,timestamptz)') IS NULL THEN
  RAISE EXCEPTION 'mobile_account_audit_cascade_precondition' USING ERRCODE='42501';
 END IF;
 FOR row IN SELECT * FROM (VALUES
  ('private.reject_onboarding_legal_mutation()','b22548dacf3d1452dbd88a272dc9ea18acf23eccd69a54b14177089964190344',ARRAY['user_onboarding_legal_actions'],'Onboarding legal records are immutable'),
  ('private.reject_coach_audit_mutation()','9141cdfe9260a97081ec72dd9a130317a7f210b3d4f8ea0acfa250acc8ac551a',ARRAY['coach_message_usage','user_mascot_state_events'],'BodyFlow coach audit records are append-only'),
  ('private.reject_bodyflow_routine_immutable_mutation()','a32ac81d03deffbb259d3e465e8bff93582febbb0aacdd1cace10c38f0d4a701',ARRAY['user_legal_acceptances','routine_adherence_logs'],'BodyFlow routine audit records are immutable'),
  ('private.guard_content_events_immutable()','4d0c46822254929db26ecabd3c1af142c1244b5df8e27ad572c81d4b57f0b7f9',ARRAY['content_events'],'content events are append-only')
 ) AS x(signature,source_sha256,owner_tables,error_message) LOOP
  SELECT p.prosrc,pg_get_functiondef(p.oid),to_jsonb(p)-'prosrc'
   INTO STRICT original,definition,before_metadata
   FROM pg_proc p WHERE p.oid=to_regprocedure(row.signature)
    AND p.proowner='postgres'::regrole AND NOT p.prosecdef
    AND p.prorettype='trigger'::regtype AND p.provolatile='v'
    AND p.prolang=(SELECT oid FROM pg_language WHERE lanname='plpgsql');
  IF encode(extensions.digest(convert_to(original,'UTF8'),'sha256'),'hex')<>row.source_sha256 THEN
   RAISE EXCEPTION 'mobile_account_audit_cascade_source_drift:%',row.signature USING ERRCODE='55000';
  END IF;
  IF EXISTS(SELECT 1 FROM unnest(row.owner_tables) t(name)
   WHERE NOT EXISTS(SELECT 1 FROM pg_constraint k JOIN pg_attribute a
    ON a.attrelid=k.conrelid AND a.attnum=k.conkey[1]
    WHERE k.conrelid=to_regclass('public.'||t.name) AND k.confrelid='public.users'::regclass
     AND k.contype='f' AND k.confdeltype='c' AND cardinality(k.conkey)=1 AND a.attname='user_id')) THEN
   RAISE EXCEPTION 'mobile_account_audit_cascade_owner_fk_drift:%',row.signature USING ERRCODE='55000';
  END IF;
  next_body:=format($body$
BEGIN
 IF TG_OP='DELETE' AND TG_TABLE_SCHEMA='public' AND TG_TABLE_NAME=ANY(%L::text[]) THEN
  IF current_user IN('postgres','service_role') AND pg_trigger_depth()>1
   AND NOT EXISTS(SELECT 1 FROM public.users WHERE id=OLD.user_id) THEN
   RETURN OLD;
  END IF;
 END IF;
 RAISE EXCEPTION %L USING ERRCODE='23514';
END;
$body$,row.owner_tables,row.error_message);
  EXECUTE replace(definition,original,next_body);
  SELECT to_jsonb(p)-'prosrc' INTO STRICT after_metadata FROM pg_proc p
   WHERE p.oid=to_regprocedure(row.signature);
  IF before_metadata IS DISTINCT FROM after_metadata OR
   (SELECT prosrc FROM pg_proc WHERE oid=to_regprocedure(row.signature)) IS DISTINCT FROM next_body THEN
   RAISE EXCEPTION 'mobile_account_audit_cascade_metadata_changed:%',row.signature USING ERRCODE='55000';
  END IF;
 END LOOP;
END $audit_cascade$;

-- Preserve the existing CASCADE ownership policy. Resolve cross-ledger FKs in
-- one SQL statement, with cascading children sequenced before their parents.
-- No foreign key is disabled, deferred, dropped or relaxed. The trigger runs
-- after the owner row disappears and before its ordinary RI cascade triggers.
DO $owned_preflight$
DECLARE required text[]:=ARRAY['private.mobile_clinical_body_fat_heads','private.mobile_clinical_body_fat_receipts','private.mobile_clinical_calorie_decisions','private.mobile_clinical_confirmation_keys','private.mobile_clinical_daily_applications','private.mobile_clinical_daily_heads','private.mobile_clinical_daily_keys','private.mobile_clinical_day_events','private.mobile_clinical_episode_events','private.mobile_clinical_first_phase_confirmations','private.mobile_clinical_first_phase_keys','private.mobile_clinical_first_phase_previews','private.mobile_clinical_full_commands','private.mobile_clinical_full_presentations','private.mobile_clinical_full_receipts','private.mobile_clinical_generation_sources','private.mobile_clinical_health_clear_receipts','private.mobile_clinical_preference_heads','private.mobile_clinical_preference_receipts','private.mobile_clinical_previews','private.mobile_clinical_signup_application_keys','private.mobile_clinical_signup_applications','private.mobile_clinical_signup_origins','private.mobile_clinical_start_requests','private.mobile_clinical_target_origin_heads','private.mobile_clinical_target_origins','private.mobile_reevaluation_cycles','private.mobile_reevaluation_photo_consent_keys','private.mobile_reevaluation_photo_consents','private.mobile_reevaluation_photo_purge_scope_visits','private.mobile_reevaluation_start_keys','private.mobile_registration_feedback','private.mobile_signup_strength_completion_receipts','private.routine_occurrence_finalizer_rules','private.strength_week_lifecycle_bindings','private.strength_week_targets','public.notification_deliveries','public.pending_registrations','public.reminder_events','public.reminder_rules','public.routine_adherence_logs']; missing text[];
BEGIN
 IF to_regprocedure('private.prune_mobile_deleted_user_owned_dependents()') IS NOT NULL
  OR EXISTS(SELECT 1 FROM pg_trigger WHERE tgrelid='public.users'::regclass AND tgname='00_mobile_account_owned_dependents') THEN
  RAISE EXCEPTION 'mobile_account_cascade_unknown_existing_object' USING ERRCODE='42P07';
 END IF;
 WITH RECURSIVE owned(oid,owner_attnum,path) AS (
  SELECT 'public.users'::regclass::oid,(SELECT attnum FROM pg_attribute WHERE attrelid='public.users'::regclass AND attname='id'),ARRAY['public.users'::regclass::oid]
  UNION ALL SELECT k.conrelid,ca.attnum,o.path||k.conrelid FROM owned o
  JOIN pg_constraint k ON k.confrelid=o.oid AND k.contype='f' AND k.confdeltype='c'
  JOIN pg_class c ON c.oid=k.conrelid JOIN pg_namespace n ON n.oid=c.relnamespace
  JOIN pg_attribute ca ON ca.attrelid=k.conrelid AND ca.attname='user_id' AND NOT ca.attisdropped AND ca.atttypid='uuid'::regtype
  WHERE n.nspname IN('public','private') AND NOT k.conrelid=ANY(o.path)
   AND EXISTS(SELECT 1 FROM generate_subscripts(k.confkey,1) x(i) WHERE k.confkey[x.i]=o.owner_attnum AND k.conkey[x.i]=ca.attnum)
 ) SELECT array_agg(name) INTO missing FROM unnest(required) x(name)
  WHERE NOT EXISTS(SELECT 1 FROM owned WHERE oid=to_regclass(x.name));
 IF missing IS NOT NULL THEN
  RAISE EXCEPTION 'mobile_account_cascade_ownership_drift' USING ERRCODE='55000';
 END IF;
 IF EXISTS(SELECT 1 FROM pg_trigger WHERE tgrelid='public.users'::regclass
  AND (tgtype::integer & 8)<>0 AND (tgtype::integer & 2)=0
  AND (tgname COLLATE "C")<('00_mobile_account_owned_dependents' COLLATE "C")) THEN
  RAISE EXCEPTION 'mobile_account_cascade_trigger_order_drift' USING ERRCODE='55000';
 END IF;
END $owned_preflight$;

CREATE FUNCTION private.prune_mobile_deleted_user_owned_dependents() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog AS $prune$
DECLARE removed bigint;
BEGIN
 PERFORM private.assert_trusted_backend();
 IF TG_OP<>'DELETE' OR TG_TABLE_SCHEMA<>'public' OR TG_TABLE_NAME<>'users'
  OR EXISTS(SELECT 1 FROM public.users WHERE id=OLD.id) THEN
  RAISE EXCEPTION 'mobile_account_cascade_not_final_owner_delete' USING ERRCODE='55000';
 END IF;
 IF EXISTS(SELECT 1 FROM public.media_assets WHERE user_id=OLD.id)
  OR EXISTS(SELECT 1 FROM private.mobile_reevaluation_photo_assets WHERE user_id=OLD.id)
  OR EXISTS(SELECT 1 FROM private.mobile_reevaluation_photo_dispositions WHERE user_id=OLD.id) THEN
  RAISE EXCEPTION 'mobile_account_media_not_purged' USING ERRCODE='55000';
 END IF;
 WITH d1 AS (DELETE FROM public.notification_deliveries WHERE user_id=OLD.id RETURNING 1),
 d2 AS (DELETE FROM private.mobile_clinical_body_fat_heads WHERE user_id=OLD.id AND (SELECT count(*) FROM d1)>=0 RETURNING 1),
 d3 AS (DELETE FROM private.mobile_clinical_body_fat_receipts WHERE user_id=OLD.id AND (SELECT count(*) FROM d2)>=0 RETURNING 1),
 d4 AS (DELETE FROM private.mobile_clinical_calorie_decisions WHERE user_id=OLD.id AND (SELECT count(*) FROM d3)>=0 RETURNING 1),
 d5 AS (DELETE FROM private.mobile_clinical_confirmation_keys WHERE user_id=OLD.id AND (SELECT count(*) FROM d4)>=0 RETURNING 1),
 d6 AS (DELETE FROM private.mobile_clinical_daily_applications WHERE user_id=OLD.id AND (SELECT count(*) FROM d5)>=0 RETURNING 1),
 d7 AS (DELETE FROM private.mobile_clinical_daily_heads WHERE user_id=OLD.id AND (SELECT count(*) FROM d6)>=0 RETURNING 1),
 d8 AS (DELETE FROM private.mobile_clinical_daily_keys WHERE user_id=OLD.id AND (SELECT count(*) FROM d7)>=0 RETURNING 1),
 d9 AS (DELETE FROM private.mobile_clinical_day_events WHERE user_id=OLD.id AND (SELECT count(*) FROM d8)>=0 RETURNING 1),
 d10 AS (DELETE FROM private.mobile_clinical_episode_events WHERE user_id=OLD.id AND (SELECT count(*) FROM d9)>=0 RETURNING 1),
 d11 AS (DELETE FROM private.mobile_clinical_first_phase_confirmations WHERE user_id=OLD.id AND (SELECT count(*) FROM d10)>=0 RETURNING 1),
 d12 AS (DELETE FROM private.mobile_clinical_first_phase_keys WHERE user_id=OLD.id AND (SELECT count(*) FROM d11)>=0 RETURNING 1),
 d13 AS (DELETE FROM private.mobile_clinical_first_phase_previews WHERE user_id=OLD.id AND (SELECT count(*) FROM d12)>=0 RETURNING 1),
 d14 AS (DELETE FROM private.mobile_clinical_full_presentations WHERE user_id=OLD.id AND (SELECT count(*) FROM d13)>=0 RETURNING 1),
 d15 AS (DELETE FROM private.mobile_clinical_generation_sources WHERE user_id=OLD.id AND (SELECT count(*) FROM d14)>=0 RETURNING 1),
 d16 AS (DELETE FROM private.mobile_clinical_health_clear_receipts WHERE user_id=OLD.id AND (SELECT count(*) FROM d15)>=0 RETURNING 1),
 d17 AS (DELETE FROM private.mobile_clinical_preference_heads WHERE user_id=OLD.id AND (SELECT count(*) FROM d16)>=0 RETURNING 1),
 d18 AS (DELETE FROM private.mobile_clinical_preference_receipts WHERE user_id=OLD.id AND (SELECT count(*) FROM d17)>=0 RETURNING 1),
 d19 AS (DELETE FROM private.mobile_clinical_signup_application_keys WHERE user_id=OLD.id AND (SELECT count(*) FROM d18)>=0 RETURNING 1),
 d20 AS (DELETE FROM private.mobile_clinical_signup_applications WHERE user_id=OLD.id AND (SELECT count(*) FROM d19)>=0 RETURNING 1),
 d21 AS (DELETE FROM private.mobile_clinical_signup_origins WHERE user_id=OLD.id AND (SELECT count(*) FROM d20)>=0 RETURNING 1),
 d22 AS (DELETE FROM private.mobile_clinical_start_requests WHERE user_id=OLD.id AND (SELECT count(*) FROM d21)>=0 RETURNING 1),
 d23 AS (DELETE FROM private.mobile_clinical_target_origin_heads WHERE user_id=OLD.id AND (SELECT count(*) FROM d22)>=0 RETURNING 1),
 d24 AS (DELETE FROM private.mobile_clinical_target_origins WHERE user_id=OLD.id AND (SELECT count(*) FROM d23)>=0 RETURNING 1),
 d25 AS (DELETE FROM private.mobile_reevaluation_photo_consent_keys WHERE user_id=OLD.id AND (SELECT count(*) FROM d24)>=0 RETURNING 1),
 d26 AS (DELETE FROM private.mobile_reevaluation_photo_purge_scope_visits WHERE user_id=OLD.id AND (SELECT count(*) FROM d25)>=0 RETURNING 1),
 d27 AS (DELETE FROM private.mobile_reevaluation_start_keys WHERE user_id=OLD.id AND (SELECT count(*) FROM d26)>=0 RETURNING 1),
 d28 AS (DELETE FROM private.mobile_registration_feedback WHERE user_id=OLD.id AND (SELECT count(*) FROM d27)>=0 RETURNING 1),
 d29 AS (DELETE FROM private.routine_occurrence_finalizer_rules WHERE user_id=OLD.id AND (SELECT count(*) FROM d28)>=0 RETURNING 1),
 d30 AS (DELETE FROM private.strength_week_lifecycle_bindings WHERE user_id=OLD.id AND (SELECT count(*) FROM d29)>=0 RETURNING 1),
 d31 AS (DELETE FROM private.strength_week_targets WHERE user_id=OLD.id AND (SELECT count(*) FROM d30)>=0 RETURNING 1),
 d32 AS (DELETE FROM public.reminder_events WHERE user_id=OLD.id AND (SELECT count(*) FROM d31)>=0 RETURNING 1),
 d33 AS (DELETE FROM public.routine_adherence_logs WHERE user_id=OLD.id AND (SELECT count(*) FROM d32)>=0 RETURNING 1),
 d34 AS (DELETE FROM public.pending_registrations WHERE user_id=OLD.id AND (SELECT count(*) FROM d33)>=0 RETURNING 1),
 d35 AS (DELETE FROM private.mobile_clinical_full_commands WHERE user_id=OLD.id AND (SELECT count(*) FROM d34)>=0 RETURNING 1),
 d36 AS (DELETE FROM private.mobile_clinical_full_receipts WHERE user_id=OLD.id AND (SELECT count(*) FROM d35)>=0 RETURNING 1),
 d37 AS (DELETE FROM private.mobile_reevaluation_photo_consents WHERE user_id=OLD.id AND (SELECT count(*) FROM d36)>=0 RETURNING 1),
 d38 AS (DELETE FROM private.mobile_signup_strength_completion_receipts WHERE user_id=OLD.id AND (SELECT count(*) FROM d37)>=0 RETURNING 1),
 d39 AS (DELETE FROM public.reminder_rules WHERE user_id=OLD.id AND (SELECT count(*) FROM d38)>=0 RETURNING 1),
 d40 AS (DELETE FROM private.mobile_clinical_previews WHERE user_id=OLD.id AND (SELECT count(*) FROM d39)>=0 RETURNING 1),
 d41 AS (DELETE FROM private.mobile_reevaluation_cycles WHERE user_id=OLD.id AND (SELECT count(*) FROM d40)>=0 RETURNING 1)
 SELECT count(*) INTO removed FROM d41;
 RETURN OLD;
END $prune$;
REVOKE ALL ON FUNCTION private.prune_mobile_deleted_user_owned_dependents() FROM PUBLIC,anon,authenticated,service_role;
CREATE TRIGGER "00_mobile_account_owned_dependents" AFTER DELETE ON public.users FOR EACH ROW EXECUTE FUNCTION private.prune_mobile_deleted_user_owned_dependents();

COMMIT;
