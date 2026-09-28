-- Synthetic legacy data written with the pre-M1 schema and the pre-M1
-- writers. LOCAL REHEARSAL ONLY. Never run against a remote database.
-- Every name, phone and value is synthetic.
-- A = 00000000-0000-0000-0000-00000000ea01, B = 00000000-0000-0000-0000-00000000eb01
\set ON_ERROR_STOP on
BEGIN;

INSERT INTO public.users (id, wpp, name) VALUES
  ('00000000-0000-0000-0000-00000000ea01', '5500000000001', 'Rehearsal A'),
  ('00000000-0000-0000-0000-00000000eb01', '5500000000002', 'Rehearsal B');

-- Legacy weight writer: weight_kg written directly, no instant exists yet.
INSERT INTO public.user_profiles (user_id, weight_kg) VALUES
  ('00000000-0000-0000-0000-00000000ea01', 82.4),
  ('00000000-0000-0000-0000-00000000eb01', NULL);

-- Every media kind that exists before M3, in several statuses, so the
-- constraints M3 drops and recreates are checked against real legacy rows.
INSERT INTO public.media_assets (
  id, user_id, kind, bucket_id, object_path, mime_type, declared_size_bytes,
  actual_size_bytes, status, processing_request_id, source_request_hash,
  retention_until, uploaded_at, processed_at
) VALUES
  ('00000000-0000-0000-0000-00000000aa01', '00000000-0000-0000-0000-00000000ea01', 'meal_photo', 'meal-photos',
   '00000000-0000-0000-0000-00000000ea01/00000000-0000-0000-0000-00000000aa01.jpg', 'image/jpeg', 204800,
   204800, 'processed', repeat('a', 64), repeat('1', 64), now() + interval '30 days', now(), now()),
  ('00000000-0000-0000-0000-00000000aa02', '00000000-0000-0000-0000-00000000ea01', 'audio_note', 'audio-notes',
   '00000000-0000-0000-0000-00000000ea01/00000000-0000-0000-0000-00000000aa02.m4a', 'audio/mp4', 512000,
   512000, 'uploaded', NULL, repeat('2', 64), now() + interval '30 days', now(), NULL),
  ('00000000-0000-0000-0000-00000000aa03', '00000000-0000-0000-0000-00000000ea01', 'body_checkin_photo', 'body-checkin-photos',
   '00000000-0000-0000-0000-00000000ea01/00000000-0000-0000-0000-00000000aa03.heic', 'image/heic', 1048576,
   NULL, 'pending_upload', NULL, repeat('3', 64), now() + interval '30 days', NULL, NULL),
  ('00000000-0000-0000-0000-00000000aa04', '00000000-0000-0000-0000-00000000eb01', 'gym_photo', 'gym-photos',
   '00000000-0000-0000-0000-00000000eb01/00000000-0000-0000-0000-00000000aa04.png', 'image/png', 4096,
   4096, 'processed', repeat('b', 64), repeat('4', 64), now() + interval '30 days', now(), now()),
  ('00000000-0000-0000-0000-00000000aa05', '00000000-0000-0000-0000-00000000eb01', 'content_cover', 'content-covers',
   '00000000-0000-0000-0000-00000000eb01/00000000-0000-0000-0000-00000000aa05.webp', 'image/webp', 8192,
   8192, 'uploaded', NULL, repeat('5', 64), NULL, now(), NULL);

INSERT INTO public.messages (id, user_id, direction, role, content_type, content) VALUES
  ('00000000-0000-0000-0000-00000000cc01', '00000000-0000-0000-0000-00000000ea01', 'in', 'user', 'text', 'almocei arroz e feijão'),
  ('00000000-0000-0000-0000-00000000cc02', '00000000-0000-0000-0000-00000000ea01', 'out', 'assistant', 'text', 'Registrei o almoço.'),
  ('00000000-0000-0000-0000-00000000cc03', '00000000-0000-0000-0000-00000000eb01', 'in', 'user', 'text', 'bom dia');

-- Legacy plan writers (gera_dieta / gera_treino shape).
INSERT INTO public.prescriptions (id, user_id, type, payload) VALUES
  ('00000000-0000-0000-0000-00000000dd01', '00000000-0000-0000-0000-00000000ea01', 'diet',
   '{"meals":[{"name":"Almoço","items":["arroz","feijão"]}]}');
INSERT INTO public.training_plans (id, user_id, plan_type, days_per_week, weekly_schedule) VALUES
  ('00000000-0000-0000-0000-00000000de01', '00000000-0000-0000-0000-00000000ea01', 'split', 3,
   '[{"day":"seg","focus":"superiores"}]');

SELECT public.register_meal_atomic(
  p_user_id => '00000000-0000-0000-0000-00000000ea01',
  p_date => DATE '2026-09-20',
  p_meal_type => 'almoco'::public.meal_type_enum,
  p_items => '[{"food_name":"Arroz branco cozido","quantity_g":150.5,"kcal":192.4,"protein_g":3.8,"carbs_g":42.1,"fat_g":0.3,"source":"taco","confidence":1}]'::jsonb,
  p_provider_message_id => 'rehearsal-legacy-meal-1'
);

COMMIT;
