# Performe AI — evidência local da integração do Flow no Mobile BFF dedicado

**Operação:** `INTEGRATE_PERFORME_AI_FLOW_INTO_DEDICATED_MOBILE_BFF_V1`

**Data:** 2026-09-14

**Escopo:** integração, testes, build e revisão locais; nenhuma mutação remota.

## 1. Baseline e host

- Host: `MacBook-Air-de-Eduardo.local`, macOS/Darwin arm64, usuário local `eduardohenrique`.
- Classificação: `LOCAL_DEVELOPMENT`; esta worktree não foi tratada como filesystem de produção.
- Worktree: `/Users/eduardohenrique/Developer/performe-ai-client-beta-flow-v1`.
- Branch: `codex/performe-ai-client-beta-flow-v1`, sem upstream.
- HEAD inicial: `dcbd6eb70c7845c156fddbffb3cce5d7bdd4de32`.
- Parent inicial: `df5524f4ba90fd3b111862099fd551bf58df3e80`.
- Tree inicial: `d29d2dc7d91dc6a1fedbedf45246887fe2b8bced`.
- Subject inicial: `feat(beta): add authenticated Flow text chat vertical slice`.
- Dirty inicial: zero. Index inicial: zero.
- Origin confirmado: `https://github.com/corehealth-app/agentempp.git`.
- Relatório read-only de staging: SHA-256 `785d04fc6fc7781118ce843431d5a363b0a225dd9a3878d3f7c555a2ed55a048`, igual ao mandato.

## 2. Proveniência do BFF histórico

Foi executado apenas o fetch seletivo autorizado, sem tags e sem gravar `FETCH_HEAD`:

```text
git fetch --no-tags --no-write-fetch-head origin e3e1e252b48e42554e75899b950692c05186f60d
```

O objeto não existia localmente antes e passou a existir como objeto Git, sem criar/trocar refs, branch ou worktree.

- Commit: `e3e1e252b48e42554e75899b950692c05186f60d`.
- Parent: `277873755bf29771a10b5f362b522c2e6a6c21d6`.
- Tree: `a167a6663cb1e476975742bcec51c7207dbcbc26`.
- Subject: `feat(staging): add dedicated Mobile API BFF surface`.
- Autoria/commit: `2026-08-26T04:12:08Z`.
- Pacote histórico: 51 arquivos sob `apps/mobile-bff`, 40 wrappers `/api/mobile/v1/**`.
- Verificação de restauração inicial: 51/51 objetos de arquivo com hash idêntico ao commit histórico, antes dos ajustes do Flow e da formatação Biome.

Não houve `pull`, `prune`, `merge`, `rebase`, `cherry-pick`, `push` ou troca de branch.

## 3. Integração realizada

- O pacote Next dedicado `@mpp/mobile-bff` foi restaurado, mantendo `apps/admin/src/app/api/mobile/v1/**` como implementação autoritativa.
- Foi criado o wrapper `/api/mobile/v1/flow/chat`, que reexporta exatamente `GET` e `POST` da rota autoritativa.
- `runtime = 'nodejs'` e `maxDuration = 300` foram declarados como literais no wrapper. O primeiro build demonstrou que o Next não reconhece `maxDuration` reexportado e usaria o default; um teste RED foi adicionado e a metadata foi tornada estaticamente analisável.
- O manifest final `functions-config-manifest.json` registra `maxDuration: 300` para `/api/mobile/v1/flow/chat`; o build final não emite aviso de configuração estática para essa rota.
- `@mpp/providers` foi declarado como dependência direta do pacote, pois a rota Flow autoritativa o importa diretamente.
- O importer do pacote foi acrescentado ao `pnpm-lock.yaml` sem atualização de versões não relacionadas.
- Receipts de fonte, wrappers, paths do build, fechamento de imports e NFT foram atualizados com revisão da diferença real.
- O verificador de wrappers aceita metadata local somente nos literais exatos `runtime = 'nodejs'` e `maxDuration = 300`; qualquer outro corpo/expressão local falha.
- Nenhuma regra de negócio, autenticação ou persistência foi copiada para o BFF; o teste do entrypoint comprova que os handlers publicados são os mesmos objetos `GET`/`POST` da rota autoritativa.

Paths de produção alterados/criados ficam restritos a `apps/mobile-bff/**` e ao importer de `pnpm-lock.yaml`. Os demais paths são o plano e esta evidência. Não houve alteração em fonte Admin, Agent ou iOS.

## 4. TDD e falhas caracterizadas

1. A primeira tentativa de comando RED usou paths/configuração relativos incorretos; uma segunda tentativa expôs a ausência inicial dos links locais do workspace. Esses dois erros foram de invocação/setup e não foram usados como prova semântica.
2. RED semântico, usando o Vitest já instalado do Admin com root explícito:
   - source: 41 rotas versus receipt histórico de 40;
   - wrappers: 40 versus source 41;
   - única omissão: `flow/chat/route.ts`;
   - 2 arquivos falharam, 20 testes ficaram fora pelo filtro.
3. GREEN inicial: source/wrapper 41/41 e import closure do Flow presentes.
4. RED de metadata: o novo teste exigiu `runtime`/`maxDuration` locais e falhou contra o reexport de quatro nomes; o build confirmou o risco ao anunciar fallback de `maxDuration`.
5. GREEN de metadata: wrapper estático, teste verde, warning do Flow ausente e manifest com `maxDuration: 300`.
6. O teste integral do BFF inicialmente falhou no receipt NFT histórico `4180/151/149/2`; a inspeção real do grafo mostrou `4302/156/154/2`, zero referências proibidas, e o receipt foi atualizado.
7. Após o autofix seguro do Biome, uma vírgula final em reexport multiline revelou uma entrada vazia no parser do guard. O parser foi corrigido para ignorar apenas nomes vazios de separação; o hash de exports voltou a coincidir 41/41.

## 5. Manifest de rotas antes e depois

| Receipt | Histórico dedicado | Integração local |
|---|---:|---:|
| Rotas Mobile API | 40 | 41 |
| SHA-256 path/export da fonte e wrappers | `7154a9a67db83e0adc8a2f3bc22e1bdd2be752904c1f416cca43d00ed10679b4` | `b8ed43a4af34bf6ebfd2402f81d1510b5fe2dfb625444dc58700b467c9f280b2` |
| SHA-256 dos paths no build | `abc24332fd370b5d7940ca56b18530a3659ba39b5205faeb2bf36771aa6f3c3a` | `de49930a0b49313c30017e3320a7584b9a3012c80ef48660210ba0a624003a5b` |
| `/api/mobile/v1/flow/chat` | ausente | presente (`GET`, `POST`) |
| Páginas, middleware, Server Actions | zero | zero |

Build final:

- `BUILD_ROUTE_PATH_COUNT=41`.
- `BUILD_APP_PATHS_MANIFEST_SHA256=9e4e86a07711dbe9e08941d6e77ae173419466a97d8c798ade807ab6d31034b1`.
- `BUILD_BUNDLE_SURFACE_STREAM_SHA256=942fe97e1c8f7638a1aef2a2313fbd665ef21aa0f5f07bb089d6b5683bd9c543`.
- `BUILD_NFT_REFERENCE_COUNT=4302`.
- `BUILD_NFT_UNIQUE_TARGET_COUNT=156`.
- `BUILD_NFT_REGULAR_FILE_TARGET_COUNT=154`.
- `BUILD_NFT_DIRECTORY_TARGET_COUNT=2`, ambos allowlisted.
- Fora de `/api/mobile/v1`: zero.
- Rotas Admin/Inngest/Stripe/Admin media: zero.
- Referências de worker em bundle/trace: zero.
- Referências administrativas em bundle/trace: zero.

O `/404` interno apresentado pelo console do Next não aparece como página publicável no manifest validado; `BUILD_PAGE_ROUTE_COUNT=0`.

## 6. Verificações locais

| Gate | Resultado |
|---|---|
| BFF dedicado | PASS — 4 arquivos, 26 testes |
| Admin Mobile API e bibliotecas | PASS — 24 arquivos, 243 testes |
| Agent | PASS — 70 arquivos, 1.056 testes |
| Typecheck `@mpp/mobile-bff` | PASS |
| Typecheck `@mpp/admin` | PASS |
| Typecheck `@mpp/agent` | PASS |
| Build `@mpp/mobile-bff` | PASS — Next 15.5.15, 41 rotas |
| Route mirror | PASS — 41/41, zero extra/omitida/mismatch |
| Import closure | PASS — Flow wrapper/route/handler/service presentes; zero denied |
| Build surface/NFT | PASS |
| Biome `apps/mobile-bff` | PASS — 52 arquivos |
| Scan de literais de segredo com boundary no build | PASS — zero OpenAI/Supabase/JWT/private-key |
| Warning estático de Flow no build final | zero |

Os testes cobrem ou preservam pelo entrypoint autoritativo: bearer ausente/erro de autenticação, ownership derivado do usuário autenticado, rejeição de `user_id`, histórico filtrado por `user_id` e `provider=mobile_flow`, limites de histórico/payload, no-store, `Vary: Authorization`, request ID, idempotência/replay, retry de inbound falho, falha do provider sem resposta simulada, rate limit, envelopes de erro e logs sem conteúdo sensível. O Agent preserva apenas quatro tools read-only no canal Flow e desliga telemetria de conteúdo.

O build ocorreu com os cinco secrets/valores principais ausentes do ambiente local: `NEXT_PUBLIC_SUPABASE_URL`, `NEXT_PUBLIC_SUPABASE_ANON_KEY`, `SUPABASE_SERVICE_ROLE_KEY`, `OPENROUTER_API_KEY` e `HELICONE_API_KEY`. Nenhum handler foi invocado no build e nenhuma chamada real a Supabase/OpenRouter foi executada.

## 7. Configuração preparada para o próximo gate

Somente nomes e procedimentos foram validados; nenhum valor foi lido, impresso, criado ou persistido.

### Cliente iOS

- `PERFORME_SUPABASE_URL`.
- `PERFORME_SUPABASE_PUBLISHABLE_KEY`.
- `PERFORME_MOBILE_API_ORIGIN`.

Devem entrar em `.xcconfig` privado fora do Git ou build settings efêmeros. O bearer pode ser enviado somente para a origem HTTPS BFF aprovada; a publishable key nunca pode ser substituída por `service_role`.

### BFF Preview

- `NEXT_PUBLIC_SUPABASE_URL`.
- `NEXT_PUBLIC_SUPABASE_ANON_KEY`.
- `SUPABASE_SERVICE_ROLE_KEY`.
- `OPENROUTER_API_KEY`.
- `HELICONE_API_KEY` é opcional e só deve ser usado se retenção/telemetria forem aprovadas.

Todas devem apontar, por nome e escopo Preview, à branch Supabase `xitugspwfxkcluxvrdeg` e ao projeto Vercel dedicado `agentempp-mobile-bff-staging`. A listagem remota de variáveis continua `NOT VERIFIABLE` por falta de acesso ao time/projeto correto; isso não foi interpretado como ausência.

### Agent, Auth e dois pacientes sintéticos

No próximo gate autorizado:

1. Criar uma única `agent_config` ativa para o estágio sintético, com modelo/limites aprovados e reutilização das seis regras já ativas; não criar prompt/modelo hard-coded nem tocar produção.
2. Corrigir redirect de confirmação exclusivamente para staging ou usar procedimento administrativo controlado que crie duas contas QA A/B já confirmadas. Não desabilitar confirmação global e não permitir redirect ao Site URL de produção.
3. Usar dois e-mails QA exclusivos em inbox controlada, credenciais fora do Git/terminal/relatório, dados neutros, `status=active` e somente o entitlement sintético mínimo `bodyflow_full`.
4. Provar login A, resposta, histórico após reabertura, replay sem nova cobrança, cancelamento/reabertura, logout e token ausente; depois login B, histórico vazio, tentativa de identidade A recusada/ignorada e token expirado/revogado.
5. Induzir falha de provider apenas por mecanismo reversível aprovado; provar inbound `failed`, retry estável e uma única mensagem lógica.

Isso prepara o E2E, mas não o executa e não valida signup/recuperação pelo app.

### Orçamento E2E apenas proposto

- Até 8 completions totais, contando tools/retries, sempre serializadas.
- `max_tool_iterations=2`, `max_tokens=1200` e contexto verificado antes do envio.
- Soft stop em US$ 3; chave exclusiva com hard cap US$ 5, sem renovação, expiração e disable no closeout.
- Parada imediata por oitava completion, cap, dado não sintético, rota/redirect de produção, vazamento A/B, auth persistentemente inválida, SHA diferente ou ausência de correlação de uso.
- Verificar tokens/custo/provider generation depois de cada chamada. O rate limit de mensagens não é controle monetário.

Este orçamento não está aprovado e não foi consumido.

## 8. Rollback e closeout futuros

- Publicar apenas Preview no projeto dedicado após nova autorização; nunca promover para Production neste gate.
- Rollback proposto: retirar/reverter somente o novo Preview e restaurar o deployment anterior conhecido, sem apagar o projeto Vercel.
- Remover/disable da chave OpenRouter exclusiva e verificar o estado no provider; remover somente o secret Preview pertencente ao teste.
- Desativar/remover somente a `agent_config` criada para o E2E, preservando regras anteriores.
- Contas/mensagens só podem ser excluídas com IDs exatos, prova sintética, ownership e autorização de closeout; caso contrário, desabilitar/reter com marcação QA.
- `DATA DISPOSITION: UNKNOWN` permanece para dados preexistentes. Não excluir/resetar a branch Supabase compartilhada.
- Nenhuma infraestrutura nova é necessária; se surgir essa necessidade, parar e apresentar custo/lifecycle antes de criar.

## 9. Revisões independentes

### A — segurança e superfície publicada

- Resultado final: `Critical 0 / Important 0 / Minor 0`.
- Validou bearer/ownership/entitlement, `service_role` server-only, headers, request ID, logs, literals de segredo, tools read-only, isolamento do Admin, closure e artefato NFT.
- O parecer preliminar encontrou como Minor o parser permissivo de metadata local. O guard foi restringido aos dois literais exatos do Flow e a revisão final confirmou a resolução, sem finding acionável.
- Riscos residuais não bloqueantes: Auth/RLS/ingress/provider reais não exercitados; rate limit não é controle monetário; retenção/telemetria do terceiro devem ser governadas no próximo gate.

### B — integração

- Resultado final: `Critical 0 / Important 0 / Minor 0`.
- Validou 41 rotas, identidade dos handlers `GET`/`POST`, metadata estática e `maxDuration: 300` no manifest, dependência/lockfile, closure, persistência/replay/retry/rate limit/falhas e compatibilidade do path/payload/bearer/idempotência com iOS.
- Executou verificação independente adicional de BFF, Admin/Agent, typechecks, mirrors, build surface, Biome e `git diff --check`.
- Risco residual não bloqueante: o timeout iOS de 30 segundos versus teto server-side de 300 segundos requer observação de latência e retry no E2E real.

Ambas as revisões foram read-only, feitas por revisores independentes e concluídas antes do commit.

## 10. Estado operacional

- Artefato publicável localmente: **VERIFIED**.
- Deployment executado: **NO**.
- Integração E2E externa: **NOT VERIFIED**.
- Vercel env/access: **NOT VERIFIABLE**.
- Deploy, migrations, usuários, `agent_config`, chamadas LLM e TestFlight: **NOT EXECUTED**.
- Supabase/Vercel remoto: preservado; nenhuma mutação.
- CI-3: HEAD `b4c09e80190fd6ce5c5f59b5193f8a6621554854`, branch e nove dirty preservados; index zero.
- Infraestrutura paga criada: nenhuma.
- Custo recorrente novo desta tarefa: US$ 0.
- A worktree/branch local deve ser preservada após o commit único; não há push, PR, merge ou cleanup remoto autorizado.

Este documento registra a árvore local revisada imediatamente antes do único commit. O SHA, parent, tree e lista de paths do commit são verificados após sua criação no relatório final da operação, sem amend.
