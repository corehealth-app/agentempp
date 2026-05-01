-- ============================================================================
-- Migration 0013: Daily closer + cron jobs
-- ============================================================================
-- Funções SQL que replicam @mpp/core/progress-calc para rodar via pg_cron
-- sem depender de workers externos.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- Constantes & helpers
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION mpp_level_for_xp(xp integer)
RETURNS integer
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT CASE
    WHEN xp >= 3500 THEN 7
    WHEN xp >= 2000 THEN 6
    WHEN xp >= 1000 THEN 5
    WHEN xp >= 500  THEN 4
    WHEN xp >= 250  THEN 3
    WHEN xp >= 100  THEN 2
    ELSE 1
  END;
$$;

-- ----------------------------------------------------------------------------
-- daily_close_user: fecha o snapshot do dia para um usuário específico
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION daily_close_user(p_user_id uuid, p_date date DEFAULT NULL)
RETURNS jsonb
LANGUAGE plpgsql
AS $$
DECLARE
  v_date              date := COALESCE(p_date, CURRENT_DATE);
  v_snap              daily_snapshots%ROWTYPE;
  v_progress          user_progress%ROWTYPE;
  v_yesterday         date;
  v_continues_streak  boolean;
  v_new_streak        smallint;
  v_new_xp_total      integer;
  v_new_level         smallint;
  v_new_deficit       integer;
  v_new_total_deficit integer;
  v_blocks_delta      smallint;
  v_new_blocks        smallint;
  v_new_deficit_block integer;
  v_new_badges        text[];
BEGIN
  SELECT * INTO v_snap
  FROM daily_snapshots
  WHERE user_id = p_user_id AND date = v_date;

  IF NOT FOUND THEN
    -- cria snapshot vazio para garantir cron funcione mesmo sem refeições
    INSERT INTO daily_snapshots(user_id, date)
    VALUES (p_user_id, v_date)
    RETURNING * INTO v_snap;
  END IF;

  IF v_snap.day_closed THEN
    RETURN jsonb_build_object('skipped', true, 'reason', 'already_closed');
  END IF;

  SELECT * INTO v_progress FROM user_progress WHERE user_id = p_user_id;
  IF NOT FOUND THEN
    INSERT INTO user_progress(user_id) VALUES (p_user_id) RETURNING * INTO v_progress;
  END IF;

  v_yesterday := v_date - INTERVAL '1 day';
  v_continues_streak := v_progress.last_active_date IS NOT NULL
    AND v_progress.last_active_date = v_yesterday;
  v_new_streak := CASE WHEN v_continues_streak THEN v_progress.current_streak + 1 ELSE 1 END;

  v_new_xp_total := v_progress.xp_total + COALESCE(v_snap.xp_earned, 0);
  v_new_level := mpp_level_for_xp(v_new_xp_total);

  v_new_deficit := GREATEST(0, COALESCE(-v_snap.daily_balance, 0));
  v_new_total_deficit := v_progress.deficit_block + v_new_deficit;
  v_blocks_delta := (v_new_total_deficit / 7700)::smallint;
  v_new_blocks := v_progress.blocks_completed + v_blocks_delta;
  v_new_deficit_block := v_new_total_deficit % 7700;

  -- Badges
  v_new_badges := v_progress.badges_earned;
  IF v_new_streak >= 7 AND NOT ('Primeira Semana' = ANY(v_new_badges)) THEN
    v_new_badges := array_append(v_new_badges, 'Primeira Semana');
  END IF;
  IF v_new_streak >= 30 AND NOT ('Mês de Ferro' = ANY(v_new_badges)) THEN
    v_new_badges := array_append(v_new_badges, 'Mês de Ferro');
  END IF;
  IF v_new_streak >= 90 AND NOT ('Atleta Real' = ANY(v_new_badges)) THEN
    v_new_badges := array_append(v_new_badges, 'Atleta Real');
  END IF;
  IF v_new_blocks >= 1 AND NOT ('Primeiro Bloco' = ANY(v_new_badges)) THEN
    v_new_badges := array_append(v_new_badges, 'Primeiro Bloco');
  END IF;
  IF v_new_xp_total >= 1000 AND NOT ('XP Master' = ANY(v_new_badges)) THEN
    v_new_badges := array_append(v_new_badges, 'XP Master');
  END IF;
  IF v_new_xp_total >= 3500 AND NOT ('Elite' = ANY(v_new_badges)) THEN
    v_new_badges := array_append(v_new_badges, 'Elite');
  END IF;

  -- Update user_progress
  UPDATE user_progress
  SET xp_total          = v_new_xp_total,
      level             = v_new_level,
      current_streak    = v_new_streak,
      longest_streak    = GREATEST(longest_streak, v_new_streak),
      blocks_completed  = v_new_blocks,
      deficit_block     = v_new_deficit_block,
      badges_earned     = v_new_badges,
      last_active_date  = v_date,
      updated_at        = now()
  WHERE user_id = p_user_id;

  -- Marca snapshot como fechado
  UPDATE daily_snapshots
  SET day_closed       = true,
      closed_at        = now(),
      deficit_accumulated = v_new_total_deficit,
      updated_at       = now()
  WHERE id = v_snap.id;

  RETURN jsonb_build_object(
    'user_id', p_user_id,
    'date', v_date,
    'xp_total', v_new_xp_total,
    'level', v_new_level,
    'streak', v_new_streak,
    'blocks_completed', v_new_blocks,
    'deficit_block', v_new_deficit_block,
    'blocks_completed_today', v_blocks_delta,
    'badges', v_new_badges,
    'daily_balance', v_snap.daily_balance
  );
END;
$$;

COMMENT ON FUNCTION daily_close_user IS
  'Fecha o snapshot do dia para um usuário e atualiza user_progress (XP, level, streak, blocks, badges).';

-- ----------------------------------------------------------------------------
-- daily_close_all: para todos os usuários ativos com snapshot do dia anterior
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION daily_close_all(p_date date DEFAULT NULL)
RETURNS jsonb
LANGUAGE plpgsql
AS $$
DECLARE
  v_date date := COALESCE(p_date, CURRENT_DATE - INTERVAL '1 day');
  v_user record;
  v_count integer := 0;
  v_results jsonb := '[]'::jsonb;
BEGIN
  FOR v_user IN
    SELECT u.id
    FROM users u
    WHERE u.status = 'active'
      AND EXISTS (
        SELECT 1 FROM daily_snapshots ds
        WHERE ds.user_id = u.id
          AND ds.date = v_date
          AND ds.day_closed = false
      )
  LOOP
    BEGIN
      v_results := v_results || daily_close_user(v_user.id, v_date);
      v_count := v_count + 1;
    EXCEPTION WHEN OTHERS THEN
      v_results := v_results || jsonb_build_object('user_id', v_user.id, 'error', SQLERRM);
    END;
  END LOOP;

  RETURN jsonb_build_object('date', v_date, 'closed', v_count, 'details', v_results);
END;
$$;

COMMENT ON FUNCTION daily_close_all IS
  'Fecha todos os snapshots não-fechados do dia indicado (default: ontem).';

GRANT EXECUTE ON FUNCTION daily_close_user TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION daily_close_all TO authenticated, service_role;

-- ----------------------------------------------------------------------------
-- engagement_eligible_users: lista usuários elegíveis para engagement
-- ----------------------------------------------------------------------------
-- Critério: ativos, com onboarding completo, sem msg in nas últimas X horas
-- e dentro da janela de horário local apropriada.
CREATE OR REPLACE FUNCTION engagement_eligible_users(
  p_quiet_hours_min integer DEFAULT 4,
  p_window_label text DEFAULT 'manha'
)
RETURNS TABLE (
  user_id uuid,
  wpp text,
  name text,
  timezone text,
  current_protocol protocol_enum,
  hours_since_last_in numeric
)
LANGUAGE sql
STABLE
AS $$
  SELECT
    u.id,
    u.wpp,
    u.name,
    u.timezone,
    p.current_protocol,
    EXTRACT(epoch FROM (now() - COALESCE(
      (SELECT MAX(created_at) FROM messages m
       WHERE m.user_id = u.id AND m.direction = 'in'),
      u.created_at
    )))/3600 AS hours_since_last_in
  FROM users u
  LEFT JOIN user_profiles p ON p.user_id = u.id
  WHERE u.status = 'active'
    AND p.onboarding_completed = true
    AND NOT EXISTS (
      SELECT 1 FROM messages m
      WHERE m.user_id = u.id
        AND m.direction = 'in'
        AND m.created_at > now() - (p_quiet_hours_min || ' hours')::interval
    );
$$;

COMMENT ON FUNCTION engagement_eligible_users IS
  'Lista usuários elegíveis a receber mensagem proativa (engagement).';

GRANT EXECUTE ON FUNCTION engagement_eligible_users TO authenticated, service_role;

-- ----------------------------------------------------------------------------
-- pg_cron schedules
-- ----------------------------------------------------------------------------
-- Daily closer: 00:30, 01:30, 02:30, 03:30 UTC (cobre múltiplos timezones BR)
SELECT cron.schedule(
  'daily-closer-0030',
  '30 0 * * *',
  $$ SELECT daily_close_all(); $$
);
SELECT cron.schedule(
  'daily-closer-0130',
  '30 1 * * *',
  $$ SELECT daily_close_all(); $$
);
SELECT cron.schedule(
  'daily-closer-0230',
  '30 2 * * *',
  $$ SELECT daily_close_all(); $$
);
SELECT cron.schedule(
  'daily-closer-0330',
  '30 3 * * *',
  $$ SELECT daily_close_all(); $$
);

-- Cleanup
SELECT cron.schedule(
  'cleanup-processed-messages',
  '0 4 * * *',
  $$ DELETE FROM processed_messages WHERE processed_at < now() - interval '30 days'; $$
);
