# Better Ahead / Flow — dossiê completo de contexto e plano de finalização

**Data de consolidação:** 20 de agosto de 2026

**Versão do dossiê:** 1.6.1

**Objetivo:** preservar em um único arquivo o contexto conhecido, o que já foi
feito, o estado técnico exato, as decisões tomadas, os bloqueios, o trabalho
restante e os gates necessários para chegar a dois resultados distintos:

1. um aplicativo funcional, integrado e distribuível para o cliente testar; e
2. um aplicativo aprovado pelo cliente, preparado e submetido à App Store.

Este documento é um handoff técnico e executivo. Ele não declara que o
aplicativo está pronto, não autoriza deploy, migração, compra de domínio,
registro de marca, assinatura, TestFlight, envio à App Store, cobrança, merge,
push ou descarte de artefatos.

---

## 1. Leitura executiva: a verdade em uma página

### 1.1 Situação atual

O produto **não está 100% finalizado**.

O que existe é uma base iOS muito avançada e amplamente testada em modo
demonstrativo, um backend/WhatsApp maduro, uma Mobile API extensa validada em
staging e uma reidentificação para **Better Ahead** e **Flow** parcialmente
concluída. O trabalho restante não é somente “trocar logo e nome”.

Hoje, a realidade é:

| Área | Estado | Verdade operacional |
| --- | --- | --- |
| Produto e jornadas iOS | **PARCIAL/AVANÇADO** | Muitas telas e jornadas existem e passaram por testes locais extensos. |
| UI/UX e acessibilidade | **PARCIAL/AVANÇADO** | Há evidência de modos claro/escuro, Dynamic Type, contraste, Reduce Motion e estados de tela. Falta a validação final do app integrado. |
| Identidade Better Ahead | **PARCIAL** | Nome, voz, slogans e estratégia visual estão aprovados. Tasks 0–2 do rebrand foram concluídos; Tasks 3–10 ainda não. |
| Português e inglês | **PARCIAL** | A fronteira bilíngue inicial e nomes públicos foram implementados. A localização completa das telas autenticadas ainda pertence às Tasks 7–8. |
| App iOS em Release | **BLOQUEADO POR PROJETO** | O Release compila, mas usa `UnavailableAPIClient` e serviços indisponíveis. Não conversa com backend real. |
| Autenticação iOS real | **FUNDAÇÃO IMPLEMENTADA** | CI-1 adicionou Auth isolado, Keychain e uma fonte única de sessão; ambiente real e E2E continuam pendentes. |
| Mobile API/BFF | **IMPLEMENTADA EM CÓDIGO, STAGING PARCIAL** | Contratos existem e foram validados em staging; a URL de staging/publicação Vercel e a integração iOS real não foram fechadas. |
| Backend em produção para o app | **NÃO VERIFICADO/NÃO PROMOVIDO** | As novas fundações foram documentadas como staging-only; produção ficou intocada nas entregas de julho. |
| Agente “Flow” ponta a ponta | **PARCIAL** | O agente MPP/WhatsApp existe, mas o rebrand público do backend e a integração do app ainda são Workstream 2. |
| Push real | **PARCIAL** | Devices, preferências, regras, filas e scheduler existem; o provider APNs e o envio real não foram configurados. |
| Assinaturas | **PARCIAL** | Entitlements e projeções foram construídos; StoreKit, produtos, preços, RevenueCat real e cobrança ficaram deliberadamente adiados. |
| Jurídico/privacidade/App Store | **PENDENTE** | Entidade vendedora, termos, privacidade, exclusão, disclosures de saúde/IA, URLs, marca, domínio e metadados ainda precisam ser fechados. |
| TestFlight/App Store | **NÃO AUTORIZADO/NÃO EXECUTADO** | Nenhuma evidência confirma upload, distribuição externa ou submissão. |

### 1.2 O que “100%” significa neste projeto

Há dois marcos. Misturá-los cria uma falsa sensação de conclusão.

#### Marco A — beta funcional para o cliente

O cliente recebe um build assinado e utilizável, com:

- marca Better Ahead e agente Flow consistentes em todas as superfícies
  alcançáveis;
- interface em português do Brasil e inglês;
- autenticação real;
- transporte HTTPS autenticado;
- Mobile API de staging publicada;
- dados e jornadas reais, sem mocks de sucesso em Release/beta;
- sessão, logout, rotação de token e cancelamento de requisições corretos;
- estados de carregamento, vazio, erro, offline e recuperação;
- backend e mensagens remotas sem vazamento da marca antiga;
- QA ponta a ponta, acessibilidade e segurança aprovados;
- canal de distribuição privado escolhido e autorizado.

#### Marco B — versão pronta para a App Store

Além de tudo do Marco A:

- aceite formal do cliente e correção dos achados da UAT;
- produção migrada/deployada com canário e rollback;
- produtos StoreKit/RevenueCat e política comercial aprovados;
- privacidade, termos, consentimentos e informações de suporte publicados;
- marca/domínio avaliados e decididos;
- App Store Connect, assinatura, provisioning, screenshots, classificação
  etária, privacy labels e notas de review;
- archive final, upload autorizado, TestFlight externo se necessário e
  submissão;
- monitoramento, suporte e resposta a incidentes preparados.

### 1.3 Estimativa realista, não promessa

Se o escopo da primeira versão for um **companion app** integrado — sem
inventar chat nativo completo, sem mudanças grandes de produto e com decisões
rápidas do cliente — a estimativa conservadora é:

| Bloco | Estimativa |
| --- | ---: |
| Retomar e concluir o rebrand iOS Tasks 3–10 | 3–7 dias produtivos no Mac, se Docker/gates não abrirem novo STOP |
| Transporte, autenticação, sessão e adapters iOS + staging E2E | 2–4 semanas |
| Rebrand do backend, APNs e/ou assinatura no escopo da beta | 1–3 semanas, parcialmente em paralelo |
| QA integrado, UAT e correções | 1–2 semanas |
| Preparação e submissão à App Store | 1–2 semanas, mais o tempo de análise da Apple |

**Faixa total prudente até estar genuinamente pronto para submissão:
aproximadamente 5–10 semanas.** O prazo depende do escopo de chat/push/paywall,
da aprovação de migrações de produção, das contas Apple/RevenueCat, dos
documentos jurídicos e do tempo de resposta do cliente.

---

## 2. Legenda de confiabilidade

Para não misturar fatos de épocas e ambientes diferentes, este dossiê usa:

- **CONFIRMADO:** comprovado por código, commit, relatório ou gate reproduzível.
- **PARCIAL:** existe uma parte funcional, mas a jornada completa não fechou.
- **REPORTADO PELA SESSÃO LOCAL:** evidência fornecida pela sessão que opera o
  Mac/Xcode; não foi reexecutada nesta VPS.
- **NÃO VERIFICADO:** pode existir externamente, mas não há prova atual neste
  contexto.
- **PENDENTE:** trabalho ou decisão ainda necessários.
- **BLOQUEADO:** há um gate explícito impedindo avanço.
- **N/A:** auditado e não aplicável à base atual.

Datas importam. Documentos de maio, junho, julho e agosto retratam momentos
distintos e podem divergir sem que um deles seja necessariamente falso.

---

## 3. Fontes e autoridade

### 3.1 Documentos centrais

- `docs/superpowers/specs/2026-08-11-better-ahead-rebranding-design.md`:
  especificação aprovada do rebrand.
- `docs/superpowers/plans/2026-08-11-better-ahead-ios-rebrand.md`:
  plano executável autoritativo do Workstream 1.
- `docs/BRIEFING-PRODUTO-MARCA-COMUNICACAO-UX.md`:
  produto, posicionamento, experiência, comunicação e visão de app.
- `docs/PLATAFORMA-AGENTE-MPP.md` e
  `docs/AGENTE-MPP-REFERENCIA-INTEGRACAO.md`:
  arquitetura do agente, integrações, tools, workers e operação.
- `docs/mobile/api-v1.md` no commit iOS aprovado:
  contrato da Mobile API.
- `docs/audits/2026-07-02-full-platform-audit.md`:
  auditoria técnica da plataforma naquele momento.
- `docs/business/2026-07-16-relatorio-precificacao-economia-unitaria-app-nativo.md`:
  hipóteses de preço e economia unitária.
- evidências e planos iOS presentes no commit aprovado
  `11f5a7cec331d4fc683b6cee5cdf046d3e89623d`.

### 3.2 Insumos externos fornecidos na conversa

- feedback do cliente de 10/08/2026 sobre BodyJourney, BeBetter, evolução
  contínua e “Better every day”;
- screenshot de indisponibilidade de `bodyflow.app`;
- screenshot de busca preliminar no INPI para “bodyflow”;
- cartão CNPJ fornecido em PDF;
- inventário forense read-only das famílias de testes do renderer;
- relatórios sucessivos da sessão local do Mac/Xcode.

### 3.3 Conflitos documentais que devem permanecer explícitos

1. `docs/CONTEXT.md` é um snapshot antigo, de maio, e menciona ausência de
   staging separado/usuários; documentos posteriores descrevem pilotos e
   staging dedicado. Não usar o snapshot antigo como estado operacional atual.
2. Documentos de junho descrevem a operação WhatsApp em uso; os documentos de
   julho deixam claro que a nova plataforma mobile foi validada somente em
   staging e não promovida à produção.
3. O relatório comercial de julho propõe novos preços, enquanto documentação
   Stripe anterior usa outro catálogo e trial de sete dias. A conversa registra
   “3 dias somente”, mas o rótulo da pergunta original não está disponível
   neste histórico consolidado. O trial de três dias precisa de confirmação
   final antes de configurar cobrança.
4. A autorização para merge sequencial dos PRs #16 e #17 foi dada, mas o
   resultado efetivo desses merges não está comprovado neste contexto.
5. Pesquisas de INPI, domínio e lojas foram preliminares. Não equivalem a
   clearance jurídico nem a reserva de nome.

---

## 4. Produto, marca e decisões já travadas

### 4.1 Produto

Better Ahead é uma plataforma de acompanhamento personalizado de saúde,
hábitos, alimentação, treino e evolução. A tese central é a continuidade:

`avaliação → objetivo → estratégia → alimentação → exercício → hábitos →
evolução → manutenção`.

O LLM não é o produto inteiro. O produto combina regras determinísticas,
estado oficial, registros confirmados, protocolos, progressão, conteúdo,
mensagens, operação profissional e IA para interpretar e orientar.

### 4.2 Nomes públicos aprovados

- **Produto:** Better Ahead.
- **Agente/guia dentro do produto:** Flow.
- Better Ahead e Flow são nomes próprios e **não são traduzidos**.
- `Focus`, `Impulse` e `Zen` permanecem como estilos do Flow, com descrições
  localizadas e códigos internos preservados.

### 4.3 Conteúdo institucional aprovado

| Uso | Português do Brasil | Inglês |
| --- | --- | --- |
| Marca | Better Ahead | Better Ahead |
| Slogan | Melhor a cada dia. | Better every day. |
| Descriptor | Sua jornada personalizada para uma vida mais saudável. | Your personalized journey to a healthier life. |
| Papel do agente | Flow, seu guia em cada etapa. | Flow, your guide every step of the way. |

### 4.4 Estratégia visual aprovada

- Reutilizar o símbolo abstrato “B” aprovado, o AppIcon, a paleta e a linguagem
  premium/wellness.
- Não redesenhar a identidade do zero.
- A leitura pretendida passa a ser: **B = Better** e movimento = **Ahead**.
- Preservar bytes dos símbolos e AppIcons invariantes.
- Criar somente os novos wordmarks/lockups/splash Better Ahead.
- Introduzir interfaces semânticas de assets, para que uma futura mudança de
  marca não exija acoplar telas ao nome histórico.

### 4.5 Identidade técnica preservada

O rebrand muda superfícies públicas, não contratos internos estáveis:

- target, scheme, módulo e raiz Swift continuam `BodyFlow`;
- bundle identifier continua `com.bodyflow.app`;
- chaves persistidas `bodyflow.*` permanecem;
- payloads como `using_bodyflow` permanecem;
- tipos internos `Coach*`/`Mascot*` permanecem;
- eventos de telemetria, accessibility identifiers, launch arguments e
  contratos de API permanecem, salvo vazamento público comprovado.

### 4.6 Evolução da decisão de naming

O caminho foi:

1. `bodyflow.app` apareceu como indisponível.
2. A busca preliminar de “BodyFlow” no INPI mostrou registros/processos em
   classes relacionadas; isso elevou o risco de continuidade.
3. Foram discutidos BodyJourney, BeBetter, Become, BeNext, BeMore, BeWell,
   BeFit, BeYou, BeYourBest, BetterYou, BetterEveryday, BetterDaily,
   BetterLife, BetterSelf, BetterWay, BetterPath, BetterUp, GetBetter,
   LiveBetter, MoveBetter, FeelBetter, DoBetter, GoBetter, GrowBetter, Evolve,
   EvolveYou, EvolveMe, EvolveDaily, GoEvolve, Thrive, ThriveYou e LevelUp.
4. O cliente destacou BodyJourney pela ideia de jornada e BeBetter pela ideia
   de evolução/aprendizado e “melhor a cada dia”.
5. Buscou-se equilíbrio entre sofisticação e clareza.
6. A escolha final foi **Better Ahead**, posteriormente aprovada junto com a
   reutilização/adaptação do símbolo existente.

### 4.7 O que ainda não está resolvido na marca

- busca formal de anterioridade e similaridade no INPI;
- estratégia de depósito e classes;
- busca/clearance internacional, se houver lançamento nos EUA;
- confirmação do nome nas lojas no momento do cadastro;
- domínio principal e variações defensivas;
- handles sociais;
- titular da marca, domínio e contas;
- aprovação visual do **candidato renderizado Better Ahead**. A aprovação
  anterior da família BodyFlow 1.0.0 não substitui esse gate.

---

## 5. Mapa de repositórios, branches e worktrees

### 5.1 Repositório documental atual nesta VPS

- caminho: `/root/agentempp`;
- branch: `codex/better-ahead-rebranding-design`;
- HEAD em 20/08/2026:
  `13fd60a709228566c2b0e639ba58a515ce0abea0`;
- parent:
  `ad3fb05b903ed034364fc6190240caf1954c4a2b`;
- assunto: `docs(brand): reconcile hierarchical TAP gate`;
- data do commit: 14/08/2026 19:16:42 UTC;
- blob atual do plano:
  `f2d622a7f7f378110fd2a0593336297fd97b65b9`;
- remote: GitHub, repositório `corehealth-app/agentempp`;
- origin da mesma branch observado sincronizado.

A worktree já estava suja por mudanças do usuário não relacionadas a este
dossiê. Antes da criação deste arquivo:

- staging vazio;
- 25 entradas usando `git status --porcelain=v1 -uall`;
- SHA-256 do porcelain:
  `455000fe5f148dcad3034f03d57e2683deedb8ae5ec655b8a459639117f040e0`;
- SHA-256 do diff binário tracked:
  `7262d613d02df890c8e0c02922fa778afb90a6b7c27aa25a417bf0c717bdbefb`.

Esses arquivos preexistentes não podem ser descartados, staged ou alterados
como efeito desta documentação.

Os cinco arquivos tracked já modificados eram:

- `.gitignore`;
- `packages/agent/src/curated-phrase-selector.test.ts`;
- `packages/agent/src/curated-phrase-selector.ts`;
- `packages/agent/src/educational-comment.test.ts`;
- `packages/agent/src/educational-comment.ts`.

Também já existiam documentos, `memory/`, PDFs e scripts não rastreados. A
árvore `apps/ios` não está presente no checkout documental atual; o cliente iOS
é consultado no objeto Git `11f5a7c…` e trabalhado na worktree isolada do Mac.

### 5.2 Git manager no Mac

Estado **REPORTADO PELA SESSÃO LOCAL**:

- caminho: `/Users/eduardohenrique/Developer/bodyflow`;
- HEAD: `0ce7f20f22b0e66a6de0544d4a46345181f2fccb`;
- worktree limpa;
- staging vazio;
- uso: fetch, consulta de objetos e gestão da worktree isolada;
- não é a fonte dos nove diagnósticos.

### 5.3 Repositório diagnóstico no Mac

Estado **REPORTADO PELA SESSÃO LOCAL**:

- caminho:
  `/Users/eduardohenrique/Developer/bodyflow-brand-design-system-v1`;
- HEAD: `03df7894e4cdb37db08351aafb6dd20ad4cb4103`;
- exatamente nove paths modificados, unstaged;
- staging vazio;
- SHA-256 do porcelain:
  `4fc733aeb4f41ce17e7ed094920c0d5ab70da26b879d49c594a84f050e58550c`;
- os nove arquivos são evidência física e devem permanecer intactos.

### 5.4 Worktree de implementação Better Ahead no Mac

Estado **REPORTADO PELA SESSÃO LOCAL**:

- caminho físico:
  `/private/tmp/better-ahead-ios.GQgTa0/worktree`;
- branch: `codex/better-ahead-ios-rebrand-v1`;
- HEAD atual antes do novo handoff:
  `ad9869c0d6b11222263ea40c7b72e329092aeef5`;
- parent:
  `8f4020b0ae27d27c0de1b97d1682f507cd0be57c`;
- staging vazio;
- exatamente sete arquivos modificados, unstaged;
- nenhum environment, bundle, export, review PNG, lock, journal ou transaction
  criado;
- nenhum render real Better Ahead executado.

### 5.5 Base iOS/asset aprovada

- branch histórica: `codex/bodyflow-ios-brand-design-system-v1`;
- tip aprovado:
  `11f5a7cec331d4fc683b6cee5cdf046d3e89623d`;
- a implementação do rebrand parte dessa base, não da branch documental.

---

## 6. O que já foi construído antes do rebrand

### 6.1 Plataforma do agente e operação WhatsApp

**CONFIRMADO EM CÓDIGO/DOCUMENTAÇÃO, com estado live atual a revalidar.**

A plataforma existente inclui:

- onboarding conversacional por WhatsApp;
- mensagens de texto, áudio e foto;
- interpretação de refeições e treinos;
- cálculos determinísticos de metas, balanços e Bloco 7700;
- dietas, treino, hábitos, lembretes e reavaliação;
- conteúdo educacional;
- TTS;
- painel administrativo;
- telemetria e jobs;
- ferramentas do agente e funções Inngest.

Integrações documentadas:

- OpenRouter para conversa/roteamento de modelos, visão e embeddings;
- Groq para speech-to-text;
- ElevenLabs e/ou Cartesia para text-to-speech;
- WhatsApp Cloud API;
- Supabase para banco, auth, storage e vetores;
- Inngest para workflows;
- Vercel para o app/admin/BFF;
- Stripe para cobrança web existente;
- Telegram em rotinas operacionais;
- Helicone, Sentry e Resend como integrações opcionais/configuráveis.

Os valores de chaves e secrets nunca devem entrar em documentação, logs ou
Git. Antes de beta, verificar somente existência, escopo, rotação, owner e
ambiente das credenciais necessárias.

### 6.2 Backend mobile

No commit iOS aprovado, a Mobile API V1 contém cerca de cinquenta operações
organizadas em:

- identidade e perfil: `/me`, `/profile`, `/onboarding`;
- dia, plano, progresso e histórico: `/today`, `/plan`, `/progress`,
  `/history`;
- ciclo de registros: propose, edit, confirm, cancel e pending;
- persona/estilo do coach;
- conteúdo, detalhe, read e save;
- entitlements;
- mídia privada, conclusão, processamento e download;
- devices;
- preferências de notificação e reminders;
- suplementos, medicamentos, histórico e aceites legais;
- hidratação e wrappers de rotina.

Contrato:

- prefixo `/api/mobile/v1`;
- bearer do Supabase para paciente com e-mail confirmado;
- bloqueio de admin/blocked/deleted/identidades legadas não migradas;
- `service_role` nunca entregue ao app;
- `Cache-Control: no-store`, `Vary: Authorization` e request ID;
- idempotency key obrigatória nas mutações;
- envelope uniforme de sucesso/erro.

Estado daquela entrega:

- ambiente validado: Supabase staging
  `xitugspwfxkcluxvrdeg`;
- produção: não alterada;
- URL base: pendente da publicação Vercel de staging;
- integração real do app: não implementada.

### 6.3 Segurança P0

A auditoria de 02/07/2026 encontrou, naquele momento:

- Server Action administrativa usando service role sem autorização suficiente;
- tabelas com RLS desabilitado e grants amplos;
- RPCs `SECURITY DEFINER` executáveis por papéis públicos;
- views administrativas potencialmente contornando RLS;
- dependências com advisories;
- `daily_close_user` quebrada no banco live;
- falta de índice para status do WhatsApp;
- busca vetorial pouco eficiente;
- auto-reconciliação operacional arriscada;
- lint global vermelho e outras dívidas de hardening.

Parte relevante foi corrigida no histórico que antecede o tip iOS aprovado:

- audit autofix opt-in: `1769045`;
- remoção da RPC diária obsoleta: `fa8b51f`;
- índice de status: `f4c99d0`;
- busca vetorial: `3b7e801`;
- hardenings P0: `58c8f5d`, `e955337`, `df32950`, `3575cac`,
  `100b02e`;
- permissões: `cd12463`.

Esses commits são ancestrais de `11f5a7c…`, mas a validação registrada foi em
staging. **Isso não prova que a produção atual esteja corrigida.** Antes da App
Store, é obrigatória uma auditoria read-only fresca do ambiente de produção,
seguida de promoção controlada, smoke/canário e rollback.

### 6.4 Push e rotina

Já existem fundações para:

- devices iOS;
- preferências;
- quiet hours e limites;
- regras de reminder;
- hidratação;
- adesão a suplementos/medicamentos;
- eventos e fila idempotente;
- scheduler Inngest que enfileira IDs.

Limite explícito da entrega: **nenhum provider APNs real foi configurado e
nenhum push real foi enviado**.

### 6.5 Entitlements e cobrança

Já foram construídos e testados:

- schema central de entitlements;
- resolver determinístico;
- projeção Stripe;
- webhook RevenueCat validado e desabilitado por padrão;
- isolamento, ownership, replay protection, allowlists e reconciliação.

Evidência de 24/07/2026:

- 2.022 testes;
- typecheck 8/8;
- build do admin;
- Deno/Stripe checks;
- lint de banco sem erros;
- staging sem jobs ativos, entitlements ou secrets de provider.

Ficaram adiados:

- configuração de conta/provider;
- produtos StoreKit;
- product IDs, preços, paywall e ofertas;
- cobrança real;
- migração de produção;
- reconciliação de usuários reais;
- deploy e merge;
- correção do lint global preexistente.

### 6.6 App iOS demonstrativo

O tip `11f5a7c…` contém uma aplicação SwiftUI substancial:

- scaffold e navegação;
- autenticação e onboarding demonstrativos;
- cinco abas;
- Hoje;
- Registrar refeição, treino, água e peso;
- Plano;
- Progresso e Bloco 7700;
- Histórico;
- Rotina, suplementos e medicamentos;
- Biblioteca educacional;
- mascote/coach, precursor visual e comportamental do Flow;
- Perfil;
- múltiplos estados de conteúdo, erro e navegação.

Gate do Prompt 14:

- 1.067 testes lógicos iOS;
- 1.185 execuções nativas;
- 955 testes unitários lógicos;
- 112 testes XCUI lógicos;
- zero falhas, skips ou expected failures;
- backend + iOS: 1.919 testes lógicos;
- backend + execuções nativas parametrizadas: 2.037 execuções;
- builds Debug unsigned, Release unsigned e Debug executável aprovados;
- 21 pares PNG/hierarquia;
- validação em Dark Mode, Dynamic Type XXXL, Increase Contrast,
  Differentiate Without Color e Reduce Motion.

Warnings herdados e não bloqueantes documentados:

- propriedades UIKit isoladas ao MainActor em telas de hidratação/treino;
- resultado não usado de `waitUntilStarted` em teste de coordenação;
- extração de AppIntents ignorada sem dependência do framework.

### 6.7 Limite crítico do app iOS

Apesar da cobertura visual e dos builds:

- Release usa `UnavailableAPIClient`;
- autenticação usa `DemoAuthenticationService`;
- várias capabilities de Today, History, Plan, Progress, Registration, Routine
  e mídia ficam indisponíveis fora da configuração Debug/demo;
- não há base URL real;
- não há token/session bridge;
- não há integração Supabase/BFF live;
- não há conta real nem provider no cliente;
- um build Release aprovado prova compilação e fail-closed, não funcionalidade.

Logo, a base é excelente para UI/UX e contratos, mas **ainda não é um app
funcional end-to-end para o cliente**.

---

## 7. Histórico da identidade BodyFlow 1.0.0

### 7.1 Entregas

A família original foi construída na branch
`codex/bodyflow-ios-brand-design-system-v1`. Histórico relevante:

| Commit | Papel |
| --- | --- |
| `3289a2f` | base da sequência de brand assets |
| `168b114` | evolução da família |
| `5f5e9a4` | evolução da família |
| `03df7894e4cdb37db08351aafb6dd20ad4cb4103` | SHA inicialmente sincronizado/pushed |
| `a384ef66543790d219c606bb963cd4cb6312d0ac` | gate nativo posterior |
| `d5617d6` | fechamento intermediário |
| `96a9401` | fechamento intermediário |
| `11f5a7cec331d4fc683b6cee5cdf046d3e89623d` | tip iOS/asset aprovado para o rebrand |

O usuário aprovou visualmente a família **BodyFlow versão 1.0.0**.

### 7.2 Divergência byte/pixel do rerender

O único rerender autorizado mudou:

- cinco exports PNG;
- as três cópias de AppIcon;
- bytes e pixels, embora a diferença visual fosse mínima.

Manifesto combinado informado:

- antes:
  `468ce80310ade419cc6ea52dfe0a8a37c96740d6c6a3104c95c165de52852a6d`;
- depois:
  `d0a6a6889a8f2fee795c2bc1994cc9475f8a1ab8d39769f557dd15f7a5055c1b`.

A revisão independente mediu diferenças reais de até 1/255 em poucos pixels.
A causa atribuída foi o stack nativo Sharp/libvips/librsvg no Mac, cujo
fingerprint histórico não havia sido versionado. Os masters, scripts e fontes
não tinham mudança explicativa.

Conclusão correta naquele gate: não era permitido declarar invariância
byte/pixel. Os nove arquivos foram mantidos para auditoria. Em seguida, o
usuário:

- autorizou aceitar os outputs gerados no Mac;
- aprovou visualmente a família;
- permitiu continuar no formato de gates nativos locais.

### 7.3 Gate nativo do SHA a384ef6…

Ambiente reportado:

- Xcode 26.6 (`17F113`);
- Swift 6.3.3;
- macOS 26.5.2;
- iPhone 17 Pro;
- iOS Simulator 26.5.

Resultado:

- 15 testes lógicos;
- 46 execuções totais;
- 46 aprovadas;
- 0 falhas, skips ou expected failures;
- Debug: `BUILD SUCCEEDED`;
- Release: `BUILD SUCCEEDED`;
- zero warnings de Asset Catalog;
- somente warnings herdados de AppIntents, MainActor e resultado não usado.

Esse histórico explica por que os nove diagnósticos continuam preservados e
por que o novo rebrand usa um renderer canônico muito mais restrito.

---

## 8. Rebrand Better Ahead — Tasks já concluídas

### 8.1 Task 0 — worktree isolada e prova de base

**Status: CONCLUÍDA.**

- commit: `5317fab1af6d82bcd2886c07149244a2cb2c1765`;
- separação correta entre Git manager e repositório diagnóstico;
- base iOS aprovada resolvida;
- worktree de implementação isolada criada no Mac;
- nenhum dos nove diagnósticos descartado ou staged.

Houve um STOP inicial porque o plano apontava o Git manager como fonte dos
nove diagnósticos. A autoridade foi reconciliada para usar:

- `/Users/eduardohenrique/Developer/bodyflow` como Git manager;
- `/Users/eduardohenrique/Developer/bodyflow-brand-design-system-v1` como
  fonte diagnóstica nos Tasks 0, 1 e 10.

### 8.2 Task 1 — proveniência e gate de bytes preservados

**Status: CONCLUÍDA.**

Commits:

- `caa644e85d3a421b4cdc2e1549690db19761bced`;
- hardening:
  `844ebcc1f761a77fa80953ba9bc9604808f14dd2`.

Resultado:

- 17/17 testes;
- 24 assets preservados verificados;
- revisão independente aprovada;
- staging e worktrees externas preservados;
- manifesto histórico continua autoridade dos bytes invariantes.

### 8.3 Task 2 — identidade bilíngue e nomes públicos do bundle

**Status: CONCLUÍDA.**

Commits:

- reconciliação documental:
  `f1bbe183081d73e1c6ed48eefbbfe97bd92fae9a`;
- implementação:
  `701c272030ead0061e76e3ee69801d7dbf763917`;
- teste das cinco chaves em ambos os idiomas:
  `4f635ad2b5802239575ef2b6ec04b0aed50db740`.

Entregas:

- `BrandIdentity`/conteúdo bilíngue inicial;
- `CFBundleDisplayName = Better Ahead`;
- `CFBundleName = Better Ahead` nos plists compilados;
- `pt-BR` e inglês com os cinco conteúdos aprovados;
- Debug e Release aprovados;
- suites focadas aprovadas;
- hashes de catálogos preservados;
- revisão independente sem Critical/Important.

### 8.4 Por que foi necessário um Info.plist explícito

Com `GENERATE_INFOPLIST_FILE=YES`, o Xcode 26.6 forçava
`CFBundleName` a partir de `PRODUCT_NAME=BodyFlow` e ignorava a tentativa de
`INFOPLIST_KEY_CFBundleName=Better Ahead`.

A solução mínima:

- criar `BodyFlow/Resources/Info.plist`;
- `GENERATE_INFOPLIST_FILE=NO`;
- `INFOPLIST_FILE=BodyFlow/Resources/Info.plist`;
- exceção de membership sincronizada para impedir Copy Bundle Resources;
- preservar target, scheme, módulo, executável, `PRODUCT_NAME` e bundle ID.

Uma divergência adicional foi documentada:

- o gerador do Xcode produzia `UILaunchScreen = { UILaunchScreen = {} }`;
- o plano inicialmente esperava `UILaunchScreen = {}`.

O baseline e o contrato foram reconciliados para preservar a estrutura
realmente compilada nos dois modos.

Minor conhecido:

- o teste de idioma oposto assume inglês para qualquer preferência inicial que
  não seja portuguesa. Não bloqueou a Task 2, mas deve ser revisitado na
  localização completa.

---

## 9. Task 3 — histórico completo dos STOPs e hardenings

### 9.1 Objetivo da Task 3

Criar um pipeline Better Ahead estreito, reproduzível e seguro que:

- não re-renderize a família BodyFlow;
- preserve todos os assets invariantes;
- gere somente wordmark, lockup e splash/review Better Ahead;
- use Docker Desktop canônico em `linux/amd64`;
- publique um bundle inteiro de forma atômica e imutável;
- registre fingerprint de ambiente;
- resista a symlink, TOCTOU, colisão, crash e recovery;
- não perca evidência da única tentativa visual autorizada.

### 9.2 Commit parcial

- `0a5001e90c9816cb2f9be6f2ff1be6bfa3b0fb38`;
- assunto: `build(brand): add Better Ahead asset pipeline`.

Antes do primeiro bloqueio:

- contrato 27/27;
- `validate:inputs` aprovado;
- baseline de 24 arquivos aprovado;
- `git diff --check` aprovado;
- nenhum export/review PNG/environment criado.

### 9.3 Sequência dos bloqueios e decisões

| Ordem | Bloqueio encontrado | Decisão/reconciliação |
| ---: | --- | --- |
| 1 | Docker não estava disponível; comando terminou no código contratual 78. | Nenhum render foi executado. Exigir Docker Desktop canônico. |
| 2 | Lock/recovery não preservavam autoridade em todas as falhas; havia TOCTOU e proveniência não delimitada de um SVG histórico. | Hardening documental e de testes. |
| 3 | Plano dizia “somente três hardenings”, mas também exigia digest, Corepack/pnpm e fingerprint Docker adicionais. | Autoridade documental ampliada explicitamente. |
| 4 | `CLEANUP_REQUIRED` entrava em conflito com fluxo genérico que poderia rerenderizar. | Definido: cleanup termina a limpeza e retoma Step 3 sem novo render. |
| 5 | Revisão encontrou Critical no commit do receipt, symlink-following no recovery e render antes do journal. | Usuário escolheu **Opção A**: publicação atômica do bundle inteiro, com arquitetura begin/resume/finish e journal antes de trabalho visual. |
| 6 | SHA documental informado `c8d2d2fef8a49d28cc821bc199590ad83494bac4` não existia; o real era diferente. | Confirmado o SHA real `c8d2d2fa9a4e137ba8e2400140a17dc2ef47fd8e` antes de prosseguir. |
| 7 | Buildx 0.32.1 apaga e recria `--iidfile` por pathname, incompatível com a promessa no-follow. | Substituir `--iidfile` por `--quiet` e capturar stdout em FD preaberto/no-follow; manter um build e um container. |
| 8 | OA-16 truncado e seis races OA-34 eram inexequíveis sem seam de teste. | Autorizar seam V3 fechada, somente programática, inacessível por CLI/env e sem paths/callbacks arbitrários. |
| 9 | 10 consumidores legados e a cauda plana impediam full GREEN. | Executar inventário forense e migrar/remover por autoridade explícita. |
| 10 | A hipótese “108 testes” estava errada. | Inventário confirmou **107**: 106 transitivos + 1 direto; o suposto 108º era NM-001 e usava somente recovery exportado. |
| 11 | Regex documental não selecionava roots chamados exatamente OA-16/OA-34 e o parser ignorava subtests TAP indentados. | Commit `13fd60a…` reconcilia parser TAP hierárquico, contagem e diagnósticos. |

### 9.4 Inventário forense consolidado

O inventário read-only confirmou:

- quatro controles proibidos:
  `nativeBeginFault`, `nativeJournalUpdateFault`,
  `nativeCleanupFault` e `nativeCleanupBarrier`;
- dez blocos consumidores;
- 23 folhas materializadas nesses blocos;
- 21 folhas controladas e duas folhas KEEP sem controle;
- 107 testes dependentes do export removido:
  - 106 transitivos;
  - 1 direto;
- classificação da cauda:
  - 83 migrações;
  - 20 remoções de arquitetura plana obsoleta;
  - 4 lacunas P1;
  - 1 deduplicação NM-001;
- nenhum dos dez blocos controlados tinha equivalência exata; sete eram
  parciais e três sem contraparte.

O export `promoteBetterAheadCandidates` pertence à arquitetura plana antiga e
não deve ser restaurado. O substituto é o lifecycle:

`begin → dispatch → resume → finish`, com `recover` e recuperação de orphan.

### 9.5 Autoridades documentais intermediárias

Commits/heads relevantes da evolução:

- `ac6960f690dda59844cb6cedef96f23f81a4558c`;
- `9d204ab10801cd2cb07ec8d5ee6a759b12dd296b`;
- `c8d2d2fa9a4e137ba8e2400140a17dc2ef47fd8e`;
- `60ecb54175fd1172ffe2105a8059702f8b3d8ea0`;
- `726bae58042dc4da86b08f3fa52de0f2dccc24a4`;
- `8f4020b0ae27d27c0de1b97d1682f507cd0be57c`;
- `ad9869c0d6b11222263ea40c7b72e329092aeef5`;
- autoridade remota atual:
  `13fd60a709228566c2b0e639ba58a515ce0abea0`.

### 9.6 Testes já executados durante o hardening

Entre os gates registrados:

- Journal R6: RED 0/2 → GREEN 2/2;
- unlock same-inode: RED 0/2 → GREEN 2/2;
- preflight Q: RED 0/2 → GREEN 2/2;
- Round 3 unlock: 9/9;
- Round 4: 6/6;
- Round 5: 3/3;
- shard final congelado: 5/5 no shard 1; shard 2 não iniciado;
- Corepack/pnpm efetivo preservado em 10.33.2.

Esses resultados são evidência parcial. Não substituem a futura suíte completa.

Transparência de execução:

- no começo da Task 3, alguns gates foram rodados diretamente com pnpm 11.16.0
  e houve uma reconciliação local usando
  `--dangerously-allow-all-builds`;
- nenhum tracked file ou lockfile mudou por isso;
- todos os gates finais devem ser repetidos exclusivamente com
  `corepack pnpm@10.33.2`;
- uma revisão intermediária retornou NO-GO com 1 Critical, 2 Important e
  1 Minor, que motivaram a arquitetura atômica e os hardenings;
- durante a preparação de um manifesto broad, dois arquivos não rastreados
  (`better-ahead-r6-final-broad-selected.txt` e
  `better-ahead-r6-final-broad-shards.txt`) foram criados acidentalmente no
  Git manager e removidos imediatamente;
- nenhum arquivo tracked do Git manager mudou.

---

## 10. Estado exato do STOP atual

### 10.1 Arquivos dirty congelados no Mac

| Path | SHA-256 reportado |
| --- | --- |
| `design/brand/better-ahead-brand-assets.json` | `5da5284c219f4b556110944c837c2dcbf0f406aa6327aec821cb72d6bf5cb11b` |
| `scripts/brand/better-ahead-brand-contract.mjs` | `c9438906d4073813e15faec31332174e557888e0460705ddc6ff7bd89a7a99f0` |
| `scripts/brand/better-ahead-brand-contract.test.mjs` | `61facfae43bc5be7b45c2c5d406ccc20f88ba75ee13d3ec97b1d4232ecd0bcf1` |
| `scripts/brand/capture-better-ahead-environment.mjs` | `7bc9239e37ad8f219b92f59f5476cd6e58276ca2b095b81c27716edbed8d0435` |
| `scripts/brand/render-better-ahead-brand-assets.mjs` | `9a5cb0ea098c787bcc80ef0bea30eb28636178211fac07ebfb6c0f29c282220b` |
| `scripts/brand/render-better-ahead-brand-review.mjs` | `e3bac5f60c9892ef936cf87585ce74820f8fa24ac6879e5e17cc2211baf05e42` |
| `scripts/brand/run-better-ahead-brand-renderer.sh` | `686b89883bd21df8c95c7eb49244b93e81cea8d6094ddf689236ea10c9092dc0` |

Estado agregado:

- SHA-256 do porcelain:
  `2d2881b85e533d247fd7b67cc9cec9a629ec66fa1b83e130d2771ac9eee416b4`;
- SHA-256 do `git diff --binary`:
  `52654f8b16bcd531902cbb285a26fc0d026739464bd04e7dc269e72fca8bf411`;
- staging vazio;
- blob congelado do teste legado:
  `4c6619113829b83494292164696ee9abbd315eaf`.

### 10.2 Log RED congelado

- path:
  `/tmp/better-ahead-native-v3-oracle-red-attempt2.log`;
- SHA-256:
  `fb79890356f3c9541615736ab185ef61a58e7882f0f76dffe94095b8e289b58d`;
- 24 roots top-level;
- 19 descendants indentados;
- 43 registros TAP;
- 10 pass;
- 33 fail;
- 0 skipped;
- sete roots exatos OA-16/OA-34;
- 17 roots OA-V3, sendo 2 pass e 15 fail.

Esse arquivo não deve ser recriado ou rerodado. O handoff atual exige o mesmo
arquivo e hash como roster hierárquico imutável.

### 10.3 Defeito documental já corrigido

A autoridade anterior usava:

`^\[OA-(16|34|35|V3)-`

Isso não selecionava os nomes exatos `[OA-16]` e `[OA-34]`. O parser também
tratava o TAP como plano e perdia 19 filhos indentados. Com os 25 OA-35, a
contagem observada seria falsamente 42, e não 68.

O commit `13fd60a…` corrige:

- seleção dos sete roots exatos;
- seleção OA-V3/OA-35;
- parsing de header/result por indentação real;
- associação ao YAML diagnóstico direto correto;
- distinção de falha direta `ERR_ASSERTION` e falha por descendente
  `ERR_TEST_FAILURE`/`subtestsFailed`;
- preservação de nome, ordem, ancestralidade, erro, código, failureType,
  exception name e operator durante RED.

Validação documental registrada:

- 53 blocos bash com sintaxe aprovada;
- checker compilado no Node 24.14;
- OA RED sintético: 68 registros, 10 pass/58 fail;
- OA GREEN sintético: 68/68;
- migration RED/GREEN: 86 top-level;
- mutações negativas rejeitadas;
- revisões independentes: GO, 0 Critical/Important/Minor.

### 10.4 Próxima ação exata

A sessão local deve importar `13fd60a…` preservando bytes e executar apenas o
handoff “Preservation and documentation-import handoff for the TAP-tree
correction”. Se ele passar, deve continuar por “Required migration order and
gates”.

Antes desse handoff:

- não rodar pnpm;
- não editar;
- não rodar teste;
- não rodar Docker;
- não capturar environment;
- não renderizar;
- não resolver conflitos por conta própria.

---

## 11. Trabalho restante do Workstream 1 — Tasks 3 a 10

### 11.1 Task 3 — concluir pipeline atômico

**Status: BLOQUEADO no handoff documental, mas com correção publicada.**

Sequência:

1. importar a autoridade `13fd60a…` na worktree do Mac;
2. preservar os sete arquivos dirty e o staging vazio;
3. alterar primeiro somente o teste;
4. congelar os ledgers 83/20/4 e 10/21/2;
5. migrar os 83 testes para nove owners atuais;
6. remover os 20 blocos exclusivos da arquitetura plana;
7. manter as duas folhas KEEP;
8. adicionar 25 casos OA-35 exatos, opcodes 08–20;
9. rodar RED corrigido:
   - árvore OA: 68 registros, 10 pass/58 fail;
   - subset de migração: 86 top-level, conforme checker;
10. implementar a seam `nativeHelperV3TestOracle` e o hardening de produção,
    com inventário fechado de 32 IDs `open` e 21 IDs `probe`, sem controles
    públicos ou ingressos por CLI/env;
11. rodar GREEN:
    - OA 68/68;
    - migração 86/86;
    - suíte completa com zero fail/skip/todo;
12. obter duas revisões independentes sem Critical/Important;
13. commit exatamente dos sete paths:
    `fix(brand): harden Better Ahead atomic asset transaction`;
14. capturar environment canônico Docker Desktop >= 4.80:
    - contexto `desktop-linux`;
    - `linux/amd64`;
    - Corepack/pnpm 10.33.2;
    - Docker CLI/Desktop/engine/context/Buildx/Offload;
15. commit de `environment.json`:
    `build(brand): pin Better Ahead render environment`.

### 11.2 Task 4 — render único e aprovação visual

**Status: NÃO INICIADA.**

Gates:

1. snapshot dos 24 assets preservados;
2. provar Docker Desktop canônico e Offload desativado;
3. executar exatamente **um** build de imagem e **um** container visual;
4. iniciar journal antes do trabalho visual;
5. publicar o bundle inteiro por rename exclusivo, sem alias/symlink `current`;
6. em falha, seguir somente a máquina de estados; não rerenderizar;
7. provar que os bytes preservados não mudaram;
8. registrar o candidate manifest;
9. copiar três review PNGs sem re-encoding;
10. commit do candidato;
11. inspeção humana:
    - grafia;
    - símbolo;
    - clearspace;
    - equilíbrio;
    - contraste;
    - tamanhos pequenos;
    - clipping do splash;
    - ausência de texto BodyFlow;
12. aprovação visual explícita do candidato Better Ahead;
13. commit:
    `docs(brand): approve Better Ahead asset family`.

Não confundir:

- a aprovação BodyFlow 1.0.0 já existe;
- a aprovação dos mockups/direção Better Ahead já existe;
- a aprovação dos **bytes renderizados Better Ahead** ainda não existe.

### 11.3 Task 5 — interfaces semânticas de assets

**Status: NÃO INICIADA.**

- substituir seis interfaces de catálogo acopladas a BodyFlow;
- integrar `BrandAsset`/`BrandLogoPresentation`;
- wordmark, logo, splash e fallback textual;
- acessibilidade;
- manter AppIcon byte-idêntico;
- rodar gates Node/nativos;
- provar que renderer legado não foi invocado;
- commit restrito aos paths autorizados.

### 11.4 Task 6 — copy Better Ahead e Flow

**Status: NÃO INICIADA.**

- trocar produto e agente em todas as superfícies iOS públicas;
- aplicar Better Ahead/Flow, slogans, descriptor e role line;
- criar/ajustar About;
- mapear Focus/Impulse/Zen como estilos do Flow;
- impedir raw name/description do servidor para os três códigos conhecidos;
- preservar termos internos sem vazamento público;
- testar fallback e acessibilidade.

### 11.5 Task 7 — localização da fundação

**Status: NÃO INICIADA.**

- Auth;
- onboarding;
- navegação;
- estados compartilhados;
- catálogo pt-BR/en;
- uma extração Xcode controlada;
- inventário exato de producers públicos;
- testes de fundação nos dois idiomas.

### 11.6 Task 8 — localização completa do cliente autenticado

**Status: NÃO INICIADA.**

Cobertura:

- Today;
- Register;
- Plan;
- Progress;
- History;
- Routine;
- Library;
- Flow;
- Profile.

Também:

- datas, números, unidades, pluralização e formatos;
- smoke nos dois idiomas;
- dark/light;
- Dynamic Type;
- Reduce Motion;
- screenshots/hierarquias;
- zero producer público sem classificação.

### 11.7 Task 9 — gate de conteúdo público e recursos compilados

**Status: NÃO INICIADA.**

- allowlist estreita por path/reason/owner;
- scan de fonte;
- scan de Info.plist Debug/Release;
- scan de String Catalogs e recursos;
- inspeção de `Assets.car`;
- inspeção de xcresult;
- proibir BodyFlow/CoreHealth/MPP-como-marca/nomes antigos em UI;
- registrar notification copy local como N/A na base atual;
- provar nomes públicos corretos sem renomear IDs internos.

### 11.8 Task 10 — gate final do Workstream 1

**Status: NÃO INICIADA.**

- candidato limpo;
- todos os gates Node;
- todos os testes nativos e UI;
- Debug e Release;
- scans de recursos compilados;
- auditoria visual;
- hashes dos 24 assets preservados;
- comparação das três worktrees;
- staging correto;
- documentação de warnings herdados;
- commit final de evidências.

Conclusão legítima da Task 10:

> Rebrand e localização do cliente iOS concluídos.

Conclusões que a Task 10 **não** autoriza:

- backend rebrand concluído;
- app integrado;
- TestFlight;
- App Store;
- produção;
- cobrança;
- domínio ou registro de marca.

---

## 12. Workstream 2 — backend e Flow públicos

**Status geral: PENDENTE.**

Esse workstream é obrigatório antes de uma beta integrada sempre que o build
alcançar respostas geradas pelo servidor.

### 12.1 Superfícies a auditar e alterar

- respostas públicas do agente;
- system prompts/configuração que mencionem nome de produto/coach;
- mensagens proativas;
- jobs e templates agendados;
- payload e texto de push remoto;
- e-mails;
- suporte;
- respostas de erro públicas;
- conteúdos CMS atuais e programados;
- TTS, caso pronuncie nome da marca/agente;
- web/admin onde o paciente veja conteúdo;
- WhatsApp e app, para que não se contradigam.

### 12.2 Regras

- Better Ahead é o único nome público do produto.
- Flow é o único nome público do agente.
- “MPP” pode permanecer como conceito metodológico verdadeiro, mas nunca como
  marca de consumo acidental.
- CoreHealth, BodyFlow, “Dr. Roberto” ou nomes históricos só podem aparecer
  onde houver motivo legal/operacional explicitamente allowlisted.
- contratos de API, enums, banco e keys não devem ser renomeados só por estética.
- a mudança de copy não pode alterar cálculo nutricional, progressão,
  segurança ou decisão clínica.

### 12.3 Gates

- inventário completo de producers públicos;
- testes pt-BR/en;
- scan de marca proibida;
- mensagens server-driven em staging;
- scheduled/current CMS audit;
- push/email/support render tests;
- WhatsApp/app equivalentes para os mesmos estados;
- revisão de segurança para evitar exposição de prompt, PII ou secrets;
- revisão humana de tom.

### 12.4 Tom do Flow

O Flow deve:

- ser claro, acolhedor e objetivo;
- incentivar consistência sem culpa;
- explicar a fonte dos números;
- pedir confirmação diante de ambiguidade;
- facilitar correção;
- reconhecer limites;
- não diagnosticar;
- não prometer cura, resultado garantido ou substituir profissional;
- usar Focus, Impulse e Zen como estilos, não como agentes diferentes.

---

## 13. Integração iOS real — gate obrigatório pré-beta

### 13.1 Transporte autenticado

Implementar um cliente HTTP de produção/beta que:

- aceite uma única origem HTTPS BFF injetada por configuração;
- não possua fallback hard-coded para produção;
- não derive host de conteúdo retornado pelo servidor;
- use `Authorization: Bearer` somente na origem aprovada;
- impeça token em redirects/cross-origin;
- aplique `no-store` a dados do paciente;
- suporte request IDs e idempotency keys;
- imponha timeout, limites de corpo e cancelamento;
- mapeie envelopes/erros da API;
- tenha retry somente onde semanticamente seguro;
- não registre token, PII, corpo sensível ou URL assinada.

Testes mínimos:

- same-origin;
- redirect bloqueado;
- redirect de cover/mídia conforme contrato;
- cross-origin sem Authorization;
- timeout;
- resposta grande;
- erro de decode;
- 401/403/409/422/429/5xx;
- replay idempotente;
- request cancellation.

### 13.2 Configuração de staging

- publicar BFF/Mobile API em uma origem de staging;
- injetar a base URL por xcconfig/configuração segura;
- nenhuma URL de produção como fallback;
- health/smoke da API;
- migrations equivalentes em staging;
- dados de teste controlados;
- CORS/headers/caching observados;
- rollback documentado.

### 13.3 Autenticação e sessão

Implementar:

- login/registro/recuperação conforme produto aprovado;
- Supabase Auth real;
- exigência de e-mail confirmado quando aplicável;
- armazenamento no Keychain;
- renovação/rotação de bearer;
- fonte única da sessão atual;
- troca de usuário;
- logout completo;
- cancelamento de trabalho patient-scoped ao sair/trocar;
- supressão de respostas atrasadas;
- limpeza de cache/estado sensível;
- tratamento de conta blocked/deleted/admin;
- exclusão de conta e exportação de dados, conforme jurídico.

Testes:

- current token;
- token rotacionado;
- expiração;
- logout durante request;
- resposta tardia depois de logout;
- troca de usuário;
- app relaunch;
- Keychain indisponível/corrompido;
- offline/reconexão.

### 13.4 Adapters de domínio

Substituir os serviços demo/unavailable por implementações reais para:

- Today;
- History;
- Plan;
- Progress;
- Meal detection/upload;
- Registration proposal/confirm/edit/cancel;
- Hydration;
- Weight;
- Routine;
- Supplements;
- Medications;
- Content/Library;
- Coach persona/Flow styles;
- Profile/onboarding;
- Entitlements;
- Media.

Cada adapter precisa:

- respeitar os DTOs V1;
- normalizar datas/timezone;
- usar idempotência;
- separar loading/empty/error/offline;
- não transformar erro em sucesso sintético;
- telemetria sem PII;
- testes unitários e de contrato;
- smoke contra staging.

### 13.5 Auditoria live de conteúdo

Antes de qualquer TestFlight:

- executar uma auditoria read-only, separadamente autorizada, sobre
  `public.content_versions`;
- não imprimir Markdown corporal nem PII;
- usar apenas allowlist técnica;
- obter zero candidatos incompatíveis em:
  - `candidate_class=current`;
  - `candidate_class=scheduled`;
- não editar versões históricas;
- se houver incompatibilidade, publicar nova versão pelo fluxo editorial e
  rerodar a auditoria.

---

## 14. Push, notificações e deep links

### 14.1 O que existe

- schema de devices;
- preferências e quiet hours;
- regras de reminders;
- queue/delivery records;
- scheduler que decide com estado oficial;
- APIs de device e preferências.

### 14.2 O que falta

- Apple Push Notification service;
- chave/certificado APNs com escopo correto;
- environment sandbox/production;
- provider de envio;
- token registration real no iOS;
- rotação/desativação do token;
- permission UX;
- handling foreground/background/tap;
- deep links;
- conteúdo localizado Better Ahead/Flow;
- limites, opt-out e quiet hours ponta a ponta;
- retry/dead-letter/observabilidade;
- redaction de logs;
- testes em dispositivo real;
- política de notificações transacionais x marketing.

### 14.3 Decisão de escopo

Se push não for necessário na primeira beta do cliente, ele pode ficar
desabilitado e ser declarado fora da beta. Para App Store, qualquer capability,
entitlement ou copy presente deve corresponder ao comportamento real.

---

## 15. Assinaturas, preços e economia unitária

### 15.1 Proposta comercial de 16/07/2026

Valores usados no modelo, ainda não aprovados como produtos StoreKit:

| País | Mensal | Trimestral | Semestral | Anual |
| --- | ---: | ---: | ---: | ---: |
| Brasil | R$ 89,90 | R$ 249,90 | R$ 449,90 | R$ 799,90 |
| Estados Unidos | US$ 29,99 | US$ 84,99 | US$ 159,99 | US$ 239,99 |

Premissas/riscos do relatório:

- comissão de loja;
- reembolsos;
- RevenueCat conforme receita rastreada;
- impostos;
- suporte/operação;
- CAC;
- custo fixo de infraestrutura;
- custo variável de IA.

O custo LLM observado no relatório era aproximadamente
**US$ 22,89 por usuário/mês**, muito alto para escalar com segurança. O alvo
recomendado era **até US$ 4 por usuário/mês** de tecnologia variável antes de
acelerar aquisição.

### 15.2 Conflitos a resolver

- catálogo antigo: R$ 197 mensal, R$ 1.164 anual e trial de sete dias;
- proposta nova: tabela acima;
- conversa: “3 dias somente”, provavelmente trial, mas sem o enunciado original
  preservado;
- limites mensais foram discutidos, porém a matriz exata de limites não está
  recuperável dos rótulos A/B deste histórico.

### 15.3 Decisões obrigatórias antes de implementar cobrança

- países da versão 1;
- planos disponíveis;
- preço por storefront/tier Apple;
- trial e elegibilidade;
- “3 dias” confirmado ou corrigido;
- limites mensais por plano;
- comportamento ao atingir limite;
- grace period;
- restore purchases;
- family sharing;
- upgrade/downgrade;
- cancelamento/refund;
- entitlement free/paid;
- product IDs;
- offerings/paywalls RevenueCat;
- vínculo Stripe legado x StoreKit;
- política para usuários existentes;
- teto de custo de IA e fallback de modelos.

### 15.4 Gate comercial

Antes da App Store:

- medir custo por feature/modelo;
- routing por complexidade;
- cache/deduplicação;
- hard caps e abuse guard;
- coortes de uso real;
- margem por plano depois de loja, imposto, reembolso, suporte, RevenueCat e IA;
- dashboard de unit economics;
- alerta de custo;
- aprovação escrita da grade de produtos.

---

## 16. Jurídico, privacidade, saúde e identidade empresarial

### 16.1 Entidade

O repositório/documentação trata **CoreHealth** como cliente/owner do produto.
Também foi fornecido um cartão CNPJ de **PIPER AUTOMAÇÕES E INTEGRAÇÕES LTDA**,
nome fantasia **PIPER HUB**, entidade ativa e com atividades de software/TI.

Por proteção de dados, este dossiê não replica CNPJ, endereço, telefone ou
e-mail do documento.

Decisão pendente:

- quem será o seller no App Store;
- quem contrata o usuário;
- quem é controlador e/ou operador de dados;
- quem será titular da marca e domínio;
- quem responde por suporte, privacidade e incidentes;
- qual entidade aparece em recibos, termos e políticas.

### 16.2 Documentos e fluxos necessários

- Política de Privacidade;
- Termos de Uso;
- termos de assinatura/auto-renovação;
- disclaimer de saúde e IA;
- disclaimer específico de lembrete de medicamentos;
- consentimento para dados corporais, saúde, fotos e mídia;
- base legal e retenção;
- subprocessadores;
- exportação de dados;
- exclusão de conta dentro do app;
- revogação de consentimento;
- contato de privacidade e suporte;
- procedimento de incidente;
- política para menores e idade mínima;
- declaração de que o app não oferece diagnóstico e não substitui profissional;
- termos localizados pt-BR/en.

### 16.3 App Privacy e compliance

- inventário de dados coletados;
- vínculo à identidade;
- tracking;
- dados de saúde/fitness;
- fotos/áudio;
- diagnósticos/telemetria;
- IDs de dispositivo;
- compras;
- retenção e finalidade;
- SDK privacy manifests;
- required-reason APIs;
- privacy nutrition labels;
- permissões com purpose strings coerentes;
- LGPD e requisitos dos países efetivamente lançados.

### 16.4 Marca

- busca formal e parecer;
- decisão de protocolo INPI;
- classes adequadas;
- titularidade;
- domínio;
- licença/cessão dos assets;
- declaração de uso de fontes e licenças;
- documentação do símbolo reaproveitado.

---

## 17. UI/UX que ainda precisa fechar

### 17.1 O que já tem boa base

- arquitetura em cinco abas;
- home “Hoje”;
- captura/registro;
- plano;
- progresso;
- histórico;
- rotina;
- biblioteca;
- coach/mascote;
- perfil;
- múltiplas configurações de acessibilidade;
- snapshots e hierarquias.

### 17.2 Revisão final integrada

Rodar o app com dados reais e validar:

- primeira abertura;
- login/registro/recuperação;
- onboarding parcial, completo e retomado;
- Today vazio, loading, loaded, erro, offline e stale;
- refeição por texto/foto e confirmação;
- treino e correção;
- água/peso;
- plano sem plano e com plano;
- progresso sem dados e com histórico;
- suplementos/medicamentos e disclaimer;
- conteúdo current/scheduled/saved;
- Flow Focus/Impulse/Zen;
- perfil e logout;
- conta bloqueada/deletada;
- assinatura free/paid/expired/grace;
- push permission e deep link, se incluídos;
- exclusão de conta.

### 17.3 Critérios visuais

- consistência Better Ahead/Flow;
- wordmark sem truncar;
- splash sem clipping;
- símbolo legível;
- safe areas;
- teclado;
- rotação suportada;
- iPhones compactos e grandes;
- Light/Dark;
- contraste;
- Dynamic Type até tamanhos de acessibilidade;
- VoiceOver;
- Reduce Motion;
- Differentiate Without Color;
- botões e targets;
- feedback de progresso sem culpa;
- nenhum número sem fonte/explicação.

### 17.4 Idiomas

- zero string pública hard-coded fora do catálogo/allowlist;
- pt-BR natural, não tradução literal;
- inglês natural;
- plural e gênero;
- datas/horas;
- unidade métrica/imperial conforme decisão;
- moeda;
- timezone e calendário;
- conteúdo remoto;
- push;
- e-mail;
- erro de backend;
- App Store metadata.

---

## 18. Qualidade, segurança e operação

### 18.1 Testes mínimos para beta

- unitários iOS;
- contract tests Mobile API;
- integration tests contra staging;
- UI tests pt-BR/en;
- smoke em dispositivo real;
- offline/retry/cancelamento;
- sessão/rotação/logout;
- mídia privada;
- idempotência;
- timezone/DST;
- acessibilidade;
- performance/memória;
- launch/crash;
- upgrade de versão e migração de estado local;
- segurança de logs;
- deep links/push, se incluídos;
- restore purchases, se incluído.

### 18.2 Testes mínimos para produção

Além da beta:

- release archive assinado;
- TestFlight build exato;
- production-like staging;
- migração/rollback ensaiados;
- canário de produção;
- smoke pós-deploy;
- dependências/audit;
- Supabase advisors e RLS;
- API abuse/rate limits;
- webhook replay/signature;
- APNs sandbox/production;
- StoreKit sandbox;
- account deletion;
- backup/PITR/restore;
- monitoramento e alertas;
- suporte e playbook de incidentes.

### 18.3 Dívidas que precisam de revalidação

- audit de dependências de 02/07 estava vermelho;
- lint global tinha dívida preexistente;
- headers efetivos de produção não foram comprovados naquela auditoria;
- GitHub branch protection/secrets/CODEOWNERS não foram integralmente validados;
- ações por tag e health endpoints mutáveis foram apontados como riscos;
- fetches externos precisavam de timeout/limite;
- produção pode ter drift em relação às migrations;
- warnings Swift herdados devem ser triados antes do release final.

### 18.4 Observabilidade

Definir e testar:

- crash reporting;
- métricas de API;
- latência e erro por endpoint;
- logs estruturados sem PII;
- correlation/request ID;
- saúde do scheduler;
- delivery de push;
- falhas de entitlement;
- custo LLM por usuário/feature;
- funil onboarding → ativação → retenção → assinatura;
- alertas e owners;
- runbooks;
- rollback.

---

## 19. Plano sequencial até 100%

### Fase 0 — preservar e retomar a Task 3

- [ ] Confirmar no Mac os três estados Git exatamente como registrados.
- [ ] Confirmar o log congelado e SHA.
- [ ] Importar `13fd60a…` pelo handoff autoritativo.
- [ ] Não recriar o log.
- [ ] Não executar renderer legado.

**Saída:** worktree pronta para o RED corrigido.

### Fase 1 — concluir o Workstream 1

- [ ] Task 3 GREEN completo e duas revisões.
- [ ] Fingerprint Docker canônico.
- [ ] Task 4, render único.
- [ ] Aprovação visual do candidato Better Ahead.
- [ ] Tasks 5–6: assets semânticos e copy.
- [ ] Tasks 7–8: localização completa.
- [ ] Task 9: scan público/compilado.
- [ ] Task 10: gate final.

**Saída:** cliente iOS rebrandado/localizado, ainda sem declarar integração.

### Fase 2 — definir a beta

- [ ] Confirmar companion app x chat nativo.
- [ ] Confirmar se push entra na beta.
- [ ] Confirmar se paywall/assinatura entra na beta.
- [ ] Confirmar canal: TestFlight interno/externo ou outro permitido.
- [ ] Confirmar usuários e dados de teste.
- [ ] Confirmar entity/account Apple.

**Saída:** escopo de beta congelado.

### Fase 3 — backend de staging e Workstream 2

- [ ] Inventário público do backend.
- [ ] Rebrand Better Ahead/Flow.
- [ ] Publicar Mobile API/BFF staging.
- [ ] Aplicar/verificar migrations staging.
- [ ] Configurar apenas secrets de staging necessários.
- [ ] Auditar content_versions current/scheduled.
- [ ] Smoke de APIs e mensagens.

**Saída:** backend de staging coerente e alcançável.

### Fase 4 — integração iOS real

- [ ] HTTP transport.
- [ ] configuração de origem.
- [ ] auth/session bridge.
- [ ] adapters de domínio.
- [ ] mídia.
- [ ] erro/offline/cache.
- [ ] telemetria.
- [ ] push, se escopo.
- [ ] entitlements, se escopo.

**Saída:** app funcional end-to-end em staging.

### Fase 5 — QA integrado e segurança

- [ ] suites automatizadas.
- [ ] device QA.
- [ ] pt-BR/en.
- [ ] acessibilidade.
- [ ] segurança de sessão/API.
- [ ] performance/memória.
- [ ] pentest/abuse review proporcional.
- [ ] sem old brand.
- [ ] relatório de release candidate.

**Saída:** candidato de beta.

### Fase 6 — distribuição e UAT do cliente

- [ ] autorização explícita de upload.
- [ ] signing/provisioning.
- [ ] archive.
- [ ] TestFlight/App Store Connect mínimo.
- [ ] grupo/testers.
- [ ] instruções e roteiro UAT.
- [ ] coleta estruturada de bugs.
- [ ] triagem e correções.
- [ ] aceite escrito do cliente.

**Saída:** beta aprovada.

### Fase 7 — produção

- [ ] backup/PITR/restore.
- [ ] auditoria read-only de produção.
- [ ] migrations controladas.
- [ ] deploy do BFF/backend.
- [ ] APNs/RevenueCat/StoreKit produção, se aplicável.
- [ ] canário.
- [ ] smoke.
- [ ] rollback pronto.

**Saída:** backend de produção pronto para o binário.

### Fase 8 — App Store

- [ ] nome disponível no App Store Connect.
- [ ] domínio e URLs.
- [ ] seller/legal.
- [ ] privacy/terms/support.
- [ ] metadata pt-BR/en.
- [ ] subtitle/keywords/category.
- [ ] screenshots.
- [ ] preview, se houver.
- [ ] age rating.
- [ ] App Privacy.
- [ ] export compliance.
- [ ] review notes e conta demo.
- [ ] archive final e upload autorizado.
- [ ] submissão.
- [ ] responder review.
- [ ] phased release/manual release decidido.
- [ ] monitorar após publicação.

**Saída:** versão publicada e operada.

---

## 20. Definições objetivas de pronto

### 20.1 “Pronto para o cliente testar”

Só declarar quando todos forem verdadeiros:

- [ ] Workstream 1 completo.
- [ ] Workstream 2 completo nas superfícies alcançáveis.
- [ ] Better Ahead/Flow sem vazamento público antigo.
- [ ] pt-BR/en completos.
- [ ] app usa staging real.
- [ ] login/sessão/logout reais.
- [ ] jornadas principais funcionam sem mocks.
- [ ] erros/offline recuperáveis.
- [ ] conteúdo current/scheduled auditado.
- [ ] QA automatizado e manual aprovado.
- [ ] privacidade/suporte mínimos do canal.
- [ ] build assinado.
- [ ] upload/distribuição autorizados.
- [ ] roteiro UAT entregue.

### 20.2 “Pronto para submeter à Apple”

- [ ] beta aceita pelo cliente.
- [ ] blockers/criticals zerados.
- [ ] produção segura e monitorada.
- [ ] StoreKit/RevenueCat final, se houver assinatura.
- [ ] legal e privacy final.
- [ ] domínio e support URLs ativos.
- [ ] seller e contas definidos.
- [ ] metadata/screenshots finais.
- [ ] App Privacy/age rating/export compliance corretos.
- [ ] account deletion disponível.
- [ ] archive Release exato passou gates.
- [ ] TestFlight final aprovado.
- [ ] rollback e suporte prontos.
- [ ] submissão explicitamente autorizada.

### 20.3 “100% finalizado”

Para fins deste projeto, significa:

- código e infraestrutura do escopo V1 entregues;
- cliente aprovou;
- release aprovado/publicado pela Apple;
- produção saudável;
- monitoramento e suporte ativos;
- documentação e handoff entregues;
- nenhum gate obrigatório pendente.

Não significa que o produto nunca mais terá backlog, manutenção ou evolução.

---

## 21. Decisões pendentes — matriz para o cliente e para a operação

| Decisão | Opções práticas | Recomendação atual | Impacto se atrasar |
| --- | --- | --- | --- |
| Escopo V1 | Companion app; companion + chat; plataforma completa | Companion integrado primeiro | Chat nativo acrescenta contrato, UI, histórico, streaming, segurança e QA. |
| Papel do Flow | Guia contextual; chat nativo; ambos | Guia contextual na V1, salvo exigência explícita | Evita ampliar prazo antes da beta. |
| Push na beta | Fora; sandbox; completo | Sandbox somente se essencial à UAT | APNs real exige conta, entitlement, provider e device QA. |
| Cobrança na beta | Fora; sandbox StoreKit; completa | Sandbox somente se preço/paywall forem objeto da UAT | Produtos e trial ainda não estão aprovados. |
| Canal de beta | TestFlight interno; externo; Ad Hoc | TestFlight interno, se as contas permitirem | Externo exige beta review e informações adicionais. |
| Trial | 3 dias; outro; sem trial | Confirmar por escrito “3 dias” | Afeta oferta, StoreKit, termos e unit economics. |
| Preços | Proposta de julho; catálogo legado; nova grade | Aprovar a proposta com validação de margem | Não criar product IDs antes da decisão. |
| Limites | Mensais por feature/modelo | Redefinir matriz completa | Impacta custo, UI, entitlement e mensagens. |
| Países | Brasil; Brasil+EUA; outros | Brasil primeiro ou Brasil+EUA somente com legal/localização completos | Altera preço, unidade, termos e storefront. |
| Usuários legados | Vincular WhatsApp; migrar; iniciar contas novas | Desenhar vínculo seguro e reversível | Identidades legadas podem ter `auth_user_id = NULL`. |
| Seller | CoreHealth; Piper; outra entidade | Decisão jurídica/comercial formal | Bloqueia Apple, termos, privacy e recebimentos. |
| Titular da marca/domínio | CoreHealth; Piper; outra | Mesmo owner contratual, salvo parecer | Evita disputa de ativos. |
| Domínio | Nome principal e defensivos | Comprar só após clearance mínimo | Bloqueia support/privacy/deep links. |
| Bundle ID | Preservar `com.bodyflow.app`; novo ID | Preservar, se App ID/account ownership estiver correto | Novo ID quebra continuidade e adiciona migração. |
| Produção | Promover staging; refazer workpack | Workpack controlado com auditoria fresh | O estado live não está comprovado. |
| Android | Fora; planejar depois | Fora da V1 atual | Não há plano Android aprovado. |

---

## 22. Riscos e dependências

| Risco | Probabilidade | Impacto | Mitigação |
| --- | --- | --- | --- |
| Novo STOP do renderer | Média | Médio/alto no prazo do rebrand | Seguir literalmente a autoridade atual; não improvisar hardening. |
| Docker Desktop diferente | Média | Bloqueia primeiro render | Verificar versão, plugins, context, engine, Buildx e Offload antes da tentativa. |
| Log congelado ausente no Mac | Baixa/média | Bloqueia handoff atual | Não recriar; exigir nova reconciliação documental. |
| Integração iOS maior que estimada | Alta | Alto | Implementar por domínio, começando auth/transport/Today; medir a cada adapter. |
| Drift entre staging e produção | Alta | Crítico | Auditoria read-only, migrations fresh, backup/PITR, canário e rollback. |
| Usuário WhatsApp sem identidade Auth | Média | Alto | Especificar vínculo/migração e impedir takeover/duplicidade. |
| Vazamento de marca antiga pelo backend | Média | Alto para UAT/brand | Workstream 2, scans e testes E2E antes da beta. |
| Custo de IA inviável | Alta no modelo observado | Crítico comercial | Routing, caps, cache, cohorts e grade de preços aprovada. |
| Marca Better Ahead indisponível | Não conhecida | Alto | Clearance formal antes de investir em lançamento público. |
| Seller/contas Apple indefinidos | Média | Bloqueia distribuição | Resolver entidade, contratos e acessos no início da fase beta. |
| Jurídico atrasado | Alta | Bloqueia App Store | Iniciar Privacy/Terms/disclaimers em paralelo à integração. |
| APNs/RevenueCat ampliam V1 | Alta se incluídos | 1–3 semanas ou mais | Tornar opcionais na primeira beta, com decisão explícita. |
| Dependências vulneráveis atuais | Não conhecida | Alto | Rerodar audit no SHA release e corrigir blockers. |
| Lint global preexistente | Alta | Médio | Definir baseline/changed-files gate e plano separado de dívida. |
| Testes somente em simulador | Média | Alto | Gate em dispositivos reais e redes reais antes da UAT. |
| Aprovação lenta do cliente/Apple | Não controlável | Alto no calendário | Checklist, builds pequenos, roteiro UAT e folga de agenda. |

---

## 23. O que explicitamente ainda não foi feito

Para impedir interpretações erradas:

- não foi concluída a Task 3;
- não foi executado nenhum render real Better Ahead;
- não existe bundle Better Ahead aprovado;
- não houve aprovação visual dos bytes Better Ahead;
- Tasks 4–10 não foram concluídas;
- a localização completa pt-BR/en não foi concluída;
- o scan final de marca pública não foi concluído;
- o Workstream 2 de backend não foi concluído;
- o Release iOS não foi ligado à Mobile API;
- a autenticação iOS real não foi implementada;
- não há sessão/token bridge;
- a URL BFF de staging não foi fechada;
- não há prova de deploy da Mobile API nova em produção;
- a auditoria live de `content_versions` não foi executada;
- APNs não foi configurado;
- push real não foi enviado;
- StoreKit não foi configurado;
- RevenueCat real não foi configurado;
- produtos/preços/trial não foram aprovados;
- chat nativo do Flow não foi especificado nem implementado;
- migração/vínculo de usuários legados WhatsApp não foi fechada;
- produção não foi revalidada;
- marca Better Ahead não recebeu clearance jurídico formal;
- domínio não foi comprado;
- seller Apple não foi decidido;
- política de privacidade e termos finais não foram comprovados;
- App Store Connect não foi configurado neste plano;
- não houve archive assinado;
- não houve TestFlight;
- não houve submissão à Apple;
- não há trabalho Android aprovado;
- a autorização dos PRs #16/#17 não comprova que tenham sido efetivamente
  mergeados;
- nenhum push/PR/merge/deploy desta fase deve ser inferido dos commits locais.

---

## 24. Invariantes e regras não negociáveis

### 24.1 Git e evidência

- não descartar, sobrescrever, stagear ou “limpar” os nove diagnósticos;
- não usar `git reset --hard`, `git clean` ou stash como cleanup;
- não confundir Git manager com repositório diagnóstico;
- preservar os sete arquivos dirty da Task 3 durante o handoff;
- staging deve continuar vazio até o step de commit autorizado;
- não criar commit com paths fora da allowlist;
- não fazer push/PR/merge/deploy sem autorização do plano/usuário.

### 24.2 Assets

- símbolo e AppIcon aprovados são byte-invariantes;
- wordmark/lockup/splash Better Ahead são novos, não comparados aos hashes
  históricos de texto BodyFlow;
- nunca atualizar hash esperado só para fazer teste passar;
- nunca executar `brand:render`/`brand:review` legado em write mode;
- um único render Better Ahead autorizado;
- sem rerender automático em recovery;
- bundle inteiro, imutável e version-addressed;
- sem symlink/mutable alias `current`;
- manifest root é registro revisado, não receipt transacional.

### 24.3 Toolchain

- Corepack invocando exatamente pnpm 10.33.2;
- não usar pnpm global;
- não usar `corepack use/up/install -g/enable`;
- não usar `--dangerously-allow-all-builds`;
- Docker Desktop >= 4.80;
- contexto `desktop-linux`;
- plataforma `linux/amd64`;
- plugins Docker devem resolver no bundle do Docker Desktop;
- Offload desativado de forma fail-closed;
- Buildx `--quiet` com stdout em FD seguro;
- `--iidfile` proibido.

### 24.4 Segurança

- nunca imprimir secret/env value;
- nunca enviar `service_role` ao app;
- não usar origem derivada de payload;
- token não cruza origem;
- sem PII em logs;
- produção somente após backup/restore/gates/rollback;
- nenhum dado histórico deve ser reescrito para “corrigir” auditoria.

### 24.5 Produto

- Better Ahead/Flow são nomes públicos;
- IDs internos BodyFlow permanecem quando não vazam;
- não prometer diagnóstico/cura;
- WhatsApp e app devem concordar;
- números precisam de fonte;
- ambiguidade pede confirmação;
- progresso não vira culpa;
- escopo novo relevante exige decisão, não suposição.

---

## 25. Prompt exato para retomar na sessão local do Mac

Copiar integralmente para a sessão que opera o Xcode e a worktree
`/private/tmp/better-ahead-ios.GQgTa0/worktree`:

```text
A nova autoridade documental do gate TAP hierárquico foi publicada.

TAP_TREE_DOC_SHA=13fd60a709228566c2b0e639ba58a515ce0abea0
Parent remoto esperado: ad3fb05b903ed034364fc6190240caf1954c4a2b
Plan blob publicado: f2d622a7f7f378110fd2a0593336297fd97b65b9
Assunto: docs(brand): reconcile hierarchical TAP gate

Retome exatamente do STOP documental atual.

Antes de qualquer edição, pnpm, teste, Docker, capture ou render:

1. Faça fetch read-only da branch codex/better-ahead-rebranding-design.
2. Leia integralmente no SHA informado a seção:
   “Preservation and documentation-import handoff for the TAP-tree correction”.
3. Exporte TAP_TREE_DOC_SHA com o valor acima.
4. Execute exclusivamente esse handoff.
5. Não recrie nem rerode o log legado. O arquivo autenticado
   /tmp/better-ahead-native-v3-oracle-red-attempt2.log
   deve continuar existindo com o SHA exigido pelo plano.

Se o handoff concluir integralmente, continue automaticamente pela seção
“Required migration order and gates”:

- preserve os sete arquivos dirty e o staging vazio;
- modifique primeiro somente o teste autorizado;
- execute os gates RED corrigidos com o parser hierárquico;
- somente após RED aprovado prossiga para a implementação GREEN;
- continue pelos gates seguintes e pelo Task 4 conforme o plano;
- não execute renderer legado;
- pare apenas se um STOP explícito ou divergência real ocorrer.

Ao final, reporte commits, contagens TAP completas, revisões, hashes, estado das três worktrees e qualquer bloqueio. Não faça push, PR, merge ou deploy além do que estiver expressamente autorizado no plano.
```

---

## 26. Ledger de commits, blobs e hashes essenciais

### 26.1 Autoridade Better Ahead

| Item | Valor |
| --- | --- |
| Branch documental | `codex/better-ahead-rebranding-design` |
| SHA atual | `13fd60a709228566c2b0e639ba58a515ce0abea0` |
| Parent | `ad3fb05b903ed034364fc6190240caf1954c4a2b` |
| Plan blob atual | `f2d622a7f7f378110fd2a0593336297fd97b65b9` |
| Plan blob anterior | `ff3e5cf3f8db7b0e5b118e7c4c4cd0fbbf43cfa1` |
| Spec blob | `d5708657f7c1929931c4957cc08b6cd86bb091ff` |
| Checker TAP SHA-256 | `58db979fc2f1e3d4f755b2262ac04304c6b1c3eca8c65619e6237778cf39449a` |

### 26.2 Implementação

| Item | Valor |
| --- | --- |
| Base iOS aprovada | `11f5a7cec331d4fc683b6cee5cdf046d3e89623d` |
| Task 0 | `5317fab1af6d82bcd2886c07149244a2cb2c1765` |
| Task 1 | `caa644e85d3a421b4cdc2e1549690db19761bced` |
| Task 1 hardening | `844ebcc1f761a77fa80953ba9bc9604808f14dd2` |
| Task 2 docs | `f1bbe183081d73e1c6ed48eefbbfe97bd92fae9a` |
| Task 2 app | `701c272030ead0061e76e3ee69801d7dbf763917` |
| Task 2 bilingual test | `4f635ad2b5802239575ef2b6ec04b0aed50db740` |
| Task 3 parcial | `0a5001e90c9816cb2f9be6f2ff1be6bfa3b0fb38` |
| HEAD Mac pré-handoff | `ad9869c0d6b11222263ea40c7b72e329092aeef5` |
| Parent Mac | `8f4020b0ae27d27c0de1b97d1682f507cd0be57c` |

### 26.3 Estados físicos

| Item | SHA-256 |
| --- | --- |
| Mac implementation porcelain | `2d2881b85e533d247fd7b67cc9cec9a629ec66fa1b83e130d2771ac9eee416b4` |
| Mac implementation binary diff | `52654f8b16bcd531902cbb285a26fc0d026739464bd04e7dc269e72fca8bf411` |
| Diagnostic porcelain | `4fc733aeb4f41ce17e7ed094920c0d5ab70da26b879d49c594a84f050e58550c` |
| Frozen RED log | `fb79890356f3c9541615736ab185ef61a58e7882f0f76dffe94095b8e289b58d` |
| Source worktree porcelain pré-dossiê | `455000fe5f148dcad3034f03d57e2683deedb8ae5ec655b8a459639117f040e0` |
| Source tracked diff pré-dossiê | `7262d613d02df890c8e0c02922fa778afb90a6b7c27aa25a417bf0c717bdbefb` |

### 26.4 Proveniência histórica BodyFlow

| Item | Valor |
| --- | --- |
| SHA diagnóstico original | `03df7894e4cdb37db08351aafb6dd20ad4cb4103` |
| Gate nativo | `a384ef66543790d219c606bb963cd4cb6312d0ac` |
| Manifest combinado antes | `468ce80310ade419cc6ea52dfe0a8a37c96740d6c6a3104c95c165de52852a6d` |
| Manifest combinado depois | `d0a6a6889a8f2fee795c2bc1994cc9475f8a1ab8d39769f557dd15f7a5055c1b` |
| Fingerprint diagnóstico posterior | `f42572fbb61c48c150a58ea8c144455ecae7cf373f369820a9140f6b58dff45d` |

O fingerprint `f425…` e os hashes `468…`/`d0a…` vêm de etapas e métodos de
evidência diferentes; não devem ser comparados como se fossem o mesmo
manifesto.

### 26.5 Prefixos dos assets preservados

| Família | Prefixo(s) SHA-256 |
| --- | --- |
| Symbol SVG | `01343fcb` |
| Symbol PNG 44/88/132/512/1024 | `d1fd4fb6`, `6221f43b`, `89eee28f`, `d272fc80`, `c1b3211e` |
| Monochrome SVG | `6809439b` |
| Monochrome PNG 44/88/132 | `6677b8ae`, `8ef78c14`, `0c7ab083` |
| Negative SVG | `a8f1ff09` |
| Negative PNG 44/88/132 | `27954fd7`, `a69f6566`, `d99817a7` |
| AppIcon default/dark/tinted | `400f0b86`, `361e42e3`, `10c3e7af` |
| Wordmark/horizontal/launch BodyFlow históricos | `57503318`, `cb88d3af`, `06580ac9` |

Os valores completos permanecem no manifesto histórico aprovado. Prefixos
servem somente para orientação.

---

## 27. Índice de evidências e caminhos

### 27.1 Repositório atual

- `/root/agentempp/docs/superpowers/specs/2026-08-11-better-ahead-rebranding-design.md`
- `/root/agentempp/docs/superpowers/plans/2026-08-11-better-ahead-ios-rebrand.md`
- `/root/agentempp/docs/BRIEFING-PRODUTO-MARCA-COMUNICACAO-UX.md`
- `/root/agentempp/docs/PLATAFORMA-AGENTE-MPP.md`
- `/root/agentempp/docs/AGENTE-MPP-REFERENCIA-INTEGRACAO.md`
- `/root/agentempp/docs/ANALISE-CONTEXTO-ATUAL.md`
- `/root/agentempp/docs/CONTEXT.md`
- `/root/agentempp/docs/audits/2026-07-02-full-platform-audit.md`
- `/root/agentempp/docs/business/2026-07-16-relatorio-precificacao-economia-unitaria-app-nativo.md`

Vários desses documentos são atualmente não rastreados na worktree da VPS.
Eles são fontes locais; não presumir que estejam publicados no remoto.

### 27.2 Git object da base aprovada

Consultar em `11f5a7c…`:

- `apps/ios/BodyFlow/BodyFlow/App/AppDependencies.swift`;
- `apps/ios/BodyFlow/BodyFlow/Core/Auth/DemoAuthenticationService.swift`;
- `apps/ios/BodyFlow/BodyFlow/Core/Networking/APIClient.swift`;
- `docs/mobile/api-v1.md`;
- `docs/runbook/bodyflow-p0-a-security.md`;
- evidência de
  `docs/superpowers/evidence/2026-08-02-bodyflow-ios-library-mascot-gamification/README.md`;
- planos/specs iOS de 26/07, 29/07, 02/08, 09/08 e 10/08;
- plano de entitlements de 24/07;
- plano de push/routine de 20/07.

### 27.3 Relatórios temporários no Mac

Reportados:

- `/private/tmp/better-ahead-ios.GQgTa0/worktree/.superpowers/sdd/2026-08-11-better-ahead-ios-rebrand/task-2-report.md`;
- `/private/tmp/better-ahead-ios.GQgTa0/worktree/.superpowers/sdd/2026-08-11-better-ahead-ios-rebrand/task-3-report.md`;
- `/tmp/better-ahead-native-v3-oracle-red-attempt2.log`;
- `/tmp/better-ahead-native-v3-oracle-task-1-design-review-round-9.md`;
- `/tmp/better-ahead-native-v3-oracle-task-1-final-microdelta-rereview-round-10.md`;
- `/tmp/better-ahead-native-v3-legacy-stop-final-independent-review.md`;
- `/tmp/better-ahead-native-v3-legacy-migration-seam-divergence.md`;
- `/tmp/better-ahead-oa29-physical-evidence.json`;
- `/tmp/better-ahead-oa29-physical-evidence-summary.txt`;
- `/tmp/better-ahead-oa29-focused-attempt5.log`;
- `/tmp/option-a-journal-cleanup-boundaries-attempt3.log`.

Arquivos em `/tmp` não são arquivo permanente. O log RED atual é exigido pelo
handoff, mas as demais evidências devem ser promovidas a documentação
persistente quando o plano autorizar.

### 27.4 Anexos da conversa

- feedback de naming do cliente;
- inventário forense 1–4;
- screenshot de domínio;
- screenshot do INPI;
- cartão CNPJ.

Esses anexos são evidência contextual, não autorização jurídica.

---

## 28. Fragmentos de decisão que não podem ser reconstruídos com segurança

Durante a conversa foram respondidas várias perguntas por letras
`A`/`B`/`C` e uma escolha “1”. Alguns enunciados originais não sobreviveram
completos no contexto disponível.

Regras para continuidade:

- não inventar o significado dessas letras;
- usar somente decisões que aparecem por extenso nos documentos aprovados;
- Better Ahead, Flow, slogans, idiomas e estratégia visual estão claros;
- “3 dias somente” deve ser confirmado como trial antes de implementação;
- limites mensais precisam de nova matriz;
- qualquer decisão comercial/legal sem rótulo deve ser refeita em linguagem
  explícita.

---

## 29. Checklist de handoff da próxima sessão

A próxima sessão deve reportar:

- [ ] path, branch, HEAD e parent;
- [ ] staging;
- [ ] sete paths e hashes;
- [ ] manager e diagnóstico;
- [ ] log congelado e SHA;
- [ ] SHA documental importado;
- [ ] contagens TAP completas, incluindo filhos;
- [ ] RED e GREEN esperados;
- [ ] duas revisões;
- [ ] commits exatos;
- [ ] ambiente Docker/Corepack;
- [ ] existência/ausência de environment/bundle/journal;
- [ ] se houve render;
- [ ] preservação dos 24 assets;
- [ ] qualquer STOP;
- [ ] confirmação de que renderer legado não rodou;
- [ ] confirmação de nenhum push/PR/merge/deploy fora do plano.

---

## 30. Conclusão

O projeto não parte do zero. Existe um app iOS visualmente rico e muito
testado, uma plataforma de agente madura, uma Mobile API ampla e fundações
sólidas de segurança, conteúdo, rotina, push e entitlement.

O ponto decisivo é transformar essas peças de **demo/staging** em um produto
único, integrado e operável:

1. concluir o rebrand iOS controlado;
2. conectar autenticação, sessão, transporte e adapters reais;
3. rebrandar o backend público como Better Ahead/Flow;
4. fechar push/billing conforme o escopo da V1;
5. executar QA, segurança e UAT;
6. preparar produção, jurídico e App Store.

Até esses gates passarem, a afirmação correta é:

> **A base do produto está avançada, mas o aplicativo ainda não está 100%
> funcional para o cliente nem pronto para a App Store.**

Este dossiê deve ser atualizado a cada gate concluído, sempre com SHA, data,
ambiente, resultado, limites e autorização correspondente.

---

## 31. Atualização operacional 1.1 — naming hold e integração neutra

**Data:** 21/08/2026

**Autoridade da auditoria física:** `USER-SUPPLIED MAC READ-ONLY AUDIT`
**Decisão:** o cliente ainda não definiu o nome público definitivo. Better Ahead
é candidato provisório, sem clearance jurídico formal confirmado.

### Baseline da VPS

Leitura realizada em `2026-08-21T20:11:03Z`:

| Campo | Valor |
| --- | --- |
| Hostname / usuário | `srv1302975` / `root` |
| Path / Git root | `/root/agentempp` |
| Branch | `codex/better-ahead-rebranding-design` |
| HEAD / parent | `13fd60a709228566c2b0e639ba58a515ce0abea0` / `ad3fb05b903ed034364fc6190240caf1954c4a2b` |
| Upstream | `origin/codex/better-ahead-rebranding-design` |
| Staging | vazio |
| Entradas porcelain antes desta atualização | 26 |
| SHA-256 porcelain antes desta atualização | `f38384f11dd17a68848822074324c25d50720c66e40dd70e25c001217a2fb2c1` |
| SHA-256 diff binário tracked | `7262d613d02df890c8e0c02922fa778afb90a6b7c27aa25a417bf0c717bdbefb` |
| SHA-256 staged diff | `e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855` |

Os cinco tracked dirty preexistentes eram `.gitignore`,
`curated-phrase-selector.test.ts`, `curated-phrase-selector.ts`,
`educational-comment.test.ts` e `educational-comment.ts`. Eles permaneceram
byte-idênticos. Os artefatos não rastreados preexistentes foram inventariados
pela lista porcelain; nenhuma divergência desconhecida foi reconciliada.

### Estado físico supersedente

O snapshot anterior de sete paths dirty foi supersedido pela auditoria física do
Mac registrada em
`docs/superpowers/evidence/2026-08-20-better-ahead-worktree-physical-audit.md`.

- `/private/tmp/better-ahead-ios.GQgTa0/worktree` é
  `PHYSICALLY_INCOMPLETE_WORKTREE`;
- seus 1.420 paths tracked estão fisicamente ausentes;
- a metadata órfã `worktree1` e seu index devem permanecer preservados;
- o log RED histórico está ausente e não será recriado;
- seis blobs dirty não possuem recuperação comprovada;
- somente o blob do teste dirty existe no object database;
- a Task 3 não pode ser retomada naquela worktree;
- o path antigo é evidência forense, não área de desenvolvimento.

### Naming hold

- não inventar nome substituto;
- não expandir Better Ahead para novas superfícies;
- valores já commitados na Task 2 podem permanecer provisoriamente;
- Flow não está automaticamente revogado, porém sua propagação pública está
  fora deste workstream;
- Tasks 3–10 do rebrand ficam congeladas;
- Workstream 2 fica congelado apenas para propagação pública de marca;
- não executar renderer, Docker de assets, capture, environment ou review;
- não reverter automaticamente os commits existentes.

### Desenvolvimento que pode continuar

Integração técnica independente do nome pode avançar em nova worktree durável
no Mac:

- servidor continua autoritativo;
- Release/beta não pode usar sucesso sintético;
- mocks somente em Debug, previews e testes;
- nomes públicos devem depender de interfaces semânticas;
- novas features não podem hard-codear nome candidato;
- identificadores internos BodyFlow continuam inalterados.

O nome definitivo será obrigatório antes de UAT visual final, distribuição
externa, metadata de loja e submissão. Esta atualização não autoriza produção,
TestFlight, App Store, push, PR, merge ou deploy.

### Separação de ambientes

| Ambiente | Limite |
| --- | --- |
| VPS | documentação, contratos, backend, segurança e staging; não executa Xcode |
| Mac | Swift/SwiftUI, Xcode, simulador, testes nativos, acessibilidade e inspeção visual |
| Worktree antiga em `/private/tmp` | somente evidência; não recuperar, reparar ou reutilizar |

O plano operacional agora aplicável é
`docs/superpowers/plans/2026-08-20-naming-neutral-core-integration.md`.

---

## 32. Atualização operacional 1.2 — CI-0 signing gate

**Data:** 21/08/2026

A CI-0 foi implementada parcialmente na worktree de integração neutra do Mac,
mas continua sem commit. A sessão local reportou GREEN nos testes focados: 63
testes registrados, 83 execuções aprovadas, zero falhas e zero skips. Esta VPS
não executou Xcode e registra o resultado apenas como evidência fornecida pela
sessão Mac.

O build Debug original para `generic/platform=iOS` foi bloqueado antes da
compilação, em `GatherProvisioningInputs`, porque a configuração de assinatura
exigia Development Team. Release não foi executado. Os scans de conteúdo e
secrets, a revisão técnica independente, o staging e o commit da CI-0 ainda
estão pendentes.

A decisão operacional estreita é usar somente nos comandos Debug e Release da
CI-0 os overrides `CODE_SIGNING_ALLOWED=NO` e
`CODE_SIGNING_REQUIRED=NO`, preservando o destino
`generic/platform=iOS`. Não houve alteração persistente de signing, nem
certificado, team ou profile. O resultado desses builds unsigned não é prova
de signing, provisioning ou binário distribuível.

A próxima ação é publicar esta emenda documental, validá-la no Mac e retomar
os gates restantes da CI-0 na mesma worktree preservada. A CI-1 continua não
autorizada. O naming hold, a preservação da worktree órfã, os limites de Git e
distribuição, e a proibição de produção, TestFlight e App Store permanecem
inalterados.

---

## 33. Atualização operacional 1.3 — drift do resíduo da worktree órfã

**Data:** 22/08/2026

O STOP pré-fetch reportado pelo Mac observou 987 diretórios residuais na
worktree órfã, contra 5.270 na auditoria anterior: diferença de -4.283. Em
ambos os estados, havia zero arquivos regulares, `.git` ausente e os 1.420
paths tracked ausentes. O index e a metadata órfã permaneceram preservados.
A causa é desconhecida; nenhuma restauração foi autorizada ou executada.

A worktree continua `PHYSICALLY_INCOMPLETE_WORKTREE`, com subclassificação
`VOLATILE_RESIDUE_DRIFT`. Contagens de diretórios e symlinks deixam de bloquear
a CI-0, pois são resíduo forense não tracked; os gates materiais de Git, index,
paths tracked, `.git` ausente, zero arquivos regulares e não reutilização da
worktree permanecem obrigatórios.

Após a publicação desta emenda, a CI-0 pode retomar no Mac pela worktree
durável, sem restauração. Os builds unsigned, scans, revisão independente e
commit local da CI-0 continuam pendentes. CI-1 permanece não autorizada e o
rebrand permanece congelado.

---

## 34. Atualização operacional 1.4 — CI-0 concluída e CI-1 isolada autorizada

> **Estado histórico, superado para CI-1 pela atualização 1.5 em 23/08/2026.**
> A referência a Auth 2.54.1 e a formulação anterior sobre listener não são
> autorização operacional atual.

**Data:** 23/08/2026

CI-0 foi concluída e publicada em `b9a51bc1a641895ef5323cb1085b3b5622bbb277`
na branch de integração neutra: 68/88 testes, builds unsigned Debug/Release e
revisão final 0/0/0. A publicação GitHub usou credencial em keyring seguro;
nenhum PR, merge ou deploy ocorreu.

CI-1 é o próximo gate, com Auth 2.54.1 isolado, actor próprio e Keychain próprio;
o SDK não terá listener, restore ou refresh. CI-2 continua não autorizada. O
app ainda não tem login real concluído nem integração ponta a ponta; staging,
beta, produção, Apple e naming hold permanecem pendentes.

---

## 35. Atualização operacional 1.5 — STOP de ciclo de vida e retomada CI-1

**Data:** 23/08/2026

A implementação CI-1 no Mac permanece congelada, sem commit ou push: 15 paths
(7 modificados e 8 novos), staging vazio, 154 testes focados e 1.071 testes
BodyFlowTests reportados como aprovados. A análise independente encontrou que
Auth 2.54.1 registrava estado de ciclo de vida sem uma limpeza pública
suficiente para o modelo de cliente por operação. O STOP está preservado como
evidência fornecida pelo Mac; não foi reexecutado na VPS.

CI-1 passa a exigir apenas `Auth` de `supabase-swift` 2.55.1, fixado no commit
`21d3aaf21ee98f41611f9f75070489fc8b23d882`. A tag inclui os fixes oficiais que
removem o cliente desalocado do registry interno e encerram o trabalho de
refresh durante `deinit`. O desenho não muda: cliente efêmero por operação,
`autoRefreshToken: false`, storage descartável, nenhuma restauração ou refresh
do SDK e `AuthenticationSessionStore` como única sessão durável do app.

“Sem listener” passa a significar sem listener de autenticação/sessão instalado
pelo aplicativo ou usado para persistir/restaurar sessão. A observação interna
do SDK é tolerada somente no cliente efêmero 2.55.1, sem refresh e com prova de
desalocação. A retomada deve testar referência fraca até um deadline finito,
sem `Task.yield()` isolado, sem requisição/refresh tardio e sem retenção pelo
storage descartável. O warning menor de polling deve ser corrigido dentro dos
15 paths ou justificado objetivamente e passar Review B final sem Critical ou
Important.

Antes do commit CI-1 ainda faltam: atualizar o pin, adaptar somente a API
necessária, completar essa prova de vida, repetir testes, builds unsigned Debug
e Release em `generic/platform=iOS`, scans e duas revisões independentes. CI-2,
integração ponta a ponta, staging, beta, produção, Apple e naming hold seguem
fora de escopo. O app continua não 100% funcional para cliente/App Store.

---

## 36. Atualização operacional 1.6 — CI-1 concluída e CI-2 autorizada

**Data:** 24/08/2026

CI-1 foi concluída e publicada em
`aba177d7cbb0d9cecb13c5f1099e6b99b6456c93` na branch
`codex/ci1-supabase-auth-session-v1`, sobre CI-0. A VPS verificou tree,
estatísticas, 15 paths e seus hashes. A implementação usa somente Auth 2.55.1,
Keychain, record interno e `AuthenticationSessionStore` como fonte única.

O relatório Mac registra 140/182 testes focados e 1.072/1.261 BodyFlowTests,
Debug/Release unsigned em `generic/platform=iOS`, lifetime bounded sem
retenção, scans aprovados e duas revisões finais 0/0/0. Nenhum ambiente real,
URL/chave, staging E2E, signing ou produção foi configurado.

CI-2 é o próximo gate autorizado para refresh/rotação, logout local seguro,
troca de usuário, cancelamento patient-scoped e supressão de respostas tardias.
CI-3 não é autorizada. A fundação de autenticação/sessão real existe, mas
refresh/logout completo, adapters e staging ainda pendem; o app não está E2E,
beta-ready ou pronto para Apple. Naming hold, staging, beta, produção e Apple
continuam pendentes.

---

## 37. Atualização operacional 1.6.1 — reconciliação da enumeração porcelain da VPS

**Data:** 25/08/2026

A auditoria read-only fornecida pelo usuário e a revalidação read-only nesta
VPS confirmaram que não houve perda de evidência nem mudança material na
worktree manager. A diferença observada entre 25 e 22 entradas decorre apenas
do modo de enumeração de arquivos não rastreados pelo Git.

A baseline histórica canônica permanece, sem substituição:

- comando: `LC_ALL=C git status --porcelain=v1 -uall`;
- 25 entradas usando `git status --porcelain=v1 -uall`;
- 5 tracked e 20 untracked;
- SHA-256 do stream integral:
  `455000fe5f148dcad3034f03d57e2683deedb8ae5ec655b8a459639117f040e0`;
- SHA-256 do diff binário tracked:
  `7262d613d02df890c8e0c02922fa778afb90a6b7c27aa25a417bf0c717bdbefb`;
- staging vazio.

A visão compacta, obtida por
`LC_ALL=C git status --porcelain=v1`, produz 22 entradas, sendo 5 tracked e
17 untracked compactas, com SHA-256
`256e29e64780b2100e569f222d810a49addbe6099254637519c30615c99bd26c`.
Nela, quatro entradas de diretório — `docs/architecture/`, `docs/audits/`,
`docs/business/` e `memory/` — representam os mesmos sete arquivos enumerados
individualmente por `-uall`. A expansão de quatro para sete explica exatamente
a diferença líquida de três entradas.

Nenhum path desapareceu, foi movido, passou a ser ignored ou foi commitado, e
nenhum byte histórico mudou. A visão compacta é somente observacional; ela não
define uma baseline alternativa. Todo futuro gate de preservação da VPS deve
usar explicitamente `LC_ALL=C git status --porcelain=v1 -uall`, registrar o
comando, as contagens total/tracked/untracked e o SHA-256 do stream integral, e
executar STOP se esses valores divergirem quando medidos pelo mesmo comando.

O estado de entrega não avança nesta atualização:

- CI-2 continua publicada e é o próximo gate de implementação autorizado;
- a staging secret source ainda não foi criada;
- projeto e deployment Vercel de staging continuam inexistentes;
- CI-3 continua não autorizada;
- nenhuma produção foi tocada.

A evidência detalhada está em
`docs/superpowers/evidence/2026-08-24-vps-manager-porcelain-enumeration-reconciliation.md`.
