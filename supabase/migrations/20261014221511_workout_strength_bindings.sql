-- Dormant X4 storage only. No producer, function, custom trigger or activation.
-- CREATE-only objects: unknown existing state fails instead of being overwritten.
DO $preflight$
BEGIN
  IF pg_catalog.to_regnamespace('private') IS NULL
    OR pg_catalog.to_regclass('public.users') IS NULL
    OR pg_catalog.to_regclass('public.workout_logs') IS NULL THEN
    RAISE EXCEPTION 'workout_strength_bindings_requires_existing_substrate' USING ERRCODE='42P01';
  END IF;
  IF pg_catalog.to_regclass('private.workout_strength_lifecycles') IS NOT NULL
    OR pg_catalog.to_regclass('private.workout_strength_operations') IS NOT NULL
    OR pg_catalog.to_regclass('public.workout_logs_user_id_id_key') IS NOT NULL THEN
    RAISE EXCEPTION 'workout_strength_bindings_unknown_existing_object' USING ERRCODE='42P07';
  END IF;
END $preflight$;

CREATE UNIQUE INDEX workout_logs_user_id_id_key ON public.workout_logs(user_id,id);

CREATE TABLE private.workout_strength_lifecycles (
  user_id uuid NOT NULL,
  lifecycle_key uuid NOT NULL,
  opened_at timestamptz NOT NULL,
  closed_at timestamptz,
  close_operation_key text,
  PRIMARY KEY(user_id,lifecycle_key),
  CONSTRAINT workout_strength_lifecycles_owner_fk FOREIGN KEY(user_id)
    REFERENCES public.users(id) ON DELETE CASCADE,
  CONSTRAINT workout_strength_lifecycles_closure_check CHECK ((
    (closed_at IS NULL AND close_operation_key IS NULL)
    OR (closed_at IS NOT NULL AND close_operation_key IS NOT NULL
      AND close_operation_key<>'' AND closed_at>=opened_at)
  ) IS TRUE)
);
CREATE UNIQUE INDEX workout_strength_lifecycles_one_open
  ON private.workout_strength_lifecycles(user_id) WHERE closed_at IS NULL;

CREATE TABLE private.workout_strength_operations (
  user_id uuid NOT NULL,
  lifecycle_key uuid NOT NULL,
  operation_kind text NOT NULL,
  operation_key text COLLATE "C" NOT NULL,
  original_operation_type text COLLATE "C",
  original_workout_log_id uuid NOT NULL,
  live_workout_log_id uuid,
  created_at timestamptz NOT NULL,
  resolution text,
  capture_outcome text,
  legacy_result jsonb,
  answer_expected_revision integer,
  answer_question_key uuid,
  answer_value text,
  answer_receipt jsonb,
  CONSTRAINT workout_strength_operations_life_fk FOREIGN KEY(user_id,lifecycle_key)
    REFERENCES private.workout_strength_lifecycles(user_id,lifecycle_key) ON DELETE CASCADE,
  CONSTRAINT workout_strength_operations_live_fk FOREIGN KEY(user_id,live_workout_log_id)
    REFERENCES public.workout_logs(user_id,id) ON DELETE SET NULL(live_workout_log_id),
  CONSTRAINT workout_strength_operations_identity_check CHECK ((
    operation_kind IN ('capture','answer') AND operation_key<>''
    AND (live_workout_log_id IS NULL OR live_workout_log_id=original_workout_log_id)
  ) IS TRUE),
  CONSTRAINT workout_strength_operations_shape_check CHECK ((
    (operation_kind='capture'
      AND original_operation_type IS NOT NULL AND pg_catalog.btrim(original_operation_type)<>''
      AND resolution IN ('sql_insert','sql_replay','provider_type_dedup','recent6h_dedup')
      AND capture_outcome IN ('fact','legacy_provenance_gap')
      AND (resolution<>'sql_insert' OR capture_outcome='fact')
      AND ((resolution IN ('sql_insert','sql_replay') AND legacy_result IS NOT NULL)
        OR (resolution IN ('provider_type_dedup','recent6h_dedup') AND legacy_result IS NULL))
      AND answer_expected_revision IS NULL AND answer_question_key IS NULL
      AND answer_value IS NULL AND answer_receipt IS NULL)
    OR (operation_kind='answer'
      AND original_operation_type IS NULL AND resolution IS NULL
      AND capture_outcome IS NULL AND legacy_result IS NULL
      AND answer_expected_revision IS NOT NULL AND answer_expected_revision>=0
      AND answer_question_key IS NOT NULL AND answer_value IN ('yes','no')
      AND CASE WHEN pg_catalog.jsonb_typeof(answer_receipt)='object' THEN (
        answer_receipt ?& ARRAY['ownerID','workoutLogID','questionKey','answer','operationKey','acceptedAt']
        AND answer_receipt-ARRAY['ownerID','workoutLogID','questionKey','answer','operationKey','acceptedAt']='{}'::jsonb
        AND pg_catalog.jsonb_typeof(answer_receipt->'ownerID')='string'
        AND pg_catalog.jsonb_typeof(answer_receipt->'workoutLogID')='string'
        AND pg_catalog.jsonb_typeof(answer_receipt->'questionKey')='string'
        AND pg_catalog.jsonb_typeof(answer_receipt->'answer')='string'
        AND pg_catalog.jsonb_typeof(answer_receipt->'operationKey')='string'
        AND pg_catalog.jsonb_typeof(answer_receipt->'acceptedAt')='string'
        AND answer_receipt->>'ownerID'=user_id::text
        AND answer_receipt->>'workoutLogID'=original_workout_log_id::text
        AND answer_receipt->>'questionKey'=answer_question_key::text
        AND answer_receipt->>'answer'=answer_value
        AND answer_receipt->>'operationKey'<>'' AND answer_receipt->>'acceptedAt'<>''
      ) ELSE false END)
  ) IS TRUE)
);

-- Kind-specific idempotency preserves the raw C-collated capture type.
CREATE UNIQUE INDEX workout_strength_operations_capture_key
  ON private.workout_strength_operations(user_id,lifecycle_key,operation_key,original_operation_type)
  WHERE operation_kind='capture';
CREATE UNIQUE INDEX workout_strength_operations_answer_key
  ON private.workout_strength_operations(user_id,lifecycle_key,operation_key)
  WHERE operation_kind='answer';
-- Child-FK lookups cannot rely on the kind predicate of those UNIQUE indexes.
CREATE INDEX workout_strength_operations_lifecycle_lookup
  ON private.workout_strength_operations(user_id,lifecycle_key);
CREATE INDEX workout_strength_operations_live_workout_lookup
  ON private.workout_strength_operations(user_id,live_workout_log_id)
  WHERE live_workout_log_id IS NOT NULL;

ALTER TABLE private.workout_strength_lifecycles ENABLE ROW LEVEL SECURITY;
ALTER TABLE private.workout_strength_operations ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE private.workout_strength_lifecycles,private.workout_strength_operations
  FROM PUBLIC,anon,authenticated,service_role;
