-- ============================================================================
-- pending_registrations — refeição/treino proposto, aguardando tap [Sim/Editar]
-- ============================================================================
-- Roberto 2026-05-28 — opção #4 (botões WhatsApp com modo express). Fase A:
-- infra. Quando o agente analisa a msg do paciente e a gravação NÃO é express
-- (foto, áudio, texto vago, sem grama), em vez de chamar registra_refeicao
-- direto, o sistema:
--   1. grava a proposta em pending_registrations (status='pending', TTL 30min)
--   2. envia msg interactive WhatsApp com [Sim, registrar] [Editar]
--   3. aguarda tap → handler determinístico marca status e grava de verdade
--
-- Resolve a classe `llm.fake_write_detected` (LLM afirma "registrado" sem
-- chamar a tool): aqui a gravação é gatilhada pelo TAP, não pela decisão do
-- LLM. Plano completo: /root/.claude/plans/botoes-whatsapp.md.
--
-- Status flow:
--   pending → confirmed   (paciente tocou Sim ou disse "sim" — grava de verdade)
--   pending → edited      (paciente tocou Editar — pede correção, próxima msg cai no LLM normal)
--   pending → expired     (TTL 30min sem resposta — cleanup cron)
--   pending → cancelled   (paciente mandou outra msg de comida — pending antigo é cancelado)
-- ============================================================================

CREATE TYPE pending_registration_status AS ENUM
  ('pending','confirmed','edited','expired','cancelled');

CREATE TABLE public.pending_registrations (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id         uuid NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  -- Snapshot da proposta. Schema:
  --   { kind: 'meal' | 'workout',
  --     meal_type?: text, items?: MealItem[], totals?: MealTotals,
  --     workout_type?: text, duration_min?: int, kcal_est?: int,
  --     source_msg_id: uuid, source_text?: text,
  --     express_eligible?: bool }
  proposal        jsonb NOT NULL,
  -- A msg out que MOSTROU a proposta (pra responder via context_message_id).
  proposal_msg_id uuid REFERENCES public.messages(id) ON DELETE SET NULL,
  status          pending_registration_status NOT NULL DEFAULT 'pending',
  created_at      timestamptz NOT NULL DEFAULT now(),
  expires_at      timestamptz NOT NULL,
  resolved_at     timestamptz
);

-- Index pro lookup do pending ativo por usuário (handler do tap + cancelamento implícito).
CREATE INDEX pending_registrations_user_pending_idx
  ON public.pending_registrations(user_id, expires_at)
  WHERE status = 'pending';

-- Index pro cron de cleanup (expirar pending sem resposta).
CREATE INDEX pending_registrations_expires_idx
  ON public.pending_registrations(expires_at)
  WHERE status = 'pending';

COMMENT ON TABLE public.pending_registrations IS
  'Refeição/treino proposto pelo agente, aguardando confirmação por botão WhatsApp (Sim/Editar) ou texto equivalente. Resolve fake_write — gravação é gatilhada pelo TAP, não pela decisão do LLM. Roberto 2026-05-28 (opção #4 botões + modo express). Fase A — infra.';
