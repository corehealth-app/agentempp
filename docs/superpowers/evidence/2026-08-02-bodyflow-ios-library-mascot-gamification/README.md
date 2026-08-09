# BodyFlow iOS — evidências locais do Prompt 14

Validação local concluída em 2026-08-09 (`America/Sao_Paulo`) para o Prompt 14:
Biblioteca educacional, mascote e gamificação.

## Fonte e ambiente imutável

- Branch: `codex/bodyflow-ios-library-mascot-gamification-v1`.
- HEAD de aplicação testado, antes deste commit somente de evidências:
  `a31449f7254d0697652866e192363c303dd9978e`.
- Checkout local: raiz do repositório BodyFlow.
- Xcode: 26.6 (`17F113`).
- Swift: 6.3.3; deployment target iOS 18.0.
- Node.js: 22.23.2.
- Gerenciador declarado e usado pelo gate: pnpm 10.33.2 via Corepack.
- Simulador: iPhone 17 Pro, iOS 26.5.
- UDID: `27291590-659D-4A29-8F45-CA5CA2D154F9`.
- Bundle ID: `com.bodyflow.app`.
- Raiz nova do gate: `/tmp/bodyflow-prompt14-gate.wpTihu`.
- Result bundle principal:
  `/tmp/bodyflow-prompt14-gate.wpTihu/BodyFlowPrompt14.xcresult`.
- Result bundles ambientais:
  `/tmp/bodyflow-prompt14-gate.wpTihu/variants/{dark,accessibility-xxxl,increase-contrast,differentiate-without-color,reduce-motion}.xcresult`.
- Derived Data de testes, Debug, Release e Debug executável:
  `/tmp/bodyflow-prompt14-gate.wpTihu/{test,debug,release,run}`.
- SourcePackages novo e compartilhado somente por este gate:
  `/tmp/bodyflow-prompt14-gate.wpTihu/SourcePackages`.

Nenhum `.xcresult`, DerivedData, attachment ou evidência de uma execução anterior
foi reutilizado. As 42 evidências rejeitadas anteriores permanecem separadas em
`/private/tmp/bodyflow-gate28n-rejected-evidence.Cvtk4b/` e não fazem parte
deste commit.

## Dependências reproduzíveis

O lockfile backend contém os oito pins exatos aprovados:

- `mdast-util-from-markdown` 2.0.3;
- `mdast-util-to-markdown` 2.1.2;
- `micromark-extension-gfm-table` 2.1.1;
- `mdast-util-gfm-table` 2.0.0;
- `micromark-extension-gfm-strikethrough` 2.1.0;
- `mdast-util-gfm-strikethrough` 2.0.0;
- `micromark-extension-gfm-task-list-item` 2.1.0;
- `mdast-util-gfm-task-list-item` 2.0.0.

O `Package.resolved` versão 3 contém:

- `swift-markdown` 0.8.0, revisão
  `3c6f9523da3a1ec2fd829673e472d95b8097a3b8`;
- `swift-cmark` 0.8.0, revisão
  `924936d0427cb25a61169739a7660230bffa6ea6`.

Uma segunda resolução usou exclusivamente o lockfile, sem atualização de
pacotes. `pnpm-workspace.yaml`, manifests, lockfiles, projeto Xcode e
`Package.resolved` permaneceram inalterados.

## Gate completo de testes

Core e Admin foram executados integralmente com pnpm 10.33.2:

| Gate | Resultado | Duração reportada pelo runner |
| --- | ---: | ---: |
| `@mpp/core` | 18 arquivos; 233/233 testes | 0,832 s |
| typecheck Core | aprovado | sem erros |
| `@mpp/admin` | 52 arquivos; 619/619 testes | 2,730 s |
| typecheck Admin | aprovado | sem erros |

O result bundle principal excluiu somente os cinco seletores ambientais, que
foram executados uma única vez em bundles separados sob sua configuração real
ou Debug-only aprovada:

| Bundle iOS | Testes lógicos | Execuções | Falhas / skips / expected | Duração |
| --- | ---: | ---: | ---: | ---: |
| Principal | 1.062 | 1.180 | 0 / 0 / 0 | 1.881,095 s |
| Dark Mode | 1 | 1 | 0 / 0 / 0 | 23,028 s |
| Accessibility XXXL | 1 | 1 | 0 / 0 / 0 | 34,038 s |
| Increase Contrast | 1 | 1 | 0 / 0 / 0 | 11,080 s |
| Differentiate Without Color | 1 | 1 | 0 / 0 / 0 | 9,987 s |
| Reduce Motion | 1 | 1 | 0 / 0 / 0 | 11,271 s |

União completa iOS:

- 1.067 testes lógicos e 1.185 execuções aprovadas;
- 955 testes unitários lógicos e 112 testes XCUI lógicos;
- 37 testes lógicos parametrizados no bundle principal produziram 155
  execuções com argumentos;
- zero falhas, zero skips e zero falhas esperadas;
- soma das durações dos seis bundles: 1.970,499 s.

Somando backend e iOS, o gate executou 1.919 testes lógicos. Considerando as
execuções parametrizadas nativas, foram 2.037 execuções aprovadas. O shell
automatizado completo permaneceu fail-fast e terminou em aproximadamente
2.059 s, do início do gate até o marcador terminal dos artefatos.

## Gates de build

Os três builds foram produzidos com o mesmo lockfile e SourcePackages novos:

| Build | Resultado | Janela observada dos artefatos |
| --- | --- | ---: |
| Debug unsigned | `** BUILD SUCCEEDED **` | aproximadamente 11 s |
| Release unsigned | `** BUILD SUCCEEDED **` | aproximadamente 33 s |
| Debug executável | `** BUILD SUCCEEDED **` | aproximadamente 12 s |

As janelas acima usam timestamps de filesystem com resolução de um segundo. O
binário Release é Mach-O universal executável (`x86_64` e `arm64`). O app Debug
foi instalado no simulador aprovado e, ao final, relançado exclusivamente com
`--ui-testing --ui-testing-prompt14-loaded`.

## Gates de Release, arquitetura e privacidade

Os scans retornaram zero correspondências proibidas para:

- fixtures, cenários, streams, recorders, repositórios demo e previews do
  Prompt 14 no binário Release;
- WhatsApp;
- OpenAI/LLM, mensagens recorrentes geradas e cálculo local de XP, nível ou
  streak;
- ranking, cooperação ou contratos de missões inventados;
- transporte adicionado desde
  `0e51adebfa8ef718db87096283154c738d8ea0ae`, usando a regex histórica
  corrigida `URLSession|URLRequest|HTTPClient|APIClient|\bAuthorization\b|\bBearer\b|baseURL|APIRequest<|https?://`.

Os identificadores compostos seguros, incluindo
`LibraryCoverAuthorizationRelay` e `ContentDetailCoverAuthorization`, não
falharam no gate; sondas sintéticas com `Authorization`, `Bearer token`,
`URLSession`, `URLRequest` e `https://` continuaram sendo detectadas. Release
permanece fail-closed, com capabilities indisponíveis e sem caminho de sucesso
por fixtures.

As sondas sintéticas foram reexecutadas no fechamento do gate. A suíte completa
incluiu `Prompt14TelemetryPrivacyTests` e os testes de fronteira Release, que
limitam a telemetria às chaves/valores aprovados e rejeitam conteúdo, PII,
capability, bearer, título, excerpt, Markdown, badge, saúde e email. Além disso,
um scan separado das 21 hierarquias por palavras autônomas de paciente, email,
bearer, authorization, capability, token, secret e URLs HTTP/HTTPS retornou
zero correspondências.

## Inspeção combinada dos 34 cenários determinísticos

Cada lançamento manual usou `--ui-testing` e exatamente um cenário Prompt 14.
Foram terminados e relançados, uma vez cada, os 34 estados Debug-only:

```text
conflict, content-not-found, cover-abusive-dimensions, cover-expired,
cover-external-path, cover-invalid, cover-mime-mismatch, cover-too-large,
differentiate-without-color, empty, error, incomplete-detail,
invalid-cursor-recovery, loaded, loading, markdown-external-link,
markdown-invalid, mascot-focus-active, mascot-variants,
mascot-zen-neglected, mutation-failure-once, next-page-failure-once,
offline, opened-error, persona-stateful,
progress-complete-duplicate-badges, progress-empty, progress-minimum,
reduce-motion, stale, streak-zero, subscription-required,
today-recommendations-stale, unavailable
```

As 34 apresentações iniciais foram inspecionadas visualmente em screenshots
novos. As jornadas profundas de navegação, paginação, detalhe, mutação, capas,
mascote e progresso foram exercitadas pela suíte XCUI fresca; seus screenshots,
hierarquias e logs relevantes foram então revisados manualmente. Essa
combinação confirmou:

- cinco abas e stacks independentes;
- Today oficial preservado enquanto recomendações carregam, ficam stale ou
  falham de forma independente;
- Library All/Saved/categoria, paginação opaca, Retry e recuperação de cursor;
- detalhe autorizado antes de um único `opened`, Markdown canônico, link HTTPS
  externo e mutações idempotentes;
- capas válida, nil, expirada, externa, oversized, MIME divergente e dimensões
  abusivas convergindo para o limite/placeholder aprovado;
- Focus, Impulse, Zen e Balanced; estados Inactive, Reactivating, Active,
  Neglected, Evolving e Unknown;
- progresso completo, mínimo, `data: null`, medalhas duplicadas e streak zero;
- ausência de ranking, cooperação, recompensa calculada, missão inventada,
  navegação externa inesperada, permission prompt, crash ou falso sucesso.

As fixtures são sintéticas, locais, determinísticas e compiladas somente em
Debug. Nenhum dado de paciente, conta real ou informação clínica real foi
usado.

## Evidências curadas

As attachments foram exportadas pelo manifest dos result bundles, aceitando
somente o nome canônico ou o sufixo terminal fechado `_índice_UUID`. A seleção
consultou `suggestedHumanReadableName` e `exportedFileName`, deduplicou pelo
nome exportado, rejeitou caminhos inesperados e exigiu exatamente uma
ocorrência não vazia para cada base/extensão.

O diretório contém exatamente 21 PNGs e 21 hierarquias TXT correspondentes.
Todos os PNGs são 1206 × 2622 pixels, os 42 arquivos são não vazios, e os 21
hashes PNG são distintos. O manifesto SHA-256 combinado da lista canônica é
`cb39624a2f8faa6594fa4935ac12f1c15df0afabef0a0c76fd473e239b71928b`.

| Par | Estado comprovado |
| --- | --- |
| `01-today-recommendations` | Today carregado e recomendações independentes |
| `02-library-all` | Library All em ordem do servidor e capa privada válida |
| `03-library-saved-empty` | Saved vazio com mensagem contratual |
| `04-library-category-pagination` | filtro, paginação opaca e título inline após colapso |
| `05-content-detail-markdown` | detalhe e Markdown nativo canônico |
| `06-opened-error-nonblocking` | falha de `opened` não bloqueia o artigo |
| `07-cover-failure-placeholder` | falha de capa produz placeholder neutro |
| `08-mascot-focus-active` | Focus + Active |
| `09-mascot-zen-neglected` | Zen + Neglected |
| `10-mascot-evolving-neutral` | Evolving com apresentação neutra |
| `11-progress-gamification` | progresso completo e medalhas recebidas |
| `12-streak-zero-missions` | streak zero e ausência de missões inventadas |
| `13-offline-error-retry` | offline/erro com Retry alcançável |
| `14-conflict-reload` | conflito de versão e reload canônico |
| `15-dark-mode` | Dark Mode efetivo |
| `16-accessibility-xxxl` | categoria e CTA simultaneamente visíveis em XXXL |
| `17-increase-contrast` | Increase Contrast real |
| `18-differentiate-without-color` | diferenciação sem depender somente de cor |
| `19-reduce-motion` | Reduce Motion determinístico |
| `20-unavailable` | estado indisponível e ação integralmente visível |
| `21-final-simulator` | Light/Large restaurado, shell final loaded |

Os 21 pares foram revisados visualmente e contra suas árvores de
acessibilidade. Não há imagem vazia, duplicada, mismatch, truncamento ou
clipping relevante, controle interativo aninhado, dado real ou sobreposição de
chrome.

Conferências geométricas específicas:

- `04`: marca, título inline e botão Voltar ficam contidos e separados; o
  botão Voltar mede 44 × 44 pt. O frame bruto do sexto card começa antes do
  recorte, mas sua região efetiva após a interseção com o `ScrollView` é
  `y=480,7…774,3`, separada 12,4 pt da categoria e 16,7 pt da TabBar.
- `16`: categoria `y=209,0…334,3` e CTA `y=665,3…790,6` aparecem juntos;
  `CTA.maxY=790,6 < TabBar.minY=791,0`. Não há ação aninhada.
- `20`: texto indisponível `y=477,3…497,6` e CTA
  `y=513,7…557,7` estão integralmente acima da TabBar em `y=791,0`.

## Acessibilidade e variantes ambientais

Foram executados em bundles separados e também inspecionados manualmente:

- Dark Mode;
- Accessibility XXXL;
- Increase Contrast real pelo Simulator;
- Differentiate Without Color pelo override Debug revisado;
- Reduce Motion pelo cenário determinístico aprovado.

A revisão cobriu ordem VoiceOver, headings, listas, links externos anunciados,
alvos mínimos de 44 × 44 pt, contraste semântico e ausência de scroll
horizontal. Os seletores XCUI comprovaram o foco após load/filtro/Retry/mutação;
as hierarquias resultantes foram revisadas manualmente. A marca aparece uma
única vez por tab autenticada, reserva espaço real e não cruza a NavigationBar.
Cor não é o único indicador de seleção, estado ou erro.

Ao final, o simulador foi restaurado para Light, Dynamic Type Large e Increase
Contrast desabilitado. O app ficou no cenário loaded, conforme o plano.

## Limitações e gates ainda obrigatórios

Avisos herdados não bloqueantes permaneceram visíveis e não foram corrigidos
neste task documental:

- warnings de propriedades UIKit `sender` isoladas ao MainActor em telas de
  registro de treino e hidratação;
- resultado não usado de `waitUntilStarted` em
  `RegistrationSheetTaskCoordinatorTests`;
- extração de metadados AppIntents ignorada porque o framework não está
  presente neste build local.

Esses avisos não produziram falha, skip ou expected failure e não alteram o
resultado dos builds Swift 6.

Este gate local não autoriza TestFlight. Antes dele continuam obrigatórios e
separadamente autorizados:

1. transporte autenticado real e origem HTTPS confiável;
2. staging com contratos equivalentes e Release fail-closed;
3. ownership/término de sessão comprovado ponta a ponta.

A auditoria live read-only de `public.content_versions` não foi executada. Ela
permanece bloqueio separado para TestFlight e deve aplicar a regra vigente em
cada ponto de ativação, sem imprimir `body_markdown` ou PII, emitindo somente a
allowlist técnica aprovada. O resultado autorizado futuro precisa conter zero
candidatos incompatíveis tanto em `candidate_class=current` quanto em
`candidate_class=scheduled`; versões históricas que comprovadamente nunca mais
podem ficar visíveis não bloqueiam e não devem ser alteradas diretamente.

Nenhum transporte/base URL/sessão live, secret, auditoria live, migration,
deploy, merge, TestFlight, alteração de produção ou arquitetura de WhatsApp foi
adicionado ou executado neste gate. Nenhum push ou PR foi criado.
