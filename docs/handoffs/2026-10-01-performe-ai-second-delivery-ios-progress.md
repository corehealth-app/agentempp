# Performe AI — segunda entrega iOS, progresso em 2026-10-01

## Escopo e estado

- Continuação da operação definida em `2026-09-30-performe-ai-beta-handoff-to-codex.md` e no addendum de escopo da segunda entrega.
- Checkout local no Mac, branch `codex/performe-ai-client-beta-flow-v1`. HEAD inicial `dc5854f4731396631501668d98e9bcf2e7c5ba53`; HEAD local atual antes deste registro: `98c9956bc098f57968b05f5076aeb3a9cfd621f2`.
- Commits locais desta continuação: `1c054e9` e `cb0982f` (escopo), `b5df45d` (rótulos iOS), `98c9956` (sessão preservada no teste Flow). Sem push, PR, merge, TestFlight, loja ou Production.
- Nenhum arquivo de `packages/agent` ou integração WhatsApp foi alterado. Impacto no WhatsApp: nenhum identificado.

## Evidência funcional e privacidade

- Rascunho de dieta do Flow gerado anteriormente continua em **Para revisar** no iPhone: 3.102 kcal e 207,9 g de proteína versus metas 3.361 kcal e 186,1 g. Revisão abriu; o plano não foi confirmado nem ativado.
- Câmera física: foto sintética de refeição capturada pelo usuário, enviada e processada no Supabase staging `xitugspwfxkcluxvrdeg`. O app apresentou revisão dos alimentos e exigiu confirmação dos itens estimados. Consulta somente leitura confirmou bucket `meal-photos` privado, objeto presente, ativo processado, 1.178.984 bytes, retenção até 2026-10-30. Não houve novo `meal_logs` nem `pending_registrations` após essa foto.
- Uma gravação de 1:05 permanece parada na tela local do iPhone. Seu conteúdo não foi confirmado pelo usuário; **não foi enviada**. O espelhamento ficou indisponível porque o Mac está bloqueado. Aguardar confirmação de que contém apenas a frase sintética de QA, ou descartá-la e gravar outra.
- A conexão Supabase staging funciona para `list_migrations` e SQL somente leitura. `get_project` retorna `NotFound` para o ref da branch, comportamento já registrado anteriormente; não é evidência de falta de acesso. Não usar o projeto Body Flow de produção como substituto.
- BFF Preview atual respondeu 401 `missing_access_token` em `/api/mobile/v1/me` sem token. Isto prova disponibilidade básica, não smoke autenticado.

## Correções e gates locais

- O iOS agora exibe o objetivo conhecido `ganho_massa` com rótulo localizado em Hoje e `full_body` como **Corpo inteiro** na revisão de plano. Ambos foram reproduzidos e cobertos por testes exatos antes da correção. Commit `b5df45d`.
- O helper de UI Flow preserva o estado autenticado mesmo com argumento adicional de movimento reduzido. O teste exato falhou antes e passou isoladamente depois; commit `98c9956`.
- No HEAD `98c9956`: 34 XCTest + 1.472 Swift Testing passaram; Release staging compilou; `codesign --verify --deep --strict` passou; `xcodebuild analyze` passou; scanner de marca sem erro e 26 testes do scanner passaram. Bundle, URL Preview, ref staging, chave publicável configurada, equipe e iPhone provisionado foram conferidos sem imprimir valores secretos. O perfil expira em 2026-10-04. O build **não foi instalado** sobre o app físico, para preservar a gravação local pendente.
- Um patch **não commitado** em `FlowChatPreviewSupport.swift` e `FlowChatUITests.swift` adiciona cenário de QA com resposta cancelável de 30 s para dois testes de cancelamento. Os 4 testes unitários da fixture passaram, mas dois testes de UI ficaram presos no onboarding do simulador antes de alcançar o cancelamento. Não considerar o patch validado nem commitá-lo sem QA de UI.

## Regressão UI, classificação atual

- Execução monolítica no Pro Max: 13 casos passaram, 2 falharam em seleção de Perfil e fechamento de sheet; ambos passaram isoladamente depois. O teste de cadastro ficou sem progresso no campo de senha por mais de 8 minutos, e a execução foi encerrada.
- `Prompt14AccessibilityUITests` no Pro Max: 12/13 passaram. `testAccessibilityXXXLEvidence` falhou exatamente na exigência de que `library.selection.all` esteja totalmente acima do viewport (`maxY 148,3` > `viewport.minY 116`). Categoria e primeiro cartão passaram nas verificações de visibilidade. O mesmo teste passou no iPhone 17 no HEAD `98c9956`. O handoff exige autorização específica do Eduardo antes de alterar essa premissa; pergunta enviada, resposta pendente.
- Lote por classes: `PlanDraftUITests` 4/4; `MealCaptureUITests` 3/3; `Prompt13RegistrationUITests` 22/22; `PremiumRegistrationUITests` 3/3; `LocalRemindersUITests` 4/4; `PremiumAuthOnboardingUITests` 3/3; `PremiumContentProfileUITests` 4/4; `PremiumConvergenceUITests` 4/4.
- `FlowChatUITests` 11/12: o botão `flow.cancel` existia após envio, mas desapareceu durante snapshot AX/tap porque a fixture respondia em 2 s. O patch não commitado torna somente os cenários de cancelamento mais longos; UI ainda não verificada.
- `Prompt13TodayUITests`: runner saiu antes de iniciar qualquer teste (0 executados). `PremiumCoreSurfacesUITests`: 6/9, com três falhas ao localizar abas após troca de tema/idioma; exigem repetição isolada antes de atribuição ao app.
- `PremiumPerformanceUITests`: runner registrou `Timed out while loading Accessibility`; Xcode permaneceu sem progresso por mais de 50 minutos. O processo de teste foi encerrado. Tentativa posterior de UI focada no Pro Max e no iPhone 17 também ficou presa no onboarding. O Mac foi observado bloqueado depois; não está comprovado quando o bloqueio começou ou se explica todas as falhas.
- **REGRESSION STATUS: PARTIALLY VERIFIED.** A suíte UI canônica completa do HEAD final não passou.

## Próxima retomada

1. Usuário desbloquear o Mac e confirmar o conteúdo da gravação local ou autorizar descartá-la. Até então, não enviar áudio.
2. Finalizar áudio físico, plano sintético por foto, smoke integrado QA A/B, instalação do Release atual por cima do app de QA e teste do novo rótulo no iPhone. Não confirmar o rascunho de dieta só para provar o fluxo.
3. Repetir UI focada do patch de cancelamento em simulador responsivo. Só após aprovação, revisar diff e fazer commit local. Repetir gates relevantes no HEAD final.
4. Aguardar decisão específica sobre o teste AXXXL. Se autorizada, corrigir a premissa sem enfraquecer visibilidade/sobreposição e validar em dois tamanhos de aparelho.
5. Executar regressão UI restante de modo confiável; classificar as falhas de Perfil, sheet e CoreSurfaces com evidência isolada. Biblioteca editorial vem depois dos fluxos principais; Roberto publica, Eduardo faz aceite visual final.

Produção não foi alterada. Nenhum novo ambiente pago foi criado. O Preview e a branch staging preexistentes continuam necessários ao beta; sua remoção depende de verificação posterior de uso e estado no provedor.

## Atualização de 2026-10-01, 08:52–09:27 BRT

- Eduardo autorizou corrigir a premissa AXXXL. O teste `testAccessibilityXXXLEvidence` foi ajustado para exigir que o seletor anterior termine antes da categoria e que o texto anterior fique fora do viewport visível. Categoria e primeiro cartão continuam exigidos por inteiro, clicáveis e sem sobreposição com as barras. O caso passou no Pro Max e no iPhone 17. Commit local `bcd7d91`.
- A fixture de cancelamento do Flow ganhou um cenário de resposta pendente por 30 segundos, só em DEBUG, sem mudar o tempo dos demais cenários. Os dois testes UI exatos de cancelamento passaram no Pro Max. Commit local `8096d3e`.
- No HEAD `bcd7d91`, a suíte unitária passou: 34 XCTest e 1.472 Swift Testing, zero falhas. A regressão UI canônica completa ainda não passou no HEAD final.
- O build Release staging já assinado foi instalado **por cima** no iPhone físico, sem apagar o app. A sessão QA A permaneceu. Hoje exibiu `Ganho de massa`; a revisão de treino exibiu `Corpo inteiro`. A sugestão de dieta continuou em `Para revisar`, abriu e mostrou meta de 3.361 kcal e 186,1 g de proteína; não foi confirmada.
- A gravação local anterior de 1:05 não reapareceu após reabrir o app; nada foi enviado. Eduardo confirmou que ela continha apenas a frase sintética. Foi solicitado que gravasse novamente a mesma frase e deixasse a tela parada antes de `Usar gravação`. Não classificar áudio físico como verificado até observar upload, transcrição e revisão.
- Sem push, PR, merge, TestFlight, loja ou Production. Arquivos `packages/agent` e integração WhatsApp continuam sem alteração nesta rodada; impacto no WhatsApp: nenhum identificado. Nenhum recurso pago novo foi criado.
- `Prompt13TodayUITests` passou 11/11 no HEAD atual. Os três casos de `PremiumCoreSurfacesUITests` que haviam falhado no lote longo (`testProgressMissingValuesAreNotZeroAndNoRangeSelector`, `testPlanThemeAndLocaleMatrix`, `testProgressThemeAndLocaleMatrix`) passaram isolados. Isto classifica a falha anterior como dependente da execução em lote, sem provar a suíte canônica integral.
- `PremiumPerformanceUITests` teve 2 casos aprovados antes do limite de 240 s do lote; os 2 restantes passaram juntos em uma segunda execução. Quatro casos passaram no total, mas a classe não terminou em um único lote.
- Ao iniciar gravação via espelhamento, o macOS exibiu literalmente `O microfone do iPhone não está disponível pelo Mac.` A gravação de 19 segundos foi parada, sem upload, porque a presença da frase não podia ser garantida. Eduardo foi orientado a usar o microfone físico do iPhone para uma nova gravação sintética e deixar a tela antes de `Usar gravação`.
- O lote `FlowChatUITests` passou 10 casos sem falhas antes de atingir o limite de 600 s durante a matriz visual escura. A matriz escura passou em lote separado e a clara passou isoladamente após o limite do lote conjunto. Assim, os 12 casos da classe passaram no HEAD atual, distribuídos em três execuções; a classe não terminou em uma única execução.

## Atualização de 2026-10-01, 09:30–11:11 BRT

- A suíte UI canônica no Pro Max executou 123 casos: 120 passaram, 3 falharam; o limite de 60 minutos interrompeu o lote durante `Prompt13TodayUITests`, antes de `Prompt14AccessibilityUITests`. Quinze classes terminaram, das quais 12 passaram integralmente; `FlowChatUITests` passou 12/12 no mesmo lote. Isto **não** valida a suíte canônica completa.
- `testFiveTabsAreReachableAndCaptured` e `testPlanThemeAndLocaleMatrix` falharam no lote longo e passaram juntos em repetição isolada no mesmo Pro Max. Não houve mudança de app para esses casos; a classificação continua dependente do lote.
- `testWrittenMealIsReviewedBeforeAnyProposal` falhou no lote por perda de foco do teclado. Duas repetições isoladas falharam depois no helper que tentava tocar duas vezes no interruptor de confirmação. A instrumentação temporária capturou o interruptor visível passando de `0` a `1` após **um** toque. O helper do teste exato agora toca uma vez e aguarda o estado `1` por até cinco segundos; as capturas temporárias foram removidas. O cenário completo passou com o diff final, commit local `f229ae1`. O código do app não mudou.
- `Prompt14AccessibilityUITests` executou 13 casos no HEAD `f229ae1`: 11 passaram; dois falharam **antes** das asserções visuais, ao entrar em Biblioteca e ao localizar a aba Progresso. Ambos passaram juntos numa repetição focada (AXXXL e contraste). A classe não passou como lote único; a evidência visual desses dois casos é a repetição isolada.
- Um lote focado das três classes restantes (`Prompt14LibraryUITests`, `Prompt14ProgressUITests`, `Prompt14TodayMascotUITests`) foi iniciado. Registrar o resultado antes de fechar a regressão UI.
- O espelhamento mostrou `iPhone em Uso`; o Mac não acessa o microfone do iPhone. Eduardo recebeu a ação exata para gravar a frase sintética no aparelho, parar e deixar a tela em `Usar gravação`. Até a confirmação da nova captura, **nenhum áudio novo foi enviado**. Plano por foto e smoke integrado A/B permanecem pendentes.
- Sem mudança em `packages/agent` ou no WhatsApp nesta atualização. Sem push, PR, merge, TestFlight, loja ou Production. Nenhum recurso pago novo foi criado.

## Atualização de 2026-10-01, 11:11–11:24 BRT

- As três classes UI que faltavam no lote canônico executaram 26 casos: 24 passaram no lote; `Prompt14ProgressUITests` passou 5/5 e `Prompt14TodayMascotUITests` passou 9/9. `Prompt14LibraryUITests` passou 10/12; os dois casos falharam na abertura da Biblioteca ou de um artigo, antes das asserções do cenário. `testConflictReloadReturnsToAuthorizedDetailStatus` e `testCoverFailuresStayInsideTheArticleWithNeutralPlaceholder` passaram juntos em repetição focada. Isto preserva **REGRESSION STATUS: PARTIALLY VERIFIED**: as falhas de navegação em lote e o limite de 60 minutos da suíte canônica não foram eliminados.
- O espelhamento terminou com `Tempo Esgotado` porque o iPhone permaneceu em uso. Ainda não há confirmação da nova gravação sintética na tela `Usar gravação`; áudio real, plano por foto e smoke integrado QA A/B continuam pendentes. Nenhum áudio da tentativa de 19 segundos foi enviado.
- A correção local desta etapa é somente do helper de teste de UI (`f229ae1`); nenhum binário iOS novo é necessário para ela. O build Release staging instalado anteriormente continua o candidato físico. WhatsApp: nenhuma alteração nesta etapa. Production: intocada. Nenhum recurso pago novo.

### Próxima ação física

No iPhone: `Registrar → Refeição → Gravar áudio → Começar gravação`; dizer em voz alta `No almoço eu comi 150 gramas de arroz branco cozido e 120 gramas de frango grelhado`; tocar em `Parar`; deixar em `Usar gravação` sem tocar nessa opção; bloquear o iPhone e avisar. Só então reconectar, conferir a tela, enviar ao staging e verificar transcrição, revisão e persistência. A foto do plano sintético e o smoke A/B vêm depois.


## Atualização de 2026-10-01 — áudio físico enviado e confirmado

- Eduardo deixou uma nova gravação sintética de **6 segundos** em `Usar gravação`. Foi enviada ao staging pelo app; a revisão mostrou literalmente `No almoço eu comi 150g de arroz branco cozido e 120g de frango grelhado.` As quantidades foram apresentadas como informadas pelo usuário. A proposta mostrou 383,4 kcal, 42,2 g de proteína, 42,1 g de carboidrato e 3,3 g de gordura; a refeição sintética da QA A foi confirmada.
- Consulta somente leitura no Supabase `xitugspwfxkcluxvrdeg`: asset `653c5bdd-2ff8-478d-91a3-8e7687776201`, `audio_note`, MIME `audio/mp4`, 107.275 bytes declarados e reais, bucket `audio-notes` **privado**, objeto presente, estado `processed`, sem failure_code, retenção até 2026-10-31 14:50:34 UTC. Nenhuma URL assinada nem credencial foi exposta.
- Proposta `2777524f-c4e2-4a90-befc-8bea387092b5` confirmada às 14:54:19 UTC. Dois logs foram persistidos: arroz `a29a59a5-7050-4e3c-bb19-84d37c4fc7c5` (150 g, 192,4 kcal, 3,78 g de proteína) e frango `10c3250a-f072-48b3-9e87-b4a8ae6555ba` (120 g, 191 kcal, 38,44 g de proteína), ambos Almoço. Histórico mostrou os dois itens e detalhe do arroz com 150 g/192,4 kcal.
- Após recarregar manualmente Hoje, a UI mostrou 383 kcal consumidas, 2.978 kcal restantes, balanço -2.978 kcal, proteína 42,22 g, meta 186,1 g, restante 143,88 g, 23%. **Áudio físico: upload/transcrição/revisão/confirmação/persistência verificados.** A atualização automática de Hoje tem o achado abaixo; não confundir atualização manual bem-sucedida com resolução dele.
- Plano por foto: documento sintético `/tmp/performe-qa-plano-treino.png` preparado no Mac, sem dados pessoais. A opção `Fotografar o plano` abriu câmera preta e o macOS avisou `A câmera do iPhone não está disponível pelo Mac.` Ação física exata solicitada ao Eduardo; extração/revisão ainda não verificadas. Não confirmar o plano importado nem substituir o treino QA existente.

### Regressão manual exata — Hoje desatualizado após confirmação de áudio

**Estado: OPEN / causa não estabelecida.** O intervalo entre a entrada em Hoje e o refresh manual não foi medido: a captura pode representar o snapshot anterior durante uma leitura em curso. A repetição precisa aguardar o fim do carregamento/limite de leitura do app e registrar duração e estado antes de classificar falha persistente. Nenhuma alteração de refresh feita com base somente no sintoma. Invalidação de confirmação, compartilhamento do centro entre shell e sheet e política de transporte sem cache foram inspecionados.

1. Usar a QA A no iPhone com Hoje previamente carregado: 0 kcal consumidas, meta 3.361 kcal, atualização antiga `27/09/2026 23:55`.
2. Em Registrar → Refeição, gravar 6 segundos dizendo `No almoço eu comi 150 gramas de arroz branco cozido e 120 gramas de frango grelhado`.
3. Enviar, revisar arroz 150 g/frango 120 g, calcular e confirmar a proposta de 383,4 kcal/42,22 g de proteína.
4. Fechar o sheet e entrar em Hoje, sem tocar em refresh. **Esperado:** carregar o snapshot atual do serviço, exibindo 383 kcal/42,22 g de proteína, 2.978 kcal restantes e data atual. **Observado nesta execução:** 0 kcal, proteína 0 e data antiga permaneceram.
5. Tocar no refresh. **Observado:** snapshot atual correto e dois logs presentes em Hoje/Histórico. Esta etapa comprova disponibilidade dos dados e funciona como controle, não como correção do passo 4.

### Regressão exata — códigos técnicos em Mais detalhes

Depois do passo 5 acima, expandir Mais detalhes. O iPhone exibiu literalmente `provisional`, `below_target` e `not_recorded` em balanço, proteína e hidratação. O teste `TodayExpandedStatusLabelTests` usa essa combinação e os valores 3.361/383/2.978 kcal, 42,22/186,1/143,88 g, hidratação 0 sem meta. A correção de apresentação e os gates serão registrados após resultados; o transporte/contrato e os cálculos devem permanecer literais.

Production intocada; nenhum ambiente pago novo; sem push/PR/merge. WhatsApp: nenhum arquivo compartilhado alterado nesta rodada. O custo adicional da transcrição curta não foi obtido do provedor; não declarar custo exato com base em estimativa anterior.


## Atualização de 2026-10-01 — correção local dos estados em Hoje

- Commit local `f101db5`: rótulos conhecidos de balanço, proteína e hidratação passam por localização **somente na apresentação iOS**. A combinação física exata `provisional/below_target/not_recorded` mostra `Dia em andamento/Abaixo da meta/Nenhum registro`; há traduções em inglês e cobertura dos estados vizinhos. Códigos desconhecidos continuam literais. Nenhuma fórmula, DTO, transporte, auth, RLS, schema ou integração compartilhada mudou. Os 10 novos itens do catálogo possuem ambos os idiomas; zero chaves anteriores foram alteradas.
- RED: o cenário exato de `TodayExpandedStatusLabelTests` falhou nas 6 expectativas de tradução pt/en antes da correção. GREEN: **34 XCTest + 1.475 Swift Testing**, zero falhas. O log persistente está em `~/.local/share/performe-ai/pre-llm-e2e/today-status-unit-20261001.log`.
- UI focada: `Prompt13TodayUITests.testExpandedTodayDetailsRenderLocalizedStatusLabels` passou. A primeira execução encontrou os rótulos traduzidos e falhou numa premissa adicionada nessa mesma rodada: exigir que o texto filho da linha de status fosse tocável. A linha combina os filhos de acessibilidade e o contrato desse teste é a renderização do texto. A premissa de toque foi corrigida; a segunda execução passou, mantendo as exigências de rótulos presentes e códigos crus ausentes. O runner da primeira execução permaneceu sem progresso após fechar a suíte e foi encerrado pelo PID específico, preservando o log de falha. **Isto não substitui a suíte UI canônica completa**, que continua parcialmente verificada.
- Release staging compilou e `codesign --verify --deep --strict` passou. Bundle dev mantido: `com.performeai.app.dev.k6942zjtv6`; equipe e iPhone presentes no perfil; expiração real **2026-10-04 18:12:24 BRT**. O host BFF e o ref staging do build foram comparados com o candidato anterior; origem mantida. Após o gate canônico, o staging foi recompilado em pasta própria persistente e sua assinatura foi verificada novamente: `~/.local/share/performe-ai/pre-llm-e2e/today-status-staging-release/BodyFlow.app`, fonte iOS `f101db5`. Build novo preparado, **ainda não instalado** enquanto a captura física do plano está pendente.
- Scanner: executá-lo diretamente no bundle dev resultou no guard esperado `UNEXPECTED_BUNDLE_IDENTIFIER`, sem PUBLIC_LEAK. Um Release canônico separado, sem assinatura e sem instalação, compilou com a configuração do projeto. Seu scanner passou, zero falhas e zero vazamentos públicos; 21 testes do scanner passaram. Não se alterou o scanner nem o bundle do app físico para passar o gate.
- Diff revisado, `git diff --check` passou. Severidade da correção de rótulos: LOW; nenhuma correção HIGH/CRITICAL foi feita nesta rodada. A causa da observação de atualização de Hoje continua aberta. Sem push, PR, merge, tag ou deploy de backend; Production intocada; WhatsApp sem impacto identificado.
- A consulta somente leitura repetida após a interrupção confirmou áudio `processed`, objeto presente, bucket privado, **2 logs / 383,40 kcal / 42,22 g de proteína**.
- A imagem sintética do plano foi recriada em caminho persistente `~/.local/share/performe-ai/pre-llm-e2e/qa-plano-treino-20261001.png` para evitar depender de `/tmp`. O iPhone foi observado ainda na câmera do Performe; nenhuma foto aceita/processada foi verificada. **Ação física pendente:** fotografar esse documento no Mac, tocar em `Usar foto`, aguardar a revisão, bloquear o iPhone e avisar; não confirmar o plano.

### Estado operacional atual

- `REGRESSION STATUS: PARTIALLY VERIFIED` — unitária e UI focada acima passam; suíte canônica integral final pendente e instabilidade de navegação em lote preservada como achado.
- `PRODUCTION STATUS: NOT DEPLOYED`; `IOS INTEGRATION STATUS: PARTIAL`.
- `SECOND DELIVERY STATUS: BLOCKED`; `ROBERTO BETA CANDIDATE STATUS: BLOCKED`; `USER VISUAL ACCEPTANCE: PENDING FINAL REVIEW`.
- Próximos gates: foto física do plano; instalação do Release novo sobre o app após a captura; conferir os três rótulos e repetir Hoje com duração medida; smoke real QA A/B; regressão canônica final; Biblioteca editorial e aceite visual humano ao final.
- `DELIVERY CHANNEL STATUS: LOCAL-DEVICE-ONLY`. Nenhum TestFlight/loja/certificado novo foi solicitado ou contratado.
- Nenhum novo recurso pago, novo worktree ou branch foi criado. Staging e Preview preexistentes permanecem necessários ao beta; closeout global ainda depende do término e de verificação no provedor. Custo adicional de áudio não foi obtido do provedor; estimativa anterior não foi transformada em valor confirmado.
