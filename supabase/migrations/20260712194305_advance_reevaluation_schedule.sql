-- Advances the 14-day reevaluation schedule and emits the due event in the
-- same transaction. A retry sees the advanced date and cannot duplicate it.

CREATE OR REPLACE FUNCTION public.advance_reevaluation_schedule(
  p_user_id uuid,
  p_closing_date date
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_next date;
  v_due date;
  v_first_snapshot date;
  v_bootstrapped boolean := false;
BEGIN
  IF p_user_id IS NULL OR p_closing_date IS NULL THEN
    RAISE EXCEPTION 'user and closing date are required';
  END IF;

  SELECT progress.next_reevaluation
  INTO v_next
  FROM public.user_progress AS progress
  WHERE progress.user_id = p_user_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'user progress not found';
  END IF;

  IF v_next IS NULL THEN
    SELECT min(snapshot.date)
    INTO v_first_snapshot
    FROM public.daily_snapshots AS snapshot
    WHERE snapshot.user_id = p_user_id;

    IF v_first_snapshot IS NULL THEN
      RETURN jsonb_build_object(
        'status', 'no_snapshot',
        'next_reevaluation', NULL
      );
    END IF;

    v_next := v_first_snapshot + 14;
    v_bootstrapped := true;

    IF p_closing_date < v_next THEN
      UPDATE public.user_progress
      SET next_reevaluation = v_next,
          updated_at = now()
      WHERE user_id = p_user_id;

      RETURN jsonb_build_object(
        'status', 'bootstrapped',
        'next_reevaluation', v_next
      );
    END IF;
  END IF;

  IF p_closing_date < v_next THEN
    RETURN jsonb_build_object(
      'status', 'not_due',
      'next_reevaluation', v_next
    );
  END IF;

  v_due := v_next;
  LOOP
    v_next := v_next + 14;
    EXIT WHEN v_next > p_closing_date;
  END LOOP;

  INSERT INTO public.product_events (user_id, event, properties)
  VALUES (
    p_user_id,
    'reevaluation.due',
    jsonb_build_object(
      'due_date', v_due,
      'closing_date', p_closing_date,
      'next_reevaluation', v_next,
      'bootstrapped', v_bootstrapped
    )
  );

  UPDATE public.user_progress
  SET next_reevaluation = v_next,
      updated_at = now()
  WHERE user_id = p_user_id;

  RETURN jsonb_build_object(
    'status', 'due',
    'due_date', v_due,
    'next_reevaluation', v_next
  );
END;
$$;
