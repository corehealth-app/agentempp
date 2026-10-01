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


## Atualização de 2026-10-01 — plano por foto, candidato novo e isolamento A/B

- Foto física sintética: após upload, o iPhone mostrou literalmente `Sem conexão. Verifique a internet e tente novamente.` O asset `d5aabd2a-8d87-41bf-a2f9-aaee52d21f0b` já estava `uploaded`, JPEG de **867.902 bytes**, com objeto presente no bucket **privado** `plan-documents`. Não foi tirada nem enviada outra foto. A ação `Tentar novamente` retomou o mesmo asset e abriu `Revisar plano importado`.
- Draft `48cd7301-67e9-4955-8f63-f5b1bcae5ec7`: `training`, `imported_photo`, **needs_completion**, sem failure_code, **confirmed_plan_id null**. Criado às 15:53:26 UTC, atualizado às 15:53:38 UTC. O asset ficou `processed`, mantendo os mesmos 867.902 bytes e objeto privado presente. Apenas um draft para esse asset. Nada foi confirmado ou ativado.
- Extração literal: `full_body`, halteres, frequência 2 dias/semana; segunda Agachamento 3×10/90 s, Remada 3×12/90 s, Prancha 3×30 segundos/60 s; quinta Terra 3×8/120 s, Supino com halteres 3×10/90 s e Caminhada com nota de 20 minutos. Duração dos dias e grupos musculares ausentes permanecem null; séries/repetições/descanso da Caminhada também. A revisão exibiu `Corpo inteiro` e exigência de completar os dados ausentes, sem inventá-los.
- **Causa da falha inicial de rede: não estabelecida.** Recuperação verificada, sem alegação de correção da causa. Logs agregados do Preview incluíram uma resposta 202 para `plan-imports`; essa agregação não prova o resultado do pedido inicial. O deployment `dpl_GLErXCCTkuvXuaNqBmqn2qBWdZSp` foi revalidado READY, target null (Preview), host igual ao instalado. Production intocada.
- Commit local **da78bf0**: teste exato `PlanImportModelTests.physicalPhotoOfflineImportResumesSameAsset`, câmera/JPEG/867.902 bytes/asset e draft acima, falha de rede na criação do import depois do complete. Asserções: uma criação/upload/complete, duas chamadas de import com a **mesma MutationAttempt**, arquivo local já removido, mesmo asset e draft; mensagem pt-BR exata. Os 10 testes do modelo passaram. Nenhum código do app foi alterado para esse erro; OCR foi verificado ao vivo, não pela imagem de zeros do fake.
- Release staging da fonte **f101db5** foi instalado por cima, sem apagar dados; sessão QA A e refeições preservadas. Os três rótulos foram verificados fisicamente: `Dia em andamento`, `Abaixo da meta`, `Nenhum registro`; todos os valores anteriores foram preservados.
- Hidratação: dois envios explícitos de 250 ml foram feitos porque a confirmação estava abaixo da área visível do sheet. Logs `81697246-6069-4a0a-8c96-e29b44d1a36a` e `85352759-6117-48a1-8215-0cdf08e247a5` confirmados somente por leitura SQL, total 500 ml. Não atribuir essa repetição manual ao replay do servidor. Hoje passou de `Nenhum registro` a `Registrado sem meta` e 500 ml **sem refresh manual**, depois de fechar o sheet e voltar à aba. O snapshot anterior apareceu primeiro e o novo estado foi capturado ainda às 13:07 BRT; o intervalo exato não foi cronometrado, portanto não usar esta rodada como medição do tempo de atualização. A observação antiga após áudio continua aberta e não foi corrigida por inferência.
- Peso QA A: um registro sintético de **80 kg**, medido em `2026-10-01T16:15:33.319Z`, confirmado pela UI e por `user_profiles.weight_kg=80.00`, `weight_instant_source=measured`. Progresso continuou exibindo `Não disponível` após mais de 60 segundos. **Achado aberto:** a UI atual lê `user_progress.current_weight`, enquanto C5 especifica último peso e data a partir de GET `/profile`, sem escrever em `user_progress`. Nenhuma fórmula, meta ou tabela de progresso foi alterada.
- Revisão de dieta no físico encontrou `mode=referencia` e `horizon=daily` crus. Commit local **93993a3** localiza só esses enums de apresentação: `Referência/Diário` em pt-BR, `Reference/Daily` em en; vizinhos `rigida/weekly` também localizados. Valores desconhecidos e textos em outros campos permanecem literais; payload, meta 3.361 kcal e proteína 186,1 g intocados. Dois testes novos cobrem o cenário físico e os vizinhos. RED: 8 falhas de tradução; GREEN: **34 XCTest + 1.478 Swift Testing**, zero falhas. Release staging compilou e assinatura estrita passou.
- Esse Release **93993a3** foi instalado por cima e lançado no iPhone. Artefato: `~/.local/share/performe-ai/pre-llm-e2e/diet-metadata-staging-release/BodyFlow.app`. Perfil/equipe/bundle/host staging mantidos; validade previamente conferida até 2026-10-04 18:12:24 BRT. Rótulos novos da dieta **verificados no iPhone** após o retorno à QA A: `Referência` e `Diário`, meta 3.361 kcal e proteína 186,1 g. O draft continuou em revisão, sem confirmação.
- **Login/logout/troca A → B → A reais feitos autonomamente no iPhone.** Perfil mostrou cada identidade. QA B: Hoje 0 g de proteína, 0 ml e 2.214 kcal de meta; Plano vazio, sem drafts da QA A. Retorno QA A: 42,22 g de proteína, 500 ml e 2.978 kcal restantes preservados. Supabase auth registrou login B às 16:41:40 UTC e A às 16:47:52 UTC. Isto comprova os estados observados; histórico/Flow/rotina completos do candidato continuam pendentes.
- As credenciais privadas existentes foram acessadas por uma ponte **apenas local**, sem alteração de senha. O login B inicial usou clipboard antigo e foi recusado; diagnóstico direto confirmou a credencial B válida, e a sessão exclusiva do diagnóstico foi encerrada (`logout?scope=local`, 204). Preenchimento automático CI-3 foi recusado, conforme escopo QA. O foco do espelhamento atrasou em outra tentativa: a senha sintética A apareceu temporariamente no campo de e-mail/captura; **o formulário incorreto não foi enviado**, campo limpo e login correto concluído. Não repetir o valor em documentação ou relatórios.
- Cleanup das pontes: clipboard limpo, variáveis de senha descartadas, processos exatos da ponte web e da ponte nativa encerrados, porta localhost 55323 comprovadamente fechada e arquivos/apps temporários removidos. Nenhum secret foi colocado no repositório.
- WhatsApp: **nenhuma alteração nesta rodada**. Sem push/PR/merge/tag/TestFlight/loja/Production. Nenhum ambiente pago novo. Regressão continua **PARTIALLY VERIFIED**: suíte UI canônica final ainda não passou. Biblioteca editorial e aceite visual humano continuam no fim da operação.

## 2026-10-01 — C5 peso oficial em Progresso

- Cenário físico exato: QA A registrou **80 kg** em **2026-10-01T16:15:33.319Z**, com `weight_instant_source=measured`; `user_profiles` persistiu o valor, mas Progresso continuou `Não disponível` porque só lia `user_progress.current_weight=null`.
- A especificação C5 (§4.2) determina peso+data de `GET /profile`. Correção somente iOS: leitura autenticada independente de `/profile`, pelo mesmo gate da sessão, com estados de erro honestos e proteção contra cancelamento/respostas antigas. Não escreve `user_progress`, histórico nem snapshots; não modifica fórmulas. O DTO de progresso permanece literal. O peso oficial fica dentro do cartão Medidas existente; fallback separado só quando não há conteúdo do ledger.
- Regressões: cenário exato 80 kg + instante + progress nil; transporte GET/profile; fonte measured versus recorded/unknown; valor ausente; provider demo sem leitura separada; offline; cancelamento; supersession; logout e troca A→B com resposta de perfil tardia. RED do cenário: 8 testes/2 assertions falharam; encerramento do runner atingiu timeout. Método isolado anterior executou zero testes e não conta como RED.
- Validação intermediária encontrou chave de tradução ausente (corrigida usando `progress.not-available`) e quebra de composição no teste estático dos três cartões (layout corrigido, teste preservado). Gate final: **34 XCTest + 1.484 Swift Testing, zero falhas**, `profile-weight-unit-final-20261001.log`. Swift compilou Debug e Release staging; assinatura estrita passou.
- Revisão independente `/root/diet_review`: achado de tradução resolvido, segunda revisão do layout sem bloqueio; gate e estados revisados. Nenhuma mudança em WhatsApp/agent nesta correção iOS.
- Release staging instalado **por cima** no iPhone, sem apagar app/sessão. Às **14:28 BRT**, Progresso exibiu **80 kg** e **Medido em 1 de out. de 2026, 13:15**; gordura corporal `Não disponível`, streak/XP/blocos/deficit zero preservados. Evidência local: `~/.local/share/performe-ai/pre-llm-e2e/profile-weight-physical-20261001.png`; candidato `profile-weight-staging-release/BodyFlow.app`.
- Suíte UI canônica completa iniciada; ainda não há resultado final, então REGRESSION STATUS permanece PARTIALLY VERIFIED para a entrega inteira. Não houve push/merge/deploy Production, recurso pago novo ou mudança WhatsApp.

## 2026-10-01 — novas observações de Flow/rotina

- Smoke Flow físico às 13:59 BRT, frase **“Resuma somente os registros de hoje, sem gerar planos.”**: reconheceu consumo **383 kcal / 42,2 g de proteína**, sem treino. A falha histórica de negar registros não foi reproduzida neste smoke. Não se pediu geração de plano.
- Divergência confirmada: Flow informou meta **2.980 kcal / 144 g**, restantes **2.597 kcal / 101,8 g**. Snapshot/Hoje mantêm **3.361 kcal / 186,1 g**, consumo 383/42,22 e água 500 ml. Hoje foi atualizado e preservou a mesma meta; isso corresponde à regra C5 de snapshot intradia. `loadContext` do Flow usa cálculo do perfil vivo, ignorando alvos do snapshot; investigar/corrigir apenas contexto mobile_flow, preservando WhatsApp. Golden exato em preparação, sem afirmar correção implantada.
- Fixture de rotina sintética criada via RPC canônico e chave estável `qa-second-delivery-routine-20261001`: item **7e6ffa8f-0863-45f4-bc51-e74f88d2e1e0**, nome **QA smoke — não ingerir**, dose **Somente teste de interface**, suplemento/origin other, lembretes **false**, horários 12:00/12:05 diários. Regras **20bc643f-986a-48bb-92b2-d956f43b5c6c** e **86d57230-e253-43ad-add5-ae65a7177ad9**. List RPC e Hoje mostram duas ocorrências pendentes. Tomado/Adiar/histórico ainda não executados. Arquivar ao finalizar, preservando evidência/histórico; não excluir dados.

## 2026-10-01 — contexto intradia do Flow após peso

- Golden exato da frase física “Resuma somente os registros de hoje, sem gerar planos.”, perfil sintético 80 kg e override de proteína real de staging (`moderada=1.8`), snapshot 3.361 kcal/186,1 g, consumo 383/42,22. RED válido: 6 testes/1 falha; cobertura adicional de consulta_metricas: 8 testes/1 falha. Não usar o mock anterior com fator default 1.5 como cenário exato.
- Correção limitada ao canal `mobile_flow`: seleciona os alvos do snapshot do dia local autenticado e usa cada valor positivo/finito; ausência/invalidade mantém fallback calculado. O contexto server-side passa esses alvos para `consulta_metricas`, mantendo BMR/TDEE do perfil. Demais canais preservam consulta e valores anteriores; nenhum snapshot, fórmula ou dado persistido foi reescrito.
- Impacto WhatsApp: arquivos compartilhados modificados, mas ramo legado preservado com golden explícito (inclusive contexto Flow indevidamente injetado em identidade legado). Usuário avisado. Geradores/propostas de planos não modificados: regra de meta para novas sugestões após peso ainda aguarda decisão de produto do Eduardo; não inferir aceite.
- Revisão independente `/root/diet_review` sem bloqueio nesta correção de contexto/metricas; P2 pendente sobre regra dos planos. GREEN: 8 golden, agente **1.296 testes/89 suites**, BFF **26 testes**, typecheck agente/BFF, rotas/imports, build BFF e superfície **47 rotas** passaram. Sem chamadas LLM nos testes. Lint do golden passou. Arquivos compartilhados têm **3 erros/18 warnings preexistentes**, reproduzidos nos mesmos arquivos de HEAD 04e954f e mesmas regras em pacote local privado; nenhuma nova categoria/quantidade de diagnóstico. Não declarar lint global verde.
- Correção ainda sem deploy/QA físico; Preview anterior permanece ativo. iOS canônico completo continua em execução. Sem push/merge/Production ou ambiente pago novo.

## 2026-10-01 — rotina recém-criada com horários anteriores

- Fixture criada às 17:13:42Z com horários 15:00/15:05Z apareceu pendente no Hoje/lista/detalhes. Confirmação física “Tomado” às 17:54:18Z retornou “Não foi possível concluir. Tente novamente.” PostgreSQL registrou `routine_occurrence_not_found`; recibo mobile falhou, **zero ações gravadas**. Não houve retry nem ingestão. Investigação independente da divergência entre leitura e snapshots de vigência iniciada; não relaxar validação de escrita nem backdatear fixture.

## 2026-10-01 — correção da ocorrência anterior à criação

- Causa comprovada: `list_mobile_routine_items` gerava ocorrências só pelo horário/weekday, ignorando `routine_occurrence_finalizer_rules.active_from/active_until`. O writer exige snapshot válido. `reminders_enabled=false` não era a causa.
- Migration `20261001180504_bodyflow_routine_list_snapshot_validity.sql` substitui somente o read model: mantém horários, usa o resolver canônico de snapshot e retorna `occurrence:null` quando não há vigência. Assinatura/grants/schema/writer/fórmulas intactos. Rollback da definição anterior salvo em arquivo privado. Não houve backdate da fixture.
- Teste SQL autocontido `bodyflow_routine_creation_occurrences.sql`, com fixture sintética em BEGIN/ROLLBACK: RED staging falhou no cenário físico exato (12:00 advertised actionable); GREEN staging após migração passou preservando schedules, null no mesmo dia, writer recusando com erro exato, zero logs, dia seguinte pendente, weekday ausente e isolamento de outro dono. Aceitação futura não é exercitada neste teste com relógio real; não inventar essa evidência.
- Revisão independente encontrou HIGH de avaliação de AND sem short-circuit: corrigido com CASE aninhado antes da aplicação e acrescido teste de weekday sem timestamp. Segunda revisão **PASS, nenhum HIGH restante**. Migration aplicada apenas em **xitugspwfxkcluxvrdeg**; definição prévia foi comparada com fonte antes. WhatsApp: nenhum caller identificado fora dos read models mobile; usuário avisado, nenhum impacto funcional encontrado.
- Físico às **15:08 BRT** após reabrir: Detalhes conserva **12:00/12:05**, remove rótulos Pendentes e botões Tomado/Adiar/Pular inválidos. Captura `~/.local/share/performe-ai/pre-llm-e2e/routine-precreation-fixed-20261001.png`. Histórico/ações de ocorrências válidas seguem como QA separado.

## 2026-10-01 — pacote privado de Preview / closeout de erro operacional

- Pacote anterior no scratchpad não existe mais. Reconstrução do BFF a partir de **47a36aa** em diretório privado, **721 arquivos conferidos byte a byte com Git**, mais declaração de tipos DB gerada/ignorada (SHA256 `4503f43d1132ced1df9e4bb7c42b7ba66aafe44f87a84f910332d3fa09ff4a6d`).
- Primeira extração falhou por versão Python/tarfile; um comando posterior pull --yes executou sem link preparado e criou erroneamente projeto vazio **pkg-47a36aa**, ID **prj_G6yu4s0xwWl6dzzLVDz8waCqfCXm**, owner desta task. Criado 15:03 BRT, **zero deployments**, sem código publicado/integração e dados descartáveis. Removido autonomamente; consulta Vercel independente retorna **project_not_found**, closeout **CLOSED**. Nenhuma infraestrutura persistente adotada; nenhum custo de runtime observado nesse projeto vazio.
- Link corrigido e conferido antes de pull: projeto staging existente **prj_NTrnUNFXfmddMuci3VWjalfAoejW**, team **team_UERmEwgxRUaDvbvd22K1Iqde**, root `apps/mobile-bff`. Guard de env Preview confirmou apenas **xitugspwfxkcluxvrdeg**, ref Production ausente. Env privado 0600, três valores sensíveis vêm como placeholders do provedor e não são utilizados para chamadas locais; deploy usa env do servidor. Install frozen/offline passou; gates do pacote em execução, nenhum deploy novo ainda.

- Registro de migration do provedor confirmado: **20261001180504 / bodyflow_routine_list_snapshot_validity**. Nome local alinhado ao timestamp real gerado pela Management API para evitar replay por ferramentas futuras; conteúdo SQL idêntico ao 08b08ed, sem nova aplicação.

## 2026-10-01 — ações válidas e cleanup da rotina

- Mesma fixture atualizada via RPC canônico para **15:15/15:17**, regras novas **7fea81b3-98cd-4504-afe1-7fd96d2b44ea / 4d52ca72-72e5-4880-bcf2-8a24d63ee916**, criadas 18:09:27Z. Versão 2; lembretes habilitados temporariamente na versão 3. Nenhum item real ou dose ingerida.
- UI física confirmou “Registrado: Tomado” e “Registrado: Adiado”; histórico mostra Tomado 15:15 e Adiado 15:17. SQL: ação **fc5918fe-eda1-4f74-812b-3db1d553aeab**, taken, occurred_at 18:20:33.011Z; ação **19a2003f-b6c7-4ba7-bc4d-269690f9c6d8**, snoozed, occurred_at 18:22:07.243Z, snoozed_until **18:37:07.243Z** (15 min exatos). Foto `routine-actions-history-20261001.png`, em diretório privado de evidência.
- Lembretes locais ativados fisicamente: UI agendou **59**, cobertura até 30/10 15:15; após janela, **58**, cobertura 15:17. Tela informa texto genérico sem nome/dose. **Isso comprova agendamento, não entrega visual.** Banner não apareceu na janela de espelhamento; acesso à central de notificações do iPhone não abriu pela interface disponível. Delivery/tap de notificação real permanece **NOT VERIFIED**, não declarar sucesso com base na contagem.
- Lembretes locais desativados no iPhone, estado original restaurado e UI confirmou Desativados. Fixture arquivada pelo RPC canônico às **18:24:01.990Z**, versão 4; verificação independente: **active=false, reminders_enabled=false, active_rules=0**, duas ações preservadas. Nenhum DELETE; closeout fixture **CLOSED**.

## 2026-10-01 — Preview 47a36aa e instalação final corrente

- Ajustes do pacote: root `tsconfig.base.json` também arquivado do commit, total **722 arquivos commitados**; primeiro teste do pacote iniciou em paralelo ao build e falhou por manifest ausente, além do config omitido. Corrigida preparação/ordem: build pronto, **26 testes passaram**, typecheck, mirrors/imports e build-surface **47 rotas** passaram; build final após config completo passou, guard de nomes de segredos em `.next/static` passou. Não alterar testes para passar.
- Deployment **dpl_6MHg32BnJZHSBAFK1zap9TWqcp8W**, host **agentempp-mobile-bff-staging-gw0tiyc19-gestao-9664s-projects.vercel.app**, criado via CLI no projeto staging existente, comprovado **READY, target=null (Preview), project prj_NTrnUNFXfmddMuci3VWjalfAoejW**. Fonte BFF **47a36aa456491fe6333f6dd1b41221aa7d089c2b** conferida no pacote. SQL staging separado no registro 20261001180504. Sem Production/alias/promote.
- Smoke remoto **me/today/plan-drafts/content: 401, Cache-Control no-store, Vary inclui Authorization**. Primeira leitura de header pegou só um dos dois campos Vary e reportou falsa falha; `get_all` confirmou ambos. Nenhum patch de header necessário. Evidência JSON `flow-target-preview-health-20261001.json` privado, sem auth token.
- Release iOS com xcconfig privado **v23** muda somente host BFF. Fonte iOS igual a **04e954f** (HEAD de build 08b08ed, backend/SQL/docs não alteram iOS). **BUILD SUCCEEDED + ANALYZE SUCCEEDED, zero erros**, assinatura estrita/equipe/UDID/bundle conferidos. Provisioning expira **04/10/2026 18:12:24 BRT**. Artefato `flow-target-staging-derived/Build/Products/Release-iphoneos/BodyFlow.app`; instalação por cima passou, sem apagar app/sessão, QA A preservada e Hoje ainda 42,22 g/500 ml/2.978 kcal.
- Smoke Flow pós-deploy preparado no composer, **não enviado**: texto inserido pelo espelhamento apareceu fora de ordem, correção por colagem não completou e telefone entrou em uso; reconexão retornou **iPhone Não Encontrado**. Aguardar aparelho disponível e conferir frase antes de enviar. Drafts QA A continuam **7, 2 confirmados históricos**, sem novo plano nesta tentativa.
- Biblioteca reconsultada em staging: **6 pt-BR + 6 en-US, todos draft**, nenhum publicado. Fluxo editorial humano e aceite visual ainda pendentes. Nenhum envio em nome de Roberto/Eduardo.

## 2026-10-01 — lifecycle verificado de staging

- Listagem oficial do parent **xuxehkhdvjivitduarvb** confirmou staging **xitugspwfxkcluxvrdeg**, branch ID **6d41a673-566b-4a6b-bbf7-3463b063979d**, name `bodyflow-staging`, **is_default=false, persistent=false, with_data=false, ACTIVE_HEALTHY**, criada 20/07/2026. `get_project` NotFound para o ref da branch é comportamento conhecido; SQL/branches confirmam presença. Parent/default Production preservado.
- Staging: **KEPT**. Owner: workstream Performe AI beta; finalidade: banco do iPhone/BFF instalado, mídia e drafts editoriais em validação. Próxima revisão: aceite da segunda entrega ou substituição/retirada do candidato. Ambiente temporário potencialmente faturável preexistente. Dependências ainda ativas; dados **PRESERVE_REQUIRED** antes de retirada, inclusive Storage separado. Compute/fatura não consultados; custo recorrente exato não determinado.
- Vercel projeto existente **prj_NTrnUNFXfmddMuci3VWjalfAoejW**, Preview atual **dpl_6MHg32BnJZHSBAFK1zap9TWqcp8W**: **KEPT**, app instalado usa o host. Preview anterior **dpl_GLErXCCTkuvXuaNqBmqn2qBWdZSp** mantido como rollback até smoke/aceite atual. Nenhuma base de compute persistente nova; consumo serverless não faturado/verificado nesta sessão. Revisar deploys substituídos após retirar referências do app e concluir aceite.
- Projeto Vercel vazio acidental **prj_G6yu4s0xwWl6dzzLVDz8waCqfCXm**: **CLOSED**, remoção/ausência verificadas. Nenhum outro projeto/branch pago novo. Env temporário do pacote removido de `.vercel/.env.preview.local` e `apps/mobile-bff/.env.local` após deploy; ambos ausentes. CLI auth anterior e xcconfig do candidato preservados.
- Fixture rotina **CLOSED**, duas ações conservadas. QA A/B e mídias anteriores pertencem ao beta e continuam preservadas. Nenhum worktree novo nesta rodada; checkout vigente ainda necessário; outros worktrees não foram limpos por inferência.
- Regressão vizinha SQL: QA B Creatina conserva **16:00**, ocorrência de hoje **19:00Z pending**, regra ativa desde 29/09, sem dados da QA A.

## 2026-10-01 — suíte UI canônica final

- Suíte completa **BodyFlowUITests** no simulador Pro Max `44AFCC15-85B3-4823-801E-2837718B9266`, sem paralelismo: **171 testes, zero falhas**, encerrada **15:35 BRT**, duração 4.102,8 segundos. Fonte iOS **04e954f**, igual à do candidato instalado; alterações posteriores foram agent/SQL/documentação. Não é uma soma de execuções isoladas. Log privado: `ios-canonical-ui-final-20261001.log`.
- Finalização do runner confirmada **15:45 BRT**: **exit 0 / TEST SUCCEEDED**. `xcresulttool` confirmou `Passed`, 171 passed, 0 failed, 0 skipped. O coletor adicional de diagnóstico do simulador expirou após 600 s, sem invalidar a sessão de testes; bundle `.xcresult` legível. Resumo privado: `ios-canonical-ui-final-summary-20261001.json`. Há um runtime warning `Invalid frame dimension (negative or non-finite)`; origem/regressão não determinadas, sem falha de teste associada no resumo. Não confundir testes aprovados com ausência de todo warning.
- O gate UI completo que antes bloqueava o candidato agora passou. Isso não comprova entrega visual de notificação, fluxo editorial ou smoke físico da nova meta do Flow ainda não enviado. Regressão funcional da entrega continua **PARTIALLY VERIFIED** até concluir esses gates e a observação cronometrada de Hoje após confirmação.

## Checkpoint de retomada — 2026-10-01, após 15:45 BRT

### Estado operacional

- **HOST:** `MacBook-Air-de-Eduardo.local`, Darwin, LOCAL_DEVELOPMENT; destinos cloud sensíveis separados do filesystem local. **REPOSITORY / WORKTREE:** `/Users/eduardohenrique/Developer/performe-ai-client-beta-flow-v1`; **BRANCH:** `codex/performe-ai-client-beta-flow-v1`. **STARTING HEAD:** a374553 nesta etapa; **HEAD antes deste checkpoint documental:** 450d785 (fonte funcional já commitada). SHA do commit documental final deve ser consultado no Git.
- **SECOND DELIVERY STATUS / ROBERTO BETA CANDIDATE STATUS: BLOCKED**, pendências abaixo. Não declarar beta aceito por inferência.
- **AUTHORITY STATUS: EXECUTED_WITHIN_STAGING_SCOPE**. Sem push/PR/merge/tag/Production/TestFlight/loja; escopo do gerador continua Flow-only, uma nova tentativa com motivo da recusa, travas preservadas.
- **IOS INTEGRATION STATUS: STAGING_INSTALLED; FINAL_DEVICE_SMOKE_PENDING**. iPhone 13 Pro Max, UDID `00008110-001649510208401E`, bundle/equipe autorizados, Release v23 sobre app existente; sessão QA A mantida. BFF Preview `gw0tiyc19`, fonte agent 47a36aa; iOS 04e954f; SQL 20261001180504.
- **REBRAND STATUS: PUBLIC_SURFACES_VERIFIED; DEV_BUNDLE_SCANNER_EXCEPTION_RECORDED**. Scanner Debug canônico PASS; Release dev anterior sem PUBLIC_LEAK, uma falha técnica esperada de bundle diferente do canônico. Não apresentar scanner Release estrito como PASS; bundle físico dev já autorizado. Assets públicos inalterados no v23.
- **USER VISUAL ACCEPTANCE: PENDING_FINAL_REVIEW**.
- **ANDROID STATUS: DEFERRED_TO_FINAL_DELIVERY**; **WHATSAPP STATUS: OUT_OF_PRODUCT_SCOPE; LEGACY_BEHAVIOR_PRESERVED_BY_CHANNEL_GUARDS_AND_TESTS**. Usuário avisado antes das alterações compartilhadas.
- **PRODUCTION STATUS: NOT DEPLOYED**. `dfik0mb7c` e parent/default Supabase intocados.

### E2E observado e limites

| Fluxo | Evidência corrente |
| --- | --- |
| Auth / session restore / A-B-A | Troca física real no iPhone, B sem drafts A, A restaurada; candidato v23 preservou QA A. Gate UI completo passou. |
| Onboarding | Gate UI passou; não repetir como cadastro físico novo nesta etapa. |
| Hoje | Snapshot real 383 kcal/42,22 g/500 ml/2.978 kcal restantes. Regra intradia C5 preservada. Atualização automática após confirmação de áudio ainda exige repetição cronometrada. |
| Texto / galeria / áudio importado / PDF | Fluxos cobertos pelo gate UI; não rotular essa execução como E2E físico novo dessas entradas. Preservar evidência PRE-LLM anterior, sem repetir chamadas pagas sem necessidade. |
| Câmera de refeição | Captura/revisão reais, mídia privada e persistida; não confirmada só para testar. |
| Gravação de áudio | 6 s sintéticos enviados/transcritos/revisados/confirmados; dois logs e histórico reais verificados. |
| Peso / Progresso | 80 kg oficial com instante de medição no iPhone; demais indicadores preservados. |
| Histórico | Refeição/arroz e ações de rotina verificados fisicamente e por SQL. |
| Flow | Histórico e consumo reais reconhecidos no smoke anterior. Contexto/consulta_metricas corrigidos e deployados; novo smoke de meta ainda não enviado porque o aparelho ficou indisponível. |
| Dieta | Retry autorizado já gerou draft válido, Revisão/Para revisar verificados; nenhuma confirmação indevida. Rótulos Referência/Diário corrigidos. Regra de meta para novas sugestões depois do peso aguarda decisão de produto. |
| Treino | Draft anterior e plano QA preservados; importação por foto abriu revisão sem ativação. |
| Foto de plano | Retry do mesmo asset após erro offline abriu revisão, 1 draft para o asset, literalidade OCR/missing fields preservados; causa de rede intermitente não estabelecida. |
| Rotina | Tomado/Adiar/histórico no iPhone e SQL; ocorrência fantasma corrigida com teste exato. Fixture arquivada, 2 ações mantidas, regras ativas zero. |
| Notificações | Ativação/agendamento/desativação no iPhone verificados. Banner entregue/tap NÃO verificados pela superfície disponível; não inferir entrega pela contagem. |
| Biblioteca | 6 artigos x 2 idiomas, todos draft; nenhum publicado. Gate UI demo passou, fluxo editorial/publicação/E2E real ainda pendentes. |

### Próxima ação concreta

1. Quando o iPhone voltar a ser encontrado, reconectar sem reinstalar novamente, abrir Flow e **conferir/limpar o composer antes de enviar** a frase exata: `Resuma somente os registros de hoje, sem gerar planos.` Deve informar meta 3.361 kcal/186,1 g, consumo 383/42,22 e restante 2.978/143,88; comprovar no SQL que não criou/confirmou plano. O último texto digitado ficou fora de ordem e NÃO foi enviado.
2. Repetir confirmação de refeição sintética em Hoje previamente carregado, medir o tempo de carregamento sem refresh e confrontar snapshot/logs. Não alterar invalidação nem fórmula baseado só na captura antiga. Teste exato de caracterização antes de eventual fix; revisão independente se grave.
3. Verificar entrega/tap de notificação local real com fixture sintética válida e apagar somente a agenda temporária via mecanismo do app; manter política de texto genérico sem nome/dose. A disponibilidade do aparelho/observação real é necessária; nenhuma credencial precisa ser enviada pelo usuário.
4. Aguardar decisão já solicitada sobre metas de novas sugestões após peso. Não inventar regra, não gerar nova dieta paga até resolver esse ponto.
5. Ao final: Roberto envia os artigos para revisão, Eduardo revisa independentemente, Roberto publica; então E2E real da Biblioteca e aceite visual explícito do Eduardo. Link editorial anterior expirou em 01/10 14:20 UTC; qualquer novo acesso deve manter identidade/permissões e destino autorizado.

### Gates e closeout

- **BASELINE:** operação dc5854f; retomada desta etapa a374553. Falhas anteriores de UI/carga documentadas; três erros e 18 warnings de lint compartilhado preexistentes.
- **TESTS / REGRESSION TESTS:** agent 1.296/89 suites; BFF 26; iOS 34 XCTest + 1.484 Swift Testing; golden exato Flow 8; SQL exato RED/GREEN; UI completo 171/0 falhas. Teste SQL não deixou usuários de fixture (contagem independente zero).
- **TYPECHECK:** agent/BFF PASS; Swift build/analyze PASS. **LINT:** golden PASS; compartilhado mantém 3 erros/18 warnings preexistentes, não verde global.
- **BUILD / SIGNING / ANALYZE:** PASS staging; **DIFF REVIEW:** PASS, independente nas correções graves; HIGH de SQL corrigido antes de aplicar/commitar.
- **RESOURCE GATE:** PASS antes do build final, 89 GiB livres/37% memória livre. Sem espera por oscilação transitória.
- **COMMIT:** YES, apenas local; **PUSH / MERGED / INTEGRATED:** NO, proibidos nesta operação.
- **DEPLOYMENT REQUIRED / PERFORMED:** YES, apenas Preview/BFF staging e migration staging; **POST-DEPLOY HEALTH:** PASS em quatro rotas 401/no-store/Vary Authorization. **PRODUCTION QA:** NOT APPLICABLE; **ROLLBACK:** NOT REQUIRED, candidato anterior e função anterior preservados.
- **NEW FAILURES INTRODUCED:** nenhuma comprovada nos gates concluídos. Runtime warning de frame na suíte UI permanece sem classificação de origem/regressão; coletor de diagnóstico adicional expirou, runner exit 0. Falha de preparação do pacote e falso negativo de header corrigidos sem enfraquecer testes/servidor. Bug de ocorrência pré-criação corrigido nesta rodada; pendências funcionais permanecem explícitas.
- **REGRESSION STATUS:** PARTIALLY VERIFIED para a entrega funcional inteira, embora a suíte UI completa tenha passado. **CLEANUP:** fixtures/env temporário/projeto vazio COMPLETE; checkout/candidato/rollback KEPT por dependências ativas.
- **COST / ENVIRONMENT CLOSEOUT:** recursos novos dispensáveis CLOSED; staging e Preview necessários KEPT com propósito/condição de revisão. Valor recorrente da branch preexistente e consumo serverless/LLM adicional não determinado; não declarar custo zero total nem encerramento financeiro completo.
- **TEMPORARY PAID ENVIRONMENTS CREATED:** projeto Vercel vazio acidental (CLOSED), novo deployment Preview no projeto existente (KEPT para candidato); nenhum Supabase branch/compute/VPS criado. **ESTIMATED RECURRING COST LEFT:** não determinado para recursos preexistentes mantidos; nenhuma nova base de compute persistente criada.
- **CLOSEOUT BLOCKERS / REMAINING RISKS:** aparelho indisponível, smoke Flow final, atualização cronometrada de Hoje, entrega de notificação, regra de produto das novas metas, Biblioteca/aceite visual e provisioning que expira em 04/10 18:12:24 BRT. Nenhum trabalho único/worktree desconhecido descartado.
- Última conferência de superfície após finalizar o Xcode: espelhamento ainda **iPhone Não Encontrado**. Nenhuma mensagem Flow enviada e nenhuma nova credencial solicitada. A pendência de disponibilidade do aparelho já foi comunicada ao usuário; não repetir login nem reinstalação ao retomar.
