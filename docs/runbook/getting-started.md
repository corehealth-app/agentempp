# Getting Started — Agente MPP

Como subir e testar o produto **agora mesmo**.

---

## 1. Pré-requisitos

- Node 22+
- pnpm 10+
- Supabase CLI logado (`supabase login`)
- `.env.local` na raiz preenchido (template em `.env.example`)
- `apps/admin/.env.local` preenchido (mesmas chaves NEXT_PUBLIC_* + SUPABASE_*)

## 2. Setup inicial (1 vez)

```bash
# Instala deps
pnpm install

# Aplica migrations no Supabase (ambiente já linkado)
SUPABASE_DB_PASSWORD='<senha>' supabase db push --linked --include-all

# Importa as 88 regras + 6 configs de sub-agentes
pnpm --filter @mpp/scripts seed:notion

# Importa base nutricional TACO (88 alimentos)
pnpm --filter @mpp/scripts seed:taco-minimal

# Valida que os prompts montam corretamente
pnpm --filter @mpp/scripts validate:prompts

# Gera tipos TS do banco (rerodar sempre que migration nova for aplicada)
pnpm db:types
```

## 3. Rodar admin localmente

```bash
pnpm --filter @mpp/admin dev
# abre em http://localhost:3000
```

Acesse `/login`, recebe magic link no email, clica.

**Primeiro acesso:** seu email ainda não está em `admin_users`. Promova-se via:

```bash
ADMIN_EMAIL=seu@email.com pnpm --filter @mpp/scripts bootstrap-admin
```

Recarregue. Agora você vê o dashboard.

## 4. Conversar com o agente (sem WhatsApp)

### Via CLI:
```bash
pnpm --filter @mpp/cli chat
```

### Via Admin:
Acesse `/prompts/playground`. Digite mensagens. Cada turno mostra:
- Stage usado
- Modelo OpenRouter
- Tokens (in + out)
- Custo $
- Latência ms
- Tools chamadas

## 5. Testar o ciclo completo

1. Em `/prompts/playground`, simule um onboarding:
   - "Oi, meu nome é Eduardo"
   - "Sou homem, 35 anos"
   - "tenho 80kg, 1.78m"
   - "treino 4x por semana"
   - … até finalizar 11 perguntas

2. Em `/users`, veja o usuário criado e seus dados.

3. Volte ao playground:
   - "almocei 150g de arroz, 100g de feijão e 120g de frango"
   - O agente deve chamar `registra_refeicao`, calcular macros via TACO,
     e responder com totais.

4. Em `/users/<id>`, veja:
   - O snapshot do dia atualizado
   - Cada item da refeição em meal_logs

5. Clique em **Fechar dia** — gamificação roda:
   - XP soma
   - Streak atualiza
   - Badges desbloqueiam
   - Bloco 7700 acumula

## 6. Ajustes de configuração via UI

Tudo personalizável sem redeploy:

- `/settings/api-keys` — troca chaves de OpenRouter, Groq, ElevenLabs, Cartesia,
  Stripe, Meta, etc. **Cache de 60s** entre admin → workers.
- `/settings/agents` — modelo, temperature, max_tokens por sub-agente.
- `/prompts/<id>` — edita persona/regras (markdown). Cada save cria versão imutável.
- `/settings/crons` — visualiza pg_cron jobs.
- `/settings/admins` — adiciona outros admins (precisa terem feito login antes).

## 7. Quando ativar WhatsApp Cloud API

O `WhatsAppCloudProvider` está pronto em `packages/providers`. Para ativar:

1. Provisione no Meta Developers:
   - App Business
   - WhatsApp Business Account (WABA)
   - Phone Number (verificado)
   - System User com permissões `whatsapp_business_messaging` + `whatsapp_business_management`
   - Permanent Access Token

2. Submeta os 7 templates HSM (utility):
   - welcome, engagement_morning_streak, engagement_check_in, meal_reminder,
     daily_closing, reevaluation_reminder, block_completed

3. No admin `/settings/api-keys` → seção Meta WhatsApp Cloud:
   - app_secret
   - phone_number_id
   - waba_id
   - access_token
   - verify_token (string aleatória que você cria; copie no Meta App webhook)

4. Configure webhook no Meta App apontando para
   `https://<supabase-ref>.supabase.co/functions/v1/webhook-whatsapp`

5. Deploy a Edge Function:
   ```bash
   supabase functions deploy webhook-whatsapp --no-verify-jwt
   ```

6. Mude env var em produção: `MESSAGING_PROVIDER=whatsapp_cloud`.

## 8. Comandos úteis

```bash
# Typecheck tudo
pnpm typecheck

# Tests do core
pnpm --filter @mpp/core test

# Build do admin
pnpm --filter @mpp/admin build

# Eval suite (precisa SUPABASE_* + OPENROUTER_API_KEY no env)
pnpm --filter @mpp/eval eval

# Gera tipos do Supabase após nova migration
pnpm db:types
```

## 9. Estrutura

```
apps/
  admin/      Next.js 15 — painel de controle
  cli/        Chat interativo no terminal

packages/
  core/       Lógica determinística (BMR/TDEE/protocolo/gamificação)
  db/         Tipos Supabase + clients
  providers/  Adapters (LLM/STT/Vision/TTS/Messaging)
  agent/      Pipeline e tools (orquestração do LLM)

scripts/      Seeds e bootstrap
eval/         Suite de avaliação (gate de CI)
supabase/     Migrations + Edge Functions
prompts/      Espelho git das regras (futuro)
docs/adr/     Decisões arquiteturais
```
