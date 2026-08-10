# BodyFlow iOS — evidências locais do Prompt 13

Validação capturada em 2026-08-02 (`America/Sao_Paulo`) para a Task 21 do
Prompt 13: Tela Hoje, registros e progresso.

## Fonte e ambiente

- Branch: `codex/bodyflow-ios-today-records-progress-v1`.
- Base empilhada: `codex/bodyflow-ios-auth-onboarding-v1`.
- HEAD de aplicação testado, antes deste commit somente de evidências:
  `8ac5b64cd572c5e757c8455bc10e7b8792322c5a`.
- Diretório: `/Users/eduardohenrique/Developer/bodyflow`.
- Sistema: Darwin.
- Xcode: 26.6 (`17F113`).
- Swift: 6; deployment target iOS 18.0.
- Simulador: iPhone 17 Pro, iOS 26.5 (`23F77`), arm64.
- UDID: `27291590-659D-4A29-8F45-CA5CA2D154F9`.
- Bundle ID: `com.bodyflow.app`.
- Raiz fresca do gate: `/tmp/bodyflow-prompt13-gate.awWRZH`.
- Result bundle:
  `/tmp/bodyflow-prompt13-gate.awWRZH/BodyFlowPrompt13.xcresult`.
- Derived Data Debug unsigned:
  `/tmp/bodyflow-prompt13-gate.awWRZH/debug`.
- Derived Data Release unsigned:
  `/tmp/bodyflow-prompt13-gate.awWRZH/release`.
- Derived Data Debug assinado e executado:
  `/tmp/bodyflow-prompt13-gate.awWRZH/run`.

Os Steps 2–7 foram executados na mesma sessão PTY persistente e todos os
caminhos acima derivam da mesma raiz criada com `mktemp -d`.

## Gate completo de testes

Comando assinado executado no simulador aprovado:

```bash
xcodebuild -project apps/ios/BodyFlow/BodyFlow.xcodeproj \
  -scheme BodyFlow \
  -configuration Debug \
  -destination "platform=iOS Simulator,id=27291590-659D-4A29-8F45-CA5CA2D154F9" \
  -resultBundlePath "/tmp/bodyflow-prompt13-gate.awWRZH/BodyFlowPrompt13.xcresult" \
  test
```

Resumo consultado diretamente no result bundle:

```bash
xcrun xcresulttool get test-results summary \
  --path /tmp/bodyflow-prompt13-gate.awWRZH/BodyFlowPrompt13.xcresult

xcrun xcresulttool get test-results tests \
  --path /tmp/bodyflow-prompt13-gate.awWRZH/BodyFlowPrompt13.xcresult \
  --compact
```

Resultado real do `xcresult`:

- resultado: `Passed` / `** TEST SUCCEEDED **`;
- 639 testes lógicos: 562 unitários e 77 de interface;
- 715 execuções aprovadas após expansão de parâmetros;
- 31 testes lógicos parametrizados produziram 107 execuções com argumentos;
- zero falhas, zero skips e zero falhas esperadas;
- duração pelo intervalo `startTime`/`finishTime` do `xcresult`:
  1.213,291 segundos (20 min 13,291 s).

A execução assinada é intencional: os testes herdados de autenticação usam
Keychain/entitlements. Builds unsigned são apenas gates de compilação e não são
usados como evidência de runtime.

## Gates de build

Debug unsigned:

```bash
xcodebuild -project apps/ios/BodyFlow/BodyFlow.xcodeproj \
  -scheme BodyFlow \
  -configuration Debug \
  -destination "platform=iOS Simulator,id=27291590-659D-4A29-8F45-CA5CA2D154F9" \
  -derivedDataPath "/tmp/bodyflow-prompt13-gate.awWRZH/debug" \
  CODE_SIGNING_ALLOWED=NO \
  build
```

Resultado: `** BUILD SUCCEEDED **`.

Release unsigned:

```bash
xcodebuild -project apps/ios/BodyFlow/BodyFlow.xcodeproj \
  -scheme BodyFlow \
  -configuration Release \
  -destination "generic/platform=iOS Simulator" \
  -derivedDataPath "/tmp/bodyflow-prompt13-gate.awWRZH/release" \
  CODE_SIGNING_ALLOWED=NO \
  build
```

Resultado: `** BUILD SUCCEEDED **`. O Release compilou sem fixtures,
repositórios ou previews exclusivos de Debug.

Debug assinado para runtime:

```bash
xcodebuild -project apps/ios/BodyFlow/BodyFlow.xcodeproj \
  -scheme BodyFlow \
  -configuration Debug \
  -destination "platform=iOS Simulator,id=27291590-659D-4A29-8F45-CA5CA2D154F9" \
  -derivedDataPath "/tmp/bodyflow-prompt13-gate.awWRZH/run" \
  build
```

Resultado: `** BUILD SUCCEEDED **`, com assinatura local para execução.

Instalação e lançamento finais:

```bash
xcrun simctl install \
  27291590-659D-4A29-8F45-CA5CA2D154F9 \
  /tmp/bodyflow-prompt13-gate.awWRZH/run/Build/Products/Debug-iphonesimulator/BodyFlow.app

xcrun simctl launch \
  27291590-659D-4A29-8F45-CA5CA2D154F9 \
  com.bodyflow.app \
  --ui-testing \
  --ui-testing-prompt13-loaded
```

O app foi deixado em execução como PID 7788 no shell de cinco abas, sem crash.

## Evidências curadas

As attachments foram exportadas primeiro para
`/tmp/bodyflow-prompt13-gate.awWRZH/attachments`. O `manifest.json` foi lido e
validado por stem: existe exatamente um PNG e um TXT de hierarquia para cada
nome aprovado. Somente os 13 PNGs finais foram materializados e versionados;
o diretório bruto de attachments não foi copiado para o repositório.

Todas as imagens são PNG RGB de 1206 × 2622 pixels e foram inspecionadas
visualmente.

| Arquivo | Estado comprovado |
| --- | --- |
| `01-today.png` | Today carregado, hierarquia e semânticas oficiais de energia |
| `02-meal-proposal-edit.png` | Proposta pendente de refeição em edição antes da confirmação |
| `03-individual-meal-log-detail.png` | Detalhe de uma linha individual de `meal_logs`, resolvido do snapshot carregado |
| `04-workout-proposal.png` | Proposta pendente de treino, com editar, confirmar e cancelar |
| `05-hydration-routine.png` | Hidratação concluída após refresh completo e detalhe de rotina com ações exatas |
| `06-plan.png` | Plano mostrando somente os campos estáveis recebidos |
| `07-progress-block.png` | Progresso e detalhe do Bloco 7.700 originado do snapshot de Today |
| `08-main-history.png` | Primeira página limitada, refeições em linhas separadas e seção de treinos |
| `09-offline-error-retry.png` | Conteúdo stale preservado, aviso offline e Retry alcançável |
| `10-dark-mode.png` | Tela representativa com esquema de cores escuro efetivo |
| `11-accessibility-xxxl.png` | Conteúdo em Accessibility XXXL, rolável e alcançável |
| `12-reduce-motion.png` | Caminho determinístico de Reduce Motion mantendo ações utilizáveis |
| `13-final-simulator.png` | Light/Large restaurado e shell final de cinco abas |

## Inspeção funcional e visual

A suíte de interface e a revisão manual das capturas/hierarquias cobriram:

- Today com cabeçalho, data local, protocolo, atenção antes de energia,
  proveniência, dia incompleto, hidratação, ocorrências e Bloco 7.700;
- distinção literal entre “restam para comida” e “déficit líquido”, sem
  recalcular ou corrigir valores oficiais no iOS;
- refeição por texto, foto e áudio sempre gerando proposta antes de confirmar,
  além de edição pending, Retry, confirmação e cancelamento;
- treino com proposta, edição, confirmação, cancelamento e valores recebidos;
- recibo local de peso, limites de peso/hidratação e ausência de sucesso falso;
- listas e detalhes próprios de suplementos/medicamentos, ações exatas, snooze
  de 15/30/60 minutos, horário personalizado na mesma data e cursor opaco dos
  históricos próprios;
- Plano, Progresso e o Bloco 7.700 sem fórmulas oficiais locais;
- Histórico principal somente com refeições e treinos confirmados, linhas de
  `meal_logs` não agrupadas, detalhe individual e ausência de “carregar mais”;
- loading, empty, offline, erro recuperável, stale, Retry, incompleto e
  indisponível;
- as cinco abas abrindo sem crash e mantendo pilhas de navegação independentes;
- ausência de clipping confirmado, sucesso enganoso ou diálogo inesperado de
  permissão nos cenários demonstrativos.

## Acessibilidade

Foram executados e inspecionados:

- Light e Dark Mode com cores semânticas e contraste preservado;
- Dynamic Type Large e Accessibility XXXL, com conteúdo rolável, frames
  representativos inteiramente entre navigation bar e tab bar;
- controles alcançáveis com alvos mínimos de 44 × 44 pt;
- hierarquias XCUI com labels, values, identificadores estáveis, summaries
  combinados e ordem de foco coerente para VoiceOver;
- cenário exclusivo `--ui-testing-prompt13-reduce-motion`, sem cenário loaded
  concorrente, com refresh e publicação final utilizáveis.

Os comandos de aparência/tamanho usados na inspeção manual foram:

```bash
xcrun simctl ui 27291590-659D-4A29-8F45-CA5CA2D154F9 appearance dark
xcrun simctl ui 27291590-659D-4A29-8F45-CA5CA2D154F9 content_size accessibility-extra-extra-extra-large
xcrun simctl ui 27291590-659D-4A29-8F45-CA5CA2D154F9 appearance light
xcrun simctl ui 27291590-659D-4A29-8F45-CA5CA2D154F9 content_size large
```

Ao final, o simulador foi restaurado para Light, Large e cenário loaded. O
contexto visual comprova a política de movimento; a ausência de animações
incompatíveis foi verificada pelo caminho determinístico e pela usabilidade das
ações, não inferida somente de um screenshot.

## Limites e segurança

- Todos os dados de demonstração são sintéticos, determinísticos e exclusivos
  de Debug, previews e testes de interface.
- Em Release, operações sem persistência real retornam
  `operationUnavailable` e a UI apresenta “Indisponível nesta versão”; não há
  registro, detecção ou sucesso fictício.
- Valores oficiais são respostas completas dos adapters e não são calculados,
  corrigidos ou completados no iOS.
- O Histórico principal lê somente a primeira página limitada de refeições e
  treinos. O detalhe de `meal_logs` usa exclusivamente o snapshot de History já
  carregado.
- Paginação compartilhada confiável do Histórico e identidade agregada de uma
  ocorrência de refeição ainda dependem de um contrato futuro de backend.
- Nenhum endpoint real, parser presumido, cliente live, Supabase/BFF, provider,
  secret, conta real ou integração externa foi configurado.
- Nenhuma arquitetura baseada em WhatsApp foi introduzida.
- Nenhum push, PR, merge, deploy, migration, TestFlight ou alteração de
  produção ocorreu durante este gate local.
