# Handoff — Performe AI beta (staging) — 2026-09-30 ~14:30 BRT

Continuação da operação `FINISH_PERFORME_AI_BETA_END_TO_END_NOW` (Claude Code → Codex).
Produto público: **Performe AI**; agente público: **Flow**; identidade técnica interna: BodyFlow (não renomear).
Responder ao Eduardo **em pt-BR, curto**, e dizer exatamente "Faça X agora." quando precisar das mãos dele.

## Regras que continuam valendo (não negociáveis)

- **Nada em Production.** Só staging: Supabase `xitugspwfxkcluxvrdeg`, Vercel Preview. Nunca `--prod`. Não tocar no deployment `dfik0mb7c`.
- **Sem push, PR, merge, tag, reset --hard, clean, stash para esconder, amend.** Commits locais por caminho explícito, com trailer de coautoria.
- **Segredos:** nunca imprimir/gravar valores (chaves, senhas, tokens, link de acesso). Não pedir segredo no chat. Senha do Roberto só ele digita.
- **Não criar identidades fictícias.** Roberto (`robertomenescal@yahoo.com.br`) = autor editorial + publicador (`content_editor` + `can_publish_content=true`). Eduardo = único `nutrition_admin` (revisor). Não registrar revisão/publicação em nome de ninguém.
- **Não marcar `USER VISUAL ACCEPTANCE: VERIFIED`** sem o Eduardo confirmar explicitamente. Não declarar "100%/pronto para Apple/produção validada".
- **Orçamento:** técnico US$15 total (gasto estimado até agora ~US$2), avaliação US$30 separado. Não criar recurso pago. Parar se algo pedir pagamento.
- **iPhone:** instalar POR CIMA (não apagar app/dados, não TestFlight). Pedir permissão antes de usar o iPhone via espelhamento (o Eduardo usa o celular).
- `CLAUDE.md` da raiz: bug relatado vira golden fixture com o cenário EXATO; revisão adversarial antes de commitar HIGH/CRITICAL; WhatsApp em produção é afetado por mudanças em `packages/agent` compartilhadas — sempre dizer isso.

## Estado atual (HEAD `79dfe83`, branch `codex/performe-ai-client-beta-flow-v1`, árvore limpa)

Commits de hoje (mais novo primeiro):
- `79dfe83` feat(flow): o chat mostra a sugestão completa (treino: exercício, séries×reps, descanso; dieta: alimento, medida+gramas, kcal, total vs meta) renderizada do rascunho gravado (`packages/agent/src/plan-suggestion-text.ts`); se o modelo resumir, o pipeline troca pela versão gravada (`ensureSuggestionShown`, evento `llm.plan_suggestion_rewritten`). "Proposta" → "sugestão" no Flow; plano importado de foto/PDF = "plano importado"; textos comuns = "rascunho"; registro de refeição continua "proposta" (decisão do Eduardo). Suplemento/medicamento nunca vai para o chat. Pendência declarada no commit (regex de cabeçalho compartilhados com WhatsApp).
- `fdb5b62` fix(agent): retry de guard ganha iteração própria (resolveu 502 `empty_reply` do Flow). Pendência: "2 rodadas de tool com max=2" ainda pode dar resposta vazia (agora mitigado quando há sugestão).
- `2be6370`, `75b82ca` CMS: `content_editor` com `can_publish_content` publica após revisão independente (migration `20260930120000_content_editor_publish_capability.sql` aplicada e testada no staging).
- `d4d7b2b`, `fc50593`, `e0b8b1f` iOS: ação de rotina usa relógio min(celular, servidor) e registra o instante do toque.

Deploys de staging (Preview):
- **BFF atual:** `https://agentempp-mobile-bff-staging-600suvc1j-gestao-9664s-projects.vercel.app` (dpl_ARNNgtv8LVgLmmsCEKghaNfRVuvF, sourceHead 79dfe83). Projeto `prj_NTrnUNFXfmddMuci3VWjalfAoejW`.
- **Worker/painel admin:** `agentempp-media-worker-staging-dopnv6cx4-…` (dpl_Cv1nyVKbncnAozuwQ9McAtgmkafX), com Vercel Authentication ligada.
- Padrão de deploy do BFF: copiar o pacote anterior (`$SP/deploy/pkg-<sha>`), `git archive HEAD` dos arquivos alterados em `packages apps/admin apps/mobile-bff`, conferir byte a byte contra HEAD, gates (`pnpm --filter @mpp/mobile-bff test|typecheck|verify:routes|verify:imports|build|verify:build-surface`, sem nomes de segredo em `.next/static`), depois `vercel deploy --target preview` com o CLI privado em `~/.local/share/performe-ai/vercel-cli-access` (`--scope gestao-9664s-projects --global-config $V/auth`). Smoke: rotas `/api/mobile/v1/{me,today,plan-drafts,content}` → 401 com `no-store` e `Vary: Authorization`.
- `$SP` = `/private/tmp/claude-501/-Users-eduardohenrique-Developer-performe-ai-client-beta-flow-v1/eb84ba62-26df-4310-815d-b453b27fc307/scratchpad` (pode sumir em reboot). Ledger detalhado: `$SP/roberto-beta/ledger.md`.

iPhone (UDID `00008110-001649510208401E`, bundle `com.performeai.app.dev.k6942zjtv6`):
- Instalado: build do commit `79dfe83` apontando para o BFF `600suvc1j` (xcconfig privado `~/.local/share/performe-ai/pre-llm-e2e/Release.staging.e2e-v21.private.xcconfig`). Sessão QA A mantida (user `864fe7a3-…`).
- Build/instalação: `xcodebuild build … -configuration Release -destination 'generic/platform=iOS' -xcconfig <v21> -allowProvisioningUpdates DEVELOPMENT_TEAM=K6942ZJTV6 PRODUCT_BUNDLE_IDENTIFIER=com.performeai.app.dev.k6942zjtv6`, depois `xcrun devicectl device install app --device <UDID> <app>`. Se o BFF mudar: novo xcconfig (trocar o id do host) e reinstalar por cima.
- Abrir o app: `xcrun devicectl device process launch --device <UDID> com.performeai.app.dev.k6942zjtv6`. Espelhamento: janela "iPhone Mirroring" em 270,47 (346×760); script `$SP/e2e/m.sh` (tap/shot); digitar com `cliclick -w 60 t:"…"` depois de focar o campo (câmera/microfone NÃO funcionam pelo espelhamento).

Simuladores: Pro Max `44AFCC15-85B3-4823-801E-2837718B9266` (gate), iPhone 17 Pro `27291590-659D-4A29-8F45-CA5CA2D154F9` (app de staging, não sobrescrever).

## Resultados verificados hoje

- Flow no iPhone: "Mostre meu progresso recente." respondeu (XP 0, sequência 0, bloco 0/7.700 — bate com `user_progress`); 502 resolvido.
- Proposta de treino pelo Flow: rascunho `956b82be` criado (limite 1/24h já usado hoje → novo teste de treino só em 2026-10-01).
- Regressão iOS (gate completo, Pro Max): unit 1470+34 OK; UI 20/20 classes, 169 testes, **1 falha**: `Prompt14AccessibilityUITests.testAccessibilityXXXLEvidence` linha 263 — falha determinística só no Pro Max (tela mais alta; o seletor "Todos/Salvos" continua visível). Passou 10× no iPhone 17 Pro. Premissa do teste, não regressão; **mudar o teste exige autorização do Eduardo** → REGRESSION STATUS: PARTIALLY VERIFIED.
- Após `79dfe83`: agent 1281, admin 802, BFF 26, typecheck limpo; iOS unit 1777 + teste novo; PlanDraftUITests 3/3; 3 testes de FlowChat falharam na rodada focada e passaram isolados (carga).

## Pendências, em ordem

1. **BLOQUEIO — gerador de dieta do Flow** (`packages/agent/src/diet-generator.ts`, compartilhado com WhatsApp `gera_dieta`; existe ramo `isFlow`). Hoje 2/2 falhas no iPhone: `protein_drift_exceeded` (242 g vs meta 186,1; tolerância 20%) e `zod_validation_failed` (`daily_meals.3.items.6.protein_g` ausente). Ontem o cardápio `7cafaf19` saiu 2.931 kcal vs meta 3.361. **Proposta feita ao Eduardo (aguardando o "sim")**: só no Flow, 1 nova tentativa do gerador com o motivo da recusa (números do desvio ou campo faltante); nada calculado/completado no código; mesmas travas. Golden com os eventos exatos acima; revisão adversarial; deploy BFF; testar no iPhone ("Quero uma sugestao de cardapio de um dia, sem restricoes.").
2. **Biblioteca (fluxo editorial real):** 6 artigos × pt-BR/en-US importados como **rascunho** do Roberto (nenhum publicado; nota `content.import.on_behalf` no audit_log). Link temporário do painel (expira 2026-10-01 14:20 UTC) guardado em `$SP/roberto-beta/share-link.txt` (0600) — o Eduardo já copiou para enviar ao Roberto. Próximo: Roberto entra e **envia para revisão** → Eduardo revisa ("Agora preciso que você revise estes artigos.") → Roberto publica. Depois: E2E da Biblioteca no app (pt/en, Dynamic Type, Pro Max, salvar/remover/concluir, persistência, A/B, nenhum rascunho visível, correção do toque na capa).
3. **Testes físicos no iPhone (mãos do Eduardo):** câmera "Tirar foto" (refeição), "Gravar áudio" com permissão de microfone, plano por foto (PDF aberto na tela do Mac), notificações se necessário.
4. Achados LOW anotados: Flow diz "nada registrado" com 7 refeições (progresso zerado por falta de fechamento de dia); tela de revisão mostra "full_body" cru; upload "Sem conexão" intermitente no 2º import.
5. Checklist de aceite visual para o Eduardo (não marcar VERIFIED sem ele).
6. Relatório final com as linhas: REGRESSION STATUS; PRODUCTION STATUS: NOT DEPLOYED; IOS INTEGRATION STATUS; REBRAND STATUS; ROBERTO BETA CANDIDATE STATUS; USER VISUAL ACCEPTANCE; COST / ENVIRONMENT CLOSEOUT.
7. Encerramento (depois do beta): bloquear QA B; arquivar config do Flow `f5013b3f` (max_tokens 1200, max_tool_iterations 2); deixar `dfik0mb7c` intocado.

## Custos (estimativa conservadora)

Técnico ~US$2 até agora (chamadas do Flow hoje: 0,062 + 0,015 + 0,034 + 0,061 + 0,033, mais gerador e áudio de ontem). Nenhum recurso pago novo.
