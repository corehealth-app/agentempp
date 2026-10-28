-- Synthetic local receipt proof only; no image, provider or real account.
BEGIN;
SET LOCAL search_path=pg_catalog;
SELECT set_config('request.jwt.claim.role','service_role',true);
\ir fixtures/mobile_reevaluation_photo_fixture.sql
DO $$
DECLARE owner_id uuid; other_id uuid; generation_id uuid; epoch_id uuid;
 completed_at timestamptz; proof jsonb; captured jsonb;
BEGIN
 owner_id:=m3b_cycle_test.seed(1900,'2026-10-01T00:00:00Z');
 other_id:=m3b_cycle_test.seed(1901,'2026-10-01T00:00:00Z');
 SELECT admission_id,epoch,r.completed_at INTO generation_id,epoch_id,completed_at
  FROM private.mobile_signup_strength_completion_receipts r WHERE user_id=owner_id;
 UPDATE public.user_profiles SET body_fat_percent=24 WHERE user_id=owner_id;
 PERFORM m3b_cycle_test.ok(private.mobile_clinical_signup_photo_origin(owner_id,generation_id,epoch_id) IS NULL,
  'a current profile and signup baseline alone are not confirmed photo provenance');
 INSERT INTO private.signup_body_photo_receipts(user_id,onboarding_completed_at,decision,method,
  front_asset_id,side_asset_id,back_asset_id,fingerprint,confirmed_body_fat_percent,decided_at)
 VALUES(owner_id,completed_at,'accepted','arithmetic_mean_v1',m3b_cycle_test.uid(1902),
  m3b_cycle_test.uid(1903),m3b_cycle_test.uid(1904),repeat('a',64),24,completed_at);
 proof:=private.mobile_clinical_signup_photo_origin(owner_id,generation_id,epoch_id);
 PERFORM m3b_cycle_test.ok(proof->>'user_id'=owner_id::text AND proof->>'signup_generation'=generation_id::text
  AND proof->>'signup_epoch'=epoch_id::text AND (proof->>'confirmed_body_fat_percent')::numeric=24
  AND proof->>'method'='arithmetic_mean_v1' AND proof->>'receipt_version'='1',
  'accepted closed receipt is bound to genuine completion generation and epoch');
 PERFORM m3b_cycle_test.ok(NOT (proof ?| ARRAY['front_asset_id','side_asset_id','back_asset_id','source_ids','path','url'])
  AND proof->>'onboarding_completed_at' ~ '\.[0-9]{6}Z$' AND proof->>'decided_at' ~ '\.[0-9]{6}Z$',
  'numeric projection has canonical instants and no media identities or paths');
 captured:=private.capture_mobile_clinical_context_at(owner_id,'ROUTINE_REVIEW',NULL,'2026-10-02T00:00:00Z');
 PERFORM m3b_cycle_test.ok(captured#>'{facts,protocol_authority,signup_body_fat_origin}'=proof,
  'signup photo proof is part of the same hashed clinical context');
 PERFORM m3b_cycle_test.ok(private.mobile_clinical_signup_photo_origin(other_id,generation_id,epoch_id) IS NULL
  AND private.mobile_clinical_signup_photo_origin(owner_id,m3b_cycle_test.uid(1905),epoch_id) IS NULL
  AND private.mobile_clinical_signup_photo_origin(owner_id,generation_id,m3b_cycle_test.uid(1905)) IS NULL,
  'owner generation and epoch cannot be borrowed');
 PERFORM m3b_cycle_test.ok(NOT EXISTS(SELECT 1 FROM public.media_assets WHERE id IN
  (m3b_cycle_test.uid(1902),m3b_cycle_test.uid(1903),m3b_cycle_test.uid(1904)))
  AND private.mobile_clinical_signup_photo_origin(owner_id,generation_id,epoch_id)=proof,
  'numeric proof does not need historical images to remain stored');
 UPDATE public.user_profiles SET body_fat_percent=body_fat_percent WHERE user_id=owner_id;
 PERFORM m3b_cycle_test.ok(private.mobile_clinical_signup_photo_origin(owner_id,generation_id,epoch_id) IS NULL,
  'manual write of the identical number invalidates photo provenance');
 PERFORM m3b_cycle_test.ok(captured->>'context_hash'<>
  private.capture_mobile_clinical_context_at(owner_id,'ROUTINE_REVIEW',NULL,'2026-10-02T00:00:00Z')->>'context_hash',
  'same-number provenance invalidation makes the old clinical preview stale');
 PERFORM m3b_cycle_test.ok((SELECT count(*)=1 FROM private.signup_body_photo_receipts WHERE user_id=owner_id),
  'numeric historical receipt is retained after invalidation');
 PERFORM public.reset_user_conversation_atomic(owner_id,true);
 PERFORM m3b_cycle_test.ok(private.mobile_clinical_signup_photo_origin(owner_id,generation_id,epoch_id) IS NULL,
  'reset cannot revive a historical accepted receipt');
END $$;
SELECT m3b_cycle_test.ok(NOT has_function_privilege(role,
 'private.mobile_clinical_signup_photo_origin(uuid,uuid,uuid)','EXECUTE'),
 role||' cannot fetch private clinical signup provenance')
 FROM unnest(ARRAY['anon','authenticated','service_role']) role;
ROLLBACK;
