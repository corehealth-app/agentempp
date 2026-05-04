-- ============================================================================
-- Runtime Config: expõe slot thresholds + meal hints + humanizer + buffer
-- ============================================================================
-- Antes hardcoded em packages/inngest-functions/src/functions/* e
-- supabase/functions/webhook-whatsapp. Agora editáveis via UI admin
-- (/settings/global). Cada chave tem fallback no código.
-- ============================================================================

INSERT INTO global_config (key, value, description) VALUES

  -- ----- Slots de engajamento -----
  -- Array ordenado por until_hour ASC. A 1ª linha cuja until_hour > localHour
  -- vence. Use slot="skip" pra não enviar (madrugada/noite).
  ('engagement.slots', $$[
    { "until_hour":  6, "slot": "madrugada",     "meal_hint": "madrugada — não envia" },
    { "until_hour":  9, "slot": "cafe_da_manha", "meal_hint": "café da manhã (jejum, primeira refeição do dia)" },
    { "until_hour": 11, "slot": "meio_da_manha", "meal_hint": "meio da manhã (lanche entre café e almoço, ou check-in pré-almoço)" },
    { "until_hour": 14, "slot": "almoco",        "meal_hint": "almoço (refeição principal do meio-dia)" },
    { "until_hour": 16, "slot": "pos_almoco",    "meal_hint": "pós-almoço (digestão, balanço parcial do dia)" },
    { "until_hour": 19, "slot": "lanche_tarde",  "meal_hint": "lanche da tarde (entre almoço e jantar)" },
    { "until_hour": 22, "slot": "jantar",        "meal_hint": "jantar (última refeição do dia)" },
    { "until_hour": 24, "slot": "noite",         "meal_hint": "noite — não envia" }
  ]$$::jsonb,
   'Mapeia hora local → slot semântico + dica de refeição pro LLM. Array ordenado por until_hour. Editar pra ajustar janelas (ex: almoço 12-14h em vez de 11-14h) ou textos.'),

  -- ----- Humanizer (typing simulation) -----
  ('humanizer.min_delay_ms', '800'::jsonb,
   'Delay mínimo entre msgs OUT, simulando digitação. ms. Padrão 800.'),
  ('humanizer.max_delay_ms', '3000'::jsonb,
   'Delay máximo entre msgs OUT. ms. Padrão 3000. Engagement usa esse valor.'),
  ('humanizer.response_max_delay_ms', '3500'::jsonb,
   'Delay máximo em respostas a msgs do user (process-message). Padrão 3500 — um pouco maior que engagement pra parecer "pensando".'),
  ('humanizer.chars_per_second', '55'::jsonb,
   'Velocidade de digitação simulada (caracteres/segundo). Padrão 55 ≈ digitação humana média.'),

  -- ----- Buffer debounce (webhook-whatsapp) -----
  ('buffer.debounce_ms', '8000'::jsonb,
   'Tempo que webhook-whatsapp aguarda antes de processar msgs do user. ms. Padrão 8000 (8s) — agrega msgs próximas pra evitar 1 LLM call por linha quando user envia várias rápido.')

ON CONFLICT (key) DO NOTHING;
