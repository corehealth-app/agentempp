# BodyFlow P0-A: segurança, identidade, RBAC e RLS

## Estado deste runbook

- Data da validação: 2026-07-20.
- Worktree: `/root/.codex/worktrees/agentempp-bodyflow-p0`.
- Branch Git: `codex/bodyflow-p0`.
- Supabase staging: `xitugspwfxkcluxvrdeg`.
- Supabase produção bloqueada: `xuxehkhdvjivitduarvb`.
- Escopo aplicado: somente Supabase staging e código local.
- Não houve deploy, push Git, acesso a dados reais ou alteração de produção.
- Os 34 cron jobs de staging permaneceram inativos durante toda a execução.

## Objetivo

O P0-A prepara o backend existente para o BodyFlow Full App v1.0, com identidade
app-first/e-mail-first. Ele não implementa o app iOS, a API mobile, o chat nativo,
Storage mobile, APNs, StoreKit, daily state ou cálculo determinístico novo.

As garantias centrais são:

1. paciente autenticado é ligado ao domínio por `users.auth_user_id`;
2. usuário legado de WhatsApp não é vinculado automaticamente;
3. paciente e administrador usam contas Auth distintas;
4. cliente direto é somente leitura nos dados próprios permitidos;
5. mutações sensíveis passam pelo BFF/backend com `service_role`;
6. tabelas críticas e tabelas com `user_id` usam RLS;
7. funções administrativas e RPCs legadas não são executáveis por clientes;
8. novos objetos PostgreSQL nascem sem grants implícitos para clientes.

## Migrations

### `20260720014221_p0_harden_admin_functions.sql`

- cria `private.assert_trusted_backend()`;
- fixa `search_path` das funções administrativas `SECURITY DEFINER`;
- revoga execução de `PUBLIC`, `anon` e `authenticated`;
- permite execução técnica via `service_role`;
- protege funções de configuração, cron, Inngest, pausa, tags e atenção;
- preserva chamadas internas de sessões PostgreSQL confiáveis.

### `20260720015358_p0_deny_default_public_grants.sql`

- remove default grants de tabelas, sequências e funções criadas por `postgres`;
- estabelece deny-by-default nos schemas da aplicação;
- não concede acesso futuro automaticamente a `anon` ou `authenticated`.

### `20260720015730_p0_revoke_global_function_defaults.sql`

- remove o default global de `EXECUTE` para `PUBLIC` em novas funções;
- complementa a migration anterior, pois um revoke por schema não desfaz o
  default global nativo do PostgreSQL.

### `20260720020351_p0_email_first_patient_identity.sql`

- adiciona `users.auth_user_id uuid NULL`;
- cria unicidade e FK para `auth.users(id)` com `ON DELETE SET NULL`;
- torna `users.wpp` nullable;
- converte papéis legados:
  - `admin` para `master_admin`;
  - `editor` para `content_editor`;
  - `viewer` para `support`;
- restringe `admin_users.role` aos cinco papéis administrativos canônicos;
- impede que a mesma identidade Auth seja paciente e administradora;
- cria `bootstrap_patient_profile()` idempotente;
- exige e-mail confirmado antes do bootstrap;
- recusa vínculo automático quando o e-mail já existe no domínio legado;
- cria somente `users`, `user_profiles` e `user_progress` vazios para conta nova.

### `20260720022441_p0_secure_app_first_rls.sql`

- remove todos os privilégios de relações públicas de `anon`;
- remove escrita direta de `authenticated` em tabelas públicas;
- concede acesso técnico explícito ao `service_role`;
- restringe funções próprias da aplicação ao backend, salvo a allowlist abaixo;
- torna views com dados de usuário `security_invoker` e backend-only;
- habilita RLS nas nove tabelas críticas e em todas as tabelas base com `user_id`;
- substitui policies legadas baseadas em papéis JWT antigos;
- implementa ownership por `auth.uid() -> users.auth_user_id`;
- aplica leitura administrativa conforme o RBAC canônico;
- limita colunas diretamente legíveis de `users`, `messages` e `subscriptions`.

## Identidade e bootstrap

### Conta paciente nova

1. Supabase Auth cria a identidade por e-mail.
2. O e-mail precisa estar confirmado.
3. O backend/cliente autenticado chama `bootstrap_patient_profile()`.
4. A função usa advisory lock por `auth.uid()` para evitar corrida.
5. A função valida que a identidade não pertence a `admin_users`.
6. Se não houver conflito legado, cria um domínio vazio com `wpp = NULL`.
7. Chamadas repetidas retornam o mesmo `users.id`.

### Conta legada

- `auth_user_id` permanece `NULL`;
- nenhum dos usuários de WhatsApp é ligado por nome, telefone ou e-mail;
- um e-mail coincidente produz conflito explícito;
- qualquer migração de identidade legada exige processo futuro, aprovado e
  auditável.

### Separação paciente/admin

- triggers bloqueiam paciente com `auth_user_id` presente em `admin_users`;
- triggers bloqueiam admin cujo `id` já esteja ligado a um paciente;
- o painel também valida a separação antes de cadastrar um admin;
- uma pessoa que desempenhe os dois papéis precisa de dois e-mails Auth.

## RBAC

| Papel | Leitura direta prevista | Mutações |
|---|---|---|
| `patient` | somente linhas próprias e colunas permitidas | somente por BFF, exceto bootstrap |
| `support` | atendimento do paciente e atenção | BFF com checagem de papel |
| `content_editor` | conteúdo e frases curadas | BFF; não publica como master |
| `nutrition_admin` | atendimento, conteúdo nutricional, referências e correções | BFF com checagem de papel |
| `operations_admin` | operação, configuração, cooldown e atendimento operacional | BFF com checagem de papel |
| `master_admin` | todas as superfícies administrativas permitidas | BFF com checagem de papel |
| `service_role` | acesso técnico server-side | mutações técnicas autorizadas |

`service_role` não é um papel de usuário e nunca deve chegar ao app, navegador
ou dispositivo móvel.

## Contrato de leitura do paciente

O paciente pode ler apenas a própria linha em:

- `users`;
- `user_profiles`;
- `user_progress`;
- `daily_snapshots`;
- `meal_logs`;
- `workout_logs`;
- `reevaluations`;
- `messages`;
- `pending_registrations`;
- `prescriptions`;
- `training_plans`;
- `subscriptions`.

Em `users`, ficam fora do grant direto campos internos como `metadata`,
`summary`, `tags`, `admin_notes` e `country_detected_from_wpp`.

Em `messages`, o contrato direto não inclui payload bruto, IDs internos do
provedor, tokens, custo, latência ou erro técnico de entrega.

Em `subscriptions`, o contrato direto não inclui o ID da assinatura no
provedor nem `metadata`.

As views `v_attention_items`, `v_user_metrics` e `vw_meal_state` permanecem
backend-only nesta fase. A API mobile definirá DTOs estáveis antes de expor
dados derivados ao app.

## Funções acessíveis por cliente autenticado

A allowlist de funções próprias da aplicação é:

- `public.bootstrap_patient_profile()`;
- `public.is_admin()`;
- `public.admin_role()`.

As demais funções próprias da aplicação são executáveis apenas pelo
`service_role` ou pela sessão PostgreSQL técnica aplicável. Funções pertencentes
a extensões PostgreSQL não foram alteradas pela migration de lockdown.

## Testes SQL

Arquivos P0-A:

- `supabase/tests/p0_admin_functions_security.sql`;
- `supabase/tests/p0_authorization_matrix.sql`;
- `supabase/tests/p0_critical_rls.sql`;
- `supabase/tests/p0_crons_inactive.sql`;
- `supabase/tests/p0_default_privileges.sql`;
- `supabase/tests/p0_patient_bootstrap.sql`;
- `supabase/tests/p0_patient_identity.sql`;
- `supabase/tests/p0_trusted_backend_guard.sql`.

A matriz usa somente e-mails `example.com`, UUIDs reservados para o teste e
conteúdo sintético. Tudo roda dentro de `BEGIN`/`ROLLBACK`.

Ela cobre:

- ausência de acesso de `anon`;
- leitura própria de paciente;
- bloqueio cross-user;
- bloqueio de colunas internas;
- bloqueio de escrita direta;
- bloqueio de RPC administrativa para paciente e admin;
- permissões de `support`, `content_editor`, `nutrition_admin`,
  `operations_admin` e `master_admin`;
- mutação protegida por `service_role`;
- conflito explícito para usuário legado;
- zero persistência de fixtures.

## Validação em staging

Antes de qualquer comando remoto:

```bash
test "$(tr -d '\n' < supabase/.temp/project-ref)" = "xitugspwfxkcluxvrdeg"
git status --short --branch
```

Validar migrations:

```bash
supabase migration list --linked
supabase db push --linked --dry-run
```

Executar um teste:

```bash
supabase db query --linked \
  --file supabase/tests/p0_authorization_matrix.sql \
  --output table
```

Executar a suíte SQL completa:

```bash
for file in $(find supabase/tests -maxdepth 1 -type f -name '*.sql' | sort); do
  supabase db query --linked --file "$file" --output table || exit 1
done
```

Validar o schema:

```bash
supabase db lint --linked --schema public --level error --fail-on error
```

Validar os crons sem ler comandos:

```sql
SELECT
  count(*) AS total,
  count(*) FILTER (WHERE active) AS active,
  count(*) FILTER (WHERE NOT active) AS inactive
FROM cron.job;
```

Resultado esperado em staging: `34 total`, `0 active`, `34 inactive`.

## Rollback

### Regra geral

- nunca editar migration histórica aplicada;
- nunca executar rollback diretamente em produção sem ensaio em branch;
- preferir uma migration forward corretiva;
- preservar colunas e dados durante o P0;
- registrar aprovação humana e resultado dos testes.

### Ordem de reversão lógica

Se for indispensável desfazer o P0-A, a ordem é inversa:

1. restaurar grants/policies anteriores a `20260720022441`;
2. remover bootstrap, triggers e vínculo Auth de `20260720020351` somente se
   nenhum app-first user tiver sido criado;
3. restaurar defaults globais de função de `20260720015730` somente se houver
   justificativa explícita;
4. restaurar defaults por schema de `20260720015358` somente em ambiente
   descartável;
5. restaurar funções anteriores a `20260720014221` somente após provar que não
   reabre execução de cliente.

No staging atual, a opção operacional mais segura para uma reversão total é
recriar/resetar a branch apenas com autorização específica, porque não há dados
reais. Para produção futura, o rollback deve ser uma migration forward ensaiada,
nunca `migration repair`, edição manual do histórico ou reset.

## Limitações e riscos conhecidos

- A CLI usada na execução foi `2.84.2`; a versão `2.109.1` estava disponível,
  mas não foi pinada porque o binário do pacote local estava com install script
  ignorado. A pinagem deve ser tratada separadamente.
- Os default privileges de objetos da aplicação criados por `postgres` estão
  protegidos. Defaults pertencentes ao papel gerenciado `supabase_admin` não
  puderam ser alterados pela role de migration e permanecem uma limitação da
  plataforma a validar com suporte/configuração administrativa.
- O lint global do admin já possuía dívida histórica fora do P0-A. Os 17 arquivos
  tocados passaram no Biome, mas o comando global ainda reporta problemas
  preexistentes.
- RLS protege acesso direto ao PostgREST. O BFF usa `service_role` e, portanto,
  deve sempre autenticar o usuário, aplicar RBAC e validar ownership antes de
  executar consultas ou mutações.
- Não houve teste em produção, por decisão de isolamento. A confirmação de
  produção intocada se baseia no ref local validado e na ausência de comandos
  contra o ref de produção.

## Preparação futura de produção

Antes de promover qualquer migration:

1. validar backup, PITR e restore em ambiente não produtivo;
2. atualizar/recriar branch de staging a partir do estado atual de produção;
3. repetir dry-run, 25 testes SQL, typecheck, testes, build e advisors;
4. revisar todas as APIs/BFF que usam `service_role`;
5. definir observabilidade e alertas de negação RLS;
6. aplicar migrations antes do código dependente;
7. executar canário sem dados reais e com crons ainda desligados;
8. obter aprovação humana específica para produção;
9. monitorar autenticação, erros 401/403, RPCs e consultas após promoção.

## Fora do P0-A

- Prompt 03;
- app iOS/SwiftUI;
- Xcode e TestFlight;
- API/BFF mobile versionada;
- chat nativo;
- Storage mobile;
- push/APNs;
- StoreKit e entitlements;
- daily state;
- cálculo nutricional/corporal novo;
- CMS, mascote e personalidades;
- reativação de crons ou integrações;
- migração/backfill dos usuários legados;
- deploy e promoção para produção.
