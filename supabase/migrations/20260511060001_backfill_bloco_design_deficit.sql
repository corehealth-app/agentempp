-- Backfill retroativo do deficit_block usando nova fórmula (design + extras).
-- Roda 1x. Pra cada paciente, percorre todos os snapshots fechados em ordem
-- e re-aplica o cálculo correto. Adiciona badge "Primeiro Bloco" quando blocks≥1.

DO $$
DECLARE
  v_user RECORD;
  v_snap RECORD;
  v_protocol text;
  v_deficit_level integer;
  v_design integer;
  v_total_deficit integer;
  v_blocks integer;
  v_remainder integer;
  v_daily_inc integer;
BEGIN
  FOR v_user IN
    SELECT id AS user_id, name FROM users WHERE status = 'active'
  LOOP
    SELECT current_protocol, deficit_level
      INTO v_protocol, v_deficit_level
      FROM user_profiles WHERE user_id = v_user.user_id;

    v_design := CASE
      WHEN v_protocol = 'recomposicao' THEN COALESCE(v_deficit_level, 500)
      ELSE 0
    END;

    v_total_deficit := 0;
    FOR v_snap IN
      SELECT daily_balance
        FROM daily_snapshots
        WHERE user_id = v_user.user_id AND day_closed = true
        ORDER BY date
    LOOP
      v_daily_inc := GREATEST(0, v_design + COALESCE(-v_snap.daily_balance, 0));
      v_total_deficit := v_total_deficit + v_daily_inc;
    END LOOP;

    v_blocks := v_total_deficit / 7700;
    v_remainder := v_total_deficit % 7700;

    UPDATE user_progress SET
      deficit_block = v_remainder,
      blocks_completed = v_blocks,
      badges_earned = CASE
        WHEN v_blocks >= 1 AND NOT ('Primeiro Bloco' = ANY(badges_earned))
          THEN array_append(badges_earned, 'Primeiro Bloco')
        ELSE badges_earned
      END,
      updated_at = NOW()
    WHERE user_id = v_user.user_id;

    RAISE NOTICE 'BACKFILL: user=% (%) proto=% design=% total_deficit=% blocks=% remainder=%',
      v_user.name, v_user.user_id, v_protocol, v_design, v_total_deficit, v_blocks, v_remainder;
  END LOOP;
END;
$$;
