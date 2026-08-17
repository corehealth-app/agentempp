# Auditoria Técnica Full Platform - Agente MPP

Data da auditoria: 2026-07-02
Escopo: repositório local `/root/agentempp` + ambientes vivos acessíveis somente em modo leitura.
Modo de execução: read-only para aplicação/infra/banco; único artefato criado/alterado nesta auditoria é este relatório.
Tratamento de dados: PII, mensagens, telefones, emails, tokens e valores de segredos devem ser mascarados ou omitidos.

## Controle Incremental

| Área | Status | Observações |
| --- | --- | --- |
| Baseline e inventário | Concluído | Estado local, ferramentas, Vercel, GitHub e Supabase live registrados. |
| Frontend/admin/APIs Next | Concluído | Rotas, middleware, Server Actions e APIs internas inspecionados. |
| Backend/agente/LLM/tools | Concluído | Pipeline, contexto, validação Zod, guardas, providers e testes inspecionados. |
| Inngest/workers | Concluído | Eventos, concurrency, crons, retries, daily closer, health e auditorias inspecionados. |
| Supabase schema/RLS/RPC/views | Concluído | Schema local e catálogo live consultados em modo leitura. |
| Edge Functions/webhooks | Concluído | Assinaturas, segredos por nome, handlers e funções live inspecionados. |
| DevOps/Vercel/GitHub/CI | Concluído | Metadados e workflows disponíveis inspecionados; branch protection/secrets não validados por limitação de acesso. |
| Dependências/checks | Concluído | Testes/typecheck/build/audit/lint/Supabase lint executados. |

## Baseline Confirmado

- Branch local: `main`.
- Commit auditado: `e515b2ba93cb54130bd3a2066c0874be73008478`.
- Relação com remoto: `main...origin/main`.
- Worktree: sujo antes da auditoria, com alterações rastreadas e arquivos não rastreados de trabalhos anteriores. Este relatório não considera essas alterações como minhas correções.
- Node local: `v24.14.0`.
- pnpm local: `10.33.2`.
- Supabase CLI local: `2.84.2`.
- Vercel CLI local: `50.35.0`.
- Supabase live consultado via `supabase db query` somente com `SELECT`.
- Supabase Postgres live: `17.6`.
- Arquivos inventariados no repositório, excluindo `node_modules`, `.next`, `.turbo` e `dist`: 516.
- Arquivos técnicos relevantes sob `apps`, `packages`, `supabase` e `.github` inspecionados por inventário: 297.
- Vercel: projeto `agentempp`, produção `Ready`, Node 22.x, URL pública de produção validada por metadados CLI.
- GitHub: repo `corehealth-app/agentempp`, visibilidade pública, default branch `main`; conector não concedeu metadados admin de branch protection/secrets.
- Supabase Edge Functions live: 6 funções ativas, correspondendo às funções locais inventariadas.
- Supabase Storage live: nenhum bucket retornado por `storage.buckets`.

## Inventário Inicial

### Apps e pacotes

- App Next/admin em `apps/admin`.
- Pacotes internos sob `packages/*`, incluindo agent, core, inngest-functions e shared UI/config.
- Supabase local em `supabase`, com migrations, config e Edge Functions.
- Scripts operacionais em `scripts`.
- Documentação em `docs`.

### Superfícies Next/API identificadas

- Middleware: `apps/admin/src/middleware.ts`.
- Rotas auth: `apps/admin/src/app/auth/*`.
- Server Actions admin: users, messages, dashboard, settings, prompts.
- APIs Next: `/api/admin/send-message`, `/api/stripe/checkout`, `/api/stripe/setup-products`, `/api/media/[id]`, `/api/inngest`.

### Supabase

- Migrations locais: presentes em `supabase/migrations`.
- Edge Functions locais: `webhook-stripe`, `webhook-whatsapp`, `telegram-webhook`, `notify-telegram`, `audit-findings`, `audit-auto-fix`.

### Inngest

- Funções identificadas em `packages/inngest-functions/src/functions`, incluindo processamento de mensagens, buffer, fechamento diário, lembretes, auditorias, treinamento e health checks.

## Achados Confirmados

### CRIT-001 - Server Actions de alimentos usam service role sem autorização server-side

Classificação: Problema confirmado
Severidade: Alta
Probabilidade: Média

Local exato:

- `apps/admin/src/app/(admin)/settings/foods/actions.ts`
- `apps/admin/src/app/(admin)/settings/foods/editor.tsx`
- `apps/admin/src/app/(admin)/settings/foods/table.tsx`

Evidência:

- `actions.ts` declara `'use server'`.
- `actions.ts` importa `createServiceClient`.
- `upsertFood(input)` cria service client e executa `upsert` em `food_db`.
- `deleteFood(id)` cria service client e executa `delete` em `food_db`.
- `editor.tsx` é Client Component e importa/chama `upsertFood`.
- `table.tsx` é Client Component e importa/chama `deleteFood`.
- Diferentemente de outras Server Actions admin inspecionadas, este arquivo não contém `auth.getUser`, consulta a `admin_users` ou helper equivalente de autorização.

Explicação técnica:

Server Actions chamadas a partir de Client Components precisam validar autorização dentro da própria action. A proteção do layout/admin page não é suficiente para confiar que a action só será invocada por UI autorizada. Como a action usa service role, ela contorna RLS e pode alterar a tabela `food_db` se invocada sem uma checagem server-side efetiva.

Impacto real:

- Mutação ou exclusão indevida de alimentos do banco operacional.
- Possível alteração indireta de cálculos nutricionais do agente.
- Quebra de integridade de dados usados por pacientes.

Como reproduzir:

1. Gerar/usar um build do app admin.
2. Identificar o endpoint/identificador da Server Action gerado pelo Next para `upsertFood` ou `deleteFood`.
3. Invocar a action sem passar por uma sessão admin válida.
4. Validar que a autorização não é verificada no corpo da action.

Melhor correção:

- Adicionar uma checagem server-side compartilhada de admin antes de qualquer uso de service role na action.
- Preferir helper único, por exemplo `requireAdmin()`, para evitar divergências entre actions.
- Registrar auditoria da alteração quando aplicável.

Exemplo de correção:

```ts
async function requireAdmin() {
  const supabase = await createClient();
  const { data: { user } } = await supabase.auth.getUser();
  if (!user) throw new Error("Unauthorized");

  const { data: admin } = await supabase
    .from("admin_users")
    .select("id")
    .eq("id", user.id)
    .maybeSingle();

  if (!admin) throw new Error("Forbidden");
}
```

Efeitos colaterais possíveis:

- Testes ou chamadas internas que invocam essas actions sem sessão admin precisarão ser ajustados.
- Ambientes de seed/admin local podem precisar de usuário admin válido.

### CRIT-002 - Tabelas com RLS desabilitado concedem permissões amplas a `anon` e `authenticated`

Classificação: Problema confirmado
Severidade: Crítica
Probabilidade: Alta

Local exato:

- Banco Supabase live.
- Migrations locais relacionadas:
  - `supabase/migrations/20260528120000_pending_registrations.sql`
  - `supabase/migrations/20260611230000_prescriptions_training_phrases.sql`
  - `supabase/migrations/20260502140000_agent_configs_full.sql`
  - `supabase/migrations/20260504161100_attention_config.sql`

Evidência:

Consulta read-only ao catálogo do Postgres confirmou RLS desabilitado e permissões `DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE` para `anon` e `authenticated` nas tabelas:

- `attention_dismissals`
- `engagement_phrases`
- `food_education_phrases`
- `global_config`
- `pending_registrations`
- `prescriptions`
- `training_plans`
- `user_phrase_cooldown`
- `workout_types`

Explicação técnica:

No Supabase, tabelas expostas com grants para `anon`/`authenticated` e sem RLS podem ser acessadas via PostgREST conforme os privilégios concedidos. Isso é especialmente grave para tabelas com dados de usuário, configurações operacionais ou estado do agente.

Impacto real:

- Leitura e mutação pública ou por usuário autenticado de dados operacionais e potencialmente sensíveis.
- Possível alteração de configurações globais do agente.
- Possível exposição/mutação de prescrições, planos de treino e registros pendentes.

Como reproduzir:

1. Consultar `pg_class`, `information_schema.table_privileges` e `pg_policies` no projeto Supabase.
2. Confirmar `relrowsecurity = false`.
3. Confirmar grants amplos para `anon` e `authenticated`.
4. Usar cliente PostgREST com anon key para tentar `SELECT`/mutação em uma dessas tabelas.

Melhor correção:

- Habilitar RLS nas tabelas listadas.
- Revogar privilégios amplos de `anon` e `authenticated`.
- Criar policies mínimas por caso de uso real.
- Para tabelas administrativas, restringir acesso a `service_role` e RPCs protegidas.

Exemplo de correção:

```sql
alter table public.pending_registrations enable row level security;
revoke all on table public.pending_registrations from anon, authenticated;

create policy pending_registrations_service_only
on public.pending_registrations
for all
to service_role
using (true)
with check (true);
```

Efeitos colaterais possíveis:

- Código que atualmente depende de acesso direto pelo client precisará migrar para APIs/RPCs protegidas.
- Jobs com papel incorreto podem falhar até receberem service role ou política adequada.

### CRIT-003 - RPCs `SECURITY DEFINER` administrativas são executáveis por `anon`

Classificação: Problema confirmado
Severidade: Crítica
Probabilidade: Alta

Local exato:

- Banco Supabase live.
- `supabase/migrations/20260502210800_cron_management.sql`
- `supabase/migrations/20260501180000_cron_inngest_bridge.sql`
- `supabase/migrations/20260502140000_agent_configs_full.sql`
- `supabase/migrations/20260502120000_user_state_pause_summary.sql`
- `supabase/migrations/20260502150000_inbox_observability.sql`
- `supabase/migrations/20260504161100_attention_config.sql`
- `supabase/migrations/20260501190000_admin_kpis_funnel.sql`

Evidência:

Consulta read-only em `pg_proc`, `pg_namespace` e `information_schema.routine_privileges` confirmou funções `SECURITY DEFINER` com execução concedida a `anon`, `authenticated` e `service_role`, incluindo:

- `cron_toggle_job(text, boolean)`
- `cron_update_schedule(text, text)`
- `cron_run_now(text)`
- `dispatch_inngest_event(text, jsonb, integer)`
- `set_global_config(text, jsonb)`
- `pause_user(uuid, integer)`
- `resume_user(uuid)`
- `tag_user(uuid, text)`
- `untag_user(uuid, text)`
- `attention_snooze(uuid, text, int)`
- `attention_dismiss(uuid, text, text)`
- `attention_restore(uuid, text)`
- `refresh_mv_kpis_daily()`

Explicação técnica:

Funções Postgres têm execução concedida a `PUBLIC` por padrão se não houver `REVOKE`. Em Supabase, RPCs executáveis por `anon` podem ser chamadas pelo cliente público. Como essas funções são `SECURITY DEFINER`, elas rodam com privilégios do dono e podem ignorar restrições esperadas do chamador.

Impacto real:

- Usuário anônimo pode pausar/retomar usuários, alterar tags, manipular atenção, alterar configs globais, alterar/rodar crons e disparar eventos Inngest se a RPC estiver acessível via API.
- Risco direto de indisponibilidade operacional e alteração de comportamento do agente.

Como reproduzir:

1. Consultar `information_schema.routine_privileges` para as funções listadas.
2. Confirmar grantee `anon`.
3. Invocar uma RPC administrativa com anon key em ambiente controlado.

Melhor correção:

- Revogar `EXECUTE` de `PUBLIC`, `anon` e, quando aplicável, `authenticated`.
- Conceder `EXECUTE` somente a `service_role` para funções internas.
- Em funções que precisem ser chamadas por usuários autenticados, adicionar guarda explícita de admin dentro da função.
- Definir `SET search_path` seguro nas funções `SECURITY DEFINER`.

Exemplo de correção:

```sql
revoke execute on function public.cron_toggle_job(text, boolean) from public, anon, authenticated;
grant execute on function public.cron_toggle_job(text, boolean) to service_role;
```

Efeitos colaterais possíveis:

- Painéis/admins que chamem RPC diretamente pelo client autenticado deixarão de funcionar até moverem a chamada para uma API server-side.
- Crons/jobs precisam usar papel compatível com os grants finais.

### CRIT-004 - Views administrativas expostas a `anon`/`authenticated` podem bypassar RLS

Classificação: Problema confirmado
Severidade: Crítica
Probabilidade: Alta

Local exato:

- Banco Supabase live.
- Migrations locais:
  - `supabase/migrations/20260501120100_users_core.sql`
  - `supabase/migrations/20260501120600_observability.sql`
  - `supabase/migrations/20260501190000_admin_kpis_funnel.sql`
  - `supabase/migrations/20260501140000_admin_extras.sql`
  - `supabase/migrations/20260626130000_meal_state_view.sql`

Evidência:

Consulta read-only confirmou views/materialized view com owner `postgres`, sem `security_invoker=true`, e grants amplos para `anon` e `authenticated`:

- `mv_kpis_daily`
- `v_active_prompts`
- `v_attention_items`
- `v_cron_jobs`
- `v_daily_cost`
- `v_funnel_activation`
- `v_mrr_summary`
- `v_user_metrics`
- `vw_meal_state`

Explicação técnica:

Views Postgres rodam com permissões do owner por padrão. Quando expostas com grants a papéis públicos e sem `security_invoker`, elas podem revelar dados de tabelas base que possuam RLS, dependendo da definição da view e do papel owner.

Impacto real:

- Exposição de métricas de usuários, dados de atenção/admin, custos, estado de refeições e metadados operacionais.
- Potencial contorno de RLS das tabelas base.

Como reproduzir:

1. Consultar `pg_class.reloptions` para confirmar ausência de `security_invoker=true`.
2. Consultar `information_schema.table_privileges` para grants a `anon`.
3. Fazer `SELECT` via API pública em uma view listada.

Melhor correção:

- Revogar grants públicos das views administrativas.
- Recriar views que precisem ser acessadas pelo client com `WITH (security_invoker=true)` e policies adequadas nas tabelas base.
- Para dashboards admin, expor dados via API server-side com service role e autorização admin.

Exemplo de correção:

```sql
revoke all on table public.v_attention_items from anon, authenticated;
```

Efeitos colaterais possíveis:

- Telas admin que consultem views diretamente pelo browser podem quebrar até passarem por Server Actions/APIs autorizadas.
- Métricas públicas, se existirem, precisarão de views separadas com dados agregados e não sensíveis.

### VULN-001 - Dependências de produção com advisories de segurança reportados por `pnpm audit`

Classificação: Problema confirmado
Severidade: Alta
Probabilidade: Média

Local exato:

- `apps/admin/package.json:35`
- `apps/admin/package.json:38`
- `pnpm-lock.yaml`

Evidência:

- `apps/admin/package.json:38` declara `next` com range `^15.1.4`.
- `next build` executado nesta auditoria mostrou Next.js `15.5.15`.
- `pnpm audit --prod` retornou exit code `1` com 36 vulnerabilidades de dependências de produção: 2 baixas, 14 moderadas e 20 altas.
- Entre os advisories de produção reportados:
  - `next`: múltiplos advisories altos com versões corrigidas a partir de `15.5.16` e `15.5.18`, incluindo DoS em Server Components, bypass de middleware/proxy e SSRF em WebSocket upgrades.
  - `protobufjs`: advisories altos/moderados transitivos via `apps__admin>inngest>@opentelemetry/...`.
  - `@opentelemetry/core`: advisory moderado transitivo via `apps__admin>inngest`.
  - `ws`: advisory moderado transitivo via `apps__admin>@supabase/supabase-js>@supabase/realtime-js`.
- `pnpm audit` sem `--prod` retornou 45 vulnerabilidades totais: 1 crítica, 21 altas, 19 moderadas e 4 baixas. A crítica reportada é em `vitest`, portanto classificada separadamente como superfície de dev/test.

Explicação técnica:

O projeto está com uma versão instalada de Next anterior aos patches reportados pelo registry. Como o app admin roda em produção e depende de middleware, App Router e Server Components, os advisories de `next` pertencem à superfície runtime. Os advisories transitivos de `protobufjs`, OpenTelemetry e `ws` dependem do caminho de execução real dessas bibliotecas, então o impacto específico deve ser validado durante upgrade, mas a presença no grafo de produção é confirmada pela ferramenta.

Impacto real:

- Possível exposição a DoS ou bypass em rotas protegidas por middleware, conforme advisories do pacote `next`.
- Risco transitivo em instrumentação/telemetria e realtime conforme caminhos reportados pelo audit.
- Bloqueio de política de segurança caso CI passe a exigir `pnpm audit --prod` limpo.

Como reproduzir:

1. Rodar `pnpm audit --prod`.
2. Rodar `pnpm --filter @mpp/admin build` e observar a versão efetiva do Next reportada pelo build.
3. Conferir `apps/admin/package.json:38`.

Melhor correção:

- Atualizar `next` para versão que cubra todos os patches reportados pelo audit, no mínimo `>=15.5.18` conforme os advisories listados.
- Atualizar `inngest`/OpenTelemetry transitivos se houver release compatível que remova `protobufjs` vulnerável.
- Atualizar `@supabase/supabase-js`/`realtime-js` se houver versão que traga `ws >=8.20.1`.
- Rodar `pnpm audit --prod`, `pnpm typecheck`, `pnpm test` e `pnpm --filter @mpp/admin build` após upgrades.

Exemplo de correção:

```sh
pnpm --filter @mpp/admin up next@latest
pnpm --filter @mpp/admin up inngest @supabase/supabase-js
pnpm audit --prod
```

Efeitos colaterais possíveis:

- Upgrade de Next pode exigir ajustes de configuração, especialmente porque o build já alerta que `experimental.typedRoutes` foi movido para `typedRoutes`.
- Upgrades transitivos podem alterar tipos, comportamento de middleware, build output ou runtime serverless.

### BUG-001 - Banco live mantém `daily_close_user` quebrada apesar de migration local removê-la

Classificação: Problema confirmado
Severidade: Média
Probabilidade: Alta

Local exato:

- Banco Supabase live.
- `supabase/migrations/20260501160000_daily_closer.sql:11`
- `supabase/migrations/20260501160000_daily_closer.sql:30`
- `supabase/migrations/20260501160000_daily_closer.sql:76`
- `supabase/migrations/20260511060000_bloco_7700_design_deficit.sql:20`
- `supabase/migrations/20260511060000_bloco_7700_design_deficit.sql:69`
- `supabase/migrations/20260504165600_critical_bugs_fix.sql:181`
- `supabase/migrations/20260504165600_critical_bugs_fix.sql:185`
- `supabase/migrations/20260504165600_critical_bugs_fix.sql:186`

Evidência:

- `supabase db lint --linked` retornou erro em `public.daily_close_user`: `function mpp_level_for_xp(integer) does not exist`, na atribuição `v_new_level := mpp_level_for_xp(v_new_xp_total)`.
- Consulta read-only em `pg_proc` confirmou que o banco live ainda possui `daily_close_user(uuid,date)`.
- A mesma consulta não retornou `mpp_level_for_xp`, confirmando que o helper chamado pela função não existe no live.
- `daily_close_user(uuid,date)` live aparece com `EXECUTE` para `anon`, `authenticated` e `service_role`.
- A migration `20260504165600_critical_bugs_fix.sql:181-186` documenta que a lógica foi migrada para Inngest e executa `DROP FUNCTION IF EXISTS daily_close_user(uuid, date);` e `DROP FUNCTION IF EXISTS mpp_level_for_xp(int);`.

Explicação técnica:

Há drift entre o estado esperado pelas migrations locais e o banco live. A função deveria ter sido removida, mas permanece publicada; ao mesmo tempo, seu helper foi removido. Isso torna a RPC quebrada e ainda exposta para papéis públicos. A função não é `SECURITY DEFINER`, então o risco é menor que os achados CRIT-003, mas ela contém lógica mutável de fechamento de dia e não deveria estar acessível.

Impacto real:

- Chamadas à RPC podem falhar em produção e gerar ruído operacional.
- Mantém uma superfície pública obsoleta envolvendo `daily_snapshots` e `user_progress`.
- Confunde manutenção porque há duas implementações históricas do fechamento diário: SQL morto e Inngest atual.

Como reproduzir:

1. Rodar `supabase db lint --linked`.
2. Consultar `pg_proc` para `daily_close_user` e `mpp_level_for_xp`.
3. Comparar com `supabase/migrations/20260504165600_critical_bugs_fix.sql:181-186`.

Melhor correção:

- Criar migration de contenção para revogar execute público e remover a função obsoleta no live.
- Regenerar tipos do banco após a migration, se `packages/db/src/generated/database.ts` ainda listar a RPC.

Exemplo de correção:

```sql
revoke execute on function public.daily_close_user(uuid, date) from public, anon, authenticated;
drop function if exists public.daily_close_user(uuid, date);
```

Efeitos colaterais possíveis:

- Qualquer chamada legada direta à RPC deixará de funcionar. A migration local já declara que essa lógica foi migrada para Inngest, então esse efeito colateral deve ser validado contra logs antes de aplicar.

### PERF-001 - Webhook de status do WhatsApp atualiza `messages` por coluna sem índice compatível

Classificação: Problema confirmado
Severidade: Média
Probabilidade: Alta

Local exato:

- `supabase/functions/webhook-whatsapp/index.ts`
- `supabase/migrations/20260501120300_messages.sql`
- `supabase/migrations/20260502120000_user_state_pause_summary.sql`
- Banco Supabase live, `pg_stat_statements` e `pg_indexes`.

Evidência:

- `webhook-whatsapp` atualiza status com `.eq('provider_message_id', status.id)`.
- Migration inicial criou `idx_messages_provider_id ON messages(provider_message_id) WHERE provider_message_id IS NOT NULL`.
- Migration posterior removeu `idx_messages_provider_id` e criou apenas `uniq_messages_provider_message_id ON messages(provider, provider_message_id) WHERE provider_message_id IS NOT NULL AND direction = 'in'`.
- Índices live em `messages` não incluem índice geral por `provider_message_id`.
- `pg_stat_statements` mostrou aproximadamente 21,7 mil chamadas da atualização de `messages.delivery_status` por `provider_message_id`, média aproximada de 8,37 ms e total aproximado de 181,7 s.
- `pg_stat_user_tables` mostrou `messages` com volume alto de seq scan/tuplas lidas em relação ao tamanho atual.

Explicação técnica:

O índice único parcial atual atende idempotência de mensagens inbound, mas não atende bem a atualização de status de mensagens outbound enviada pela Meta. A query filtra somente `provider_message_id`; o índice live exige `provider` e ainda é parcial para `direction = 'in'`, portanto não cobre o caminho mais frequente de delivery status.

Impacto real:

- Custo crescente de CPU/IO a cada status recebido da Meta.
- Latência desnecessária no webhook WhatsApp.
- Risco de degradação progressiva conforme `messages` cresce.

Como reproduzir:

1. Inspecionar `webhook-whatsapp` e confirmar o filtro por `provider_message_id`.
2. Inspecionar `pg_indexes` para `messages`.
3. Consultar `pg_stat_statements` filtrando queries de update em `messages` com `provider_message_id`.

Melhor correção:

- Criar índice btree específico para lookup por provider message id usado em status updates.
- Alternativamente, alterar a query para incluir `provider` e criar índice parcial compatível para mensagens outbound.

Exemplo de correção:

```sql
create index concurrently if not exists idx_messages_provider_message_id_any
on public.messages(provider_message_id)
where provider_message_id is not null;
```

Efeitos colaterais possíveis:

- Aumento pequeno de custo de escrita em `messages`.
- Migration `CONCURRENTLY` precisa ser executada fora de transação, dependendo do runner.

### PERF-002 - RPC `match_food_phrases` não explora plenamente índice HNSW por causa da ordenação

Classificação: Problema confirmado
Severidade: Média
Probabilidade: Média

Local exato:

- `supabase/migrations/20260613000006_match_food_phrases_rpc.sql`
- `packages/agent/src/curated-phrase-selector.ts`
- Banco Supabase live, `pg_stat_statements` e `pg_stat_user_indexes`.

Evidência:

- `match_food_phrases` filtra por `1 - (food_name_embedding <=> query_embedding) > match_threshold`.
- A função ordena primeiro por `last_used_at ASC NULLS FIRST`, depois por distância vetorial.
- Existe índice live `idx_food_phrases_embedding` HNSW em `food_education_phrases(food_name_embedding vector_cosine_ops)`.
- `pg_stat_statements` mostrou poucas chamadas da RPC, mas média aproximada de 3,76 s e total aproximado de 518,6 s.
- `pg_stat_user_indexes` mostrou uso muito baixo de `idx_food_phrases_embedding` em comparação ao custo observado.

Explicação técnica:

Índices HNSW do pgvector são efetivos quando a query ordena por distância vetorial com `LIMIT`. Ao ordenar primeiro por `last_used_at`, o planner tende a não usar o índice vetorial como caminho principal, ficando mais perto de scan/filter/sort.

Impacto real:

- Latência alta em fallback de frase educativa quando match exato falha.
- Aumento de tempo de resposta do agente em refeições que caem na cascata semântica.
- Custo de banco desproporcional ao número de chamadas.

Como reproduzir:

1. Consultar `pg_stat_statements` para chamadas de `match_food_phrases`.
2. Comparar com `pg_stat_user_indexes` de `idx_food_phrases_embedding`.
3. Executar `EXPLAIN` em ambiente seguro com uma query equivalente.

Melhor correção:

- Fazer busca vetorial em CTE/subquery ordenada por distância e limitada a um conjunto candidato.
- Aplicar rotação por `last_used_at` apenas sobre os candidatos vetoriais já reduzidos.

Exemplo de correção:

```sql
with candidates as (
  select id, phrase, tags, usage_count, last_used_at,
         1 - (food_name_embedding <=> query_embedding) as similarity
  from public.food_education_phrases
  where active = true
    and language = match_language
    and food_name_embedding is not null
    and polaridade is not null
  order by food_name_embedding <=> query_embedding
  limit greatest(match_count * 5, 50)
)
select *
from candidates
where similarity > match_threshold
order by last_used_at asc nulls first, similarity desc, id asc
limit match_count;
```

Efeitos colaterais possíveis:

- Resultado pode mudar levemente porque a rotação de uso passa a acontecer dentro de candidatos vetoriais top-N.
- Precisa validar qualidade semântica em golden tests de frases.

### OPS-001 - Daily audit faz auto-correção de bloco em produção

Classificação: Problema confirmado
Severidade: Média
Probabilidade: Média

Local exato:

- `packages/inngest-functions/src/functions/daily-audit.ts`
- `packages/inngest-functions/src/lib/bloco-recompute.ts`

Evidência:

- `daily-audit.ts` executa step `auto-reconcile-blocos`.
- A rotina lista `user_progress`, recalcula bloco via `recomputeUserBloco` e atualiza `user_progress.deficit_block` e `blocks_completed`.
- Há circuito de segurança `MAX_BLOCO_FIX = 8`, mas quando divergências ficam abaixo desse limite a correção é aplicada automaticamente.
- `bloco-recompute.ts` recompõe o estado usando todos os `daily_snapshots` fechados e `meal_logs` por snapshot.

Explicação técnica:

A rotina chamada de auditoria não é apenas observabilidade; ela também altera estado de progresso. Isso pode ser intencional e tem circuit breaker, mas aumenta o acoplamento entre auditoria e mutação de dados históricos/derivados.

Impacto real:

- Divergência temporária ou bug de fórmula pode alterar progresso sem aprovação manual se afetar até 8 usuários por execução.
- Dificulta distinguir auditoria read-only de self-healing mutável.
- Pode conflitar com expectativa operacional de "sem recompute/backfill sem aprovação".

Como reproduzir:

1. Abrir `daily-audit.ts` nas linhas do step `auto-reconcile-blocos`.
2. Confirmar updates em `user_progress`.
3. Confirmar chamada a `recomputeUserBloco`.

Melhor correção:

- Separar auditoria read-only de correção.
- Exigir feature flag explícita para mutação, com default desligado.
- Trocar auto-fix por criação de `pending_approval`/alerta quando o ambiente exigir aprovação manual.

Exemplo de correção:

```ts
const autoFixEnabled = await loadBooleanConfig(supabase, 'audit.bloco_autofix_enabled', false)
if (!autoFixEnabled) {
  return { divergeCount: diverge.length, applied: 0, circuitBroke: false, readOnly: true }
}
```

Efeitos colaterais possíveis:

- Divergências deixam de ser corrigidas automaticamente e exigem operação manual.
- Alertas podem aumentar até o fluxo de aprovação estar afinado.

### MAINT-001 - `pnpm lint` falha no estado auditado

Classificação: Problema confirmado
Severidade: Baixa
Probabilidade: Alta

Local exato:

- `packages/core`
- `packages/providers`
- `packages/inngest-functions`
- Também houve falha reportada pelo turbo para `@mpp/admin` e `@mpp/agent`, mas a saída foi interrompida/truncada após falhas anteriores.

Evidência:

- `pnpm lint` retornou exit code `1`.
- `@mpp/core` reportou 25 erros, 9 warnings e 1 info pelo Biome.
- `@mpp/providers` reportou 12 erros, 8 warnings e 1 info pelo Biome.
- `@mpp/inngest-functions` reportou 31 erros e 49 warnings pelo Biome.
- Exemplos concretos:
  - `packages/providers/src/credentials.ts:51`: non-null assertion proibida.
  - `packages/providers/src/llm/openrouter.ts:131`: `any` explícito.
  - `packages/inngest-functions/src/lib/runtime-config.ts:29`: `any` explícito.
  - `packages/inngest-functions/src/functions/buffer-listener.ts`: formatação divergente.

Explicação técnica:

O estado atual não passa no gate de lint. Isso não prova bug runtime, mas reduz confiabilidade de CI, aumenta ruído em PRs e dificulta separar problemas novos de dívida existente.

Impacto real:

- CI com lint obrigatório falharia.
- Revisões futuras ficam mais difíceis porque alterações pequenas podem herdar grande volume de diagnósticos existentes.
- Regras de tipo/estilo, como `noExplicitAny`, perdem valor quando o baseline já está quebrado.

Como reproduzir:

1. Rodar `pnpm lint`.
2. Observar exit code `1` e diagnósticos do Biome.

Melhor correção:

- Corrigir primeiro formatação/import sorting com comando seguro do Biome.
- Tratar `any`/non-null assertions por pacote, com PR separado de mudanças funcionais.
- Depois ativar lint como gate obrigatório.

Exemplo de correção:

```sh
pnpm --filter @mpp/core lint
pnpm --filter @mpp/providers lint
pnpm --filter @mpp/inngest-functions lint
```

Efeitos colaterais possíveis:

- Correções automáticas de formatação podem gerar diff grande sem mudança funcional; ideal fazer em PR isolado.

## Possíveis Riscos

### RISK-001 - Workflow GitHub usa Actions por tag, não por SHA

Classificação: Possível risco
Severidade: Média
Probabilidade: Baixa a Média

Local exato:

- `.github/workflows/lint-agent.yml`

Evidência:

- Workflow usa `actions/checkout@v4`, `pnpm/action-setup@v4` e `actions/setup-node@v4`.
- Não há pinning por SHA.
- `pnpm/action-setup` é action de terceiro.

Explicação técnica:

Pinning por tag depende da integridade da tag e da conta/organização mantenedora. Pinning por SHA reduz risco de supply chain em CI.

Impacto real:

- Se uma action/tag for comprometida, execução de CI pode rodar código não esperado.

Como reproduzir:

1. Abrir `.github/workflows/lint-agent.yml`.
2. Verificar `uses:` com tags sem SHA.

Melhor correção:

- Fixar actions por commit SHA.
- Usar ferramentas como Dependabot/Renovate para atualizar SHAs com revisão.

Efeitos colaterais possíveis:

- Atualizações de actions deixam de ser automáticas e passam a exigir manutenção explícita.

### RISK-002 - Health check de pipeline chama endpoint mutável `PUT /api/inngest`

Classificação: Possível risco
Severidade: Média
Probabilidade: Baixa a Média

Local exato:

- `packages/inngest-functions/src/functions/pipeline-health.ts`
- `apps/admin/src/app/api/inngest/route.ts`
- `apps/admin/src/middleware.ts`

Evidência:

- `pipeline-health.ts` detecta mensagens inbound sem outbound e chama `fetch(syncUrl, { method: 'PUT' })`.
- `syncUrl` padrão é `https://agentempp.vercel.app/api/inngest`.
- Middleware marca `/api/inngest` como API pública, delegando validação ao Inngest.
- A rota `/api/inngest` exporta `GET, POST, PUT` via `serve`.

Explicação técnica:

Um health check que executa uma mutação operacional automática pode recuperar drift real, mas também pode executar syncs por falso positivo ou por mudança de comportamento do endpoint. A auditoria não validou internamente a semântica/autorização do `PUT` da biblioteca Inngest.

Impacto real:

- Sync automático inesperado em produção.
- Dificuldade de auditar mudanças de registro Inngest como ação humana vs rotina.

Como reproduzir:

1. Abrir `pipeline-health.ts` e localizar o `fetch` com método `PUT`.
2. Confirmar que `/api/inngest` é público no middleware.
3. Confirmar que a rota exporta `PUT`.

Melhor correção:

- Tornar auto-sync dependente de feature flag.
- Registrar tentativa com correlação e limitar frequência.
- Preferir alerta manual quando o ambiente estiver em modo de mudança controlada.

Efeitos colaterais possíveis:

- Recuperação automática de drift pode ficar mais lenta.

### RISK-003 - Fetchs externos diretos sem timeout/limite local de bytes

Classificação: Possível risco
Severidade: Baixa a Média
Probabilidade: Média

Local exato:

- `packages/providers/src/messaging/whatsapp-cloud.ts`
- `packages/providers/src/tts/elevenlabs.ts`
- `packages/inngest-functions/src/functions/*` que chamam Telegram/Meta via `fetch`.

Evidência:

- OpenRouter/Groq usam SDK com timeout explícito.
- Vários `fetch` diretos para Meta, Telegram e TTS não passam `AbortSignal`.
- Download de mídia WhatsApp retorna `Blob` completo e imagens são convertidas para base64 antes de enviar à vision.

Explicação técnica:

Sem timeout e limites explícitos, chamadas externas lentas ou respostas grandes podem consumir janela do worker/serverless e memória. O WhatsApp/Meta impõe limites próprios, então isso é risco operacional, não vulnerabilidade comprovada.

Impacto real:

- Workers podem ficar presos até timeout da plataforma.
- Imagens/áudios grandes podem elevar memória e latência.

Como reproduzir:

1. Inspecionar os `fetch` diretos nos arquivos listados.
2. Confirmar ausência de `AbortController`/timeout local.

Melhor correção:

- Criar wrapper `fetchWithTimeout`.
- Validar tamanho máximo de mídia por `Content-Length` quando disponível.
- Definir limites por tipo: áudio, imagem, TTS.

Efeitos colaterais possíveis:

- Algumas mídias lentas mas válidas passarão a falhar com mensagem de retry ao paciente.

### RISK-004 - API manual usa `SUPABASE_SERVICE_ROLE_KEY` como bearer operacional

Classificação: Possível risco
Severidade: Média
Probabilidade: Baixa

Local exato:

- `apps/admin/src/app/api/admin/send-message/route.ts`
- `apps/admin/src/middleware.ts`

Evidência:

- A rota `/api/admin/send-message` autentica `Authorization` comparando com `Bearer ${SUPABASE_SERVICE_ROLE_KEY}`.
- O middleware considera `/api/admin/send-message` público porque a rota valida bearer próprio.

Explicação técnica:

Usar service role como segredo de API aumenta blast radius: o mesmo segredo que autoriza envio manual também concede privilégios amplos no Supabase. A rota não fica sem autenticação, portanto isso é risco de desenho, não exploit confirmado.

Impacto real:

- Se o bearer vazar, o impacto vai além da API manual.

Como reproduzir:

1. Abrir a rota e localizar a comparação com `SUPABASE_SERVICE_ROLE_KEY`.
2. Confirmar isenção no middleware.

Melhor correção:

- Criar segredo dedicado, por exemplo `ADMIN_SEND_MESSAGE_TOKEN`.
- Rotacionar o endpoint para usar token com escopo único.

Efeitos colaterais possíveis:

- Scripts existentes que usam service role como bearer precisarão ser atualizados.

## Boas Práticas Ausentes

### BP-001 - CODEOWNERS não encontrado

Classificação: Boa prática ausente
Severidade: Baixa
Probabilidade: Média

Local exato:

- Repositório GitHub/local: nenhum arquivo `CODEOWNERS` encontrado por `rg --files CODEOWNERS`.

Evidência:

- Busca local por `CODEOWNERS` não retornou arquivos.

Explicação técnica:

CODEOWNERS ajuda a exigir revisão de áreas sensíveis, mas sua ausência só é falha operacional se o processo do projeto depender dele ou se branch protection exigir ownership review.

Impacto real:

- Maior chance de alterações sensíveis serem revisadas por pessoas sem contexto do componente.

Como reproduzir:

1. Rodar `rg --files CODEOWNERS`.

Melhor correção:

- Criar CODEOWNERS para áreas sensíveis: migrations/RLS, Edge Functions, Inngest, auth/admin, billing/webhooks.

Efeitos colaterais possíveis:

- PRs podem exigir revisores específicos e ficar mais lentos.

### BP-002 - Headers de segurança não definidos no app Next local

Classificação: Boa prática ausente
Severidade: Baixa
Probabilidade: Média

Local exato:

- `apps/admin/next.config.mjs`

Evidência:

- `next.config.mjs` contém configurações experimentais/transpile/webpack, mas não define `headers()`.
- Nenhum arquivo local equivalente de headers foi encontrado no app admin.

Explicação técnica:

Headers como `Content-Security-Policy`, `X-Frame-Options`/`frame-ancestors`, `Referrer-Policy` e `Permissions-Policy` reduzem impacto de XSS/clickjacking/exposição acidental. A ausência no repo não prova ausência em Vercel/proxy externo.

Impacto real:

- Menor defesa em profundidade caso uma tela admin renderize conteúdo controlável.

Como reproduzir:

1. Abrir `apps/admin/next.config.mjs`.
2. Confirmar ausência de `headers()`.

Melhor correção:

- Definir headers no Next ou na camada Vercel/proxy.
- Começar por CSP report-only se houver risco de quebrar scripts/styles atuais.

Efeitos colaterais possíveis:

- CSP estrita pode quebrar integrações até todas as origens necessárias serem mapeadas.

## Informação Insuficiente

- Branch protection e GitHub secrets: `gh` local está com token inválido e o conector disponível não expôs essas configurações durante a auditoria.
- Valores de secrets/env: por regra desta auditoria, valores não foram lidos nem impressos.
- Configuração live de Auth Supabase (signup, MFA, captcha, redirect URLs): o arquivo local `supabase/config.toml` foi inspecionado, mas ele não prova a configuração live hospedada.
- Headers HTTP efetivos em produção: Vercel metadata não confirma headers de resposta; não foi feito teste HTTP de produção nesta etapa.

## Itens Corretos Confirmados

- O workflow GitHub inspecionado não usa `pull_request_target`.
- A busca local não encontrou padrões evidentes de segredo ativo rastreado nos arquivos auditados, excluindo `.env.local`, artefatos gerados e dependências.
- `.env.example` usa chaves vazias/placeholders para variáveis sensíveis.
- `webhook-whatsapp` valida `x-hub-signature-256` com HMAC SHA-256 antes de processar payload POST.
- `webhook-stripe` usa `stripe.webhooks.constructEventAsync` com `Stripe-Signature`.
- `telegram-webhook` valida `x-telegram-bot-api-secret-token` quando `TELEGRAM_WEBHOOK_SECRET` está configurado, e o secret existe no ambiente Supabase live por nome.
- `notify-telegram`, `audit-findings` e `audit-auto-fix` validam `x-audit-secret` e fazem fail-closed quando `AUDIT_SECRET` está ausente.
- Supabase Storage live não possui buckets configurados; não há superfície Storage pública confirmada.
- `process-message` tem concorrência por `userId` e `buffer-listener` também serializa por `userId`, reduzindo risco de corrida no processamento do mesmo paciente.
- A correção recente de contexto por burst está presente: `message.received` carrega `providerMessageIds[]`, `buffer-listener` coleta todos os IDs, e `buildPromptRecentMessages` filtra o conjunto de mensagens atuais.

## Checks e Validações

| Comando | Resultado | Evidência |
| --- | --- | --- |
| `pnpm typecheck` | Passou | Turbo reportou 8 tarefas bem-sucedidas. |
| `pnpm test` | Passou | 5 tarefas bem-sucedidas; core, providers, inngest-functions e agent cobertos. |
| `pnpm --filter @mpp/core test` | Passou | 12 arquivos, 118 testes. |
| `pnpm --filter @mpp/agent test` | Passou | 42 arquivos, 806 testes. |
| `pnpm --filter @mpp/inngest-functions test` | Passou | 6 arquivos, 26 testes. |
| `pnpm --filter @mpp/admin build` | Passou com rede liberada | Next build compilou, gerou 21 páginas/rotas e finalizou build traces. |
| `pnpm lint` | Falhou | Biome reportou erros em core, providers e inngest-functions; turbo encerrou com exit code 1. |
| `pnpm audit --prod` | Falhou | 36 vulnerabilidades de produção: 2 baixas, 14 moderadas, 20 altas. |
| `pnpm audit` | Falhou | 45 vulnerabilidades totais: 4 baixas, 19 moderadas, 21 altas, 1 crítica. |
| `supabase db lint --linked` | Falhou | `public.daily_close_user` chama `mpp_level_for_xp(integer)`, função inexistente no live. |

Observações:

- O primeiro build do admin falhou no sandbox por DNS ao buscar Google Fonts; repetido com rede liberada, passou. A falha inicial não foi classificada como problema do projeto.
- O audit de dependências foi classificado separando produção (`--prod`) de dev/test.
- Nenhum deploy, backfill, push de banco, alteração de código de produção ou chamada mutável a `/api/inngest` foi executado.

## Resumo Executivo

A plataforma está funcional do ponto de vista de testes e build, mas a auditoria encontrou riscos críticos no perímetro Supabase. O maior problema confirmado é a exposição pública de tabelas, views e RPCs administrativas no banco live: há tabelas com RLS desabilitado e grants amplos, funções `SECURITY DEFINER` executáveis por `anon`, e views administrativas sem `security_invoker` expostas a papéis públicos. Isso é mais urgente que ajustes de frontend ou manutenção.

No app admin, há uma Server Action de alimentos usando service role sem checagem server-side de admin dentro da própria action. Em dependências, `pnpm audit --prod` confirma advisories de produção, incluindo Next instalado antes dos patches reportados. Em banco, também há drift: `daily_close_user` deveria ter sido removida, mas ainda existe no live, está quebrada e executável por papéis públicos.

Os fluxos recentes de agente/burst foram validados estaticamente e por testes: `providerMessageIds[]` existe, o contexto filtra as mensagens atuais e o teste do agent passou. Edge Functions críticas de webhook têm validação de assinatura/segredo confirmada. Supabase Storage não possui buckets live, então não há superfície Storage pública confirmada nesta auditoria.

## Lista de Vulnerabilidades

1. `CRIT-002`: tabelas com RLS desabilitado e grants amplos a `anon`/`authenticated`.
2. `CRIT-003`: RPCs `SECURITY DEFINER` administrativas executáveis por `anon`.
3. `CRIT-004`: views/materialized view administrativas expostas a `anon`/`authenticated` sem `security_invoker`.
4. `CRIT-001`: Server Actions de alimentos usam service role sem autorização server-side.
5. `VULN-001`: dependências de produção com advisories reportados por `pnpm audit --prod`.

## Lista de Bugs

1. `BUG-001`: `daily_close_user` live está quebrada por helper ausente e deveria ter sido removida.
2. `PERF-001`: webhook WhatsApp faz update frequente em `messages` sem índice compatível.
3. `PERF-002`: `match_food_phrases` tem latência alta e não usa HNSW de forma ideal.

## Gargalos de Performance

1. `match_food_phrases`: média aproximada de 3,76 s em `pg_stat_statements`; reordenar busca vetorial antes da rotação por `last_used_at`.
2. Update de status WhatsApp: aproximadamente 21,7 mil chamadas e 181,7 s totais em `pg_stat_statements`; falta índice compatível.
3. `messages` tem volume alto de seq scans/tuplas lidas para o tamanho atual; parte está ligada ao item anterior.
4. Fetchs externos diretos sem timeout/limite de bytes são risco operacional de latência/memória, não gargalo comprovado.

## Problemas de Arquitetura

1. `OPS-001`: rotina chamada de auditoria também faz auto-correção de dados de bloco, misturando observabilidade e mutação.
2. `RISK-002`: health check do pipeline pode chamar endpoint mutável `PUT /api/inngest`.
3. Uso de service role aparece em Server Actions; a maior parte tem guarda, mas `settings/foods/actions.ts` fugiu do padrão.
4. Views/admin analytics estão expostas no banco, quando o padrão mais seguro seria API server-side autorizada para dashboards.

## Problemas de Banco de Dados

1. RLS/grants críticos em tabelas operacionais e sensíveis.
2. RPCs administrativas com grants públicos e `SECURITY DEFINER`.
3. Views administrativas sem `security_invoker` e com grants públicos.
4. Função obsoleta `daily_close_user` ainda existe no live, quebrada.
5. Índice ausente para lookup de `messages.provider_message_id` no caminho de status outbound.
6. Ordenação da RPC vetorial reduz benefício do índice HNSW.

## Problemas de Segurança

1. Exposição Supabase pública é o risco dominante.
2. Dependências runtime precisam de upgrade por advisories confirmados.
3. Falta de headers de segurança no Next local é boa prática ausente, ainda sem validação dos headers efetivos em produção.
4. Workflow GitHub não fixa actions por SHA.
5. Endpoint manual usa service role como bearer operacional, aumentando blast radius em caso de vazamento.

## Problemas de Escalabilidade

1. Query de status WhatsApp degradará conforme `messages` crescer.
2. RPC semântica de frases pode ficar cara com crescimento de `food_education_phrases`.
3. Fetchs externos sem timeout podem consumir janelas serverless/workers sob lentidão de provedores.
4. Auditoria com auto-fix percorre `user_progress` e recomputa usuários; precisa de cuidado conforme base cresce.

## Problemas de Manutenção

1. `pnpm lint` não passa no baseline auditado.
2. Drift entre migrations e live (`daily_close_user`) reduz confiança operacional.
3. CODEOWNERS ausente.
4. Branch protection/secrets GitHub não puderam ser validados com o acesso disponível.
5. Tipos gerados ainda listam RPCs históricas; validar após corrigir drift.

## Melhorias Recomendadas

1. Criar migration de contenção Supabase focada em grants/RLS/RPCs/views, com revisão cuidadosa antes de aplicar.
2. Adicionar `requireAdmin()` em todas as Server Actions com service role e criar teste/regra de busca para impedir regressão.
3. Atualizar `next` e dependências transitivas afetadas, com validação de build/test/audit.
4. Separar auditoria read-only de auto-fix mutável por feature flag.
5. Adicionar índices e reescrever RPC vetorial conforme evidência de `pg_stat_statements`.
6. Adicionar timeouts e limites de mídia nos providers externos.
7. Corrigir lint em PR separado, depois tornar lint gate confiável.
8. Adicionar CODEOWNERS e pinning por SHA nas GitHub Actions.

## Priorização por Impacto

1. Crítica: revogar execute público das RPCs `SECURITY DEFINER` administrativas e proteger funções internas.
2. Crítica: habilitar RLS/revogar grants nas tabelas expostas, começando por `pending_registrations`, `prescriptions`, `training_plans` e `global_config`.
3. Crítica: revogar grants públicos das views administrativas e decidir entre APIs server-side ou `security_invoker`.
4. Alta: corrigir `settings/foods/actions.ts` com autorização server-side.
5. Alta: atualizar Next/dependências runtime vulneráveis.
6. Média: remover/revogar `daily_close_user` live quebrada.
7. Média: corrigir índices/queries de `messages` e `match_food_phrases`.
8. Média: desligar ou controlar auto-fix de auditoria por flag.
9. Baixa/Média: headers, CODEOWNERS, pinning SHA, lint baseline.

## Plano de Ação em Ordem de Execução

1. Preparar migration de contenção Supabase apenas com `REVOKE EXECUTE` das RPCs críticas e `REVOKE` de views administrativas; revisar em staging antes de produção.
2. Mapear telas/rotas admin que dependem de acesso direto às views/tabelas afetadas e migrar para Server Actions/APIs autorizadas onde necessário.
3. Habilitar RLS e policies mínimas nas tabelas expostas, uma família por vez, com smoke tests do admin e workers.
4. Remover ou revogar `daily_close_user(uuid,date)` live e regenerar tipos do banco.
5. Corrigir `settings/foods/actions.ts` adicionando `requireAdmin()` antes do service role.
6. Atualizar `next` para versão corrigida e depois tratar `inngest`/OpenTelemetry/Supabase transitivos até `pnpm audit --prod` ficar aceitável.
7. Criar índice compatível para status WhatsApp e reescrever `match_food_phrases` com CTE vetorial top-N.
8. Colocar auto-fix do daily audit atrás de feature flag default off ou fluxo de aprovação.
9. Adicionar timeouts/limites nos fetchs externos.
10. Corrigir lint baseline e transformar lint em gate.
11. Adicionar CODEOWNERS, pinning por SHA e validar branch protection/secrets quando houver acesso administrativo.

## Encerramento da Auditoria

Status: concluída para todos os componentes disponíveis localmente e ambientes live acessíveis em modo leitura.
Limitações documentadas: branch protection/secrets GitHub, valores de secrets/env, configuração live completa de Supabase Auth e headers HTTP efetivos em produção não puderam ser validados com as permissões/ferramentas disponíveis sem extrapolar o escopo definido.
