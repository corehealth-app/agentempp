-- ============================================================================
-- Engagement Config: expõe parâmetros de janela do engagement-sender
-- ============================================================================
-- Antes hardcoded em packages/inngest-functions/src/functions/engagement-sender.ts.
-- Agora editáveis via /settings/global na UI admin.
-- ============================================================================

INSERT INTO global_config (key, value, description) VALUES

  ('engagement.wake_offset_min', '60'::jsonb,
   'Quantos minutos depois do wake_time do paciente o engajamento começa. Padrão 60min — dá tempo dele acordar/tomar café antes de receber msg.'),

  ('engagement.bed_offset_min', '60'::jsonb,
   'Quantos minutos antes do bedtime do paciente o engajamento para. Padrão 60min — não atrapalha a transição pro sono.'),

  ('engagement.fallback_wake_hour', '6'::jsonb,
   'Hora local de início padrão (0-23) quando o paciente não preencheu wake_time no onboarding. Padrão 6h.'),

  ('engagement.fallback_bed_hour', '22'::jsonb,
   'Hora local de fim padrão (0-23) quando o paciente não preencheu bedtime no onboarding. Padrão 22h.')

ON CONFLICT (key) DO NOTHING;
