# Tarefa 5 — Rascunho validado e etapas centrais do onboarding

## Escopo implementado

- `OnboardingFlowModel` em `@MainActor @Observable`, dependente apenas de `OnboardingRepository`, com draft tipado, validação por etapa, save-before-advance, retry, guarda de concorrência e cancelamento sem transição/erro tardio.
- Validadores puros para país ISO 3166-1 alpha-2 uppercase, timezone IANA, data de nascimento, altura `100...250`, peso `30...300`, gordura opcional `3...60` e frequência `0...7`.
- Sincronização do `AppFlowModel` via `updateOnboardingStep(_:)`, preservando o userID atual.
- `AppRootView` cria e retém uma única instância de `OnboardingFlowModel` por userID em `.task(id:)`, remove-a na saída/troca de usuário, oferece retry de load e rejeita callbacks de um usuário antigo.
- Container exaustivo e telas funcionais para welcome, body data, objective e routine, com IDs estáveis, controles nativos, progresso textual e nenhum cálculo de calorias/macros.
- 20 previews determinísticos: válido, validação em Dynamic Type de acessibilidade e erro de save onde aplicável.

## Evidência TDD

### RED principal — modelo, transições, validações e sync do root

Todos os testes de transição/validação foram escritos antes de existir produção nova.

```sh
xcodebuild -project apps/ios/BodyFlow/BodyFlow.xcodeproj -scheme BodyFlow -destination 'platform=iOS Simulator,id=27291590-659D-4A29-8F45-CA5CA2D154F9' -only-testing:BodyFlowTests/OnboardingFlowModelTests -only-testing:BodyFlowTests/AppFlowModelTests test
```

Resultado observado: `** TEST FAILED **`, com os erros esperados:

```text
Value of type 'AppFlowModel' has no member 'updateOnboardingStep'
Cannot infer contextual base in reference to member 'bodyData'
Cannot find type 'OnboardingFlowModel' in scope
```

### GREEN principal — núcleo

Após implementar somente `OnboardingFlowModel`, validadores e `updateOnboardingStep(_:)`, o mesmo comando retornou `** TEST SUCCEEDED **`.

### RED adicional — invariantes de Back e cancelamento

Antes de alterar esses comportamentos, foram adicionados testes exigindo que Back sincronize o root e que um save que ignora cancelamento e depois falha não publique erro tardio.

```sh
xcodebuild -project apps/ios/BodyFlow/BodyFlow.xcodeproj -scheme BodyFlow -destination 'platform=iOS Simulator,id=27291590-659D-4A29-8F45-CA5CA2D154F9' -only-testing:BodyFlowTests/OnboardingFlowModelTests test
```

Resultado observado: `** TEST FAILED **`, exatamente em:

```text
OnboardingFlowModelTests.backPreservesDraft()
OnboardingFlowModelTests.cancellationPreventsLateFailure()
```

Após callback de Back e guarda de cancelamento também no catch genérico, o mesmo comando retornou `** TEST SUCCEEDED **`.

### GREEN focado final

O comando principal foi repetido depois da UI/wiring e retornou `** TEST SUCCEEDED **`. O xcresult registrou 40 testes lógicos, 52 execuções incluindo argumentos dinâmicos, zero falhas e zero skips.

## Verificação final

Build Debug:

```sh
xcodebuild -project apps/ios/BodyFlow/BodyFlow.xcodeproj -scheme BodyFlow -configuration Debug -destination 'platform=iOS Simulator,id=27291590-659D-4A29-8F45-CA5CA2D154F9' build
```

Resultado: `** BUILD SUCCEEDED **`.

Target unitário completo:

```sh
xcodebuild -project apps/ios/BodyFlow/BodyFlow.xcodeproj -scheme BodyFlow -destination 'platform=iOS Simulator,id=27291590-659D-4A29-8F45-CA5CA2D154F9' -only-testing:BodyFlowTests test
```

Resultado: `** TEST SUCCEEDED **`; xcresult com 105 testes lógicos, 123 execuções incluindo argumentos dinâmicos, zero falhas e zero skips.

`git diff --check` retornou sem saída.

## Inspeção visual e acessibilidade

- O iPhone 17 Pro solicitado foi iniciado e configurado com `content_size accessibility-extra-large`.
- O app Debug foi instalado/lançado e uma captura real confirmou renderização e scroll em Dynamic Type de acessibilidade.
- Cada tela de onboarding tem preview determinístico; as variantes de validação usam `.dynamicTypeSize(.accessibility3)` e todas compilam no build Debug.
- O launcher `ios-simulator-browser` aceita previews de Swift Package, enquanto este app é `.xcodeproj`; `npx` não está instalado e o macOS recusou automação assistiva do Simulator.
- Uma última inspeção sistemática usou um harness XCUI estritamente transitório. Preencher ambos os `SecureField` com `x` destravou o auth e chegou ao onboarding; foi capturada e inspecionada a tela Welcome real em `accessibility-extra-large`. A hierarquia confirmou `screen.onboarding.welcome`, progresso `Etapa 1 de 7`, campos e botão Continuar.
- Limitação honesta: com o teclado de software ainda aberto, o tap automatizado em Continuar não avançou da etapa 1. Os anexos seguintes permaneceram em `screen.onboarding.welcome`, apesar de o harness procurar `screen.onboarding.body-data`/`objective`; o xcresult terminou com `** TEST FAILED **` por essa limitação do harness. Ele foi removido integralmente e não houve ajuste de produção para acomodá-lo. Portanto não há alegação de captura live das outras etapas nem de render individual dos 20 previews nesta tarefa.
- Ao concluir a inspeção, o Simulator foi restaurado para o `content_size` padrão `large`, confirmado por `simctl`, para não contaminar as próximas tarefas.

## Decisão incremental Task 5 / Task 6

O switch exaustivo exige persona, consent e completion, mas a Task 6 é dona do enriquecimento e da orquestração final. Para não deixar tela vazia, placeholder, `EmptyView`, `fatalError` ou `ProgressView` temporário no checkpoint, foram antecipadas bases reais e reutilizáveis:

- `PersonaStepView` escolhe uma persona pública e grava somente no draft.
- `ConsentStepView` confirma claramente os mesmos IDs sintéticos de desenvolvimento já usados pelas fixtures (`development-privacy`, `development-terms`) e grava somente no draft.
- `OnboardingCompletionView` revisa os valores salvos e permanece sem ação final.

Essas superfícies serão enriquecidas, não substituídas, pela Task 6. Nesta tarefa não há `CoachPersonaRepository.setPersona`, `OnboardingRepository.complete`, callback `onCompleted`, autenticação ou transição ao shell. A cópia não menciona implementação futura e continua válida antes da ação final.

## Auto-revisão

- Views recebem somente `OnboardingFlowModel`; nenhuma acessa repository ou storage.
- Continue valida apenas a etapa atual, grava o draft já com a próxima etapa, só então muda estado/callback.
- Falha mantém a etapa visível e Continue vira retry; input inválido não salva nem avança.
- Double tap é suprimido no model e no container; cancelamento verifica identidade da submissão e userID ativo depois de `await`.
- Back preserva campos e sincroniza root/draft, sem persistência adicional não pedida.
- Opcionais não exibem valores falsamente selecionados: data, frequência e horários exigem ação explícita; food organization informa que o toggle off ainda não foi confirmado.
- País persiste somente código uppercase e timezone somente identificador IANA; listas são derivadas de `Locale.Region.isoRegions` e `TimeZone.knownTimeZoneIdentifiers`.
- Progresso tem dimensão estável e texto `Etapa N de 7`; layouts usam scroll, pilhas verticais e labels com wrap.
- Não há rede, live adapter, endpoint, segredo, WhatsApp, calorias ou macros.

## Arquivos

- `apps/ios/BodyFlow/BodyFlow/App/AppFlowModel.swift`
- `apps/ios/BodyFlow/BodyFlow/App/AppRootView.swift`
- `apps/ios/BodyFlow/BodyFlow/Features/Onboarding/OnboardingFlowModel.swift`
- `apps/ios/BodyFlow/BodyFlow/Features/Onboarding/OnboardingContainerView.swift`
- `apps/ios/BodyFlow/BodyFlow/Features/Onboarding/OnboardingViewSupport.swift`
- `apps/ios/BodyFlow/BodyFlow/Features/Onboarding/WelcomeStepView.swift`
- `apps/ios/BodyFlow/BodyFlow/Features/Onboarding/BodyDataStepView.swift`
- `apps/ios/BodyFlow/BodyFlow/Features/Onboarding/ObjectiveStepView.swift`
- `apps/ios/BodyFlow/BodyFlow/Features/Onboarding/RoutineStepView.swift`
- `apps/ios/BodyFlow/BodyFlow/Features/Onboarding/PersonaStepView.swift`
- `apps/ios/BodyFlow/BodyFlow/Features/Onboarding/ConsentStepView.swift`
- `apps/ios/BodyFlow/BodyFlow/Features/Onboarding/OnboardingCompletionView.swift`
- `apps/ios/BodyFlow/BodyFlowTests/AppFlowModelTests.swift`
- `apps/ios/BodyFlow/BodyFlowTests/OnboardingFlowModelTests.swift`

## Preocupações remanescentes

- Task 6 ainda deve fazer persistência final ordenada/idempotente, usar o persona repository, chamar `complete`, ligar `onCompleted` e só então autenticar/transicionar.
- A inspeção visual individual dos previews deve ser repetida em Xcode Canvas ou em host compatível assim que disponível; build e previews compilados não substituem essa evidência visual.
