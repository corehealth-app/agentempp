# Agente MPP — Referência Técnica Completa & Mapa de Integração

> **Propósito deste documento.** Este é um dossiê técnico exaustivo do **Agente MPP** pensado para **pesquisa de integração**: o que o sistema faz, com que stack, em que formatos troca dados, e — sobretudo — **quais são todas as fronteiras (inbound/outbound) onde um sistema externo pode plugar**. Cada contrato externo (webhook, endpoint HTTP, evento de fila, RPC, view, env var, payload) está descrito com o formato real, extraído direto do código em `/root/agentempp`.
>
> Use o [Capítulo 14 — Superfícies de integração](#14-superfícies-de-integração-o-mapa) como índice de pontos de plugagem e o [Capítulo 15 — Cenários de integração](#15-cenários-de-integração-recomendados) como catálogo de "onde dá pra entrar".
>
> Gerado em 2026-06-24 a partir do estado real do repositório. Complementa (e atualiza em pontos) o [docs/PLATAFORMA-AGENTE-MPP.md](PLATAFORMA-AGENTE-MPP.md) e a fonte de verdade de cálculo [docs/CALCULO-MPP.md](CALCULO-MPP.md).

---

## Sumário

1. [Resumo executivo](#1-resumo-executivo)
2. [Arquitetura de alto nível e fluxo de uma mensagem](#2-arquitetura-de-alto-nível-e-fluxo-de-uma-mensagem)
3. [Stack tecnológico (versões exatas) e workspaces](#3-stack-tecnológico-versões-exatas-e-workspaces)
4. [Hospedagem e infraestrutura](#4-hospedagem-e-infraestrutura)
5. [Banco de dados Supabase (schema completo)](#5-banco-de-dados-supabase-schema-completo)
6. [Motor de cálculo determinístico](#6-motor-de-cálculo-determinístico)
7. [Pipeline conversacional e as 20 tools do LLM](#7-pipeline-conversacional-e-as-20-tools-do-llm)
8. [Provedores de IA e serviços externos](#8-provedores-de-ia-e-serviços-externos)
9. [Mensageria WhatsApp — envelope e payloads exatos](#9-mensageria-whatsapp--envelope-e-payloads-exatos)
10. [Workers Inngest, eventos e crons](#10-workers-inngest-eventos-e-crons)
11. [Edge Functions (webhooks e endpoints públicos)](#11-edge-functions-webhooks-e-endpoints-públicos)
12. [Painel administrativo e configuração em runtime](#12-painel-administrativo-e-configuração-em-runtime)
13. [Billing Stripe multi-moeda](#13-billing-stripe-multi-moeda)
14. [Telemetria `product_events` (catálogo de eventos)](#14-telemetria-product_events-catálogo-de-eventos)
15. [Superfícies de integração — o mapa](#15-superfícies-de-integração-o-mapa)
16. [Cenários de integração recomendados](#16-cenários-de-integração-recomendados)
17. [Catálogo de variáveis de ambiente](#17-catálogo-de-variáveis-de-ambiente)
18. [Glossário](#18-glossário)
19. [Notas factuais e divergências conhecidas](#19-notas-factuais-e-divergências-conhecidas)

---

## 1. Resumo executivo

O **Agente MPP** é um **agente de coaching nutricional conversacional via WhatsApp** — um SaaS sem app próprio: o paciente nunca aprende uma interface, tudo acontece no chat. Ele conversa, registra refeições e treinos por **foto, áudio ou texto**, calcula **em código** toda a contabilidade calórica do dia, e devolve em tempo real um **card de balanço** com saldo, proteína, exercício e progresso no **"bloco 7700"** (gamificação: 1 kg de gordura = 7700 kcal de déficit líquido).

| Campo | Valor |
|---|---|
| Produto / dono | **CoreHealth** (org GitHub `corehealth-app`), modelo work-for-hire |
| Método encarnado | **Muscular Power Plant (MPP)** do **Dr. Roberto Menescal** (persona do agente) |
| Repositório | `corehealth-app/agentempp` (monorepo pnpm + turbo) |
| Projeto Supabase | ref `xuxehkhdvjivitduarvb` (Postgres 17 + pgvector + pg_cron) |
| Projeto Vercel | `agentempp` (`https://agentempp.vercel.app`) |
| Canal | WhatsApp Cloud API (Meta), Graph `v21.0` |
| Custo operacional | ~**$50–$154/mês** para a base atual (~9 pacientes-piloto) |

**Tese central (atravessa toda decisão de engenharia):** *o LLM conversa, interpreta linguagem natural e escolhe ferramentas — mas o **SISTEMA** é dono dos números e da gravação.* Corolários: (1) toda escrita no banco passa por uma ferramenta determinística; (2) todo número exibido é re-renderizado a partir do banco (card canônico); (3) uma malha de detectores e auditorias intercepta os modos de falha clássicos de LLM.

**Funcionalidades de ponta a ponta:** onboarding conversacional (com botões/listas WhatsApp) · registro multimodal (foto/áudio/texto) · card de balanço + bloco 7700 (XP, 8 níveis, streaks, badges) · lembretes proativos · dieta e treino sob demanda · reavaliação quinzenal · voz (TTS) · billing Stripe multi-país.

---

## 2. Arquitetura de alto nível e fluxo de uma mensagem

O sistema é um **monorepo** tratado como software de verdade (não um encadeamento de automações). Três planos de execução:

- **Borda (Supabase Edge Functions, Deno)** — recebe webhooks de terceiros (WhatsApp, Stripe, Telegram), valida assinatura e empilha/dispara.
- **Orquestração (Inngest Cloud)** — step functions durables + crons que executam o trabalho pesado, chamando de volta a Vercel.
- **App + dados (Vercel + Supabase)** — painel admin Next.js, endpoints serverless, Postgres com toda a lógica de negócio em tabelas.

```
                         ┌─────────────────────── Serviços externos de IA ───────────────────────┐
                         │ OpenRouter(LLM/Vision/Embeddings) · Groq(STT) · ElevenLabs/Cartesia(TTS)│
                         └────────────────────────────────▲──────────────────────────────────────┘
                                                          │
  Meta WhatsApp Cloud ──webhook──▶ Edge Fn webhook-whatsapp ─┐
                                     │ (HMAC SHA-256)         │ POST inn.gs/e/{KEY}
       Stripe ──webhook──▶ Edge Fn webhook-stripe            │  { name, data, ts? }
       Telegram ──webhook──▶ Edge Fn telegram-webhook        ▼
                                                    ┌──────────────────┐    callback (assinado)
                                                    │  Inngest Cloud    │◀───────────────────────┐
                                                    │  (event bus +     │                        │
                                                    │   crons + workers)│──POST /api/inngest──▶ Vercel
                                                    └─────────┬─────────┘                  (Next.js admin
                                pg_cron ──dispatch_inngest_event──┘                          + workers servidos)
                                  (no Postgres)                                                   │
                                                                                                  ▼
                                                                                          Supabase Postgres
                                                                                   (RLS, RPC, views, pgvector, telemetria)
```

### Fluxo de uma mensagem (webhook → card)

```
Meta ──POST──▶ webhook-whatsapp (Edge Fn)
   │  TAP em botão  → inn.gs 'interactive.button.tapped' (delay 0)
   │  mensagem      → RPC buffer_append_msg (atomic; flush_after = now + 8000ms)
   │                → inn.gs 'buffer.flush' (delay = debounce + 1500ms)
   ▼
buffer-listener (Inngest; concurrency=1 por userId, idempotente)
   - gate vision-inflight: foto recente <30s sem análise → estende +20s (1×)
   - agrega textos, escolhe contentType (áudio>imagem>texto), monta mediaUrls[]
   - emite 'message.received'
   ▼
process-message (Inngest; concurrency=1 por userId; retries=3)
   - ack 👀 / checa pausa 💤
   - STT (Groq Whisper, pt) p/ áudio | Vision (Claude Sonnet 4.5) p/ imagem
   - processMessage(deps)  →  @mpp/agent: LLM (OpenRouter) + loop de tools + cálculo determinístico
   - envio: interactive (botões/lista) | TTS | sendHumanized (até 3 bolhas)
   - reação final ✅/⚠️/🤔
```

A função de entrada do núcleo conversacional é `processMessage(deps, input): Promise<AgentOutput>` em [packages/agent/src/pipeline.ts](../packages/agent/src/pipeline.ts).

---

## 3. Stack tecnológico (versões exatas) e workspaces

### Toolchain

| Ferramenta | Resolvida (lockfile) | Declarada | Notas |
|---|---|---|---|
| Node.js | runtime `>=22` (`.nvmrc=22`) | `>=22.0.0` | |
| pnpm | `10.33.2` | `>=10.0.0` | `packageManager` fixo |
| Turborepo | `2.9.7` | `^2.5.0` | `ui: "tui"` |
| TypeScript | `5.9.3` | `^5.7.3` | ES2022, ESM (`verbatimModuleSyntax`, `noUncheckedIndexedAccess`) |
| Biome | `2.4.13` | `^2.2.5` | substitui ESLint+Prettier |
| Vitest | `2.1.9` | `^2.1.8` | trava regras de cálculo |
| Supabase CLI | `2.98.0` | `^2.95.4` | |
| tsx | `4.21.0` | `^4.20.6` | scripts/eval/cli |

### Frameworks (app admin)

Next.js `15.5.15` (App Router, `runtime nodejs`, `maxDuration 300`) · React `19.2.5` · Inngest `3.54.2` · `@supabase/supabase-js` `2.105.1` · `@supabase/ssr` `0.5.2` · Stripe SDK `22.1.0` · OpenAI SDK `4.104.0` · Zod `3.25.76` · Tailwind `3.4.19` + shadcn/ui sobre Radix · `lucide-react` · `motion` · `cmdk` · `sonner`.

> Todo o tráfego de LLM/Vision/Embeddings usa o **SDK `openai`** apontado para endpoints OpenAI-compatíveis (OpenRouter, Groq). **Não há** `@anthropic-ai/sdk` nem `@google/generative-ai` instalados.

### Workspaces (pnpm-workspace: `apps/*`, `packages/*`, `scripts`, `eval`)

| Workspace | Papel | Deps internas |
|---|---|---|
| `@mpp/core` | **Motor determinístico puro** (cálculo de meta, balanço, bloco 7700, protocolo). Sem I/O. Regras travadas por teste. | — (base) |
| `@mpp/db` | Cliente Supabase + tipos TS gerados (`./types`, `./client`) | — |
| `@mpp/providers` | Adapters externos: `llm`, `vision`, `stt`, `tts`, `embeddings`, `messaging` (subpaths) | — |
| `@mpp/agent` | Pipeline conversacional, 20 tools, model-router, detectores, geradores | core, db, providers |
| `@mpp/inngest-functions` | 16 workers Inngest (process-message, daily-closer, crons) | todos |
| `@mpp/admin` (`apps/admin`) | Painel Next.js 15 + endpoints HTTP (`/api/inngest`, `/api/stripe/*`, `/api/media/*`, `/api/admin/send-message`) | todos os `@mpp/*` |
| `@mpp/cli` (`apps/cli`) | Chat de teste no terminal (`pnpm chat`) | agent, db, providers |
| `@mpp/scripts` | Operação: seed TACO/Notion, ingestão RAG, backfills, deploy | db |
| `@mpp/eval` | Suíte de avaliação (`tsx runner.ts`) | agent, db, providers |

> `packages/ui` está no glob de workspaces mas é **diretório vazio** (sem `package.json`); componentes vivem em `apps/admin/src/components`.

**Grafo:** `core` é a base; `providers`/`db` são folhas de infra; `agent` depende dos três; `inngest-functions` depende de todos; `admin` consome os cinco `@mpp/*`.

### Comandos

```bash
pnpm install
pnpm dev                              # turbo run dev
pnpm --filter @mpp/admin dev          # admin em http://localhost:3000
pnpm --filter @mpp/cli chat           # chat de teste no terminal
pnpm test                             # turbo run test (vitest)
pnpm --filter @mpp/agent test         # regras de cálculo MPP (fonte de verdade travada)
pnpm typecheck                        # turbo run typecheck
pnpm check                            # biome (lint + format)
pnpm db:types                         # gera tipos TS do schema
bash scripts/deploy.sh                # deploy prod + sync Inngest (autorização do Eduardo)
```

### CI/CD

- **CI (GitHub Actions):** `.github/workflows/lint-agent.yml` — job **`no-new-as-any`** que roda `biome check packages/agent/src` e **falha o build** se houver novo `lint/suspicious/noExplicitAny` (>0). Gatilho: push em `main` e PRs que tocam `packages/agent/**`/`biome.json`. *(É o único workflow; não há CI de deploy.)*
- **Deploy:** `scripts/deploy.sh` faz `vercel --prod`, espera 5s, e força `curl -X PUT $PROD_URL/api/inngest` para **re-sincronizar as Inngest functions** (deploy manual da Vercel não dispara o auto-sync). Aborta se status != 200. **Só com autorização explícita do Eduardo.**

---

## 4. Hospedagem e infraestrutura

| Componente | Onde roda | Boundary |
|---|---|---|
| App admin + endpoints serverless | **Vercel** (`agentempp.vercel.app`) | Next.js 15, `runtime nodejs`, `maxDuration 300s` |
| Endpoint Inngest | **Vercel** `/api/inngest` (via `inngest/next` `serve()`) | `GET` discovery · `POST` (Inngest Cloud, assinado por `INNGEST_SIGNING_KEY`) · `PUT` sync |
| Workers / step functions | **Inngest Cloud** (chama de volta a Vercel) | eventos tipados via `EventSchemas` |
| Crons | **Inngest Cloud** (crons nativos) + **pg_cron** (no Postgres) | ver [Cap. 10](#10-workers-inngest-eventos-e-crons) |
| Banco / Auth / Storage / RAG | **Supabase** (`xuxehkhdvjivitduarvb`) | Postgres 17, pgvector, pg_cron, RLS desde o dia 1 |
| Webhooks de entrada | **Supabase Edge Functions** (Deno) | 6 funções (ver [Cap. 11](#11-edge-functions-webhooks-e-endpoints-públicos)) |
| Auditoria profunda | **VPS Linux** (crontab) | roda Claude analista read-only (`scripts/claude-deep-audit.sh`) |
| CLI / scripts / eval | Local / VPS | `tsx` contra o banco de prod |

---

## 5. Banco de dados Supabase (schema completo)

Postgres **major 17**. **65 migrations** versionadas em `supabase/migrations/**` (source of truth). Tipos TS gerados em `packages/db/src/generated/database.ts`. Schemas expostos na API REST: `public`, `graphql_public`. `max_rows = 1000`.

### 5.1 Extensões

| Extensão | Uso |
|---|---|
| `pgcrypto` | `gen_random_uuid()` (PKs UUID) |
| `pg_trgm` | fuzzy search de alimentos (`gin_trgm_ops` em `food_db.name_norm`) |
| `unaccent` | normalização de acentos (`f_unaccent` IMMUTABLE) |
| `vector` (pgvector) | embeddings **1024 dims** em `message_embeddings`, `food_db`, `method_chunks`, `food_education_phrases` (índices HNSW `vector_cosine_ops` e IVFFlat) |
| `pg_cron` | agendamento interno (engagement, daily-closer, health, cleanup) |
| `pg_net` | HTTP assíncrono Postgres→Inngest (`net.http_post`) |

Há também FTS nativo: `agent_rules.content_tsv` é `tsvector GENERATED ALWAYS` (índice GIN).

### 5.2 Enums do domínio

```
user_status:        active | blocked | deleted
sex_enum:           masculino | feminino
activity_enum:      sedentario | leve | moderado | alto | atleta
water_enum:         pouco | moderado | bastante
hunger_enum:        pouca | moderada | muita
protocol_enum:      recomposicao | ganho_massa | manutencao
goal_type_enum:     BF | IMC | peso_kg
direction_enum:     in | out
msg_role_enum:      user | assistant | system | tool
content_type_enum:  text | audio | image | template | interactive
meal_type_enum:     cafe | almoco | lanche | jantar | ceia | outro
agent_stage:        coleta_dados | recomposicao | ganho_massa | manutencao | analista_diario | engajamento
rule_tipo:          recomposicao | ganho_massa | manutencao | coleta_dados | regras_gerais
config_status:      draft | testing | active | archived
plan_enum:          trial | mensal | anual
sub_status:         trial | active | past_due | canceled | expired
pending_registration_status: pending | confirmed | edited | expired | cancelled
```

### 5.3 Tabelas por domínio

| Grupo | Tabelas |
|---|---|
| **Usuários / perfil / gamificação** | `users`, `user_profiles`, `user_progress`, `reevaluations` |
| **Operacional diário** | `daily_snapshots`, `meal_logs`, `workout_logs`, `user_food_corrections` |
| **Conversação / WhatsApp** | `messages`, `processed_messages` (idempotência), `message_buffer` (UNLOGGED, debounce), `message_embeddings` (vector 1024) |
| **RAG / conhecimento / config do agente** | `agent_configs`+`agent_configs_versions`, `agent_rules`+`agent_rules_versions`, `method_chunks` (vector 1024), `food_db` (trgm + vector) |
| **Frases curadas** | `food_education_phrases`, `engagement_phrases`, `user_phrase_cooldown` |
| **Prescrições / treino** | `prescriptions`, `training_plans` |
| **Billing (Stripe)** | `subscriptions`, `subscription_events` (idempotência por `provider_event_id`) |
| **Pending / botões / aprovações** | `pending_registrations` (tap [Sim/Editar]), `pending_approvals` (aprovação via Telegram) |
| **Telemetria / auditoria** | `product_events`, `tools_audit`, `llm_evaluations`, `audit_log`, `whatsapp_phone_status`, `attention_dismissals` |
| **Config runtime / admin / cache** | `global_config`, `feature_flags`, `service_credentials`, `admin_users`, `tts_cache`, `mv_kpis_daily` |

### 5.4 Tabelas centrais — colunas-chave

**`users`** — `id uuid PK` · `wpp text UNIQUE NOT NULL` (E.164 sem `+`) · `email text UNIQUE` · `name` · `locale text DEFAULT 'pt-BR'` · `timezone text DEFAULT 'America/Sao_Paulo'` · `status user_status` · `metadata jsonb` · `country/country_confirmed/country_detected_from_wpp`.

**`user_profiles`** (PK `user_id`) — `sex` · `birth_date` · `height_cm/weight_kg numeric(5,2)` · `body_fat_percent numeric(4,2)` · `activity_level` · `training_frequency smallint (0-7)` · `water_intake/hunger_level` · `wake_time/bedtime time` · `current_protocol` · `goal_type/goal_value` · `deficit_level smallint (400/500/600)` · `onboarding_completed/onboarding_step` · `bf_*` (estimated/source/measured_at) · `cycle_start_*` (baseline de ciclo).

**`user_progress`** (PK `user_id`) — `xp_total int` · `level smallint` · `current_streak/longest_streak` · `blocks_completed smallint` · `deficit_block int` (acúmulo no bloco atual de 7700) · `current_weight/current_bf_percent` · `badges_earned text[]` · `last_active_date/next_reevaluation date`.

**`meal_logs`** (1 linha por item) — `id` · `user_id` · `snapshot_id` · `meal_type` · `food_name` · `quantity_g numeric(6,2)` · `kcal/protein_g/carbs_g/fat_g` · `source` (`taco|gemini_estimate|user_correction|manual|no_match|...`) · `confidence numeric(3,2)` · `image_url` · `raw_message_id` · `consumed_at timestamptz`.

**`daily_snapshots`** (UNIQUE `(user_id, date)`) — `calories_consumed/calories_target int` · `protein_g/protein_target/carbs_g/fat_g` · `exercise_calories int` · `steps/training_done/sleep_hours/water_consumed_ml` · `xp_earned` · `daily_balance int **GENERATED STORED** = calories_consumed − COALESCE(calories_target,0) − COALESCE(exercise_calories,0)` · `current_protocol` · `day_closed/closed_at` · `day_status text DEFAULT 'complete'` · `gap_reminder_sent_at`.

> ⚠️ `daily_balance` é **coluna gerada** (o balanço NET/bloco, **com** exercício). Não dá para setar via UPDATE/PATCH (erro `428C9`); corrige-se `calories_consumed` e o banco recalcula. O "Restam/Excedente" do card (**sem** exercício) é calculado em runtime, não nesta coluna.

**`messages`** (envelope WhatsApp) — `direction direction_enum` · `role msg_role_enum` · `content_type content_type_enum` · `content text` · `media_url/media_storage_path` · `provider text DEFAULT 'whatsapp_cloud'` · `provider_message_id` · `raw_payload jsonb` (webhook bruto) · `intent` · `agent_stage/model_used` · `prompt_tokens/completion_tokens/latency_ms/cost_usd` · `delivery_status` (`sent|delivered|read|failed`) · `delivery_error jsonb`.

**`pending_registrations`** — `proposal jsonb NOT NULL` · `proposal_msg_id` · `status pending_registration_status` · `expires_at` (+24h). Shape do `proposal`:
```json
{ "kind":"meal|workout", "meal_type":"almoco", "items":[/*MealItem[]*/], "totals":{...},
  "workout_type":"corrida", "duration_min":30, "kcal_est":300,
  "source_msg_id":"uuid", "source_text":"texto do paciente", "express_eligible":true, "replace":false }
```

**`global_config`** — `key text PK` · `value jsonb` · `description` · `updated_at/updated_by`. É o **ponto central de configuração em runtime** (ver [Cap. 12](#12-painel-administrativo-e-configuração-em-runtime)).

**`prescriptions`** — `type text (diet|shopping_list|combined)` · `payload jsonb` · `generated_by/generated_at` · `last_sent_at/valid_until/version`.
**`training_plans`** — `plan_type (split|full_body|custom)` · `days_per_week (1-7)` · `equipment_summary` · `weekly_schedule jsonb` · `active` · `valid_until/version`.
**`subscriptions`** — `provider DEFAULT 'stripe'` · `provider_subscription_id UNIQUE` · `plan plan_enum` · `status sub_status` · `current_period_start/end` · `trial_ends_at` · `cancel_at_period_end`.
**`method_chunks`** (RAG) — `page_title` · `chunk_index` · `content` · `protocol` · `embedding vector(1024)`.
**`food_education_phrases`** — `food_canonical_name` · `phrase` · `tags jsonb` · `language` · `active` · `usage_count/last_used_at` · `food_name_embedding vector(1024)`.

### 5.5 Funções SQL / RPC notáveis

| Função | Descrição |
|---|---|
| `dispatch_inngest_event(p_event_name, p_data, p_delay_ms)` | **Ponte pg_cron→Inngest.** Lê `INNGEST_EVENT_KEY` de `service_credentials` e faz `net.http_post` para `https://inn.gs/e/{KEY}` com `{name, data, [ts]}` |
| `daily_close_user(user_id, date)` / `daily_close_all()` | Fecha snapshot, calcula bloco 7700 + XP + streak + badges |
| `buffer_append_msg(uuid, jsonb, int)` | Append atômico no `message_buffer` com `GREATEST(flush_after)` (debounce) |
| `match_food_phrases(query_embedding vector(1024), threshold, count, language)` | Similarity pgvector → `(id, phrase, tags, similarity)`. GRANT a `service_role, anon, authenticated` |
| `match_method_chunks(query_embedding, count, filter_protocol)` | RAG do método → `(content, distance, page_title, protocol)[]` |
| `search_food_trgm(...)` / `search_food_cross_country` | fuzzy + cross-country no `food_db` |
| `search_messages(...)` | busca semântica em `message_embeddings` |
| `agent_kpis(days int=7)` | KPIs agregados (jsonb) para dashboard |
| `get_global_config` / `set_global_config` | leitura/upsert key/value |
| `is_admin()` / `admin_role()` | checagem RLS (SECURITY DEFINER contra `admin_users`) |
| `snapshot_add_meal` / `snapshot_add_workout` | agrega refeição/treino no snapshot |
| `pause_user` / `resume_user` / `tag_user` / `user_metadata_merge` | gestão de estado/metadata |
| `cron_run_now` / `cron_toggle_job` / `cron_update_schedule` | gestão de pg_cron via admin |

**Triggers:** versionamento imutável de prompts (`trg_rules_version`/`trg_configs_version`), audit de admins (`trg_audit_admin_users`).

**Views úteis p/ BI/integração:** `v_user_metrics` (BMR/TDEE/IMC/LBM derivados), `v_active_prompts` (system prompt montado por stage), `v_daily_cost` (custo LLM por dia/stage/modelo), `v_cron_jobs`, `v_attention_items`, `mv_kpis_daily` (materialized).

### 5.6 RLS (resumo)

Edge Functions/workers usam `service_role` (bypass RLS). O painel admin usa JWT + `is_admin()`/`admin_role()` (roles `admin`/`editor`/`viewer`). Tabelas de domínio: SELECT só para `is_admin()`; mutação só por service_role. `food_db` é SELECT público. `agent_rules`/`agent_configs`: write = `editor`+, publish = `admin`. `feature_flags`/`service_credentials`: ALL só `admin`. `processed_messages`/`message_buffer`: nunca expostos via API.

### 5.7 Storage

**Nenhum bucket Supabase Storage** é definido nas migrations ou usado em código. Mídia de WhatsApp é referenciada por **media id / URL** nas colunas `messages.media_url`, `meal_logs.image_url`, etc. — bytes são obtidos via Graph API (proxy em `/api/media/[id]`).

---

## 6. Motor de cálculo determinístico

Pacote `@mpp/core` — funções **puras** (sem I/O), travadas por teste Vitest. Fonte de verdade conceitual: [docs/CALCULO-MPP.md](CALCULO-MPP.md). Toda função aceita um `CalcConfig` opcional (injetado em runtime via `global_config` chaves `calc.*`); omitido, usa `DEFAULT_CALC_CONFIG`.

### 6.1 Métricas base (`nutrition.ts`)

```
# BMR — escolhe fórmula pela presença de %BF
SE bodyFatPercent > 0:  # Katch-McArdle
    LBM = peso × (1 − bf/100);  BMR = 370 + 21.6 × LBM
SENÃO:                  # Mifflin-St Jeor
    base = 10×peso + 6.25×altura − 5×idade
    BMR  = base + (masculino ? +5 : −161)

TDEE = BMR × activity_factor       # sed 1.2 / leve 1.375 / mod 1.55 / alto 1.725 / atleta 1.9
IMC  = peso / (altura_m)²
proteinTargetG = peso × proteinFactor   # achatado em 1.5 g/kg em prod (Roberto 2026-05-15)
```

### 6.2 Meta calórica por protocolo (`engine/targets.ts`)

```
recomposicao:  meta = BMR × 1.2 − design_deficit       # TDEE NÃO entra; é só informativo
ganho_massa:   meta = TDEE × 1.05                       # superávit leve
manutencao:    meta = TDEE
# design_deficit (= deficit_level): leve 400 / médio 500 / alto 600
```

### 6.3 Os DOIS balanços (`engine/balance.ts`) — **a regra nº 1 do projeto**

```
eatingBalance   = consumido − meta                 # COMIDA — "Restam/Excedente", SEM exercício
netBalance      = consumido − meta − exercício     # déficit do dia — alimenta o bloco, COM exercício
realDailyDeficit = designDeficit − netBalance       # déficit REAL vs manutenção (comunicado ao paciente)
```

> **Comida = sem exercício. Bloco/déficit = com exercício. Exercício acelera o bloco, mas NÃO libera comer mais.** Misturar os dois é "a confusão nº 1 da história deste agente". Ex.: `designDeficit=500, netBalance=−397 → déficit real = 897` (não 397).

### 6.4 Bloco 7700 LÍQUIDO (`engine/bloco.ts`) — fonte única

```
KCAL_BLOCK = 7700
crédito_do_dia (creditDayToBloco) — em ordem:
  1. !hasActivity                              → 0
  2. day_status == 'user_skipped'              → designDeficit − dailyBalance (pode ser negativo)
  3. consumido < 0.5×target (sub-registro)     → designDeficit se completo/null, senão 0
  4. day_status == 'incomplete_no_response'    → 0 (gap aberto no fechamento)
  5. CASO PADRÃO (líquido)                      → designDeficit − dailyBalance (pode ser NEGATIVO)

accumulateBloco(credits[]):
  total = max(0, round(Σ credits))    # clamp no TOTAL → cofrinho nunca fica negativo
  deficit_block   = total % 7700
  blocks_completed = floor(total / 7700)
```

`daily-closer`, `progress-calc.computeProgress` e `lib/bloco-recompute` **todos chamam essa mesma função** (não replicam a regra) — o que mantém paridade auditável.

### 6.5 Roteamento de protocolo (`protocol-router.ts`)

`resolveProtocol(profile, metrics, config)` → `ProtocolDecision { protocol, canChoose, blockers[], goalType, goalValue }`. Decisão preferencial por %BF (limites recomp homem 20% / mulher 28%), fallback por IMC (limite 25). Hoje **todos os pacientes estão em recomposição**; `ganho_massa`/`manutencao` estão implementados e testados, mas dormentes (`engine/protocols.ts`).

### 6.6 Gamificação (`progress-calc.ts`)

8 níveis (Início → Lenda MPP, thresholds de XP), 6 badges (streak/blocks/xp), XP diário por refeição/proteína/treino/dia-perfeito. `computeProgress` recebe o `dayCredit` já pronto e só **acumula** (não recalcula a regra do bloco).

---

## 7. Pipeline conversacional e as 20 tools do LLM

### 7.1 Contratos de entrada/saída

`AgentInput` → `processMessage(deps, input)` → `AgentOutput` ([packages/agent/src/types.ts](../packages/agent/src/types.ts)):

```ts
interface AgentInput {
  from: string                  // E.164 sem '+'
  providerMessageId: string     // idempotência
  text?: string
  mediaUrl?: string; mediaMimeType?: string; mediaUrls?: string[]
  contentType: 'text' | 'audio' | 'image'
  imageHint?: 'meal' | 'body' | 'scale' | 'other'
  provider: string              // 'whatsapp_cloud' | 'console' | ...
  timestamp: Date
}

interface AgentOutput {
  text: string
  singleMessage?: boolean       // card determinístico não fragmenta
  interactive?: { body: string; buttons: {id;title}[]; pendingId: string; list?: {buttonText} }
  toolCalls: { name; arguments; result?; error? }[]
  stage: AgentStage; modelUsed: string
  promptTokens: number; completionTokens: number; costUsd: number|null; latencyMs: number
}
```

Sequência de um turno: `ensureUser` → `checkSubscription` (gate) → `loadContext` → `resolveStage` → `loadActivePrompt` (filtra prompt por idioma, −token) → roteamento de modelo → filtro de tools → system prompt em 2 blocos (estável com cache Anthropic `ephemeral_1h` + variável com RAG/contexto) → **RAG do método** (`match_method_chunks`, top-5, degradação graciosa) → **loop de tools** (até 5 iterações) → caminhos determinísticos pós-tool (registro/status/reavaliação) → **card canônico** (substitui número alucinado pelo do banco) → redes de finalização (log-only).

### 7.2 As 20 tools expostas ao LLM

Formato OpenAI tool-calling; `parameters` é Zod → JSON Schema. Cada chamada grava em `tools_audit`.

| # | Tool | Parâmetros (resumo) | Grava no banco? |
|---|------|--------------------|-----------------|
| 1 | `cadastra_dados_iniciais` | perfil clínico completo + `onboarding_step/completed` | **Sim** — `user_profiles`, `users.name` |
| 2 | `define_protocolo` | `protocol`, `deficit_level?`, `goal_type?`, `goal_value?` | **Sim** — `user_profiles` |
| 3 | `define_meta_peso` | XOR `target_weight_kg` ou `target_bf_percent` | **Sim** — `user_profiles` |
| 4 | `registra_refeicao` | `meal_type?`, `replace?`, `items[]:{food_name, quantity_g}`, `corrections?[]`, `consumed_date?` | **Sim** — `meal_logs`, `daily_snapshots` (RPC), `user_food_corrections`, `product_events` |
| 5 | `registra_treino` | `workout_type`, `duration_min`, `intensity?`, `estimated_kcal_from_image?` | **Sim** — `workout_logs`, `daily_snapshots` |
| 6 | `consulta_progresso` | `{}` | Não (leitura) |
| 7 | `consulta_metricas` | `{}` | Não (leitura, anti-alucinação) |
| 8 | `consulta_resumo_periodo` | `periodo ∈ {semana, mes}` | Não (leitura) |
| 9 | `consulta_reavaliacao_protocolo` | peso/BF/freq atuais | Não (leitura) |
| 10 | `registra_metrica_diaria` | `water_ml?`, `sleep_hours?`, `steps?` | **Sim** — `daily_snapshots` (upsert) |
| 11 | `marca_refeicao_pulada` | `meal_type`, `reason?` | **Sim (evento)** — `product_events` (`meal.user_skipped`) |
| 12 | `reclassifica_refeicao` | `from_meal_type`, `to_meal_type`, `consumed_date?` | **Sim** — `meal_logs` (só meal_type) |
| 13 | `atualiza_data_user` | `name?`, `timezone?` (IANA), `city?` | **Sim** — `users` |
| 14 | `encerra_atendimento` | `motivo` | **Sim** — metadata (escala p/ humano) |
| 15 | `delete_user` | `confirmacao: 'confirmo'` | **Sim** — `users.status='deleted'` (LGPD) |
| 16 | `pausar_agente` | `days (1-60)`, `reason?` | **Sim** — RPC `pause_user` |
| 17 | `retomar_agente` | `{}` | **Sim** — RPC `resume_user` |
| 18 | `confirma_pais_residencia` | `country`, `language?`, `unit_system?`, `timezone?` | **Sim** — `users` (country/locale) |
| 19 | `gera_dieta` | `horizon`, `meals_per_day?`, `restrictions?`, `preferences?` | **Sim** — `prescriptions` (rate-limit 2/2h) |
| 20 | `gera_treino` | `available_equipment[]`, `location`, `days_per_week`, `training_level`, ... | **Sim** — `training_plans` (rate-limit 1/24h) |

Shape de retorno de `registra_refeicao` (alimenta o card):
```jsonc
{ "success": true,
  "meal": { "items":[{ "name","matched_to","quantity_g","display_qty","display_unit","kcal","protein_g","carbs_g","fat_g","source" }],
            "totals": { "kcal","protein_g","carbs_g","fat_g","fiber_g" } },
  "day_totals": { "calories_consumed","protein_g","calories_target","protein_target","daily_balance" },
  "warnings": [...], "replaced": { "count","kcal_removed" } | null }
```

### 7.3 Roteamento de modelo (`model-router.ts`)

Default = Sonnet (`anthropic/claude-sonnet-4.6`, de `v_active_prompts.model`). Haiku = `anthropic/claude-4.5-haiku-20251001`, controlado por flag `router.haiku_enabled`. **Mantém Sonnet** em mídia, onboarding, reentrada, pending aberto, texto longo, keyword de comida/treino. **Troca p/ Haiku** em medição pura ("75kg"), saudação trivial, pergunta de status.

### 7.4 Detectores e defesas (anti-alucinação / escrita-fantasma)

- **De texto do LLM (forçam retry):** `fake-write-detector` (afirma registro sem chamar tool), `false-duplication-detector`, `detectPrematureBlockCompletion`.
- **Semânticos do paciente (em tools):** `correction-detector`, `addition-intent-detector` ("segunda fatia" cancela replace), `phantom-item-detector`, `consumed-date-detector`, `express-mode-detector`, `pending-response-detector` (digitar "sim" = tap), `numeric-validator` (compara números da resposta com o banco, threshold 10%, log-only).
- **Classificadores puros:** `weight-goal-classifier`, `bf-goal-classifier`, `meal-patterns`, `personal-meal-windows` (janela meal_type por paciente).
- **Hard-guards pós-LLM (`tools/`, recusam antes do execute):** `registra_refeicao-guard` (empty/implausible/duplicate), `marca_refeicao_pulada-guard`.

### 7.5 Geração de dieta/treino e botões

- `gera_dieta` → `DietPlan` (refeições + lista de compras, usa top-30 alimentos do paciente, TACO, validação Zod).
- `gera_treino` → `TrainingPlan` (split por músculo, séries/reps, RPE, execução). Entregue diariamente por cron sem custo de LLM.
- **Botões WhatsApp:** onboarding (`[BTN:...]`/`[LIST:...]` → `btn_<field>_<value>`); proposta de registro (`confirm_<pendingId>`/`edit_<pendingId>`). O tap fecha o circuito do lado humano: agente propõe → paciente toca → sistema grava determinístico.

---

## 8. Provedores de IA e serviços externos

Pacote `@mpp/providers`. **Resolução de credenciais** (`credentials.ts`): tabela `service_credentials` (editável por admin) → fallback `process.env`; cache em memória TTL 60s.

| Capacidade | Serviço | Modelo (default) | Base URL | Env / credencial |
|---|---|---|---|---|
| **LLM** | OpenRouter (SDK `openai`) | `anthropic/claude-sonnet-4.6` (conversa), `anthropic/claude-4.5-haiku` (router/edu/TTS-rewrite) | `https://openrouter.ai/api/v1` | `OPENROUTER_API_KEY`, `HELICONE_API_KEY?` |
| **Vision** | OpenRouter | `anthropic/claude-sonnet-4.5` (default real; rótulo nutricional `anthropic/claude-sonnet-4.6`) | idem | idem |
| **STT** | Groq (SDK `openai`) | `whisper-large-v3-turbo` (pt) | `https://api.groq.com/openai/v1` | `GROQ_API_KEY` |
| **Embeddings** | OpenRouter | `openai/text-embedding-3-large`, **truncado a 1024 dims** | idem | `OPENROUTER_API_KEY` |
| **TTS (âncora)** | ElevenLabs (`fetch`) | `eleven_multilingual_v2`, voz Dr. Roberto `oArP4WehPe3qjqvCwHNo` | `api.elevenlabs.io/v1/text-to-speech/{voiceId}` | `ELEVENLABS_API_KEY`, `ELEVENLABS_VOICE_ID` |
| **TTS (operacional)** | Cartesia (`fetch`) | `sonic-2` (pt) | `api.cartesia.ai/tts/bytes` | `CARTESIA_API_KEY`, `CARTESIA_VOICE_ID` |
| **Mensageria** | WhatsApp Cloud (Meta Graph) | — | `graph.facebook.com/v21.0` | `META_*` (ver Cap. 9) |
| **Observabilidade LLM** | Helicone (proxy opcional) | — | headers `Helicone-*` | `HELICONE_API_KEY` |

### 8.1 LLM — contrato (`OpenRouterLLM.complete`)

```ts
// Entrada
{ model, systemPrompt: string | {text; cache?:'ephemeral'|'ephemeral_1h'}[],
  messages, temperature?(0.4), maxTokens?(8192), tools?, cacheTools?, toolChoice?,
  responseFormat?:{type:'json_object'}, metadata?, userId? }
// Saída
{ content, toolCalls:{id,name,arguments}[], promptTokens, completionTokens, totalTokens,
  cacheCreationInputTokens?, cacheReadInputTokens?, costUsd, model, finishReason, latencyMs }
```

**Prompt caching Anthropic** via OpenRouter: blocos `{type:'text', text, cache_control}`; `ephemeral`=5min, `ephemeral_1h`=1h. `cacheTools` cacheia o último tool. **Helicone** (se `heliconeApiKey`): headers `Helicone-Auth`, `Helicone-User-Id`, `Helicone-Property-*` (de `metadata`).

### 8.2 Vision — multi-prompt (`vision/gemini.ts`, classe legada `GeminiVision`)

6 tipos de imagem: `meal | body | scale | nutrition_label | equipment | other`. `analyzeImage(url, {hint?})`: se sem hint, `classify()` barato (12 tokens) escolhe o tipo, despacha para analisador dedicado.

> **Default de modelo em duas camadas (importante para operação):** a classe `GeminiVision` (provider) tem default de construtor `anthropic/claude-sonnet-4.5` ([gemini.ts:434](../packages/providers/src/vision/gemini.ts#L434)). Mas no caminho de produção o worker `process-message` chama `loadVisionConfig` ([runtime-config.ts:83](../packages/inngest-functions/src/lib/runtime-config.ts#L83)), que lê `global_config.vision.model` com fallback **`google/gemini-2.5-flash`** e o passa ao construtor, **sobrescrevendo** o default Claude. Ou seja: o modelo efetivo é o de `global_config.vision.model`; se essa chave for removida, o caminho de produção cai para **Gemini 2.5 Flash**, não para Claude. (`nutrition_label_model` default `anthropic/claude-sonnet-4.6`.) Cada um pede `response_format:json_object`, mas o parser `parseJsonLoose()` tolera JSON sujo (code fences, bloco balanceado). Saídas tipadas por analisador (ver schema meal/body/scale/nutrition_label/equipment abaixo):

```jsonc
// meal
{ "items":[{"name":"2x ovo frito","quantity_g_estimate":100,"confidence":0.92}], "meal_context":"..." }
// scale
{ "weight_kg":87.4, "confidence":0.95, "unit_detected":"kg" }   // lb→kg automático
// nutrition_label (OCR ANVISA, números pt-BR)
{ "product_name":"...", "serving_size_g":170, "per_serving":{...}, "per_100g":{...}, "confidence":0.92 }
```

### 8.3 TTS híbrido (`tts/router.ts`)

Mensagens-âncora (`welcome, daily_closing, reevaluation, block_completed, badge_earned`) → **ElevenLabs**. Demais (`standard`) → **Cartesia** (~6× mais barato). `rewriteForTTS` (Haiku) transforma texto cru em script falável (1ª pessoa, números por extenso, `<break>`); há atalho sem LLM para textos curtos e versão determinística por regex. Cache em memória + tabela `tts_cache`.

---

## 9. Mensageria WhatsApp — envelope e payloads exatos

Abstração `MessagingProvider` (adapter). Implementadores: `WhatsAppCloudProvider` (prod), `ConsoleProvider` (dev). Factory por `MESSAGING_PROVIDER` (default `console`).

### 9.1 Envelope canônico (interno)

```ts
type ContentType = 'text'|'audio'|'image'|'template'|'interactive'
interface NormalizedInbound {
  providerMessageId: string   // idempotência
  from: string                // E.164 sem '+'
  type: ContentType
  text?: string               // texto OU caption
  mediaUrl?: string           // media id Meta
  mediaMimeType?: string
  timestamp: Date
  raw: unknown                // payload bruto
}
interface SendResult { providerMessageId: string|null; status:'queued'|'sent'|'failed'; error? }
interface InteractiveButton { id: string; title: string }       // id ≤256, title ≤20
interface InteractiveListItem { id; title; description? }        // id ≤200, title ≤24, desc ≤72
```

Interface `MessagingProvider`: `sendText/sendAudio/sendImage/sendTemplate/sendInteractive/sendInteractiveList/react/uploadMedia/downloadMedia/markRead/showTypingFor/parseInbound/verifyWebhook/getQualityStatus`.

### 9.2 Payloads de envio (Graph API `POST {base}/{phoneNumberId}/messages`)

```json
// texto
{ "messaging_product":"whatsapp","to":"<E164>","type":"text","text":{"body":"...","preview_url":false} }
// imagem
{ "messaging_product":"whatsapp","to":"<E164>","type":"image","image":{"link":"https://...","caption":"..."} }
// interactive — botões reply (max 3; intra-24h, sem template)
{ "messaging_product":"whatsapp","to":"<E164>","type":"interactive",
  "interactive":{"type":"button","body":{"text":"..."},
    "action":{"buttons":[{"type":"reply","reply":{"id":"confirm_<id>","title":"Sim, registrar"}}]}} }
// interactive — list (1-10 rows)
{ "interactive":{"type":"list","body":{"text":"..."},
    "action":{"button":"Escolher","sections":[{"title":"Opções","rows":[{"id":"...","title":"...","description":"..."}]}]}} }
// template HSM (fora da janela 24h)
{ "type":"template","template":{"name":"...","language":{"code":"pt_BR"},
    "components":[{"type":"body","parameters":[{"type":"text","text":"<v>"}]}]} }
```

Sucesso: `{ messages:[{id}] }` → `providerMessageId`. **Humanizer** quebra a resposta em até ~3 bolhas de ≤280 chars com delay proporcional e typing real.

### 9.3 Webhook de entrada

`verifyWebhook`: HMAC SHA-256 do raw body comparado em tempo constante com `x-hub-signature-256` (`sha256=<hmac(app_secret, body)>`). `parseInbound` espera o envelope Meta `entry[].changes[]` com `field==='messages'`; extrai `text/image/audio/video` (vídeo cai em `text`). `mediaUrl` é o **media id** (não URL final — resolver via Graph API). **Taps interativos** (`button_reply`/`list_reply`) e status são tratados no `webhook-whatsapp` (Edge Fn), não neste parser.

---

## 10. Workers Inngest, eventos e crons

Cliente: `new Inngest({ id:'agentempp', schemas: EventSchemas().fromRecord<Events>() })`. Endpoint único `/api/inngest` (Vercel). Envelope de evento: `{ name, data, ts? }` POSTado a `https://inn.gs/e/{INNGEST_EVENT_KEY}`.

### 10.1 Contrato de eventos Inngest (nomes EXATOS — pontos de integração)

| Evento | `data` | Quem dispara |
|---|---|---|
| `message.received` | `{ userId, wpp, providerMessageId, contentType, text?, mediaUrl?, mediaUrls?, provider, timestamp }` | buffer-listener, interactive-handler |
| `buffer.flush` | tipo declarado `{ count, fired_at }` (o webhook adiciona `userId` ao payload em runtime) | webhook-whatsapp (delay), buffer-listener |
| `interactive.button.tapped` | `{ userId, wpp, buttonId, buttonTitle?, providerMessageId?, tappedAt }` | webhook-whatsapp (tap imediato), process-message (fallback texto) |
| `day.close.tick` | `{ hour, fired_at }` | pg_cron (4×/dia) |
| `engagement.tick` | `{ slot, fired_at }` | pg_cron (5×/dia) |
| `wa.quality.check` | `{ fired_at }` | pg_cron (30min) |
| `pipeline.health.tick` | `{ fired_at }` | pg_cron (5min) |
| `subscription.event` | `{ provider_event_id, event_type, raw }` | **declarado-mas-órfão** — `webhook-stripe` escreve direto em `subscriptions`/`subscription_events`, nenhum worker consome este evento |
| `openrouter.balance.tick` | `{ fired_at }` | **órfão/deprecado** — substituído por cron nativo em `openrouter-balance-check` (não confie neste evento) |
| `audit.daily.tick` | `{ fired_at }` | **órfão/deprecado** — `daily-audit` migrou para cron nativo |

> **Triggers secundários:** além do evento principal, alguns workers registram um 2º trigger de evento (ex.: `process-message`↔`vision.analyzed`, `interactive-handler`↔`pending.confirmed`, `daily-closer`↔`badge.earned`, `pipeline-health`↔`pipeline.stuck`, `wa-quality-check`↔`wa.quality.degraded`). São pontos de integração de evento adicionais.
>
> **Atenção a namespaces:** alguns nomes coincidem entre o **event-bus Inngest** (esta tabela) e o **event-store `product_events`** (Cap. 14) — ex.: `message.received`, `interactive.button.tapped`, `buffer.flush`, `vision.analyzed`, `wa.quality.check`. São namespaces distintos (fila vs telemetria SQL), apesar do nome igual.

### 10.2 As 16 funções Inngest

| Função | Trigger | O que faz |
|---|---|---|
| `buffer-listener` | `buffer.flush` | Debounce; gate vision-inflight; agrega → emite `message.received` |
| `process-message` | `message.received` | **Worker principal:** STT/Vision → `processMessage` (LLM+tools) → envio (interactive/TTS/humanized) |
| `interactive-button-handler` | `interactive.button.tapped` | Tap: `confirm_/edit_` (pending) e `btn_<field>_<value>` (onboarding); grava determinístico |
| `daily-closer` | `day.close.tick` | **Fecha o dia:** consolida snapshot, credita bloco 7700, XP/streak/badges, dispara reavaliação 14d |
| `daily-gap-checker` | `day.close.tick` | Pré-fechamento (21h-23h local): detecta gap de refeição e lembra |
| `meal-gap-reminder` | cron `0 10-19 * * *` BRT | Lembretes proativos **sem LLM** (opt-in, gap≥4h + proteína baixa) |
| `engagement-sender` | `engagement.tick` | **Mensagens proativas com LLM** (Haiku, slots por hora local, frase curada, guards anti-alucinação) |
| `training-daily-delivery` | cron `0 * * * *` | Entrega o treino do dia **sem LLM** (opt-in, hora local) |
| `sample-judge` | cron `0 10,22 * * *` BRT | **LLM-as-judge** (amostra ~10% OUT, `JUDGE_MODEL=gpt-4o-mini`, grava `llm_evaluations`) |
| `regression-beacon` | cron `0 * * * *` | Compara 5 métricas (1h vs baseline 7d), alerta Telegram |
| `pipeline-health-check` | `pipeline.health.tick` | Detecta pipeline parado → auto-sync Inngest (`PUT`) |
| `openrouter-balance-check` | cron `0 4,10,16,22 * * *` BRT | Saldo OpenRouter, alerta Telegram se baixo |
| `wa-quality-check` | `wa.quality.check` | Quality rating do número (Meta) → `whatsapp_phone_status` |
| `food-db-gaps-report` | cron `0 9 * * 1` BRT | Relatório semanal de alimentos sem match → Telegram |
| `pending-registrations-cleanup` | cron `*/5 * * * *` | Expira `pending_registrations` |
| `daily-audit` | cron `0 8,12,15,18,21 * * *` BRT | **Auditoria 24h** + auto-reconcile do bloco 7700 (circuit-breaker `MAX_BLOCO_FIX=8`) + relatório Telegram |

### 10.3 Crons via pg_cron → Inngest (em UTC)

`engagement-morning/late-morning/afternoon/evening/night` (5 slots) · `daily-closer-0030/0130/0230/0330` (cobre fusos BR) · `wa-quality-check` (`*/30`) · `pipeline-health` (5min) · `cleanup-processed-messages`. A função SQL `dispatch_inngest_event` faz a ponte via `pg_net`.

> O `daily-closer` só processa cada paciente quando a meia-noite **local** dele bate (timezone por usuário em `users.timezone`); por isso o mesmo `day.close.tick` dispara 4× ao dia.

---

## 11. Edge Functions (webhooks e endpoints públicos)

Runtime **Deno** (`Deno.serve`). Base de URL: `https://xuxehkhdvjivitduarvb.supabase.co/functions/v1/<nome>`. Cada função implementa **sua própria autenticação** (JWT do Supabase desabilitado para os webhooks de terceiros). Todas usam `SUPABASE_SERVICE_ROLE_KEY`.

| Função | Método | Público | Auth | Dispara depois |
|---|---|---|---|---|
| `webhook-whatsapp` | GET/POST | Sim (Meta) | `hub.verify_token` (GET) + HMAC `x-hub-signature-256` (POST) | Inngest `interactive.button.tapped`/`buffer.flush`; escreve `messages`/`processed_messages`/`users`; RPC `buffer_append_msg` |
| `webhook-stripe` | POST | Sim (Stripe) | assinatura `Stripe-Signature` (`webhook_secret`) | upsert `subscriptions`; `subscription_events` |
| `telegram-webhook` | POST | Sim (Telegram) | `x-telegram-bot-api-secret-token` + `from.id == ADMIN` | aplica fix → `food_db`; `pending_approvals`; `audit_log` |
| `notify-telegram` | POST | Não (interno) | header `x-audit-secret` | `pending_approvals`; Telegram `sendMessage` (botões inline) |
| `audit-findings` | GET | Não | `x-audit-secret` | nada (read-only; agrega bugs 8h) |
| `audit-auto-fix` | POST | Não | `x-audit-secret` | `food_db` (só `food_alias`); `audit_log`; `product_events` |

### 11.1 `webhook-whatsapp` (entrada principal)

- **GET** (challenge Meta): query `hub.mode/hub.verify_token/hub.challenge` → `200` ecoando o challenge.
- **POST**: valida HMAC; idempotência via `processed_messages` (PG `23505` → pula); ensure user; **status updates** → `UPDATE messages.delivery_status`; **tap** → Inngest `interactive.button.tapped` (sem buffer); **mensagem normal** → grava `messages` + RPC `buffer_append_msg` → Inngest `buffer.flush` (delay = `buffer.debounce_ms`, fallback **8000ms**).

### 11.2 `webhook-stripe` (billing)

Idempotência por `provider_event_id`. Eventos tratados: `checkout.session.completed`, `customer.subscription.created/updated/deleted`, `invoice.payment_succeeded/failed` → upsert `subscriptions` (mapeia status Stripe → `sub_status`; plano de `price.lookup_key`). Casa o user por `metadata.user_id > metadata.wpp > customer_email`.

### 11.3 Telegram (canal admin / "Margot")

`notify-telegram` cria `pending_approvals` e envia mensagem com botões inline `[✅ Aprovar][❌ Rejeitar]` (`callback_data: approve:<id>`/`reject:<id>`). `telegram-webhook` recebe o callback, aplica `applyFix` (hoje só `food_alias` → INSERT `food_db`) e edita a mensagem. Os três endpoints `audit*`/`notify` compartilham o segredo `AUDIT_SECRET` no header `x-audit-secret`.

---

## 12. Painel administrativo e configuração em runtime

`@mpp/admin` — Next.js 15 App Router, Tailwind + shadcn/ui, auth Supabase SSR (magic link). Autorização por tabela `admin_users` (roles `admin/editor/viewer`).

### 12.1 Telas (grupo `(admin)/`)

`/dashboard` (KPIs + fila de atenção + MRR) · `/messages` (inbox WhatsApp realtime) · `/users` + `/users/[id]` (ficha + checkout Stripe) · `/crescimento` (receita/conquistas/cohorts) · `/prompts` + `/prompts/[id]` (editor de `agent_rules` com histórico de versões + diff) · `/prompts/playground` (testa a **pipeline real**) · `/settings/agents` (config por stage) · `/settings/tools` (catálogo das 20 tools) · `/settings/global` · `/settings/calc` + `/formulas` (constantes `calc.*`) · `/settings/foods` (CRUD `food_db`) · `/settings/api-keys` (`service_credentials`) · `/settings/stripe` · `/settings/crons` (pg_cron) · `/settings/admins` · `/tutorial` · `/evaluations` (LLM-judge) · `/audit`.

### 12.2 API Routes (HTTP)

| Rota | Método | Propósito | Auth |
|---|---|---|---|
| `/api/inngest` | GET/POST/PUT | serve das 16 Inngest functions | Inngest signing (`INNGEST_SIGNING_KEY`) |
| `/api/media/[id]` | GET | proxy de mídia WhatsApp (resolve media id → bytes via Graph) | cookie admin |
| `/api/admin/send-message` | POST | **envio manual de WhatsApp** ao paciente | **Bearer = `SUPABASE_SERVICE_ROLE_KEY`** (server-to-server) |
| `/api/stripe/checkout` | POST | cria Checkout Session multi-moeda | cookie admin |
| `/api/stripe/setup-products` | POST | cria/atualiza catálogo Stripe (idempotente) | cookie admin |

`/api/admin/send-message` — request `{ user_id, text }`, response `{ success, user_id, wpp, delivery_status, error }`. **Este é o endpoint server-to-server mais direto para um sistema externo enviar uma mensagem WhatsApp pelo agente** (autenticado pela service role key).

### 12.3 Configuração em runtime (sem deploy)

Filosofia: **nenhuma decisão clínica/nutricional/gamificação/conversa fica trancada em código.** Tudo mora em `global_config`, `agent_configs`, `agent_rules`, `service_credentials`, `food_db`. Workers cacheiam config por **60s** → mudança reflete em ≤1 min. Toda mutação grava `audit_log`.

Grupos de `global_config` (por prefixo): `rate_limit.*` · `alerts.*` · `tts.*` · `vision.*` · `engagement.*` · `humanizer.*` · `buffer.*` · `attention.*` · `numeric_validator.*` · `persona.*` · `country_to_language.*` · `calc.*` (constantes de cálculo, UI dedicada).

---

## 13. Billing Stripe multi-moeda

Catálogo `STRIPE_CATALOG`: 1 produto por plano, N preços (1 por moeda), chave estável = `lookup_key`.

| Plano | Intervalo | Trial | BRL | USD | EUR |
|---|---|---|---|---|---|
| Mensal (`mpp_mensal_<moeda>_v1`) | mês | 7d | R$197,00 | US$39,00 | €37,00 |
| Anual (`mpp_anual_<moeda>_v1`) | ano | 7d | R$1.164,00 | US$239,00 | €229,00 |

Moeda por país: `BR→brl`; UE→`eur`; resto→`usd`. `createCheckoutSession`: `mode:'subscription'`, `metadata:{user_id, wpp}` (o webhook usa para casar). Webhook configurado fora do painel: `https://xuxehkhdvjivitduarvb.supabase.co/functions/v1/webhook-stripe`.

---

## 14. Telemetria `product_events` (catálogo de eventos)

Tabela "espelho local do PostHog para queries SQL". **Esta é a principal superfície de observabilidade para integração analítica/BI.**

```sql
CREATE TABLE product_events (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid REFERENCES users(id) ON DELETE CASCADE,  -- nullable
  event text NOT NULL,             -- dot.notation
  properties jsonb,                -- payload livre (sempre inclui level, stage)
  occurred_at timestamptz NOT NULL DEFAULT now()
);
-- índices: (user_id, occurred_at DESC), (event, occurred_at DESC)
```

Helper de escrita `emitEvent()` ([packages/agent/src/telemetry.ts](../packages/agent/src/telemetry.ts)) é never-throw. Famílias de eventos (catálogo exaustivo extraído do código):

- **Pipeline/mensageria:** `message.received`, `pipeline.deterministic_registration|status|reeval`, `pipeline.express_used`, `pipeline.pending_created`, `pipeline.model_routed`, `pipeline.user_kcal_override`, `pipeline.duplicate_meal_suppressed`, `pipeline.onboarding_button_sent|list_sent`, `pipeline.auto_sync`, `pipeline.stuck`, `pipeline.error`, `pipeline.health.tick`
- **Vision:** `vision.analyzed|completed|failed|download_failed|model|meal.confidence_threshold`
- **Anti-alucinação (LLM):** `llm.fake_write_detected|unresolved`, `llm.fake_skip_unresolved`, `llm.numeric_mismatch`, `llm.card_replaced`, `llm.loose_bloco_replaced`, `llm.balance_prose_reconciled`, `llm.deficit_real_mismatch`, `llm.false_duplication_caught`, `llm.premature_block_completion`, `llm.sentiment_mismatch`, `llm.cache_usage`
- **Tools/guards:** `tool.consumed_date_injected`, `tool.items_deduped`, `tool.meal_logs_insert_failed`, `tool.meal_type_reclassified`, `tool.phantom_items_blocked`, `tool.replace_*`, `tool.workout_replaced`, `tool_rejected_by_guard`
- **Botões/pending:** `interactive.button.tapped`, `interactive.onboarding_tap`, `pending.created|confirmed|edited|expired|not_found|duplicate_tap`, `tap.blocked_zero_kcal`
- **Bloco 7700 / closer:** `bloco7700.block_completed|skipped_inactive_day|skipped_incomplete_day|skipped_subregistro`, `daily_closer.completed|skipped`, `day.close.tick`, `daily.gap_reminder_sent`
- **Engajamento/frases:** `engagement.tick|sent|skipped|failed|bloco_reconciled|hallucinated_closure`, `edu_comment.curated_hit|curated_miss|haiku_*|skipped_*`
- **Comida:** `food_correction.applied|confirmed|learned|contradicted`, `meal.match_warning`, `meal.user_skipped`
- **Reavaliação/gamificação:** `reevaluation.due|check_failed`, `metric.captured`, `badge.earned`, `streak.reset_inactive`, `agent.paused|resumed`
- **Auditoria/judge/beacon:** `audit.daily_report|bloco_autofixed|telegram_failed`, `sample_judge.completed|skipped`, `regression_beacon.tick|alert`
- **Dieta/treino:** `training.plan_generated|daily_delivered|generation_failed`, `diet.generated|generation_failed`
- **Infra/billing:** `buffer.flush`, `wa.quality.check|degraded`, `country.confirmed`, `openrouter.balance_checked`, `human.escalation_requested`, `user.delete_requested`, `food_db.gaps_report`

---

## 15. Superfícies de integração — o mapa

Esta é a seção-âncora para a pesquisa: **todas as fronteiras onde um sistema externo pode entrar ou sair**, classificadas por direção e tipo.

### 15.1 Inbound — coisas que recebem dados de fora (webhooks/endpoints)

| Superfície | URL / contrato | Auth | Para integrar… |
|---|---|---|---|
| **WhatsApp inbound** | `…/functions/v1/webhook-whatsapp` (POST) | HMAC SHA-256 Meta | injetar mensagens de paciente (formato Meta) |
| **Stripe webhook** | `…/functions/v1/webhook-stripe` (POST) | `Stripe-Signature` | eventos de billing externos |
| **Telegram callbacks** | `…/functions/v1/telegram-webhook` (POST) | secret_token + admin id | aprovar/rejeitar fixes |
| **Auditoria push** | `…/functions/v1/notify-telegram` (POST) | `x-audit-secret` | criar uma aprovação manual (food_alias, config, rule, bug) |
| **Auditoria pull** | `…/functions/v1/audit-findings` (GET) | `x-audit-secret` | ler bugs agregados (8h) — JSON estruturado |
| **Auto-fix** | `…/functions/v1/audit-auto-fix` (POST) | `x-audit-secret` | aplicar `food_alias` em lote |
| **Envio manual WhatsApp** | `https://agentempp.vercel.app/api/admin/send-message` (POST) | `Bearer SERVICE_ROLE_KEY` | **enviar WhatsApp pelo agente, server-to-server** |
| **Stripe checkout** | `…/api/stripe/checkout` (POST) | cookie admin | gerar link de assinatura |
| **Inngest serve** | `…/api/inngest` | Inngest signing | registrar/executar workers |

### 15.2 Outbound — coisas que o sistema chama (clientes a serviços externos)

| Destino | Endpoint / formato | Disparado por |
|---|---|---|
| **Inngest ingest** | `POST https://inn.gs/e/{EVENT_KEY}` body `{name,data,ts?}` | pg_cron (`dispatch_inngest_event`), edge fn, SDK |
| **OpenRouter** (LLM/Vision/Embeddings) | `https://openrouter.ai/api/v1` (SDK openai); saldo `GET /api/v1/key` | agent, workers |
| **Groq** (STT) | `https://api.groq.com/openai/v1` | process-message |
| **ElevenLabs / Cartesia** (TTS) | `api.elevenlabs.io` / `api.cartesia.ai` | process-message, engagement |
| **WhatsApp Cloud** (envio) | `POST graph.facebook.com/v21.0/{phoneId}/messages` | process-message, lembretes (alguns via `v18.0` direto) |
| **Telegram Bot API** | `POST api.telegram.org/bot{token}/sendMessage` | daily-audit, beacon, balance, gaps-report |
| **Stripe API** | SDK `stripe@22` | checkout, setup-products, webhook handler |
| **Helicone** (opcional) | proxy/headers sobre OpenRouter | LLM/Vision |

### 15.3 Event bus (Inngest) — pontos de extensão por evento

Qualquer worker novo pode escutar os eventos do [Cap. 10.1](#101-contrato-de-eventos-inngest-nomes-exatos--pontos-de-integração). Os mais úteis para integração: `message.received` (cada turno de paciente), `interactive.button.tapped` (tap), `day.close.tick` (fechamento diário), `engagement.tick` (proatividade), `subscription.event` (billing). Para **emitir** um evento de fora, basta `POST inn.gs/e/{EVENT_KEY}` com o envelope `{name, data}`.

### 15.4 Data layer (Supabase) — o caminho mais rico

- **REST/PostgREST** sobre `public` (gated por RLS; service_role faz bypass). Tabelas-chave para BI: `daily_snapshots`, `meal_logs`, `user_progress`, `subscriptions`, `messages`, `product_events`.
- **RPCs públicas/semipúblicas:** `match_food_phrases`, `match_method_chunks`, `search_food_*`, `agent_kpis`, `get_global_config`/`set_global_config`.
- **Views de leitura:** `v_user_metrics`, `v_active_prompts`, `v_daily_cost`, `v_cron_jobs`, `mv_kpis_daily`.
- **Realtime:** o painel já consome `messages` via websocket — um integrador pode assinar o mesmo canal.
- **Telemetria:** `product_events` é um event-store SQL pronto para ETL/dashboards externos.

### 15.5 Registro de credenciais (extensão de provedores)

`service_credentials (service, key_name, value, is_active)` é o catálogo central, editável pela UI (`/settings/api-keys`), lido por workers/edge em ≤60s. Services existentes: `openrouter`, `groq`, `elevenlabs`, `cartesia`, `helicone`, `sentry`, `inngest`, `meta_whatsapp`, `stripe`, `resend`. **Adicionar um novo provedor externo = adicionar um service aqui + um adapter em `@mpp/providers`.**

### 15.6 Pontos de extensão no código

| Quero… | Onde plugo |
|---|---|
| Nova **capacidade de IA** (ex. outro vision/STT) | novo adapter em `packages/providers/src/<cap>/` + `service_credentials` |
| Nova **tool do agente** | `packages/agent/src/tools.ts` (`ALL_TOOLS`) — Zod schema + `execute` |
| Novo **canal de mensagem** (Telegram/SMS/Instagram) | implementar `MessagingProvider` + factory |
| Novo **worker/cron/automação** | `packages/inngest-functions/src/functions/` (escuta evento ou cron) |
| Nova **fonte de alimentos** | `food_db` (seed) + `search_food_*` |
| Novo **conhecimento RAG** | `method_chunks` + embeddings + `match_method_chunks` |
| Nova **tela/relatório admin** | `apps/admin/src/app/(admin)/` |
| Nova **regra de cálculo** | `packages/core` (código + teste + doc na mesma PR) |

---

## 16. Cenários de integração recomendados

Catálogo de "onde dá pra entrar", com o caminho técnico de cada um.

1. **Sincronizar pacientes/assinaturas com um CRM externo.** Fonte: tabelas `users`/`user_profiles`/`subscriptions` via PostgREST (service role) **ou** webhook reverso lendo `product_events` (`country.confirmed`, `subscription.event`). Stripe já é a fonte de billing — espelhar `subscriptions`.

2. **Disparar mensagens WhatsApp a partir de outro sistema** (ex.: app do nutricionista, automação de marketing). Caminho direto: `POST /api/admin/send-message` com `Bearer SERVICE_ROLE_KEY`. Para fluxos conversacionais completos, emitir `message.received` no Inngest.

3. **Dashboard/BI externo (Metabase, Looker, Grafana).** Conectar direto ao Postgres (read replica/service role) e consumir `mv_kpis_daily`, `v_daily_cost`, `product_events`, `daily_snapshots`. O event-store `product_events` é ideal para funis e qualidade.

4. **Pipeline de qualidade/observabilidade.** `product_events` (`llm.*`, `tool_*`, `sample_judge.*`) + `tools_audit` + `llm_evaluations` + Helicone. Um consumidor externo pode escutar `audit.daily_report`/`regression_beacon.alert` (hoje vão para Telegram) e redirecionar para Slack/PagerDuty.

5. **Integração de wearables / health data** (passos, sono, peso, balança Bluetooth). Escrever em `daily_snapshots` (steps/sleep/water) via RPC `registra_metrica_diaria` ou direto; peso via `user_progress`. A tool `registra_metrica_diaria` já existe como ponto de entrada normalizado.

6. **Base nutricional ampliada / parceria de dados de alimentos.** Popular `food_db` (multi-país já suportado por `country_code`) e/ou alimentar `food_education_phrases`/`method_chunks` para RAG. O fluxo de aprovação (`notify-telegram` → `audit-auto-fix`) já existe para curadoria semi-automática de `food_alias`.

7. **Novo canal de atendimento** (Instagram DM, Telegram do paciente, web chat). Implementar `MessagingProvider` + factory; o restante do pipeline (tools, cálculo, card) é agnóstico de canal.

8. **Exportação / portabilidade (LGPD).** A tool `delete_user` já cobre o direito ao esquecimento; para exportação, ler todas as tabelas com `user_id` via service role.

9. **Pagamentos alternativos (Pix, gateways locais).** Substituir/complementar o `webhook-stripe` por um novo webhook Edge Function que escreve em `subscriptions`/`subscription_events` (mesmo schema), mantendo o gate de assinatura intacto.

10. **Embeddings/semantic search externo.** As RPCs `match_food_phrases`/`match_method_chunks` e a coluna `message_embeddings` (vector 1024) permitem que um sistema externo reaproveite a memória semântica (mesma dimensão `text-embedding-3-large` truncado a 1024).

> **Recomendações transversais para qualquer integração:**
> - Respeitar a **tese central**: escreva dados de paciente sempre via tool determinística ou RPC, nunca números "no olho" (há auditoria automática que reverte divergências de bloco).
> - `daily_snapshots.daily_balance` é **coluna gerada** — não tente setá-la.
> - Idempotência é convenção do sistema (`provider_message_id`, `provider_event_id`) — replique-a.
> - Config muda em runtime (cache 60s); leia de `global_config`/`service_credentials` em vez de hardcodar.

---

## 17. Catálogo de variáveis de ambiente

| Variável | Serviço | Função |
|---|---|---|
| `SUPABASE_URL` / `SUPABASE_ANON_KEY` / `SUPABASE_SERVICE_ROLE_KEY` | Supabase | API REST, cliente público, service role (workers/edge) |
| `SUPABASE_PROJECT_REF` / `SUPABASE_ACCESS_TOKEN` / `SUPABASE_DB_PASSWORD` | Supabase | Management API (`POST /v1/projects/{ref}/database/query`), `db push` |
| `NEXT_PUBLIC_SUPABASE_URL` / `NEXT_PUBLIC_SUPABASE_ANON_KEY` | Supabase | client browser/SSR no admin |
| `META_APP_ID` / `META_APP_SECRET` / `META_WABA_ID` / `META_PHONE_NUMBER_ID` / `META_ACCESS_TOKEN` / `META_VERIFY_TOKEN` / `META_DISPLAY_PHONE_NUMBER` | WhatsApp Cloud | envio, assinatura webhook, challenge |
| `MESSAGING_PROVIDER` | mensageria | `console` (default) / `whatsapp_cloud` |
| `OPENROUTER_API_KEY` / `OPENROUTER_BASE_URL` | LLM/Vision/Embeddings | OpenRouter |
| `GROQ_API_KEY` | STT | Whisper |
| `HELICONE_API_KEY` | observability | proxy LLM (opcional) |
| `ELEVENLABS_API_KEY` / `ELEVENLABS_VOICE_ID` · `CARTESIA_API_KEY` / `CARTESIA_VOICE_ID` | TTS | âncora / operacional |
| `INNGEST_EVENT_KEY` / `INNGEST_SIGNING_KEY` | workers | enviar eventos / verificar callback |
| `INNGEST_SYNC_URL` | workers | auto-sync (default `…/api/inngest`) |
| `STRIPE_PUBLISHABLE_KEY` / `STRIPE_SECRET_KEY` / `STRIPE_WEBHOOK_SECRET` | billing | checkout / server / webhook |
| `TELEGRAM_BOT_TOKEN` / `TELEGRAM_ADMIN_CHAT_ID` / `TELEGRAM_WEBHOOK_SECRET` | alertas/aprovação | bot Margot |
| `AUDIT_SECRET` | auditoria | header `x-audit-secret` dos endpoints internos |
| `JUDGE_MODEL` | qualidade | LLM-as-judge (default `openai/gpt-4o-mini`) |
| `SENTRY_DSN` / `SENTRY_AUTH_TOKEN` | observability | erros / sourcemaps |
| `RESEND_API_KEY` | email | transacional |
| `GITHUB_OWNER` / `GITHUB_REPO` | infra | `corehealth-app/agentempp` |
| `NODE_ENV` / `LOG_LEVEL` | misc | — |

> Em produção, muitas dessas chaves vivem em `service_credentials` (editáveis na UI) com fallback para `process.env`. Config de comportamento (audit chat ids, judge enabled, engagement, vision model) vive em `global_config`, não em env.

---

## 18. Glossário

| Termo | Significado |
|---|---|
| **MPP** | *Muscular Power Plant* — método do Dr. Roberto Menescal que o agente encarna |
| **CoreHealth** | Empresa cliente/dona (org `corehealth-app`) |
| **Bloco 7700** | Gamificação: 1 kg de gordura = 7700 kcal; o "cofrinho" (`deficit_block`) acumula déficit líquido |
| **Balanço de comida** | `consumido − meta` (sem exercício) — o "Restam/Excedente" do card |
| **Balanço NET / déficit do dia** | `consumido − meta − exercício` (com exercício) — alimenta o bloco |
| **design_deficit** | "Fome programada" (`deficit_level` 400/500/600) embutida na meta de recomposição |
| **Déficit real** | `design_deficit − netBalance`: déficit verdadeiro vs manutenção, comunicado ao paciente |
| **TACO / USDA** | Bases nutricionais (UNICAMP / EUA) do `food_db` |
| **HSM** | Template Meta aprovado, necessário fora da janela de 24h |
| **D-RAG** | RAG do método via pgvector (`method_chunks`); encolheu o prompt ~70% |
| **Escrita-fantasma (fake-write)** | LLM afirma "registrado" sem chamar a tool; alvo de detector + botões |
| **Express mode** | Registro gravado direto (sem botão), só com certeza (texto + gramatura) |
| **Card canônico** | Card re-renderizado pelo sistema a partir do banco (`injectCanonicalCard`) |
| **Margot** | Bot Telegram (`@MargotPiper_Bot`) — alertas de auditoria e aprovações |
| **daily-closer** | Worker que fecha o dia: snapshot + bloco 7700 + gamificação |
| **Reavaliação quinzenal** | Roteiro determinístico a cada 14 dias que recalcula a meta |
| **Protocolo** | `recomposicao` (único ativo) / `ganho_massa` / `manutencao` |

---

## 19. Notas factuais e divergências conhecidas

1. **Vision:** ADR-005 e `README` citam Gemini 2.0 Flash; **produção usa `anthropic/claude-sonnet-4.5`** (classe ainda nomeada `GeminiVision`). Há dois defaults em camadas: o construtor da classe usa `anthropic/claude-sonnet-4.5`, mas o loader `loadVisionConfig` (caminho de produção dos workers) tem fallback `google/gemini-2.5-flash`, sobrescrito por `global_config.vision.model`. Efeito prático: se `global_config.vision.model` for removida, o caminho de produção cai para **Gemini 2.5 Flash** (ver Cap. 8.2 para detalhe).
2. **LLM principal:** `README` cita "Grok 4.1 Fast / DeepSeek V3"; produção usa `anthropic/claude-sonnet-4.6` (conversa) + `anthropic/claude-4.5-haiku` (router). Strings de outros provedores no model-router são apenas comentários.
3. **CI:** o `docs/PLATAFORMA-AGENTE-MPP.md` (2026-06-12) diz "não há CI"; **isso mudou** — `.github/workflows/lint-agent.yml` (gate `no-new-as-any`) foi adicionado em 2026-06-16. Ainda não há CI de deploy.
4. **Estado de produção:** `docs/CONTEXT.md` (2026-05-01, defasado) diz "sem usuários/sem pagantes/`MESSAGING_PROVIDER=console`"; o estado real tem pacientes-piloto e WhatsApp Cloud ativo.
5. **Contagens (verificadas em 2026-06-24):** 65 migrations · 6 Edge Functions · 16 funções Inngest · 20 tools em `ALL_TOOLS` · 5 workspaces `@mpp/*` ativos (+`admin`/`cli`/`scripts`/`eval`).
6. **Versões declaradas vs resolvidas:** as faixas `^` nos `package.json` estão atrás do lockfile (ex.: Next `^15.1.4` instala `15.5.15`; Turbo `^2.5.0` → `2.9.7`; TS `^5.7.3` → `5.9.3`).
7. **Storage:** não há bucket Supabase; mídia é referenciada por media id / URL e obtida via Graph API.

---

*Documento gerado por exploração automatizada do repositório `/root/agentempp` em 2026-06-24. Para detalhes de cada subsistema, ver os arquivos-fonte citados ao longo do texto. Fonte de verdade de cálculo: [docs/CALCULO-MPP.md](CALCULO-MPP.md). Visão de produto e histórico: [docs/PLATAFORMA-AGENTE-MPP.md](PLATAFORMA-AGENTE-MPP.md).*
