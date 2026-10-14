-- TEST-ONLY substrate fragment. Included INSIDE the X26 runner transaction.
-- Requires the pinned C59a2 minimum bootstrap users/protocol_enum/roles.
-- No fake product function, new enum, DROP, clone, remote access or COMMIT.
-- Exact selected schema/index statements copied from real repository migrations.

CREATE TABLE daily_snapshots (
  id                    uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id               uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  date                  date NOT NULL,
  calories_consumed     integer NOT NULL DEFAULT 0,
  calories_target       integer,
  protein_g             numeric(6,2) NOT NULL DEFAULT 0,
  protein_target        numeric(6,2),
  carbs_g               numeric(6,2) NOT NULL DEFAULT 0,
  fat_g                 numeric(6,2) NOT NULL DEFAULT 0,
  exercise_calories     integer NOT NULL DEFAULT 0,
  steps                 integer,
  training_done         boolean NOT NULL DEFAULT false,
  sleep_hours           numeric(3,1),
  water_consumed_ml     integer NOT NULL DEFAULT 0,
  xp_earned             integer NOT NULL DEFAULT 0,
  deficit_accumulated   integer NOT NULL DEFAULT 0,
  daily_balance         integer GENERATED ALWAYS AS (
    calories_consumed - COALESCE(calories_target, 0) - COALESCE(exercise_calories, 0)
  ) STORED,
  current_protocol      protocol_enum,
  day_closed            boolean NOT NULL DEFAULT false,
  closed_at             timestamptz,
  created_at            timestamptz NOT NULL DEFAULT now(),
  updated_at            timestamptz NOT NULL DEFAULT now(),
  UNIQUE(user_id, date)
);

CREATE INDEX idx_daily_user_date ON daily_snapshots(user_id, date DESC);
CREATE INDEX idx_daily_unclosed ON daily_snapshots(date, day_closed) WHERE day_closed = false;

COMMENT ON TABLE daily_snapshots IS 'Resumo agregado por usuário/dia. Atualizado por cada refeição/treino.';
COMMENT ON COLUMN daily_snapshots.daily_balance IS 'Positivo = surplus, negativo = déficit.';

CREATE TABLE workout_logs (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id         uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  snapshot_id     uuid REFERENCES daily_snapshots(id) ON DELETE CASCADE,
  workout_type    text,
  duration_min    integer CHECK (duration_min IS NULL OR duration_min > 0),
  estimated_kcal  integer CHECK (estimated_kcal IS NULL OR estimated_kcal >= 0),
  intensity       text,
  notes           text,
  performed_at    timestamptz NOT NULL DEFAULT now(),
  raw_message_id  uuid,
  created_at      timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX idx_workouts_user_performed ON workout_logs(user_id, performed_at DESC);

ALTER TABLE workout_logs
  ADD COLUMN IF NOT EXISTS raw_provider_message_id text;

CREATE UNIQUE INDEX IF NOT EXISTS uniq_workout_logs_provider_msg
  ON workout_logs (user_id, raw_provider_message_id, workout_type)
  WHERE raw_provider_message_id IS NOT NULL;

ALTER TABLE daily_snapshots
  ADD COLUMN day_status text NOT NULL DEFAULT 'complete'
    CHECK (day_status IN ('complete', 'user_skipped', 'incomplete_no_response', 'pending_close'));

ALTER TABLE daily_snapshots
  ADD COLUMN gap_reminder_sent_at timestamp with time zone;

-- Índice pra cron de re-check: encontra rapidamente os pending_close vencidos.
CREATE INDEX idx_daily_snapshots_pending_close
  ON daily_snapshots (gap_reminder_sent_at)
  WHERE day_status = 'pending_close';

ALTER TABLE daily_snapshots ENABLE ROW LEVEL SECURITY;
ALTER TABLE workout_logs ENABLE ROW LEVEL SECURITY;

-- S5 test-only owner helpers, independent from prior task schemas.
CREATE SCHEMA c59s5_fixture;
REVOKE ALL ON SCHEMA c59s5_fixture FROM PUBLIC,anon,authenticated,service_role;
CREATE FUNCTION c59s5_fixture.ok(p_ok boolean,p_label text) RETURNS void
LANGUAGE plpgsql SECURITY INVOKER SET search_path=pg_catalog AS $$
BEGIN
  IF p_ok IS DISTINCT FROM true THEN RAISE EXCEPTION 'C59S5_ASSERT:%',p_label USING ERRCODE='P0001';END IF;
  RAISE NOTICE 'C59S5_PASS:%',p_label;
END $$;
CREATE FUNCTION c59s5_fixture.throws(p_sql text,p_state text,p_message text,p_label text) RETURNS void
LANGUAGE plpgsql SECURITY INVOKER SET search_path=pg_catalog AS $$
DECLARE s text;m text;
BEGIN
  BEGIN EXECUTE p_sql;
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS s=RETURNED_SQLSTATE,m=MESSAGE_TEXT;
    PERFORM c59s5_fixture.ok(s=p_state AND(p_message IS NULL OR m=p_message),p_label);RETURN;
  END;
  RAISE EXCEPTION 'C59S5_EXPECTED_ERROR:%',p_label USING ERRCODE='P0001';
END $$;
REVOKE ALL ON FUNCTION c59s5_fixture.ok(boolean,text) FROM PUBLIC,anon,authenticated,service_role;
REVOKE ALL ON FUNCTION c59s5_fixture.throws(text,text,text,text) FROM PUBLIC,anon,authenticated,service_role;
