-- Adiciona calc.sleep_min_hours em global_config.
-- Critério oficial Notion: 6h30 mínimo de sono pra qualificar pra Ganho de Massa.
-- Antes hardcoded em resolveProtocol; agora editável via /settings/calc.

INSERT INTO global_config (key, value, description)
VALUES (
  'calc.sleep_min_hours',
  '6.5'::jsonb,
  'Horas mínimas de sono pra qualificar pra Ganho de Massa (doc MPP: 6h30). Valor numérico.'
)
ON CONFLICT (key) DO NOTHING;
