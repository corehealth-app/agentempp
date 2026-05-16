-- ============================================================================
-- Sanity CHECK em wake_time / bedtime do user_profiles.
-- ============================================================================
-- Caso Amanda (2026-05-16): wake_time=03:00 entrou no onboarding (provável
-- erro de digitação/interpretação do LLM). Resultado: janela ativa de
-- engajamento virou 04h-20h → enviou msg às 04:07 BRT. Amanda reclamou
-- explicitamente "4 horas da manhã ele tá mandando mensagem".
--
-- Defesa em camadas:
--   1. agent_rule "sanity-check-horario-acorda-dorme" (coleta_dados) — LLM
--      pergunta antes de gravar valor fora do esperado (4h-12h pra wake,
--      19h-3h pra bedtime).
--   2. CHECK constraint (este arquivo) — backend rejeita INSERT/UPDATE com
--      valor absurdo, defesa contra bug de software escrevendo lixo.
--   3. engagement-sender slots "madrugada"/"noite" silent=true — NUNCA
--      enviam mesmo se janela ativa abrange.
--
-- Sem violadores ativos no banco (Amanda+Erika já foram resetados pra NULL
-- antes deste constraint).
-- ============================================================================

ALTER TABLE user_profiles
  ADD CONSTRAINT user_profiles_wake_time_sane
    CHECK (wake_time IS NULL OR (wake_time >= '04:00'::time AND wake_time <= '12:00'::time));

-- bedtime aceita tanto noite tardia (19h-23:59) quanto madrugada cedinha
-- (00:00-03:00) — pra contemplar pessoas que dormem depois da meia-noite.
ALTER TABLE user_profiles
  ADD CONSTRAINT user_profiles_bedtime_sane
    CHECK (bedtime IS NULL OR (bedtime >= '19:00'::time OR bedtime <= '03:00'::time));
