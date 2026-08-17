BEGIN;

DO $test$
DECLARE
  v_user_id uuid := '00000000-0000-0000-0000-000000000113';
  v_phrase_ids uuid[] := ARRAY[
    '00000000-0000-0000-0000-000000000201'::uuid,
    '00000000-0000-0000-0000-000000000202'::uuid,
    '00000000-0000-0000-0000-000000000203'::uuid,
    '00000000-0000-0000-0000-000000000204'::uuid,
    '00000000-0000-0000-0000-000000000205'::uuid,
    '00000000-0000-0000-0000-000000000206'::uuid,
    '00000000-0000-0000-0000-000000000207'::uuid,
    '00000000-0000-0000-0000-000000000208'::uuid
  ];
  v_seen uuid[] := ARRAY[]::uuid[];
  v_claim record;
  v_index integer;
  v_total_usage integer;
  v_cooldown_rows integer;
  v_security_definer boolean;
BEGIN
  INSERT INTO public.users (id, wpp, name)
  VALUES (v_user_id, '17777777777', 'food-phrase-claim-test')
  ON CONFLICT (id) DO NOTHING;

  INSERT INTO public.food_education_phrases (
    id,
    food_canonical_name,
    phrase,
    tags,
    language,
    curated_by,
    active,
    bloco_id,
    polaridade,
    allowed_meal_types
  )
  SELECT
    v_phrase_ids[series.number],
    'whey claim test',
    format('Frase de rotação %s.', series.number),
    '{}'::jsonb,
    'pt-BR',
    'sql_test',
    true,
    'sql_test_claim',
    'bom',
    ARRAY['cafe', 'lanche']::public.meal_type_enum[]
  FROM generate_series(1, 8) AS series(number);

  FOR v_index IN 1..9 LOOP
    SELECT *
    INTO STRICT v_claim
    FROM public.claim_food_education_phrase(v_user_id, v_phrase_ids, 7);

    IF v_index <= 8 THEN
      IF v_claim.exhausted THEN
        RAISE EXCEPTION 'claim % exhausted before catalog was consumed', v_index;
      END IF;
      IF v_claim.phrase_id = ANY(v_seen) THEN
        RAISE EXCEPTION 'claim % repeated phrase % before exhaustion', v_index, v_claim.phrase_id;
      END IF;
      IF v_claim.cooldown_count <> v_index - 1 THEN
        RAISE EXCEPTION 'claim % returned cooldown_count %, expected %',
          v_index, v_claim.cooldown_count, v_index - 1;
      END IF;
      v_seen := array_append(v_seen, v_claim.phrase_id);
    ELSE
      IF NOT v_claim.exhausted THEN
        RAISE EXCEPTION 'ninth claim did not report exhaustion';
      END IF;
      IF v_claim.phrase_id <> v_seen[1] THEN
        RAISE EXCEPTION 'ninth claim selected %, expected least recent %',
          v_claim.phrase_id, v_seen[1];
      END IF;
      IF v_claim.phrase_id = v_seen[8] THEN
        RAISE EXCEPTION 'ninth claim repeated the immediately previous phrase';
      END IF;
    END IF;
  END LOOP;

  SELECT sum(phrase.usage_count)::integer
  INTO v_total_usage
  FROM public.food_education_phrases AS phrase
  WHERE phrase.id = ANY(v_phrase_ids);

  SELECT count(*)::integer
  INTO v_cooldown_rows
  FROM public.user_phrase_cooldown AS cooldown
  WHERE cooldown.user_id = v_user_id
    AND cooldown.phrase_table = 'food'
    AND cooldown.phrase_id = ANY(v_phrase_ids);

  IF v_total_usage <> 9 OR v_cooldown_rows <> 8 THEN
    RAISE EXCEPTION 'claim writes were not atomic: usage %, cooldown rows %',
      v_total_usage, v_cooldown_rows;
  END IF;

  SELECT procedure.prosecdef
  INTO v_security_definer
  FROM pg_proc AS procedure
  WHERE procedure.oid = 'public.claim_food_education_phrase(uuid,uuid[],integer)'::regprocedure;

  IF v_security_definer THEN
    RAISE EXCEPTION 'claim_food_education_phrase must remain SECURITY INVOKER';
  END IF;
  IF has_function_privilege(
    'anon',
    'public.claim_food_education_phrase(uuid,uuid[],integer)',
    'EXECUTE'
  ) OR has_function_privilege(
    'authenticated',
    'public.claim_food_education_phrase(uuid,uuid[],integer)',
    'EXECUTE'
  ) THEN
    RAISE EXCEPTION 'public API roles can execute internal phrase claim';
  END IF;
  IF NOT has_function_privilege(
    'service_role',
    'public.claim_food_education_phrase(uuid,uuid[],integer)',
    'EXECUTE'
  ) THEN
    RAISE EXCEPTION 'service_role cannot execute internal phrase claim';
  END IF;
END;
$test$;

ROLLBACK;
