# Evidências — Prompt 11, scaffold iOS nativo

Data da validação: 2026-07-26.

## Ambiente validado antes da implementação

- Diretório: `/Users/eduardohenrique/Developer/bodyflow`.
- Sistema: Darwin.
- Branch: `codex/bodyflow-ios-scaffold-v1`.
- Worktree: limpa antes da primeira edição.
- Xcode: 26.6, build 17F113.
- Destino: iPhone 17 Pro, iOS 26.5, UDID
  `27291590-659D-4A29-8F45-CA5CA2D154F9`.

## Configuração efetiva

- Projeto e scheme: `apps/ios/BodyFlow/BodyFlow.xcodeproj`, `BodyFlow`.
- Swift 6 com strict concurrency `complete`.
- Deployment target iOS 18.0; iPhone apenas.
- Bundle ID `com.bodyflow.app`; nome visível `BodyFlow`.
- Build e testes executados com `CODE_SIGNING_ALLOWED=NO`.
- Nenhum package externo ou equipe de assinatura configurados.

## Comandos de verificação

```sh
xcodebuild \
  -project apps/ios/BodyFlow/BodyFlow.xcodeproj \
  -scheme BodyFlow \
  -configuration Debug \
  -destination 'platform=iOS Simulator,id=27291590-659D-4A29-8F45-CA5CA2D154F9' \
  -derivedDataPath <DERIVED_DATA> \
  -resultBundlePath <RESULT_BUNDLE> \
  CODE_SIGNING_ALLOWED=NO \
  test

xcrun xcresulttool get test-results summary --path <RESULT_BUNDLE>

xcodebuild -quiet \
  -project apps/ios/BodyFlow/BodyFlow.xcodeproj \
  -scheme BodyFlow \
  -configuration Debug \
  -destination 'platform=iOS Simulator,id=27291590-659D-4A29-8F45-CA5CA2D154F9' \
  -derivedDataPath <DERIVED_DATA> \
  CODE_SIGNING_ALLOWED=NO \
  build

xcrun simctl install \
  27291590-659D-4A29-8F45-CA5CA2D154F9 \
  <DERIVED_DATA>/Build/Products/Debug-iphonesimulator/BodyFlow.app

xcrun simctl launch --terminate-running-process \
  27291590-659D-4A29-8F45-CA5CA2D154F9 \
  com.bodyflow.app
```

Resultado final:

- suite completa: `Passed`;
- 30 testes lógicos: 27 unitários e 3 de interface;
- 36 execuções contabilizadas, incluindo parâmetros dinâmicos;
- 0 falhas, 0 falhas esperadas e 0 testes ignorados;
- build Debug: exit code 0, sem warnings ou erros do compilador Swift;
- instalação e lançamento: exit code 0; PID final 78792 no simulador aprovado.

## Inspeção visual

| Arquivo | Cobertura |
| --- | --- |
| `01-hoje.png` | Aba Hoje em modo claro; contraste da conquista corrigido. |
| `02-registrar.png` | Quatro comandos de registro e disclaimer local. |
| `03-plano.png` | Resumo e navegação de Plano. |
| `04-progresso.png` | Métricas e navegação de Progresso. |
| `05-perfil.png` | Perfil assentado, cinco abas visíveis e um único chevron. |
| `06-hoje-detalhe-restaurado.png` | Histórico da aba Hoje restaurado após troca de aba. |
| `07-registro-refeicao.png` | Sheet local assentada, sem alegar persistência. |
| `08-dark-hoje.png` | Modo escuro com tokens semânticos e contraste preservado. |
| `09-accessibility-xxxl-hoje.png` | Dynamic Type AX XXXL; conteúdo rolável e abas acessíveis. |
| `10-final-debug-launch.png` | Artefato Debug final instalado e executando. |
| `11-accessibility-xxxl-registration-sheet.png` | Sheet em detent grande no AX XXXL, sem corte de conteúdo. |

As árvores `accessibility-five-tabs.txt`, `accessibility-detail.txt`,
`accessibility-registration-sheet.txt` e
`accessibility-xxxl-registration-sheet.txt` comprovam os identificadores,
rótulos, rotas e frames efetivos. No AX XXXL, o botão `sheet.fechar` mede
74 × 74 pt e mantém o rótulo acessível “Fechar”.

A inspeção não encontrou conteúdo cortado, tab bar incompleta, disclosure
duplicado ou texto essencial inacessível. As capturas de UI aguardam seleção,
geometria centralizada e estabilização visual antes de gerar os attachments.

## Limites e segurança

- Fixtures e mocks determinísticos, todos locais e em memória.
- Nenhum host, `URLSession`, header de autorização, secret, Keychain, SDK de
  terceiros, serviço real ou package remoto.
- Nenhuma persistência real e nenhuma fórmula nova de saúde.
- Nenhuma arquitetura ou referência nova a WhatsApp.
- Nenhum deploy, merge, migration, TestFlight, assinatura ou alteração de
  produção foi executado.
