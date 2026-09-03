# Better Ahead / Flow — dossiê completo de contexto e plano de finalização

**Data de consolidação:** 20 de agosto de 2026

**Versão do dossiê:** 1.7.18

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

---

## 38. Atualização operacional 1.6.2 — reconciliação da criação não autorizada de secret key no projeto primary/live

**Data:** 25/08/2026

Uma auditoria read-only confirmou que uma modern secret key chamada
`manager_vps_20260825` foi criada no projeto Supabase primary/live em
25/08/2026 às 15:31:33 UTC. A criação foi uma escrita histórica no
control-plane, excedeu o escopo autorizado e não estava autorizada pelo gate
operacional vigente. O projeto exato é `xuxehkhdvjivitduarvb`, classificado
como produção/live; a key é do tipo modern secret e permanece ativa. Esta
reconciliação não reclassifica o ato como aprovado e não autoriza usar, rotar,
renomear ou desativar a key.

O projeto primary/live permanece ativo. As cinco chaves observadas por GET —
as duas legacy, as duas default modernas e a nova secret key — continuam
ativas. A auditoria não encontrou consumidor atual, container, processo PM2,
processo externo ou launcher conhecido que carregue a nova key. O arquivo
local que a contém é regular, `root:root`, modo `0600`, sem symlink, está em
diretório `0700` e permanece separado da fonte de staging. Seus valores não
foram impressos nem copiados para Git.

A classificação operacional é:

- `CONTROL_PLANE_WRITE_OCCURRED_HISTORICALLY=YES`;
- `CONTROL_PLANE_WRITE_TYPE=API_KEY_CREATION`;
- `PRIMARY_PROJECT_TOUCHED=YES`;
- `PRODUCTION_DATABASE_TOUCHED=NO`;
- `PRODUCTION_DEPLOYED=NO`;
- `PRIMARY_KEY_STATE=ACTIVE_QUARANTINED_UNUSED`;
- `PRIMARY_KEY_RETENTION_IS_OPERATIONAL_APPROVAL=NO`;
- `PRIMARY_KEY_DISABLE_AUTHORIZED=NO`;
- `STAGING_SOURCE_PRESERVED=YES`.

Manter a key ativa e isolada é apenas preservação fail-closed enquanto não há
uma nova autorização específica e uma auditoria de consumidores imediatamente
anterior à eventual desativação. A key primary não pode ser usada em staging,
Preview, testes, builds, CI-3 ou deploy Vercel.

A fonte segura de staging já existe separadamente, com três variáveis e receipt
root-only coerente com o projeto staging. A auditoria não detectou mistura de
fingerprints entre primary e staging. Os dois `.env.local` observados são
regulares, `root:root`, modo `0600`; nenhum contém os fingerprints elevados
auditados. A equivalência histórica integral dos bytes desses arquivos não é
comprovável e não deve ser alegada ou reconstruída.

Duas revisões independentes — control-plane Supabase e filesystem/runtime —
concluíram `GO` somente para esta reconciliação documental, ambas com
0 Critical, 0 Important e 0 Minor. Nenhuma migração, escrita de banco, criação
de usuário, deploy, restart, rotação, desativação ou uso da key primary ocorreu
nesta operação.

CI-3 continua não autorizada neste primeiro gate documental. A criação do
projeto interno e a publicação do BFF Preview de staging continuam pendentes e
dependem dos gates técnicos e de segurança seguintes.

A evidência detalhada está em
`docs/superpowers/evidence/2026-08-25-primary-supabase-secret-control-plane-reconciliation.md`.

---

## 39. Atualização operacional 1.6.3 — STOP no provisionamento do BFF Preview

**Data:** 25/08/2026

A CI-2 está publicada e foi revalidada no SHA
`277873755bf29771a10b5f362b522c2e6a6c21d6`, com 15 paths, tree e parent
esperados. A worktree detached usada para os gates permaneceu limpa. Nesta VPS,
48/48 testes focados da Mobile API, 10/10 testes de estado diário, 619/619
testes do admin, typecheck e build Next.js com a fonte staging passaram. Duas
revisões independentes pré-Vercel terminaram com 0 Critical, 0 Important e
0 Minor.

O projeto Vercel exato `agentempp-mobile-bff-staging` e deployments associados
não existiam no preflight. A única tentativa autorizada de criação do projeto
terminou com HTTP 400: a API v11 rejeitou `nodeVersion` como propriedade
adicional. A consulta read-only posterior confirmou que nenhum projeto parcial
foi criado.

Estado congelado:

- projeto Vercel criado: não;
- tentativa de criação do projeto: 1/1;
- variáveis Preview criadas: 0;
- tentativa de deployment Preview: 0/1;
- deployment ID: N/A;
- source pretendido:
  `277873755bf29771a10b5f362b522c2e6a6c21d6`;
- produção, banco primary/live, runtime e domínios: intocados;
- nenhuma segunda tentativa autorizada ou executada;
- CI-3: não autorizada.

O próximo gate exato é
`RECONCILE_STAGING_BFF_PROVISIONING_STOP`: uma nova autoridade documental deve
definir um request compatível com a API atual sem enfraquecer Node 22,
Preview-only, root `apps/admin`, Corepack/pnpm 10.33.2, zero Git integration e a
regra de tentativa única. Não se deve reutilizar esta autorização para repetir
a criação.

Evidências detalhadas:

- `docs/superpowers/evidence/2026-08-25-ci2-session-lifecycle-completion.md`;
- `docs/superpowers/evidence/2026-08-25-ci3-staging-bff-provisioning-stop.md`.

---

## 40. Atualização operacional 1.6.4 — STOP por proteção herdada no Preview

**Data:** 25/08/2026

A reconciliação do schema Vercel foi executada com uma autorização nova e
independente da tentativa histórica consumida. O schema autenticado do Vercel
CLI 50.35.0 confirmou que `nodeVersion` não pertence ao request de criação e
que `nodeVersion: 22.x` pertence ao endpoint de atualização. O preflight
confirmou novamente a ausência do projeto exato e de deployments associados.

A tentativa de reconciliação 1/1 criou o projeto
`agentempp-mobile-bff-staging` com somente nome, framework Next.js, root
`apps/admin` e opt-out de conexão Git. O PATCH 1/1 aplicou Node 22.x, os
comandos congelados de Corepack/pnpm 10.33.2 e a inclusão dos packages externos
ao root. O GET posterior confirmou os settings materiais, zero Git Integration
e zero custom domains. O project ID foi registrado somente pelo fingerprint
SHA-256
`26c8edbed7fb4ed89674c43934733686f605f5152551110a14cc2b8798e7584f`.

O mesmo GET revelou que o projeto herdou
`ssoProtection.deploymentType=all_except_custom_domains` (Vercel
Authentication). Como o contrato exige que o endpoint Preview
público alcance a Mobile API e retorne seu próprio envelope 401, essa proteção
interceptaria o gate. A operação parou antes de copiar qualquer secret, criar
env vars, vincular a worktree ou executar deployment. A proteção não foi
desativada, contornada ou alterada.

Estado preservado:

- tentativa histórica de criação: 1/1, falha e sem projeto;
- tentativa de criação da reconciliação: 1/1, aprovada;
- total histórico de requests de criação: 2;
- projeto criado: sim, preservado;
- PATCH de settings: 1/1, aprovado;
- env vars Preview: 0; batch attempts: 0/1;
- env vars Production: 0;
- local link attempts: 0/1;
- deployment Preview attempts: 0/1;
- deployment ID e origem: N/A;
- source pretendido:
  `277873755bf29771a10b5f362b522c2e6a6c21d6`;
- Git Integration e custom domains: ausentes;
- Supabase e banco: nenhuma escrita;
- produção: intocada;
- CI-3: não autorizada.

O projeto e seus settings devem permanecer intactos. Não existe autorização
para apagar ou recriar o projeto, alterar a proteção, criar bypass/share token,
inserir env vars ou tentar deployment. Os budgets registrados como 0/1 são
estado histórico desta execução encerrada e não podem ser reutilizados. O
próximo gate exato é
`RECONCILE_STAGING_BFF_PREVIEW_PROTECTION_POLICY`, que deve decidir uma
arquitetura de ingresso Preview compatível com a Mobile API sem expor
indevidamente as demais superfícies de `apps/admin`.

Evidência detalhada:
`docs/superpowers/evidence/2026-08-25-ci3-staging-bff-reconciliation-stop.md`.

---

## 41. Atualização operacional 1.6.5 — STOP na política de ingresso público do Preview

**Data:** 25/08/2026

A nova autoridade permitia, condicionalmente, remover a Vercel Authentication
somente do projeto staging, criar três env vars Preview, vincular a worktree e
executar um deployment. O gate anterior obrigatório era provar que toda a
superfície compartilhada de `apps/admin` possuía proteção própria no
application layer.

O inventário read-only classificou 132 unidades: 27 páginas, 48 route handlers,
54 Server Actions exportadas, dois layouts e um middleware. Zero superfície
ficou sem classificação. Os testes focados existentes passaram 172/172, mas a
auditoria encontrou 21 superfícies blocking em três famílias:

- `/api/admin/send-message` é excluído pelo middleware e aceita a própria
  `SUPABASE_SERVICE_ROLE_KEY` como bearer público;
- `upsertFood` e `deleteFood` abrem o service client sem autenticação ou
  autorização admin própria;
- 18 rotas de página administrativas — 17 diretamente e `/crescimento` por
  três views transitivas — consultam por `service_role` sem verificar o papel
  admin junto à leitura privilegiada, dependendo apenas do middleware e do
  layout pai.

As duas revisões independentes retornaram `NO-GO`, cada uma com 0 Critical,
3 Important e 1 Minor.

Assim, a arquitetura foi classificada como
`REQUIRES_DEDICATED_BFF_ONLY_ARTIFACT`. Nenhuma escrita desta autorização foi
executada: protection PATCH 0/1, env batch 0/1, link 0/1 e deployment 0/1. O
projeto continua protegido por
`ssoProtection.deploymentType=all_except_custom_domains`, com zero env, zero
deployment e zero custom domain. A fonte staging ficou intacta e a fonte
primary/live não foi aberta.

CI-3 continua não autorizada. O próximo gate material é
`AUTHORIZE_DEDICATED_PUBLIC_MOBILE_BFF_SURFACE`: separar um artefato público que
contenha somente `/api/mobile/v1/**`, sem expor o painel e seus endpoints
administrativos. Essa etapa exige nova autoridade antes de código, env,
proteção ou deployment.

Evidência detalhada:
`docs/superpowers/evidence/2026-08-25-ci3-preview-protection-policy-stop.md`.

---

## 42. Atualização operacional 1.6.6 — autorização do artefato público Mobile BFF dedicado

**Data:** 25/08/2026

A auditoria de ingresso do artefato compartilhado encontrou 21 blockers
administrativos e concluiu que `apps/admin` não pode perder a Vercel
Authentication como um todo. A arquitetura autorizada para o próximo gate é
`DEDICATED_NEXTJS_MOBILE_BFF_ARTIFACT`: um app Next.js separado em
`apps/mobile-bff`, package `@mpp/mobile-bff`, cuja única superfície roteável é
`/api/mobile/v1/**`.

Os handlers oficiais permanecem como fonte única em
`apps/admin/src/app/api/mobile/v1/**/route.ts`. O app dedicado deve criar um
mirror estático e auditável de wrappers, com named re-exports exatos, sem
`export *`, cópia de lógica, alteração dos handlers existentes ou correção dos
21 findings administrativos. O inventário congelado contém 40 route modules,
zero export inválido e stream canônico SHA-256
`7154a9a67db83e0adc8a2f3bc22e1bdd2be752904c1f416cca43d00ed10679b4`.

A closure transitiva pode alcançar somente os route modules Mobile API, suas
libs estritamente necessárias, packages workspace e dependências externas
comprovadamente requeridas. Ela deve excluir páginas e layouts administrativos,
Server Actions, middleware, APIs admin/Inngest/Stripe/media administrativas,
webhooks, callbacks do painel, login, assets públicos e qualquer route fora do
prefixo Mobile API. Source tests, import-closure tests, build manifests e smoke
loopback precisam provar 40/40 wrappers, zero superfície proibida, 401 JSON com
os headers Mobile API para rotas protegidas e 404 sem redirect para rotas
administrativas.

A implementação futura parte exclusivamente do CI-2
`277873755bf29771a10b5f362b522c2e6a6c21d6`, em
`codex/ci3-dedicated-mobile-bff-surface-v1`, worktree
`/root/agentempp-ci3-dedicated-mobile-bff-surface-v1`, com subject
`feat(staging): add dedicated Mobile API BFF surface`. A worktree detached
`/root/agentempp-ci3-staging-bff-v1` e a worktree congelada do Mac permanecem
intocadas. O plano executável integral está em
`docs/superpowers/plans/2026-08-25-dedicated-public-mobile-bff-surface.md`, e o
contrato em
`docs/superpowers/specs/2026-08-25-dedicated-public-mobile-bff-surface.md`.

O projeto Vercel existente `agentempp-mobile-bff-staging` deve ser reutilizado,
nunca apagado ou recriado. A proteção SSO permanece ativa enquanto o único
deployment Preview é construído e inspecionado. Somente após source SHA,
manifests e revisão de ingresso aprovados ela pode ser removida nesse projeto;
o team default não muda e um rollback único restaura
`all_except_custom_domains` se qualquer probe público posterior falhar. Apenas
as três variáveis staging existentes podem ser enviadas, exclusivamente ao
target Preview; Production env, Production deployment, Git Integration,
custom domain, bypass e uso do secret primary/live continuam proibidos.

Esta atualização autoriza somente a sequência documentada do artefato dedicado
e seus budgets novos e independentes de uma tentativa. Ela não autoriza
produção, correção das 21 superfícies admin, CI-4, PR, merge, TestFlight ou App
Store. CI-3 só poderá ser autorizada pela documentação final `PASS_COMPLETE`,
depois do BFF público verificado e de um caminho de paciente sintético
`VERIFIED`; com paciente ausente, o resultado obrigatório é `PASS_PARTIAL` e
um gate separado de provisionamento, sem criar usuário nesta operação.

### Hardening da autoridade após as revisões independentes

Os receipts deixam de usar um hash ambíguo. O stream source e o stream wrapper
continuam separados por nome e raiz relativa, embora ambos tenham 40 registros
path/export e SHA-256
`7154a9a67db83e0adc8a2f3bc22e1bdd2be752904c1f416cca43d00ed10679b4`.
O stream build é path-only: transforma cada `<segments>/route.ts` em
`/api/mobile/v1/<segments>`, preserva `[id]`/`[token]`, exclui somente o
`/_not-found` interno, ordena e codifica `<route-url>\n`; são 40 registros e
SHA-256
`abc24332fd370b5d7940ca56b18530a3659ba39b5205faeb2bf36771aa6f3c3a`.

O gate dos 21 findings também é congelado. Há 19 probes HTTP GET concretos — a
rota API e as 18 páginas, com UUID sintético nos dois paths dinâmicos — no
stream `GET\0<path>\n`, SHA-256
`8677245f63ee3b5f1fb36a58c2a36e2eddfe8f9cc2065f74ab65298676a6f718`.
`deleteFood` e `upsertFood` formam o stream manifest-only de duas linhas,
SHA-256
`2cc8eac1a54c3f88673701d4b9ede202f1ec4440bf414ac7696dda341bd53a35`;
elas nunca são invocadas e devem estar ausentes do server-reference manifest.
Qualquer falha de transporte, status, JSON/envelope/header/request ID, 404,
manifest, HTML/Vercel/stack, secret ou PII nos Steps públicos 1–3, depois do
forward SSO, aciona o único rollback e proíbe repetir probes.

O histórico 172/172 não é tratado como uma lista recuperada. O gate corrente
deriva deterministicamente do objeto CI-2 um superset seguro de 39 test files,
com stream de paths SHA-256
`586a6653c80b06d77293f0d32f6a2166fb93f935c5d53080cbd0971e60b7a3b8`,
executa esse conjunto e registra a contagem atual. RED 1 usa o Vitest já
congelado de `apps/admin` após install frozen e cria somente os dois tests
dedicados; package/config são GREEN 1.

Antes de operação pesada, o resource gate da VPS é obrigatório; toda mutação
recebe ledger imediato com target, evidence, result e rollback/restore, sem
valor sensível. A ref documental exata é
`refs/heads/codex/better-ahead-rebranding-design`; a evidência Mac congelada é
`/Users/eduardohenrique/Developer/bodyflow-production-secret-contract-v1`.
Falha do commit/push de autoridade encerra em report-only
`STOP_PRE_AUTHORITY`, sem código ou serviço. Depois da autoridade publicada,
os três outcomes usam allowlists, versões, subjects, parent, reviews e push
exatos definidos integralmente na spec e no plano. A preservação final exige
staging vazio e `.vercel` ausente na worktree CI-2; `.vercel` local somente na
implementation worktree limpa reutilizada para deploy, sempre
untracked/unstaged; nenhuma deployment worktree dedicada é criada.

## 43. Atualização operacional 1.6.7 — STOP na descoberta do RED 1 do Mobile BFF dedicado

**Data:** 25/08/2026

A autoridade documental do artefato dedicado foi publicada em
`89f8bc1c41073d110fe17ee3c638da3998c31aad`. A implementação isolada partiu do
CI-2 `277873755bf29771a10b5f362b522c2e6a6c21d6`, no branch
`codex/ci3-dedicated-mobile-bff-surface-v1` e worktree
`/root/agentempp-ci3-dedicated-mobile-bff-surface-v1`.

O último gate aprovado foi Task 3 Step 1: após resource gate, o install frozen
com Corepack pnpm 10.33.2 terminou com exit 0, sem alteração rastreada e com
`pnpm-lock.yaml` byte a byte igual ao CI-2, SHA-256
`2ea2083229ce0f5b8c1fab28f4324b1840a596939dac369f32b073a8d065dc55`.
Somente os dois testes RED autorizados foram criados, ambos unstaged:

```text
apps/mobile-bff/src/source-surface.test.ts
apps/mobile-bff/src/route-mirror.test.ts
```

O gate seguinte, Task 3 Step 4 — RED 1, não atingiu a falha semântica exigida
de wrapper count zero. O comando exato publicado executou Vitest 2.1.9 com
root em `apps/admin`, mas descobriu zero arquivos e executou zero testes porque
os dois operands resolvem para o sibling `apps/mobile-bff`. O resultado foi
exit 1 e `No test files found`. O transcript normalizado tem SHA-256
`5faceda6a65a877d02f0eb1115c9227c98689ad8bc5cddb38929fabbac655a07`.

O source manifest ainda foi reproduzido read-only diretamente do objeto CI-2
como 40 registros e SHA-256
`7154a9a67db83e0adc8a2f3bc22e1bdd2be752904c1f416cca43d00ed10679b4`,
mas isso não substitui o RED executado. Wrapper parity, import closure,
build-surface, focused tests, typecheck, build e smoke não foram executados.
Nenhum package/config GREEN, wrapper ou lockfile importer foi criado.

O resultado obrigatório é `STOP_DOCUMENTED`. Alterar o root/comando do runner
ou antecipar `vitest.config.ts` exige reconciliação explícita da autoridade e
preservação da ordem test-first. Não houve commit/push de código, settings
PATCH, env batch, link, deployment, SSO forward/rollback, probe público,
receipt, Supabase/database write, produção, CI-3 ou CI-4. O projeto Vercel
existente permanece no último estado confirmado pela autoridade, sem qualquer
tentativa desta fase.

```text
DEDICATED_MOBILE_BFF_STATUS=NOT_VERIFIED
STAGING_BFF_STATUS=NOT_VERIFIED
CI3_DOCUMENTATION_STATUS=NOT_AUTHORIZED
VERCEL_PROJECT_SETTINGS_PATCH_ATTEMPTS=0
VERCEL_PREVIEW_ENV_BATCH_ATTEMPTS=0
VERCEL_PREVIEW_DEPLOYMENT_ATTEMPTS=0
VERCEL_PROJECT_SSO_DISABLE_ATTEMPTS=0
VERCEL_PROJECT_SSO_ROLLBACK_ATTEMPTS=0
NEXT_ENVIRONMENT=VPS
NEXT_GATE=RECONCILE_RED1_VITEST_EXTERNAL_TEST_DISCOVERY
```

Preservação: o manager conserva seus 25 itens históricos e staging vazio; a
worktree antiga permanece detached, clean no CI-2 e sem `.vercel`; a worktree
de implementação permanece no CI-2, sem upstream, com somente os dois testes
RED unstaged. Esta atualização não autoriza executar o próximo gate, editar
código, tocar serviços, produção, CI-3 ou CI-4.

Evidência detalhada:
`docs/superpowers/evidence/2026-08-25-ci3-dedicated-mobile-bff-stop.md`.

## 44. Atualização operacional 1.6.8 — reconciliação da descoberta externa do RED 1 do Mobile BFF dedicado

**Data:** 26/08/2026

Esta atualização promove o dossiê de `1.6.7` para `1.6.8` e é a
autoridade exclusiva para reconciliar a descoberta externa do RED 1. O STOP
anterior permanece correto como evidência histórica: o Vitest 2.1.9 foi
executado a partir de `apps/admin`, conservou `apps/admin` como root efetivo,
descobriu zero test files, executou zero tests e terminou com
`No test files found`. Isso foi um defeito de root/discovery do comando, não
um defeito dos testes nem do source manifest.

O receipt source read-only continua válido:

```text
SOURCE_ROUTE_EXPORT_COUNT=40
SOURCE_ROUTE_INVALID_EXPORT_COUNT=0
SOURCE_ROUTE_EXPORT_STREAM_SHA256=7154a9a67db83e0adc8a2f3bc22e1bdd2be752904c1f416cca43d00ed10679b4
```

Os dois testes preservam exatamente estes bytes antes da primeira execução
reconciliada:

```text
50298447a2956c07693baa80468b70b4fd08a6f556542531b2e7f67428298ab6  apps/mobile-bff/src/source-surface.test.ts
289b5d447c0c30743553e8f9a5a725fdba0e722ab5ccb0c6e0580f8ed923829f  apps/mobile-bff/src/route-mirror.test.ts
```

O comando relativo registrado em 1.6.6/1.6.7 fica `SUPERSEDED` para novas
execuções, sem apagar seu resultado histórico. Depois que esta autoridade
for publicada e seu SHA remoto for registrado como
`RED_DISCOVERY_AUTHORITY_SHA`, o único comando RED 1 autorizado, com
`WORKTREE=/root/agentempp-ci3-dedicated-mobile-bff-surface-v1`, é:

```bash
corepack pnpm@10.33.2 \
  --dir "$WORKTREE/apps/admin" \
  exec vitest run \
  --config "$WORKTREE/apps/admin/vitest.config.ts" \
  --root "$WORKTREE" \
  --dir "$WORKTREE/apps/mobile-bff/src" \
  "$WORKTREE/apps/mobile-bff/src/source-surface.test.ts" \
  "$WORKTREE/apps/mobile-bff/src/route-mirror.test.ts"
```

O RED reconciliado tem budget de uma tentativa e só é semântico quando
todos os critérios abaixo forem verdadeiros na mesma execução:

```text
RED1_DISCOVERED_TEST_FILE_COUNT=2
RED1_EXECUTED_TEST_COUNT=>0
RED1_SOURCE_ROUTE_EXPORT_COUNT=40
RED1_SOURCE_INVALID_EXPORT_COUNT=0
RED1_SOURCE_ROUTE_EXPORT_STREAM_SHA256=7154a9a67db83e0adc8a2f3bc22e1bdd2be752904c1f416cca43d00ed10679b4
RED1_WRAPPER_ROUTE_EXPORT_COUNT=0
RED1_FAILURE_CLASSIFICATION=MIRROR_ABSENT_ONLY
RED1_NO_TEST_FILES_FOUND=NO
RED1_CONFIG_ERROR=NO
RED1_MODULE_ERROR=NO
RED1_SYNTAX_ERROR=NO
RED1_SOURCE_DRIFT=NO
RED1_SKIP_TODO_CANCEL=0
RED1_EXIT_CODE=1
```

Antes desse RED semântico é proibido criar `package.json`, config Vitest ou
qualquer outro artefato GREEN em `apps/mobile-bff`, usar
`--passWithNoTests` ou alterar qualquer byte dos dois testes. A worktree e o
branch de implementação existentes devem ser reutilizados; esta reconciliação
não reautoriza criação de worktree, branch, upstream ou novo RED.

Os budgets externos anteriores não são reutilizados implicitamente. Depois da
confirmação remota de `RED_DISCOVERY_AUTHORITY_SHA`, valem apenas estes novos
budgets separados:

```text
RED1_RECONCILED_EXECUTION_ATTEMPTS=1
IMPLEMENTATION_COMMIT_ATTEMPTS=1
IMPLEMENTATION_PUSH_ATTEMPTS=1
VERCEL_DEDICATED_PROJECT_SETTINGS_PATCH_ATTEMPTS=1
VERCEL_PREVIEW_ENV_BATCH_ATTEMPTS=1
VERCEL_LOCAL_LINK_ATTEMPTS=1
VERCEL_PREVIEW_DEPLOYMENT_ATTEMPTS=1
VERCEL_PROJECT_SSO_DISABLE_ATTEMPTS=1
VERCEL_PROJECT_SSO_ROLLBACK_ATTEMPTS=1
FINAL_DOCUMENTATION_COMMIT_ATTEMPTS=1
FINAL_DOCUMENTATION_PUSH_ATTEMPTS=1
```

As Tasks 4–14 do plano dedicado continuam literalmente somente depois que o
RED semântico for aprovado. Em qualquer outcome final, a autoridade parental
exclusiva é `RED_DISCOVERY_AUTHORITY_SHA`: `STOP_DOCUMENTED` e
`PASS_PARTIAL` promovem `1.6.8` para `1.6.9`, enquanto `PASS_COMPLETE`
promove `1.6.8` para `1.7`. Esta reconciliação isolada executa zero produção
e não autoriza CI-3 ou CI-4.

### Hardening Round 1 da reconciliação

Os Steps 1–3 da Task 3 são históricos/concluídos: install frozen e escrita dos
dois testes não devem ser repetidos. Antes do comando acima, a Fase B exige
preflight read-only da identidade integral da worktree, dois untracked/hashes,
staging vazio, tracked clean, lockfile
`2ea2083229ce0f5b8c1fab28f4324b1840a596939dac369f32b073a8d065dc55`,
Vitest 2.1.9, config CI-2
`8bb6705e6315f5a28bdf6cc15cae3ff7526007913c8f7c01acd7279ad0b91266`
sem `root`/`include` conflitante, source `40/0/hash`, wrapper `0` e zero
package/config GREEN. O único capability check é
`corepack pnpm@10.33.2 --dir "$WORKTREE/apps/admin" exec vitest --help`,
confirmando `--root`, `--dir` e `--config`, sem discovery/list. Install frozen
só pode ocorrer se o binário estiver ausente; falha seleciona
`STOP_DOCUMENTED`.

A execução única deve gerar transcript ordenado `key=value\n`, normalizado sem
ANSI, com fingerprint do comando, Vitest/root/dir/config, contagens de
files/tests/pass/fail/skip, exit, source/invalid/hash, wrapper e todas as
classificações. O raw transcript não é receipt. O campo vinculante é
`RED1_RECONCILED_NORMALIZED_LOG_SHA256=<SHA_REAL>`, e o relatório final inclui
grupo separado `RED1_RECONCILED`.

As Tasks 11–14 reutilizam a implementation worktree limpa; nenhuma deployment
worktree nova é criada. A partir do SSO forward, sucesso ou possível sucesso
obriga rollback único em qualquer falha/ambiguidade posterior, inclusive
response/readback. Probes não começam nem se repetem; proteção ativa deve ser
comprovada por readback. Falha/ambiguidade do rollback é material-risk STOP. Em
`STOP_DOCUMENTED`, os únicos valores autorizados para
`DEDICATED_MOBILE_BFF_STATUS` são `NOT_VERIFIED`,
`IMPLEMENTED_NOT_DEPLOYED`, `DEPLOYED_PROTECTED` e `PUBLIC_ROLLED_BACK`.

Evidência detalhada:
`docs/superpowers/evidence/2026-08-25-ci3-red1-vitest-external-discovery-reconciliation.md`.

## 45. Atualização operacional 1.6.9 — STOP no PATCH de settings do Mobile BFF dedicado

**Data:** 26/08/2026

Esta atualização promove o dossiê de `1.6.8` para `1.6.9` e registra o
outcome obrigatório `STOP_DOCUMENTED` da operação
`RECONCILE_RED1_VITEST_EXTERNAL_TEST_DISCOVERY_AND_RESUME_DEDICATED_BFF`.
O RED reconciliado, a implementação e a validação local foram concluídos; o
STOP ocorreu somente no Task 9, depois do único PATCH de settings permitido
para o projeto Vercel existente.

### Autoridade e implementação publicada

- Autoridade documental:
  `d5bf981a6c3e926eb63ecb39ccc1d3bdabf31459`.
- Implementação base/commit/tree:
  `277873755bf29771a10b5f362b522c2e6a6c21d6` /
  `e3e1e252b48e42554e75899b950692c05186f60d` /
  `a167a6663cb1e476975742bcec51c7207dbcbc26`.
- Branch: `codex/ci3-dedicated-mobile-bff-surface-v1`.
- Subject: `feat(staging): add dedicated Mobile API BFF surface`.
- Publicação: uma tentativa sem force e sem upstream; remote readback exato.

O RED reconciliado descobriu dois arquivos e executou três testes: dois
passaram, um falhou exclusivamente como `MIRROR_ABSENT_ONLY`, zero skip, exit
1. O receipt normalizado tem SHA-256
`0b320926087f0f250af2ad5737f0dad85f5cf3935248fe0c4613dc063e6674a9`.

```text
SOURCE_ROUTE_EXPORT_COUNT=40
SOURCE_ROUTE_EXPORT_STREAM_SHA256=7154a9a67db83e0adc8a2f3bc22e1bdd2be752904c1f416cca43d00ed10679b4
WRAPPER_ROUTE_EXPORT_COUNT=40
WRAPPER_ROUTE_EXPORT_STREAM_SHA256=7154a9a67db83e0adc8a2f3bc22e1bdd2be752904c1f416cca43d00ed10679b4
BUILD_ROUTE_PATH_COUNT=40
BUILD_ROUTE_PATH_STREAM_SHA256=abc24332fd370b5d7940ca56b18530a3659ba39b5205faeb2bf36771aa6f3c3a
BUILD_BUNDLE_SURFACE_STREAM_SHA256=e385efda5cc6455112d3bab1a03955e7732b5a151a907d3ce200e7d3617bf1b4
IMPORT_CLOSURE_RECORD_COUNT=121
IMPORT_CLOSURE_STREAM_SHA256=2553c0d366d7c38e778f7509ab64de2ea0f90feb44c20bac29d056d95f36b5f4
DEDICATED_TESTS=24/24_PASS
FOCUSED_SECURITY_TESTS=433/433_PASS
TYPECHECK=PASS
SYNTHETIC_BUILD=PASS
LOOPBACK_MOBILE=3/3_PASS
LOOPBACK_FORBIDDEN=24/24_PASS
IMPLEMENTATION_REVIEW_A=GO_0_CRITICAL_0_IMPORTANT
IMPLEMENTATION_REVIEW_B=GO_0_CRITICAL_0_IMPORTANT
```

As revisões fecharam antes do commit o grafo de workers Inngest no bundle
público e dois gates NFT fail-open. O build final resolve somente o client
publicado e registra 4.180 referências NFT, 151 targets, 149 arquivos e apenas
dois diretórios estruturais semanticamente allowlisted (`next` e
`@opentelemetry/api`), com worker/admin/missing/external/special em zero.

### STOP exato do Task 9

O preflight confirmou um único `agentempp-mobile-bff-staging` com o fingerprint
esperado, root `apps/admin`, Node 22.x, Next.js, external sources habilitado,
SSO `all_except_custom_domains`, env 0/0, deployments 0, Git Integration 0 e
custom domain 0. A única entrada de domínio é o domínio automático
`.vercel.app`.

O PATCH único enviou os sete campos publicados. O readback confirmou seis,
mas `skipGitConnectDuringLink` permaneceu ausente/null:

```text
VERCEL_PROJECT_ROOT=apps/mobile-bff
VERCEL_PROJECT_NODE=22.x
VERCEL_PROJECT_FRAMEWORK=nextjs
VERCEL_PROJECT_BUILD_COMMAND=MATCH
VERCEL_PROJECT_INSTALL_COMMAND=MATCH
VERCEL_PROJECT_OUTSIDE_ROOT=YES
VERCEL_PROJECT_SKIP_GIT_CONNECT=ABSENT_OR_NULL
VERCEL_PROJECT_GIT_INTEGRATION=NO
VERCEL_PROJECT_CUSTOM_DOMAIN_COUNT=0
VERCEL_PREVIEW_ENV_COUNT=0
VERCEL_PRODUCTION_ENV_COUNT=0
VERCEL_DEPLOYMENT_COUNT=0
PROJECT_SSO_FINAL=all_except_custom_domains
TEAM_DEFAULT_CHANGED=NO
```

O plano classifica qualquer PATCH falho/parcial como STOP sem retry. Não houve
env batch, leitura da fonte de secrets, link, deployment, SSO forward/rollback,
probe público, receipt de deployment ou avaliação do paciente sintético.

### Preservação e próximo gate

Antes desta atualização, o manager preservava os 25 itens históricos e staging
vazio. A worktree CI-2 antiga continua detached/clean no SHA exato e sem
`.vercel`; a implementação está clean no commit publicado, staging vazio, sem
upstream e sem `.vercel`. Não houve Supabase/database write, produção, PR,
merge, tag, CI-3, CI-4, TestFlight ou App Store. GitHub Actions permanece
`UNAVAILABLE — NOT USED`.

```text
OPERATION_STATUS=STOPPED
FINAL_STATUS=STOP_DOCUMENTED
LAST_SUCCESSFUL_GATE=TASK9_PROJECT_PREFLIGHT_AND_IMPLEMENTATION_PUBLICATION
FAILED_GATE=TASK9_SINGLE_SEVEN_FIELD_PROJECT_PATCH_READBACK
DEDICATED_MOBILE_BFF_STATUS=IMPLEMENTED_NOT_DEPLOYED
STAGING_BFF_STATUS=NOT_VERIFIED
CI3_DOCUMENTATION_STATUS=NOT_AUTHORIZED
VERCEL_PROJECT_SETTINGS_PATCH_ATTEMPTS=1
VERCEL_PREVIEW_ENV_BATCH_ATTEMPTS=0
VERCEL_LOCAL_LINK_ATTEMPTS=0
VERCEL_PREVIEW_DEPLOYMENT_ATTEMPTS=0
VERCEL_PROJECT_SSO_DISABLE_ATTEMPTS=0
VERCEL_PROJECT_SSO_ROLLBACK_ATTEMPTS=0
PRODUCTION_DEPLOYMENT=NO
CI3_AUTHORIZED=NO
CI4=NO
NEXT_ENVIRONMENT=VPS
NEXT_GATE=RECONCILE_VERCEL_SKIP_GIT_CONNECT_DURING_LINK_SCHEMA
```

O próximo gate deve reconciliar o schema oficial de
`skipGitConnectDuringLink`, preservar o budget de zero retry já consumido e
decidir como validar a ausência de Git Integration antes de qualquer novo env
batch, link ou deployment. Esta atualização não executa esse gate.

Evidência detalhada:
`docs/superpowers/evidence/2026-08-25-ci3-dedicated-mobile-bff-stop.md`.

## 46. Atualização operacional 1.6.10 — reconciliação do controle Vercel de vínculo Git local

**Data:** 26/08/2026

A reconciliação read-only usou Vercel CLI 50.35.0, seu OpenAPI autenticado
atual, ajuda da CLI, implementação instalada, documentação oficial e Project
GET sanitizado. O cache OpenAPI atualizado em 26/08/2026 tem SHA-256
`dc9b5aa7e80f74d96f5bdc57e322a5b1fcd4405ee0bb6c8d6e42cb6d7caf62e3`.

`PATCH /v9/projects/{idOrName}` aceita
`skipGitConnectDuringLink` como boolean opcional, não nullable e explicitamente
deprecated. A descrição limita o campo ao opt-out da mensagem da CLI que
oferece conectar Git durante `vercel link`. PATCH response e Project GET
podem conter o campo, mas não o incluem nas listas `required`; não há promessa
de echo ou persistência obrigatória. O Project GET expõe separadamente o objeto
opcional `link`, com as formas concretas dos providers Git.

A CLI atual confirma que `vercel link --project` liga o diretório local a um
projeto existente. `vercel git connect` é a operação separada que conecta um
repositório, e `vercel link --repo` é um fluxo distinto que requer Git
Integration. No código instalado, o vínculo de um projeto existente retorna
após escrever a metadata local e não chama a conexão Git. O bundle da CLI não
consome mais `skipGitConnectDuringLink`.

O OpenAPI autenticado atual não lista um endpoint separado de Git Integration,
mas a implementação instalada da CLI usa explicitamente
`POST /v9/projects/{projectId}/link` para conectar e
`DELETE /v9/projects/{projectId}/link` para desconectar. Isso confirma a
separação material sem autorizar ou executar nenhuma dessas operações.

A classificação aprovada é:

```text
LINK_CONTROL_CLASSIFICATION=FIELD_REMOVED_OR_IGNORED_WITH_MATERIAL_GIT_LINK_ABSENT
```

Duas revisões independentes concluíram GO, cada uma com 0 Critical,
0 Important e 0 Minor. O projeto continua com o fingerprint esperado, seis
settings persistentes corretos, `skipGitConnectDuringLink` ausente/null,
`link` ausente/null, zero Git Integration, zero env, zero deployment, zero
custom domain e SSO `all_except_custom_domains`.

Consequências vinculantes:

- o PATCH de settings permanece consumido em 1/1 e nunca será repetido;
- o antigo gate de echo do campo deprecated está `SUPERSEDED`;
- o estado material é Project `link` ausente antes e depois do vínculo local;
- o vínculo local será uma única chamada explícita a `vercel link`, com
  `--yes`, `--project agentempp-mobile-bff-staging` e scope existente
  `gestao-9664s-projects`;
- `--repo`, `vercel git connect` e `vercel git disconnect` permanecem
  proibidos;
- `.vercel/project.json` deve corresponder ao fingerprint do projeto e ao
  scope, sem token, secret ou env;
- o deployment Preview único usará metadata declarativa
  `githubCommitSha=e3e1e252b48e42554e75899b950692c05186f60d`, combinada com
  worktree detached limpa, SHA/tree e receipts; a metadata isolada não é
  tratada como vínculo criptográfico;
- nenhuma nova escrita Vercel pode começar antes da publicação remota desta
  autoridade.

Budgets novos após a autoridade remota:

```text
DEDICATED_DEPLOY_WORKTREE_CREATION_ATTEMPTS=1
VERCEL_LOCAL_LINK_ATTEMPTS=1
VERCEL_PREVIEW_ENV_BATCH_ATTEMPTS=1
VERCEL_PREVIEW_DEPLOYMENT_ATTEMPTS=1
VERCEL_PROJECT_SSO_DISABLE_ATTEMPTS=1
VERCEL_PROJECT_SSO_ROLLBACK_ATTEMPTS=1
FINAL_DOCUMENTATION_COMMIT_ATTEMPTS=1
FINAL_DOCUMENTATION_PUSH_ATTEMPTS=1
```

Produção, CI-4, settings PATCH, Git Integration, custom domain, Production env,
Production deployment, Supabase/database write, PR e merge continuam
proibidos. CI-3 ainda não está autorizada. A continuação depende do commit
documental remoto desta atualização.

## 47. Atualização operacional 1.6.11 — STOP no batch Preview do Mobile BFF

**Data:** 26/08/2026

A autoridade de local-link foi publicada e confirmada remotamente em
`fb1e0a3b76b831976f1e8b7f129758405b42e694`. O preflight pós-autoridade
preservou o baseline histórico `25/5/20`, confirmou a implementação limpa e
publicada em `e3e1e252b48e42554e75899b950692c05186f60d`, a worktree CI-2
intocada e a fonte de staging pelos hashes já autorizados, sem abrir ou usar a
fonte primária.

A worktree exclusiva
`/root/agentempp-ci3-dedicated-mobile-bff-deploy-v1` foi criada detached no SHA
da implementação, tree `a167a6663cb1e476975742bcec51c7207dbcbc26`, limpa e sem
branch/upstream. O único `vercel link` local autorizado ligou esse diretório ao
projeto existente sem `--repo`. `.vercel/project.json` é regular, local,
ignored, mode `0600`, contém somente `orgId`, `projectId` e `projectName` e
corresponde ao fingerprint/scope esperados. Project GET permaneceu com `link`
ausente, zero Git Integration, env zero, deployments zero, settings íntegros e
SSO `all_except_custom_domains`.

O primeiro disparo local do executor JavaScript falhou antes da API porque o
pathname sem shebang foi interpretado como shell. A investigação comprovou
env remoto zero; portanto isso não consumiu o budget Vercel. A invocação
corrigida explicitamente com Node realizou a única tentativa real do batch
Preview e o cliente Vercel retornou exit 1. O diagnóstico foi reduzido ao
SHA-256 `e71d492d1abf97ecf9d984116c77e83470ef08214c21805a6f6085a6528e01cf`;
nenhum valor ou resposta sensível foi persistido ou exibido.

Readback imediato após a falha:

```text
VERCEL_PREVIEW_ENV_BATCH_ATTEMPTS=1/1
VERCEL_ENV_TOTAL=0
VERCEL_PREVIEW_ENV_COUNT=0
VERCEL_PRODUCTION_ENV_COUNT=0
VERCEL_DEVELOPMENT_ENV_COUNT=0
VERCEL_PROJECT_GIT_LINK=ABSENT
VERCEL_GIT_INTEGRATION=NO
VERCEL_DEPLOYMENT_COUNT=0
PROJECT_SSO=all_except_custom_domains
```

O contrato fail-closed proíbe retry ou delete após uma tentativa externa
falha. Por isso deployment, inspeção protegida, SSO forward/rollback, probes,
receipt e descoberta de paciente não foram executados. O executor temporário
foi removido; a worktree dedicada e a metadata local foram preservadas para
auditoria. Produção, primary/live, Supabase/database, CI-4, PR e merge seguem
intocados.

```text
FINAL_STATUS=STOP_DOCUMENTED
DEDICATED_MOBILE_BFF_STATUS=IMPLEMENTED_NOT_DEPLOYED
STAGING_BFF_STATUS=NOT_VERIFIED
CI3_DOCUMENTATION_STATUS=NOT_AUTHORIZED
NEXT_ENVIRONMENT=VPS
NEXT_GATE=RECONCILE_VERCEL_PREVIEW_ENV_BATCH_CLIENT_FAILURE_WITH_ZERO_REMOTE_ENV
```

Esse próximo gate deve ser uma nova autoridade read-only para diagnosticar o
contrato cliente/API usando somente schema, implementação instalada e estado
remoto zero; não pode repetir o batch sem autorização documental separada.

## 48. Atualização operacional 1.6.12 — reconciliação do cliente Vercel para o batch Preview

A investigação read-only do STOP 1.6.11 terminou fail-closed. O executor
temporário antigo foi removido como previsto e seu source/argv/erro bruto não
existe nas fontes sanitizadas permitidas. Foram preservados somente o hash do
executor `e41caa1…5867e`, o hash diagnóstico `e71d492…01cf`, JSON via stdin,
a invocação explícita com Node, client exit 1 e executor exit 78. A evidência
ausente não foi reconstruída por hipótese.

Vercel CLI 50.35.0 e seu source instalado provam que `--input -` lê stdin até
EOF; uma validação sintética sem rede também passou. O OpenAPI autenticado,
atualizado em 2026-08-26, prova `POST /v10/projects/{idOrName}/env`, body objeto
ou array, os tipos `encrypted`/`sensitive`, target `preview` e sucesso HTTP 201.
Os probes atuais com child env mínimo passaram para `whoami`, Project GET e
Env GET. Assim, stdin/path e o contexto atual de HOME/auth/scope não explicam
a falha histórica.

O mesmo source revela retries internos padrão (`retries=3`) e parsing não
limitado do request/response, sem flag do comando `api` para desativar o retry.
Isso também impede aprovar o mecanismo de arquivo temporário sob o contrato
vigente de uma única tentativa, sem retry automático e com limites de bytes.
As duas revisões independentes terminaram GO em 0 Critical / 0 Important / 0
Minor após um microdelta puramente enumerativo.

```text
ROOT_CAUSE_PRIMARY=UNRESOLVED
ROOT_CAUSE_SECONDARY=CLIENT_RUNTIME_EXECUTION_ERROR
ROOT_CAUSE_SECONDARY_DETAIL=UNCLASSIFIED
ENV_BATCH_RETRY_AUTHORIZED=NO
CORRECTED_MECHANISM=NOT_AUTHORIZED
VERCEL_PREVIEW_ENV_BATCH_HISTORICAL_ATTEMPTS=1/1
VERCEL_PREVIEW_ENV_BATCH_RETRY_ATTEMPTS=0/0_NOT_ACTIVATED
VERCEL_PREVIEW_DEPLOYMENT_ATTEMPTS=0
VERCEL_PROJECT_SSO_DISABLE_ATTEMPTS=0
VERCEL_PROJECT_SSO_ROLLBACK_ATTEMPTS=0
VERCEL_ENV_TOTAL=0
VERCEL_PREVIEW_ENV_COUNT=0
VERCEL_PRODUCTION_ENV_COUNT=0
VERCEL_DEVELOPMENT_ENV_COUNT=0
VERCEL_DEPLOYMENT_COUNT=0
VERCEL_PROJECT_GIT_LINK=ABSENT
PROJECT_SSO_FINAL=all_except_custom_domains
STAGING_SECRET_OPENED=NO
PRIMARY_SECRET_OPENED=NO
STAGING_BFF_STATUS=NOT_VERIFIED
CI3_DOCUMENTATION_STATUS=NOT_AUTHORIZED
PRODUCTION=UNTOUCHED
CI4=NOT_STARTED
NEXT_ENVIRONMENT=VPS
NEXT_GATE=RECONCILE_VERCEL_ENV_CLIENT_DIAGNOSTIC_EVIDENCE
```

Nenhum batch foi repetido, nenhum secret foi aberto, nenhum env foi criado ou
apagado e nenhum deployment, SSO, Supabase, banco, produção ou CI-4 foi
alterado. A continuidade exige nova evidência diagnóstica que preserve uma
classificação sem dados brutos e defina um transporte que consiga provar uma
única requisição antes de qualquer novo budget.

## 49. Atualização operacional 1.6.13 — transporte Vercel one-shot com evidência diagnóstica durável

A causa semântica do exit histórico do cliente permanece irrecuperável e não
decisiva. O executor, argv e erro bruto removidos não foram inventados nem
reconstruídos. O estado remoto continuou zero. O bloqueio material passou a ser
tratado pela substituição do cliente mutável, não por uma alegação de causa.

O transporte V1 root-only usa `node:https` contra a origem fixa da API Vercel,
um request por operação, zero retry, limites de bytes, timeout, TLS e zero
redirect. Source/test congelados fora do Git:

```text
TRANSPORT_SOURCE_SHA256=b21520e29d260a01cecff1bad17d5f05fb50bffd976aa664afec53bed36d06df
TRANSPORT_TEST_SHA256=fb5a222849adb3e6902dcc5015acf3608cf194ec5dd0103200f84abb621b6198
SOURCE_TEST_MODE=0400
SELF_TESTS=30/30_PASS
SOURCE_SCAN_RECEIPT_SHA256=8028ad56755f44f5173ec5f669ad1c285257cd695c1ee02dc088b2f0350ac877
```

O preflight real executou somente Project GET e Env GET: ambos HTTP 200,
request count 1, retry 0. Root `apps/mobile-bff`, Node `22.x`, framework
`nextjs`, build/install e outside-root conferem; link está ausente, SSO ativo,
deployments 0 e env `0/0/0`. O receipt sanitizado tem SHA-256
`25bb55fe10141d275a7fea582d3aedbb47712e711a4137b74513e65c80c0c539`.
Staging e primary/live não foram abertos; token e values não foram reportados.

As revisões finais ficaram em 0 Critical / 0 Important: Review A também ficou
em 0 Minor; Review B registrou dois Minors não bloqueantes, cobertos pela
evidência externa de modo/ausência de marcador ACL e pelo predicado
conservador de rollback documentado na evidência dedicada.

A circularidade do source receipt foi resolvida documentalmente: este commit
publica primeiro os hashes congelados. O receipt permanece
`PENDING_POST_PUSH_BINDING` e só pode ser criado uma vez, atomicamente, depois
do push fast-forward e da confirmação do SHA remoto. Ele deve ligar esse SHA
aos hashes publicados. Modos mutáveis seguem bloqueados até manager/remoto,
receipt, hashes e modos `0400` coincidirem.

```text
HISTORICAL_ROOT_CAUSE=UNRECOVERABLE_NON_DECISIVE
DIAGNOSTIC_EVIDENCE_STATUS=RECONCILED_BY_DURABLE_ONE_SHOT_RECEIPT
VERCEL_CLI_MUTATING_USE=SUPERSEDED_FOR_ENV_AND_SSO
CORRECTED_TRANSPORT=BOUNDED_NODE_HTTPS_ONE_SHOT_V1
ENV_BATCH_RETRY_AUTHORIZED=YES_ONE_SHOT_NEW_TRANSPORT
SOURCE_RECEIPT_STATUS=PENDING_POST_PUSH_BINDING
ONE_SHOT_TRANSPORT_DOCUMENTATION_COMMIT_ATTEMPTS=1
ONE_SHOT_TRANSPORT_DOCUMENTATION_PUSH_ATTEMPTS=1
VERCEL_PREVIEW_ENV_ONE_SHOT_ATTEMPTS=1
VERCEL_PREVIEW_DEPLOYMENT_ATTEMPTS=1
VERCEL_PROJECT_SSO_FORWARD_ONE_SHOT_ATTEMPTS=1
VERCEL_PROJECT_SSO_ROLLBACK_ONE_SHOT_ATTEMPTS=1
PRODUCTION=UNTOUCHED
CI3_DOCUMENTATION_STATUS=NOT_AUTHORIZED
CI4=NOT_STARTED
NEXT_ENVIRONMENT=VPS
NEXT_GATE=BIND_ONE_SHOT_SOURCE_RECEIPT_AND_REVALIDATE_PHASE_E
```

Os dois budgets `ONE_SHOT_TRANSPORT_DOCUMENTATION_*` estão ativos pela
autoridade desta operação. Os budgets Vercel e de documentação final acima só
se tornam ativos após confirmação remota do commit de autoridade.

Nenhum POST, deployment, SSO, Supabase/database write, produção, CI-3 ou CI-4
foi executado nesta atualização. Settings PATCH, local link, projeto e
tentativa CLI histórica continuam fechados e não recebem novo budget. Falha no
commit ou push desta autoridade encerra `STOP_PRE_AUTHORITY`, sem source
receipt, leitura de staging ou POST.

## 50. Atualização operacional 1.6.14 — STOP no review final do env one-shot

A autoridade V1 foi publicada e vinculada corretamente. O commit local/remoto
`af03a01be7103fa63254da4e95de8b19cc6d78d4` confirmou os hashes congelados, e o
source receipt root-only `0600` foi criado uma única vez com SHA-256
`8a981c2c895c2d42f63bde6aefa25e5ae127ac5450f59c13315c102e4d2fbbb8`.
A Phase E revalidou o manager com os 25 itens históricos, as três worktrees
exatas e limpas, source/test `0400`, receipts congelados, ausência de claims e
receipts mutáveis e a fonte staging com três entradas/fingerprints exatos. Os
valores brutos não foram reportados e a fonte primary/live não foi aberta.

O review read-only final obrigatório divergiu: um revisor registrou GO
`0 Critical / 0 Important / 0 Minor`; o outro registrou NO-GO
`0 Critical / 1 Important / 0 Minor`. A inspeção direta confirmou o Important:
o V1 persiste a evidência do POST, mas retorna antes do GET de inventário quando
o resultado mutável é timeout, socket error, HTTP diferente de 201 ou resposta
parcial. Nesse estado ambíguo, o transporte impede corretamente qualquer retry,
porém não consegue provar se o remoto ficou com zero, uma ou duas, ou as três
variáveis. Isso contradiz a classificação honesta e fail-closed exigida pela
autoridade. Como qualquer Important bloqueia o POST, a tentativa não foi
consumida.

Estado do STOP:

```text
VERCEL_ENV_DIAGNOSTIC_EVIDENCE_STATUS=RECONCILED
VERCEL_ONE_SHOT_TRANSPORT_STATUS=AUTHORIZED_NOT_EXECUTED
VERCEL_PREVIEW_ENV_BATCH_STATUS=NOT_EXECUTED
VERCEL_PREVIEW_ENV_COUNT=0
VERCEL_PRODUCTION_ENV_COUNT=0
VERCEL_DEVELOPMENT_ENV_COUNT=0
ENV_ONE_SHOT_REQUESTS=0/1
ENV_CLAIM=ABSENT
ENV_ATTEMPT_RECEIPT=ABSENT
PREVIEW_DEPLOYMENTS=0/1
SSO_FORWARD_ATTEMPTS=0/1
SSO_ROLLBACK_ATTEMPTS=0/1
SSO_FINAL=ALL_EXCEPT_CUSTOM_DOMAINS
DEDICATED_MOBILE_BFF_STATUS=IMPLEMENTED_NOT_DEPLOYED
STAGING_BFF_STATUS=NOT_VERIFIED
CI3_DOCUMENTATION_STATUS=NOT_AUTHORIZED
PRODUCTION=UNTOUCHED
CI4=NOT_STARTED
NEXT_ENVIRONMENT=VPS
NEXT_GATE=RECONCILE_VERCEL_ENV_ONE_SHOT_AMBIGUOUS_POST_READBACK
```

Nenhum POST, deployment, SSO forward/rollback ou probe foi executado. Nenhum
claim ou receipt mutável foi criado. O projeto Preview permanece com o último
inventário read-only confirmado `0/0/0`, zero deployments, Project link ausente
e proteção SSO ativa. O helper/test V1 e todos os receipts permanecem
preservados e não podem ser modificados. A retomada exige uma nova versão em
novo path e uma nova autoridade que desenhe e prove um protocolo read-only
limitado de estabilização/quiescência após timeout, socket error, non-201 ou
resultado parcial. Um GET imediato isolado não basta, pois o POST remoto pode
concluir depois desse snapshot. A autoridade deve fixar budgets de GET,
condições de estabilidade e classificação inconclusiva, sempre sem um segundo
POST, além de novos testes, hashes, receipts e publicação remota.

## 51. Atualização operacional 1.6.15 — três upserts Preview com objeto JSON simples

**Data:** 27/08/2026

A investigação do transporte histórico confirmou que o batch em array é
inválido no Vercel CLI 50.35.0: arrays não entram no caminho de serialização
JSON do cliente. Nenhum POST real foi executado pelas reconciliações
posteriores e o inventário remoto continua Preview/Production/Development
`0/0/0`, com zero deployments e SSO original ativo.

O caminho de objeto JSON simples foi comprovado read-only. O CLI lê stdin,
aplica `JSON.parse`, reconhece um objeto cujo construtor é `Object`, serializa
com `JSON.stringify` e envia `Content-Type: application/json`. O OpenAPI
oficial aceita um único objeto, `upsert=true`, tipos `encrypted` e `sensitive`
e target `preview`. Um teste sintético sem rede aprovou três objetos e rejeitou
array. Duas revisões independentes aprovaram o desenho em 0 Critical,
0 Important e 0 Minor.

Esta autoridade cria exatamente três operações lógicas sequenciais, uma por
chave: URL pública, chave pública anônima e chave de serviço. Cada operação usa
um único objeto com somente `key`, `value`, `type` e `target:[preview]`. Os
retries internos do CLI são aceitos apenas dentro da mesma invocação lógica,
com conteúdo idêntico e `upsert=true`. Uma segunda invocação lógica para a
mesma chave é proibida.

Antes de cada invocação, um claim exclusivo e durável deve registrar o budget
consumido sem conter valor. Depois de cada invocação, Env GET sem decrypt deve
produzir três snapshots idênticos em +15, +30 e +60 segundos. A sequência só
avança com inventário exato: `1/0/0`, depois `2/0/0`, depois `3/0/0`, tipos e
targets corretos e nenhuma chave inesperada. Estado zero, parcial, duplicado,
errado, oscilante ou inconclusivo termina em STOP sem retry externo, segunda
invocação, correção ou delete. Exit não zero só pode ser aceito como
`COMMAND_AMBIGUOUS_REMOTE_VERIFIED` quando os três readbacks provarem o estado
remoto exato e estável.

V1, V2, V3 e V4 permanecem preservados e não podem ser modificados ou
executados. Os descritores SSO forward, rollback e original foram revalidados
por metadata, hash e schema, sem alteração. O secret primary/live permanece
proibido. Esta etapa autoriza apenas Preview, zero Production/Development,
zero Supabase/database write e zero CI-4.

Somente depois do inventário `3/0/0` estável poderá ocorrer um único deploy
Preview protegido, seguido de inspeção e uma operação lógica de SSO forward.
Os readbacks do forward em +10/+20/+40 devem ser estáveis; qualquer divergência
nessa fase termina em STOP sem segundo forward e sem rollback. Somente depois
do forward comprovado os probes públicos são executados. Se qualquer probe
falhar, uma única operação lógica de rollback é autorizada, seguida dos
readbacks do objeto original e sem reprobe.

Outcomes:

Os três contratos abaixo supersedem integralmente todas as allowlists,
versões, subjects e instruções finais históricas, inclusive as do Task 15 de
25/08. Nenhuma allowlist histórica permanece executável para esta operação.

- `PASS_COMPLETE`: BFF/probes aprovados, caminho de paciente sintético
  `VERIFIED` e Today `PASS` ou `DEFERRED_TO_MAC_BY_DESIGN`; atualizar
  `1.6.15→1.7` em exatamente
  `docs/handoffs/2026-08-20-better-ahead-contexto-completo-e-finalizacao.md`,
  `docs/superpowers/evidence/2026-08-27-ci3-dedicated-mobile-bff-authority.md`,
  `docs/superpowers/plans/2026-08-20-naming-neutral-core-integration.md`,
  `docs/superpowers/specs/2026-08-27-ci3-today-staging-vertical-slice.md` e
  `docs/superpowers/plans/2026-08-27-ci3-today-staging-vertical-slice.md`; parent
  `SINGLE_OBJECT_AUTHORITY_SHA`; assunto
  `docs(ios): authorize CI-3 after dedicated Mobile BFF verification`; um
  commit/push; gerar o macro-prompt integral do Mac; autorizar CI-3 e manter
  CI-4 proibida.
- `PASS_PARTIAL`: BFF/probes aprovados e paciente sintético `MISSING`; atualizar
  `1.6.15→1.6.16` em exatamente
  `docs/handoffs/2026-08-20-better-ahead-contexto-completo-e-finalizacao.md`,
  `docs/superpowers/evidence/2026-08-27-ci3-dedicated-mobile-bff-preview-verification.md`
  e `docs/superpowers/plans/2026-08-20-naming-neutral-core-integration.md`;
  parent `SINGLE_OBJECT_AUTHORITY_SHA`; assunto
  `docs(staging): record verified dedicated Mobile BFF preview`; um
  commit/push; gerar `AUTHORIZE_SYNTHETIC_STAGING_PATIENT_PROVISIONING`, sem
  criar usuário; preservar Preview e manter CI-3 não autorizada.
- `STOP_DOCUMENTED`: qualquer divergência depois desta autoridade; atualizar
  `1.6.15→1.6.16` em exatamente
  `docs/handoffs/2026-08-20-better-ahead-contexto-completo-e-finalizacao.md`,
  `docs/superpowers/evidence/2026-08-27-ci3-single-object-env-or-mobile-bff-stop.md`
  e `docs/superpowers/plans/2026-08-20-naming-neutral-core-integration.md`;
  parent `SINGLE_OBJECT_AUTHORITY_SHA`; assunto
  `docs(staging): record single-object Preview env or Mobile BFF stop`; um
  commit/push; registrar chave/gate, contagem lógica, exit, modelo de retries,
  readbacks, estado final de env, deployment/SSO/probes, zero segunda
  invocação/delete, recursos preservados, produção intocada, CI-3 não
  autorizada e próximo gate exato.

Para qualquer outcome final: staging inicial vazio, allowlist exata,
`git diff --check`, diff integral, scan de token/fingerprint/secret/raw
origin/raw ID/PII, zero Production, zero CI-4, duas revisões em zero
Critical/Important, staging seletivo sem histórico, parent exato, um commit e
um push sem force, tags, PR ou merge.

```text
VERCEL_JSON_ARRAY_TRANSPORT=REJECTED
VERCEL_SINGLE_PLAIN_OBJECT_TRANSPORT=SUPPORTED
VERCEL_INTERNAL_RETRIES=ACCEPTED_PER_LOGICAL_KEY_UPSERT
SINGLE_OBJECT_AUTHORITY_COMMIT_ATTEMPTS=1
SINGLE_OBJECT_AUTHORITY_PUSH_ATTEMPTS=1
VERCEL_ENV_LOGICAL_INVOCATIONS_MAX=3
VERCEL_ENV_LOGICAL_INVOCATIONS_PER_KEY_MAX=1
VERCEL_ENV_SECOND_LOGICAL_INVOCATION=FORBIDDEN
VERCEL_ENV_DELETE=FORBIDDEN
PRODUCTION=UNTOUCHED
CI4=NOT_STARTED
```

Evidência detalhada:
`docs/superpowers/evidence/2026-08-27-ci3-vercel-single-object-upsert-authority.md`.

## 52. Atualização operacional 1.6.16 — STOP por deployment classificado como Production

**Data:** 27/08/2026

As três variáveis autorizadas foram publicadas individualmente e estabilizadas
em Preview. Cada chave consumiu exatamente uma invocação lógica, todas
terminaram com exit code 0 e não houve retry externo, segunda invocação,
correção ou delete. Os três readbacks de cada etapa, em +15, +30 e +60,
confirmaram a progressão exata `1/0/0`, `2/0/0` e `3/0/0` para
Preview/Production/Development. Os retries internos do Vercel CLI 50.35.0
permaneceram limitados à mesma requisição idempotente com `upsert=true`.

O único deployment autorizado foi então invocado sem `--prod`, sem alias,
domínio, promoção, redeploy ou conexão Git. O comando terminou com exit code 0
e o deployment ficou `READY`, com o SHA de origem esperado. Porém tanto
`vercel inspect` quanto uma leitura independente pela API oficial classificaram
o target remoto como `production`, e não `preview`. Esse resultado viola o
gate material de ambiente e encerra a operação em `STOP_DOCUMENTED`.

Não houve segunda tentativa de deploy, promoção, alias, delete, SSO forward,
rollback ou probe. O SSO original permanece ativo; os três claims, o lock da
operação, os testes, a fonte/receipt de staging e a evidência root-only do
deployment foram preservados. O emissor, o runner e o diretório temporário
vazio foram removidos somente depois do settlement `3/0/0`, conforme a
autoridade. O secret primary/live não foi aberto, Supabase e banco não foram
alterados, e CI-4 não começou.

Para manter a verdade operacional: `PRODUCTION_UNTOUCHED=NO`. Nenhuma mutação
de Production foi solicitada pelo comando, mas a Vercel criou um artefato
remoto classificado como Production. Ele foi preservado porque esta autoridade
não concede delete, rollback ou outra recuperação. CI-3 continua não
autorizada. O próximo gate exato é
`RECONCILE_UNEXPECTED_VERCEL_PRODUCTION_TARGET_AND_AUTHORIZE_RECOVERY`, na VPS.

Evidência completa:
`docs/superpowers/evidence/2026-08-27-ci3-single-object-env-or-mobile-bff-stop.md`.

## 53. Atualização operacional 1.6.17 — recuperação autorizada do bootstrap Production

**Data:** 27/08/2026

O STOP 1.6.16 foi reconciliado sem alterar o projeto remoto. A documentação
geral atual da Vercel descreve `vercel deploy` sem `--prod` como Preview, mas o
registro oficial do default production domain e uma referência Vercel Labs
atual documentam a exceção: o primeiro deployment de um projeto novo criado ou
vinculado pela CLI inicializa Production; os seguintes retornam ao fluxo
Preview. O cliente 50.35.0 instalado também converte o target literal
`preview` no default da API, tornando o readback remoto — e não o argumento ou
o exit code — a prova material do target.

O estado read-only continua exato: env Preview/Production/Development `3/0/0`,
um único deployment `production`, `READY` e no source SHA dedicado
`e3e1e252b48e42554e75899b950692c05186f60d`; dois aliases gerados pela
plataforma, zero domínio customizado, zero custom environment, Project link
ausente e SSO `all_except_custom_domains`. O projeto tinha zero deployments
antes da tentativa congelada; não houve `--prod`, promoção, alias command,
custom domain, Git Integration ou env Production. Primary/live, Supabase,
banco e CI-4 permanecem intocados.

```text
VERCEL_FIRST_DEPLOYMENT_CLASSIFICATION=FIRST_CLI_DEPLOYMENT_BOOTSTRAP_PRODUCTION
DOCUMENTATION_CONFLICT=GENERAL_PREVIEW_DEFAULT_VS_FIRST_DEPLOYMENT_BOOTSTRAP
RECOVERY_ORDER=CREATE_AND_VERIFY_PREVIEW_THEN_DELETE_BOOTSTRAP_PRODUCTION
VERCEL_STAGING_PROJECT_PRODUCTION_TARGET_TOUCHED=YES
PRIMARY_LIVE_PRODUCT_PRODUCTION_TOUCHED=NO
```

A recuperação é estritamente bounded. Depois desta authority estar publicada
remotamente, pode existir uma única segunda tentativa com target explicitamente
Preview e metadata do source SHA. Se o readback não provar simultaneamente
`target=preview`, `READY` e o SHA exato, a execução para, não cria terceiro
deployment e não remove nada. Somente um Preview distinto e integralmente
verificado ativa uma única remoção do ID exato do bootstrap Production; URL,
project name, wildcard, remoção do Preview, projeto, env ou domínio permanecem
proibidos. Readbacks em +10/+20/+40 devem terminar com exatamente um Preview,
zero Production, env `3/0/0`, aliases do original ausentes e SSO ainda ativo.

SSO permanece ativo durante Preview, inspeção protegida, remoção, settlement e
Review C. Imediatamente antes do único forward, o objeto remoto precisa ser
estrutural e canonicamente igual ao descritor original congelado; uma
classificação genérica “ativo” não basta. Se o forward ou seus readbacks forem
ambíguos, o objeto original exato termina em STOP sem rollback, `null` consome
a única tentativa compartilhada de rollback e estado não determinável termina
em `SSO_STATE=UNRESOLVED` sem nova mutação. O mesmo budget atende eventual
falha dos probes públicos e nunca pode ser consumido duas vezes.

Os receipts com identidades brutas permanecem root-only fora do Git. Esta
authority registra apenas o receipt do incidente por SHA-256
`dae421f7a86897ca16cc09d4a52590bf451a0017695ffc6c7aad8879d6065813`.
As revisões independentes A e B aprovaram o desenho final com zero Critical,
zero Important e zero Minor. A execução continua sem alterar settings, envs,
Git Integration, Supabase, banco, primary/live ou CI-4 e sem PR, merge ou tag.

Autoridade detalhada:
`docs/superpowers/evidence/2026-08-27-ci3-first-deployment-production-recovery-authority.md`.

## 54. Atualização operacional 1.6.18 — BFF dedicado verificado, paciente sintético ausente

**Data:** 27/08/2026

A recuperação bounded do primeiro deployment foi concluída. A única segunda
tentativa usou `--target=preview`, ficou `READY` no source SHA dedicado
`e3e1e252b48e42554e75899b950692c05186f60d` e foi classificada honestamente
como Preview pelo predicado composto congelado: CLI `preview`, API wire
`target=null` e nunca `production`. A CLI 50.35.0 normaliza o target literal
Preview para target omitido antes da API; duas revisões independentes
aprovaram essa equivalência contextual com zero Critical/Important.

Com o Preview distinto e íntegro, a única remoção autorizada do ID do bootstrap
Production foi consumida. O comando terminou com exit 0 e os readbacks
+10/+20/+40 provaram original ausente, aliases zero, Production `0`, Preview
semântico `1`, total `1`, env Preview/Production/Development `3/0/0`, Project
link ausente e SSO ainda ativo. Não houve terceiro deployment, segundo delete,
remoção do Preview/projeto/env/domínio ou custom domain.

Review C aprovou o ingress dedicado com 0 Critical e 0 Important. Os manifests
provam 40 Mobile API routes, zero admin routes, zero pages autorais, zero
Server Actions e zero middleware. A inspeção protegida passou. O único forward
SSO autorizado retornou HTTP 200; os três snapshots estabilizaram em
`ssoProtection=null`, Production `0`, Preview `1` READY e env `3/0/0`.
Rollback permaneceu `0/1`. Os probes públicos passaram 30/30: três contratos
Mobile 401, oito rotas proibidas base e os 19 achados congelados em 404, sem
redirect, stack, secret ou PII.

O receipt final do deployment foi publicado fora do Git, root:root 0600, SHA-256
`f9f2b8cdb4aaa066ceb5ec73978f32d8710c434a9582b68ed9b1375096ce60b6`.
O origin bruto existe somente nele. TEAM_DEFAULT_MUTATION_REQUESTS permaneceu
zero e TEAM_DEFAULT_LIVE_STATE não foi observado.

A descoberta posterior foi somente leitura no Supabase staging. O inventário
retornou zero usuários Auth, zero identidade explicitamente sintética elegível
e zero mecanismo de credencial runtime aprovado. Nenhum usuário, profile,
senha, confirmação, token ou dado foi criado ou alterado; PII não foi
reportada. O service role staging autorizou apenas os GETs de inventário e não
foi usado como bearer runtime de paciente; primary/live não foi aberto. Logo:

```text
FINAL_STATUS=PASS_PARTIAL
VERCEL_FIRST_DEPLOYMENT_CLASSIFICATION=FIRST_CLI_DEPLOYMENT_BOOTSTRAP_PRODUCTION
VERCEL_BOOTSTRAP_PRODUCTION_RECOVERY=VERIFIED
VERCEL_ORIGINAL_PRODUCTION_DEPLOYMENT=REMOVED
VERCEL_ACTIVE_PRODUCTION_DEPLOYMENT_COUNT=0
VERCEL_ACTIVE_PREVIEW_DEPLOYMENT_COUNT=1
VERCEL_RECOVERY_PREVIEW_TARGET=VERIFIED
VERCEL_PREVIEW_ENV_COUNT=3
VERCEL_PRODUCTION_ENV_COUNT=0
VERCEL_DEVELOPMENT_ENV_COUNT=0
PRIMARY_LIVE_PRODUCT_PRODUCTION_TOUCHED=NO
DEDICATED_MOBILE_BFF_STATUS=VERIFIED
STAGING_BFF_STATUS=VERIFIED
SYNTHETIC_PATIENT_PATH=MISSING
CI3_DOCUMENTATION_STATUS=NOT_AUTHORIZED
NEXT_ENVIRONMENT=VPS
NEXT_GATE=AUTHORIZE_SYNTHETIC_STAGING_PATIENT_PROVISIONING
```

O Preview público verificado deve ser preservado. CI-3 continua não autorizada
porque falta a identidade sintética. A próxima operação é exclusivamente
documental: deve redigir, revisar e publicar a autoridade bounded para uma
futura execução provisionar exatamente uma conta staging explicitamente
sintética, confirmada, patient-role, ativa, não admin/bloqueada/deletada, com
mecanismo de credencial aprovado e token runtime de paciente — nunca bearer de
service role — e então parar antes de qualquer criação. CI-4, primary/live,
produção do produto, TestFlight e App Store permanecem proibidos.

Evidência completa:
`docs/superpowers/evidence/2026-08-27-ci3-dedicated-mobile-bff-preview-verification.md`.

## 55. Atualização operacional 1.6.19 — autoridade bounded do paciente sintético de staging

**Data:** 28/08/2026

Esta atualização é exclusivamente documental. O BFF dedicado verificado em
1.6.18 permanece preservado: implementação
`e3e1e252b48e42554e75899b950692c05186f60d`, um Preview semântico READY,
Production `0`, env Preview/Production/Development `3/0/0`, SSO `null` e
probes públicos `30/30`. Nenhum deployment, setting, env, SSO, domínio ou alias
foi alterado. O origin bruto continua somente no receipt root-only de SHA-256
`f9f2b8cdb4aaa066ceb5ec73978f32d8710c434a9582b68ed9b1375096ce60b6`.

A inspeção read-only do source e do schema staging confirmou que Auth user e
patient bootstrap não bastam para um Today 200. `/me` é entitlement-exempt e
é o caminho canônico de bootstrap; `/today` exige uma decisão ativa para a key
técnica `bodyflow_full`. O staging continuou vazio: Auth users `0`, patients
sintéticos `0`, entitlements sintéticos ativos `0` e credenciais runtime
aprovadas `0`.

A authority futura congela:

- uma única identidade `ci3-synthetic-<UTC_COMPACT>-<RANDOM_BASE32>@example.invalid`,
  sem dados reais, phone, invite, role admin, MFA ou storage;
- um marker único `ci3-synthetic-<UTC_COMPACT>-<RANDOM_BASE32>`, usado como
  `source_reference`, e `<OPERATION_MARKER>-grant` como `provider_event_id`;
- `createUser` uma vez, com e-mail confirmado e app metadata sintética
  server-controlled, seguida de um único sign-in com token memory-only;
- um único `GET /me`, que chama `bootstrap_patient_profile` e cria
  idempotentemente `users`, `user_profiles` e `user_progress`, sem insert
  manual;
- um único `apply_entitlement_event` para `bodyflow_full`, source `manual`,
  status `active`, plan `trial`, environment `sandbox`, reason
  `ci3_synthetic_staging`, actor UUID da operação e expiry exata em
  `CREATED_AT_PLUS_14_DAYS`;
- aceitação do grant somente quando a RPC retorna `result=applied` e os IDs
  correspondem aos dois readbacks; `duplicate`, `stale` ou mismatch são STOP;
- um readback/resolver, um `GET /entitlements` e um `GET /today`;
- rollback exato e de cardinalidade fechada para estados parciais/inválidos;
  uma fixture estruturalmente válida com falha somente de sign-in/probe é
  `PRESERVED_FOR_DIAGNOSIS`, sem recriação ou auto-delete;
- depois de `TODAY_VERIFIED`, nenhum rollback: a fixture é preservada e o
  cleanup até o prazo de 14 dias exige uma operação posterior separadamente
  autorizada.

Contratos principais congelados:

```text
SOURCE_CONTRACT_STREAM_SHA256=0540cb5ed3bdc903dd5feda1499fed0eb5fe5b6197c0365f09c19596d6ac44bf
BOOTSTRAP_FUNCTION_SHA256=94a5de8bc0126fbbc03d1879efaa1a03f6333cb53acc6e9c97362275e679f0ab
PATIENT_SCHEMA_EXECUTION_GATE_SHA256=0859248cfa92245e27598a3aed82ba6224bc2b378ee21353790ee17890f346e9
ENTITLEMENT_SOURCE_FUNCTION_SHA256=797feb1288d91e195dd86f7c878c9b87a6f6577d14b19e9cace31b4e42ba68e3
ENTITLEMENT_RESOLUTION_SHA256=c25d2d1218c0952d26215f7cef57b0f57c3f713ff8c25d8aa33c3771398ececc
TODAY_RELATIONS_AUTHORING_EVIDENCE_SHA256=af34e74b68050e264930df866e9094372261c23e684e85d2507830477381c903
TODAY_FUNCTIONS_AUTHORING_EVIDENCE_SHA256=ee15dcc08e3b767c13f2acfe395c9566ebced1d33127d7471b06eb58f5adfc89
SCHEMA_GATE_V1_SHA256=0859248cfa92245e27598a3aed82ba6224bc2b378ee21353790ee17890f346e9
PUBLIC_USERS_INBOUND_FK_STREAM_SHA256=a5fffce98a0c33f0fc4271de3e6c13a5993c12855da945074fa3ef87157a138f
```

Os arquivos futuros — claim exclusivo, credential, provisioning receipt e
recovery receipt — ficam sob `/root/.config/agentempp/secrets`, root-owned,
`0600`, no-clobber e fora do Git. Credential pode conter e-mail/senha
sintéticos, mas nunca service role, anon key, bearer, origin ou dado de saúde.
Access/refresh token nunca é persistido. A execução usa Node 24.14.0,
Corepack/pnpm 10.33.2 e `@supabase/supabase-js` 2.105.1, com clients separados,
sem sessão persistente, auto-refresh ou detecção de URL.

O rollback inválido/parcial usa somente uma invocação sem retry do conector
oficial `mcp__codex_apps__supabase_execute_sql` com o `ROLLBACK_SQL_V1`
literal versionado como `ROLLBACK_SQL_V1@AUTHORITY_SHA` na evidência. O gate
exige o conjunto fechado de 43 FKs:
o patient parent é bloqueado antes da contagem e, após remover
event/entitlement exatos, somente um profile e um progress podem
existir; todos os demais filhos devem ser zero. Create ambíguo admite um único
read-only settlement; zero não libera claim/credential porque a criação ainda
pode concluir tarde. Grant ambíguo também preserva toda a fixture e proíbe
rollback. Nunca há uma segunda criação. O cleanup posterior remove credential
e claim até o limite de 14 dias e retém apenas receipts sanitizados.

Esta atualização não cria usuário, profile, entitlement, credencial ou token,
não executa Today autenticado, não inicia CI-3/CI-4 e não altera Supabase,
banco, Vercel, primary/live ou produção do produto. A autoridade executável e
o handoff futuro integral estão em
`docs/superpowers/evidence/2026-08-27-ci3-synthetic-staging-patient-provisioning-authority.md`.

```text
SYNTHETIC_PATIENT_AUTHORITY_STATUS=PUBLISHED_PENDING_COMMIT_IDENTITY
PATIENT_PROVISIONING_ATTEMPTS=0
AUTH_USER_CREATION_ATTEMPTS=0
PATIENT_BOOTSTRAP_ATTEMPTS=0
ENTITLEMENT_CREATION_ATTEMPTS=0
CREDENTIAL_ISSUANCE_ATTEMPTS=0
AUTHENTICATED_TODAY_PROBE_ATTEMPTS=0
SUPABASE_WRITE=NO
DATABASE_WRITE=NO
VERCEL_WRITE=NO
CI3_STARTED=NO
CI4_STARTED=NO
NEXT_ENVIRONMENT=VPS
NEXT_GATE=EXECUTE_SYNTHETIC_STAGING_PATIENT_PROVISIONING_AND_AUTHENTICATED_TODAY
```

## 56. Atualização operacional 1.6.20 — readback Auth reconciliado e retomada autorizada

**Data:** 28/08/2026

A execução única autorizada em 1.6.19 criou um Auth user sintético e parou
antes do sign-in em `CREDENTIAL_WRITTEN`, com
`auth_identity_contract_failed`. Claim, credential e recovery receipt ficaram
preservados; provisioning receipt não existe. Create `1/1` e readback `1/1`
foram consumidos; sign-in, `/me`, entitlement, `/entitlements` e `/today`
permanecem `0/1`.

O diagnóstico read-only usou 35/35 testes sintéticos sem rede, exatamente um
Admin LIST, um Admin GET e uma consulta SQL oficial sanitizada. Ele confirmou
Auth total `1`, synthetic match `1`, uma única identidade e-mail, e zero
patient/profile/progress/entitlement/event/storage.

A causa exata foi a igualdade case-sensitive do launcher. O identificador
aleatório da credencial continha maiúsculas, enquanto o Supabase Auth aplica
`strings.ToLower` ao e-mail antes de persistir. O hash do e-mail da credencial
em minúsculas coincide com Admin GET, Admin LIST e banco. Todos os demais
campos obrigatórios são válidos: e-mail confirmado, metadata sintética typed,
provider e identidade e-mail, role/aud authenticated, phone ausente e usuário
não anônimo, não SSO, não banido e não deletado. A auditoria pré-commit também
registrou um Minor de sequência: 11 casos suplementares de redaction/order
foram executados depois dos reads reais, sem rede ou repetição de read; o
helper já tinha guard de output e revisão estática antes do primeiro read.

`provider`/`providers`, provider identity data e a projeção sem identities do
LIST foram classificados conforme docs/source oficiais. Toda diferença é
somente `EXTRA_SERVER_OWNED_DOCUMENTED`, `NORMALIZED_ALIAS_DOCUMENTED` ou
`NORMALIZED_NULL_EMPTY_DOCUMENTED`. As revisões A e B aprovaram a retomada com
zero Critical e zero Important; Review B registrou o único Minor de sequência
acima.

```text
OFFICIAL_AUTH_SEMANTICS_STREAM_SHA256=14e3a6be89402808e485a87108d7a597bd28616b21c72bc255d8a7d4816cb169
LOCAL_AUTH_JS_SOURCE_STREAM_SHA256=0252913cf3003ec3224243b9f344793a2730a446f861d5c03a00405596b1dd2c
DIAGNOSTIC_MATRIX_SHA256=9ddba9fa79f46f82591a8b031f0c36298fd88394fd9e3edfacd188d24f98e812
RESUME_AUTHORITY_STATUS=PUBLISHED_PENDING_COMMIT_IDENTITY
STATE_START=AUTH_USER_CREATED
AUTH_USER_CREATION_ATTEMPTS=1/1_CONSUMED
SECOND_AUTH_USER_CREATION=NO
PATIENT_SIGN_IN_ATTEMPTS=0/1
PATIENT_ME_BOOTSTRAP_ATTEMPTS=0/1
ENTITLEMENT_CREATION_ATTEMPTS=0/1
ENTITLEMENTS_ENDPOINT_PROBE_ATTEMPTS=0/1
AUTHENTICATED_TODAY_PROBE_ATTEMPTS=0/1
CLEANUP_DEADLINE=2026-09-11T11:44:11.182Z
SUPABASE_WRITE=NO
DATABASE_WRITE=NO
VERCEL_WRITE=NO
PRIMARY_LIVE_OPENED=NO
CI3_STARTED=NO
CI4_STARTED=NO
NEXT_ENVIRONMENT=VPS
NEXT_GATE=RESUME_EXISTING_SYNTHETIC_AUTH_IDENTITY_AND_COMPLETE_AUTHENTICATED_TODAY
```

A próxima operação deve reutilizar a identidade e credencial existentes,
comparar e-mail pelo canonical lowercase documentado e continuar exatamente
sign-in → `/me` → grant/readback → `/entitlements` → `/today`. Ela não pode
criar, atualizar ou apagar Auth user, reescrever credential, sobrescrever ou
remover claim/recovery receipt, alterar deadline, tocar Vercel/primary/live ou
iniciar CI-4. A autoridade integral está em
`docs/superpowers/evidence/2026-08-28-ci3-synthetic-auth-identity-readback-diagnostic.md`.

## 57. Atualização operacional 1.7 — staging autenticado verificado e CI-3 Today autorizada

**Data:** 28/08/2026

A retomada única autorizada pela versão 1.6.20 foi concluída com `PASS`. Ela
reutilizou a única identidade Auth sintética existente, canonicalizou o e-mail
somente em memória, realizou exatamente uma tentativa de cada gate restante e
chegou a `TODAY_VERIFIED`. Nenhum segundo usuário foi criado, o usuário
existente não foi atualizado ou apagado, e nenhum token foi persistido.

O staging dedicado permaneceu materialmente isolado: existe um único Preview
semântico `READY` no SHA de implementação
`e3e1e252b48e42554e75899b950692c05186f60d`, zero deployment Production,
três variáveis somente em Preview, zero em Production/Development, sem vínculo
Git, alias customizado, domínio customizado, custom environment ou SSO. O
origin e os identificadores reais continuam apenas no receipt root-only e não
foram publicados.

O readback sanitizado confirmou cardinalidade `1/1/1/1/1/1/1` para Auth user,
Auth identity, patient, profile, progress, entitlement e entitlement event;
existe exatamente um acesso ativo `bodyflow_full`, zero storage e zero mutação
de usuário real. `/me`, `/entitlements` e `/today` retornaram HTTP 200 JSON,
`Cache-Control: no-store`, `Vary: Authorization`, request ID coerente e envelope
API v1. Today apresentou data local, versão de cálculo, fontes, estado de
conclusão e proveniência nas seções aplicáveis. Body, token, identidade, dado
de saúde, origin e IDs não foram persistidos como evidência.

```text
SYNTHETIC_PATIENT_RESUME_STATUS=PASS
AUTHENTICATED_TODAY_STATUS=PASS
AUTH_USER_CREATION_ATTEMPTS=1/1_CONSUMED_PREVIOUSLY
SECOND_AUTH_USER_CREATION=NO
PATIENT_SIGN_IN_ATTEMPTS=1/1
PATIENT_ME_BOOTSTRAP_ATTEMPTS=1/1
PATIENT_BOOTSTRAP_READBACK_ATTEMPTS=1/1
ENTITLEMENT_CREATION_ATTEMPTS=1/1
ENTITLEMENT_READBACK_ATTEMPTS=1/1
ENTITLEMENT_RESOLUTION_ATTEMPTS=1/1
ENTITLEMENTS_ENDPOINT_PROBE_ATTEMPTS=1/1
AUTHENTICATED_TODAY_PROBE_ATTEMPTS=1/1
TOKEN_PERSISTED=NO
SERVICE_ROLE_RUNTIME_BEARER=NO
VERCEL_WRITE=NO
SUPABASE_WRITE=NO
PRIMARY_LIVE_OPEN=NO
PRODUCT_PRODUCTION_WRITE=NO
CI3_STARTED=NO
CI4_STARTED=NO
```

Claim, credential, recovery receipt e provisioning receipt continuam
root-owned, regulares, `0600`, sem symlink e com link count um. O provisioning
receipt está em `TODAY_VERIFIED`. A fixture permanece deliberadamente
preservada para a CI-3, sem dado clínico real, e requer autoridade separada de
cleanup até `2026-09-11T11:44:11.182Z`.

A publicação documental 1.7 autoriza somente a futura implementação local no
Mac da vertical Today autenticada, sobre a base CI-2 exata:

```text
CI2_SHA=277873755bf29771a10b5f362b522c2e6a6c21d6
CI2_PARENT=aba177d7cbb0d9cecb13c5f1099e6b99b6456c93
CI2_TREE=9999e3a05fe4c30d9d1ddd29f0714d263ff3eaf4
CI2_SUBJECT=feat(ios): add secure session lifecycle and user boundary
CI3_BRANCH=codex/ci3-today-staging-v1
CI3_WORKTREE=/Users/eduardohenrique/Developer/bodyflow-ci3-today-staging-v1
CI3_COMMIT_SUBJECT=feat(ios): connect Today to authenticated staging
NEXT_ENVIRONMENT=MAC_LOCAL
NEXT_GATE=IMPLEMENT_CI3_TODAY_STAGING_VERTICAL_SLICE
```

O escopo liga somente configuração local segura, Supabase Auth staging, os
atores de sessão CI-1/CI-2, `MobileAPITransport`, `GET /api/mobile/v1/today`,
validação do envelope/headers/DTO e os estados existentes de Today. Cálculos e
proveniência continuam exclusivamente server-authoritative. History, Plan,
Progress, Registration, conteúdo, mídia, profile mutation, push, cobrança,
chat, backend, migração, assets, rebranding amplo, produção e CI-4 permanecem
fora do escopo.

Valores reais serão transferidos por ponte SSH criptografada para arquivos
owner-only fora do Git e instalados no container do simulador sem argv, stdout
ou histórico; `service_role` nunca irá ao Mac. A credencial sintética será
consumida apenas por bootstrap `DEBUG` e sua cópia no simulador será removida
após a leitura. Release/beta sem configuração completa falha fechado. Tokens
continuam limitados à fronteira de sessão CI-1/CI-2.

Esta atualização não criou worktree CI-3, não editou código iOS, não executou
Xcode/teste/simulador, não repetiu endpoint autenticado e não alterou Vercel,
Supabase, fixture, primary/live ou produção. Também não executou cleanup,
CI-3, CI-4, PR, merge, deploy, TestFlight ou App Store. A evidência, a spec e o
plano executável completos estão, respectivamente, em:

- `docs/superpowers/evidence/2026-08-28-ci3-authenticated-today-staging-completion.md`;
- `docs/superpowers/specs/2026-08-28-ci3-today-staging-vertical-slice.md`;
- `docs/superpowers/plans/2026-08-28-ci3-today-staging-vertical-slice.md`.

## 58. Atualização operacional 1.7.1 — ponte CI-3 versionada após STOP V3

**Data:** 29/08/2026

A implementação local da Task 1 permaneceu preservada no HEAD CI-2, com
staging vazio e os mesmos cinco paths working. Antes de qualquer Task 2, três
gerações de ponte Mac→VPS foram adjudicadas. V1 e V2 ficam
`FROZEN_SUPERSEDED`; V3 terminou `FROZEN_REJECTED_AFTER_ROUND5` e jamais pode
ser executada.

O STOP V3 é terminal: cinco rodadas consumidas, Review A final
`0 Critical / 5 Important / 1 Minor`, Review B final
`0 Critical / 6 Important / 1 Minor`. Os 11 Important foram mantidos sem
deduplicação. Embora a suíte sintética tenha terminado `174/174`, não existia
âncora terminal imutável suficiente para scans/fases, alguns bindings ainda
podiam trocar generation/inode e a policy sintética de `ssh -G` não provava a
saída nativa real. Não houve SSH, stream, simulador, pair canônico, Supabase,
Vercel, produção, cleanup ou CI-4.

A arquitetura sucessora é `VERSIONED_REMOTE_BRIDGE_ARTIFACT_V1`. Um gerador
Node core Git-tracked, ligado ao commit/blob/hash, roda futuramente na VPS e
produz somente config pública sanitizada mais receipt em diretório imutável
endereçado pelo authority SHA. A credential existente continua em seu path
root-only; apenas path fixo e hash entram no receipt. `service_role` nunca é
emitida ou copiada.

No Mac, B0 é estritamente local/no-network e o simulador passa por gate físico
antes de remote Git ou SSH. O fetch usa `/usr/bin/ssh` e `/usr/bin/ssh -G`
reais com trust concreto version-addressed/hash-bound por VPS PASS. Há três
reads exatos com claim/result O_EXCL, tentativa única e zero refetch. O bundle
local publica `local-publication.receipt.json` pre-terminal por claim+
receipt-last `link(2)` no-replace. Instalação/scans geram outro receipt
versionado e um controller privilegiado o ancora fora do bundle, em arquivo
root-owned O_EXCL/imutável. Isso remove circularidade e reescrita
autoconsistente no mesmo domínio.

A fronteira receipt-last não oculta fisicamente o config durante toda a janela:
um crash após o primeiro hardlink pode deixar o diretório final e o config
visíveis sem receipt. Esse estado é obrigatoriamente `UNPUBLISHED`; nenhum
consumer pode ler/usar/instalar/streamar o config. Receipt presente significa
apenas `COMMIT_MARKER_PRESENT_REQUIRES_VALIDATION`, e PASS exige validação
integral de claim/schema/metadados. Purpose errado ou ausente STOPa mesmo se o
hash do claim for reescrito de forma autoconsistente; o self-test usa receipt
sintético completo, sem bypass.

O controller privilegiado também não é autoridade implícita deste handoff.
Antes de preparar o anchor, deve existir
`CI3_PRIVILEGED_TERMINAL_ANCHOR_WRITER_AUTHORITY_V1` separado, version-addressed
e hash-bound, ligando bridge SHA, writer/executable/path/controller, uid/gid
zero, flags O_EXCL/no-follow, `0444` e `UF_IMMUTABLE`. Ausência é
`STOP_PRIVILEGED_TERMINAL_ANCHOR_WRITER_AUTHORITY`; VPS PASS/Mac/normal executor
não podem inferir ou cunhar essa autoridade. Nenhuma foi criada nesta task.

O TDD inicial registrou RED `90/1/89` e GREEN `90/90`. A remediação adicionou
RED `123/91/32`, depois RED `125/123/2`, e terminou GREEN `125/125`, zero
fail/skip/todo; `node --check` passou e o self-test permaneceu sintético/local
com network calls zero. Um RED final `126/125/1` cobriu crash entre hardlink e
de-link. O finding do controller registrou RED `130/126/4`; a integração do
STOP no builder registrou RED focado `1/0/1`; o GREEN final é `131/131`.
Nenhum `--create` foi executado.

```text
CI3_BRIDGE_V1_STATUS=FROZEN_SUPERSEDED
CI3_BRIDGE_V2_STATUS=FROZEN_SUPERSEDED
CI3_BRIDGE_V3_STATUS=FROZEN_REJECTED
CI3_BRIDGE_V3_EXECUTED=NO
CI3_BRIDGE_ARCHITECTURE=VERSIONED_REMOTE_BRIDGE_ARTIFACT_V1
CI3_BRIDGE_GENERATOR_TRACKED=YES
CI3_BRIDGE_GENERATOR_TESTS=131_PASS
CI3_WORKTREE_PRESERVED=YES
CI3_IMPLEMENTATION_STARTED_BEYOND_TASK1=NO
SSH_REAL_EXECUTED=NO
CONFIG_STREAM_EXECUTED=NO
CREDENTIAL_STREAM_EXECUTED=NO
REMOTE_BUNDLE_CREATED=NO
SIMULATOR_REAL_EXECUTED=NO
VERCEL_WRITE=NO
SUPABASE_WRITE=NO
PRIMARY_LIVE_OPEN=NO
CLEANUP_EXECUTED=NO
CI4_STARTED=NO
NEXT_ENVIRONMENT=VPS
NEXT_GATE=CREATE_VERSIONED_CI3_BRIDGE_BUNDLE_ON_VPS
```

Handoff VPS, publicado como contrato mas não executado:

```text
OPERATION=CREATE_VERSIONED_CI3_BRIDGE_BUNDLE_ON_VPS
NEXT_ENVIRONMENT=VPS
AUTHORITY_SHA=CONTROLLER_PASS.authority_sha
AUTHORITY_PARENT=9f5cbb61a7266c6e0f40179fc6dcdafd55aecd52
AUTHORITY_TREE=CONTROLLER_PASS.authority_tree
AUTHORITY_SUBJECT=build(ops): authorize executable CI-3 bridge tooling
GENERATOR=scripts/ci3/create-ios-staging-bridge-config.mjs
GENERATOR_BLOB=/usr/bin/git rev-parse "$AUTHORITY_SHA:scripts/ci3/create-ios-staging-bridge-config.mjs"
GENERATOR_SHA256=/usr/bin/git cat-file blob "$AUTHORITY_SHA:scripts/ci3/create-ios-staging-bridge-config.mjs" | /usr/bin/shasum -a 256
GENERATOR_EXECUTION=/root/.config/agentempp/bridges/ci3/.launchers/$AUTHORITY_SHA/create-ios-staging-bridge-config.mjs --create
OUTPUT=/root/.config/agentempp/bridges/ci3/AUTHORITY_SHA
OUTPUT_FILES=mobile-staging-config.json,bridge.receipt.json
HISTORICAL_GENERATOR_ONLY_TESTS=131_PASS_0_FAIL_0_SKIP_0_TODO
CREATION_BUDGET=1
OVERWRITE=NO
CREDENTIAL_COPY=NO
SERVICE_ROLE_OUTPUT=NO
GIT_VERCEL_SUPABASE_PRODUCTION_WRITE=NO
CI4=NO
```

Handoff Mac posterior a VPS PASS, também não executado:

```text
OPERATION=FETCH_VERSIONED_CI3_BRIDGE_BUNDLE_AND_RESUME_CI3
NEXT_ENVIRONMENT=MAC_LOCAL
AUTHORITY_SHA=VPS_PASS.authority_sha
REMOTE_RECEIPT_SHA256=VPS_PASS.remote.receipt_sha256
REMOTE_CONFIG_SHA256=REMOTE_RECEIPT.output_config_sha256
REMOTE_CREDENTIAL_SHA256=d36c96998b5879150d5dbd45a8118de0e50b24a815f5ff5cbeb0d87d449d8208
SIMULATOR_GATE=BEFORE_SSH
TRUST_DESCRIPTOR=VPS_PASS.ssh.trust_descriptor_path+trust_descriptor_sha256
SSH_EFFECTIVE_CONFIG=/usr/bin/ssh -G -F VERIFIED_CONFIG VERIFIED_DESCRIPTOR_ALIAS
REMOTE_READS=3_TOTAL_1_EACH
RETRY=NO
LOCAL_BUNDLE=$HOME/.config/agentempp/ci3/bundles/AUTHORITY_SHA
NO_REFETCH_AFTER_CLAIM=YES
LOCAL_RECEIPT=PRE_TERMINAL_PUBLICATION_ONLY
INSTALL=/usr/bin/install -m 0600
TERMINAL_RECEIPT=SEPARATE_VERSIONED_AFTER_INSTALL_AND_SCANS
TERMINAL_ANCHOR=EXTERNAL_ROOT_OWNED_O_EXCL_UCHG
V1_V2_V3_EXECUTION=NO
CI3_EXISTING_PATHS=5_PRESERVED
CI3_ALLOWLIST=23
CI3_ORIGINAL_TASKS=2_THROUGH_11_AFTER_BRIDGE_PASS
CONTINUATION_LABEL_12=FINAL_REPORT_ONLY
CI3_PARENT=277873755bf29771a10b5f362b522c2e6a6c21d6
CI3_SUBJECT=feat(ios): connect Today to authenticated staging
CI4=NO
```

Evidência completa, manifest sanitizado, contrato e plano de execução:

- `docs/superpowers/evidence/2026-08-29-ci3-bridge-v3-review-stop.md`;
- `docs/superpowers/specs/2026-08-29-ci3-versioned-bridge-bundle.md`;
- `docs/superpowers/plans/2026-08-29-ci3-versioned-bridge-bundle.md`.

## 59. Atualização operacional 1.7.1 — controller executável e âncora terminal

O STOP da §58 permanece histórico e correto: generator-only não era authority
executável. O complemento 1.7.1 adiciona launcher Git-bound, controller Mac
único e writer Swift privilegiado aos sete paths anteriores, totalizando treze
paths. A arquitetura corrente passa a
`VERSIONED_REMOTE_BRIDGE_ARTIFACT_V1_WITH_EXECUTABLE_MAC_CONTROLLER`.

Os executáveis implementam commit/tree/manifest/component/tool provenance,
quatro generations, bootstrap/read claims originais, recovery local sem
refetch, `ssh -G` nativo, gate simulador de sete fases, publication receipt-last,
install/readback 0600, scans literais `argv`, `history`, `terminal-log`,
`attachment`, `xcresult`, `runtime` e anchor externo root-owned O_EXCL/fsync/
immutable. A ausência do privileged-writer claim explícito continua STOP; o
handoff Mac normal não possui autoridade implícita para mintá-lo.

Os findings fechados, sem deduplicação, são `RA-FINAL-I-1` até
`RA-FINAL-I-6`, `RB-FINAL-I-1` até `RB-FINAL-I-7`; os Minors separados são
`RA-FINAL-M-1` e `RB-FINAL-M-1`. A matriz e cada binding receipt/anchor estão na
spec §12.6.

### Handoff VPS integral — não executar nesta authoring operation

```text
OPERATION=CREATE_VERSIONED_CI3_BRIDGE_BUNDLE_ON_VPS
AUTHORITY_ARCHITECTURE=VERSIONED_REMOTE_BRIDGE_ARTIFACT_V1_WITH_EXECUTABLE_MAC_CONTROLLER
AUTHORITY_SHA=CONTROLLER_PASS.authority_sha
AUTHORITY_PARENT=9f5cbb61a7266c6e0f40179fc6dcdafd55aecd52
AUTHORITY_SUBJECT=build(ops): authorize executable CI-3 bridge tooling
AUTHORITY_MANIFEST_COMMAND=/usr/bin/git ls-tree -r $AUTHORITY_SHA -- [the thirteen literal paths printed below]
COMPONENTS=generator,controller,launcher,writer
GENERATOR=scripts/ci3/create-ios-staging-bridge-config.mjs
GENERATOR_MODE=--create
GENERATOR_EXECUTION=/root/.config/agentempp/bridges/ci3/.launchers/$AUTHORITY_SHA/create-ios-staging-bridge-config.mjs --create
REMOTE_OUTPUT=/root/.config/agentempp/bridges/ci3/AUTHORITY_SHA/REMOTE_GENERATION_ID
REMOTE_FILES=mobile-staging-config.json,bridge.receipt.json
REMOTE_GENERATION=HASH_BOUND
CLAIM=DETERMINISTIC_O_EXCL_FSYNC_ATTEMPT_1
PUBLICATION=NO_REPLACE_RECEIPT_LAST
OVERWRITE=NO
RETRY=NO
CREDENTIAL_COPY=NO
SERVICE_ROLE_OUTPUT=NO
TRUST_DESCRIPTOR=SANITIZED_VERSION_ADDRESSED_HASH_BOUND_VPS_PASS
TRUST_VALUES=DESTINATION_ROOT_PORT_IDENTITY_PUBLIC_FINGERPRINT_HOST_ED25519_FINGERPRINT
TRUST_CONFIG=ISOLATED_OWNER_ONLY_NO_USER_GLOBAL_INHERITANCE
TRUST_FALLBACK=NO
RAW_DESTINATION_ORIGIN_CREDENTIAL_OUTPUT=NO
NEXT_MAC_HANDOFF=ONLY_AFTER_VPS_PASS
V1_V2_V3_EXECUTION=NO
SIMULATOR=NO
CI3_TASK2=NO
GIT_VERCEL_SUPABASE_PRODUCTION_WRITE=NO
```

### Handoff Mac integral — somente depois de VPS PASS; não executar agora

```text
OPERATION=RUN_EXECUTABLE_CI3_MAC_BRIDGE_CONTROLLER
ENTRYPOINT=scripts/ci3/ci3-bridge-launcher.zsh
CONTROLLER=scripts/ci3/ci3-bridge-controller.mjs
WRITER_SOURCE=scripts/ci3/ci3-terminal-anchor-writer.swift
AUTHORITY_SHA=VPS_PASS.authority_sha
AUTHORITY_MANIFEST=CONTROLLER_PASS.authority_manifest_sha256+ordered_entries
LAUNCH_ATTESTATION=CI3_GIT_BOUND_LAUNCH_ATTESTATION_V2
CONTROLLER_MODES=plan,verify-simulator,verify-ssh,fetch,install-simulator,scan,write-terminal-anchor,resume,status
B0=STRICT_LOCAL_NO_NETWORK
SIMULATOR_PHASES=SELECT_DEVICE,RESOLVE_CONTAINER,INSTALL_PROBE,LAUNCH_PROBE,ACK_PROBE,REMOVE_PROBE,REOBSERVE
SIMULATOR_BUNDLE_ID=com.bodyflow.app
SIMULATOR_GATE=BEFORE_BOOTSTRAP_CLAIM_AND_ANY_REMOTE_READ
SSH_EXECUTABLE=/usr/bin/ssh
SSH_EFFECTIVE_CONFIG=/usr/bin/ssh -G -F ISOLATED_CONFIG VERIFIED_ALIAS
SSH_POLICY=ROOT_SINGLE_DESTINATION_NO_AGENT_PASSWORD_KBD_PROXY_FORWARD_CONTROLMASTER
REMOTE_READS=receipt,config,credential
REMOTE_READ_BUDGET=1_EACH_NO_RETRY
CLAIMS=ORIGINAL_O_EXCL_FSYNC_BEFORE_EACH_SPAWN
RECOVERY=LOCAL_ONLY_NO_REFETCH_NO_RETROACTIVE_CLAIM
LOCAL_BUNDLE=$HOME/.config/agentempp/ci3/bundles/AUTHORITY_SHA/REMOTE_GENERATION_ID
LOCAL_PUBLICATION=O_EXCL_FSYNC_NO_REPLACE_RECEIPT_LAST
ABSENT_LOCAL_RECEIPT=UNPUBLISHED
INSTALL=/usr/bin/install -m 0600
INSTALL_DESTINATIONS=Library/Application Support/Agentempp/mobile-staging-config.json;Library/Application Support/Agentempp/synthetic-patient.credentials.json
CREDENTIAL_SIMULATOR_COPY=REMOVE_AFTER_ACK_AND_REOBSERVE
TERMINAL_SCAN_IDS=argv,history,terminal-log,attachment,xcresult,runtime
TERMINAL_MANIFEST=SANITIZED_HASH_BOUND_PHYSICALLY_REVALIDATED
PRIVILEGED_CLAIM=EXTERNAL_ORIGINAL_O_EXCL_ATTEMPT_1
PRIVILEGE=ONE_STANDARD_MACOS_ADMIN_PROMPT_NO_PASSWORD_TO_CODEX
WRITER_BUILD=/usr/bin/xcrun swiftc -parse-as-library -o ROOT_VERSIONED_WRITER AUTHORITY_WRITER_SOURCE
TERMINAL_ANCHOR=/Library/Application Support/Agentempp/ci3-terminal-authority/AUTHORITY_SHA/TERMINAL_GENERATION_ID/terminal-anchor.json
TERMINAL_ANCHOR_PUBLICATION=ROOT_WHEEL_0444_O_EXCL_FSYNC_UF_IMMUTABLE
MISSING_PRIVILEGED_AUTHORITY=STOP_PRIVILEGED_TERMINAL_ANCHOR_WRITER_AUTHORITY
V1_V2_V3_EXECUTION=NO
CI3_EXISTING_PATHS=5_PRESERVED
CI3_ALLOWLIST_PATHS=23_EXACT_FROM_SPEC_SECTION_10
CI3_NEXT_TASKS=ORIGINAL_TASKS_2_THROUGH_11_ONLY_AFTER_TERMINAL_PASS
CONTINUATION_LABEL_12=FINAL_REPORT_ONLY
CI3_PARENT=277873755bf29771a10b5f362b522c2e6a6c21d6
CI3_SUBJECT=feat(ios): connect Today to authenticated staging
CI4=NO
```

Nenhum handoff foi executado. Nenhum SSH connect, rede, simulador real,
install, stream, remote bundle, privilégio, anchor, Task 2, commit ou push foi
feito nesta implementação. Antes de reviews independentes e do único commit
controller, o status é `STOP_PRE_AUTHORITY`, não `PUBLISHED`.

### Fechamento executável da authority 1.7.1

Os modos `plan`, `verify-simulator`, `verify-ssh`, `fetch`,
`install-simulator`, `scan`, `write-terminal-anchor`, `resume` e `status` não
são stubs: testes com adapters sintéticos provam que cada modo alcança sua fase
na mesma máquina de estados do controller. Em execução futura, todos exigem
primeiro launcher Git-bound e o receipt root-owned imutável
`mac-operation-authority.v1.json`; authority ausente ou inválida STOP antes de
simulador, SSH, secret, remote read ou privilégio.

O handoff privilegiado é separado e posterior a `scan`. O operation receipt
normal fornece apenas `authority_path` e `manifest_path`. O scan congela writer
source/binary/signature, seis scan receipts, 62 evidências,
`CI3_TERMINAL_PREPARATION_RECEIPT_V1` e manifest. Um controller externo com
autoridade privilegiada explícita — não o bridge executor — deve validar esses
bytes e, sem clobber, criar o claim original e o
`CI3_PRIVILEGED_TERMINAL_ANCHOR_WRITER_AUTHORITY_V1` root:wheel `0444` +
`uchg` em:

```text
/Library/Application Support/Agentempp/ci3-terminal-authority/
  AUTHORITY_SHA/TERMINAL_GENERATION_ID/privileged-authority.receipt.json
```

O receipt liga manifest/source/binary/signature/claim/path hashes,
`attempt=1`, `retry=false`, `raw_values=false` e
`normal_executor_authorized=false`. Sem autorização concreta para esse writer,
o próximo operador deve retornar
`STOP_PRIVILEGED_TERMINAL_ANCHOR_WRITER_AUTHORITY`; nenhum handoff VPS/Mac
implica ou inventa privilégio.

Verificação sintética Round 1, preservada apenas como histórico e substituída
pela seção Round 3: generator `152/152`, controller `383/383`, launcher `46/46`,
writer `122/122`, total `703`; nenhum modo real, rede,
SSH connect, simulator, install, privileged receipt, admin prompt, anchor,
Task 2, commit ou push foi executado.

O commit futuro deve registrar `100755` para
`scripts/ci3/ci3-bridge-launcher.zsh` e
`scripts/ci3/ci3-bridge-controller.mjs`; o source Swift permanece `100644`
porque o executável é o binary compilado e hash-bound. Antes desse commit, o
comando direto do launcher retorna `ERROR COMPONENT_MISSING` porque HEAD ainda
não contém os treze blobs. O teste de transição prova que o mesmo comando passa
após um commit sintético com os treze paths e modos exatos; isso não é authority
para fazer o commit real agora.

### Handoff normativo Round 1 — valores e comandos exatos

O commit futuro deve ter parent
`9f5cbb61a7266c6e0f40179fc6dcdafd55aecd52`, subject
`build(ops): authorize executable CI-3 bridge tooling` e exatamente os treze
paths seguintes, em ordem:

```text
docs/handoffs/2026-08-20-better-ahead-contexto-completo-e-finalizacao.md
docs/superpowers/evidence/2026-08-29-ci3-bridge-v3-review-stop.md
docs/superpowers/specs/2026-08-29-ci3-versioned-bridge-bundle.md
docs/superpowers/plans/2026-08-29-ci3-versioned-bridge-bundle.md
docs/superpowers/plans/2026-08-20-naming-neutral-core-integration.md
scripts/ci3/create-ios-staging-bridge-config.mjs
scripts/ci3/create-ios-staging-bridge-config.test.mjs
scripts/ci3/ci3-bridge-controller.mjs
scripts/ci3/ci3-bridge-controller.test.mjs
scripts/ci3/ci3-bridge-launcher.zsh
scripts/ci3/ci3-bridge-launcher.test.mjs
scripts/ci3/ci3-terminal-anchor-writer.swift
scripts/ci3/ci3-terminal-anchor-writer.test.mjs
```

O controller resolve cada `AUTHORITY_PATH` por
`git rev-parse "$AUTHORITY_SHA:$AUTHORITY_PATH"`,
`git cat-file blob "$AUTHORITY_SHA:$AUTHORITY_PATH" | shasum -a 256` e
`git ls-tree "$AUTHORITY_SHA" -- "$AUTHORITY_PATH"`; OIDs/hashes finais não
são embutidos nos próprios blobs porque isso seria circular. Launcher e
controller exigem `100755`; os outros onze paths, `100644`.

No VPS, `AUTHORITY_SHA`, `VPS_NODE_PATH` e `VPS_NODE_SHA256` vêm do receipt
controller PASS. O operador valida parent/subject/Node root-owned e executa:

```sh
REL=scripts/ci3/create-ios-staging-bridge-config.mjs
OID=$(/usr/bin/git rev-parse "$AUTHORITY_SHA:$REL") || exit 70
SHA=$(/usr/bin/git cat-file blob "$AUTHORITY_SHA:$REL" | /usr/bin/shasum -a 256 | /usr/bin/awk '{print $1}') || exit 70
ROOT="/root/.config/agentempp/bridges/ci3/.launchers/$AUTHORITY_SHA"
/usr/bin/install -d -o root -g root -m 0700 "$ROOT" || exit 70
TMP=$(/usr/bin/mktemp "$ROOT/.generator.XXXXXXXX") || exit 70
/usr/bin/git cat-file blob "$AUTHORITY_SHA:$REL" > "$TMP" || exit 70
/bin/chmod 0600 "$TMP" || exit 70
test "$(/usr/bin/git hash-object "$TMP")" = "$OID" || exit 70
test "$(/usr/bin/shasum -a 256 "$TMP" | /usr/bin/awk '{print $1}')" = "$SHA" || exit 70
FINAL="$ROOT/create-ios-staging-bridge-config.mjs"
if ! /bin/ln "$TMP" "$FINAL" 2>/dev/null; then /usr/bin/cmp -s "$TMP" "$FINAL" || exit 70; fi
/bin/rm -f "$TMP" || exit 70
test "$(/usr/bin/stat -c '%u:%g:%a:%h' "$FINAL")" = 0:0:600:1 || exit 70
test "$(/usr/bin/shasum -a 256 "$VPS_NODE_PATH" | /usr/bin/awk '{print $1}')" = "$VPS_NODE_SHA256" || exit 70
"$VPS_NODE_PATH" "$FINAL" --self-test || exit 70
"$VPS_NODE_PATH" "$FINAL" --create || exit 70
```

O generator usa os cinco inputs fixos/hashes do código, claim O_EXCL+fsync,
path `<output>/<authority>/<remote-generation>`, staging same-filesystem e
hard-link no-replace. Config sem `bridge.receipt.json` é `UNPUBLISHED`; recovery
não cria generation, não relê inputs e não refaz efeito. O PASS VPS entrega
somente manifest/hashes/paths versionados e descriptor SSH sanitizado.

No Mac, o modo separado `publish-operation-authority`, com receipt humano
explicitamente autorizado, instala como
root:wheel/single-link/`uchg` o Node `0555` e
`mac-operation-authority.v1.json` `0444` sob
`/Library/Application Support/Agentempp/ci3-controller-authority/$AUTHORITY_SHA/`.
A state machine normal não cria essa authority. A sequência inclui:

```sh
/bin/zsh scripts/ci3/ci3-bridge-launcher.zsh --self-test
/bin/zsh scripts/ci3/ci3-bridge-launcher.zsh publish-operation-authority
/bin/zsh scripts/ci3/ci3-bridge-launcher.zsh plan
/bin/zsh scripts/ci3/ci3-bridge-launcher.zsh verify-simulator
/bin/zsh scripts/ci3/ci3-bridge-launcher.zsh verify-ssh
/bin/zsh scripts/ci3/ci3-bridge-launcher.zsh fetch
/bin/zsh scripts/ci3/ci3-bridge-launcher.zsh install-simulator
/bin/zsh scripts/ci3/ci3-bridge-launcher.zsh scan
/bin/zsh scripts/ci3/ci3-bridge-launcher.zsh publish-privileged-writer-authority
/bin/zsh scripts/ci3/ci3-bridge-launcher.zsh write-terminal-anchor
/bin/zsh scripts/ci3/ci3-bridge-launcher.zsh status
/bin/zsh scripts/ci3/ci3-bridge-launcher.zsh resume
```

B0 encerra sete receipts físicos antes de remote Git/read; SSH é primeiro
`/usr/bin/ssh -G` contra config/known_hosts/identity isolados e descriptor
ordered duplicate-aware. Fetch permite somente três commands
`exec /usr/bin/cat -- <exact-path-from-receipt>`, cada um com claim/capture/
result duráveis e sem refetch. Bundle local é um único directory rename
no-replace; install persiste `/usr/bin/install -m 0600` + readback; scan tem
implementação/counters separados para `argv`, `history`, `terminal-log`,
`attachment`, `xcresult`, `runtime` e revalida inputs no terminal.

Após scan, o modo `publish-privileged-writer-authority` exige outro receipt
humano, compila os bytes Git-bound via stdin com
`/usr/bin/xcrun swiftc -parse-as-library`, assina e instala o writer em
`/Library/Application Support/Agentempp/ci3-terminal-authority/$AUTHORITY_SHA/$TERMINAL_GENERATION_ID/writer/ci3-terminal-anchor-writer`
root:wheel `0555`, single-link, `uchg`; antes disso publica/fsynca o claim
original root e depois cria `privileged-authority.receipt.json` root:wheel
`0444`, single-link, `uchg`,
ligando source/binary/signature/manifest/claim/anchor path/hash/physical
identity. O writer elevado consome esse receipt, reabre e recomputa toda a
cadeia, e só então publica anchor `0444` O_EXCL+fsync+`uchg`. A ausência de
autoridade do publisher é
`STOP_PRIVILEGED_TERMINAL_ANCHOR_WRITER_AUTHORITY`; nenhum handoff a presume.

GREEN sintético Round 1, histórico e superseded pela seção Round 3: generator
`152`, controller `383`, launcher `46`, writer `122`, total `703`. Nenhum passo real
acima, commit/push ou Task 2 foi executado. Estado: `STOP_PRE_AUTHORITY`.

## Handoff executável Round 2 — publishers e recovery fechados

Esta seção substitui a descrição anterior de publishers externos inexistentes.
Os dois publishers agora são modes do launcher oficial e continuam sujeitos a
autoridade humana separada. O VPS PASS deve fornecer, por hash e sem valor raw:
authority/parent/tree/subject, manifest dos 13 paths, quatro component blobs,
quatro tool identities, quatro generation IDs, operation-authority candidate,
Node candidate, seis contratos de collector sem surfaces prebuilt, trust descriptor SSH completo,
três paths remotos hash-bound e os receipts humanos. Nenhum valor pode ser
digitado como variável livre no Mac.

### Mac — sequência futura exata

No checkout do único commit autorizado, confirmar primeiro que o launcher e o
controller têm Git mode `100755` e o writer source `100644`. O request do
Publisher 1 deve existir em:

```text
~/.config/agentempp/ci3/publisher-input/<authority>/operation-authority.publisher-request.json
```

Ele referencia candidates/receipts `0600` e seus hashes. O receipt humano
`CI3_OPERATION_AUTHORITY_HUMAN_AUTHORIZATION_V1` deve ligar manifest, Node,
operation authority e a ação
`PUBLISH_ROOT_IMMUTABLE_OPERATION_AUTHORITY`. Então a única invocação é:

```sh
zsh scripts/ci3/ci3-bridge-launcher.zsh publish-operation-authority
```

O modo apresenta um prompt admin, cria sem clobber
`/Library/Application Support/Agentempp/ci3-controller-authority/<authority>/`,
instala Node/controller `0555`, operation/human/scans `0444`, verifica hashes,
owner/type/nlink/mode, aplica `uchg`, fsynca tudo e imprime somente PASS. Se a
generation já existe, a execução STOPa e preserva evidência; não há retry que
reescreva authority.

Somente após esse PASS, continuar:

```sh
zsh scripts/ci3/ci3-bridge-launcher.zsh plan
zsh scripts/ci3/ci3-bridge-launcher.zsh verify-simulator
zsh scripts/ci3/ci3-bridge-launcher.zsh verify-ssh
zsh scripts/ci3/ci3-bridge-launcher.zsh fetch
zsh scripts/ci3/ci3-bridge-launcher.zsh install-simulator
zsh scripts/ci3/ci3-bridge-launcher.zsh scan
```

B0 é estritamente local/no-network antes do simulator; `ssh -G` e qualquer read
remoto ficam depois do simulator PASS. Os três reads usam exatamente
`/usr/bin/ssh -F <fixed-config> <fixed-alias> 'exec /usr/bin/cat -- <fixed-path>'`,
sem `--` espúrio no argv e sem quarto read. O trust descriptor liga executável,
signature/version, config/known-hosts/key/fingerprints/destination e todos os
records nativos ordered/duplicate-aware. Os paths preservados Task-1 são
exatamente:

```text
apps/ios/BodyFlow/BodyFlow/BodyFlowApp.swift
apps/ios/BodyFlow/BodyFlow/App/AppLaunchConfiguration.swift
apps/ios/BodyFlow/BodyFlow/Core/Configuration/MobileStagingConfiguration.swift
apps/ios/BodyFlow/BodyFlowTests/CI3StagingLaunchConfigurationTests.swift
apps/ios/BodyFlow/BodyFlowTests/MobileStagingConfigurationTests.swift
```

Depois de `scan`, criar o receipt humano
`CI3_PRIVILEGED_WRITER_PUBLISHER_AUTHORIZATION_V1` em
`~/.config/agentempp/ci3/publisher-input/<authority>/<terminal-generation>/`,
já ligado aos hashes reais de manifest/source/binary. Executar:

```sh
zsh scripts/ci3/ci3-bridge-launcher.zsh publish-privileged-writer-authority
zsh scripts/ci3/ci3-bridge-launcher.zsh write-terminal-anchor
zsh scripts/ci3/ci3-bridge-launcher.zsh status
zsh scripts/ci3/ci3-bridge-launcher.zsh resume
```

O segundo publisher cria primeiro o original claim root `0444` e fsync, depois
instala o writer `0555`; o Node root reabre o binary e computa a identidade
`uid/gid/mode/nlink/size/mtime_ns/dev/ino` para o privileged authority receipt
O_EXCL. Claim/binary/receipt são `root:wheel`, single-link e `uchg`. O writer
reabre todos os 62 evidence roles atuais, incluindo 21 simulator phase e 24
controller phase roles até `RUN_SCANS`, recomputa os schemas/cross-bindings e só publica anchor
quando os seis scans `argv`, `history`, `terminal-log`, `attachment`,
`xcresult`, `runtime` permanecem CLEAN.

Claim sem physical receipt é STOP e nunca repete install/launch/publish/write.
Receipt existente é reaberto pelo mesmo inode e metadata antes de completar
result/event. O bundle local surge por um único directory
`renameatx_np(RENAME_EXCL)`; corrida preserva staging. Nenhuma authority futura
é presumida: request/receipt ausente continua `STOP_PRE_AUTHORITY` ou
`STOP_PRIVILEGED_TERMINAL_ANCHOR_WRITER_AUTHORITY`.

Este handoff não foi executado nesta authoring operation. Não houve SSH,
simulator, publisher, admin prompt, bundle real, anchor, commit/push ou Task 2.

## Handoff executável Round 3 — supersede integralmente os blocos Round 1/2

As contagens, schemas e instruções desta seção prevalecem sobre qualquer número
ou referência a `surface/collector pairs` pré-publicados acima. O estado segue
`STOP_PRE_AUTHORITY`: nenhum comando operacional, publisher, SSH, simulator,
anchor, commit, push ou Task 2 foi executado durante a authoring operation.

### Proveniência VPS para o Publisher 1

O PASS VPS autorizado deve materializar quatro inputs independentes: o JSON
`CI3_MAC_OPERATION_AUTHORITY_V1`, o executável Node, o
`CI3_VPS_PUBLISHER_INPUT_MANIFEST_V1` e o
`CI3_VPS_OPERATION_AUTHORITY_PASS_V1`. O manifest enumera exatamente
`operation-authority` e `node-runtime`, cada um com `path_sha256` e `sha256`,
e fecha `transfer_payload_sha256`; ele também liga authority, remote/controller
generation e o root dos seis contratos de collector. O PASS liga parent/tree/
subject/manifest, source/remote/controller generations, os hashes dos dois
candidates, o próprio input manifest, os contratos e o transfer payload.

O transfer controller aprovado deve copiar esses bytes para paths locais
owner-only e produzir o request abaixo já com paths absolutos e hashes; um
operador não pode digitar ou substituir valores livres:

```text
~/.config/agentempp/ci3/publisher-input/<authority>/
  operation-authority.publisher-request.json
  mac-operation-authority.v1.json
  node
  publisher-input.manifest.json
  vps-operation-authority.pass.json
  human-authorization.receipt.json
```

O request `CI3_OPERATION_AUTHORITY_PUBLISHER_REQUEST_V1` referencia os cinco
inputs por path/hash. O receipt humano liga também os hashes do input manifest
e do VPS PASS, além de authority manifest, Node e operation authority. O modo
`publish-operation-authority` reabre tudo no-follow, recompõe todas as relações
e só então apresenta seu único prompt admin. Ele instala Node/controller
`0555` e authority/human/PASS/input-manifest `0444`, root:wheel, single-link,
`uchg`, com readback e fsync. Ele não instala surfaces nem collector receipts.
Ausência de qualquer valor concreto fornecido pelo PASS é STOP; esta
documentação não cria a autoridade do transfer controller nem do privileged
writer publisher.

### B0, simulator e observação física

Antes do primeiro claim do gate simulator, config, credential e ACK devem
estar ausentes. Antes das claims internas `INSTALL_PROBE` e `LAUNCH_PROBE`, a
ausência aplicável é revalidada; original execution instala/lança exatamente
uma vez. Recovery nunca adota um receipt: chama somente o observer tipado,
reabre devices/runtime/container, destinos, ACK ou ausência final e compara o
objeto inteiro. Drift ou efeito sem prova inequívoca STOPa sem reexecução.

As dez fases duráveis usam observers tipados sobre alvos reais: authority,
worktree observation, simulator gate, SSH provenance, local receipt commit
marker, install receipt, credential ausente, seis scan receipts e anchor root
imutável. `physical_observation_sha256` é o hash dessa observação reaberta, não
o hash do receipt que a descreve.

### SSH e seis superfícies finais

`identity_public_key_sha256` é o SHA-256 dos bytes da chave pública;
`identity_public_key_fingerprint_sha256` é o SHA-256 da saída de fingerprint.
Os campos são distintos e cruzados pelo descriptor, provenance e writer.

O VPS PASS fornece apenas os seis contratos autenticados, nunca bytes finais
de surface. Depois de fetch/install e dentro da generation corrente, o
controller deriva `argv`, `history`, `terminal-log`, `attachment`, `xcresult`
e `runtime` de sources fixos produzidos pela execução atual. Cada surface
serializa authority/controller/terminal generations e roots de source com
hash+identidade física. Cada collector recompõe command/schema/tool, examina
somente sua surface final, persiste counters e input byte range, reabre os
bytes/metadata depois do scan e publica um receipt write-once. Recovery aceita
somente esses seis receipts e surfaces da mesma generation.

### Settlement terminal não circular

O manifest contém 62 roles sem deduplicação: 17 roots centrais, 21 roles das
sete fases simulator e 24 roles das oito fases controller até `RUN_SCANS`.
`terminal-preparation.receipt.json` liga o result físico de `RUN_SCANS`. Dois
contratos posteriores, `INVOKE_WRITER` e `VERIFY_ANCHOR`, formam uma cadeia
versionada cujo predecessor inicial é esse result. Assim o anchor não contém
seu próprio hash: o writer privilegiado valida o manifest pre-terminal e
publica o anchor; o controller observa o anchor root para liquidar os dois
contratos. Autoridade ausente para publicar/usar o writer root continua
`STOP_PRIVILEGED_TERMINAL_ANCHOR_WRITER_AUTHORITY`.

O writer reabre os 62 roles e recompõe claims/results, expected=capture,
commands remotos, parent/subject/source commit, read chains, local/remote/
SSH/simulator/install roots, predecessor/contract/result de cada fase, input
manifest, terminal receipt, os seis command/schema/tool/output roots e os dois
settlement contracts. Mutation autoconsistente em qualquer edge STOPa antes de
`TERMINAL_PASS`.

### Evidência sintética corrente

```text
GENERATOR=152_PASS
CONTROLLER=408_PASS
LAUNCHER=108_PASS
WRITER=128_PASS
TOTAL=796_PASS_0_FAIL_0_CANCEL_0_SKIP_0_TODO
OPERATIONAL_E2E=60_SCENARIOS_10_PHASES_X_6_BOUNDARIES
REAL_NETWORK_SSH_SIMULATOR_INSTALL_PRIVILEGE_ANCHOR=0
```

Cada cenário executa o launcher oficial contra um commit sintético de treze
paths e o writer compilado com `-D CI3_SYNTHETIC_TEST`; as duas fases terminais
e os seis boundaries estão presentes. Isso é prova local/sintética, não um
PASS VPS/Mac nem autorização para continuar as Tasks originais 2–11/relatório
12.

## Handoff executável Round 4 — ainda não autorizado para execução real

Esta seção substitui as contagens 796 e qualquer interpretação anterior de que
o pre-anchor já fosse PASS. O estado correto é:

```text
PRE_ANCHOR=PRE_ANCHOR_PENDING_SETTLEMENT/PENDING_VERIFICATION
TERMINAL_PASS=ONLY_TERMINAL_SETTLEMENT_AFTER_VERIFY_ANCHOR
EXPECTED_LOCAL_SUITE_DIMENSION=821
REAL_VPS_SSH_SIMULATOR_PRIVILEGE_ANCHOR_TASK2_ACTIONS=0
```

### Handoff VPS/Publisher 0

O futuro operador VPS deve materializar, por um publisher externo já
autorizado, exatamente estes três objetos owner-only e transferi-los como um
único payload autenticado:

```text
CI3_VPS_PUBLISHER_INPUT_MANIFEST_V1
CI3_VPS_OPERATION_AUTHORITY_PASS_V1
CI3_VPS_EXTERNAL_ISSUER_AUTHORITY_V1
```

O issuer receipt é root-owned/immutable e contém a chave pública Ed25519 real,
`issuer_generation_id`, `issuer_identity_sha256`, authority commit e purpose
permitido. Nenhuma chave concreta existe neste bundle Git. O PASS é a
assinatura Ed25519 do JSON canônico sem os campos de assinatura e liga
authority parent/tree/subject/manifest, operation authority, Node, collector
contracts, publisher manifest, transfer payload e remote/controller
generations. Os paths/aliases/destino reais nunca aparecem em log; somente os
hashes previstos no PASS podem atravessar o handoff. Ausência de issuer root ou
assinatura válida: `STOP_PRE_AUTHORITY`.

O emissor VPS deve produzir um receipt PASS sanitizado antes de qualquer ação
Mac. Ele não pode autorizar o prompt administrativo Mac nem o writer terminal;
essas autoridades continuam separadas.

### Handoff Mac/Publisher 1

O operador Mac futuro recebe os hashes exclusivamente do PASS assinado, cria o
request owner-only `CI3_OPERATION_AUTHORITY_PUBLISHER_REQUEST_V1` e acrescenta
o receipt humano separado. O único entrypoint é o launcher Git-bound:

```text
zsh scripts/ci3/ci3-bridge-launcher.zsh publish-operation-authority
```

Esse comando futuro deve parar antes do prompt se qualquer input não for
regular/single-link/no-follow/hash-bound, se o issuer não estiver root-owned e
imutável, se o PASS não validar ou se o receipt humano não ligar exatamente o
PASS e o publisher manifest. Dentro do prompt único, Publisher 1 instala com
`/usr/bin/install` e verifica hash de cada target antes de `chown/chmod/chflags`:

```text
/Library/Application Support/Agentempp/ci3-controller-authority/<AUTHORITY>/
  mac-operation-authority.v1.json                 root:wheel 0444 uchg
  human-authorization.receipt.json                root:wheel 0444 uchg
  vps-operation-authority.pass.json               root:wheel 0444 uchg
  vps-issuer-authority.receipt.json               root:wheel 0444 uchg
  publisher-input.manifest.json                   root:wheel 0444 uchg
  ssh-trust-descriptor.json                       root:wheel 0444 uchg
  ssh-identity.pub                                root:wheel 0444 uchg
  runtime/node                                    root:wheel 0555 uchg
  runtime/ci3-bridge-controller.mjs               root:wheel 0555 uchg
```

Depois do prompt, o controller reabre todos os nove targets e valida bytes,
uid/gid, regular file, nlink=1, modo, immutable flag e parent chain. Isso inclui
explicitamente o receipt humano, fechando a troca de source durante o prompt.

### Handoff Mac/controller, scans e terminal

B0 é local/no-network. Depois do gate simulator completo, o controller executa
`/usr/bin/ssh -G -F <CONFIG> <ALIAS>` com descriptor sanitizado/root-bound,
valida a policy nativa e executa exatamente três argv de leitura com um único
comando remoto fixo `exec /usr/bin/cat -- <PATH>`. Não existe quarto fetch e
recovery usa somente captures locais.

As fases seguintes publicam bundle local, instalam/removem credential no
simulator e produzem os seis sources literais `argv`, `history`,
`terminal-log`, `attachment`, `xcresult`, `runtime`. Cada source é PRESENT em
path fixo ou, apenas para `xcresult`, ABSENT com prova fechada. Os scanners
reabrem source/surface/receipt e o writer recompõe todas as relações.

Publisher 2 permanece outro gate separado:

```text
zsh scripts/ci3/ci3-bridge-launcher.zsh publish-privileged-writer-authority
```

Sem receipt/binary root-owned, version-addressed e imutável, o próximo comando
STOPa. Com autoridade válida, o fluxo futuro é:

```text
zsh scripts/ci3/ci3-bridge-launcher.zsh write-terminal-anchor
zsh scripts/ci3/ci3-bridge-launcher.zsh resume
zsh scripts/ci3/ci3-bridge-launcher.zsh status
```

`write-terminal-anchor` executa uma única transação privilegiada: publica e
reabre o pre-anchor pending, deriva e liquida internamente as duas fases
terminais e publica o settlement. `resume` somente reabre e recompõe os mesmos
roots; não existe uma segunda invocação privilegiada. Somente o
`terminal-settlement.json` root-owned append-only/no-clobber pode declarar
`TERMINAL_PASS`.

### Continuação congelada

Mesmo com settlement real, é obrigatório obter Reviews A e B independentes
com `0 Critical / 0 Important` e então o único commit do controller. Até lá,
Tasks originais 2–11/relatório 12, os cinco paths iOS preservados e a allowlist
exata de 23 paths permanecem congelados. Nesta rodada não houve commit, push,
VPS, SSH, rede, simulator, prompt, root publisher, anchor ou Task 2.

## Round 5 executable authority correction — supersedes every earlier `--settle` description

The terminal lifecycle now has one privileged writer invocation only. The
controller invokes the root-owned, immutable, version-addressed writer once
with `--write`. That same process validates the frozen manifest and external
roots, publishes and reads back the pending pre-anchor, derives and publishes
the complete `INVOKE_WRITER` and `VERIFY_ANCHOR`
claim/physical-receipt/result chains, scans the final terminal bytes with all
six literal scanners, and publishes and reads back
`terminal-settlement.json`. `--settle` is not a public or private mode and
returns `MODE_INVALID`; there is no second elevation or second prompt.

`TERMINAL_PASS` is derived only inside that root transaction. It binds all
four generation IDs, the authority receipt hash, the pre-anchor hash, both
contract hashes, every claim/receipt/result edge, the ordered terminal phase
graph, physical target observations, and the terminal-final six-scan root.
The normal executor may reopen and recompute this graph but cannot supply a
terminal triple or settlement manifest.

Remote read bindings are derived again by the writer from the root-owned
operation authority. Each exact path is paired with exactly
`exec /usr/bin/cat -- <authority-path>`; the bootstrap claim, each read claim,
each read result, and the terminal input manifest must match those independent
derivations. The same operation authority contains the ordered per-phase
target contracts. Role, state, path hash, owner allowlist, mode allowlist and
immutability policy must match exactly; a fully rehashed alternate regular
file is rejected.

The six scans remain distinct and ordered: `argv`, `history`,
`terminal-log`, `attachment`, `xcresult`, `runtime`. The controller
collects complete argv, journal/history bytes, event/log bytes, attachment
bytes and only the closed sanitized runtime allowlist/process identity. The xcresult observation uses the
fixed generation-addressed operational result path, with an authenticated
absence receipt when it does not exist. The privileged transaction performs a
second terminal-final scan over current journal/output, the new pre-anchor,
phase objects, actual settlement and writer output, then publishes the bound
`complete-result.json` last.

Publisher 0 is a controller mode reachable only through the separately
installed root-owned immutable external bootstrap. The user-owned worktree
launcher rejects it. The bootstrap verifies the external issuer, fixed runtime
and full root directory chain before reading the fixed issuer/request/key
inputs, signs Ed25519, creates the PASS no-clobber, fsyncs, freezes and reopens
it. No real key is embedded; missing external provisioning is
`STOP_PRE_AUTHORITY`.

Synthetic crash coverage now invokes the actual Swift test writer as the
`INVOKE_WRITER` phase effect, and `VERIFY_ANCHOR` reopens the artifacts from
that same causal run. A crash after a durable claim but before any physical
effect is not healed by replay: it deterministically returns
`STOP_CLAIM_CONSUMED_NO_RESULT` and publishes no anchor. Other boundaries
recover with at-most-once effects and exact-existing readback.

All real authority inputs remain absent in this implementation operation.
Therefore `STOP_PRE_AUTHORITY` remains the only current operational status;
no VPS publisher, SSH/network, simulator, admin prompt, root publication,
anchor, Task 2, commit or push was executed.

Each matrix case now uses two distinct Git-bound controller processes: the first exits at the selected synthetic crash, and the second reconstructs maps, physical target bindings, effect counts and journal state exclusively from the durable scenario snapshot before recovery or STOP.

## Round 6 handoff correction

Do not run the Git worktree launcher as root and do not use it for Publisher 0.
The future VPS operator must first supply the separately authorized root-owned
immutable Publisher 0 bootstrap and issuer receipt described in the versioned
bridge spec; absent either, stop. The future Mac operator then consumes only the
authenticated transfer manifest, installs the exact root-owned immutable SSH
snapshot and operation authority, and verifies every byte/metadata identity
before B0. Raw scan payloads precede Base64, environment persistence is closed,
and `complete-result.json` must exist and bind the actual settlement/final-scan
bytes before any `COMPLETE` report. `VERIFY_ANCHOR:after-claim` is a STOP, never
retroactive adoption. No real VPS/Mac/root/network/simulator/Task 2 action has
been performed here.

### Round 6 causal E2E correction

The 60 synthetic crash/restart cases MUST NOT pre-materialize terminal writer
evidence. The first or recovery Git-bound controller reaches `INVOKE_WRITER`,
reopens its own `journal-snapshot.json`, and only then invokes the local
synthetic materializer with a closed environment. The materializer copies that
exact snapshot into the mandatory `controller-durable-state-root` evidence
role, binding scenario ID/hash, physical snapshot-path hash and canonical
snapshot hash. The controller proves the durable snapshot did not change
during materialization and reopens the descriptor/evidence; the compiled Swift
writer independently reopens the role, validates the complete snapshot schema
and recomputes scenario/snapshot hashes before its single transaction. A claim
without physical effect still STOPs and never creates this evidence. This is a
test adapter only, not authority to materialize a real VPS/Mac artifact.

## Round 8 future operator handoff (do not execute from this worktree)

Publisher 0 must first be installed by the external VPS issuer as an immutable
version-addressed runtime containing fixed Node, controller, launcher, launch
attestation, authority manifest and the exact ten-line launcher authority.
The root operator then runs the fixed Node/controller directly under the four
closed environment entries and the `publish-vps-operation-authority-pass`
mode. The controller performs the retained-descriptor transaction; absence of
the issuer receipt, signing key, boundary or any matching hash STOPs. The
worktree launcher is never that root entrypoint.

The VPS-to-Mac handoff must deliver the authenticated eleven-role transport
manifest and separately authorized human receipt. Publisher 1 is invoked only
from the externally installed root-owned
`ci3-publisher1-bootstrap/<authority>/<generation>/runtime` launcher. It
installs/reopens the sixteen-target Mac authority set, including the exact five
SSH snapshot files and generated launcher-bootstrap authority. A path supplied
only by the normal user is not authority.

After Publisher 1, every future command uses the installed
`ci3-controller-authority/<authority>/runtime/ci3-bridge-launcher.zsh` with
`/bin/zsh -f`. The launcher checks root:wheel, single-link, immutable modes and
all line-authority hashes before fixed Node. For `resume`, the first controller
process may emit only `PRE_TERMINAL_UNPUBLISHED`. The normal controller has no
claim/receipt API capable of changing that status. The one privileged writer
invocation writes/readbacks the anchor and settlement, scans the actual
reversible final journal plus stdout/stderr/complete/final-scan bytes, then
publishes the fixed root-owned immutable
`CI3_PRIVILEGED_TERMINAL_PASS_MARKER_V1` last. The internal terminalizer
validates that marker and emits its retained stdout bytes directly; there is no
post-scan pathname `cat`. Missing privileged marker means unpublished, never
PASS.

Keep the five original iOS changed paths and the exact 23-path continuation
allowlist already embedded in this handoff. Tasks 2–11 and report Task 12 remain
frozen until the external authorities exist and this complete handoff passes.
No real handoff command, admin prompt, SSH, simulator, anchor or Task 2 was run
in Round 8.

## Round 9 executable handoff correction (still do not execute)

The Round 8 description of a normal-owned `terminal-tail.receipt.json` is
superseded by the privileged marker above. The future external Mac bootstrap
must install, as root:wheel immutable objects, the exact materializer authority,
the VPS issuer receipt and the reviewed Swift binary at:

```text
/Library/Application Support/Agentempp/ci3-publisher1-bootstrap/<authority>/<controller-generation>/publisher1-materializer.authority.json
/Library/Application Support/Agentempp/ci3-publisher1-bootstrap/<authority>/<controller-generation>/vps-issuer-authority.receipt.json
/Library/Application Support/Agentempp/ci3-publisher1-bootstrap/<authority>/<controller-generation>/runtime/ci3-terminal-anchor-writer
```

The receipt must bind exact path/hash, writer source hash, issuer receipt hash,
closed environment and `normal_executor_authorized=false`. No key/value is
invented here; the VPS PASS issuer supplies the concrete authority, otherwise
the only result is `STOP_PRE_AUTHORITY`. The Mac controller snapshots the
already authenticated eleven transport roles plus the human receipt and
derived launcher authority into deterministic owner-only receiver leaves and
writes one hash-bound transaction request. The fixed root materializer opens
that request once, independently verifies the root issuer, Ed25519 PASS,
manifest/operation/attestation/human/SSH bindings and retains all sixteen
source descriptors.

Publisher 1 then claims durably before its first install effect, creates the
whole tree through `openat/O_NOFOLLOW/O_EXCL`, freezes all files and directories,
promotes the single authority directory with `RENAME_EXCL`, fsyncs/readbacks
through retained descriptors and writes its result. Recovery never refetches
or repeats the prompt/effect: exact-existing with the original claim is
reobserved; partial, unclaimed or divergent state STOPs. Source-path and
ancestor swaps are negative tests. No real receiver, bootstrap, prompt,
privilege, network, simulator, terminal anchor or continuation Task 2 was
executed in Round 9.

## Round 10 handoff correction — do not split terminal publication

The future Mac operator must not run an old two-step finalization. The normal
controller may settle the eight normal phases, scan their actual bytes, write
the COMPLETE commit-contract event and seal the reversible journal. It must
then make one privileged writer invocation and perform no normal write after
that call. `events/COMPLETE.json` is not PASS. Only the externally authorized
writer may create the two privileged phase roots, settlement/final scans,
COMPLETE/output frames and, after full readback, the no-clobber
`terminal-pass.marker.json` as the literal last object. `status`/`resume` must
return unpublished whenever that exact marker is absent or invalid.

Before Publisher 1, obtain the external V2 materializer authority. It must bind
the exact fixed request pathname/hash/full physical identity and the exact
receiver root pathname/hash/descriptor identity. Invoke production only with
`--publisher1-transaction <fixed-request-path> <expected-sha256>`; never pipe
stdin and never choose a receiver by suffix. Reobserve the root claim/result
and complete sixteen-leaf tree before prompting. Exact settled state is reused;
claim-only, partial or divergent state STOPs without a second admin prompt.
The privileged install constructs/fsyncs staging, promotes once with
`RENAME_EXCL`, then freezes and readbacks the destination.

Do not treat the local Darwin promotion probe or the 60 synthetic crash/restart
scenarios as production authority. They prove ordering and recovery only. The
real external issuer, immutable Node/materializer, operation authority and
writer authority have not been supplied. Until they are supplied and verified,
the executable handoff remains `STOP_PRE_AUTHORITY`; do not run SSH, simulator,
anchor publication or continuation Task 2.

## Round 11 handoff correction — physical receiver leaves and marker-only recovery

The future external materializer authority must carry one ordered
`receiver_leaves` entry for each of the exact sixteen Publisher 1 roles. Every
entry binds `role`, fixed path hash, content hash, `uid`, `gid`, mode `0600`,
`nlink=1`, size, nanosecond mtime, device, inode and the canonical physical
identity hash. The owner-only request, original root claim and result preserve
the same values. The privileged Swift materializer performs
`fstat-before/read/fstat-after`, compares every field, and immediately before
the claim reobserves both the retained receiver directory and each leaf with
descriptor-relative `fstatat`. A same-bytes inode replacement, owner/mode
drift, hardlink or ancestor swap must STOP before claim, prompt or effect.

Terminal restart must not use the old five-file predicate. The operational
controller first reads and semantically validates the exact privileged
`terminal-pass.marker.json` and all of its fixed authority, journal,
stdout/stderr, COMPLETE, settlement, scan and generation bindings. Only that
complete root can yield `TERMINAL_PASS`. If the marker is absent but an
externally authorized writer transaction left an exact recoverable prefix, the
same reviewed writer transaction may exact-reopen and finish it; a divergent
prefix STOPs. Crash tests cover the prefix after COMPLETE final scan, after the
four retained frames, after marker readback and after directory freeze. The
marker remains the commit boundary, and `resume` obtains PASS only through the
marker-validating `terminalStatus` path.

The reviewed writer itself is the privilege-continuity mechanism. One
`osascript` launches the exact root-owned writer binary as a transient
supervisor; it spawns the same absolute binary under a closed environment as
the transaction worker. A worker crash is retried once by the still-authorized
supervisor and exact-reopens the no-clobber roots. A controller restart only
waits for and revalidates the marker; it never launches a second `osascript`.
The supervisor is not installed, daemonized or persisted. If the supervisor
itself dies before the marker, recovery returns `STOP_PRE_AUTHORITY` and does
not claim PASS or replay an effect. This local run did not prompt for privilege
or execute any real Publisher, SSH, simulator, anchor or Task 2 action.

## Round 12 handoff correction — immutable-prefix recovery and complete marker root

The future privileged writer must preserve its original anchor claim across
the final-file publication window. Each fixed file is created with `O_EXCL`,
written, changed to `0444`, fsynced with its parent, and then receives
`UF_IMMUTABLE` through the still-retained descriptor. A crash immediately
before or after `fchflags` may be recovered only when the already validated
original privileged claim exists and the retained/fstatat object is the exact
same owner, mode, single-link inode, metadata and bytes. The writer then sets
or verifies the flag, fsyncs, rereads through the descriptor and revalidates
the parent entry. A byte-identical preexisting file without that claim STOPs;
it is never retroactively adopted.

The terminal marker reader no longer accepts nine posterior files as a
sufficient root. It requires exactly eighteen authority-fixed paths: the prior
nine plus `pre-anchor.json`, `writer-output.json`,
`terminal-final-scan.json`, and the claim/receipt/result objects for both
`INVOKE_WRITER` and `VERIFY_ANCHOR`. It rejects a missing or extra terminal or
phase-directory entry, reopens every file as root-owned single-link `0444`
`UF_IMMUTABLE`, revalidates directory identity/mode, and recomputes authority,
all generations, path hashes, phase triples/graph, physical observations,
settlement, scan, COMPLETE and marker hashes. Only this exact transitive root
permits `TERMINAL_PASS`.

Round 12 remained local and synthetic. No external authority, privilege,
network, SSH, simulator, real anchor or continuation task was used; future
execution remains `STOP_PRE_AUTHORITY` until those external roots are supplied.

## Round 13 handoff correction — canonical terminal corpus validation

The future `status`, `resume` and terminal-output paths must call one canonical
terminal-corpus validator, not marker-only or abbreviated authority checks.
That validator applies the same exact-key privileged-writer authority receipt
validator used at publication, with independent expectations from the fixed
operation authority, retained root writer executable and frozen terminal
manifest. It then validates the complete Swift pre-anchor schema: authority
tree/manifest/components, all generations, writer source/binary/signature and
original claim, fixed authority/anchor paths, ordered external-authority and
phase-target arrays and their recomputed hashes, six ordered scan roots, all 24
Important IDs, UTC timestamp, pending state and closed boolean policy.

Settlement, phase receipts/results, COMPLETE roots and the receipt-last marker
are validated in the same call. A corpus whose invalid authority or pre-anchor
is rehashed through settlement, COMPLETE and marker still STOPs. Exact-existing
revalidation is deterministic. These local validators supply no external
issuer, writer authority or privileged artifact; operational execution remains
`STOP_PRE_AUTHORITY` and Round 13 ran no real action.

## Round 14 handoff correction — all 71 evidence roles are semantic inputs

The future common marker reader MUST execute the fixed absolute immutable
terminal-writer binary in its read-only `--validate-manifest` mode before it
can accept a terminal corpus. That mode calls the identical Swift
`validateManifest()`/`validateSemanticRoots()` path used before publication: it
reopens all 71 evidence files and six scan receipts with no-follow physical
bindings and validates their exact role-specific schemas, purposes, attempts,
retry/raw policies, generations, fixed paths and complete provenance DAG. It
does not publish, mutate, prompt or acquire privilege.

The validator emits one closed hash-only semantic receipt bound to the exact
manifest, writer binary/signature/physical identity, ordered evidence roots,
scan roots and independently recomputed semantic roots. `RUN_SCANS` is reopened
as the initial predecessor; the two terminal contracts are rebuilt from the
canonical transition table. `INVOKE_WRITER` and `VERIFY_ANCHOR` claims must bind
the exact contract hashes and recomputed prior result, never values asserted by
the manifest. The common reader reexecutes this validation on every marker
read; it does not persist or accept a normal-user semantic receipt.

Any unavailable writer/external authority, changed evidence, role-class schema
mutation, disconnected predecessor or contract root remains STOP. This handoff
adds no real authority and performs no real operation; `STOP_PRE_AUTHORITY`
continues to govern future execution.

## Round 15 handoff correction — exact cross-language physical identity

Every future Node physical observation MUST use `lstat/stat({ bigint: true })`
through the retained descriptor and serialize the exact decimal integers in
this order: `uid;gid;mode&0777;nlink;size;mtimeNs;dev;ino`. It MUST NOT derive
nanoseconds from `mtimeMs` or pass identity fields through `Number` before
hashing. JSON metadata may convert bounded fields only after the exact hash is
formed and MUST STOP when a numeric schema field is not safely representable.

The Swift writer uses the identical field order and exact `st_mtimespec`
nanoseconds. Root terminal reads, descriptor transactions, scan/local reads,
capture evidence, SSH snapshots, Publisher authority materialization and
simulator install observations all share this boundary. A real local compiled
writer probe with sub-millisecond mtime MUST compare equal; changing one
nanosecond MUST STOP. This amendment supplies no authority and starts no real
operation.

## Round 16 handoff correction — promotion and simulator authority

The local publication promoter MUST obtain staging, parent, final-before and
final-after observations with `lstat(..., { bigint: true })`. It compares
`dev` and `ino` directly as BigInt, preserves BigInt mode/nlink/uid/gid checks,
and rejects a final directory whose exact identity differs from the staged
directory even when both values would collapse to one IEEE-754 Number.

The simulator container authority MUST likewise use a BigInt `lstat` of the
resolved container and the complete canonical eight-field physical identity
hash. A VPS/Mac handoff may bind only that exact hash; the former
`{dev,ino,mode}` Number-derived digest is not authority. Adjacent values
`9007199254740992` and `9007199254740993` MUST compare and hash differently.
No simulator or real publication is authorized by this correction.

## Round 17 handoff correction — generator owner-only reader

The generator's owner-only reader MUST retain all eight physical fields as
BigInt from entry-before through descriptor-before, descriptor-after and
entry-after. Stable identity compares canonical exact integers and MUST reject
Number projections, including sizes `9007199254740992` and
`9007199254740993` that collapse under IEEE-754.

Original-claim, exact-existing, staging and recovery reads use this same
reader. Its identity SHA uses the controller/Swift field order
`uid;gid;mode&0777;nlink;size;mtimeNs;dev;ino`. Only bounded owner/mode/link
schema checks may convert through an explicit safe-integer gate; `size`,
mtime, device and inode never do. This handoff supplies no authority and
authorizes no real generator execution.

## Atualização operacional 1.7.2 — Node runtime capsule imutável para a ponte CI-3

O STOP do runtime permanece evidência válida. `/usr/bin/node` é aceito somente
como bootstrap exato, nunca alterado, e o Node NVM é rejeitado. A arquitetura
`PRIVATE_VERSIONED_IMMUTABLE_NODE_RUNTIME_CAPSULE_V1` autoriza uma cópia
privada version-addressed, root-owned, `0555`, single-link e com immutable flag
real. Receipt `0444` e diretório final `0555` também são imutáveis.

O builder Git-bound tem apenas `--self-test`, `--create` e `--verify`. Claim
O_EXCL/fsync precede um único capability probe e a cópia; o probe remove `i`
somente de seu próprio arquivo sintético. A publicação é no-clobber, sem alias,
e exact-existing exige claim original. Closure dinâmica é inventariada e
ligada por count/hash antes e depois; bibliotecas do SO não são chamadas de
imutáveis.

Há duas authorities: bridge components/generator permanecem em
`ba8473799a19aec586b0fe706bb7d4084589c86c`; o runtime usa o commit filho com
subject `build(ops): authorize immutable VPS Node runtime capsule`. Depois do
capsule PASS, o generator roda em worktree detached limpa no SHA da bridge e
somente pelo Node capsule. Bridge output continua endereçado por `ba847...`.

Os gates sintéticos atuais são 127/127 e self-test 8/8, sem rede, secret read,
system/NVM/package mutation. A execução real fica bloqueada até publicação da
runtime authority. Primary/live, Supabase, Vercel, produção, Mac, simulador,
CI-3 Task 2, CI-4 e cleanup permanecem zero.

## Atualização operacional 1.7.3 — STOP preservado na closure do runtime

A runtime authority foi publicada em
`f039fe38b35084a33a4b7a3649b1112f26a93fb2`, parent exato `ba847...`, após
127/127 testes, self-test 8/8 e duas revisões em zero Critical/Important/Minor.
O builder foi materializado exclusivamente do blob publicado, com owner
root:root, modo `0600`, single-link, no-clobber e readback exato.

A única invocação autorizada de `--create` terminou fail-closed com
`ERROR DYNAMIC_CLOSURE`. O diagnóstico read-only mostrou sete entradas no
`ldd` atual e duas entradas symlink. O reader publicado exige arquivo regular
direto e rejeita essas duas entradas antes de canonicalizá-las. A falha ocorreu
antes de claim, probe, cópia, staging ou final; ainda assim o budget lógico do
runtime está consumido `1/1` e não pode ser repetido.

Somente o snapshot versionado do builder permanece. Capsule, claim, staging,
probe, bridge root e bundle estão ausentes. `/usr/bin/node`, NVM, manager e os
25 itens históricos permanecem inalterados. O generator da bridge não foi
executado e seu budget continua `0/1`. Próximo gate exige nova authority que
corrija explicitamente a canonicalização no-follow da closure e autorize uma
nova tentativa; esta execução não realiza esse gate.

## Atualização operacional 1.7.4 — baseline full-path e closure no-follow V2 do Node capsule

O STOP_PRE_AUTHORITY posterior ao V1 foi correto: `2 symlink / 5 direct`
classificava somente o componente final, enquanto o walk obrigatório considera
todo o pathname. Duas observações independentes congelaram 7 loader entries;
7 atravessam algum symlink, 0 atravessam zero, 2 terminam em symlink, 5
terminam regulares e são intermediate-only, com 9 hops totais, máximo 2, 7
targets regulares únicos e zero duplicatas. Os três hashes sanitizados são os
publicados na evidence V2; nenhum path bruto é documentado.

`PRIVATE_VERSIONED_IMMUTABLE_NODE_RUNTIME_CAPSULE_V2` usa
`NOFOLLOW_COMPONENT_CANONICALIZATION_V1`: walk por `lstat/readlink`, parent
root-owned sem escrita group/other, limite/ciclo, revalidação da chain e leitura
final única via `O_NOFOLLOW`. Claim V2 O_EXCL/fsync precede o `ldd` operacional;
o capture root-only O_EXCL/fsync permite recovery sem novo source `ldd`. V1
permanece congelado em 1/1; V2 recebe budget novo 1/1 somente após authority
remota e reviews 0C/0I.

O probe publica seu receipt durável antes da própria limpeza, impedindo replay
após crash. O Node final é congelado antes de sua identidade ser ligada; o
receipt é o último arquivo publicado. O gate autoritativo concluiu 264/264
testes, self-test 8/8, duas reproduções reais da baseline e Reviews A/B com
zero Critical/Important.

Bridge components continuam em `ba847379...`; apenas o runtime usa a authority
V2. Mac handoff e CI-3 Task 2 permanecem bloqueados até runtime e bundle VPS
PASS. Credential não é copiada, service role/valores não são emitidos e o
cleanup da fixture segue reservado a outra operação, com deadline preservado
`2026-09-11T11:44:11.182Z`.

## Atualização operacional 1.7.5 — STOP preservado no verify do Node capsule V2

A authority V2 foi publicada em
`b08e6326fbd22c96b852ccfe53abdeb254e54bd1` e seu builder Git-blob foi
materializado e validado. A única tentativa `--create` foi consumida `1/1`.
Ela publicou claim, capture, probe receipt, Node, runtime receipt e diretório
final, mas terminou `ERROR UNEXPECTED` durante o verify obrigatório.

O diagnóstico read-only confirmou closure 7/7/0, 2/5/5, 9/max2, três hashes,
bindings e três immutable flags. A causa é uma precedência incorreta na
expressão que compara a projeção do capability probe: o retorno de
`JSON.stringify` é chamado como função. Como o verifier publicado não retornou
PASS, o estado oficial é `PARTIAL_PRESERVED`, mesmo com artefatos fisicamente
completos. Não houve segunda invocação, thaw, cleanup ou bridge.

V1 permanece 1/1 congelada e bridge 0/1 ausente. System Node, NVM, manager,
fixture e sistemas externos estão preservados. Mac, simulador, CI-3 Task 2 e
CI-4 continuam bloqueados. O próximo gate é uma nova authority para corrigir o
verifier e adotar read-only o capsule existente; é proibido repetir create,
source/capsule `ldd`, probe ou `chattr`.

## Atualização operacional 1.7.6 — adoção read-only do Node capsule V2 após fix do verifier

O STOP `030aa2be4e2facc5edbcda143c18a8477e727855` permanece válido. A
tentativa V2 continua consumida `1/1`; o capsule não será recriado, reparado,
descongelado nem limpo. A evidência física confirma que claim, capture, probe
receipt, Node, runtime receipt e diretório final publicados pela authority
`b08e6326fbd22c96b852ccfe53abdeb254e54bd1` estão completos e imutáveis. O
runtime receipt conserva SHA-256
`577fff150c608bfa848c7e9775e92cd02ed427a83484e859480b3e2607a94744`.

A causa exata do STOP é isolada no verifier antigo: a projeção do capability
probe sofre precedência incorreta e tenta chamar o texto retornado por
`JSON.stringify`. A reprodução sintética falha com o `TypeError` esperado,
depois da publicação física, sem filesystem real. O builder V2 e seus testes
permanecem byte-idênticos.

Esta authority adiciona somente
`READ_ONLY_NODE_RUNTIME_CAPSULE_V2_ADOPTION_VERIFIER_V1`, com modos fechados
`--self-test` e `--verify-existing`. Um claim O_EXCL/fsync separado precede a
abertura dos artifacts; a closure é revalidada exclusivamente pelo capture
durável com walk no-follow. Owner, mode, nlink, hashes, identities e três flags
imutáveis são conferidos, seguidos por smoke bounded no Node capsule e por
verificação bootstrap/self-hosted sem segundo claim. O receipt de adoção é
externo ao capsule, version-addressed e publicado por último. Controles
operacionais permanecem `create=false`, `ldd=false`, `probe=false`,
`chattr=false` e `capsule_mutation=false`.

Somente depois da authority remota e de uma adoção PASS o budget ainda intacto
da bridge `ba847379...` pode ir de `0/1` a `1/1`, usando exclusivamente o
capsule adotado. Até lá, Mac, simulador, CI-3 Task 2, CI-4, fixture cleanup,
Supabase, Vercel, banco, primary/live e produção permanecem bloqueados.

## Atualização operacional 1.7.7 — capsule adotado e STOP preservado na bridge CI-3

A authority do verifier foi publicada em
`461a2e0dbe091a5c352d5dfdc1952b444f41aac0`. O snapshot Git-bound foi
materializado root-only e a única tentativa de adoção read-only retornou PASS.
Claim e receipt externos foram publicados; o receipt de adoção tem SHA-256
`1cd3843745c3bfa759d3e99f15a92651a8462610089bfb31175fba49b58ec0d3`.
Node, runtime receipt, diretório, closure e três immutable flags permaneceram
exatos. Não houve create, nova descoberta de closure, probe, attribute mutation
ou capsule mutation.

Depois desse PASS, a worktree detached limpa `ba847379...` e o generator de
blob exato passaram sintaxe, 154/154 testes e self-test 8/8 pelo capsule
adotado. A primeira e única invocação real da bridge, contudo, terminou
`ERROR GIT_AUTHORITY` antes de claim, source-secret read ou output. O reader
Git publicado limita cada `cat-file` a 64 KiB, enquanto o próprio blob do
generator tem 82.675 bytes; a ingestão autoritativa é encerrada pelo limite.

O budget da bridge está consumido `1/1`, sem claim, staging, generation,
config ou receipt. Não existe remote generation para transportar ao Mac.
A adoção do runtime permanece `VERIFIED_ADOPTED_READ_ONLY`; bridge fica STOP.
Próximo gate requer nova authority para corrigir o reader Git e conceder nova
tentativa explícita da bridge. Esta operação não executa essa correção, não
repete `--create` e não inicia Mac, simulador, CI-3 Task 2, CI-4 ou cleanup.

## Reconciliação Bridge V2 — reader bounded e gate zsh por ambiente

O STOP 1.7.7 permanece válido: a Bridge V1 `ba847379...` consumiu 1/1 antes
do claim porque o reader de 64 KiB não comportava o blob de 82.675 bytes.
A sucessora usa `BOUNDED_GIT_OBJECT_READER_V2`, limite explícito de 1 MiB,
type/size preflight e postflight, body assíncrono com timeout, stdout/stderr
bounded, SHA-256 incremental, tamanho exato, zero retry e zero body reread.

O launcher continua sendo um entrypoint exclusivo do Mac. A VPS não possui
zsh e isso é o estado esperado: `VPS_ZSH_SYNTAX_EXECUTION=NOT_APPLICABLE`.
Não instalar zsh, não criar runtime zsh e não usar Bash como equivalente. O
skeleton estrutural do launcher atual e o último blob validado no Mac é o
mesmo (`ad3ab9d577d413c611bf000f1a64ef351e7060f5eb068dfca11879c163dfc1a8`);
somente manifest data, parent e subject mudaram.

O primeiro gate do futuro handoff Mac é
`MAC_GATE_0=EXACT_LAUNCHER_ZSH_SYNTAX`. Antes de simulador, bootstrap claim,
SSH ou qualquer remote read, o Mac deve materializar o blob exato, validar o
runtime literal `/bin/zsh`, executar uma única vez `/bin/zsh -n` com stdout e
stderr vazios, provar launcher unchanged e publicar
`mac-zsh-syntax.receipt.json` owner-only/no-clobber. Falha implica zero rede,
zero claim, zero stream e STOP sem retry.

A authority sucessora altera exatamente os 14 paths fechados da Bridge V2 e
usa o subject `build(ops): authorize bounded Git blob reader for CI-3 bridge`
com parent `92cccf3dca21a29d601d2f274a67ea2ba284914b`. O receipt remoto registra o
gate zsh como deferred ao Mac, nunca como PASS na VPS. Runtime Node V2,
Bridge V1, inputs, fixture, CI-3 Task 2, CI-4 e sistemas externos permanecem
preservados até a publicação e a única tentativa autorizada da Bridge V2.

## STOP terminal Bridge V2 — staging env receipt incompatível

A authority V2 foi publicada e confirmada no remoto em
`c8e1d00c8d43912e55c5ecae3b2e3d84ae232026`. O generator exato foi
materializado pelo blob Git em worktree detached limpa e seu self-test passou
8/8 pelo Node capsule V2 adotado. A única invocação `--create` autorizada
terminou `ERROR ENV_RECEIPT_STATE`; o budget V2 está 1/1, sem retry.

O STOP ocorreu antes de claim, staging, generation, config ou receipt. O
diagnóstico read-only encontrou sete divergências semânticas no receipt de env
existente: purpose, marcador legacy-key, classificação de elevated exposure,
classificação de required permission e as classificações das três variáveis.
Nenhum valor bruto foi reportado e nenhum input foi alterado.

O snapshot Git-bound, o capsule e os cinco inputs permanecem preservados. A
classificação zsh continua deferred ao Mac, não bypassed, mas o handoff Mac não
pode começar porque não existe bundle remoto. Próximo gate é uma nova authority
na VPS para reconciliar explicitamente o contrato do staging env receipt e
conceder uma tentativa sucessora; não repetir a Bridge V2.

## Atualização operacional 1.7.10 — contrato canônico do receipt de staging da ponte CI-3

A proveniência do receipt foi revalidada pelo hash físico, pela authority
original de control-plane e pelo primeiro commit documental que registrou o
mesmo hash. Seus sete valores canônicos são purpose com hífens, legacy-key
true, exposição local `no`, permissão `api_gateway_keys_read` e as três
classificações específicas de URL, anon e service-role. Nenhuma authority
posterior os reclassificou; o generator V2 introduziu os aliases incorretos.

A authority sucessora mantém V1/V2 consumidas, reader bounded, capsule adotado,
zsh deferred ao Mac, hashes e gates de staging/preview/produção. Ela altera
somente os 15 paths fechados e concede uma tentativa independente após GREEN,
scans, duas reviews e publicação remota. Não há mutação do receipt, emissão de
valor, execução do handoff Mac, CI-3 Task 2, CI-4, produção ou cleanup.

## Atualização operacional 1.7.11 — STOP pre-attempt no deployment receipt

A authority canônica foi publicada e o snapshot Git-bound passou self-test e
leitura bounded dos 15 blobs. O env receipt físico passou integralmente o
contrato reconciliado. Antes de `--create`, porém, o próximo gate detectou duas
divergências semânticas no deployment receipt preservado: `purpose` e `node`.

Nenhuma tentativa sucessora foi consumida (`0/1`), e não existe authority root,
claim, staging, generation, config ou receipt. O snapshot, capsule, adoption,
cinco inputs e V1/V2 permanecem preservados. Próximo gate é uma nova authority
para reconciliar explicitamente o deployment receipt; Gate 0 do Mac, CI-3 Task
2, CI-4, produção e cleanup continuam não executados.

## Atualização operacional 1.7.10 — contrato canônico do deployment receipt da ponte CI-3

O STOP anterior permanece válido. O receipt físico, root-only e hash-bound,
prova o purpose literal `ci3-dedicated-mobile-bff-deployment`, o Node Vercel
literal `22.x`, framework `nextjs`, root `apps/mobile-bff` e a authority de
recuperação do Preview `7b08e67c81e63b3302de6d8642b3855f5ec60ed9`.
O commit final do Preview é `34636d321d5d5fa2d108a88ffda2dc2a7072de90`.
Nenhum receipt ou secret foi alterado.

A nova arquitetura é
`VERSIONED_REMOTE_BRIDGE_ARTIFACT_V2_BOUNDED_GIT_BLOB_STREAMING_WITH_CANONICAL_INPUT_CONTRACTS_V1`,
com parent `70a7d60dd9c4224e3be9072ce5fbd966bd534560`, subject
`build(ops): reconcile remaining CI-3 bridge input contracts` e 16 paths fechados.
`deploymentReceipt.node=22.x` descreve exclusivamente a configuração/runtime
Vercel; o capsule privado executado na VPS continua ancorado nas authorities
`b08e6326fbd22c96b852ccfe53abdeb254e54bd1` e
`461a2e0dbe091a5c352d5dfdc1952b444f41aac0`. Os dois contratos não são
normalizados nem comparados.

Bridge V1 e V2 permanecem consumidas sem retry. `c5172be7…` permanece
`0/1_NOT_EXECUTED_SUPERSEDED`, sem claim/output, e nunca pode ser executada.
A authority sucessora recebe orçamento independente `0/1` somente após testes,
preflight dos cinco inputs, scans, duas reviews sem Critical/Important,
publicação e readback remoto. Zsh continua N/A na VPS e `/bin/zsh -n` permanece
Gate 0 obrigatório no Mac antes de rede. CI-3 Task 2, CI-4, produção e cleanup
continuam bloqueados nesta fase.

### STOP pre-authority durante o preflight integral

O preflight read-only dos cinco inputs revelou uma divergência adicional em
`CREDENTIAL_STATE`: somente o contrato de `synthetic_marker` não corresponde à
expectativa herdada; o valor físico não foi relatado. Schema, environment,
cleanup flag, key set, metadata e hash da credential permanecem exatos. Como a
authority desta rodada autorizava apenas purpose/node do deployment receipt,
nenhum commit/push ou tentativa foi permitido. Próximo gate:
`RECONCILE_ADDITIONAL_BRIDGE_INPUT_CONTRACT`.

### Contratos completos dos cinco inputs

A authority histórica `e4159e85…`, o launcher contemporâneo e os artifacts
hash-bound provam que `synthetic_marker` é específico da operação, no formato
fechado `ci3-synthetic-YYYYMMDDTHHMMSSZ-[A-Z2-7]{16}`. Ele coincide entre
claim, credential, recovery e provisioning, relaciona-se byte-exact ao e-mail
no domínio reservado e permanece distinto do e-mail canonicalizado pelo Auth e
de todos os IDs da fixture. Somente seu SHA-256 sanitizado é documentado:
`9f768034584af72f213b9d89816d4f1d506141a37375477369a4817180e4bdd3`.

O provisioning receipt físico exige purpose `ci3_authenticated_today`,
authority `5cecaa7…`, cleanup class `CREATED_AT_PLUS_14_DAYS`, canonicalization
class `NORMALIZED_ALIAS_DOCUMENTED`, progress `1`, settlements `0/0` e HTTP
counts patient/service `1/7`. Todos foram classificados como
`GENERATOR_EXPECTATION_BUG`; os inputs permaneceram imutáveis.

O novo `--preflight-inputs` usa os mesmos readers e a mesma
`validateSourceDocuments` do `--create`. O preflight físico passou env,
deployment, credential, provisioning e relações cruzadas, com zero write,
claim, output, receipt, rede, SSH ou primary/live. Marker, e-mail e senha não
foram emitidos. A authority só pode ser publicada após testes, scans e duas
reviews 0C/0I; a única tentativa real permanece posterior ao readback remoto.

## Atualização operacional 1.7.11 — bundle canônico dos cinco inputs publicado

A authority de 16 paths foi publicada e confirmada no remoto em
`7a929b0cebb28c339010dd5bf115e67b79523156`, parent
`70a7d60dd9c4224e3be9072ce5fbd966bd534560`, tree
`902a89cab73ebe5ea78b246a9961aa20a6eaaf96`, subject
`build(ops): reconcile remaining CI-3 bridge input contracts`. O generator
versionado foi materializado do blob Git exato, passou novamente syntax,
426/426, 708/708, 22/22, 4/4, self-test 8/8 e o preflight integral.

A única tentativa autorizada foi consumida 1/1 e terminou `CREATE PASS`. O
claim durável precedeu a publicação; a geração remota é
`rb-b1ec265eb71070f50932a4d7af8af5fed4ba4937c8858319d3550b76a04880ad`.
Receipt e config passaram readback físico no-follow, owner-only, single-link e
hash-bound. Seus hashes são, respectivamente,
`349842c03aaaa039ddaf0da9e14ccb6b7793618cb346ab301de7f45fa146c10d` e
`5132de192dba24912d65aa61228606864e3e86a56c04593cf63126c66554ee2a`;
os path hashes são `e76eac812e1aff61a19f9e3797f3a4b90da56eddadaba2e0b43c71c69d21c8a2`
e `ee92379f73ed156ebbbb5141ea4b8efe83de6aba40925e2643c97e789a868ba8`.

A credential não foi copiada: path hash
`3ece3ed674cd3ffd605565f05170297b549fa50fcf9c9ad1a8ea1bfe1702a677`,
SHA-256 `d36c96998b5879150d5dbd45a8118de0e50b24a815f5ff5cbeb0d87d449d8208`.
O marker permanece representado somente pelo SHA-256
`9f768034584af72f213b9d89816d4f1d506141a37375477369a4817180e4bdd3`.
Marker, e-mail, senha e service-role brutos tiveram zero matches no bundle.
Inputs e capsule permaneceram byte-idênticos; nenhuma ação Vercel, Supabase,
banco, primary/live, produção, simulador, CI-3 Task 2, CI-4 ou cleanup ocorreu.

O próximo ambiente é o Mac local. O primeiro gate permanece a materialização
dos 16 blobs exatos e `/bin/zsh -n` do launcher antes de qualquer rede, claim,
SSH ou remote read. Este handoff não foi executado na VPS.

## Atualização operacional 1.7.12 — bootstrap Git limitado antes do Gate 0 do Mac

O STOP reportado pelo Mac é válido: a documentação terminal, a authority da
bridge ou o launcher exato ainda não estavam disponíveis no object database
local, enquanto a authority 1.7.11 proibia toda rede antes do Gate 0. Isso
formava uma circularidade, pois `/bin/zsh -n` exige primeiro os bytes exatos do
launcher.

`PRE_GATE0_GIT_OBJECT_BOOTSTRAP_V1` resolve somente essa disponibilidade. O
Mac começa com um preflight local. Se a nova authority de object-bootstrap
informada neste handoff, seu parent documental, a authority
`7a929b0cebb28c339010dd5bf115e67b79523156` e o blob do launcher já existirem
e validarem, usa zero fetch. Se algum objeto faltar, pode executar no máximo uma
invocação lógica de `git fetch`, sem retry, tags, prune, submodules, shallow,
force-refspec, checkout, pull, merge ou rebase, atualizando somente
`refs/remotes/origin/codex/better-ahead-rebranding-design` a partir do origin
HTTPS exato `https://github.com/corehealth-app/agentempp.git`.

Esse tráfego é exclusivamente `code-provenance network`: transporta commits e
blobs Git públicos/privados já versionados. Não é `operational network` e não
pode alcançar a VPS operacional, bundle, config, credential, secrets,
simulador, SSH, remote reads ou claims. Depois do fetch opcional, a execução
revalida ref, lineage, authority, manifesto de 16 paths, mode/OID/SHA do
launcher e a invariância das duas worktrees. Qualquer falha ou ambiguidade
termina em STOP sem Gate 0 nem segunda tentativa.

O Gate 0 não foi reduzido. Após o bootstrap, e antes de simulador,
`/usr/bin/ssh -G`, SSH, três remote reads, claims ou qualquer rede operacional,
o Mac materializa o blob exato
`918de148626fbfa642a4ac97a1e2057092ecffb8` e executa uma única vez
`/bin/zsh -n`, exigindo exit zero, stdout/stderr vazios e identidade estável. O
receipt liga a authority desta reconciliação, a authority da bridge, o launcher,
o fetch count 0 ou 1 e a prova de que não houve rede operacional antes do gate.

O bundle VPS permanece PASS e não foi recriado ou alterado: geração
`rb-b1ec265eb71070f50932a4d7af8af5fed4ba4937c8858319d3550b76a04880ad`,
receipt SHA-256
`349842c03aaaa039ddaf0da9e14ccb6b7793618cb346ab301de7f45fa146c10d`
e config SHA-256
`5132de192dba24912d65aa61228606864e3e86a56c04593cf63126c66554ee2a`.
Credential e service role não fazem parte do bootstrap. A VPS não executou o
handoff Mac, simulator, CI-3 Task 2, CI-4, cleanup ou qualquer escrita em
Vercel, Supabase, banco, primary/live ou produção.

O próximo ambiente continua `MAC_LOCAL`; o próximo gate continua
`FETCH_VERSIONED_CI3_BRIDGE_BUNDLE_AND_RESUME_CI3`, agora precedido somente
pelo bootstrap Git bounded aqui autorizado e seguido imediatamente pelo Gate 0.

## Atualização operacional 1.7.13 — executor Mac compatível da ponte CI-3

A compatibility suite Mac preservou STOP em `1323/1409`, com 86 falhas, zero
skip/todo e 86 identificadores classificados. Os quatro grupos foram provados
por RED focado antes do GREEN: helper descriptor Darwin materializado (3),
fixture writer completa (75), separação entre modos físicos owner-only e modos
Git (1), e policy explícita de repository identity Mac com suporte ao sufixo
atestado do Apple Git (7). As classificações são Mac operational, cross-platform
protocol e VPS+Mac operational, sem bypass de plataforma.

A authority sucessora é `MAC_EXECUTOR_AUTHORITY_V1`, parent
`65a06d3e7426117ea80679933f6a7bb611be5988`, subject
`build(ops): authorize mac-compatible CI-3 bridge executor` e manifest exato de
17 paths. Ela não substitui a authority remota predecessora
`7a929b0cebb28c339010dd5bf115e67b79523156`: bundle, cinco inputs, config,
receipt, derivação e claims permanecem read-only. Verdict:
`REMOTE_BUNDLE_COMPATIBILITY=REUSE_READ_ONLY`.

Nenhuma operação externa foi executada nesta authoring task: zero network
operacional, simulator, SSH, remote read, privilégio, CI-3 worktree ou produção.
Depois de reviews independentes, a publicação futura precisa produzir um novo
Gate 0 `/bin/zsh -n` sobre os blobs exatos; o receipt antigo não é reutilizável.
O cleanup deadline preservado é `2026-09-11T11:44:11.182Z`.

## Atualização operacional 1.7.14 — correções da review Mac do executor

O normalizador estrutural voltou a ser byte-idêntico ao contrato do generator
remoto; nenhuma declaração nova é apagada do skeleton. O predecessor remoto
permanece ligado pelo controller/writer e pelo manifesto da authority Mac, não
por uma exceção alcançável no caminho Linux/root. Portanto o bundle existente
continua candidato a `REUSE_READ_ONLY` sem rerun do generator.

A cadeia Mac passa a ligar simultaneamente executor, launch attestation,
authority/generation/receipt/config remotos, object-bootstrap e base CI-3 por
um digest canônico sem valores brutos. O launch attestation faz o primeiro
binding pelo manifesto de 17 paths; bootstrap e local receipt carregam o digest;
o writer o recompõe da evidência antes de aceitar a cadeia.

O reader current-UID agora possui rota Darwin realmente alcançável antes do
launcher: um request privado seleciona um único blob local por OID/hash, que é
materializado no-clobber e produz receipt sanitizado com zero rede. O dispatcher
Linux/root e seus três modos permanecem inalterados. Esta authoring task não
executou fetch, Gate 0, SSH, simulator, remote read, privilégio ou CI-3.

## Registro complementar — provenance Git completa antes do Gate 0

A grammar genérica de `git --version` voltou ao acceptance set exato do
predecessor. O sufixo Apple só é aceito depois que a policy Darwin explícita
valida plataforma, UID, root e attestation; policy ausente no Linux/root não
altera a criação remota. `parseMode()`, schemas, cinco inputs, derivação,
claims/publicação e manifesto remoto de 16 paths permanecem preservados.

O request object-bootstrap V2 liga commit executor, parent/lineage exatos,
tree, subject hash, raiz literal do manifesto de 17 paths e o mode/path/OID/hash
do alvo. O reader prova commit/tree e todos os `ls-tree` antes de qualquer body,
verifica o conteúdo bounded de todos os 17 entries e materializa somente o alvo
em `0600`, no-clobber. O blob órfão deixou de ser aceito.

Não existe mais receipt isolado nessa fase: sucesso da CLI tem stdout/stderr
vazios. O primeiro receipt continua sendo o launch attestation versionado do
Gate 0 `/bin/zsh -n`; bootstrap, local receipt e writer consomem o hash desse
gate pela cadeia dual-root. Nenhum fetch, Gate 0 operacional, SSH, simulator,
remote read, privilégio, CI-3 ou produção foi executado nesta correção local.

## Registro terminal 1.7.14 — STOP_PRE_AUTHORITY do executor Mac publicado

A authority sucessora do executor Mac foi publicada com os 17 paths exatos,
parent e subject exigidos, suite final `1460/1460` e duas reviews independentes
com `0 Critical / 0 Important`. Os 86 failures originais permanecem
contabilizados em quatro root causes comprovadas, sem unresolved, skip, todo ou
expected failure. A compatibilidade final é `REUSE_READ_ONLY`: generator,
schemas, cinco inputs, generation/path e claims/publicação remotos não mudaram;
o bundle remoto continua um predecessor distinto e read-only.

Os blobs publicados foram materializados pelo object database local, sem novo
fetch, com no-clobber, owner-only, `fsync` e readback. A suite publicada passou
`1460/1460`, o writer compilou e o novo Gate 0 `/bin/zsh -n` passou com exit 0 e
stdout/stderr vazios. Um receipt versionado novo foi preservado junto do receipt
histórico, sem reutilizá-lo.

O primeiro preflight pós-Gate-0 encontrou ausentes o
`ci3-publisher1-bootstrap` root-owned e o `ci3-controller-authority` externo.
O launcher fixo rejeita corretamente qualquer modo operacional fora dessa
cadeia autenticada e proíbe usar a worktree como Publisher 0. Como o issuer,
materializer e runtime externos necessários não estão provisionados no Mac,
o resultado terminal é `STOP_PRE_AUTHORITY` antes de simulator, `ssh -G`, SSH,
claims, três reads, bundle local, scans, writer, anchor ou CI-3 Tasks 2–12.

Não houve escrita em VPS, Supabase, Vercel, banco, primary/live, produção ou
fixture; também não houve cleanup, CI-4, PR, merge, deploy, TestFlight ou App
Store. Os cinco paths da worktree CI-3 seguem preservados. Durante tooling
pré-publicação houve uma exposição local acidental de metadados de commit e
identificadores não secretos; nenhum valor de config/credential/token foi
transferido e o desvio fica registrado, sem repetir os valores.

Próximo gate: provisionar externamente o Publisher 1 imutável e autenticado
para esta mesma authority do executor Mac. A retomada deve consumir o Gate 0
novo preservado, executar simulator antes de `ssh -G`, manter exatamente três
reads sem retry/refetch e publicar a terminal anchor antes de qualquer mutação
da CI-3.

## Atualização operacional 1.7.15 — cadeia externa Publisher 0/Publisher 1 da CI-3

Esta atualização autoriza somente a autoria local e sintética da cadeia externa.
O modelo tem três authorities separadas: o executor Mac já publicado, o issuer/
pass do Publisher 0 e o materializador/bootstrap do Publisher 1. A ligação é
feita por lineage, geração, manifests canônicos, identidades físicas e receipts
sanitizados; `raw_values=false` é obrigatório em toda projeção.

O Gate 0 preservado continua sendo a única attestation de launcher utilizável.
As roots externas Publisher 0, issuer/pass, transporte, autorização humana e
Publisher 1/controller permanecem ausentes e, portanto, o estado operacional
continua `STOP_PRE_AUTHORITY`. Nenhum valor congelado, byte de configuração,
credencial, host ou chave foi exposto nesta atualização.

Evidência local corrente: 223/223 testes da cadeia externa, 143/143 do
instalador Publisher 1 e 161/161 do writer congelado, todos sem falhas, skips
ou todos. O registro publicado anterior de 1460/1460 e o Gate 0 preservado não
foram reexecutados nem reinterpretados. O bundle remoto permanece inalterado.
Não houve rede, VPS, SSH operacional, prompt administrativo, simulador,
escrita root, CI-3 subsequente ou produção.

A continuação ordenada exige uma autorização humana nova e explícita no estágio
próprio, Publisher 0 externo com tentativa única, transporte allowlisted,
Publisher 1 imutável e readback do controller, antes de qualquer simulador ou
SSH operacional. Os budgets de prompt e operação são fechados, sem retry. O
deadline de cleanup previamente preservado continua aplicável; nenhum cleanup
foi executado nesta authoring task.

## Atualização operacional 1.7.16 — successor semantic-safe local

O `STOP_PRE_AUTHORITY` do predecessor permanece válido. Esta autoria local não
publicou uma nova authority operacional e não reutiliza o Gate 0 histórico. O
successor exige um Gate 0 novo, posterior à materialização e verificação dos
blobs exatos, antes de qualquer Publisher ou gate operacional.

A remediação cobre as causas originais: os semantic guards antes ausentes na
integração agora pertencem ao mesmo validator Swift usado pelo writer; a
validation binary e a operational binary têm capabilities disjuntas; nenhum
candidato mutável do usuário pode ser o executor privilegiado; Publisher 0
produz issuer, pass e transporte antes de qualquer consumo; e request-byte
swap e receiver-leaf swap são negativos independentes. As contagens antigas
de 223, 143, 161 e 1460 são somente evidência histórica, não resultado atual.

A ordem local comprovada é: authority sucessora sintética, blobs exatos, Gate
0 novo, Publisher 0, issuer/pass, transporte, captura owner-only, receiver,
request, autorização humana, identidades físicas finais, semantic preflight,
Phase A do installer imutável, Phase B/Publisher 1, readback, operation
authority, controller de dezesseis targets, settlement e somente depois gates
de simulador. A Phase A instala apenas o próprio installer; somente o self
imutável e readbackado pode executar a Phase B com claim-before-effect.

A seleção do installer também deixou de ser uma autorização autoemitida: uma
compile authority independente fixa source, driver, compiler selecionado,
argumentos/proveniência e o digest binário esperado. A autorização humana
vincula essa authority e esse digest, o preflight Swift os repete e a Phase A
aceita somente bytes iguais ao digest esperado. A canonicalização successor
usa ordenação UTF-8 explícita e tem prova JS/Swift byte a byte inclusive para o
caso adversarial dígito/underscore. O contrato aceita somente o schema exato;
chaves adicionais são recusadas, não tratadas como extensão compatível.

A prova focada da remediação 1.7.16 passou 56 testes de ordem, 54 do seam
semântico, 10 do installer imutável, 3 de wiring real sem preseed, 7 negativos
preservados e 5 de controller/downstream, além de 1 negativo independente de
seleção do installer. As execuções completas 282/282 da cadeia externa,
153/153 do installer, 215/215 do writer e 1501/1501 do gate Mac de quatro
arquivos são o checkpoint histórico pré-review da 1.7.16, não o resultado da
remediação 1.7.17. O modo de
operation authority é alcançável após Publisher 1; o privileged writer exige
os seis scans e o terminal anchor continua inacessível antes deles.

Generator remoto, schema, derivação de paths e input contract permanecem
inalterados e read-only. Não houve rede, SSH, simulador, prompt administrativo,
escrita root, produção, CI-3, retry ou cleanup. O deadline de cleanup já
registrado continua vigente.

## Atualização operacional 1.7.17 — successor review remediation local

A lineage sucessora agora exige parent e subject exatos no launcher e no
controller e recusa a authority predecessora. Publisher 0 inicia sem outputs
futuros: seus artefatos são produzidos pelo subprocesso fixo, capturados por
transporte autenticado e somente então recebidos. A autorização humana V2 é
criada independentemente depois do request e vincula authority, request,
receiver, dezesseis leaves, proveniência do installer e o budget único do
prompt não administrativo.

O primeiro boundary privilegiado é um driver macOS fixo, posterior ao
preflight e à reobservação do request, receiver e dezesseis leaves. Ele executa
os bytes exatos do supervisor Swift vinculados ao path e blob OID do Git; não
há verify-path/execute-path, seleção por candidato ou confiança em `argv[0]`.
Somente depois esse supervisor instala e readbacka o immutable self da Phase A;
a Phase B aceita apenas esse self. Recovery em crash antes ou depois do freeze
é determinístico e falha fechado, sem cleanup, refetch, retry ou nova tentativa.

O receipt canônico V2 é exact-schema e versionado de ponta a ponta. O validator
Swift compartilhado valida todas as chaves e relações; a mutation parity JS/
Swift cobre 103 alterações (97 remoções e 6 adições), todas recusadas. O
consumer real autentica request, issuer/pass, autorização humana e operation
authority, readbacka exatamente dezesseis targets, publica settlement e torna
a authority do later writer alcançável somente na ordem autorizada. Essa prova
usa seams apenas no boundary de privilégio; não fabrica authority nem substitui
o consumer de produção.

O focused gate consolidado da 1.7.17 passou 150/150: 1 launcher-lineage, 10
controller, 70 cadeia externa, 13 installer e 56 writer, sem falha,
cancelamento, skip ou todo. O fechamento serial passou cadeia externa 293/293,
installer 156/156, controller 740/740, launcher 115/115, writer 217/217 e
generator 434/434. O primeiro gate agregado expôs uma regressão estrutural do
launcher (1505/1506); após restaurar o skeleton predecessor sem alterar o
generator nem enfraquecer assertions, o rerun agregado passou 1506/1506, com
zero fail/cancel/skip/todo. Generator remoto, schema,
derivação de paths e input contract seguem read-only; não houve rede, SSH,
simulador, prompt administrativo, privilégio real, escrita root, produção,
CI-3, stage, commit, push, retry ou cleanup. O estado segue
`STOP_PRE_AUTHORITY`.

## Atualização operacional 1.7.18 — successor round-2 local

Esta seção substitui qualquer alegação arquitetural 1.7.17 incompatível com a
remediação round-2. O dispatcher macOS atravessa o mesmo subprocess boundary
limitado usado pelo restante da cadeia, com argumentos sem LF/NUL, delimiter
`swift - --privileged-supervisor`, um único prompt e seleção atômica pelo
supervisor fixo. Nenhum prompt ou privilégio real foi exercido.

Publisher 0 materializa o helper remoto a partir dos blobs Git exatos no único
transporte SSH autorizado pelo contrato; receive é builtin e verify aponta ao
launcher instalado no modo de produção. A prova local usa fake spawn somente
no boundary de execução e o writer Swift compilado real para materializar e
reobservar claim, result e os dezesseis targets. Executável ausente falha antes
do primeiro attempt. A projeção de authority vem do pass assinado e dos
artefatos current-user disponíveis, sem depender de root congelado prévio.

A Phase B instala e readbacka nove objetos canônicos do bootstrap antes de
produzir o request de operation authority. Recovery cobre promoção/freeze da
Phase A e, no ledger externo, só aceita o settlement específico da operação:
verify não pode reutilizar settlement de Phase B. Claim, result, árvore de
dezesseis targets e receipt do controller precisam coincidir; estado ausente,
parcial ou divergente termina em `STOP_PRE_AUTHORITY`, sem respawn, retry,
refetch, prompt ou cleanup.

O schema V2 compartilhado permanece fechado e a matriz literal contém 103
mutações independentes, 97 por remoção e 6 por adição, com paridade JS/Swift.
Os testes completos atuais passam external 304/304, installer 158/158,
controller 743/743, launcher 115/115, writer 227/227 e generator read-only
434/434; o agregado atual passa 1981/1981, com zero fail/cancel/skip/todo.
Generator, schema, paths e input contract remotos permanecem read-only. Não
houve rede, SSH, simulador, privilégio real, escrita root, produção, CI-3,
stage, commit, push, retry ou cleanup. O estado continua
`STOP_PRE_AUTHORITY`.

## Atualização operacional 1.7.19 — successor round-3 local

Esta seção substitui qualquer alegação arquitetural 1.7.18 incompatível com a
remediação round-3. O único transporte Publisher 0 agora parte, no modelo de
produção local, sem object root, issuer, request, pass, payload ou helper
remoto preexistente. A sessão começa no shell fixo e recebe pelo stdin os bytes
Git exatos, manifesto, proveniência e os onze inputs de authority. Dentro dessa
mesma sessão ela materializa, readbacka e congela controller e tool antes de
executar o controller; só então cria a transação versionada claim-first, a
chave Ed25519 restrita ao proprietário, o issuer público, request sem assinatura
e payloads, publicando pass assinado, manifesto e receipt de transporte por
último. A prova usa um fake remote vazio e não executa SSH real.

O stdout autenticado da sessão é gravado em journal local exclusivo, owner-only
e sincronizado antes de o efeito remoto poder ser considerado settled. Assim,
um crash depois do settlement remoto e antes da promoção do capture local é
recuperado do mesmo journal, sem uma segunda sessão. No Mac, um único
supervisor permanece responsável pelas Phases A e B sob o prompt original:
reentrada após Phase A exata aguarda a continuação original, sem segundo prompt
ou segunda Phase A; Phase B parcial/divergente termina fechada.

A integração no-effect executa de fato o launcher instalado pelo zsh e atravessa
o controller Node instalado. O controller deriva o request causal da própria
árvore versionada instalada, sem descriptor ambiente, readbacka dezesseis
targets, publica settlement, executa as seis funções reais de scan e demonstra
reachability do later writer. O modo terminal permanece recusado nesse ponto.
O launcher voltou ao skeleton estrutural predecessor, preservando o generator
read-only.

Os testes completos atuais passam external 311/311, installer 158/158,
controller 743/743, launcher 115/115, writer 227/227 e generator read-only
434/434. O agregado serial passa 1988/1988 em 711,07 segundos, com zero
fail/cancel/skip/todo e sem timeout. Generator, schema, paths e input contract
remotos permanecem read-only. Não houve rede, SSH, simulador, privilégio real,
escrita root, produção, CI-3, stage, commit, push, retry ou cleanup. O estado
continua `STOP_PRE_AUTHORITY`.

## Atualização operacional 1.7.20 — successor round-4 local

Esta seção substitui os claims 1.7.19 incompatíveis. O bootstrap Publisher 0
agora materializa cada arquivo por criação exclusiva/no-follow, sincroniza
arquivos e diretórios, congela e readbacka flags e a identidade física completa
(owner, group, nlink, device, inode, size, mtime, mode e conteúdo), valida a
árvore exata e executa controller/runtime pelos descritores fixados. Trocas de
arquivo, diretório, modo e folha extra terminam antes do controller. Uma
transação nova exige root ausente e publica o claim como primeira folha; root
preexistente sem claim original exato, com extra, key, issuer ou payload
preseedado para sem mutação.

O transporte distribuído permanece uma única sessão. O remoto publica apenas
PREPARED até o journal local autenticado e seu ACK estarem sincronizados; os
receipts causais locais são escritos em staging owner-only, sincronizados,
promovidos atomicamente e sincronizados no parent. O ACK precede o commit
remoto e um receipt QUIESCED, gravado por último pelo broker, impede retorno com
filesystem writes pendentes. As três janelas de morte — antes do primeiro
chunk, antes do último e depois do ACK — recuperam a decisão original sem nova
sessão ou efeito.

No Publisher 1, o supervisor cria dentro do protocolo administrativo original
uma continuação root-owned e version-addressed, ligada ao immutable self, claim
e definição persistente. A seam sintética mata o supervisor e a continuação
retoma Phase B sem segundo prompt nem segunda Phase A. Uma barreira autenticada
imediatamente antes de Phase B torna parcial/divergente determinístico e faz
tanto reentrada quanto supervisor original pararem. O E2E no-effect executa o
launcher instalado de verdade, atravessa zsh para o controller Node, usa as
superfícies serializadas produzidas nos seis scanners, readbacka dezesseis
targets, assenta a operação e alcança o dispatcher real do later writer; o
terminal continua negado.

Os testes completos atuais passam external 322/322, installer 159/159,
controller 743/743, launcher 115/115, writer 227/227 e generator read-only
434/434. O agregado serial passa 2000/2000 em 811,70 segundos, com zero
fail/cancel/skip/todo. A matriz literal compartilhada continua 103 = 97 campos
ausentes + 6 extras. Generator, schema, paths e input contract remotos
permanecem read-only. Não houve rede, SSH, simulador, prompt/privilégio real,
escrita root, produção, CI-3, stage, commit, push, retry ou cleanup. O estado
continua `STOP_PRE_AUTHORITY`, pendente de duas novas reviews independentes.

## Atualização operacional 1.7.21 — successor round-5 local

Esta seção substitui os claims 1.7.20 incompatíveis. Antes de qualquer processo
Node/controller, o bootstrap Publisher 0 usa o materializador fixo para criar
root e folhas com primitivas exclusive/no-follow, manter descritores fixados,
autenticar bytes e identidade física pelo mesmo descritor, sincronizar,
congelar/readbackar e validar a árvore exata. Os testes locais cobrem root
preexistente sem claim, troca de pathname entre open/hash e hash/exec, troca de
diretório e folha extra; nenhuma árvore não reclamada é normalizada por
chmod/chflags.

O protocolo local production-shaped separa PREPARED de COMMIT: o resultado
remoto terminal permanece ausente até journal e ACK locais duráveis. A
continuação version-addressed detém a única sessão na fixture e os testes matam
o broker e o outer nas três janelas preparadas, recuperando a decisão local sem
segunda sessão ou efeito. Receipts locais usam staging owner-only, fsync e
publicação no-clobber por link exclusivo, com race divergente recusada; não há
rename substitutivo do destino.

No Publisher 1, claim, definição, invocation, registration e markers precisam
ser exatos e imutáveis. A definição launchd é one-shot, sem KeepAlive, e a
matriz sintética cobre morte em CLAIM, DEFINITION, BOOTSTRAP e REGISTRATION,
além de provar uma única invocation após falha. O E2E no-effect executa o
launcher instalado da fixture, atravessa zsh e o controller Node, coleta e
serializa as seis superfícies produzidas pela execução, lê dezesseis targets e
chama a implementação real `publishPrivilegedWriterAuthority`; somente o
boundary de efeito abaixo do consumidor é substituído.

O escopo dessas provas é deliberadamente local: fake remote sem SSH/restart de
host real, seam de serviço sem launchd/reboot/prompt root real e launcher
instalado em fixture sem Terminal/Xcode/simulador. Os testes completos passam
external 337/337, installer 172/172, controller 743/743, launcher 115/115,
writer 227/227 e generator read-only 434/434. O agregado serial passa
2028/2028 em 953,86 segundos, com zero fail/cancel/skip/todo. Generator,
schema, paths e input contract remotos permanecem read-only. Não houve rede,
SSH, simulador, prompt/privilégio real, escrita root, produção, CI-3, stage,
commit, push, retry ou cleanup. O estado permanece `STOP_PRE_AUTHORITY`,
pendente de duas novas reviews independentes.

## Atualização operacional 1.7.22 — successor round-7 local

Esta seção substitui os claims one-shot e de ownership incompatíveis da
1.7.21. No Publisher 0, a árvore PREPARED da fixture é sincronizada,
mode-frozen, relida e validada antes do ACK local. Um session supervisor local
version-addressed mantém a única sessão fake-SSH enquanto workers de journal
podem morrer e ser reiniciados nas três janelas autenticadas. Depois do ACK, o
COMMIT remoto terminal é somente o hard-link no-replace final; PREPARED
permanece como evidência no mesmo inode, com `nlink=2`.

No Publisher 1, o registrar sintético é uma state machine supervisionada e
retoma o mesmo Phase A após morte real do processo registrar em CLAIM,
DEFINITION, INVOCATION, PRE_BOOTSTRAP, POST_BOOTSTRAP e PRE_REGISTRATION. O job
worker não contém `RunAtLoad` nem `KeepAlive`: registro ocorre antes de um
único kickstart explícito. Run-claim e effect-entry são arquivos exclusivos;
`completed` ou `failed` bloqueiam uma nova entrada e produzem settlement. Os
testes reinvocam de verdade o mesmo binário Swift instalado duas vezes após
sucesso e duas vezes após falha, sem novo claim, entry ou efeito.

As provas são locais e processuais: o session supervisor permanece vivo, não
há prova de restart do host ou reattach de SSH; launchd, bootout, reboot,
prompt/root, Terminal, Xcode, simulador e writer privilegiado reais não foram
executados. Os focused passam external 12/12 e installer 1/1. As suites
completas passam external 347/347, installer 173/173, controller 743/743,
launcher 115/115, writer 227/227 e generator read-only 434/434. O agregado
serial passa 2039/2039 em aproximadamente 594 segundos, com zero
fail/cancel/skip/todo. Generator, schema, paths e input contract remotos
permanecem read-only. Não houve rede, SSH, simulador, privilégio/root, produção,
CI-3, stage, commit, push, retry externo ou cleanup. O estado permanece
`STOP_PRE_AUTHORITY`, pendente de duas novas reviews independentes.

## Atualização operacional 1.7.24 — successor round-9 local

Esta seção substitui a inferência incompatível de ativação do Publisher 1 da
1.7.23. O registrar agora cria e verifica identidade, claim, lock e handshake
duráveis de um activation owner version-addressed antes de publicar o sinal de
ativação. O activation owner, não o registrar, possui o único kickstart físico
e a recuperação do worker. Um registrar reiniciado antes do sinal ou depois da
aceitação do start e antes do receipt se junta ao mesmo owner; ausência do
worker-launch receipt não é tratada como prova de que o kickstart não ocorreu.
O worker continua sem `RunAtLoad` e sem `KeepAlive`.

Os novos testes primeiro falharam 0/2 por ausência desses boundaries e depois
passaram 2/2. Eles matam o PID real do registrar em `PRE_SIGNAL` e em
`POST_ACCEPT_PRE_RECEIPT`, preservam o PID do owner e observam exatamente um
kickstart executável, um worker launch e no máximo uma effect entry, com
settlement terminal determinístico. As provas predecessoras Round 8 passam
11/11; regressões impactadas passam 4/4, 4/4 e 6/6; installer completo passa
173/173. Typechecks Swift e sintaxe Node passam. As suites completas passam
external 360/360, installer 173/173, controller 743/743, launcher 115/115,
writer 227/227 e generator read-only 434/434. O agregado serial passa
2052/2052 em aproximadamente 1156,5 segundos, com zero fail/cancel/skip/todo.

O modelo de falha permanece local e não prova morte do activation owner,
reboot/reattach do host, launchd/root/prompt reais, Terminal, Xcode, simulador
ou publicação privilegiada. Generator, schema, paths e input contract remotos
permanecem read-only. Não houve rede, SSH real, admin/root, produção, CI-3,
stage, commit, push ou efeito externo. O estado permanece
`STOP_PRE_AUTHORITY`.

## Atualização operacional 1.7.23 — successor round-8 local

Esta seção substitui os limites processuais incompatíveis da 1.7.22. No
Publisher 0, um transport owner separado mantém o único child/session da
fixture enquanto o session supervisor pode morrer e ser reiniciado nas três
janelas de journal/ACK e nas três fronteiras do COMMIT remoto. A decisão local
`COMMIT_DECIDED` é durável antes do ACK. O remoto então cria o único hard-link
no-replace, sincroniza o diretório que o contém e emite por último uma decisão
terminal autenticada e ligada aos hashes do output e request. Não há segundo
transport, refetch ou efeito.

No Publisher 1, `KICKSTART_DECIDED`, run-claim, effect-entry e estado terminal
são persistentes e version-addressed. O registrar reiniciado após kickstart
se junta ao worker original por um lock exclusivo sobre identidade imutável e
não emite outro kickstart. Morte do worker em run-claim ou antes de
effect-entry relança a mesma continuação; morte após effect-entry ou antes do
terminal produz `STOP_PARTIAL` e nunca repete o efeito. Os testes contam
kickstarts, launches e effect entries físicos.

O modelo continua estritamente local: ele não prova morte/restart do processo
SSH real, reboot do host, reattach externo, launchd/root/prompt real, Terminal,
Xcode, simulador ou publicação privilegiada. O focused Round 8 passa 11/11 e
as regressões predecessoras passam external 27/27 e installer 14/14. As suites
completas passam external 358/358, installer 173/173, controller 743/743,
launcher 115/115, writer 227/227 e generator read-only 434/434, sem
fail/cancel/skip/todo. Generator, schema, paths e input contract remotos
permanecem read-only. Não houve rede, SSH real, admin/root, produção, CI-3,
stage, commit, push, retry externo ou cleanup. O estado permanece
`STOP_PRE_AUTHORITY`, pendente de duas novas reviews independentes.

## Atualização operacional 1.7.25 — authority publicada, Gate 0 PASS e STOP documentado

A authority semantic-safe sucessora foi publicada por fast-forward e relida no
remoto. As reviews finais independentes fecharam em `0 Critical / 0 Important`
em ambos os lados. A materialização owner-only dos 16 paths alterados e do par
generator/test herdado passou por readback; a suíte final executada dos blobs
publicados passou `2052/2052`, sem fail/cancel/skip/todo. Os writers operacional
e de preflight ficaram distintos e capability-separated, o installer foi
compilado da fonte publicada e o novo Gate 0 passou com exit zero, stdout/stderr
vazios e launcher inalterado.

O executor publicado foi então chamado uma única vez em `--prepare` e falhou
fechado antes de qualquer efeito. O corpus frozen de produção exigido pelo
próprio contrato não existe e não há construtor publicado/autorizado para
produzir context, launch attestation, operation authority, payloads Node/SSH e
operation authorities reais. Inventar esses bindings de segurança e valores
futuros de simulador/SSH seria incompatível com a authority. Publisher0 e
Publisher1 permanecem `0/1`; não houve SSH, claim, processo filho, prompt admin,
simulador, root write, remote read, CI-3 Task 2 ou cleanup. O estado terminal é
`STOP_DOCUMENTED`; próximo gate material não executado:
`AUTHORIZE_PRODUCTION_FROZEN_INPUT_CONSTRUCTOR_V1`.
