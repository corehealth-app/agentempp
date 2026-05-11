-- ============================================================================
-- Bloco 7700: inclui design_deficit do protocolo (não só extras vs target)
-- ============================================================================
-- Roberto observou (2026-05-09): "só somou as calorias que sobraram de ontem,
-- não adicionou as 500 kcal do déficit".
--
-- Bug conceitual: a fórmula antiga calculava bloco_progress = max(0, -balance)
-- onde balance = consumed - target - exercise. Pra paciente on-plan
-- (consumed = target, exercise = 0), balance = 0, bloco progress = 0.
--
-- Mas o target em recomp JÁ é meta com déficit embutido (BMR×1.2 - X kcal).
-- Quando o paciente come o target, ele atinge déficit X vs maintenance.
-- O bloco 7700 representa progresso REAL ("≈ 1 kg gordura"), então deveria
-- acumular X/dia mesmo on-plan.
--
-- Fix: para recomposicao, soma o deficit_level designado + qualquer balance
-- adicional. Outros protocolos não usam bloco 7700.
-- ============================================================================

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
  -- NOVOS: pra calcular design_deficit
  v_protocol          text;
  v_deficit_level     integer;
  v_design_deficit    integer;
BEGIN
  SELECT * INTO v_snap
  FROM daily_snapshots
  WHERE user_id = p_user_id AND date = v_date;

  IF NOT FOUND THEN
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

  -- NOVO: pega protocol + deficit_level do profile pra calcular design_deficit
  SELECT current_protocol, deficit_level
    INTO v_protocol, v_deficit_level
    FROM user_profiles WHERE user_id = p_user_id;

  -- Design deficit (kcal/dia que o método tá programando):
  -- - recomp: deficit_level salvo (400/500/600 conforme fome) ou snapshot
  -- - outros: 0 (não usam bloco 7700)
  v_design_deficit := CASE
    WHEN v_protocol = 'recomposicao' THEN COALESCE(v_deficit_level, 500)
    ELSE 0
  END;

  -- Bloco 7700 progress = design_deficit + extras_realized
  -- extras_realized = -balance (se positivo). Negativo = ate além do target
  -- e queima o design deficit em parte.
  v_new_deficit := GREATEST(0, v_design_deficit + COALESCE(-v_snap.daily_balance, 0));
  v_new_total_deficit := v_progress.deficit_block + v_new_deficit;
  v_blocks_delta := (v_new_total_deficit / 7700)::smallint;
  v_new_blocks := v_progress.blocks_completed + v_blocks_delta;
  v_new_deficit_block := v_new_total_deficit % 7700;

  -- Badges (mesmo do antes)
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

  UPDATE user_progress SET
    xp_total = v_new_xp_total,
    level = v_new_level,
    current_streak = v_new_streak,
    longest_streak = GREATEST(longest_streak, v_new_streak),
    deficit_block = v_new_deficit_block,
    blocks_completed = v_new_blocks,
    badges_earned = v_new_badges,
    last_active_date = v_date,
    updated_at = NOW()
  WHERE user_id = p_user_id;

  UPDATE daily_snapshots SET
    day_closed = true,
    closed_at = NOW(),
    deficit_accumulated = v_new_deficit_block
  WHERE id = v_snap.id;

  RETURN jsonb_build_object(
    'success', true,
    'xp_earned', COALESCE(v_snap.xp_earned, 0),
    'xp_total', v_new_xp_total,
    'level', v_new_level,
    'streak', v_new_streak,
    'deficit_block', v_new_deficit_block,
    'blocks_completed', v_new_blocks,
    'design_deficit', v_design_deficit,
    'daily_balance', v_snap.daily_balance
  );
END;
$$;

COMMENT ON FUNCTION daily_close_user IS
  'Fecha snapshot do dia + atualiza user_progress. Bloco 7700 agora inclui design_deficit do protocolo recomp (400/500/600 conforme fome) — antes só somava extras vs target.';
