# Agente MPP

Coach nutricional via WhatsApp baseado no método **Muscular Power Plant** (Dr. Roberto Menescal).

> **Cliente:** CoreHealth
> **Status:** Em desenvolvimento (Fase 0 — Setup)

---

## O que é

SaaS conversacional que opera via WhatsApp:

- Onboarding em 11 perguntas, cálculo automático de protocolo (Recomposição / Ganho de Massa / Manutenção)
- Registro de refeições por foto, áudio ou texto, com cálculo nutricional via base TACO
- Treinos, sono, água, passos
- Gamificação com bloco 7.700 kcal, XP, níveis, streak e badges
- Reavaliação quinzenal
- Voz bidirecional (STT + TTS com identidade do Dr. Roberto)
- Billing recorrente via Stripe

---

## Stack

| Camada | Serviço |
|---|---|
| Backend | Supabase (Postgres + Edge Functions + Storage + Auth + pgvector + pg_cron) |
| Frontend | Vercel + Next.js 15 + shadcn/ui (admin) |
| Workers | Inngest |
| Canal | WhatsApp Cloud API (Meta) |
| LLM | OpenRouter (Grok 4.1 Fast / DeepSeek V3) |
| Vision | Gemini 2.0 Flash via OpenRouter |
| STT | Groq Whisper |
| TTS | ElevenLabs (âncoras) + Cartesia (operacional) |
| Billing | Stripe |
| Observability | Helicone + Sentry |

---

## Estrutura

```
agentempp/
├── apps/
│   └── admin/              # Next.js admin UI (prompts, evals, dashboards)
├── packages/
│   ├── core/               # Lógica de domínio pura (protocol, progress, nutrition)
│   ├── db/                 # Tipos Supabase + helpers
│   ├── providers/          # Adapters (messaging, llm, tts, stt, vision)
│   ├── inngest-functions/  # Step functions (process-message, daily-closer, etc)
│   └── ui/                 # Componentes compartilhados shadcn
├── supabase/
│   ├── migrations/         # Schema versionado
│   ├── functions/          # Edge Functions (webhooks)
│   └── seed.sql
├── prompts/                # Espelho git das regras do agent_rules
├── eval/                   # Suite de avaliação (gate de CI)
├── scripts/                # Utilitários (import TACO, seed regras)
└── docs/
    ├── adr/                # Architecture Decision Records
    ├── runbook/
    └── CONTEXT.md          # Estado vivo do projeto
```

---

## Pré-requisitos

- Node.js 22+ (`.nvmrc`)
- pnpm 10+
- Supabase CLI 2.84+
- `gh` CLI autenticado com write access em `corehealth-app/agentempp`
- `.env.local` preenchido (template em `.env.example`)

---

## Setup local

```bash
# Instalar dependências
pnpm install

# Linkar projeto Supabase (já feito uma vez)
SUPABASE_DB_PASSWORD='...' supabase link --project-ref xuxehkhdvjivitduarvb

# Aplicar migrations em staging
pnpm db:push

# Gerar types
pnpm db:types

# Rodar testes do core
pnpm test
```

---

## Convenções

- **Conventional Commits** (`feat:`, `fix:`, `chore:`, `refactor:`, `docs:`)
- **Branches:** `phase-N/escopo` ou `feat/nome-curto`
- **PRs:** descrição com o que / por quê / como testei / risco
- **RLS desde o dia 1** — todas as tabelas com policies
- **Eval gate** — mudanças em `prompts/` rodam suite e bloqueiam regressão

---

## Documentação

- [`docs/CONTEXT.md`](docs/CONTEXT.md) — estado atual e próximos passos
- [`docs/adr/`](docs/adr/) — decisões arquiteturais registradas
- [`docs/runbook/`](docs/runbook/) — procedimentos operacionais

---

## Licença

UNLICENSED — propriedade da CoreHealth.
