-- Per-user curated phrase rotation with an atomic claim. The application
-- filters candidates by food, tags and meal compatibility; this function
-- serializes the final user-specific choice and records its use.

ALTER TABLE public.food_education_phrases
  ADD COLUMN allowed_meal_types public.meal_type_enum[];

COMMENT ON COLUMN public.food_education_phrases.allowed_meal_types IS
  'Optional explicit meal slots. NULL/empty keeps defensive text compatibility for legacy rows.';

DROP FUNCTION IF EXISTS public.match_food_phrases(vector, double precision, integer, text);

CREATE FUNCTION public.match_food_phrases(
  query_embedding vector(1024),
  match_threshold double precision,
  match_count integer,
  match_language text DEFAULT 'pt-BR'
)
RETURNS TABLE (
  id uuid,
  phrase text,
  tags jsonb,
  allowed_meal_types public.meal_type_enum[],
  usage_count integer,
  last_used_at timestamptz,
  similarity double precision
)
LANGUAGE sql
STABLE
SECURITY INVOKER
SET search_path = public, pg_temp
AS $$
  WITH params AS (
    SELECT greatest(coalesce(match_count, 1), 1) AS requested_count
  ),
  candidates AS MATERIALIZED (
    SELECT
      food.id,
      food.phrase,
      food.tags,
      food.allowed_meal_types,
      food.usage_count,
      food.last_used_at,
      1 - (food.food_name_embedding <=> query_embedding) AS similarity
    FROM public.food_education_phrases AS food
    WHERE food.active = true
      AND food.language = match_language
      AND food.food_name_embedding IS NOT NULL
      AND food.polaridade IS NOT NULL
    ORDER BY food.food_name_embedding <=> query_embedding ASC
    LIMIT (SELECT greatest(requested_count * 5, 50) FROM params)
  )
  SELECT
    candidate.id,
    candidate.phrase,
    candidate.tags,
    candidate.allowed_meal_types,
    candidate.usage_count,
    candidate.last_used_at,
    candidate.similarity
  FROM candidates AS candidate
  WHERE candidate.similarity > match_threshold
  ORDER BY candidate.last_used_at ASC NULLS FIRST,
           candidate.similarity DESC,
           candidate.id ASC
  LIMIT (SELECT requested_count FROM params);
$$;

CREATE FUNCTION public.claim_food_education_phrase(
  user_id uuid,
  phrase_ids uuid[],
  cooldown_days integer DEFAULT 7
)
RETURNS TABLE (
  phrase_id uuid,
  usage_count integer,
  last_used_at timestamptz,
  cooldown_count integer,
  selected_after_cooldown boolean,
  exhausted boolean
)
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = public, pg_temp
AS $$
DECLARE
  p_user_id ALIAS FOR $1;
  p_phrase_ids ALIAS FOR $2;
  p_cooldown_days ALIAS FOR $3;
  v_now timestamptz := clock_timestamp();
  v_cutoff timestamptz;
  v_candidate_count integer := 0;
  v_cooldown_count integer := 0;
  v_picked_id uuid;
  v_last_phrase_id uuid;
  v_usage_count integer;
  v_last_used_at timestamptz;
  v_exhausted boolean := false;
BEGIN
  IF p_user_id IS NULL THEN
    RAISE EXCEPTION 'user_id is required';
  END IF;
  IF p_phrase_ids IS NULL OR cardinality(p_phrase_ids) = 0 THEN
    RAISE EXCEPTION 'phrase_ids must contain at least one phrase';
  END IF;
  IF p_cooldown_days IS NULL OR p_cooldown_days < 1 OR p_cooldown_days > 365 THEN
    RAISE EXCEPTION 'cooldown_days must be between 1 and 365';
  END IF;

  PERFORM pg_advisory_xact_lock(hashtextextended(p_user_id::text || ':food-education', 0));
  v_now := clock_timestamp();
  v_cutoff := v_now - make_interval(days => p_cooldown_days);

  SELECT
    count(*)::integer,
    count(*) FILTER (WHERE cooldown.last_seen_at >= v_cutoff)::integer
  INTO v_candidate_count, v_cooldown_count
  FROM public.food_education_phrases AS phrase
  LEFT JOIN public.user_phrase_cooldown AS cooldown
    ON cooldown.user_id = p_user_id
   AND cooldown.phrase_table = 'food'
   AND cooldown.phrase_id = phrase.id
  WHERE phrase.id = ANY(p_phrase_ids)
    AND phrase.active = true;

  IF v_candidate_count = 0 THEN
    RETURN;
  END IF;

  SELECT phrase.id
  INTO v_picked_id
  FROM public.food_education_phrases AS phrase
  LEFT JOIN public.user_phrase_cooldown AS cooldown
    ON cooldown.user_id = p_user_id
   AND cooldown.phrase_table = 'food'
   AND cooldown.phrase_id = phrase.id
  WHERE phrase.id = ANY(p_phrase_ids)
    AND phrase.active = true
    AND (cooldown.last_seen_at IS NULL OR cooldown.last_seen_at < v_cutoff)
  ORDER BY (cooldown.last_seen_at IS NULL) DESC,
           cooldown.last_seen_at ASC NULLS FIRST,
           phrase.last_used_at ASC NULLS FIRST,
           phrase.usage_count ASC,
           phrase.id ASC
  LIMIT 1;

  IF v_picked_id IS NULL THEN
    v_exhausted := true;

    SELECT cooldown.phrase_id
    INTO v_last_phrase_id
    FROM public.user_phrase_cooldown AS cooldown
    JOIN public.food_education_phrases AS phrase ON phrase.id = cooldown.phrase_id
    WHERE cooldown.user_id = p_user_id
      AND cooldown.phrase_table = 'food'
      AND phrase.id = ANY(p_phrase_ids)
      AND phrase.active = true
    ORDER BY cooldown.last_seen_at DESC, cooldown.phrase_id DESC
    LIMIT 1;

    SELECT phrase.id
    INTO v_picked_id
    FROM public.food_education_phrases AS phrase
    JOIN public.user_phrase_cooldown AS cooldown
      ON cooldown.user_id = p_user_id
     AND cooldown.phrase_table = 'food'
     AND cooldown.phrase_id = phrase.id
    WHERE phrase.id = ANY(p_phrase_ids)
      AND phrase.active = true
      AND (v_candidate_count = 1 OR phrase.id <> v_last_phrase_id)
    ORDER BY cooldown.last_seen_at ASC,
             phrase.usage_count ASC,
             phrase.id ASC
    LIMIT 1;
  END IF;

  IF v_picked_id IS NULL THEN
    RETURN;
  END IF;

  UPDATE public.food_education_phrases AS phrase
  SET usage_count = phrase.usage_count + 1,
      last_used_at = v_now
  WHERE phrase.id = v_picked_id
  RETURNING phrase.usage_count, phrase.last_used_at
  INTO v_usage_count, v_last_used_at;

  INSERT INTO public.user_phrase_cooldown (
    user_id,
    phrase_table,
    phrase_id,
    last_seen_at
  ) VALUES (
    p_user_id,
    'food',
    v_picked_id,
    v_now
  )
  ON CONFLICT ON CONSTRAINT user_phrase_cooldown_pkey DO UPDATE
  SET last_seen_at = EXCLUDED.last_seen_at;

  RETURN QUERY SELECT
    v_picked_id,
    v_usage_count,
    v_last_used_at,
    v_cooldown_count,
    (NOT v_exhausted AND v_cooldown_count > 0),
    v_exhausted;
END;
$$;

REVOKE ALL ON FUNCTION public.claim_food_education_phrase(uuid, uuid[], integer)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.claim_food_education_phrase(uuid, uuid[], integer)
  TO service_role;

-- Keep semantic phrase lookup internal to the application as well.
REVOKE ALL ON FUNCTION public.match_food_phrases(vector, double precision, integer, text)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.match_food_phrases(vector, double precision, integer, text)
  TO service_role;

UPDATE public.food_education_phrases
SET active = false
WHERE curated_by = 'seed_exemplo'
  AND food_canonical_name = 'leite com whey';

UPDATE public.food_education_phrases
SET active = false
WHERE phrase ILIKE '%porre estratégico%';

INSERT INTO public.food_education_phrases (
  food_canonical_name,
  phrase,
  tags,
  language,
  curated_by,
  active,
  bloco_id,
  polaridade,
  allowed_meal_types
) VALUES
  ('leite com whey', 'Leite com whey deixa a refeição prática e ajuda a compor o aporte de proteína do dia.', '{}'::jsonb, 'pt-BR', 'system_whey_v2_2026_07_13', true, 'edu_leite_whey_v2', 'bom', ARRAY['cafe','almoco','lanche','jantar','ceia','outro']::public.meal_type_enum[]),
  ('leite com whey', 'A combinação de leite com whey acrescenta proteína de forma simples à refeição.', '{}'::jsonb, 'pt-BR', 'system_whey_v2_2026_07_13', true, 'edu_leite_whey_v2', 'bom', ARRAY['cafe','almoco','lanche','jantar','ceia','outro']::public.meal_type_enum[]),
  ('leite com whey', 'Leite com whey é uma opção prática para distribuir melhor a proteína entre as refeições.', '{}'::jsonb, 'pt-BR', 'system_whey_v2_2026_07_13', true, 'edu_leite_whey_v2', 'bom', ARRAY['cafe','almoco','lanche','jantar','ceia','outro']::public.meal_type_enum[]),
  ('leite com whey', 'Ao incluir leite com whey, você reforça a proteína da refeição sem complicar a rotina.', '{}'::jsonb, 'pt-BR', 'system_whey_v2_2026_07_13', true, 'edu_leite_whey_v2', 'bom', ARRAY['cafe','almoco','lanche','jantar','ceia','outro']::public.meal_type_enum[]),
  ('leite com whey', 'Leite com whey combina praticidade com um aporte relevante de proteína.', '{}'::jsonb, 'pt-BR', 'system_whey_v2_2026_07_13', true, 'edu_leite_whey_v2', 'bom', ARRAY['cafe','almoco','lanche','jantar','ceia','outro']::public.meal_type_enum[]),
  ('leite com whey', 'Essa porção de leite com whey ajuda a manter a refeição mais estruturada.', '{}'::jsonb, 'pt-BR', 'system_whey_v2_2026_07_13', true, 'edu_leite_whey_v2', 'bom', ARRAY['cafe','almoco','lanche','jantar','ceia','outro']::public.meal_type_enum[]),
  ('leite com whey', 'Leite com whey pode facilitar a constância quando a rotina está corrida.', '{}'::jsonb, 'pt-BR', 'system_whey_v2_2026_07_13', true, 'edu_leite_whey_v2', 'bom', ARRAY['cafe','almoco','lanche','jantar','ceia','outro']::public.meal_type_enum[]),
  ('leite com whey', 'Manter leite com whey na rotina é uma forma simples de organizar o aporte proteico.', '{}'::jsonb, 'pt-BR', 'system_whey_v2_2026_07_13', true, 'edu_leite_whey_v2', 'bom', ARRAY['cafe','almoco','lanche','jantar','ceia','outro']::public.meal_type_enum[]),
  ('whey protein', 'Whey protein é uma forma prática de complementar a proteína da refeição.', '{}'::jsonb, 'pt-BR', 'system_whey_v2_2026_07_13', true, 'edu_whey_protein_v2', 'bom', ARRAY['cafe','almoco','lanche','jantar','ceia','outro']::public.meal_type_enum[]),
  ('whey protein', 'Ao incluir whey protein, você deixa o aporte proteico mais fácil de organizar.', '{}'::jsonb, 'pt-BR', 'system_whey_v2_2026_07_13', true, 'edu_whey_protein_v2', 'bom', ARRAY['cafe','almoco','lanche','jantar','ceia','outro']::public.meal_type_enum[]),
  ('whey protein', 'Whey protein pode ajudar a distribuir a proteína ao longo das refeições.', '{}'::jsonb, 'pt-BR', 'system_whey_v2_2026_07_13', true, 'edu_whey_protein_v2', 'bom', ARRAY['cafe','almoco','lanche','jantar','ceia','outro']::public.meal_type_enum[]),
  ('whey protein', 'Essa porção de whey protein reforça a estrutura proteica da refeição.', '{}'::jsonb, 'pt-BR', 'system_whey_v2_2026_07_13', true, 'edu_whey_protein_v2', 'bom', ARRAY['cafe','almoco','lanche','jantar','ceia','outro']::public.meal_type_enum[]),
  ('whey protein', 'Whey protein combina praticidade com uma dose concentrada de proteína.', '{}'::jsonb, 'pt-BR', 'system_whey_v2_2026_07_13', true, 'edu_whey_protein_v2', 'bom', ARRAY['cafe','almoco','lanche','jantar','ceia','outro']::public.meal_type_enum[]),
  ('whey protein', 'Usar whey protein pode simplificar a rotina nos dias mais corridos.', '{}'::jsonb, 'pt-BR', 'system_whey_v2_2026_07_13', true, 'edu_whey_protein_v2', 'bom', ARRAY['cafe','almoco','lanche','jantar','ceia','outro']::public.meal_type_enum[]),
  ('whey protein', 'Whey protein é uma alternativa simples quando a refeição precisa de mais proteína.', '{}'::jsonb, 'pt-BR', 'system_whey_v2_2026_07_13', true, 'edu_whey_protein_v2', 'bom', ARRAY['cafe','almoco','lanche','jantar','ceia','outro']::public.meal_type_enum[]),
  ('whey protein', 'A presença do whey protein torna mais direto completar o aporte proteico da refeição.', '{}'::jsonb, 'pt-BR', 'system_whey_v2_2026_07_13', true, 'edu_whey_protein_v2', 'bom', ARRAY['cafe','almoco','lanche','jantar','ceia','outro']::public.meal_type_enum[])
ON CONFLICT DO NOTHING;
