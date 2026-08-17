ALTER TABLE public.message_buffer
  ADD COLUMN IF NOT EXISTS media_extension_count smallint NOT NULL DEFAULT 0;

DO $constraints$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_constraint
    WHERE conname = 'message_buffer_media_extension_count_check'
      AND conrelid = 'public.message_buffer'::regclass
  ) THEN
    ALTER TABLE public.message_buffer
      ADD CONSTRAINT message_buffer_media_extension_count_check
      CHECK (media_extension_count BETWEEN 0 AND 1);
  END IF;
END;
$constraints$;

CREATE OR REPLACE FUNCTION public.extend_message_buffer_once(
  p_user_id uuid,
  p_new_flush_after timestamptz
) RETURNS boolean
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_extended boolean := false;
BEGIN
  IF p_user_id IS NULL OR p_new_flush_after IS NULL THEN
    RAISE EXCEPTION 'user id and flush timestamp are required';
  END IF;

  UPDATE public.message_buffer
  SET
    flush_after = GREATEST(flush_after, p_new_flush_after),
    media_extension_count = 1
  WHERE user_id = p_user_id
    AND media_extension_count = 0
  RETURNING true INTO v_extended;

  RETURN COALESCE(v_extended, false);
END;
$$;
