# Analise de contexto atual - Agente MPP

Data da varredura: 2026-07-01.

## Resumo executivo

O projeto e um monorepo TypeScript/pnpm/Turbo do Agente MPP, produto da CoreHealth
para coaching nutricional conversacional via WhatsApp. O principio central do sistema
e: o LLM conversa e escolhe tools, mas numeros, calculos e gravacoes sao
deterministicos e auditaveis.

O repositorio esta bem documentado e ja possui bastante regra travada por teste. A
area mais critica e o calculo MPP: meta calorica, balanco de comida, balanco net e
bloco 7700. Antes de qualquer alteracao nessa area, a fonte de verdade e
`docs/CALCULO-MPP.md`; mudanca de formula deve alterar codigo, teste e doc na mesma
PR.

## Estado do repositorio

- Branch local: `main`, rastreando `origin/main`.
- Sem modificacoes rastreadas no momento da analise.
- Arquivos nao versionados relevantes:
  - `docs/AGENTE-MPP-REFERENCIA-INTEGRACAO.md`
  - `docs/PLATAFORMA-AGENTE-MPP.md`
  - `docs/arquitetura-fluxograma.json`
  - `regras-agente-mpp.pdf`
  - scripts pontuais de recover/fix/dry-run em `scripts/`
- Inventario aproximado:
  - 370 arquivos TS/TSX em `apps`, `packages`, `scripts`, `eval`, `supabase`
  - 59 arquivos de teste
  - 66 migrations Supabase
  - 6 Edge Functions Supabase
  - 25 documentos Markdown em `docs/`
  - 39 materiais raiz exportados do Notion/CSV/PDF

## Validacao rodada

Passaram:

- `pnpm --filter @mpp/core test`: 119 testes verdes.
- `pnpm --filter @mpp/agent test`: 795 testes verdes.
- `pnpm --filter @mpp/providers test`: 10 testes verdes.
- `pnpm --filter @mpp/inngest-functions test`: 23 testes verdes.
- `pnpm typecheck`: 8 tarefas Turbo verdes.

Falhou:

- `pnpm lint`: baseline ja esta sujo. Principais categorias:
  - formatacao/import order do Biome;
  - `noNonNullAssertion` em testes/scripts/middleware;
  - `noExplicitAny` legado em providers, Inngest e alguns pontos do agent;
  - scripts operacionais antigos fora do padrao de formatacao.

Recomendacao: nao misturar uma limpeza geral de lint com alteracoes de produto. Para
mudancas novas, evitar aumentar o ruido e validar com testes/typecheck focados.

## Workspaces

- `apps/admin`: painel Next.js 15/React 19 com App Router, auth Supabase, dashboards,
  usuarios, mensagens, prompts, playground, settings, Stripe e endpoints serverless.
- `apps/cli`: chat local de teste contra o agente.
- `packages/core`: motor deterministico puro; formulas, metas, protocolos, bloco,
  progresso e agregados.
- `packages/agent`: pipeline conversacional, tools do LLM, guardrails, detectores,
  geradores de dieta/treino e card canonico.
- `packages/providers`: adapters de LLM, embeddings, STT, vision, TTS e mensageria.
- `packages/db`: cliente Supabase e types gerados.
- `packages/inngest-functions`: workers Inngest, crons e funcoes duraveis.
- `scripts`: seeds, backfills, recoveries, auditorias e operacoes pontuais.
- `eval`: suite de avaliacao com casos JSON.

## Fluxo principal

1. WhatsApp Cloud recebe mensagem.
2. Edge Function `webhook-whatsapp` valida assinatura e coloca no buffer.
3. Inngest `buffer-listener` agrega mensagens e dispara `message.received`.
4. Inngest `process-message` resolve STT/vision quando necessario.
5. `packages/agent/src/pipeline.ts` carrega usuario, contexto, prompt ativo e modelo.
6. LLM chama tools deterministicas.
7. Sistema injeta card canonico calculado a partir do banco.
8. Mensagem sai por provider de mensageria, com opcao de interativos/TTS.

## Regras criticas de calculo

Fonte: `docs/CALCULO-MPP.md`.

- Meta diaria de recomposicao: `BMR * 1.2 - design_deficit`.
- Balanco de comida, exibido como Restam/Excedente: `consumido - meta`, sem
  exercicio.
- Balanco net, usado no bloco: `consumido - meta - exercicio`.
- `daily_snapshots.daily_balance` e coluna gerada no banco; nao deve ser setada
  diretamente.
- Bloco 7700 usa modelo liquido: dia bom soma, dia ruim subtrai, com clamp do total
  em zero.
- Card de balanco e renderizado pelo sistema, nao pelo LLM.
- Backfill/correcao de dado de paciente exige autorizacao explicita do Eduardo.

## Tools do agente

Tools principais em `packages/agent/src/tools.ts`:

- `cadastra_dados_iniciais`
- `define_protocolo`
- `define_meta_peso`
- `registra_refeicao`
- `consulta_progresso`
- `consulta_metricas`
- `registra_treino`
- `atualiza_data_user`
- `encerra_atendimento`
- `delete_user`
- `pausar_agente`
- `retomar_agente`
- `confirma_pais_residencia`
- `reclassifica_refeicao`
- `marca_refeicao_pulada`
- `consulta_reavaliacao_protocolo`
- `registra_metrica_diaria`
- `consulta_resumo_periodo`
- `gera_dieta`
- `gera_treino`

## Workers Inngest

Funcoes exportadas em `packages/inngest-functions/src/index.ts`:

- `process-message`
- `daily-closer`
- `daily-gap-checker`
- `engagement-sender`
- `buffer-listener`
- `wa-quality-check`
- `pipeline-health-check`
- `openrouter-balance-check`
- `daily-audit`
- `sample-judge`
- `interactive-button-handler`
- `pending-registrations-cleanup`
- `food-db-gaps-report`
- `meal-gap-reminder`
- `training-daily-delivery`
- `regression-beacon`

## Admin UI

Areas principais:

- `/dashboard`: KPIs, itens de atencao e saude operacional.
- `/users` e `/users/[id]`: usuarios, perfil, snapshots, assinaturas e acoes.
- `/messages`: inbox/conversas, busca, thread e ferramentas de debug.
- `/prompts`: listagem e editor de prompts.
- `/prompts/playground`: teste conversacional sem WhatsApp.
- `/settings/api-keys`: credenciais runtime.
- `/settings/agents`: modelo, temperatura e tokens por agente.
- `/settings/calc`: config de calculo.
- `/settings/crons`: gerenciamento de pg_cron.
- `/settings/foods`: base de alimentos.
- `/settings/stripe`: setup de produtos.
- `/audit`, `/evaluations`, `/formulas`, `/crescimento`, `/tutorial`.

## Banco e infra

- Supabase project ref documentado: `xuxehkhdvjivitduarvb`.
- Banco Postgres com RLS, pgvector, pg_cron, pg_trgm, unaccent e pg_net.
- Edge Functions:
  - `webhook-whatsapp`
  - `webhook-stripe`
  - `telegram-webhook`
  - `notify-telegram`
  - `audit-findings`
  - `audit-auto-fix`
- Vercel hospeda admin e `/api/inngest`.
- Deploy por `scripts/deploy.sh`, que faz `vercel --prod` e sincroniza Inngest.
  Requer autorizacao explicita do Eduardo.

## Material de referencia local

Priorizar estes documentos:

- `CLAUDE.md`: regras operacionais do projeto.
- `docs/CALCULO-MPP.md`: fonte de verdade de calculo.
- `docs/CONTEXT.md`: estado vivo do projeto.
- `docs/AGENTE-MPP-REFERENCIA-INTEGRACAO.md`: mapa tecnico/integracoes.
- `docs/PLATAFORMA-AGENTE-MPP.md`: explicacao ampla da plataforma.
- `docs/runbook/getting-started.md`: como testar localmente.
- `docs/runbook/deploy-vercel.md`: deploy Vercel.
- `docs/adr/*.md`: decisoes arquiteturais.
- Materiais raiz exportados do Notion/CSV/PDF: regras originais, historico de
  pacientes-piloto, formulas, fases, dashboards e logs.

## Riscos e cuidados antes de alterar

- Mudancas em formula/calculo sao de alto risco e precisam teste + doc.
- Mudancas em registro de refeicao devem respeitar `registra_refeicao`, guards,
  card canonico e detectors anti fake-write/phantom/duplicate.
- Alteracoes em cron/closer podem afetar dados de paciente e bloco 7700.
- Alteracoes em prompts devem ser testadas no playground/eval e considerar que
  prompts ativos vivem no banco.
- `prompts/` local esta estruturado, mas sem arquivos; nao parece ser a fonte ativa.
- Scripts de backfill/recovery possuem dados reais de paciente; nao executar sem
  autorizacao explicita.
- Lint global falha no baseline; nao usar isso como unico gate de merge sem decidir
  antes uma limpeza dedicada.

## Onde mexer por tipo de pedido do cliente

- Comportamento conversacional/prompt: `agent_rules` no banco, admin `/prompts`,
  `packages/agent/src/pipeline.ts` se envolver guardrails.
- Formula, meta, bloco, protocolos: `packages/core/src/**`,
  `packages/agent/src/balance-card.ts`, `packages/inngest-functions/src/functions/daily-closer.ts`,
  `docs/CALCULO-MPP.md`.
- Registro de comida: `packages/agent/src/tools.ts`, `meal-pipeline.ts`,
  guards em `packages/agent/src/tools/*`, food DB/migrations.
- Foto/vision: `packages/providers/src/vision/gemini.ts`,
  `packages/inngest-functions/src/functions/process-message.ts`.
- WhatsApp/interativos: `packages/providers/src/messaging/*`,
  `packages/inngest-functions/src/functions/interactive-handler.ts`,
  `webhook-whatsapp`.
- Admin/backoffice: `apps/admin/src/app/(admin)/**` e componentes em
  `apps/admin/src/components/**`.
- Billing: `apps/admin/src/app/api/stripe/**`, `apps/admin/src/lib/stripe.ts`,
  `supabase/functions/webhook-stripe`.
- Crons/automacoes: `packages/inngest-functions/src/functions/**`,
  migrations de `pg_cron`, `/settings/crons`.
